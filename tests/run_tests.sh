#!/usr/bin/env bash
# Simple test harness (no extra dependencies): bash tests/run_tests.sh
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL - $1"
    if [[ -n "${2:-}" ]]; then
        while IFS= read -r line; do echo "       | $line"; done <<<"$2"
    fi
}

# check_re NAME REGEX OUTPUT
check_re() {
    if grep -qE -- "$2" <<<"$3"; then ok "$1"; else fail "$1 (expected regex: $2)" "$3"; fi
}
# check_eq NAME EXPECTED ACTUAL
check_eq() {
    if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (expected: '$2', got: '$3')"; fi
}

# Everything the tests create goes into a private directory (fixed names in /tmp collide
# when two runs happen at the same time).
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

# --- SSH ---
out=$(./logtool ssh-ips samples/auth.log)
check_re "ssh-ips: top attacker 203.0.113.5 (12)" '^ +12  203\.0\.113\.5$' "$out"
check_re "ssh-ips: 198.51.100.7 (5)" '^ +5  198\.51\.100\.7$' "$out"
check_eq "ssh-ips: 'Invalid user' lines are not counted twice" "3" "$(grep -cE '^ +[0-9]+  [0-9.]+$' <<<"$out")"

out=$(./logtool ssh-ips -n 1 samples/auth.log)
check_eq "ssh-ips -n 1: only one IP" "1" "$(grep -cE '^ +[0-9]+  [0-9.]+$' <<<"$out")"

out=$(./logtool ssh-users samples/auth.log)
check_re "ssh-users: admin (8)" '^ +8  admin$' "$out"
check_re "ssh-users: root (4)" '^ +4  root$' "$out"

out=$(./logtool ssh-hourly samples/auth.log)
check_re "ssh-hourly (syslog): 03:00 -> 12" '^03:00 +12 +#+$' "$out"
check_re "ssh-hourly (syslog): 14:00 -> 7" '^14:00 +7 +#+$' "$out"
check_re "ssh-hourly: empty hour 05:00 -> 0" '^05:00 +0 *$' "$out"
out=$(./logtool ssh-hourly samples/auth_iso.log)
check_re "ssh-hourly (ISO 8601): 03:00 -> 12" '^03:00 +12 +#+$' "$out"

# --- stdin and gzip ---
out=$(cat samples/auth.log | ./logtool ssh-ips -)
check_re "stdin support" '^ +12  203\.0\.113\.5$' "$out"
gzip -c samples/auth.log > "$WORK/auth.log.gz"
out=$(./logtool ssh-ips "$WORK/auth.log.gz")
check_re "gzip support" '^ +12  203\.0\.113\.5$' "$out"
for tool in xz bzip2; do
    ext=$tool; [[ "$tool" == "bzip2" ]] && ext=bz2
    if command -v "$tool" >/dev/null 2>&1; then
        "$tool" -c samples/auth.log > "$WORK/auth.log.$ext"
        out=$(./logtool ssh-ips "$WORK/auth.log.$ext")
        check_re "$tool support" '^ +12  203\.0\.113\.5$' "$out"
    else
        echo "skip - $tool is not installed"
    fi
done
head -c 60 "$WORK/auth.log.gz" > "$WORK/broken.log.gz"
./logtool ssh-ips "$WORK/broken.log.gz" >/dev/null 2>&1; check_eq "damaged .gz -> exit code 1" "1" "$?"

# --- Lines the sample logs do not have ---
cat > "$WORK/tricky.log" <<'LOG'
Oct  8 03:10:01 srv sshd[1]: Failed password for root from 203.0.113.5 port 4000 ssh2
Oct  8 03:10:02 srv sshd[1]: message repeated 5 times: [ Failed password for root from 203.0.113.5 port 4000 ssh2]
Oct  8 03:10:03 srv sshd[2]: Failed password for invalid user x from 10.0.0.1 from 198.51.100.9 port 4001 ssh2
Oct  8 03:10:04 srv sshd[3]: Failed password for invalid user a Failed password for root from 198.51.100.9 port 4002 ssh2
Oct  8 04:00:00 srv sshd[4]: Failed password for root from 2001:db8::7 port 4003 ssh2
LOG
out=$(./logtool ssh-ips "$WORK/tricky.log")
check_re "ssh-ips: 'message repeated 5 times' adds 5 attempts" '^ +6  203\.0\.113\.5$' "$out"
check_re "ssh-ips: forged user name -> the real source is counted" '^ +2  198\.51\.100\.9$' "$out"
check_eq "ssh-ips: an IP inside a user name is not reported" "0" "$(grep -c '10\.0\.0\.1' <<<"$out")"
check_re "ssh-ips: IPv6 source" '^ +1  2001:db8::7$' "$out"
out=$(./logtool ssh-users "$WORK/tricky.log")
check_re "ssh-users: repeated message counted (root 7)" '^ +7  root$' "$out"
check_re "ssh-users: a forged name is shown as it was sent" '^ +1  a Failed password for root$' "$out"
out=$(./logtool ssh-hourly "$WORK/tricky.log")
check_re "ssh-hourly: repeated messages are added up (03:00 -> 8)" '^03:00 +8 +#+$' "$out"

# A server with password login switched off never logs "Failed password"
cat > "$WORK/keyonly.log" <<'LOG'
Oct  8 05:00:00 srv sshd[1]: Invalid user admin from 192.0.2.77 port 5000
Oct  8 05:00:01 srv sshd[1]: Connection closed by invalid user admin 192.0.2.77 port 5000 [preauth]
Oct  8 05:00:02 srv sshd[2]: Connection closed by authenticating user root 192.0.2.77 port 5001 [preauth]
Oct  8 05:00:03 srv sshd[3]: Disconnected from authenticating user root 192.0.2.78 port 5002 [preauth]
LOG
out=$(./logtool ssh-ips "$WORK/keyonly.log")
check_re "ssh-ips: key-only server -> probes are listed" '^ +2  192\.0\.2\.77$' "$out"
check_re "ssh-ips: key-only server -> says there were no password attempts" 'no failed password attempts found' "$out"
out=$(./logtool ssh-users "$WORK/keyonly.log")
check_re "ssh-users: key-only server -> root (2)" '^ +2  root$' "$out"
out=$(./logtool ssh-hourly "$WORK/keyonly.log")
check_re "ssh-hourly: key-only server -> 05:00 -> 3" '^05:00 +3 +#+$' "$out"

# --- Web ---
out=$(./logtool web samples/access.log)
check_re "web: total requests 30" 'Total requests: 30' "$out"
check_re "web: 2xx = 16" '^ +16  2xx$' "$out"
check_re "web: 4xx = 10" '^ +10  4xx$' "$out"
check_re "web: 5xx = 4" '^ +4  5xx$' "$out"
check_re "web: top IP 192.168.1.10 (13)" '^ +13  192\.168\.1\.10$' "$out"
check_re "web: query strings are stripped from URLs" '^ +3  /about$' "$out"

out=$(./logtool web-suspicious samples/access.log)
check_re "web-suspicious: SQLi 4 requests" 'SQL injection \(requests: 4\)' "$out"
check_re "web-suspicious: SQLi source" '^ +4  203\.0\.113\.5$' "$out"
check_re "web-suspicious: traversal 3 requests" 'Path traversal \(requests: 3\)' "$out"
check_re "web-suspicious: XSS 1 request" 'XSS \(requests: 1\)' "$out"
check_re "web-suspicious: scanner UA 6 requests" 'Scanner User-Agent \(requests: 6\)' "$out"

# --- No false alarms on clean traffic ---
grep -E '^192\.168\.1\.' samples/access.log > "$WORK/clean.log"
out=$(./logtool web-suspicious "$WORK/clean.log")
check_re "web-suspicious: clean traffic -> 0 matches" 'Total matches: 0' "$out"

# Each pattern belongs to one field: URL patterns to the request, scanner names to the User-Agent
cat > "$WORK/web.log" <<'LOG'
192.168.1.20 - - [08/Oct/2026:10:00:00 +0400] "GET /wp-admin/admin-ajax.php?action=heartbeat HTTP/1.1" 200 51 "https://example.com/" "Mozilla/5.0"
192.168.1.20 - - [08/Oct/2026:10:00:01 +0400] "GET /api/unmapped HTTP/1.1" 200 12 "-" "Mozilla/5.0"
192.168.1.20 - - [08/Oct/2026:10:00:02 +0400] "GET /style.css HTTP/1.1" 200 900 "https://example.com/admin/users" "Mozilla/5.0"
203.0.113.9 - - [08/Oct/2026:10:00:03 +0400] "-" 408 0 "-" "-"
203.0.113.9 - - [08/Oct/2026:10:00:04 +0400] "GET /index.php HTTP/1.1" 200 10 "-" "Mozilla/5.0 (compatible; Nmap Scripting Engine)"
203.0.113.9 - - [08/Oct/2026:10:00:05 +0400] "GET /.env HTTP/1.1" 200 120 "-" "curl/8.5.0"
LOG
out=$(./logtool web-suspicious "$WORK/web.log")
check_re "web-suspicious: admin-ajax, a Referer and 'unmapped' are not alarms" 'probing \(requests: 1\)' "$out"
check_re "web-suspicious: scanner names are looked for in the User-Agent" 'Scanner User-Agent \(requests: 1\)' "$out"
check_re "web-suspicious: a probe that got a 2xx answer is pointed out" '1 of them got a 2xx answer' "$out"
out=$(./logtool web "$WORK/web.log")
check_re "web: a request line of \"-\" keeps its status (4xx = 1)" '^ +1  4xx$' "$out"
check_eq "web: a status code is not listed as a URL" "0" \
    "$(sed -n '/Most requested URLs/,/Top User-Agents/p' <<<"$out" | grep -c ' 408$')"
printf '%s\n\n%s' "$(sed -n 1p samples/access.log)" "$(sed -n 2p samples/access.log)" > "$WORK/nonl.log"
out=$(./logtool web "$WORK/nonl.log")
check_re "web: no final newline and an empty line -> 2 requests" '^Total requests: 2$' "$out"

# --- Journal (with fake journalctl/systemctl) ---
out=$(PATH="$PWD/tests/fakebin:$PATH" ./logtool journal)
check_re "journal: nginx errors (2)" '^ +2  nginx$' "$out"
check_re "journal: failed service" 'nginx\.service' "$out"
check_re "journal: failed SSH attempts (3)" 'attempts: 3' "$out"
out=$(PATH="$PWD/tests/fakebin:$PATH" ./logtool journal -s not-a-time 2>&1); rc=$?
check_eq "journal: a journalctl error -> exit code 1" "1" "$rc"
check_re "journal: a journalctl error is shown" 'journalctl failed: Failed to parse timestamp' "$out"

# --- Error cases ---
./logtool ssh-ips /nonexistent/auth.log >/dev/null 2>&1; check_eq "nonexistent file -> exit code 1" "1" "$?"
./logtool ssh-ips samples >/dev/null 2>&1;          check_eq "a directory instead of a file -> exit code 1" "1" "$?"
./logtool ssh-ips >/dev/null 2>&1;                  check_eq "no file given -> exit code 1" "1" "$?"
./logtool ssh-ips -n abc samples/auth.log >/dev/null 2>&1; check_eq "bad -n -> exit code 1" "1" "$?"
./logtool no-such-command >/dev/null 2>&1;          check_eq "unknown command -> exit code 1" "1" "$?"
./logtool ssh-ips -h >/dev/null 2>&1;               check_eq "-h -> exit code 0" "0" "$?"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

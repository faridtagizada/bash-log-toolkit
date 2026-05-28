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
gzip -c samples/auth.log > /tmp/logtool_auth.log.gz
out=$(./logtool ssh-ips /tmp/logtool_auth.log.gz)
check_re "gzip support" '^ +12  203\.0\.113\.5$' "$out"
rm -f /tmp/logtool_auth.log.gz

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
grep -E '^192\.168\.1\.' samples/access.log > /tmp/logtool_clean.log
out=$(./logtool web-suspicious /tmp/logtool_clean.log)
check_re "web-suspicious: clean traffic -> 0 matches" 'Total matches: 0' "$out"
rm -f /tmp/logtool_clean.log

# --- Journal (with fake journalctl/systemctl) ---
out=$(PATH="$PWD/tests/fakebin:$PATH" ./logtool journal)
check_re "journal: nginx errors (2)" '^ +2  nginx$' "$out"
check_re "journal: failed service" 'nginx\.service' "$out"
check_re "journal: failed SSH attempts (3)" 'attempts: 3' "$out"

# --- Error cases ---
./logtool ssh-ips /nonexistent/auth.log >/dev/null 2>&1; check_eq "nonexistent file -> exit code 1" "1" "$?"
./logtool ssh-ips >/dev/null 2>&1;                  check_eq "no file given -> exit code 1" "1" "$?"
./logtool ssh-ips -n abc samples/auth.log >/dev/null 2>&1; check_eq "bad -n -> exit code 1" "1" "$?"
./logtool no-such-command >/dev/null 2>&1;          check_eq "unknown command -> exit code 1" "1" "$?"
./logtool ssh-ips -h >/dev/null 2>&1;               check_eq "-h -> exit code 0" "0" "$?"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

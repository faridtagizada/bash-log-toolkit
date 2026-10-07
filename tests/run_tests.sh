#!/usr/bin/env bash
# Sadə test çərçivəsi (əlavə asılılıq yoxdur): bash tests/run_tests.sh
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

# check_re AD REGEX ÇIXIŞ
check_re() {
    if grep -qE -- "$2" <<<"$3"; then ok "$1"; else fail "$1 (gözlənilən regex: $2)" "$3"; fi
}
# check_eq AD GÖZLƏNİLƏN ALINAN
check_eq() {
    if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (gözlənilən: '$2', alındı: '$3')"; fi
}

# --- SSH ---
out=$(./logtool ssh-ips samples/auth.log)
check_re "ssh-ips: ən çox cəhd 203.0.113.5 (12)" '^ +12  203\.0\.113\.5$' "$out"
check_re "ssh-ips: 198.51.100.7 (5)" '^ +5  198\.51\.100\.7$' "$out"
check_eq "ssh-ips: 'Invalid user' sətirləri ikiqat sayılmır" "3" "$(grep -cE '^ +[0-9]+  [0-9.]+$' <<<"$out")"

out=$(./logtool ssh-ips -n 1 samples/auth.log)
check_eq "ssh-ips -n 1: yalnız bir IP" "1" "$(grep -cE '^ +[0-9]+  [0-9.]+$' <<<"$out")"

out=$(./logtool ssh-users samples/auth.log)
check_re "ssh-users: admin (8)" '^ +8  admin$' "$out"
check_re "ssh-users: root (4)" '^ +4  root$' "$out"

out=$(./logtool ssh-hourly samples/auth.log)
check_re "ssh-hourly (syslog): 03:00 -> 12" '^03:00 +12 +#+$' "$out"
check_re "ssh-hourly (syslog): 14:00 -> 7" '^14:00 +7 +#+$' "$out"
check_re "ssh-hourly: boş saat 05:00 -> 0" '^05:00 +0 *$' "$out"
out=$(./logtool ssh-hourly samples/auth_iso.log)
check_re "ssh-hourly (ISO 8601): 03:00 -> 12" '^03:00 +12 +#+$' "$out"

# --- stdin və gzip ---
out=$(cat samples/auth.log | ./logtool ssh-ips -)
check_re "stdin dəstəyi" '^ +12  203\.0\.113\.5$' "$out"
gzip -c samples/auth.log > /tmp/logtool_auth.log.gz
out=$(./logtool ssh-ips /tmp/logtool_auth.log.gz)
check_re "gzip dəstəyi" '^ +12  203\.0\.113\.5$' "$out"
rm -f /tmp/logtool_auth.log.gz

# --- Web ---
out=$(./logtool web samples/access.log)
check_re "web: ümumi sorğu 30" 'Ümumi sorğu sayı: 30' "$out"
check_re "web: 2xx = 16" '^ +16  2xx$' "$out"
check_re "web: 4xx = 10" '^ +10  4xx$' "$out"
check_re "web: 5xx = 4" '^ +4  5xx$' "$out"
check_re "web: top IP 192.168.1.10 (13)" '^ +13  192\.168\.1\.10$' "$out"
check_re "web: sorğu parametrləri URL-dən çıxarılır" '^ +3  /about$' "$out"

out=$(./logtool web-suspicious samples/access.log)
check_re "web-suspicious: SQLi 4 sorğu" 'SQL injection: 4 sorğu' "$out"
check_re "web-suspicious: SQLi mənbəyi" '^ +4  203\.0\.113\.5$' "$out"
check_re "web-suspicious: traversal 3 sorğu" 'Path traversal: 3 sorğu' "$out"
check_re "web-suspicious: XSS 1 sorğu" 'XSS: 1 sorğu' "$out"
check_re "web-suspicious: skaner UA 6 sorğu" 'Skaner User-Agent: 6 sorğu' "$out"

# --- Təmiz trafikdə yalan həyəcan olmasın ---
grep -E '^192\.168\.1\.' samples/access.log > /tmp/logtool_clean.log
out=$(./logtool web-suspicious /tmp/logtool_clean.log)
check_re "web-suspicious: təmiz trafik -> 0 uyğunluq" 'Cəmi uyğunluq: 0' "$out"
rm -f /tmp/logtool_clean.log

# --- Journal (saxta journalctl/systemctl ilə) ---
out=$(PATH="$PWD/tests/fakebin:$PATH" ./logtool journal)
check_re "journal: nginx xətaları (2)" '^ +2  nginx$' "$out"
check_re "journal: uğursuz servis" 'nginx\.service' "$out"
check_re "journal: SSH uğursuz cəhdlər (3)" '3 cəhd' "$out"

# --- Xəta halları ---
./logtool ssh-ips /yoxdur/auth.log >/dev/null 2>&1; check_eq "mövcud olmayan fayl -> çıxış kodu 1" "1" "$?"
./logtool ssh-ips >/dev/null 2>&1;                  check_eq "fayl göstərilməyib -> çıxış kodu 1" "1" "$?"
./logtool ssh-ips -n abc samples/auth.log >/dev/null 2>&1; check_eq "yanlış -n -> çıxış kodu 1" "1" "$?"
./logtool bilinmeyen >/dev/null 2>&1;               check_eq "naməlum əmr -> çıxış kodu 1" "1" "$?"
./logtool ssh-ips -h >/dev/null 2>&1;               check_eq "-h -> çıxış kodu 0" "0" "$?"

echo
echo "Nəticə: $PASS keçdi, $FAIL uğursuz"
[[ "$FAIL" -eq 0 ]]

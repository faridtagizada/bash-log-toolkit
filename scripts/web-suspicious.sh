#!/usr/bin/env bash
# Access log-da şübhəli sorğuların (SQLi, path traversal, XSS, skaner) aşkarlanması
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

usage() {
    cat <<USAGE
İstifadə: $(basename "$0") ACCESS_LOG
  Şübhəli sorğuları kateqoriyalar üzrə sayır və hər kateqoriyada ən aktiv IP-ləri göstərir.
  Qeyd: sadə regex əsaslıdır, URL-decode etmir. Yalan müsbət və yalan mənfi mümkündür.
USAGE
}

while getopts "h" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
LABEL="${1:-}"
prepare_input "$LABEL"

SP='(\+|%20| )'
# "kateqoriya|regex" cütləri (grep -iE ilə istifadə olunur)
CATEGORIES=(
    "SQL injection|union${SP}+(all${SP}+)?select|(%27|')${SP}*(or|and)${SP}|information_schema|sleep\(|benchmark\("
    "Path traversal|\.\./|%2e%2e(/|%2f|%5c)|/etc/passwd|/etc/shadow|boot\.ini|win\.ini"
    "XSS|<script|%3cscript|javascript:|onerror=|onload="
    "Həssas fayl/admin axtarışı|/\.env|/\.git/|wp-login\.php|wp-admin|xmlrpc\.php|phpmyadmin|/admin|\.bak( |\?|\")|\.sql( |\?|\")|/server-status|/cgi-bin/"
    "Skaner User-Agent|sqlmap|nikto|nmap|masscan|dirbuster|gobuster|wpscan|acunetix|nessus|zgrab"
)

echo "Şübhəli aktivlik hesabatı: $LABEL"
suspicious_total=0
for entry in "${CATEGORIES[@]}"; do
    name="${entry%%|*}"
    regex="${entry#*|}"
    count=$(grep -ciE -- "$regex" "$INPUT")
    section "$name: $count sorğu"
    if [[ "$count" -gt 0 ]]; then
        suspicious_total=$((suspicious_total + count))
        grep -iE -- "$regex" "$INPUT" | awk '{ print $1 }' | sort | uniq -c | sort -rn | head -n 3 \
            | awk '{printf "  %5d  %s\n", $1, $2}'
    fi
done

echo
echo "Cəmi uyğunluq: $suspicious_total (bir sorğu bir neçə kateqoriyaya düşə bilər)"
exit 0

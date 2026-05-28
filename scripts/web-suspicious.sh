#!/usr/bin/env bash
# Detects suspicious requests in an access log (SQLi, path traversal, XSS, scanners)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: $(basename "$0") ACCESS_LOG
  Counts suspicious requests per category and shows the most active IPs in each.
  Note: this is plain regex matching and does not URL-decode. False positives
  and false negatives are possible.
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
# "category|regex" pairs (used with grep -iE)
CATEGORIES=(
    "SQL injection|union${SP}+(all${SP}+)?select|(%27|')${SP}*(or|and)${SP}|information_schema|sleep\(|benchmark\("
    "Path traversal|\.\./|%2e%2e(/|%2f|%5c)|/etc/passwd|/etc/shadow|boot\.ini|win\.ini"
    "XSS|<script|%3cscript|javascript:|onerror=|onload="
    "Sensitive file/admin probing|/\.env|/\.git/|wp-login\.php|wp-admin|xmlrpc\.php|phpmyadmin|/admin|\.bak( |\?|\")|\.sql( |\?|\")|/server-status|/cgi-bin/"
    "Scanner User-Agent|sqlmap|nikto|nmap|masscan|dirbuster|gobuster|wpscan|acunetix|nessus|zgrab"
)

echo "Suspicious activity report: $LABEL"
suspicious_total=0
for entry in "${CATEGORIES[@]}"; do
    name="${entry%%|*}"
    regex="${entry#*|}"
    count=$(grep -ciE -- "$regex" "$INPUT")
    section "$name (requests: $count)"
    if [[ "$count" -gt 0 ]]; then
        suspicious_total=$((suspicious_total + count))
        grep -iE -- "$regex" "$INPUT" | awk '{ print $1 }' | sort | uniq -c | sort -rn | head -n 3 \
            | awk '{printf "  %5d  %s\n", $1, $2}'
    fi
done

echo
echo "Total matches: $suspicious_total (one request can fall into several categories)"
exit 0

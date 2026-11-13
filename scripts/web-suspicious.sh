#!/usr/bin/env bash
# Detects suspicious requests in an access log (SQLi, path traversal, XSS, scanners)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: $(basename "$0") ACCESS_LOG
  Counts suspicious requests per category and shows the most active IPs in each.
  Only the request line ("GET /path?query HTTP/1.1") is searched, and the
  User-Agent for scanners, so a Referer or a page name can't raise an alarm.
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
# "category|field|regex". The log line is split on double quotes: field 2 is the
# request line, field 6 the User-Agent. Regexes are lowercase (ERE) and are matched
# against the lowercased field, so the check ignores case.
CATEGORIES=(
    "SQL injection|2|union${SP}+(all${SP}+)?select|(%27|')${SP}*(or|and)${SP}|information_schema|sleep\(|benchmark\("
    "Path traversal|2|\.\./|%2e%2e(/|%2f|%5c)|/etc/passwd|/etc/shadow|boot\.ini|win\.ini"
    "XSS|2|<script|%3cscript|javascript:|onerror=|onload="
    "Sensitive file/admin probing|2|/\.env|/\.git/|wp-login\.php|wp-admin|xmlrpc\.php|phpmyadmin|/admin|\.bak( |\?|\$)|\.sql( |\?|\$)|/server-status|/cgi-bin/"
    "Scanner User-Agent|6|sqlmap|nikto|nmap|masscan|dirbuster|gobuster|wpscan|acunetix|nessus|zgrab"
)

echo "Suspicious activity report: $LABEL"
suspicious_total=0
for entry in "${CATEGORIES[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    field="${rest%%|*}"
    regex="${rest#*|}"
    # Client IP of every request whose request line (or User-Agent) matches.
    # The regex is passed through the environment: "awk -v" would eat the backslashes.
    ips=$(RE="$regex" FIELD="$field" awk -F'"' '
        BEGIN { re = ENVIRON["RE"]; f = ENVIRON["FIELD"] + 0 }
        tolower($f) ~ re { split($1, a, " "); print a[1] }' "$INPUT")
    count=0
    if [[ -n "$ips" ]]; then count=$(printf '%s\n' "$ips" | wc -l | tr -d ' '); fi
    section "$name (requests: $count)"
    if [[ "$count" -gt 0 ]]; then
        suspicious_total=$((suspicious_total + count))
        printf '%s\n' "$ips" | sort | uniq -c | sort -rn | head -n 3 \
            | awk '{printf "  %5d  %s\n", $1, $2}'
    fi
done

echo
echo "Total matches: $suspicious_total (one request can fall into several categories)"
exit 0

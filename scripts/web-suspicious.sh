#!/usr/bin/env bash
# Detects suspicious requests in an access log (SQLi, path traversal, XSS, scanners)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: $(basename "$0") ACCESS_LOG
  Counts suspicious requests per category and shows the most active IPs in each.
  The URL patterns are matched against the request, the scanner names against
  the User-Agent. Requests that were answered with a 2xx status are pointed out.
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
# "category|field|regex". The regex is matched, ignoring case, against ONE field of the
# request and not against the whole line: "url" is the request target, "ua" the User-Agent.
# Matching the whole line reported a CSS file with "/admin" in its Referer as admin probing
# and "/api/unmapped" as a scanner, because it contains "nmap".
CATEGORIES=(
    "SQL injection|url|union${SP}+(all${SP}+)?select|(%27|')${SP}*(or|and)${SP}|information_schema|sleep\(|benchmark\("
    "Path traversal|url|\.\./|%2e%2e(/|%2f|%5c)|/etc/passwd|/etc/shadow|boot\.ini|win\.ini"
    "XSS|url|<script|%3cscript|javascript:|onerror=|onload="
    "Sensitive file/admin probing|url|/\.env|/\.git/|wp-login\.php|/wp-admin|xmlrpc\.php|phpmyadmin|/admin|\.bak(\?|$)|\.sql(\?|$)|/server-status|/cgi-bin/"
    "Scanner User-Agent|ua|sqlmap|nikto|nmap|masscan|dirbuster|gobuster|wpscan|acunetix|nessus|zgrab"
)

echo "Suspicious activity report: $LABEL"
suspicious_total=0
for entry in "${CATEGORIES[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    field="${rest%%|*}"
    regex="${rest#*|}"
    # One line per matching request: "IP<TAB>STATUS". The regex travels in the environment
    # because "awk -v" would eat its backslashes.
    matches=$(RE="$regex" FIELD="$field" awk "$ACCESS_LOG_AWK"'
        BEGIN { re = ENVIRON["RE"]; field = ENVIRON["FIELD"] }
        NF && parse_access($0) {
            text = tolower(field == "ua" ? UA : TARGET)
            # admin-ajax.php is called by the browser of every WordPress visitor
            if (field == "url") sub(/^\/wp-admin\/admin-ajax\.php/, "/", text)
            if (text != "" && text ~ re) print $1 "\t" STATUS
        }' "$INPUT")
    count=$(grep -c . <<<"$matches")
    section "$name (requests: $count)"
    if [[ "$count" -gt 0 ]]; then
        suspicious_total=$((suspicious_total + count))
        awk -F'\t' '{ print $1 }' <<<"$matches" | sort | uniq -c | sort -rn | head -n 3 \
            | awk '{printf "  %5d  %s\n", $1, $2}'
        answered=$(awk -F'\t' '$2 ~ /^2/ { n++ } END { print n + 0 }' <<<"$matches")
        if [[ "$answered" -gt 0 ]]; then
            echo "         $answered of them got a 2xx answer - look at those first"
        fi
    fi
done

echo
echo "Total matches: $suspicious_total (one request can fall into several categories)"
exit 0

#!/usr/bin/env bash
# Quick statistics for an Apache/Nginx access log (combined format)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=5
usage() {
    cat <<USAGE
Usage: $(basename "$0") [-n COUNT] ACCESS_LOG
  Total requests, status code groups, and the top IPs, URLs and User-Agents.
  Format: Apache/Nginx "combined".
USAGE
}

while getopts "n:h" opt; do
    case "$opt" in
        n) check_top "$OPTARG"; TOP="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
prepare_input "${1:-}"

total=$(wc -l < "$INPUT" | tr -d ' ')
echo "Total requests: $total"

section "Status code groups"
awk '$9 ~ /^[0-9][0-9][0-9]$/ { g[substr($9, 1, 1) "xx"]++ }
     END { for (k in g) printf "%8d  %s\n", g[k], k }' "$INPUT" | sort -k2

section "Status codes"
awk '$9 ~ /^[0-9][0-9][0-9]$/ { print $9 }' "$INPUT" \
    | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{printf "%8d  %s\n", $1, $2}'

section "Top IPs (top $TOP)"
awk '{ print $1 }' "$INPUT" | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}'

section "Most requested URLs (without query strings)"
awk '{ split($7, p, "?"); print p[1] }' "$INPUT" | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}'

section "Top User-Agents"
awk -F'"' 'NF >= 6 { print $6 }' "$INPUT" | sort | uniq -c | sort -rn | head -n "$TOP" \
    | sed -E 's/^ *([0-9]+) /\1  /' | awk '{printf "%8s  ", $1; $1=""; print substr($0, 2)}'
exit 0

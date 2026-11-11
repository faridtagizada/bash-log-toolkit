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

# count_and_rank: "sort | uniq -c" output -> the usual two columns (the value may contain blanks)
count_and_rank() {
    sort | uniq -c | sort -rn | head -n "$TOP" \
        | awk '{ n = $1; sub(/^ *[0-9]+ /, ""); printf "%8d  %s\n", n, $0 }'
}

# Lines are counted with awk, not "wc -l": a last line without a newline still is a request,
# and an empty line is not one.
total=$(awk 'NF { n++ } END { print n + 0 }' "$INPUT")
echo "Total requests: $total"

# The fields come from parse_access (lib/common.sh), which splits by the quotes. Taking the
# status from column 9 lost every request whose request line is "-" or has a blank in it.
section "Status code groups"
awk "$ACCESS_LOG_AWK"'
    NF && parse_access($0) && STATUS != "" { g[substr(STATUS, 1, 1) "xx"]++ }
    END { for (k in g) printf "%8d  %s\n", g[k], k }' "$INPUT" | sort -k2

section "Status codes"
awk "$ACCESS_LOG_AWK"'NF && parse_access($0) && STATUS != "" { print STATUS }' "$INPUT" | count_and_rank

section "Top IPs (top $TOP)"
awk 'NF { print $1 }' "$INPUT" | count_and_rank

section "Most requested URLs (without query strings)"
awk "$ACCESS_LOG_AWK"'
    NF && parse_access($0) && TARGET != "" { split(TARGET, p, "?"); print p[1] }' "$INPUT" | count_and_rank

section "Top User-Agents"
awk "$ACCESS_LOG_AWK"'NF && parse_access($0) && UA != "" { print UA }' "$INPUT" | count_and_rank
exit 0

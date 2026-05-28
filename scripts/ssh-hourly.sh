#!/usr/bin/env bash
# Failed SSH attempts per hour of day (ASCII chart)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: $(basename "$0") LOG_FILE
  Counts failed SSH attempts per hour and draws a bar chart.
  Understands both the classic syslog timestamp ("Oct  8 03:10:01") and
  ISO 8601 ("2026-10-08T03:10:01+04:00", the default on Ubuntu 24.04).
USAGE
}

while getopts "h" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
prepare_input "${1:-}"

echo "Failed SSH attempts by hour"
grep -E 'Failed password' -- "$INPUT" | awk '
{
    # ISO 8601: field 1 is "2026-10-08T03:10:01..." ; syslog: field 3 is "03:10:01"
    if ($1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) {
        h = substr($1, 12, 2)
    } else {
        split($3, t, ":")
        h = t[1]
    }
    c[h + 0]++
}
END {
    max = 0
    for (i = 0; i < 24; i++) if (c[i] > max) max = c[i]
    for (i = 0; i < 24; i++) {
        n = (max > 0) ? int(c[i] * 40 / max) : 0
        bar = ""
        for (j = 0; j < n; j++) bar = bar "#"
        printf "%02d:00  %6d  %s\n", i, c[i], bar
    }
}'
exit 0

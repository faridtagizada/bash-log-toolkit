#!/usr/bin/env bash
# Uğursuz SSH cəhdlərinin saatlar üzrə paylanması (ASCII qrafik)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

usage() {
    cat <<USAGE
İstifadə: $(basename "$0") LOG_FAYLI
  Uğursuz SSH cəhdlərini saat üzrə sayır və çubuq qrafiki çəkir.
  Həm klassik syslog ("Oct  8 03:10:01"), həm də ISO 8601
  ("2026-10-08T03:10:01+04:00", Ubuntu 24.04) vaxt formatını başa düşür.
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

echo "Uğursuz SSH cəhdləri: saat üzrə"
grep -E 'Failed password' -- "$INPUT" | awk '
{
    # ISO 8601: 1-ci sahə "2026-10-08T03:10:01..." ; syslog: 3-cü sahə "03:10:01"
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

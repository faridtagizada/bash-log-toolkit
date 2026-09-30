#!/usr/bin/env bash
# Apache/Nginx access log (combined format) üzrə qısa statistika
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=5
usage() {
    cat <<USAGE
İstifadə: $(basename "$0") [-n SAY] ACCESS_LOG
  Ümumi sorğu sayı, status kodu qrupları, ən aktiv IP-lər, URL-lər və User-Agent-lər.
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
echo "Ümumi sorğu sayı: $total"

section "Status kodu qrupları"
awk '$9 ~ /^[0-9][0-9][0-9]$/ { g[substr($9, 1, 1) "xx"]++ }
     END { for (k in g) printf "%8d  %s\n", g[k], k }' "$INPUT" | sort -k2

section "Status kodları"
awk '$9 ~ /^[0-9][0-9][0-9]$/ { print $9 }' "$INPUT" \
    | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{printf "%8d  %s\n", $1, $2}'

section "Ən aktiv IP-lər (top $TOP)"
awk '{ print $1 }' "$INPUT" | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}'

section "Ən çox sorğu edilən URL-lər (sorğu parametrləri olmadan)"
awk '{ split($7, p, "?"); print p[1] }' "$INPUT" | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}'

section "Ən çox User-Agent"
awk -F'"' 'NF >= 6 { print $6 }' "$INPUT" | sort | uniq -c | sort -rn | head -n "$TOP" \
    | sed -E 's/^ *([0-9]+) /\1  /' | awk '{printf "%8s  ", $1; $1=""; print substr($0, 2)}'
exit 0

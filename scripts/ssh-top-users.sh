#!/usr/bin/env bash
# Hücumçuların ən çox sınadığı istifadəçi adları
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=10
usage() {
    cat <<USAGE
İstifadə: $(basename "$0") [-n SAY] LOG_FAYLI
  Uğursuz SSH cəhdlərində ən çox sınanan istifadəçi adlarını göstərir.
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

# "Failed password for invalid user admin from ..." və
# "Failed password for root from ..." formatlarının hər ikisini tutur.
result=$(grep -E 'Failed password for' -- "$INPUT" \
    | sed -nE 's/.*Failed password for (invalid user )?([^ ]+) from .*/\2/p' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}')

echo "Ən çox sınanan istifadəçi adları (top $TOP)"
printf '%8s  %s\n' "CƏHD" "İSTİFADƏÇİ"
if [[ -z "$result" ]]; then
    echo "  (uğursuz cəhd tapılmadı)"
else
    echo "$result"
fi
exit 0

#!/usr/bin/env bash
# Ən çox uğursuz SSH login cəhdi edən IP-lər (auth.log)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=10
usage() {
    cat <<USAGE
İstifadə: $(basename "$0") [-n SAY] LOG_FAYLI
  Uğursuz SSH parol cəhdlərini IP üzrə sayır.
  -n SAY   Neçə IP göstərilsin (default: 10)
  LOG_FAYLI  /var/log/auth.log, *.gz və ya '-' (stdin)
Nümunə: sudo $(basename "$0") -n 5 /var/log/auth.log
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

# Yalnız "Failed password" sətirləri sayılır. sshd eyni cəhd üçün ayrıca
# "Invalid user ..." sətri də yazır; onu saysaydıq, cəhdlər ikiqat görünərdi.
result=$(grep -E 'Failed password' -- "$INPUT" \
    | grep -oE "from $IP_RE" \
    | awk '{print $2}' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}')

echo "Ən çox uğursuz SSH cəhdi edən IP-lər (top $TOP)"
printf '%8s  %s\n' "CƏHD" "IP"
if [[ -z "$result" ]]; then
    echo "  (uğursuz cəhd tapılmadı)"
else
    echo "$result"
fi
exit 0

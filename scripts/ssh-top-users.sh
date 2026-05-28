#!/usr/bin/env bash
# Usernames attackers try most often
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=10
usage() {
    cat <<USAGE
Usage: $(basename "$0") [-n COUNT] LOG_FILE
  Shows the usernames tried most often in failed SSH attempts.
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

# Catches both "Failed password for invalid user admin from ..." and
# "Failed password for root from ..."
result=$(grep -E 'Failed password for' -- "$INPUT" \
    | sed -nE 's/.*Failed password for (invalid user )?([^ ]+) from .*/\2/p' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}')

echo "Most frequently tried usernames (top $TOP)"
printf '%8s  %s\n' "ATTEMPTS" "USERNAME"
if [[ -z "$result" ]]; then
    echo "  (no failed attempts found)"
else
    echo "$result"
fi
exit 0

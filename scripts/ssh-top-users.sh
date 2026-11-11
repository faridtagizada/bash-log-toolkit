#!/usr/bin/env bash
# Usernames attackers try most often
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=10
usage() {
    cat <<USAGE
Usage: $(basename "$0") [-n COUNT] LOG_FILE
  Shows the usernames tried most often in failed SSH attempts
  (failed passwords, plus connections rejected before a password was tried).
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

# The name is everything between "for [invalid user]" and the final "from IP port N":
# sshd logs it as it was sent, so it may contain spaces or look like another log line.
result=$(ssh_failed_events "$INPUT" \
    | awk -F'\t' '{ c[$5] += $1 } END { for (u in c) printf "%d\t%s\n", c[u], u }' \
    | sort -t $'\t' -k1,1nr -k2,2 | head -n "$TOP" \
    | awk -F'\t' '{ printf "%8d  %s\n", $1, $2 }')

echo "Most frequently tried usernames (top $TOP)"
printf '%8s  %s\n' "ATTEMPTS" "USERNAME"
if [[ -z "$result" ]]; then
    echo "  (no failed attempts found)"
else
    echo "$result"
fi
exit 0

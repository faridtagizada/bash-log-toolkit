#!/usr/bin/env bash
# IPs with the most failed SSH login attempts (auth.log)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=10
usage() {
    cat <<USAGE
Usage: $(basename "$0") [-n COUNT] LOG_FILE
  Counts failed SSH password attempts per IP.
  -n COUNT   How many IPs to show (default: 10)
  LOG_FILE   /var/log/auth.log, *.gz, or '-' (stdin)
Example: sudo $(basename "$0") -n 5 /var/log/auth.log
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

# Only "Failed password" lines are counted. For the same attempt sshd also logs a
# separate "Invalid user ..." line; counting that one too would double every attempt.
result=$(grep -E 'Failed password' -- "$INPUT" \
    | grep -oE "from $IP_RE" \
    | awk '{print $2}' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{printf "%8d  %s\n", $1, $2}')

echo "Top $TOP IPs by failed SSH attempts"
printf '%8s  %s\n' "ATTEMPTS" "IP"
if [[ -z "$result" ]]; then
    echo "  (no failed attempts found)"
else
    echo "$result"
fi
exit 0

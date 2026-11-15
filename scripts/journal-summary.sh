#!/usr/bin/env bash
# Error summary from the systemd journal (needs journalctl)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

SINCE="24 hours ago"
TOP=10
usage() {
    cat <<USAGE
Usage: $(basename "$0") [-s TIME] [-n COUNT]
  -s TIME   value for journalctl --since (default: "24 hours ago")
  -n COUNT  How many services to show (default: 10)
  Groups error messages (priority err and above) by service, and shows
  failed services and the number of failed SSH logins.
Note: for complete results you may need sudo or membership of the systemd-journal group.
USAGE
}

while getopts "s:n:h" opt; do
    case "$opt" in
        s) SINCE="$OPTARG" ;;
        n) check_top "$OPTARG"; TOP="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

command -v journalctl >/dev/null 2>&1 || die "journalctl not found (systemd required)"
INPUT_NAME="the journal"    # for the error message of a failed step

new_tmp; JOURNAL_OUT="$REPLY"
new_tmp; JOURNAL_ERR="$REPLY"
# journal ARGS...: runs journalctl into the file $JOURNAL_OUT. If journalctl fails (for
# example because it cannot parse the -s value) the script stops with journalctl's own
# message. With the errors thrown away, that case looked like "no errors, 0 attempts".
journal() {
    if ! journalctl --no-pager -q --since "$SINCE" "$@" > "$JOURNAL_OUT" 2> "$JOURNAL_ERR"; then
        die "journalctl failed: $(head -n 1 "$JOURNAL_ERR")"
    fi
}

journal -p err -o short
echo "Journal summary (since: $SINCE)"

section "Error messages by service (priority: err and above)"
errors=$(awk 'NF >= 5 { u = $5; sub(/\[[0-9]+\]:?$/, "", u); sub(/:$/, "", u); print u }' "$JOURNAL_OUT" \
    | sort | uniq -c | sort -rn | top_lines "$TOP" | awk '{printf "%8d  %s\n", $1, $2}') || failed
if [[ -z "$errors" ]]; then
    echo "  (no error messages found, or the journal is not readable)"
else
    echo "$errors"
fi

section "Failed systemd services"
if ! command -v systemctl >/dev/null 2>&1; then
    echo "  (systemctl not available)"
elif units=$(systemctl --failed --no-legend --plain 2> "$JOURNAL_ERR"); then
    failed_units=$(awk 'NF { print "  " $1 }' <<<"$units")
    if [[ -z "$failed_units" ]]; then
        echo "  (none)"
    else
        echo "$failed_units"
    fi
else
    # e.g. in a container without systemd: that is not the same as "no failed services"
    echo "  (systemctl failed: $(head -n 1 "$JOURNAL_ERR"))"
fi

section "SSH: failed password attempts"
count=0
for unit in ssh sshd; do
    journal -u "$unit" -o short
    c=$(ssh_failed_events "$JOURNAL_OUT" | awk -F'\t' '$4 == "password" { n += $1 } END { print n + 0 }') || failed
    count=$((count + c))
done
echo "  attempts: $count"
exit 0

#!/usr/bin/env bash
# IPs with the most failed SSH login attempts (auth.log)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

TOP=10
usage() {
    cat <<USAGE
Usage: $(basename "$0") [-n COUNT] LOG_FILE
  Counts failed SSH password attempts per IP (IPv4 and IPv6).
  Connections that were rejected before a password was tried (invalid user, or
  closed while authenticating - all a key-only server logs) get a second table.
  -n COUNT   How many IPs to show (default: 10)
  LOG_FILE   /var/log/auth.log, *.gz, *.xz, *.bz2, or '-' (stdin)
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

# One line per kind and IP, e.g. "password<TAB>203.0.113.5<TAB>12".
# ssh_failed_events (lib/common.sh) explains what is counted and why.
counts=$(ssh_failed_events "$INPUT" \
    | awk -F'\t' '{ c[$4 "\t" $3] += $1 } END { for (k in c) printf "%s\t%d\n", k, c[k] }')

top_ips() {   # top_ips KIND
    awk -F'\t' -v kind="$1" '$1 == kind { printf "%d\t%s\n", $3, $2 }' <<<"$counts" \
        | sort -t $'\t' -k1,1nr -k2,2 | head -n "$TOP" \
        | awk -F'\t' '{ printf "%8d  %s\n", $1, $2 }'
}

result=$(top_ips password)
probes=$(top_ips probe)

echo "Top $TOP IPs by failed SSH attempts"
printf '%8s  %s\n' "ATTEMPTS" "IP"
if [[ -z "$result" ]]; then
    echo "  (no failed password attempts found)"
else
    echo "$result"
fi
if [[ -n "$probes" ]]; then
    echo
    echo "Rejected before a password was tried (invalid user, or closed while authenticating)"
    printf '%8s  %s\n' "ATTEMPTS" "IP"
    echo "$probes"
fi
exit 0

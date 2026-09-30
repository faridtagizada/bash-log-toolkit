#!/usr/bin/env bash
# systemd journal üzrə xəta xülasəsi (journalctl lazımdır)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

SINCE="24 hours ago"
TOP=10
usage() {
    cat <<USAGE
İstifadə: $(basename "$0") [-s ZAMAN] [-n SAY]
  -s ZAMAN  journalctl --since dəyəri (default: "24 hours ago")
  -n SAY    Neçə servis göstərilsin (default: 10)
  Xəta (priority err və daha yüksək) mesajlarını servis üzrə qruplaşdırır,
  uğursuz servisləri və SSH uğursuz giriş sayını göstərir.
Qeyd: tam nəticə üçün sudo və ya systemd-journal qrupu lazım ola bilər.
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

command -v journalctl >/dev/null 2>&1 || die "journalctl tapılmadı (systemd lazımdır)"

echo "Journal xülasəsi (since: $SINCE)"

section "Servis üzrə xəta mesajları (priority: err və yuxarı)"
errors=$(journalctl --no-pager -q -p err --since "$SINCE" -o short 2>/dev/null \
    | awk 'NF >= 5 { u = $5; sub(/\[[0-9]+\]:?$/, "", u); sub(/:$/, "", u); print u }' \
    | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{printf "%8d  %s\n", $1, $2}')
if [[ -z "$errors" ]]; then
    echo "  (xəta mesajı tapılmadı və ya journal oxunmur)"
else
    echo "$errors"
fi

section "Uğursuz systemd servisləri"
if command -v systemctl >/dev/null 2>&1; then
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print "  " $1}')
    if [[ -z "$failed" ]]; then
        echo "  (yoxdur)"
    else
        echo "$failed"
    fi
else
    echo "  (systemctl yoxdur)"
fi

section "SSH: uğursuz parol cəhdləri"
count=0
for unit in ssh sshd; do
    c=$(journalctl --no-pager -q -u "$unit" --since "$SINCE" 2>/dev/null | grep -c 'Failed password')
    count=$((count + c))
done
echo "  $count cəhd"
exit 0

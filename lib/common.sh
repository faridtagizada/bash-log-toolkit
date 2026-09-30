#!/usr/bin/env bash
# Ümumi köməkçi funksiyalar (digər skriptlər tərəfindən `source` edilir)

# IPv4 üçün sadə regex (grep -E ilə istifadə olunur)
# shellcheck disable=SC2034  # digər skriptlər istifadə edir
IP_RE='([0-9]{1,3}\.){3}[0-9]{1,3}'

_TMP=""
# shellcheck disable=SC2034  # digər skriptlər istifadə edir
INPUT=""

die() {
    echo "Xəta: $*" >&2
    exit 1
}

section() {
    echo
    echo "== $1 =="
}

cleanup_tmp() {
    if [[ -n "$_TMP" ]]; then
        rm -f "$_TMP"
    fi
}

# prepare_input FAYL
#   FAYL = '-'    → stdin oxunur
#   FAYL = *.gz   → açılır
#   digər         → olduğu kimi istifadə olunur
# Nəticə INPUT dəyişənində qalır (fayl bir neçə dəfə oxuna bilsin deyə).
prepare_input() {
    local f="${1:-}"
    [[ -n "$f" ]] || die "log faylı göstərilməyib (kömək üçün -h)"
    case "$f" in
        -)
            _TMP=$(mktemp)
            cat > "$_TMP"
            INPUT="$_TMP"
            ;;
        *.gz)
            [[ -r "$f" ]] || die "fayl oxunmur: $f"
            _TMP=$(mktemp)
            zcat -- "$f" > "$_TMP"
            INPUT="$_TMP"
            ;;
        *)
            [[ -r "$f" ]] || die "fayl oxunmur: $f"
            INPUT="$f"
            ;;
    esac
    trap cleanup_tmp EXIT
}

# top_n_arg: -n parametrinin müsbət tam ədəd olduğunu yoxlayır
check_top() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "-n müsbət tam ədəd olmalıdır: $1"
}

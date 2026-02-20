#!/usr/bin/env bash
# Shared helper functions (sourced by the other scripts)

# Simple IPv4 regex (used with grep -E)
# shellcheck disable=SC2034  # used by the other scripts
IP_RE='([0-9]{1,3}\.){3}[0-9]{1,3}'

_TMP=""
# shellcheck disable=SC2034  # used by the other scripts
INPUT=""

die() {
    echo "Error: $*" >&2
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

# prepare_input FILE
#   FILE = '-'    -> read stdin
#   FILE = *.gz   -> decompress
#   anything else -> used as is
# The result is left in INPUT (so the file can be read more than once).
prepare_input() {
    local f="${1:-}"
    [[ -n "$f" ]] || die "no log file given (use -h for help)"
    case "$f" in
        -)
            _TMP=$(mktemp)
            cat > "$_TMP"
            INPUT="$_TMP"
            ;;
        *.gz)
            [[ -r "$f" ]] || die "cannot read file: $f"
            _TMP=$(mktemp)
            zcat -- "$f" > "$_TMP"
            INPUT="$_TMP"
            ;;
        *)
            [[ -r "$f" ]] || die "cannot read file: $f"
            INPUT="$f"
            ;;
    esac
    trap cleanup_tmp EXIT
}

# check_top: makes sure the -n value is a positive integer
check_top() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "-n must be a positive integer: $1"
}

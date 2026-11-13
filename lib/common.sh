#!/usr/bin/env bash
# Shared helper functions (sourced by the other scripts)

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

# expand_repeats FILE
#   rsyslog writes "message repeated 3 times: [ Failed password ...]" instead of
#   repeating an identical line ($RepeatedMsgReduction is on by default in Ubuntu).
#   That line stands for 3 more attempts, so the inner message is printed 3 times,
#   with the original timestamp and host in front. Other lines are printed as is.
expand_repeats() {
    awk '{
        if (match($0, /message repeated [0-9]+ times: \[ ?/)) {
            prefix = substr($0, 1, RSTART - 1)
            n = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", n)
            msg = substr($0, RSTART + RLENGTH); sub(/ ?\]$/, "", msg)
            for (i = 0; i < n + 0; i++) print prefix msg
            next
        }
        print
    }' "$1"
}

# check_top: makes sure the -n value is a positive integer
check_top() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "-n must be a positive integer: $1"
}

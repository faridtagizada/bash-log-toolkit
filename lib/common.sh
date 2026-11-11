#!/usr/bin/env bash
# Shared helper functions (sourced by the other scripts)

# Simple IPv4 regex (used with grep -E)
# shellcheck disable=SC2034  # kept for scripts that source this file
IP_RE='([0-9]{1,3}\.){3}[0-9]{1,3}'

_TMP_FILES=()
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
    if [[ ${#_TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${_TMP_FILES[@]}"
    fi
}

# new_tmp: creates a temporary file that is removed when the script exits.
# The name is left in REPLY (call it directly, not inside $(...)).
new_tmp() {
    REPLY=$(mktemp) || die "cannot create a temporary file"
    _TMP_FILES+=("$REPLY")
    trap cleanup_tmp EXIT
}

# _decompress TOOL FILE: unpacks FILE into a temporary file and points INPUT at it
_decompress() {
    local tool="$1" f="$2"
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found (needed to read $f)"
    new_tmp
    # Without this check a truncated archive gives a partial result and exit code 0
    "$tool" -dc -- "$f" > "$REPLY" 2>/dev/null \
        || die "cannot decompress (damaged, or not a $tool archive): $f"
    INPUT="$REPLY"
}

# prepare_input FILE
#   FILE = '-'               -> read stdin
#   FILE = *.gz, *.xz, *.bz2 -> decompress
#   anything else            -> used as is
# The result is left in INPUT (so the file can be read more than once).
prepare_input() {
    local f="${1:-}"
    [[ -n "$f" ]] || die "no log file given (use -h for help)"
    if [[ "$f" == "-" ]]; then
        new_tmp
        cat > "$REPLY"
        INPUT="$REPLY"
        return 0
    fi
    # -r alone is also true for a directory, and grep then finds "nothing"
    [[ ! -d "$f" ]] || die "is a directory, not a log file: $f"
    [[ -r "$f" ]] || die "cannot read file: $f"
    case "$f" in
        *.gz)  _decompress gzip "$f" ;;
        *.xz)  _decompress xz "$f" ;;
        *.bz2) _decompress bzip2 "$f" ;;
        *)     INPUT="$f" ;;
    esac
}

# check_top: makes sure the -n value is a positive integer
check_top() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "-n must be a positive integer: $1"
}

# ssh_failed_events FILE
# Prints one line per failed SSH login, tab separated:
#     COUNT  HOUR  IP  KIND  USER
# KIND is "password" (a "Failed password" line) or "probe" (the connection never got as far
# as a password: "Invalid user ..." or "... by authenticating user ... [preauth]", which is
# all a key-only server logs). COUNT is 1, or more when rsyslog folded identical lines into
# "message repeated N times: [ ... ]" (N more attempts on top of the line before it).
#
# Why this is not a plain grep:
#   * The user name is chosen by the attacker and logged as is. A name such as
#     "x from 10.0.0.1" must not put 10.0.0.1 into the report, so the address is taken from
#     the END of the message and the kind of message from its START.
#   * A probe is only reported when the same connection (IP and port) has no "Failed
#     password" line. sshd logs both for one attempt on an invalid user, and counting both
#     would double every attempt.
ssh_failed_events() {
    awk '
    function clean(s) { gsub(/[\001-\037\177]/, "?", s); return s }
    function parse(    p, n, rest, tail, t) {
        KIND = ""; MULT = 1
        p = index($0, ": ")
        if (p == 0) return 0
        MSG = substr($0, p + 2)
        if (MSG ~ /^message repeated [0-9]+ times: \[ /) {
            n = MSG
            sub(/^message repeated /, "", n); sub(/ times: .*$/, "", n)
            MULT = n + 0
            sub(/^message repeated [0-9]+ times: \[ /, "", MSG)
            sub(/\][ \t]*$/, "", MSG)
        }
        if (index(MSG, "Failed password for ") == 1) {
            rest = substr(MSG, 21)
            if (!match(rest, / from [0-9A-Fa-f:.]+(%[A-Za-z0-9_.-]+)? port [0-9]+( ssh2)?[ \t]*$/)) return 0
            USER = substr(rest, 1, RSTART - 1); tail = substr(rest, RSTART + 6)
            sub(/^invalid user /, "", USER)
            KIND = "password"
        } else if (index(MSG, "Invalid user ") == 1) {
            rest = substr(MSG, 14)
            if (!match(rest, / from [0-9A-Fa-f:.]+(%[A-Za-z0-9_.-]+)? port [0-9]+[ \t]*$/)) return 0
            USER = substr(rest, 1, RSTART - 1); tail = substr(rest, RSTART + 6)
            KIND = "probe"
        } else if (match(MSG, /^(Connection closed by|Disconnected from|Connection reset by) authenticating user /)) {
            rest = substr(MSG, RLENGTH + 1)
            if (!match(rest, / [0-9A-Fa-f:.]+(%[A-Za-z0-9_.-]+)? port [0-9]+ \[preauth\][ \t]*$/)) return 0
            USER = substr(rest, 1, RSTART - 1); tail = substr(rest, RSTART + 1)
            KIND = "probe"
        } else {
            return 0
        }
        split(tail, t, " ")
        IP = t[1]; PORT = t[3]
        # ISO 8601: field 1 is "2026-10-08T03:10:01..." ; syslog: field 3 is "03:10:01"
        if ($1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) {
            HOUR = substr($1, 12, 2)
        } else {
            split($3, t, ":")
            HOUR = t[1]
        }
        if (HOUR !~ /^[0-9][0-9]?$/) HOUR = "-"
        return 1
    }
    NR == FNR { if (parse() && KIND == "password") seen[IP "|" PORT] = 1; next }
    parse() {
        if (KIND == "probe" && ((IP "|" PORT) in seen)) next
        printf "%d\t%s\t%s\t%s\t%s\n", MULT, HOUR, IP, KIND, clean(USER)
    }' "$1" "$1"
}

# awk function shared by the web scripts. parse_access(line) splits one line of the
# Apache/Nginx "combined" format by its quotes instead of by blanks, so an empty request
# ("-"), a binary one or a URL with a space in it cannot shift the status code into another
# column. It sets REQ (the request line), TARGET (the URL as it was sent), STATUS and UA.
# shellcheck disable=SC2034,SC2016  # used by the web scripts; the $ signs belong to awk
ACCESS_LOG_AWK='
function parse_access(line,    q, rest, a, b, n) {
    REQ = ""; TARGET = ""; STATUS = ""; UA = ""
    gsub(/\\"/, "%22", line)
    q = index(line, "\"")
    if (q == 0) return 0
    rest = substr(line, q + 1)
    q = index(rest, "\"")
    if (q == 0) return 0
    REQ = substr(rest, 1, q - 1)
    rest = substr(rest, q + 1)
    n = split(rest, a, "\"")
    if (n >= 4) UA = a[4]
    split(a[1], b, " ")
    if (b[1] ~ /^[0-9][0-9][0-9]$/) STATUS = b[1]
    if (REQ ~ / /) {
        TARGET = REQ
        sub(/^[^ ]+ +/, "", TARGET)
        sub(/ +HTTP\/[0-9.]+$/, "", TARGET)
    }
    return 1
}'

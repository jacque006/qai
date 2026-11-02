#!/usr/bin/env bash
# sanitize.sh: normalize and redact text before it is written to observations/.
#
# Usage:
#   sanitize.sh < raw.txt > clean.txt     filter mode: read stdin, write sanitized text to stdout
#   sanitize.sh --check FILE              scan FILE; exit 1 and list offending line numbers if
#                                         anything suspicious remains; exit 0 if clean
#   sanitize.sh --selftest                run built-in checks of the denylist; exit 0 on pass
#
# Every capture script must run --check on its own output as a final step and delete the
# file (and report) if the check fails. When in doubt, this script redacts.
#
# Deliberately does NOT read hostname, user name, env, or any machine identifier.

set -u
export LC_ALL=C

readonly REDACT='[REDACTED]'

# Long base64/hex blob: 32+ token characters with no dot, so file names such as
# 'aiutilities.lua' or 'lua.scd/lua/AI/x.lua' keep their structure.
BLOB_LEFT='(^|[^A-Za-z0-9+/=_.-])'
BLOB_RUN='[A-Za-z0-9+/=_-]{32,}'
BLOB_RIGHT='([^A-Za-z0-9+/=_.-]|$)'

# Denylist. Each entry is an ERE. Order matters only for readability; each is applied in turn.
PATTERNS=(
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'   # email addresses
  '([0-9]{1,3}\.){3}[0-9]{1,3}'                       # IPv4 literals
  '([0-9A-Fa-f]{1,4}:){2,7}[0-9A-Fa-f]{0,4}'          # IPv6 literals (rough, conservative)
  '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}'             # MAC addresses
  '76561[0-9]{12}'                                    # SteamID64
  '\[U:1:[0-9]+\]'                                    # SteamID3
  '/home/[^/[:space:]]+'                              # any /home/<user> path
  '/Users/[^/[:space:]]+'                             # any /Users/<user> path
  'sk-[A-Za-z0-9_-]{8,}'                              # API key shape
  'ghp_[A-Za-z0-9]{20,}'                              # GitHub token shape
  'AKIA[0-9A-Z]{16}'                                  # AWS access key shape
)

# Literal expanded home directory -> the token $HOME. Escape sed-special characters.
home_escaped() {
  printf '%s' "${HOME:-}" | sed 's/[][\.*^$|#&/]/\\&/g'
}

sanitize_stream() {
  local esc p sed_args=()
  esc=$(home_escaped)
  if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
    sed_args+=(-e "s#${esc}#\$HOME#g")
  fi
  for p in "${PATTERNS[@]}"; do
    sed_args+=(-e "s#${p}#${REDACT}#g")
  done
  sed_args+=(-e "s#${BLOB_LEFT}${BLOB_RUN}${BLOB_RIGHT}#\\1${REDACT}\\2#g")
  sed -E "${sed_args[@]}"
}

check_file() {
  local f=$1 p hits=()
  if [ ! -r "$f" ]; then
    echo "sanitize: cannot read '$f'" >&2
    return 2
  fi
  for p in "${PATTERNS[@]}" "${BLOB_LEFT}${BLOB_RUN}${BLOB_RIGHT}"; do
    while IFS= read -r n; do
      hits+=("$n")
    done < <(grep -nE -- "$p" "$f" 2>/dev/null | cut -d: -f1)
  done
  # Expanded home directory appearing literally is also a failure.
  if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
    while IFS= read -r n; do
      hits+=("$n")
    done < <(grep -nF -- "$HOME" "$f" 2>/dev/null | cut -d: -f1)
  fi
  if [ "${#hits[@]}" -gt 0 ]; then
    local uniq
    uniq=$(printf '%s\n' "${hits[@]}" | sort -n -u | tr '\n' ' ')
    echo "sanitize: CHECK FAILED for '$f'. Offending line numbers: $uniq" >&2
    echo "sanitize: the file must not be committed. Delete it and re-run the capture." >&2
    return 1
  fi
  echo "sanitize: check passed for '$f'"
  return 0
}

selftest() {
  local fail=0 out
  expect_clean() {  # input, description
    if printf '%s\n' "$1" | sanitize_stream | grep -q -- "$REDACT"; then :; else
      echo "FAIL (not redacted): $2" >&2; fail=1; fi
  }
  expect_clean 'contact someone@example.com now' 'email'
  expect_clean 'host 192.168.1.20 up' 'ipv4'
  expect_clean 'mac 00:1A:2B:3C:4D:5E seen' 'mac'
  expect_clean 'id 76561198012345678 here' 'steamid64'
  expect_clean 'path /home/alice/games/x' 'home path'
  expect_clean 'path /Users/bob/x' 'users path'
  expect_clean 'key sk-abcdef123456' 'api key'
  expect_clean 'tok ghp_abcdefghijklmnopqrstuv' 'github token'
  expect_clean 'blob QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=ABCDEFG' 'base64 blob'

  out=$(printf 'ok line\n' | sanitize_stream)
  if [ "$out" != "ok line" ]; then echo "FAIL (benign line altered): $out" >&2; fail=1; fi

  if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
    out=$(printf '%s/.steam/x\n' "$HOME" | sanitize_stream)
    case "$out" in
      '$HOME/.steam/x') ;;
      *) echo "FAIL (home not tokenised): $out" >&2; fail=1 ;;
    esac
  fi

  if [ "$fail" -eq 0 ]; then echo "sanitize: selftest passed"; return 0; fi
  echo "sanitize: selftest FAILED" >&2
  return 1
}

case "${1:-}" in
  --check)
    [ $# -eq 2 ] || { echo "usage: sanitize.sh --check FILE" >&2; exit 2; }
    check_file "$2"
    exit $?
    ;;
  --selftest)
    selftest
    exit $?
    ;;
  -h|--help)
    sed -n '2,12p' "$0"
    exit 0
    ;;
  "")
    if [ -t 0 ]; then
      cat >&2 <<'EOF'
sanitize.sh: no input given. It reads text from standard input and writes sanitized text to standard output.

  tools/sanitize.sh < raw.txt > clean.txt        sanitize a file
  printf 'text\n' | tools/sanitize.sh            sanitize piped text
  tools/sanitize.sh --check FILE                 scan FILE; exit 1 if anything suspicious remains
  tools/sanitize.sh --selftest                   run built-in checks of the denylist
EOF
      exit 2
    fi
    sanitize_stream
    ;;
  *)
    echo "usage: sanitize.sh [--check FILE | --selftest] < input" >&2
    exit 2
    ;;
esac

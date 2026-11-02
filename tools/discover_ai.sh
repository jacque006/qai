#!/usr/bin/env bash
# discover_ai.sh: Phase 0 round 3 harvester (local-only extraction).
#
# Run on the game machine from a checkout of this repo:
#   tools/discover_ai.sh
#
# What it does:
#   1. Locates the SCFA install (honors STEAM_LIBRARY, same as discover_local.sh).
#   2. Extracts ONLY the AI-related Lua members from LOUD's .scd archives into a temporary
#      directory outside the repo. The temporary directory is deleted on exit.
#   3. Records structure only: extracted file names and sizes, function names with line
#      numbers, and knob-like assignments with their numeric values (matched text only).
#   4. Runs tools/sanitize.sh --check on the report and writes observations/<date>-ai-N.txt.
#
# Nothing extracted is written into the repo. Full source lines are never printed.

set -u
export LC_ALL=C

readonly APP_ID=9420
readonly GAME_NAME="Supreme Commander Forged Alliance"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd) || exit 1
SAN="$SCRIPT_DIR/sanitize.sh"
OBS_DIR="$REPO_DIR/observations"
DATE=$(date +%Y-%m-%d)

if [ ! -x "$SAN" ]; then
  echo "discover_ai: cannot find sanitizer at $SAN. Aborting; nothing written." >&2
  exit 1
fi

# ---- locate the game install (same probe order as discover_local.sh) --------------------------
CANDIDATE_LIBS=()
[ -n "${STEAM_LIBRARY:-}" ] && CANDIDATE_LIBS+=("$STEAM_LIBRARY")
CANDIDATE_LIBS+=("$HOME/.steam/steam" "$HOME/.local/share/Steam")

GAME_DIR=""
for lib in "${CANDIDATE_LIBS[@]}"; do
  cand="$lib/steamapps/common/$GAME_NAME"
  if [ -d "$cand" ]; then GAME_DIR="$cand"; break; fi
done

if [ -z "$GAME_DIR" ] || [ ! -d "$GAME_DIR/LOUD/gamedata" ]; then
  echo "discover_ai: game install or LOUD/gamedata NOT FOUND. Nothing written." >&2
  exit 1
fi

# ---- temporary extraction area, always removed on exit ----------------------------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/qai-ai.XXXXXX") || { echo "discover_ai: cannot create temp dir" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# AI-related members only. Patterns are zip member globs.
MEMBERS=('lua/AI/*' 'lua/aibrain.lua' 'lua/aipersonality.lua' 'lua/AIChatSorian.lua')
ARCHIVES=(lua.scd loud_misc.scd loud_units.scd)

extract_archive() {  # archive-path dest-dir -> returns 0 if extraction was attempted
  local archive=$1 dest=$2
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$archive" "${MEMBERS[@]}" -d "$dest" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I - "$archive" "$dest" "${MEMBERS[@]}" <<'PY' 2>/dev/null
import fnmatch, sys, zipfile, os
archive, dest, patterns = sys.argv[1], sys.argv[2], sys.argv[3:]
with zipfile.ZipFile(archive) as z:
    for name in z.namelist():
        if name.endswith('/'):
            continue
        if any(fnmatch.fnmatch(name, p) for p in patterns):
            z.extract(name, dest)
PY
  else
    return 1
  fi
}

# ---- build the report on stdout (sanitized before writing) ------------------------------------
report() {
  echo "# QAI AI-structure observation (round 3, local extraction)"
  echo "# harvester: tools/discover_ai.sh   date: $DATE   app_id: $APP_ID"
  echo "# Only file names, function names, line numbers, and knob assignments with values are"
  echo "# recorded. No source lines are printed."
  echo

  echo "## 0. Extraction"
  if ! command -v unzip >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    echo "NOT FOUND: neither unzip nor python3 is available; nothing extracted"
    echo "## end"
    return
  fi
  for a in "${ARCHIVES[@]}"; do
    src="$GAME_DIR/LOUD/gamedata/$a"
    if [ -f "$src" ]; then
      extract_archive "$src" "$TMP/$a.d" || true
      echo "$a: extraction attempted ($(find "$TMP/$a.d" -type f 2>/dev/null | wc -l) AI members copied)"
    else
      echo "$a: NOT FOUND"
    fi
  done
  echo

  echo "## 1. Extracted AI files (size and relative path only)"
  (cd "$TMP" && find . -type f -printf '%s %P\n' | sort -k2 | sed 's#^\([0-9]*\) \./#\1 #')
  echo

  echo "## 2. Function definitions (path:line and name only; max 400)"
  (cd "$TMP" && grep -rnoE '^[[:space:]]*(local[[:space:]]+)?function[[:space:]]+[A-Za-z0-9_.:]+' . 2>/dev/null \
     | sed -E 's#^\./##; s#^([^:]+):([0-9]+):[[:space:]]*(local[[:space:]]+)?function[[:space:]]+#\1 L\2 #' \
     | head -n 400)
  echo

  echo "## 3. Knob-like assignments (name and numeric value only; max 200)"
  (cd "$TMP" && grep -rnoiE '(aggress|persona|expan|threat|ratio|priority|delay|interval|timer|max|min|count|target|experimental|tech)[A-Za-z_]*[[:space:]]*[=:][[:space:]]*-?[0-9]+(\.[0-9]+)?' . 2>/dev/null \
     | sed -E 's#^\./##; s#:([0-9]+):#  L\1  #' | head -n 200)
  echo

  echo "## 4. Table keys that look like tunables (name only; max 100)"
  (cd "$TMP" && grep -rnoiE '\[?"?(aggress|persona|expan|threat|ratio|priority|delay|interval|timer)[A-Za-z_]*"?\]?[[:space:]]*=[[:space:]]*\{' . 2>/dev/null \
     | sed -E 's#^\./##; s#:([0-9]+):#  L\1  #' | head -n 100)
  echo
  echo "## end"
}

# ---- write, check, keep or delete --------------------------------------------------------------
mkdir -p "$OBS_DIR" || { echo "discover_ai: cannot create $OBS_DIR" >&2; exit 1; }
n=1
while [ -e "$OBS_DIR/$DATE-ai-$n.txt" ]; do n=$((n + 1)); done
OUT="$OBS_DIR/$DATE-ai-$n.txt"

echo "discover_ai: writing sanitized report to observations/$(basename "$OUT")"
report | sed "s#${TMP}/##g" | "$SAN" > "$OUT"

if "$SAN" --check "$OUT"; then
  echo "discover_ai: wrote and checked observations/$(basename "$OUT")"
  echo "discover_ai: commit this file and tell the agent it's ready."
else
  rm -f "$OUT"
  echo "discover_ai: the output failed the privacy check and was deleted. Nothing was committed." >&2
  exit 1
fi

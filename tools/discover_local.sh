#!/usr/bin/env bash
# discover_local.sh: Phase 0 discovery harvester for QAI.
#
# Run on the game machine from a checkout of this repo:
#   tools/discover_local.sh
# Writes observations/<date>-discovery-N.txt (sanitized). Commit that file and tell the agent it's ready.
#
# Reads only: the resolved Steam library's Supreme Commander Forged Alliance install directory, and
# the Proton compatdata prefix for app 9420 (top-level *.log files only). Never reads
# userdata, configs, env, hostnames, or anything else. All output passes tools/sanitize.sh.

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
  echo "discover_local: cannot find sanitizer at $SAN. Aborting; nothing written." >&2
  exit 1
fi

# ---- locate the Steam library and the game install -------------------------------------------
# Probe order: STEAM_LIBRARY override (if set), then the default Steam roots.
CANDIDATE_LIBS=()
[ -n "${STEAM_LIBRARY:-}" ] && CANDIDATE_LIBS+=("$STEAM_LIBRARY")
CANDIDATE_LIBS+=("$HOME/.steam/steam" "$HOME/.local/share/Steam")

GAME_DIR=""
LIB_ROOT=""
for lib in "${CANDIDATE_LIBS[@]}"; do
  cand="$lib/steamapps/common/$GAME_NAME"
  if [ -d "$cand" ]; then
    GAME_DIR="$cand"
    LIB_ROOT="$lib"
    break
  fi
done

age_of() {  # epoch seconds -> relative age string
  local now d
  now=$(date +%s)
  d=$(( now - $1 ))
  [ "$d" -lt 0 ] && d=0
  if   [ "$d" -lt 3600 ];    then echo "$(( d / 60 ))m ago"
  elif [ "$d" -lt 86400 ];   then echo "$(( d / 3600 ))h ago"
  else                            echo "$(( d / 86400 ))d ago"
  fi
}

# Rewrite absolute game-dir prefixes to a relative form so paths are structurally identical
# across machines.
relpath_game() { sed "s#^${GAME_DIR}/##"; }

report() {
  echo "# QAI discovery observation"
  echo "# harvester: tools/discover_local.sh   date: $DATE   app_id: $APP_ID"
  echo "# Paths are normalized. Excerpts are matched fragments only, never full source lines."
  echo
  echo "## 0. Locations"
  if [ -n "$GAME_DIR" ]; then
    echo "game_install: FOUND (library probed: $([ -n "${STEAM_LIBRARY:-}" ] && echo 'STEAM_LIBRARY override' || echo 'default roots'))"
  else
    echo "game_install: NOT FOUND (probed STEAM_LIBRARY override and default Steam roots)"
    echo "result: cannot continue with sections 1-4; section 5 still probed below"
  fi
  echo

  if [ -n "$GAME_DIR" ]; then
    echo "## 1. Tree map (LOUD/, top two levels)"
    if [ -d "$GAME_DIR/LOUD" ]; then
      (cd "$GAME_DIR" && find LOUD -mindepth 1 -maxdepth 2 -printf '%y %p\n' | sort)
    else
      echo "LOUD/: NOT FOUND"
    fi
    echo
    echo "## 1b. AI-hinting names under LOUD/gamedata and LOUD/bin"
    for d in gamedata bin; do
      if [ -d "$GAME_DIR/LOUD/$d" ]; then
        (cd "$GAME_DIR" && find "LOUD/$d" \( -iname '*ai*' -o -iname '*sorian*' -o -iname '*platoon*' \
          -o -iname '*builder*' -o -iname '*engineer*' -o -iname '*brain*' \) -printf '%y %p\n' | sort | head -n 300)
      else
        echo "LOUD/$d: NOT FOUND"
      fi
    done
    echo "(names are matched case-insensitively and loosely; expect false positives)"
    echo

    echo "## 2. Documentation digest (LOUD/doc)"
    if [ -d "$GAME_DIR/LOUD/doc" ]; then
      (cd "$GAME_DIR" && find LOUD/doc -type f -printf '%s bytes  %p\n' | sort)
      echo
      echo "### headings (text files only)"
      (cd "$GAME_DIR" && find LOUD/doc -type f -print0 | sort -z | while IFS= read -r -d '' f; do
        if grep -qI . "$f" 2>/dev/null; then
          hits=$(grep -nE '^#{1,6} ' "$f" | head -n 40)
          if [ -n "$hits" ]; then
            echo "-- $f"
            printf '%s\n' "$hits"
          fi
        fi
      done)
      echo
      echo "### keyword hits (line numbers and matched fragments only, max 15 per file)"
      (cd "$GAME_DIR" && find LOUD/doc -type f -print0 | sort -z | while IFS= read -r -d '' f; do
        if grep -qI . "$f" 2>/dev/null; then
          hits=$(grep -nioE 'aggress[a-z]*|difficult[a-z]*|personalit[a-z]*|tuning|config[a-z]*|engineer[a-z]*|platoon[a-z]*|build ratio' "$f" | head -n 15)
          if [ -n "$hits" ]; then
            echo "-- $f"
            printf '%s\n' "$hits"
          fi
        fi
      done)
    else
      echo "LOUD/doc: NOT FOUND"
    fi
    echo

    echo "## 3. Candidate knob hunt (path:line and matched fragment only; max 200 hits)"
    if [ -d "$GAME_DIR/LOUD" ]; then
      (cd "$GAME_DIR" && grep -rnIoi \
          --include='*.lua' --include='*.txt' --include='*.cfg' --include='*.ini' --include='*.json' \
          -E 'factory[a-z_ ]*ratio|engineer[a-z_]*(count|target|max|min)|platoon[a-z_]*(timer|interval|delay)|attack[a-z_]*(timer|interval|delay)|aggress[a-z_]*|threat[a-z_]*|expansion[a-z_]*|experimental[a-z_]*|tech[a-z_]*level|tech[a-z_]*gate' \
          LOUD/gamedata LOUD/bin 2>/dev/null | head -n 200) || true
      [ -z "$(cd "$GAME_DIR" && grep -rnIoi --include='*.lua' --include='*.txt' --include='*.cfg' --include='*.ini' --include='*.json' -E 'aggress|threat|engineer|platoon|expansion|experimental|ratio' LOUD/gamedata LOUD/bin 2>/dev/null | head -n 1)" ] && echo "(no candidate knob matches)"
    else
      echo "LOUD/: NOT FOUND"
    fi
    echo
  fi

  echo "## 4. Log location probe"
  if [ -n "$GAME_DIR" ]; then
    echo "game_dir *.log files:"
    logs=$(cd "$GAME_DIR" && find . -type f -name '*.log' -printf '%s %T@ %p\n' 2>/dev/null | sort -k3 | head -n 100)
    if [ -n "$logs" ]; then
      while IFS=' ' read -r size mtime path; do
        printf '  %s bytes  modified: %s  %s\n' "$size" "$(age_of "${mtime%.*}")" "${path#./}"
      done <<< "$logs"
    else
      echo "  NOT FOUND"
    fi
  else
    echo "game_dir *.log files: NOT FOUND (no game install)"
  fi
  echo

  echo "## 5. Proton compatdata prefix (app $APP_ID), top-level *.log only"
  prefix=""
  if [ -n "$LIB_ROOT" ] && [ -d "$LIB_ROOT/steamapps/compatdata/$APP_ID" ]; then
    prefix="$LIB_ROOT/steamapps/compatdata/$APP_ID"
  fi
  if [ -n "$prefix" ]; then
    echo "prefix: FOUND"
    plogs=$(find "$prefix" -maxdepth 1 -type f -name '*.log' -printf '%s %T@ %f\n' 2>/dev/null | sort -k3 | head -n 50)
    if [ -n "$plogs" ]; then
      while IFS=' ' read -r size mtime name; do
        printf '  %s bytes  modified: %s  %s\n' "$size" "$(age_of "${mtime%.*}")" "$name"
      done <<< "$plogs"
    else
      echo "  NOT FOUND (no top-level *.log in prefix)"
    fi
  else
    echo "prefix: NOT FOUND"
  fi
  echo
  echo "## end"
}

# Pick the next free N so existing observations are never overwritten.
mkdir -p "$OBS_DIR" || { echo "discover_local: cannot create $OBS_DIR" >&2; exit 1; }
n=1
while [ -e "$OBS_DIR/$DATE-discovery-$n.txt" ]; do n=$((n + 1)); done
OUT="$OBS_DIR/$DATE-discovery-$n.txt"

echo "discover_local: writing sanitized report to observations/$(basename "$OUT")"
report | "$SAN" > "$OUT"

if "$SAN" --check "$OUT"; then
  echo "discover_local: wrote and checked observations/$(basename "$OUT")"
  echo "discover_local: commit this file and tell the agent it's ready."
else
  rm -f "$OUT"
  echo "discover_local: the output failed the privacy check and was deleted. Nothing was committed." >&2
  echo "discover_local: report this to the agent; no file was written." >&2
  exit 1
fi

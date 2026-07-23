#!/usr/bin/env bash
# Promote a scout task to a ship task in place: the crewmate keeps its window,
# worktree, and loaded context; only the contract changes. Flips kind= to ship in
# state/<task-id>.meta so fm-teardown.sh applies the full ship-task teardown protection
# again. `--persona <name>` explicitly replaces the retained brief persona; without it,
# an existing data/<task-id>/persona sidecar remains untouched. After promoting, send
# the crewmate its ship instructions via fm-send.sh (inventory scratch state, reset to a
# clean default-branch base, carry over only intended fix changes, create branch
# fm/<task-id>, implement, then report done according to the project's delivery mode).
# Usage: fm-promote.sh <task-id> [--persona <name>]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
"$FM_ROOT/bin/fm-guard.sh" || true
ID=${1:-}
PERSONA=
case "$#" in
  1) ;;
  3)
    [ "$2" = --persona ] || { echo "usage: fm-promote.sh <task-id> [--persona <name>]" >&2; exit 1; }
    PERSONA=$3
    ;;
  *) echo "usage: fm-promote.sh <task-id> [--persona <name>]" >&2; exit 1 ;;
esac
[ -n "$ID" ] || { echo "usage: fm-promote.sh <task-id> [--persona <name>]" >&2; exit 1; }
META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }
grep -qx 'kind=scout' "$META" || { echo "error: task $ID is not a scout task (kind=scout not in meta)" >&2; exit 1; }

if [ -n "$PERSONA" ]; then
  FM_CONFIG_OVERRIDE="$CONFIG" "$FM_ROOT/bin/fm-persona.sh" validate "$PERSONA"
  mkdir -p "$DATA/$ID"
  tmp=$(mktemp "$DATA/$ID/.persona.XXXXXX") || exit 1
  if ! printf '%s\n' "$PERSONA" > "$tmp" || ! chmod 600 "$tmp" || ! mv -f "$tmp" "$DATA/$ID/persona"; then
    rm -f "$tmp"
    exit 1
  fi
fi

TMP="$META.tmp"
if [ -n "$PERSONA" ]; then
  grep -v -E '^(kind|persona)=' "$META" > "$TMP"
else
  grep -v '^kind=' "$META" > "$TMP"
fi
echo "kind=ship" >> "$TMP"
[ -z "$PERSONA" ] || echo "persona=$PERSONA" >> "$TMP"
mv "$TMP" "$META"

HOME_Q=$(printf '%q' "$FM_HOME")
echo "promoted $ID to ship (teardown protection restored)"
echo "next: FM_HOME=$HOME_Q bin/fm-send.sh fm-$ID '<ship instructions: review scratch state with git status and git log; reset to a clean default-branch base; carry over only intended fix changes; create branch fm/$ID; implement; report done>'"

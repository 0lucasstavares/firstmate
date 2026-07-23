#!/usr/bin/env bash
# Manage private reusable crewmate personas.
# Usage: fm-persona.sh init|list|validate [<name>]|render <name>
#        fm-persona.sh inherit|remove-inherited <destination-config-dir>
#
# Personas live only in config/crew-personas/<lowercase-kebab-name>.md.
# `init` atomically installs the tracked sanitized starter library into absent
# local files without replacing a captain's existing definitions.
# `list` prints validated persona names, one per line.
# `validate` validates every local persona, or one named persona.
# `render` validates and prints one named persona.
# `inherit` validates the active source library and atomically replaces only
# <destination-config-dir>/crew-personas, including removals.
#
# Names are lowercase kebab slugs. Persona content is bounded text only, starts
# with one display-name H1, and has exactly the required operational H2 sections.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$CODE_ROOT}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
PERSONA_DIR="$CONFIG/crew-personas"
TEMPLATE_DIR="$CODE_ROOT/docs/examples/crew-personas"
MAX_BYTES=32768
REQUIRED_SECTIONS=(
  Mission
  'Domain Expertise'
  'Tool Expertise'
  'Decision Rules'
  'Working Method'
  'Verification Strategy'
  'Common Failure Modes'
  'Deliverable Standards'
  Boundaries
)

fail() {
  printf 'fm-persona: %s\n' "$*" >&2
  exit 1
}

valid_name() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
}

persona_path() {
  local name=$1
  valid_name "$name" || return 1
  printf '%s/%s.md\n' "$PERSONA_DIR" "$name"
}

safe_persona_dir() {
  [ -d "$PERSONA_DIR" ] && [ ! -L "$PERSONA_DIR" ]
}

validate_file() {
  local file=$1 label=$2 bytes sections expected h1_count
  [ -f "$file" ] && [ ! -L "$file" ] || { printf '%s: missing, not regular, or symlinked\n' "$label" >&2; return 1; }
  bytes=$(wc -c < "$file") || return 1
  [ "$bytes" -le "$MAX_BYTES" ] || { printf '%s: exceeds %s-byte limit\n' "$label" "$MAX_BYTES" >&2; return 1; }
  if LC_ALL=C od -An -v -tx1 "$file" | grep -qw 00; then
    printf '%s: binary content is not allowed\n' "$label" >&2
    return 1
  fi
  h1_count=$(grep -c '^# [^[:space:]].*$' "$file" || true)
  if [ "$h1_count" -ne 1 ] || ! head -n 1 "$file" | grep -q '^# [^[:space:]]'; then
    printf '%s: requires one display-name H1 as its first line\n' "$label" >&2
    return 1
  fi
  sections=$(awk '/^## / { sub(/^## /, ""); print }' "$file")
  expected=$(printf '%s\n' "${REQUIRED_SECTIONS[@]}")
  [ "$sections" = "$expected" ] || {
    printf '%s: requires exactly these H2 sections in order: %s\n' "$label" "${REQUIRED_SECTIONS[*]}" >&2
    return 1
  }
}

validate_one() {
  local name=$1 file
  valid_name "$name" || { printf 'invalid persona name: %s\n' "$name" >&2; return 1; }
  safe_persona_dir || { printf 'persona directory is missing or unsafe: %s\n' "$PERSONA_DIR" >&2; return 1; }
  file=$(persona_path "$name") || return 1
  validate_file "$file" "persona $name"
}

list_names() {
  local file name
  [ -e "$PERSONA_DIR" ] || return 0
  safe_persona_dir || fail "persona directory is unsafe: $PERSONA_DIR"
  while IFS= read -r file; do
    [ -f "$file" ] && [ ! -L "$file" ] || fail "unsafe persona entry: ${file##*/}"
    case "$file" in *.md) ;; *) fail "invalid persona filename: ${file##*/}" ;; esac
    name=${file##*/}
    name=${name%.md}
    valid_name "$name" || fail "invalid persona filename: ${file##*/}"
    validate_file "$file" "persona $name" || exit 1
    printf '%s\n' "$name"
  done < <(find "$PERSONA_DIR" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
}

write_atomic_copy() {
  local src=$1 dest=$2 parent tmp
  parent=${dest%/*}
  mkdir -p "$parent" || return 1
  tmp=$(mktemp "$parent/.fm-persona.XXXXXX") || return 1
  if ! cp "$src" "$tmp" || ! chmod 600 "$tmp" || ! mv -f "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
}

init_library() {
  local file name dest
  [ -d "$TEMPLATE_DIR" ] && [ ! -L "$TEMPLATE_DIR" ] || fail "starter library is missing: $TEMPLATE_DIR"
  mkdir -p "$PERSONA_DIR" || fail "cannot create persona directory: $PERSONA_DIR"
  [ ! -L "$PERSONA_DIR" ] || fail "persona directory is unsafe: $PERSONA_DIR"
  for file in "$TEMPLATE_DIR"/*.md; do
    [ -f "$file" ] || continue
    name=${file##*/}
    name=${name%.md}
    valid_name "$name" || fail "invalid starter persona filename: ${file##*/}"
    validate_file "$file" "starter persona $name" || exit 1
    dest="$PERSONA_DIR/$name.md"
    [ -e "$dest" ] || [ -L "$dest" ] || write_atomic_copy "$file" "$dest" || fail "cannot install starter persona: $name"
  done
}

remove_inherited_library() {
  local dest_config=$1 dest backup
  [ -n "$dest_config" ] || fail "remove-inherited requires a destination config directory"
  [ -d "$dest_config" ] && [ ! -L "$dest_config" ] || fail "destination config directory is unsafe: $dest_config"
  dest="$dest_config/crew-personas"
  [ -e "$dest" ] || [ -L "$dest" ] || return 0
  [ -d "$dest" ] && [ ! -L "$dest" ] || fail "destination persona directory is unsafe: $dest"
  backup=$(mktemp -d "$dest_config/.fm-personas-remove.XXXXXX") || fail "cannot stage persona removal"
  rmdir "$backup" || { rm -rf "$backup"; fail "cannot stage persona removal"; }
  mv "$dest" "$backup" || fail "cannot publish persona removal"
  rm -rf "$backup"
}

inherit_library() {
  local dest_config=$1 dest tmp backup source_file
  [ -n "$dest_config" ] || fail "inherit requires a destination config directory"
  safe_persona_dir || fail "source persona directory is missing or unsafe: $PERSONA_DIR"
  list_names >/dev/null
  mkdir -p "$dest_config" || fail "cannot create destination config directory: $dest_config"
  [ -d "$dest_config" ] && [ ! -L "$dest_config" ] || fail "destination config directory is unsafe: $dest_config"
  dest="$dest_config/crew-personas"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    [ -d "$dest" ] && [ ! -L "$dest" ] || fail "destination persona directory is unsafe: $dest"
  fi
  tmp=$(mktemp -d "$dest_config/.fm-personas.XXXXXX") || fail "cannot stage persona inheritance"
  if ! cp -R "$PERSONA_DIR/." "$tmp"; then
    rm -rf "$tmp"
    fail "cannot copy persona inheritance"
  fi
  for source_file in "$tmp"/*.md; do
    [ -f "$source_file" ] || continue
    validate_file "$source_file" "staged inherited persona ${source_file##*/}" || { rm -rf "$tmp"; exit 1; }
  done
  backup=
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup=$(mktemp -d "$dest_config/.fm-personas-backup.XXXXXX") || { rm -rf "$tmp"; fail "cannot stage persona replacement"; }
    rmdir "$backup" || { rm -rf "$tmp" "$backup"; fail "cannot stage persona replacement"; }
    if ! mv "$dest" "$backup"; then
      rm -rf "$tmp"
      fail "cannot stage persona replacement"
    fi
  fi
  if ! mv "$tmp" "$dest"; then
    [ -z "$backup" ] || mv "$backup" "$dest" || true
    rm -rf "$tmp"
    fail "cannot publish inherited personas"
  fi
  [ -z "$backup" ] || rm -rf "$backup"
}

case "${1:-}" in
  init)
    [ "$#" -eq 1 ] || fail "usage: fm-persona.sh init"
    init_library
    ;;
  list)
    [ "$#" -eq 1 ] || fail "usage: fm-persona.sh list"
    list_names
    ;;
  validate)
    case "$#" in
      1) list_names >/dev/null ;;
      2) validate_one "$2" ;;
      *) fail "usage: fm-persona.sh validate [<name>]" ;;
    esac
    ;;
  render)
    [ "$#" -eq 2 ] || fail "usage: fm-persona.sh render <name>"
    validate_one "$2"
    cat "$(persona_path "$2")"
    ;;
  inherit)
    [ "$#" -eq 2 ] || fail "usage: fm-persona.sh inherit <destination-config-dir>"
    inherit_library "$2"
    ;;
  remove-inherited)
    [ "$#" -eq 2 ] || fail "usage: fm-persona.sh remove-inherited <destination-config-dir>"
    remove_inherited_library "$2"
    ;;
  -h|--help)
    sed -n '2,18p' "$0" | sed 's/^# //'
    ;;
  *)
    fail "usage: fm-persona.sh init|list|validate [<name>]|render <name>"
    ;;
esac

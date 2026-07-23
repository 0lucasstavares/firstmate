#!/usr/bin/env bash
# Behavior tests for private crewmate persona validation and brief integration.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-persona)
HOME_DIR="$TMP_ROOT/home"
CONFIG="$HOME_DIR/config"
mkdir -p "$CONFIG"
PERSONA="$ROOT/bin/fm-persona.sh"

run_persona() {
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$CONFIG" "$PERSONA" "$@"
}

install_library() {
  run_persona init || fail "starter persona init failed"
}

test_initial_library_lists_validates_and_renders() {
  local listed rendered name
  install_library
  listed=$(run_persona list) || fail "starter library list failed"
  for name in architect backend-engineer data-engineer data-scientist investigator reviewer; do
    assert_contains "$listed" "$name" "starter library missing $name"
    run_persona validate "$name" || fail "starter persona $name did not validate"
  done
  rendered=$(run_persona render investigator) || fail "render investigator failed"
  assert_contains "$rendered" '# Investigator' "render lost display heading"
  assert_contains "$rendered" '## Boundaries' "render lost required boundary section"
  pass "fm-persona: initial library lists, validates, and renders"
}

test_safe_resolution_and_content_rejection() {
  local outside err status
  outside="$TMP_ROOT/outside.md"
  printf '# Outside\n\n## Mission\n' > "$outside"
  err=$(run_persona render ../outside 2>&1); status=$?
  expect_code 1 "$status" "traversal name must fail"
  assert_contains "$err" 'invalid persona name' "traversal refusal lacked diagnostic"
  err=$(run_persona render missing 2>&1); status=$?
  expect_code 1 "$status" "missing persona must fail"
  ln -s "$outside" "$CONFIG/crew-personas/escape.md"
  err=$(run_persona validate escape 2>&1); status=$?
  expect_code 1 "$status" "escaping symlink must fail"
  assert_contains "$err" 'symlinked' "symlink refusal lacked diagnostic"
  printf 'x\0y' > "$CONFIG/crew-personas/binary.md"
  err=$(run_persona validate binary 2>&1); status=$?
  expect_code 1 "$status" "binary persona must fail"
  assert_contains "$err" 'binary content' "binary refusal lacked diagnostic"
  head -c 32769 /dev/zero | tr '\000' x > "$CONFIG/crew-personas/oversized.md"
  err=$(run_persona validate oversized 2>&1); status=$?
  expect_code 1 "$status" "oversized persona must fail"
  assert_contains "$err" 'exceeds' "oversize refusal lacked diagnostic"
  cat > "$CONFIG/crew-personas/incomplete.md" <<'EOF'
# Incomplete

## Mission
Only one section.
EOF
  err=$(run_persona validate incomplete 2>&1); status=$?
  expect_code 1 "$status" "missing required sections must fail"
  assert_contains "$err" 'requires exactly these H2 sections' "section refusal lacked diagnostic"
  rm -f "$CONFIG/crew-personas/escape.md" "$CONFIG/crew-personas/binary.md" "$CONFIG/crew-personas/oversized.md" "$CONFIG/crew-personas/incomplete.md"
  pass "fm-persona: names, symlinks, binary, size, and sections fail safely"
}

test_brief_profile_placement_and_no_persona_compatibility() {
  local no_profile with_profile scout
  mkdir -p "$HOME_DIR/data"
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-brief.sh" no-profile repo >/dev/null || fail "no-persona brief failed"
  no_profile="$HOME_DIR/data/no-profile/brief.md"
  assert_no_grep '# Work Profile' "$no_profile" "no-persona brief changed"
  assert_absent "$HOME_DIR/data/no-profile/persona" "no-persona brief wrote a sidecar"
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-brief.sh" with-profile repo --persona investigator >/dev/null || fail "ship persona brief failed"
  with_profile="$HOME_DIR/data/with-profile/brief.md"
  assert_grep '# Work Profile' "$with_profile" "ship persona brief omitted Work Profile"
  assert_grep '# Herdr lifecycle declaration - NOT ENABLED' "$with_profile" "persona displaced mandatory Herdr section"
  assert_grep '# Definition of done' "$with_profile" "persona displaced Definition of done"
  [ "$(cat "$HOME_DIR/data/with-profile/persona")" = investigator ] || fail "persona sidecar was not canonical"
  [ ! -e "$HOME_DIR/data/with-profile/.persona" ] || fail "persona temporary sidecar remained"
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-brief.sh" scout-profile repo --scout --persona reviewer >/dev/null || fail "scout persona brief failed"
  scout="$HOME_DIR/data/scout-profile/brief.md"
  task_line=$(grep -n '^# Task$' "$scout" | cut -d: -f1)
  profile_line=$(grep -n '^# Work Profile$' "$scout" | cut -d: -f1)
  setup_line=$(grep -n '^# Setup$' "$scout" | cut -d: -f1)
  [ "$task_line" -lt "$profile_line" ] && [ "$profile_line" -lt "$setup_line" ] || fail "Work Profile placement changed mandatory ordering"
  pass "fm-persona: ship/scout profile briefs preserve mandatory sections and no-persona output"
}

test_secondmate_inheritance_updates_and_removes_library() {
  local source dest
  source="$TMP_ROOT/inherit-source"
  dest="$TMP_ROOT/inherit-dest"
  mkdir -p "$source" "$dest"
  printf 'config/crew-personas/\n' > "$TMP_ROOT/inherit-ignore"
  git init -q -b main "$TMP_ROOT/inherit-repo"
  cp "$TMP_ROOT/inherit-ignore" "$TMP_ROOT/inherit-repo/.gitignore"
  git -C "$TMP_ROOT/inherit-repo" add .gitignore
  git -C "$TMP_ROOT/inherit-repo" -c user.name=tests -c user.email=tests@example.invalid commit -qm initial
  dest="$TMP_ROOT/inherit-repo/config"
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$source" "$PERSONA" init >/dev/null || fail "inherit source init failed"
  # shellcheck source=bin/fm-config-inherit-lib.sh
  FM_ROOT="$ROOT" . "$ROOT/bin/fm-config-inherit-lib.sh"
  FM_ROOT="$ROOT" propagate_inheritable_config "$source" "$dest" || fail "persona inheritance failed"
  assert_present "$dest/crew-personas/investigator.md" "persona inheritance omitted starter library"
  assert_absent "$dest/crew-personas/.fm-personas" "persona inheritance left staging material"
  rm -f "$source/crew-personas/reviewer.md"
  FM_ROOT="$ROOT" propagate_inheritable_config "$source" "$dest" || fail "persona inheritance update failed"
  assert_absent "$dest/crew-personas/reviewer.md" "persona inheritance did not remove deleted persona"
  rm -rf "$source/crew-personas"
  FM_ROOT="$ROOT" propagate_inheritable_config "$source" "$dest" || fail "persona inheritance absence mirror failed"
  assert_absent "$dest/crew-personas" "persona inheritance did not remove absent source library"
  pass "persona inheritance updates and removes only the inherited library"
}

test_promotion_retains_or_explicitly_replaces_persona() {
  local meta
  mkdir -p "$HOME_DIR/state" "$HOME_DIR/data/promote-persona"
  meta="$HOME_DIR/state/promote-persona.meta"
  printf 'window=fm-promote-persona\nkind=scout\npersona=investigator\n' > "$meta"
  printf 'investigator\n' > "$HOME_DIR/data/promote-persona/persona"
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-promote.sh" promote-persona --persona reviewer >/dev/null || fail "persona promotion failed"
  assert_grep 'kind=ship' "$meta" "promotion did not preserve ship conversion"
  assert_grep 'persona=reviewer' "$meta" "explicit promotion persona did not override metadata"
  [ "$(cat "$HOME_DIR/data/promote-persona/persona")" = reviewer ] || fail "explicit promotion persona did not override sidecar"
  mkdir -p "$HOME_DIR/data/retain-persona"
  printf 'window=fm-retain-persona\nkind=scout\npersona=investigator\n' > "$HOME_DIR/state/retain-persona.meta"
  printf 'investigator\n' > "$HOME_DIR/data/retain-persona/persona"
  FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-promote.sh" retain-persona >/dev/null || fail "persona retention promotion failed"
  assert_grep 'persona=investigator' "$HOME_DIR/state/retain-persona.meta" "promotion did not retain metadata persona"
  [ "$(cat "$HOME_DIR/data/retain-persona/persona")" = investigator ] || fail "promotion did not retain persona sidecar"
  pass "promotion retains persona state unless explicitly replaced"
}

test_initial_library_lists_validates_and_renders
test_safe_resolution_and_content_rejection
test_brief_profile_placement_and_no_persona_compatibility
test_secondmate_inheritance_updates_and_removes_library
test_promotion_retains_or_explicitly_replaces_persona

echo "# all fm-persona tests passed"

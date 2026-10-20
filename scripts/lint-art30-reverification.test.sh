#!/usr/bin/env bash
# Synthesized-repo battery for the Art. 30 re-verification trigger gate.
# Fixtures are invented. This file does not copy cloud-init.yml, ci-deploy.sh,
# journald-soleur.conf, or the live PA-8 section (f) cell.
set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO_ROOT/scripts/lint-art30-reverification.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/pr-quality-guards.yml"
RUNBOOK="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md"
MANIFEST_FILE="$REPO_ROOT/knowledge-base/legal/art30-reverification-triggers.yml"
POINTER='The check executes knowledge-base/legal/art30-reverification-triggers.yml. This list stays numbered 1 through 7. That file is the predicate.'
CELL_BASE='| **(f) Retention** | Reviewed **(1)** **(2)** **(3)** **(4)** **(5)** **(6)** **(7)** on 2020-01-01 with word alpha.'
CELL_PASS='| **(f) Retention** | Reviewed **(1)** **(2)** **(3)** **(4)** **(5)** **(6)** **(7)** on 2026-10-21 with word noted-2 noted-4.'
ROW1_WANT=1

fails=0
passes=0
pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1" >&2; }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

APPROVED_MANIFEST="$(cat <<'EOF'
triggers:
  1:
    class: unactuated
  2:
    class: actuated
  3:
    class: unactuated
  4:
    class: actuated
  5:
    class: actuated
  6:
    class: unactuated
  7:
    class: unactuated
sites:
  - kind: path-token
    paths:
      - apps/web-platform/infra/cloud-init.yml
      - apps/web-platform/infra/ci-deploy.sh
    groups:
      - token: --log-driver
        fires: [2, 4]
      - token: --log-opt
        fires: [2, 4]
      - token: --restart
        fires: [4]
  - kind: file
    paths:
      - apps/web-platform/infra/journald-soleur.conf
    fires: [5]
EOF
)"

if [[ ! -f "$GATE" ]]; then
  fail "scripts/lint-art30-reverification.sh is absent"
  printf 'passed: %s  failed: %s\n' "$passes" "$fails" >&2
  exit 1
fi

SANDBOX="$(mktemp -d -t art30-reverification.XXXXXXXX)" || { printf 'mktemp failed\n' >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf -- "$SANDBOX"' EXIT

SEED_CELL="$CELL_BASE"
SEED_MANIFEST=1
SEED_POINTER=1
SEED_ITEM7=1
SEED_DRIVER_BASE=0
RUN_MODE=normal
GATE_PATH="$GATE"
EXTRA_PATH=""

reset_seed() {
  SEED_CELL="$CELL_BASE"
  SEED_MANIFEST=1
  SEED_POINTER=1
  SEED_ITEM7=1
  SEED_DRIVER_BASE=0
  RUN_MODE=normal
  GATE_PATH="$GATE"
  EXTRA_PATH=""
}

write_register() {
  local d="$1" pa8="$2" pa2="${3:-| **(f) Retention** | other activity word 2019-01-01.}"
  assert_fixture_dir "$d"
  printf '%s\n' \
    '## Processing Activity 2 — Example' \
    "$pa2" \
    '' \
    '## Processing Activity 8 — Operational Telemetry' \
    '| **(b) Purpose** | telemetry |' \
    "$pa8" \
    '' \
    '## Processing Activity 9 — Next' \
    '| **(f) Retention** | next activity word. |' \
    > "$d/knowledge-base/legal/article-30-register.md"
}

write_decoy_first_cell() {
  local d="$1"
  assert_fixture_dir "$d"
  printf '%s\n' \
    '## Processing Activity 2 — Example' \
    '| **(f) Retention** | other activity word 2019-01-01.' \
    '' \
    '## Processing Activity 8 — Operational Telemetry' \
    '| **(b) Purpose** | telemetry |' \
    "$CELL_PASS" \
    "$CELL_BASE" \
    '' \
    '## Processing Activity 9 — Next' \
    '| **(f) Retention** | next activity word. |' \
    > "$d/knowledge-base/legal/article-30-register.md"
}

write_fake_pa8_pair() {
  local d="$1"
  assert_fixture_dir "$d"
  printf '%s\n' \
    '## Processing Activity 8 — Decoy' \
    "$CELL_PASS" \
    '## Processing Activity 9 — Decoy' \
    '## Processing Activity 2 — Example' \
    '| **(f) Retention** | other activity word 2019-01-01.' \
    '' \
    '## Processing Activity 8 — Operational Telemetry' \
    '| **(b) Purpose** | telemetry |' \
    '| **(f) Retention** | Reviewed **(1)** **(2)** **(3)** **(4)** **(5)** **(6)** **(7)** on 2020-01-01 with word alpha.' \
    '' \
    '## Processing Activity 9 — Next' \
    '| **(f) Retention** | next activity word. |' \
    > "$d/knowledge-base/legal/article-30-register.md"
}

replace_register_with_symlink() {
  local d="$1"
  assert_fixture_dir "$d"
  printf '%s\n' \
    '## Processing Activity 8 — Decoy' \
    "$CELL_PASS" \
    '## Processing Activity 9 — Decoy' \
    > "$d/knowledge-base/legal/decoy-register.md"
  rm -f -- "$d/knowledge-base/legal/article-30-register.md"
  ln -s decoy-register.md -- "$d/knowledge-base/legal/article-30-register.md"
}

write_prose_retention() {
  local d="$1"
  assert_fixture_dir "$d"
  printf '%s\n' \
    '## Processing Activity 2 — Example' \
    '| **(f) Retention** | other activity word 2019-01-01.' \
    '' \
    '## Processing Activity 8 — Operational Telemetry' \
    '| **(b) Purpose** | telemetry |' \
    'see (f) Retention on 2026-10-21 with word noted-2 noted-4 **(1)** **(2)** **(3)** **(4)** **(5)** **(6)** **(7)**.' \
    '' \
    '## Processing Activity 9 — Next' \
    '| **(f) Retention** | next activity word. |' \
    > "$d/knowledge-base/legal/article-30-register.md"
}

write_nul_register() {
  local d="$1"
  assert_fixture_dir "$d"
  write_register "$d" "$CELL_PASS"
  printf '\0' >> "$d/knowledge-base/legal/article-30-register.md"
}

write_multiline_symlink_register() {
  local d="$1" target
  assert_fixture_dir "$d"
  target=$(printf '## Processing Activity 8 — Decoy\n%s\n' "$CELL_PASS")
  rm -f -- "$d/knowledge-base/legal/article-30-register.md"
  ln -s "$target" -- "$d/knowledge-base/legal/article-30-register.md"
}

write_runbook() {
  local d="$1"
  assert_fixture_dir "$d"
  {
    printf '%s\n' '### Re-verification triggers' ''
    if [[ "$SEED_POINTER" == 1 ]]; then
      printf '%s\n' "$POINTER" ''
    fi
    printf '%s\n' \
      '1. Annual review synthesized.' \
      '2. Flag change synthesized.' \
      '3. Shipper synthesized.' \
      '4. Restart synthesized.' \
      '5. Journald synthesized.' \
      '6. Retention synthesized.'
    if [[ "$SEED_ITEM7" == 1 ]]; then
      printf '%s\n' '7. Source synthesized.'
    fi
    printf '%s\n' '' '### Steps' '' 'Dormant synthesized flow.'
  } > "$d/knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md"
}

write_manifest_text() {
  local d="$1" text="$2"
  assert_fixture_dir "$d"
  printf '%s\n' "$text" > "$d/knowledge-base/legal/art30-reverification-triggers.yml"
}

commit_all() {
  local d="$1" msg="$2"
  assert_fixture_dir "$d"
  git -C "$d" add -A
  git -C "$d" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -m "$msg"
}

seed() {
  local d
  d="$(mktemp -d "$SANDBOX/case.XXXXXXXX")" || return 1
  assert_fixture_dir "$d"
  mkdir -p \
    "$d/apps/web-platform/infra" \
    "$d/knowledge-base/legal" \
    "$d/knowledge-base/engineering/operations/runbooks"
  printf '%s\n' '# synthesized unit' 'echo boot' '"log-driver": "json-file"' \
    > "$d/apps/web-platform/infra/cloud-init.yml"
  {
    printf '%s\n' '#!/bin/sh' 'echo start'
    if [[ "$SEED_DRIVER_BASE" == 1 ]]; then
      printf '%s\n' 'docker run --log-driver journald'
    fi
  } > "$d/apps/web-platform/infra/ci-deploy.sh"
  printf '%s\n' '# synthesized cap' 'SystemMaxUse=1G' \
    > "$d/apps/web-platform/infra/journald-soleur.conf"
  write_register "$d" "$SEED_CELL"
  write_runbook "$d"
  if [[ "$SEED_MANIFEST" == 1 ]]; then
    write_manifest_text "$d" "$APPROVED_MANIFEST"
  fi
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  commit_all "$d" base
  git -C "$d" checkout -q -b feat
  printf '%s\n' "$d"
}

run_gate() {
  local d="$1" sha rc=0 path_prefix=()
  assert_fixture_dir "$d"
  sha="$(git -C "$d" rev-parse refs/heads/main)"
  if [[ -n "$EXTRA_PATH" ]]; then
    path_prefix=("PATH=${EXTRA_PATH}:$PATH")
  fi
  : > "$SANDBOX/last.out"
  rc=0
  case "$RUN_MODE" in
    normal)
      (
        cd "$d" || exit 2
        env -u GITHUB_BASE_REF EVENT_NAME= MERGE_GROUP_BASE_SHA="$sha" \
          ${path_prefix[@]+"${path_prefix[@]}"} \
          bash "$GATE_PATH"
      ) >"$SANDBOX/last.out" 2>&1 || rc=$?
      ;;
    merge-empty)
      (
        cd "$d" || exit 2
        env -u GITHUB_BASE_REF EVENT_NAME=merge_group MERGE_GROUP_BASE_SHA= \
          bash "$GATE_PATH"
      ) >"$SANDBOX/last.out" 2>&1 || rc=$?
      ;;
    no-base)
      (
        cd "$d" || exit 2
        env -u GITHUB_BASE_REF -u MERGE_GROUP_BASE_SHA -u EVENT_NAME \
          bash "$GATE_PATH"
      ) >"$SANDBOX/last.out" 2>&1 || rc=$?
      ;;
    *)
      printf 'bad RUN_MODE\n' >&2
      exit 2
      ;;
  esac
  printf '%s\n' "$rc"
}

expect_rc() {
  local name="$1" want="$2" got="$3" snippet
  if [[ "$got" == "$want" ]]; then
    pass "$name"
  else
    snippet="$(head -c 300 "$SANDBOX/last.out" | tr '\n' ' ')"
    fail "$name: expected rc=$want got rc=$got -- $snippet"
  fi
}

want_text() {
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$SANDBOX/last.out"; then
    pass "$name"
  else
    fail "$name: annotation lacks [$needle]"
  fi
}

forbid_text() {
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$SANDBOX/last.out"; then
    fail "$name: annotation contains [$needle]"
  else
    pass "$name"
  fi
}

add_line() {
  local d="$1" rel="$2" text="$3"
  assert_fixture_dir "$d"
  printf '%s\n' "$text" >> "$d/$rel"
}

overwrite() {
  local d="$1" rel="$2" text="$3"
  assert_fixture_dir "$d"
  printf '%s\n' "$text" > "$d/$rel"
}

write_nul_payload() {
  local d="$1" rel="$2"
  assert_fixture_dir "$d"
  printf 'line\n\0\n' > "$d/$rel"
}

replace_with_symlink() {
  local d="$1"
  assert_fixture_dir "$d"
  rm -f "$d/apps/web-platform/infra/journald-soleur.conf"
  ln -s synthesized-target "$d/apps/web-platform/infra/journald-soleur.conf"
  git -C "$d" add -A
}

rename_away() {
  local d="$1"
  assert_fixture_dir "$d"
  git -C "$d" mv -- \
    apps/web-platform/infra/journald-soleur.conf \
    apps/web-platform/infra/journald-soleur.conf.moved
}

dispatch_ok() {
  local f="$1" line in_job=0 seen_steps=0 job_has_if=0 step_n=0
  local backstop_step=0 gate_step=0 step_has_if=0 step_has_event=0 step_has_sha=0
  local gate_if=1 gate_event=0 gate_sha=0
  [[ -f "$f" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ "$in_job" == 0 && "$line" == "  enforce:" ]]; then
      in_job=1
      continue
    fi
    if [[ "$in_job" == 1 && "$line" =~ ^[[:space:]]{2}[A-Za-z0-9_-]+:[[:space:]]*$ && "$line" != "  enforce:" ]]; then
      break
    fi
    [[ "$in_job" == 1 ]] || continue
    if [[ "$seen_steps" == 0 && "$line" =~ ^[[:space:]]+if: ]]; then
      job_has_if=1
    fi
    if [[ "$line" == "    steps:" ]]; then
      seen_steps=1
    fi
    if [[ "$line" =~ ^[[:space:]]{6}-[[:space:]] ]]; then
      step_n=$((step_n + 1))
      step_has_if=0
      step_has_event=0
      step_has_sha=0
    fi
    if [[ "$line" =~ ^[[:space:]]+if: ]]; then
      step_has_if=1
    fi
    if [[ "$line" == *"EVENT_NAME:"* ]]; then
      step_has_event=1
    fi
    if [[ "$line" == *"MERGE_GROUP_BASE_SHA:"* ]]; then
      step_has_sha=1
    fi
    if [[ "$line" == *"check-backstop-revision.sh"* ]]; then
      backstop_step=$step_n
    fi
    if [[ "$line" == *"bash scripts/lint-art30-reverification.sh"* ]]; then
      gate_step=$step_n
      gate_if=$step_has_if
      gate_event=$step_has_event
      gate_sha=$step_has_sha
    fi
  done < "$f"
  [[ "$job_has_if" == 0 && "$gate_step" -gt "$backstop_step" && "$backstop_step" -gt 0 && "$gate_if" == 0 && "$gate_event" == 1 && "$gate_sha" == 1 ]]
}

# --- rows -------------------------------------------------------------------

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 1 flag without review hunk" "$ROW1_WANT" "$RC"
want_text "row 1 names ci-deploy.sh" "apps/web-platform/infra/ci-deploy.sh"
want_text "row 1 names fired id 2" " 2"
want_text "row 1 names fired id 4" " 4"
forbid_text "row 1 does not echo the flag line" "max-size=1m"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
commit_all "$D" head
assert_fixture_dir "$SANDBOX"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SANDBOX/exit0-stub.sh"
GATE_PATH="$SANDBOX/exit0-stub.sh"
RC="$(run_gate "$D")"
if [[ "$RC" == "0" && "$ROW1_WANT" == "1" ]]; then
  pass "row 2 exit 0 stub is not accepted as a row-1 rejection"
else
  fail "row 2 exit 0 stub rc=$RC want-for-row1=$ROW1_WANT"
fi

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_register "$D" "${CELL_BASE} 2026-10-03 **(2)** **(4)** noted"
overwrite "$D" apps/web-platform/infra/journald-soleur.conf $'# synthesized cap moved\nSystemMaxUse=1G'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 3 journald touched without id 5" 1 "$RC"
want_text "row 3 names journald" "journald-soleur.conf"

reset_seed
D="$(seed)"
MANIFEST_ACTUATED="$(printf '%s\n' "$APPROVED_MANIFEST" | sed '0,/class: unactuated/s//class: actuated/')"
write_manifest_text "$D" "$MANIFEST_ACTUATED"
write_register "$D" "${CELL_BASE} 2026-10-04 **(1)** stated"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 4 id 1 actuated" 1 "$RC"
want_text "row 4 shape" "shape"

reset_seed
D="$(seed)"
MANIFEST_DROP="$(printf '%s\n' "$APPROVED_MANIFEST" | grep -v 'ci-deploy.sh' || true)"
write_manifest_text "$D" "$MANIFEST_DROP"
write_register "$D" "${CELL_BASE} 2026-10-05 **(2)** **(4)** noted"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 5 dropped ci-deploy.sh" 1 "$RC"
want_text "row 5 shape" "shape"

reset_seed
D="$(seed)"
MANIFEST_DAEMON="$(printf '%s\n' "$APPROVED_MANIFEST" | sed 's#apps/web-platform/infra/cloud-init.yml#apps/web-platform/infra/daemon.json#')"
write_manifest_text "$D" "$MANIFEST_DAEMON"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 6 daemon.json path" 1 "$RC"
want_text "row 6 shape" "shape"

reset_seed
SEED_ITEM7=0
D="$(seed)"
commit_all "$D" head || true
RC="$(run_gate "$D")"
expect_rc "row 7 deleted runbook id 7" 1 "$RC"

reset_seed
SEED_CELL='| **(f) Retention** | Reviewed **(1)** **(2)** **(3)** **(4)** **(6)** **(7)** on 2020-01-01 with word alpha.'
D="$(seed)"
RC="$(run_gate "$D")"
expect_rc "row 8 removed bold id 5" 1 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-driver journald'
write_register "$D" "$CELL_BASE" "| **(f) Retention** | other activity 2026-10-09 **(2)** **(4)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 9 review hunk only in PA-2" 1 "$RC"

reset_seed
SEED_CELL='| **(f) Retention** | Reviewed **(1)** **(2)** **(3)** **(4)** **(5)** **(6)** **(7)** on 2020-01-01 with word alpha prefix=2026-09-16.'
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_register "$D" "${SEED_CELL} 2026-09-16 **(2)** **(4)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 10 date already in removed cell text" 1 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-driver journald'
write_register "$D" "${CELL_BASE} 2026-10-11 **(2)** **(4)**"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 11 date and ids with no letter-word" 1 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --restart always'
write_register "$D" "${CELL_BASE} 2026-10-12 **(2)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 12 restart names only id 2" 1 "$RC"

reset_seed
SEED_MANIFEST=0
D="$(seed)"
RC="$(run_gate "$D")"
expect_rc "row 13 manifest omitted" 1 "$RC"

reset_seed
D="$(seed)"
write_manifest_text "$D" $'triggers: [\n  :'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 14 unparseable manifest" 1 "$RC"

reset_seed
D="$(seed)"
RUN_MODE=merge-empty
RC="$(run_gate "$D")"
expect_rc "row 15 empty merge_group base" 1 "$RC"

reset_seed
D="$(seed)"
RUN_MODE=no-base
RC="$(run_gate "$D")"
expect_rc "row 16 unresolved base exits 2" 2 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/cloud-init.yml '  # docker run --log-driver journald'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 17 comment flag" 0 "$RC"

reset_seed
D="$(seed)"
overwrite "$D" apps/web-platform/infra/cloud-init.yml $'# synthesized unit\necho boot\n"log-driver": "journald"'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 18 json log-driver key" 0 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/cloud-init.yml 'docker run --restart-policy always'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 19 non-flag line and restart-policy" 0 "$RC"

reset_seed
D="$(seed)"
overwrite "$D" apps/web-platform/infra/journald-soleur.conf $'# synthesized cap edited\nSystemMaxUse=1G'
write_register "$D" "${CELL_BASE} 2026-10-20 **(5)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 20 journald comment with id 5 hunk" 0 "$RC"

reset_seed
SEED_MANIFEST=0
D="$(seed)"
write_manifest_text "$D" "$APPROVED_MANIFEST"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 21 birth manifest and no anchor change" 0 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/cloud-init.yml 'docker run --log-driver journald'
write_register "$D" "${CELL_BASE} 2026-10-22 **(2)** **(4)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 22 log-driver with date ids and a word" 0 "$RC"

assert_fixture_dir "$SANDBOX"
cat > "$SANDBOX/workflow-good.yml" <<'EOF'
jobs:
  enforce:
    runs-on: ubuntu-latest
    steps:
      - name: Enforce legal-doc cross-document lockstep
        run: echo legal
      - name: Enforce BACKSTOP_REVISION bump on memory-backstop hook changes
        run: bash scripts/check-backstop-revision.sh
      - name: Enforce Art. 30 re-verification triggers
        env:
          EVENT_NAME: ${{ github.event_name }}
          MERGE_GROUP_BASE_SHA: ${{ github.event.merge_group.base_sha }}
        run: bash scripts/lint-art30-reverification.sh
EOF
cat > "$SANDBOX/workflow-bad.yml" <<'EOF'
jobs:
  enforce:
    runs-on: ubuntu-latest
    steps:
      - name: Enforce legal-doc cross-document lockstep
        run: echo legal
      - name: Enforce BACKSTOP_REVISION bump on memory-backstop hook changes
        run: bash scripts/check-backstop-revision.sh
EOF
if dispatch_ok "$SANDBOX/workflow-good.yml"; then
  pass "row 23 control accepts a step after the backstop"
else
  fail "row 23 control rejected a well-formed step"
fi
if dispatch_ok "$SANDBOX/workflow-bad.yml"; then
  fail "row 23 removed invocation was accepted"
else
  pass "row 23 removed invocation is RED"
fi
if dispatch_ok "$WORKFLOW"; then
  pass "row 23 real enforce job invokes the script after the backstop"
else
  fail "row 23 real enforce job is missing the script step"
fi

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_register "$D" "${CELL_BASE/alpha./beta.}"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 24 unrelated token on a pre-filled cell" 1 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_register "$D" "${CELL_BASE} 2026-10-25 **(2)** **(4)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 25 pre-filled cell plus date ids and a word" 0 "$RC"

reset_seed
SEED_DRIVER_BASE=1
D="$(seed)"
overwrite "$D" apps/web-platform/infra/ci-deploy.sh $'#!/bin/sh\necho start'
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 26 deleted log-driver line" 1 "$RC"

reset_seed
D="$(seed)"
rename_away "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 27 rename journald without id 5" 1 "$RC"

reset_seed
D="$(seed)"
write_nul_payload "$D" apps/web-platform/infra/ci-deploy.sh
commit_all "$D" head
GIT_RC=0
GIT_OUT="$(git -C "$D" diff --no-ext-diff --no-color main...HEAD -- apps/web-platform/infra/ci-deploy.sh)" || GIT_RC=$?
if [[ "$GIT_RC" == 0 ]]; then
  pass "row 28 git diff of a NUL exits 0"
else
  fail "row 28 git diff exited $GIT_RC"
fi
BIN_HIT=0
while IFS= read -r line; do
  if [[ "$line" =~ ^Binary\ files\ .+\ differ$ ]]; then
    BIN_HIT=1
  fi
done <<< "$GIT_OUT"
if [[ "$BIN_HIT" == 1 ]]; then
  pass "row 28 binary report has the measured shape"
else
  fail "row 28 binary report missing"
fi
RC="$(run_gate "$D")"
expect_rc "row 28 NUL in a watched flag file" 1 "$RC"
forbid_text "row 28 does not echo the diff line" "Binary files"

reset_seed
D="$(seed)"
MANIFEST_DUP_DROP="$(cat <<'EOF'
triggers:
  1:
    class: unactuated
  2:
    class: actuated
  3:
    class: unactuated
  4:
    class: actuated
  5:
    class: actuated
  6:
    class: unactuated
  7:
    class: unactuated
sites:
  - kind: path-token
    paths:
      - apps/web-platform/infra/cloud-init.yml
      - apps/web-platform/infra/ci-deploy.sh
    paths:
      - apps/web-platform/infra/cloud-init.yml
    groups:
      - token: --log-driver
        fires: [2, 4]
      - token: --log-opt
        fires: [2, 4]
      - token: --restart
        fires: [4]
  - kind: file
    paths:
      - apps/web-platform/infra/journald-soleur.conf
    fires: [5]
EOF
)"
write_manifest_text "$D" "$MANIFEST_DUP_DROP"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 29 duplicate key whose last list drops a path" 1 "$RC"

reset_seed
D="$(seed)"
MANIFEST_COMMENT="$(printf '%s\n' "$APPROVED_MANIFEST" | sed 's|^      - apps/web-platform/infra/ci-deploy.sh$|      # apps/web-platform/infra/ci-deploy.sh|')"
write_manifest_text "$D" "$MANIFEST_COMMENT"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 29 path named only in a comment" 1 "$RC"

reset_seed
D="$(seed)"
MANIFEST_DUP_OK="$(printf '%s\n' "$APPROVED_MANIFEST" | sed '0,/class: unactuated/s//class: unactuated\n    class: unactuated/')"
write_manifest_text "$D" "$MANIFEST_DUP_OK"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 29 duplicate key whose last value is still approved" 1 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-driver journald'
commit_all "$D" head
assert_fixture_dir "$SANDBOX"
mkdir -p "$SANDBOX/diffbin"
printf '%s\n' '#!/bin/sh' 'exit 2' > "$SANDBOX/diffbin/diff"
chmod +x "$SANDBOX/diffbin/diff"
EXTRA_PATH="$SANDBOX/diffbin"
RC="$(run_gate "$D")"
expect_rc "row 30 token diff exit 2" 2 "$RC"

reset_seed
SEED_POINTER=0
D="$(seed)"
RC="$(run_gate "$D")"
expect_rc "row 31 id census stays green without the pointer" 0 "$RC"
if grep -F -q -- "$POINTER" "$D/knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md"; then
  fail "row 31 fixture still has the pointer sentence"
else
  pass "row 31 deleting the pointer fails the sentence assertion"
fi
if grep -F -q -- "$POINTER" "$RUNBOOK"; then
  pass "real runbook has the pointer sentence"
else
  fail "real runbook is missing the pointer sentence"
fi
SECTION="$(awk 'BEGIN{p=0} /^### Re-verification triggers$/{p=1; next} /^### /{if(p){exit}} p{print}' "$RUNBOOK")"
MARKERS_OK=1
for n in 1 2 3 4 5 6 7; do
  if ! printf '%s\n' "$SECTION" | grep -q "^${n}\\."; then
    MARKERS_OK=0
  fi
done
if [[ "$MARKERS_OK" == 1 ]]; then
  pass "real runbook still has markers 1. through 7."
else
  fail "real runbook lost a numbered marker"
fi

reset_seed
D="$(seed)"
replace_with_symlink "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 32 symlink journald without id 5" 1 "$RC"

reset_seed
D="$(seed)"
MANIFEST_NARROW="$(printf '%s\n' "$APPROVED_MANIFEST" | sed '0,/fires: \[2, 4\]/s//fires: [4]/')"
write_manifest_text "$D" "$MANIFEST_NARROW"
add_line "$D" apps/web-platform/infra/cloud-init.yml 'docker run --log-driver journald'
write_register "$D" "${CELL_BASE} 2026-10-27 **(4)** noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 33 narrowed log-driver group" 1 "$RC"
want_text "row 33 shape" "shape"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/cloud-init.yml 'docker run --log-driver journald'
write_register "$D" "**(2)** **(4)** | **(f) Retention** | Reviewed **(1)** **(3)** **(5)** **(6)** **(7)** on 2020-01-01 with word alpha. 2026-10-28 noted"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 34 reorder marks an old fired id added" 0 "$RC"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_decoy_first_cell "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 35 earlier retention row is not the cell" 1 "$RC"
want_text "row 35 census" "id census rejected"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_fake_pa8_pair "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 36 earlier activity pair is not the cell" 1 "$RC"
want_text "row 36 census" "id census rejected"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
replace_register_with_symlink "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 37 symlink register blob is not the cell" 1 "$RC"
want_text "row 37 census" "id census rejected"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_prose_retention "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 38 prose retention mention is not the cell" 1 "$RC"
want_text "row 38 census" "id census rejected"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_nul_register "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 39 nul byte is not the cell" 1 "$RC"
want_text "row 39 census" "id census rejected"

reset_seed
D="$(seed)"
add_line "$D" apps/web-platform/infra/ci-deploy.sh 'docker run --log-opt max-size=1m'
write_multiline_symlink_register "$D"
commit_all "$D" head
RC="$(run_gate "$D")"
expect_rc "row 40 symlink mode is not the cell" 1 "$RC"
want_text "row 40 census" "id census rejected"

if grep -n 'docs/legal/' "$GATE" >/dev/null; then
  fail "script references docs/legal"
else
  pass "script does not reference docs/legal"
fi
if grep -F -q 'legal_resolve_base ""' "$GATE" && grep -F -q 'base_rc=0' "$GATE" && grep -F -q 'filter_rc=0' "$GATE" && grep -F -q 'diff_rc=0' "$GATE" && grep -F -q '${EVENT_NAME:-}' "$GATE" && grep -F -q '${MERGE_GROUP_BASE_SHA:-}' "$GATE" && grep -F -q -- '--no-ext-diff' "$GATE" && grep -F -q -- '--no-textconv' "$GATE" && grep -F -q -- '--no-renames' "$GATE"; then
  pass "script keeps the capture and diff pins"
else
  fail "script is missing a capture or diff pin"
fi
if [[ -f "$MANIFEST_FILE" ]] && cmp -s "$MANIFEST_FILE" <(printf '%s\n' "$APPROVED_MANIFEST"); then
  pass "committed manifest matches the approved shape"
else
  fail "committed manifest does not match the approved shape"
fi

printf 'passed: %s  failed: %s\n' "$passes" "$fails"
if (( fails > 0 )); then
  exit 1
fi
# The bound sits on the line directly above the comparison. The vacuity mutant
# slices only that comparison plus the contiguous assignments above it.
MIN_ASSERTIONS=68
if (( passes < MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: only %s assertion(s) ran, floor is %s\n' "$passes" "$MIN_ASSERTIONS" >&2
  exit 1
fi
exit 0

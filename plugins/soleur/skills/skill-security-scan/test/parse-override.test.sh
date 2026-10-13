#!/usr/bin/env bash
# parse-override.test.sh — required-field presence check in
# skill-security-scan/scripts/parse-override.sh (#10167).
#
# WHAT THIS GUARDS. Every required frontmatter key is gated on a presence
# check. Before #10167 that check was `grep -qE "^${f}:[[:space:]]"` — any
# whitespace (even alone) after the colon, same line — which false-rejects the
# schema-permitted
# block-mapping spelling of findings_json (`findings_json:` + indented keys;
# override-artifact-schema.json admits oneOf string|object, and
# override-mechanism.md documents the inline-object form for artifacts that
# must outlive the .scan-meta.json retention window). The rejected artifact
# surfaces as `missing fields: findings_json` → invalid_schema → the
# PreToolUse hook denies the Write and the pr-quality-guards CI job reddens.
#
# THE RULING (decision-challenges.md `#10167` ruling row, CTO). A required
# field counts PRESENT iff a `^f:` top-level key line exists AND either (a)
# non-whitespace non-null content follows the colon on the same line, or (b) a
# following INDENTED (whitespace-led) line carries content before the block
# ends — where "the block ends" is the next recognized key OR any other
# column-0 content line. Comments and blank lines are neutral — they neither
# satisfy presence nor close the block. Rejects: `f:` bare, `f:   `
# (whitespace-only — the dissent), `f: null`/`~` (YAML null), `f:value` (no
# separation space — YAML reads a plain scalar, not a mapping).
#
# THE FIXTURE. Each arm builds a scratch repo under $SUITE_TMP: `git init`, one
# empty base commit on ref `base`, then the synthesized override artifact(s)
# committed on top, so `git diff base...HEAD --diff-filter=A` enumerates them —
# the same door the PreToolUse hook and the two CI jobs walk through.
# parse-override.sh is run with cwd = the fixture repo (it diffs in $PWD and
# reads artifacts from the working tree). Fixtures are synthesized
# (cq-test-fixtures-synthesized-only); rule_pack_sha256 is seeded from the real
# manifest's sha256sum at runtime so the freshness arm never enters the
# assertion path.
#
# ANTI-VACUITY. Every reject arm pairs a compliant `ok-skill` artifact in the
# SAME fixture repo and asserts it lands in `matched`: a run that enumerates
# zero artifacts (a broken --diff-filter=A enumeration) fails the positive
# control instead of passing vacuously (Guard 1 mutation row 6). Every arm
# also asserts on the RESULT JSON naming the specific artifact path, never on
# the exit code alone.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE="$SCRIPT_DIR/../scripts/parse-override.sh"
MANIFEST="$SCRIPT_DIR/../references/rules/manifest.yaml"

# Session scratch root (#7004, ADR-250): adopt the owned `soleur-run.<pid>.*`
# root so a SIGKILL's residue is attributable to this suite — the same pattern
# this PR ships for cloud-init-inngest-bootstrap.test.sh (eat your own
# cooking). Load-bearing, not opportunistic: a missing lib means the path
# rotted (exit 2) — a silently-degrading [[ -f ]] guard is exactly how a
# wrong-depth path shipped dead in the first fix round. An environmental
# begin failure still degrades via `|| true` (never block the suite).
_SCRATCH_LIB="$SCRIPT_DIR/../../../../../scripts/lib/scratch-root.sh"
[[ -f "$_SCRATCH_LIB" ]] || { echo "FATAL: scratch-root.sh not found at $_SCRATCH_LIB" >&2; exit 2; }
# shellcheck source=../../../../../scripts/lib/scratch-root.sh
source "$_SCRATCH_LIB"
declare -F soleur_scratch_session_begin >/dev/null 2>&1 || { echo "FATAL: scratch-root.sh sourced but begin missing" >&2; exit 2; }
declare -F _soleur_scratch_cleanup >/dev/null 2>&1 || { echo "FATAL: scratch-root.sh sourced but cleanup missing" >&2; exit 2; }
# No arg: derived base normalizes a PrivateTmp-style TMPDIR up to /tmp where
# the reapers can enumerate (no private measured-base contract here).
soleur_scratch_session_begin || true

# Scratch root with its owning trap installed before ANY source or further
# allocation — the trap is this file's only cleanup owner (ADR-129). Under a
# bound session, SUITE_TMP already lands inside the owned root; the splice
# reclaims the (empty) root itself on clean exit.
SUITE_TMP="$(mktemp -d -t parse-override.XXXXXXXX)"
trap 'rm -rf "$SUITE_TMP"; _soleur_scratch_cleanup || true' EXIT

# The shared fixture git environment — sweeps inherited GIT_* location vars,
# pins a discovery ceiling, config hermeticity, and a synthesized identity.
# Sourced AFTER the EXIT trap above on purpose: the lib composes with a trap
# that already exists, and lint rule (c) wants ownership registered first.
# shellcheck source=../../../test/lib/git-fixture-env.sh
source "$SCRIPT_DIR/../../../test/lib/git-fixture-env.sh"

REPOS="$SUITE_TMP/repos"
mkdir -p "$REPOS"
git_fixture_env "$REPOS" || { printf '[FATAL] git_fixture_env refused %s\n' "$REPOS" >&2; exit 2; }

# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
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

command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v sha256sum >/dev/null 2>&1 || { echo "UNRESOLVED: sha256sum missing — this suite asserted nothing"; exit 3; }
[[ -f "$PARSE" ]] || { echo "FATAL: not found: $PARSE" >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "FATAL: not found: $MANIFEST" >&2; exit 2; }

# Seeded at runtime from the REAL manifest — the artifact's rule_pack_sha256
# then matches the freshness check byte-for-byte and stays out of every arm.
MANIFEST_SHA="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"
[[ -n "$MANIFEST_SHA" ]] || { echo "FATAL: could not sha256 $MANIFEST" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  [ok] $1"; }
bad() {
  FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2
  # Surface the gate's stderr on failure — run_parse redirects it to a file
  # the EXIT trap deletes, so a crash's diagnostics are otherwise lost.
  if [[ -s "$SUITE_TMP/parse.err" ]]; then tail -3 "$SUITE_TMP/parse.err" >&2; fi
}

OVERRIDE_DIR="knowledge-base/engineering/security/skill-overrides"

# mk_repo <dir> — a scratch repo whose `base` ref sits one commit behind HEAD.
mk_repo() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" commit -q --allow-empty -m "base"
  git -C "$d" branch -f base
}

# commit_all <dir> <msg> — stage and commit everything the arm wrote.
commit_all() {
  local d="$1" msg="$2"
  assert_fixture_dir "$d"
  git -C "$d" add -A
  git -C "$d" commit -qm "$msg"
}

# write_artifact <repo> <slug> <findings-lines> [verdict] [omit-fields]
#
# Writes $OVERRIDE_DIR/2026-10-13-<slug>.md with a compliant frontmatter.
# <findings-lines> is emitted VERBATIM between `source:` and `justification:` —
# empty omits the field entirely, a multi-line $'…\n…' string carries the
# block-mapping spelling, and a whitespace-led line nests the key under
# `source:`. [omit-fields] is a space-separated list of required names to drop
# (the missing-timestamp arm). The body stays free of any email-shaped token —
# the PII arm is not under test here and must not fire.
write_artifact() {
  local d="$1" slug="$2" findings="$3" verdict="${4:-HIGH-RISK}"
  local omit=" ${5:-} "
  assert_fixture_dir "$d"
  local dir="$d/$OVERRIDE_DIR"
  local f="$dir/2026-10-13-$slug.md"
  mkdir -p "$dir"
  assert_fixture_dir "$f"
  {
    printf -- '---\n'
    [[ "$omit" == *" skill "* ]]            || printf 'skill: %s\n' "$slug"
    [[ "$omit" == *" source "* ]]           || printf 'source: https://example.com/skills/%s\n' "$slug"
    [[ -z "$findings" ]]                    || printf '%s\n' "$findings"
    [[ "$omit" == *" justification "* ]]    || printf 'justification: operator accepted the residual risk after review\n'
    [[ "$omit" == *" approver "* ]]         || printf 'approver: fixture@example.com\n'
    [[ "$omit" == *" scanner_version "* ]]  || printf 'scanner_version: 0.1.0\n'
    [[ "$omit" == *" rule_pack_sha256 "* ]] || printf 'rule_pack_sha256: %s\n' "$MANIFEST_SHA"
    [[ "$omit" == *" verdict "* ]]          || printf 'verdict: %s\n' "$verdict"
    [[ "$omit" == *" timestamp "* ]]        || printf 'timestamp: 2026-10-13T00:00:00Z\n'
    printf -- '---\n\n'
    printf '# Override: %s\n\n## Findings\n%s/redacted.scan-meta.json\n\n## Justification\nReviewed and accepted.\n' "$slug" "$dir"
  } > "$f"
}

# run_parse <repo> — run the gate from inside the fixture repo; sets
# PARSE_OUT (stdout JSON) and PARSE_RC.
PARSE_OUT=""
PARSE_RC=0
run_parse() {
  local d="$1"
  assert_fixture_dir "$d"
  : > "$SUITE_TMP/parse.err"
  PARSE_OUT="$(cd "$d" && bash "$PARSE" --base base --head HEAD 2>"$SUITE_TMP/parse.err")"
  PARSE_RC=$?
}

# in_bucket <bucket> <relpath> — the result JSON names <relpath> under .<bucket>.
in_bucket() {
  printf '%s' "$PARSE_OUT" | jq -e --arg b "$1" --arg p "$2" \
    'any(.[$b][]; .path == $p)' >/dev/null
}

# reason_for <relpath> — the invalid_schema reason recorded for <relpath> ("" if none).
reason_for() {
  printf '%s' "$PARSE_OUT" | jq -r --arg p "$1" \
    'first(.invalid_schema[] | select(.path == $p) | .reason) // ""'
}

echo "=== parse-override.sh presence check (#10167) ==="

# --- Arm 0: instrument self-check --------------------------------------------
# Drive both counters once each (output suppressed — the assertion is the
# counter delta, not the line). A suite whose ok/bad never move reports a
# green vacuously; the exit gate below also pins an arm-count floor.
_self_pass=$PASS; _self_fail=$FAIL
ok "self-check" >/dev/null
bad "self-check" 2>/dev/null
if [[ $PASS -eq $((_self_pass + 1)) && $FAIL -eq $((_self_fail + 1)) ]]; then
  PASS=$_self_pass; FAIL=$_self_fail
else
  echo "FATAL: ok/bad counters did not move — instrument dead" >&2; exit 2
fi

# --- Arm 1 (MUST-PASS, non-canonical): block-mapping findings_json ACCEPT -----
# The defect itself: schema-permitted spelling the old grep rejected.
R="$REPOS/arm-block-map"
rel="$OVERRIDE_DIR/2026-10-13-demo-skill.md"
mk_repo "$R"
write_artifact "$R" "demo-skill" \
  $'findings_json:\n  code-execution: {"verdict": "HIGH-RISK", "count": 1}\n  filesystem-boundary: {"verdict": "REVIEW", "count": 0}'
commit_all "$R" "add override artifact"
run_parse "$R"
if [[ "$PARSE_RC" -eq 0 ]] && in_bucket matched "$rel" && ! in_bucket invalid_schema "$rel"; then
  ok "block-mapping findings_json validates (matched, rc=0)"
else
  bad "block-mapping findings_json rejected — the #10167 defect (rc=$PARSE_RC, out=$PARSE_OUT)"
fi

# --- Arm 2: flow-style findings_json ACCEPT -----------------------------------
# Same-line `{…}` — present before and after the fix; regression cover.
R="$REPOS/arm-flow"
rel="$OVERRIDE_DIR/2026-10-13-flow-skill.md"
mk_repo "$R"
write_artifact "$R" "flow-skill" 'findings_json: {"code-execution": {"verdict": "HIGH-RISK", "count": 1}}'
commit_all "$R" "add override artifact"
run_parse "$R"
if [[ "$PARSE_RC" -eq 0 ]] && in_bucket matched "$rel" && ! in_bucket invalid_schema "$rel"; then
  ok "flow-style findings_json validates (matched, rc=0)"
else
  bad "flow-style findings_json regressed (rc=$PARSE_RC, out=$PARSE_OUT)"
fi

# --- Arm 3: absent findings_json REJECT (+ positive control) ------------------
# `findings` arg empty → the field never reaches the frontmatter.
R="$REPOS/arm-absent"
rel="$OVERRIDE_DIR/2026-10-13-absent-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "absent-skill" ""
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "absent findings_json still rejects (missing fields; ok-skill matched)"
else
  bad "absent findings_json not rejected as missing fields (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4: declared-but-empty findings_json REJECT ---------------------------
# `findings_json:` then the NEXT top-level key — the presence check must not
# degenerate into key-line existence (Guard 1 mutation row 3).
R="$REPOS/arm-empty"
rel="$OVERRIDE_DIR/2026-10-13-empty-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "empty-skill" 'findings_json:'
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "declared-but-empty findings_json still rejects (missing fields)"
else
  bad "declared-but-empty findings_json not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4b (CTO dissent): whitespace-only findings_json REJECT ---------------
# `f:   ` — same key line, whitespace-only value. The dissent's named case.
R="$REPOS/arm-ws-empty"
rel="$OVERRIDE_DIR/2026-10-13-ws-empty-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "ws-empty-skill" 'findings_json:   '
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "whitespace-only findings_json rejects (CTO dissent: f:<ws-only> is empty)"
else
  bad "whitespace-only findings_json not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4c (comments are neutral): comment-only block REJECT -----------------
# `findings_json:` followed by an indented COMMENT then the next key. A comment
# is not content — the block arm must not count it (ruling: comments neutral).
R="$REPOS/arm-comment-only"
rel="$OVERRIDE_DIR/2026-10-13-comment-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "comment-skill" $'findings_json:\n  # redacted copy lives in .scan-meta.json'
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "comment-only findings_json block rejects (comments are not content)"
else
  bad "comment-only findings_json block not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 5: nested-under-another-key findings_json REJECT ---------------------
# `  findings_json:` whitespace-led under `source:` — the `^` anchor must keep
# a nested same-named key from false-presenting (the plan's Sharp Edge).
R="$REPOS/arm-nested"
rel="$OVERRIDE_DIR/2026-10-13-nested-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "nested-skill" '  findings_json: {"code-execution": {"verdict": "REVIEW", "count": 1}}'
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "nested findings_json rejects (^-anchored; nested keys do not count)"
else
  bad "nested findings_json not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 6: second artifact missing timestamp REJECT --------------------------
# The check must not stop at the first member (Guard 1 mutation row 5): a
# compliant ok-skill AND a bad-skill missing `timestamp` in one diff.
R="$REPOS/arm-second"
rel="$OVERRIDE_DIR/2026-10-13-bad-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "bad-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 1}}' "REVIEW" "timestamp"
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"timestamp"* ]]; then
  ok "a second artifact missing timestamp rejects (enumeration does not stop at member one)"
else
  bad "missing-timestamp second artifact not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 7: verdict: LOW-RISK REJECT (downstream check intact) ----------------
# An otherwise-valid artifact with a forbidden verdict — the presence fix must
# not weaken the downstream value checks (Guard 1 mutation row 7).
R="$REPOS/arm-lowrisk"
rel="$OVERRIDE_DIR/2026-10-13-lowrisk-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "lowrisk-skill" 'findings_json: {"code-execution": {"verdict": "LOW-RISK", "count": 0}}' "LOW-RISK"
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"verdict"* && "$reason" == *"LOW-RISK"* ]]; then
  ok "verdict: LOW-RISK rejects (downstream value check intact)"
else
  bad "verdict: LOW-RISK not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4d: stale-cur — indented stray under an UNRECOGNIZED col-0 key -------
# `findings_json:` bare, then `other :` (space-before-colon — legal YAML, not
# recognized by this gate's key regex), then an indented line. The block ends
# at ANY col-0 content line, so `  k: v` must NOT credit findings_json. A
# predicate that only resets `cur` on recognized key lines back-fills the
# pending field — the security-sentinel/structural-enum review finding.
R="$REPOS/arm-stale-cur"
rel="$OVERRIDE_DIR/2026-10-13-stalecur-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "stalecur-skill" $'findings_json:\nother :\n  k: v'
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "indented stray under an unrecognized col-0 key does not back-fill (missing fields)"
else
  bad "stale-cur back-fill accepted (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4e: no-separation-space key REJECT ------------------------------------
# `verdict:HIGH-RISK` — YAML requires `:` + space/EOL for a mapping entry;
# without it the whole line is a plain scalar and the field is absent. The
# pre-#10167 grep rejected this spelling; an `^f:`-alone predicate accepts it,
# and the file's downstream extractors read `f:v` too — an end-to-end bypass
# (review P2). write_artifact always emits `verdict: <v>`, so this arm writes
# the artifact directly.
R="$REPOS/arm-nospace"
rel="$OVERRIDE_DIR/2026-10-13-nospace-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
mkdir -p "$R/$OVERRIDE_DIR"
{
  printf -- '---\n'
  printf 'skill: nospace-skill\n'
  printf 'source: https://example.com/skills/nospace-skill\n'
  printf 'findings_json: {"code-execution": {"verdict": "HIGH-RISK", "count": 1}}\n'
  printf 'justification: operator accepted the residual risk after review\n'
  printf 'approver: fixture@example.com\n'
  printf 'scanner_version: 0.1.0\n'
  printf 'rule_pack_sha256: %s\n' "$MANIFEST_SHA"
  printf 'verdict:HIGH-RISK\n'
  printf 'timestamp: 2026-10-13T00:00:00Z\n'
  printf -- '---\n\n'
  printf '# Override: nospace-skill\n\n## Findings\n%s/redacted.scan-meta.json\n\n## Justification\nReviewed and accepted.\n' "$OVERRIDE_DIR"
} > "$R/$rel"
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"verdict"* ]]; then
  ok "no-separation-space verdict:HIGH-RISK rejects (a scalar, not a mapping)"
else
  bad "no-separation-space key accepted — end-to-end bypass (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4f: findings_json: null REJECT ----------------------------------------
# A YAML null is not "present" for a schema-required field — `f: null`/`f: ~`
# must report missing, not satisfy presence.
R="$REPOS/arm-null"
rel="$OVERRIDE_DIR/2026-10-13-null-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "null-skill" 'findings_json: null'
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "findings_json: null rejects (YAML null is absent for a required field)"
else
  bad "findings_json: null not rejected (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 4g: duplicate key — LAST occurrence wins -------------------------------
# `findings_json: {}` then a bare `findings_json:` — YAML last-wins makes the
# field null; a first-seen latch would keep it present (review P3).
R="$REPOS/arm-dup"
rel="$OVERRIDE_DIR/2026-10-13-dup-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
write_artifact "$R" "dup-skill" $'findings_json: {}\nfindings_json:'
commit_all "$R" "add override artifacts"
run_parse "$R"
reason="$(reason_for "$rel")"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket invalid_schema "$rel" && in_bucket matched "$rel_ok" \
   && [[ "$reason" == *"missing fields"* && "$reason" == *"findings_json"* ]]; then
  ok "duplicate findings_json resolves last-wins (trailing bare key is missing)"
else
  bad "duplicate key latched first-wins (rc=$PARSE_RC, reason='$reason', out=$PARSE_OUT)"
fi

# --- Arm 8: empty-diff baseline -------------------------------------------------
# The modal CI path: a diff containing no override artifacts at all must
# return rc 0 with all three buckets empty (pr-quality-guards.yml consumes
# this shape directly).
R="$REPOS/arm-empty-diff"
mk_repo "$R"
git -C "$R" commit -q --allow-empty -m "no artifacts"
run_parse "$R"
if [[ "$PARSE_RC" -eq 0 ]] \
   && [[ "$(printf '%s' "$PARSE_OUT" | jq '[.matched[], .invalid_schema[], .stale_findings[]] | length')" == "0" ]]; then
  ok "empty-diff baseline: rc=0, all buckets empty"
else
  bad "empty-diff baseline broken (rc=$PARSE_RC, out=$PARSE_OUT)"
fi

# --- Arm 9: stale rule_pack_sha256 → stale_findings bucket ---------------------
# The third bucket, unexercised until now: a wrong-but-well-formed sha must
# land in stale_findings and fail closed (rc=1) while ok-skill still matches.
R="$REPOS/arm-stale-sha"
rel="$OVERRIDE_DIR/2026-10-13-stale-skill.md"
rel_ok="$OVERRIDE_DIR/2026-10-13-ok-skill.md"
mk_repo "$R"
write_artifact "$R" "ok-skill" 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 2}}'
# write_artifact seeds MANIFEST_SHA verbatim; emit this artifact by hand with a
# bogus sha (64-hex, well-formed, deliberately not the live manifest's).
mkdir -p "$R/$OVERRIDE_DIR"
{
  printf -- '---\n'
  printf 'skill: stale-skill\n'
  printf 'source: https://example.com/skills/stale-skill\n'
  printf 'findings_json: {"code-execution": {"verdict": "REVIEW", "count": 0}}\n'
  printf 'justification: operator accepted the residual risk after review\n'
  printf 'approver: fixture@example.com\n'
  printf 'scanner_version: 0.1.0\n'
  printf 'rule_pack_sha256: %064d\n' 0
  printf 'verdict: REVIEW\n'
  printf 'timestamp: 2026-10-13T00:00:00Z\n'
  printf -- '---\n\n'
  printf '# Override: stale-skill\n\n## Findings\n%s/redacted.scan-meta.json\n\n## Justification\nReviewed and accepted.\n' "$OVERRIDE_DIR"
} > "$R/$rel"
commit_all "$R" "add override artifacts"
run_parse "$R"
if [[ "$PARSE_RC" -ne 0 ]] && in_bucket stale_findings "$rel" && in_bucket matched "$rel_ok" \
   && ! in_bucket matched "$rel"; then
  ok "stale rule_pack_sha256 lands in stale_findings and fails closed"
else
  bad "stale sha not bucketed (rc=$PARSE_RC, out=$PARSE_OUT)"
fi

echo "=== parse-override: $PASS passed, $FAIL failed ==="
# Real failures first — report them as failures, not as vacuity.
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
# Assertion floor: a run that executed fewer than every arm reads RED, never
# vacuously green — the `(( PASS < N ))` counter-comparison shape is the one
# guard-vacuity-floor.test.sh derives floors from.
if (( PASS < 15 )); then
  echo "VACUITY: only $PASS of 15 arms passed — refusing green" >&2
  exit 1
fi
echo "OK: $PASS assertions"
exit 0

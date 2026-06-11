#!/usr/bin/env bash
# Tests for kb-domain-allowlist-guard.sh.
# Run via:  bash .claude/hooks/kb-domain-allowlist-guard.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/kb-domain-allowlist-guard.sh"

[[ -x "$HOOK" ]] || { echo "ERROR: $HOOK not executable" >&2; exit 1; }

# Point the on-disk existence check at a synthetic kb root so the test does not
# depend on the operator's real working tree. Absolute paths in payloads carry
# their own prefix, so the guard resolves existence against the prefix directly.
TMP_KB="$(mktemp -d)"
mkdir -p "$TMP_KB/knowledge-base/engineering/security/skill-overrides"
mkdir -p "$TMP_KB/knowledge-base/project/plans"
export CLAUDE_PROJECT_DIR="$TMP_KB"
trap 'rm -rf "$TMP_KB"' EXIT

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

invoke_write() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK"; }
invoke_bash()  { printf '%s' "$1" | jq -Rs '{tool_input: {command: .}}' | bash "$HOOK"; }
# Explicit-tool_name variants: the invoke_bash/invoke_write helpers above omit
# tool_name, exercising the fail-open-by-shape discriminator path. These inject
# tool_name so at least one case per class exercises the explicit-tool_name path.
invoke_bash_named()  { printf '%s' "$1" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$HOOK"; }
invoke_write_named() { jq -nc --arg f "$1" '{tool_name: "Write", tool_input: {file_path: $f}}' | bash "$HOOK"; }
decision_of()  { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }

# T1 — NEW unsanctioned top-level dir (relative path) → ask.
echo "T1: new unsanctioned top-level dir → ask"
out=$(invoke_write "knowledge-base/observability/foo.md")
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on knowledge-base/observability/" || fail "out=$out"

# T2 — Re-introducing security/ (the exact Part A anomaly) → ask (regression guard).
echo "T2: re-adding security/ → ask"
out=$(invoke_write "knowledge-base/security/skill-overrides/x.md")
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on re-added security/" || fail "out=$out"

# T3 — Sanctioned domain (engineering) short-circuit → pass-through, even for a
# nested security/ subpath. (This passes via the SANCTIONED_DIRS check, NOT the
# on-disk-existence branch — that branch is covered by T10.)
echo "T3: write into sanctioned engineering domain (nested security/) → pass-through"
out=$(invoke_write "$TMP_KB/knowledge-base/engineering/security/skill-overrides/2026-06-02-foo.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision (sanctioned engineering domain)" || fail "out=$out"

# T4 — Sanctioned top-level file → pass-through.
echo "T4: knowledge-base/INDEX.md → pass-through"
out=$(invoke_write "knowledge-base/INDEX.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision on sanctioned file" || fail "out=$out"

# T5 — Write into an existing sanctioned domain (project/) → pass-through.
echo "T5: write into project/plans → pass-through"
out=$(invoke_write "knowledge-base/project/plans/2026-06-02-some-plan.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision on sanctioned project domain" || fail "out=$out"

# T6 — Malformed JSON → pass-through (fail-open).
echo "T6: malformed JSON → pass-through"
out=$(printf 'not-json' | bash "$HOOK" 2>/dev/null || true)
[[ -z "$(decision_of "$out" 2>/dev/null || echo "")" ]] && pass "fail-open on malformed JSON" || fail "out=$out"

# T7 — Non-KB path → pass-through.
echo "T7: non-KB path → pass-through"
out=$(invoke_write "apps/web-platform/components/kb/file-tree.tsx")
[[ -z "$(decision_of "$out")" ]] && pass "no decision on non-KB path" || fail "out=$out"

# T8 — Bash mkdir of a new unsanctioned top-level dir → ask.
echo "T8: Bash 'mkdir -p knowledge-base/observability' → ask"
out=$(invoke_bash 'mkdir -p knowledge-base/observability')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on Bash mkdir new domain" || fail "out=$out"

# T9 — Empty tool_input → pass-through.
echo "T9: empty tool_input → pass-through"
out=$(printf '{"tool_input":{}}' | bash "$HOOK")
[[ -z "$(decision_of "$out")" ]] && pass "no-op on empty tool_input" || fail "out=$out"

# T10 — Unsanctioned segment that ALREADY EXISTS on disk → pass-through.
# Exercises the on-disk-existence branch (guard.sh) that T1-T9 never reach:
# a previously-acknowledged (but not-yet-allowlisted) domain must stop nagging.
# `observability` is NOT in SANCTIONED_DIRS, so the only thing that can produce a
# pass here is the existence check resolving against CLAUDE_PROJECT_DIR.
echo "T10: unsanctioned-but-on-disk segment → pass-through (existence branch)"
mkdir -p "$TMP_KB/knowledge-base/observability"
out=$(invoke_write "knowledge-base/observability/foo.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision (segment exists on disk)" || fail "out=$out"

# T11 — Bash command whose COMMENT mentions knowledge-base/*.md but whose real
# writes are under sanctioned project/ → pass-through (glob-metachar skip). This is
# the exact reported false-positive: the first-match scan lands on the comment
# (yielding SEGMENT=*.md), not the git-add write (project/).
echo "T11: comment with knowledge-base/*.md + real project/ write → pass-through"
out=$(invoke_bash '# verify no broken knowledge-base/*.md citations in the plan
grep -oE "knowledge-base/[A-Za-z0-9/_.-]+\.md" "$PLAN"
git add knowledge-base/project/plans/ knowledge-base/project/specs/x/tasks.md')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (glob in comment, real write sanctioned)" || fail "out=$out"

# T12 — Bash command containing a grep/regex pattern over knowledge-base paths →
# pass-through (first match yields a bracket-class token [A-Za-z0-9, not a real segment).
echo "T12: grep pattern knowledge-base/[A-Za-z0-9/_.-]+ → pass-through"
out=$(invoke_bash "grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\\.md' \"\$PLAN\"")
[[ -z "$(decision_of "$out")" ]] && pass "no decision (grep regex pattern, not a write)" || fail "out=$out"

# --- Read-vs-write distinction for the Bash class (write-target gate) ----------
# T13-T15 are the reported false-positive: read-only Bash commands that merely
# MENTION a kb path (via `git show <ref>:path`, `grep`) must pass cleanly. They
# carry no write verb and no kb-targeted redirect, so the write-target gate
# short-circuits them before the advisory `ask`.

# T13 — the exact reported repro: a multi-statement read-only command containing
# `git show main:knowledge-base/.gitkeep >/dev/null 2>&1`. The `>/dev/null` must
# NOT be read as a kb-targeted redirect. Also exercises the `[^|;&]*` segment
# boundary (multiple `;`/`&&`/`||`-joined statements + a pipe to `head`).
echo "T13: exact repro (read-only multi-statement) → pass-through"
out=$(invoke_bash 'git branch --show-current; echo "---kb---"; git show main:knowledge-base/.gitkeep >/dev/null 2>&1 && echo "kb-tracked" || git ls-tree main knowledge-base >/dev/null 2>&1 && echo "kb-exists-on-main" || echo "no-kb"; echo "---5085---"; gh issue view 5085 --json state,title 2>/dev/null | head; echo "---ledger---"; git ls-tree -r --name-only main | grep -iE "expense|ledger|cost" | head -30')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (read-only repro command)" || fail "out=$out"

# T14 — standalone `git show <ref>:knowledge-base/...` read.
echo "T14: 'git show main:knowledge-base/.gitkeep' → pass-through"
out=$(invoke_bash 'git show main:knowledge-base/.gitkeep')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (git show read reference)" || fail "out=$out"

# T15 — `grep -r knowledge-base/foo .` read (no write verb, no kb redirect).
echo "T15: 'grep -r knowledge-base/foo .' → pass-through"
out=$(invoke_bash 'grep -r knowledge-base/foo .')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (grep read reference)" || fail "out=$out"

# T15b — repro command via explicit tool_name:"Bash" (exercises the tool_name path,
# not just the fail-open-by-shape path that invoke_bash uses).
echo "T15b: repro command via invoke_bash_named (explicit tool_name) → pass-through"
out=$(invoke_bash_named 'git show main:knowledge-base/.gitkeep >/dev/null 2>&1')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (explicit tool_name read)" || fail "out=$out"

# T16 — genuine new-domain write via `mkdir` → still ask (regression guard: the
# gate must NOT swallow real writes).
echo "T16: 'mkdir knowledge-base/newdomain' → ask (regression guard)"
out=$(invoke_bash 'mkdir knowledge-base/newdomain')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on Bash mkdir new domain" || fail "out=$out"

# T17 — genuine new-domain write via redirect → still ask.
echo "T17: 'echo x > knowledge-base/newdomain/file.md' → ask (regression guard)"
out=$(invoke_bash 'echo x > knowledge-base/newdomain/file.md')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on Bash redirect into new domain" || fail "out=$out"

# T18 — genuine new-domain write via `git add` → still ask.
echo "T18: 'git add knowledge-base/newdomain/file.md' → ask (regression guard)"
out=$(invoke_bash 'git add knowledge-base/newdomain/file.md')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on Bash git add new domain" || fail "out=$out"

# T18b — genuine new-domain write via `tee` → still ask. `tee` is the only verb
# in KB_WRITE_VERB_RE not otherwise exercised (T16=mkdir, T17=redirect,
# T18=git add); this locks it so a future verb-regex narrowing cannot drop `tee`
# silently behind a green suite.
echo "T18b: 'echo x | tee knowledge-base/newdomain/file.md' → ask (regression guard)"
out=$(invoke_bash 'echo x | tee knowledge-base/newdomain/file.md')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on Bash tee into new domain" || fail "out=$out"

# T19 — write into a SANCTIONED domain via mkdir → pass-through.
echo "T19: 'mkdir knowledge-base/engineering/x' → pass-through (sanctioned)"
out=$(invoke_bash 'mkdir knowledge-base/engineering/x')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (sanctioned domain write)" || fail "out=$out"

# T20 — file-tool write to a new unsanctioned domain → still ask (unaffected by
# the Bash-only gate; file_path is unambiguously a write target).
echo "T20: file-tool write to knowledge-base/newdomain/x.md → ask (unaffected)"
out=$(invoke_write "knowledge-base/newdomain/x.md")
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on file-tool write new domain" || fail "out=$out"

# T20b — same, with explicit tool_name:"Write".
echo "T20b: file-tool write via invoke_write_named → ask (unaffected, explicit tool_name)"
out=$(invoke_write_named "knowledge-base/newdomain/x.md")
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on explicit-tool_name file write" || fail "out=$out"

# T21 — documented-acceptable string-literal false positive (Sharp-Edge Finding 1).
# The redirect regex is not quote-aware: `> knowledge-base/y` inside a quoted
# argument matches even though the real redirect target is /tmp/notes.txt. This
# locks the behavior so a future regex edit cannot silently "fix" it and regress
# the genuine `echo x > knowledge-base/...` write detection (T17).
echo "T21: quoted '> knowledge-base/' inside an arg → ask (documented-acceptable)"
out=$(invoke_bash 'echo "cp x > knowledge-base/y is the move cmd" > /tmp/notes.txt')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask (known-acceptable quoted-string match)" || fail "out=$out"

# T22 — read-only `sed` (no `-i`) over a sanctioned kb path → pass-through. The
# verb regex anchors on `sed[[:space:]]+-i`, so a read-only sed is not a write.
echo "T22: read-only 'sed' (no -i) over kb path → pass-through"
out=$(invoke_bash 'sed "s/a/b/" knowledge-base/engineering/x.md')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (read-only sed)" || fail "out=$out"

# T23 — `mv` with kb as the SOURCE (sanctioned segment) → pass-through. The verb
# regex matches, but SEGMENT=project is sanctioned so the sanctioned-dir check
# passes it. Locks kb-as-source behavior against a future verb-regex narrowing.
echo "T23: 'mv knowledge-base/project/foo.md /tmp/' (kb source, sanctioned) → pass-through"
out=$(invoke_bash 'mv knowledge-base/project/foo.md /tmp/')
[[ -z "$(decision_of "$out")" ]] && pass "no decision (kb-as-source, sanctioned segment)" || fail "out=$out"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

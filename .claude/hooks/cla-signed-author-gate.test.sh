#!/usr/bin/env bash
# Fixture-based tests for cla-signed-author-gate.sh. Asserts the hook blocks
# `gh pr ready`/`merge` when a branch commit is authored/committed by the
# non-CLA-signed identity, and fail-opens on every infra/edge case.
# Isolation pattern mirrors ship-unpushed-commits-gate.test.sh.

set -euo pipefail
SUITE_TMP=$(mktemp -d)
[[ "$SUITE_TMP" == /* ]] || { echo "FATAL: SUITE_TMP is not absolute: $SUITE_TMP" >&2; exit 2; }
trap 'rm -rf "$SUITE_TMP"' EXIT

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects, beyond empty: bare `/` AND its aliases `//` and `/.` (a `/*` arm accepts all three, and
# `rm -rf "/"/*` is the worst outcome in this corpus — a one-character bypass of a stated
# rejection); any path containing `..`, which can resolve back inside the real repo; and
# /proc, /sys, /dev, because `/proc/self/cwd` is absolute, passes every other arm, and resolves
# to precisely "whatever repository the caller happens to be standing in".
#
# Still no `realpath`: it breaks on a symlinked /tmp, which this corpus uses. So a symlink to
# $HOME is ACCEPTED — stated here rather than left implied, because the arms above make this
# look like a containment check and it is not.
#
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/cla-signed-author-gate.sh"
UNSIGNED="noreply@anthropic.com"

PASS=0; FAIL=0; TOTAL=0
command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }

init_git_repo() {
  local dir="$1"
  assert_fixture_dir "$dir"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email test@test.local
  git -C "$dir" config user.name "Test User"
  git -C "$dir" config commit.gpgsign false
}

# Build a work-tree on feature branch off origin/main. $3 = author email for the
# feature commit (signed test@test.local or the unsigned id). Echoes "$work $inc".
make_branch() {
  local tmp="$1" branch="$2" author_email="$3"
  local work="$tmp/work" origin="$tmp/origin.git" inc="$tmp/inc"
  assert_fixture_dir "$tmp"
  mkdir -p "$work" "$inc"
  git init -q --bare "$origin"
  init_git_repo "$work"
  echo base > "$work/file.txt"; git -C "$work" add file.txt; git -C "$work" commit -q -m init
  git -C "$work" remote add origin "$origin"; git -C "$work" push -q origin main
  git -C "$work" checkout -q -b "$branch"
  echo feat > "$work/feat.txt"; git -C "$work" add feat.txt
  GIT_AUTHOR_NAME="A" GIT_AUTHOR_EMAIL="$author_email" \
    git -C "$work" commit -q -m "feature work"
  echo "$work $inc"
}

make_payload() { jq -nc --arg c "$1" --arg x "$2" '{tool_input:{command:$x},cwd:$c}'; }
run_hook() { printf '%s' "$2" | INCIDENTS_REPO_ROOT="$1" "$HOOK" 2>/dev/null; }
# Masks global/system git config so `git config --get user.email` inside the
# hook reads ONLY the fixture repo's local config — required for the
# unset-config arms, which otherwise inherit the developer's global identity.
run_hook_noglobal() { printf '%s' "$2" | GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null INCIDENTS_REPO_ROOT="$1" "$HOOK" 2>/dev/null; }

# make_repo <tmp> — bare origin + work repo on `main` with a base commit
# pushed. Echoes "<work> <inc>". Roster artifacts and branch commits are
# provisioned per-arm by the helpers below so each fixture carries only what
# it exercises.
make_repo() {
  local tmp="$1"
  local work="$tmp/work" origin="$tmp/origin.git" inc="$tmp/inc"
  assert_fixture_dir "$tmp"
  mkdir -p "$work" "$inc"
  git init -q --bare "$origin"
  init_git_repo "$work"
  echo base > "$work/file.txt"; git -C "$work" add file.txt; git -C "$work" commit -q -m init
  git -C "$work" remote add origin "$origin"; git -C "$work" push -q origin main
  echo "$work $inc"
}

# push_cla_yml <work> — commit a fixture .github/workflows/cla.yml ON main and
# push, so `git show origin/main:.github/workflows/cla.yml` resolves. The
# allowlist carries soleur-ai[bot] (and NOT Elvalio — that login resolves via
# signatures only). The word "allowlist" also appears in the comment block to
# pin the anchored-parse edge case (`^[[:space:]]+allowlist:`).
push_cla_yml() {
  local work="$1"
  assert_fixture_dir "$work"
  mkdir -p "$work/.github/workflows"
  cat > "$work/.github/workflows/cla.yml" <<'EOF'
name: cla
on: [pull_request_target]
jobs:
  cla:
    steps:
      # The allowlist below is login-keyed; the word allowlist also appears
      # in this comment block — a non-anchored parse would read this line.
      - uses: contributor-assistant/github-action@v2
        with:
          allowlist: "dependabot[bot],github-actions[bot],deruelle,soleur-ai[bot],soleur-infra[bot]"
EOF
  git -C "$work" add .github/workflows/cla.yml
  setup_commit "$work" "add cla.yml"
  git -C "$work" push -q origin main
}

# push_cla_signatures <work> — push a cla-signatures branch carrying
# signatures/cla.json so `git show origin/cla-signatures:signatures/cla.json`
# resolves (signedContributors: Elvalio + deruelle).
push_cla_signatures() {
  local work="$1"
  assert_fixture_dir "$work"
  git -C "$work" checkout -q -b cla-signatures
  mkdir -p "$work/signatures"
  cat > "$work/signatures/cla.json" <<'EOF'
{"signedContributors":[{"name":"Elvalio","id":92384917},{"name":"deruelle","id":54279}]}
EOF
  git -C "$work" add signatures/cla.json
  setup_commit "$work" "signatures"
  git -C "$work" push -q origin cla-signatures
  git -C "$work" checkout -q main
}

# commit_branch <work> <branch> <spec>... — cut <branch> off main and apply
# one commit per spec "author_email[,committer_email]". An omitted committer
# part leaves git's configured identity as committer.
commit_branch() {
  local work="$1" branch="$2" spec ae ce
  assert_fixture_dir "$work"
  shift 2
  git -C "$work" checkout -q -b "$branch"
  for spec in "$@"; do
    ae="${spec%%,*}"
    ce="${spec#*,}"; [[ "$ce" == "$spec" ]] && ce=""
    echo "$ae" >> "$work/feat.txt"; git -C "$work" add feat.txt
    # NB: no quotes inside ${ce:+...} — they would survive literally in the
    # env value (emails carry no spaces, so bare expansion is safe here).
    env GIT_AUTHOR_NAME="A" GIT_AUTHOR_EMAIL="$ae" \
      ${ce:+GIT_COMMITTER_NAME=C GIT_COMMITTER_EMAIL=$ce} \
      git -C "$work" commit -q -m "work by $ae"
  done
}

# setup_commit <work> <msg> — fixture-setup commit with an explicit identity via
# env, so it works on runners with no global git identity. Repo config is left
# untouched: T15/T16 unset user.email on purpose so the hook under test sees none.
setup_commit() {
  local work="$1" msg="$2"
  assert_fixture_dir "$work"
  env GIT_AUTHOR_NAME="S" GIT_AUTHOR_EMAIL="setup@test.local" \
    GIT_COMMITTER_NAME="S" GIT_COMMITTER_EMAIL="setup@test.local" \
    git -C "$work" commit -q -m "$msg"
}

# $5 (optional) = a literal substring the deny payload MUST name — used by the
# subset-check arms to prove the deny identifies the offending email, not just
# that some deny fired.
assert_deny() {
  local name="$1" inc="$2" out="$3" rc="$4" expect="${5-}"
  local decision jsonl rule named=0
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$inc/.claude/.rule-incidents.jsonl"
  rule=$([[ -f "$jsonl" ]] && jq -r '.rule_id' < "$jsonl" | head -1 || echo "")
  if [[ -n "$expect" ]] && ! grep -qF -- "$expect" <<<"$out"; then named=1; fi
  if [[ "$rc" -eq 0 && "$decision" == "deny" && "$rule" == "wg-cla-signed-author-before-merge" && "$named" -eq 0 ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (rc=$rc decision=$decision rule=$rule named=$named)"; FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
}

assert_pass() {
  local name="$1" inc="$2" out="$3" rc="$4"
  local decision jsonl denied=0
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$inc/.claude/.rule-incidents.jsonl"
  [[ -f "$jsonl" ]] && denied=$(grep -c '"event_type":"deny"' "$jsonl" 2>/dev/null || echo 0)
  if [[ "$rc" -eq 0 && "$decision" != "deny" && "$denied" -eq 0 ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (rc=$rc decision=$decision denied=$denied)"; FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
}

# T1: unsigned-author commit + gh pr merge → DENY
t1() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_branch "$t" feat-x "$UNSIGNED")
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 123 --squash --auto')") || rc=$?
  assert_deny "T1 unsigned author + gh pr merge denies" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T1b: rtk-prefixed merge reaches the gate identically (#10248)
t1b() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_branch "$t" feat-rtk "$UNSIGNED")
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'rtk gh pr merge 123 --squash --auto')") || rc=$?
  assert_deny "T1b unsigned author + rtk gh pr merge denies (#10248)" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T2: all-signed commits + gh pr merge → PASS
t2() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_branch "$t" feat-y test@test.local)
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 123 --squash --auto')") || rc=$?
  assert_pass "T2 signed authors pass" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T3: unsigned author + gh pr ready → DENY (gate also covers ready)
t3() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_branch "$t" feat-z "$UNSIGNED")
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready 123')") || rc=$?
  assert_deny "T3 unsigned author + gh pr ready denies" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T4: unrelated command → no fire (PASS)
t4() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_branch "$t" feat-w "$UNSIGNED")
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'git status')") || rc=$?
  assert_pass "T4 non-gh-pr command does not fire" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T5: on main → fail-open PASS even with command match
t5() { local t; t=$(mktemp -d -p "$SUITE_TMP"); local work="$t/work" inc="$t/inc"; mkdir -p "$work" "$inc"
  git init -q --bare "$t/o.git"; init_git_repo "$work"
  echo b > "$work/f"; git -C "$work" add f
  GIT_AUTHOR_EMAIL="$UNSIGNED" git -C "$work" commit -q -m c
  git -C "$work" remote add origin "$t/o.git"; git -C "$work" push -q origin main
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 1 --squash')") || rc=$?
  assert_pass "T5 main branch fail-opens" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T6 (#5192): a `git commit` whose MESSAGE documents `gh pr merge` must NOT
# fire — even with an unsigned-author commit on the branch (which would deny if
# the trigger grep ran on the raw command). The strip blanks the -m body first.
t6() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_branch "$t" feat-fp "$UNSIGNED")
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" $'git add . && git commit -m "ship note\ngh pr merge must not be hand-rolled\n"')") || rc=$?
  assert_pass "T6 commit-body gh pr merge does not fire (#5192)" "$inc" "$out" "$rc"; rm -rf "$t"; }

# ==========================================================================
# Stage-2 subset-check arms (#12027, #7218). Fixture emails:
#   SIGNED_CFG   — session-configured identity (init_git_repo default below)
#   WRONG        — real-but-wrong `-c user.email` class (#12027: jean@jikig.ai
#                  over configured jean.deruelle@jikigai.com)
#   PINNED       — the pinned CLA-allowlisted human email (SANCTIONED_EMAILS)
#   BOT_ALLOW    — allowlisted-bot noreply (soleur-ai[bot], login in cla.yml)
#   SIGNED_LOGIN — signed contributor noreply (Elvalio, in cla.json only)
#   DEVIN        — devin-ai-integration[bot] noreply (NEITHER roster; DENIED)
#   BARE_LOGIN   — pre-2017 `login@users.noreply.github.com` (no <id>+)
#   INJECTED     — `$(…)` payload email (survives git ident into %ae verbatim)
#   WEB          — `noreply@github.com` (sanctioned in the committer slot only)
# ==========================================================================

# T7 (#12027): config supplies the CLA-signed identity; commits authored by a
# real-but-wrong email → DENY naming the wrong email.
t7() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  git -C "$work" config user.email jean.deruelle@jikigai.com
  push_cla_yml "$work"
  commit_branch "$work" feat-c "jean@jikig.ai"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T7 wrong-identity -c email denies (#12027)" "$inc" "$out" "$rc" "jean@jikig.ai"; rm -rf "$t"; }

# T8 (#7218): unsigned non-noreply identity unconfigured anywhere → DENY.
t8() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"; push_cla_signatures "$work"
  commit_branch "$work" feat-ops "ops@jikigai.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 1 --squash')") || rc=$?
  assert_deny "T8 unsigned non-noreply email denies (#7218)" "$inc" "$out" "$rc" "ops@jikigai.com"; rm -rf "$t"; }

# T9: allowlisted-bot noreply author + configured committer → PASS.
t9() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-bot "273333864+soleur-ai[bot]@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T9 allowlisted-bot noreply passes" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T10: signed-contributor noreply (login in cla.json signatures, NOT in the
# allowlist) → PASS.
t10() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_signatures "$work"
  commit_branch "$work" feat-sig "92384917+Elvalio@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T10 signed-login noreply passes" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T11: devin-bot noreply — in NEITHER roster (measured cla-check fail, PR
# #11690) → DENY even with both rosters present.
t11() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"; push_cla_signatures "$work"
  commit_branch "$work" feat-devin "158243242+devin-ai-integration[bot]@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T11 devin-bot noreply denies" "$inc" "$out" "$rc" "devin-ai-integration[bot]"; rm -rf "$t"; }

# T12: explicit-exclusion precedence — the devin-bot email AS the session's
# `git config user.email` still denies (deny overrides admit).
t12() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  git -C "$work" config user.email "158243242+devin-ai-integration[bot]@users.noreply.github.com"
  push_cla_yml "$work"; push_cla_signatures "$work"
  commit_branch "$work" feat-dcfg "158243242+devin-ai-integration[bot]@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T12 devin-bot as config user.email still denies" "$inc" "$out" "$rc" "devin-ai-integration[bot]"; rm -rf "$t"; }

# T13: committer-only offender — sanctioned author, unsanctioned COMMITTER →
# DENY (%ce coverage; the rule says authored AND committed).
t13() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-cmt "test@test.local,ops@jikigai.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T13 committer-only offender denies" "$inc" "$out" "$rc" "ops@jikigai.com"; rm -rf "$t"; }

# T14: mixed authors — compliant FIRST commit, unsanctioned SECOND → DENY
# naming the second offender (no stop-at-first-member).
t14() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-mix "test@test.local" "ops@jikigai.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T14 mixed authors denies (second member)" "$inc" "$out" "$rc" "ops@jikigai.com"; rm -rf "$t"; }

# T15: unset config + pinned human email — the sanctioned `-c` override path
# for unset-config sessions → PASS.
t15() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  git -C "$work" config --unset user.email
  push_cla_yml "$work"
  commit_branch "$work" feat-pin "jean.deruelle@jikigai.com,jean.deruelle@jikigai.com"
  local rc=0; out=$(run_hook_noglobal "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T15 unset-config + pinned human email passes" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T16: all sanctioned sources absent — no cla.yml at origin/main, no
# cla-signatures ref, config unset; a would-be offender on the branch → PASS
# (fail-open: the property is "enforce when evaluable", not "deny by absence").
t16() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  git -C "$work" config --unset user.email
  commit_branch "$work" feat-open "ops@jikigai.com,ops@jikigai.com"
  local rc=0; out=$(run_hook_noglobal "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T16 all-sources-absent fail-opens" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T17: pre-2017 bare-login noreply form `login@users.noreply.github.com`
# (no `<id>+` prefix) whose login IS in the roster → PASS.
t17() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"; push_cla_signatures "$work"
  commit_branch "$work" feat-bare "deruelle@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T17 bare-login noreply on roster passes" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T18: pre-2017 bare-login noreply form whose login is in NEITHER roster →
# DENY naming the email.
t18() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"; push_cla_signatures "$work"
  commit_branch "$work" feat-badeny "madeup@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T18 bare-login noreply off roster denies" "$inc" "$out" "$rc" "madeup@users.noreply.github.com"; rm -rf "$t"; }

# T19: case-insensitive roster match — `92384917+elvalio@…` (lowercase) vs
# the roster's `Elvalio` → PASS (GitHub logins compare case-insensitively).
t19() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_signatures "$work"
  commit_branch "$work" feat-fold "92384917+elvalio@users.noreply.github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T19 case-folded login matches roster" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T20: remedy-path injection — a `$(…)` payload survives git's ident
# sanitization into %ae verbatim (measured), so the offender denies, but the
# payload must NOT appear in the executable `for e in` args; it is demoted
# to a "manual rewrite required for" line while the conforming offender
# still gets an executable arg.
t20() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-inj 'x$(echo INJECTED)@bad.example' 'ops@jikigai.com'
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T20 injected-payload email denies" "$inc" "$out" "$rc" 'x$(echo INJECTED)@bad.example'
  local reason fixline ok=1
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
  grep -qF 'manual rewrite required for' <<<"$reason" || ok=0
  fixline=$(printf '%s' "$reason" | grep 'for e in' || true)
  grep -qF 'INJECTED' <<<"$fixline" && ok=0
  grep -qF 'ops@jikigai.com' <<<"$fixline" || ok=0
  if [[ "$ok" -eq 1 ]]; then echo "PASS: T20b payload excluded from executable remedy"; PASS=$((PASS+1));
  else echo "FAIL: T20b payload reached executable remedy args (fixline: $fixline)"; FAIL=$((FAIL+1)); fi
  TOTAL=$((TOTAL+1)); rm -rf "$t"; }

# T21: committer-slot web-merge carve-out — sanctioned author +
# `noreply@github.com` COMMITTER (the GitHub web-edit/update-branch shape,
# which cla-check never evaluates) → PASS.
t21() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-web "test@test.local,noreply@github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_pass "T21 web-flow committer passes" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T22: the carve-out is committer-ONLY — `noreply@github.com` as AUTHOR
# resolves to the unsigned web-flow login → DENY.
t22() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-webauth "noreply@github.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T22 noreply@github.com author denies" "$inc" "$out" "$rc" "noreply@github.com"; rm -rf "$t"; }

# T23: combined offender detail — a branch carrying BOTH a stage-1 unsigned
# commit and a stage-2 unsanctioned commit denies on stage 1 but NAMES the
# stage-2 offender too, so one rewrite round fixes both classes.
t23() { local t; t=$(mktemp -d -p "$SUITE_TMP"); read -r work inc < <(make_repo "$t")
  push_cla_yml "$work"
  commit_branch "$work" feat-both "$UNSIGNED" "ops@jikigai.com"
  local rc=0; out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready')") || rc=$?
  assert_deny "T23 stage-1 deny names stage-2 offender" "$inc" "$out" "$rc" "ops@jikigai.com"; rm -rf "$t"; }

# T24: pinned-literal parity — the emails the hook pins by name must be the
# SAME literals INSTRUCTIONS.md's commit-author section teaches. They are
# extracted from the hook source (never a second copy) so a hook/doc drift
# fails here. Anchored on the section's bullet phrase so a literal appearing
# in an unrelated bullet cannot satisfy the check.
t24() { local doc="$SCRIPT_DIR/../../plugins/soleur/devin/INSTRUCTIONS.md" ca e login bad=0
  ca=$(grep -F 'Commit author identity' "$doc" 2>/dev/null || true)
  if [[ -z "$ca" ]]; then
    echo "FAIL: T24 no 'Commit author identity' section in INSTRUCTIONS.md"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); return
  fi
  # SANCTIONED_EMAILS literals must appear verbatim in the section.
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    grep -qF -- "$e" <<<"$ca" \
      || { printf '  drift: sanctioned literal %s absent from INSTRUCTIONS.md commit-author section\n' "$e" >&2; bad=1; }
  done < <(awk '/^SANCTIONED_EMAILS="/,/"$/' "$HOOK" | grep -oE '[^"[:space:]]+@[^"[:space:]]+')
  # DENIED_EMAILS identities are documented by login — assert the login form.
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    login="${e%@users.noreply.github.com}"; login="${login#*+}"
    grep -qF -- "$login" <<<"$ca" \
      || { printf '  drift: denied-bot login %s absent from INSTRUCTIONS.md commit-author section\n' "$login" >&2; bad=1; }
  done < <(awk '/^DENIED_EMAILS="/,/"$/' "$HOOK" | grep -oE '[^"[:space:]]+@users\.noreply\.github\.com')
  if [[ "$bad" -eq 0 ]]; then echo "PASS: T24 hook-pinned literals match INSTRUCTIONS.md"; PASS=$((PASS+1));
  else echo "FAIL: T24 hook/doc literal drift"; FAIL=$((FAIL+1)); fi
  TOTAL=$((TOTAL+1)); }

t1; t1b; t2; t3; t4; t5; t6; t7; t8; t9; t10; t11; t12; t13; t14; t15; t16; t17; t18; t19; t20; t21; t22; t23; t24

# === Instrument self-test ===
# Drives BOTH assert helpers through their pass AND fail branches on
# fabricated payloads and refuses to continue unless every counter moved —
# otherwise a disarmed instrument (e.g. a deleted JSON parse inside
# assert_deny) summarizes green over arms it never measured (ADR-193 shape).
# Probe rows are folded back out of the counters afterwards so the printed
# tally reflects only real arms.
_p=$PASS _f=$FAIL _t=$TOTAL
_st=$(mktemp -d -p "$SUITE_TMP"); mkdir -p "$_st/incd/.claude" "$_st/incp/.claude"
printf '%s\n' '{"rule_id":"wg-cla-signed-author-before-merge","event_type":"deny"}' \
  > "$_st/incd/.claude/.rule-incidents.jsonl"
_deny='{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"probe"}}'
assert_deny "self-test: deny instrument parses deny payload" "$_st/incd" "$_deny" 0   # PASS+1
assert_deny "self-test: deny instrument rejects non-deny" "$_st/incd" "" 0            # FAIL+1
assert_pass "self-test: pass instrument accepts clean run" "$_st/incp" "" 0           # PASS+1
assert_pass "self-test: pass instrument rejects deny payload" "$_st/incp" "$_deny" 0  # FAIL+1
if (( PASS != _p + 2 || FAIL != _f + 2 )); then
  printf '[FATAL] instrument self-test: an assert helper did not move counters (PASS %d->%d, FAIL %d->%d)\n' \
    "$_p" "$PASS" "$_f" "$FAIL" >&2
  exit 1
fi
PASS=$_p; FAIL=$_f; TOTAL=$_t
rm -rf "$_st"

echo "----"
echo "$PASS/$TOTAL passed"
[[ "$FAIL" -eq 0 ]] || exit 1

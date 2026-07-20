#!/usr/bin/env bash
# Fixture tests for pre-merge-auto-close-scan.sh. Each test builds a tmp git repo
# (with an origin/main ref + feature commits), composes a PreToolUse(Bash) input,
# pipes it to the hook, and asserts the permissionDecision — and, for the
# degraded arms, the number of stderr notices.
#
# Isolation pattern mirrors follow-through-directive-gate.test.sh.
#
# THE `gh` STUB DISPATCHES ON "$@". That is load-bearing, not stylistic. The
# previous stub printed the PR body for ANY argv, so the hook's malformed
# `--repo` slug (it kept the trailing `.git` on SSH remotes) still read as
# success here while failing against real gh. The PR-body arm was dead for 17
# days at 8/8 green — the fixture seam sat ABOVE the code under test (#6775 D3).
# `stub-argv-fidelity.test.sh` now enforces argv dispatch for every hook stub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pre-merge-auto-close-scan.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCANNER="$REPO_ROOT/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"

PASS=0; FAIL=0; TOTAL=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }
[[ -f "$SCANNER" ]] || { echo "SKIP: auto-close-scan.sh not found"; exit 0; }

# Per-case options. Set immediately before a run_case call; run_case clears them
# afterwards so they never leak into the next case.
OPT_ACK=""        # non-empty -> SOLEUR_ACK_AUTOCLOSE=1 (broad hatch)
OPT_FTACK=""      # non-empty -> SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1 (scoped hatch)
OPT_MODE="ok"     # ok | ghfail (auth/network) | nopr (no PR for branch)
OPT_FT=""         # newline/space separated issue numbers carrying `follow-through`
OPT_SUBDIR=""     # non-empty -> run the hook with cwd set to a subdirectory
OPT_NOSCANNER=""  # non-empty -> do not install the scanner in the tmp repo
OPT_NOTICES=""    # expected count of stderr notice lines ("" = do not assert)
OPT_REASON=""     # newline-separated substrings the deny reason must ALL contain
                  # ("" = do not assert). This is the discriminator for WHICH
                  # arm denied — the prose arm and the label gate both emit
                  # `deny`, so a decision-only assertion cannot tell them apart —
                  # and for WHICH body the operator has to scrub, which is the
                  # entire lesson of #6775 (the keyword lived in two places).

# Build a tmp WORK_DIR: a git repo on a feature branch with an origin/main ref,
# the scanner copied in, and an argv-dispatching gh stub on PATH.
#   $1 = commit body (last feature commit), $2 = PR body (served by the stub)
make_work_dir() {
  local body="$1" pr_body="$2" tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q -b feat-x
  git -C "$tmp" config user.email t@t; git -C "$tmp" config user.name t
  git -C "$tmp" commit -q --allow-empty -m "base"
  git -C "$tmp" update-ref refs/remotes/origin/main HEAD            # origin/main = base
  git -C "$tmp" remote add origin "git@github.com:acme/repo.git"
  git -C "$tmp" commit -q --allow-empty -m "$body"                  # feature commit
  if [[ -z "$OPT_NOSCANNER" ]]; then
    mkdir -p "$tmp/plugins/soleur/skills/ship/scripts"
    cp "$SCANNER" "$tmp/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"
  fi
  mkdir -p "$tmp/.binstub" "$tmp/sub/deeper"

  # Fixture payloads live in files, not interpolated into the stub source, so a
  # quote or `$` in a fixture cannot corrupt the stub.
  printf '%s\n' "$pr_body"  > "$tmp/.binstub/pr-body.txt"
  printf '%s'   "$OPT_MODE" > "$tmp/.binstub/gh-mode"
  : > "$tmp/.binstub/follow-through.txt"
  local n
  for n in $OPT_FT; do printf '%s\n' "$n" >> "$tmp/.binstub/follow-through.txt"; done

  cat > "$tmp/.binstub/gh" <<'STUB'
#!/usr/bin/env bash
# Hook-test `gh` stub — MUST inspect "$@".
#
# A stub that ignores argv cannot see HOW the hook invokes gh, so a malformed
# --repo, a wrong issue number, or a wrong subcommand all read as success. That
# is the blind spot that kept the PR-body arm of this hook dead while its test
# reported green (#6775 D3). Copy this dispatch shape into any new hook stub;
# stub-argv-fidelity.test.sh fails the build if a gh stub drops it.
set -uo pipefail
STUB_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="$(cat "$STUB_DIR/gh-mode" 2>/dev/null || echo ok)"

# Reject a malformed --repo exactly as real gh does. The slug the hook used to
# build kept the trailing ".git" on SSH remotes, so gh answered with a GraphQL
# error, the non-zero exit was swallowed, and the body was never scanned.
_repo=""; _prev=""
for _a in "$@"; do
  [[ "$_prev" == "--repo" ]] && _repo="$_a"
  _prev="$_a"
done
if [[ -n "$_repo" && "$_repo" != "acme/repo" ]]; then
  echo "GraphQL: Could not resolve to a Repository with the name '$_repo'." >&2
  exit 1
fi

case "${1:-}:${2:-}" in
  pr:view)
    if [[ "$MODE" == "ghfail" ]]; then
      echo "error connecting to api.github.com" >&2; exit 1
    fi
    if [[ "$MODE" == "nopr" ]]; then
      echo 'no pull requests found for branch "feat-x"' >&2; exit 1
    fi
    cat "$STUB_DIR/pr-body.txt" 2>/dev/null || true
    ;;
  issue:view)
    if [[ "$MODE" == "ghfail" ]]; then
      echo "error connecting to api.github.com" >&2; exit 1
    fi
    # $3 is the issue number the hook resolved. Emitting labels for the WRONG
    # number is how an extraction bug would surface here.
    if [[ -n "${3:-}" ]] && grep -qxF "${3:-}" "$STUB_DIR/follow-through.txt" 2>/dev/null; then
      printf 'follow-through,observability\n'
    else
      printf 'type/bug,priority/p2-medium\n'
    fi
    ;;
  *) : ;;
esac
exit 0
STUB
  chmod +x "$tmp/.binstub/gh"
  echo "$tmp"
}

make_input() { jq -n --arg cmd "$1" --arg cwd "$2" \
  '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}'; }

# run_case <name> <expect: deny|allow> <cmd> <commit-body> <pr-body>
run_case() {
  local name="$1" expect="$2" cmd="$3" body="$4" pr="$5"
  TOTAL=$((TOTAL+1))
  local wd cwd out decision reason errf notices ok=1 detail=""
  wd="$(make_work_dir "$body" "$pr")"
  cwd="$wd"; [[ -n "$OPT_SUBDIR" ]] && cwd="$wd/sub/deeper"
  errf="$(mktemp)"
  # `env` is required, NOT an assignment prefix. Bash recognises assignment
  # prefixes at PARSE time, so `${OPT_ACK:+FOO=1} bash …` makes the expanded
  # `FOO=1` the COMMAND NAME ("command not found") and the hook never runs —
  # which silently defaults the decision to `allow`. main's ack case was green
  # for exactly that reason: it asserted `allow` against a hook that never
  # executed. Same family as the argv-blind stub this file exists to fix.
  out="$(make_input "$cmd" "$cwd" | PATH="$wd/.binstub:$PATH" env \
    ${OPT_ACK:+SOLEUR_ACK_AUTOCLOSE=1} \
    ${OPT_FTACK:+SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1} \
    bash "$HOOK" 2>"$errf" || true)"
  decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  [[ -n "$decision" ]] || decision="allow"   # empty hook output = allow
  reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || true)"
  notices="$(grep -c '^pre-merge-auto-close-scan: ' "$errf" || true)"
  rm -rf "$wd" "$errf"

  [[ "$decision" == "$expect" ]] || { ok=0; detail="expected $expect, got $decision"; }
  if [[ -n "$OPT_NOTICES" && "$notices" != "$OPT_NOTICES" ]]; then
    ok=0; detail="${detail:+$detail; }expected $OPT_NOTICES notice(s), got $notices"
  fi
  if [[ -n "$OPT_REASON" ]]; then
    local want
    while IFS= read -r want; do
      [[ -n "$want" ]] || continue
      # grep a FILE-free herestring, never `printf | grep -q`: under pipefail an
      # early match makes grep close the pipe, the producer takes SIGPIPE (141),
      # and the pipeline reports failure even though the pattern matched.
      grep -qF -- "$want" <<<"$reason" || {
        ok=0; detail="${detail:+$detail; }deny reason lacks '$want'"
      }
    done <<< "$OPT_REASON"
  fi

  OPT_ACK=""; OPT_FTACK=""; OPT_MODE="ok"; OPT_FT=""
  OPT_SUBDIR=""; OPT_NOSCANNER=""; OPT_NOTICES=""; OPT_REASON=""

  if [[ "$ok" == 1 ]]; then
    PASS=$((PASS+1)); echo "PASS: $name ($decision)"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $name — $detail"
  fi
}

# ---------------------------------------------------------------------------
# Prose arm — the original #5887/#5955 vectors. Preserved for all issues,
# labelled or not (plan 3.7).
# ---------------------------------------------------------------------------

# T2 — prose-embedded close in the COMMIT body → DENY (the #5887 vector).
OPT_REASON="prose-embedded" \
run_case "T2 commit prose-embedded closes → deny" deny \
  "gh pr merge 1 --squash --auto" $'fix: thing\n\nthe follow-through sweeper closes #5887 post-merge.' ""

# T1 — prose-embedded close in the PR BODY → DENY (the #5955 vector).
# RED before the D1 repair: the stub rejects the malformed --repo, so the body
# never reaches the corpus. The T2 case above must stay green in the same run —
# a body-only failure is also what a broken stub produces.
OPT_REASON="prose-embedded" \
run_case "T1 PR-body prose-embedded close → deny" deny \
  "gh pr merge 1 --squash" "fix: thing" "I'll close #5955 after the pipeline confirms green."

# Standalone directives on an UNLABELLED issue stay allowed — this is the form
# every ordinary fix-PR uses, including this one.
run_case "standalone Closes line → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #5887' ""

run_case "bullet Fixes line → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\n- Fixes #5887' ""

run_case "Ref only → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nRef #5887, #5877' ""

# T7 — non-merge command → ALLOW (early exit).
run_case "T7 non-merge command → allow" allow \
  "git status --short" $'fix: thing\n\nsweeper closes #5887' ""

# T9 — broad hatch disarms the prose arm.
OPT_ACK=1 \
run_case "T9 broad ack env overrides → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nsweeper closes #5887' ""

# T8 — `gh pr merge` documented inside a commit -m string is NOT a merge.
# (The embedded close IS in the body: if strip_command_bodies fails, this denies.)
run_case "T8 gh pr merge in quoted string → allow" allow \
  "git commit -m 'do not hand-roll gh pr merge here'" $'base\n\nsweeper closes #5887' ""

# ---------------------------------------------------------------------------
# follow-through label gate (D2). A standalone `Closes #N` is allowed BY DESIGN
# for ordinary issues; when #N is a follow-through tracker, closing it makes the
# daily sweeper skip it and the soak never runs.
# ---------------------------------------------------------------------------

# T3 — REACHABILITY (AC2). A standalone close produces an EMPTY prose-arm
# result, so a gate appended after the `[[ -n "$EMBEDDED" ]] || exit 0` early
# exit can never fire on it. This case is what proves the gate is reachable.
# The reason must also name the SURFACE. #6775's whole story is that the keyword
# had to be scrubbed in two places; a deny that does not say which body it found
# the close in sends the operator hunting.
OPT_FT="6617" OPT_REASON=$'follow-through\n#6617 — referenced from the PR body' \
run_case "T3 PR-body standalone Closes on follow-through → deny" deny \
  "gh pr merge 1 --squash" "fix: thing" $'Summary.\n\nCloses #6617'

# T4 — same, carried by the COMMIT message. Same fixture, different surface:
# together these two pin the attribution in BOTH directions, so an
# implementation that hardcodes either label fails one of them.
OPT_FT="6617" OPT_REASON=$'follow-through\n#6617 — referenced from the commit message' \
run_case "T4 commit standalone Closes on follow-through → deny" deny \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #6617' ""

# T5 — `Ref #N` alone is not a close, even for a follow-through tracker.
OPT_FT="6617" \
run_case "T5 Ref alone on follow-through → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nRef #6617' ""

# T6 — standalone close on an issue WITHOUT the label still merges. The gate
# must not widen denial beyond follow-through trackers.
OPT_FT="6617" \
run_case "T6 standalone Closes on non-follow-through → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #6295' ""

# GH-N is the other reference form the canonical scanner recognises.
OPT_FT="6617" OPT_REASON="follow-through" \
run_case "GH-N form on follow-through → deny" deny \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses GH-6617' ""

# T10 — the SCOPED hatch must NOT disarm the prose arm. (The broad hatch sits
# above corpus construction; the scoped one is checked at the gate.)
OPT_FTACK=1 \
run_case "T10 scoped hatch does not disarm prose arm → deny" deny \
  "gh pr merge 1 --squash" $'fix: thing\n\nsweeper closes #5887' ""

# T13 — a PR that LEGITIMATELY resolves a follow-through tracker can merge.
# With 44 open trackers this is the deny operators will actually hit.
OPT_FT="6617" OPT_FTACK=1 \
run_case "T13 legitimate follow-through close + scoped hatch → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #6617' ""

# ---------------------------------------------------------------------------
# Extraction contract (AC9). The scanner emits `<line-number>:<matched-text>`
# and its DIRECTIVE filter is line-granular, so a naive `grep -oE '#[0-9]+'`
# over a matched line denies over issues the PR explicitly declined to close.
# ---------------------------------------------------------------------------

# T11a — the label gate must pair each number with ITS OWN keyword. Here the
# line-leading directive closes #6295 (so the PROSE arm allows, as it does for
# every line-leading close), and #6617 is merely referenced. A naive
# `grep -oE '#[0-9]+'` over the matched line would scrape #6617 and deny over a
# tracker this PR explicitly declined to close.
OPT_FT="6617" \
run_case "T11a keyword-paired extraction ignores a bare ref → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #6295 (refs #6617)' ""

# T11b — the same two references with the close NOT line-leading. This is a
# genuine prose-embedded close, so the PROSE arm denies (AC5) — and the reason
# must show it was the prose arm, not the label gate mistaking #6617 for a
# closing reference.
OPT_FT="6617" OPT_REASON="prose-embedded" \
run_case "T11b Refs #A, closes #B on one line → deny via prose arm" deny \
  "gh pr merge 1 --squash" $'fix: thing\n\nRefs #6617, closes #6295' ""

# T12 — exact-token comparison: #661 is a PREFIX of the follow-through 6617.
OPT_FT="6617" \
run_case "T12 issue number prefixing a follow-through number → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #661' ""

# ---------------------------------------------------------------------------
# Degraded arms (AC11). Fail-open for the merge DECISION, loud for DIAGNOSIS —
# except the normal no-PR state, which must stay silent or every pre-PR merge
# attempt cries wolf.
# ---------------------------------------------------------------------------

# T14 — gh unreachable (auth expired / offline / GitHub 5xx).
OPT_MODE="ghfail" OPT_NOTICES=1 \
run_case "T14 gh failure → allow + one notice" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nnothing to see' ""

# T15a — merge issued from a SUBDIRECTORY. The scanner must still resolve (via
# the repo toplevel, not the payload cwd), so the deny still fires.
OPT_SUBDIR=1 \
run_case "T15a merge from subdirectory still finds scanner → deny" deny \
  "gh pr merge 1 --squash" $'fix: thing\n\nsweeper closes #5887' ""

# T15b — scanner genuinely absent.
OPT_NOSCANNER=1 OPT_NOTICES=1 \
run_case "T15b scanner unresolvable → allow + one notice" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nsweeper closes #5887' ""

# T16 — no PR exists for the branch yet. A NORMAL state: allow, and NO notice.
OPT_MODE="nopr" OPT_NOTICES=0 \
run_case "T16 no PR for branch → allow, no notice" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nnothing to see' ""

# ---------------------------------------------------------------------------
# Static assertions on the hook SOURCE.
#
# Comment lines are stripped first. A raw grep over the whole file matches the
# hook's own explanatory comments — which name both forbidden constructs
# precisely BECAUSE the code must not use them — so an unstripped assertion
# false-FAILs on a correct file and would be "fixed" by deleting the
# documentation. Anchor on code, never on prose (`cq-assert-anchor-not-bare-token`).
# ---------------------------------------------------------------------------

HOOK_CODE="$(grep -vE '^[[:space:]]*#' "$HOOK")"

static_case() {   # <name> <expected-count> <extended-regex>
  local name="$1" expect="$2" pattern="$3" n
  TOTAL=$((TOTAL+1))
  n="$(printf '%s\n' "$HOOK_CODE" | grep -cE "$pattern" || true)"
  if [[ "$n" == "$expect" ]]; then
    PASS=$((PASS+1)); echo "PASS: $name ($n)"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $name — expected $expect match(es), got $n"
  fi
}

# AC10 — gh must resolve the repo from the working directory. Hand-building the
# slug is what made the PR-body arm dead code. Genuine before/after
# discriminator: this returns 1 against main.
static_case "AC10 no --repo or hand-built slug in hook code" 0 'remote get-url origin|--repo'

# AC8 — label lookup must stay per-issue. `gh issue list` paginates at 30 by
# default and a full page is indistinguishable from a truncated one, which would
# silently exempt the oldest trackers.
#
# NOTE: this returns 0 against main too, so it is a guard against INTRODUCING
# the truncating call, not evidence the label gate works. AC2/AC3 (T3/T4) carry
# that. Stated explicitly because an assertion that passes before and after
# reads as state-change proof and is not — the exact vacuity class this suite
# exists to eliminate.
static_case "AC8 no paginated gh issue list in hook code" 0 'gh issue list'

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]

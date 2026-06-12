# Learning: restoring a hook-contained cron whose commit lives in a multi-phase SKILL — sweep EVERY bash-emitting phase, and verify shared-hook matcher fixes against the FULL suite

## Problem

Restoring `cron-bug-fixer` (#5199, the FINAL Tier-2 cron — an autonomous code-writer
that runs claude against the live prod repo) surfaced two recurring traps beyond the
PR-5235 `$ROUTER`/`$VAR` containment-break class, both caught only at multi-agent review:

## Trap 1 — the literal-allowlisted-form rewrite must sweep EVERY phase of the SKILL, not just the happy path

`cron-bug-fixer` invokes the WHOLE `fix-issue/SKILL.md` as its prompt. The implementation
rewrote Phases 2/4/5 (test-baseline, fix, PR-create) from hook-DENIED constructs
(`eval "$TEST_CMD"`, `node -e`, `$(cat <<EOF)`, `| tail -50`) to literal forms
(`./node_modules/.bin/vitest run --root apps/web-platform`, `--body-file pr-body.md`) —
but **left Phase 6 (the Failure Handler) untouched**, still emitting:
- `gh issue comment <N> --body "…\n\n…"` — MULTILINE body → `dangerousMetacharReason` denies `[\n\r]`.
- `git worktree remove … --force 2>/dev/null` and `git branch -D … 2>/dev/null` — redirect denied.
- a bare `cd …` — `cd` is not an allowlisted verb.

Phase 6 fires on ANY phase failure — a COMMON path for an automated bug-fixer — so the
failure comment never posts and cleanup is denied at runtime, while every test stayed green.

**Generalizable:** when a hook-contained cron's prompt is a multi-phase SKILL, the
literal-form rewrite (and the verb enumeration) must cover EVERY phase that emits bash —
explicitly including failure/cleanup/rollback handlers, which happy-path testing never
exercises. Grep the whole SKILL for bash fences, not just the phases the plan names.

## Trap 2 — the decide-paired test fixtures must mirror the SKILL's ACTUAL per-phase emitted text

The substrate decide-paired test's ALLOW block used hand-sanitized fixtures (single-line
`gh issue comment … --body "Bot Fix Attempted"`, bare `git branch -D bot-fix-4321-foo`)
that DIVERGED from the SKILL's real Phase-6 forms (multiline body, `2>/dev/null`). So the
parity defense the test comment claims ("a membership/parity test is vacuous-green against
a runtime DENY") had its OWN vacuum: the ALLOW fixtures didn't match what the SKILL emits,
so they passed while the real forms would deny. Fix: add the SKILL's REAL per-phase forms
(post-rewrite) as ALLOW fixtures so the test regression-locks the rewrite.

## Trap 3 — a reviewer-prescribed change to a SHARED containment matcher must be verified against the FULL existing suite before shipping

security-sentinel found a real P1: the hook's `segmentMatchesAllowlist` had a bare
no-separator clause (`norm.startsWith(p)`) so `bash …/worktree-manager.sh-pwn` prefix-matched
the allowlisted `bash …/worktree-manager.sh` → a prompt-injected model could `Write` a sibling
exfil script then bash it → ALLOW → key exfil. The prescribed fix — DELETE the third clause,
leaving only exact-match + trailing-space — **broke 3 pre-existing tests**: another cron's
allowlist carries a directory-scoped `gh api repos/jikig-ai/soleur/` prefix (trailing `/`, no
space) that LEGITIMATELY relies on no-separator prefix matching so `…/milestones?…` matches.
The "every legitimate command is exact-verb or `verb <space> args`" premise is FALSE for
`/`-terminated directory prefixes.

**The correct fix** carves out the path boundary: a no-separator match is allowed ONLY when the
prefix ends in `/` —
`norm === p || norm.startsWith(p + " ") || (p.endsWith("/") && norm.startsWith(p))`.
This denies `.sh-pwn` (ends in `h`) while preserving `gh api repos/…/` (ends in `/`).

**Generalizable:** a reviewer's one-line fix to a SHARED guard (containment hook, drift
gate, regex matcher) is a HYPOTHESIS — run the guard's FULL existing test suite before
shipping it. A red sibling test is the signal that a legitimate consumer relied on the
behavior the "fix" removes. Prefer the narrowest carve-out that closes the vuln AND keeps
every green test green, over the broad deletion the single-finding reviewer proposed.

## Trap 3b — plan literal text on a two-sided invariant can be imprecise; encode the invariant, not the literal

The plan's AC12b said "add `payload.tool_name === "Bash"` to the mock's `allowed` condition."
Taken literally, a BLANKET Bash-allow breaks `runHookSelfTest`'s two-sided contract — the
self-test fires BOTH an `allow[0]` Bash probe (must ALLOW) AND a `cat /proc/self/environ`
exfil probe (must DENY) in the same run. The correct mock is command-aware:
`BASH_EXFIL_DENY = /\/proc\/self\/environ|eval |node -e|\$\(|\| |> \//` — allow the verb,
still deny the exfil probe. Plan prose describing a guard is intent; implement the invariant.

## Key insight

For a containment-cron restore, the cron's prompt SKILL — including its failure handlers —
is the live attack surface, and the decide-paired test is only as strong as the fidelity of
its ALLOW fixtures to the SKILL's ACTUAL emitted bash. And when review prescribes a fix to a
SHARED matcher, the full existing suite is the safety net that catches a legitimate consumer
(here: a `/`-terminated `gh api` directory prefix) the single finding didn't model.

## Session Errors

1. **Impl subagent rewrote SKILL Phases 2/4/5 but missed Phase 6 (Failure Handler)** — Recovery: pattern-recognition-specialist caught it at review; rewrote Phase 6 to literal forms + added real Phase-6 ALLOW fixtures. **Prevention:** Trap 1 — sweep every bash-emitting phase of a multi-phase prompt SKILL, not just the named ones.
2. **Reviewer-prescribed hook matcher fix (delete the no-separator clause) broke 3 pre-existing `gh api repos/.../` tests** — Recovery: fix subagent STOPped per instruction, ran the full hook suite, shipped the trailing-`/` carve-out instead. **Prevention:** Trap 3 — run a shared guard's full suite before shipping a reviewer's matcher change.
3. **Plan's literal AC12b text would have broken the self-test's two-sided contract** — Recovery: impl subagent encoded a command-aware deny regex. **Prevention:** Trap 3b — implement the invariant, not the literal prose.
4. **Push rejected after rebasing the draft-PR branch onto new main** (init-commit SHA changed post-rebase) — Recovery: `git push --force-with-lease`. **Prevention:** expected for a one-shot draft-PR branch rebased onto a moved main; force-with-lease is the correct, safe response.
5. **#5244 merged the cron-egress nftables CIDR injection to main unfixed** (discovered mid-session via background security review) — Recovery: filed + escalated #5242 as a separate PR (different subsystem; scope discipline, NOT bundled into bug-fixer). **Prevention:** a different-subsystem defect stays its own issue/PR.
6. **Impl subagent updated `cron-safe-commit-parity.test.ts` for the empty TIER2 set but MISSED a THIRD sibling test file (`cron-shared.test.ts`)** whose `deferIfTier2Cron` describe block used `cron-bug-fixer` as the still-deferred fixture (`has("cron-bug-fixer")).toBe(true)`, `size).toBe(1)`, and a positive-path "defers a Tier-2 cron" test) — 3 stale assertions. The 4 touched-file suites the work/review phases ran did NOT include it; only ship Phase 4's full `test-all.sh` (the orphan-suite exit gate) caught it. Recovery: rewrote the 3 tests to the empty-set contract (bug-fixer no longer defers; `size` is 0; the positive defer-path is now unreachable dead code so the test asserts the no-op) + grep-swept `test/` for every other `cron-bug-fixer.*toBe(true)` / `size).toBe(1)` assertion (none remained). **Prevention:** when emptying/shrinking a SHARED const set (or any cross-file invariant), `grep -rn` ALL test files asserting the old membership BEFORE relying on the touched-file suites — the parity test is not the only consumer; a sibling `*-shared.test.ts` often carries the guard-mechanics tests. This is the SAME sweep-class as Trap 1/2 (every consumer, not just the named one), now extended to test files.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest (cron containment); plugins/soleur/skills/fix-issue

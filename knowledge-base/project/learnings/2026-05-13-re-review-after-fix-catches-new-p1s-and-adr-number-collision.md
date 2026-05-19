---
date: 2026-05-13
category: review-process
module: review,plan,ship
related_prs: [3701]
related_issues: [3698, 3710, 3711]
related_learnings:
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
  - 2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md
  - 2026-05-12-plan-review-5-agent-panel-and-architecture-only-p1s.md
---

# Re-review after the first fix pass catches new P1s; ADR-number collision needs a pre-merge guard

## Problem

PR #3701 (#3698 PR-A — pino `formatters.log()` userId rename hook) went through a full 11-agent `/soleur:review` pass that surfaced 4 P1s. After applying those P1 fixes inline AND rebasing onto `origin/main` (8 commits ahead), a focused 4-agent re-review (security-sentinel, architecture-strategist, data-integrity-guardian, code-quality-analyst) found **4 NEW P1s the first pass could not have seen** — three of which were introduced by the fix surface itself or by the rebase:

1. **CI gate fix introduced two new bypass vectors.** The first pass's P1 ("CI gate `userIdHash` exemption is line-level, defeated by mentioning the token anywhere") was patched by adding property-position regexes (`\buserIdHash\s*:` and `(reportSilentFallback|...)\s*\(`). The re-review's security-sentinel agent reproduced two bypasses against the FIX: (a) a decoy `{userId: x, userIdHash: "decoy"}` on the same line still passed the `\buserIdHash\s*:` filter because the filter is per-line, not per-key; (b) a string-literal `"warnSilentFallback("` still matched the `\s*\(` filter because regex cannot distinguish syntactic context. Each fix opened a new vector class.

2. **ADR-028 number collision** detected only post-rebase. PR #3634 (DSAR export, landed on main before the rebase) had already authored `ADR-028-dsar-export-substrate-and-audit-retention.md`. Our branch had authored `ADR-028-rename-at-boundary-userid-pseudonymisation.md` weeks earlier. Post-rebase both files coexisted in the worktree. The data-integrity-guardian agent flagged it; the architecture-strategist independently flagged it the same turn. The fix required `git mv` to ADR-029 + 8 lockstep reference updates (logger.ts, observability.ts, userid-pseudonymize.ts, article-30-register.md, plan, spec, tasks, learning).

3. **Rebase introduced a two-primitive architectural fact that needed an ADR invariant.** Pre-rebase: only `hashUserId` (HMAC-SHA256 + pepper) existed. Post-rebase: `hashUserIdForSentry` (SHA-256 + salt, 16-hex truncation) coexists, emits field names `offendingUserIdHash`/`expectedUserIdHash` from `mirrorCrossTenantViolation`. The architecture-strategist promoted prior P2-advisory "I8 (userIdHash reserved key)" to P1 and added new I10 (two-primitive separation table with threat-model justification) — neither invariant was a P1 before the rebase because the second primitive didn't exist on our branch.

4. **One agent claim was a false positive that would have caused harm if accepted.** data-integrity-guardian's P1-2 in the FIRST pass claimed "both `mirrorCrossTenantViolation` and `userid-pseudonymize` emit a field literally named `userIdHash` — name collision across two different hash domains". Verification via `git show origin/main:apps/web-platform/server/observability.ts | sed -n '498,541p'` showed `mirrorCrossTenantViolation` actually emits `offendingUserIdHash` and `expectedUserIdHash` — domain-distinct field names, no collision. Acting on this claim (e.g., renaming to add a domain suffix) would have introduced churn for a non-issue.

## Solution

### Pattern: re-review after fix pass + rebase is mandatory when both are non-trivial

If a PR's fix delta touches a boundary contract (security gate, error-handler, schema-key registry) AND the branch was rebased post-fix, a focused 4-agent re-review (security + architecture + data-integrity + code-quality) catches bypass-of-the-fix and rebase-induced architectural facts that the first pass could not see. Deviating to a smaller agent slice is reasonable; spawning all 8 again is overkill on a confirmation pass.

### Pattern: verify cross-domain field-name collision claims by name

When any review agent flags "field X collides with field Y across two consumers", run a focused grep (`git show <ref>:<file> | sed -n '<line>,<line>p'`) on both consumers and read the actual emit fields BEFORE acting. The agent's claim is a hypothesis until grep-verified. This generalizes the pattern in `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` (cross-reconcile triad) to field-name claims specifically.

### Pattern: ADR-number reservation guard

The canonical sequence today is "author ADR-N locally during planning; merge whenever." This creates a race window: any PR shipped to main between local-authoring and local-rebase can claim the same N. The pre-rebase / pre-merge guard that closes this race:

```bash
# Run before merging (or as part of pre-merge-rebase hook):
LOCAL_ADRS=$(ls knowledge-base/engineering/architecture/decisions/ADR-*.md | grep -oE 'ADR-[0-9]+' | sort -u)
MAIN_ADRS=$(git ls-tree -r --name-only origin/main knowledge-base/engineering/architecture/decisions/ | grep -oE 'ADR-[0-9]+' | sort -u)
COLLIDING=$(comm -12 \
  <(printf '%s\n' "$LOCAL_ADRS") \
  <(printf '%s\n' "$MAIN_ADRS") \
  | while read n; do
      # Same number — check if it's a different file (collision) or our own ADR (already on main)
      local_file=$(ls knowledge-base/engineering/architecture/decisions/${n}-*.md 2>/dev/null | head -1)
      main_file=$(git ls-tree -r --name-only origin/main knowledge-base/engineering/architecture/decisions/ | grep "^knowledge-base.*${n}-" | head -1)
      if [[ "$local_file" != "$main_file" && -n "$main_file" ]]; then
        echo "$n: local=$local_file main=$main_file"
      fi
    done)
[[ -n "$COLLIDING" ]] && echo "ADR collision: $COLLIDING" && exit 1
```

Routing: add as a `pre-merge-rebase.sh` check (already enforces other invariants) OR as a step in the plan skill when an ADR is being authored (reserve the next number by checking origin/main at plan time).

### Pattern: fix-of-a-regex-gate should drop the exempted pattern, not exempt-with-conditions

The first pass's CI-gate fix tried to ALLOW (`grep -vE`) the rename target (`userIdHash:`). The re-review showed this was unnecessary — lines containing ONLY `userIdHash:` (no raw `userId:`) already filter out at the earlier `\buserId\b|\buser_id\b` step because `\b` fails on `userIdHash` (`H` is a word character). The cleaner pattern: rely on the earlier filter's word-boundary semantics, drop the redundant `userIdHash:` exemption. Generalizable lesson: when adding an exemption to a multi-stage grep chain, first prove the existing chain doesn't already filter the legitimate case — exemptions are bypass surfaces.

## Key Insight

**Re-review after a non-trivial fix surface + rebase is a separate workflow step, not a polish pass.** Three of the four P1s the re-review found could not have existed at first-pass time: they were either introduced by the fix surface (bypass-of-the-fix) or surfaced by the rebase (new architectural facts). Plan reviews + post-fix re-reviews are different cost centers; a /work pipeline that runs /review → fix → /review again is correct, even at the cost of one extra agent fan-out.

**Pseudonymisation primitive separation is the architectural invariant, not field-name uniqueness.** Two hashing primitives (HMAC vs SHA-256+salt) coexisting in the same codebase is fine when the threat models genuinely differ AND the emit field names are domain-distinct AND the ADR documents the split. The first-pass agent's "field collision" claim conflated "same hash function" with "same field name" — those are independent. The fix isn't to consolidate primitives; it's to document the separation in an ADR invariant (I10 in ADR-029) so future contributors don't try to consolidate.

## Session Errors

1. **Stale `node_modules` post-rebase** — `tsc --noEmit` failed with "Cannot find module 'archiver'" after rebase brought #3634's DSAR dependency. Recovery: `bun install` in `apps/web-platform/`. **Prevention:** add a step to the rebase / pre-merge-rebase hook that runs `bun install` (or detects `package.json` diff vs HEAD@{1} and prompts) so node_modules stays in sync with the post-rebase package.json.

2. **Bash CWD reset mid-sequence** — `cd apps/web-platform && npx tsc --noEmit` in one bash call left CWD reset on the next call; second `npx tsc --noEmit` returned empty stdout (silent success-or-failure ambiguity). Recovery: re-`cd` with full absolute path + `pwd && <cmd>` confirmation. **Prevention:** prefer absolute paths in bash commands; never assume CWD persists across separate bash tool invocations.

3. **`bun test test/foo.test.ts` filename-syntax rejection** — bun's test runner doesn't accept the same file-path syntax as vitest. Recovery: `npx vitest run ./test/foo.test.ts`. **Prevention:** this project uses vitest for unit tests, not bun test — prefer `npx vitest run` for test invocations.

4. **`vitest run --grep` unknown flag** — vitest uses `-t` / `--testNamePattern` for test-name filters, not `--grep`. Recovery: re-ran with `-t "<pattern>"`. **Prevention:** quick reference — vitest filter flags are `-t` (name pattern) and positional file paths, not `--grep`.

5. **data-integrity-guardian P1-2 false positive (cross-domain field-name collision)** — agent claimed `userIdHash` collision, actual code emits `offendingUserIdHash`/`expectedUserIdHash`. Recovery: grep-verified against `origin/main:observability.ts:498-541` before acting. **Prevention:** captured as a generalized pattern in the Solution section ("verify cross-domain field-name collision claims by name").

6. **ADR-028 number collision detected only post-rebase** — required mid-stream renumber to ADR-029 across 9 lockstep references. **Prevention:** captured as a generalized pattern in the Solution section ("ADR-number reservation guard") with a draft pre-merge-rebase check.

## Cross-References

- ADR-029 (rename-at-boundary userId pseudonymisation) — invariants I3, I8, I10 added in PR #3701 as a direct result of the re-review.
- ADR-028 (DSAR export substrate, from #3634) — the colliding ADR that triggered the rename.
- `apps/web-platform/server/observability.ts:501-547` — `mirrorCrossTenantViolation` with the defensive ctx-strip added by this PR's re-review.
- `.github/workflows/pr-quality-guards.yml:226-244` — `userid-bypass-lint` gate, tightened twice via this PR.
- PR #3710 (PR-B follow-up — Sentry symmetric coverage) — receives the I8/I10 invariants forward.
- PR #3711 (PR-C follow-up — operator CLI + PA8 §(f) retention).

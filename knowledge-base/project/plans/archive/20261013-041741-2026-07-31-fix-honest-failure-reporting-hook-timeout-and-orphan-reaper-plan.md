---
title: "fix(dev-infra): two steps that report success they did not achieve"
date: 2026-07-31
type: fix
branch: feat-one-shot-7101-7102-honest-failure-reporting
lane: cross-domain
closes: [7101, 7102]
brand_survival_threshold: none
requires_cpo_signoff: false
revision: v3 (post 4-agent plan-review)
---

# fix(dev-infra): two steps that report success they did not achieve

> **Lane note.** No `spec.md` exists for this branch, so `lane:` could not be carried
> forward. Defaulted to `cross-domain` per the TR2 fail-closed rule.

## Enhancement Summary

**Deepened:** 2026-07-31 · **Rounds:** plan-review (4 agents) → deepen-plan (gates +
verify-the-negative + live reproduction)

**Gates:** 4.6 User-Brand Impact **PASS** (threshold `none`, 0 sensitive-path matches) ·
4.7 Observability **PASS** (5/5 fields, no placeholders, no empty keys, no ssh) · 4.8
PAT-shaped variable **PASS** · 4.9 UI wireframe **skip** (no UI surface) · 4.10 Encryption
posture **skip** (no store/connection) · 4.55 Downtime **skip** · 4.5 Network-outage
**not applicable** ("timeout" here is a test-runner hook budget, not reachability).

**Citations verified:** 4/4 AGENTS rule IDs ACTIVE (none fabricated or retired) · issues
#7101/#7102/#4254/#3272 all OPEN with matching titles · ADR-081 present · all learning
paths resolve in this worktree.

### Key changes from v1

1. **Docker-as-root escalation deferred** — v1's premise ("operator's own machine") is
   falsified; the script runs inside the agent sandbox. Logged as a User-Challenge.
2. **A third defect found and fixed** — the reaper returns `rc=1` on the default path
   after a *successful* clean, aborting its caller under `set -e`.
3. **A fourth lying surface found** — the per-directory `Removed orphan directory:` line
   prints on failure too (proven live).
4. **Two unrunnable ACs removed**, arithmetic corrected, 17 ACs → 9.

### Verified by execution, not assertion

- The `chmod 500` fixture yields `EACCES`, rc=1, dir survives, as EUID 1001 — no root.
- The reaper reproduces **both** defects live (output quoted in Work Target 2).
- Sourcing the script in a temp repo resolves `WORKTREE_DIR` correctly and defines the
  functions — the sibling suite's harness pattern is viable.
- `guardrails:block-rm-rf-worktrees`: plain form MATCHES, docker-wrapped form BYPASSES.
- `grep -c` exits 1 on a zero count; `Number("60_000")` is `NaN`.

## Overview

Two open dev-infra bugs, one PR. Both are the same defect: **a step that reports a
success it did not achieve.**

- **#7101** — a teardown hook gets 20s to undo what a 60s hook built. When it blows the
  budget every assertion has already passed, so the suite is green everywhere except the
  one hook that had no chance. `tenant-integration-required` is a required check, so it
  reds `main`.
- **#7102** — the orphan reaper runs `rm -rf`, never checks the exit status, and
  increments its success counter unconditionally. It prints
  `Cleaned N orphan directory(ies)` for directories still on disk.

## v3 revision note — what plan-review changed

Four review agents ran. Three findings materially changed the plan; all were verified
first-hand before being accepted.

**1. The Docker-as-root fallback is deferred, not shipped.** v1 proposed it, as the
issue and task ARGUMENTS requested. Three reviewers independently said don't, and the
premise v1 rested on is false:

- **v1's central rebuttal was factually wrong.** v1 argued ADR-081's rejection of
  auto-`rm -rf` ("blind surface + no privilege") didn't apply because "this runs on the
  operator's own machine." It does not only run there.
  `apps/web-platform/server/git-lock-marker-telemetry.ts:3` states verbatim that
  `worktree-manager.sh` runs "**INSIDE the agent sandbox**", and
  `apps/web-platform/server/safe-bash.ts:165-166` names `cleanup-merged` — the verb that
  reaches this reaper — as a write verb running "via the autonomous/sandbox path."
  **ADR-081's blind-surface leg holds for this file.**
- **The remediation hint bypasses a guardrail.** `guardrails:block-rm-rf-worktrees`
  (`.claude/hooks/guardrails.sh:129`) matches `rm -rf … .worktrees/`. Tested both forms:
  plain **MATCHES (blocked)**; docker-wrapped **NO MATCH (bypassed)**. v1 would have
  emitted that command on stdout — the stream it documents as the one agents grep —
  inside the very script the guardrail's deny message names as the safe alternative.
- **`sh -c` with an interpolated basename is shell injection as root.** The loop is
  `for dir in "$WORKTREE_DIR"/*/` — any directory. v1's guards rejected `..`, symlinks,
  and `/`, but not `'`, `;`, `$`, or backtick.
- **The classifier is too weak to justify removing the ownership backstop.** "Not in
  `git worktree list`" + "no `.git` file" is far weaker than ADR-081's falsifiable
  `-type c`. Today an unprivileged `rm` cannot destroy what the operator doesn't own;
  escalation removes that backstop exactly where the classifier is most likely wrong.

v1's own ADR text conceded "the escalation is the convenience, the honesty is the fix."
v3 ships the fix and routes the escalation to a tracking issue with the safe design
recorded. **This departs from stated operator direction, so it is logged as a
User-Challenge in `decision-challenges.md` — the operator decides, not this plan.**
ADR-154 is dropped with it (no substrate ships → no decision to record).

**2. The function this PR rewrites is already broken, one line below the reported bug.**
`cleanup_orphan_worktree_dirs` **returns 1 whenever it removed ≥1 orphan and
`verbose != "true"`**, because the trailing `[[ … ]] && echo` at `:1638` is the last
statement executed. Reproduced in isolation:

```
cleaned≥1, verbose=false -> rc=1      cleaned≥1, verbose=true -> rc=0
```

The script runs `set -euo pipefail` (`:16`) and both call sites (`:1718`, `:1888`) are
bare, inside `cleanup_merged_worktrees`, itself invoked bare at `:2229`. So on the
**default** path — session start, `work` Phase 0, ship Phase 7 Step 4 — a *successful*
orphan removal aborts `cleanup_merged_worktrees` mid-flight, silently skipping
`cleanup_claude_tmp` (`:1891`) and the `/tmp` sandbox reaper. Same defect class as
#7102. v3 fixes it and tests for it; v1 would have preserved it.

**3. v1's headline arithmetic was false.** v1 claimed a 20s budget is "exceeded by the
retry ladder by itself." 14.25s is **71%** of 20s, not more than it. Corrected below —
this matters disproportionately because that sentence was headed into a committed
source comment.

Acceptance criteria are cut from 17 to 9; two of v1's were unrunnable.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / ARGUMENTS) | Reality (verified) | Plan response |
| --- | --- | --- |
| One file affected | **Four** of 21 violate `afterAll ≥ beforeAll`. Only `workspace-member-revocation` has no override; three carry explicit `30_000` under a `60_000` setup. | Fix all 4. |
| Teardown walks 4 tables for both fixtures | Confirmed. `tearDownSharedWorkspace` (`test/helpers/workspace-members-fixtures.ts:145`) is `2M + 2` sequential awaited round-trips per fixture → **11** for this hook, 3 of them `deleteUser`. | Budget justification. |
| (not in issue) | Those 3 run under `withGoTrueRetry` — 5 attempts, backoff `min(4000, 250·2^(n-1)) + jitter·250` (`gotrue-retry.ts:68-71, 83-84`) → **≈14.25s of sleep**, leaving ~5.75s of a 20s budget for 11 remote round-trips. | Corrected arithmetic; goes in the code comment. |
| `tearDownSharedWorkspace` is in `tenant-isolation-teardown.ts` | **False.** That module exports only `tearDownTenantUser` (`:109`). | Correct path used. |
| "EACCES classifier ~line 157" | `_rm_errno()` at `:153-162`. The `LC_ALL=C rm … 2>&1 >/dev/null` **command is `:312`** (`:308-311` are the reset + comments). | Reused with its comment. |
| "Docker runs as root and is already a project dependency" — implying operator-local | **Falsified.** Docker *is* used in tests (`cloud-init-plugin-seed.test.sh:113`), but there is **no precedent for Docker as privilege escalation**, and the surface is not operator-only. | Escalation deferred. |
| Use `alpine:3` | Below convention (`alpine:3.20`, `build-inngest-bootstrap-image.yml:193`); both precedents are Dockerfile `FROM` bases, not a privileged runtime container — that case wants a **digest** pin. | Recorded in the deferral issue. |

## Premise Validation

- `gh issue view 7101` → **OPEN**; `7102` → **OPEN**. Neither closed by a merged PR.
- Line citations re-verified after review found drift: `vitest.config.ts` `hookTimeout`
  is **`:37`** (rationale comment `:30-35`); reaper is **`:1608-1640`**; the `LC_ALL=C`
  command is **`:312`**. Per `cq-cite-content-anchor-not-line-number`, Phase 0 verifies
  by content anchor, not by line number.
- All cited learnings verified present **in this worktree** (not the bare root).
- **ADR-corpus grep for the mechanism:** ADR-081 §Alternatives (ii) rejects auto-`rm -rf`
  on a blind surface. v1 argued the rejection didn't reach this surface; verification
  showed it does. Exactly the rejected-mechanism trap the gate exists to catch.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — internal dev tooling.
Indirect but real: a red `main` from #7101 blocks the merge queue; a lying reaper leaves
an agent believing a worktree was reclaimed; and the rc=1 bug silently skips two tmp
reapers on every default-path run.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector. No
user data, auth, billing, or network-reachable surface. v3 ships **no** privileged
operation.

**Brand-survival threshold:** `none`. The canonical sensitive-path regex (preflight
Check 6 SSOT, `preflight/SKILL.md:478`) returns **zero matches** —
`apps/web-platform/test/server/…` does not match
`^apps/web-platform/(server|supabase|app/api|middleware\.ts$)`, and `plugins/soleur/…`
matches no alternative. No scope-out bullet required.

## Open Code-Review Overlap

62 open `code-review` issues queried against every path in Files to Edit. Two mention
`tenant-isolation`: **#4254** (fixture `template_id` schema drift), **#3272** (`byok.ts`
`authTagLength`). **Both: Acknowledge** — different concerns, neither touches a timeout
literal or a file in scope. Zero overlaps for `worktree-manager.sh`.

---

# Work Target 1 — #7101: teardown budget must be ≥ setup budget

## The measured asymmetry

| File | `beforeAll` | `afterAll` | Status |
| --- | --- | --- | --- |
| `workspace-member-revocation` | 60_000 (:144) | **global 20_000** (:159) | **VIOLATION** — the reported failure |
| `byok-delegation.atomicity` | 60_000 (:271) | **30_000** (:281) | **VIOLATION** |
| `byok-delegations` | 60_000 (:169) | **30_000** (:178) | **VIOLATION** |
| `conversation-visibility` | 60_000 (:155) | **30_000** (:167) | **VIOLATION** |
| 14 others | 30_000 | 30_000 | symmetric — OK |
| `audit-byok-use`, `tenant-jwt-deny` (×2 describes), `tenant-jwt-rls-deny` | global | global | symmetric — OK |

21 files, **22 hook pairs** (`tenant-jwt-deny` has two `describe` blocks). Independently
reproduced byte-identical by a second reviewer.

**Scope decision (explicit).** Files where both hooks sit on the global 20_000 are **not**
changed. The invariant is *symmetry*; they satisfy it. Raising their absolute budget is a
separate judgment, and this PR's thesis is that the asymmetry — not the absolute number —
is the defect.

## Why 60_000, stated correctly

`afterAll` performs **11 sequential awaited remote round-trips**, of which **3** are
`deleteUser` under `withGoTrueRetry`:

```
maxAttempts = 5, baseDelayMs = 250                  (gotrue-retry.ts:83-84)
backoffMs(n) = min(4000, 250·2^(n-1)) + jitter·250   (gotrue-retry.ts:68-71)
  → 250 + 500 + 1000 + 2000 = 3750ms + 4×250 jitter ≈ 4750ms per call
  → × 3 calls ≈ 14.25s of pure sleep
```

Against a 20_000 ms budget that is **71%** consumed by sleep alone, leaving **~5.75s**
for 11 sequential remote round-trips — roughly 520ms each, with zero margin for a slow
dev-Supabase. Under a 60_000 budget the same ladder leaves ~45s. *(v1 claimed the ladder
alone "exceeds" 20s. It does not; the honest number is stronger than the wrong one
because it survives scrutiny.)*

## The invariant the guard enforces, stated honestly

Review caught a real inconsistency: the *number* was chosen by measurement while the
*guard* enforces symmetry. Those are different rules, and v1 didn't notice.

**v3 defends symmetry deliberately, as a proxy chosen for a stated reason.** A guard
enforcing measured budgets would need per-suite round-trip arithmetic no static parser
can do, and would rot the moment a fixture changed. Symmetry is checkable from source,
needs no dev-Supabase access, and encodes a property true of every suite here:
**teardown undoes what setup built, over the same remote, and is therefore never
cheaper.** It is a lower bound, not an estimate — it cannot say 60_000 is enough, only
that 20_000 under a 60_000 setup is indefensible.

Known false-positive: a heavy `beforeAll` with a genuinely trivial `afterAll` would be
told to inflate a budget it doesn't need. Accepted — the cost is one over-large timeout
on a hook that finishes early. The guard's comment must say so, so the next reader
overrides with intent rather than confusion.

## Not in scope

`vitest.config.ts` `hookTimeout: 20_000` (`:37`) is **not** raised. Its comment
(`:30-35`) records it as a deliberate 2× default for pdfjs cold-start across 473 files.
Widening it globally trades a loud, correct failure for a quiet, wrong one — the exact
trade this PR exists to undo.

## The guard

`apps/web-platform/test/tenant-isolation-hook-budget-symmetry.test.ts`

- Collected by the **`unit`** project (`vitest.config.ts:44` includes
  `test/**/*.test.ts`, env `node`) — runs on every CI run, **not** gated on
  `INTEGRATION_ENABLED` or Supabase credentials.
- **Primary rule is structural and needs no global value:** *if `beforeAll` carries an
  explicit override, `afterAll` MUST carry an explicit override ≥ it.* All four of
  today's violations are caught by this rule alone, and it cannot be wrong about what
  the runner's default is. This is the load-bearing assertion.
- The global default is needed only for the residual case (`beforeAll` absent,
  `afterAll` explicit). Read it by **importing** `vitest.config.ts` and reading
  `config.test.hookTimeout`. v1 planned to *parse* it — a second parser with its own
  vacuity risk, and a loose regex would have matched the comment at `:33`, which
  contains the literal text `20_000ms hookTimeout`.
  > **Correction (deepen-plan).** v1/v2 called that module "side-effect-free." **It is
  > not:** `vitest.config.ts:14-15` performs a top-level
  > `process.env.WEBPLAT_TEST_USE_THREADS` read at module-evaluation time. Importing is
  > still safe — it is a *read*, not a mutation, and the `unit` project pins
  > `isolate: true` (`:46-53`) precisely so module-init env reads cannot leak between
  > files sharing a worker. But the justification was wrong, and the import also pulls
  > in `vitest/config` (and thus vite) transitively. If that import proves heavy or
  > brittle at /work time, fall back to a hardcoded `20_000` **plus** a parity assertion
  > against the config — never silently hardcode.
- **Fails against current code with 4 violations.**

### Required guard mechanics

- **Strip `_` before `Number()`.** Every literal is `60_000` / `30_000` / `20_000`.
  `Number("60_000")` is **`NaN`** and `parseInt("60_000")` is **`60`** — both verified.
  Either silently produces a wrong guard, which is precisely the vacuity class below.
- Pair hooks to closers **structurally** (matching indentation), never by grepping the
  literal — `}, 60_000);` also terminates per-*test* timeouts (lines 213, 354 in the
  revocation suite).

### Anti-vacuity requirements

A source parser can pass by parsing nothing —
`2026-07-22-repairing-a-silent-guard-reintroduced-the-guards-own-defect-class-in-the-tests.md`
is exactly this class. Two requirements (v1 had four; two were redundant or
self-defeating):

1. **Coverage floor.** Assert matched files **> 0**, **every** matched file yields ≥ 1
   hook pair, and total pairs ≥ total files. v1's `≥ 20` magic floors were pinned to
   today's census — and a hardcoded 20 tolerates silently losing a file. *(Review argued
   for pinning to 21/22 instead. Declined: detecting a deleted suite is a different
   guard's job, and a census constant reds this one on any legitimate add/remove. The
   floor here exists to catch a **broken parser**, and "every file yields a pair" catches
   that exactly, without a constant to drift.)*
2. **In-suite parser mutation case.** Feed the parser a synthetic asymmetric fixture
   string; assert it reports a violation. This makes "0 violations" distinguishable from
   "matched nothing," and it runs every time — unlike a proof pasted into a PR body.

---

# Work Target 2 — #7102: the reaper must not count what it did not do

## Live reproduction (executed during planning)

Sourced `worktree-manager.sh` inside a throwaway git repo (the sibling suite's pattern —
`cd` into the temp repo *then* `source`, which resolves `GIT_ROOT`/`WORKTREE_DIR` to it),
planted one removable orphan and one made unremovable by `chmod 500` on an inner dir, and
called the reaper. Verbatim output:

```
Removed orphan directory: plain-orphan
rm: cannot remove '…/.worktrees/stuck-orphan/apps/supabase/snippets/deep': Permission denied
Removed orphan directory: stuck-orphan          <-- FALSE
Cleaned 2 orphan directory(ies)                 <-- FALSE (1 was removed)
rc=0
stuck-orphan still on disk? YES
```

Then, after a *successful* clean on the default path:

```
cleaned>=1, verbose=false -> rc=1               <-- aborts the caller under set -e
```

This confirms the fixture design works unprivileged, and surfaces a **third** lying
surface the issue did not name: the per-directory `Removed orphan directory: <name>` line
prints on failure too. The fix moves it inside the success branch, so all three lying
surfaces (per-dir line, counter, summary) are corrected together.

## Three defects, not one

Current code (`worktree-manager.sh:1620-1640`):

```bash
local orphans_cleaned=0
for dir in "$WORKTREE_DIR"/*/; do
  ...
  if [[ ! -f "$dir/.git" ]]; then
    rm -rf "$dir"                                # exit status never checked
    orphans_cleaned=$((orphans_cleaned + 1))     # incremented unconditionally
...
  if [[ $orphans_cleaned -gt 0 ]]; then
    [[ "$verbose" == "true" ]] && echo -e "…Cleaned $orphans_cleaned…"   # :1638
  fi
}                                                                        # :1640
```

1. **The count lies.** `rm -rf` fails; the counter increments anyway.
2. **The summary is verbose-gated** (`:1637-1639`). On the default path the operator sees
   `rm`'s raw stderr with **no summary at all** — the failure is visible only as noise.
3. **The function returns 1 on the default path when it succeeded** (found at review).
   `:1638` is the branch-terminal statement, so `cleaned≥1 && verbose=false` → rc=1.
   Under `set -e` (`:16`) with bare call sites (`:1718`, `:1888`, and
   `cleanup_merged_worktrees` itself at `:2229`), a *successful* removal aborts the
   caller mid-flight, silently skipping `cleanup_claude_tmp` (`:1891`) and the `/tmp`
   sandbox reaper. Verified by isolated reproduction.

## Design — honest reporting, inline

No new functions. With the escalation deferred the whole fix is ~14 lines in the existing
loop, and the sibling idiom at `:312` already has the shape:

```bash
local orphans_cleaned=0
local -a orphans_failed=()
...
# 2>&1 >/dev/null ordering is load-bearing: capture stderr, discard stdout.
# LC_ALL=C pins strerror to English so _rm_errno maps reliably under a
# non-C operator/CI locale (else every failure degrades to OTHER).
if rm_err=$(LC_ALL=C rm -rf -- "$dir" 2>&1 >/dev/null); then
  orphans_cleaned=$(( orphans_cleaned + 1 ))   # assignment form, NOT (( x++ ))
  [[ "$verbose" == "true" ]] && echo -e "${BLUE}Removed orphan: $(basename "$dir")${NC}"
else
  orphans_failed+=("$(basename "$dir")")
  echo "SOLEUR_ORPHAN_UNREMOVABLE dir=$(basename "$dir") errno=$(_rm_errno "$rm_err") \
reason=rm-partial hint=\"root-owned residue (local Supabase bind-mount); directory is \
PARTIALLY deleted — see git-worktree SKILL.md §Sharp Edges\""
fi
...
# Failures print unconditionally; successes stay verbose-gated.
if (( ${#orphans_failed[@]} > 0 )); then
  echo "orphan cleanup: ${#orphans_failed[@]} directory(ies) could NOT be removed: ${orphans_failed[*]}"
fi
if [[ $orphans_cleaned -gt 0 && "$verbose" == "true" ]]; then
  echo -e "${GREEN}Cleaned $orphans_cleaned orphan directory(ies)${NC}"
fi
return 0    # explicit: a trailing `[[ … ]] && echo` would return 1 under set -e
```

Five details that are not cosmetic:

- **`return 0` as the final statement.** This is defect 3. Without it the function's exit
  status is whatever the last conditional evaluated to.
- **The errexit reasoning must be stated precisely.** v1 said the `if … then … else` form
  "makes the question moot." It does not: that form disarms errexit for the **inner
  `rm`**, and says nothing about the **function's own exit status**, which is what the
  bare call sites consume. Two distinct concerns; both need handling.
- **`reason=rm-partial`, not `rm-failed`.** `rm -rf` deletes everything it can before
  hitting EACCES, so the survivor is a hollow shell. `rm-failed` reads as "nothing
  happened" — a silent-success variant of the very bug being fixed.
- **The hint names a doc section, never a raw `docker run`.** Emitting the containerized
  command would publish a verified `guardrails:block-rm-rf-worktrees` bypass onto the
  stream autonomous agents grep.
- **Copy the explanatory comment, not just the idiom.** `:308-311` carries the lines
  explaining redirection order and the locale pin; the idiom is inscrutable without them.

## Test — `plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh`

Auto-collected: `scripts/test-all.sh:572` globs
`plugins/soleur/skills/*/test/*.test.sh`; `want_scripts()` (`:125`) accepts
`TEST_GROUP=scripts`. No registration needed — `lint-orphan-test-suites.sh:28` iterates
only `scripts/*.test.sh`, a different directory.

Harness copied from `stale-lock-sweep.test.sh`: `set -uo pipefail`, `REPO_ROOT` via
`BASH_SOURCE`, `source "$WM"` then `set +e`, `PASS`/`FAIL` counters.

### The unprivileged failure lever — verified by execution

```bash
mkdir -p "$T/wt/orphan/sub/deep"; chmod 500 "$T/wt/orphan/sub"
LC_ALL=C rm -rf "$T/wt/orphan"
# → rc=1, "rm: cannot remove '…/sub/deep': Permission denied", dir survives
```

**Executed during planning as EUID 1001.** Maps through `_rm_errno` to exactly `EACCES`,
the real bug's errno, with **no root and no Docker**.

### Cases

| # | Case | Assertion |
| --- | --- | --- |
| 1 | One temp `WORKTREE_DIR` holding {plain orphan, registered worktree, orphan-with-`.git`}; one invocation | `orphans_cleaned == 1`; the other two survive. One setup, three behaviours. |
| 2 | **RED** — unremovable orphan (`chmod 500`) | `orphans_cleaned == 0`; sentinel on **stdout**; dir survives; **summary prints at `verbose=false`** |
| 3 | Counter integrity | `orphans_cleaned` equals a `find`-verified removal delta |
| 4 | **RED — return code** (defect 3) | rc == 0 for all of: (cleaned≥1, verbose=false), (cleaned≥1, verbose=true), (failed, verbose=false) |

Case 4 is new in v3 and is the only case that catches the rc=1 abort. The harness runs
without `set -e`, so it **cannot** notice the bug incidentally — the return code must be
asserted explicitly.

**Preflights (skip cleanly):**
- `[[ $EUID -eq 0 ]]` → `SKIP`. Root ignores permission bits, so case 2 cannot be
  constructed. A suite that silently passes on a root CI container is exactly the vacuity
  this PR is about.
- Non-GNU `rm` strerror → `SKIP` (mirrors the sibling suite).

**Anti-vacuity parity.** Review noted the shell guard was held to a lower bar than the TS
one: "exits 0 with no `FAIL:`" is satisfied by a skip-everything run. The suite must
therefore assert a **minimum PASS count** before exiting 0, so a preflight `SKIP` cannot
masquerade as coverage.

**Harness self-cleanup.** Case 2 leaves a `chmod 500` directory behind, which defeats the
sibling suites' `trap 'rm -rf "$TMP"' EXIT` idiom — the suite would litter `/tmp` on every
run with directories it cannot remove, reproducing this PR's own bug in its test harness.
`chmod -R u+rwX "$TMP"` before (or at the top of) the trap.

---

## Files to Edit

| Path | Change |
| --- | --- |
| `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` | `afterAll` closer `:159` → `}, 60_000);` + comment with the corrected 11-round-trip / 14.25s-of-20s arithmetic |
| `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts` | `:281` `30_000` → `60_000` |
| `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` | `:178` `30_000` → `60_000` |
| `apps/web-platform/test/server/conversation-visibility.tenant-isolation.test.ts` | `:167` `30_000` → `60_000` |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | honest counting + unconditional failure summary + **explicit `return 0`** in `cleanup_orphan_worktree_dirs` (`:1608-1640`) |
| `plugins/soleur/skills/git-worktree/SKILL.md` | Sharp Edge: root-owned Supabase residue; partial deletion; manual remediation. **Body prose only — no `description:` change, so no skill-budget check fires** |

## Files to Create

| Path | Purpose |
| --- | --- |
| `apps/web-platform/test/tenant-isolation-hook-budget-symmetry.test.ts` | #7101 guard (RED at 4 violations) |
| `plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh` | #7102 suite (RED at cases 2/3/4) |

Two files, not three — ADR-154 drops with the escalation.

**Glob verification:** `apps/web-platform/test/server/*.tenant-isolation.test.ts` → 21
tracked files. `plugins/soleur/skills/*/test/*.test.sh` → the 4 existing git-worktree
suites. Both confirmed against the working tree.

## Implementation Phases

**Phase 0 — Preconditions**
1. Re-run the asymmetry sweep; confirm 4 violations on current `HEAD`.
2. Confirm by **content anchor** (not line number): `_rm_errno()`, the
   `LC_ALL=C rm … 2>&1 >/dev/null` command, and the `[[ "$verbose" == "true" ]] && echo`
   at the tail of `cleanup_orphan_worktree_dirs`.

**Phase 1 — RED for #7101**
3. Write the guard (separator stripping, structural pairing, both anti-vacuity items).
4. Run it. MUST fail listing **exactly 4** violations. A run reporting 0 means the parser
   is broken, not that the code is clean.

**Phase 2 — GREEN for #7101**
5. Apply the 4 timeout edits. Re-run → green, coverage floor still asserting.

**Phase 3 — RED for #7102**
6. Write the suite (4 cases + preflights + minimum-PASS assertion).
7. Run it. Cases 2, 3, **and 4** MUST fail against current code.

**Phase 4 — GREEN for #7102**
8. Apply the inline honest-counting edit **and the explicit `return 0`**. Re-run → green.

**Phase 5 — Docs + deferrals**
9. SKILL.md Sharp Edge.
10. File the three tracking issues below; write `decision-challenges.md`.

**Phase 6 — Exit gate**
11. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
    (**not** `npm run -w …` — the repo root declares no `workspaces` field).
12. `./node_modules/.bin/vitest run test/tenant-isolation-hook-budget-symmetry.test.ts`
13. `bash plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh`
14. `TEST_GROUP=scripts bash scripts/test-all.sh` — catches regressions in the 4 sibling
    git-worktree suites.

## Acceptance Criteria

Nine, down from seventeen. Every one can be failed by a correct-looking but wrong
implementation — the test v1's cut criteria failed.

### Pre-merge (PR)

1. The guard passes and reports **0** violations across all 21 files.
2. The guard runs green in the `unit` project **without** `INTEGRATION_ENABLED` and with
   no Supabase credentials in the environment.
3. **Guard mutation-proof:** reverting one `60_000` to `30_000` makes it fail with
   exactly 1 violation; the in-suite synthetic-fixture case also passes. Recorded in the
   PR body.
4. **Guard coverage floor:** matched files > 0, every matched file yields ≥ 1 hook pair,
   pairs ≥ files — asserted in-suite, no hardcoded census.
5. `orphan-reaper-honest-count.test.sh` exits 0, prints no `FAIL:`, **and reports a PASS
   count ≥ its case count** (so a preflight SKIP cannot masquerade as coverage).
6. **Counter mutation-proof:** restoring the unconditional increment fails case 2 or 3.
   **Return-code mutation-proof:** removing the explicit `return 0` fails case 4. Both
   recorded in the PR body.
7. `TEST_GROUP=scripts bash scripts/test-all.sh` green and
   `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
8. **`tenant-integration-required` is green on the PR.** The 4 edited files match
   `tenant-integration.yml:116`'s changed-path anchor, so the full dev-Supabase suite
   runs; that check going green *is* the deliverable of #7101. *(No v1 AC asserted the
   very check the issue exists to fix.)*
9. The reaper emits no raw `docker run` string, and the failure branch's hint contains
   the anchor `see git-worktree SKILL.md`. *(Anchor stated explicitly rather than
   "verified by reading" — `cq-assert-anchor-not-bare-token`.)*

> **Dropped from v1 and why:** AC2 was unrunnable — `grep -c '}, 60_000);'` returns **3**
> today (lines 144/213/354, since per-test timeouts share the form) and **4** after the
> fix, while asserting 2. AC3 and AC12 used `grep -c`, which **exits 1 when the count is
> 0** (verified), so they failed exactly when satisfied. AC11 (`grep -c
> 'orphans_cleaned++' → 0`) would false-fail against the house comment style the plan
> itself prescribes at `:314`. AC9/AC10 were bare-token greps; the suites prove those
> behaviourally, forever. AC12/AC13/AC16 were Docker/ADR-only. AC17 restates a repo-wide
> workflow gate.

### Post-merge (operator)

None. Code-only, self-verifying in CI; no deploy, migration, secret, or infrastructure.

## Deferrals — tracking issues to file (Phase 5)

Per `wg-when-deferring-a-capability-create-a`, none is left as prose:

1. **EACCES escalation for the orphan reaper, done safely.** Must record: opt-**in**
   default (`SOLEUR_WORKTREE_DOCKER_REAP=1`) — a capability defaulting on wherever a
   daemon answers is the inverse of a boundary; a **code-enforced surface predicate** (not
   a claim about who runs it) using the existing `/workspaces/<id>` discriminator; a
   positive **object-class predicate** identifying the residue (all unremovable paths
   under `<dir>/apps/web-platform/supabase/`) as ADR-081's `-type c` analogue;
   **exec-form `docker run`, no `sh -c`**; positive charset validation
   `^[A-Za-z0-9._-]+$`; **mount the target, not the parent** (`-v "$dir":/target`,
   `find /target -mindepth 1 -delete`, then unprivileged `rmdir` outside — the parent is
   user-owned); **digest** pin; `timeout 5 docker info`; a local-unix-socket assertion
   (`-v` resolves in the *daemon's* namespace); a live-Supabase-stack precondition; a
   distinct `docker-killed-mid-rm` state; the ADR the gate will demand; and a one-line
   pointer from ADR-081 §Alternatives (ii) narrowing it for this surface.
2. **`guardrails:block-rm-rf-worktrees` does not match containerized `rm -rf`.** A
   pre-existing blind spot this investigation surfaced (verified: plain MATCH,
   docker-wrapped NO MATCH). Not widened by this PR — v3 ships no docker form — so fixing
   it here would be unrelated scope.
3. **Producer-side fix — the strongest option, and more tractable than v2 claimed.** The
   residue exists because the local Supabase stack bind-mounts as root. v2 asserted "no
   `supabase stop` path exists under `apps/web-platform/`"; **that is false.**
   `apps/web-platform/package.json:25` defines `"db:stop": "./scripts/supabase-local.sh
   stop"`, which reaches `supabase-local.sh` (`exec supabase … stop`). So a teardown hook
   **already exists** — it simply does no residue cleanup (grep for `snippets` / `rm -rf`
   in that script returns nothing). The fix is therefore an addition to an existing stop
   path, not a new lifecycle: remove the root-owned `supabase/snippets` residue while the
   stack's own privileged context is still available. That kills the class at the
   component that owns the artifact and needs no escalation anywhere.

## Observability

```yaml
liveness_signal:
  what: "cleanup_orphan_worktree_dirs prints a summary whenever it removed or failed to
         remove an orphan. Failures print unconditionally; successes stay verbose-gated."
  cadence: "session start, `work` Phase 0, ship Phase 7 Step 4 (`cleanup-merged`)"
  alert_target: "the orchestrating agent's stdout capture; operator sees it in-session"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

error_reporting:
  destination: "SOLEUR_ORPHAN_UNREMOVABLE … on STDOUT, plain and color-free"
  fail_loud: true
  layer_citation: "This surface includes the agent sandbox AND the operator's local
    machine — NOT a server. Sentry and Better Stack are not reachable observability
    layers for it. The wired layer is the stdout sentinel the orchestrating agent greps;
    the script documents the choice at :218-219 (stdout because 'stderr is invisible
    under `claude --bg`'), and ADR-081 §Observability records the same constraint for the
    sibling SOLEUR_GIT_LOCK_* markers."

failure_modes:
  - mode: "rm -rf partially completes then fails (root-owned Supabase residue)"
    detection: "_rm_errno classifies captured stderr → EACCES"
    alert_route: "SOLEUR_ORPHAN_UNREMOVABLE … errno=EACCES reason=rm-partial"
  - mode: "reaper returns non-zero after a successful removal, aborting the caller
           mid-flight and skipping the tmp reapers (defect 3)"
    detection: "orphan-reaper-honest-count.test.sh case 4 asserts rc == 0 across the
                verbose/cleaned/failed matrix"
    alert_route: "CI red in the test-scripts shard"
  - mode: "hook-budget asymmetry reintroduced in a new/edited tenant-isolation suite"
    detection: "tenant-isolation-hook-budget-symmetry.test.ts in the `unit` project"
    alert_route: "CI red on the web-platform test job, every PR, not gated on dev-Supabase"

logs:
  where: "session stdout / agent transcript; no persistent sink (local + sandbox surface)"
  retention: "session lifetime"

discoverability_test:
  command: |
    bash plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh
  expected_output: "SOLEUR_ORPHAN_UNREMOVABLE dir=… errno=EACCES reason=rm-partial …"
```

No `ssh` appears in any command above.

**Soak enrollment: not applicable.** No acceptance criterion is time-gated. #7101 is
proven by the guard at merge time — the point of adding a guard rather than declaring
victory on a flake that stopped happening.

## Architecture Decision (ADR/C4)

**No ADR ships, because no architectural decision ships.** v1 proposed ADR-154 for the
privileged-fallback substrate; with that deferred, v3 changes four integer literals, a
counter, a return statement, and adds two test files. That is not architecture. The ADR
gate fired correctly on v1 — and read backwards, its firing was the signal that a
two-issue bug fix had grown a second feature.

The ADR-081 reconciliation is not lost: it is recorded in deferral issue 1, so whoever
ships the escalation inherits both the finding and the required ADR-081 pointer.

**C4 impact: none.** All three model files were read, not grepped. The founder actor is
already modeled (`model.c4:8`); `.worktrees/` is not a modeled store (modeled stores are
`supabase`, `gitDataStore`, `sessionStore`, `workspacesVolume`, `inngestPostgres`,
`inngestRedis`); no external system is added (v3 introduces no Docker Hub pull); no
actor↔surface access relationship changes; no `view … include` line is affected. On
ADR-081's own precedent, this is "an internal filesystem-substrate maintenance step
within already-modeled containers."

## Domain Review

**Domains relevant:** Engineering.

**Engineering (CTO lens).** Pure dev-infra. No product surface, user data, revenue,
legal, or marketing artifact. v1's one architecturally-weighty decision is deferred; v3
carries no privileged operation and no novel substrate.

**Product/UX Gate: NONE.** The mechanical UI-surface override does not fire — no path
matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface
glob. `ux-design-lead` correctly not invoked.

**Gates skipped, with reasons:** GDPR (2.7) — no regulated surface, none of triggers
(a)-(d). IaC (2.8) — no infrastructure. Encryption posture (2.11) — detection globs match
nothing; no store, no new connection. Skill-budget (1.8) — SKILL.md edit is body prose.
Network-outage checklist (1.4) — "timeout" here is a test-runner hook budget, not network
reachability; no host or firewall in the causal chain. Functional-overlap / community
discovery (1.5, 1.5b) — fixes existing first-party code; no new capability an external
registry could supply; bash + vitest fully covered.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| 60_000 masks a genuinely-hung teardown | Bounded: matches setup, justified by measured arithmetic, and the global `hookTimeout` stays 20_000 for every other hook in 473 files. |
| The guard passes vacuously | Coverage floor + in-suite parser mutation case + `_`-stripping (`Number("60_000")` is `NaN`). |
| Symmetry over-constrains a cheap teardown | Known and accepted; documented in the guard's comment so the next reader overrides with intent. |
| The bash suite passes vacuously as root in CI | `EUID == 0` → `SKIP` preflight **plus** a minimum-PASS-count assertion, so a skip-everything run cannot satisfy AC5. |
| `set -e` abort from the counter | Assignment form (`:314` documents the `(( x++ ))` trap). |
| `set -e` abort from the function's own rc | Explicit `return 0` — the inner-`rm` `if` form does **not** address this; two distinct concerns. |
| `_rm_errno` misclassifies under a non-C locale | `LC_ALL=C` pin copied from `:312` with its comment. |
| Operator reads `rm-partial` as "nothing happened" | That is why it is `rm-partial`, and why SKILL.md documents the hollow-shell state. |
| The orphan keeps recurring (no escalation) | Accepted and honest: the sentinel names it every run with a doc pointer. Converting a silent lie into a correct, actionable nag **is** the fix; the escalation was always the convenience. |

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Raise global `hookTimeout` to 60_000 | **Rejected** — masks hung hooks across 473 files to fix 4. |
| Fix only the one file the issue named | **Rejected** — the sweep found 4. |
| Also raise the 3 symmetric-at-20_000 files | **Rejected as scope creep**, recorded rather than silently omitted. |
| Guard as a shell/CI lint | **Rejected** — vitest already has the file list, config, and CI wiring. |
| Pin guard floors to 21 files / 22 pairs | **Rejected** — a census constant reds the guard on any legitimate add/remove; "every file yields a pair" catches parser breakage without a constant. |
| **Ship the Docker escalation in this PR (v1's design)** | **Rejected** — surface premise falsified, guardrail bypass, `sh -c` injection, weak classifier. Deferred with a safe design recorded. **Contradicts operator direction → logged as a User-Challenge.** |
| `mv` orphan to quarantine | **Rejected** — works unprivileged but trades one residue for another; no disk reclaimed. |
| `sudo rm -rf` | **Rejected** — `hr-the-bash-tool-runs-in-a-non-interactive`: no sudo, no TTY. |
| Producer-side teardown in the local Supabase stack | **Not rejected — deferred as issue 3.** Kills the class at the component that owns the artifact. The strongest long-term answer, absent from v1. |

## Sharp Edges

- **Run each guard and observe it RED before its fix.** A guard first run *after* the fix
  cannot distinguish "clean" from "matched nothing." Phases 1 and 3 exist for this and
  must not be folded into 2 and 4.
- **A trailing `[[ … ]] && echo` is a return statement.** As the last statement of a
  function or branch it sets the exit status, and under `set -e` a bare caller aborts.
  This is defect 3 — it was live in this exact function. End such functions with an
  explicit `return 0`.
- **`if f; then` disarms errexit inside `f`, not for `f`'s own exit status.** The two are
  routinely conflated; v1 conflated them.
- **`(( orphans_cleaned++ ))` aborts under `set -e`** when the old value is 0. Use the
  assignment form; the file documents this at `:314`.
- **`Number("60_000")` is `NaN` and `parseInt("60_000")` is `60`.** Strip `_` before
  parsing any numeric-separator literal, or the guard is silently wrong.
- **`2>&1 >/dev/null` is not `>/dev/null 2>&1`.** The first captures stderr and discards
  stdout. Copy the comment at `:308-311`, not just the idiom.
- **`grep -c` exits 1 when the count is 0.** Never write an AC whose pass condition is a
  zero count without `! grep -q` or an explicit `-eq` comparison — v1 shipped two.
- **`}, 60_000);` is not a hook-timeout marker.** Per-test timeouts share the form (lines
  213, 354 in the revocation suite). Pair hooks to closers structurally, never by grep.
- **A plan's surface claim about a script is a claim to verify, not assume.** v1 asserted
  `worktree-manager.sh` "runs on the operator's own machine" and built an entire
  privileged mechanism on it; `git-lock-marker-telemetry.ts:3` says it runs inside the
  agent sandbox. One grep would have collapsed the design before it was written.
- **"Side-effect-free" and "no teardown exists" are negative claims — grep them.** v2
  asserted `vitest.config.ts` was side-effect-free (it reads `process.env` at module
  scope, `:14-15`) and that no `supabase stop` path existed (it does,
  `apps/web-platform/package.json:25`). Both were caught only by a dedicated
  verify-the-negative sweep. A negative claim in a plan is the cheapest thing to check
  and the easiest to assert from memory.

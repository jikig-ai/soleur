---
title: "chore: reconcile the AGENTS rule-budget rubric with the linter (single source of truth + firing gate)"
issue: 6461
branch: feat-one-shot-6461-rule-budget-rubric-linter-drift
lane: cross-domain
type: chore
brand_survival_threshold: none
date: 2026-07-20
---

# chore: reconcile the AGENTS rule-budget rubric with the linter

`Closes #6461`

## Enhancement Summary

**Deepened on:** 2026-07-20
**Agents used:** architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer,
claim-verification sweep (14 claims, all CONFIRMS), learnings scan.

### Key improvements from the deepen pass

1. **The originating file would have exited the sync graph (P0).** After FR1 strips step 8's
   literals, `compound/SKILL.md` was covered only by one-time PR-time greps — snapshots, not
   invariants. Nothing stopped a future agent re-adding threshold prose or deleting the invocation,
   *which is exactly how #6461 happened*. Added FR4b: the guard now asserts the file as a standing
   invariant.
2. **The `emit_incident` telemetry block sits inside the replaced span (P0).** It was not in FR2's
   retention list. Dropping it would zero telemetry for `cq-agents-md-why-single-line` and make
   Deferral 2's metric permanently unanswerable. Now explicitly retained + asserted.
3. **`MAX_ALWAYS_LOADED_BYTES` has TWO use sites, not one.** The original plan saw only the LLM
   prompt hint; the constant is also the **post-apply hard gate** that reverts an applied diff
   (`git checkout -- .`) and mirrors to Sentry. FR5 now splits the conflated constant by job.
4. **`2>&1` is load-bearing.** `[WARN]`/`[REJECT]` print to **stderr**; only `[OK]` to stdout. The
   tree is in the WARN tier, so the un-redirected invocation yields **empty stdout, exit 0** — an
   agent would capture nothing and see no signal.
5. **Tier remap.** Old CRITICAL (`>22000`) guidance re-attached to the linter's **WARN** tier, not
   REJECT — at 22900 bytes WARN is the tier an agent actually observes, and REJECT means the commit
   is already blocked.
6. **A sixth site, currently correct but ungated.** `plan/SKILL.md:939` carries the right number
   *today* plus the same raw-`wc -c` method bug — "currently correct" is not "gated". Added to the
   guard.
7. **AC grep patterns were blind in both directions.** Digit-only patterns miss the `(22k)`, `18k`
   and `21,949` prose forms in the tree (false pass), while whole-file negative greps false-*fail*
   on the retained `emit_incident` snippet's `~600 bytes`. Both fixed via AC-shape rules.
8. **Enabled-state verified, not assumed.** `promotion-config.yml` is `enabled: true` (since
   2026-07-06, #6039), cron `0 0 * * 0`, registered — so the dead-path is live and firing weekly.
9. **Headroom corrected 100 B → ≈27 B.** The promoters measure raw bytes (22973), not the linter's
   frontmatter-stripped 22900.
10. **Simplification applied:** guard is table-driven (one loop, not five bespoke assertions), test
    suite sized to the code, and ~9 ceremony/identity ACs cut.

## Overview

`plugins/soleur/skills/compound/SKILL.md` step 8 restates the AGENTS always-loaded byte budget as
`warn > 18000 / critical > 22000`, and claims the commit-gate linter "rejects at > 22000". Both are
false. `scripts/lint-agents-rule-budget.py` warns at `>= 20000` and rejects at `> 23000`.

Empirical investigation found the drift is **wider than the issue reported** and includes one
**live production dead-path**, not just stale prose. The root cause is a single un-swept commit.

**Root cause.** Commit `d475c4e46` ("chore(agents): trim AGENTS B_ALWAYS -15% and wire budget linter
into CI (#4601)", issue #4599) raised `B_ALWAYS_REJECT` 22000 → 23000. It updated
`scripts/lint-agents-rule-budget.py`, its test, and `deepen-plan/SKILL.md` — but **not**
`compound/SKILL.md`, **not** `scripts/compound-promote.sh`, **not** the Inngest cron, and **not** the
compound-promote runbook. The threshold was duplicated across five artifacts in four languages with
no gate asserting they agree.

**Deliverable.** Make the linter's constants the single source of truth, extend the *existing*
`scripts/lint-agents-compound-sync.sh` guard to enforce agreement across every restatement site, and
wire that guard into CI (it is currently lefthook-only, so a `--no-verify` commit bypasses it).

## Measurement (empirical, 2026-07-20, this worktree)

All numbers below were produced by running the code, not by trusting the issue body.

### Always-loaded payload — **under budget, no pruning required**

```
$ python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
[WARN] B_ALWAYS=22900 >= 20000 (AGENTS.md=6072 + AGENTS.core.md=16828).
       Approaching the 23000-byte harness ceiling.
exit=0
```

| Metric | Value | Note |
|---|---|---|
| `AGENTS.md` (index, every turn) | **6072 B** | raw; loaded via `@AGENTS.md`, unstrippable |
| `AGENTS.core.md` (every SessionStart) | **16828 B** | frontmatter-**stripped** (loaded bytes) |
| `AGENTS.core.md` raw on disk | 16901 B | 73 B of `last_reviewed`/`review_cadence` frontmatter |
| **`B_ALWAYS`** | **22900** | **WARN tier, exit 0 — 100 B under the 23000 reject** |
| `B_ALWAYS` by the rubric's own method | 22973 | rubric uses raw `wc -c`; **overstates by 73 B** |
| Registry total (`B_TOTAL`) | 43513 B | issue said 42142 |
| Registry rule count | **202** | issue said 198 |
| Longest rule body | **600 B** | exactly at the `PER_RULE_CAP` |
| Retired rule IDs | 58 | `scripts/retired-rule-ids.txt` |

**Consequence for scope:** `B_ALWAYS = 22900 ≤ 23000`. The payload is **not** over the real
threshold. Per the issue's own instruction ("If the current payload is genuinely over the real
threshold, do the minimum demote/prune needed"), **no demotion and no pruning is in scope.** No
`AGENTS*.md` file is edited by this PR (see Sharp Edge 1 for why that is load-bearing).

### `rules_unused_over_8w` — the issue's "98/198" is a category error

```
$ bash scripts/rule-metrics-aggregate.sh
rule-metrics: 0 rule-carrying incident lines; leaving committed .../rule-metrics.json unchanged.
exit=0
```

The aggregator **no-ops in a worktree**: `.claude/.rule-incidents.jsonl` is an operator-machine-local
telemetry log and does not exist here (this is the documented #6042 no-op path, and per ADR-091
compound is the authoritative local producer). The figure therefore cannot be re-measured in this
worktree; the committed artifact stands:

```json
{ "total_rules_tagged": 101, "rules_unused_over_8w": 98, "rules_bypassed_over_baseline": 0 }
```

Two corrections to the issue's framing:

1. The denominator is **101 tagged rules, not the 202-rule registry.** "98/198" compares an
   unused-count against a registry size those two numbers do not share. The real ratio is 98/101.
2. 98/101 unused is at least as consistent with **"telemetry is barely being recorded"** as with
   "half the rules are dead weight" — the incidents log is per-machine and absent here. Treating 98
   as a mandate to prune ~half the registry would be acting on an unvalidated inference.

This reinforces the scope decision: **no pruning in this PR.** A pruning campaign needs a trustworthy
denominator first, which is filed as a follow-up.

### The gate DOES fire — "the more urgent half" is already satisfied

The issue flagged confirming the gate as the more urgent half. It is wired in **three** places and
genuinely rejects:

| Surface | Anchor | Fires on PRs? |
|---|---|---|
| lefthook pre-commit | `lefthook.yml` job `rule-budget-lint`, glob `AGENTS*.md` + self-glob of the linter | pre-commit only |
| **CI (required check)** | `scripts/test-all.sh` → `run_suite "scripts/lint-agents-rule-budget-live"` + `-unit`, run by `.github/workflows/ci.yml` job `test-scripts`, aggregated into the required `test` check on ruleset 14145388 | **yes — blocks merge** |
| Grok fidelity gate | `plugins/soleur/scripts/grok-fidelity-gate.sh` | yes |

Reject behaviour proven by the existing unit suite (all 20 cases pass):

```
$ bash scripts/lint-agents-rule-budget.test.sh
PASS: T2 byte-budget reject exit 1
PASS: T2 B_ALWAYS > 23000 reported
Total: 20  Pass: 20  Fail: 0
```

`lefthook` is installed at `/usr/bin/lefthook`. **No fix needed for the budget gate.** However, the
*sync* guard that would have caught this drift is CI-blind — see FR4.

## Research Reconciliation — Issue claims vs. codebase reality

| Issue claim | Reality | Plan response |
|---|---|---|
| Linter rejects at 23000 | ✅ Correct — `B_ALWAYS_REJECT = 23000`, reject on `>` | Rubric corrected to match |
| Rubric says CRITICAL > 22000 | ✅ Correct, and also `warn > 18000` (a second stale tier) | Both removed via delegation to the linter |
| `always-loaded total: 22757` | Stale. Now **22900** (stripped) / 22973 (raw) | Actuals reported in PR body |
| `registry total: 42142 / 198 rules` | Stale. **43513 / 202 rules** | Actuals reported |
| `rules_unused_over_8w = 98` of 198 | 98 of **101 tagged**; aggregator no-ops in worktree | Reframed; pruning descoped |
| "confirm the gate is actually firing" | Fires in lefthook **and CI**; T2 proves exit 1 | Confirmed, no fix needed |
| Payload is over the CRITICAL threshold | **False** against the real 23000 threshold (22900) | **No demote/prune in scope** |
| Drift is confined to the rubric | **False** — 5 sites, incl. a live cron dead-path | Scope extended (see below) |

## The full drift inventory

`scripts/lint-agents-rule-budget.py:74-76` is the authority:
`B_ALWAYS_WARN = 20000`, `B_ALWAYS_REJECT = 23000`, `PER_RULE_CAP = 600`.

| # | Site | States | Status |
|---|---|---|---|
| — | `scripts/lint-agents-rule-budget.py` | 20000 / 23000 / 600 | ✅ **AUTHORITY** |
| — | `AGENTS.docs.md` `cq-agents-md-why-single-line` | `≤20000 warn / ≤23000 critical (#4599)` | ✅ correct — **not edited** |
| 1 | `compound/SKILL.md` "Commit-gate:" line | `rejects at > 22000` | ❌ **DRIFT** — falsely describes the linter |
| 2 | `compound/SKILL.md` output template | `warn > 18000 / critical > 22000` | ❌ **DRIFT** (both tiers) |
| 3 | `compound/SKILL.md` `B_CORE=$(wc -c ...)` | raw bytes | ❌ **WRONG METHOD** (+73 B vs loaded) |
| 4 | `compound/SKILL.md` CRITICAL text | `sed -n '88,115p' session-rules-loader.sh` | ❌ **STALE ANCHOR** — real block is ~167-190 |
| 5a | `cron-compound-promote.ts:61,433` — **prompt hint** | `MAX_ALWAYS_LOADED_BYTES = 18000`, labelled "the warn cap" | ❌ **DRIFT — LIVE** |
| 5b | `cron-compound-promote.ts:580-587` — **post-apply hard gate** | same constant; `postBytes > cap` → Sentry mirror + `git checkout -- .` **revert** | ❌ **DRIFT — LIVE** |
| 6 | `scripts/compound-promote.sh:159,174` | `ALWAYS_LOADED_CAP=18000`, same "warn cap" label | ❌ DRIFT (operator-local driver) |
| 7 | `scripts/compound-promote.test.sh:341-343` | asserts `9:18000` | ❌ DRIFT (mirrors #6) |
| 8 | `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md:95` | `18000-byte warn / 22000-byte critical` | ❌ DRIFT (prose) |
| 9 | `plugins/soleur/skills/plan/SKILL.md:939` | `23000-byte critical cap` + `B_ALWAYS = $(wc -c …)` | ⚠️ **VALUE CORRECT, UNGATED** — and carries the same raw-`wc -c` method bug as site 3 |

**Site 5 is two use sites, not one** (found at architecture review; the original inventory saw only
the prompt). The same constant is both the *proposal hint* the LLM is told to respect (line 433) and
the *post-apply hard gate* that reverts an applied diff and mirrors to Sentry (lines 580-587). Those
are semantically different jobs and must not share one constant — see FR5/TR5.

**Site 9 is the "currently correct is not gated" case.** `plan/SKILL.md:939` states the right number
today but is excluded from every guard, so it drifts on the next bump exactly as `compound/SKILL.md`
did — the identical failure mode this PR exists to prevent. It is therefore added to FR4's assertion
set. Its raw-`wc -c` measurement bug is corrected in the same edit.

Scoped **out** (dead migration tooling, filed as follow-up): `tools/migration/split-sidecars.sh`
(`target ≤ 18000`), `tools/migration/classify-rules.sh` (`core_ok … <= 18000`).
Scoped **out** (point-in-time historical records, correctly frozen): `knowledge-base/**/learnings/`,
`**/brainstorms/`, **`knowledge-base/project/specs/**` and `knowledge-base/project/plans/**`
(~15 spec/session-state files restate 18000/22000; this plan file itself necessarily quotes every
stale value it is fixing), `**/archive/**`, ADR-094, ADR-129, and `deepen-plan/SKILL.md` (which
*narrates* "raised reject 22000→23000" as history rather than asserting a current threshold).
Enumerated explicitly so a reviewer running `git grep 22000` does not read the sweep as incomplete.

### Site 5 is a production capability outage

`cron-compound-promote.ts` computes `alwaysLoadedNow` from live bytes and injects it into the
clustering LLM's prompt:

> `Current always-loaded payload … is ${alwaysLoadedNow} bytes; the warn cap is ${MAX_ALWAYS_LOADED_BYTES} bytes. For agents-core targets, REFUSE the cluster if ${alwaysLoadedNow} + your byte_impact.delta exceeds ${MAX_ALWAYS_LOADED_BYTES}`

With `alwaysLoadedNow ≈ 22973` and the cap at `18000`, the predicate `22973 + delta > 18000` is
**unconditionally true for every delta ≥ 0**. The `agents-core` promotion tier has therefore been
refusing 100% of clusters since `B_ALWAYS` first crossed 18000 — a silent, unmonitored outage of the
ADR-027 self-modifying-cron capability, caused by the same un-swept constant.

**Enabled-state verified, not merely assumed** (per the `2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state`
learning, whose second half is exactly this trap — that learning was itself written about *this*
loop being silently `enabled: false`):

| Probe | Result |
|---|---|
| `knowledge-base/project/promotion-config.yml` | **`enabled: true`** — "Enabled 2026-07-06 (#6039) — operator dogfood" |
| Cron schedule (`cron-compound-promote.ts`) | `{ cron: "0 0 * * 0" }` — weekly, Sun 00:00 UTC |
| Registered | `apps/web-platform/app/api/inngest/route.ts` (`cronCompoundPromote`), `server/inngest/cron-manifest.ts` |
| Gate in handler | reads `promotion-config.yml`; `if (!config.enabled)` early-returns |

So the loop is **live and firing weekly**, and has been since the operator deliberately enabled it
for dogfooding on 2026-07-06. Every tick since has had its `agents-core` tier structurally refuse
every cluster. This is a current bug with operator-visible impact, not a latent one.

**Precision:** only the **`agents-core` tier** is affected. The `skill` tier (promotions targeting
`plugins/soleur/skills/<name>/SKILL.md`) is not gated by this cap and works normally. Do not
describe the loop as wholly dead.

**Honesty note (load-bearing, carried into the PR body):** correcting `18000 → 23000` restores
*correct* behaviour, **not** capacity. The cron measures raw bytes (22973) against the new 23000
cap, leaving **≈27 B** of headroom — so the promoter will still refuse essentially every
`agents-core` cluster, but now for the right reason, and it self-heals the moment a trim lands.
Do **not** describe this fix as "re-enabling promotion". The capacity restoration is the trim
campaign, which is out of scope and filed as Deferral 1.

## Design: single source of truth

The issue asks to "prefer a single source of truth over duplicated magic numbers". Three mechanisms
were considered; the repo already contains the right precedent.

**Chosen: the Python linter's constants are the source of truth; the existing
`scripts/lint-agents-compound-sync.sh` guard is extended to enforce agreement; the rubric stops
restating numbers at all and instead invokes the linter.**

`scripts/lint-agents-compound-sync.sh` already exists and already guards this exact file pair
(`AGENTS*.md` ↔ `compound/SKILL.md`) using a grep-stable sentinel-comment extraction, with a header
comment explicitly citing symbol-anchoring over line numbers. Extending it is strictly cheaper than
inventing a new mechanism, and it matches the established repo pattern from
`plugins/soleur/test/kb-search-lockstep.test.sh`: *"the executable is the source of truth; the
SKILL.md must quote the same bytes."*

Delegating the rubric's computation to the linter collapses **four** drift axes at once (sites 1, 2,
3 and the `(22k)` prose) because the linter already performs the frontmatter-stripped measurement
correctly.

### Alternatives considered

| Alternative | Verdict |
|---|---|
| New shared `agents-budget-thresholds.json` consumed by Python + TS + Bash + tests | Rejected. The decisive argument is not "cheaper" — it is that a shared JSON would put a **config read on the promotion execution path**, adding a runtime failure mode (missing/malformed file inside the Hetzner container) to remove a *static* comparison problem a lint already solves at zero runtime cost. Compile-time agreement enforced by a linter strictly dominates runtime coupling here. **Reconsideration trigger:** when a consumer must *branch on* the value rather than merely compare against it. (The earlier "if a 4th consumer appears" trigger was already tripped — there are six sites — and is replaced as unfalsifiable.) |
| Add `--print-thresholds` / `--json` to the linter | Rejected — no `--print-thresholds` pattern exists anywhere in the repo; the TS cron would need a runtime `python3` shell-out that is fragile in the Hetzner container (Dockerfile installs no python). |
| Fix the four numbers, add a regression test, change nothing structural | Rejected — satisfies the letter of the issue but leaves five independent copies of the same magic number, which is precisely the failure mode that produced this issue. |

## Functional Requirements

- **FR1 — Rubric delegates instead of restating.** `compound/SKILL.md` step 8's **tier-decision
  logic** MUST NOT contain threshold literals or a hand-rolled `B_ALWAYS` computation. It MUST
  invoke the linter and quote its verdict line. Implementation location:
  `plugins/soleur/skills/compound/SKILL.md`, the block anchored on `8. **Rule budget count.**`
  through the `B_TOTAL is informational only` paragraph.

  **The invocation MUST redirect stderr — this is load-bearing, not cosmetic:**

  ```bash
  cd "$(git rev-parse --show-toplevel)" && \
    python3 scripts/lint-agents-rule-budget.py \
      AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1
  ```

  Verified empirically: `[WARN]` and `[REJECT]` are printed to **stderr**; only `[OK]` goes to
  stdout. The tree is currently at `B_ALWAYS=22900` → WARN tier → **stdout is empty and exit is 0**.
  Without `2>&1` an agent following step 8 captures nothing and sees no error signal — the tier the
  repo actually lives in is precisely the one that produces a silent empty result. The
  `cd "$(git rev-parse --show-toplevel)"` is required because the linter takes bare relative paths
  and step 8 may run from any CWD.

  **Degrade path required (FR1b).** Step 8 already handles a missing/erroring aggregator without
  failing the phase; the linter invocation MUST get the same treatment, because `compound` is a
  **distributed plugin skill that also runs against consumer repos** where `scripts/lint-agents-rule-budget.py`,
  `python3`, and the four-file `AGENTS.*` split may all be absent. Wrap in an existence check and
  define behaviour for: linter absent, `python3` absent, linter exit 2 (`AGENTS.md missing`), and
  linter exit 1 on malformed frontmatter — the last two emit **no** `[OK]/[WARN]/[REJECT]` line at
  all, so the agent must be told what to do when the verdict line is missing rather than left to
  improvise.

- **FR2 — Non-duplicative content retained.** These MUST survive the step-8 rewrite:
  1. Registry statistics the linter does not compute: `B_TOTAL`, rule count `A`, longest rule `L`,
     constitution count `C`.
  2. The `<!-- rule-threshold: 115 -->` sentinel (already guarded by `lint-agents-compound-sync.sh`).
  3. **The `emit_incident cq-agents-md-why-single-line applied` telemetry block** (currently inside
     the replaced span). This is the producer that writes `.claude/.rule-incidents.jsonl`, which
     `rule-metrics-aggregate.sh` consumes to compute `rules_unused_over_8w` — the very metric
     Deferral 2 depends on, and which ADR-091 names `compound` authoritative for. Dropping it would
     silently zero telemetry for this rule and make Deferral 2 permanently unanswerable.
     Note its snippet legitimately contains the string `~600 bytes`; see FR6's AC-shape rule.

- **FR3 — Remediation guidance preserved, re-tiered, and de-staled.** Three parts:
  1. **Both tiers' guidance survives.** The old CRITICAL-tier prose (retire via
     `scripts/retired-rule-ids.txt`; only `wg-*` may be demoted, never `hr-*`, per CPO sign-off
     PR #3496; preserve per-issue mechanism labels when trimming `**Why:**` lines) AND the old
     WARNING-tier prose (apply the placement gate, discoverability litmus, route already-enforced
     and domain-scoped insights to a skill/agent rather than `AGENTS.core.md`) MUST both be retained.
  2. **Tier remap — the guidance must attach where it will actually fire.** Old CRITICAL was
     `> 22000`; the tree sits at 22900, which is **WARN** under the linter's scheme. Attaching the
     shrink/demote guidance solely to the linter's REJECT tier would make it effectively unreachable
     — REJECT means the commit is already blocked. Therefore the old-CRITICAL remediation prose maps
     onto the linter's **WARN** tier (alongside the old-WARNING prose), and the REJECT tier carries
     the hard-stop framing. Getting this backwards ships guidance that never reaches an agent.
  3. **De-stale the citation.** Replace `sed -n '88,115p' .claude/hooks/session-rules-loader.sh`
     (the class-selection block is actually at ~167-190) with a content anchor —
     `grep -n 'DOCS_RE=' -A 25 .claude/hooks/session-rules-loader.sh` — per
     `cq-cite-content-anchor-not-line-number`. Also remove the `(22k)` prose form, which is a
     threshold restatement that survives a digit-only grep.
- **FR4 — Sync guard extended (table-driven) and CI-wired.**
  `scripts/lint-agents-compound-sync.sh` MUST extract `B_ALWAYS_REJECT` and `B_ALWAYS_WARN` from
  `scripts/lint-agents-rule-budget.py` by symbol anchor, then assert every consumer site agrees via
  a **single table-driven loop** — one array entry per site, not one bespoke assertion per site, so
  adding a future site is one line rather than a new function + new test + new AC:

  ```bash
  # site-spec: <file>|<extract-regex>|<expected-symbol>
  SITES=(
    "apps/web-platform/server/inngest/functions/cron-compound-promote.ts|MAX_ALWAYS_LOADED_BYTES = ([0-9]+)|REJECT"
    "apps/web-platform/server/inngest/functions/cron-compound-promote.ts|PROPOSE_ALWAYS_LOADED_BUDGET = ([0-9]+)|WARN"
    "scripts/compound-promote.sh|ALWAYS_LOADED_CAP=([0-9]+)|REJECT"
    "scripts/compound-promote.sh|PROPOSE_ALWAYS_LOADED_BUDGET=([0-9]+)|WARN"
    "AGENTS.docs.md|([0-9]+) critical|REJECT"
    "AGENTS.docs.md|([0-9]+) warn|WARN"
    "AGENTS.docs.md|cap at ~([0-9]+) bytes|PER_RULE_CAP"
    "plugins/soleur/skills/plan/SKILL.md|([0-9]+)-byte critical cap|REJECT"
    "plugins/soleur/skills/plan/SKILL.md|per-rule ([0-9]+)-byte cap|PER_RULE_CAP"
  )
  ```

  Requirements on the loop:

  - **(a) Fail-closed on empty extraction.** An extraction yielding an empty value is a hard
    failure (exit non-zero), never a silent pass. Same for a **missing target file** — emit a
    diagnostic naming the absent path rather than a bare `grep: No such file`.
  - **(b) Accumulate, then report.** The guard currently uses `set -euo pipefail` with an early
    `exit 1` on first mismatch. It MUST instead collect **every** mismatch, print all per-site
    diagnostics (file, expected, found), and exit non-zero once at the end. Without this, a
    linter-only bump reports one site and hides the other four.
  - **(c) Unit is named in the diagnostic.** Consumer sites measure **raw** bytes while the linter's
    threshold is defined over **frontmatter-stripped** bytes (see TR5). The guard asserts constant
    equality, not measurement-basis equality — so its diagnostic MUST state the unit, or a green
    guard silently certifies a comparison performed in the wrong unit. A green guard over an
    unstated unit mismatch is worse than no guard, because it retires the suspicion.
  - **(d) ASCII-safe extraction patterns.** Anchor the `AGENTS.docs.md` entries on
    `[0-9]+ warn` / `[0-9]+ critical`, not the multibyte `≤`, per
    `cq-regex-unicode-separators-escape-only` and to avoid locale-dependent `grep`.
  - **(e) Numbers, not prose.** The `AGENTS.docs.md` entries assert **extracted numbers**, so a
    reword of `cq-agents-md-why-single-line` does not false-fail the guard.
  - **(f) Resolve paths from the repo root** via `git rev-parse --show-toplevel`, since
    `test-all.sh` and lefthook invoke from different working directories, and the guard now reads
    across the `apps/web-platform/` package boundary.
  - **(g) `PER_RULE_CAP` IS asserted.** `600` is restated in `AGENTS.docs.md` and in
    `compound/SKILL.md`'s `L > 600` branch, so it is a real fifth restatement, not dead code. Add
    site entries for it. (Extracting a constant and never comparing it is exactly the vacuity
    requirement (a) exists to prevent.)

  **FR4b — the originating file must not exit the sync graph (P0).** After FR1 removes step 8's
  literals, `compound/SKILL.md` would be covered only by one-time PR-time greps (AC2/AC3) — which
  are *snapshots, not invariants*. Nothing would stop a future agent re-adding
  `warn > 20000 / critical > 23000` prose or deleting the linter invocation, which is **exactly how
  #6461 happened**. The guard MUST therefore additionally assert, as standing invariants, that
  `plugins/soleur/skills/compound/SKILL.md`:
  1. contains the linter invocation string **including the `2>&1`**, and
  2. contains no threshold literal in its **tier-decision logic** — scoped to that region, not the
     whole file, because the preserved `emit_incident` snippet legitimately contains `~600 bytes`
     (see FR6).

  **FR4c — wiring.** Add to `scripts/test-all.sh` via `run_suite` so it gates PRs. Extend the
  lefthook `agents-compound-sync` glob to **explicitly enumerate** every file the guard now reads:
  `AGENTS.docs.md` (**already missing today** — the `rule-threshold` sentinel moved there post-#3493
  and the glob never followed, so editing the sentinel does not currently fire the guard),
  `scripts/lint-agents-rule-budget.py`, `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`,
  `scripts/compound-promote.sh`, `plugins/soleur/skills/plan/SKILL.md`, plus the **self-glob** of
  `scripts/lint-agents-compound-sync.sh` and its new test.
- **FR5 — Stale constants corrected, and the conflated constant split.** One constant currently
  serves two semantically different jobs. Splitting it is the correctness half of this FR:

  | Use site | Job | Bind to |
  |---|---|---|
  | `cron-compound-promote.ts:580-587` — post-apply gate (Sentry mirror + `git checkout -- .` revert) | Mirror the commit gate exactly | `MAX_ALWAYS_LOADED_BYTES` = `B_ALWAYS_REJECT` (23000) |
  | `cron-compound-promote.ts:433` — proposal hint in the LLM prompt | Propose something that leaves the registry *healthy* | `PROPOSE_ALWAYS_LOADED_BUDGET` = `B_ALWAYS_WARN` (20000) |

  **Why the split matters.** Binding the *proposal* hint to the reject ceiling means a cluster
  landing at exactly 23000 passes the commit gate and pins the registry at the ceiling with zero
  headroom for the next promotion or any hand-authored rule. The promoter's job is not "propose
  anything not rejected" — it is "propose something that leaves room". `B_ALWAYS_WARN` is exactly
  what the linter's own comment defines as the *"trim opportunistically"* signal. This costs nothing
  today (at 22973 raw the promoter refuses either way) and becomes correct the moment Deferral 1's
  trim lands. Mirror the same split into `scripts/compound-promote.sh`.

  **Prompt label must be corrected too.** Both the TS and Bash prompts currently say
  `the warn cap is ${…}`. After the split, the proposal hint genuinely *is* the warn budget — so the
  label becomes accurate for `PROPOSE_ALWAYS_LOADED_BUDGET`. Ensure the post-apply gate's Sentry
  `extra.cap` field reports the reject constant and is not mislabelled.

  Sites 6, 7, 8 follow. Every new/changed constant MUST carry a comment naming
  `scripts/lint-agents-rule-budget.py` as the source of truth,
  `scripts/lint-agents-compound-sync.sh` as the enforcing guard, and the raw-vs-stripped unit note
  from TR5. Site 7 (`compound-promote.test.sh`) MUST also have its stale `# … Cap is 18000.`
  **comment** updated, not just the assertion — comment drift is the same defect class as this PR.
  Site 9 (`plan/SKILL.md:939`) keeps its correct `23000` but its raw `B_ALWAYS = $(wc -c …)`
  recipe MUST be corrected to note the frontmatter-stripped basis (same bug as site 3).
- **FR6 — Regression test.** A test MUST assert that the rubric text and the linter constants agree,
  and MUST fail if either side changes alone. Implemented as the extended guard (FR4) plus its own
  unit suite (see TR2), both wired into `scripts/test-all.sh`.
- **FR7 — No `AGENTS*.md` edits.** This PR MUST NOT modify `AGENTS.md`, `AGENTS.core.md`,
  `AGENTS.docs.md`, or `AGENTS.rest.md`. `B_ALWAYS` is under budget so no demotion is needed, and
  touching them would trip a pre-existing red lint (Sharp Edge 1).

## Technical Requirements

- **TR1 — Extraction must be symbol-anchored, not line-anchored.** The guard extracts constants via
  `grep -E '^B_ALWAYS_REJECT = [0-9]+'`-shaped patterns, never `sed -n 'N,Mp'`. This is the same
  discipline the guard's own header already documents, and is the defect class of site 4.
- **TR2 — The guard needs its own unit suite.** Add `scripts/lint-agents-compound-sync.test.sh`
  following the `scripts/lint-agents-rule-budget.test.sh` convention (throwaway `mktemp -d` trees,
  `assert_exit` / `assert_contains`). The canonical case list is the **Test Scenarios** table below
  — it is the single enumeration; do not restate it here.

  Sizing note (from simplicity review): because the guard is a table-driven loop, testing three
  different sites is testing *the same code path with different array data* and proves nothing the
  first iteration didn't. The suite is therefore deliberately small — one in-sync case, one
  single-site drift, one two-site drift (proves accumulate), one empty-extraction and one
  missing-file case (both fail-closed), and one `compound/SKILL.md` self-guard case. Test code
  outweighing a ~50-line bash guard 4:1 would be over-testing.
- **TR3 — Verify the extraction against the real files before freezing the patterns.** Each
  `grep -E` pattern must be run against the actual target file and shown to return exactly one match
  during implementation. A pattern that matches zero lines makes the guard vacuous.
- **TR4 — Do not change reject/warn values.** `B_ALWAYS_WARN = 20000` and
  `B_ALWAYS_REJECT = 23000` stay as-is. This PR reconciles restatements to the authority; it does
  not renegotiate the budget.
- **TR5 — Promote cap semantics, measurement basis, and prompt label.** Three coupled decisions,
  all of which must land together:
  1. **Which constant.** The promoter's refusal predicate binds to `B_ALWAYS_REJECT` (23000), not
     `B_ALWAYS_WARN` — the promoter's job is to avoid proposing a cluster the *commit gate* would
     reject.
  2. **Measurement-basis skew (load-bearing — do NOT skip).** The cron measures **raw** bytes
     (`(await readFile(p)).length`, no frontmatter strip) while the linter measures
     **frontmatter-stripped** bytes. Raw = stripped + 73. So the linter's true reject boundary is
     `raw > 23073`, and a raw-vs-23000 comparison is **73 B conservative** — it refuses slightly
     earlier than the gate would. That is the safe direction and is accepted, but it MUST be
     documented in the constant's comment rather than left as an accident. The corresponding
     residual headroom is therefore **≈27 B** (23000 − 22973 raw), **not** ~100 B.
     Do not copy the 22900 stripped figure into any reasoning about this constant.
  3. **Prompt label must be corrected.** The prompt currently reads
     `the warn cap is ${MAX_ALWAYS_LOADED_BYTES} bytes` while the value will now be the *reject*
     ceiling. Leaving the label would make the prompt misdescribe its own constant to the model.
     Change the prompt text to name it a hard/reject ceiling in **both**
     `cron-compound-promote.ts` and `scripts/compound-promote.sh` (the string is duplicated).

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/compound/SKILL.md` | FR1/FR2/FR3 — step 8 delegates to the linter; retain registry stats + `<!-- rule-threshold: 115 -->`; de-stale the loader citation |
| `scripts/lint-agents-compound-sync.sh` | FR4 — extend with budget-threshold cross-site assertions |
| `scripts/test-all.sh` | FR4 — `run_suite "scripts/lint-agents-compound-sync"` + the new unit suite |
| `lefthook.yml` | FR4 — extend `agents-compound-sync` glob (self-glob + newly-read files) |
| `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` | FR5 — split into `MAX_ALWAYS_LOADED_BYTES`=23000 (post-apply gate, L580) + `PROPOSE_ALWAYS_LOADED_BUDGET`=20000 (prompt hint, L433); fix the "warn cap" label; add source-of-truth + unit comments |
| `scripts/compound-promote.sh` | FR5 — same two-constant split + label fix + comments |
| `scripts/compound-promote.test.sh` | FR5 — expected sentinel `9:18000` → `9:23000` **and** the stale `# … Cap is 18000.` comment |
| `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` | FR5 — correct the `18000 warn / 22000 critical` prose **and** the `18k` prose at L97 |
| `plugins/soleur/skills/plan/SKILL.md` | FR5 — site 9: keep `23000`, correct the raw `wc -c` recipe to the stripped basis; brings it under the guard |

## Files to Create

| File | Purpose |
|---|---|
| `scripts/lint-agents-compound-sync.test.sh` | TR2 — unit suite for the extended guard |

**Explicitly NOT edited:** `AGENTS.md`, `AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md`,
`scripts/lint-agents-rule-budget.py`, `scripts/retired-rule-ids.txt`.

## Implementation Phases

Phase order is load-bearing: the **consumers** are corrected before the guard that asserts they
agree, so the guard is never committed in a state where it fails against the tree. (The *authority*
is never corrected — TR4 freezes `B_ALWAYS_WARN`/`B_ALWAYS_REJECT`.)

1. **Phase 0 — Preconditions.** Re-run the probes and pin outputs in the PR body: the linter with
   `2>&1` (expect `[WARN] B_ALWAYS=22900`, exit 0 — note stdout alone is empty), the linter unit
   suite (expect 20/20), the aggregator (expect the no-op line). Verify each FR4 extraction pattern
   returns exactly one match against its real target file (TR3) — including the ASCII-safe
   `AGENTS.docs.md` patterns and the two new `plan/SKILL.md` patterns.
2. **Phase 1 — Correct the consumers (FR5).** Split the cron's conflated constant into
   `MAX_ALWAYS_LOADED_BYTES` (post-apply gate) + `PROPOSE_ALWAYS_LOADED_BUDGET` (prompt hint), fix
   the "warn cap" prompt labels, mirror both into `scripts/compound-promote.sh`, correct the runbook
   (including the `18k` prose) and `plan/SKILL.md`. Update `scripts/compound-promote.test.sh`
   (assertion **and** stale comment) in the **same commit** as `scripts/compound-promote.sh` — the
   test asserts the constant, so a split commit leaves an intermediate red.
3. **Phase 2 — Rewrite the rubric (FR1/FR1b/FR2/FR3).** Replace step 8's byte-math block with the
   `2>&1` linter invocation behind an existence-check degrade path; retain the registry stats, the
   `rule-threshold` sentinel and the `emit_incident` telemetry block; re-tier the remediation prose
   onto WARN; de-stale the loader citation and drop the `(22k)` form.
4. **Phase 3 — Extend the guard (FR4/FR4b/FR4c/FR6/TR2).** Write the Test Scenarios suite. **T2-T6
   are RED-first** — confirm they fail against the unextended guard. **T1, T7, T8 are
   regression-pins that pass by construction** — do not "fix" them. Then extend
   `scripts/lint-agents-compound-sync.sh` (table-driven loop, accumulate-then-report, fail-closed,
   repo-root path resolution) until green. (`cq-write-failing-tests-before`.)
5. **Phase 4 — Wire into CI (FR4).** Add both `run_suite` entries to `scripts/test-all.sh`; extend
   the `lefthook.yml` `agents-compound-sync` glob.
6. **Phase 5 — Verify.** Run `bash scripts/test-all.sh scripts`, `bash scripts/lint-agents-compound-sync.sh`,
   `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, and confirm
   `python3 scripts/lint-agents-rule-budget.py …` still exits 0 at `B_ALWAYS=22900` (unchanged — this
   PR touches no `AGENTS*.md`).
7. **Phase 6 — File follow-ups.** Create the three deferral issues listed under Deferrals.

## Acceptance Criteria

### Pre-merge (PR)

**AC-shape rules (apply to every AC below).** (i) Negative assertions use `! grep -qE …`, never
"`grep -c` returns 0" — a passing `grep -c` exits 1, which under
`hr-when-a-command-exits-non-zero-or-prints` an agent may misread as failure. (ii) Threshold-literal
patterns MUST cover the prose forms, not just bare digits:
`(18|20|22|23)000|\b(18|20|22|23)k\b|\b2[0-9],[0-9]{3}\b` — the tree contains `(22k)`, `18k`, and
`21,949` forms that a digit-only pattern silently misses. (iii) Negative greps are **region-scoped**,
never whole-file, because preserved content legitimately contains threshold strings (the retained
`emit_incident` snippet contains `~600 bytes`). This is the AC self-reference grep trap — see
Sharp Edge 6.

- **AC1** — In `compound/SKILL.md`, the **tier-decision region** of step 8 contains no threshold
  literal under the pattern in AC-shape rule (ii). Region-scoped via an `awk` range over step 8's
  verdict block, excluding the retained `emit_incident` snippet. Verified in the same shape the
  guard uses (FR4b), so AC and guard cannot disagree.
- **AC2** — Step 8 contains the linter invocation **including `2>&1`**:
  `! grep -q 'lint-agents-rule-budget.py .*2>&1' plugins/soleur/skills/compound/SKILL.md` fails.
  (The `2>&1` is load-bearing — without it the WARN tier prints nothing to stdout.)
- **AC3** — `grep -q 'rule-threshold: 115'` matches (sentinel survives) **and**
  `grep -q 'emit_incident cq-agents-md-why-single-line'` matches (FR2.3 telemetry survives).
- **AC4** — `! grep -qF "sed -n '88,115p'" plugins/soleur/skills/compound/SKILL.md`, and the
  retained remediation text still contains all three CRITICAL guardrails (`retired-rule-ids.txt`,
  the `#3496` never-`hr-*` citation, `preserve per-issue mechanism labels`) **and** the two WARN
  guardrails (placement gate, route-to-skill-not-`AGENTS.core.md`) — per FR3.1/FR3.2, attached to
  the linter's WARN tier.
- **AC5** — `grep -qE 'MAX_ALWAYS_LOADED_BYTES = 23000'` and
  `grep -qE 'PROPOSE_ALWAYS_LOADED_BUDGET = 20000'` both match in the cron TS, and
  `! grep -qE '\b18000\b'` in that file.
- **AC6** — `grep -qE '^ALWAYS_LOADED_CAP=23000' scripts/compound-promote.sh`,
  `! grep -qE '\b18000\b' scripts/compound-promote.sh`, **and**
  `bash scripts/compound-promote.test.sh` exits 0 with no stale `18000` in its comments.
- **AC7** — `! grep -qE '(18|22)000|\b(18|22)k\b' knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
  (catches the `18k` prose at line 97 that a digit-only pattern misses).
- **AC8 (the anti-drift gate)** — Mutating **any one** site constant alone makes
  `bash scripts/lint-agents-compound-sync.sh` exit non-zero: `B_ALWAYS_REJECT` or `B_ALWAYS_WARN` in
  the linter; either cron TS constant; either `compound-promote.sh` constant; a threshold in
  `AGENTS.docs.md`; the `23000-byte critical cap` in `plan/SKILL.md`; and the step-8 invocation
  string or a re-added literal in `compound/SKILL.md` (FR4b).
- **AC9 (fail-closed)** — An extraction returning empty, **or a target file that is missing/renamed**,
  makes the guard exit non-zero with a diagnostic naming the file. A vacuous pass is a test failure.
- **AC10 (accumulate)** — With **two** sites mutated, a single guard run reports **both** in its
  output before exiting non-zero (proves FR4(b) accumulate-then-report, not first-failure-exit).
- **AC11** — `bash scripts/test-all.sh scripts` exits 0.
- **AC12** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- **AC13 (lefthook wiring)** — The `agents-compound-sync` glob in `lefthook.yml` contains
  `AGENTS.docs.md`, `scripts/lint-agents-rule-budget.py`, the cron TS path,
  `scripts/compound-promote.sh`, `plugins/soleur/skills/plan/SKILL.md`, and the self-glob of
  `scripts/lint-agents-compound-sync.sh`.
- **AC14 (issue-mandated reporting)** — PR body reports the measured actuals: `B_ALWAYS=22900`
  (6072 + 16828 stripped; 22973 raw), registry 43513 B / 202 rules, the
  `rules_unused_over_8w = 98 of 101 tagged` reframing with the worktree-no-op caveat, **and** the
  statement that the cron cap fix restores *correct behaviour, not capacity* (**≈27 B** raw headroom
  remains until a trim lands).

### Post-merge (operator)

None. Every step above is automatable in-session and in CI.

## Test Scenarios

Canonical enumeration (TR2 implements exactly these).

| ID | Scenario | Expected | Kind |
|---|---|---|---|
| T1 | Tree as-shipped, all sites in sync | exit 0 | regression-pin |
| T2 | `B_ALWAYS_REJECT` bumped in the linter only | exit non-zero; output names **every** out-of-sync site in one run (proves accumulate-then-report, FR4(b)) | RED |
| T3 | `MAX_ALWAYS_LOADED_BYTES` changed in cron TS only | exit non-zero, names the TS file with expected/found **and the unit** | RED |
| T4 | Threshold removed from `AGENTS.docs.md` (extraction empty) | exit non-zero, fail-closed — never a vacuous 0 | RED |
| T5 | A target file renamed/absent | exit non-zero with a diagnostic naming the missing path (not a bare `grep: No such file`) | RED |
| T6 | `compound/SKILL.md` invocation string deleted, or a threshold literal re-added to step 8's tier logic | exit non-zero (FR4b — the originating file stays guarded) | RED |
| T7 | `rule-threshold` sentinel de-synced | exit non-zero (pre-existing behaviour preserved) | regression-pin |
| T8 | `compound-promote.sh` byte-budget sentinel | emits `::compound-promote-byte-budget::<now>:23000` | regression-pin |

**Phase-3 labelling note:** T1, T7 and T8 **pass** against the unextended guard by construction —
they are regression-pins, not RED cases. Only T2-T6 are legitimately RED-first. Do not let an
implementer "fix" a passing pin.

## Observability

Required because Files-to-Edit includes a code-class file under `apps/*/server/`.

```yaml
liveness_signal:
  what: "scripts/lint-agents-compound-sync suite result in the CI `test-scripts` job"
  cadence: "every PR + every push to main + main-health-monitor.yml full run"
  alert_target: "GitHub required check `test` (ruleset 14145388) — blocks merge on failure"
  configured_in: ".github/workflows/ci.yml job test-scripts; scripts/test-all.sh run_suite entries"
error_reporting:
  destination: "CI job log + non-zero exit propagated to the required `test` check"
  fail_loud: true
failure_modes:
  - mode: "A future edit changes the linter constant without sweeping the consumers (the exact #4599 defect recurring)"
    detection: "lint-agents-compound-sync.sh exits 1 with a per-site expected/found diagnostic"
    alert_route: "CI required check `test` fails → merge blocked"
  - mode: "The guard's grep extraction silently returns empty and the guard passes vacuously"
    detection: "Explicit empty-extraction and missing-file checks exit non-zero (AC9); asserted by T4 and T5"
    alert_route: "CI required check `test` fails → merge blocked"
  - mode: "cron-compound-promote refuses every agents-core cluster because the cap is below B_ALWAYS"
    detection: "The cron already emits alwaysLoadedNow + the cap into its prompt; after this PR the cap tracks B_ALWAYS_REJECT, so a refusal means genuine budget exhaustion, not a stale constant. The `::compound-promote-byte-budget::<now>:<cap>` telemetry line makes the pair observable."
    alert_route: "Inngest run history; the follow-up trim issue tracks the headroom"
logs:
  where: "GitHub Actions job logs (ci.yml test-scripts); Inngest run history for the cron"
  retention: "GitHub Actions default (90d); Inngest project retention"
discoverability_test:
  command: "bash scripts/lint-agents-compound-sync.sh"
  expected_output: "lint-agents-compound-sync: OK"
```

No `ssh` appears in any verification path.

## Architecture Decision (ADR/C4)

**No ADR required.** Applying the Phase 2.10 detection set: no data-model ownership/tenancy move; no
new substrate or integration pattern (the guard, the linter and the cron all already exist); no
resolver/dispatch/trust-boundary change; no reversal of an existing ADR — ADR-027 (stateless
self-modifying cron) is *unblocked* by correcting the cap, not contradicted, and ADR-094's
frontmatter-strip contract is honoured, not changed. The single-source-of-truth convention is
recorded in the guard's own header comment, which is where the existing `rule-threshold` contract is
already documented.

**No C4 impact — enumeration performed against all three model files**
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** none added or changed. No new correspondent, reviewer, or recipient.
- **External systems / vendors:** none added. No new inbound webhook, outbound API, or third-party
  store. The Anthropic call in `cron-compound-promote.ts` is pre-existing and unchanged.
- **Containers / data stores touched:** none added. The change is a constant and lint coverage.
- **Actor↔surface access relationships:** unchanged. No sharing, ownership, or permission edge moves.
- The one related element, `compound = component "compound skill"` (`model.c4`, description
  *"Captures learnings and promotes to constitution"*), remains accurate after this change — the
  rubric's arithmetic moves, its purpose does not.

## User-Brand Impact

**If this lands broken, the user experiences:** a CI required-check failure on an unrelated PR (if
the new guard is over-strict or vacuous), or — in the worst case — a `compound` session reporting a
budget verdict that disagrees with the commit gate, causing a rule addition to be authored and then
rejected at commit time. No end-user-facing surface is touched.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector. This PR touches
no user data, no secrets, no auth path, no network boundary, and no persisted record. The only
runtime behaviour change is a numeric threshold in an internal clustering prompt.

**Brand-survival threshold:** `none`.

*Scope-out justification:* `threshold: none, reason: the change set is developer-tooling thresholds
and lint coverage with no user-facing surface, no regulated data, and no credential or network
boundary.* The diff touches `apps/web-platform/server/**` (a sensitive-path match) solely to change
one integer constant and its comment, with no data-flow, schema, or auth implication.

## GDPR / Compliance

Not applicable. No regulated-data surface: no schema, migration, `.sql`, auth flow, or API route is
touched. None of the four expansion triggers fire — (a) no new LLM processing activity on
operator-session data (the existing Anthropic call's *threshold* changes, not its data scope or
corpus); (b) brand-survival threshold is `none`; (c) no new cron reads `learnings/` or `specs/`
(the existing cron's corpus is unchanged); (d) no new artifact distribution surface.

## Infrastructure (IaC)

Not applicable. No server, service, cron schedule, vendor account, DNS record, TLS cert, secret,
firewall rule, or monitoring webhook is introduced or changed. No `.tf` file is touched. The change
is a constant inside an already-provisioned Inngest function plus lint/test wiring.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` against every planned file path.

- `plugins/soleur/skills/compound/SKILL.md` — none.
- `scripts/lint-agents-rule-budget.py` — none.
- `scripts/rule-metrics-aggregate.sh` — none.
- `AGENTS.core.md` — #4133 (*follow-through(#4116): Schema parity test for `## Observability` block*).
  **Acknowledge** — different concern (observability-block schema parity), and FR7 means this PR does
  not edit `AGENTS.core.md` at all.
- `AGENTS.md` — #3373 (*SLOT_TRIGGER_INTEGRATION_TEST not wired into nightly CI*), #3002
  (*service-worker global error handler*). **Acknowledge** — both mention `AGENTS.md` only as a
  convention reference; neither touches the rule-budget subsystem, and FR7 excludes `AGENTS*.md`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No Product/UX surface: the
mechanical UI-surface scan over `## Files to Edit` and `## Files to Create` matches no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` path, so the Product/UX Gate does
not fire at any tier.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The extended guard is vacuous (a `grep` matches nothing and it exits 0) | AC9 + TR2 case (e) + T7 make empty extraction a hard failure; TR3 requires proving each pattern returns exactly one match against the real file before freezing it |
| Raising the promote cap widens the additive envelope of an LLM that writes to the always-loaded payload (ADR-092 / AP-017 — see Sharp Edge 8) | Two-constant split (FR5): the **proposal** budget binds to `B_ALWAYS_WARN` (20000) so the promoter cannot propose up to the hard ceiling, while the **post-apply gate** binds to `B_ALWAYS_REJECT` (23000) and still reverts + mirrors to Sentry. The linter remains the hard backstop in lefthook **and** CI. Net headroom today is ≈27 B raw against the gate and negative against the proposal budget — deliberately conservative |
| The step-8 rewrite drops guidance that other artifacts depend on | FR2 pins the `rule-threshold` sentinel (already guarded), FR3 pins the three remediation guardrails, and AC3/AC4 assert both |
| Editing `compound/SKILL.md` trips the red `lint-agents-enforcement-tags` lint | It does not — that hook's glob is `AGENTS*.md` + its own script only. FR7 keeps this PR off `AGENTS*.md`. See Sharp Edge 1 |
| The cron TS edit breaks the Inngest function | Single integer constant + comment; AC11 (`tsc --noEmit`) and the existing `test/server/inngest/cron-compound-promote.test.ts` cover it |

## Deferrals (follow-up issues to file in Phase 6)

1. **Trim `B_ALWAYS` to restore promotion headroom.** At 22900/23000 the `agents-core` promotion
   tier is functionally inert even after this fix. Re-evaluation criterion: `B_ALWAYS ≤ 20000`
   (the WARN floor). Label `type/chore`, `domain/engineering`, `priority/p3-low`.
2. **Establish a trustworthy `rules_unused_over_8w` denominator before any pruning campaign.**
   `total_rules_tagged = 101` vs a 202-rule registry, and the incidents log is operator-machine-local
   (the aggregator no-ops in a worktree). Determine whether 98/101 reflects genuine non-use or absent
   telemetry before retiring anything. This is the issue's "98/198" claim, correctly scoped.
3. **12 unresolved `[skill-enforced:]` anchors in `AGENTS.{core,docs}.md`.**
   `scripts/lint-agents-enforcement-tags.py` currently exits 1 on the tree; it is wired **only** in
   lefthook and **not** in CI, so it silently fails to gate. Two defects: the broken anchors, and the
   missing CI wiring. Pre-existing and a different subsystem — filed per
   `wg-when-an-audit-identifies-pre-existing`. See Sharp Edge 1.
4. **Stale 18000 constants in dead migration tooling.** `tools/migration/split-sidecars.sh` and
   `tools/migration/classify-rules.sh`. Confirm dead, then delete or correct. (Nuance:
   `classify-rules.sh`'s `DOCS_RE`/`CODE_RE`/`INFRA_RE` strings *are* parity-tested against the live
   loader by `tests/scripts/test_classifier_regex_parity.sh`, but that test does not reference the
   18000 constant and neither script runs in CI — so the 18000 specifically is dead.)
5. **Port the frontmatter strip to the promote consumers so the comparison is unit-exact.**
   `scripts/lib/frontmatter-strip/SPEC.md` is explicitly a canonical contract with byte-identical
   implementations (`strip.py`, `strip.sh`) and mechanical parity enforcement via
   `scripts/lib/frontmatter-strip.test.sh`. Adding a third (`strip.ts`) and using it in
   `cron-compound-promote.ts` (and `strip.sh` in `compound-promote.sh`) would make the promoters
   measure in the same unit as the gate they mirror, letting the guard assert true parity instead of
   a documented 73 B skew. Deliberately **not** done here: it changes a production self-modifying-cron
   write path and deserves its own PR with the parity-test extension. Re-evaluation trigger: when
   `B_ALWAYS` drops enough that the 73 B skew becomes decision-relevant (i.e. after Deferral 1), or
   when any promoter false-reverts a diff the commit gate would have accepted.

## Sharp Edges

1. **`scripts/lint-agents-enforcement-tags.py` is currently RED on the tree (12 unresolved
   anchors), and it is wired only in `lefthook.yml`, not in CI.** Any PR that stages an `AGENTS*.md`
   file will be blocked at pre-commit by a failure it did not cause — and the only escapes are
   fixing 12 unrelated anchors or `--no-verify`. This is a second, independent instance of the same
   meta-defect as #6461: a guard whose coverage and health nobody checks. FR7 (no `AGENTS*.md`
   edits) is what keeps this PR clear of it; deferral 3 tracks the fix. Do not "just fix one anchor"
   inline — it is a different subsystem and would expand this PR.
2. **The rubric's `wc -c` measurement is wrong in a way that is invisible at any single reading.**
   It reports raw core bytes (16901) where the loader and linter use frontmatter-stripped bytes
   (16828). The 73 B gap only matters within 73 B of a boundary — which, at 22900/23000, is exactly
   where the tree now sits. Delegating to the linter (FR1) is what fixes this; simply correcting the
   two tier numbers would have left the measurement bug in place.
3. **`compound/SKILL.md` step 8 is prose read by an agent, not executed code.** Its "output" is a
   template the agent fills in. Verification must therefore assert on the *instruction text*
   (does it tell the agent to run the linter?) rather than on any runtime output. AC2 asserts the
   literal invocation string for this reason.
4. **Do not describe FR5 as "re-enabling compound promotion".** It restores correct behaviour with
   **≈27 B** of raw headroom against the post-apply gate (and *negative* headroom against the new
   20000 proposal budget, which is the intended conservative posture); the capability stays inert
   until a trim lands (Deferral 1). AC14 carries that honesty into the PR body, because "fixed the
   outage" is the tempting and wrong summary.
5. **`agents-compound-sync`'s lefthook glob is already wrong today, in two ways.** (a) It does not
   self-glob its own script (unlike `rule-budget-lint`, which globs the linter and its test), so an
   edit to the guard does not re-run the guard. (b) It globs `AGENTS.md`, but the `rule-threshold`
   sentinel moved to `AGENTS.docs.md` post-#3493 and **the glob never followed** — so editing the
   sentinel does not currently fire the guard that reads it. FR4c fixes both; AC13 pins it. Do not
   just append the new files and leave `AGENTS.docs.md` out.
6. **The AC self-reference grep trap — this plan is a prime candidate for it.** A whole-file
   "no threshold literals in `compound/SKILL.md`" AC **false-fails a correct implementation**,
   because the retained `emit_incident` snippet legitimately contains the string `~600 bytes`, and
   FR3's preserved remediation prose legitimately discusses budgets. Every negative AC here is
   therefore region-scoped and paired with a positive guardrail assertion. The symmetric trap: a
   digit-only pattern **passes while the file is still wrong**, because the tree contains `(22k)`,
   `18k`, and `21,949` prose forms. Both directions are covered by the AC-shape rules. See
   `knowledge-base/project/learnings/2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md`
   — a learning written about *this same subsystem*.
7. **The stripped-vs-raw skew is now knowingly accepted, not accidental — and the guard must say so.**
   The guard asserts *constant equality*, not *measurement-basis equality*. After this PR the cron
   still compares raw bytes against a stripped-basis threshold (73 B conservative, the fail-safe
   direction). That is fine, but a green guard that does not name the unit silently certifies a
   comparison performed in the wrong unit — which retires exactly the suspicion that would catch it
   next time. FR4(c) requires the unit in the diagnostic; Deferral 5 tracks the real fix.
8. **The additive-envelope note (ADR-092 / AP-017).** The cron is the harness self-edit path that
   writes to `AGENTS.core.md`. AP-017 human-gates *edits and deletions* of `hr-*`/`wg-*` bodies but
   permits *additions*, so the post-apply byte cap is the only **volumetric** brake on the additive
   envelope. Moving it 18000 → 23000 widens that brake by 5000 B in principle. This is not a
   violation — 23000 is the true ceiling and 18000 was never a deliberate policy choice — but the
   brake is being *restored to its intended position*, not merely "unblocked". Record this in the
   constant's comment.

## Research Insights

- Root-cause commit: `d475c4e46` ("chore(agents): trim AGENTS B_ALWAYS -15% and wire budget linter
  into CI (#4601)"). Touched `scripts/lint-agents-rule-budget.py`,
  `scripts/lint-agents-rule-budget.test.sh`, `plugins/soleur/skills/deepen-plan/SKILL.md` — and no
  other restatement site.
- Precedent for "executable is the source of truth; the doc must quote the same bytes":
  `plugins/soleur/test/kb-search-lockstep.test.sh`.
- Precedent for a shared source-only constants module (the rejected heavier alternative):
  `scripts/lib/rule-metrics-constants.sh`.
- Bash test-suite convention (`mktemp -d` trees, `assert_exit` / `assert_contains`):
  `scripts/lint-agents-rule-budget.test.sh`.
- CI wiring: `.github/workflows/ci.yml` job `test-scripts` runs `bash scripts/test-all.sh scripts`;
  the synthetic `test` job (`if: always()`, inspects per-shard `result`) is the required check on
  ruleset 14145388.
- Loader class selection lives at `.claude/hooks/session-rules-loader.sh` around the `DOCS_RE=` /
  `CODE_RE=` / `INFRA_RE=` block (~167-190): `docs-only` fires when `HAS_DOCS=1 && HAS_CODE=0 &&
  HAS_INFRA=0` → `CLASSES="core docs-only"`, i.e. `AGENTS.rest.md` does **not** load on docs-only
  sessions. Recorded for completeness; no demotion is in scope, so the constraint is not exercised.
- No `--print-thresholds` or `--print-config` flag pattern exists anywhere in the repo, which is why
  that alternative was rejected.

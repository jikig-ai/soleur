# Tasks — fix: the soak-enrollment gate matches a token, not a claim (#7056, #7087)

Plan: [`knowledge-base/project/plans/2026-08-01-fix-ship-soak-gate-matches-token-not-claim-plan.md`](../../plans/2026-08-01-fix-ship-soak-gate-matches-token-not-claim-plan.md)

Lane: `cross-domain` (spec.md absent — TR2 fail-closed default)
Brand-survival threshold: `none`

---

## Phase 0 — Preconditions (no edits)

- [ ] **0.1** Baseline the existing suite: `bun test plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts` → record pass/fail counts (expected 14 pass / 0 fail).
- [ ] **0.2** Baseline the precedent suite: `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts` → green.
- [ ] **0.3** Read `scripts/ship-incident-pir-gate.sh` end to end. Note three things to mirror: `set -uo pipefail`, herestring-not-pipe for `grep -q` (a pipe under `pipefail` can SIGPIPE on early match and invert the result), and the exit-code contract (0 = signal + stdout marker, 1 = clean no-signal).
- [ ] **0.4** Confirm the hook resolves the repo root as `$(dirname "${BASH_SOURCE[0]}")/../..` (it already uses `$(dirname …)/lib/incidents.sh` for `incidents.sh`).
- [ ] **0.5** Re-run the planning measurement to confirm the starting numbers still hold on current `main`: current `SOAK_RE` fires on 20/40 most-recent plans.

## Phase 1 — RED: fixtures and failing tests first

`cq-write-failing-tests-before`. Fixtures and harness land **before** the script exists.

- [ ] **1.1** Create `plugins/soleur/test/fixtures/ship-soak-followthrough-gate/`.
- [ ] **1.2** Author 9 **synthesized** plan-shaped fixtures (`cq-test-fixtures-synthesized-only` — no real emails, no prod-shape UUIDs, no tokens; never copy #7034's or #7072's real plan):
  - [ ] `real-soak-declaration.md` — **FIRE** (numeric-window claim)
  - [ ] `soak-disposition-not-applicable.md` — **QUIET** (#7056 required pair, negative)
  - [ ] `soak-filename-only.md` — **QUIET** (#7087; include both backticked and bare forms)
  - [ ] `negated-criterion-soak.md` — **QUIET** (`no post-deploy soak`, `no 7-day soak`)
  - [ ] `negation-adjacent-real-soak.md` — **FIRE** (`no P0 incidents during the 7-day soak`)
  - [ ] `prose-soak-no-numeric-window.md` — **FIRE** (`One-week soak`, `after a prod soak`, `when the soak holds`)
  - [ ] `gate-name-and-fenced-regex.md` — **QUIET** (names the gate; quotes `SOAK_RE` in a fence)
  - [ ] `adopting-accepted-arrow.md` — **FIRE** (multibyte `→` is the only signal)
  - [ ] `prose-about-soaks.md` — **QUIET** (weak-preposition bound: `a recall survey of ~70 prose soak declarations`, `the soak gate fired`)
- [ ] **1.3** Add the `spawnSync` harness to `plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts`, modelled on `ship-incident-pir-gate.test.ts`'s `signals()`:
  - FIRE ⇒ assert `status === 0` **and** stdout contains `SOAK-SIGNAL: yes`
  - QUIET ⇒ assert `status === 1` (exactly 1, never merely non-zero) **and** stdout empty
  - Feed each fixture independently via stdin — never concatenate fixtures.
- [ ] **1.4** Re-derive and re-measure both regexes against the fixtures **and** the 40-most-recent-plans corpus. Do not paste the plan's literals unverified. Record the measured numbers for the PR body.
- [ ] **1.5** Confirm RED (suite fails because the script does not exist yet).

## Phase 2 — GREEN: extract the scan into a script that owns the regex

**Ordering is load-bearing** — the contract producer must exist before Phase 3 rewires its consumers.

- [ ] **2.1** Create `scripts/ship-soak-signal-gate.sh` with a header comment covering: what it is, the #7056/#7087 false positives it retires, the exit contract, and *why each strip stage exists* (so a later editor cannot delete a stage without reading its reason).
- [ ] **2.2** Implement the strip pipeline in order: fenced code blocks → inline `` `code` `` spans → `GATENAME_RE` → `NEGATION_RE`.
- [ ] **2.3** Implement the dual-locale match, preserved from the hook: once under `LC_ALL=C.UTF-8`, once without (the regex carries the multibyte `→`).
- [ ] **2.4** Exit contract: `echo "SOAK-SIGNAL: yes"; exit 0` on a hit; bare `exit 1` otherwise. Never exit 2, never crash on empty input.
- [ ] **2.5** `chmod +x scripts/ship-soak-signal-gate.sh`.
- [ ] **2.6** Confirm GREEN on all 9 fixtures.
- [ ] **2.7** Mutation-test each fixture: delete the corresponding regex alternative or strip stage and confirm at least one test turns RED. Record the mutation matrix for the PR body (AC8).

## Phase 3 — Wire the two consumers

- [ ] **3.1** `.claude/hooks/ship-soak-followthrough-gate.sh`: replace the inline `SOAK_RE` + dual `grep -qiE` with a pipe of `"$CORPUS"` into the script; branch on its exit inside an `if` so `set -eo pipefail` never sees the clean `exit 1`.
- [ ] **3.2** Same file: fail-open (`exit 0`) if the script is absent or unreadable, consistent with the hook's other fail-open arms.
- [ ] **3.3** `plugins/soleur/skills/ship/SKILL.md`: replace the §Detection `SOAK_RE=` / `SOAK_HIT=` block with the script invocation, mirroring the call shape used at §"Incident-signal scan". Keep the `COMBINED` corpus build (plan-file resolution stays the skill's job).
- [ ] **3.4** Same file: add the `**Why:**` sentence citing #7056 + #7087 and the measured corpus rate.

## Phase 4 — Docs, retroactive application, full suite

- [ ] **4.1** `.claude/hooks/README.md`: rewrite the `SOAK_RE is kept **byte-identical**…` bullet to describe single ownership; add the false-positive history and the `SOAK-SIGNAL` exit contract.
- [ ] **4.2** Delete the `soakRe()` scraper and the byte-identity parity test from the test file; re-anchor the two prose assertions that referenced `SOAK_RE=`.
- [ ] **4.3** **Retroactive gate application** (`wg-when-fixing-a-workflow-gates-detection`): run the shipped script against `knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md` (#7034) and #7072's linked plan; both must exit 1. Record in the PR body. Read-only — do not copy either into `fixtures/`.
- [ ] **4.4** Self-check (AC10): pipe the PR body concatenated with this feature's plan file into the shipped script; must exit 1.
- [ ] **4.5** Measure the corpus rate over the 40 most recent plans; must be ≤ 6 (baseline 20). Record the number.
- [ ] **4.6** Full suite: `bash scripts/test-all.sh`.

## Phase 5 — Ship

- [ ] **5.1** Verify all 18 Acceptance Criteria in the plan.
- [ ] **5.2** PR body carries `Closes #7056` and `Closes #7087` (body, not title — `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **5.3** PR body records: the measured corpus rate (before → after), the mutation matrix, and the retroactive-application result for #7034 and #7072.
- [ ] **5.4** Remove the `deferred-scope-out` label from #7087 at merge — its recorded re-evaluation trigger is satisfied by this PR.
- [ ] **5.5** Post-merge operator steps: **none**.

---

## Notes for the implementer

- The plan's regex literals are a **verified starting point**, not a frozen contract. Task 1.4 re-derives them. The fixture matrix is the contract.
- Every regex literal in the plan lives inside a fenced code block on purpose. If a literal moves into prose, the PR blocks itself and it will look like a gate bug rather than a formatting slip.
- Do not add a second drift guard for the regex — the whole point is that there is now one copy, so parity is unrepresentable rather than asserted.
- This gate's precision bias is deliberately the **opposite** of `ship-incident-pir-gate.sh`'s fail-toward-PIR posture. Do not harmonize them; the rationale is in the plan's Domain Review.

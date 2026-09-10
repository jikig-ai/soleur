# Tasks — separate the machinery ledger, move the filing lever to filing time

Plan: `knowledge-base/project/plans/2026-09-10-feat-issue-flow-ledger-separation-plan.md`

## Phase 0 — Preconditions (VERIFIED 2026-09-10, not assumed)

- [x] **0.1** AGENTS budget authorities recorded.
      `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
      → `B_ALWAYS=45999` (AGENTS.md=5489 + AGENTS.rules.md=40510) against
      `B_ALWAYS_REJECT=46000`. **Effective headroom: 1 byte.** Every later phase
      must keep it at or below this; AC10 requires strictly lower.
- [x] **0.2** `meta/*` namespace free. `gh label list --limit 300 --json name`
      → 0 labels match `^meta/`; no label matches `machinery`. No collision.
- [x] **0.3** Next-free ADR ordinal derived across **all 85** `refs/remotes/origin`
      refs (not `origin/main` alone). Highest claimed: **ADR-215**.
      → **ADR-216 is next-free, provisional until /ship re-verifies at merge.**
- [x] **0.4** Planning-time baseline recorded.
      `gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:open" --jq '.total_count'`
      → **1455**. (Write-up figure was 1,456; a session-start recount read 1,459.
      All three are churn inside the measurement window — recorded as a band, not
      reconciled into a single false-precision number.)
- [x] **0.5** `bash .claude/hooks/guardrails.test.sh` on the untouched tree →
      **Total: 65  Pass: 65  Fail: 0**, exit 0. A later red is therefore
      attributable to this change.

### Phase 0 exit note — rebase performed before any edit

Phase 0.5's own pre-flight found the branch **3 commits behind** `origin/main`,
one of which (`fix(test-fixtures): fixture-env adoption, ledger isolation, and the
ancestry walk`) touches `plugins/soleur/test/net-issue-flow.test.sh` — a file
inside lever 4's scope. Rebased onto `b29131393` before Phase 1, per the
AGENTS-class fail-hard rule in work Phase 0.5. Now 0 behind.

## Phase 1 — L1: create the label and sweep every consumer

- [x] **1.1** Create `meta/machinery` (house style: slash-namespaced, one-line
      description matching the `domain/*` shape).
- [x] **1.2** Sweep consumers in the SAME PR (2026-04-02 coupling learning):
  - [x] `plugins/soleur/skills/operator-digest/SKILL.md` §4 EXCLUDE list
  - [x] `plugins/soleur/agents/support/ticket-triage.md` routing exclusion
  - [x] `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` explicit query exclusion
  - [x] **NOT** `net-issue-flow.sh` — deliberate non-change, AC4. The label
        separates visibility, never accountability.
- [x] **1.3** Backfill by evidence rule → committed proposal artifact. Classifies
      only; closes nothing (AC5).

## Phase 2 — L2 (PRIMARY): the blocking filing-time gate

- [x] **2.1** Mutation matrix written BEFORE the guard.
- [x] **2.2** Check added INSIDE the existing `guardrails:require-milestone` block.
- [x] **2.3** Three exits: `--label meta/machinery` | `User-Impact:` + `Fix-Size:` | `Mandated-By:`.
- [x] **2.4** No fourth escape hatch — recorded as a deliberate cut in ADR-216.
- [x] **2.5** `wg-defer-only-after-inline-triage` reconciled, byte-NEGATIVE (AC10).
- [x] **2.6** `guardrails.test.sh` extended, incl. assertion-count floor (AC6b).

## Phase 3 — L3: extend the existing sweeper (stock cleanup only)

- [x] **3.0** Real safety properties (tranches, `MAX_CLOSES_PER_RUN`,
      `MACHINERY_SWEEP_NOT_BEFORE`, empirical `updated_at` probe).
- [x] **3.1** Target set — **one** comma-joined `label:` qualifier (multiple
      qualifiers AND and would match zero, indistinguishably from a clean run).
- [x] **3.2** Kill switch widened + never-touch guards; **3.2a** comment fetch
      hoisted above the dry-run short-circuit.
- [x] **3.3** Explanatory comment; cross-generation idempotency defect fixed.
- [x] **3.4** Separability keyed on `COMMENT_MARKER`, NOT `stateReason`.
- [ ] **3.5** Dry-run exercised and reviewed before any live sweep.

## Phase 4 — L4: net-negative cadence and gate visibility

- [x] **4.1** Inngest cron → `workflow_dispatch:{}`-only workflow (ADR-033).
- [x] **4.2** Closing floor >= 20, with the candidate-supply waiver arm.
- [x] **4.3** Weekly measurement: five separately-counted lines.
- [x] **4.4** Find-or-update ONE standing issue (AC19).
- [x] **4.5** `GH_TOKEN` declared and forwarded.

## Phase 5 — Artifacts

- [x] **5.1** `measurement-baseline.md`.
- [x] **5.2** ADR-216.

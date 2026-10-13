---
title: "fix(infra): class-aware stock-gate closing lines and a documented, tested post-destroy recovery read"
type: fix
date: 2026-10-06
slug: fix-stock-gate-class-aware-recovery
branch: feat-one-shot-9510-stock-gate-recovery
issue: 9510
closes: 9510
lane: single-domain
---

# fix(infra): class-aware stock-gate closing lines and a documented, tested post-destroy recovery read

## Enhancement Summary

**Deepened on:** 2026-10-06 (inline deepen — no Task subagent surface in this runner; the deepen
phases ran as an in-process pass: gates 4.6–4.12 verified mechanically, learnings sweep applied,
verify-the-negative greps run inline).

### Key improvements landed during the deepen pass

1. Byte-budget math made concrete: 485,630 B used of a 490,000 B enforced cap → the plan moves
   all class-advice prose into the sourced lib and keeps per-site YAML edits ~1 line.
2. `_STOCK_LAST_CLASS` staleness handling added: gate resets on entry, plan-shape aborts render
   `class=none`, multi-class plans render `class=mixed`.
3. The recovery report's absent-vs-tainted state arm (optional `terraform show -json` input)
   added after reading the web-host two-arm doctrine — the two states have OPPOSITE re-dispatch
   paths, so naming the state is what makes the doctrine actionable.

### Gate results

User-Brand Impact present, threshold `none` with the sensitive-path scope-out reason (4.6);
Observability schema present, probe verb `git` allowlisted, no SSH, sub-15s, literal expected
output (4.7); PAT sweep clean (4.8); no UI surface (4.9); Encryption Posture stated N/A with
reason — no new store or connection (4.10); `lint-guard-contract.py` green on 2 entries (4.11);
one unfenced `## Scope Check`, every ask quoted verbatim from issue #9510, both `inferred` rows
carry justifications (4.12). `lint-infra-no-human-steps.py` clean on this file;
`lint-infra` full-tree output is 518 pre-existing hits, none on this plan.

## Overview

Issue #9510 tracks two defects sharing one trigger — the next destroy-first replace dispatch of
`.github/workflows/apply-web-platform-infra.yml`:

- **Item B (messaging):** the eight `stock-preflight ABORTED` closing lines and the pre-rehearsal
  advisory probe all read as if every non-zero gate result were a stock shortage, but the gate lib
  (`tests/scripts/lib/stock-preflight-gate.sh`, rebuilt by #9505) emits four distinct failure
  classes — `class=stock`, `class=config`, `class=unreachable`, `class=malformed` — with different
  advice. A `config`/`malformed`/`unreachable` abort that prints "not orderable — wait for stock
  and re-fire" sends a mid-incident reader in the wrong direction.
- **Item A (recovery):** a `terraform apply -replace` destroys before it creates. When the create
  fails after the destroy, the fleet is short a host; today's apply steps print a static recovery
  annotation (five of six destroy-first sites have one; `inngest-host-replace` has none) but nothing
  re-reads the stock gate at failure time to say whether the create failed on stock or on a cause
  stock says nothing about, and nothing names which recovery arm applies.

## Problem Statement / Motivation

The gate narrows the stock window to Hetzner's own `available` indicator, which is an indicator,
not a reservation: stock can flip between the preflight read and the create, and a create can fail
for reasons stock never covered (quota, placement group, attach). Once the destroy has run, the
operator's only question is "what failed and what do I re-dispatch" — and both current surfaces
answer it wrongly or not at all. This is the follow-up the #9505 review already flagged in the run
log and the runbook row that says "trust the `class=` line" because the closing line is wrong for
three of four classes.

## Proposed Solution

**Item A — option 2: documented and tested post-destroy recovery** (over create-before-destroy).
Rationale, recorded for the issue's explicit choice-point:

- The recovery that already works today is a **re-dispatch**: the guards pin the data volumes out
  of the destroy set, so a create that fails post-destroy leaves them in state; a new dispatch
  re-plans a create + reattach. `web-host-replace` documents the absent-vs-tainted two-arm
  recovery, `registry-luks-recut` has a tested resume arm, and `workspaces-luks-recut` proved the
  bare-create recovery shape in #6855. The doctrine exists; what is missing is the *diagnostic* —
  which failure class fired — and coverage: `inngest-host-replace`'s apply step has no failure
  branch at all.
- **Create-before-destroy is rejected**: the transient second host cannot take the retained
  volume (a `hcloud_volume_attachment` binds one server), cannot hold the same identity/NIC, and
  rebuilds the warm-standby topology retired at #6575 — a topology change to prod replace paths,
  far beyond the issue's own ~500-line estimate, that would need its own rehearsal evidence.
- **In-run re-application of the saved plan is rejected**: stock moves on an hours timescale
  (cx33 went orderable→nowhere in ~3h on 2026-07-15), so a retry inside the same run cannot wait
  out `class=stock`, and re-applying a saved plan after a partial apply is not a semantics this
  repo's gates certify. The recovery is a *new dispatch* with a fresh plan — the lib's job at
  failure time is to name the class so the operator picks the right wait-or-fix arm.

Concretely, all in `tests/scripts/lib/stock-preflight-gate.sh` (the sourced lib every caller shares):

1. `_STOCK_LAST_CLASS` — a sourced-shell global that `stock_preflight` sets on every abort arm
   (`stock|config|unreachable|malformed`) and clears to `orderable` on success. `stock_preflight_gate`
   resets it to `none` on entry and folds a second distinct failing class to `mixed`, so the closing
   line can never name one class over a multi-row plan-shape failure.
2. `stock_abort_closing <label> [tail]` — emits the `::error::<label> stock-preflight ABORTED …`
   closing line with `class=<c>` interpolated and the per-class advice (single source of truth in
   the lib, byte-neutral at the eight call sites — the workflow file is 485,630 B against the
   490,000 B cap of `plugins/soleur/test/workflow-file-size.test.ts`, so prose moves INTO the lib,
   not into the YAML).
3. `stock_recovery_report <plan_json> [state_json]` — called from a replace job's apply-failure
   branch (or a `if: failure()` sibling step): re-extracts the planned server creates from the
   SAVED plan with the same `@tsv` extraction the gate uses, re-reads `stock_preflight` for each
   (fresh Hetzner read → current class named), optionally reads a post-failure `terraform show -json`
   dump to state `present|absent` per planned address (absent → the re-dispatch plans a bare create;
   present → tainted, plans delete+create), and emits the doctrine block: volumes were never in the
   destroy set, recovery is a NEW dispatch per this job's annotation, never an `[ack-destroy]`
   bypass, never a saved-plan re-apply.

**Item B wiring:** each of the eight `if ! stock_preflight_gate tfplan.json` sites replaces its
hand-written closing echo with `stock_abort_closing <label>` (+ its existing tail where the tail
carries host-specific consequence text). The advisory probe reuses `_STOCK_LAST_CLASS` directly to
prefix its warning with the real class instead of "NOT currently orderable" unconditionally.

## Technical Considerations

- **Byte budget.** `apply-web-platform-infra.yml` is 485,630 bytes; the enforced ceiling is 490,000
  (`workflow-file-size.test.ts`; the real GitHub refusal is 512,000 — #8361). Net YAML delta MUST
  stay under ~4 KB: centralize advice in the lib, keep per-site edits to the helper call, measure
  `wc -c` before/after, and prefer shortening existing comment prose over adding new.
- **Token-in-prose contamination** (learning 2026-10-05, same lib): every new emitted line must be
  grepped against the suite's assertions before commit — a class-advice sentence that literally
  contains `class=stock`/`api_error=` can false-match greps anchoring on those tokens.
- **`_STOCK_LAST_CLASS` staleness**: it is a shell global; a plan-shape abort in
  `stock_preflight_gate` after a probe ran must not report the probe's class. The gate resets it on
  entry and overwrites on each probe failure; `mixed` covers divergence.
- **`terraform show -json` in the failure branch** reads the R2-backed state via the job's
  already-exported backend credentials (AWS_* land in `$GITHUB_ENV` from `infra-credentials`);
  it is a best-effort `|| true` — the report must degrade to "state probe unreadable" lines, never
  abort the annotation the job already prints.
- **`HCLOUD_TOKEN`** reaches every step after `Load infra credentials (tiered)` via `$GITHUB_ENV`
  (loader-exported, #8209) — the recovery step needs no new secret plumbing, only the same
  unreadable-token degrade arm the preflight steps carry.
- NFR impact: none beyond CI/runtime surface (workflow YAML + test lib); see
  `knowledge-base/engineering/architecture/nfr-register.md` — reliability/operability row only.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the worst reachable defect is
  a wrong or missing `::error::` annotation during a prod replace dispatch, or a workflow file that
  crosses the byte cap and refuses to start (CI-gated by `workflow-file-size.test.ts`).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the
  change emits operator-facing log text and adds a read-only Hetzner probe; it does not move user
  data, credentials, or auth surfaces.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this PR narrows a misdiagnosis window on an already
  fail-closed path — it adds no destroy capability, no bypass, and no data-plane change; the
  destructive authorization boundary (menu-ack + gates) is untouched.
- `threshold: none, reason: the diff touches .github/workflows/apply-web-platform-infra.yml (a
  sensitive-path regex match on the web-platform workflow family) but only edits run-log
  annotations and adds a failure-branch diagnostic — no apply scope, no credential, no data surface.`

## Observability

```yaml
liveness_signal:
  what: the stock-preflight PASS/ABORT annotation plus the new `recovery-read` ::error:: block in the apply run log
  cadence: every dispatch that plans a server create; the recovery-read fires only on apply failure
  alert_target: GitHub Actions run annotations; the dispatching operator reads the run log; notify-apply-failure email already exists
  configured_in: tests/scripts/lib/stock-preflight-gate.sh + .github/workflows/apply-web-platform-infra.yml
error_reporting:
  destination: GitHub Actions ::error::/::warning:: annotations in the dispatch run
  fail_loud: true — every abort path already prints; the closing line now carries class=
failure_modes:
  - mode: closing line names the wrong class after a gate abort
    detection: test-suite cases asserting class= propagation per arm; a wrong class fails the suite
    alert_route: CI red on tests/scripts/test-stock-preflight-gate.sh
  - mode: recovery read itself fails (token missing, state unreadable, API down)
    detection: the report prints its own degrade lines (class=unreachable / state probe unreadable) inside the failure branch
    alert_route: ::error:: annotation on the failed run
  - mode: workflow file crosses the byte cap
    detection: plugins/soleur/test/workflow-file-size.test.ts at 490,000 B
    alert_route: required CI check red
logs:
  where: GitHub Actions run logs (apply-web-platform-infra.yml)
  retention: GitHub default run-log retention
discoverability_test:
  command: git grep -l stock_abort_closing .github/workflows/
  expected_output: |-
    apply-web-platform-infra.yml
    web2-luks-rebirth.yml   # sibling site wired during review (9a2d84a35e)
```

The probe proves the class-aware closing helper is wired into the workflow (a site that silently
kept the old literal echo would not carry the token). It is NOT the suite — the suite is how the
functions are TESTED; this is the 15-second liveness read.

## Infrastructure (IaC) and Encryption Posture

Not applicable: no server, secret, vendor, DNS or Terraform resource is created and no persistent
store or new cross-component connection is introduced. The diff references the retained
`hcloud_volume.*` attachments only to describe the recovery they already enable; their existing
at-rest postures (LUKS for workspaces/git-data/inngest stores, provider-managed for the rest) are
unchanged and unmodified. The recovery read's only network call is the same
`GET /server_types?name=` the gate already makes, under the same token, with curl's default
certificate verification.

## Guard Contract

The deliverable includes gate-family machinery (a new sourced-lib diagnostic that re-reads a gate
and a class-propagation channel the closing line depends on), so the contract is written from the
design, before the code.

### Guard 1 — Class propagation to the closing line

**Property.** After `stock_preflight_gate` returns non-zero, `stock_abort_closing`'s emitted line
names the failure class that actually fired (`stock|config|unreachable|malformed|none|mixed`) —
never a hardcoded stock verdict on a config/unreachable/malformed abort.

**Assembly.** Every abort arm in `stock_preflight` (the chokepoint that sets `_STOCK_LAST_CLASS`),
the gate's reset-on-entry and mixed-fold, `stock_abort_closing`'s render switch, and the eight
call sites in `.github/workflows/apply-web-platform-infra.yml` (structural: the workflow-parity
assertion that every `stock_preflight_gate` invocation is followed by the closing helper, not a
hand-written echo).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1.1 | Make one abort arm (say UNKNOWN_LOCATION) skip setting `_STOCK_LAST_CLASS` | RED — its closing-line case prints the stale/none class |
| 1.2 | Remove the gate's `_STOCK_LAST_CLASS` reset on entry | RED — a plan-shape abort after a prior probe reports the probe's class |
| 1.3 | Point one of the eight call sites back at a literal "not orderable" echo | RED — the workflow-parity assertion counts unconverted sites |
| 1.4 | Drop the mixed-fold (two rows failing on different classes report the second only) | RED — the mixed-class fixture must render `class=mixed` |
| 1.5 (harness) | Edit the suite: capture stderr but assert on an empty string | RED-detector — proves the assertion reads the emitted text, not a constant |
| 1.6 (must-PASS, non-canonical) | class=stock abort keeps today's closing semantics verbatim | PASS — stock stays "not orderable … wait and re-fire" |

**Anchor.** None — no stored value is compared; the property is a live render.

### Guard 2 — Recovery read names the class and never authorizes

**Property.** `stock_recovery_report` performs a FRESH `_stock_fetch` per planned create (not a
replayed verdict), prints the current class per create plus the retained-volume doctrine, and
returns non-zero on any internal failure — it can annotate a failure but can never turn one into
a pass or print an `ORDERABLE`-implies-go-ahead line.

**Assembly.** The plan re-extraction (same `hcloud_server`/create/`@tsv` chokepoint as the gate —
extracted to a shared helper so the two can never disagree on what counts as a create), the
per-create `stock_preflight` call, the optional `terraform show -json` state-read arm, and the
doctrine block. The workflow assembly is the set of destroy-first apply steps that call it in
their failure branch — asserted by the same parity check as Guard 1's call sites.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 2.1 | Make the report reuse a cached verdict instead of re-fetching | RED — a fetch-count probe proves a second fetch fired |
| 2.2 | Make the report `return 0` unconditionally | RED — a call under a dead `_stock_fetch` must still report the failure class and exit non-zero |
| 2.3 | Omit the doctrine block (volumes-retained / new-dispatch / no-bypass lines) | RED — the doctrine-token assertions fail |
| 2.4 | Drop `present|absent` state mapping so a tainted host reads "absent" | RED — the tainted-state fixture must not print the bare-create arm |
| 2.5 (harness) | Make the suite's `_stock_fetch` seam serve stock on the re-read but assert only "some error printed" | RED-detector — the class must be NAMED, not just nonzero |
| 2.6 (must-PASS, non-canonical) | A plan with zero planned server creates still prints the doctrine and exits non-zero | PASS-shaped degrade — no crash, no false class |

**Anchor.** None — the assertion surface is emitted text plus the fetch-count seam.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "design a recovery path for a destroy-first replace whose create fails … (2) a documented AND TESTED post-destroy recovery — re-create from the retained volumes, with the stock gate re-read and the failure class named" [issue #9510, Item A] | `stock_recovery_report` + apply-step failure branches + runbook sections + suite cases (FR-1–FR-3, Phase 2–4) | mapped |
| 2 | "the closing line the workflow wrappers print after `stock_preflight_gate` returns non-zero is class-blind … Make it class-aware (or point at the class line)" [issue #9510, Item B] | `_STOCK_LAST_CLASS` + `stock_abort_closing` at the eight sites (FR-4, Phase 1) | mapped |
| 3 | "the advisory probe near the pre-rehearsal step prefixes every non-zero result with 'NOT currently orderable'" [issue #9510, Item B] | class-aware prefix on the probe warning (FR-5, Phase 1) | mapped |
| 4 | "update the recut runbook row that already says so" [issue #9510, Item B] | `registry-luks-recut-6929.md` row + sibling runbook rows (Phase 5) | mapped |
| 5 | "verify target-type stock in the target location BEFORE dispatching" [issue #9510, constraints] | already covered by the existing pre-dispatch `stock_preflight_gate`; the recovery report re-reads it post-failure — no new gate (Research Insights → premise validation) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `_STOCK_LAST_CLASS` + `stock_abort_closing` (lib) | "Make it class-aware (or point at the class line)" | asked |
| `stock_recovery_report` (lib) | "with the stock gate re-read and the failure class named" | asked |
| Eight closing-line call-site swaps (workflow) | "at the `inngest-host-replace`, `registry-host-replace`, `registry-region-migrate`, `registry-luks-recut`, `git-data-host-replace`, `web-host-create`, `web-host-replace` and `git-data-host-create` steps" | asked |
| Advisory-probe class prefix (workflow) | "prefixes every non-zero result with \"NOT currently orderable\"" | asked |
| Apply-failure branches on the six destroy-first steps (workflow) | "a documented AND TESTED post-destroy recovery — re-create from the retained volumes" | asked |
| Same report on the two additive creates' failure branches | — | inferred — justification: a failed `web-host-create`/`git-data-host-create` hits the identical class-misdiagnosis this issue names (a create that failed on stock reads identically to a config fault); ~150 B per site stays inside the byte cap |
| Suite cases + workflow-parity assertions (test file) | "documented AND TESTED" | asked |
| Runbook updates (recut row + web-host/registry rows) | "update the recut runbook row that already says so" | asked |
| Byte-budget measurement + comment trims (workflow) | — | inferred — justification: the file sits ~4 KB under a mechanically enforced 490,000 B cap, so the prose must move into the lib or the diff cannot merge |

### Split Assessment

- Subsystems touched: 3 — `tests/`, `.github/`, `knowledge-base/`
- Planned files: 9 | Estimated changed lines: ~500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — Every `stock-preflight ABORTED` closing line in `apply-web-platform-infra.yml` prints
  the `class=` token that actually fired; `class=stock` keeps "wait and re-fire" advice while
  `config`/`unreachable`/`malformed`/no-class each carry distinct, correct advice.
- [ ] AC2 — The pre-rehearsal advisory probe's warning is class-aware (stock → "not currently
  orderable"; other classes name the class and the correct posture).
- [ ] AC3 — On `terraform apply` failure of a destroy-first replace step
  (`inngest-host-replace`, `registry-host-replace`, `registry-region-migrate`,
  `registry-luks-recut`, `git-data-host-replace`, `web-host-replace`) — and, for the same
  misdiagnosis class, the two additive creates (`web-host-create`, `git-data-host-create`) —
  the run prints a
  recovery-read block that re-fetches stock for every planned create, names the current class,
  states the absent-vs-tainted arms when the state probe is readable, and states the
  retained-volume re-dispatch doctrine with no `[ack-destroy]` bypass.
- [ ] AC4 — `inngest-host-replace`'s apply step gains a failure annotation where none existed.
- [ ] AC5 — `tests/scripts/test-stock-preflight-gate.sh` covers: class propagation per arm,
  mixed/none rendering, the closing helper's per-class text, the recovery report's fresh fetch
  (fetch-count proof), doctrine lines, state-arm mapping, and a workflow-parity assertion that
  every `stock_preflight_gate` call site uses the closing helper.
- [ ] AC6 — `.github/workflows/apply-web-platform-infra.yml` stays under 490,000 bytes.
- [ ] AC7 — `registry-luks-recut-6929.md`'s `stock-preflight ABORTED` row and the recovery sections
  of `web-host-replace.md` / `registry-host-replace-dispatch.md` describe the class-aware lines and
  the recovery read.
- [ ] AC8 — `git grep -n 'stock-preflight ABORTED'` shows zero remaining class-blind closing lines.

## Test Scenarios

- Given a synthesized `UNAVAILABLE` fixture, when `stock_preflight_gate` aborts, then
  `stock_abort_closing` prints `class=stock` and the wait-and-re-fire advice.
- Given `UNKNOWN_TYPE`, an unreachable stub, and a malformed body, when the closing helper runs,
  then each prints its own class token and advice — never the stock wording.
- Given a two-create plan whose probes fail on different classes, when the gate returns, then the
  closing line prints `class=mixed`; given a plan-shape abort (no probe), it prints `class=none`.
- Given a saved plan JSON and a `_stock_fetch` seam counter, when `stock_recovery_report` runs,
  then fetch count increases per planned create and the output names the fresh class, prints the
  volumes-retained + re-dispatch doctrine, and exits non-zero.
- Given a post-failure `terraform show -json` fixture with the planned address present/absent,
  when the report runs, then it prints the corresponding arm (tainted → re-dispatch-this-target;
  absent → the job's documented recovery dispatch).
- Given the workflow file, when the parity assertion runs, then every `stock_preflight_gate`
  invocation is paired with `stock_abort_closing` and every destroy-first apply step names
  `stock_recovery_report`.

## Implementation Phases

### Phase 1 — RED first (cq-write-failing-tests-before)

Extend `tests/scripts/test-stock-preflight-gate.sh` with the AC5 cases (they fail against the
current lib). Then run the suite to confirm the new cases are RED for the right reason.

### Phase 2 — GREEN: the lib

Add `_STOCK_LAST_CLASS` propagation, `stock_abort_closing`, `stock_recovery_report`, and extract
the planned-create jq into a shared helper the gate and the report both call.

### Phase 3 — GREEN: the workflow

Swap the eight closing lines, class-aware-ize the advisory probe, and wire
`stock_recovery_report` into the six destroy-first apply failure branches plus the two additive
creates (inngest gains a branch). Measure `wc -c` at every edit; net delta must hold the byte cap.

### Phase 4 — mutation battery (scratch, not committed)

Mirror `tests/scripts/` into the scratchpad and drive each Guard Contract row RED, per the
predecessor plan's battery shape. Paste the row/verdict table into the PR body.

### Phase 5 — runbooks

Update the `stock-preflight ABORTED` row in `registry-luks-recut-6929.md`, the "If the apply
fails partway" section in `web-host-replace.md`, and the failure/recovery notes in
`registry-host-replace-dispatch.md` to describe the class-aware closing line and the recovery read.

### Phase 6 — verify

Targeted suites only: `bash tests/scripts/test-stock-preflight-gate.sh`, plus
`test-eu-location-allowset-parity.sh` and the registered workflow test suites that grep this file
(run `git grep -l 'stock_preflight\|apply-web-platform' tests/ scripts/`). `actionlint` if
installed. Never dispatch the apply workflow to validate.

## Files to Edit

- `tests/scripts/lib/stock-preflight-gate.sh` — `_STOCK_LAST_CLASS`, `stock_abort_closing`,
  `stock_recovery_report`, shared create-extraction helper, header prose.
- `tests/scripts/test-stock-preflight-gate.sh` — new cases, parity assertions, floor re-measure.
- `.github/workflows/apply-web-platform-infra.yml` — eight closing lines, advisory probe, six
  apply-failure branches.
- `.github/workflows/web2-luks-rebirth.yml` — two same-class closing lines (pre/post gate) plus
  its apply failure branch; found by the `stock_preflight_gate` propagation sweep, same defect.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — the row.
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md` — recovery section.
- `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md` — failure notes.

## Files to Create

None beyond this plan and `knowledge-base/project/specs/feat-one-shot-9510-stock-gate-recovery/{tasks.md,session-state.md,decision-challenges.md}`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (87 issues) searched per planned file path —
zero bodies name them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (workflow annotations,
test lib, runbooks). Mechanical UI-surface override scan of Files-to-Edit/Create: no `*.tsx`,
`app/**/page.tsx`, `components/**` — no UI surface.

## Architecture Decision (ADR/C4)

### ADR

None new. The recovery doctrine — re-dispatch to re-create from retained volumes, never bypass —
is already recorded in ADR-154 §1 ("zero stock makes `-replace` unavailable, not merely
inadvisable"), the #6855 recovery-arm precedent (bare-create arm for absent-from-state), and
ADR-148/ADR-145 for the web-host dispatch split. This plan operationalizes the existing doctrine
with a diagnostic; it does not change who resolves what, adds no trust boundary, and reverses no
prior decision. The rejected alternative (create-before-destroy) is documented here and in the
issue, not in an ADR, because it changes nothing that ships.

### C4 views

No impact. Checked against `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`:
external actors (none added — the same Actions runner and the same Hetzner API), external systems
(Hetzner Cloud already modeled as `hetzner` compute container; the `/server_types` read is an
existing edge), containers/data stores (the volumes already modeled; no new store), and
actor↔surface relationships (the workflow↔Hetzner read edge exists via the gate already). Nothing
the diff adds would mislead a reader of the current models.

## Research Insights

### Premise Validation

- Issue #9510 verified OPEN, `closedByPullRequestsReferences` empty. Its cited predecessor #9505
  (merged 2026-10-05) is context, not a collision — it rebuilt the gate and this issue tracks the
  residual it named.
- The eight class-blind closing lines verified live at apply-web-platform-infra.yml:2090, 2590,
  2832, 3531, 4238, 5162, 5582, 6091; the advisory probe at :3178. The lib emits four `class=`
  tokens (verified at lib lines ~218–278).
- The recut runbook row (~:448) verified — it already says "trust the `class=` line" and must be
  rewritten once the closing line is class-aware.
- `inngest-host-replace`'s apply step (workflow ~:2105) verified to have NO failure annotation —
  the only destroy-first site without one.
- `HCLOUD_TOKEN` verified loader-exported into `$GITHUB_ENV` by
  `.github/actions/infra-credentials/action.yml` (:220–243), so apply-time steps already carry it.
- Byte budget verified: file is 485,630 B; enforced cap 490,000 B
  (`plugins/soleur/test/workflow-file-size.test.ts`, constant pinned under the measured 512,000 B
  GitHub refusal — #8361/ADR-231).
- No open code-review issue touches the planned files (87 issues swept).

### Property List

1. The closing line of a gate abort names the true failure class — never "not orderable" on a
   non-stock abort.
2. The advisory probe's prefix names the true class.
3. A destroy-first apply failure emits a fresh stock re-read naming the current class plus the
   re-dispatch recovery doctrine.
4. The recovery is documented per-target in the runbooks and proven by the suite.
5. The workflow file stays under the byte cap.

### Cut List (mechanism minimality, Phase 0.6b)

| Proposed mechanism | Property it buys | Verdict |
|---|---|---|
| create-before-destroy / transient second host | no post-destroy window at all | CUT — conflicts with retained-volume attach, fixed identity/NIC; rebuilds the #6575-retired standby topology; >> 500-line estimate |
| in-run saved-plan re-apply retry | recovers without a new dispatch | CUT — cannot wait out class=stock (hours timescale); partial-apply saved-plan re-application is not a certified semantic; the new-dispatch path already exists |
| a new dedicated recovery workflow | a distinct operator entry point | CUT — a re-dispatch of the same `apply_target` is the existing, gated, menu-acked route; a new workflow duplicates the 10-input/concurrency surface for no property |
| `_STOCK_LAST_CLASS` + closing helper | P1, P2 | KEEP |
| `stock_recovery_report` | P3 | KEEP |
| runbook edits | P4 | KEEP |

### Institutional learnings applied

- `2026-10-05-the-advice-i-added-to-the-abort-message…` — new prose tokens become assertion
  surface; grep the suite for each new token before commit.
- `2026-09-19-a-sibling-merge-took-the-apply-workflow…` — byte budget; prose lives in the lib.
- `2026-07-23-terraform-destroy-guard…recovery-arm` — a re-dispatch plans a bare create; the
  recovery arm must be named in the message or the operator loops on a refused dispatch.
- `2026-07-15-replace-shaped-ops-are-net-zero…` — a `-replace` frees its own slot; the stranding
  risk is stock, not the account cap (why the re-read is the right diagnostic).
- `plan-gate-preamble.sh` header — every gate invocation must honor the return code; the helper
  calls sit inside `if !` branches, never bare.

### Related issues and PRs

#9505 (predecessor gate rebuild), #9510 (this issue), #6393/#6400 (the ~10h stranding), #6460
(fleet capacity), #6463, #6453, #6575 (warm-standby removal), #6855 (recovery-arm precedent),
#6946, #7044, #7045 (adjacent gate chores — not folded), #8209 (credential loader), #8361/ADR-231
(byte cap).

## Success Metrics

- `git grep -n 'stock-preflight ABORTED' -- .github/workflows` shows only class-aware lines.
- Suite passes with the new cases; mutation battery lands every row.
- The workflow file is < 490,000 B and `actionlint`-clean.

## Dependencies & Risks

- **Byte cap** — the dominant constraint; mitigated by lib-side prose + per-edit `wc -c`.
- **No live validation** — the apply workflow is never dispatched to test (standing rule); the
  suite + parity assertions carry the proof. Residual risk: a YAML-shape slip survives; mitigated
  by actionlint/YAML-parse + byte gate + the parity greps.
- **`_STOCK_LAST_CLASS` is a shell global** — mitigated by the gate's entry reset and the mixed
  fold; a caller that sources the lib mid-step inherits correct semantics.
- **Token absent in the recovery step** — degrades to `class=unreachable` lines, never aborts the
  annotation.

## References & Research

- Gate lib: `tests/scripts/lib/stock-preflight-gate.sh` (header documents the four classes).
- Predecessor plan: `knowledge-base/project/plans/archive/20261005-112710-…-stock-preflight-server-types-locations-plan.md`.
- Recut runbook row: `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` (`stock-preflight ABORTED` row).
- ADR-154 §1; ADR-231 (byte cap); ADR-096/ADR-148/ADR-145 (dispatch arms).

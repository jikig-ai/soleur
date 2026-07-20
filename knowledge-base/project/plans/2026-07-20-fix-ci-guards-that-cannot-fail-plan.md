---
title: "fix: two CI guards that structurally cannot fail (#6766, #6774)"
date: 2026-07-20
type: fix
lane: cross-domain
issues: [6766, 6774, 6480]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-6766-6774-ci-guards-cannot-fail
revision: v2 (post 2-agent plan-review — architecture-strategist + spec-flow-analyzer)
---

# fix: two CI guards that structurally cannot fail (#6766, #6774)

## Enhancement Summary

**Deepened on:** 2026-07-20
**Prior pass:** 2-agent plan-review (architecture-strategist + spec-flow-analyzer) → v2, 14 findings applied (§Plan Review Findings)
**This pass:** gates 4.4/4.5/4.55/4.6/4.7/4.8/4.9, verify-the-negative sweep, live attribution probes

### Key improvements
1. **Verdict-script contract specified** — exact 5-arg signature and a 6-row allow-list
   table for `scripts/infra-validate-gate-verdict.sh`, diffed against the
   `tenant-integration-gate-verdict.sh` precedent (which was read in full, not paraphrased).
   The `detect ≠ success ⇒ fail` row is called out as a second, independent defence for F3.
2. **`merge_group` routing precedent captured** — both sibling required workflows handle it
   as an explicit *first* branch with a written rationale; copy verbatim.
3. **Verification ledger added** — 16 load-bearing claims probed, all confirmed, none
   contradicted. Covers every negative claim, every cited PR/issue, the ADR ordinal, the
   labels, and the AGENTS rule IDs.
4. **Gate dispositions recorded** — including two *false* triggers (4.5 network-outage
   matches only Check 10's SSH reject-regex prose; 4.9 UI matches only the Product/UX
   Gate's own negation), so a later reader does not re-litigate them.

### New considerations discovered
- The verdict script's `detect ≠ success` arm is load-bearing beyond its obvious purpose:
  it is what makes an unrouted `merge_group` fail loudly rather than pass green.
- `substRejectReason`'s operator-facing message string must survive the function split
  verbatim — helper-split message drift is a known dashboard-regression class.
- `git diff --name-only` includes deletions; guardrail 4 avoids the class entirely by
  grepping the tree at HEAD rather than iterating the diff path list.
- ADR-130 re-derived from a **freshly-fetched** `origin/main` (not the branch base), per
  the stale-ordinal failure mode.

## Overview

Two guards assert a property they cannot actually verify.

- **#6766** — `.github/workflows/infra-validation.yml` runs only on `pull_request`
  (path-filtered) and `workflow_dispatch`. Nothing re-runs it against `main`, and none
  of its jobs is a required status check. A red loopback suite therefore neither blocks
  a merge nor produces a post-merge signal.
- **#6774** — `preflight` Check 10 rejects every shell-active token (including `|`)
  before executing `discoverability_test.command`. Correct as injection defence, but it
  means no log-grep discoverability test can ever pass — and log-grep is the only way to
  observe an emitter that fires *during a run* rather than *at an endpoint*.

Both are `ci/guard-broken`. The unifying failure class is **a check that certifies a
different property than the one it names** — and this plan must not commit that same
error while fixing it.

> No `spec.md` exists for this branch (the one-shot path entered plan directly), so
> `lane:` could not be carried forward — defaulted to `cross-domain` (TR2 fail-closed).

**Two findings reshaped this plan.** (1) The issue's own prescribed ordering is inverted
and, executed as written, would wedge every PR in the repository (§R1). (2) Plan-review
found that the first draft's own aggregator would have shipped green on the exact case
#6766 exists to catch (§Plan Review Findings, F1) — the same defect class, one level up.

## Delivery shape: two PRs, workflow-first

**PR A** — workflow routing (#6766 Gap 1) + the whole of #6774 + ADR-130.
Closes **#6774**. The ruleset is untouched, so there is no window in which a context is
required but not posted.

**Verification gate between A and B** — after A merges, open any docs-only PR and confirm
`infra-validate-required` posts a **terminal** state (not "Expected — Waiting"). This is
an *empirical* check that GitHub actually posts the context; the static parity test can
only confirm string membership across three files.

**PR B** — the ruleset flip + the `*-required` drift detector.
Closes **#6766** and **#6480**.

**Why not one PR** (this reverses the v1 decision): v1 argued single-PR atomicity because
"a split leaves a live window where the context is required but never posted." That is
true only of the *ruleset-first* split. Workflow-first has no such window, and it retires
the single Critical-rated risk in §Risks by empirical observation rather than by a string
test. At `single-user incident` threshold the extra merge is cheap insurance. The detector
ships in **PR B** so that "zero exemptions" (AC7) holds the moment it exists.

## Research Reconciliation — Spec vs. Codebase

| # | Issue / ARGUMENTS claim | Codebase reality (verified) | Plan response |
|---|---|---|---|
| **R1** | "Gap 2 first (lowest risk, stops the bleeding): add `deploy-script-tests` as a required context." | **False, and inverted.** `infra-validation.yml` `on: pull_request:` carries a `paths:` filter (`:11-47`). A path-filtered workflow posts **no status context at all** on a PR it does not match. A required context that never posts sits at *"Expected — Waiting for status"* **forever** — every non-infra PR becomes unmergeable. Stated verbatim in the workflow's own comment (`:246-263`), verified by four review agents during #6458, and the entire subject of open issue **#6480** ("**Do not simply add the context to the ruleset**"). | **Reject the stated ordering.** Enabling work first (PR A), ruleset flip last (PR B). Surfaced as a User-Challenge — §Decision Challenges. |
| **R2** | Implied: `deploy-script-tests` is the right job to make required. | It is a 12-minute job (`timeout-minutes: 12`, `:287`) that builds an alpine+bubblewrap image. Both `-required` precedents (`tenant-integration-required`, `sentry-destroy-required`) are **cheap static-named `if: always()` aggregators**. `infra-validate-required` already exists in that shape (`:264-283`). | Make **`infra-validate-required`** the required context and **fold `deploy-script-tests`' result into it**. Delivers the issue's intent without a 12-min build on every PR's critical path. |
| **R3** | Implied: gating `deploy-script-tests` on `detect-changes` is straightforward. | **It under-triggers.** `directories` enumerates *terraform roots only*. The `paths:` list deliberately includes non-`infra/` paths (`restart-inngest-server.yml`, `apply-inngest-rls*.yml`, `.github/scripts/validate-infra-templates.sh`, `scan-workflow.yml`, `model.c4`) because `deploy-script-tests` runs cross-file drift guards over them. | `detect-changes` gains a **second output** `suite_relevant` from the *full `paths:` union*. `directories` keeps its matrix meaning. Confirmed by architecture review as the only correct decomposition. |
| **R4** | "add `deploy-script-tests` to the ruleset's 20 contexts." | Adding one context needs **four** coordinated edits or CI reds: (1) `infra/github/ruleset-ci-required.tf`; (2) `scripts/ci-required-ruleset-canonical-required-status-checks.json` (**T-rsc-9** byte-equality); (3) the hardcoded `"20"` in **T-rsc-7** (`tests/scripts/test-audit-ruleset-bypass.sh:642`); (4) `scripts/required-checks.txt` (bot PRs deadlock otherwise). Spec-flow confirmed this list is **complete** — all other consumers read the SSOT files. | All four in PR B, §Files to Edit. |
| **R5** | Part 2: "check that every `*-required` job name is in the ruleset." | Exactly **three** such jobs: `tenant-integration-required` (present), `sentry-destroy-required` (present), `infra-validate-required` (**absent**). A `scheduled-inngest-health.yml:805` hit is a **step** name — the detector must scope to `jobs:` children. | Written as specified, in PR B so it passes with **zero exemptions**. Extended per review to also assert *postability* (§F6). |
| **R6** | Implied: `merge_group:` is a live blocker. | **The merge queue is DISABLED.** `test-audit-ruleset-bypass.sh` **T-mq-1** fails CI if a `merge_queue` rule reappears (reverted per #5780 — CodeQL default setup does not post on `merge_group` temp refs). Confirmed: `merge_queue` appears in the `.tf` only inside the #5780 comment at `:36`. | Adding `merge_group:` is prophylactic — but it **must be routed**, not just declared (§F3). |
| **R7** | #6774: "the pipe is the blocker." | **Three independent blockers.** `SUBST_REJECT_RE` (`discoverability-test-parser.ts:33`) has bare `\|`, bare `<`, bare `>` — `gh run view <run-id> --log \| grep MARKER` trips all three. `<run-id>` is a **placeholder**: no run exists at preflight time. And `expected_output: >-` is captured by `parseExpected` as the literal `">-"`. | Confirms direction 1 cannot work — §Direction Evaluation. |
| **R8** | Direction 2: "so a post-merge check can assert it." | **Achievable with existing machinery.** `scripts/followthroughs/` (41 scripts), `scheduled-followthrough-sweeper.yml` (daily cron), and a direct precedent — `scripts/followthroughs/cert-reissue-markers-6698.sh` is literally a marker-presence probe. | Recorded; enrollment **scoped out** with a deferral issue (§Non-Goals). |
| **R9** | Implied: a `kind:` sub-field may break schema parity. | `observability-schema-parity.test.ts` `topLevelKeys()` matches `/^([a-z_]+):/` — **column-0 only**. An *indented* `kind:` is invisible; `CANONICAL.length === 5` stays green. | `kind` is added strictly **indented**. Column-0 is a hard error (AC12). |
| **R10** | "#6766 and #6774 are two independent issues." | #6766's Gaps 1 and 2 are prerequisites-of / prerequisite-to open issue **#6480**, whose scope is a superset of #6766 parts 1 and 3. | Plan closes **#6766, #6774, #6480**. |
| **R11** | *(new, v2)* Implied: the LUKS plan's marker can satisfy a diff-presence check. | `git grep -lF SOLEUR_WORKSPACES_LUKS_FSCK -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` → **present** in `apps/web-platform/infra/workspaces-cutover.sh` and `workspaces-luks-loopback.test.sh`. | Guardrail 4 is redefined as **present-at-HEAD outside planning artifacts** (§F4), which this satisfies — so Phase 7.6 is safe to ship. |

## Plan Review Findings (v1 → v2)

Two agents (architecture-strategist, spec-flow-analyzer) reviewed v1. Findings applied:

| # | Finding | Severity | Resolution in v2 |
|---|---|---|---|
| **F1** | **The aggregator would ship green on #6766's own headline case.** `infra-validate-required`'s existing step opens with `if [[ "$DIRS" == "[]" ]]; then exit 0`. A PR touching only `restart-inngest-server.yml` gives `directories='[]'`, `suite_relevant='true'`, `deploy-script-tests` **red** → early `exit 0` → **green, merges**. v1's AC5 only required the string `needs.deploy-script-tests.result` to *appear* — a reference in unreachable code after `exit 0` satisfies it. | **P0** | Extract **`scripts/infra-validate-gate-verdict.sh`** as an **allow-list** over `needs.*.result`, mirroring the existing `scripts/tenant-integration-gate-verdict.sh` + `tests/scripts/test-tenant-integration-gate-verdict.sh` precedent (both verified present). Any unenumerated state fails closed. Unit-tested; AC5 rewritten to assert **behaviour**, not string presence. New T13–T17. |
| **F2** | **`kind: run-log` bypasses the SSH reject.** `rejectReason` fuses SSH + subst checks; branching before it lets `kind: run-log` + `command: ssh host 'grep MARKER …'` return SKIP — defeating `hr-no-ssh-fallback-in-runbooks`, a **larger** downgrade than the one direction 3 was rejected for. v1 also specified TS and bash inconsistently (bash keeps the ssh reject, TS drops it). | **P0** | Split into `sshRejectReason` (**always** runs, both kinds) and `substRejectReason` (live-probe only). Bash order is explicit: ssh-reject (end of 10.4) → **10.4b** → subst-reject (10.5). New T18. |
| **F3** | **`merge_group:` declared but never routed.** On `merge_group`, `base_ref` is empty → `git diff origin/...HEAD` → fatal → `detect-changes` fails → the required aggregator reds **every queue candidate**. Both sibling workflows branch on it explicitly. | **P0** | Route `merge_group` as an explicit **first** branch → `directories='[]'`, `suite_relevant=false` → aggregator PASSes via the `suite=skipped` path, exactly matching `tenant-integration.yml` / `apply-sentry-infra.yml:99-102`. New T19. |
| **F4** | **Guardrail 4 was not implementable and was vacuous.** (a) `ClassifyInput` has no diff input, so fixtures 09 and 11 are indistinguishable; (b) `preflight-diff-files.txt` holds **filenames, not contents** — grepping it can never match a marker; (c) the plan file itself contains the marker, so a diff-set grep **always** matches; (d) "added by this diff" vs "present at HEAD" was undefined, and the former false-FAILs the legitimate emitter-landed-earlier case. | **P0** | Redefined: **`git grep -F -- "$MARKER" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` at HEAD**, non-empty ⇒ satisfied. Excludes planning artifacts (kills the vacuity), uses contents not names, and accepts an emitter from an earlier PR. `ClassifyInput` gains `markerLookup: (marker: string) => boolean` (injected, keeps the parser pure and the fixtures distinguishable) — added to §Files to Edit. |
| **F5** | **`kind: run-log` placed no constraint on `command` at all** — a plan could declare `run-log` + valid marker + the literal #4148 typo'd curl and get a SKIP. On that axis direction 2 was *weaker* than direction 3. | **P1** | **Guardrail 5**: under `run-log`, `command` must contain the marker literal, else FAIL. New T20. |
| **F6** | **The detector enforced membership but not postability.** A future `*-required` job inside a `paths:`-filtered workflow with no `merge_group:` satisfies all three surfaces and still wedges every PR — R1 recurring, now with a green guard certifying it. | **P1** | Detector also asserts: any workflow containing a `*-required` job has **no `pull_request.paths:` key** and **does** declare `merge_group:`. New T7b. |
| **F7** | **No `concurrency:` group** on a workflow about to fire on every PR and every push to main, with a 12-min job inside. Superseded runs stack unbounded. `tenant-integration.yml` carries one with a written rationale. | **P1** | Workflow-level `concurrency: group: infra-validation-${{ github.event.number \|\| github.ref }}`, `cancel-in-progress: true`. Rationale recorded (unlike tenant-integration, no required-context-on-cancel hazard here because PR A ships before the context is required, and the aggregator re-runs on the new head SHA). |
| **F8** | **Gating `check-secrets` on `suite_relevant` is net-negative** — it is a checkout-free `[[ -n ]]` test costing seconds; gating serializes it behind a `fetch-depth: 0` clone and couples `plan`'s skip semantics to `suite_relevant`. | **P2** | `check-secrets` left **ungated**. Only `deploy-script-tests` is gated. |
| **F9** | **Five stale "8 states / 8 fixtures" anchors** the plan didn't touch; AC10's `≥10 rows` leaves the prose wrong and green — the same class this plan is about. | **P2** | All five added to §Files to Edit, gated by **AC20**. |
| **F10** | `kind` is unreachable in **Form B** (prose+fence); a prose `Kind: run-log` silently classifies as `live-probe`. | **P2** | **Guardrail 6**: if the block contains a case-insensitive `kind` token but `parseKind` returns null ⇒ **FAIL** (malformed, fail-closed). Documented as Form-A-only. New T21. |
| **F11** | `marker:` present with `kind: live-probe` or `kind` absent was undefined/ignored. | **P2** | **Guardrail 7**: `marker:` without `kind: run-log` ⇒ **FAIL**. New T22. |
| **F12** | `pull_request:` branches filter unspecified after `paths:` removal. | **P2** | Explicitly `pull_request: branches: [main]`, matching `tenant-integration.yml`. AC1 checks it. |
| **F13** | No pre-merge lint of the workflow; an unparseable `infra-validation.yml` post-flip wedges every PR and AC19 detects it one PR too late. | **P1** | **AC21**: `actionlint` on the workflow pre-merge (workflow file, not a composite action — `actionlint` is correct here). The A/B split (§Delivery shape) is the primary mitigation. |
| **F14** | `push` + enumerate-all runs the full matrix + the 12-min job on **every** commit to main; a `github.event.before` diff would be far cheaper. | **P1** | **Accepted trade-off, recorded.** A diff-based push only catches redness *this merge introduced*; #6766's defining complaint is that main can be red **indefinitely** from an earlier cause, which only enumerate-all detects. Mitigated by F7's `cancel-in-progress`. Cheaper alternative (nightly `schedule:` instead of every push) recorded in §Alternatives Considered. |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (61 open) against every
path in §Files to Edit.

- **#4133** — "follow-through(#4116): Schema parity test for `## Observability` block".
  **Disposition: acknowledge.** The parity test it asks for already exists
  (`plugins/soleur/test/observability-schema-parity.test.ts`); this plan's obligation is
  to keep it green (R9), not re-implement it. Separate lifecycle.
- No other open code-review issue references `infra-validation.yml`,
  `ruleset-ci-required.tf`, `preflight/SKILL.md`, `discoverability-test-parser`, or
  `required-checks.txt`.

## User-Brand Impact

- **If this lands broken, the user experiences:** every pull request in the repository
  wedged at *"Expected — Waiting for status"* with no merge path — the founder's agent
  cannot ship anything at all, and the failure is **silent** (a pending check, not a red X).
  The escape hatch exists but is non-obvious: `bypass_actors` in
  `infra/github/ruleset-ci-required.tf` grants OrganizationAdmin `bypass_mode = "pull_request"`.
- **If this leaks, the user's workflow is exposed via:** no new data surface. The one
  adjacent exposure is that adding a context to `scripts/required-checks.txt` makes bot
  PRs post a **synthetic green** for it (#6049 auto-fabrication guard) — mitigated in
  PR B by the composite action's `ALLOWED_PATHS` argument.
- **Brand-survival threshold:** single-user incident

**Rationale:** a mis-flipped ruleset is repo-wide and immediate; one bad merge blocks the
operator's entire delivery pipeline. `requires_cpo_signoff: true`; `user-impact-reviewer`
runs at review time. The A/B split exists specifically to lower this risk.

## Direction Evaluation (#6774) — three directions, one chosen

| Direction | Verdict | Rationale |
|---|---|---|
| **1. Allow a safe-listed pipeline shape** (single `\| grep <literal>` via argv, not `bash -c`) | **Reject** | Decisive: **the blocker is not the pipe, it is the absence of a subject.** Per R7 the command is `gh run view <run-id> …`; `<run-id>` does not exist at preflight time because the run has not happened. A perfect argv executor still cannot run it. Also adds a second execution mode — new attack surface — for zero coverage gain. |
| **2. Add `discoverability_test.kind`** (`live-probe` \| `run-log`) | **Choose** | Makes the distinction the gate is *implicitly* drawing explicit and reviewable. `live-probe` keeps today's behaviour byte-for-byte (no downgrade for the #4148 class). `run-log` returns SKIP-with-recorded-marker instead of a false FAIL. Per R8 the post-merge substrate already exists; per R9 the schema change is parity-safe. |
| **3. Leave live-probe-only, make the SKIP explicit** | **Reject** | With no field, Check 10 must **infer** "this is a run-log test" from the command's shape — exactly the "gate implicitly drawing a distinction" problem the issue names. It cannot record the marker, so nothing downstream can assert anything. Worst, it degrades toward "any command we cannot run → SKIP", which **is** the silent downgrade the issue forbids: a genuinely broken live probe would start passing. |

### Anti-downgrade guardrails (load-bearing — this is what makes direction 2 not a downgrade)

All fail-closed. Guardrails 4–7 were added or rewritten in v2 after review.

1. **Absent `kind` ⇒ `live-probe`.** Every existing plan behaves exactly as today.
2. **Unknown `kind` value ⇒ FAIL** (not SKIP, not default).
3. **`kind: run-log` requires `marker:`** matching `^[A-Za-z0-9_]+$`. Missing/malformed ⇒ **FAIL**.
4. **The marker must exist in the codebase outside planning artifacts.**
   `git grep -F -- "$MARKER" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
   at HEAD must be non-empty, else **FAIL**. Excluding plans/specs is load-bearing: the
   marker appears in the plan by construction, so without the exclusion the check is
   vacuous (F4c). Present-at-HEAD (not added-by-this-diff) so an emitter that landed in
   an earlier PR is accepted (F4d).
5. **The `command` must contain the marker literal** under `run-log`, else **FAIL** — so
   `run-log` cannot certify a command that has nothing to do with the marker (F5).
6. **A `kind` token present but unparseable ⇒ FAIL.** `kind` is **Form A only**; a prose
   `Kind: run-log` in a Form B block must fail loudly, not silently default (F10).
7. **`marker:` without `kind: run-log` ⇒ FAIL** (F11).

**The SSH reject is never bypassed.** It runs unconditionally for both kinds (F2).

Guardrails 4 + 5 together make `run-log` a **stronger** check than direction 3 offers:
they verify that a real emitter exists and that the command actually names it. That is the
core of the not-a-downgrade argument.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-130 — "`discoverability_test.kind`: live-probe vs run-log, and the
`*-required` suffix as an enforceable convention."** Two coupled decisions, one record:

1. The observability contract gains an explicit **kind discriminator**. A gate that
   cannot observe a property must say *which* property it declines to observe, and must
   still assert the checkable remainder (guardrails 4–5). Directions 1 and 3 go in
   `## Alternatives Considered` with the §Direction Evaluation rationale.
2. The `*-required` suffix is promoted from **convention** to **mechanically enforced
   invariant** — membership in all three ruleset surfaces **and** postability (no
   `pull_request.paths:`, `merge_group:` present, per F6). Records that enforcement is
   only honest once `infra-validate-required` is genuinely required (hence #6480), and
   that **no exemption allowlist** is introduced — an exemption list would recreate the
   defect class.

Record in the ADR the caveat surfaced at review: the aggregator observes **job** results,
so a `continue-on-error` step inside `deploy-script-tests` stays invisible — a
pre-existing property of `infra-validation.yml`, not a regression.

Ordinal 130 is **provisional** (next free after ADR-129); `/ship`'s ADR-Ordinal Collision
Gate re-verifies against `origin/main`. On renumber, sweep
`grep -rn 'ADR-130' knowledge-base/project/{plans,specs}/feat-one-shot-6766-6774-ci-guards-cannot-fail/`
plus the ADR body **and AC13**.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) per the
completeness mandate:

- **External human actors:** none added or changed. Entirely operator-internal (CI gates
  + a plan-authoring schema). No new correspondent, reviewer, or recipient role.
- **External systems / vendors:** none added. GitHub Actions and the GitHub rulesets API
  are the only externals touched; both already sit inside the modelled CI/GitHub
  boundary. No new webhook, third-party API, or data store.
- **Containers / data stores:** none created, removed, or repointed.
- **Actor↔surface access relationships:** unchanged. Required-status-check membership is
  an attribute of an already-modelled CI gate, not a new access edge; no ownership or
  sharing semantics change.

### Sequencing

Both decisions are true at merge of PR B. ADR-130 ships in **PR A** with
`status: accepted` and a one-line note that clause 2's enforcement lands in PR B.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Single atomic PR (v1's choice) | **Rejected** in v2 — workflow-first split has no required-but-unposted window and allows empirical verification of context posting before the flip (F, §Delivery shape). |
| Make `deploy-script-tests` itself the required context (the issue's literal ask) | **Rejected** — a 12-min docker build on every PR's critical path; both precedents use a cheap aggregator (R2). Intent preserved by folding its result in. |
| `push` diff against `github.event.before` instead of enumerate-all | **Rejected** — only catches redness *this merge* introduced; #6766's complaint is indefinite redness from an earlier cause (F14). |
| Nightly `schedule:` instead of `push:` for main visibility | **Rejected for now** — up to 24h of blind time, and #6745's red suite would have been invisible for a full day. Recorded as the fallback if push-cost proves unacceptable. |
| Exemption allowlist in the `*-required` detector | **Rejected** — would recreate the "guard that claims teeth it lacks" defect class (R5). PR B ordering makes it unnecessary. |
| Refactor `parseCommand`/`parseExpected` into a single struct return | **Rejected** — high churn across every existing test for no functional gain; `parseKind`/`parseMarker` as siblings matches existing style. |

## Non-Goals / Out of Scope

- **Follow-through enrollment wiring for `kind: run-log`** (R8). The substrate exists,
  but auto-generating a `scripts/followthroughs/<name>-<issue>.sh` from a `kind: run-log`
  declaration is a new coupling between the plan schema and the sweeper. Guardrails 4–5
  assert the preflight-checkable half. **Deferral issue filed** (Phase 8.2), labels
  `chore` + `priority/p3-low` (both verified to exist), re-evaluation criterion:
  *"when a second plan declares `kind: run-log`."*
- **Reversing the bot-synthetic fabrication** (#6049 class). PR B documents the
  `ALLOWED_PATHS` argument in `required-checks.txt` per the `sentry-destroy-required`
  precedent; a per-check synthesis opt-out is separate work.
- **`scripts/post-bot-statuses.sh`** — verified at review to have **zero callers** across
  `.github/workflows/` and `scripts/`. Genuinely dead, not a latent wedge. Untouched.
- **Re-enabling the merge queue** (#5780, blocked on CodeQL advanced setup). This plan
  only makes `infra-validation.yml` *ready* for it (F3).
- **Relocating `fixtures-validate-infra-templates.sh`** into a terraform-carrying required
  job (#6480 bullet 6) — folding `deploy-script-tests` into the required aggregator
  satisfies the intent without the physical move.

## Implementation Phases

> **Phase order is load-bearing.** Phases 1–3 are the enabling contract change; Phase 4 is
> the ruleset flip that depends on them **and ships in a separate PR** after empirical
> verification. Reversing this order is exactly the R1 defect.

### PR A — Phases 0–3, 5–8

### Phase 0 — Preconditions (verify before editing)

0.1 Deadlock premise still holds on `origin/main`:
`git show origin/main:.github/workflows/infra-validation.yml | awk '/^on:/{f=1} f{print} /^jobs:/{exit}'`
→ expect `pull_request:` **with** `paths:`, no `push:`.
0.2 Merge-queue-off still holds:
`grep -vE '^[[:space:]]*#' infra/github/ruleset-ci-required.tf | grep -cE 'merge_queue[[:space:]]*\{'` → `0`.
0.3 Context-count baseline: `jq length scripts/ci-required-ruleset-canonical-required-status-checks.json` → `20`.
0.4 `yaml` importable in the bun shard: `grep -n '"yaml"' package.json`.
0.5 Verdict-script precedent readable:
`cat scripts/tenant-integration-gate-verdict.sh tests/scripts/test-tenant-integration-gate-verdict.sh`
— PR A copies this shape (F1).
0.6 Marker precondition for Phase 7.6:
`git grep -lF SOLEUR_WORKSPACES_LUKS_FSCK -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
→ non-empty (verified: `apps/web-platform/infra/workspaces-cutover.sh`).
0.7 Baseline green before any edit: `bash tests/scripts/test-audit-ruleset-bypass.sh`,
`bash plugins/soleur/test/required-checks-canonical-parity.test.sh`,
`bash plugins/soleur/test/infra-validation-detect.test.sh`,
`bun test plugins/soleur/test/observability-schema-parity.test.ts plugins/soleur/test/preflight-discoverability-test.test.ts`.

### Phase 1 — RED: tests for the workflow-routing contract

1.1 Extend `plugins/soleur/test/infra-validation-detect.test.sh` with `detect_event_route()`
mirroring the event-routing branch (the existing `detect_infra_dirs()` models only the
pathspec collapse). Cases: `pull_request` → diff; `workflow_dispatch` → enumerate-all;
**`push` → enumerate-all**; **`merge_group` → empty + `suite_relevant=false`** (F3).
Assert the `push` and `merge_group` cases never emit `origin/...HEAD`.
1.2 Add `detect_suite_relevant()` mirror, including the case proving a diff touching
**only** `.github/workflows/restart-inngest-server.yml` yields `suite_relevant=true` (R3).
1.3 New `tests/scripts/test-infra-validate-gate-verdict.sh`, modelled on
`tests/scripts/test-tenant-integration-gate-verdict.sh`, covering the F1 matrix —
crucially `dirs='[]' suite_relevant=true deploy=failure` ⇒ **FAIL**.
**Register it** via a `run_suite` line in `scripts/test-all.sh`: `tests/scripts/*.sh` is
**not** globbed, and `scripts/lint-orphan-test-suites.sh` reds on an unregistered suite.

### Phase 2 — GREEN: `detect-changes` event routing + `suite_relevant`

2.1 Add `suite_relevant` to the job's `outputs:`.
2.2 Route on `EVENT_NAME`, **`merge_group` first** (F3): `merge_group` → `directories='[]'`,
`suite_relevant=false`; `workflow_dispatch` or `push` → enumerate all infra roots;
else → the existing `git diff origin/${BASE_REF}...HEAD` pipeline. Keep the
`{ grep -E … || true; }` brace group and the `#4012` comment intact.
2.3 Compute `suite_relevant` from the **full union** of the paths currently in the
workflow-level `paths:` block, evaluated against the PR diff. `true` unconditionally on
`push`/`workflow_dispatch`; `false` on `merge_group`. **Move the `paths:` rationale
comments into this step verbatim** — they are the only record of why each non-infra path
is listed.

### Phase 3 — GREEN: triggers, gating, concurrency, aggregator

3.1 **`on:`** — add `push: branches: [main]`; add `merge_group:`; set
`pull_request: branches: [main]` and **remove the workflow-level `paths:` filter** (F12).
Replace it with a comment pointing at `detect-changes` as the new path authority and at #6480.
3.2 **Workflow-level `concurrency:`** (F7): `group: infra-validation-${{ github.event.number || github.ref }}`,
`cancel-in-progress: true`, with a written rationale comment.
3.3 **Gate only `deploy-script-tests`**: `needs: detect-changes` +
`if: needs.detect-changes.outputs.suite_relevant == 'true'`. **Leave `check-secrets`
ungated** (F8) — it is a checkout-free seconds-long secret presence test.
3.4 **`plan` job** — add `github.event_name == 'pull_request'` to its `if:` (it posts a PR
comment; its concurrency group degenerates to `github.run_id` off-PR; this also keeps
`secrets.DOPPLER_TOKEN` off the push and merge_group paths).
3.5 **`infra-validate-required`** — `needs: [detect-changes, validate, deploy-script-tests]`,
`if: always()`. **Replace the inline gate step** (which early-`exit 0`s on `$DIRS == "[]"`
and would ship green on #6766's own case — F1) with a call to new
**`scripts/infra-validate-gate-verdict.sh`**: an allow-list over `needs.*.result` +
`directories` + `suite_relevant`, where any unenumerated state fails closed. Update the
stale `DO NOT make this a required context yet` comment block to record that the
prerequisites are now met and that the flip lands in PR B.

### Phase 5 — RED: tests for `discoverability_test.kind`

5.1 New fixtures in `plugins/soleur/test/fixtures/preflight-check-10/` — synthetic only,
`issue: 9999` (`cq-test-fixtures-synthesized-only`): `09-run-log-pass.md`,
`10-run-log-no-marker.md`, `11-run-log-marker-absent.md`, `12-unknown-kind.md`,
`13-run-log-ssh.md` (F2), `14-run-log-command-lacks-marker.md` (F5),
`15-form-b-kind-token.md` (F10), `16-marker-without-run-log.md` (F11).
**Fixtures are loaded by hardcoded filename** via `fx(...)` — an unreferenced fixture is
silently dead, so each needs an explicit `test(...)` call site.
5.2 Add the eight cases plus a regression test asserting a fixture **without** `kind:`
classifies exactly as today (guardrail 1).

### Phase 6 — GREEN: implement `kind` in parser + SKILL.md

6.1 `plugins/soleur/test/lib/discoverability-test-parser.ts`:
- **Split `rejectReason`** into `sshRejectReason` (always) and `substRejectReason`
  (live-probe only) — F2. Keep `rejectReason` as a thin back-compat wrapper if any caller
  depends on it.
- Add `parseKind(block): "live-probe" | "run-log" | null` and `parseMarker(block): string | null`
  as **siblings** (do not refactor `parseCommand`/`parseExpected` into a struct).
- Widen `ClassifyInput` with `markerLookup: (marker: string) => boolean` (injected, keeps
  the function pure and makes fixtures 09/11 distinguishable — F4a).
- Widen `ClassificationResult` with optional `marker?: string`.
- Order in `classifyDiscoverabilityResult`: `sshRejectReason` → **kind resolution +
  guardrails 2–7** → `substRejectReason` (live-probe only) → runner.
- The SKIP `reason` must contain the tokens `run-log` and the marker literal (tests assert
  reasons by loose regex).

6.2 `plugins/soleur/skills/preflight/SKILL.md` Check 10:
- Add **Step 10.4b** (kind resolution + guardrails) **after** the Step 10.4 ssh reject and
  **before** the Step 10.5 subst reject — the bash is the runtime and its order is
  authoritative (F2).
- Guardrail 4's shell form is
  `git grep -F -- "$MARKER" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
  — **not** a grep of `preflight-diff-files.txt`, which holds filenames (F4b).
- Add matrix rows 9–12 to Step 10.6 (run-log valid → SKIP; guardrail violations → FAIL);
  update the **Result** block. Cite
  `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`
  in the SKIP row's Rationale — *"SKIP only when truly indeterminate"*, and a run not yet
  executed is genuinely indeterminate.
- **Do not touch** the `SENSITIVE_PATH_RE` literal, the ssh reject regex string, the
  `Form A`/`Form B` strings, or the fast-path SKIP table row — four tests assert them verbatim.
- **Update the five stale "8 states / 8 fixtures" anchors** (F9).

### Phase 7 — GREEN: propagate the schema to its other surfaces

7.1 `plugins/soleur/skills/plan/references/plan-issue-templates.md` — add `kind:` (and
`marker:`) as **indented sub-fields** of `discoverability_test` in **all three** blocks
(MINIMAL `:36`, MORE `:164`, A LOT `:306`). **Column-0 is a hard error** (R9/AC12).
7.2 `plugins/soleur/skills/plan/SKILL.md` §2.9 canonical block — update the
`discoverability_test:` **trailing comment only** (`# kind / marker / command (NO ssh) / expected_output`).
The comment form keeps `topLevelKeys()` at 5.
7.3 `plugins/soleur/skills/deepen-plan/SKILL.md` §4.7 — add reject bullets mirroring
guardrails 2, 3, 6, 7 at authoring time. **Keep `the 5 required top-level fields` verbatim**
— `kind` is a sub-field and the parity guard reads that enumeration.
7.4 `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js` `:83-84`, `:236`
— manual prose sync (not covered by the parity guard).
7.5 `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` `:106-108`
— note the `kind` distinction in the no-SSH check step.
7.6 **Proof the fix works:** update
`knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md`'s
`## Observability` block to `kind: run-log` + `marker: SOLEUR_WORKSPACES_LUKS_FSCK`, fix its
`expected_output: >-` folded scalar (captured today as the literal `">-"`, R7), and make
its `command` contain the marker (guardrail 5). Safe to ship: Phase 0.6 verified the
marker is present at HEAD in `apps/web-platform/infra/workspaces-cutover.sh` (R11).

### Phase 8 — ADR, deferral, docs

8.1 Write ADR-130 per §Architecture Decision via `/soleur:architecture`.
8.2 File the follow-through-enrollment deferral issue (§Non-Goals), labels `chore` +
`priority/p3-low` (verified present).
8.3 ~~CHANGELOG entry.~~ **Plan error, corrected at /work: there is no root
`CHANGELOG.md`.** `git ls-tree origin/main --name-only | grep -ci changelog` → `0`;
the changelog is derived from the GitHub API at docs-build time by
`plugins/soleur/docs/_data/changelog.js`. The only committed `CHANGELOG.md` belongs to
`.github/actions/bot-pr-with-synthetic-checks/` and is unrelated. No file to edit — the
PR title and body carry this role. (`hr-when-a-plan-specifies-relative-paths-e-g`: plan
paths are claims to verify, never facts.)

### PR B — Phase 4 (after the inter-PR verification gate)

### Phase 4 — The ruleset flip + the drift detector

4.0 **Gate:** confirm on a live docs-only PR that `infra-validate-required` posts a
terminal state. Do not proceed otherwise.

4.0b **Revisit `cancel-in-progress` before the flip (carried forward from PR A).**
PR A ships `cancel-in-progress: true` per F7. **Both** sibling required workflows
(`tenant-integration.yml`, `apply-sentry-infra.yml`) use `false`, and their written
rationale is precisely that a cancelled run reds a *required* gate. F7's justification for
diverging — "no required-context-on-cancel hazard **because PR A ships before the context
is required**" — is therefore self-expiring: **PR B is the event that expires it.**
Re-evaluate here, do not inherit silently. If keeping `true`, record why the
cancelled-run-reds-a-required-check hazard does not apply (the aggregator re-runs on the
new head SHA, and GitHub evaluates required contexts against the latest SHA); if that
argument does not survive scrutiny, flip to `false` and match the precedents. The divergence
and its expiry condition are recorded in the workflow's own `concurrency:` comment.
4.1 `infra/github/ruleset-ci-required.tf` — add one
`required_check { context = "infra-validate-required"; integration_id = var.actions_integration_id }`.
Fix the stale "the 19 `context` strings" header comment (already wrong at 20 → 21).
4.2 `scripts/ci-required-ruleset-canonical-required-status-checks.json` — matching entry (T-rsc-9).
4.3 `tests/scripts/test-audit-ruleset-bypass.sh` — bump the `"20"` literal in
`t_rsc_real_canonical_shape` to `"21"`.
4.4 `scripts/required-checks.txt` — add `infra-validate-required` **with the #6049
auto-fabrication justification comment** per the `sentry-destroy-required` precedent: the
composite action's `ALLOWED_PATHS` (`bot-pr-with-synthetic-checks/action.yml:148`) `exit 1`s
on any path outside `{weakness-digest.md, rule-metrics.json}`, so no bot PR can produce a
diff this gate would red. **This file is CODEOWNERS-gated to @deruelle.**
4.5 New `plugins/soleur/test/required-job-suffix-parity.test.ts` (**bun** shard — the
`test-scripts` shard has no bun; the `yaml` package is importable here). Parse every
`.github/workflows/*.yml`; collect **`jobs:` children** whose effective context name
(job `name:` if present, else job id) ends in `-required`; assert for each:
(a) present in `infra/github/ruleset-ci-required.tf`, the canonical JSON, **and**
`scripts/required-checks.txt`; (b) **postability** — its workflow has no
`pull_request.paths:` key and does declare `merge_group:` (F6).
Non-vacuity floor: `≥3` such jobs found. **No exemption allowlist** (R5).

> `deploy-script-tests` is deliberately **not** a required context (R2). Its redness now
> blocks merge *through* `infra-validate-required`.

## Infrastructure (IaC)

### Terraform changes

- `infra/github/ruleset-ci-required.tf` — one added `required_check {}` block inside
  `rules { required_status_checks { … } }` of `github_repository_ruleset.ci_required`
  (live ruleset id `14145388`). Provider `integrations/github ~> 6.10`, pinned in
  `infra/github/versions.tf`. No new variables; reuses `var.actions_integration_id` (15368).
- No new secrets. Auth is the existing GitHub App creds from Doppler `soleur/prd_terraform`.

### Apply path

**(a) Auto-apply on merge of PR B.** `.github/workflows/apply-github-infra.yml` fires on
`push: branches: [main]`, `paths: infra/github/*.tf`, running a **full-root**
`terraform plan -out=tfplan` + `apply -auto-approve` (not `-target`-scoped). No operator
step, no environment reviewer gate — the PR merge *is* the human authorization. Kill
switch: `[skip-github-apply]` on its own line in the merge commit message.

Blast radius: the ruleset gains one required context, live within one workflow run of
merge. Zero downtime. The **destroy guard** counts nested `required_check` block removals
as deletes — this is a pure **add**, so `destroy_count = 0` and no `[ack-destroy]` is needed.

### Distinctness / drift safeguards

- `strict_required_status_checks_policy = true` unchanged.
- `bypass_actors` (OrganizationAdmin actor_id 0, `bypass_mode = "pull_request"`) unchanged
  — the **documented escape hatch** if the context name does not match. Named in §Risks.
- The post-apply verify step *logs* the required-check count but does **not** assert it, so
  20→21 will not red the verify. T-rsc-7 (Phase 4.3) is the real count gate.
- No secret values enter `terraform.tfstate` from this change.

### Vendor-tier reality check

Not applicable — GitHub repository rulesets carry no paid-tier gate for required status
checks on this plan.

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions `infra-validation` workflow run on every push to main (new in Phase 3.1) plus the `infra-validate-required` required-status-check context on every PR (PR B)"
  cadence: "per-PR and per-push-to-main"
  alert_target: "operator — a red required check blocks merge; a red main run appears in the Actions tab and on the commit status"
  configured_in: ".github/workflows/infra-validation.yml (on: push/pull_request/merge_group) and infra/github/ruleset-ci-required.tf (required_check block)"

error_reporting:
  destination: "GitHub Actions job logs and the PR checks UI; no Sentry surface (CI-plane change, no runtime code)"
  fail_loud: "scripts/infra-validate-gate-verdict.sh exits non-zero and prints the specific unenumerated or failing state (e.g. `deploy-script-tests=failure while suite_relevant=true`)"

failure_modes:
  - mode: "Context name posted by the workflow does not match the ruleset string — every PR wedges at Expected — Waiting for status"
    detection: "PR B's required-job-suffix-parity.test.ts asserts three-way membership pre-merge; the PR A/B split additionally verifies posting empirically on a live docs-only PR before the flip"
    alert_route: "operator; remediation is the OrganizationAdmin bypass_actors entry already present in ruleset-ci-required.tf"
  - mode: "Aggregator ships green while deploy-script-tests is red (the F1 defect)"
    detection: "tests/scripts/test-infra-validate-gate-verdict.sh case `dirs=[] suite_relevant=true deploy=failure` asserts FAIL"
    alert_route: "CI red on the scripts shard before merge"
  - mode: "detect-changes suite_relevant under-triggers, silently skipping the cross-file drift guards"
    detection: "plugins/soleur/test/infra-validation-detect.test.sh case asserting a restart-inngest-server.yml-only diff yields suite_relevant=true"
    alert_route: "CI red on the scripts shard before merge"
  - mode: "merge_group routing unhandled — every queue candidate reds once the queue is re-enabled"
    detection: "detect_event_route() merge_group case asserts empty directories and suite_relevant=false, never an origin/...HEAD diff"
    alert_route: "CI red on the scripts shard before merge"
  - mode: "A plan buys a false SKIP with kind: run-log (no marker, absent marker, ssh command, or command unrelated to the marker)"
    detection: "Check 10 guardrails 2-7, each with a dedicated fixture and test (T9-T11, T18, T20-T22)"
    alert_route: "preflight FAIL aborts /ship in headless mode"
  - mode: "The *-required suffix convention drifts again (a new -required job added without a ruleset entry, or added inside a path-filtered workflow)"
    detection: "required-job-suffix-parity.test.ts asserts membership AND postability with a non-vacuity floor of 3 jobs"
    alert_route: "CI red on the bun shard"

logs:
  where: "GitHub Actions run logs for the `infra-validation` and `apply-github-infra` workflows"
  retention: "90 days (GitHub Actions default log retention for this repository)"

discoverability_test:
  kind: live-probe
  command: gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[].parameters.required_status_checks[].context] '
  expected_output: "a JSON array of 21 context strings that includes infra-validate-required"
```

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** A CI-plane change whose blast radius is the entire delivery pipeline. The
governing judgement is R1 — the issue's stated ordering is inverted and must not be
executed as written. Three structural decisions carry the risk: (1) the cheap static-named
aggregator, not the heavy job, becomes the required context — the shape both existing
precedents validate; (2) `suite_relevant` is a distinct output from `directories`, without
which dropping `paths:` silently disables the cross-file drift guards; (3) the aggregator's
verdict is extracted to an allow-list script rather than left as inline conditionals, after
review showed the inline form would ship green on the very case #6766 names. Merge-queue-off
(R6) lowers the risk profile — but the `merge_group` branch must still be *routed*, not just
declared. The two-PR split is the right call at this threshold: it converts the Critical
risk from "a string test asserts membership" to "we watched the context post." The `kind`
discriminator is a cross-cutting schema contract change and is correctly ADR-recorded.

### Product/UX Gate

Not applicable — the mechanical UI-surface scan over §Files to Create and §Files to Edit
matches no path in the UI-surface term list or glob superset. No `components/**/*.tsx`, no
`app/**/page.tsx`, no `app/**/layout.tsx`. Product tier: **NONE**.

## GDPR / Compliance

`.github/workflows/infra-validation.yml` matches the sensitive-path regex on its
`infra-validation` filename token, so the gate was consulted. **No regulated-data surface
is touched:** no schema, migration, auth flow, API route, or `.sql` file; no personal data
is read, written, transmitted, or newly processed; no new external processor. None of the
four expansion triggers fire (no LLM/external-API processing of operator data; no new cron
reading `learnings/` or `specs/`; no new artifact distribution surface). The
`single-user incident` threshold reflects **availability** blast radius, not data exposure.
**Verdict: no findings.**

## Files to Edit

### PR A

| Path | Change |
|---|---|
| `.github/workflows/infra-validation.yml` | `on:` triggers (+push, +merge_group, `branches: [main]`, −`paths:`); workflow `concurrency:`; `detect-changes` routing + `suite_relevant`; gate `deploy-script-tests` only; `plan` PR-only guard; `infra-validate-required` delegates to the verdict script |
| `plugins/soleur/test/infra-validation-detect.test.sh` | +`detect_event_route()` (incl. push + merge_group), +`detect_suite_relevant()` |
| `scripts/test-all.sh` | register `tests/scripts/test-infra-validate-gate-verdict.sh` (`tests/scripts/*.sh` is not globbed) |
| `plugins/soleur/skills/preflight/SKILL.md` | Check 10: Step 10.4b, matrix rows 9–12, Result block, **3 stale "8 states/fixtures" anchors** |
| `plugins/soleur/test/lib/discoverability-test-parser.ts` | split `rejectReason`; `parseKind`/`parseMarker`; `markerLookup` on `ClassifyInput`; `marker?` on result; **header "8 decision states"** |
| `plugins/soleur/test/preflight-discoverability-test.test.ts` | +9 tests; **`describe("… 8 decision states")`** |
| `plugins/soleur/skills/plan/references/plan-issue-templates.md` | `kind:`/`marker:` indented sub-fields × 3 blocks |
| `plugins/soleur/skills/plan/SKILL.md` | §2.9 `discoverability_test:` trailing comment only |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | §4.7 guardrail-2/3/6/7 reject bullets |
| `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js` | prose sync `:83-84`, `:236` |
| `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` | `:106-108` kind note |
| `knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md` | `kind: run-log` + `marker:`; fix `>-` scalar; command names the marker |
| `CHANGELOG.md` | entry |

### PR B

| Path | Change |
|---|---|
| `infra/github/ruleset-ci-required.tf` | +1 `required_check` block; fix stale count comment |
| `scripts/ci-required-ruleset-canonical-required-status-checks.json` | +1 entry (T-rsc-9) |
| `tests/scripts/test-audit-ruleset-bypass.sh` | T-rsc-7 count literal `"20"` → `"21"` |
| `scripts/required-checks.txt` | +1 line + #6049 justification comment (**CODEOWNERS @deruelle**) |

## Files to Create

| Path | PR | Purpose |
|---|---|---|
| `scripts/infra-validate-gate-verdict.sh` | A | Allow-list aggregator verdict (F1), mirroring `tenant-integration-gate-verdict.sh` |
| `tests/scripts/test-infra-validate-gate-verdict.sh` | A | Unit test for the above |
| `plugins/soleur/test/fixtures/preflight-check-10/09-run-log-pass.md` … `16-marker-without-run-log.md` | A | 8 fixtures for guardrails 2–7 |
| `knowledge-base/engineering/architecture/decisions/ADR-130-*.md` | A | ADR (ordinal provisional) |
| `plugins/soleur/test/required-job-suffix-parity.test.ts` | B | `*-required` membership + postability detector |

## Acceptance Criteria

### Pre-merge — PR A

- **AC1** `on:` contains `push:` with `branches: [main]`, contains `merge_group:`, and
  `pull_request:` has `branches: [main]` and **no** `paths:` key.
  Verify: `awk '/^on:/{f=1} f{print} /^jobs:/{exit}' .github/workflows/infra-validation.yml`.
- **AC2** `detect-changes` declares both outputs.
  Verify: `awk '/^  detect-changes:/{f=1} f&&/^  [a-z]/&&!/detect-changes/{exit} f' .github/workflows/infra-validation.yml | grep -cE '^\s*(directories|suite_relevant):'` → `2`.
  (Flag-based awk — a `start,end` range self-matches; §Sharp Edges.)
- **AC3** `deploy-script-tests` is gated (`needs: detect-changes` + `suite_relevant == 'true'`)
  and `check-secrets` is **not** gated (F8).
- **AC4** The `plan` job's `if:` contains `github.event_name == 'pull_request'`.
- **AC5** *(rewritten — behaviour, not string presence)* `bash tests/scripts/test-infra-validate-gate-verdict.sh`
  passes, **including** the case `dirs='[]' suite_relevant=true deploy=failure` ⇒ non-zero exit.
  Verify additionally that `infra-validate-required` invokes the script:
  `grep -c 'infra-validate-gate-verdict.sh' .github/workflows/infra-validation.yml` → `≥1`.
- **AC6** `bash plugins/soleur/test/infra-validation-detect.test.sh` passes, with case names
  mentioning `push`, `merge_group`, and `suite_relevant`.
- **AC7** Workflow-level `concurrency:` block present with `cancel-in-progress: true` (F7).
- **AC8** `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes; the
  Step 10.6 matrix has ≥12 rows with **exactly one** `**PASS**` terminal:
  `awk '/^\| # \| State/{f=1} f&&/^$/{exit} f' plugins/soleur/skills/preflight/SKILL.md | grep -c '\*\*PASS\*\*'` → `1`.
- **AC9** SSH is never bypassed: fixture `13-run-log-ssh.md` classifies **FAIL** (F2), and
  `grep -c 'sshRejectReason' plugins/soleur/test/lib/discoverability-test-parser.ts` → `≥2`
  (definition + unconditional call site).
- **AC10** Guardrail 4 is non-vacuous: `grep -c "knowledge-base/project/plans" plugins/soleur/skills/preflight/SKILL.md`
  shows the exclusion pathspec present in Step 10.4b, and fixture `11-run-log-marker-absent.md` FAILs.
- **AC11** Regression: a fixture with **no** `kind:` classifies identically to pre-change;
  `bun test plugins/soleur/test/observability-schema-parity.test.ts` green (`CANONICAL.length === 5`).
- **AC12** No column-0 `kind:` or `marker:`:
  `grep -cE '^(kind|marker):' plugins/soleur/skills/plan/references/plan-issue-templates.md plugins/soleur/skills/plan/SKILL.md` → `0` each.
- **AC13** `ADR-130-*.md` exists with `## Decision` and `## Alternatives Considered` naming
  directions 1 and 3. *(On `/ship` renumber, sweep this AC with the plan/tasks — §Sharp Edges.)*
- **AC14** `SENSITIVE_PATH_RE` untouched:
  `grep -cF "SENSITIVE_PATH_RE='^(apps/web-platform" plugins/soleur/skills/preflight/SKILL.md plugins/soleur/skills/deepen-plan/SKILL.md`
  → `3` and `1` (unchanged from Phase 0 baseline).
  *(Corrected at /work: the plan was authored with `2`, but the measured baseline on
  `origin/main` is `3` — the third preflight hit is a Sharp Edges prose bullet, not a
  second copy of the literal. Left as `2`, this AC would have red for a reason unrelated
  to the change — the same "self-describing counts rot silently" class AC20 exists to
  catch. The invariant it protects is asserted directly:
  `git diff origin/main...HEAD -- <both files> | grep -cE '^[+-].*SENSITIVE_PATH_RE'` → `0`.)*
- **AC20** No stale count survives:
  `git grep -c "8 decision states\|8 states\|all 8 fixtures" -- plugins/soleur/skills/preflight/SKILL.md plugins/soleur/test/lib/discoverability-test-parser.ts plugins/soleur/test/preflight-discoverability-test.test.ts`
  → `0` for each (F9).
- **AC21** `actionlint .github/workflows/infra-validation.yml` exits 0 (F13). *(`actionlint`
  is correct for a **workflow**; never run it against a composite `action.yml` — §Sharp Edges.)*
- **AC22** Full suite green: `bash scripts/test-all.sh`.
- **AC23** PR A body contains `Closes #6774` and `Ref #6766`, `Ref #6480`.

### Inter-PR verification gate (automatable — `gh` CLI, no operator dashboard)

- **AC24** After PR A merges, `infra-validate-required` posts a **terminal** state on a
  docs-only PR. Verify: `gh pr checks <N> --json name,state` includes `infra-validate-required`
  with a terminal state (not `PENDING`/`EXPECTED`).
- **AC25** The first post-merge push to `main` produced an `infra-validation` run.
  Verify: `gh run list --workflow=infra-validation.yml --branch=main --limit 5 --json event,conclusion`
  → at least one row with `event: push`.

### Pre-merge — PR B

- **AC15** Context count is 21 consistently across all three surfaces.
  Verify: `jq length scripts/ci-required-ruleset-canonical-required-status-checks.json` → `21`;
  `grep -cE 'context[[:space:]]*=' infra/github/ruleset-ci-required.tf` → `21`;
  `bash tests/scripts/test-audit-ruleset-bypass.sh` passes (T-rsc-7 **and** T-rsc-9 ok).
- **AC16** `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` passes
  (Test 1a/1b set-equality both directions).
- **AC17** `bun test plugins/soleur/test/required-job-suffix-parity.test.ts` passes with
  **zero exemptions**:
  `grep -ciE 'allowlist|exempt|skip.*infra-validate-required' plugins/soleur/test/required-job-suffix-parity.test.ts` → `0`.
- **AC18** The detector asserts postability (F6), not just membership:
  `grep -c 'merge_group' plugins/soleur/test/required-job-suffix-parity.test.ts` → `≥1`, and a
  mutation control (T7b) proves a synthetic `foo-required` job in a `paths:`-filtered workflow FAILs.
- **AC19** PR B body contains `Closes #6766` and `Closes #6480`.

### Post-merge — PR B (automatable, run in `/ship`)

- **AC26** The ruleset apply landed:
  `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[].parameters.required_status_checks[].context] '`
  → array of 21 including `infra-validate-required`. Automation: `gh` CLI via Bash.
- **AC27** The next PR opened after merge shows `infra-validate-required` as a **posted**
  check. Verify: `gh pr checks <N> --json name,state`. Automation: `gh` CLI via Bash.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `detect_event_route` `EVENT_NAME=push` | enumerate-all; no `origin/...HEAD` |
| T2 | `detect_event_route` `EVENT_NAME=pull_request`, `BASE_REF=main` | diff branch |
| T3 | `detect_event_route` `EVENT_NAME=workflow_dispatch` | enumerate-all (unchanged) |
| T4 | `detect_suite_relevant` on a `restart-inngest-server.yml`-only diff | `true` (R3 under-trigger trap) |
| T5 | `detect_suite_relevant` on a docs-only diff | `false` |
| T6 | `required-job-suffix-parity` over real workflows | 3 jobs, all in all 3 surfaces |
| T7 | Synthetic `foo-required` job absent from the ruleset | FAIL (mutation control) |
| T7b | Synthetic `foo-required` job inside a `pull_request.paths:`-filtered workflow | FAIL (postability, F6) |
| T8 | Fixture `09-run-log-pass.md`, marker resolvable | SKIP; reason contains `run-log` + marker |
| T9 | `10-run-log-no-marker.md` | FAIL (guardrail 3) |
| T10 | `11-run-log-marker-absent.md` | FAIL (guardrail 4) |
| T11 | `12-unknown-kind.md` | FAIL (guardrail 2) |
| T12 | Existing fixtures 01–08 (no `kind:`) | byte-identical to pre-change (guardrail 1) |
| T13 | verdict `dirs=[] suite_relevant=false deploy=skipped` | PASS |
| T14 | verdict `dirs=[] suite_relevant=true deploy=failure` | **FAIL** (the F1 defect) |
| T15 | verdict `dirs=[…] validate=failure` | FAIL |
| T16 | verdict `dirs=[…] validate=success deploy=success` | PASS |
| T17 | verdict with an unenumerated state (e.g. `cancelled`) | FAIL (fail-closed allow-list) |
| T18 | `13-run-log-ssh.md` | FAIL (guardrail: ssh never bypassed, F2) |
| T19 | `detect_event_route` `EVENT_NAME=merge_group` | `[]` + `suite_relevant=false`; no diff (F3) |
| T20 | `14-run-log-command-lacks-marker.md` | FAIL (guardrail 5) |
| T21 | `15-form-b-kind-token.md` | FAIL (guardrail 6) |
| T22 | `16-marker-without-run-log.md` | FAIL (guardrail 7) |

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Context-name mismatch ⇒ **every PR wedges** | **Critical** | **The A/B split is the primary mitigation** — PR B flips the ruleset only after AC24 empirically observes the context posting. Plus AC17's three-way parity test. Live escape hatch: `bypass_actors` OrganizationAdmin, `bypass_mode = "pull_request"`. |
| Aggregator ships green while `deploy-script-tests` is red (F1) | **Critical** | Verdict extracted to a fail-closed allow-list script with a unit test; T14 is the dedicated control; AC5 asserts behaviour, not string presence. |
| Dropping `paths:` puts a 12-min build on every PR | High | Phase 3.3 gates `deploy-script-tests` on `suite_relevant` **in the same commit** as the `paths:` removal; T5 is the control; F7's `cancel-in-progress` bounds pile-up. |
| `suite_relevant` under-triggers, silently disabling cross-file drift guards | High | T4 is a dedicated mutation control; path rationale comments are **moved, not deleted**. |
| `merge_group` unrouted ⇒ every queue candidate reds on re-enable (F3) | High | Explicit first branch matching both sibling precedents; T19. |
| `kind: run-log` becomes a free SKIP | Medium | Seven fail-closed guardrails; guardrails 4+5 are the non-vacuity checks; T9–T11, T18, T20–T22. |
| Push-on-main cost: full matrix + 12-min job every merge (F14) | Medium | Accepted trade-off with recorded rationale (§Alternatives Considered); `cancel-in-progress: true`; nightly `schedule:` is the documented fallback. |
| Bot PRs get a synthetic green for the new context (#6049) | Medium | PR B requires the `ALLOWED_PATHS` justification comment; the composite action `exit 1`s outside `{weakness-digest.md, rule-metrics.json}`. |
| Column-0 `kind:` breaks schema parity | Medium | AC12 greps explicitly; AC11 runs the parity test. |
| `scripts/post-bot-statuses.sh` is stale | Low | Verified at review to have **zero callers**. Out of scope, noted so its silence is not mistaken for correctness. |
| ADR-130 ordinal collision | Low | `/ship`'s collision gate re-verifies; §Sharp Edges carries the renumber sweep. |

## Decision Challenges

**Challenge (User-Challenge class, ADR-084):** the operator's stated direction was
*"Gap 2 first (lowest risk, stops the bleeding) — add `deploy-script-tests` as a required
context."*

- **What the operator specified:** do the ruleset edit first, as an isolated low-risk change.
- **What research found:** `infra-validation.yml` is path-filtered with no `merge_group:`;
  a required context there never posts on a non-infra PR and wedges the entire repository.
  Verified three ways — the workflow's own comment (`:246-263`), open issue #6480 ("Do not
  simply add the context to the ruleset"), and four review agents during #6458.
- **Why it matters:** executed as stated, this is a repo-wide outage, not a low-risk edit.
- **What the plan does instead:** inverts the order (enabling work in PR A, ruleset flip in
  PR B after empirical verification), and swaps the required context from
  `deploy-script-tests` to `infra-validate-required` while folding the former's result in.
- **The operator's direction remains the default on *intent*:** a red loopback suite must
  block merge. Only the *mechanism and ordering* changed.

Headless run — persist to
`knowledge-base/project/specs/feat-one-shot-6766-6774-ci-guards-cannot-fail/decision-challenges.md`
for `/ship` to render into the PR body and file as an `action-required` issue.

## Research Insights (deepen-plan pass)

### Precedent diff — the aggregator verdict script (Phase 3.5)

Pattern-bound behavior with an established canonical form in-repo. Precedent read in full:
`scripts/tenant-integration-gate-verdict.sh` (32 lines) + `tests/scripts/test-tenant-integration-gate-verdict.sh`.

**Precedent shape (verified):** two positional args; exits 0 **only** on the enumerated
combination `detect == "success" && (suite == "success" || suite == "skipped")`; exits 1
with a loud `::error::` for **every** other combination, including the empty string. Its
header names the rationale explicitly — the *"DROP-1 fail-open class"*. It is standalone
and unit-testable rather than inline workflow YAML.

**New script — `scripts/infra-validate-gate-verdict.sh`.** Copy the shape; widen the arity
from 2 to 5. Signature:

```
infra-validate-gate-verdict.sh <detect_result> <validate_result> <deploy_result> <directories> <suite_relevant>
```

Allow-list — exit 0 **only** on these rows; anything else (including `cancelled`,
`skipped` where not enumerated, or an empty string) exits 1:

| detect | directories | suite_relevant | validate | deploy-script-tests | verdict |
|---|---|---|---|---|---|
| success | `[]` | `false` | skipped | skipped | **0** — nothing in scope |
| success | `[]` | `true` | skipped | success | **0** — non-terraform guard surface only |
| success | non-`[]` | `true` | success | success | **0** — full pass |
| success | any | `true` | any | **failure** | **1** — the F1 defect (T14) |
| success | non-`[]` | any | **≠ success** | any | **1** |
| **≠ success** | any | any | any | any | **1** — detect itself failed |

The last row is load-bearing and inherited from the precedent: it is what makes an
unrouted `merge_group` (F3) fail **loudly** rather than silently green. Keep it.

**Divergence from precedent, recorded:** the precedent folds "no work in scope" into a
single `skipped` arm; this script needs two distinct in-scope axes (`directories` for the
terraform matrix, `suite_relevant` for the cross-file guard surface — R3), which is why the
table has two separate zero-work rows rather than one.

### Precedent diff — `merge_group` routing (Phase 2.2)

Both sibling required workflows handle `merge_group` as an **explicit first branch**, not
as a fall-through: `tenant-integration.yml` `detect-changes` (`if [[ "$EVENT_NAME" == "merge_group" ]]` → `tenant=false`,
aggregator PASSes via the `suite=skipped` path) and `apply-sentry-infra.yml:99-102`
(same shape, `sentry=false`). Both carry a written rationale that the heavy suite already
ran authoritatively on the PR pre-queue and that `secrets.*` may be absent on a
GITHUB_TOKEN-authored `merge_group` event. **Copy this shape verbatim** — it is why F3 is a
P0 rather than a nice-to-have.

### Verification ledger

Every load-bearing negative and attribution claim in this plan was probed. All confirmed;
none contradicted.

| Claim | Verdict | Evidence |
|---|---|---|
| `scripts/post-bot-statuses.sh` has zero callers | confirms | only self-references at `:2,5,22` |
| `tests/scripts/*.sh` not globbed; `plugins/soleur/test/*` is | confirms | `scripts/test-all.sh:316` glob; `:198` comment; hand-registered `run_suite` at `:201,207,212,217` |
| `test-scripts` shard has no bun/node pin | confirms | `ci.yml:522-526` comment + no `setup-bun`/`setup-node` in `:522-577` |
| `topLevelKeys()` is column-0 only | confirms | `observability-schema-parity.test.ts:48-53`, `^([a-z_]+):` |
| Merge queue disabled | confirms | `ruleset-ci-required.tf:36` — comment only, no live block |
| `check-secrets` + `deploy-script-tests` have no `needs:`/`if:` | confirms | `infra-validation.yml:285-294`, `:706-716` |
| `infra-validate-required` early-`exit 0` on `$DIRS == "[]"` | confirms | `infra-validation.yml:264-283` — the F1 defect, quoted |
| `preflight-diff-files.txt` holds filenames | confirms | `preflight/SKILL.md:35` `git diff --name-only`; 12 consumers all treat it as a path set |
| `rejectReason` fuses ssh + subst | confirms | `discoverability-test-parser.ts:165-173`, single call site `:204` |
| `tenant-integration-gate-verdict.sh` is a fail-closed allow-list | confirms | `:26` allow row, `:31-32` catch-all, `:14-17` rationale |
| #6458 / #6745 / #4148 | MERGED PRs, roles match | `gh pr view` |
| #6480 open; #5780 / #6049 / #6454 / #6446 / #4012 / #5145 / #6604 closed issues, roles match | confirms | `gh issue view` |
| ADR-130 is next free | confirms | derived from **freshly-fetched `origin/main`**; highest existing is ADR-129 |
| Labels `chore`, `priority/p3-low` exist | confirms | `gh label list` |
| AGENTS rule IDs cited are active | confirms | `hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`, `cq-test-fixtures-synthesized-only`, `hr-weigh-every-decision-against-target-user-impact` all present in `AGENTS.md` |
| Marker resolvable outside planning artifacts | confirms | `apps/web-platform/infra/workspaces-cutover.sh`, `workspaces-luks-loopback.test.sh` |

### Gate dispositions

- **Phase 4.5 (network-outage): not applicable.** The keyword scan matches `ssh`/`unreachable`
  only inside §R7 and §F2, which discuss Check 10's **SSH reject regex** — a string-matching
  rule, not a connectivity symptom. No `terraform apply` on a resource carrying
  `provisioner "file"` / `"remote-exec"` / a `connection { type = "ssh" }` block. False trigger.
- **Phase 4.55 (downtime & cutover): not triggered, but the discipline was applied anyway.**
  No infra reboot/replace, no lock-taking DDL, no deploy/router restructure — no serving
  surface goes offline. The *developer* surface (merge capability) does carry an availability
  risk, and the A/B split with the AC24 verification gate is precisely the zero-downtime
  cutover shape that phase asks for: stage the new capability, verify it live, then switch.
- **Phase 4.8 (PAT-shaped): pass.** No `var.*_token` / `TF_VAR_GITHUB_*` / literal token
  shapes. The ruleset change reuses `var.actions_integration_id` (an integer app id, not a
  credential); auth is the existing GitHub App via Doppler `prd_terraform`.
- **Phase 4.9 (UI wireframe): not applicable.** The `components/**/*.tsx` /
  `app/**/page.tsx` matches in this plan are inside the Product/UX Gate's own *negation*
  prose, not in §Files to Edit or §Files to Create. No UI surface.
- **Scheduled-work pattern check: not applicable.** No new scheduled job. The `push:`
  trigger is an event trigger on an existing workflow, not a cron; the nightly `schedule:`
  alternative is explicitly rejected in §Alternatives Considered.

### Implementation notes surfaced by research

- **The verdict script's `detect ≠ success ⇒ 1` row doubles as the merge_group safety net.**
  If Phase 2.2's routing is ever regressed, `detect-changes` fails on the empty `base_ref`
  and the aggregator reds loudly instead of passing green. Two independent defences for F3.
- **`substRejectReason` must keep the precedent's full message string.** The existing text
  enumerates every rejected token (`;, &&, ||, |, >, <, &, $var, $(, \`, <(, >()`) and is
  what an operator sees on a FAIL. Preserve it verbatim when splitting the function —
  message-string drift on a helper split is a known operator-dashboard regression class.
- **`rejectReason` has exactly one call site** (`:204`), so the split is low-risk: keep a
  thin back-compat wrapper only if an external consumer appears in `git grep rejectReason`.
- **`git diff --name-only` includes deletions**, so any path-list consumer must tolerate
  missing files. Guardrail 4 sidesteps this entirely by using `git grep` over the tree at
  HEAD rather than iterating the diff's path list.

## Sharp Edges

- **Never add the ruleset context before the workflow posts it.** PR B depends on AC24.
  The ruleset auto-applies on merge (`apply-github-infra.yml`), so a ruleset-first order
  leaves a live window where the context is required but never posted — every PR wedges.
- **An early `exit 0` can make a gate certify the wrong property.** The existing
  `infra-validate-required` step returns 0 whenever `directories == '[]'` — which is
  exactly the state of the case #6766 is about. Any "fold job X's result in" instruction
  must specify **where relative to the early return**, and an AC that greps for a string
  will happily match unreachable code. Prefer extracting the verdict to a unit-tested
  allow-list script (precedent: `scripts/tenant-integration-gate-verdict.sh`).
- **`awk '/start/,/end/'` self-matches.** `awk '/^  detect-changes:/,/^  [a-z]/'` closes on
  its own start line. AC2 uses the flag-based form.
- **`kind:`/`marker:` must be indented.** A column-0 key becomes a 6th top-level key and
  breaks `expect(CANONICAL.length).toBe(5)` plus three sibling assertions in
  `observability-schema-parity.test.ts`. AC12 is the gate.
- **The SSH reject must never sit behind the `kind` branch.** `rejectReason` fuses the ssh
  and subst checks; branching before it lets `kind: run-log` + `ssh …` return SKIP. Split
  the function; run ssh unconditionally.
- **`preflight-diff-files.txt` holds filenames, not contents.** Grepping it for a marker
  can never match. Use `git grep -F -- "$MARKER"` over the tree, excluding
  `knowledge-base/project/{plans,specs}` — without that exclusion the check is vacuous,
  because the plan declaring the marker is itself in the diff.
- **The parser file is a mirror, not the runtime.** Its header: *"the production runtime is
  the bash in `preflight/SKILL.md` §Check 10 … If the bash and TS drift, the bash wins and
  this file is the bug."* Both must change together, in the same order.
- **Put the `*-required` detector in `plugins/soleur/test/*.test.ts`, not `*.test.sh`.** The
  `test-scripts` shard has **no bun and no node pin** (`ci.yml:522`, with an explicit
  comment that a `bun` invocation in a `.test.sh` requires adding `setup-bun`). The bun
  shard auto-discovers `.test.ts` and `yaml` (`package.json:12`) is importable there.
- **`tests/scripts/*.sh` is NOT globbed by `scripts/test-all.sh`.** The new verdict test
  must be hand-registered via `run_suite`, or `scripts/lint-orphan-test-suites.sh` reds.
  (`plugins/soleur/test/*` — both `.test.sh` and `.test.ts` — *is* auto-discovered.)
- **Fixtures are loaded by hardcoded filename.** `fx("09-run-log-pass.md")` — no glob, no
  manifest. An added fixture with no `test(...)` call site is silently dead.
- **`actionlint` validates workflows, not composite actions.** Correct for
  `.github/workflows/infra-validation.yml` (AC21); it emits 5+ spurious schema errors
  against a `.github/actions/*/action.yml`.
- **`scripts/required-checks.txt` is CODEOWNERS-gated to @deruelle** precisely because
  adding a name there fabricates a green for bot PRs. The justification comment is not optional.
- **Four files move together on any ruleset context change:** the `.tf`, the canonical JSON,
  the T-rsc-7 count literal, and `required-checks.txt`. Missing one reds a different suite
  than the one you were editing.
- **Self-describing counts rot silently.** Five anchors say "8 decision states / 8 fixtures";
  AC8's `≥12 rows` would leave every one of them wrong and green. AC20 gates them.
- **On ADR renumber, sweep the planning artifacts too:**
  `grep -rn 'ADR-130' knowledge-base/project/{plans,specs}/feat-one-shot-6766-6774-ci-guards-cannot-fail/`
  — otherwise AC13 verifies a nonexistent file.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Fill it
  before requesting deepen-plan or `/work`.

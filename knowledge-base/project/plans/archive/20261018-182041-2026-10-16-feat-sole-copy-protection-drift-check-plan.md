---
title: "infra: sole-copy protection drift check in the scheduled drift workflow (#9927 item 9)"
date: 2026-10-16
slug: sole-copy-protection-drift-check
branch: feat-one-shot-9927-sole-copy-drift-check
issue: 9927
type: feat
lane: cross-domain
ref: "Ref #9927"
closes: none
brand_survival_threshold: aggregate pattern
---

# infra: sole-copy protection drift check in the scheduled drift workflow (#9927 item 9)

Spec lacks valid `lane:` (no spec.md exists for this branch) - defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-16
**Sections enhanced:** Overview-adjacent research, Phase 1 to Phase 4, Guard Contract (rewritten, 15 rows), Observability, Acceptance Criteria, Test Scenarios, Sharp Edges, Files to Edit.
**Agents used:** security-sentinel, architecture-strategist, observability-coverage-reviewer, test-design-reviewer, spec-flow-analyzer, framework-docs-researcher (Hetzner contract, public docs only), CTO (rulings E1-E8), plus the earlier learnings-researcher, code-simplicity-reviewer and CTO (D1-D6). Gates run: user-brand impact, observability (5 fields), PAT-shape grep, scope check, guard-contract lint, label and milestone existence, SHA pin length (40 characters, 21 uses of the pinned action).

### Key Improvements

1. A red run reaches no one (the dispatcher never reads conclusions): the `notify-ops-email` fallback is reinstated, the Cut List entry is reversed, and an empty or unknown verdict now files through a complement filer.
2. The volume id is pinned as an identity check, closing the planted-read-only-token false-clean path; the Doppler CLI comes from the loader's pinned tarball instead of the mutable-install action.
3. A 90-minute grace verdict stops the apply-lag window from paging as a lift outside Terraform; the sanctioned unprotected window stays visible as a warning every run.
4. The suite is specified at the harness level (real `bc_curl` behind a stub `curl`, shared sequence log, stateful `gh`, expression resolver, real-file case with mutants) and the guards that run over the workflow text are listed so none reddens by surprise.

### New Considerations Discovered

- The census needs no runbook row (measured on a scratch copy); the row is documentation hygiene.
- Four live workflow lints and the alarm-issue-filing guard apply to the new steps.
- A shallow checkout makes `git log -1 -- <path>` return the HEAD commit, so the `.tf` age comes from the commits API.
- The Hetzner list-envelope `protection.delete` is inferred from the SDK type and the single-volume read; the first run is the proof.
- Open limit: the effective check gap can exceed 12 hours (concurrency group, branch dispatch), accepted and documented.

## Overview

Item 9 of the Inngest LUKS key-loss residuals tracker (#9927) asks for a distinct sole-copy
protection check in the scheduled drift workflow. The workflow's untargeted `terraform plan`
already sees a delete-protection flip on the Inngest sole-copy volume
(`hcloud_volume.inngest_redis_luks`, name `soleur-inngest-redis-store-luks`, Hetzner id 106903269),
but it reports it as one more comment on the standing drift issue (#10236, open), so a flip is not a
distinct signal. This plan adds one new, read-only job to
`.github/workflows/scheduled-terraform-drift.yml`. The job asks Hetzner directly whether the
volume's `protection.delete` flag matches what the committed Terraform declares, and files its own
issue when it does not.

**The operator's first question, answered (token in scope).** The `HCLOUD_TOKEN` that the two existing
Hetzner sweeps read is loader-exported (#8209) and is **not provably read-only**: in the Tier-B arm of
`.github/actions/infra-credentials/action.yml` it is the read/write token from
`soleur-infra-privileged/prd`; in the legacy arm it is `HCLOUD_TOKEN_READONLY` if present, with the
read/write `HCLOUD_TOKEN` as the before-state fallback. A genuinely read-only token,
`HCLOUD_TOKEN_READONLY` (Hetzner Read permission, ADR-241 D4), lives in `soleur/prd_terraform`, is not
part of the Tier-B payload, and is readable with the repo secret `DOPPLER_TOKEN` that these jobs already
bind. Ruled by CTO agent, 2026-10-16: a new standalone job with no loader and no `environment:` reads
that token itself, with no fallback to the read/write name (decision D1 in `decision-challenges.md`).
The read/write token therefore never enters the new job's environment.

No Hetzner, Doppler or production call was made while planning. The existence of `HCLOUD_TOKEN_READONLY`
in `prd_terraform` is inferred from a committed record (the ADR-282 addendum of 2026-10-15: the
section-5c read-back printed `protected`, and that one-liner reads only this secret and exits
`missing-token` otherwise); the new job reports `no-token` as its own verdict if the inference is wrong.

## Research Insights

**Premise Validation (Phase 0.6).** Checked and held: #9927 is OPEN; item 8c merged as `c9deab509e`
(PR #10355); the standing drift issue #10236 ("infra: drift detected in web-platform") is open, which is
the premise of item 9; ADR-282 is `accepted` and its 2026-10-15 addendum records the read-back; the
parked draft #10405 (branch `feat-inngest-arc-window`) is OPEN and draft and its only hunks in the drift
workflow are in the `inngest-rehearsal-orphan-sweep` job (about lines 2315-2560); draft PR #10424
(this branch) has no closing references. Stale: the issue's "about 60 lines" estimate (see Research
Reconciliation) and the 2026-10-15 triage note that "whether the drift job already has a read-only
Hetzner token in scope is unverified" (now answered above). The task brief says "web-1's LUKS volume
106443278 (sole copy)"; that is `hcloud_volume.workspaces_luks` (ADR-119), a different volume from the
Inngest sole-copy `106903269` that item 9 and ADR-282 cover. Both are sole copies and neither is touched.
The mechanism (a Hetzner GET) was grepped against the ADR corpus: ADR-282 and the runbook section 5c
already use exactly this read as the post-merge arbiter, and ADR-282 says "the post-apply read-back is
the only distinct check", so this adds the recurring twin, not a rejected alternative.

**Property List (Phase 0.6b).**

1. A lifted delete-protection flag on the Inngest sole-copy volume reaches an issue of its own within one
   drift cycle (about 12 hours), instead of a comment on an issue that is already open.
2. A missing or ambiguous sole-copy volume reaches the same channel.
3. A check that could not read Hetzner (token absent, HTTP error, truncated listing, malformed body)
   never reports clean.
4. The check cannot mutate anything and never prints a delete, detach or protection-change recipe.
5. The read/write Hetzner token never enters the check's environment.
6. A sanctioned two-step lift (ADR-282) does not page for its whole duration, and the 5-90 minute gap between a
   re-protect merge and its apply does not page as a lift outside Terraform.
7. A stale or resolved issue cannot mask a later signal: finding and could-not-perform issues are commented on
   each run while the condition holds, a clean run clears the bot-authored ones, and a red run reaches ops by
   email, not only by a log nobody reads.
8. A planted read-only token pointing at another Hetzner project cannot produce a clean verdict (id pin).

**Cut List (mechanisms the ask or the first design proposed that were removed).**

- Reuse of the loader-exported `HCLOUD_TOKEN` (it breaks property 5) -> the new job's own
  `HCLOUD_TOKEN_READONLY` read; the loader is not used.
- A hard-coded volume id (reversed by E1: the id is pinned as an identity check) and a hard-coded expected `true` -> the id is looked up by name and the expected
  flag is derived from the checked-out `.tf` (already pinned by Guard 1 and the parity test, so a third
  copy would be a new place to drift and would page during a sanctioned lift).
- (Reversed by deepen-plan, E2.) The email fallback the orphan sweeps carry was first cut on the premise that a
  red run is the channel. It is not: `cron-terraform-drift.ts` only dispatches and never reads the run's
  conclusion, and the dispatching App sends no failure mail. `notify-ops-email` is KEPT (Phase 2 step 7).
- A Sentry cron-monitor / heartbeat slug for the new job (would move the C4 count-parity numbers and
  `cron-monitors.tf`) -> not added; accepted gap recorded in Observability, follow-up issue filed in Phase 3.
- `DopplerHQ/cli-action` for the Doppler CLI (deepen-plan security P1: mutable latest-CLI install script) -> the
  loader's pinned-tarball plus sha256 step, copied into the job.
- A second volume entry for web-1's `workspaces_luks` -> excluded by ruling D2, follow-up recorded.
- A `schedule:` trigger -> none; the workflow is `workflow_dispatch` only and fires through the
  Inngest dispatcher (ADR-033), unchanged.

**Institutional learnings applied** (from `soleur:engineering:research:learnings-researcher`):

- `2026-10-15-removing-a-printed-recipe-owes-a-bounded-replacement-and-a-spelling-guard-is-a-tripwire.md`:
  a spelling ban is a tripwire; scan every string leaf (joined and flattened), run the mutation table
  in-process, one row per spelling alternative, and keep the new prose from spelling a command.
- `2026-10-03-a-failure-notice-must-tell-failed-from-unknown-and-the-census-must-run-the-body.md`: execute
  the `run:` bodies under stubs and compare the whole `$GITHUB_OUTPUT` and exit code per case.
- `2026-10-13-a-classifier-that-reads-absent-as-skip-fails-open-on-name-drift.md` and
  `2026-09-24-an-empty-api-search-is-not-evidence-of-absence-and-my-sanitiser-died-before-it-could-page.md`:
  an empty or partial answer is not a clean result; require exactly one match and check
  `meta.pagination.next_page`.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`
  and `2026-02-18-token-env-var-not-cli-arg.md`: token on stdin through `bc_curl`; do not redirect
  `bc_curl`'s stderr (it carries the refusal marker).
- `2026-10-01-the-guards-i-wrote-to-protect-the-sole-copy-scanned-a-shape-the-attack-did-not-take.md`: scan
  raw YAML `run:` text and job/workflow `env:`, not a JSON serialization.
- `2026-10-11-sole-copy-pins-the-required-check-anchor-must-not-be-a-subset-of-the-advisory-guard.md`: the
  required-check anchor for the expected value is the parity test (G2e), an independent implementation.
- `2026-10-06-terraform-show-json-configuration-is-declaration-not-state.md`: derive "expected" from the
  declaration, judge presence from live API state, and require at least one volume inspected before clean.

**Wiring facts (verified by reading, not by calling).**

- Both existing sweeps: `environment: infra-privileged`, loader, `TOKEN="${HCLOUD_TOKEN:-}"`, fail-closed on a
  listing failure, idempotent create-or-comment on `infra-drift`, and a create-only "could not perform" filer.
  Only the rung-2 sweep uses `source scripts/lib/bearer-curl.sh` and
  `bc_curl scheduled-terraform-drift 'Authorization:Bearer :TOKEN' -- -sS -f URL` (with the
  `meta.pagination.next_page != null` check); the inngest sweep pipes a header to `curl --config -`, so it is not
  a template for the argv-bearer sweep rules below. The runbook heading is `## 5c. Sole-copy protection and key
  loss` (cite "section 5c" in bodies and tests).
- Tier census (`tests/scripts/test-infra-privileged-tier-census.sh`): G1g inspects only `TIER_B_NAMES`;
  `HCLOUD_TOKEN_READONLY` is not one, so a no-fallback read of it from `prd_terraform` is permitted.
  `ENV_SECRETS` is only `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE`, `DOPPLER_TOKEN_GIT_DATA_ROOT`
  and `DOPPLER_TOKEN_INFRA_APP`; the new job names none, so it is Tier A (G1b/G1c do not fire). Measured by the
  architecture reviewer on a throwaway copy of `.github/` with a synthetic no-`environment:` job: the census
  stayed green (364 passed; the one failure, G6q, is identical on an unmodified copy; the real tree is 365/0)
  and the census never opens a runbook, so the Group 3 row is documentation hygiene, not a census requirement.
- R1-R5 in `plugins/soleur/test/token-drift-workflow-causes.test.sh` scan every step of every job for
  non-GET methods, curl body flags, hcloud write verbs and Doppler delete/destroy/revoke, so the new job's
  text is automatically covered and must not spell any of them.
- `scripts/infra-drift-autoclose.sh` searches `infra: drift detected in web-platform in:title`; the new
  titles do not collide.
- ADR-280: the S3/S4 stages of the argv-bearer sweep derive their population from the workflow text, so the
  new `bc_curl` site is picked up and must satisfy them.

## Research Reconciliation - Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Item 9 / triage: "about 60 lines" | One GET plus the fail-closed reads, two filers and a red-job gate that the sibling sweeps carry is about 300 workflow lines (comments included), plus a new test suite | Keep the outcome, record the estimate as wrong (decision-challenges row); do not trim the fail-closed behaviour to hit the number |
| Triage: "whether the drift job already has a read-only Hetzner token in scope is unverified" | The sweeps' `HCLOUD_TOKEN` is the loader's token and is read/write in the Tier-B arm; a read-only token exists only as `HCLOUD_TOKEN_READONLY` in `prd_terraform` | New job reads `HCLOUD_TOKEN_READONLY` itself, no fallback (D1) |
| Brief: "web-1's LUKS volume 106443278 (sole copy)" | Item 9 is about the Inngest volume 106903269 (ADR-282); 106443278 is `workspaces_luks` | Scope = Inngest volume only (D2); the suite asserts 106443278 never appears |
| Issue item 9: "or a scheduled read-only protection check" | A step in the existing `drift-check` matrix job would run for three directories and sit beside the plan path | A separate job (D5) |
| Existing runbook Group 3 rows for `heartbeat-live-reconcile` and the rung-2 sweep say `environment: (none)` | The workflow now sets `infra-privileged` on both | Stale rows noted, not fixed in this diff (not ours); the new row is accurate |

## Hypotheses

Not a connectivity fix: no SSH, sshd or fail2ban hypothesis applies (the brief's "no SSH" is a constraint,
and the check is a runner-to-`api.hetzner.cloud` HTTPS GET). The L3 firewall/egress-IP step of the
network-outage checklist is not applicable because no host is reached; a runner that cannot reach the API
is the `could-not-read` verdict, which fails closed.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; a broken check is a detector that
either stays silent (the status quo before this PR) or files a false p1 issue. The harm it exists to shorten
is a lifted delete-protection flag on the only copy of the queue and run state going unseen for the
interval between merge-time reads, which would put every user's armed reminders and run history one
console click from irreversible loss.

**If this leaks, the user's [workflow] data is exposed via:** no user data is read at all. The only
credential involved is the Hetzner Read-permission token, which is masked, passed to curl on stdin
(`bc_curl`, ADR-280) and never printed; issue bodies carry the volume name, the expected and live
flag values, the HTTP code and the run URL, and never an API response body (labels could leak).

**Brand-survival threshold:** aggregate pattern - the check is read-only and adds detection only, so a
defect cannot cause the loss; the loss class itself is ADR-282's `single-user incident` threshold and is
unchanged by this PR. (No CPO sign-off frontmatter key is added for that reason.)

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-16 on six forks (D1-D6, recorded as rows in
`knowledge-base/project/specs/feat-one-shot-9927-sole-copy-drift-check/decision-challenges.md`): standalone
no-loader job with a no-fallback `HCLOUD_TOKEN_READONLY` read; Inngest volume only; name lookup plus
expected flag derived from the checked-out `.tf`; the verdict/filer taxonomy below; placement at about line
1860, away from #10405's hunks; new test suite with registry entries. Additional CTO risks carried into the
plan: the first run after merge may go red if the secret or the `DOPPLER_TOKEN` scope is not as inferred
(`no-token` is the designed signal), pagination of a name-filtered listing, issue bodies carry parsed fields
only, and a `.tf` resource rename must fail closed.

No product/UI surface (Files lists contain no `components/`, `app/` or page paths), no regulated-data
surface (no schema, auth, API route; no personal data processed), no new store or connection (Encryption
Posture gate: skipped, the HTTPS call to the Hetzner API is an existing edge), and no new infrastructure
resource (IaC routing gate: skipped; the credential and the workflow already exist).

## Architecture Decision (ADR/C4)

No new architectural decision: the check is a recurring instance of the read-back ADR-282 already
specifies, using a credential and an edge ADR-241 and the C4 model already define.

### ADR

Amend ADR-282 with an append-only addendum placed after the 2026-10-15 item-8c addendum, titled
`## Addendum — 2026-10-16 (#9927 item 9, recurring protection check)`, opening (as the 8c addendum does) with
"the only change above is the residual 'Detection of lifted protection is generic'" (status stays `accepted`;
no test pins the residual text): the post-apply read-back stays the point-in-time arbiter and
`sole-copy-protection-check` is the recurring distinct signal, and its limits (a derived expectation, so a lift that was applied through the sanctioned two-step
route is quiet by design; the read is a point-in-time flag read, not a `prevent_destroy` read-back). Update
the residual "Detection of lifted protection is generic" to point at the new check. Via the `architecture`
skill / Edit in this PR, never a deferred issue.

### C4 views

"No C4 impact", with the enumeration checked against all three model files
(`model.c4`, `views.c4`, `spec.c4`), to be re-read at work time: (a) external human actors - none added;
(b) external systems - Hetzner API (edge `github -> hetzner` exists; what supports a read-only drift GET is
its clause "Other CI callers include ... drift and apply workflows", and the same Tier-A pattern
(`HCLOUD_TOKEN_READONLY` from `prd_terraform` with the repo `DOPPLER_TOKEN`) is already carried on that edge by
`workspaces-luks-cutover` and `cutover-inngest`; the sibling drift orphan sweeps are not named there), Doppler
(`github -> doppler` exists), GitHub Issues (existing); (c) containers/data stores - none touched;
(d) actor-to-surface access relationships - none change. Verify with `plugins/soleur/test/c4-count-parity.test.sh`
(the new job adds no heartbeat slug, so the monitor counts do not move). If re-reading shows the
`github -> hetzner` prose now misstates the read set, add one clause there and run
`apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

### Sequencing

The ADR addendum ships in this PR.

## Open Code-Review Overlap

One open code-review issue touches a planned file: #8800 (test fixture: census sandbox shares inodes/symlinks
with the live repo, write-through hazard) names `scripts/lib/test-affected-paths.sh`. **Acknowledge:** this
plan adds a path-list entry there and does not touch the census sandbox; the issue stays open. No other
planned file is named by an open code-review issue.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a sole-copy drift check to .github/workflows/scheduled-terraform-drift.yml (~60 lines)" [brief] | Phase 2 (new job `sole-copy-protection-check`) | mapped (the line estimate is recorded as wrong, not trimmed to) |
| 2 | "FIRST confirm that a read-only Hetzner token is in scope in the drift job (inspect the workflow/secrets wiring only; make NO Hetzner/Doppler/production calls)" [brief] | Overview "token in scope" finding + decision D1 + Phase 1 | mapped |
| 3 | "Ship as its own PR; the PR body must use \"Ref #9927\" only (never a closing keyword) and, after every PR body edit, assert closingIssuesReferences is []" [brief] | Phase 5 | mapped |
| 4 | "the check must be read-only and must never emit a runnable delete/detach recipe" [brief] | Phase 2 step 4, Guard 1 rows 10 and 13 | mapped |
| 5 | "never touch web-1's LUKS volume 106443278 (sole copy)" [brief] | D2, name-filtered query, suite row asserting the id never appears | mapped |
| 6 | "#10405 also edits the drift workflow, so keep the diff localized to avoid conflicts" [brief] | D5 placement at about line 1860; no edit to the inngest-rehearsal-orphan-sweep job | mapped |
| 7 | "if it is NOT provably read-only, record that as a finding for the CTO to rule on" [brief] | Overview finding, D1 | mapped |
| 8 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/feat-one-shot-9927-sole-copy-drift-check/decision-challenges.md" [brief] | `decision-challenges.md` (created) | mapped |
| 9 | "Locally run only targeted or TEST_GROUP=affected suites; CI is the authority" [brief] | Phase 4 | mapped |
| 10 | "Known unrelated red: \"Tenant integration (dev-Supabase)\" failing on test/server/action-sends-worm.test.ts - do not fix" [brief] | Phase 5 note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/scheduled-terraform-drift.yml` new job | "add a sole-copy drift check to .github/workflows/scheduled-terraform-drift.yml" | asked |
| New suite `plugins/soleur/test/sole-copy-drift-check.test.sh` | "the check must be read-only and must never emit a runnable delete/detach recipe" | asked (a read-only/no-recipe claim needs an executing test; CI is the authority) |
| Suite registry entries (`scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, `scripts/lib/test-affected-paths.sh`) | - | inferred - justification: the repo's CI registries gate a new suite file; without the entries the suite is not selected or sharded |
| Runbook Group 3 row in `infra-credential-tiers-8209.md` | - | inferred - justification: the runbook's Group 3 table is the repository's inventory of which jobs read which credential tier (documentation hygiene; the census does not open it), and a Tier-A Hetzner reader missing from it reads as an unreviewed credential path |
| ADR-282 addendum and residual-text edit | - | inferred - justification: the residual "Detection of lifted protection is generic ... the post-apply read-back is the only distinct check" turns false on merge, and the ADR is the cited source (same reasoning as the 8c erratum) |
| Runbook `inngest-luks-cutover-6894.md` one-sentence pointer | - | inferred - justification: the runbook's "No drift check by log search" paragraph is the first place a responder reads about drift and should name the new distinct signal |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows`, `plugins/soleur/test` plus `scripts`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: about 1000 (about 300 workflow, about 550 suite, about 150 docs and registry), above the 800-line threshold on purpose: the suite is most of the diff and is the guard the brief demands; the production change is one added job. Recommendation below accounts for it.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the suite cannot be split from the job it executes (the job's own extractor floor reds without it), and the docs/registry edits are what the tier census and the ADR need to stay green; a split would land a red or an unguarded job.

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml` - insert job `sole-copy-protection-check` after
  `heartbeat-live-reconcile` and before the rung-2 comment block (about line 1860). Touch nothing else.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` - one Group 3 row, Tier A.
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` -
  addendum plus the residual-text edit.
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` - one sentence in the "No
  drift check by log search" paragraph. Do not touch the section-5c one-liner block (Guard 1 pins it
  byte-identical to the postmerge skill's copy).
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` - register the new suite.
- `scripts/lib/test-affected-paths.sh` - add the suite and its subject paths to the affected-paths lists.
- `plugins/soleur/test/token-drift-workflow-causes.test.sh` - add a pin that job `sole-copy-protection-check`'s
  steps are in the R1-R5 scanned population (the suite hardcodes `WF=` and its SCAN_PY is a heredoc, so the new
  suite cannot feed it a mutated workflow); check whether the R3 population assertion (exactly two filers named
  "File an issue for orphaned rehearsal hosts") or the steps-examined floor needs the new job's step count (the
  new filers are named differently, so no change is expected). Verify at work time.
- Read, not edited: `.github/actions/notify-ops-email/action.yml` (consumed), `.github/actions/infra-credentials/action.yml`
  (the Doppler CLI pin is copied from it and compared in a test), `scripts/lib/bearer-curl.sh`.

## Files to Create

- `plugins/soleur/test/sole-copy-drift-check.test.sh` - the executing suite and mutation matrix (Phase 1).

## Implementation Phases

### Phase 1 - RED first (the suite, before the job)

Write `plugins/soleur/test/sole-copy-drift-check.test.sh` against the Guard Contract below before the
workflow job exists, so every row is RED for the right reason.

**Harness shape (precedents: `token-drift-workflow-causes.test.sh`, `heartbeat-reconcile-issue-step.test.sh`).**

- One Python call (`python3 -I`, `yaml.safe_load`) extracts every step's `run:`, `env:` and `if:` of job
  `sole-copy-protection-check` by job id and step id (`probe`, `tf_commit`, `file_finding`, `file_unreadable`,
  `clear`, `notify`, `gate`). A resolver substitutes `secrets.DOPPLER_TOKEN` with a fixture, `github.*` with fixed
  values and `steps.<id>.outputs.<k>` with the real `$GITHUB_OUTPUT` of the producing step; an unresolvable
  reference is FATAL, so an output-key rename reds instead of reading empty. No `run:` body contains `${{`
  (static assertion); every expression lives in `if:` or `env:`. The job and filer `if:` expressions and the gate
  are evaluated with the heartbeat suite's GitHub-expression interpreter (copy it or extract it to
  `plugins/soleur/test/lib/gha-expr.py`).
- Each body runs as `env -u BASH_ENV -u SHELLOPTS -u BASHOPTS ... bash --noprofile --norc -e` (the runner's shell:
  `-e`, no pipefail; include the precedent's self-test, a control proving errexit is on) in a scratch `GITHUB_WORKSPACE` that holds a COPY of
  `scripts/lib/bearer-curl.sh`, `cmp`-verified against the repo file. The library is never stubbed; a stub `curl`
  first on `PATH` is the only seam. `GITHUB_OUTPUT`, `GITHUB_ENV`, `GITHUB_STEP_SUMMARY` and `RUNNER_TEMP` point
  at scratch files; `GITHUB_ENV` must stay empty after every case (the token must not persist).
- Stub `curl`: parses `-o <file>` and writes the fixture body there, prints the code for `-w '%{http_code}'`,
  reads stdin only for `--config -` and records it, applies the `name=` filter from the URL query itself (so
  dropping the filter really serves the unfiltered listing), and REFUSES any argv it does not model (exit 64
  plus a refusal log the suite asserts empty). Per request the suite asserts the recorded stdin config holds
  `header = "Authorization: Bearer <fixture>"` and that argv never holds the token. The existing curl stub
  prints only a code and ignores `-o`, so it is not reusable as is.
- Stub `doppler`: accepts only `secrets get <NAME> --plain` and refuses unless `DOPPLER_PROJECT=soleur` and
  `DOPPLER_CONFIG=prd_terraform` are in the environment; logs each requested name; the suite asserts exactly
  one call. Stub `gh`: a stateful in-memory issue store that rejects any flag the real CLI lacks and any
  non-`--json number,title` list shape. Stubs append to one shared `$SEQ` log so ordering is observable.
- Whole `$GITHUB_OUTPUT` compared per case: exact key set `{verdict, expected, live, volume_id, http, name,
  tf_age_min}`, one line each, no `<<` heredoc form.
- Anti-vacuity: the extractor floor (probe, tf_commit, both filers, clear, notify and gate steps all found); the
  heartbeat suite's outer/inner structure (re-run under an `_INNER` guard, count the inner pass/fail lines,
  conservation against the Results line, a pass()/fail() positive control, `FLOOR` set at the realized count with
  the comment and number in agreement).
- Rows that mutate step TEXT (2, 5, 6, 9, 12 below) run in-process on the YAML in the R5 style with a
  landed-in-region assertion; the committed behavioural cases above are what kill them at run time.
- Real-file case: run the probe with `GITHUB_WORKSPACE` at the real checkout; the step's `.tf` path is
  `"${GITHUB_WORKSPACE:?}/apps/web-platform/infra/inngest-redis-luks.tf"`. Assert the derived name and expected
  flag equal an independent Python derivation over the same file (never the literal `true`, so a sanctioned lift
  does not break the suite). Mutants on a copy: rename the resource; `delete_protection = var.x`; a duplicated
  attribute; `name = "other"` inside `labels = {...}`; a decoy `delete_protection = false` in the next resource
  (proves the block is bounded at its closing brace). Each gives `could-not-read`. The awk is POSIX (the runner
  is `mawk`); run it under `mawk` when present.
- Pins: the job's Doppler CLI version and sha256 equal the loader's; `VOLUME_ID_PIN` equals the id in ADR-282 and
  the postmerge skill's section-5c one-liner; the finding-filer text points at headings that exist (ADR-282,
  runbook "Sole-copy protection and key loss", step O5 of `infra-credential-tiers-8209.md`).

### Phase 2 - GREEN: the job

Insert one job (a specification for work-time code, not code):

1. **Job header.** `sole-copy-protection-check`; `runs-on: ubuntu-24.04`; `timeout-minutes: 10`;
   `if: github.ref == 'refs/heads/main'`; no `environment:`; no loader; no `continue-on-error` anywhere except
   the `notify` step; no `set -x`. The `if:` is hygiene only: it stops an unmerged `.tf` from filing issues on an
   accidental branch run. It is NOT a security boundary (a branch dispatch runs the branch's own workflow file;
   `DOPPLER_TOKEN` reach is the existing Tier-A posture), and a branch-modified copy of this job is outside the
   check's threat model. A header comment states the token ruling and that the read/write token is absent.
2. **Steps.**
   - `actions/checkout` (SHA-pinned like the siblings) with `persist-credentials: false`.
   - `doppler_cli`: the loader's pinned-tarball step copied into the job (`DOPPLER_CLI_VERSION` 3.75.3, the
     tarball's sha256 verified with `sha256sum -c`, appended to `$GITHUB_PATH`; bump together with the loader
     and `cloud-init.yml`). `DopplerHQ/cli-action` is NOT used: it declares no inputs and runs the mutable
     latest-CLI install script. The loader itself is not used either (its legacy arm exports `HCLOUD_TOKEN`).
   - `tf_commit`: `GH_TOKEN: ${{ github.token }}` bound here and in the filers only, never in `probe`. Reads the
     last commit time of the `.tf` with `gh api` on the commits endpoint (`path=` and `per_page=1`; a read that
     works with `contents: read`) and publishes one integer epoch; unreadable or empty publishes nothing. The
     checkout is shallow, so `git log -1 -- <path>` would return the HEAD commit and silently extend the grace.
   - `probe` (id `probe`): below.
   - `file_finding`, `file_unreadable`, `clear`, `notify`, `gate`: below. Outputs reach these steps through
     `env:` only; no `${{ ... }}` appears inside any `run:` of this job, and each step declares every ALL_CAPS
     variable it reads in its own `env:` (step env does not cross steps;
     `scripts/lint-workflow-step-env-refs.py` enforces it).
3. **Probe step.** Env: `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` (bound in this step only),
   `DOPPLER_PROJECT: soleur`, `DOPPLER_CONFIG: prd_terraform`, `TF_COMMIT_EPOCH`. `set -uo pipefail` with explicit
   status capture. A `run:` with no `shell:` key is `bash -e {0}` and `set -uo pipefail` does not clear `-e`, so
   begin the body with `set +e` or capture every status with `|| rc=$?`, never a bare `rc=$?`
   (`scripts/lint-workflow-errexit-capture.py` enforces it); a trap writes `verdict=could-not-read` first so a
   crash after that point still publishes a verdict; the response body goes to a `mktemp` file under
   `$RUNNER_TEMP` and is never printed; `jq` runs with stderr discarded and any failure maps to `could-not-read`.
   a. One named constant `VOLUME_ID_PIN=106903269` with a comment pointing at ADR-282 (a non-secret identifier
      that changes only on recreate, which is already a p1 event).
   b. Derive the volume name and expected flag from the `.tf`: a POSIX awk bounded to
      `resource "hcloud_volume" "inngest_redis_luks" {` through its closing brace, comments and trailing
      comments stripped, requiring exactly one top-level `name = "<literal>"` and exactly one
      `delete_protection = true|false`. The name must match `^[a-z0-9-]{1,63}$` BEFORE any URL or title is built;
      a failure stops with `could-not-read` and an empty `name` output. The raw value is never echoed.
   c. Read the token: `doppler secrets get HCLOUD_TOKEN_READONLY --plain` (explicit project and config flags) into
      a plain unexported shell variable, mask it per line immediately, no second read of any other name; run the
      library's pre-guard (`bc_ok_var`) so a shape-invalid or control-character token yields `no-token` without
      parsing stderr. Empty or failed is `no-token`.
   d. Make no request unless (b) and (c) succeeded.
   e. Request: `bc_curl scheduled-terraform-drift 'Authorization:Bearer :TOKEN' -- -sS --max-time 30 -o "$tmp" -w '%{http_code}' "https://api.hetzner.cloud/v1/volumes?name=${name}&per_page=50"`,
      GET only, stderr NOT redirected (it carries the refusal marker), inside a bounded three-attempt shell loop
      (5 s apart) that retries only on transport failure, 429 and 5xx (curl's `--retry` does not retry 429
      without `--retry-all-errors`, so the loop is the form used; `bc_curl` is not widened). 401 and 403 map
      to `no-token`; any other non-200, or exhausted retries, is `could-not-read`. Absence is expressed by an
      empty list, never by a 404.
   f. `jq` requires `(.volumes|type)=="array"`, `(.meta.pagination|type)=="object"`, `has("next_page")` and
      `next_page == null` (else `could-not-read`). Then: zero or more than one volume, or an `id` that is not
      the number `VOLUME_ID_PIN`, is `volume-not-found`; for exactly one, `.name == $name` and
      `.protection.delete` a JSON boolean (else `could-not-read`).
   g. Verdict (closed `case`): expected true, live true: `matches-declared`. Expected true, live false: when
      `TF_COMMIT_EPOCH` is a number and the `.tf` commit is under 90 minutes old, `lift-pending-apply`
      (green, `::warning::` plus a job-summary line); otherwise `lifted-outside-terraform` (finding). Expected
      false, live false: `unprotected-as-declared` (green, `::warning::` plus a job-summary line every run).
      Expected false, live true: `lift-not-applied` (green, `::warning::`). Plus `volume-not-found`,
      `could-not-read`, `no-token`.
   h. Publish single-line outputs only (`verdict`, `expected`, `live`, `volume_id`, `http`, `name`,
      `tf_age_min`) with `printf '%s=%s\n'`, each validated first (`name` `^[a-z0-9-]{1,63}$`; `volume_id`
      a jq `type=="number"` then `^[0-9]+$`; `http` `^[0-9]{3}$`; `expected`/`live` `^(true|false)$`;
      `tf_age_min` `^[0-9]+$`). A failing value becomes `could-not-read` with the field omitted. The API body is
      never echoed.
4. **Finding filer** (`file_finding`; `if: always()` and the verdict is `lifted-outside-terraform` or
   `volume-not-found`). Dedupe by exact title among open `infra-drift` issues:
   `gh issue list --label infra-drift --state open --limit 100 --json number,title` with
   `jq 'select(.title==$T)'` (never `--search`, which matches fuzzily); a list failure declines to create a
   duplicate and fails the step. Titles are built from the validated `$name`:
   `infra: Inngest store volume delete protection differs from Terraform (<name>)` and
   `infra: Inngest store volume not found at Hetzner (<name>)`. Labels `infra-drift`, `action-required`,
   `priority/p1-high`; milestone `Post-MVP / Later`, with one retry WITHOUT `--milestone` if the milestone is
   rejected so the p1 still files. While the condition holds, each run adds ONE one-line comment (verdict,
   expected, live, `.tf` last-commit time, run URL; no plan or log block). Public-safe body: it states that the
   delete-protection state of the Inngest store volume differs from its Terraform declaration, names
   ADR-282 and the runbook heading "Sole-copy protection and key loss", says this workflow prints no command and
   mutates nothing, says "closing this does not acknowledge; fix the declaration or restore the flag through the
   reviewed route", says "if a re-protect PR merged recently, check the apply run before acting", and
   cross-links the other title if open. It omits the Hetzner id and the phrases "sole copy" and "only copy" (the
   repo is public). The body spells no delete, no protection-change call, no detach, and echoes no API body.
5. **Could-not-perform filer** (`file_unreadable`; `if: always()` and the verdict is NOT one of the four clean
   verdicts or the two finding verdicts, so it also fires on an empty or unknown verdict from a probe crash,
   timeout or skipped step). Two titles so a later outage is not hidden by an old one:
   `infra: the Inngest store volume protection check has no usable credential (<name>)` for `no-token`, and
   `infra: the Inngest store volume protection check could not read Hetzner (<name>)` for everything else.
   Same exact-title dedupe, labels at `priority/p2-medium`, one one-line comment per run while the condition holds
   (so a stale open issue cannot mask a changed verdict), the verdict slug and HTTP code, no claim about the
   volume, and, for `no-token`, step O5 of `infra-credential-tiers-8209.md` plus the `DOPPLER_TOKEN` scope as the
   second cause.
6. **Clear step** (`clear`). On `matches-declared`, comment "cleared in run <url>: live equals declared" on any
   open issue with one of the four titles and close it only when its author is `github-actions[bot]`; a
   human-opened issue is never auto-closed; never comment on a closed issue.
7. **Notify step** (`notify`). `continue-on-error: true`, `uses: ./.github/actions/notify-ops-email`, `if:
   always()` and (a filer step's outcome is `failure`, or the verdict is a finding verdict), mirroring the
   rung-2 sweep's email step. Reason: `cron-terraform-drift.ts` only dispatches the run and never reads its
   conclusion, and no Sentry check-in covers this job, so a red run reaches no one on its own.
8. **Gate step** (`gate`). `if: always()`; prints `::error::sole-copy-check verdict=<slug> http=<code>` and exits
   1 unless the verdict is one of the four clean ones (`matches-declared`, `unprotected-as-declared`,
   `lift-pending-apply`, `lift-not-applied`); an empty verdict is red. It runs after the filers, so a non-clean
   run is red regardless of whether a filer succeeded.
9. **Concurrency note.** The workflow's `terraform-drift` group keeps one running and one pending run, so a
   manual dispatch during the queue can drop the 06:00 or 18:00 check, and a branch dispatch skips the job:
   the effective gap can exceed 12 hours. Accepted, documented in Observability.

### Phase 3 - registries and docs

Suite registration is generated, not hand-edited: run `python3 scripts/regenerate-shard-manifest.py --incremental --write`
(it edits `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`; expect a `floor` duration token until
measured). In `scripts/lib/test-affected-paths.sh` add
`AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS=( ... )` modelled on
`AFFECTED_PLUGINS_SOLEUR_TEST_HEARTBEAT_RECONCILE_ISSUE_STEP_TEST_SH_PATHS` (about line 1396), listing the
workflow, the `.tf`, `scripts/lib/bearer-curl.sh`, the loader `action.yml`, the suite itself, the runbook and
ADR-282 files (the suite checks their headings) and `scripts/lib/test-affected-paths.sh`.
`token-drift-workflow-causes.test.sh` is in `ALWAYS_ON_SUITES` (about line 226) and needs no new entry; the
consumer of these lists is `scripts/test-all.sh --affected` / the CI selection, and the consuming line is quoted
at work time before claiming the entry selects the suite. Docs: the Group 3 runbook row (Tier A,
`DOPPLER_TOKEN` to `HCLOUD_TOKEN_READONLY`, read-only GET); the ADR-282 addendum and residual edit (states: the
derived expectation makes a sanctioned lift quiet by design; the 90-minute grace; the id pin and what it does and
does not defend; a mis-minted read/write `HCLOUD_TOKEN_READONLY` is undetectable by this job and the O5 record is
the control; the effective check gap can exceed 12 hours); one sentence in the runbook; the three `.c4` files
re-read for the C4 enumeration. Follow-up issues (each per `wg-when-deferring-a-capability-create-a`, milestone
from the roadmap): add the job to the `scheduled-terraform-drift` Sentry monitor; extract a shared pinned
Doppler-install step; the web-1 `workspaces_luks` protection check.

### Phase 4 - verification (targeted only; CI is the authority)

`bash plugins/soleur/test/sole-copy-drift-check.test.sh`;
`bash plugins/soleur/test/token-drift-workflow-causes.test.sh`;
`bash plugins/soleur/test/terraform-drift-step-order.test.sh`;
`bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh`;
`bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`;
`bash scripts/alarm-issue-filing-guard.test.sh` (the highwater must not increase; every filer `if:` contains
`always()`); the four live workflow lints `scripts/lint-workflow-errexit-capture.py`,
`scripts/lint-workflow-step-env-refs.py`, `scripts/lint-workflow-run-body-syntax.py` and
`scripts/lint-workflow-issue-write-scope.py` (each runs as a `-live` suite in `scripts/test-all.sh`);
`bash tests/scripts/test-argv-bearer-sweep.sh`; `bash tests/scripts/test-infra-privileged-tier-census.sh`;
`bash .github/actions/infra-credentials/infra-credentials.test.sh`;
`bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-guard-contract.py`;
`bun test plugins/soleur/test/terraform-target-parity.test.ts`; the repo's registry/orphan census for the new
suite; `bash -n` on every extracted step body; YAML parse of the workflow. No Hetzner, Doppler or production call
is made by any of these (all use stubs and fixtures). Substitute-gate note: the new suite's affected-paths
declaration degrades the local `--affected` gate to the full battery, so the consumer suites above are run
directly and CI's full battery is the gate.

### Phase 5 - ship

Branch `feat-one-shot-9927-sole-copy-drift-check`, draft PR #10424. PR body: `Ref #9927` only, never a
closing keyword; after every PR body edit run
`gh pr view 10424 --json closingIssuesReferences --jq '.closingIssuesReferences'` and assert `[]`.
Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. The parked draft #10405 and
the plaintext-volume-resolver PR are not touched, synced or unparked. The known unrelated red
"Tenant integration (dev-Supabase)" on `test/server/action-sends-worm.test.ts` is not fixed here. A
workflow-file diff means an untrusted-CI merge path: no agent `--admin` fallback.

## Guard Contract

### Guard 1 - Sole-copy protection drift probe

**Property.** A live Hetzner object whose id is the pinned Inngest store volume and whose `protection.delete`
differs from the committed Terraform declaration (beyond the 90-minute apply grace), or that is absent or
ambiguous, always produces an issue of its own and a red run, and a probe that could not read Hetzner (including
one that produced no verdict at all) never reports clean.

**Assembly.** The population is every code path that can end the probe step with an output: (a) the `.tf`
derivation (name and expected flag) and the `.tf`-age input, (b) the token read and its shape pre-guard, (c) the
request loop (URL including the `name=` filter, HTTP code, retries, `-w` capture), (d) the `jq` reading
(container types, pagination key, count, id pin, name equality, boolean type), (e) the verdict `case`, which is
the one chokepoint every path must flow through to write `verdict=`, and the output validators in front of the
single `printf`. On the consuming side there are FOUR consumers of that one output, each exercised by the suite
and none by the first only: the finding filer's `if:`, the could-not-perform filer's `if:` (the COMPLEMENT of the
clean and finding sets, so an empty or unknown verdict still files), the notify step, and the gate. The job `if:`
and the steps' existence are part of the assembly. The assembly is the step texts extracted by job id and step id,
not a list of today's verdict words.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: live `protection.delete=false`, `.tf` `true`, `.tf` last commit 3 hours old (the property's core case) | RED: verdict `lifted-outside-terraform`, finding filer fires, notify fires, gate exits 1 |
| 2 | Own dispatch: rename the job id, flip the job `if:` to a constant false, rename a step id, or delete the gate or a filer so the extractor finds nothing | RED: the suite fails on its extractor floor (probe, tf_commit, both filers, clear, notify and gate each found), never "0 checked, exit 0" |
| 3 | Second member after a compliant first: the listing returns two volumes with the target name, the first matching and protected, the second unprotected | RED: verdict `volume-not-found` (ambiguous), not a read of the first |
| 4 | Drop the `name=` filter (the stub then serves a listing with a web-1-shaped volume); remove the `id` pin; point the pin at another id | RED: count is not 1 or the id check fails; the static URL assertion fails; id 106443278 appearing anywhere in the job text or in a request fails the suite; a forged same-name volume with another id yields `volume-not-found`, not `matches-declared` |
| 5 | REORDER, not delete: move the token read after the request | RED: the empty-token case must show no recorded request AND no `SOLEUR_CREDENTIAL_REFUSED` marker in the shared `$SEQ` log; the reordered body emits the marker. Plus a must-RED case: a shape-invalid token (`bad token"`) gives the marker, a non-clean verdict (`no-token`) and no request |
| 6 | Add a fallback read of `HCLOUD_TOKEN`, or bind it in any `env:` (stub `doppler` serves only the read/write name) | RED: with only the read/write token available the verdict is `no-token`, one doppler call is logged and zero requests are recorded; static assertion that the job text never names `HCLOUD_TOKEN` outside `HCLOUD_TOKEN_READONLY` |
| 7 | `next_page` non-null or the key absent; `meta` absent; `{}` or an error object with 200; a non-array `volumes`; non-200; 401/403; a transport failure; non-JSON body; `protection.delete` null, missing or the string "true"; `.name` mismatch; `volume_id` containing a newline | RED each: `could-not-read` (401/403: `no-token`), no clean verdict, no finding filer, exactly one line per key in `$GITHUB_OUTPUT`, job red |
| 8 | Empty-listing-as-clean: change `volume-not-found` handling so an empty list falls through to clean | RED: an empty listing yields `volume-not-found` and the finding filer |
| 9 | Make the gate `continue-on-error: true`, drop its `exit 1`, add `continue-on-error` to any other step, or put `could-not-read` or an empty verdict in the clean set | RED: static assertion plus the case table (empty and unknown verdict: the could-not-perform filer fires and the gate exits 1) |
| 10 | Remediation text (the tree the fix produces): render each filer body under the stub `gh`; assert it contains none of `curl`, `hcloud`, `doppler`, ` -X `, the Hetzner id, "sole copy" or "only copy", and that its dynamic fields are limited to {name, expected, live, http, tf_age_min, run URL}; then inject one write-verb line | GREEN for the real bodies; RED for the injected line. The static filer text is also covered by R1-R5 in `token-drift-workflow-causes.test.sh`, which gets a pin that this job's steps are in its scanned population |
| 11 | Print leakage: stub `curl` returns a body (also a malformed one) containing a label string; the token is a recognizable fixture | RED if the token appears in any captured stream, output or issue body after dropping lines matching `^::add-mask::` (at least one such line must exist and precede the first recorded request in `$SEQ`), or if the label string appears anywhere; `GITHUB_ENV` stays empty |
| 12 | Static job shape: add `environment:`, a `uses: ./.github/actions/infra-credentials` step or `DopplerHQ/cli-action` to the job; bind `DOPPLER_TOKEN` outside the probe step's `env:`; bind `GH_TOKEN` in the probe step; add `HCLOUD_TOKEN` (not `_READONLY`) to any `env:`; use any `secrets.*` other than `DOPPLER_TOKEN`; put `${{` in a `run:`; add `set -x` | RED (the loader would put the read/write token in the job environment; the mutable installer runs with the repo secret) |
| 13 | Second member: add a second job (same step names) containing a write verb | RED in R1-R5 (existing in-process write-verb rows quantify over every job, not the first) and in the suite's population assertion |
| 14 | Grace boundary and sequence: `.tf` age 89 vs 91 minutes; `TF_COMMIT_EPOCH` empty, non-numeric or in the future; then the ordered sequence clean, lift merge (declared false, live true), declared false and live false, re-protect merge (declared true, live false, age 5 min), age 95 min, clean, out-of-band lift, owner closes the issue, a 500, clean | RED when 91 min does not file or 89 min files; unreadable epoch fails open to `lifted-outside-terraform`; in the sequence: a lift merge is quiet, the 5-minute case is green with a warning, the 95-minute case files, a clean run comments "cleared" and closes only a bot-authored issue, a closed issue is replaced by a new one, one 500 files exactly one could-not-perform issue and a later clean run clears it |
| 15 | Partial failures: `gh issue create` succeeds then the step exits non-zero; the filer step fails outright; the milestone is missing; `gh issue list` fails | RED unless the gate still exits 1, a second run does not duplicate, the milestone-less retry files the p1, and a list failure creates nothing |

**Harness rows:** (H1) neuter the stub `curl` to always return a matching fixture - rows 1, 3, 7, 8 must go RED,
proving the suite can see its own stub; (H2) neuter the output comparison to the exit code only - the case table
must go RED (`lift-not-applied` and `matches-declared` both exit 0 and differ only in outputs, the discriminator);
(H3) delete one case from the table - the suite must FATAL on conservation or the floor. Must-PASS inputs that are
not the canonical: declared `false` with live `false` (the sanctioned lift, quiet but warned), declared `false`
with live `true` (warned, exit 0), a `.tf` with a trailing comment on the `delete_protection` line and a
commented-out opposite value earlier in the block, an API body with extra fields and reordered keys, a second
listing page whose `next_page` is explicitly `null`, and two `.tf` fixtures with different names (a hard-coded
name must red).

**Anchor.** The stored value is the `.tf` declaration, and the pinned id is a second stored value. A single diff
can edit the `.tf`, the pin and this workflow together, so this check proves live-versus-declared consistency, not
integrity. The outside anchors are the independent `G2e` effective-text pin in
`plugins/soleur/test/terraform-target-parity.test.ts` (a required check and a separate implementation in another
language), Guard 1 of #9879, the test that `VOLUME_ID_PIN` equals the id in ADR-282 and the postmerge skill's
section-5c one-liner, and the live Hetzner state itself, which no diff can edit. A lift therefore requires the
reviewed two-step route and an apply that makes the live flag change, and this check is quiet only after both have
happened. Residual, stated in the ADR addendum: a branch actor who can plant `HCLOUD_TOKEN_READONLY` (until the
ADR-241 O11 eviction) can point the job at another Hetzner project but cannot forge a match for the pinned id.

## Observability

```yaml
liveness_signal:
  what: the job sole-copy-protection-check of the Inngest-dispatched drift workflow concludes success only on a clean verdict; NOTHING consumes that conclusion automatically (cron-terraform-drift.ts only dispatches the run and never reads it, and no Sentry check-in covers this job), so job liveness is read from the next run and from AC11
  cadence: every 12 hours (06:00 and 18:00 UTC, dispatched by apps/web-platform/server/inngest/functions/cron-terraform-drift.ts); the effective gap can exceed 12 hours because the terraform-drift concurrency group keeps one running and one pending run, so a manual dispatch during the queue can drop a scheduled check, and a branch dispatch skips the job
  alert_target: a GitHub issue under the infra-drift label (primary; priority/p1-high for lifted-outside-terraform and volume-not-found, priority/p2-medium for no-token and could-not-read) plus a notify-ops-email message on a finding verdict or a failed filer; the red run is a log artifact, not an alert
  configured_in: .github/workflows/scheduled-terraform-drift.yml (job sole-copy-protection-check)
error_reporting:
  destination: GitHub issues under the infra-drift label, the notify-ops-email fallback, and an ::error:: annotation in the workflow run log (layer 6, workflow run log) naming the verdict slug
  fail_loud: the gate step exits 1 on every non-clean verdict (including an empty one) after the filers ran and prints ::error::sole-copy-check verdict=<slug> http=<code>; no filer step is continue-on-error, so a failed filer reddens the job and triggers the email
failure_modes:
  - mode: protection flag lifted outside Terraform (live false, declared true, .tf unchanged for more than 90 minutes)
    detection: verdict lifted-outside-terraform from the live GET
    alert_route: finding issue (p1, one comment per run) and notify-ops-email; run-log annotation (layer 6)
  - mode: volume deleted, renamed, replaced under a new id, or two volumes share the name
    detection: verdict volume-not-found (zero or more than one match, or an id other than the pinned one)
    alert_route: finding issue (p1) and notify-ops-email; run-log annotation (layer 6)
  - mode: Hetzner unreachable, HTTP error after retries, truncated or malformed listing, unparseable .tf, probe crash or timeout (empty verdict)
    detection: verdict could-not-read or an empty verdict (the could-not-perform filer is the complement of every other verdict set)
    alert_route: could-not-perform issue (p2, one comment per run) and run-log annotation (layer 6); email only if a filer fails
  - mode: HCLOUD_TOKEN_READONLY absent from prd_terraform, rejected (401/403) or DOPPLER_TOKEN unauthorized
    detection: verdict no-token
    alert_route: credential issue (p2, one comment per run) and run-log annotation (layer 6)
  - mode: sanctioned unprotected window or an unapplied lift (declared false)
    detection: verdicts unprotected-as-declared and lift-not-applied
    alert_route: ::warning:: annotation plus a job-summary line every run (layer 6); no issue by design (ADR-282 states nothing alerts in that window; the dated re-protect issue is the forcing function)
logs:
  where: GitHub Actions run log of the drift workflow (layer 6, workflow run log); values masked; only verdict, expected and live flag, http code, volume id and name are printed
  retention: GitHub Actions default log retention
discoverability_test:
  command: curl -s "https://api.github.com/search/issues?q=repo:jikig-ai/soleur+is:open+label:infra-drift+Inngest+store+volume+in:title&per_page=1"
  expected_output: total_count
```

The probe is a runner-side job (not a blind sandbox or a host), so the in-surface probe is the job itself. The
discoverability command reads the job's own alarm channel through the unauthenticated public search API (it
printed a `total_count` of 0 when executed at plan time, with no Hetzner, Doppler or production call): a non-zero
count means a finding issue is open. It cannot prove the job ran (a removed or never-run job also reads 0); job
liveness is AC11 plus the executed suite (Guard 1 row 2). The first scheduled run after merge is the proof run
(read it with `gh run list` and `gh run view`, which are read-only); no dispatch is required and none is
authorized by this plan. Accepted gap, with a tracked follow-up (filed in Phase 3): a silently skipped or dropped
job is caught only by the executed suite in CI and by AC11, not at runtime, because adding a Sentry check-in would
move `cron-monitors.tf` and the C4 count-parity numbers.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. Job `sole-copy-protection-check` exists in `.github/workflows/scheduled-terraform-drift.yml`, inserted
  between `heartbeat-live-reconcile` and the rung-2 comment block; `git diff origin/main --stat` for that
  file shows only additions inside that gap (no edit to any existing job, none to the
  inngest-rehearsal-orphan-sweep region).
- [ ] AC2. The job has no `environment:`, no `infra-credentials` step, and its only Hetzner credential is
  `HCLOUD_TOKEN_READONLY` read with no fallback (Guard 1 rows 6 and 12 green).
- [ ] AC3. Every request is a GET to `https://api.hetzner.cloud/v1/volumes?name=...` (name derived from the
  `.tf`), via `bc_curl`; web-1's id 106443278 appears nowhere in the job or in any request (Guard 1 row 4).
- [ ] AC4. All verdict classes behave as specified by executing the extracted step bodies under stubs
  (Guard 1 rows 1, 3, 7, 8, 9, 14, 15), including that an unreadable or empty state never yields a clean
  verdict and that the id pin rejects a same-name volume with another id.
- [ ] AC5. No issue body or log line contains a delete, detach, protection-change or non-GET method
  spelling, and R1-R5 in `token-drift-workflow-causes.test.sh` stays green with its floors unchanged or
  deliberately raised (Guard 1 rows 10 and 13); `token-drift-workflow-causes.test.sh` gains a pin that this
  job's steps are in the scanned population; `scripts/alarm-issue-filing-guard.test.sh` stays green and its
  highwater count does not increase.
- [ ] AC6. The new suite is registered by `python3 scripts/regenerate-shard-manifest.py --incremental --write`
  (both TSVs) and by an `AFFECTED_*_PATHS` array in `scripts/lib/test-affected-paths.sh`, and the repo's
  registry/orphan/affected-paths checks pass.
- [ ] AC7. The targeted suites in Phase 4 pass locally; `python3 scripts/lint-guard-contract.py` passes on
  this plan; the tier census and argv-bearer sweep stay green.
- [ ] AC8. Runbook Group 3 row, ADR-282 addendum plus residual edit, and the runbook sentence are in the PR;
  the ADR status remains `accepted`; the section-5c one-liner block is byte-identical to before; the job's
  Doppler CLI version and sha256 equal the loader's and `VOLUME_ID_PIN` equals the ADR-282 and postmerge-skill
  value (both pinned by tests); the three follow-up issues (Sentry check-in, shared pinned Doppler-install
  step, web-1 `workspaces_luks` check) exist with a roadmap milestone.
- [ ] AC9. PR body contains `Ref #9927` and no closing keyword; `gh pr view 10424 --json closingIssuesReferences
  --jq '.closingIssuesReferences'` prints `[]` after the last body edit.
- [ ] AC10. No file outside `.github/workflows/scheduled-terraform-drift.yml`, the paths in Files to Edit/Create
  and the plan/spec artifacts is changed; the parked draft PRs are untouched.

### Post-merge (read-only)

- [ ] AC11. The first Inngest-dispatched drift run after merge (up to 12 hours after the merge): the new job
  concludes success with verdict `matches-declared` (read with `gh run view`; no agent dispatch is needed, and a
  proof dispatch would need the owner's per-command go-ahead). If it reports `no-token` or `could-not-read`,
  the could-not-perform issue is the finding and #9927 gets a comment; nothing is retried by an agent without
  that go-ahead.
- [ ] AC12. #9927 stays open (this PR carries `Ref` only); a comment on #9927 records item 9 as built and
  the web-1 `workspaces_luks` follow-up.

## Test Scenarios

1. Declared true, live true: green, no issue, `verdict=matches-declared`; a bot-authored open issue is cleared.
2. Declared true, live false, `.tf` last commit older than 90 minutes: red run, finding issue created (first
   run) or commented (later runs), email sent.
3. Declared true, live false, `.tf` commit under 90 minutes old: `lift-pending-apply`, green with a warning.
   Declared false, live false: `unprotected-as-declared`, green with a warning every run. Declared false, live
   true: `lift-not-applied`, green with a warning.
4. Zero volumes with the name; two volumes with the name (first compliant); a same-name volume with another id:
   `volume-not-found`, finding issue.
5. Token absent or shape-invalid; token rejected (401/403); HTTP 500 after retries; HTTP 200 with a non-JSON
   body, `{}` or an error object; `next_page` non-null or absent; `protection` missing; probe crash (empty
   verdict): each `could-not-read` or `no-token`, red run, could-not-perform issue, no claim about the volume.
6. `.tf` resource renamed or `delete_protection` written as a variable: `could-not-read`.
7. Existing issue found by title: comment, not create; `gh issue list` failure: no duplicate, job red; the
   milestone missing: the p1 still files without it.
8. Sentinel secrecy: the fixture token never appears in any captured stream or issue body.
9. The ordered multi-run sequence (Guard 1 row 14).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6; this plan's is filled with `aggregate pattern`.
- The R1-R5 scan is a tripwire on spelling: the new filer bodies and comments must describe the absence of a
  recipe without spelling one (no method flag, no verb-before-URL, no hcloud write verb, no protection-change
  word next to an API path). Write the prose, then run R1-R5, then rewrite.
- `bc_curl` returns rc 2 for a refused credential and curl's own exit 2 collides with it. Do not branch on
  rc 2 and never redirect `bc_curl`'s stderr; give a shape-invalid or control-character token its verdict
  with the library's pre-guard (`bc_ok_var`) BEFORE the request, then treat the rc as curl's. `bc_curl` does
  not enforce GET-only (it accepts a method flag and a body flag), so the no-write guarantee rests on the
  executed argv assertion (the recorded URL matches the pinned pattern and no method or body flag appears), the
  R1-R5 text scan and the token's scope; a mis-minted read/write `HCLOUD_TOKEN_READONLY` is undetectable here
  and is stated as a residual in the ADR addendum.
- Hetzner contract (public docs and the SDK; no API call was made): the `name` filter is documented as exact
  match on sibling list endpoints and as a volumes filter in the official SDK; name uniqueness per project is
  documented for the console only; `protection.delete` is a boolean (SDK type) and the single-volume read is
  recorded in the runbook section 5c; `meta.pagination.next_page` is null on the last page and `per_page` caps
  at 50; an invalid token is 401 `unauthorized`; the default rate limit is 3600 requests per hour per project,
  shared with the other `HCLOUD_TOKEN` callers (one GET per run is negligible; 429 is retried then
  `could-not-read`). The list-envelope `protection.delete` is inferred from the SDK type and the single-volume
  read; confirm it with the first run (AC11), not before.
- The shallow checkout makes `git log -1 -- <path>` return the HEAD commit, not the `.tf`'s last change; the
  `.tf` age therefore comes from the commits API in its own step.
- The job reads `secrets.DOPPLER_TOKEN`, which is a repo secret scoped to one config; if its scope is not
  `prd_terraform` the result is `no-token`, which is the designed signal and not a code defect.
- Do not edit the inngest-rehearsal-orphan-sweep job or the section-5c one-liner block; the first would
  conflict with the parked #10405 and the second is pinned byte-identical by Guard 1 of #9879.
- Spelling tripwires that run over this job's text: in the job text never use the bare word `curl` or `wget`
  (say "the bearer library"; R1's flattened body-flag scan also looks at prose because comments are not
  stripped), never `awk -F` or `grep -F` in a step that also holds a `bc_curl`, never the dotted address
  `hcloud_volume.inngest_redis_luks` next to `-target`, `-replace`, `terraform destroy`, `state rm|mv|push`,
  `terraform import` or `terraform taint` (the parity test's G2 sole-copy census runs over every workflow job;
  the `.tf` awk uses the space-separated `resource "hcloud_volume" "inngest_redis_luks"` spelling, which is
  fine), and no `monitor-slug:` text (C4 count parity). The argv-bearer sweep (S3, the workflow is already in
  `S3_MANIFEST`) requires at the `bc_curl` site: the exact `source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"`
  line in the same step before the first call (D1), no `-H` (D2), no `2>/dev/null` on the call (D3), no line that
  tests `= 2` against `rc`/`$?` without `exit 2` (D5), and the caller name `scheduled-terraform-drift` (D6).
  `S3_CALLS_FLOOR` (41) may be raised by one for the new site (optional, taste).
- A new suite for a workflow-YAML subject needs an `AFFECTED_*_PATHS` declaration (the census reports it
  UNCLASSIFIED otherwise), and that declaration degrades the local `test-all.sh --affected` gate to the full
  battery (`INDEX-UNBOUND`), which a sibling full run then refuses (rc=4). Substitute gate, named up front:
  run the consumer suites of the touched registration files and the ratchets directly (Phase 4 list) and let
  CI's full battery be the gate. A suite that stubs `sha256sum` and names a second workflow file also owes a
  `grep-q-pipe-guard` triple; this suite stubs neither, so none is expected.
- Any negated grep in the suite (`! grep -q`) folds grep's rc 2 (bad pattern) into "no match"; use `grep -c`
  comparisons or an explicit `rc -eq 1` check plus a pattern compile pre-check.
- The `discoverability_test` command was executed once at plan time and printed `200` (public GitHub API,
  no Hetzner, Doppler or production call). It contains none of the shell-active characters preflight
  Check 10 rejects.
- Run `npx markdownlint-cli2` on this plan and on `tasks.md` before the session summary (tabs inside quoted
  commands, lists starting right after a heading).
- Plan-prescribed paths were verified to exist: `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`,
  `scripts/lib/test-affected-paths.sh` (the `token-drift-workflow-causes` entries are the template).

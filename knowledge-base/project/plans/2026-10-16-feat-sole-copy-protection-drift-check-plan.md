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
6. A sanctioned two-step lift (ADR-282) does not page for its whole duration.

**Cut List (mechanisms the ask or the first design proposed that were removed).**

- Reuse of the loader-exported `HCLOUD_TOKEN` (it breaks property 5) -> the new job's own
  `HCLOUD_TOKEN_READONLY` read; the loader is not used.
- A hard-coded volume id and a hard-coded expected `true` -> the id is looked up by name and the expected
  flag is derived from the checked-out `.tf` (already pinned by Guard 1 and the parity test, so a third
  copy would be a new place to drift and would page during a sanctioned lift).
- The email fallback the orphan sweeps carry (buys "finding reaches a channel when `gh` fails") -> the job
  is red when a filer step fails, and a red run is the channel; `notify-ops-email` is not added.
- A Sentry cron-monitor / heartbeat slug for the new job (would move the C4 count-parity numbers and
  `cron-monitors.tf`) -> not added; the issue plus the red run are the signal.
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

- Both existing sweeps: `environment: infra-privileged`, loader, `TOKEN="${HCLOUD_TOKEN:-}"`,
  `source scripts/lib/bearer-curl.sh`, `bc_curl scheduled-terraform-drift 'Authorization:Bearer :TOKEN' -- -sS -f URL`,
  fail-closed on a listing failure and on `meta.pagination.next_page != null`, idempotent create-or-comment
  on `infra-drift`, and a create-only "could not perform" filer.
- Tier census (`tests/scripts/test-infra-privileged-tier-census.sh`): G1g inspects only `TIER_B_NAMES`;
  `HCLOUD_TOKEN_READONLY` is not one, so a no-fallback read of it from `prd_terraform` is permitted.
  `ENV_SECRETS` is only `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE`, `DOPPLER_TOKEN_GIT_DATA_ROOT`
  and `DOPPLER_TOKEN_INFRA_APP`; the new job names none, so it is Tier A (G1b/G1c do not fire).
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
| Item 9 / triage: "about 60 lines" | One GET plus the fail-closed reads, two filers and a red-job gate that the sibling sweeps carry is about 150-190 workflow lines (comments included), plus a new test suite | Keep the outcome, record the estimate as wrong (decision-challenges row); do not trim the fail-closed behaviour to hit the number |
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
(`bc_curl`, ADR-280) and never printed; issue bodies carry the volume name, id, the expected and live
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

Amend ADR-282 with an append-only addendum (status stays `accepted`): the distinct recurring signal now
exists, and its limits (a derived expectation, so a lift that was applied through the sanctioned two-step
route is quiet by design; the read is a point-in-time flag read, not a `prevent_destroy` read-back). Update
the residual "Detection of lifted protection is generic" to point at the new check. Via the `architecture`
skill / Edit in this PR, never a deferred issue.

### C4 views

"No C4 impact", with the enumeration checked against all three model files
(`model.c4`, `views.c4`, `spec.c4`), to be re-read at work time: (a) external human actors - none added;
(b) external systems - Hetzner API (edge `github -> hetzner` exists and already states that the remaining
Hetzner calls through it are reads; the sibling drift orphan sweeps are likewise not named there), Doppler
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
| Runbook Group 3 row in `infra-credential-tiers-8209.md` | - | inferred - justification: the tier census requires every job that references `secrets.DOPPLER_TOKEN` to be classified, or the census goes red |
| ADR-282 addendum and residual-text edit | - | inferred - justification: the residual "Detection of lifted protection is generic ... the post-apply read-back is the only distinct check" turns false on merge, and the ADR is the cited source (same reasoning as the 8c erratum) |
| Runbook `inngest-luks-cutover-6894.md` one-sentence pointer | - | inferred - justification: the runbook's "No drift check by log search" paragraph is the first place a responder reads about drift and should name the new distinct signal |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows`, `plugins/soleur/test` plus `scripts`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: about 650 (about 180 workflow, about 330 suite, about 140 docs and registry)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

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
- `plugins/soleur/test/token-drift-workflow-causes.test.sh` - only if the R3 population assertion (exactly
  two filers named "File an issue for orphaned rehearsal hosts") or the steps-examined floor needs the new
  job's step count; the filers are named differently, so the expectation is no edit. Verify at work time.

## Files to Create

- `plugins/soleur/test/sole-copy-drift-check.test.sh` - the executing suite and mutation matrix (Phase 1).

## Implementation Phases

### Phase 1 - RED first (the suite, before the job)

Write `plugins/soleur/test/sole-copy-drift-check.test.sh` against the Guard Contract below before the
workflow job exists, so every row is RED for the right reason. Shape: load the workflow with `python3 -I`
and `yaml.safe_load`, extract the probe and filer step `run:` bodies of job `sole-copy-protection-check`
by job id, and run them in a scratch directory under stub `curl`, `doppler` and `gh` on a synthesized
`PATH`, with a synthesized `.tf` and synthesized Hetzner JSON fixtures (`cq-test-fixtures-synthesized-only`).
The stubs record argv and stdin; the suite asserts the whole `$GITHUB_OUTPUT` content and the exit code
per case. Anti-vacuity floors: the extractor must find the probe step, both filer steps and the gate step
by their step ids (the gate's `exit 1` per verdict is executed, not only grepped), and the suite counts its
own executed cases against a pinned minimum.

### Phase 2 - GREEN: the job

Insert one job. Design (this is a specification for work-time code, not code):

1. **Job header.** `sole-copy-protection-check`; `runs-on: ubuntu-24.04`; `timeout-minutes: 10`;
   `if: github.ref == 'refs/heads/main'` (a branch dispatch cannot redefine the expectation); no
   `environment:`; no loader; the workflow's existing `permissions: contents: read, issues: write` suffice.
   A header comment states the token ruling and that the read/write token is deliberately absent.
2. **Steps.** Checkout (SHA-pinned, same pin as the sibling jobs); Doppler CLI setup with
   `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4` (the pin `apply-sentry-infra.yml`
   already uses); the probe step (id `probe`); the finding filer; the could-not-perform filer; a final
   gate step that fails the job on any verdict other than `protected-as-expected` or
   `protection-unexpected-on`.
3. **Probe step.** Env: `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}`, `DOPPLER_PROJECT: soleur`,
   `DOPPLER_CONFIG: prd_terraform`. `set -uo pipefail` with explicit status capture (a bare `-e` aborts
   with no named verdict). Order:
   a. Derive the volume name and expected flag from `apps/web-platform/infra/inngest-redis-luks.tf`:
      a bounded awk over `resource "hcloud_volume" "inngest_redis_luks" {` to its closing brace, comments
      and trailing comments stripped, requiring exactly one `name = "<literal>"` (shape
      `^[a-z0-9-]+$`) and exactly one `delete_protection = true|false`. Anything else is `could-not-read`.
   b. Read the token: `doppler secrets get HCLOUD_TOKEN_READONLY --plain` into a variable, `::add-mask::`
      it per line immediately, **no second read of any other name**. Empty or failed is `no-token` (the two
      causes share one verdict and one issue, so Doppler's stderr is not parsed and never echoed).
   c. Make no request unless (a) and (b) both succeeded.
   d. `bc_curl scheduled-terraform-drift 'Authorization:Bearer :TOKEN' -- -sS --max-time 30 -o "$tmp" -w '%{http_code}' "https://api.hetzner.cloud/v1/volumes?name=${name}&per_page=50"`
      with GET only (no method flag, no body flag, no stderr redirect on `bc_curl`). Non-200 is
      `could-not-read` (a 404 on the list endpoint is also `could-not-read`; absence is expressed by an
      empty list).
   e. `jq`: `.meta.pagination.next_page` must be `null` (else `could-not-read`); count of `.volumes`;
      0 or more than 1 is `volume-not-found`; for exactly 1, `.volumes[0].name == $name` and
      `.volumes[0].protection.delete` must be a JSON boolean (else `could-not-read`).
   f. Verdict: `protected-as-expected` (live == expected), `protection-missing` (expected true, live
      false), `protection-unexpected-on` (expected false, live true: `::notice::` and a job-summary
      line, no issue), `volume-not-found`, `could-not-read`, `no-token`.
   g. Publish single-line outputs only (`verdict`, `expected`, `live`, `volume_id`, `http`, `name`):
      the API body is never echoed and never written to a multi-line output.
4. **Finding filer** (`if: always() && (verdict == protection-missing || verdict == volume-not-found)`).
   Idempotent create-or-comment on exact title match among open `infra-drift` issues (the sibling
   filers' shape; a `gh issue list` failure declines to create a duplicate and fails the step). Titles:
   `infra: sole-copy volume protection missing (soleur-inngest-redis-store-luks)` and
   `infra: sole-copy volume not found at Hetzner (soleur-inngest-redis-store-luks)`. Labels
   `infra-drift`, `action-required`, `priority/p1-high`; milestone `Post-MVP / Later`. Comment on every
   run while the condition holds. Body assembled inline (no repo-file `cat`, no `uses:`): facts only (name,
   id, expected and live flag, run URL), the statement that this workflow prints no command and mutates
   nothing, and a pointer to ADR-282 and the runbook heading "Sole-copy protection and key loss"
   (restoring the flag is a reviewed change or the per-merge apply delivered on the owner's per-command
   go-ahead, per that section). The body spells no delete, no protection-change call, no detach.
5. **Could-not-perform filer** (`if: always() && (verdict == could-not-read || verdict == no-token)`).
   Create-only, title `infra: the sole-copy protection check could not read Hetzner (soleur-inngest-redis-store-luks)`,
   same labels at `priority/p2-medium`; states the verdict slug and the HTTP code, claims no verdict about
   the volume, and names step O5 of `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
   (the read-only token) when the slug is `no-token`.
6. **Gate step.** `exit 1` for every verdict except the two clean ones, after the filers ran
   (`if: always()`), so a non-clean run is red regardless of whether a filer succeeded.

### Phase 3 - registries and docs

Suite registry entries (`scripts/suite-shard-legs.tsv` with a shard number matching the neighbours,
`scripts/suite-durations.tsv` as an incremental row, and in `scripts/lib/test-affected-paths.sh` a new
`AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS=( ... )` array modelled on
`AFFECTED_PLUGINS_SOLEUR_TEST_HEARTBEAT_RECONCILE_ISSUE_STEP_TEST_SH_PATHS` (about line 1396), listing the
workflow, the `.tf`, `scripts/lib/bearer-curl.sh`, the suite itself and `scripts/lib/test-affected-paths.sh`;
`token-drift-workflow-causes.test.sh` is in `ALWAYS_ON_SUITES` at about line 226 and needs no new entry).
The consumer of these lists is `scripts/test-all.sh --affected` / the CI selection; quote the consuming line
at work time before claiming the entry selects the suite. Runbook Group 3 row (Tier A,
`DOPPLER_TOKEN` to `HCLOUD_TOKEN_READONLY`, read-only GET). ADR-282 addendum and residual edit. One-sentence
runbook pointer. Re-read the three `.c4` files for the C4 enumeration above.

### Phase 4 - verification (targeted only; CI is the authority)

`bash plugins/soleur/test/sole-copy-drift-check.test.sh`;
`bash plugins/soleur/test/token-drift-workflow-causes.test.sh`;
`bash plugins/soleur/test/terraform-drift-step-order.test.sh`;
`bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh`;
`bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`;
`bash tests/scripts/test-argv-bearer-sweep.sh`; `bash tests/scripts/test-infra-privileged-tier-census.sh`;
`bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-guard-contract.py`;
`bun test plugins/soleur/test/terraform-target-parity.test.ts`; the repo's affected-paths/registry checks
for the new suite (`TEST_GROUP=affected` form); `bash -n` on every extracted step body; YAML parse of the
workflow. No Hetzner, Doppler or production call is made by any of these (all use stubs and fixtures).

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

**Property.** A live Hetzner object named `soleur-inngest-redis-store-luks` whose `protection.delete`
differs from the committed Terraform declaration, or that is absent or ambiguous, always produces an
issue of its own and a red run, and a probe that could not read Hetzner never reports clean.

**Assembly.** The population is every code path that can end the probe step with an output: (a) the
`.tf` derivation (name and expected flag), (b) the token read, (c) the request (URL including the `name=`
filter, HTTP code, `-w` capture), (d) the `jq` reading (pagination, count, name equality, boolean type),
(e) the verdict function, which is the one chokepoint every path must flow through to write `verdict=`,
(f) the two filer `if:` conditions keyed on that single output, (g) the final gate step, and (h) the job
`if:`. More than one chokepoint exists on the consuming side (two filers plus the gate), so the suite
quantifies over all three, not the first filer. The assembly is the step texts extracted by job id and
step id, not a list of current verdict words.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: live `protection.delete=false`, `.tf` `true` (the property's core case) | RED: verdict `protection-missing`, finding-filer condition true, gate exits 1 |
| 2 | Own dispatch: rename the job id, flip the job `if:` to a constant false, or rename the probe step id so the extractor finds nothing | RED: the suite fails on its extractor floor (probe step and two filers must each be found), never "0 checked, exit 0" |
| 3 | Second member after a compliant first: the listing returns two volumes with the target name, the first protected and matching, the second unprotected | RED: verdict `volume-not-found` (ambiguous), not a read of the first |
| 4 | Drop the `name=` filter from the URL (the suite's stub then serves a listing that includes a web-1-shaped volume) | RED: count is not 1, and the static URL assertion fails; the id 106443278 appearing anywhere in the job text or in a request fails the suite |
| 5 | REORDER, not delete: move the token read after the request | RED: the empty-token case must show zero recorded requests; the reordered body records one (a single case; the order is not a listed property, so no further reorder rows) |
| 6 | Add a fallback read of `HCLOUD_TOKEN` (stub `doppler` serves only the read/write name) | RED: with only the read/write token available the verdict must be `no-token` and zero requests are recorded; also a static assertion that the job text never names `HCLOUD_TOKEN` outside the string `HCLOUD_TOKEN_READONLY` |
| 7 | `meta.pagination.next_page` non-null; non-200; non-JSON body; `protection.delete` null, missing or the string "true"; `.volumes[0].name` mismatching | RED each: `could-not-read`, no `protected-as-expected`, no finding filer, job red |
| 8 | Empty-listing-as-clean: change `volume-not-found` handling so an empty list falls through to clean | RED: empty listing must yield `volume-not-found` and the finding filer |
| 9 | Make the gate step `continue-on-error: true`, drop its `exit 1`, or make a clean-verdict set that includes `could-not-read` | RED: static assertion on the step plus the case table |
| 10 | Remediation text (the tree the fix produces): render each filer body under the stub `gh` and run the R1-R5 classifier over the rendered text; then inject one write-verb line into a body | GREEN for the real bodies; RED for the injected line (proves the classifier is wired to the rendered body; the per-spelling matrix belongs to R1-R5 and is not duplicated here) |
| 11 | Print leakage: stub `curl` returns a body containing a label string; the token value is a recognizable fixture | RED if the fixture token or the label string appears in stdout, stderr, any output or any issue body |
| 12 | Static job shape: add `environment: infra-privileged` or a `uses: ./.github/actions/infra-credentials` step to the job, or add `HCLOUD_TOKEN` (not `_READONLY`) to any step or job `env:` | RED (the loader would put the read/write token in the job environment) |
| 13 | Second member: add a second job (same step names) containing a write verb | RED in R1-R5 and in the suite (the scan quantifies over every job, not the first) |

**Harness rows:** (H1) neuter the stub `curl` to always return a protected fixture - the suite's
lifted-protection rows (1, 3, 7, 8) must go RED, proving the suite can see its own stub; (H2) neuter the
output comparison (compare only the exit code) - the case table must go RED; (H3) lower the pinned
minimum executed-case count - the suite must FATAL. Must-PASS inputs that are not the canonical:
`.tf` `false` with live `false` (the sanctioned lift, quiet), `.tf` `false` with live `true` (notice only,
exit 0), a `.tf` carrying a trailing comment on the `delete_protection` line and a commented-out opposite
value earlier in the block, an API body with extra fields and reordered keys, and a second listing page
whose `next_page` is explicitly `null`.

**Anchor.** The stored value is the `.tf` declaration. A single diff can edit both the `.tf` and this
workflow, so this check proves live-versus-declared consistency, not integrity. The outside anchors are
the independent `G2e` effective-text pin in `plugins/soleur/test/terraform-target-parity.test.ts` (a
required check and a separate implementation in another language) and Guard 1 of #9879, plus the live
Hetzner state itself, which no diff can edit; a lift therefore requires the reviewed two-step route and an
apply that makes the live flag change, and this check is quiet only after both have happened.

## Observability

```yaml
liveness_signal:
  what: the twice-daily Inngest-dispatched run of the drift workflow, whose job sole-copy-protection-check concludes success only on a clean verdict
  cadence: every 12 hours (06:00 and 18:00 UTC, dispatched by apps/web-platform/server/inngest/functions/cron-terraform-drift.ts)
  alert_target: a red job on a non-clean verdict plus a GitHub issue (infra-drift, action-required, priority/p1-high for protection-missing and volume-not-found; priority/p2-medium create-only for could-not-read and no-token)
  configured_in: .github/workflows/scheduled-terraform-drift.yml (job sole-copy-protection-check)
error_reporting:
  destination: GitHub issues under the infra-drift label plus the run annotation (::error:: with the verdict slug)
  fail_loud: the final gate step exits 1 on every non-clean verdict after the filers ran; a filer failure is not continue-on-error, so it reddens the job
failure_modes:
  - mode: protection flag lifted outside Terraform (live false, declared true)
    detection: verdict protection-missing from the live GET
    alert_route: finding issue (p1, comment on every run) and red run
  - mode: volume deleted or renamed, or two volumes share the name
    detection: verdict volume-not-found (zero or more than one match)
    alert_route: finding issue (p1) and red run
  - mode: Hetzner unreachable, HTTP error, truncated listing, malformed body, unparseable .tf
    detection: verdict could-not-read (no verdict about the volume is claimed)
    alert_route: create-only could-not-perform issue (p2) and red run
  - mode: HCLOUD_TOKEN_READONLY absent from prd_terraform or DOPPLER_TOKEN unauthorized
    detection: verdict no-token
    alert_route: create-only could-not-perform issue (p2) and red run
logs:
  where: GitHub Actions run log of the drift workflow (values masked; only verdict, expected and live flag, http code, volume id and name are printed)
  retention: GitHub Actions default log retention
discoverability_test:
  command: curl -s -o /dev/null -w "%{http_code}" https://api.github.com/repos/jikig-ai/soleur/actions/workflows/scheduled-terraform-drift.yml
  expected_output: 200
```

The probe is a runner-side job (not a blind sandbox or a host), so an in-surface probe is the job itself.
The first scheduled run after merge is the proof run (read it with `gh run list`/`gh run view`, which are
read-only); a dispatch is not required and none is authorized by this plan.

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
  (Guard 1 rows 1, 3, 7, 8, 9), including that an unreadable state never yields `protected-as-expected`.
- [ ] AC5. No issue body or log line contains a delete, detach, protection-change or non-GET method
  spelling, and R1-R5 in `token-drift-workflow-causes.test.sh` stays green with its floors unchanged or
  deliberately raised (Guard 1 rows 10 and 13).
- [ ] AC6. The new suite is registered in `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` and
  `scripts/lib/test-affected-paths.sh`, and the repo's registry/affected-paths checks pass.
- [ ] AC7. The targeted suites in Phase 4 pass locally; `python3 scripts/lint-guard-contract.py` passes on
  this plan; the tier census and argv-bearer sweep stay green.
- [ ] AC8. Runbook Group 3 row, ADR-282 addendum plus residual edit, and the runbook sentence are in the PR;
  the ADR status remains `accepted`; the section-5c one-liner block is byte-identical to before.
- [ ] AC9. PR body contains `Ref #9927` and no closing keyword; `gh pr view 10424 --json closingIssuesReferences
  --jq '.closingIssuesReferences'` prints `[]` after the last body edit.
- [ ] AC10. No file outside `.github/workflows/scheduled-terraform-drift.yml`, the paths in Files to Edit/Create
  and the plan/spec artifacts is changed; the parked draft PRs are untouched.

### Post-merge (read-only)

- [ ] AC11. The first Inngest-dispatched drift run after merge: the new job concludes success with verdict
  `protected-as-expected` (read with `gh run view`; no dispatch needed). If it reports `no-token` or
  `could-not-read`, the could-not-perform issue is the finding and #9927 gets a comment; nothing is
  retried by an agent without the owner's per-command go-ahead.
- [ ] AC12. #9927 stays open (this PR carries `Ref` only); a comment on #9927 records item 9 as built and
  the web-1 `workspaces_luks` follow-up.

## Test Scenarios

1. Declared true, live true: green, no issue, `verdict=protected-as-expected`.
2. Declared true, live false: red run, finding issue created (first run) or commented (later runs).
3. Declared false (sanctioned lift), live false: green and quiet; declared false, live true: notice only.
4. Zero volumes with the name; two volumes with the name (first compliant): `volume-not-found`, finding issue.
5. Token absent; token rejected; HTTP 500; HTTP 200 with a non-JSON body; `next_page` non-null; `protection`
   missing: each `could-not-read`/`no-token`, red run, create-only issue, no claim about the volume.
6. `.tf` resource renamed or `delete_protection` written as a variable: `could-not-read`.
7. Existing issue found by title: comment, not create; `gh issue list` failure: no duplicate, job red.
8. Sentinel secrecy: the fixture token never appears in any captured stream or issue body.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6; this plan's is filled with `aggregate pattern`.
- The R1-R5 scan is a tripwire on spelling: the new filer bodies and comments must describe the absence of a
  recipe without spelling one (no method flag, no verb-before-URL, no hcloud write verb, no protection-change
  word next to an API path). Write the prose, then run R1-R5, then rewrite.
- `bc_curl` returns rc 2 for a refused credential and curl's own exit 2 collides with it; branch on the
  `SOLEUR_CREDENTIAL_REFUSED` marker, never on rc 2, and never redirect `bc_curl`'s stderr.
- The job reads `secrets.DOPPLER_TOKEN`, which is a repo secret scoped to one config; if its scope is not
  `prd_terraform` the result is `no-token`, which is the designed signal and not a code defect.
- Do not edit the inngest-rehearsal-orphan-sweep job or the section-5c one-liner block; the first would
  conflict with the parked #10405 and the second is pinned byte-identical by Guard 1 of #9879.
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

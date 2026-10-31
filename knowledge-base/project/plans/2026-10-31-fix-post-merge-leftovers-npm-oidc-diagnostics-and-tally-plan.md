---
title: "fix: post-merge leftovers - npm OIDC publish diagnostics, infra-validation recheck, pipeline-tally reconciliation, read-only prod check"
date: 2026-10-31
slug: post-merge-leftovers-npm-oidc-diagnostics-and-tally
branch: feat-one-shot-post-merge-leftovers-npm-tally
issue: 11585
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
closes: none
---

# fix: post-merge leftovers (npm OIDC diagnostics, infra-validation recheck, tally reconciliation, read-only prod check)

## Overview

One PR (draft PR #11688) closes four leftovers from the messages owner-draft UPDATE policy merge (PR #11622, squash `0ca85fb1f7`, 2026-10-30):

1. **npm Publish is red on every main merge.** Root cause established from run logs: the npm-side trusted-publisher entry for `@soleur/opencode` does not exist, so the OIDC exchange silently fails and `npm publish` dies `ENEEDAUTH`. That entry is an owner-only credential gate (already tracked in #11633). The in-repo fix is to make the leg diagnose itself: a failure-only step that replays the exact OIDC exchange, prints the registry's reason and the exact values to configure, plus a runbook. The leg stays red until the owner step lands (no soft-skip).
2. **Infra-validation `deploy-script-tests` (4/4):** the premise is stale. The pin-disagreement red was a transient window (run 41125333864 on `f60979559a`) closed by the bot bump commit `85079f73e0`; main has been green on the last two runs. Verify-and-record only.
3. **Tally reconciliation:** the `83/15/1/12` figure is the shared `main` ledger, not this PR's ledger. The branch's own ledger is `19/2/2/4`, and the merged PR body (`19/1/2/4`) is correct on three of four dimensions. The generation bug is that the script treats `main` as an ordinary per-branch ledger that accumulates forever; fix it so default-branch ledgers are init-scoped and disclosed.
4. **Read-only prod check:** listed as a verification task with exact command shapes; the orchestrator executes it during work and records results in the PR body.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| npm Publish "failed on the merge of the messages UPDATE policy work (0ca85fb1f7)" and the three later commits, all with the same defect | Two distinct failures. Run 41141302808 (0ca85fb1f7) is still the OLD workflow: `E404` from the expired `NPM_TOKEN` (first E404 2026-10-29T22:26Z). Runs on 1ae11b1b8a, f532fb99d8, 6a6cdc0c07, d1fa52f922 (41142562752, 41144957796, 41149881110, 41181530366) run the NEW OIDC workflow and fail `ENEEDAUTH` | Treat the OIDC miss as the live defect; note the E404 era is already fixed by #11598 |
| "npm CLI too old / missing id-token / NODE_AUTH_TOKEN interference" are candidate causes | All three excluded from logs: step 6 `npm install -g npm@^11` succeeds, `id-token: write` is on the job, `NODE_AUTH_TOKEN`/`registry-url` are removed. npm 11.20 `lib/utils/oidc.js` swallows every OIDC failure at `log.verbose` and returns undefined, so the remaining cause (no matching trust entry) is invisible at default loglevel | Add a failure-only replay of the exchange that surfaces `body.message` |
| "Infra-validation deploy-script-tests (4/4) are red on main" | Red run 41125333864 (head `f60979559a`): `cloud-init pin (v1.1.67) matches latest vinngest-v* tag merged into HEAD (v1.1.68)`. The bot bump `85079f73e0` closed it; Infra Validation is success on 85079f73e0, 0ca85fb1f7, 6a6cdc0c07, d1fa52f922. Only other red: f532fb99d8 shard 2/4 `cron-egress-nftables.test.sh` rc=124 (361s), one-off | Verify-and-record; no code change (CTO ruling R3) |
| Session tally `83/15/1/12` vs PR body `19/1/2/4` - which is correct? | `83/15/1/12` is byte-for-byte counter file `main-88d050` (the ledger keyed to branch `main`, last write 2026-10-30T18:43Z, i.e. BEFORE the 22:54Z merge). The branch ledger `feat-one-shot-11569-11572-messages-update-policy-708df7` reads `19/2/2/4` (last write 22:06Z); the body was rendered before one more `ci_cycles` incr. gh history shows 10 distinct pushed head SHAs, which neither figure claims (ADR-268 counts instrumented pushes only) | Correct the record in this PR's body (CTO ruling R4: do not rewrite merged PR #11622) and fix the script |
| "The registry's reason is just a 401/404 body" (assumed shape for the diagnose step) | Measured live 2026-10-31 with a bogus bearer (no credential): `POST /-/npm/v1/oidc/token/exchange/package/@soleur%2fopencode` -> HTTP 401, body `{"message":"OIDC token exchange error - unauthorized"}`. The `no trusted publisher` case could not be provoked without a real GitHub id-token, so its status is not asserted anywhere; the script classifies any 4xx and prints the exact status plus `.message` | Stub fixtures reuse the measured body shape; AC9 captures the real 'no trusted publisher' response from the first post-merge run |
| Open PR #10926 fixes a SIGPIPE in `git tag \| head` | Main already resolves the tag with `\| sed -n '1p'` (sed drains stdin, no SIGPIPE under pipefail). #10926 also rewrites unrelated files and is CONFLICTING | Not folded in; PR left untouched (CTO ruling R2; the CTO's suggestion to comment on #10926 is overridden by the brief's "never edit or comment") |

## Research Insights

**Premise Validation.** Checked: run logs for 41141302808, 41142562752, 41144957796, 41149881110, 41181530366 (failure codes), infra-validation run 41125333864/41144839849/41181409788, PR #11622 body and commits, counter files under `.git/soleur-session-state/counters/`, PR #10926 diff, issue #11585 (open, 4 comments) and #11633 (open, action-required), ADR-310. Held: ENEEDAUTH on the OIDC leg, trust entry is the owner-only gate. Stale: infra-validation red (self-healed), the tally figure's provenance.

**Property List.**

- P1: a red npm Publish run names its own cause (which of: id-token missing, no matching trusted publisher, exchange fine) without opening verbose npm logs.
- P2: the exact npm-side configuration values are printed in the failing run and in a runbook, so the owner step is one command with no research.
- P3: the leg never reports green when nothing was published (no soft-skip).
- P4: main's Infra Validation is confirmed green at a named SHA.
- P5: a tally read on `main`/`master` cannot be mistaken for one run's cost.
- P6: the record of #11622's tally is corrected where it is read next (this PR's body).
- P7: production state for drafts/archived and the `discard-send-race` signal is measured read-only and recorded.

**Cut List.**

- Pre-publish exchange check (CTO option C) -> doubles the OIDC surface; the failure-only replay buys P1/P2 without a second failure site.
- `--loglevel verbose` on `npm publish` (option B alone) -> npm logs the exchange `body.message` at verbose, but buries it in CLI noise next to an 853-file tarball listing and cannot name the expected values or compare claims; the replay prints one classified verdict. Kept as a fallback only if the script proves infeasible.
- Soft-skip when no trust entry exists -> violates P3 (false green on a release-integrity leg).
- Editing merged PR #11622's body -> retroactive rewrite of a merged record (ruling R4).
- Folding #10926 -> already solved on main (ruling R2).
- New suite file for the classifier test -> `npm-publish-oidc.test.sh` is already registered in `scripts/suite-shard-legs.tsv:257` and `scripts/suite-durations.tsv:254`; extend it.
- `model.c4` ADR-309 -> ADR-310 prose fix, JWT claim decode and claim-vs-expected diff, `$GITHUB_STEP_SUMMARY` table, exec-bit and one-workflow assertions, parsing the exchange `.token` (plan review: no ask or property; the 2xx body is discarded unread, which removes the minted-token risk instead of guarding it).
- Refusing ledgers on default branches (option C) -> returns UNKNOWN on every post-merge shell.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/integration-issues/2026-10-30-npm-e404-is-authz-masking-and-devin-commits-break-cla-check.md`: registries mask authz as 404; the ENEEDAUTH variant is the same class with the masking moved into npm's own swallow-at-verbose behaviour.
- ADR-310 (adopting): OIDC trusted publishing decision; its dissent (fall back to rotating `NPM_TOKEN`) stays available only if the trust entry proves impossible.
- ADR-268: tally contract; `Pipeline-Tally:` PR-body line is the cross-PR aggregation surface.
- Prior art for the operator-reserved step: decision-challenges row T1a in `knowledge-base/project/specs/archive/20261030-144939-feat-one-shot-11585-npm-publish-e404/decision-challenges.md`.

**CLI verification (npm).** `npm trust --help` (local npm 11.20.0) lists `npm trust github [package] --file [--repo] [--env] [--allow-publish] [-y]`, `list`, `revoke`; `npm help trust` states 2FA is required at account level and granular tokens with the bypass-2FA option are not supported. OIDC exchange endpoint and audience verified from `lib/utils/oidc.js` (npm 11.20): `POST /-/npm/v1/oidc/token/exchange/package/<escapedName>`, audience `npm:<registry host>`, id-token fetched from `ACTIONS_ID_TOKEN_REQUEST_URL` with bearer `ACTIONS_ID_TOKEN_REQUEST_TOKEN`.

## Open Code-Review Overlap

Two open code-review issues mention paths this plan touches only incidentally: #8593 (probe-gate window; mentions the `.github/scripts/` directory generically) and #8800 (census sandbox inodes; mentions `scripts/lib/test-affected-paths.sh`). Disposition: **Acknowledge** both - different concerns; this plan appends one array entry to the affected-paths file and adds one script under `.github/scripts/`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "npm Publish workflow is failing on main." [brief item 1] | Phase 1 (root cause + diagnose step) | mapped |
| 2 | "Pull the logs yourself (gh run list/view), find the root cause, and fix whatever is fixable in-repo (.github/workflows/npm-publish.yml)." [brief item 1] | Phase 1 tasks 1.1-1.4; Research Reconciliation rows 1-2 | mapped |
| 3 | "say so precisely and make the workflow fail with a clearer, self-diagnosing message plus a runbook note" [brief item 1] | Phase 1: `.github/scripts/npm-oidc-diagnose.sh`, workflow step, runbook | mapped |
| 4 | "do not label a step manual unless every automated option was exhausted" [brief item 1] | Phase 1 task 1.7 (automation ladder) | mapped |
| 5 | "fold in its SIGPIPE fix only if it is still relevant and clearly in scope; never edit or comment on it" [brief item 1] | Research Reconciliation row 5 | descoped - justification: main already uses `sed -n '1p'`, so the fix is not relevant |
| 6 | "repair it so main is green" [brief item 2] | Phase 2 (verify-and-record) | mapped - premise stale, already green at d1fa52f922 |
| 7 | "Determine which is correct from the real data (gh run history, review/fix commits) and correct the record where it lives" [brief item 3] | Phase 3 tasks 3.1-3.2 | mapped |
| 8 | "if tally generation is buggy, fix that" [brief item 3] | Phase 3 tasks 3.3-3.6 | mapped |
| 9 | "report results in the PR body; do NOT write to prod" [brief item 4] | Phase 4 | mapped |
| 10 | "the plan just needs to list it as a verification task with the exact command shape and where results are recorded" [brief item 4] | Phase 4 command shapes | mapped |
| 11 | "byte-frozen, do not touch it" [brief constraints] | AC7 | mapped |
| 12 | "in ONE PR" [brief header] | Split Assessment | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/npm-publish.yml` edit | "fix whatever is fixable in-repo (.github/workflows/npm-publish.yml)" | asked |
| `.github/scripts/npm-oidc-diagnose.sh` | "make the workflow fail with a clearer, self-diagnosing message" | asked |
| `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md` | "plus a runbook note" | asked |
| `plugins/soleur/test/npm-publish-oidc.test.sh` extension | -- | inferred - justification: the existing guard pins the workflow surface; an unguarded new step/script rots silently (Guard Contract) |
| `scripts/lib/test-affected-paths.sh` entry | -- | inferred - justification: the ratchet `lint-orphan-test-suites` requires the new script path in the suite's affected edge or an edit to it selects no test |
| ADR-310 amendment | -- | inferred - justification: ADR-310 states the failure signature as E404; the ENEEDAUTH signature and the diagnose contract must be recorded or the ADR misleads |
| Phase 2 verification | "repair it so main is green" | asked |
| `plugins/soleur/scripts/pipeline-tally.sh` default-branch handling | "if tally generation is buggy, fix that" | asked |
| `plugins/soleur/scripts/pipeline-tally.test.sh` cases | -- | inferred - justification: cq-write-failing-tests-before; the behaviour change needs a RED-first test |
| ADR-268 amendment | -- | inferred - justification: ADR-268 documents per-branch ledgers without a default-branch exception; the extension must be recorded |
| Tally reconciliation in PR body | "correct the record where it lives (PR body or the relevant knowledge-base artifact)" | asked |
| Phase 4 read-only prod check | "list it as a verification task with the exact command shape and where results are recorded" | asked |

### Split Assessment

- Subsystems touched: 4 - `.github`, `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 12 | Estimated changed lines: ~500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the subsystem-root count trips the threshold only because docs/ADR/runbook live under `knowledge-base` and the C4 ordinal fix rides the npm change; the operator explicitly asked for "ONE PR". The natural seam if review pushes back: npm leg (Phase 1) vs tally (Phase 3), which share no files.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Technical forks ruled by the CTO agent on 2026-10-31 (R1-R4, recorded in `knowledge-base/project/specs/feat-one-shot-post-merge-leftovers-npm-tally/decision-challenges.md`): failure-only replay diagnostic, no soft-skip, classifier test in the existing guard suite, SIGPIPE not folded, infra-validation verify-only, default-branch ledgers init-scoped with a disclosure line, reconciliation recorded in this PR's body only. No product, marketing, legal, finance, sales or support surface is touched; no UI file in Files lists, so the Product/UX gate does not fire.

## User-Brand Impact

- **If this lands broken, the user experiences:** a stale `@soleur/opencode` on npm (the documented `npx @soleur/opencode install` path keeps serving 3.363.0 while GitHub tags advance); the new diagnostic step cannot worsen that because it runs only after the publish step already failed and always exits 0.
- **If this leaks, the user's workflow is exposed via:** the diagnostic handles a short-lived OIDC id-token and, on success, a minted publish token. A leak would let a third party publish `@soleur/opencode` under the repo identity for minutes; mitigated by `::add-mask::` before first use, printing claims only (never tokens), and a test that fails if either token string appears in output.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** aggregate, not single-user: a stale package mildly harms all new installers; no per-user data, money, or private resource is touched and the diff touches no preflight sensitive path.

## Architecture Decision (ADR/C4)

This plan extends two existing decisions rather than making a new one.

### ADR

- Amend **ADR-268** (`pipeline-tally-per-branch-counters`) with one paragraph: ledgers keyed to `main`/`master` are init-scoped (`init` resets, outcome `default-branch-reset`) and `show` discloses it; side effect named - a concurrent session's `init` on `main` zeroes another session's counts, where before it only accumulated; rejected alternatives in one line each (record-only; refuse the ledger). Task 3.7.
- Amend **ADR-310** (status stays `adopting`) with 3-4 lines: the `ENEEDAUTH` signature (npm swallows OIDC exchange failures at verbose level) and a link to the runbook. Task 1.8.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Checked against the feature: external human actor - the npm package owner acts through the registry web/CLI and is the repo owner already represented; external systems - `npmRegistry` (element in `model.c4`, rendered in `views.c4` at the two ADR-310 include lines) and `github` (hosts the OIDC issuer; edge `github -> npmRegistry` exists); data stores - none added; actor-surface relationships - none changed. The tally script lives inside the already-modeled `plugin` container. No C4 change. `bash plugins/soleur/test/c4-count-parity.test.sh` was run at plan time: ALL TESTS PASSED. Noted and deliberately NOT fixed here (plan review: no ask, no property): the `github -> npmRegistry` edge prose in `model.c4` cites `ADR-309` (durable approval requests) where it means ADR-310; tracked as a deferred drive-by in task 5.4.

### Sequencing

No sequencing dependency; ADR-310 stays `adopting` until the first green OIDC publish (owner step #11633).

## Observability

```yaml
liveness_signal:
  what: "npm Publish run conclusion on main plus the NPM_OIDC_VERDICT line printed by the diagnose step on failure; dist-tags.latest on the registry matching the newest v* tag"
  cadence: "per main merge (workflow_run) and per release"
  alert_target: "GitHub Actions red run on the npm Publish workflow; tracking issue #11633 (action-required) until the trust entry exists"
  configured_in: ".github/workflows/npm-publish.yml (diagnose step) and .github/scripts/npm-oidc-diagnose.sh"

error_reporting:
  destination: "GitHub Actions run log and step summary ($GITHUB_STEP_SUMMARY); ::error annotation on the run page; no Sentry (CI surface)"
  fail_loud: "publish step exits 1 (job stays red); diagnose step prints NPM_OIDC_VERDICT=<verdict> and an ::error:: annotation naming the exact trusted-publisher values to configure"

failure_modes:
  - mode: "trusted-publisher entry missing or mismatched (current state)"
    detection: "diagnose step: exchange POST returns 401/403/404; verdict trusted-publisher-missing-or-mismatched with claim-vs-expected diff"
    alert_route: "red npm Publish run + ::error annotation; owner step tracked in #11633"
  - mode: "id-token permission removed from the job"
    detection: "diagnose step: ACTIONS_ID_TOKEN_REQUEST_URL unset -> verdict id-token-missing; also pinned by npm-publish-oidc.test.sh member id-token"
    alert_route: "red run + CI test failure on the PR"
  - mode: "exchange succeeds but publish still fails (version conflict, provenance, registry outage)"
    detection: "diagnose step verdict exchange-ok directs the reader to the npm publish error above it"
    alert_route: "red npm Publish run"
  - mode: "diagnose step itself regresses (removed, reordered before publish, loses failure() guard)"
    detection: "npm-publish-oidc.test.sh member diagnose-on-failure, mutation rows"
    alert_route: "CI failure on the PR touching the workflow"

logs:
  where: "GitHub Actions run logs for workflow 'npm Publish'"
  retention: "GitHub default Actions log retention (90 days)"

discoverability_test:
  command: bash plugins/soleur/test/npm-publish-oidc.test.sh
  expected_output: "0 failed"
```

## Guard Contract

### Guard 1 - diagnose-on-failure wiring member (extends the existing npm-publish-oidc guard)

**Property.** Whenever the publish step fails, the next step in the job runs the diagnose script; that step can never be absent, run before publish, run on success, or point at a step id that is not the publish step, and the publish step can never be made to succeed through `continue-on-error`.

**Assembly.** `jobs.publish.steps` in `.github/workflows/npm-publish.yml` is the only place the step lives. The member quantifies over the parsed steps list by index: the step whose run body contains `npm publish` (its `id`, its `continue-on-error`), and the later step whose `if:` must contain `failure()` and reference `steps.<that id>.outcome` and whose `run:` must invoke `.github/scripts/npm-oidc-diagnose.sh`. One chokepoint: the parsed YAML.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the diagnose step | RED |
| 2 | Move the diagnose step before the publish step | RED |
| 3 | Drop `failure()` from the step's `if:` (runs on success) | RED |
| 4 | Dispatch: workflow whose `jobs.publish` is absent (vacuous) | RED |
| 5 | Publish step gains `continue-on-error: true` (job goes green while diagnose still fires) | RED |
| 6 | `if:` references a wrong or missing step id (`steps.nope.outcome`, step never runs) | RED |
| 7 | Replace the script invocation with `echo` (step present, does nothing) | RED |
| 8 | Add a second compliant diagnose-style step after the first | GREEN (must-pass superset, not the canonical) |

**Harness rows.** (a) Stub the new member to return 0 in a scratch copy of the suite: mutation rows 1-3 and 5-7 must then report `mutation SURVIVED` (the battery's own accounting turns that into a FAIL), proving the rows can fail. (b) Row 8 is the must-PASS non-canonical input.

**Anchor.** The member compares live YAML to constants in the test file; both move in one diff, so this guard proves consistency, not integrity. Integrity of the npm-side binding is out of reach of any in-repo guard and is covered by the first post-merge run (AC9).

### Guard 2 - classifier and log-safety of the diagnose script (functional cases in the same suite)

**Property.** For every classified outcome the script exits 0, prints exactly one `NPM_OIDC_VERDICT=` line, never prints the id-token or any exchange response body, emits one `::add-mask::` line for the id-token before any other use, and never lets a printed value start a line with `::`.

**Assembly.** Every code path in `.github/scripts/npm-oidc-diagnose.sh` that expands the id-token, the registry body, or prints a registry message: the token fetch, the exchange request, each verdict branch. All printing goes through one `say()` helper that prefixes every value with a `key=` label and strips CR/LF; the test greps combined stdout and stderr, excluding `::add-mask::` lines, for the stub strings, and separately requires exactly one add-mask line that precedes every other mention.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Script echoes the id-token or the exchange body | RED (leak assertion) |
| 2 | Remove the `::add-mask::` line | RED (mask-before-use assertion) |
| 3 | A stubbed 401 (the measured real body shape) or 404 is classified `exchange-ok` | RED |
| 4 | A stubbed 429 or 503 is classified `trusted-publisher-missing-or-mismatched` | RED (must be `registry-error`) |
| 5 | Script exits 1 on a verdict | RED (exit-0 assertion) |
| 6 | Dispatch: stub `curl` never invoked | RED (stub-call-count floor) |
| 7 | Registry message containing `\n::notice::PASS` or a leading `::stop-commands::` | RED if any output line starts with `::` other than the script's own annotation and add-mask lines |
| 8 | Token fetch loses the `audience` parameter or drops the URL's existing `api-version` query (bad `?`/`&` join) | RED (recorded request URL assertion) |
| 9 | Package-name and registry env overrides set | GREEN, the recorded exchange URL reflects them (must-pass non-canonical input) |

**Harness rows.** (a) A scratch copy of the script that leaks must turn the leak assertion RED. (b) The stub-call-count floor proves the stub is exercised. (c) Row 9 is the must-PASS input.

**Anchor.** Stub strings are random per run (generated with `printf` from `/dev/urandom` bytes), so a fixed constant in the script cannot satisfy the leak assertion by accident; the script is never told the stub values.

## Implementation Phases

### Phase 1 - npm Publish: self-diagnosing failure (+ runbook, ADR note)

Failing tests first (cq-write-failing-tests-before): extend `plugins/soleur/test/npm-publish-oidc.test.sh` with the `diagnose-on-failure` member, mutation rows and the stubbed-`curl` classifier cases; run it RED; then implement.

- 1.1 Add `id: publish` to the "Resolve version and publish to npm" step; keep `npm publish --access public --ignore-scripts` byte-identical (the flag-contract member pins it).
- 1.2 Add step "Diagnose npm OIDC trusted-publisher binding" after it: `if: failure() && steps.publish.outcome == 'failure'`, `run: bash .github/scripts/npm-oidc-diagnose.sh`. No `env:` credential keys (the `no-cred-wiring` member scans them); the script reads the runner-provided `ACTIONS_ID_TOKEN_REQUEST_URL`/`ACTIONS_ID_TOKEN_REQUEST_TOKEN` (neither matches the member's key patterns).
- 1.3 Create `.github/scripts/npm-oidc-diagnose.sh`, kept small. `set -uo pipefail` with no `-e` and `|| true` on every `curl` (the script must reach `exit 0` on rc 28/000); refuse xtrace (repo convention, #7797). Steps: (i) fetch the id-token with `curl -G --data-urlencode audience=npm:registry.npmjs.org "$ACTIONS_ID_TOKEN_REQUEST_URL"` (the URL already carries a query string, so a hand-written `?audience=` would be malformed) and `::add-mask::` it at once; (ii) `POST $REGISTRY/-/npm/v1/oidc/token/exchange/package/@soleur%2fopencode` with the id-token as bearer, response body written to a temp file; the body of a 2xx is deleted unread (no minted publish token is ever parsed or printed); (iii) verdicts: id-token env unset -> `id-token-missing`; token fetch failed -> `id-token-fetch-failed`; exchange 2xx -> `exchange-ok` (the failure is not an OIDC miss; read the npm error above); exchange 401/403/404 -> `trusted-publisher-missing-or-mismatched` with the printed `status=`, the registry `message=` (only if the body is JSON with a string `.message`, else just the byte count), the expected values `repository=jikig-ai/soleur workflow=npm-publish.yml environment=(none)`, the one-line `npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish` remediation and the runbook path; any other status (429, 5xx, 000) -> `registry-error` with `status=`. Every printed value goes through `say()`: a `key=` prefix and CR/LF stripped, so no registry-controlled byte can start a line with `::`. One `::error title=npm trusted publisher::` annotation. Every `curl` carries `--connect-timeout 10 --max-time 20` and no retry flag. Always `exit 0`. The decoded JWT claims are deliberately not printed (plan review: the registry cannot distinguish missing from mismatched, and the expected values suffice; add the claim dump only if a mismatched-entry incident ever needs it).
- 1.4 Reword the publish failure hint in the workflow to name both signatures (`E404` and `ENEEDAUTH`) and the runbook path, keep `exit 1`. The hint is a `run:` body and the `no-cred-wiring` member scans it: it must not contain `NPM_TOKEN`, `_authToken`, `AUTH_TOKEN=` or `npm config set` (the runbook, which is not scanned, may).
- 1.5 Extend `scripts/lib/test-affected-paths.sh` `AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS` with `.github/scripts/npm-oidc-diagnose.sh`. If the suite's measured runtime exceeds its `scripts/suite-durations.tsv` row (`floor`, 1200), update only that row.
- 1.6 Create the runbook `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`, short: symptom table (E404 = dead credential era, ENEEDAUTH = OIDC exchange not accepted), how to read `NPM_OIDC_VERDICT`, the single owner step with the exact command and its verification (`npm trust list @soleur/opencode`, `gh workflow run npm-publish.yml`, `npm view @soleur/opencode dist-tags.latest`), a pointer to #11633 and ADR-310 for the rest, and no SSH.
- 1.7 **Automation ladder for the trust entry (work-phase, bounded, read-only):** (a) one `doppler run -p soleur -c prd -- bash -c 'NODE_AUTH_TOKEN="$NPM_TOKEN" npm trust list @soleur/opencode'` - expected to fail (expired token; `npm trust` rejects bypass-2FA tokens); record the exit text, never the token. (b) Playwright MCP on `https://www.npmjs.com/package/@soleur/opencode/access`: add the entry if a logged-in maintainer session exists, otherwise record the `playwright-attempt:` line (`navigated <URL>; reached <named human gate>`; the gate is password plus 2FA/passkey, neither stored - Doppler holds only `NPM_TOKEN` and `NPM_RECOVERY_CODES`). (c) `NPM_RECOVERY_CODES` is not consumed (decision row T-OP1). Residual: one interactive maintainer login, tracked in action-required issue #11633. Record in `evidence.md` under `## npm Publish root cause`.
- 1.8 Amend ADR-310 (`## Amendment 2026-10-31`, 3-4 lines): the `ENEEDAUTH` signature, why it appears, link to the runbook. Status unchanged.
- 1.9 Gates by their own invocations: `actionlint .github/workflows/npm-publish.yml`; `bash -n` and `shellcheck` on the new script; `bash plugins/soleur/test/npm-publish-oidc.test.sh`; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-guard-contract.py`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`. Stage the new files before any check that reads `git ls-files`.

### Phase 2 - Infra Validation: verify and record (no code change)

- 2.1 `gh run list --workflow=infra-validation.yml --branch main --limit 5 --json conclusion,headSha,databaseId,url` - record the green SHA/run URL in `evidence.md` under `## Infra Validation status`.
- 2.2 If main is red at work time for the pin reason again (a new `vinngest-v*` tag precedes its bot bump PR), report it as the known transient window with the open bot PR number; do not hand-edit the bot-owned pins and add no tolerance to the pin check (CTO R3). Note the f532fb99d8 `cron-egress-nftables.test.sh` rc=124 as a one-off, cause unverified; file nothing unless it recurs.

### Phase 3 - Tally: reconcile the record, fix the generation bug

Failing tests first: add cases to `plugins/soleur/scripts/pipeline-tally.test.sh` (Tests 30-34), run RED, then implement.

- 3.1 Evidence line for `evidence.md`: `83/15/1/12` is the shared ledger of branch `main` (`main-88d050`, last written 2026-10-30T18:43Z, before the 22:54Z merge, cumulative across sessions); this PR's own ledger is `19/2/2/4` (`feat-one-shot-11569-11572-messages-update-policy-708df7`, last written 22:06Z); the merged body `19/1/2/4` matches it except `ci_cycles` (rendered before one more increment). Supporting cross-check: the sandbox-followups ledger also reads `ci_cycles=15`, and gh shows 10 pushed head SHAs on the PR (ADR-268 counts instrumented pushes only).
- 3.2 Record the corrected line `Pipeline-Tally: seats=19; ci_cycles=2; fix_rounds=2; agent_rounds=4` for PR #11622 under `## Tally reconciliation` in `knowledge-base/project/specs/feat-one-shot-post-merge-leftovers-npm-tally/evidence.md` (the durable artifact `ship` folds into the PR #11688 body - `ship` is the sole PR-body author and full-replaces the body, so a block written straight into the body by `work` is clobbered). Do not edit PR #11622 (ruling R4). Wording rule for every evidence block: avoid the `ship-operator-step-gate.sh` deny tokens (`Operator`, `Post-merge`, `Follow-up`) and operator-action bullets; say "owner step" and "production state check".
- 3.3 `pipeline-tally.sh`: `_tally_paths` also sets `T_BRANCH` (resolved or `--branch` value); add `_tally_is_default_branch` (exact match `main` or `master`; `feat-main`, `main-x` and a detached `HEAD` do not match; add a test that `init` on detached `HEAD` does not reset).
- 3.4 `_tally_init_locked`: new outcome `default-branch-reset` after `repaired` and before `capped-reset` (explicit `--reset` still reports `reset`; absent file still `fresh`); extend the counts-clearing `case` arm; fail-open, exit 0; caps merge as for other resets. Kept per CTO ruling R4 although the simplicity seat would reuse `reset` and drop the `show` note line (it dissents; recorded here, ruling stands).
- 3.5 `show`: when the ledger's branch is a default branch, append one line `note:default-branch-ledger (shared across sessions; not attributable to one run)` after the existing lines; the `tally:` line and the `cap:`/`warned:`/`capped:` tokens are unchanged so `hooks/stop-hook.sh` and ship's render parse as before (the note contains none of those tokens).
- 3.6 Update the script header (COUNTER FILE / init outcomes docs).
- 3.7 Amend ADR-268 with the one-paragraph default-branch clause (see Architecture Decision).

### Phase 4 - Read-only production check (verification task, no code)

Executed by the orchestrator during work; **no writes to prod**. Results are recorded in `knowledge-base/project/specs/feat-one-shot-post-merge-leftovers-npm-tally/evidence.md` under `## Production state check (read-only)` (folded into the PR #11688 body by `ship`), with UTC timestamp, the baseline (2026-10-30: 1903 github drafts, 45 kb-drift drafts, 0 archived) and the deltas.

- 4.1 Counts (read-only transaction; the pooler may reject startup `options`, so the guard is in-SQL):

  ```bash
  doppler run -p soleur -c prd -- bash -c 'psql "$DATABASE_URL_POOLER" -At -F "|" -v ON_ERROR_STOP=1 -f -' <<'SQL'
  begin read only;
  select source, status, count(*) from public.messages where status in ('draft','archived') group by 1,2 order by 1,2;
  commit;
  SQL
  ```

  Shape follows `knowledge-base/engineering/operations/runbooks/egress-audit-dsar.md`. Output is aggregate counts only (no row content).
- 4.2 Sentry (read-only Discover query on the RO token; the org host and token ladder follow `scripts/sentry-issue.sh` and `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`):

  ```bash
  doppler run -p soleur -c prd -- bash -c 'curl -fsS -H "Authorization: Bearer $SENTRY_ISSUE_RO_TOKEN" "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/?field=timestamp&field=title&query=op%3Adiscard-send-race&statsPeriod=14d&per_page=25"' | jq '{count: (.data | length)}'
  ```

  On 401/403 follow the runbook's token note; report `count` (expected 0 unless a Discard raced a Send).
- 4.2a Quoting: both commands expand their variable inside `bash -c '...'` so it is read from the Doppler-injected environment, not the caller's shell (a bare `doppler run -- psql "$VAR"` would expand it empty). The plan-time check was limited to `doppler run -p soleur -c prd -- sh -c 'echo ${DATABASE_URL_POOLER:+set}'` style presence checks; the live queries are executed by the orchestrator in the work phase, per the brief.
- 4.3 Interpretation to record: if `archived` is still 0, say so - it means only that no founder has used Discard or Dismiss yet, not a defect. A `discard-send-race` count of 0 is the expected steady state.

## Files to Edit

- `.github/workflows/npm-publish.yml`
- `plugins/soleur/test/npm-publish-oidc.test.sh`
- `scripts/lib/test-affected-paths.sh`
- `scripts/suite-durations.tsv` (conditional, only if the measured runtime exceeds the row)
- `knowledge-base/engineering/architecture/decisions/ADR-310-npm-publish-oidc-trusted-publishing.md`
- `plugins/soleur/scripts/pipeline-tally.sh`
- `plugins/soleur/scripts/pipeline-tally.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-268-pipeline-tally-per-branch-counters.md`

## Files to Create

- `.github/scripts/npm-oidc-diagnose.sh`
- `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`
- `knowledge-base/project/specs/feat-one-shot-post-merge-leftovers-npm-tally/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-post-merge-leftovers-npm-tally/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-post-merge-leftovers-npm-tally/evidence.md` (written during work; sections listed in AC6)

**Frozen / out of scope (do not touch):** `apps/web-platform/supabase/migrations/181_messages_owner_draft_update.sql`; PR #10926 (no edit, no comment); issues #11628, #11629, #11630, #11655, #11656 stay open; bot-owned pins in `apps/web-platform/infra/cloud-init.yml` and `cloud-init-inngest.yml`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash plugins/soleur/test/npm-publish-oidc.test.sh` prints `0 failed`, including the new `diagnose-on-failure` member, the classifier cases and mutation rows (Guards 1 and 2).
- [ ] AC2: `.github/workflows/npm-publish.yml` parses with `id: publish` on the publish step and a following step with `if: failure() && steps.publish.outcome == 'failure'` invoking `bash .github/scripts/npm-oidc-diagnose.sh`; `npm publish --access public --ignore-scripts` is unchanged; no credential wiring added (verified by the existing members).
- [ ] AC3: `.github/scripts/npm-oidc-diagnose.sh` passes `bash -n` and `shellcheck`; in the functional cases it never prints the stub id-token or response body (apart from its one `::add-mask::` line), prints exactly one `NPM_OIDC_VERDICT=` line and always exits 0.
- [ ] AC4: runbook `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md` exists, contains the exact `npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish` line, no `ssh`, and is linked from the workflow hint and the ADR-310 amendment.
- [ ] AC5: `bash plugins/soleur/scripts/pipeline-tally.test.sh` prints `0 failed` with the new default-branch cases; a non-default branch still reports `continued`; the `tally:` line format is byte-identical.
- [ ] AC6: `evidence.md` (and therefore the `ship`-authored PR #11688 body) carries `## Tally reconciliation` (evidence table, corrected line for #11622), `## Infra Validation status` (green SHA + run URL), `## Production state check (read-only)` (Phase 4 results with timestamp) and `## npm Publish root cause` (ENEEDAUTH, trust entry missing, automation-ladder outcomes incl. the `playwright-attempt:` line, pointer to #11633). The body uses `Ref #11585` and `Ref #11633`, never `Closes` (the leg is not green until the owner step), and contains none of the deny tokens `Operator`/`Post-merge`/`Follow-up`.
- [ ] AC7: `git diff --quiet origin/main...HEAD -- apps/web-platform/supabase/migrations/181_messages_owner_draft_update.sql` exits 0 (three-dot: the merge-base diff, not the moving tip); PR #10926 and issues #11628/#11629/#11630/#11655/#11656 untouched.

### Post-merge (automated verification)

- [ ] AC9: the first npm Publish run on main after merge shows `NPM_OIDC_VERDICT=` in its log (`gh run view <id> --log | grep NPM_OIDC_VERDICT`). Expected verdict while #11633 is open: `trusted-publisher-missing-or-mismatched`. After the owner adds the entry, the next run is green and `npm view @soleur/opencode dist-tags.latest` equals the newest `v*` tag (that closes #11585/#11633; this PR does not).

## Test Scenarios

- Given a stubbed exchange answering 401 with the measured body `{"message":"OIDC token exchange error - unauthorized"}` (and separately 404), the script prints `NPM_OIDC_VERDICT=trusted-publisher-missing-or-mismatched`, `status=`, the registry `message=`, the expected repo/workflow values, and exits 0 without printing the id-token.
- Given a stub returning 200 with a body carrying a random secret string, the script prints `exchange-ok` and the secret never appears in any output.
- Given `ACTIONS_ID_TOKEN_REQUEST_URL` unset, the verdict is `id-token-missing`; given a failing token fetch, `id-token-fetch-failed`.
- Given a 429 or a 503 (or curl rc 28/000) from the registry, the verdict is `registry-error`, never the trusted-publisher verdict.
- Given a registry message containing a newline followed by `::notice::PASS`, no output line other than the script's own annotation and add-mask lines starts with `::`.
- The recorded token-fetch request keeps the URL's existing query and adds `audience=npm:registry.npmjs.org`.
- Tally: `init` on `main`, `incr seats 3`, `init` again -> `default-branch-reset`, counts zero; `show` on `main` carries the `note:` line; on `feat-x` a second `init` still reports `continued` and `show` has no note; `--branch master` behaves like `main`; `feat-main` and `main-x` do not match.
- Detached `HEAD`: `init` does not reset a ledger.
- Regression: the stop-hook's `show` parsing still extracts `capped:`/`cap:` tokens when the note line is present.

## Dependencies & Risks

- **Owner-only gate.** The npm trust entry needs an interactive maintainer login with 2FA; granular tokens with bypass-2FA are rejected by `npm trust`. Tracked in #11633; this PR does not and cannot close it. The leg stays red by design until then.
- **Diagnose step may cause the registry to mint a token on success.** The 2xx response body is written to a temp file and deleted unread, so no publish credential is ever parsed, printed or held in a variable; only the id-token (a short-lived OIDC bearer) is masked. Pinned by the leak tests (Guard 2).
- **Deferred drive-by (task 5.4).** The `github -> npmRegistry` edge prose in `model.c4` cites `ADR-309` where it means ADR-310; not fixed here (no ask, no property); tracked by a deferred-scope issue filed in the work phase so it is not invisible.
- **Failure-only step cannot be exercised on a green run.** Functional coverage comes from the stubbed-curl cases; the live proof is AC9.
- **Default-branch reset semantics.** `init` on `main` now zeroes counts. Pipelines do not run on `main` (commit-on-main is hook-blocked), so the loss is only the accidental cross-session accumulation. A skill that runs `init` twice on `main` in one session loses its first count; accepted and documented in ADR-268.
- **Infra pin window recurs** on every new `vinngest-v*` tag until the bot bump PR merges; documented as expected, not changed.

## References

- Runs: 41141302808 (E404, old workflow), 41142562752, 41144957796, 41149881110, 41181530366 (ENEEDAUTH); infra-validation 41125333864 (red), 41144839849 (shard 2/4 timeout), 41181409788 (green).
- Issues: #11585, #11633 (and the drive-by issue from task 5.4); PRs: #11598 (OIDC switch), #11622 (messages policy), #11688 (this PR), #10926 (untouched).
- ADR-310, ADR-268; npm 11.20 `lib/utils/oidc.js`; `npm help trust`.

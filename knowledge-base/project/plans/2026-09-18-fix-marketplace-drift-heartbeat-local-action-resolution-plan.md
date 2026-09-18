---
title: "fix: scheduled-marketplace-drift heartbeat never resolves its local composite — reference it by self-repository ref, guard the class, correct the PIR"
date: 2026-09-18
slug: fix-marketplace-drift-heartbeat-local-action-resolution
branch: feat-one-shot-marketplace-drift-heartbeat-checkout
issue: none
closes: none
type: fix
priority: p1
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-18
**Sections enhanced:** Proposed Solution §3, Technical Considerations, Implementation Phases
(1.2, 2.1, 3.3, 3.5, 4.1, 4.4, 4.5, Post-merge), Observability, Guard Contract, Acceptance
Criteria (AC4, AC5, AC6, AC8, AC11), Research Insights (external docs)
**Research agents used:** architecture-strategist, security-sentinel,
observability-coverage-reviewer, test-design-reviewer, pattern-recognition-specialist,
git-history-analyzer (11/11 attributions confirmed), best-practices-researcher, a
verify-the-negative + post-edit self-audit sweep (12/12 negatives confirmed, 0 stale symbols);
halts 4.5–4.11 all pass (no network trigger, User-Brand Impact valid with scope-out,
Observability 5 fields + allowlisted probe verb, no PAT shape, no UI surface, no store or
connection, Guard Contract lint green).

### Key Improvements

1. Row 9 of the guard's mutation matrix is now arm- and phase-independent (delete a sibling's
   checkout, assert the delta) — the previous shape could not go green before Phase 2 and was a
   no-op on the fallback arm.
2. The lint adopts the family's exit contract (0/1/2), the `::error file=` finding line, the
   `run-body-syntax` walk, a once-built filler tree with a `reset()` that keeps the floor, and a
   second zero-floor surface (`.github/actions/*/action.yml` nested `./`).
3. The verification chain exports one secret (`--only-secrets SENTRY_IAC_AUTH_TOKEN`), never the
   whole `prd` config; AC8 gains a negative anchor so the composite's `-w` format can never
   print a URL variable; the PIR records row values only, never a token-scope map.
4. `recovery_at` carries its layer citation on the value line (`# measured: Sentry cron monitor
   check-in id …`), and every Observability failure mode names its layer.

### New Considerations Discovered

- Sentry's HTTP check-in endpoint answers `202` with no body, so the step-log line reads
  `http_code=202`; a first-ever `status=error` check-in opens a Sentry issue immediately
  (`failure_issue_threshold = 1`), which the branch dispatch can trigger.
- actionlint's `$/` support (rhysd/actionlint#732) is OPEN, not released — a research agent
  claimed otherwise; the live `gh` probe decides.
- Switching to `$/` moves the heartbeat's failure from a swallowed step error to a `Set up job`
  failure that skips the manifest check — loud and correct, and the workflow comment now says so.
- The all-`$/` migration, if ever run, must sweep four `./`-anchored consumer censuses that
  would otherwise go fail-open; they are named in the `SOLEUR-DEBT:` marker.

## Overview

The daily `scheduled-marketplace-drift.yml` watcher ends its `drift-check` job with a Sentry Crons
heartbeat step that has never delivered a check-in. The job is deliberately checkout-free (its
inputs are public URLs fetched over HTTPS), but the heartbeat step is `uses:
./.github/actions/sentry-heartbeat` — a repo-local composite that GitHub resolves from the
runner's checked-out workspace, which does not exist in this job. The runner emits `Can't find
'action.yml' ... Did you forget to run actions/checkout` on every tick, and the step's
`continue-on-error: true` converts that into a green step, so every run since the 2026-08-13
repair has concluded `success` (or failed for unrelated reasons) while the monitor stayed dark.

This plan makes the heartbeat resolve without giving the untrusted-input job a checkout, adds a
structural guard so a `uses: ./` step without a preceding checkout cannot ship green again,
corrects the 2026-08-13 post-incident report whose `recovery_at` never came true, and prescribes
verification from Sentry's side rather than from the run conclusion that lied for 36 days.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for
this one-shot branch; the Domain Review below found no cross-domain implications.)

**No issue is closed by this PR.** The `closes:` field is deliberately `none`: the open issues in
this workflow's neighbourhood (#7520 — narrow `actions: write`; #7524 — guard gaps from the
marketplace-protection review; #8282 — the Sentry infra apply that failed on main) are not work
targets and must not be edited or closed here.

## Problem Statement

Measured 2026-09-18 from the observability layer, not the dashboard:

- **Run logs.** All 36 scheduled runs after the 2026-08-13 repair merged (run `31782063181` on
  2026-08-14T07:59Z through run `35341073667` on 2026-09-18T11:43Z) carry exactly one
  `##[error]Can't find 'action.yml', 'action.yaml' or 'Dockerfile' under
  '/home/runner/work/soleur/soleur/.github/actions/sentry-heartbeat'. Did you forget to run
  actions/checkout before running your local action?` line in the `drift-check` job log. 33 of the
  36 concluded `success`; the 3 `failure` conclusions (2026-09-06, 2026-09-13, 2026-09-16) are
  unrelated job failures and carry the same line. Read with `gh run view <id> --log --job <job>`
  — `gh api repos/.../actions/jobs/<id>/logs` returns nothing greppable from this session.
- **Sentry.** `GET /api/0/organizations/jikigai-eu/monitors/scheduled-marketplace-drift/checkins/`
  returns `[]`; the monitor object exists (`status: active`, `dateCreated:
  2026-08-12T17:40:50Z`, schedule `37 6 * * *`, `checkin_margin: 360`) with an empty
  `environments` list — no environment has ever checked in. The sibling
  `scheduled-terraform-drift` returns an `ok` check-in from 2026-09-18T06:03Z on the same query,
  so the read path is sound.
- **The step.** `.github/workflows/scheduled-marketplace-drift.yml` job `drift-check` has six
  steps and no `actions/checkout`; its final step is `uses: ./.github/actions/sentry-heartbeat`
  with `if: always()` and `continue-on-error: true`.

The 2026-08-13 PIR recorded `recovery_at: "2026-08-13 — ... first live check-in expected at the
next 06:37 UTC tick"`. That was a future expectation with no probe behind it. The repair PR
forwarded the three composite inputs the workflow had omitted, and its verification saw a green
step — which `continue-on-error` guarantees regardless of whether the action resolved. Nothing in
the repo asserts that a `uses: ./` step is preceded by a checkout; the class surfaced again on
2026-09-17 in the devin-docs-drift watcher and was repaired there (merged 2026-09-18 11:34Z) by
adding a checkout, with the learning captured in open PR #8311.

## Research Reconciliation — Premise vs. Codebase

| Claim in the brief | Reality (measured) | Plan response |
|---|---|---|
| All post-repair runs `conclusion=success` | 33/36 success, 3/36 failure (unrelated); all 36 carry the resolution error | PIR amendment states 36/36 resolution errors and 33/36 green conclusions |
| 14 `sentry-heartbeat` call sites; only `drift-check` lacks a checkout | Confirmed by a yaml-parsed census of every `uses:` in 80 workflows: 54 `./` local-action steps across 38 jobs in 32 workflows, 53 preceded by `actions/checkout`, exactly one not (`scheduled-marketplace-drift.yml:drift-check`); 288 `owner/repo[/path]@<40-hex>` steps; 0 `$/`; 0 unclassified; 2 job-level `uses: ./.github/workflows/reusable-release.yml` (reusable workflows, resolved from the repo ref, not the workspace) | Lint quantifies over ALL `./` steps, not only `sentry-heartbeat`; job-level `uses:` is skipped explicitly; the `$/…@ref` form actionlint accepts is the one named reject |
| Prefer remote ref `jikig-ai/soleur/.github/actions/sentry-heartbeat@<sha>` or a sparse checkout | GitHub added a third form on 2026-07-30: the self-repository reference `$/path/to/action`, which "resolves to your workflow's own repository at the exact commit that is running, with no checkout required" and is the documented recommendation for same-repo actions (`./` is now labelled "edge cases only"). Requires runner ≥ 2.336.0 (hosted `ubuntu-24.04` runners are current); not available on GHES (irrelevant); must not carry an `@ref` suffix | Primary mechanism is `$/.github/actions/sentry-heartbeat`; the remote-ref SHA form is the fallback, verified against the docs and the in-repo precedent `actions/cache/restore@0400d5f6...` (owner/repo/subpath@sha); sparse checkout is rejected (see Proposed Solution) |
| `gh workflow run` works pre-merge only if the workflow exists on the default branch | The 2026-04-21 learning's 404 was for a NEW workflow file absent from `main`. This workflow exists on `main`, so `gh workflow run scheduled-marketplace-drift.yml --ref <branch>` dispatches the BRANCH's copy of the file; `$/` then resolves the branch commit's composite | Verification runs PRE-merge from the branch (a real check-in lands before the PR merges) and again POST-merge from `main` |
| A branch dispatch could file spurious drift/delivery issues | `scripts/plugin-delivery-canary.sh` compares the installed plugin against `main` HEAD (`/repos/${REPO}/commits/main`, unconditionally), and `drift-check`'s fetch URLs are hardcoded to `.../main/...`; neither reads `github.sha`/`github.ref` | A branch dispatch yields the same verdicts a scheduled run would; no spurious filing |
| The devin-docs-drift repair "verified live" its heartbeat | Its verification was the step conclusion. The `scheduled-devin-docs-drift` monitor does not exist in Sentry (404 on `/monitors/scheduled-devin-docs-drift/checkins/`; absent from the 57-monitor org list) because the post-merge Sentry infra apply failed — tracked in open #8282. The ingest POST still returned 2xx (step outcome `success`, 128 ms) | Out of scope here; recorded as evidence that an ingest 2xx is necessary, not sufficient — the plan's verification reads the check-in back from the monitors API |
| PIR `recovery_at` should be amended | `recovery_at` is free-text across the PIR corpus; the incident skill's dry-run regex demands `YYYY-MM-DDTHH:MM:SSZ` for new PIRs; `/ship` Phase 5.5 (`ship-pir-action-items-gate.sh --branch`) checks every PIR the diff touches and requires the Action Items section to be either a `#NNNN`-keyed table or the permitted no-item sentence | Amend to an ISO timestamp measured from the Sentry API at /work time; keep the no-item sentence (the fix ships in this PR); add an `AMENDED` banner mirroring the `RECURRED` banner precedent in `betterstack-quota-near-miss-postmortem.md` |
| "Gate-moratorium posture" (PIR's reason for not filing a lint) | ADR-131 is `status: proposed` and decides nothing; the lint here is asked for by the brief and is an extension of the existing `scripts/lint-workflow-*` family registered in `scripts/test-all.sh`, not a new CI gate name | Proceed; no new required-check name is introduced |

## Research Insights

**Premise validation (Phase 0.6).** Cited artifacts verified 2026-09-18: PR #8311 OPEN (adds
`knowledge-base/project/learnings/2026-09-18-local-composite-action-needs-checkout-continue-on-error-masks-it.md`,
not on `main`); the devin-docs-drift repair PR MERGED 2026-09-18T11:34Z (added `actions/checkout`
with `persist-credentials: false` before the heartbeat); #7520 OPEN, #7524 OPEN (not targets);
draft PR #8313 OPEN on this branch; `.github/actions/sentry-heartbeat/action.yml` exists (last
touched by the 2026-05-18 commit that collapsed 7 sister check-ins into the composite); the PIR
exists at the cited path. No open duplicate issue for this fix (`gh issue list --search
marketplace-drift` returns #7520, #7511, #7512, #7490, #3786, #7524 — none is this defect).
Mechanism-vs-ADR grep: no ADR decides how same-repo actions are referenced; ADR-033 (Inngest as
the cron substrate) is already overridden for this workflow by its gate-override header.

**Property list (Phase 0.6b).**

- P1 — The `scheduled-marketplace-drift` Sentry monitor records a check-in on every `drift-check`
  run, with the status the workflow computed.
- P2 — `drift-check` keeps its no-checkout property: the check step reads only HTTPS inputs, the
  workspace stays empty, and the job's `permissions:` block is byte-identical.
- P3 — No job in `.github/workflows/` can reference a `./` local action without an earlier
  `actions/checkout` in the same job while CI stays green.
- P4 — The PIR states the recovery that actually happened, with a measured timestamp.
- P5 — Recovery is evidenced by the Sentry monitors API, not by a run or step conclusion.
- P6 — The lesson (a `continue-on-error` heartbeat step is not evidence; a PIR `recovery_at`
  needs a probe) is captured once, linked to the class learning in PR #8311, not duplicated.

**Cut list (Phase 0.6b).**

- Sparse checkout of `.github/actions/sentry-heartbeat` → P1 → superseded by `$/`, which buys P1
  without touching the workspace at all (cut; kept in the alternatives table only).
- A follow-through soak probe (`scripts/followthroughs/…` + tracker issue) → P5 → not needed:
  verification is immediate (dispatch, then read the check-in back) and the monitor's own
  `checkin_margin: 360` makes a missed future tick a Sentry issue by itself. No time-gated close
  criterion exists, so Phase 2.9.1 does not fire.
- A new learning file restating the "local composite needs checkout" class → P6 → PR #8311's file
  already carries it; this PR's learning covers the distinct lesson (verification proxy + PIR
  recovery claim) and cites that path in prose.

**Relevant files.**

- `.github/workflows/scheduled-marketplace-drift.yml` — `drift-check` job at the `No
  actions/checkout` comment; heartbeat step `Sentry check-in (final)` (`uses:
  ./.github/actions/sentry-heartbeat`, `if: always()`, `continue-on-error: true`); the
  `permissions:` block (`contents: read`, `issues: write`, `actions: write`) is untouched.
- `.github/actions/sentry-heartbeat/action.yml` — five `required: true` inputs; `curl --max-time
  10 -fSs -X POST` with no `-w`, so a 2xx prints nothing to the step log.
- `scripts/lint-workflow-step-env-refs.py`, `scripts/lint-workflow-issue-write-scope.py` (+
  `.test.sh`) — nearest siblings: PyYAML-parsed per-job/per-step scans, fail-closed with no
  allowlist, `scanned == 0` → exit 1, synthesized fixtures via `mkwf`, `pass()/fail()` canary rows.
- `scripts/test-all.sh` — workflow lints are registered as a unit + live pair (ADR-170 shape:
  "the unit suite proves the RULE is right, the live scan proves the TREE is clean"); the
  `scripts` group runs in CI under `bash scripts/test-all.sh scripts`.
- `scripts/lint-orphan-test-suites.sh` — every tracked `*.test.sh` must be registered by a runner.
- `.github/workflows/ci.yml` — actionlint 1.7.7 pinned; rc=1 (findings) is accepted (census
  ratchet tracked in open #7042), so an actionlint finding on the `$/` form cannot block.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — `sentry_cron_monitor.scheduled_marketplace_drift`
  (`37 6 * * *`, `checkin_margin_minutes = 360`, `max_runtime_minutes = 10`). Nothing
  count-shaped changes: no monitor is added, and `model.c4` embeds no monitor count.
- `scripts/followthroughs/ghcr-minter-live-6031.sh`, `scripts/followthroughs/sentry-checkins-3859.sh`
  — precedent for reading a monitor's check-ins: `GET
  https://sentry.io/api/0/organizations/jikigai-eu/monitors/<slug>/checkins/?per_page=N` with a
  Bearer token. In CI that token is the `SENTRY_ACTIONS_RO_TOKEN` Actions secret; from a
  workstation the ADR-031 path is Doppler `soleur/prd` `SENTRY_IAC_AUTH_TOKEN` (measured 200;
  `SENTRY_ISSUE_RO_TOKEN` returns 403).
- `plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh` — shape gate on any PIR in
  the diff (see reconciliation table).
- `knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md`
  — precedent for amending a PIR whose resolution did not hold (`status:` comment + blockquote
  banner at the top).

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — the guard must be driven RED by the real defect, and the suite must carry harness rows.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — write the mutation matrix from the design before the guard.
- `knowledge-base/project/learnings/2026-09-13-the-guard-pinned-the-names-the-plan-listed-and-the-readback-read-every-page-unpinned.md`
  — discovery is a census over the file set, the enumeration is only a floor, and the one shape
  the runtime does not reject loudly (`$/…@ref`, per actionlint) is named rather than assumed.
- `knowledge-base/project/learnings/2026-09-14-every-guard-i-shipped-had-a-narrower-window-than-its-name-and-my-first-mutant-caught-my-own-guard.md`
  — an ORDER property needs a REORDER mutation row.
- `knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` —
  `continue-on-error: true` at the step is the right place for "a Sentry blip must not red the
  job"; it is also why nothing else can be inferred from a green step.
- `knowledge-base/project/learnings/2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`
  — zero events from the path being "fixed" is decisive; the fix must be evidenced by the path's
  own telemetry (here: the check-in row).
- `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`
  — scoped to workflows absent from `main`; does not block the pre-merge dispatch here.
- `knowledge-base/project/learnings/2026-05-18-composite-action-extraction-inline-on-multi-file-rollout.md`
  — why the composite exists and why inlining the curl at one site is drift.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — the soak-probe
  shape; consulted and found not required (see cut list).
- ADR-193 (`ADR-193-anti-vacuity-floor-contract.md`) — the `asserted` counter is incremented at
  the call site, never inside helpers; floors are matched to their own enumeration.
- ADR-170 (`ADR-170-workflow-run-step-must-clear-inherited-errexit.md`) — the unit + live pair
  registration.

**External documentation (verified 2026-09-18).**

- GitHub Docs, Workflow syntax → `jobs.<job_id>.steps[*].uses`
  (`https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax`): "`$/path/to/action`
  … resolves to that repository at the running commit … You do not need to check out the
  repository first, so it is the recommended way to reference an action within its own
  repository. … A `$/` reference must not include an `@{ref}` suffix." The comparison table
  labels `./path/to/action` "Edge cases only" and states "You must check out your repository
  before using the action". `{owner}/{repo}/{path}@{ref}` is "A subdirectory in a public GitHub
  repository at a specific branch, ref, or SHA."
- GitHub Changelog 2026-07-30, "Reference same-repository actions with self-repository syntax"
  (`https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/`):
  "with no checkout required … requires the GitHub Actions runner to be on version 2.336.0 or
  newer … works everywhere the workspace-relative `./` syntax works, including workflow steps,
  composite action steps, nested composition, and reusable workflow calls."
- Sentry Crons HTTP heartbeat (`docs.sentry.io/product/crons/getting-started/http/`): "The API
  endpoint will always respond with a `202` with no body (unless there is an error)" — so the
  composite's `-w` line will read `sentry-heartbeat: http_code=202` on success, and `-fSs` prints
  nothing else. Read-back: `GET /api/0/organizations/{org}/monitors/{monitor_id_or_slug}/checkins/`
  (`docs.sentry.io/api/crons/retrieve-checkins-for-a-monitor/`; token scopes `alerts:read` /
  `project:read` or wider; fields `status`, `dateCreated`, `environment`), exercised above.
- actionlint upstream status, resolved live 2026-09-18 with `gh`: PR rhysd/actionlint#732
  ("Support the `$/` self-repository `uses:` syntax") is OPEN and unmerged; issue #711 OPEN;
  latest release v1.7.12 (2026-03-30) predates the 2026-07-30 announcement. A research agent
  reported #732 as merged; the live probe says otherwise, and the plan follows the probe.

## Proposed Solution

### 1. Reference the composite by self-repository ref (`$/`)

Change the one `uses:` line in `drift-check` from `./.github/actions/sentry-heartbeat` to
`$/.github/actions/sentry-heartbeat`. Nothing else about the step changes: `if: always()`,
`continue-on-error: true`, the five inputs, the `status:` expression.

**Why this over the alternatives (state this in the PR body):**

| Option | No-checkout property | Version coupling | Verdict |
|---|---|---|---|
| `$/.github/actions/sentry-heartbeat` | Preserved outright — the workspace stays empty; the runner fetches the action from the repo at `github.sha` | Same commit as the workflow, exactly like the 13 `./`+checkout siblings | **Chosen** |
| `jikig-ai/soleur/.github/actions/sentry-heartbeat@<40-hex>` | Preserved (action tarball lands in `_actions/`, not the workspace) | Pinned SHA drifts from the composite the siblings run; a composite change in the same PR cannot be referenced until it is on `main`; the pin must be re-bumped by hand | **Fallback** if `$/` fails to resolve on the hosted runner (measured in Phase 3, not assumed) |
| `actions/checkout` with `sparse-checkout: .github/actions/sentry-heartbeat` | Weakened — a checkout step lands in the untrusted-input job; cone mode also materialises every root-level file; `ci.yml` carries an explicit warning that sparse checkouts turn scan-based guards fail-open | Same commit | Rejected |
| Full `actions/checkout` (what the devin-docs-drift repair did) | Lost — the constraint forbids it for this job | Same commit | Rejected |
| Inline the curl in the workflow | Preserved | Diverges from the shared composite that the 2026-05-18 rollout created to stop exactly this drift | Rejected |

The workflow's two comment blocks (the `No actions/checkout` rationale at the top of the job and
the heartbeat step's 2026-08-13 repair note) are rewritten to say what is true NOW: the job has no
checkout; `./` resolves from the workspace and never resolved here; the composite resolves through
the self-repository reference at the running commit; actionlint 1.7.7 flags the form
(rhysd/actionlint#711). Incident history stays in the PIR. The block also carries the repo's
reference-form posture and a `SOLEUR-DEBT:` marker so `/soleur:harvest-debt` surfaces it with a
trigger: `./` + `actions/checkout` remains canonical for jobs that already check out; `$/` is for
checkout-free jobs; revisit all-`$/` when a released actionlint recognises `$/` — and that
migration's mandatory sweep set is the four `./`-anchored consumer censuses that would go
fail-open on a moved site (`scripts/audit-bot-codeql-coverage.sh`,
`scripts/check-cloudflare-token-drift.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`,
`scripts/wire-anthropic-preflight.awk`), named in the marker. One more sentence the rewrite must
carry: the job now depends on the heartbeat action resolving at `Set up job` — a download
failure fails the whole job before the manifest check runs (red run + Sentry miss), which is
every checkout sibling's posture and is loud, unlike the step-time failure `continue-on-error`
swallowed; it also means no `GITHUB_TOKEN` is ever written to disk in this job, which a
"helpful" `actions/checkout` would change — say so, so nobody adds one.

### 2. Make the step log carry the HTTP outcome

Add `-w '\nsentry-heartbeat: http_code=%{http_code}\n'` to the composite's curl (one line in
`.github/actions/sentry-heartbeat/action.yml`), and add a header paragraph documenting `$/` as
the reference form for checkout-free jobs. Today a 2xx is silent (`-fSs` prints only failures),
so the step log cannot evidence delivery. `-w` prints on failure too (`curl: (22)` plus
`http_code=404`), preserving the composite's property 2. This is additive output for all 14
call sites and changes no exit code. It is deliberately the ONLY composite change.

### 3. Structural guard: `scripts/lint-workflow-local-action-checkout.py`

PyYAML-parsed, per job, per step, in order — the `lint-workflow-issue-write-scope.py` shape
(glob `<root>/*.yml|*.yaml` of the directory argument, default `.github/workflows`; never
`git ls-files`, so tree copies under `mktemp -d` scan). Two buckets, not four: a step whose
`uses:` starts with `./` is a **same-repo local step** and is a finding unless an earlier step in
the same job has `uses:` matching `^actions/checkout(@|$)` (anchored — `jikig-ai/checkout@…`,
`actions/checkout-foo@…` and `./…/checkout-helper` are not checkouts); every other `uses:` value
(`$/…`, `owner/repo[/path]@ref`, `docker://…`) needs no checkout and is ignored, because GitHub
resolves those at `Set up job` and fails the job loudly when they are wrong. One explicit reject
outside that rule: a `$/` value carrying an `@` — GitHub rejects it at setup, but actionlint 1.7.7
accepts it (measured), so the lint names it. Conditional-checkout clause as in the Guard Contract.
Job-level `uses:` (reusable workflows) is skipped. One floor over the population the property
quantifies over: `MIN_SAME_REPO_STEPS=30` counting `./` + `$/` steps together (54 today), so a
future `./`→`$/` migration cannot drive the guard to "scanning nothing". Exit contract is the
family's (`issue-write-scope.py`, `errexit-capture.py`): 0 clean, 1 findings, 2 usage/empty/parse
— `scanned == 0`, an unparseable file, a file with no `jobs` mapping, a non-mapping job or step,
or a non-string `uses:` exits 2 naming the file, never a silent skip. The per-job/per-step walk
is the `lint-workflow-run-body-syntax.py` `isinstance` ladder (the only sibling with a full walk;
`issue-write-scope.py` is regex-only and lends the argv/glob/`scanned == 0` skeleton). Finding
lines are `::error file=<wf>::…` on stderr; the OK line keeps its nouns invariant. Second surface
at zero floor: `.github/actions/*/action.yml` `runs.steps[].uses` must not start with `./`. Registered in `scripts/test-all.sh` as the unit + live pair beside its siblings; the unit
suite's tail is the `lint-workflow-issue-write-scope.test.sh` tail verbatim (`verdict_ok`
discriminator, then `FAIL_FLOOR_MIN=<n>` as a LITERAL on the line directly above the `-lt` test,
FATAL `exit 2`, not `fail()`) because `scripts/guard-vacuity-floor.test.sh` scores every suite
under `scripts/` and a computed or `fail()`-enforced floor is "not constructible" there. Full
contract in `## Guard Contract`.

### 4. PIR amendment

See Phase 4. Frontmatter `recovery_at` becomes the ISO timestamp of the first check-in row the
Sentry API returns; `incident_window` extends to that timestamp; `status` gains an `# amended`
comment; an `AMENDED 2026-09-18` blockquote banner at the top records the second dark window
(2026-08-13 → first check-in, 36 days beyond the claimed recovery; 37 days since the monitor was
created on 2026-08-12), the mechanism, why the repair's verification could not see it, and the
guard now in place. `## What would have caught it` gains the second gap. The Action Items section
keeps the permitted no-item sentence.

### 5. Verification — pre-merge AND post-merge, from Sentry

Pre-merge: `gh workflow run scheduled-marketplace-drift.yml --ref
feat-one-shot-marketplace-drift-heartbeat-checkout`, wait for the run, read the `drift-check` job
log for the `sentry-heartbeat: http_code=2xx` line and the absence of `Can't find 'action.yml'`,
then `GET .../monitors/scheduled-marketplace-drift/checkins/?per_page=5` and require ≥ 1 row with
`dateCreated` after the dispatch. Record the run URL, the check-in `id`, `status` and `dateCreated`
in the PR body and in the PIR. Post-merge: repeat from `main` (`gh workflow run` without `--ref`)
and require a second row. The scheduled-tick delay (measured 11:43–13:16 UTC against a 06:37 cron)
is irrelevant because dispatch is used; the next scheduled tick is then guarded by the monitor's
own `checkin_margin` — a miss becomes a Sentry issue, which is the alarm working.

## Technical Considerations

- **`$/` is two months old.** It is documented and GA on github.com, but this repo has no
  precedent. The pre-merge branch dispatch is the measurement; if the step log shows a resolution
  error or the run rejects the syntax, switch to the fallback remote-ref form
  `jikig-ai/soleur/.github/actions/sentry-heartbeat@<40-hex of a main commit>` (the composite's
  last change is on `main`; any current `main` SHA works) and record the switch in the PR body.
  With the fallback, the `-w` composite change is not reachable from the pinned SHA (a pin to a
  commit that does not yet exist is impossible, and nothing re-pins after merge), so on the
  fallback arm the step-log `http_code` evidence is unavailable and AC9/AC16 use their fallback
  predicate (0 resolution errors + `outcome=success` + the AC10 row). A pinned self-repository ref
  also opts this one site out of every future composite change — the coupling the lint's must-PASS
  row (g) permits by design; if the fallback ships, the PR body says so AND a tracking issue is
  filed to migrate the site to `$/` once the runner resolves it (`wg-when-deferring-a-capability-create-a`
  — the same-commit coupling and the step-log evidence are deferred capabilities on that arm).
- **A `$/` or remote-ref failure is LOUD, not masked.** `./` failed at step time, where
  `continue-on-error` swallowed it. `$/` and `owner/repo@ref` are downloaded during `Set up job`,
  so a resolution failure fails the whole `drift-check` job before the manifest check runs, and a
  syntax rejection can surface as a run-level `startup_failure` with no job log at all. That is
  the correct direction of error for a heartbeat (dark-and-loud beats dark-and-green), and Phase
  3.2 has an arm for it.
- **actionlint 1.7.7 flags `$/` — measured 2026-09-18** with the pinned, sha-verified binary
  (`-shellcheck= -pyflakes=` to isolate the `[action]` rule): the pre-fix file yields 0 findings,
  the `$/` edit yields exactly one — `specifying action "$/.github/actions/sentry-heartbeat" in
  invalid format because ref is missing … [action]`, rc=1. CI's hang guard accepts rc=1 as
  findings and `scripts/lint-workflows.sh` exits 0 on findings, so this cannot block; the open
  #7042 census absorbs +1, stated in the PR body. No `.github/actionlint.yaml` exists and none is
  added (an ignore regex would hide the whole `[action]` rule for the file). A later actionlint
  bump that understands `$/` removes the finding. Trap measured alongside: actionlint 1.7.7
  ACCEPTS `$/…@v1` (rc=0), which GitHub rejects — so the new lint names `$/` values carrying an
  `@` as a reject (mutation row 7), because actionlint will not.
- **ADR considered and declined (plan Phase 2.10 test).** A reader of the existing ADRs + C4 is
  not misled about the system after this ships: the reference form is a workflow-syntax choice,
  the lint extends the `lint-workflow-*` family, and the posture lives in the workflow comment +
  `SOLEUR-DEBT:` marker where `/soleur:harvest-debt` reads it. If the all-`$/` migration ever
  runs, THAT is the architecture decision and gets the ADR.
- **`gh api .../jobs/<id>/logs` returns no greppable body from this session**; use `gh run view
  <run-id> --log --job <job-id>` (measured on 36 runs).
- **Ingest 2xx ≠ recorded check-in.** The devin-docs-drift step got a 2xx-equivalent success for a
  monitor Sentry does not have. The only evidence of P1 is a row from the monitors API.
- **The composite's `-w` line is output only.** Exit codes, the secret-presence guard and the
  `-f` behaviour are unchanged; the 13 sibling sites see one extra log line.
- **Reusable-workflow job-level `uses: ./.github/workflows/…`** resolves from the repository ref
  (GitHub docs: "reusable workflows are referenced … from the caller's repository"), not the
  workspace; the lint classifies it explicitly rather than ignoring it.
- **Branch dispatch side effects** are the workflow's normal ones (it may file/close its own
  drift/delivery issues) because both jobs read `main`; nothing branch-specific leaks.
- **`hr-github-api-endpoints-with-enum`** — the check-ins read uses no enum parameters; the
  dispatch uses `gh workflow run` (documented `ref` input).

## Implementation Phases

### Phase 0 — Probes (no writes outside the scratchpad)

0.1 Re-run the census in `Research Reconciliation` (yaml-parsed, all `uses:`) and confirm the
    single RED is `scheduled-marketplace-drift.yml:drift-check`. This is the RED baseline the
    lint's live run must reproduce before the workflow edit lands.
0.2 Already measured at plan time (see Technical Considerations): actionlint 1.7.7 adds exactly
    one `[action]` finding for the `$/` form. Re-run once against the final file: acquire the
    binary into the scratchpad exactly as `ci.yml`'s "Install actionlint (pinned, sha-verified)"
    step does (the release tarball URL for `ACTIONLINT_VERSION` + `sha256sum -c` against
    `ACTIONLINT_SHA256`, both read from `ci.yml`), then `./actionlint -no-color -shellcheck=
    -pyflakes= <file>`; paste the delta line into the PR body AND as a comment on #7042 (the
    census reader looks there, not in a PR body). No released actionlint parses `$/` (v1.7.12
    predates the 2026-07-30 announcement; upstream tracker rhysd/actionlint#711), so the bump is
    unschedulable — the workflow comment beside the `$/` line cites that tracker so the finding
    self-explains.
0.3 **Gate 0 — the monitor exists.** `GET /api/0/organizations/jikigai-eu/monitors/scheduled-marketplace-drift/`
    must return HTTP 200 with `config.schedule == "37 6 * * *"` (measured 2026-09-18: 200,
    `status: active`, `environments: []`). An empty `checkins/` array is ambiguous between "no
    check-in yet" and "no such monitor" — the sibling `scheduled-devin-docs-drift` returns 404 on
    the same read while its ingest POST still succeeds. Only after Gate 0 does `checkins/?per_page=5`
    → `[]` mean "dark". Record both reads' timestamps for the PIR.
0.4 Record the dispatch pre-conditions the read-back predicate needs: the job inherits the
    workflow-level `permissions: contents: read` (no job-level override on `drift-check`), so a
    `$/` resolution failure that reads as 403/404 is a token/permissions cause, not syntax
    novelty — diagnose before switching to the fallback.

### Phase 1 — The guard, RED first (`cq-write-failing-tests-before`)

1.1 Write `scripts/lint-workflow-local-action-checkout.test.sh` from the mutation matrix in
    `## Guard Contract` — every RED row, every must-PASS row, the harness rows. Row 4 is the
    synthesized production shape (a `needs:` + `if: ${{ !cancelled() }}` job, five inputs,
    `if: always()`, `continue-on-error: true`, no checkout). Every fixture tree the suite builds
    clears `MIN_SAME_REPO_STEPS` so the floor is exercised by design, not bypassed (no
    floor-override flag exists — that is the weakening vector the Anchor forbids).
    Build the floor-clearing fixture tree ONCE per suite run and reuse it across cases (runtime
    band of `issue-write-scope`, ~1.5 s, not `install-sites`, ~13 s). The suite's tail is the
    `lint-workflow-issue-write-scope.test.sh` tail verbatim (`verdict_ok`, literal
    `FAIL_FLOOR_MIN`, FATAL `exit 2`) so `scripts/guard-vacuity-floor.test.sh` scores it
    constructible. Row 9 is the H3 shape from `lint-workflow-errexit-capture.test.sh`: copy the
    live `.github/workflows/` tree, rewrite the `$/` heartbeat line back to `./`, expect RED by
    name; the unmutated copy must be clean. Run the suite: every case fails because the SUT does
    not exist.
1.2 Write `scripts/lint-workflow-local-action-checkout.py`. Header, in the family's shape: WHY
    (the 36-run dark window and the devin-docs-drift twin); THE RULE; the `$/…@` reject and why
    actionlint cannot catch it; named non-properties; the floor; DIRECTION OF ERROR; the measured
    sentence "Measured on origin/main's 80 workflows: exactly ONE finding
    (`scheduled-marketplace-drift.yml:drift-check`), fixed in this PR, so the `-live` arm is
    green on merge"; the reference-form posture; and trailing `Usage: python3
    scripts/lint-workflow-local-action-checkout.py [<dir>]` / `Exit: 0 clean, 1 findings, 2
    usage/parse` lines. Run the unit suite → green (row 9 is a delta assertion, so it is green
    before Phase 2 too). Run the live scan → exactly one finding (the marketplace-drift job).
    This is the guard proving the tree is red before the fix.
1.3 Register both in `scripts/test-all.sh` next to `lint-workflow-issue-write-scope` (unit +
    `-live`, with the sibling's two-line "both halves are required" comment), and confirm
    `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/guard-vacuity-floor.test.sh` pass.

### Phase 2 — The fix

2.1 `.github/workflows/scheduled-marketplace-drift.yml`: `uses: $/.github/actions/sentry-heartbeat`;
    rewrite the two comment blocks. `permissions:` untouched (AC checks the byte range).
2.2 `.github/actions/sentry-heartbeat/action.yml`: add the `-w` line; add the `$/` paragraph to
    the header; keep every other byte.
2.3 Live lint now returns 0 findings — 53 `./` steps (all preceded by a checkout) and 1 `$/` step
    classified; unit suite still green.

### Phase 3 — Pre-merge verification from the branch

3.1 Push. `gh workflow run scheduled-marketplace-drift.yml --ref
    feat-one-shot-marketplace-drift-heartbeat-checkout`; wait with a bounded poll (Monitor tool,
    not `run_in_background`, per `hr-monitor-not-run-in-background-for-polling`).
3.2 Read the `drift-check` job log: `##[group]Run $/.github/actions/sentry-heartbeat` (or the
    fallback form), zero `Can't find 'action.yml'` lines, a `sentry-heartbeat: http_code=2xx`
    line (primary arm only — the fallback pin cannot carry the `-w` change), and `##[end-action …
    outcome=success`. **Setup-failure arm:** if the run is `startup_failure`, or `drift-check`
    fails inside `Set up job` before the manifest check runs, or `gh workflow run` returns HTTP
    422, the reference form was rejected at download time — there may be no job log at all. That
    is the fallback trigger (3.4), after the Phase 0.4 permissions check rules out a 403/404
    token cause.
3.3 Read back: `doppler run -p soleur -c prd --only-secrets SENTRY_IAC_AUTH_TOKEN -- sh -c 'curl
    -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN"
    "https://sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-marketplace-drift/checkins/?per_page=5"'
    | jq '.'` (the ADR-031 workstation read path — org integration `iac-terraform-prd`, Doppler
    `soleur/prd`, measured 200 on this endpoint 2026-09-18. `--only-secrets` (flag verified in the
    installed CLI) exports ONE key into the shell instead of the whole prd config; the
    single-quoted `sh -c` body is load-bearing — the variable must expand INSIDE the `doppler run`
    environment, never in the caller's shell — and the body must never run under `set -x` or
    `curl -v`. `SENTRY_API_TOKEN` in the same config is the fallback if the integration token is
    rotated mid-session.)
    → ≥ 1 row with `dateCreated` after the dispatch and `status` equal to the value the run
    computed; capture `id`, `status`, `environment`, `dateCreated`. If no such row exists after the
    run completes, the fix has not landed regardless of what the log says — stop and diagnose
    (first suspect: the `$/` form; switch to the fallback).
3.4 If the `$/` form failed to resolve: apply the fallback pin, push, repeat 3.1–3.3.
3.5 **Side effect, named:** this first check-in ARMS the monitor. Sentry starts expecting a
    check-in every tick from now on; `main` still runs `./` until this PR merges, so if the merge
    slips past the next tick plus the 360-minute margin (≈ 12:37 UTC the following day), Sentry
    files a missed-check-in issue against `main`'s still-dark copy. That issue would be correct,
    not noise — but merge on the same day to avoid creating it, and if it appears, it closes
    itself on the first post-merge check-in (`recovery_threshold = 1`). Second side effect: with
    `failure_issue_threshold = 1`, a first-ever check-in of `status=error` opens a Sentry issue
    IMMEDIATELY, not after the margin — 3 of the last 36 runs were unrelated failures, so the
    dispatched run can compute `error`. That is the monitor working; an `error` row satisfies
    AC10 (it proves resolution, not health), but diagnose the unrelated failure before recording
    it, and say which status the row carried in the PR body.

### Phase 4 — PIR amendment (after 3.3 has a timestamp)

4.1 Frontmatter: `recovery_at: "<dateCreated of the first check-in row, ISO-8601 Z>"  # measured:
    Sentry cron monitor check-in id <id> via GET /monitors/scheduled-marketplace-drift/checkins/`
    (the layer citation lives on the value line, so a future reader can tell a measured row from
    a typed timestamp — the defect this amendment corrects);
    `incident_window: "2026-08-12 (workflow created in #7473, 790dd8227) → <that date> (PR #8313:
    the composite resolves through a self-repository reference)"` — the `#7473` token is the
    PIR's own content and stays as the PIR wrote it; `status: resolved  # amended
    2026-09-18 — the 2026-08-13 repair did not recover the monitor; see the AMENDED banner`.
4.2 Banner (blockquote directly under the frontmatter, mirroring the RECURRED precedent):
    what was claimed, what was measured (36/36 runs with the resolution error, 33/36 green,
    `[]` from the monitors API until the pre-merge dispatch), the mechanism (`./` resolves from
    the workspace; the job has none; `continue-on-error` greened the step), why the repair's
    verification could not see it (it read the step/run conclusion; the PIR's `recovery_at` was
    an expectation with no probe), the dark-window arithmetic, the fix (self-repository ref) and
    the guard (`scripts/lint-workflow-local-action-checkout.py`). State plainly that the
    `recovery_at` row came from a `workflow_dispatch` of this PR's branch (measured, not
    expected) while `main` stayed dark until merge, and that the `main`-ref check-in is evidenced
    by AC16's row in the PR body — no skill edits the PIR after merge, so the PIR must not claim
    the `main` row itself.
4.3 `## What would have caught it`: add the second gap — nothing asserted that a `uses: ./` step
    is preceded by a checkout — and state that it is now closed by the lint (not a proposal).
4.4 `## Related`: add PR #8313, the devin-docs-drift repair (2026-09-18), the PR #8311 learning
    path, and #8282 (the sibling monitor absent from Sentry). `## Action Items & Follow-ups`
    keeps the permitted no-item sentence as its prefix and appends the truth in the same line:
    `*No action items — incident fully resolved by PR #8313 (2026-09-18; the source PR #7504
    did not recover the monitor — see the AMENDED banner); no residual work.*` — the gate's
    `SENTENCE_RE` is `^[_*]?No action items — incident fully resolved` with no end anchor, so
    the honest suffix passes and "in the source PR" (the claim the banner retracts) is gone; run
    `bash plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh <pir-path>` → pass.
4.5 Run `python3 scripts/lint-infra-no-human-steps.py <pir-path>` → OK (the banner names no
    human-run infra step). The PIR records only the row values (`id`, `status`, `environment`,
    `dateCreated`) and the run URL — never which Doppler token holds which Sentry scope (that
    token-scope map stays in this plan; the repo is public).

### Phase 5 — Learning (compound at ship)

`/compound` at ship decides whether a learning is written. If it is, it carries ONLY the two
novel points — a PIR `recovery_at` written as a future expectation is not a measurement, and an
ingest 2xx is not a recorded check-in (the devin-docs-drift monitor 404) — and cites, rather than
restates, `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` (green `continue-on-error`
step ≠ delivery), `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`
(the path's own telemetry), and the PR #8311 learning path in prose (not a link — that file is
not on `main` yet). Directory + topic only; the date is chosen at write time.

### Post-merge (executed by the one-shot pipeline's post-merge step — no operator step)

**Who runs it, stated precisely (`hr-verify-repo-capability-claim-before-assert`):** `/ship`'s
generic "post-merge validation of modified workflows" dispatches the workflow and checks
`conclusion` only — the proxy that lied for 36 days — and `/postmerge` Phase 3.5 reads
`/monitors/` and treats `status: active` as healthy, which this monitor reported throughout the
dark window. Neither reads `checkins/`. So the read-back below is executed verbatim by the
one-shot pipeline's post-merge verification (the runner's own constraint 4), as the LAST step
before DONE, and its output — the row — is what DONE cites. Stated honestly: no skill in the repo
reads this block; the runner executes it by hand (it is also Phase 6 of `tasks.md`, unchecked,
so DONE cannot pass it silently), and the DURABLE post-merge guard is the monitor's own
missed-check-in issue after the 360-minute margin. The commands, copy-paste:

```bash
# /ship's modified-workflow validation already dispatches this workflow on main and polls it;
# reuse THAT run (the newest run on main). Dispatch again only if none exists after merge.
RUN=$(gh run list --workflow scheduled-marketplace-drift.yml --branch main --limit 1 --json databaseId,createdAt,event -q '.[0]')
JOB=$(gh run view "$(jq -r .databaseId <<<"$RUN")" --json jobs -q '.jobs[]|select(.name=="drift-check")|.databaseId')
gh run view "$(jq -r .databaseId <<<"$RUN")" --log --job "$JOB" | grep -c "Can.t find .action.yml"      # must be 0
gh run view "$(jq -r .databaseId <<<"$RUN")" --log --job "$JOB" | grep -E "sentry-heartbeat: http_code=2[0-9]{2}"  # primary arm: 1 line
doppler run -p soleur -c prd --only-secrets SENTRY_IAC_AUTH_TOKEN -- sh -c 'curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
  "https://sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-marketplace-drift/checkins/?per_page=5"' \
  | jq --arg t "$(jq -r .createdAt <<<"$RUN")" '[.[] | select(.dateCreated > $t)] | length'            # must be >= 1
```

DONE requires the last command to print ≥ 1. A green conclusion with 0 here is the 36-day
failure recurring, and is reported as such. The two log greps are diagnostics for the report; the
row is the gate. The read is inline rather than a `scripts/followthroughs/` reader because no
existing reader is parameterised for a workstation token and this is not a follow-through — said
here so the next reviewer does not file it as duplication. No re-pin step exists on the fallback
arm (see Technical Considerations). The standing guard after this session is the monitor itself:
a missed tick becomes a Sentry issue after the 360-minute margin.

## Files to Edit

- `.github/workflows/scheduled-marketplace-drift.yml` — one `uses:` line + two comment blocks;
  `permissions:` (lines `permissions:` … `actions: write`) byte-identical.
- `.github/actions/sentry-heartbeat/action.yml` — `-w` on the curl; header paragraph on `$/`.
- `scripts/test-all.sh` — two `run_suite` lines beside `lint-workflow-issue-write-scope`.
- `knowledge-base/engineering/operations/post-mortems/2026-08-13-marketplace-drift-monitor-dark-since-creation-postmortem.md`
  — frontmatter + banner + two sections (Phase 4).

## Files to Create

- `scripts/lint-workflow-local-action-checkout.py`
- `scripts/lint-workflow-local-action-checkout.test.sh`
- `knowledge-base/project/learnings/<date>-<topic>.md` (Phase 5 — only if `/compound` decides to write it)

Pipeline-written files that also land in the diff (diff-scope AC lists them):
`knowledge-base/INDEX.md`, `knowledge-base/project/specs/feat-one-shot-marketplace-drift-heartbeat-checkout/{tasks.md,session-state.md,decision-challenges.md}`
(the last only if plan-review emits a challenge), and this plan.

## Open Code-Review Overlap

- #7942 (`Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no
  gate`) mentions `scripts/test-all.sh`. **Acknowledge:** it concerns `plugins/soleur/test/*.mutation.sh`
  registration, not the `scripts/lint-workflow-*` block this plan touches; the two `run_suite`
  lines added here do not change its scope. It stays open.
- No open code-review issue names the workflow, the composite, the PIR or the new lint path.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The affected artifact is the
  operator's alarm that the plugin's only distribution channel (`jikig-ai/soleur-marketplace`) is
  still being watched; a broken fix leaves that alarm dark, as it is today, so a future manifest
  drift could reach a user's `claude plugin install` unnoticed — a second, independent failure.
- **If this leaks, the user's data is exposed via:** no vector. The workflow processes no user
  data; the only new bytes on the wire are a Sentry check-in status and the HTTP code in a public
  Actions log, and the ingest values are already masked as secrets.
- **Brand-survival threshold:** `none` — `threshold: none, reason: the diff changes how an
  internal liveness beacon is resolved and adds a workflow lint; no user-facing surface,
  credential or data path is touched, and the PIR that declared single-user incident did so for
  the channel, not for its alarm.` No sensitive path is matched (`scheduled-marketplace-drift.yml`
  is outside the preflight regex).

## Observability

```yaml
liveness_signal:
  what:            "Sentry Crons monitor `scheduled-marketplace-drift` — one ok|error check-in per drift-check run"
  cadence:         "daily (cron 37 6 * * *, scheduled-run delay observed up to ~6 h) plus every workflow_dispatch"
  alert_target:    "Sentry issue on missed check-in (checkin_margin 360 min, failure_issue_threshold 1) → the web-platform project's alert routing"
  configured_in:   "apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor.scheduled_marketplace_drift); .github/workflows/scheduled-marketplace-drift.yml step `Sentry check-in (final)`"

error_reporting:
  destination:     "the same monitor — status=error is a check-in, not a silence; curl failures print `curl: (22) …` plus `sentry-heartbeat: http_code=<code>` in the public Actions step log"
  fail_loud:       "`sentry-heartbeat: http_code=` absent or non-2xx in the step log; `Can't find 'action.yml'` in the job log; an empty array from /monitors/scheduled-marketplace-drift/checkins/"

failure_modes:
  - mode:          "local action fails to resolve again (a future edit reverts to `./` without a checkout)"
    detection:     "layer 6 (CI workflow run log): the live scan in the `test-scripts` shard prints `::error file=<wf>::<wf>: job '<job>', step '<step>' …` and exits 1, which reddens the required `test` aggregator (`ci.yml` `needs:`)"
    alert_route:   "red CI on the PR; nothing can merge (ruleset context `test`)"
  - mode:          "the self-repository ref stops resolving on the hosted runner"
    detection:     "the download happens in `Set up job`, so the whole drift-check job fails before the manifest check runs (red run, or a run-level startup_failure with no job log) AND the check-in stops — Sentry raises a missed-check-in issue after the 360-min margin"
    alert_route:   "layer 6 (Actions run log: red scheduled run on main) + Sentry cron monitor `scheduled-marketplace-drift` missed-check-in issue → the web-platform project's alert routing (same route every sibling monitor uses)"
  - mode:          "Sentry ingest rejects the POST (auth/ingest blip)"
    detection:     "layer 6 (Actions step log): `curl: (22)` + `sentry-heartbeat: http_code=4xx`; the step stays green by design (continue-on-error); the monitor misses"
    alert_route:   "Sentry cron monitor `scheduled-marketplace-drift` missed-check-in issue"
  - mode:          "the workflow stops being scheduled (repo inactivity / dropped ticks)"
    detection:     "Sentry cron monitor `scheduled-marketplace-drift`: no check-in inside the 360-min margin (this is the property the whole fix restores)"
    alert_route:   "Sentry cron monitor missed-check-in issue → project alert routing"

logs:
  where:           "GitHub Actions run logs for scheduled-marketplace-drift.yml (public); Sentry monitor check-in rows"
  retention:       "Actions logs 90 days (repo default); Sentry check-ins per the org's Crons retention (90 days)"

discoverability_test:
  command:         "python3 scripts/lint-workflow-local-action-checkout.py"
  expected_output: "lint-workflow-local-action-checkout: OK —"
```

The check-in read-back (`curl … /monitors/scheduled-marketplace-drift/checkins/`) needs a Sentry
token and is therefore an Acceptance Criterion, not the discoverability test: the lint is the
unauthenticated probe of the structural property, and the AC is the authenticated probe of the
live one. `expected_output` is the invariant prefix, not the counts — Check 10 tokenises on `,`
and `/` so counts would any-match anyway, and no path in this diff matches the preflight
sensitive-path regex, so Check 10 is path-gated OFF for this PR; AC4 is the executed twin.

## Guard Contract

### Guard 1 — lint-workflow-local-action-checkout

**Property.** Every `uses:` step in a workflow file whose value starts with `./` is preceded, in
the same job's `steps` list, by a step whose `uses:` matches `^actions/checkout(@|$)` that is
usable for it: either that checkout carries no `if:`, or its `if:` string is byte-identical to
the `./` step's `if:` (a checkout skipped by its own condition is no checkout —
`workspaces-luks-cutover.yml:preflight` guards both with `${{ inputs.clean_stray }}` and passes;
the heartbeat's `if: always()` after a conditional checkout would fail). With several earlier
checkouts, ANY qualifying one satisfies the step. Second surface, zero-floor: no
`.github/actions/*/action.yml` `runs.steps[].uses` starts with `./` (a nested `./` resolves from
the CALLER's workspace, which no lint can see; GitHub documents `$/` for composite steps, so the
enforceable rule is "no `./` inside composites"; 0 today). Named non-properties, documented in
the lint header: `if:` is compared as a string, never evaluated (a `./` step whose `if:`
legitimately narrows its checkout's `if:` is a loud false positive whose fix is obvious); the
checkout's `with:` (`sparse-checkout:`, `path:`, `repository:` — 0 members of each on any
checkout today) is not inspected; the checkout ref's pin-ness (`@v4` vs `@<sha>`) is a separate
property this lint does not own; `$/`, `owner/repo[/path]@ref` and `docker://` values are
ignored except that a `$/` value carrying `@` is a named reject.

**Assembly.** Two chokepoints, both walked: (1) `jobs.<id>.steps[]` in list order for every job
of every `*.yml`/`*.yaml` in the directory argument (default `.github/workflows`; 80 files
today), and (2) `runs.steps[]` of every `.github/actions/*/action.yml` (7 today). PyYAML
`safe_load`, the `lint-workflow-run-body-syntax.py` walk (`isinstance` ladder over doc / `jobs`
/ job / step), the `lint-workflow-issue-write-scope.py` argv + glob + `scanned == 0` skeleton.
Job-level `uses:` (2 reusable-workflow calls today) is skipped. Members (54 `./` steps across 38
jobs in 32 workflows today) are a snapshot; the assembly is the walk, floored at
`MIN_SAME_REPO_STEPS=30` over `./` + `$/` steps together. Exit contract is the family's: 0 clean,
1 findings, 2 usage/empty/parse — an unparseable file, a file with no `jobs` mapping, a
non-mapping job or step, a non-string `uses:`, or zero files scanned exits 2 NAMING the file,
never a silent skip. A finding prints `::error file=<wf>::<wf>: job '<job>', step '<step>' uses
'<value>' with no preceding actions/checkout in this job` on stderr plus a
`N violation(s) across N workflow(s)` summary; the clean line is
`lint-workflow-local-action-checkout: OK — N workflows scanned, N local-action steps, N
self-repository steps; every local-action step is preceded by actions/checkout in its job`
(nouns invariant, counts sed-parseable).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A job with `uses: ./.github/actions/x` and no `actions/checkout` step at all | RED (rc 1; stderr names `file: job 'j'`) |
| 2 | Same job, `actions/checkout` present but AFTER the `./` step (reorder — the order property, not presence) | RED |
| 3 | Two jobs in one file: job A has checkout then `./`; job B has `./` with no checkout (A's checkout must not satisfy B); plus a THIRD file, sorting after the first, whose only job is mutation 1 (the walk must not stop at the first file or the first job) | RED, naming B and the third file, not A |
| 4 | The `./` step carries `continue-on-error: true` and `if: always()` in a `strategy.matrix` job (the production shape — neither key is an exemption; a matrix does not change `steps[]`) | RED |
| 5 | `actions/checkout` with `if: ${{ inputs.x }}` followed by `./` with `if: always()` (conditional checkout, unconditional local step) | RED |
| 6 | A checkout LOOKALIKE before the `./` step: `actions/checkout-foo@<40-hex>` (a guard implemented as an unanchored substring passes rows 1–5) | RED |
| 7 | `$/.github/actions/x@v1` (the form actionlint 1.7.7 accepts and GitHub rejects) | RED |
| 8 | Dispatch sub-cases, each asserted separately: an empty directory; a tree of 40 workflows containing 0 `uses:` steps (below `MIN_SAME_REPO_STEPS`); a tree containing one file that does not parse; a file with no `jobs` mapping; extra argv | rc 2 AND the file / floor named in stderr (a bare `rc != 0` is not enough — "exit 1 unconditionally" must not pass) |
| 9 | Verify-the-verifier, arm- and phase-independent: copy the live `.github/workflows/` tree into `$TMP`, delete the `actions/checkout` step from one checkout+`./` sibling (`scheduled-domain-model-drift.yml:drift-check`), re-parse the mutated copy and assert the deletion landed in `steps[]`, run — the `lint-workflow-errexit-capture.test.sh` H3 shape | RED naming `scheduled-domain-model-drift.yml: job 'drift-check'`, and the mutated copy's finding count equals the unmutated copy's + 1 (the control is the delta, so the row is green before Phase 2 lands and on the fallback arm) |
| 10 | A commented-out `# - uses: actions/checkout@<sha>` (and a `run:` string mentioning `actions/checkout`) before the `./` step | RED (pins YAML-parse over text-scan) |
| 11 | Row 1 in a `.yaml` file | RED (the glob covers both extensions) |
| 12 | `.github/actions/x/action.yml` whose `runs.steps[]` contains `uses: ./.github/actions/y` | RED (second surface) |

Must-PASS rows (non-canonical, explicitly permitted): (a) `$/.github/actions/x` with no checkout
anywhere; (b) `actions/checkout@<40-hex>` with `with: {fetch-depth: 0, persist-credentials:
false}` then `./` (the live shape — 55/55 live checkouts carry `with:`); (c) `actions/checkout@v4`
(tag form — pin-ness is a separate property, not a permission this fixture grants) then `./`;
(d) job-level `uses: ./.github/workflows/reusable.yml` with no steps; (e) a job with `run:`-only
steps and no `uses:` at all; (f) `actions/checkout` with `if: ${{ inputs.x }}` then `./` with the
byte-identical `if:` (the `workspaces-luks-cutover.yml:preflight` shape); (g)
`jikig-ai/soleur/.github/actions/x@<40-hex>` with no checkout (the fallback form); (h) an
unconditional checkout, then a conditional checkout, then `./` with `if: always()` (any qualifying
earlier checkout satisfies the step); (i) the filler tree alone is clean (rc 0, same-repo count ≥
30) — asserted once before any case runs, so every case's verdict rests on an asserted premise.

**Harness rows:** (i) `pass()`/`fail()` canary lines as in
`lint-workflow-issue-write-scope.test.sh` — a false condition MUST register as FAIL; (ii) the
sibling tail verbatim: `verdict_ok` discriminated in both directions, then `FAIL_FLOOR_MIN=<n>` as
a literal on the line directly above `if [[ "$TOTAL" -lt "$FAIL_FLOOR_MIN" ]]` with FATAL
`exit 2`, where `<n>` is the number of assertions EXECUTED on a green run (= AC6's N; ≥ 24 on the
rows above — not the number of `pass`/`fail` call sites, which double-counts every `if/else`).
The floor-clearing filler tree is built ONCE into `$TMP/filler`; `reset()` is
`rm -rf "$TMP/wf"; cp -r "$TMP/filler" "$TMP/wf"` (the sibling's bare `rm -rf` would drop every
case below the floor), and only row 8's below-floor sub-cases use a bare directory. Runtime band:
`issue-write-scope` (~1.5 s), not `install-sites` (~13 s). No stub-SUT self-recursion row: the
skeleton hardcodes `SUT=` and the twelve RED rows already fail against a `sys.exit(0)` stub.

**Anchor.** No stored value is compared: the guard quantifies over the live tree on every run, so
there is nothing a single diff could weaken alongside the thing it protects. The floor is `>= N`
and is paired with set identity through row 9, which reddens a real sibling by name on every
run, on either arm, before and after merge.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `grep -cE '^\s*uses: \$/\.github/actions/sentry-heartbeat$' .github/workflows/scheduled-marketplace-drift.yml` returns `1` and `grep -cE '^\s*uses: \./\.github/actions/sentry-heartbeat$' .github/workflows/scheduled-marketplace-drift.yml` returns `0` (syntax-anchored — the rewritten comment blocks may quote either form in prose; or, on the documented fallback, `grep -cE '^\s*uses: jikig-ai/soleur/\.github/actions/sentry-heartbeat@[0-9a-f]{40}$'` returns `1` and the PR body says why).
- [ ] AC2 — `python3 -c 'import yaml,sys;d=yaml.safe_load(open(".github/workflows/scheduled-marketplace-drift.yml"));sys.exit(any(str(s.get("uses","")).startswith("actions/checkout") for s in d["jobs"]["drift-check"]["steps"]))'` exits 0 (the no-checkout property is preserved by structure, not by comment).
- [ ] AC3 — `git diff origin/main -- .github/workflows/scheduled-marketplace-drift.yml | grep -E '^[-+]\s*(permissions:|contents:|issues:|actions:)'` prints nothing (the `permissions:` block is byte-identical).
- [ ] AC4 — `python3 scripts/lint-workflow-local-action-checkout.py` exits 0 and prints the canonical OK line matching `OK — ([0-9]+) workflows scanned, ([0-9]+) local-action steps, ([0-9]+) self-repository step` with the first two counts ≥ 40 and ≥ 30 and the third ≥ 1 on the primary `$/` arm (0 on the documented fallback arm, where the site is a remote ref) — measured 2026-09-18 on the post-fix tree: 80 / 53 / 1, recorded not asserted, because a sibling merge adding a workflow must not flip this AC; the test suite, not this AC, owns the floors.
- [ ] AC5 — RED proof against the real merge-base file, with the floor intact: `T=$(mktemp -d); cp .github/workflows/*.yml "$T/"; git show origin/main:.github/workflows/scheduled-marketplace-drift.yml > "$T/pre.yml"; python3 scripts/lint-workflow-local-action-checkout.py "$T"` exits 1 (a FINDING — not 2, which is the usage/empty/parse code) and its stderr carries `::error file=…pre.yml::pre.yml: job 'drift-check'` (81 files and 54+ same-repo steps, so `MIN_SAME_REPO_STEPS` is satisfied; a bare directory holding one file would exit 2 on the floor first). Pre-merge only — after merge `origin/main` carries the fixed file; the unit suite's row 9 carries the same assertion by mutation forever.
- [ ] AC6 — `bash scripts/lint-workflow-local-action-checkout.test.sh` exits 0 with `=== Results: N/N passed, 0 failed ===` where N equals the suite's literal `FAIL_FLOOR_MIN` (≥ 24, the count of assertions executed on a green run), and the canary line `FAIL: canary: a false condition MUST register as FAIL (this line is EXPECTED)` is present.
- [ ] AC7 — `grep -cE '^\s*run_suite "scripts/lint-workflow-local-action-checkout(-live)?"' scripts/test-all.sh` returns `2` (unit + `-live`; the explanatory comment beside them is not counted), `bash scripts/lint-orphan-test-suites.sh` exits 0, and `bash scripts/guard-vacuity-floor.test.sh` stays green with the new suite counted as constructible.
- [ ] AC8 — `grep -cF "sentry-heartbeat: http_code=%{http_code}" .github/actions/sentry-heartbeat/action.yml` returns `1` AND that line begins with `-w` after leading whitespace (`grep -cE "^\s*-w '" .github/actions/sentry-heartbeat/action.yml` returns `1`); `grep -c '^ *exit 0$' .github/actions/sentry-heartbeat/action.yml` still returns `1` (the run-body guard; the header comment also says `exit 0`, so a bare grep reads 2) and `grep -cE '^\s*curl --max-time 10 -fSs -X POST' .github/actions/sentry-heartbeat/action.yml` still returns `1` (guard and `-f` unchanged; the greps are anchored on syntax so the new header paragraph must not contain the literal `http_code=%{http_code}` — it describes the line in words); and the negative anchor `grep -cE '%\{(url|url_effective|redirect_url|json|header_json)' .github/actions/sentry-heartbeat/action.yml` returns `0` (the format string must never gain a URL- or header-printing variable — the URL carries `SENTRY_PUBLIC_KEY`, and runner masking is value-substring only).
- [ ] AC9 — A `workflow_dispatch` run of `scheduled-marketplace-drift.yml` on this branch exists whose `drift-check` job log (`gh run view <id> --log --job <job>`) contains 0 lines matching `Can.t find .action.yml` and — on the primary `$/` arm — 1 line matching `sentry-heartbeat: http_code=2[0-9]{2}`; on the documented fallback arm the `http_code` line is unobtainable (the pinned composite predates `-w`) and the predicate is 0 resolution errors + `##[end-action … outcome=success` for the heartbeat step + the AC10 row. The run id and the arm are recorded in the PR body.
- [ ] AC10 — Gate 0 first: `GET …/monitors/scheduled-marketplace-drift/` returns HTTP 200 (the slug exists). Then `doppler run -p soleur -c prd --only-secrets SENTRY_IAC_AUTH_TOKEN -- sh -c 'curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" "https://sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-marketplace-drift/checkins/?per_page=5"' | jq --arg t "<AC9 run createdAt>" '[.[] | select(.dateCreated > $t and .status == "<the status the AC9 run computed, expected ok>")] | length'` returns ≥ 1 — a row AFTER the dispatch with the status the workflow computed, not merely "≥ 1 row" (a pre-existing or cron-fired row proves nothing about this branch); the row's `id`, `status`, `environment`, `dateCreated` are recorded in the PR body and in the PIR.
- [ ] AC11 — PIR frontmatter: `grep -E '^recovery_at: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' <pir>` matches (end anchor dropped at /work: the value line carries the `# measured:` citation the last clause requires); `grep -c '^> \*\*AMENDED 2026-09-18' <pir>` returns `1`; `awk 'NR==1{next} /^---$/{exit} {print}' <pir> | grep -c 'expected at'` returns `0` (frontmatter only — the retracted phrase may survive inside the banner as a quotation); and `grep -cE '^recovery_at: .*# measured: Sentry cron monitor check-in id [0-9a-f-]{36}' <pir>` returns `1` (the layer citation rides the value line).
- [ ] AC12 — `bash plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh <pir>` exits 0 (this IS a ship gate: `--branch` mode checks every PIR in the diff), and `python3 scripts/lint-infra-no-human-steps.py <pir>` prints OK as an explicit-path courtesy check (`post-mortems/` is not in that lint's `SCAN_DIRS`, so it is not a gate for this file; the plan itself, under `project/plans/`, is in scope and passes today).
- [ ] AC13 — The PR body has a section "Why `$/` and not a checkout" reproducing the option table's verdicts, the AC9 run URL, the AC10 row, the actionlint finding delta from Phase 0.2, and states that #7520/#7524/#8282 are untouched.
- [ ] AC14 — Diff scope: `git diff --name-only origin/main...HEAD` is a subset of {the four Files to Edit, the three Files to Create, `knowledge-base/INDEX.md`, `knowledge-base/project/specs/feat-one-shot-marketplace-drift-heartbeat-checkout/*`, this plan, and — per the 2026-09-18 work-time addendum below — `test/fixtures/orphan-proc-dangling/**`}; in particular no other `.github/workflows/*.yml` changes.
- [ ] AC15 — `bash scripts/lint-workflow-local-action-checkout.test.sh` and `python3 scripts/lint-workflow-local-action-checkout.py` are green locally; the full `scripts` shard is CI's job (`bash scripts/test-all.sh scripts` refuses with rc=4 on a host with a sibling full-gate run in flight — measured — and needs `SOLEUR_ALLOW_FULL_GATE=1` for a sanctioned local run, which this AC does not require); and `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'` prints nothing except the PR #8311 learning path (expected absent until that PR merges).

### Post-merge (executed by the one-shot pipeline's post-merge step, commands in Implementation Phases → Post-merge)

- [ ] AC16 — `gh workflow run scheduled-marketplace-drift.yml` on `main`; the resulting run's `drift-check` log has 0 `Can.t find .action.yml` lines and (primary arm) 1 `sentry-heartbeat: http_code=2[0-9]{2}` line; the AC10 query returns ≥ 1 row with `dateCreated` after that run's `createdAt`. DONE is claimed on this row, never on the run conclusion; `/ship`'s conclusion-only workflow validation does not satisfy this AC.

## Test Scenarios

- Unit suite (`scripts/lint-workflow-local-action-checkout.test.sh`): the 12 RED rows (row 8
  with sub-cases), 9 must-PASS rows and 2 harness rows above; synthesized fixtures except row 9,
  which mutates a copy of the live tree (delta-asserted, so green on either arm and before the
  fix); every fixture tree above the floor via the once-built filler.
- AC5: the real pre-fix workflow dropped into a copy of the live `.github/workflows/` tree
  reddens by name (pre-merge only).
- Live scan before the workflow edit: exactly one finding, `scheduled-marketplace-drift.yml:drift-check:Sentry check-in (final)`.
- Live scan after: zero findings, counts as in AC4.
- Branch dispatch (AC9/AC10): real check-in observed via the API.
- Post-merge dispatch (AC16): second check-in observed.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a workflow reference,
a workflow lint, a PIR correction). Product/UX: no UI surface in Files to Edit/Create. Legal: the
PIR's Art. 33/34 fields stay `false`; no personal data is processed. Finance/ops: no vendor
change.

## Dependencies & Risks

- **Risk: `$/` unsupported in practice.** Mitigated by measuring on the branch (Phase 3) with a
  documented fallback; the AC set is written so the fallback still satisfies AC1/AC9/AC10.
- **Risk: actionlint finding delta.** Non-blocking by CI design (rc=1 accepted); measured and
  recorded. If actionlint 1.7.7 rejects `$/` with an exit other than 1, that is a CI-invocation
  failure per the hang guard's `*)` arm — Phase 0.2 catches it locally first.
- **Risk: the PIR gate rejects the amended Action Items section.** The section is left exactly
  as the permitted sentence; AC12 runs the gate.
- **Risk: false positives from the lint on a sibling that checks out via `run: git clone`.**
  Census shows 0 such jobs; the lint header documents `actions/checkout` as the only recognised
  checkout and the direction of error (a false positive blocks a PR loudly — the fix is to add
  `actions/checkout` or switch to `$/`).
- **Dependency: Doppler `soleur/prd` `SENTRY_IAC_AUTH_TOKEN`** for AC10/AC16 (read-only; the
  ADR-031 workstation path; measured 200 on the monitor endpoint). `prd_terraform` is the config
  #8090 is de-personalising, so the plan does not enshrine it; `SENTRY_API_TOKEN` in `soleur/prd`
  is the fallback (also 200). `SENTRY_ISSUE_RO_TOKEN` returns 403 on this endpoint (measured).
- **Dependency: PR #8311** is referenced by path only; nothing here edits it or depends on its
  merge order.

## Non-Goals

- Migrating the 53 sibling `./` + checkout steps to `$/`. They work; the lint accepts both
  forms; and every migrated site would add one actionlint `[action]` finding until a released
  actionlint parses `$/` (rhysd/actionlint#711). Posture, recorded in the workflow comment's
  `SOLEUR-DEBT:` marker: `./` + checkout stays canonical for jobs that already check out; `$/` is
  for checkout-free jobs; revisit when actionlint catches up. Not a capability deferral, so no
  tracking issue (ADR-131 posture).
- The devin-docs-drift monitor's absence from Sentry (#8282) and that repair's step-conclusion
  verification — recorded in the reconciliation table and in the learning; not fixed here.
- Extending the lint to `.github/actions/*/action.yml` nested `./` references (0 today) — named
  as a non-property in the lint header.
- Any change to `permissions:` (#7520), or to the guard gaps in #7524.
- A required-check promotion or a new gate NAME — the pair rides the existing `scripts` shard.

## Plan Review

Panel (headless, one-shot): spec-flow-analyzer (plan Phase 3), scoped advisor consult (Step 4.5),
DHH, Kieran, code-simplicity, CTO (devex). Standing check `cq-ac-must-not-depend-on-concurrent-sessions`:
AC4 rewritten to assert the OK line by shape with floors, not literal counts a sibling merge could
flip; AC15 no longer prescribes the full `scripts` shard locally (refuses rc=4 with a sibling
full-gate run in flight — measured). Mechanical findings applied in place (row 9 replaces the
real-file copy; one floor over `./`+`$/`; two-bucket classification; anchored ACs; ADR-031
credential path; post-merge gate on the `checkins/` row; posture marker). One User-Challenge —
whether to keep the `-w http_code` composite line the operator's constraint 4 asks for — is
recorded in
`knowledge-base/project/specs/feat-one-shot-marketplace-drift-heartbeat-checkout/decision-challenges.md`
with the pipeline default (keep).

## References & Research

- GitHub Docs — Workflow syntax, `jobs.<job_id>.steps[*].uses` (self-repository reference, subdirectory reference).
- GitHub Changelog 2026-07-30 — "Reference same-repository actions with self-repository syntax".
- `knowledge-base/engineering/operations/post-mortems/2026-08-13-marketplace-drift-monitor-dark-since-creation-postmortem.md`
- `knowledge-base/project/learnings/2026-09-18-local-composite-action-needs-checkout-continue-on-error-masks-it.md` (in open PR #8311)
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
- `knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md`
- `knowledge-base/engineering/architecture/decisions/ADR-170-workflow-run-step-must-clear-inherited-errexit.md`
- `scripts/lint-workflow-issue-write-scope.py` / `.test.sh` — harness precedent.
- `scripts/followthroughs/ghcr-minter-live-6031.sh` — check-ins read precedent.

## Addendum — 2026-09-18 (work-time deviation, measured)

The first branch dispatch (run `35360150848`) refuted one premise and confirmed another. The
`$/` form RESOLVED — the runner logged `Download action repository
'jikig-ai/soleur@4dc73ecb3…'` — and then `Set up job` failed extracting the repository archive:
`Could not find file '…/_staging/soleur-<sha>/test/fixtures/orphan-proc-dangling/4242/cwd'`.
That path was a COMMITTED dangling symlink (`/nonexistent-orphan-fixture/work (deleted)`) from
the orphan-process-reaper work; `4242/fd/255` was the second. Both `$/` and the fallback
`owner/repo/path@ref` form extract the whole repository archive, so the fallback arm in
Technical Considerations would have failed identically — the failure is not the reference form
but the archive. The repo's five valid symlinks (which sort earlier) extracted fine.

No runtime test reads the committed tree (AC30b in `scripts/orphan-process-reaper.test.sh`
synthesizes the same two links under `mktemp` on every run; 148/148 green after the change),
so the two symlinks were removed and the fixture's README records why a dangling symlink must
never be committed. This adds `test/fixtures/orphan-proc-dangling/**` to AC14's scope. Phase 3
repeats from run `35361236920`.

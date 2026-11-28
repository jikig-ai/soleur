---
title: "ci: scheduled-machinery-drain agent has never run on a weekly dispatch — bot-actor refusal after id-token fix, closed=0 on every run"
type: fix
date: 2026-11-27
slug: scheduled-machinery-drain-allowed-bots
branch: feat-one-shot-13095-drain-allowed-bots
issue: 13095
closes: 13095
domain: engineering
priority: p3-low
brand_survival_threshold: none
lane: cross-domain
---

# ci: scheduled-machinery-drain agent has never run on a weekly dispatch — bot-actor refusal after id-token fix, closed=0 on every run

## Enhancement Summary

**Deepened on:** 2026-11-27 (inline deepen-plan pass — subagent context, so
the agent fan-out gates §2/§3/§4/§5 were run as inline equivalents and the
always-on mechanical halts were run verbatim)
**Sections enhanced:** Acceptance Criteria (pre-merge/post-merge split per
the post-merge-operator-steps sharp edge); this summary
**Deepen gates run (all PASS or conditional-skip):**

- 4.6 User-Brand Impact — PASS: threshold `none`; the sensitive-path regex
  does not match `.github/workflows/scheduled-machinery-drain.yml` (verified
  mechanically).
- 4.7 Observability — PASS: all 5 fields present; `discoverability_test`
  executed live — `curl` (allowlisted verb) against the #9508 comments API
  returns the standing comment containing the literal `Machinery drain
  outcome`.
- 4.8 PAT-shaped variables — PASS: 0 hits on the canonical regex.
- 4.12 Scope Check — PASS: unfenced count 1; all three subsections present;
  6 Ask-Mapping rows all `mapped`; `Recommendation: single PR`; no BLOCKED.
- 4.4/4.45/4.5/4.55/4.9/4.10/4.11/4.13 — conditional-skip: no new scheduled
  job, no pattern-bound precedent (in-repo `allowed_bots` is novel; sibling
  audit is the precedent-diff), no network-SSH keywords, no downtime
  surface, no UI file, no store/connection, no guard-shaped deliverable
  (the presence-guard was deliberately cut), `Files to Create: None`.

**Live verifications performed in this pass (the run-each-command-once
edge):**

```text
$ gh run list --workflow=scheduled-machinery-drain.yml --limit 3
completed  failure  ...  workflow_dispatch  45143702615  42s  2026-11-23
completed  failure  ...  workflow_dispatch  43836618753  33s  2026-11-16
completed  failure  ...  workflow_dispatch  42590040792  41s  2026-11-09

$ gh run view 45143702615 --log | grep -n "non-human actor\|Drain the machinery"
439:measure-and-drain ... ##[error]Action failed with error: Workflow
    initiated by non-human actor: soleur-ai (type: Bot). Add bot to
    allowed_bots list or use '*' to allow all bots.
```

- Action source at the pinned commit (`8041f1d1`, tag object `3b7e1a45`,
  `# v1.0.263`, 40-char SHA — resolved live via `gh api`): `actor.ts`
  `isAllowedBot` lowercases and strips a trailing `[bot]` on BOTH the
  allowlist entries and `githubContext.actor`, and `action.yml:30-33`
  declares `allowed_bots` with the `'*'`-on-public-repos warning the
  in-file comment paraphrases.
- All cited issue/PR numbers resolved live: #13095 OPEN (the fix target),
  #9508 OPEN (standing issue), #9537 MERGED (prior id-token fix), #11556
  OPEN (epic), #12885/#12905 OPEN (queued items).

### New considerations discovered

- The refusal error's printed actor (`soleur-ai`, `type: Bot`) is the
  NORMALIZED form — the action strips `[bot]$` before printing. Empirical
  confirmation that `allowed_bots: "soleur-ai[bot]"` normalizes to the
  same `soleur-ai` token it compares against.
- `actor.ts` resolves actor type via `users.getByUsername`; unresolvable
  App actors take a catch-branch that still consults `allowed_bots` — the
  input covers both resolvable-Bot and unresolvable-App-actor paths, so no
  second gate can reject the dispatcher after this lands.

## Overview

`scheduled-machinery-drain.yml` is a `workflow_dispatch`-only workflow whose
weekly run is dispatched by the Inngest function `cron-machinery-drain.ts`
through a GitHub App installation token, so every weekly run's
`github.actor` — the value the action's actor gate reads — is the bot
`soleur-ai[bot]`. The `Drain the machinery ledger` step invokes
`anthropics/claude-code-action` (pinned to the annotated tag object of
v1.0.263), whose actor gate refuses non-human initiators unless they appear
in the action's `allowed_bots` input. The step carries no `allowed_bots`
entry, so since 2026-10-12 every weekly run has died ~1.7 s into the
action's inner `Run Claude Code Action` substep; `continue-on-error: true`
masks the death and the closing floor then reports BREACH with `closed=0`
(issue #13095, standing issue #9508). One post-merge human-dispatched
verification run (2026-10-05, actor `deruelle`) did execute the agent — the
only completed execution on record — and still reported `closed=0`; no
weekly bot dispatch has ever run it.

The fix is one input on the existing step: add
`allowed_bots: "soleur-ai[bot]"` to the `with:` block, with an explanatory
comment matching the file's comment conventions. The sibling
`claude-code-action` consumers (`fix-constraints-stage-a.yml`,
`claude-code-review.yml`, `test-pretooluse-hooks.yml`) need no change today —
but not because their triggers are human-only: `pull_request` is
actor-agnostic — the actor is whoever initiated the event, never
author-determined. Bot-authored PRs produce `soleur-ai[bot]` runs when the
bot itself synchronizes (measured: #13083's check runs), while a human push
to a bot-authored branch runs as the human (counterexample: dependabot's
#13103 ran as `deruelle`). The accurate per-consumer rationale is in the
audit table below. Verification is post-merge only: the action
validates the dispatched workflow file against default-branch content, so a
branch dispatch can never exercise the agent; the bot-actor path is exercised
by the weekly Inngest dispatch (or the allowlisted
`cron/machinery-drain.manual-trigger` event, which shares the cron's dispatch
code path).

## Research Insights

### Premise Validation (Phase 0.6)

- `#13095` is OPEN with measured evidence (0 `closed` on every run;
  `triggering_actor` = `soleur-ai[bot]` on every weekly dispatch). Cited
  refs verified: `#9508` OPEN (standing measurement issue), `#9537` MERGED
  (the `id-token: write` fix that exposed this second failure mode),
  `#11556` OPEN (epic), `#12885`/`#12905` OPEN (queued pool items).
- The dispatcher is real and bot-actor by construction:
  `apps/web-platform/server/inngest/functions/cron-machinery-drain.ts:37-56`
  mints a GitHub App installation token and POSTs the `dispatches` endpoint
  with `ref: "main"`, so `triggering_actor` on the run is the App login
  `soleur-ai[bot]`.
- **Proposed mechanism verified against the action itself:** `allowed_bots`
  is a declared input of `anthropics/claude-code-action` at tag `v1.0.263`
  (the pinned ref `3b7e1a45ca6f231c62605aabcf79e6a41b08c7da` is that tag's
  annotated tag-object SHA, which resolves to commit `8041f1d1` — the action
  demonstrably executes at this pin because the refusal error is emitted by
  its code). The input's description: "Comma-separated list of allowed bot
  usernames, or '*' to allow all bots … WARNING: On public repos with '*',
  external Apps may be able to invoke this action with prompts they
  control." Single entry — no separator hazard; the `"soleur-ai[bot]"`
  quoting avoids any flow-sequence parse of the brackets.
- **Collision precheck (exit 10):** PR #13096 is this pipeline's own
  auto-created draft on this branch (expected, not a duplicate); a foreign
  `test-all.sh` runs in sibling worktree `feat-one-shot-9294-deploy-trio-prb`
  (no overlap with a workflow-YAML edit).
- **ADR corpus:** no ADR governs the actor-allowlist surface. ADR-033
  (Inngest as the single scheduling substrate) explains why the dispatch is
  a `workflow_dispatch` and is untouched by this fix. ADR-053 explains the
  existing `--model claude-sonnet-5-5` pin comment. Nothing in the ADR set
  rejects `allowed_bots`.

### Property List (Phase 0.6b)

The ask restated as observable properties:

- **P1.** The `soleur-ai[bot]` actor passes `claude-code-action`'s actor
  gate on the `Drain the machinery ledger` step, so the drain agent runs on
  the weekly dispatch.
- **P2.** No other bot gains invocation (explicit login, not `*`) — the
  repo is public and `*` would let any external App invoke the action with
  prompts it controls (the action's own `allowed_bots` warning).
- **P3.** The change stays observable: the weekly floor verdict and Sentry
  heartbeat continue to report the drain's real state.

### Cut List (Phase 0.6b)

- No new mechanism invented. The `with:` block's existing inputs already
  buy P1 once `allowed_bots` names the dispatcher — the input is the
  action's own designed surface for this property.
- **Cut:** a presence-guard asserting `allowed_bots` in the workflow
  (invented by planning, not in the ask). Declined — P3 already covers the
  regression class: deleting the key re-breaks the drain within one weekly
  cycle and BREACHes on #9508, louder than a static pin would be.
- **Cut:** removing `continue-on-error: true` or otherwise redesigning the
  masking semantics. Out of the ask; the floor-verdict → standing-issue
  channel is the designed reporting path and already reports the failure.
- **Cut:** `github_token:` step input. The OIDC path (job-level
  `id-token: write`) is the resolved token path per #9537; `allowed_bots`
  governs a different gate (actor, not token mint).

### Institutional learnings that apply

- `learnings/2026-10-05-the-drain-was-born-broken-and-the-waiver-hid-it.md`
  — this same workflow; established that `claude-code-action` validates the
  dispatched workflow file against default-branch content, so a branch
  dispatch of a modified consumer skips the agent cleanly. Consequence:
  verification is post-merge only, by design.
- `learnings/2026-11-05-a-branch-dispatch-of-the-workflow-you-edited-is-skip-masked-and-a-tokenised-allowlist-is-split-on-spaces.md`
  — a green run `conclusion` is not evidence where `continue-on-error:
  true` is set; read the step log for the skip/refusal line. Also: allowlist
  values must be quoted and separator-aware (ours is a single quoted
  literal — no hazard).
- `learnings/2026-08-05-i-built-a-cadence-on-a-bot-that-never-ran-and-my-battery-certified-the-gate.md`
  — an AC must validate EXECUTION (a bot-actor run of the drain), not only
  the config (the diff landing). Drives AC3/AC4.
- `learnings/2026-05-04-schedule-once-template-missing-id-token.md` —
  recurrence class this defect belongs to (this is recurrence 4's sibling:
  a second stacked gate on the same step, surfaced only after the first was
  fixed).

### Sibling consumer audit (verified, extends the issue's)

| Workflow | `uses:` pin | Trigger set | Actor on dispatch | `allowed_bots` needed? |
|---|---|---|---|---|
| `scheduled-machinery-drain.yml` | `@3b7e1a45… # v1.0.263` | `workflow_dispatch` only, fired by Inngest via App token | `soleur-ai[bot]` | **yes — this fix** |
| `claude-code-review.yml` | same pair | `pull_request` | actor-agnostic — whoever initiated the event (opener on `opened`/`ready_for_review`, the pusher on `synchronize`); `soleur-ai[bot]` when the bot itself is the initiator (measured: #13083's check runs), the human when a human pushes to a bot-authored branch | not today — the workflow is disabled (`scripts/pr-fanout-ledger.txt`); re-enabling it must revisit this input |
| `fix-constraints-stage-a.yml` | same pair | path-filtered `pull_request` + `workflow_dispatch` | actor-agnostic; the agent-step condition is trigger-agnostic — it fires whenever the constraint gate is red and preflight green, on a filtered PR event or a manual `workflow_dispatch` alike — no observed bot-authored instance | not today — latent; if the refusal ever fires it is the same loud error with this same one-line remedy, and an unexercised input is unverifiable surface. Any future edit must mirror the Stage-A template carrier |
| `test-pretooluse-hooks.yml` | same pair | `workflow_dispatch` only, manual-only by design ("avoid recurring API costs"); no in-repo automated dispatcher | human | no |

The four consumers are pinned in lockstep by
`apps/web-platform/test/claude-pin-lockstep.test.ts` (`EXPECTED_CARRIERS`,
`KNOWN_ACTION_PINS`) — the `uses:` line is not touched, so that suite stays
green.

### Community/functional discovery

Skipped by shape: the change is one input on one existing workflow step in
this repository — no community agent or skill overlaps a repo-specific
config fix. (Agent spawn unavailable in this subagent context; the check is
recorded rather than delegated.)

### Open Code-Review Overlap

None — 96 open `code-review` issues scanned for
`.github/workflows/scheduled-machinery-drain.yml` and
`scheduled-machinery-drain.yml`; zero hits.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact —
  the visible symptom is unchanged: the weekly drain keeps dying inside its
  step, `closed=0` persists, and the standing issue #9508 keeps accruing
  BREACH verdicts while the `meta/machinery` pool (363+) keeps growing.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  workflow backlog, not data — a mis-spelled allowlist silently extends the
  status quo; `*` (rejected) would let any external App invoke the agent on
  a public repo with controlled prompts.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI/tooling on the
  operator's own tracker — worst case is the defect persisting, not a new
  user-facing failure.

## Observability

The change repairs a broken observability chain, so the section is emitted
even though the touched file is not in the Phase 2.9 code-class list.

```yaml
liveness_signal:
  what: Weekly floor verdict (MET/BREACH/WAIVED-*) posted to standing issue #9508 + Sentry cron check-in `scheduled-machinery-drain`
  cadence: weekly (Mondays 09:00 UTC) + every manual-trigger run
  alert_target: standing issue #9508 comment; Sentry monitor `scheduled_machinery_drain` (failure_issue_threshold = 1)
  configured_in: .github/workflows/scheduled-machinery-drain.yml (`Enforce the closing floor`, `Update the standing measurement issue`, `Sentry heartbeat` steps)

error_reporting:
  destination: standing issue #9508 (verdict comment, `if: always()`) and the workflow run log
  fail_loud: a `BREACH: closed=…` verdict comment on #9508; the drain step's own log line `Workflow initiated by non-human actor` if the refusal recurs

failure_modes:
  - mode: actor refusal recurs (typo/drift in `allowed_bots`)
    detection: in-surface — the drain step log prints `Workflow initiated by non-human actor`; the floor then emits `BREACH: closed=0` to #9508 the same week
    alert_route: standing issue #9508 comment + Sentry heartbeat `error` status
  - mode: drain runs but closes fewer than floor
    detection: `closed` is a measured delta (`pre` count vs post count), never self-reported by the agent
    alert_route: `BREACH` verdict on #9508
  - mode: scheduler dead (Inngest function fails to dispatch)
    detection: Sentry cron monitor misses its weekly check-in
    alert_route: Sentry monitor `scheduled_machinery_drain`

logs:
  where: GitHub Actions run log (`gh run view <id> --log`); verdict heredoc on #9508
  retention: GitHub-hosted run retention; standing issue is permanent

discoverability_test:
  command: curl -sS "https://api.github.com/repos/jikig-ai/soleur/issues/9508/comments?per_page=1" | jq -r '.[0].body'
  expected_output: Machinery drain outcome
```

## Implementation

### Files to Edit

- `.github/workflows/scheduled-machinery-drain.yml` — one input added to the
  `with:` block of the `Drain the machinery ledger` step, immediately after
  `anthropic_api_key:` (the other authorization-shaped input), before the
  `prompt:`/`claude_args:` block. An explanatory comment precedes it,
  matching this file's convention of multi-line `#` comments that record
  the measured "why" (see the `id-token: write` and `--headless` comments
  for the model):

```yaml
      - name: Drain the machinery ledger
        id: drain
        continue-on-error: true
        uses: anthropics/claude-code-action@3b7e1a45ca6f231c62605aabcf79e6a41b08c7da # v1.0.263
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          # The weekly dispatch comes from Inngest (cron-machinery-drain.ts)
          # through a GitHub App installation token, so the run's github.actor
          # -- what the action's actor gate reads -- is soleur-ai[bot], and
          # the gate refused it on every weekly run since 2026-10-12 (#13095,
          # recurrence after the id-token fix #9537). The explicit login,
          # never '*': the repo is public and the action's own allowed_bots
          # doc warns that '*' lets any external App invoke it with prompts
          # it controls. isAllowedBot strips a trailing '[bot]' on both
          # sides, so either spelling matches; the [bot] form is the login
          # GitHub reports.
          allowed_bots: "soleur-ai[bot]"
          # `--headless` is load-bearing, not decoration: ...
          prompt: '/soleur:drain-labeled-backlog --label meta/machinery --headless'
          claude_args: '--model claude-sonnet-5-5'
```

### Files to Create

None.

### Out of scope (deliberate)

- `continue-on-error: true` on the step stays (masking semantics are a
  separate design question; the floor verdict is the designed reporter).
- No edit to `test-pretooluse-hooks.yml` / `fix-constraints-stage-a.yml` /
  `claude-code-review.yml` (human-actor triggers — audit table above).
- No `github_token:` input (OIDC path resolved by #9537).
- No pin/version bump (`uses:` line untouched; `claude-pin-lockstep.test.ts`
  pins it).

## CI Gates and Hooks that fire on this diff

Pre-commit (lefthook, `lefthook.yml`):

- `scheduled-show-full-output-lint` (glob `.github/workflows/scheduled-*.yml`)
  — runs `scripts/lint-scheduled-show-full-output.sh`; fires on this file.
  Passes: `show_full_output` is not added.
- `gitleaks-staged` — scans the staged index; `allowed_bots` is not a secret.
- `markdown-lint` — fires on this plan and `tasks.md`.
- `lint-infra-no-human-steps` — scans `knowledge-base/project/plans/*.md`
  and `specs/**/*.md` for actor+infra-imperative co-occurrence; the
  verification prose below contains no imperative tokens.

PreToolUse (Claude Code; advisory in this harness):

- `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` — allows: the file
  exists on `origin/main` (edit arm), and the diff adds no `schedule:`/
  `cron:` key.

CI (PR checks):

- `actionlint` job (pinned + sha-verified in `ci.yml`) — validates workflow
  syntax and step shape. `allowed_bots` is a declared input of the action at
  v1.0.263, so the step is well-formed.
- `test` context — `plugins/soleur/test/machinery-drain-floor.test.sh`
  (derives `MACHINERY_DRAIN_CLOSING_FLOOR` from this file; untouched),
  `plugins/soleur/test/claude-code-action-auth.test.sh` (per-step token
  census; the job keeps `id-token: write`),
  `apps/web-platform/test/claude-pin-lockstep.test.ts` (this file is an
  `EXPECTED_CARRIERS` member via `scripts/lib/test-affected-paths.sh:517`;
  the `uses:` SHA→tag pair is unchanged).
- `lint-infra-no-human-steps` equivalent CI coverage for the plan artifacts.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add `allowed_bots: \"soleur-ai[bot]\"` to the `with:` block of the `Drain the machinery ledger` step in `.github/workflows/scheduled-machinery-drain.yml`." [issue #13095] | Implementation / Files-to-Edit entry | mapped |
| 2 | "prefer the explicit login over `*`" [issue #13095] | `allowed_bots: "soleur-ai[bot]"` literal + comment rationale | mapped |
| 3 | "Sibling `claude-code-action` consumers audited — none need it" [issue #13095] | Sibling consumer audit table (verified independently) | mapped |
| 4 | "Next weekly dispatch (or a manual `gh workflow run scheduled-machinery-drain.yml` post-merge) completes the drain step without the actor refusal." [issue #13095] | Post-Merge Verification + AC3 | mapped |
| 5 | "`closed > 0` machinery issues on that run (or a reported outcome naming a different, diagnosed failure)." [issue #13095] | AC4 | mapped |
| 6 | "Standing issue #9508 stops accruing weekly BREACH verdicts." [issue #13095] | AC5 + Observability liveness_signal | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `allowed_bots: "soleur-ai[bot]"` in the `with:` block | "Add `allowed_bots: \"soleur-ai[bot]\"` to the `with:` block of the `Drain the machinery ledger` step" | asked |
| explanatory comment on the new input | — | inferred — justification: the file's own convention (every non-obvious input carries a measured-why comment); a bare key would be the only uncommented input in the block |
| sibling-consumer audit section | "Sibling `claude-code-action` consumers audited — none need it" | asked |
| post-merge bot-path verification step | "Next weekly dispatch (or a manual `gh workflow run scheduled-machinery-drain.yml` post-merge) completes the drain step without the actor refusal" | asked |
| `trigger.sh` / trigger-cron variant of the verification | — | inferred — justification: a human `gh workflow run` passes the actor gate trivially and cannot exercise `allowed_bots`; the Inngest manual trigger is the only on-demand bot-actor path (CTO ruling in decision-challenges.md) |

### Split Assessment

- Subsystems touched: 1 — `.github`
- Planned files: 1 | Estimated changed lines: ~10 (one input + comment)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

Split per the post-merge-operator-steps sharp edge: AC1/AC2/AC6 are
checkable inside the PR; AC3/AC4/AC5 are intrinsically post-merge
(workflow-file-on-default-branch validation — see Post-Merge
Verification).

### Pre-merge (PR)

- [ ] AC1 — `.github/workflows/scheduled-machinery-drain.yml` carries
      `allowed_bots: "soleur-ai[bot]"` in the `with:` block of the `Drain
      the machinery ledger` step, preceded by an explanatory comment.
- [ ] AC2 — The diff is confined to that `with:` block: `uses:` pin,
      `prompt`, `claude_args`, `continue-on-error`, permissions and every
      other step are byte-identical.
- [ ] AC6 — `bash plugins/soleur/test/machinery-drain-floor.test.sh`,
      `bash plugins/soleur/test/claude-code-action-auth.test.sh`, and
      `bun test apps/web-platform/test/claude-pin-lockstep.test.ts` all
      green locally before push; `actionlint` and the required `test`
      context green on the PR.

### Post-merge

- [ ] AC3 — Post-merge, a bot-actor run of the workflow shows the drain
      step's log free of `Workflow initiated by non-human actor` — read
      the step log (`gh run view <id> --log` or the step-level API), never
      the run `conclusion` (`continue-on-error` makes it vacuous).
- [ ] AC4 — That run reports `closed > 0` machinery issues, or a floor
      verdict naming a different diagnosed failure (the verdict names the
      cause either way).
- [ ] AC5 — The run's verdict lands as a comment on standing issue #9508.

## Post-Merge Verification

The acceptance is intrinsically post-merge: `claude-code-action` refuses to
run the agent when the dispatched workflow file differs from default-branch
content, so a branch dispatch is skip-masked and proves nothing
(learning 2026-10-05 / 2026-11-05).

Verification paths, ranked:

1. **Weekly dispatch (zero-authorization default).** The next Monday 09:00
   UTC Inngest dispatch exercises the bot-actor path automatically. Poll:

   ```bash
   gh run list --workflow=scheduled-machinery-drain.yml --limit 3
   gh run view <run-id> --log | grep -n "non-human actor\|Drain the machinery"
   ```

   Success = the drain step log has no refusal line and the floor posts a
   verdict to #9508.

2. **On-demand bot-actor dispatch (accelerated; production-mutating).**
   `cron/machinery-drain.manual-trigger` is allowlisted
   (`EXPECTED_CRON_FUNCTIONS`, `apps/web-platform/server/inngest/cron-manifest.ts`)
   and routes through the same dispatcher code path as the weekly cron —
   the resulting workflow run's actor is `soleur-ai[bot]`:

   ```bash
   plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
     --event cron/machinery-drain.manual-trigger
   ```

   This fires the real drain early — it closes `meta/machinery` issues and
   may open PRs. It is outside `ship`'s delegable command grammar, so it is
   an operator-class hold; the default is path 1.

3. **Human `gh workflow run` (supplementary only).** A human-dispatched run
   passes the actor gate trivially — it CANNOT prove `allowed_bots` works,
   but it does exercise the drain pipeline end-to-end on a surface whose
   only completed execution (the 2026-10-05 human verification run) still
   ended `closed=0` (useful secondary evidence if path 1 is slow):

   ```bash
   gh workflow run scheduled-machinery-drain.yml
   ```

   Delegable under `ship`'s production-envelope grammar.

   Caveat (CTO-ruled, recorded in decision-challenges.md): do not read a
   green human-dispatch run as allowlist verification.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The
semantic sweep against all eight assessment questions resolves every domain
below its relevance bar: one input on one existing CI step, no user-facing
surface (Product/UX mechanical override does not fire — no UI-surface files),
no vendor/procurement (Operations), no legal artifact or regulated-data
surface (Legal), no content/messaging (Marketing), no financial surface
(Finance), no pipeline/revenue surface (Sales), no support workflow
(Support), and below the "significant architectural … beyond normal
implementation" bar (Engineering — the fix direction is fixed by the issue
and verified against the action's own `action.yml`).

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed) in
frontmatter; the actual fan-out was scoped by the semantic sweep.

## Test Scenarios

- Given the workflow file edited, when `python3 -c 'import yaml,sys;
  yaml.safe_load(open(".github/workflows/scheduled-machinery-drain.yml"))'`
  runs, then it parses clean and the step's `with:` mapping contains
  `allowed_bots == "soleur-ai[bot]"`. (unit — YAML validity + key presence)
- Given the edited file, when
  `bash plugins/soleur/test/machinery-drain-floor.test.sh` runs, then the
  floor derivation still succeeds (the `env:` block is untouched).
  (integration — suite green)
- Given the edited file, when
  `bash plugins/soleur/test/claude-code-action-auth.test.sh` runs, then the
  per-step token census still resolves the drain step via job-level
  `id-token: write`. (integration — suite green)
- Given the edited file, when
  `bun test apps/web-platform/test/claude-pin-lockstep.test.ts` runs, then
  the SHA→tag pair still verifies (the `uses:` line is untouched).
  (integration — suite green)
- Given the edited file, when
  `bash scripts/lint-scheduled-show-full-output.sh
  .github/workflows/scheduled-machinery-drain.yml` runs, then it passes
  (`show_full_output` absent). (unit — lefthook gate locally)
- Given a merged PR, when the next weekly (or manual-trigger) dispatch runs,
  then the `Drain the machinery ledger` step's log contains no
  `Workflow initiated by non-human actor` line and the floor posts a verdict
  comment to #9508. (e2e — the load-bearing acceptance; post-merge by
  construction)

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| `allowed_bots: "soleur-ai[bot]"` | adopted | issue's fix direction; explicit login; verified input at v1.0.263 |
| `allowed_bots: "*"` | rejected | the action's own doc warns `*` lets any external App invoke it with controlled prompts on a public repo |
| `allowed_bots: "soleur-ai"` (no `[bot]`) | rejected | `isAllowedBot` strips a trailing `[bot]` on both sides, so both spellings work; the `[bot]` form is the login GitHub reports — precision over abbreviation |
| dispatch as a human / PAT instead of the App | rejected | changes the dispatch substrate, not the actor gate; out of ask and out of the Inngest-dispatcher design (ADR-033) |
| remove `continue-on-error` so the step goes red | descoped | the floor verdict → #9508 channel is the designed reporter; masking semantics are a separate design question |
| run the drain inside the Inngest function | rejected | agent pipelines cannot run in the Inngest runtime — that is why the dispatcher exists (`cron-machinery-drain.ts` header) |

## Review-added scope (round 1)

`cron-machinery-drain.ts` now mints its installation token narrowed to
`permissions: { actions: "write" }` + `repositories: [REPO_NAME]`, mirroring
the production-proven sibling dispatchers (`cron-actions-queue-health-dispatch`,
`cron-supabase-watchdog-dispatch`, `cron-merge-queue-stall-dispatch`). Origin:
security-sentinel's pre-existing hardening note → CONCUR gate DISSENT with
evidence (sibling precedent + separable failure surfaces) → cost-of-filing
auto-flip to fix-inline. The failure surfaces are separable: a bad narrowed
token fails in Inngest before any workflow run exists; an allowlist failure
occurs inside the dispatched step — the post-merge verification in §Post-Merge
Verification is unconfounded.

## Context

- Pool trajectory (issue): 16 → **363** open `meta/machinery` issues since
  2026-09-14; nine weekly BREACH runs 2026-09-21 → 2026-11-23 (no 2026-11-02
  dispatch — the sequence is not consecutive; the first two verdicts landed
  on the duplicate standing issues #8482/#9132 before #9508 existed, the
  rest on #9508).
- The pool queues epic #11556 items #12885 and #12905 — the "as scheduled"
  path is dead until this lands.
- `closes: 13095` is in frontmatter; the issue auto-closes on merge while
  AC3/AC4/AC5 remain post-merge evidence — the verification continues
  post-merge regardless (see Post-Merge Verification; the weekly path
  requires no authorization).

## References

- Issue: #13095 (fix direction + measured evidence); standing issue #9508;
  prior fix #9537; epic #11556; queued items #12885, #12905.
- Action input verified:
  `https://raw.githubusercontent.com/anthropics/claude-code-action/v1.0.263/action.yml`
  (`allowed_bots` declared input; retrieved 2026-11-27).
- Dispatcher:
  `apps/web-platform/server/inngest/functions/cron-machinery-drain.ts`.
- Trigger route runbook:
  `knowledge-base/engineering/operations/runbooks/inngest-server.md`
  (§On-demand cron trigger).
- Learnings:
  `2026-10-05-the-drain-was-born-broken-and-the-waiver-hid-it.md`,
  `2026-11-05-a-branch-dispatch-of-the-workflow-you-edited-is-skip-masked-and-a-tokenised-allowlist-is-split-on-spaces.md`,
  `2026-08-05-i-built-a-cadence-on-a-bot-that-never-ran-and-my-battery-certified-the-gate.md`.

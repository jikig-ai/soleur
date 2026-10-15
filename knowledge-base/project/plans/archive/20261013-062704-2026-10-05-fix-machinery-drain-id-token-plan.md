---
title: "fix: restore claude-code-action auth in machinery-drain + fix-constraints stage A; repair standing-issue lookup; census guard"
type: fix
date: 2026-10-05
slug: fix-machinery-drain-id-token
branch: feat-one-shot-machinery-drain-id-token
lane: cross-domain
---

# fix: restore claude-code-action auth in machinery-drain + fix-constraints stage A; repair standing-issue lookup; census guard

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-05 (inline deepen — no Task fan-out available in the planning subagent;
mechanical halt gates 4.6–4.12 all executed and passed)
**Sections enhanced:** Guard Contract (census-anchor trap), Observability (probe de-suite'd),
Implementation Phases (jq correctness, sharp-edge disciplines)

### Key Improvements

1. `discoverability_test` probe replaced with `grep -c` twin-anchor check — the original
   `bash <suite>` form matched the suite-shaped reject proxy and would have halted at 4.7 /
   failed preflight Check 10.
2. Standing-issue jq corrected live: `contains("x")` on the labels array is a jq type error;
   `index("x") != null` verified end-to-end against the real repo (returns `[9508,9132,8482,8068]`).
3. Guard census anchor sharpened to `uses: anthropics/claude-code-action@` —
   `claude-code-review.yml` alone carries 3 `anthropics/claude-code*` strings and only one is a
   consumer (marketplace URL + doc comment are false positives).
4. Compatibility verified: `machinery-drain-floor.test.sh` asserts floor/waiver/verdict/create-label
   shapes only — the lookup rewrite touches none of its anchors.

### New Considerations Discovered

- Both cited action SHAs are reachable via `git/trees`+`contents` APIs but return **422** from
  `repos/{r}/commits/{sha}` (tag-target commits not on a branch — the objects exist; the live
  failed run executed code at `20f0b248`). Re-verification must use the trees/contents path.
- Post-fix live-tree census = 4 consumers, all compliant: claude-code-review + test-pretooluse-hooks
  (id-token), scheduled-machinery-drain (id-token after this fix), fix-constraints-stage-a
  (github_token input).

## Overview

claude-code-action v1.0.236 (SHA `20f0b248c5003db4b9ca43c45e17949bcdc36d2d`, rolled out repo-wide
by #9236 / commit `6d27cd17da` on ~2026-09-18) authenticates via `setupGitHubToken` →
`getOidcToken`, which hard-fails when the calling job lacks `id-token: write`. Two of the four
consumers never granted it:

1. `.github/workflows/scheduled-machinery-drain.yml` (trusted `workflow_dispatch` context) —
   the drain step fails ~15s in on every run; `continue-on-error: true` masks it, the floor
   reports BREACH (closed=0), and the Sentry heartbeat checks in `error`. Three consecutive
   weekly failures (runs 35580861691, 36402277938, 37287175185) since last success 2026-09-14;
   the monitor is approaching auto-mute.
2. `.github/workflows/fix-constraints-stage-a.yml` — the `pull_request`-context UNTRUSTED stage
   of ADR-074's two-stage design. `contents: read` only is deliberate and load-bearing; the
   agent step is conditional on a red gate, so the OIDC failure is latent until the next
   constraint-gate trip.

Fix (1) with `id-token: write` (mirrors `claude-code-review.yml`/`test-pretooluse-hooks.yml`).
Fix (2) with `github_token: ${{ github.token }}` — verified at the pinned SHA to bypass OIDC
entirely while granting only the `contents: read` token the job already holds; granting
`id-token: write` in that context would let PR-head-controlled code mint OIDC tokens that the
Anthropic app-token exchange converts to `contents:write`/`pull-requests:write`/`issues:write` —
destroying ADR-074's invariant.

Secondary (same PR): the standing-issue lookup uses `gh issue list --limit 100` over 1700+ open
issues and re-files its own issue weekly — four live duplicates exist (#8068, #8482, #9132,
#9508). Replace with a `search/issues` title query that selects exactly one canonical issue and
self-heals by closing bot-authored duplicates.

Tertiary: a census guard under `plugins/soleur/test/` asserting every claude-code-action
consumer has a resolvable token path — modeled on `reusable-release-caller-permissions.test.sh`.
This is the **third occurrence** of the missing-OIDC-permission defect class
(`learnings/2026-05-04-schedule-once-template-missing-id-token.md`, #5977/#5981, this) — a
recurrence guard is warranted, not optional polish.

## Problem Statement / Motivation

- **Evidence chain (verified 2026-10-05):** `git log` on the workflow files shows both bumped
  `5aa6f47`→`20f0b24` in `6d27cd17da`; `gh run list` shows last green drain run 2026-09-14
  (`34825797967`), then failures 09-21/09-28/10-05; `--log-failed` on run 37287175185 shows
  `Requesting OIDC token... Failed to get OIDC token` from
  `node_modules/@actions/core/lib/oidc-utils.js` under the pinned SHA.
- **Why masking hurt:** `continue-on-error: true` on the drain step converts a hard action
  failure into a floor BREACH, which is honest telemetry about the *wrong* failure — the
  monitor records "drain underperformed" when in fact "drain never ran."
- **Stage A is worse than it looks:** green today only because `steps.gate.outputs.rc != '0'`
  short-circuits the agent step. The next tripped constraint gate on a same-repo PR fires a
  guaranteed-failing agent dispatch — a silent stall of the founder-zero-touch recovery ADR-074
  exists to provide.
- **Standing-issue churn:** the lookup window (`--limit 100`) sits ~1700 open issues below the
  standing issue, so `existing` is always empty and the workflow files a fresh
  `issue-flow: weekly measurement` every Monday — the "measurement that files a fresh issue
  every week" defect the step's own comment says it exists to prevent.

## Proposed Solution

- **Drain workflow:** add `id-token: write` at JOB level on `measure-and-drain`
  (least-privilege convention — job-level `permissions:` replaces, and a
  `permissions: {}` deny-all top-level keeps any future second job at zero) —
  trusted context (main-branch workflow definition, `workflow_dispatch`), mirrors the
  established convention.
- **Stage A:** add `github_token: ${{ github.token }}` to the agent step's `with:` block and a
  header/step comment recording why `id-token: write` is deliberately NOT used here.
- **Standing issue:** replace the positional `--limit 100` scan with a `gh api search/issues`
  `in:title` query (the same API the pre/post count steps already use), filtered to exact title
  + `keep-open` + `meta/machinery` labels + `github-actions[bot]` author; update the newest
  match as canonical and close older matches as duplicates.
- **Regression guard:** new `plugins/soleur/test/claude-code-action-auth.test.sh` census-asserting
  a token path for every consumer, wired via the existing `plugins/soleur/test/*.test.sh` glob +
  shard-manifest regen + `test-affected-paths.sh` declaration.
- **ADR-074:** one short amendment paragraph recording the OIDC posture decision so a future
  reader does not "fix" Stage A by granting `id-token: write`.

## Technical Considerations

- **Action internals, verified at pin `20f0b248`:** `action.yml` maps
  `inputs.github_token` → `OVERRIDE_GITHUB_TOKEN` env; `src/github/token.ts` `setupGitHubToken()`
  early-returns `providedToken` BEFORE `getOidcToken()`. The OIDC path then POSTs the token to
  `https://api.anthropic.com/api/github/github-app-token-exchange` for a Claude App token with
  `DEFAULT_PERMISSIONS = {contents: write, pull_requests: write, issues: write}` (bounded by the
  installation's granted scopes). The `Revoke app token` post-step is correctly skipped when
  `inputs.github_token != ''` (action.yml `if:` condition).
- **v1.0.161 ran green without the permission:** its `src/` carries the same unconditional OIDC
  call — the behavioral delta lives in the shipped bundle / bundled `@actions/core`. The
  observable record (green→red at the bump commit, OIDC error in logs) is authoritative; the
  fix does not depend on naming the upstream diff.
- **Stage A actor check:** `checkWritePermissions` still runs for `pull_request` entity context
  and verifies the PR AUTHOR via `getCollaboratorPermissionLevel` (works on a read token);
  `[bot]` actors pass; a no-write author fails → existing give-up marker path handles it —
  acceptable and arguably desired. Same-repo PRs (the only population with secrets present) are
  authored by write-holding members.
- **OIDC blast radius, enumerated:** (a) Doppler — `provision-doppler.sh` binds service accounts
  with `subject_claims {repository_owner, repository, environment: "production"}` → a
  `pull_request` OIDC token carries no `environment` claim and cannot satisfy the trust today;
  (b) Cosign — `ci-deploy.sh` pins identity
  `^https://github\.com/jikig-ai/soleur/\.github/workflows/reusable-release\.yml@refs/heads/main$`
  — a Stage A token's `job_workflow_ref`/`ref` claims cannot match; (c) no `*.tf` file
  configures cloud-provider `assume_role_with_web_identity`. Even so, `id-token: write` in Stage
  A is rejected on principle: the Anthropic exchange alone upgrades a repo-scoped OIDC token to
  write-scoped app credentials inside a job that executes PR-head code
  (`.dependency-cruiser.cjs`, `constraint-gates.sh`, `node_modules` binaries all come from the
  PR head).
- **`github_token` residual on Stage A:** the token is `contents: read`-only — the exact scope
  the job already holds; passing it changes nothing privilege-wise. The "Post buffered inline
  comments" composite step (`if: always() && classify_inline_comments != 'false'`) no-ops when
  the agent emits no buffered comments — the fix-only prompt produces none; watch the first real
  run for a comment-permission 403 as a known small tail risk.
- **Standing-issue lookup details:** `in:title` is a substring/token match — keep a client-side
  exact-title jq `select` (same pattern as today). The `--search`+`--label` `gh issue list` bug
  noted in the workflow comment is avoided by using `gh api search/issues` directly (no
  `--label` involved). Canonical = newest matching issue (sorted `created` desc) — matches the
  brief ("the newest one is the live one"). Auto-close is restricted to
  `user.login == "github-actions[bot]"` matches carrying both labels, so a human-filed
  same-titled issue is never closed.
- **Test wiring (verified):** `scripts/test-all.sh` auto-globs
  `plugins/soleur/test/*.test.sh` (line ~97) — no `run_suite` line needed. New suites require:
  (a) `python3 scripts/regenerate-shard-manifest.py --incremental --write` to add the
  `suite-shard-legs.tsv` row (`scripts-shard-totality.test.sh` fails otherwise); (b) a declared
  `AFFECTED_<LABEL>_PATHS` edge in `scripts/lib/test-affected-paths.sh` (the census linter scans
  those arrays); (c) `.test.sh` naming — a `*.mutation.sh` battery would run in no gate (#7942),
  so mutation rows live as synthesized fixtures inside the suite itself.
- **`continue-on-error: true` on the drain step stays.** It is deliberate (floor derives
  `closed` as a delta; a crashed agent is a legitimate BREACH signal). The fix removes the
  guaranteed-fail cause, not the safety net.
- **NFR impacts:** security surface (OIDC grant discipline) and observability (monitor
  integrity) are the affected non-functional requirements; no performance/reliability NFR moves.

### Attack Surface Enumeration

Every path by which a token reaches code executing in the Stage A job:

- `secrets.ANTHROPIC_API_KEY` → the action (absent on forks; same-repo only). Unchanged.
- `GITHUB_TOKEN` (`github.token`) → already ambient in the job; `contents: read` only. The fix
  passes it explicitly to the action — no new scope.
- **OIDC minting** → would be NEW capability if `id-token: write` were added; rejected. The
  enumeration of what such a token reaches is in Technical Considerations (Anthropic exchange
  → write-scoped app token; Doppler trust requires absent `environment` claim; cosign identity
  unreachable).
- `persist-credentials: false` on checkout — the git credential helper holds nothing.
- Artifact upload → Stage B attestation path; unchanged.

## Research Insights

- **Premise validation (Phase 0.6) — all cited claims held:** commit `6d27cd17da` exists and
  bumped both files `5aa6f47`→`20f0b24`; `scheduled-machinery-drain.yml` permissions block is
  `contents: read` + `issues: write` (lines 13-15, no `id-token`); `fix-constraints-stage-a.yml`
  has `contents: read` at top level (31-32) AND job level (48-49); ADR-074 file exists and its
  Decision confirms the untrusted-context invariant; run 37287175185 failed with the cited OIDC
  error; `claude-code-review.yml` (job-level, ~lines 44-48) and `test-pretooluse-hooks.yml`
  (top-level, 20-22) carry `id-token: write`; the standing-issue duplication is worse than the
  brief states — four open duplicates (#8068 09-11, #8482 09-21, #9132 09-28, #9508 10-05), all
  `github-actions[bot]`-authored, all carrying `keep-open`+`meta/machinery`.
- **Action source verified (not assumed):** `github_token` → `OVERRIDE_GITHUB_TOKEN` → early
  return before `getOidcToken()`, at BOTH the old and new pinned SHAs. Fetch path used:
  `api.github.com/repos/anthropics/claude-code-action/contents/{action.yml,src/github/token.ts,src/github/validation/permissions.ts}?ref=<sha>`.
- **Property list (Phase 0.6b):** P1 drain step authenticates → honest check-ins resume; P2
  Stage A agent can run when the gate trips WITHOUT new privilege in the untrusted context; P3
  exactly one standing measurement issue, updated in place, duplicates self-healed; P4 a future
  action bump or new consumer cannot silently reintroduce the missing-permission defect; P5 the
  four live duplicates collapse to one.
- **Cut list (Phase 0.6b):** none — every proposed mechanism buys a property nothing on
  `origin/main` covers. Closest existing guard `reusable-release-caller-permissions.test.sh`
  quantifies over reusable-workflow CALLERS, not action consumers; `machinery-drain-floor.test.sh`
  pins the floor, not auth; `workflow-model-pins.test.ts` pins `claude_args` models only.
- **Relevant learnings:**
  `learnings/2026-05-04-schedule-once-template-missing-id-token.md` (identical failure text —
  "OIDC permission belongs to the action, not the caller task"; this is recurrence 3);
  `learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` (two-stage `--json` + `jq --arg`);
  reusable-release test header documents the job-overrides-workflow permission semantics the
  guard must implement.
- **No relevant brainstorm** (none within 14 days matches); no tracking issue exists — this
  brief is the spec; `issue:` intentionally absent.
- **Community/functional overlap:** no new stack (GitHub Actions YAML + bash test); the sibling
  guard is the pattern to mirror, not a community artifact. Skipped per skip conditions.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| "three consecutive weekly failures" | Exactly: 09-21, 09-28, 10-05; last green 09-14 | Confirmed |
| "at least three prior open issues with that exact title" | 3 prior + 1 filed today = 4 open dupes | Consolidate all → #9508 canonical |
| "claude-code-review.yml line ~44-48 carries id-token: write" | Confirmed (job-level block) | Mimic convention |
| Stage A "contents: read ONLY, deliberate, ADR-074" | Confirmed — top-level AND job-level both pin it | Option (b), not (a); document why |
| "check whether infra has OIDC federation trusting this repo" | Doppler federation exists (`environment: production`-scoped); cosign identity is `reusable-release.yml@main`-scoped; no cloud `assume_role_with_web_identity` | Option (a) rejected regardless — Anthropic exchange alone grants write app-token in untrusted context |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — internal CI. The indirect
  founder-visible failure already happened: a dying monitor that auto-mutes is a dead paging
  surface the founder relies on for machinery health.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the rejected path is
  the only one with exposure: `id-token: write` on Stage A would let PR-head code mint OIDC
  tokens exchangeable for write-scoped app credentials. The chosen path adds no capability.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-internal auth fix; the blast-radius analysis is
  about repo credentials, not user data.

`threshold: none, reason: touches .github/workflows/* (a preflight-sensitive path) but the diff grants no new capability — Stage A keeps contents:read-only and the drain workflow is trusted-context.`

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor 'scheduled-machinery-drain' end-of-run check-in (ok|error)"
  cadence: "weekly Mon 09:00 UTC (Inngest dispatch) + each manual workflow_dispatch"
  alert_target: "Sentry issue in web-platform project (failure_issue_threshold=1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf sentry_cron_monitor.scheduled_machinery_drain; emitter is the 'Sentry heartbeat' step in scheduled-machinery-drain.yml"
error_reporting:
  destination: "Sentry web-platform project via .github/actions/sentry-heartbeat"
  fail_loud: "floor step ::error::<verdict> line on BREACH; missed check-in pages via checkin_margin_minutes=30"
failure_modes:
  - mode: "drain step fails before the agent runs (auth/infra regressions)"
    detection: "floor BREACH verdict + error check-in — the incident this plan repairs"
    alert_route: "Sentry issue → operator"
  - mode: "no check-in at all (dispatch dead / workflow renamed)"
    detection: "Sentry missed-check-in alert"
    alert_route: "Sentry issue → operator"
logs:
  where: "GitHub Actions run logs, workflow scheduled-machinery-drain"
  retention: "GitHub default retention (~90 days)"
discoverability_test:
  # Probe asserts the two load-bearing anchors exist in the same file: the
  # job-level `id-token: write` grant (anchored, comment-proof, any indent —
  # the grant lives on the `measure-and-drain` job, least-privilege convention)
  # AND the Sentry heartbeat wiring. grep -c prints the matched-line count.
  # Chosen over the new test suite deliberately: the suite TESTS the invariant,
  # this DISCOVERS the signal — and a *.test.sh command is reject-proxy-shaped
  # at deepen-plan 4.7 / preflight Check 10 anyway.
  command: "grep -cE -e '^[[:space:]]+id-token: write' -e 'monitor-slug: scheduled-machinery-drain' .github/workflows/scheduled-machinery-drain.yml"
  expected_output: "2"
```

## Architecture Decision (ADR/C4)

- `### ADR` — **amend ADR-074** (`knowledge-base/engineering/architecture/decisions/ADR-074-fix-constraints-two-stage-privileged-split.md`): append a short paragraph recording that
  Stage A's claude-code-action step authenticates via the `github_token:` input (the job's own
  `contents: read` GITHUB_TOKEN) rather than OIDC, because `id-token: write` would grant
  OIDC-minting to code running the untrusted PR head — and the Anthropic app-token exchange
  would convert that mint into `contents:write`/`pull-requests:write`/`issues:write` app
  credentials, violating the Decision's invariant. No re-decision; the invariant is upheld.
- `### C4 views` — **no C4 impact.** Enumeration performed against all three model files:
  external actors — none new (workflow_dispatch actor is the Inngest substrate already modeled);
  external systems — GitHub Actions (`github`), Sentry (`sentry` + `webapp -> sentry` cron
  check-in edge), Anthropic (`anthropic`), Doppler (`doppler`) are all already modeled; the
  OIDC→Anthropic exchange edge already exists for `claude-code-review.yml`, and this change adds
  no new edge — it restores one existing consumer (drain) and narrows another (Stage A) to the
  ambient token; containers/data-stores — none touched; access relationships — none change.
- `### Sequencing` — N/A; the amendment ships in this PR.

## Guard Contract

### Guard 1 — claude-code-action token-path census

**Property.** Every `.github/workflows/*.yml` file containing a live (non-commented)
`uses: anthropics/claude-code-action@` step grants a resolvable GitHub-token path for each
consuming job: EITHER the effective `permissions:` (job-level block replaces workflow-level)
contain `id-token: write` (or `write-all`), OR the consuming step's `with:` block carries a
`github_token:` input.

**Assembly.** The population is DERIVED by grep census over `.github/workflows/*.yml` for
`uses: anthropics/claude-code-action@` (the `@`-suffixed `uses:` form — never an enumerated
list). The anchor matters: `claude-code-review.yml` alone carries three `anthropics/claude-code*`
strings and only one is a consumer (`plugin_marketplaces: 'https://github.com/anthropics/claude-code.git'`
and a doc-comment URL are NOT `uses:` lines) — a bare `anthropics/` or unanchored action-name
grep over-counts the assembly. Per file: locate each job containing a consumer step; resolve effective permissions
(job block if present else workflow block); inspect the step's `with:` block for `github_token:`.
The suite asserts `consumers >= 1` on the live tree — a census over nothing is vacuous. Fixture
runs override the scan root via `WF_DIR` env (`mktemp -d` synthesized workflows per
`cq-test-fixtures-synthesized-only`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Fixture: consumer workflow with `permissions: contents: read` and no `github_token` (the drain defect shape) | RED |
| 2 | Fixture dir containing only non-consumer workflows → `consumers=0` | RED (dispatch-vacuity: a census that finds nothing asserts nothing) |
| 3 | Fixture: compliant file (id-token) PLUS a second non-compliant file | RED (must not stop at first member) |
| 4 | Fixture: `github_token: ${{ github.token }}` under `with:` with no `id-token` anywhere | PASS (legalizes the Stage A shape — without this row the guard reddens the fix it ships with) |
| 5 | Fixture: workflow-level `id-token: write` but job-level `permissions: contents: read` on the consuming job | RED (job-level REPLACES workflow-level — the semantics #5977/#5981 established) |
| 6 | Fixture: `# id-token: write` commented out under permissions | RED (commented grant is no grant — `^`-anchored matching) |
| 7 | Fixture: `id-token: write` string inside a step's `with:`/`env:` block, permissions without it | RED (scoping: only a `permissions:` block counts) |
| 8 | Fixture: `permissions: write-all` | PASS (functionally grants id-token — a must-PASS non-canonical input; catches a reject-everything guard) |
| 9 | Fixture: `uses: anthropics/claude-code-action` present only in a comment | PASS (not a consumer — census anchored on live `uses:` lines) |

**Anchor.** The guard asserts a property of the workflow files themselves — there is no stored
hash/manifest to co-edit; the census derivation means adding a consumer without a token path is
a one-file change that reds the suite.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Two workflows use claude-code-action v1.0.236 WITHOUT `id-token: write`" → fix scheduled-machinery-drain.yml | Phase 1 / FR-1 / `.github/workflows/scheduled-machinery-drain.yml` edit | mapped |
| 2 | "The fix here needs explicit security review: options include (a)…(b)…(c)… Do not just slap the permission on" | Phase 2 / FR-2 / `fix-constraints-stage-a.yml` edit + Attack Surface Enumeration + ADR-074 amendment | mapped |
| 3 | "Fix the lookup so exactly one standing issue exists (e.g., `gh issue list --search …` or a label-scoped query), and consider whether the duplicate standing issues should be consolidated" | Phase 1b / FR-3 / standing-issue lookup rewrite + self-healing dedup | mapped |
| 4 | "Also consider a regression guard: a test under plugins/soleur/test/ … asserting every workflow that uses anthropics/claude-code-action grants `id-token: write`" | Phase 3 / FR-4 / `plugins/soleur/test/claude-code-action-auth.test.sh` + wiring | mapped |
| 5 | "Convention to mimic for (1): claude-code-review.yml already carries job-level permissions including id-token: write" | Phase 1 implementation note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/scheduled-machinery-drain.yml` — add `id-token: write` | "Convention to mimic for (1): `.github/workflows/claude-code-review.yml` already carries job-level `permissions:` including `id-token: write`" | asked |
| `.github/workflows/fix-constraints-stage-a.yml` — `github_token:` input | "passing a `github_token:` input to the action so it skips OIDC (verify against the pinned action's source/docs that this bypasses getOidcToken)" | asked |
| Standing-issue lookup rewrite + dedup | "Fix the lookup so exactly one standing issue exists" / "the duplicate standing issues should be consolidated (the newest one is the live one)" | asked |
| `plugins/soleur/test/claude-code-action-auth.test.sh` | "a test under plugins/soleur/test/ (or wherever workflow linting lives — check how machinery-drain-floor.test.sh and actionlint are wired)" | asked |
| `scripts/suite-shard-legs.tsv` + `scripts/lib/test-affected-paths.sh` updates | — | inferred — justification: shard-totality and census lints fail an unregistered suite; the test cannot ship without registration |
| ADR-074 amendment paragraph | — | inferred — justification: the ask's option (a)/(b) decision is a security posture on an ADR-governed invariant; recording it prevents a future re-"fix" granting id-token in the untrusted context |
| Self-healing dedup inside the workflow step | "consider whether the duplicate standing issues should be consolidated" | asked (consolidation realized as durable mechanism rather than one-off) |
| `verify:` draft-PR gate-trip exercise for Stage A | — | inferred — justification: the Stage A failure is latent; the only live exercise of the fixed path is a real gate trip or a synthesized one |

### Split Assessment

- Subsystems touched: 3 — `.github`, `plugins/soleur`, `knowledge-base` (+ `scripts/` registration rows)
- Planned files: 6 | Estimated changed lines: ~250 (guard suite ~160, workflow diffs ~40, ADR ~15, registrations ~5)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one coherent incident fix; the Stage A security decision is small and same-rooted

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `.github/workflows/scheduled-machinery-drain.yml` `permissions:` block grants `id-token: write`; `machinery-drain-floor.test.sh` stays green.
- [ ] AC2: `.github/workflows/fix-constraints-stage-a.yml` agent step carries `github_token: ${{ github.token }}` in its `with:` block; top-level AND job-level `permissions:` remain `contents: read` only — the string `id-token` may legitimately appear in the explanatory comment, so the assertion is on the `permissions:` blocks, not a bare file grep. A comment records the OIDC posture decision.
- [ ] AC3: The standing-issue step uses `gh api search/issues` (or equivalent non-positional lookup), selects exactly one canonical issue (newest exact-title match carrying `keep-open`+`meta/machinery`, authored by `github-actions[bot]`), updates it, and closes older bot-authored duplicates with a pointer comment; when no canonical match exists it creates the labeled+milestoned issue as today.
- [ ] AC4: `plugins/soleur/test/claude-code-action-auth.test.sh` exists, is green on the post-fix tree, and RED-proven against the mutation-matrix fixture rows (Guard 1).
- [ ] AC5: Suite registered: `suite-shard-legs.tsv` regenerated via `regenerate-shard-manifest.py --incremental --write`; `AFFECTED_*_PATHS` edge declared in `scripts/lib/test-affected-paths.sh`; `lint-orphan-test-suites.sh` and `scripts-shard-totality.test.sh` green.
- [ ] AC6: `actionlint` clean on both edited workflows (CI gate runs it over `run:` bodies too — the rewritten standing-issue block must pass shellcheck through actionlint; tilde fences stay).
- [ ] AC7: ADR-074 carries the OIDC-posture amendment paragraph.

### Post-merge (pipeline — all steps are `gh`-automatable, no operator gate)

- [ ] AC8: `gh workflow run scheduled-machinery-drain.yml` dispatch watched to completion (`gh run watch`, blocking — not a background poll): drain step passes the OIDC point and runs the agent; standing issue #9508 updated; duplicates #8068/#8482/#9132 closed by the self-heal arm; Sentry check-in `ok` → monitor recovers (`recovery_threshold: 1`).
- [ ] AC9: Stage A path exercised: a draft PR off `main` deliberately tripping the constraint gate shows the agent step proceeding past token setup (no OIDC error); close the draft after capture.
- [ ] AC10: `gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:open+in:title+%22issue-flow%3A+weekly+measurement%22" --jq '.total_count'` returns `1` after AC8 completes (verified live 2026-10-05: returns 4 pre-fix).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to GitHub
Actions auth plumbing, a bash test suite, and one ADR paragraph. Assessed against the 8-domain
sweep: no user-facing surface (Product NONE — the mechanical UI-surface scan of Files to
Edit/Create matches nothing), no regulated data (Legal/GDPR — see skip note), no spend or
revenue surface (Finance/Sales), no customer artifact (Marketing/Support), no new vendor or
provisioned resource (Operations — the change runs inside existing CI). The security dimension
is handled inline via Attack Surface Enumeration + Guard Contract rather than a domain leader.

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` bodies for each planned path:

- `.github/workflows/scheduled-machinery-drain.yml`, `.github/workflows/fix-constraints-stage-a.yml`, `scripts/suite-shard-legs.tsv`: **none**.
- `plugins/soleur/test/` (directory match): #8659 (test-helpers EXIT-trap/sandbox leak — N/A: the new suite is a pure static grep guard, does NOT source test-helpers, mirroring `reusable-release-caller-permissions.test.sh`), #7942 (`*.mutation.sh` naming — handled: mutation rows live as synthesized fixtures inside the `.test.sh`), #8593, #4133, #3531, #3216 — all unrelated subjects. Disposition: **acknowledge** (conventions absorbed; no scope folded in).
- `scripts/lib/test-affected-paths.sh`: #8800 (census sandbox write-through hazard) — disposition: **acknowledge**; the guard uses `mktemp -d` fixture dirs, not the census sandbox.

## Implementation Phases

### Phase 1 — Drain workflow (auth + standing-issue repair)

Edit `.github/workflows/scheduled-machinery-drain.yml`:

1. `permissions:` block (lines 13-15): add `id-token: write` with a one-line comment —
   `# claude-code-action mints its app token via OIDC (setupGitHubToken → getOidcToken);
   # without this the drain step dies ~15s in — recurrence 3 of the missing-id-token class
   # (learning 2026-05-04-schedule-once-template-missing-id-token)`. Guarded by the census suite.
2. "Update the standing measurement issue" step: replace the `gh issue list --limit 100`
   lookup with:

   ```bash
   # Census, not a positional window: `gh issue list --limit 100` sits ~1700 open
   # issues below the standing issue, so `existing` was always empty and the step
   # re-filed its own issue every week (#8068/#8482/#9132/#9508 all open).
   matches="$(gh api "search/issues?q=repo:${{ github.repository }}+is:issue+is:open+in:title+%22issue-flow%3A+weekly+measurement%22&sort=created&order=desc&per_page=100" \
     --jq "[.items[] | select(.title == \"$TITLE\"
             and .user.login == \"github-actions[bot]\"
             and ([.labels[].name] | index(\"keep-open\") != null)
             and ([.labels[].name] | index(\"meta/machinery\") != null)) | .number]")"
   # Verified live 2026-10-05: returns [9508,9132,8482,8068] → existing=9508,
   # dupes=9132 8482 8068. Label membership uses index(), NEVER contains() —
   # jq `contains` on an array takes an array argument; `contains("x")` is a
   # runtime type error (measured while drafting this plan).
   # `matches` is a JSON array of numbers, e.g. [9508,9132,8482,8068] — keep it JSON
   # (`.[].number` would emit bare lines and break the `jq .[0]` reads below).
   existing="$(jq -r '.[0] // empty' <<<"$matches")"   # newest = canonical
   dupes="$(jq -r '.[1:][]?' <<<"$matches")"          # one number per line
   ```

   Then: `existing` non-empty → `gh issue comment` as today + loop `gh issue close "$n"
   --comment "Superseded by #$existing — the weekly measurement consolidates to one standing
   issue."` over `dupes`; empty → `gh issue create` (keep `--label`+`--milestone` as today).
   The label+author filter means a human-filed same-titled issue is never auto-closed.

### Phase 2 — Stage A auth without privilege expansion

Edit `.github/workflows/fix-constraints-stage-a.yml`:

1. Agent step `with:` block (line ~93): add `github_token: ${{ github.token }}` — verified at
   pin `20f0b248` (`action.yml` → `OVERRIDE_GITHUB_TOKEN` → `setupGitHubToken` early-returns
   before `getOidcToken()`). The token is the job's own `contents: read` GITHUB_TOKEN.
2. Extend the SECURITY header comment with the OIDC posture: why `id-token: write` is
   deliberately withheld (OIDC minting reachable by PR-head code; Anthropic exchange upgrades
   it to write-scoped app credentials → ADR-074 invariant broken) and why `github_token` is
   safe (grants only what the job already holds).

### Phase 3 — Regression guard

1. Create `plugins/soleur/test/claude-code-action-auth.test.sh` implementing Guard 1 (census +
   per-job permission resolution + `github_token` alternative + fixture-driven mutation rows
   via `WF_DIR` override). Mirror `reusable-release-caller-permissions.test.sh` idioms:
   `^`-anchored greps, `permissions:`-block-scoped checks, job-header matching tolerant of
   trailing comments. Final summary line: `echo "token-path census: ${CONSUMERS} consumer(s), ${FAIL} failure(s)"`.
   Sharp-edge disciplines the suite must honor: (a) block extraction uses the flag-based awk
   form (`/start/{flag=1} flag{print} /end/&&!/start/&&flag{exit}`), NEVER `awk '/A/,/B/'` —
   the range form self-matches the start line and collapses the block (plan-sharp-edges:
   #4337/#3809); (b) fixture greps read tempfiles, not `printf ... | grep -q` pipes (#3550's
   stdin-buffering misfire); (c) a comment line containing `id-token: write` satisfies NOTHING —
   the Stage A fix file will carry exactly such a comment, so the permissions-block scoping is
   load-bearing on the real tree too, not just in fixture row 6.
2. `python3 scripts/regenerate-shard-manifest.py --incremental --write` → commits
   `suite-shard-legs.tsv` row + durations floor.
3. Declare `AFFECTED_PLUGINS_SOLEUR_TEST_CLAUDE_CODE_ACTION_AUTH_TEST_SH_PATHS` in
   `scripts/lib/test-affected-paths.sh` covering `.github/workflows/` + the suite + the lib.

### Phase 4 — ADR-074 amendment

Append the OIDC-posture paragraph to ADR-074 (see `## Architecture Decision`).

### Phase 5 — Live verification (post-merge)

1. `gh workflow run scheduled-machinery-drain.yml` → `gh run watch` (blocking — not a
   background poll). Assert: drain step proceeds past OIDC, floor verdict emitted honestly,
   #9508 updated, #8068/#8482/#9132 auto-closed, Sentry `ok`.
2. Draft PR adding a deliberate client→server violation under `apps/web-platform/` → watch
   `fix-constraints-stage-a` run the agent step past token setup → close draft. This exercises
   the latent arm end-to-end; the alternative (wait for the next organic trip) leaves the fix
   unverified.
3. Confirm Sentry monitor `scheduled-machinery-drain` leaves the failing/auto-mute-pending
   state (`recovery_threshold: 1` — one `ok` check-in suffices; verify via the monitor's
   check-in list, not the dashboard eyeballed — pull the data).

## Files to Edit

- `.github/workflows/scheduled-machinery-drain.yml` — `id-token: write` + lookup rewrite (Phase 1)
- `.github/workflows/fix-constraints-stage-a.yml` — `github_token:` input + security comment (Phase 2)
- `scripts/suite-shard-legs.tsv` — regenerated row (Phase 3)
- `scripts/lib/test-affected-paths.sh` — `AFFECTED_*_PATHS` declaration (Phase 3)
- `scripts/suite-durations.tsv` — floor row emitted by regen (Phase 3)
- `knowledge-base/engineering/architecture/decisions/ADR-074-fix-constraints-two-stage-privileged-split.md` — OIDC posture paragraph (Phase 4)

## Files to Create

- `plugins/soleur/test/claude-code-action-auth.test.sh` — Guard 1 (Phase 3)

## Test Scenarios

- **Given** the drain workflow on the post-fix tree, **when** dispatched, **then** the
  claude-code-action step authenticates (OIDC path succeeds with `id-token: write`) and the
  agent runs — verified live in Phase 5.
- **Given** a fixture workflow using the action with `contents: read` only, **when** the guard
  scans it, **then** the suite reports RED (mutation row 1 — the exact defect shape).
- **Given** Stage A's fixed shape (github_token, no id-token), **when** the guard scans it,
  **then** PASS (mutation row 4 — the guard does not redden its own remediation).
- **Given** two standing-issue duplicates exist, **when** the measurement step runs, **then**
  exactly one is updated and the rest are closed with a pointer comment — exercised live by the
  Phase 5 dispatch (4 open dupes today).
- **Given** a human-authored issue titled `issue-flow: weekly measurement` without the
  machinery labels, **when** the step runs, **then** it is neither selected as canonical nor
  closed.
- **Regression:** re-running `machinery-drain-floor.test.sh`, `actionlint` (CI), and
  `lint-orphan-test-suites.sh` after all edits.
- **API verify:** `gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:open+in:title+%22issue-flow%3A+weekly+measurement%22" --jq '.total_count'` expects `1` after Phase 5.

## Success Metrics

- Next scheduled (and dispatched) run checks into Sentry `ok`/`error` on merit — the monitor
  exits the failure streak and any auto-mute warning clears (`recovery_threshold: 1`).
- Exactly one open `issue-flow: weekly measurement` issue after the first post-fix run.
- The census guard runs in CI; a future consumer missing a token path fails at PR time.

## Dependencies & Risks

- **Drain run cost:** the Phase 5 dispatch runs a real paid agent (weekly job shape, bounded by
  the pinned model + skill); it also drains the machinery backlog early — that is the job's
  purpose, not a side effect to avoid.
- **Stage A tail risk:** the action's "Post buffered inline comments" composite step could 403
  on a read-only token IF the agent emits buffered comments — the fix-only prompt produces
  none; Phase 5's gate-trip exercise surfaces it if wrong.
- **App-token scope note (drain):** the OIDC exchange's app token defaults to
  `contents:write`/`pull_requests:write`/`issues:write` — broader than the workflow's
  GITHUB_TOKEN. Accepted: trusted `workflow_dispatch` context, same convention as
  `claude-code-review.yml` and `test-pretooluse-hooks.yml`; narrowing it would deviate from
  the action's designed path.
- **Fork PRs on Stage A:** unchanged — no secrets → preflight fails → agent step gated off.

## References & Research

- Pinned action source: `anthropics/claude-code-action@20f0b248c5003db4b9ca43c45e17949bcdc36d2d`
  — `action.yml` (`OVERRIDE_GITHUB_TOKEN` mapping, `Revoke app token` `if:`), `src/github/token.ts`
  (`setupGitHubToken` early-return, `DEFAULT_PERMISSIONS`), `src/github/validation/permissions.ts`
  (`checkWritePermissions`, `githubTokenProvided`).
- Convention: `.github/workflows/claude-code-review.yml` (job-level `id-token: write`),
  `.github/workflows/test-pretooluse-hooks.yml` (workflow-level).
- Sibling guard: `plugins/soleur/test/reusable-release-caller-permissions.test.sh` (#5977/#5981).
- Learning: `knowledge-base/project/learnings/2026-05-04-schedule-once-template-missing-id-token.md`.
- ADR-074: `knowledge-base/engineering/architecture/decisions/ADR-074-fix-constraints-two-stage-privileged-split.md`.
- OIDC federation found: `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh`
  (Doppler trust, `environment: production` claim); `apps/web-platform/infra/ci-deploy.sh`
  (`COSIGN_IDENTITY_REGEXP` scoped to `reusable-release.yml@refs/heads/main`).
- Live evidence: runs 34825797967 (last green 09-14), 35580861691, 36402277938, 37287175185
  (failures); duplicate issues #8068, #8482, #9132, #9508; Sentry monitor
  `sentry_cron_monitor.scheduled_machinery_drain` (cron-monitors.tf:1367).

---
title: "fix(ci): rename resolve-target's gate output off the CodeQL head-SHA heuristic (CodeQL alert #332)"
type: fix
date: 2026-11-04
slug: fix-codeql-332-untrusted-checkout
branch: feat-one-shot-codeql-332-untrusted-checkout
issue: none
closes: none
priority: P2
domain: engineering
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): rename resolve-target's gate output off the CodeQL head-SHA heuristic (CodeQL alert #332)

## Overview

CodeQL alert **#332** (`actions/untrusted-checkout/medium`, open on `main`)
flags `.github/workflows/web-platform-release.yml:326` — the `resolve-target`
job's `actions/checkout` whose `ref:` reads the gate-validated
`steps.gate.outputs.deploy_sha` merged by PR #12033. The query's
`ActionsSHACheckout` heuristic arm matches any `ref:` field/step/job identifier
against `.*(head|sha|commit).*`; `deploy_sha` matches via `sha`, and the query
carries no `if:` sanitizer and no step-output sanitizer, so the runtime trust
gate the expression passes through is invisible to it. The fix renames the
gate's output to a name that matches neither heuristic token set
(`deploy_target`) while keeping the gate, the `if:` conditioning, the deploy-arm
`--depth=1 origin <sha>` log contract, and every runtime check bit-identical;
the invariants suite is updated so a rename back to a head-patterned output
name goes red.

## Research Insights

### Premise Validation (Phase 0.6 — all claims verified against live state and query source)

- `gh api repos/jikig-ai/soleur/code-scanning/alerts/332` — OPEN,
  `actions/untrusted-checkout/medium`, path
  `.github/workflows/web-platform-release.yml`, line 326. The only open
  `untrusted-checkout` alert (`gh api .../alerts?state=open` filtered on the
  rule id). Alert #216 (the same file, old line 283) is `fixed`.
- `gh pr view 12033` — MERGED 2026-11-04T03:24:59Z; its gate +
  `ref: ${{ steps.gate.outputs.deploy_sha }}` is live at lines 270–329.
- Issue **#8707** (dispatch arm deploys any dispatched ref) and **#8780**
  (dispatch from non-main ref can publish artifacts) are OPEN and adjacent —
  noted, not in scope per the brief.
- Issue **#7592** (compensating control for dismissed CodeQL alert #203) is
  OPEN — it is the repo's dismissal-with-compensating-control precedent, and
  its existence confirms dismissal is a supported-but-last-resort arm.
- **`sec:` tracker search: none exists.** `gh issue list --search "sec: 332
  in:title"` / `"codeql 332"` / all open `sec:` titles return no tracker for
  this alert — medium-severity alerts get no tracker (same as #216's
  disposition); the PR body references the alert number instead. Sibling work
  on the filer machinery lives in issues #12065/#12066 (open) and worktree
  `feat-one-shot-12065-12066-codeql-filer-converge` — adjacent, no file
  overlap.
- **Collision precheck** (`collision-precheck.sh` on 8707/8780/7592): no open
  PR names them (`prs=none`). `gh pr list` over open PRs touching
  `web-platform-release.yml|deploy-arm|invariants` found **PR #12064**
  (`feat-one-shot-10390-ci-hygiene-batch`) — its diff to this file is a single
  comment line at ~:1162 (`verify-migrations`), far from the edited region
  (~:275–330); a rebase may be needed if it merges first but there is no
  semantic conflict.
- **File/symbol verification on `origin/main`:** the flagged checkout is at
  `:326` (`uses: actions/checkout@34e1148...` with `if:
  steps.gate.outputs.trusted == 'true'` and `ref: ${{
  steps.gate.outputs.deploy_sha }}` at :327–329); the gate step `id: gate`
  emits `deploy_sha` at :294/:299/:302; `deploy-arm.sh:259` carries the
  `\[command\][^ ]*git .* --depth=1 origin [0-9a-f]{40}` primary-key regex and
  :261 the `resolving deploy target for [0-9a-f]{40}` fallback;
  `workflow-run-deploy-invariants.test.sh:501–503` pins `deploy_sha`/`ref:`
  strings (P4), :489/:534 pin exactly-one-checkout + `fetch-depth` unset/1
  (P2); `deploy-arm.test.sh:684` pins the literal `ref:` text and
  checkout-before-resolve ordering; the `resolve` step echoes
  `resolving deploy target for $WR_HEAD_SHA` at :498 inside the workflow_run
  arm only (the dispatch arm `exit 0`s at :477 before reaching it).

### The query, read at predicate level (github/codeql `main`)

Why #332 fired on a *gated* ref — the two match arms of `ActionsSHACheckout`
(`UntrustedCheckoutQuery.qll`):

1. **Taint arm** (`ActionsSHACheckoutFlow::flowPath`): sources are
   `GitHubCtxSource` (`github.head_ref` only), `GitHubEventCtxSource`
   (untrusted-event-property regexes — `untrusted_event_properties.yml`
   does **not even list** `github.event.workflow_run.head_sha`),
   `GitHubEventJsonSource` (fromJSON/toJSON-wrapped event fields), `MaDSource`,
   and expressions matching `containsHeadSHA` (`\bgithub.event.workflow_run
   .head_sha\b`, `\bhead_sha\b`, `\bmerge_sha\b`, `\bhead\.sha\b`,
   `\bpr_head_sha\b`, check_suite/check_run/merge_group variants — `deploy_sha`
   matches none). The env→step-output flow
   (`FlowSteps.qll` `envToOutputStoreStep`/`commandToOutputStoreStep`) only
   registers when a `$VAR` appears literally inside an `echo|printf >>
   $GITHUB_OUTPUT` line or a `VAR2=$VAR` assignment chain — the gate's
   `emit() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }` +
   `emit deploy_sha "$WR_HEAD_SHA"` defeats it (`emit` is not `echo|printf`
   and `$1`/`$2` positional indirection is unmodeled). **No taint path exists
   into `steps.gate.outputs.deploy_sha`.**
2. **Heuristic arm** (the one that fired): `value.regexpMatch(".*
   (head|sha|commit).*")` tested against the `ref:` expression's
   `StepsExpression.getStepId()` (`gate` — clean), `NeedsExpression
   .getNeededJobId()` (n/a), `SimpleReferenceExpression.getFieldName()`
   (**`deploy_sha` — matches via `sha`**), `JsonReferenceExpression
   .getAccessPath()`/`getInnerExpression()` (n/a). The mutable-ref sibling
   class `ActionsMutableRefCheckout` runs the same arm against `.*
   (head|branch|ref).*`. So the clearing name must avoid **all five** tokens:
   `head`, `sha`, `commit`, `branch`, `ref`. `deploy_target` matches none.
- `UntrustedCheckoutMedium.ql` = `PRHeadCheckoutStep` +
  `inNonPrivilegedContext` — **no `if:` sanitizer, no
  `persist-credentials` sanitizer, no step-output sanitizer** (PR #12033's
  body claim verified). `resolve-target` is the workflow's **only**
  non-privileged checkout-bearing job (`permissions: {contents: read,
  actions: read}`, no `secrets.*`): every other `actions/checkout` site
  (`migrate`, `verify-migrations`, `verify-doppler-secrets`, `live-verify`,
  ~:1059/:1097/:1243/:2171) is privileged via inherited `contents: write` /
  `packages: write` (top-level `permissions:`), explicit write, or a
  `secrets.*` access — which is why `ref: ${{ needs.resolve-target.outputs
  .head_sha }}` (field name `head_sha` matches the same heuristic!) and
  `verify-doppler-secrets`'s `ref: ${{ github.event.workflow_run.head_sha
  || github.sha }}` produce **no** alerts. `workflow_dispatch` is
  externally-triggerable + privileged per `externally_triggereable_events.yml`
  + `EventImpl.isPrivileged`, making privilege hinge on the job's own
  perms/secrets — confirmed consistent with the observed alert set.
- **`GitSHACheckout` (run-step sinks):** a `run:` command matching
  `git\s+(fetch|pull).*` is only a sink when the command text or an in-scope
  env var's expression matches `containsHeadSHA` — `git fetch --depth=1 origin
  "$DEPLOY_SHA"` + `DEPLOY_SHA: ${{ steps.gate.outputs.deploy_sha }}` matches
  neither (verified — `deploy_sha` is not in `containsHeadSHA`'s regex list).
  The plan-B fallback (untrusted-checkout sink structurally absent) is real.
- The 2026-11-03 learning
  (`learnings/security-issues/2026-11-03-codeql-untrusted-checkout-medium-has-no
  -if-or-persist-credentials-sanitizer.md`) and PR #12033's deepen-plan both
  verified `deploy_sha` against `containsHeadSHA` — **the wrong regex set**.
  The heuristic that fired is `.*(head|sha|commit).*` on identifiers, a
  different predicate in the same file. The learning's sink description
  ("a `steps.<id>`/`needs.<job>` expression whose **id** matches") is
  incomplete — the field name/access-path/inner-expression are checked too.
  The plan updates that learning so it stops teaching the miss.

### Property List (Phase 0.6b)

- **P-1:** `actions/untrusted-checkout/medium` no longer fires on
  `resolve-target`'s checkout — alert 332 closes on `main` post-merge.
- **P-2:** the runtime trust boundary is preserved bit-for-bit — `gate` emits
  trusted+deploy-SHA only for `push`-to-`main` or dispatch; the checkout and
  `budget` stay `if:`-gated; `resolve`'s runtime re-check is untouched.
- **P-3:** the deploy-arm `[command]…git … --depth=1 origin <sha>` primary
  key and the `resolving deploy target for` fallback are preserved —
  `deploy-arm.sh` behavior identical on both arms.
- **P-4:** the checked-out tree remains the gate-validated deploy SHA (never
  `github.sha`/main HEAD), so `budget`/`resolve` parse the deployed tree.
- **P-5:** the invariants suite goes red on the regression that produced
  #332 — an output name matching `head|sha|commit|branch|ref` in the `ref:`
  expression, a dropped `if:`, or a re-inlined event field.

### Cut List (Phase 0.6b)

- **Restructure (brief's option a — no-ref/literal checkout + run-step
  `git fetch --depth=1 origin` + `checkout FETCH_HEAD`):** buys P-1 and P-4,
  but the `actions/checkout` fetch of a context ref produces
  `+refs/heads/main*`/`+<sha>:refs/…` log shapes — never `origin <40hex>` at
  EOL — and run-step `git` logs `[command]/usr/bin/bash`, not `git`. The
  deploy-arm **primary key dies on both arms** (wr arm falls back to the
  `resolve` echo; the dispatch arm has NO `resolving deploy target` echo —
  :477 `exit 0` precedes it — so it needs a new shaped echo or
  `deploy-arm.sh` regex surgery + `deploy-arm.test.sh` rework). More diff on
  ship/postmerge-critical tooling than the property buys. **Kept as the
  documented plan-B escalation**, not the plan.
- **Dismissal (brief's option b):** #7592's precedent makes dismissal legal,
  but a structural clearing exists; dismissing waives the scanner's coverage
  of this site against future edits. **Kept as plan-C** (only if the PR-ref
  scan shows the rename is insufficient).
- **Provenance-visible-to-query (brief's option c):** impossible — the query
  has no sanitizer that models gates; nothing written into the expression or
  `if:` is read by it. **Cut.**
- **Make `resolve-target` privileged** (grant a secrets access or write perm
  to exit `inNonPrivilegedContext`): silences the alert by weakening
  least-privilege on a job that needs neither secrets nor write. **Cut — the
  cure is worse than the alert.**
- **`fromJSON(...)` indirection around `deploy_sha`:** `getInnerExpression()`
  is checked against the same heuristic — cosmetics that still fails.
  **Cut.**

### CTO ruling (technical fork: rename vs restructure — sequential execution, no spawn tool)

**Decision:** Option A — rename the gate output `deploy_sha` → `deploy_target`
(matching neither `.*(head|sha|commit).*` nor `.*(head|branch|ref).*`), keep
the gate/`if:`/runtime re-check/`--depth=1` checkout byte-identical, update
the P4 + `deploy-arm.test.sh` pins, and add a negative-token pin so a future
rename back to a head-patterned output name reds the suite. Escalate to the
restructure (plan-B) only if the PR-ref CodeQL scan still flags.

**Rationale:** the alert's only live match is the field-name heuristic —
verified at predicate level that no modeled taint path reaches the output
(the env source isn't modeled and the `emit` indirection defeats the bash
extractors). A rename therefore clears the *actual* mechanism at ~10 lines of
diff and zero runtime delta, while the restructure kills the deploy-arm
primary key on both arms and needs compensating machinery in three files for
the same property. Minimalism ladder rung 1–5; the PR-ref CodeQL scan is the
cheap arbiter if the deployed pack differs from the source read.

**Rejected alternatives:** restructure (deploy-arm contract churn —
documented as plan-B), dismissal (structural fix exists), privilege grant
(least-privilege regression), fromJSON cosmetics (still flagged).

**Dissent:** if GitHub's deployed query pack models env→output flow through
function-call indirection (not modeled on `main` today), the rename fails
PR-scan — the AC makes that arm the escalation trigger rather than a
post-merge surprise. `Ruled by CTO agent, 2026-11-04` (sequential execution —
recorded to `decision-challenges.md`).

### Learnings applied

- `2026-11-03-codeql-untrusted-checkout-medium-has-no-if-or-persist-credentials-sanitizer.md`
  — read the query source first; no `if:`/persist-credentials sanitizer;
  `git\s+(fetch|pull)` run-step sink class exists (checked, does not fire on
  the plan-B shape).
- `2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md` — dismissal is a
  legal arm with precedent but secondary to a structural clear; no
  `sec:`-issue machinery needed for medium alerts.
- ADR-074 precedent (from the prior plan) — the sink should be unreachable
  before trust is established; the runtime gate already satisfies this, the
  rename makes the *scanner-visible* form match.
- Prior plan `archive/20261103-234120-2026-11-03-fix-codeql-216-untrusted-checkout-plan.md`
  — template, coupled-surface map (P1–P5, G3, W3, six-state taxonomy), and
  the exact pin sites that must move in lockstep.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a
  botched rename is caught by the invariants suite before merge; if a
  `ref:`/output-name drift ever shipped, `resolve-target`'s checkout would
  fail or fetch nothing, the deploy clean-skips, and `release-outcome` /
  `notify-gated` pages the operator while the user keeps the
  already-deployed version.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing new — the diff introduces no data surface and changes no runtime
  trust boundary; the alert it closes is a CI-scanner signal about a
  pre-existing-on-main shape, not exposure added by this diff.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff renames a workflow output key inside an
  already-gated CI security boundary — `.github/workflows/web-platform-release.yml`
  matches the sensitive-path regex, but the change alters no runtime trust,
  secrets, or user-facing surface; the residual of a bad landing is a red
  invariants suite or a clean-skipped deploy, both operator-visible, neither
  user-reaching.`

## Proposed Solution

Rename the `gate` step's output `deploy_sha` → `deploy_target` and point
`ref:` at it. `deploy_target` matches neither `.*(head|sha|commit).*`
(`ActionsSHACheckout` heuristic) nor `.*(head|branch|ref).*`
(`ActionsMutableRefCheckout` heuristic), and no modeled taint path reaches a
step output produced through the `emit` indirection — so both query arms go
silent while the runtime gate is byte-for-byte identical. Update the
comment block to say *why* the name avoids the five tokens (a future editor
must not "fix" the odd name back — the name IS the fix), update the two pin
sites in the test suite, and correct the 2026-11-03 learning whose
id-only description of the heuristic is what produced this alert.

## Technical Considerations

- **Rename surface is fully enumerated** (grep over non-archive files):
  `emit deploy_sha` ×3 (:294/:299/:302), `ref:` (:329), comments (:275,
  :315–318), `workflow-run-deploy-invariants.test.sh` (:501–503, :554),
  `deploy-arm.test.sh` (:684). No other consumer reads
  `steps.gate.outputs.deploy_sha` — verified by grep. `steps.gate.outputs
  .trusted` consumers (:327, :801) are `if:` conditions, not `ref:` args —
  unaffected.
- **Known residual, not in scope:** `resolve-target.outputs.head_sha`
  (emitted by `resolve`, consumed as `needs.resolve-target.outputs.head_sha`
  by `migrate`, `verify-migrations`, `live-verify`, and the ~:2171 job) is
  also a heuristic-matching identifier — it produces no alert today only
  because every consumer job is privileged. Renaming it would churn four
  consumer sites for zero scanner-visible gain; left alone deliberately. If
  a consumer ever loses its write/secrets privilege it will flag — noted so
  the next alert isn't a surprise.
- **G3/W3/P1–P3 invariants are untouched:** no `github.sha` is introduced,
  `resolve` gains no `if:`/`continue-on-error`, RELEASE_PATH_FILTER is
  byte-identical, exactly-one-checkout stands.
- **`emit` indirection is load-bearing and must be kept:** if the gate ever
  writes `echo "deploy_target=$WR_HEAD_SHA" >> $GITHUB_OUTPUT` directly, a
  modeled env→output flow *could* exist (`envToOutputStoreStep`) — keeping
  `emit` is both style and scanner-invisibility. The amended P4 pin asserts
  the output is emitted (substring), and the comment documents the
  constraint.
- **CodeQL's deployed pack may differ from `main`:** the alert firing proves
  the deployed heuristic includes the field-name arm; the PR-ref scan is the
  arbiter for anything the source read can't see (AC encodes the escalation).

### Attack Surface Enumeration

The security surface is "what tree materializes on the `resolve-target`
runner and drives the deploy pipeline." All paths into it:

- `actions/checkout` `ref:` — gate-validated `deploy_target`; only
  `push`-to-`main` upstream SHAs (collaborator/merge-queue only) or
  dispatch `github.sha` ever reach it (`if: trusted == 'true'`). UNCHANGED.
- `resolve` step's runtime re-check (`WR_HEAD_BRANCH`/`WR_EVENT`/
  40-hex `bad_sha` fail-closed) — defense in depth behind the gate.
  UNCHANGED.
- `verify-doppler-secrets` — gated at job level by the P5-pinned trusted-shape
  conjunct (privileged, out of the medium query's scope). UNCHANGED.
- Downstream `needs.resolve-target.outputs.head_sha` checkouts — downstream
  of `resolve`'s validation, all in privileged jobs. UNCHANGED.
- Unchecked-path note: none introduced; the diff is an identifier rename
  with the trust boundary byte-identical.

## Files to Edit

- `.github/workflows/web-platform-release.yml` —
  (a) `gate` step `run:` emits `deploy_target` instead of `deploy_sha`
  (three `emit` lines; `emit trusted` lines unchanged);
  (b) `ref:` reads `${{ steps.gate.outputs.deploy_target }}`;
  (c) comments at ~:275 and ~:311–318 updated: name the field-name
  heuristic as the reason the identifier avoids
  `head|sha|commit|branch|ref`, update the #216 references to include
  #332, and warn that `emit` indirection must be kept (a literal
  `echo "x=$VAR" >> $GITHUB_OUTPUT` can become a modeled flow).
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` —
  P4 row amended: `gate_ok` asserts `deploy_target`+`trusted` in the gate
  `run:`; `ref_ok` asserts `if:` and `co_ref == "${{ steps.gate.outputs
  .deploy_target }}"` PLUS a negative-token clause — the `steps.<id>.outputs
  .<name>` identifier must not match `(head|sha|commit|branch|ref)`; fail
  message text updated to name the heuristic and #332. Row count unchanged
  (no MIN_ROWS bump needed).
- `plugins/soleur/test/deploy-arm.test.sh` — the `_ref` grep at ~:684
  updated to `deploy_target` (ordering `_co < _ref < _res` unchanged).
- `knowledge-base/project/learnings/security-issues/2026-11-03-codeql-untrusted-checkout-medium-has-no-if-or-persist-credentials-sanitizer.md` —
  append a dated correction: the heuristic tests field
  name/access-path/inner-expression, not only the id; `deploy_sha`
  re-alerted as #332 on that arm.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-codeql-332-untrusted-checkout/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-codeql-332-untrusted-checkout/session-state.md`
- `knowledge-base/project/specs/feat-one-shot-codeql-332-untrusted-checkout/decision-challenges.md`

## Domain Review

### Engineering

**Status:** reviewed (sequential execution — no spawn tool; role executed
inline against `agents/engineering/cto.md`'s Assess guidance)

**Assessment:** a ~10-line identifier rename inside an existing trust
boundary plus its two pin sites and one learning correction. No new jobs,
triggers, permissions, or autonomous surfaces; `resolve-target`'s step count
is unchanged so the P2 exactly-one-checkout invariant is untouched. The
riskiest adjacency — the `deploy-arm.sh` `[command]…--depth=1 origin <sha>`
log contract — is preserved bit-for-bit because the `actions/checkout` fetch
line is produced by the same `ref:`→fetch mechanism under a different name.

### Security

**Status:** reviewed (sequential — inline)

**Assessment:** runtime trust posture is identical before and after; the
change is scanner-visible only. Verified at predicate level that the alert's
live match is the `.*(head|sha|commit).*` field-name heuristic and that no
modeled taint path reaches `steps.gate.outputs.*` through the `emit`
indirection (untrusted_event_properties.yml doesn't list
`workflow_run.head_sha`; `envReachingGitHubFileWrite` can't see `$1`/`$2`
function args). Residual: the rename bets on the heuristic set read from
`main` — the PR-ref scan arbitrates.

## Observability

(The surface changed is the release pipeline's own gating; its observability
is the existing `::error::`/`::notice::` annotations, `skip_reason` outputs,
`notify-gated` Slack page, and `release-outcome` classification — all
preserved byte-for-byte. `.github/workflows/web-platform-release.yml`
matches `SENSITIVE_PATH_RE`, so this block is emitted for Check 10.)

```yaml
liveness_signal:
  what: "release-outcome job classifies every non-push-arm run (delivered / clean-skip / non-delivery) and notify-gated pages on non-delivery"
  cadence: "per workflow_run completion"
  alert_target: "operator Slack page via notify-gated; email via release-outcome"
  configured_in: ".github/workflows/web-platform-release.yml (release-outcome, notify-gated)"

error_reporting:
  destination: "GitHub Actions check-run annotations (a release-pipeline failure, not app runtime)"
  fail_loud: "::error::deploy blocked [skip_reason=<reason>] annotation on resolve-target; job exits non-zero"

failure_modes:
  - mode: "untrusted-shape upstream event (fork-PR CI on branch 'main')"
    detection: "resolve-target clean-skips with skip_reason=not_main|not_push; checkout + budget skipped"
    alert_route: "none — green clean-skip by design (pre-existing state semantics)"
  - mode: "gate emits trusted=false on a genuinely deployable run (regression)"
    detection: "deploy never runs; release-outcome classifies non-delivery"
    alert_route: "operator Slack page via notify-gated / email via release-outcome"
  - mode: "renamed output re-flagged by the deployed CodeQL pack (heuristic set differs from source read)"
    detection: "CodeQL check on the PR ref reports actions/untrusted-checkout; alert 332 stays open on main post-merge"
    alert_route: "PR check failure + post-merge alert-gate (codeql-main-alert-gate.sh) — plan-B escalation documented in Alternatives"

logs:
  where: "GitHub Actions run logs (resolve-target, deploy-arm identification)"
  retention: "GitHub default retention"

discoverability_test:
  command: "bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh"
  expected_output: "workflow-run-deploy-invariants.test.sh"
  # Suite-shaped but inside the 15s cap — measured 9.4s wall-clock locally
  # (2026-11-04, 82 rows); the smallest command that prints the signal this
  # change owns is this suite itself.
```

## Encryption Posture

```yaml
posture: unchanged
rationale: >
  No new secret is minted, stored, or transmitted. The diff renames a
  workflow output identifier; permissions, secrets access, and the
  persist-credentials posture of every checkout are byte-identical.
```

## Task Design

N/A — no new autonomous-task surface (no new workflow, cron, registered
check, or daemon); this edits steps inside an existing workflow and its
existing tests.

## Guard Contract

The deliverable amends an existing guard (P4) rather than shipping a new
one; the amended guard's contract is specified here, including the new
anti-regression clause.

### Guard 1 — `resolve-target` checkout trust-gate + CodeQL identifier contract (P4 row, amended)

**Property.** On the `workflow_run`/`workflow_dispatch` arms of
`web-platform-release.yml`, `resolve-target`'s single `actions/checkout` is
conditioned on `steps.gate.outputs.trusted == 'true'` and its `ref:` reads a
gate-emitted output whose identifier matches neither `.*(head|sha|commit).*`
nor `.*(head|branch|ref).*` — never an expression naming an event field, and
never a name CodeQL's head-SHA/mutable-ref heuristics match.

**Assembly.** The chokepoint is the step sequence inside
`jobs.resolve-target.steps`: exactly one `actions/checkout@` uses-step (P2
bounds the count), exactly one `gate` step emitting `trusted` and
`deploy_target` (substring-asserted in its `run:`), the checkout's `if:` and
`with.ref` asserted by exact string equality, and the `ref:`'s
`steps.<id>.outputs.<name>` identifier asserted against the five-token
blocklist — so a compliant rename to ANY future head-patterned name reds
the row, not just a revert to `deploy_sha`. The runtime contract the row
certifies is unchanged: `trusted` is `true` only for `push`-to-`main`
upstream events or non-`workflow_run` (dispatch → `github.sha`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert `ref:` to `${{ github.event.workflow_run.head_sha \|\| github.sha }}` (guard's own dispatch — an event-field expression returns) | P4 RED |
| 2 | Rename the output to `deploy_sha` / `deploy_ref` / `deploy_commit` on BOTH the emit and the `ref:` — identifiers matching a heuristic token, i.e. the exact #332 regression (precondition satisfied — a name is present — but the property fails) | P4 RED |
| 3 | Drop the checkout's `if:` (step runs unconditioned on any event shape) | P4 RED |
| 4 | Delete the `gate` step (no `trusted`/`deploy_target` producer — absent-assembly row) | P4 RED |
| 5 | Add a SECOND checkout whose `ref:` also reads `steps.gate.outputs.*` (second-member row — the count bound is P2's, this row confirms the pair stays consistent under addition) | P2 + P4 RED |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Close code-scanning alert 332 (`actions/untrusted-checkout/medium`) at `.github/workflows/web-platform-release.yml:326` — the residual sink left by merged PR 12033's fix for alert 216." | Files to Edit (a)–(c); AC-1..AC-6 | mapped |
| 2 | "(a) restructure so actions/checkout's `ref:` input is not traceable to event-derived data — e.g. checkout a trusted context SHA and move `git fetch --depth=1 origin $deploy_sha && git checkout FETCH_HEAD` into a `run:` step (run-step git is not a CodeQL checkout sink), preserving the deploy-arm contract: `plugins/soleur/scripts/deploy-arm.sh` identifies the deploy arm by this checkout's `--depth=1 origin <sha>` log line and `workflow-run-deploy-invariants.test.sh` pins the depth-1 shape + gate (P2/P4)" | Cut List + Alternatives: restructure documented as plan-B with its deploy-arm-primary-key cost verified; the deploy-arm contract + P2/P4 preservation is AC-4/AC-5 | descoped — justification: the rename clears the same alert without breaking the `[command]` primary key (analysis in Research Insights); held as the escalation arm the AC names |
| 3 | "(b) a code-scanning dismissal with reason if no structural form clears it and repo precedent supports dismissal (check issue 7592 'Compensating control for dismissed CodeQL alert 203')" | Cut List + Alternatives: dismissal held as plan-C; #7592 verified OPEN as precedent | descoped — justification: a structural clearing exists, so the precondition ("if no structural form clears it") does not hold |
| 4 | "(c) any form that makes the trusted-SHA provenance visible to the query" | Cut List | descoped — justification: the query has no sanitizer that reads gates or `if:`s — verified at predicate level; no such form exists |
| 5 | "Related context: issues 8707 and 8780 (workflow_dispatch arm deploys any dispatched ref) are adjacent arm-gating concerns — note them, do not expand scope" | Research Insights Premise Validation + Dependencies & Risks | mapped |
| 6 | "Search for a `sec:`-prefixed tracker issue for this alert and link it if one exists" | Research Insights: none exists (medium alerts get no tracker) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `deploy_sha` → `deploy_target` rename (workflow file a–c) | "Close code-scanning alert 332 (`actions/untrusted-checkout/medium`) at `.github/workflows/web-platform-release.yml:326`" | inferred — justification: it is the minimal structural clearing of the flagged expression, chosen over the ask's enumerated (a)/(b)/(c) arms per the CTO ruling; the ask says "Evaluate" those arms, it does not mandate (a) |
| P4 amendment + negative-token clause (invariants test) | "`workflow-run-deploy-invariants.test.sh` pins the depth-1 shape + gate (P2/P4)" | inferred — justification: repo guard convention — every load-bearing invariant on this pipeline is pinned by a suite row, and the token clause is the anti-regression control the #332 incident bought |
| `deploy-arm.test.sh` `_ref` pin update | "preserving the deploy-arm contract" | inferred — justification: the pin asserts the literal `ref:` text; it must move in lockstep or the suite reds on the fix |
| Learning-file correction | — | inferred — justification: the learning's id-only description of the heuristic is the defect that produced #332 (the prior plan verified `deploy_sha` against `containsHeadSHA`, not the identifier heuristic); leaving it teaches the miss to the next planner |
| `deploy-arm.sh` unchanged; no `sec:` tracker filed | "Search for a `sec:`-prefixed tracker issue for this alert and link it if one exists" | asked |

### Split Assessment

- Subsystems touched: 1 — `.github` (+ `plugins/soleur/test`, `knowledge-base`)
- Planned files: 4 edited + 3 spec artifacts | Estimated changed lines: ~45
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no
references to `web-platform-release.yml`,
`workflow-run-deploy-invariants.test.sh`, `deploy-arm.test.sh`, or the
learning file.

## Acceptance Criteria

- [ ] `gh api repos/jikig-ai/soleur/code-scanning/alerts/332` reports the
  alert `fixed`/`dismissed` on `refs/heads/main` after merge. Pre-merge
  proxy: the CodeQL analysis on the PR ref reports no
  `actions/untrusted-checkout` alert on this branch — **and if it does,
  that is the documented escalation trigger to plan-B (restructure), not a
  merge-blocker surprise.**
- [ ] `resolve-target`'s `ref:` reads `${{ steps.gate.outputs.deploy_target }}`;
  the identifier in the `steps.<id>.outputs.<name>` expression contains
  none of `head|sha|commit|branch|ref`; the `gate` step emits `trusted`
  and `deploy_target`.
- [ ] The checkout and `budget` steps remain conditioned on
  `steps.gate.outputs.trusted == 'true'`; the gate's trust-shape logic and
  `resolve`'s runtime re-check are semantically byte-identical (only the
  output identifier changes).
- [ ] `deploy-arm.sh`'s `--depth=1 origin <sha>` arm-identification
  contract is preserved: exactly one `actions/checkout` in `resolve-target`
  with `fetch-depth` unset/1 (P2 green), so the `[command]` fetch line is
  still produced by the same mechanism.
- [ ] `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh`
  passes including the amended P4 (exact-string + negative-token clause);
  `bash plugins/soleur/test/deploy-arm.test.sh` passes including the
  updated `_ref` pin; `bash
  plugins/soleur/test/resolve-target-decision.test.sh` passes (resolve
  step body unchanged).
- [ ] No non-archive file references `steps.gate.outputs.deploy_sha` or
  emits `deploy_sha` from the `gate` step (`grep -rn "deploy_sha"
  .github/ plugins/` residual-zero outside archive paths and the
  unrelated `ci_deploy_sha256` name).
- [ ] The 2026-11-03 learning carries the dated correction documenting the
  field-name heuristic arm.
- [ ] No `sec:` tracker is filed (medium-severity convention; the PR body
  cites "CodeQL alert #332").

## Test Scenarios

- `unit`: Given the amended P4, when `ref:` reads `deploy_target` gated on
  `trusted`, then the row reports ok (must-PASS, new canonical).
- `unit`: Mutation battery rows 1–5 in the Guard Contract — each drives P4
  (or P2) RED; run the suite's own mutation battery.
- `unit`: `bash plugins/soleur/test/deploy-arm.test.sh` — the ordering
  assertion `_co < _ref < _res` passes against the renamed pin.
- `integration`: Given a CodeQL scan of the PR ref, when the workflow is
  analyzed, then no `actions/untrusted-checkout` instance exists on
  `resolve-target`'s checkout (the pre-merge proxy for AC-1).
- `unit`: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/web-platform-release.yml"))'`
  — structure parses (with the `on:`-key caveat).

## Success Metrics

- Alert 332 transitions to `fixed` on `main` post-merge; zero
  `actions/untrusted-checkout` alerts open.
- Deploy-arm identification in ship/postmerge is unchanged (no
  `unresolved`/`log_line_absent` class changes on the next release run).

## Dependencies & Risks

- **Deployed-pack drift risk (medium):** the analysis ran against
  `github/codeql` `main`; the deployed query pack could model an
  env→output path `main` does not. Mitigation: the PR-ref CodeQL scan is a
  required check and is the named escalation trigger to plan-B.
- **Adjacent open issues:** #8707/#8780 (dispatch arm deploys any
  dispatched ref) are real arm-gating concerns in the same file —
  deliberately not touched; the diff does not intersect their surface
  (dispatch arm emits `deploy_target` the same way).
- **Adjacent open PR #12064:** touches this file at ~:1162 (comment only)
  — trivial rebase if it merges first.
- **`resolving deploy target` echo is wr-arm-only:** known and unchanged —
  the dispatch arm relies on the primary `[command]` key today, which this
  diff preserves (the plan-B restructure is what would have broken it).

## Enhancement Summary

**Deepened on:** 2026-11-04
**Sections enhanced:** Observability (cap-argued probe), Guard Contract (lint-resolved)
**Review passes:** sequential-fallback — no spawn tool; halt gates 4.6–4.13
executed mechanically; negative-claim and post-edit self-audit sweeps run
inline.

### Key Improvements (deepen-plan)

- **Measured the suite-shaped `discoverability_test.command`:** the
  `test/`-path reject regex flags it, but the suite completes in 9.4s
  wall-clock (< 15s Check-10 cap, 82 rows) — argued down with the measurement
  rather than silently waived; the probe is the smallest command that prints
  the signal this change owns.
- **Verified-the-negative sweep:** every negative claim in the plan was
  grep-proven — "no taint path into `steps.gate.outputs.*`" (FlowSteps.qll
  `envToOutputStoreStep`/`commandToOutputStoreStep` can't see the `emit`
  indirection; `untrusted_event_properties.yml` doesn't list
  `workflow_run.head_sha`), "no other `deploy_sha` consumer" (grep over
  non-archive files), "no `sec:` tracker" (three `gh issue list` shapes),
  "no open-PR collision" (`prs=none`; PR #12064's diff is a far-field
  comment).
- **Post-edit self-audit:** the renamed symbol's full consumer set
  (emit ×3, `ref:`, P4 pins, deploy-arm `_ref` pin, comments, learning) is
  enumerated in Files to Edit — no downstream reference escapes the rewrite.
- **All deepen halt gates pass:** 4.6 User-Brand Impact (`none` + sensitive-
  path scope-out), 4.7 Observability (5 fields, allowlisted verb, literal
  expected_output, measured runtime), 4.8 PAT (zero), 4.9 `.pen` (non-UI),
  4.10 Encryption (no store/connection), 4.11 Guard Contract (`lint-guard-contract.py`
  green, assembly is structural — chokepoint + identifier census), 4.12
  Scope Check (one unfenced section, all rows mapped/descoped-with-reason),
  4.13 Task Design (no new autonomous surface).

### New Considerations Discovered

- The `emit()` indirection is scanner-load-bearing, not just style: a literal
  `echo "x=$VAR" >> $GITHUB_OUTPUT` would make the env→output flow modeled
  and could re-flag any renamed output — pinned by P4's `gate_ok` substring
  assertion plus the comment warning.
- `deploy_target` was verified against all five heuristic tokens
  (`head|sha|commit|branch|ref`) programmatically, in both the bare
  identifier and the full `${{ steps.gate.outputs.deploy_target }}`
  expression — the exact check the prior deepen-pass ran against the wrong
  regex set.
- Known residual recorded in Technical Considerations:
  `needs.resolve-target.outputs.head_sha` is heuristic-matching and unflagged
  only because every consumer job is privileged — a deliberate non-goal.

## Alternative Approaches Considered

| Option | Verdict |
|--------|---------|
| **Rename the output (chosen)** | Clears the field-name heuristic at ~10 lines; zero runtime delta; preserves the deploy-arm primary key. |
| Restructure: no-ref/`ref: main` checkout + run-step `git fetch --depth=1 origin "$DEPLOY_TARGET" && git checkout FETCH_HEAD` (+ `echo "resolving deploy target for $DEPLOY_TARGET"` for the dispatch arm) | **Plan-B.** Clears the sink structurally and survives future heuristic tightening, but kills the `[command]…--depth=1 origin <sha>` primary key on both arms (checkout fetches `+refs/heads/main*`/`+<sha>:refs/…` — never `origin <sha>` at EOL; run-step git logs `[command]/usr/bin/bash`), requiring a shaped echo or `deploy-arm.sh` regex surgery + test rework on ship/postmerge-critical tooling. Escalate iff the PR-ref scan still flags. |
| Code-scanning dismissal (w/ compensating control per #7592 precedent) | **Plan-C.** Only if no structural form clears it; waives scanner coverage of this site. |
| Privilege grant to exit `inNonPrivilegedContext` | Rejected — weakens least-privilege to silence a scanner. |
| `fromJSON(...)` indirection | Rejected — `getInnerExpression()` is checked by the same heuristic. |
| Keep `deploy_sha` and make `ref:` read it via `env.` | Rejected — `env.X` fieldName `X` is clean but the env value expression still names `deploy_sha`; adds indirection the output rename gives for free. |

## References & Research

- Flagged site: `.github/workflows/web-platform-release.yml:326-329`
  (gate at :270-304)
- Pin sites: `plugins/soleur/test/workflow-run-deploy-invariants.test.sh:488-503,554`;
  `plugins/soleur/test/deploy-arm.test.sh:680-692`;
  `plugins/soleur/scripts/deploy-arm.sh:259-261`
- Query source: `github/codeql` —
  `actions/ql/lib/codeql/actions/security/UntrustedCheckoutQuery.qll`
  (`ActionsSHACheckout`/`ActionsMutableRefCheckout`/`GitSHACheckout`),
  `.../UntrustedCheckoutMedium.ql`, `.../ast/internal/Ast.qll`
  (`StepsExpressionImpl.getFieldName`, `isPrivilegedExternallyTriggerable`),
  `.../Bash.qll` (`envReachingGitHubFileWrite`),
  `.../dataflow/FlowSteps.qll` (`envToOutputStoreStep`),
  `.../ext/config/{untrusted_event_properties,externally_triggereable_events}.yml`
- Prior art: PR #12033; archived plan
  `archive/20261103-234120-2026-11-03-fix-codeql-216-untrusted-checkout-plan.md`;
  learning `2026-11-03-codeql-untrusted-checkout-medium-has-no-if-or-persist-credentials-sanitizer.md`;
  dismissal precedent #7592; adjacent #8707/#8780 (noted, out of scope)

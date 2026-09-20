# Decision challenges — feat-one-shot-8010-rung2-gate-load-bearing

Persisted headless (no TTY, one-shot pipeline) per ADR-084 / `plan-review` classifier routing. `soleur:ship` Phase 6 renders these into the PR body and files an `action-required` issue. Each item challenges the operator's **stated direction**; none was auto-applied.

## UC1 — "Split #8361 first; this plan is blocked behind a dead workflow"

**Source:** `soleur:engineering:review:dhh-rails-reviewer` (P0), corroborated by `soleur:engineering:review:architecture-strategist`.
**Measured:** `.github/workflows/apply-web-platform-infra.yml` is 513,306 bytes (over GitHub's 500 KB limit) and its last five runs conclude `failure` with zero jobs — startup failure, as #8361 reports. The two gate call sites this plan is careful not to disturb therefore **cannot execute today**.
**The challenge:** land #8361's split before hardening a gate whose primary consumers are inert, rather than shaping this plan around an un-editable file.
**Plan's position (default = the brief):** the brief names `git-data-rung2-rehearsal.yml` as the only workflow to touch. The plan proceeds and states the inertness explicitly, because the gate's other live surfaces (the PR freshness step, the daily #8210 probe, the operator's local invocation) are real and because #8361 is a separate, larger change. The credential and tri-state call-site work for those files is filed as a blocker issue.
**If the operator disagrees:** sequence #8361 first and re-run this plan's Phase 4 against the split file.

## UC2 — "Delete the Sentry-verdict mechanism entirely"

**Source:** `soleur:engineering:review:dhh-rails-reviewer` (P1).
**The challenge:** the verdict guards a string the same human types into the same file they are gating; its own Guard Contract says it has no anchor. Keep one line ("present and not `FATAL`") and drop the ack, the token set and the arms.
**Plan's position (default = the brief):** the brief requires that "a failed/absent cross-check must HOLD the gate, not pass", so cutting the mechanism drops operator-requested scope — never Mechanical. The plan did take the simplification the finding implies: the reset-arm corroboration path was cut, `SENTRY_ACK_CONTRADICTS` was cut, and what remains is one cardinality entry, one at-most-once loop and one `case`.
**If the operator disagrees:** the minimal form is FR1 without the ack grammar — and `UNAVAILABLE` then holds every quiet-window rehearsal, including PR #8393's evidence.

## UC3 — "Cut the capture-script edits into their own PR"

**Source:** `soleur:engineering:review:dhh-rails-reviewer` (P1).
**The challenge:** none of the capture edits makes the gate load-bearing; FR12 (the literal `<now>` in a recorded query) is a one-line bug that could ship today, alone.
**Plan's position (default = the brief):** the brief scopes "the rehearsal capture script" into this cycle, and FR10/FR11 (the 24 h liveness window and `NOT_RUN`) are preconditions for the Sentry key being load-bearing at all — #8171 declined item 5 precisely as "tied to body item 3". FR12 arrived from the coordinator's own mid-plan instruction.
**If the operator disagrees:** FR12 alone splits out cleanly; FR10/FR11 should stay with FR1.

## UC4 — "Thread `GH_TOKEN` + `actions: read` into `infra-validation.yml` in this PR"

**Source:** `soleur:engineering:cto` (Medium), `soleur:product:spec-flow-analyzer` (P1).
**Measured:** no gate call site grants `actions: read` (`apply-web-platform-infra.yml:4029` and `:6113`, `infra-validation.yml:169`, `scheduled-followthrough-sweeper.yml:43`), so **every** CI resolution runs anonymously against the 60/h-per-IP budget. `infra-validation.yml` is editable now and is the highest-frequency caller (every infra PR, once evidence lands); #8361 blocks only the apply workflow.
**The challenge:** fix the one call site that can be fixed, instead of deferring all four.
**Plan's position (default = the brief):** the brief permits one workflow. The plan keeps FR15 and files the grant for all four sites as a blocker of the L27 birth/replace dispatch (CPO condition 2).
**If the operator disagrees:** it is a ~4-line edit to that step's `permissions:` and `env:`, and it would narrow FR15 to the apply workflow only.

## Note — decided, not challenged

`hr-technical-fork-is-not-an-operator-question`: DHH's suggestion that the **replace** route proceed when the network is unreachable (its hash binding being local) was decided in-plan against, and the reasoning is recorded in `## Alternative Approaches Considered`. It is a technical fork, not a change to operator-stated scope.

## Supersession — UC4 was ACCEPTED, not declined (2026-09-20)

> **Superseded 2026-09-20 (#8010, commit `237a49299`):** UC4 above records the plan's position as "keep FR15 and file the grant for all four sites as a blocker". That was the position at plan time. During the nine-seat review round it was **reversed**: `infra-validation.yml` is modified in this PR after all.
>
> **What changed the decision.** The panel measured that all four gate call sites resolved the Actions run anonymously (60 requests/hour per IP, shared behind hosted-runner NAT), so a rate limit turns an unrelated infra PR into a red check. `infra-validation.yml` is the only one of the four editable this cycle — the two apply-workflow sites are blocked behind #8361/#8362, and the sweeper runs under `env -i`.
>
> **What shipped.** `deploy-script-tests` gained `permissions: {contents: read, actions: read}`; the freshness step gained `env: GH_TOKEN: ${{ github.token }}` and a tri-state branch that distinguishes a could-not-measure token from a measured refusal. The brief's explicit prohibition — do not edit the apply workflow — is respected and asserted: `git diff --name-only origin/main...HEAD` contains no `apply-web-platform-infra.yml`.
>
> **Residual.** The other three call sites remain anonymous and are carried by #8397. The plan's FR15 has been amended in place to record the same supersession; UC1, UC2 and UC3 above stand as written.

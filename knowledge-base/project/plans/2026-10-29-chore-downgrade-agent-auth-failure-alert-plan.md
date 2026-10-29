---
title: "chore: downgrade the agent-auth-failure diagnostic alert (step 1 of #11085)"
date: 2026-10-29
slug: downgrade-agent-auth-failure-alert
branch: feat-one-shot-11085-downgrade-agent-auth-alert
issue: 11085
type: chore
lane: single-domain
closes: none
pr_body_reference: "Ref #11085"
---

## Overview

Step 1 of the two-step takedown tracked on #11085: stop the temporary `agent-auth-failure` Sentry
rule from emailing anyone, while the Sentry issue, the ten tags and the pino/Better Stack line
(`feature=agent-auth`) stay in place. Step 2 (removal of the rule, both guard tests, the emit and the
other items of the checklist in the header of `apps/web-platform/server/agent-auth-mode.ts`) is a
separate later pass, at the root-cause fix (#11086) or on 2026-11-26 (30 days after the first event
of 2026-10-27T09:01Z), whichever comes first. The 48-hour downgrade deadline was 2026-10-29T09:01Z,
so this is time-sensitive. The PR body says `Ref #11085` and closes nothing.

**The one technical fork, and its ruling.** The issue says "drop the rule's email action". The pinned
provider (jianyuan/sentry 0.15.7) cannot express a rule with zero actions: `terraform validate` on a
scratch config with `actions = []` fails with `Attribute action_filters[0].actions list must contain
at least 1 elements, got: 0` (measured 2026-10-29; `action_filters` and `actions` are both Required).
Ruled by CTO agent, 2026-10-29: keep the rule enabled with exactly one action,
`email = { target_type = "issue_owners", fallthrough_type = "NoOne" }`. That is the idiom three live
rules in `issue-alerts.tf` already use for "lands in the issue stream to be read, not pushed", and
the project has no Sentry ownership rule, so `issue_owners` resolves to nobody and `NoOne` alone decides
delivery. Everything else about the rule stays byte-identical. See `decision-challenges.md`.

## Enhancement Summary

**Deepened on:** 2026-10-29 (targeted pass: the change is one attribute value, so the 40-agent fan-out was not run; the halt gates and a live-fact verification pass were).
**Gates run:** User-Brand Impact (4.6, threshold `none` with the sensitive-path scope-out present), Observability (4.7), PAT-shaped variable sweep (4.8, no hits), Encryption Posture (4.10, skip stated), Guard Contract (4.11, `scripts/lint-guard-contract.py` green), Scope Check (4.12, section rebuilt to the Ask Mapping / Provenance / Split schema), no UI surface (4.9), no network/SSH trigger (4.5), no downtime trigger (4.55: an in-place alert-rule update, no host or DB change).
**Plan-review panel (DHH, Kieran, code-simplicity):** applied the mechanical findings (tolerant regex instead of string equality, extractor pushes a problem rather than throwing, the `noOne` red-goes row rewritten so it cannot pass vacuously, two pinned single-line phrases named, redundant Phase 0/C4/scratch-validate steps cut, caveat stated once). Kept the heading rename in the README responder steps because "When the email arrives" would become false.

### Key verifications (live, 2026-10-29)
- `terraform validate` with `actions = []` on provider 0.15.7: `list must contain at least 1 elements, got: 0` (why the form is one `NoOne` action).
- `frequency_minutes = 40` appears once in the Sentry root (`issue-alerts.tf`), so uniqueness holds and the value is unchanged.
- The README's pinned phrase `removal checklist in the header of \`server/agent-auth-mode.ts\`` sits on one line (Lifecycle paragraph); the `apply-sentry-infra.yml` header states "the PR merge IS the human authorization".
- `GET .../projects/jikigai-eu/web-platform/ownership/` with `SENTRY_ISSUE_RO_TOKEN` returned HTTP 403 (scopes `event:read, org:read`), so the ownership-rule premise stays at its 2026-09-06 measurement.
- ADR ordinal note: two files carry the `ADR-031` prefix (`ADR-031-sentry-as-iac.md` and `ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md`); this plan means the former.

## Research Insights

**Premise Validation.** Checked: #11085 is OPEN and its Step 1 text matches the brief; #11086 OPEN; #10455
OPEN and carries the first-event tuple record; draft PR #11482 is this branch (the collision pre-check
reports only it, plus three foreign `test-all.sh` processes in another worktree that touch nothing here).
`sentry_alert.agent_auth_failure` exists on `origin/main` in `apps/web-platform/infra/sentry/issue-alerts.tf`,
the reference entry `agent-auth-failure` exists in `alert-reference.json`, and both guard tests exist. ADR
corpus: ADR-031 (Sentry as IaC) owns the reference-equals-plan-projection rule and ADR-260 (Slack wake path,
unverified) is why nothing is paged; neither rejects the `NoOne` idiom. Stale: nothing.

**Property List.**
1. No person is emailed by `agent-auth-failure` events after the merge applies.
2. The Sentry issue (one constant-message group), the ten tags and the Better Stack pino line are unchanged.
3. `alert-reference.json` equals the plan projection in the same PR (the `plan_pr` gate stays green and the daily live-fidelity probe sees no DRIFT).
4. The guard tests and the README describe the downgraded state, so a future edit that restores paging goes red.
5. The rule, tags and emit remain, so step 2 stays a single removal pass.

**Cut List.** (mechanism -> property -> what already covers it)
- Delete the rule now -> reverses property 5 -> contradicts the operator's scope; step 2 owns it.
- `enabled = false` with the email action kept dormant -> property 1 -> `NoOne` already delivers to nobody, while a disabled rule keeps the paging config one flag away from re-paging; the live-fidelity probe also flags a live-disabled rule as `DISABLED`.
- A non-email action (webhook, slack, plugin) -> property 1 -> needs an integration id and notifies elsewhere; none needed.
- New tags or matcher patterns -> none -> explicitly out of scope per the brief.
- A new standalone "downgrade" test file -> property 4 -> the existing contract test already parses the .tf and the reference; edit it instead.

**How the email action is pinned today (the sweep).** A search for `ActiveMembers|NoOne|email` over the relevant files:
- `issue-alerts.tf` resource block: the `email` action with `ActiveMembers`, plus two comment paragraphs ("Email only (issue owners, ActiveMembers fallthrough...)" and "Lifecycle: the email action is dropped within 48 hours").
- `alert-reference.json` key `agent-auth-failure`: `fallthroughType: "ActiveMembers"`.
- `test/sentry-agent-auth-failure-alert-op-contract.test.ts`: `ruleProblems()` requires the exact `ActiveMembers` email regex and bans `NoOne`; `expectedReferenceEntry()` hard-codes `ActiveMembers`; `RULE_FIXTURE` carries it; the harness row "disabling the rule ... or NoOne fallthrough goes red" asserts `NoOne` is red.
- `test/agent-auth-failure-sentry-path.test.ts`: no pin (a search for `email|ActiveMembers|NoOne|alert-reference` is empty).
- `server/agent-auth-mode.ts` removal checklist item 5 names deleting the rule; it does not mention the action, so it needs no edit.
- `README.md` section "Diagnostic rule: agent-auth-failure": the opening paragraph ("emails `issue_owners` -> `ActiveMembers`", "Email only: nobody is paged..."), "When the email arrives (responder steps)", responder step 3 ("swallow the next real email") and the "Lifecycle" paragraph ("a PR drops the rule's email action").
- No other test pins this rule: the `NoOne`-aware siblings (`sentry-fresh-boot-luks-alert-op-contract`, `sentry-git-data-warning-stages-op-contract`) are scoped to their own rules, and `sentry-no-text-block-alert-op-contract` bans `NoOne` only inside its own rule block.

**Ownership-rule caveat (carried from the ruling, not re-measurable here).** Delivery by `NoOne` rests on the 2026-09-06 measurement that
`GET /api/0/projects/<org>/web-platform/ownership/` returns `"raw": null` (comment in `issue-alerts.tf`). Re-measuring on 2026-10-29
with `SENTRY_ISSUE_RO_TOKEN` returns HTTP 403 (the token's scopes are `event:read, org:read`), so the CTO's flip condition ("a non-null
`raw` means use `enabled = false` instead") cannot be checked with the read-only token. Residual risk: an ownership rule added before
step 2 would make `issue_owners` resolve and re-enable mail. It is bounded by step 2 (the rule is deleted) and made visible by the
comment the PR adds above the resource.

**Learnings applied.** `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody` (an alert's delivery is a claim about each hop; check
the routing rather than assuming it, here the inverse: confirm it routes to nobody); ADR-031's "reference equals plan projection" convention.

**Open Code-Review Overlap.** None (open `code-review` issues searched by body for each of the five files: no matches).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Drop the email action from sentry_alert.agent_auth_failure in apps/web-platform/infra/sentry/issue-alerts.tf" [brief] | Phase 1 (CTO-ruled form: one `NoOne` email action, since the provider rejects zero actions) | mapped |
| 2 | "keep the Sentry issue and the pino/Better Stack line (feature=agent-auth)" [brief] | Phase 1 changes no emit, tag, filter or trigger; AC4 | mapped |
| 3 | "update apps/web-platform/infra/sentry/alert-reference.json in the same PR so the plan-projection gate stays green" [brief] | Phase 2, AC2, AC6 | mapped |
| 4 | "Update the README section \"Diagnostic rule: agent-auth-failure\"" [brief] | Phase 4, AC5 | mapped |
| 5 | "any guard tests that pin the email action" [brief] | Phase 3, AC3 | mapped |
| 6 | "without removing the rule, the tags or the emit" and "Do not extend the diagnostic with new tags or matcher patterns" [brief] | Non-Goals, AC4 | mapped |
| 7 | "Use \"Ref #11085\" in the PR body, and close nothing" [brief] | AC8, Phase 5 | mapped |
| 8 | "Every infra apply on merge is production-mutating: note that in the plan." [brief] | Infrastructure (IaC) section, Apply path | mapped |
| 9 | "have the CTO rule on it" (the zero-actions fork) [brief] | Overview ruling, `decision-challenges.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `issue-alerts.tf` edit (Phase 1) | "Drop the email action from sentry_alert.agent_auth_failure" (asks 1-2) | asked |
| `alert-reference.json` edit (Phase 2) | "update apps/web-platform/infra/sentry/alert-reference.json in the same PR" (ask 3) | asked |
| `README.md` edit (Phase 4) | "Update the README section" (ask 4) | asked |
| contract test edit (Phase 3) | "any guard tests that pin the email action" (ask 5) | asked |
| Phase 0 baseline `terraform validate` | — | inferred — justification: `terraform validate` is the only local check that the provider still accepts the edited block, and ask 3 requires the plan gate to stay green |
| Phase 5 verification run | — | inferred — justification: the red-then-green guard run is how ask 5 is shown to hold; no new file is added |
| `decision-challenges.md` and `tasks.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table" (ask 9) | asked |

### Split Assessment

- Subsystems touched: 2 — apps/web-platform/infra/sentry, apps/web-platform/test
- Planned files: 4 edited (plus plan, tasks and decision-challenges artifacts) | Estimated changed lines: ~70
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Non-Goals

- Step 2 (removal of the rule, reference entry, README section, both guard tests, wiring pins, emit, signatures): stays tracked on #11085, no new issue needed.
- New tags, new matcher patterns, a changed `frequency_minutes` (40 stays, the unique value this root's dedup convention reserves), a changed trigger or filter.
- Slack/paging (ADR-260 unverified) and any ownership rule.
- The root-cause fix and the friendly error: #11086.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: Phase 3 (guard flip) runs red first against the unchanged .tf, then Phases 1-2 turn it green.

### Phase 0: pre-flight (read-only)
- 0.1 Baseline the Sentry root without a backend: `terraform -chdir=apps/web-platform/infra/sentry init -backend=false -input=false` then `terraform -chdir=apps/web-platform/infra/sentry validate` (provider 0.15.7 is in the local plugin cache). Expect `Success`.

### Phase 3 (runs first): flip the guard test, watch it go red
`apps/web-platform/test/sentry-agent-auth-failure-alert-op-contract.test.ts`:
- `ruleProblems()`: replace the `ActiveMembers` email-regex check with a single-action check: the block's `actions = [ ... ]` must match one tolerant regex (every gap is `\s*`, so a `terraform fmt` realignment cannot redden it) that admits exactly one entry, the `issue_owners` + `NoOne` email (trailing comma optional). When the regex does not match (for example the `noEmail` row empties the body), the extractor must PUSH the problem, never throw. Message: `"actions must be exactly one email issue_owners + NoOne (downgraded, #11085 step 1)"`. Invert the old `fallthrough NoOne` ban into an `ActiveMembers` ban (one line, a clearer message than the regex miss). Keep every other check (feature+op filters, `logic_type all`, enabled, trigger, unique frequency, `monitor_ids`, `ignore_changes`).
- `expectedReferenceEntry()`: `fallthroughType: "NoOne"`.
- `RULE_FIXTURE`: `fallthrough_type = "NoOne"`.
- Header and chain comments ("-> live rule -> email action") reworded to the downgraded contract; keep the phrases other cases match: README `one copy of the tag decode table`, `removal checklist in the header of server/agent-auth-mode.ts`, `never archive or ignore it`, `2026-11-30`.
- The red-goes row at the `noOne` mutation (it replaces `ActiveMembers` with `NoOne`, which becomes a no-op once the fixture is `NoOne`) is rewritten to replace `"NoOne"` with `"ActiveMembers"`, with `expect(mutated).not.toBe(RULE_FIXTURE)` so it cannot pass vacuously.
- Harness rows (see Guard Contract): flip "NoOne fallthrough goes red" to "ActiveMembers fallthrough goes red"; add one row, "a second action after the compliant first goes red" (the same regex covers it; no extra code); keep the must-pass non-canonical rows (reordered filters, a different unique frequency).
- Run `cd apps/web-platform && npx vitest run test/sentry-agent-auth-failure-alert-op-contract.test.ts`: expect RED on the live-rule and reference cases (the .tf and JSON still carry `ActiveMembers`) and green on the harness rows.

### Phase 1: the Terraform change
`apps/web-platform/infra/sentry/issue-alerts.tf`, resource `sentry_alert.agent_auth_failure`:
- `actions = [ { email = { target_type = "issue_owners", fallthrough_type = "NoOne" } } ]` (a one-word value change).
- Header comment: replace "Email only (issue owners, ActiveMembers fallthrough...)" with a DOWNGRADED paragraph: since 2026-10-29 (step 1 of #11085) the action is `issue_owners` + `NoOne`, which delivers to nobody because the project has no Sentry ownership rule (cite the "WHAT WAS MEASURED (2026-09-06)" comment further up this file); the provider rejects zero actions (`list must contain at least 1 elements`, measured 2026-10-29, v0.15.7), so a no-mail rule still needs one action; adding an ownership rule would make `issue_owners` resolve and re-enable mail, so none may be added before step 2; the rule is deleted at step 2. Rewrite the Lifecycle sentence ("the email action is dropped within 48 hours...") to past tense for step 1 and keep the step 2 trigger and the checklist pointer verbatim (`removal checklist is in the header of server/agent-auth-mode.ts`). Reword the GROUPING sentence: the constant message still gives ONE Sentry issue; drop "the 40-minute re-notify bounds the email volume" (no mail is sent) and say 40 is kept so the reference diff is one field and the value stays unique.
- Do NOT touch `frequency_minutes`, `trigger_conditions`, the two `tagged_event` conditions, `monitor_ids` or `lifecycle`.

### Phase 2: the reference
`apps/web-platform/infra/sentry/alert-reference.json`: key `agent-auth-failure`, `actionFilters[0].actions[0].fallthroughType` `"ActiveMembers"` -> `"NoOne"`. Nothing else; keep it `jq -S`-sorted (a contract case asserts key order).

### Phase 4: README
`apps/web-platform/infra/sentry/README.md`, section "Diagnostic rule: `agent-auth-failure` (temporary, #10455 / #10548)":
- Opening paragraph: the rule no longer emails; it routes `issue_owners` -> `NoOne` (delivers to nobody) and exists to keep the Sentry issue grouped and the tags searchable; the pino line to Better Stack is unchanged. The provider-limit and ownership-rule reasons live once, in the .tf comment; the README points there.
- Rename "When the email arrives (responder steps)" to "When you read the issue (responder steps)": step 1 starts from the issue stream or the Discover read command below; step 3 keeps `Resolve the issue after recording the tuple; never archive or ignore it` (required text) with the rationale reworded (a benign tenant-key event groups with the real outage signal, so an archived issue hides the next real occurrence from the stream); steps 2, 4, 5 unchanged.
- Two pinned phrases stay on ONE line each when rewrapping: README ``removal checklist in the header of `server/agent-auth-mode.ts` `` (Lifecycle paragraph) and, in the .tf, `removal checklist is in the header of server/agent-auth-mode.ts`; also leave the .tf line matching `README\.md[^\n]*one copy of the tag decode table` untouched.
- "Lifecycle": step 1 recorded as done (downgraded 2026-10-29, #11085; first event 2026-10-27T09:01Z, tuple on #10455); the step 2 trigger is unchanged (root-cause fix, or 30 days after the first event = 2026-11-26) and the `2026-11-30` absolute-fallback sentence is kept verbatim.
- Header counts ("49 `sentry_alert` rules") are unchanged: no rule is added or removed.

### Phase 5: verify and hand off to ship
- `cd apps/web-platform && npx vitest run test/sentry-agent-auth-failure-alert-op-contract.test.ts test/agent-auth-failure-sentry-path.test.ts` green.
- `terraform -chdir=apps/web-platform/infra/sentry validate` green; `terraform fmt -check` on `issue-alerts.tf`.
- The authoritative reference-equals-projection check is the PR-time `plan_pr` job (the gate needs `terraform show -json` of a real plan, which needs Sentry credentials; do not hand-craft a plan JSON).
- PR body: `Ref #11085` (never a closing keyword), the CTO ruling row, the production-mutating note below.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`
- `apps/web-platform/infra/sentry/README.md`
- `apps/web-platform/test/sentry-agent-auth-failure-alert-op-contract.test.ts`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11085-downgrade-agent-auth-alert/decision-challenges.md` (written)
- `knowledge-base/project/specs/feat-one-shot-11085-downgrade-agent-auth-alert/tasks.md`

`apps/web-platform/server/agent-auth-mode.ts` is deliberately NOT edited: its removal checklist item 5 deletes the rule wholesale and says nothing of the action.

## Acceptance Criteria

- [x] AC1. `issue-alerts.tf` `sentry_alert.agent_auth_failure` carries exactly one action, `email = { target_type = "issue_owners", fallthrough_type = "NoOne" }`; the block contains no `ActiveMembers`.
- [x] AC2. `alert-reference.json` `agent-auth-failure.actionFilters[0].actions[0].fallthroughType == "NoOne"` and the entry is otherwise unchanged (the diff is that one line).
- [x] AC3. The contract test is red against the unchanged .tf/JSON (Phase 3) and green after Phases 1-2; the Guard Contract mutations 1-2 are in-test fixture rows, so they run on every CI pass without a hand-run campaign.
- [x] AC4 (2026-10-29: amended). No change to `frequency_minutes = 40`, `trigger_conditions`, the `feature`/`op` conditions, `monitor_ids`, the emit in `server/agent-auth-failure.ts`, the ten tags, `claude-error-signatures.ts` or the other guard tests; `git diff --stat origin/main...HEAD` lists only the Files to Edit plus plan artifacts, with one addition made at review: a comment-only edit in `server/agent-auth-failure.ts` (the safety header claimed a tenant could mute the outage's "email"; the emit, tags and matcher are untouched, verified by a diff that shows comment lines only).
- [x] AC5 (2026-10-29: amended; reviewed by reading, not enforced by a test: no case pins the README's emailing wording). README: no sentence says the rule emails a person; it still contains `never archive or ignore it`, `2026-11-30` and the step 2 trigger, and "Lifecycle" records step 1 as taking effect when the change is applied on merge (not as already done, per the review's git-history seat: the Sentry rule changes only at the apply); the contract test's README case passes. The README also states that Sentry's vendor-default high-priority workflow can still email, which this plan had not anticipated.
- [ ] AC6. `terraform validate` passes in the Sentry root; the PR-time `plan_pr` job (reference-equals-projection gate) is green.
- [ ] AC7. Post-merge: `apply-sentry-infra.yml` succeeds on the merge commit with an in-place update of one `sentry_alert` and zero destroys (no `[ack-destroy]` needed), and the live-fidelity probe reports no DRIFT for `agent-auth-failure`.
- [ ] AC8. The PR body uses `Ref #11085` and contains no closing keyword for #11085, #11086, #10455 or #10548.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; this is an internal alert route. The worst case is that the diagnostic keeps emailing the founder (stale noise) or that a later auth outage on the Concierge raises no email because the rule is now silent by design; the first real events are already recorded and root-cause work continues on #11086.
**If this leaks, the user's data is exposed via:** no vector; the change removes a notification target and adds no data path (events still carry only ten closed-enum tags).
**Brand-survival threshold:** none. threshold: none, reason: the diff edits a Sentry notification route and its docs and tests only, with no user data, credential or user-facing surface touched.

## Infrastructure (IaC)

Not new infrastructure; an in-place change to an existing Terraform-owned `sentry_alert` in `apps/web-platform/infra/sentry/`.

### Terraform changes
`issue-alerts.tf` (one resource, one attribute value). Provider `jianyuan/sentry` 0.15.7 unchanged. No sensitive variables.

### Apply path
Merge-triggered: `.github/workflows/apply-sentry-infra.yml` applies the whole root on push to main (path filter `apps/web-platform/infra/sentry/**`). **This apply is production-mutating**: it rewrites the live Sentry workflow `agent-auth-failure` in the `jikigai-eu` org. It is an in-place update (expected plan: `1 to change, 0 to add, 0 to destroy`), reversible by reverting the PR (which re-applies `ActiveMembers`), and covered by this root's standing model ("the PR merge IS the human authorization", workflow header). Nothing further is asked of anyone; the plan job's output must show zero destroys before merge.

### Host fan-out
Not applicable (no `terraform_data` SSH provisioner involved).

### Distinctness / drift safeguards
`frequency_minutes = 40` is unchanged, so it stays unique in the root. `lifecycle { ignore_changes = [environment] }` unchanged. The daily live-fidelity probe compares `actionFilters` field for field, so the reference and live must both carry `NoOne` after the apply.

### Vendor-tier reality check
Provider limit, measured: `actions` must contain at least one element. Sentry's own API behaviour for a zero-action workflow was not probed (the provider forbids it, and a direct API write would bypass Terraform).

## Encryption Posture

Skipped: no persistent data store and no new cross-component connection is introduced (a `.tf` edit to an existing alert rule).

## Architecture Decision (ADR/C4)

No ADR or C4 change. The decision is a per-rule routing value inside ADR-031's existing mechanism and the same idiom three sibling rules already use; no ownership or tenancy boundary, substrate, trust boundary or ADR reversal. C4 check: the Sentry system and the app-to-Sentry edges are already modelled, and this change adds no actor, system, container or access relationship; no derived cardinality in `model.c4` moves (no rule added or removed, the 49-rule count is unchanged),.

## Observability

```yaml
liveness_signal:
  what: the Sentry issue for feature=agent-auth op=cli-auth-failure keeps receiving events (Discover count over 24h) and the pino line reaches Better Stack
  cadence: per occurrence of the CLI "Not logged in" reply (event-driven; deduplicated per user+tuple per 5 min, 10 per 5 min process-wide)
  alert_target: none by design after this PR (reads only: the Discover query in the infra/sentry README, and the Better Stack query for feature == "agent-auth")
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (rule kept, delivery NoOne); apps/web-platform/server/agent-auth-failure.ts (emit, unchanged)
error_reporting:
  destination: Sentry (issue, message path) and Better Stack (pino error line), both unchanged
  fail_loud: false (deliberately downgraded; the cause is tracked on #11086 and the diagnostic is removed at step 2)
failure_modes:
  - mode: the live rule keeps the old ActiveMembers action after merge (apply failed or drift)
    detection: apply-sentry-infra.yml post-apply probe and the daily sentry-alert-live-fidelity probe (DRIFT on actionFilters)
    alert_route: the existing drift tracking issue
  - mode: an ownership rule is added to the project, so issue_owners resolves and mail resumes
    detection: not detectable by this PR (the read-only token gets 403 on the ownership endpoint); bounded by step 2 deleting the rule
    alert_route: none (accepted residual risk, recorded in the .tf comment and the CTO ruling)
logs:
  where: Better Stack (pino line, feature=agent-auth); Sentry event store
  retention: vendor defaults, unchanged
discoverability_test:
  command: jq -r '.["agent-auth-failure"].actionFilters[0].actions[0].fallthroughType' apps/web-platform/infra/sentry/alert-reference.json
  expected_output: NoOne
```

## Guard Contract

### Guard 1 — agent-auth-failure rule contract (`sentry-agent-auth-failure-alert-op-contract.test.ts`, edited)

**Property.** While the diagnostic is downgraded, the only action on `sentry_alert.agent_auth_failure` is an `issue_owners` email with `NoOne` fallthrough, the committed reference says the same, and nothing else about the rule drifts.

**Assembly.** Three committed artifacts agree: the live HCL block (comment-stripped), `alert-reference.json`'s `agent-auth-failure` entry, and the README section. The chokepoints are `ruleProblems()` for the HCL and `expectedReferenceEntry()` for the JSON. The anchor outside this commit is `scripts/sentry-alert-reference-gate.sh` (the `plan_pr` job holds the reference equal to the Terraform plan projection) plus the daily live-fidelity probe; this test proves the committed artifacts agree with each other, not that live Sentry matches.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expected failure |
|---|---|---|
| 1 | Restore `fallthrough_type = "ActiveMembers"` in the block (the pre-downgrade shape) | `ruleProblems` reports the single-action and mail-reaches-a-person problems |
| 2 | Add a second action after the compliant first (a second email with `target_type = "team"`, or a slack/webhook entry) | the single-action check reds (a check that stops at the first member is itself the defect) |
| 3 | Edit the reference entry back to `ActiveMembers`, or change its `frequency` | the reference case reds (`toEqual` against `expectedReferenceEntry`) |
| 4 | Delete the whole `sentry_alert "agent_auth_failure"` block (the guard's own dispatch) | `no live sentry_alert "agent_auth_failure" block`; the server-walk floors (>= 200 sources, `app/` and `lib/` walked) keep the emit cases from passing vacuously |

Harness rows: (a) MUST-RED, an edit to the SUITE rather than the guard: make `ruleProblems` return `[]` unconditionally and confirm the fixture-mutation rows 1-2 fail; (b) MUST-PASS non-canonical inputs: the two tag conditions in the opposite order, and a different unique `frequency_minutes`, both still pass (an all-rejecting guard cannot satisfy these).

## Test Scenarios

- Phase 3's red run before Phases 1-2 (the guard fails on the unchanged .tf and JSON), then green after.
- `terraform validate` and `terraform fmt -check` green on the Sentry root.
- The full contract file green, including the README case and the key-sort case.

## Sharp Edges

- Do not "simplify" to `actions = []`: it fails `terraform validate` on provider 0.15.7 and would red every Sentry-root PR.
- The reference diff must be exactly one field. Anything more (for example a reordered key) reds the `plan_pr` gate or the key-sort contract case.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails deepen-plan Phase 4.6; this one declares threshold `none` with a reason because the diff touches `infra/`.
- The README step 3 text and the `2026-11-30` sentence are pinned by the contract test; reword around them, not through them.
- After the apply, confirm the live rule through the existing read path (the live-fidelity result in the apply job), not by looking at a dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`).

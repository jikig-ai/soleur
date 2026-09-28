---
title: "sentry: page on git-data host-key pin faults (replication push, boot, Art. 17 erasure) — flag-flip precondition for #8211"
type: feat
date: 2026-09-28
slug: feat-sentry-git-data-pin-fault-paging
branch: feat-one-shot-8572-git-data-pin-fault-paging
issue: 8572
closes: none  # PR body carries `Ref #8572`; #8572 is closed post-merge once both deploy paths are green (Phase 6)
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: "SIGN-OFF 2026-09-28 (soleur:product:cpo, plan-time; notes folded into §D and Deferrals)"
lane: cross-domain
---

<!-- Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this one-shot branch. -->

# sentry: page on git-data host-key pin faults

## Enhancement Summary

**Deepened on:** 2026-09-28.

**Gates run** (all pass):

- 4.5 network-outage: Hypotheses present.
- 4.6 User-Brand Impact.
- 4.7 Observability, including the probe verb and Check 10 characters.
- 4.8 PAT-shape: none.
- 4.9 UI: no UI surface.
- 4.10 Encryption Posture.
- 4.11 Guard Contract (`lint-guard-contract.py` green, 2 entries).
- 4.55 downtime: not triggered. The rule-1b change is an in-place update, and the release is the
  routine deploy.

**Agents:** observability-coverage-reviewer, security-sentinel, test-design-reviewer,
user-impact-reviewer and terraform-architect (provider source read at the pinned v0.15.7), plus the
round-1 verify-the-negative and post-edit self-audit passes.

**Verified live in this pass:**

- Every cited issue and PR (`gh issue view`).
- Every cited rule id (`AGENTS.md`).
- The #8708 attribution (`git log`).
- The AC4 and AC5 `jq` programs and the AC3 grep, run against real reference entries.
- The discoverability command, through `probe-verb-gate.sh` (rc 0, no shell-active characters).

### Key Improvements

1. **Breadcrumb sink closed.** `reportGitDataPinFault` captures inside an isolation scope with
   cleared breadcrumbs, and a real-path test drives `replicateToGitData` with the real
   `observability` and `logger` modules. The sweep covers the whole payload, with a
   `hashUserId(WS)` positive control (security and test-design reviews).
2. **Guards made non-vacuous.** The census strips comments, excludes tests, matches the writer shape
   and proves it recursed. Guard 2 pins "exactly two conditions under `all`". New mutation rows cover
   `value = 1`, `interval = "1d"`, `enabled = false`, `logic_type = "none"` and the reference mirror.
   `ART17_ERASURE_*` constants replace source scraping.
3. **Typed error hardened.** The constructor builds its own fixed messages, and the classifier also
   accepts `err.name` (double module load) and validates `reason`.
4. **Operator path without SSH.** Push recovery is verified through Better Stack's
   `git_data_pin=present fp=` warn line (the success log line is `info` and never ships).
   `extra.via` tells a provision failure from a push failure. Layer citations were added to every
   failure mode.
5. **Post-merge checks widened.** The Phase 6 Sentry query catches boot events that landed before
   the rule existed, and checks no issue group is muted. The #8211 check must treat "no pin_fault
   event" as not-healthy. The re-erasure path is a **hard** flip precondition. On the red path, rule
   1b's live state is read (a drift dispatch needs the operator's per-step authorization).

### New Considerations Discovered

- The CTO's "any-short across two keys has never run" was false (`zot_mirror_fallback_rate`). The
  single-tag design stands on other grounds; it is corrected in place.
- The `pin_fault` tag is advisory. A compromised host can fake `host_key_mismatch` through
  relayed stderr, and a network attacker can suppress it pre-host-key. Nothing leaks either way,
  because the pin fails closed.
- The Terraform provider confirms: only `organization` forces a replace, so adding the 1b trigger is
  an in-place PUT. `frequency_minutes` is the per-issue interval over all triggers, with no cap. The
  1b ceiling is about 288 emails a day per persisting issue.
- Pre-existing: the non-pin push Error path still carries raw ids in `err.message`. Filed as #9154,
  outside this PR.

## Overview

Route the git-data host-key pin faults to a human through Sentry issue-alert rules. Today a stale,
malformed or missing pin, or a missing `ssh` client, is visible only to someone who queries for it.
The #8211 `GIT_DATA_STORE_ENABLED` flip is blocked on this (runbook
`git-data-luks-cutover-5274.md`, "Flag-flip precondition (hard)"; #8211 PR2's future
`pin_fault_paging_absent` verdict).

There are three surfaces, from the issue body and the scope extension in #8572
issuecomment-5866635102:

1. **Replication push**: `replicateToGitData`, `op=git_data_replication_push`.
2. **Boot**: `logGitDataHostKeyPinAtStartup` emits `pin_absent_at_startup`, `pin_invalid_at_startup`
   and `ssh_client_absent_at_startup` (added by PR #9096).
3. **Art. 17 erasure**: `erasure_outcome=unconfigured` with an `erasure_reason` tag, and
   `host_key_mismatch`.

The work has three parts:

- An app change so surfaces 1 and 2 carry one indexed `pin_fault` tag on Sentry's message path.
- One new `sentry_alert`, `git-data-host-key-pin-fault`, keyed on that tag.
- A trigger added to the existing `art17_erasure_incomplete` rule, so it keeps paging while
  erasures keep failing.

The rules reach production **only** through the existing merge-triggered
`.github/workflows/apply-sentry-infra.yml`. There is no manual `terraform apply` and no workflow
dispatch. The emitter reaches production only through the merge-triggered `web-platform-release.yml`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (verified in this worktree) | Plan response |
|---|---|---|
| "The app reports these through `reportSilentFallback` with `op: "git_data_replication_push"`", and a rule can match "op:git_data_replication_push with the pin-fault discriminator". | The push catch (`server/git-data-replication.ts`, `replicateToGitData` catch, anchor `feature: "worktree_lease",`) calls `reportSilentFallback(err, …)`, which is the **Error path**. Under #8629 (open), the pino mirror pre-captures the Error as `feature=pino-mirror` and Sentry drops the tagged capture. A rule keyed on this `op` is therefore **vacuous**. The push path also carries **no pin-fault discriminator**: that vocabulary exists only in `removeGitDataRepo`'s `GitDataErasureOutcome`. | Classify the push error. Report a pin fault on the **message path** (`err = null`) with `pin_fault=<reason>`. Other push failures keep the Error-path report unchanged. This is the one statement of the #8629 rationale; other sections refer back here. |
| The reason word is `pin_absent_store_enabled`. | Since PR #9096 it is `pin_absent`. `detail` sits in `extra`, which Sentry does not index. | The rule keys on the `pin_fault` tag only. |
| The boot ops use the message path, so their `feature`/`op` tags survive. | True: `logGitDataHostKeyPinAtStartup` makes three `reportSilentFallback(null, …)` calls. No rule routes them. | Add `pin_fault` to all three; they stay on the message path. |
| "Also page on Art. 17 `erasure_outcome=unconfigured` with `erasure_reason` tags." | `account-delete.ts` already emits on the message path with `{feature: account-delete, op: git-data-bare-repo-erasure, erasure_outcome, erasure_reason?}`. `art17_erasure_incomplete` filters on `feature`+`op` only, so it **already pages** every non-terminal outcome. Its triggers are only first_seen, reappeared and regression, so an issue left open swallows every later event with the same reason. | Add `event_frequency_count {1h, 0}` to `art17_erasure_incomplete` (CLO ruling). Do **not** tag erasure events with `pin_fault`: two rules would then email per event (CTO ruling). This is the one statement of that rationale; other sections refer back here. |
| #8211 PR2's flip mode refuses with `pin_fault_paging_absent` until this exists. | Not implemented yet: `pin_fault_paging` has no hit outside plans. | Give the rule a stable name. Post on #8211 what its check must verify (Phase 6). |
| The issue's re-evaluation trigger: "#8451's Sentry-provider migration has merged". | #8451 is CLOSED. Every rule is a `sentry_alert` and `plan_pr` works. | No blocker. |

**Premise Validation:**

- #8572 is OPEN. #8211 is OPEN and is the consumer.
- PR #9096 is MERGED (2026-09-28T11:00Z). It is the source of the boot ops and of `erasure_reason`.
- #8451 is CLOSED. #8629 is OPEN. #5914 and #7226 are CLOSED.
- The issue body's claim that the push report already carries the pin-fault vocabulary is **false**
  (see the table above).
- Every cited path exists on this branch.

## Research Insights

**Files and anchors (worktree, read directly):**

- `apps/web-platform/server/git-data-replication.ts` (811 lines):
  - `resolveGitDataHostKeyPin` throws a plain `Error`, and its messages never interpolate the
    value.
  - `logGitDataHostKeyPinAtStartup` makes three message-path reports.
  - `SSH_AUTH_FAILURE` and `SSH_HOST_KEY_MISMATCH` are regexes that are both case-insensitive.
  - `removeGitDataRepo` has a dedicated pin guard that re-reads the env. Its ENOENT arm uses
    `syscall.startsWith("spawn")`. Its host-key arm is `exitCode === 255 &&
    SSH_HOST_KEY_MISMATCH.test(detail)`.
  - In `replicateToGitData`, the pin is resolved **inside** the push `try`. Then
    `provisionGitDataRepo` → `sshWithPrivateKeyAuth` spawns `ssh`, and `gitWithPrivateKeyAuth`
    spawns `git`, whose ssh runs through `GIT_SSH_COMMAND` via `sh -c`. So a missing `ssh` shows
    there as `sh: 1: ssh: not found`, exit 128. Provision always runs first, fails with `spawn
    ssh`, and is what gets classified.
  - The comment at `replicateToGitData`'s doc says the next session force-pushes every head and
    tag, so the replica self-heals.
- `apps/web-platform/server/observability.ts` `reportSilentFallback`:
  - `err instanceof Error` → `captureException`, pre-empted by `server/logger.ts` `mirrorToSentry`
    (#8629).
  - Otherwise → `captureMessage(safeMessage, {level:"error", tags, extra:{err, …}, user})`.
  - Only `extra.userId` is renamed (to `userIdHash`). The pino line carries `feature`, `op` and
    `extra`, **not tags**.
  - `beforeSend` → `server/sentry-scrub.ts` `scrubSentryEvent` redacts by exact key name
    (`server/sensitive-keys.ts`). `pin_fault` is not a sensitive key.
- `apps/web-platform/server/account-delete.ts`: the erasure report is on the message path (anchor
  `erasure_outcome: outcome.status`). Its comment says "the alert fires only on first-seen /
  reappeared / regression", which becomes false.
- `apps/web-platform/server/git-data-client.ts` `fetchFromGitData` is a third pinned dial. See the
  Cut List.
- `apps/web-platform/server/index.ts`: `import "../sentry.server.config"` is the first import, and
  `logGitDataHostKeyPinAtStartup()` runs after it.
- `apps/web-platform/infra/sentry/issue-alerts.tf`:
  - Rule 1b `art17_erasure_incomplete`: `frequency_minutes = 5`, first_seen / reappeared /
    regression, feature+op `all`. Its comment wrongly says it "Keys on the `erasure_outcome` TAG".
  - Message-path precedents are `anthropic_credit_exhausted` (#8505) and `spawn_agent_dead_letter`
    (#8719): four triggers including `event_frequency_count {1h,0}`, own `frequency_minutes`
    1440/1442, `issue_owners` → `ActiveMembers`.
  - `sentry_alert` exposes no trigger `logic_type`. The provider always sends `any-short`, so
    triggers are OR'd (header comment of `issue-alerts.tf`).
- `frequency_minutes` values in use across the root (`grep -hE '^\s*frequency_minutes\s*=' apps/web-platform/infra/sentry/*.tf`):
  5 (×3), 10–27 (15, 22 ×2; 24 ×3), 30 (×2), 31, 60–63, 1440–1442. Several are shared. The
  precedent test only checks that a **new** rule's own value is unique. **240 is unused.**
- Current rule counts, comment lines stripped:
  - `issue-alerts.tf`: 34 `resource "sentry_alert"`. 2 have `fallthrough_type = "NoOne"`, 2 have
    `ignore_changes = all`.
  - `cron-monitor-alerts.tf`: 1.
  - `alert-reference.json`: 33 entries (the frozen two are excluded).
- `apps/web-platform/infra/sentry/alert-reference.json`:
  - Gated by `scripts/sentry-alert-reference-gate.sh` in `apply-sentry-infra.yml`'s `plan_pr`,
    which compares sorted forms. On a mismatch it uploads artifact
    `sentry-alert-reference-expected-<run-id>`.
  - After the apply, `scripts/sentry-alert-live-fidelity.sh` prints the live literal
    `sentry_alert live fidelity: PASS (all N in-scope rules match the committed reference
    field-for-field)`. It prints a distinct `PASS (FIXTURE — not live)` literal in fixture mode.
- Only `apply-sentry-infra.yml` applies this root (push on `apps/web-platform/infra/sentry/**`, plus
  PR-time `plan_pr`). `apply-web-platform-infra.yml`'s `infra/*.tf` does not reach `sentry/`.
  `sentry-audit-gate.yml` runs on `infra/sentry/**/*.tf` PRs.
- `scripts/followthroughs/phase3-ga-soak-5274.sh` queries `(level:error OR level:warning)
  (feature:worktree_lease OR …)`. So do runbook line ~1196 (`feature:worktree_lease level:error` =
  0). Push failures never reached it before (#8629). After this PR, push **pin faults** will.
- The existing boot tests `toEqual({feature, op, message})` on each of the three reports, so adding
  `tags` changes three assertions.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/2026-09-28-the-pinned-path-i-made-the-only-path-had-never-run-because-the-image-had-no-ssh.md`:
  a tag query over the Error path reads 0. Use the message path, one message per reason.
- `knowledge-base/project/learnings/2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`:
  the new rule needs an unused `frequency_minutes`.
- `knowledge-base/project/learnings/2026-06-03-sentry-alert-match-feature-only-when-feature-is-dedicated.md`:
  key on the tag dedicated to the signal.
- `knowledge-base/project/learnings/bug-fixes/2026-06-02-sentry-auth-alert-rules-drifted-to-empty-filters-not-a-red-herring.md`:
  the contract test asserts a non-empty filter.
- `knowledge-base/project/learnings/security-issues/2026-09-25-a-no-raw-id-claim-tested-at-the-call-args-missed-three-sinks-on-the-same-event.md`:
  the raw-id sweep runs over the real event, not the mock's arguments.

**Conventions:**

- `cq-silent-fallback-must-mirror-to-sentry`
- `hr-observability-layer-citation`
- `hr-menu-option-ack-not-prod-write-auth`: the merge click authorizes both applies.
- `cq-write-failing-tests-before`
- `cq-assert-anchor-not-bare-token`
- Dated legal and ADR records are append-only.

**Domain rulings (binding, plan time):**

- **CTO:**
  - Put one `pin_fault` tag on the boot and push emits, and route them with a single-condition
    `all` rule. The reasons: one exported vocabulary feeds both emit sites and the Terraform value
    list, and op names stay free to change without silently dropping paging. **[Deepen correction
    2026-09-28]** The CTO also said an `any-short` OR across two tag keys "has never run in this
    root". That is false: `zot_mirror_fallback_rate` ORs `registry` and `stage`. The decision
    stands on the two reasons above.
  - The typed resolver error is acceptable. Tighten ssh-absent to `spawn ssh`.
  - Use 4 triggers.
  - Add dated notes to ADR-237 and ADR-220. No new ADR. Change only the C4 count prose.
- **CLO:**
  - Rule 1b's first-seen-only paging is inadequate for Art. 12(3). Add `event_frequency_count`.
  - Land the register marker and the audit addendum **in this PR**, conditioned on the merge and a
    successful apply. Append the verification afterwards (#9077 precedent).
  - Use fixed-vocabulary tags only, and sweep the real event for raw ids.
  - No counsel re-attestation and no `clo-attestation` issue. `docs/legal/**` stays untouched.
- **CPO:** SIGN-OFF. The runbook must say to resolve a pin-fault issue after the fix. The Art. 12(3)
  clock is still started by hand (see Deferrals).
- **Plan-review panel:** changes applied are in "Review & Consult Provenance" below.

**Property List (Phase 0.6b):**

- P1: A pin fault on a replication push pushes an email to the operator.
- P2: An armed container that boots with an absent or invalid pin, or with no `ssh`, pushes an
  email.
- P3: An Art. 17 erasure that does not complete, pin faults included, emails even while an older
  Sentry issue for that outcome is still open. The cap is at most one email per issue per 5 minutes.
- P4: A pin fault that persists keeps paging (bounded) instead of going quiet after the first email.
- P5: #8211 can verify the paging exists: rule content live, emitter deployed.
- P6: No raw identifier reaches Sentry in the new events.

**Cut List (Phase 0.6b and plan review):**

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| A new rule for Art. 17 `erasure_reason`, or a `pin_fault` tag on erasure events | P3 | Rule 1b already routes every outcome; one added trigger buys P3 without a second email. |
| Refactoring `removeGitDataRepo` onto the new classifier | none | The erasure path works and is tested. Rewiring an Art. 17 path "for parity" is risk with no listed property (advisor, DHH and simplicity reviews). Deferred, characterization-first (see Deferrals). |
| `hostKeyReason` sub-split (`alg` / `unknown` / `changed`) | diagnosis | The cutover precheck's `_access_reason` gives the split on demand, and the runbook routes there. |
| Stderr `detail` on the push event | diagnosis | Free text: Node's `Command failed:` argv names the worktree id. |
| Pin-fault classification in `fetchFromGitData` | P1 | The pin, the host and the ssh client are process-wide and fixed for the process's life. The same fault shows on every push and at boot, and both now page. |
| Fixing #8629 fleet-wide | P1 | Out of scope, and it could revive dormant rules. The rule is robust to it: non-pin push failures carry no `pin_fault`. |
| Two new rules (boot and push) | P1, P2 | One tag, one rule, one name for #8211. |
| Adding the rule to `assert-byok-rules-exist.sh` `EXPECTED_RULES` | P5 | `sentry-alert-live-fidelity.sh` already checks every `sentry_alert` after each apply and daily. |
| A follow-through soak probe | — | No close criterion is time-gated. |
| Dropping the push-side `pin_absent` / `pin_invalid` / `ssh_client_absent` arms (simplicity review) | P1, P4 | **Rejected.** The boot event fires once per boot, so it cannot re-page (P4). The push arms emit on every session end while the fault persists, and the issue's own AC names the push op. |

**Functional overlap:** no community tool manages Terraform Sentry rules for this.

## Proposed Solution

### A. App

**New module `apps/web-platform/server/git-data-pin-fault.ts`.** It keeps the pin-fault vocabulary
out of the 811-line replication module. There is no import cycle: it imports only `observability`.

1. `export const GIT_DATA_PIN_FAULT_REASONS = ["host_key_mismatch", "pin_absent", "pin_invalid",
   "ssh_client_absent"] as const` and `export type GitDataPinFault`. The list is sorted, so the
   Terraform `in` string is its `join(",")`.
2. `export class GitDataHostKeyPinError extends Error` with `readonly reason: "pin_absent" |
   "pin_invalid"` and `name = "GitDataHostKeyPinError"`. The constructor takes **only** `(reason,
   { storeEnabled: boolean })` and builds the two fixed messages itself, byte-identical to today's
   resolver strings. No caller can pass text, so the pin value can never reach the message
   (security review).
3. The host-key regex `SSH_HOST_KEY_MISMATCH` moves here, exported, byte-identical.
   `git-data-replication.ts` imports it back, so the erasure path uses the same constant unchanged.
4. `export function classifyGitDataPinFault(err: unknown, via: "ssh" | "git"): GitDataPinFault |
   null`. It is total: the body sits in `try { … } catch { return null }`, and the catch carries
   `// review: swallowed — null falls through to the caller's Error-path report`
   (`cq-silent-fallback-must-mirror-to-sentry`; nothing is lost). Its arms:
   - `err instanceof GitDataHostKeyPinError`, **or** `err.name === "GitDataHostKeyPinError"` (a
     module loaded twice defeats `instanceof`), → `err.reason`, accepted only if it is a member of
     `GIT_DATA_PIN_FAULT_REASONS`.
   - `code === "ENOENT"` **and** `syscall === "spawn ssh"` → `ssh_client_absent`. `spawn git` does
     not match.
   - `typeof stderr === "string"` **and** `SSH_HOST_KEY_MISMATCH.test(stderr)` **and** the exit
     code matches the transport (255 when `via === "ssh"`, which is ssh's own status; 128 when
     `via === "git"`, which is git's fatal status when its ssh transport fails) →
     `host_key_mismatch`. A remote command's own non-255 exit through ssh is never read as a host
     fault (Kieran and architecture reviews).
   - Anything else → `null`.
5. `export function reportGitDataPinFault(reason: GitDataPinFault, site: { feature: string; op:
   string; message: string; extra?: Record<string, unknown> })`. It calls
   `reportSilentFallback(null, { ...site, tags: { pin_fault: reason }, extra: { ...site.extra,
   pinFault: reason } })`. The `extra.pinFault` copy exists because the pino line carries `extra`
   but not tags, so Better Stack also sees the reason. This function is the **only** writer of the
   `pin_fault` tag in the app.

   The call runs inside `Sentry.withIsolationScope((scope) => { scope.clearBreadcrumbs(); … })`, the
   precedent inventoried in `server/sentry-scrub.ts`. The session-end call sites open no scope of
   their own, so without this the event would carry other sessions' breadcrumbs. Those can hold raw
   workspace paths, and the scrub redacts by key name, not by value (security review).

   The module header carries the same "MESSAGE PATH ON PURPOSE" note as the precedents
   `server/anthropic-credit.ts` and `server/spawn-dead-letter.ts`: dedicated module, exported
   vocabulary constants, one reporting helper. This is the precedent diff; the only deviation is the
   isolation scope above.

**Edits in `apps/web-platform/server/git-data-replication.ts`:**

6. `resolveGitDataHostKeyPin` throws `GitDataHostKeyPinError` with **byte-identical messages**. It is
   exported, `git-data-client.ts` uses it, and the tests match `/GIT_DATA_SSH_HOST_KEY/`. A side
   effect: the Error-path grouping name of rehydration failures in `git-data-client.ts` changes from
   `Error` to `GitDataHostKeyPinError`. That is harmless, and the PR body will say so.
7. **Boot.** The three reports in `logGitDataHostKeyPinAtStartup` go through
   `reportGitDataPinFault` with `pin_invalid`, `pin_absent` and `ssh_client_absent`. `feature`,
   `op` and `message` stay byte-identical, because the runbook and the counsel audit query those
   strings.
8. **Push.** `replicateToGitData` sets a local `let via: "ssh" | "git" = "ssh"` before pin
   resolution and provision, and sets `via = "git"` immediately before `gitWithPrivateKeyAuth`. In
   the catch:
   - `const pinFault = classifyGitDataPinFault(err, via)`.
   - If it is non-null, call `reportGitDataPinFault(pinFault, { feature: "worktree_lease", op:
     "git_data_replication_push", message, extra: { workspaceIdHash, worktreeIdHash,
     leaseGeneration, userId, via } })`, where `message` is the template literal
     "git-data replication push pin fault (<reason>): the workspace's objects were NOT replicated
     to the shared store". The reason leads the message, so each reason is
     its own Sentry issue. No stderr and no `err.message` is sent.
   - Otherwise, keep the existing Error-path report byte-identical.
   - Exactly **one** Sentry capture per failure either way. The message path logs `{err: null}`, so
     the pino mirror captures nothing extra. The re-throw is unchanged.
   - Add a comment at the provision call: provision must stay **before** the git push, because a
     missing `ssh` only reads as `spawn ssh` ENOENT there. Under git it is `sh: ssh: not found`.
9. **The erasure path is not touched** beyond importing `SSH_HOST_KEY_MISMATCH` from the new
   module. The `GitDataHostKeyPinError` its guard now catches is still classified by the unchanged
   `inspectGitDataHostKeyPin()` re-read.

**Edit in `apps/web-platform/server/account-delete.ts`:**

- Export `ART17_ERASURE_FEATURE = "account-delete"` and `ART17_ERASURE_OP =
  "git-data-bare-repo-erasure"`, and use them at the two erasure report sites (the outcome report
  and the throw arm).
- This is behavior-neutral. It exists so Guard 2 imports the literals instead of scraping one pair
  out of about 40 `feature: "account-delete"` sites (test-design review).
- Append a dated comment under the "first-seen / reappeared / regression" comment (anchor `const
  reason =`) that corrects it: rule 1b now also re-pages per event (#8572).

### B. Terraform (`apps/web-platform/infra/sentry/issue-alerts.tf`)

1. **New rule**, appended after `spawn_agent_dead_letter`:

   ```hcl
   resource "sentry_alert" "git_data_host_key_pin_fault" {
     organization      = var.sentry_org
     name              = "git-data-host-key-pin-fault"
     enabled           = true
     frequency_minutes = 240
     monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

     trigger_conditions = [
       { first_seen_event = {} },
       { reappeared_event = {} },
       { regression_event = {} },
       { event_frequency_count = { interval = "1h", value = 0 } },
     ]

     action_filters = [
       {
         logic_type = "all"
         conditions = [
           { tagged_event = { key = "pin_fault", match = "in", value = "host_key_mismatch,pin_absent,pin_invalid,ssh_client_absent" } },
         ]
         actions = [
           { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
         ]
       },
     ]

     lifecycle {
       ignore_changes = [environment]
     }
   }
   ```

   The comment block must cover these points:
   - Why the rule keys on the tag (see Reconciliation, #8629).
   - The single writer: `server/git-data-pin-fault.ts` `reportGitDataPinFault`.
   - Grouping is per message, so one Sentry issue per surface and reason.
   - **`frequency_minutes = 240` is Sentry's per-issue action interval.** It applies to all four
     triggers. A persisting fault re-pages at most every 4 h per issue, which is at most about 6
     emails a day per live issue. A fault that recurs within 4 h of a resolve is silent: the
     runbook tells the operator to run the `pin_fault:*` query after resolving. The interval was
     chosen over 1443, which is a 24 h blind window (advisor and spec-flow reviews), and over
     hourly, which is the cadence that got the credit-probe monitor muted (#8704).
   - Before the flip, only the boot arm can fire.
   - This rule is #8211's `pin_fault_paging_absent` anchor.
   - `SSH_HOST_KEY_MISMATCH` also matches an absent or unwritable known_hosts file under
     `StrictHostKeyChecking=yes`.
   - The tag is **advisory**. ssh passes remote stderr through, so a compromised host that already
     holds the pinned key can print a host-key message and fake `host_key_mismatch`. A network
     attacker can also fail the connection before the host-key check, which stays unclassified.
     Neither leaks anything, because the pin still fails closed. The remedy is never to re-pin to
     the key a host presents (the runbook's H4 rule).
2. **Rule 1b** `art17_erasure_incomplete`:
   - Append `{ event_frequency_count = { interval = "1h", value = 0 } }` to `trigger_conditions`.
     Leave `frequency_minutes = 5`, the filters and the action unchanged.
   - Append a dated comment (`# (2026-09-28, #8572) …`) under the existing block comment. Do not
     edit that comment in place. The appended comment:
     - corrects "Keys on the `erasure_outcome` TAG" (the rule filters on `feature`+`op` only, which
       is why every outcome routes);
     - corrects "The four routed values are …" (the set is now `refused | unauthorized |
       unconfigured | unreachable | host_key_mismatch | threw`, and `unconfigured` carries
       `erasure_reason`);
     - records the CLO ruling and the throttle ("at most one email per issue per 5 min, not per
       refusal"), with the daily ceiling spelled out: a persistently failing issue can send up to
       288 emails a day (terraform review);
     - points to the Reconciliation rationale for not tagging erasure events with `pin_fault`.
   - This is an **in-place update**: same address, native triggers only, so the frozen-rules
     tripwire does not fire. #8708 is the precedent for an in-place change to a live rule.
3. **`alert-reference.json`**: add the `git-data-host-key-pin-fault` entry and append the
   `event_frequency_count` trigger to `art17-erasure-incomplete`. Hand-author them from the
   `spawn-agent-dead-letter` entry's shape (`jq -S` key order). On a `plan_pr` reference-gate
   mismatch, copy **only these two entries** from the gate's expected artifact, not the whole file.

### C. Contract test (new): `apps/web-platform/test/sentry-git-data-pin-fault-alert-op-contract.test.ts`

- Follows the `sentry-anthropic-credit-alert-op-contract.test.ts` shape (~100 LOC). It imports
  `GIT_DATA_PIN_FAULT_REASONS` and strips comment lines before any match.
- Implements Guards 1 and 2 below, plus one small census.

### D. Records

| File | Change | Form |
|---|---|---|
| `apps/web-platform/infra/sentry/README.md` line 5 | Rule counts: total M+1, Terraform-owned = M − frozen | Edit in place. Counts come from the AC8 formula, never incremented by hand. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` `sentry -> founder` edge | "N of the M" where M = `sentry_alert` blocks in `issue-alerts.tf` and N = M − `NoOne` blocks (expected "33 of the 35") | Edit in place, then `bash scripts/regenerate-c4-model.sh`. |
| `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` | See the list below | Living runbook: edit rows in place; append to dated bullets. |
| `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md` | "until then they are pull-only" | Append a dated bullet under the PR #9096 addendum: `> **2026-09-28 (#8572):** …` |
| `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md` | The list naming "#8572 paging" as a remaining flip precondition | Append a dated note. |
| `knowledge-base/legal/article-30-register.md`, PA-36 TOM (g) cell | "…which no alert routes until #8572." and "…the alert then fires per Sentry issue (first seen, reappeared or regression), not per refusal" | Inline `**[Superseded 2026-09-28 (#8572), as to "…": …]**` markers. **Drafted by `soleur:legal:clo` in the work phase.** |
| `knowledge-base/legal/audits/2026-09-counsel-reattestation-5914.md` | D4 row, line-85 row ("triggers on first seen, reappeared or regression"), `re_evaluation_triggers` (1) and (2) | See the list below. CLO-drafted. |

Runbook `git-data-luks-cutover-5274.md` changes:

- **Pin-fault row (erasure):**
  - Replace "(none pages until #8572; pull them)".
  - Name the rule and the `pin_fault:*` query.
  - Correct "the alert fires only on first-seen, reappeared or regression, so an issue left open
    swallows the next fault". Rule 1b now re-pages per event, throttled to one email per 5 min per
    issue.
  - Keep "resolve after the sweep", and add the `pin_fault:*` query to run after a resolve.
  - State that after the first flip, discharging an erasure depends on #8211's per-id re-erasure
    path (spec-flow review).
- **New push pin-fault row:**
  - Remedy: republish the pin, or re-run `git-data-pin-redeploy.yml`.
  - Verify, without SSH: `scripts/betterstack-query.sh --since 30m --grep 'git_data_pin=present fp='`
    shows the redeployed pin loaded with the expected fingerprint (a warn line, so Vector ships it;
    the `git-data replication push complete` line is `info` and never reaches Better Stack). Then
    `scripts/sentry-issue.sh` shows no new `pin_fault:*` event after the next session end.
  - Diagnose `host_key_mismatch` with `extra.via` (`ssh` = provision dial, `git` = push) and the
    `git-data-cutover.yml` dry-run precheck, whose `_access_reason` splits `alg` / `unknown` /
    `changed` without SSH.
  - Catch-up: the replica self-heals at each workspace's next session end, which force-pushes every
    head and tag. Commits in the window exist only on the host until then.
  - Never re-pin to the key a host presents (repeat the H4 rule). The tag is advisory, and a
    compromised host can print host-key text.
- **Host-key rows:** note the known_hosts false-positive class.
- **Line ~1196 soak query:** append a note that `feature:worktree_lease level:error` now also
  counts push **pin faults**, which were invisible before #8572 (architecture review).
- **Flag-flip precondition bullet:** append that the #8572 condition is met on this merge **plus**
  a green `apply-sentry-infra.yml` **and** a green `web-platform-release.yml`. State that #8211's
  per-id re-erasure path stays a **hard** precondition beside it.

Counsel audit `2026-09-counsel-reattestation-5914.md` changes:

- Add frontmatter `addendum_2026_09_28_8572:`.
- Add a `> **Superseded 2026-09-28 (#8572): …**` blockquote under the D4 table.
- Add a new `## Addendum (2026-09-28, #8572)`:
  - Trigger (1) is **half discharged**, conditioned on the merge and both deploys. #8211's re-erasure
    path still stands.
  - Trigger (2) is paged, no longer pulled. Paging is at most once per issue per 5 min, never "per
    refusal".

Every marker is conditioned on the merge **and** both deploys succeeding. If either fails, the
superseded sentence stands. `git diff --word-diff=porcelain` shows no deleted tokens (AC7).

### E. Ship and apply

- The PR body's **first line** says the merge mutates production. `apply-sentry-infra.yml` creates
  `git-data-host-key-pin-fault` and updates `art17-erasure-incomplete` in place.
  `web-platform-release.yml` deploys the emitter. The merge click is the authorization for both
  (`hr-menu-option-ack-not-prod-write-auth`). There is no other production write and no dispatch.
- The PR body carries `Ref #8572`, not `Closes`. #8572 closes in Phase 6 with evidence.
- No `.github/workflows/**` change, so the PR is not UNTRUSTED-CI. Admin merge is approved once
  every required check passes by name on the exact head SHA, **including** the Sentry `plan_pr` and
  `sentry-destroy-required`.
- Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test` and rely on CI for the full battery.

## Implementation Phases

The emitter vocabulary comes first, then the rule that consumes it, then the records.

### Phase 1 — RED: emitter contract

1. `test/git-data-host-key-pin.test.ts` (mocks `observability` and `logger`, so it asserts the
   **call arguments** only):
   - Update the three boot `toEqual` assertions (`pin_invalid_at_startup`, `pin_absent_at_startup`,
     `ssh_client_absent_at_startup`) to add `tags: { pin_fault: <reason> }` and `extra: { pinFault:
     <reason> }`. Keep them as `toEqual`; do not loosen them.
   - Build every transport rejection the way production does:
     `Object.assign(new Error("Command failed: …"), { code, stderr, syscall })`. A plain object
     would take the `captureMessage` branch and measure the wrong arm (test-design review).
   - Push, absent pin: exactly one `reportSilentFallback` call. First arg is `null`. `feature:
     worktree_lease`, `op: git_data_replication_push`, `tags.pin_fault: pin_absent`,
     `extra.via: "ssh"`. The rejection stays catchable.
   - Push, invalid pin → `pin_invalid`.
   - Provision ssh rejects `{code: "ENOENT", syscall: "spawn ssh"}` → `ssh_client_absent`.
   - Provision ssh rejects `{code: 255, stderr: "Host key verification failed."}` →
     `host_key_mismatch`, `extra.via: "ssh"`.
   - Provision ssh rejects `{code: 128, stderr: "Host key verification failed."}` → **not** a pin
     fault (via ssh, 128 is the remote command's status) → Error path.
   - Git push rejects `{code: 128, stderr: "Host key verification failed.\nfatal: Could not read from
     remote repository."}` → `host_key_mismatch`, `extra.via: "git"`.
   - Git push rejects `{code: "ENOENT", syscall: "spawn git"}` → **not** a pin fault: one Error-path
     report, no `pin_fault`.
   - Fence reject → Error path. `toEqual` the full options object, existing message included, so
     "unchanged" is asserted rather than assumed.
2. New `test/git-data-pin-fault.test.ts` (unit; no module mocks):
   - A `classifyGitDataPinFault` table covering every arm × `via`, including an error whose `name`
     is `GitDataHostKeyPinError` but which fails `instanceof`, and a forged `reason` outside the
     vocabulary (→ `null`).
   - `null`, `undefined`, a string, `{}`, and an object whose `stderr` getter throws → `null`, never
     a throw.
   - `GitDataHostKeyPinError`'s two messages equal today's resolver strings byte for byte.
3. New `test/git-data-pin-fault-event.test.ts`: the **real-path** event test (Kieran, spec-flow and
   test-design reviews). It is a separate file because the suite above mocks `observability` and
   `logger`.
   - Setup:
     - drive `replicateToGitData` end to end, with `git-auth`, `child_process` and
       `@/lib/supabase/tenant` mocked;
     - keep `observability.ts` and `logger.ts` **real**;
     - mock `@sentry/nextjs` with `vi.mock` (importOriginal spread, plus `captureMessage`,
       `captureException`, `addBreadcrumb` and a `withIsolationScope` that records
       `clearBreadcrumbs`);
     - set `SENTRY_USERID_PEPPER` in `vi.hoisted`.
   - Before the push, emit a pino `logger.warn` whose payload holds a raw `WS` path (a breadcrumb
     candidate).
   - Assert, for an absent-pin push:
     - `captureMessage` is called exactly once and `captureException` never. The real logger keeps
       the #8629 double capture observable;
     - `level: "error"`;
     - `tags.pin_fault === "pin_absent"`;
     - `clearBreadcrumbs` ran inside the isolation scope;
     - serialising the whole captured payload (message, tags, extra, user, scope data) contains
       none of the raw `WS`, `WT` or `USER` values;
     - **positive control:** it does contain `hashUserId(WS)`, so the sweep is not vacuous.
4. `test/account-delete.test.ts`: first assert the erasure report **was** called for each outcome.
   Then assert its `tags` never carry `pin_fault`. Assert the two call sites use `ART17_ERASURE_OP`.
5. The existing erasure-outcome tests in `test/git-data-replication.test.ts` and
   `test/git-data-host-key-pin.test.ts` stay **unmodified** and green. This is the no-change net for
   §A.9.

### Phase 2 — GREEN: emitter

Implement §A. Run the suites above, then `./node_modules/.bin/tsc --noEmit`.

### Phase 3 — RED then GREEN: rule contract

1. Write the contract test (Guards 1 and 2). It fails against the current `.tf`.
2. Edit `issue-alerts.tf` (§B.1 and §B.2) and `alert-reference.json` (§B.3). The test turns green.
3. Run `cd apps/web-platform/infra/sentry && terraform fmt -check`. Run `terraform init
   -backend=false && terraform validate` if the provider download is reachable. Otherwise record
   that, and rely on `plan_pr`.

### Phase 4 — Records

Apply §D. Spawn `soleur:legal:clo` with:

- the final rule behavior (triggers, 240 min and 5 min throttles, per-issue grouping);
- the rule-1b change;
- the "conditioned on the merge and both deploys" form.

Then regenerate `model.likec4.json`.

### Phase 5 — Ship (`soleur:ship`)

Review, push, and get CI green by name on the head SHA (including `plan_pr`). Then admin merge.

### Phase 6 — Post-merge (automated, read-only; `soleur:ship` post-merge)

1. Watch both runs on the merge SHA with the Monitor tool: `apply-sentry-infra.yml` and
   `web-platform-release.yml`. Accept the first successful run of each whose head contains the merge
   commit. For the apply, match the **live** literal `sentry_alert live fidelity: PASS (all` in `gh
   run view <id> --log`, never the fixture literal.
2. **Green path:**
   - Comment on #8211. `pin_fault_paging_absent` must verify two things:
     - (a) the live `git-data-host-key-pin-fault` projection equals its `alert-reference.json` entry
       (enabled, the exact `in` set, `ActiveMembers`), not only its name;
     - (b) the deployed release SHA contains this merge.
   - The same comment adds:
     - only the boot arm can fire before the flip;
     - #8211's per-id re-erasure path is a **hard** flip precondition, beside
       `pin_fault_paging_absent`. Without it, a post-flip Art. 17 page cannot be discharged
       (user-impact review);
     - "no `pin_fault` event" must never count as healthy, because a network attacker can hold
       every dial before the host-key check (security review). The flip check needs positive
       replication evidence.
   - Run one read-only Sentry query covering `pin_fault:*` and the three boot messages since the
     merge time. A hit that landed before the rule existed (the release restarted containers before
     the apply) is handled as a page. Also check that none of those issue groups is archived or
     ignored, since a muted group fires no trigger (user-impact review).
   - Close #8572 with both run URLs.
   - Open the evidence-only PR that appends the dated verification lines (run ids, the fidelity
     PASS line) to the register and the audit, per the #9077 precedent and the CLO ruling.
3. **Red or partial path:**
   - Keep #8572 open.
   - Link the p1 issue that `apply-sentry-infra.yml` files on failure (its `if: failure()` step) to
     #8572.
   - Still open the evidence PR, recording "apply/release failed, run X; the superseded sentences
     stand", or the partial state (for example, the rule was created but the 1b update failed).
   - Read rule 1b's live state before recording it. `sentry-alert-live-fidelity.sh` does not run
     after a failed apply. The read-only `scheduled-sentry-alert-drift.yml` compares live rules with
     the committed reference.
   - A `workflow_dispatch` of that workflow is a production dispatch. It needs the operator's
     explicit per-step authorization under the #8211 brief. Without it, rely on its next daily run,
     up to 24 h later, and say so in the evidence PR.
   - Fix forward in a follow-up PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** a deleted user is told on the login page that
  their outstanding git-data erasure "will be completed". Meanwhile the erasure is refused by a pin
  fault and the operator email never arrives. Ways this could happen:
  - a typo narrowing rule 1b;
  - a vacuous tag filter;
  - a failed apply;
  - an emitter that was never deployed.

  After the #8211 flip, a stale pin also stops every workspace's replication to the shared store
  with no page. A user's latest commits would then exist only on the host-local working tree.
- **If this leaks, the user's data is exposed via:** the new push event's `extra` and message in
  Sentry (an existing processor, DE region). Only these are admitted: hashed workspace and worktree
  ids, the lease generation, `userIdHash`, and fixed-vocabulary `pin_fault`/`pinFault`. A real-path
  test sweeps the whole event for raw ids. Pseudonymized ids are still personal data (Recital 26).
  #9121 (raw `extra.gitDataRepoId` on the erasure event) is a separate open defect, untouched here.
- **Brand-survival threshold:** `single-user incident`. One subject's unpaged Art. 17 failure is an
  Art. 12(3) exposure.

CPO signed off at plan time. `soleur:engineering:review:user-impact-reviewer` runs at review.

## Hypotheses

The feature text matches the network-outage trigger ("ssh"). This plan routes existing signals and
diagnoses no connectivity symptom. The layer checks:

- **L3 firewall:** not applicable, because no path is failing. When a page fires, the runbook's
  L3-first `role=… verdict=… reason=…` table stays the diagnosis order.
- **L3 DNS/routing:** not applicable. `GIT_DATA_SSH_HOST` is a private-net address.
- **L7 TLS:** not applicable. The transport is SSH, and Sentry ingest is unchanged.
- **L7 host identity:** `host_key_mismatch` is paged and `unreachable` is not, so a page never sends
  the operator to sshd for a firewall fault.

## Observability

```yaml
liveness_signal:
  what: "Sentry issue-alert rule git-data-host-key-pin-fault (sentry_alert.git_data_host_key_pin_fault) plus the event_frequency_count trigger added to art17-erasure-incomplete"
  cadence: "per event; re-pages at most once per Sentry issue per 240 min (pin fault) / 5 min (Art. 17) while events continue"
  alert_target: "operator email (issue_owners -> ActiveMembers fallthrough; the project has no ownership rule)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.git_data_host_key_pin_fault, sentry_alert.art17_erasure_incomplete), applied by .github/workflows/apply-sentry-infra.yml on push to main"
error_reporting:
  destination: "Sentry web-platform (org jikigai-eu, DE ingest) via SENTRY_DSN, message path (reportSilentFallback(null, ...)) through server/git-data-pin-fault.ts reportGitDataPinFault"
  fail_loud: "Sentry issue titled 'git-data replication push pin fault (<reason>): ...' or 'git-data host-key pin absent at startup' / '... invalid at startup' / 'git-data ssh client absent at startup', tag pin_fault=<reason>; the pino error line carries extra.pinFault=<reason> (tags do not reach pino)"
failure_modes:
  - mode: "stale or wrong pin after a git-data host replace (push host_key_mismatch)"
    detection: "classifyGitDataPinFault(err, via) in the replicateToGitData catch -> reportGitDataPinFault message path, tag pin_fault=host_key_mismatch, extra.via; layer-5 Sentry captureMessage (release-tagged) + layer-2 pino logger.error carrying extra.pinFault -> layer-3 vector app_container_warn_filter -> Better Stack"
    alert_route: "sentry_alert.git_data_host_key_pin_fault -> operator email"
  - mode: "armed container boots without GIT_DATA_SSH_HOST_KEY or with a malformed one"
    detection: "logGitDataHostKeyPinAtStartup -> reportGitDataPinFault message path, pin_fault=pin_absent or pin_invalid; layer-5 Sentry captureMessage (release-tagged) + layer-2 pino logger.error carrying extra.pinFault -> layer-3 vector app_container_warn_filter -> Better Stack; plus the Better Stack warn line git_data_pin=absent or git_data_pin=invalid"
    alert_route: "sentry_alert.git_data_host_key_pin_fault -> operator email"
  - mode: "runner image lacks the ssh client"
    detection: "boot PATH walk and the push's provision spawn ssh ENOENT -> reportGitDataPinFault message path, pin_fault=ssh_client_absent; layer-5 Sentry captureMessage (release-tagged) + layer-2 pino logger.error carrying extra.pinFault -> layer-3 vector app_container_warn_filter -> Better Stack; plus the Better Stack warn line git_data_ssh_client=absent"
    alert_route: "sentry_alert.git_data_host_key_pin_fault -> operator email"
  - mode: "Art. 17 erasure refused while an earlier issue for that outcome is still open"
    detection: "account-delete erasure report (layer-5 Sentry captureMessage, release-tagged, tags erasure_outcome and erasure_reason) + event_frequency_count on art17_erasure_incomplete; layer-2 pino logger.error -> layer-3 vector -> Better Stack"
    alert_route: "sentry_alert.art17_erasure_incomplete -> operator email (at most once per issue per 5 min)"
  - mode: "the rule is not live, or the emitter is not deployed"
    detection: "apply-sentry-infra.yml post-apply scripts/sentry-alert-live-fidelity.sh; daily scheduled-sentry-alert-drift.yml against alert-reference.json; web-platform-release.yml run on the merge SHA (Phase 6)"
    alert_route: "failed-apply p1 issue filed by apply-sentry-infra.yml; drift issue filed by the drift workflow"
logs:
  where: "Sentry issue stream (web-platform); container stdout via pino, shipped to Better Stack at level >= 40 by Vector (app_container_warn_filter)"
  retention: "Sentry org plan event retention; Better Stack source retention per plan"
discoverability_test:
  command: "jq -r '.\"git-data-host-key-pin-fault\".actionFilters[0].conditions[0].comparison.key' apps/web-platform/infra/sentry/alert-reference.json"
  expected_output: "pin_fault"
```

The `plan_pr` reference gate holds the committed `alert-reference.json` equal to the plan before
merge. `sentry-alert-live-fidelity.sh` holds live Sentry equal to that plan after the apply. The
local probe therefore reads the state the live check enforces, and needs no credential. There is no
`credentials_required` field, so `BASELINE_DECLARED_PROBES` does not move.

## Encryption Posture

The `.tf` edit triggers this gate, but the plan introduces **no** persistent store and **no** new
cross-component connection. The only change is which Sentry path one app event takes on an existing
connection.

```yaml
in_transit:
  - connection: "web-platform container (server/observability.ts reportSilentFallback) -> Sentry DE ingest (existing; payload shape changes, connection unchanged)"
    enforced_at: "apps/web-platform/sentry.server.config.ts (dsn: process.env.SENTRY_DSN, an https DSN; @sentry/nextjs node transport)"
    tls: "HTTPS, TLS 1.2+ (Node default minimum)"
    cert_verification: on
    does_not_defend: "a Sentry org member or a compromised Sentry account reading event extras; hashed workspace/worktree ids and userIdHash are pseudonymous, not anonymous, and can be re-linked by anyone holding the hash inputs"
    disclosed_as: "knowledge-base/legal/article-30-register.md, Processing Activity 8 — Operational Telemetry & Breach-Detection Logs, (d) Recipients (Sentry, DE region)"
```

## Guard Contract

### Guard 1 — pin-fault emit/rule vocabulary contract

**Property.** The app has exactly one writer of the `pin_fault` tag. Every value it can write is one
the rule routes, and the rule routes exactly that vocabulary: nothing missing, nothing extra.

**Assembly.**

- **Chokepoint:** `reportGitDataPinFault` in `server/git-data-pin-fault.ts`.
- **Value set:** `GIT_DATA_PIN_FAULT_REASONS`, typed via `GitDataPinFault`, so `tsc` rejects a
  literal outside the set.
- **Callers:** the three boot reports and the push catch in `server/git-data-replication.ts`.
- **Consumer:** the single `tagged_event` condition of `sentry_alert.git_data_host_key_pin_fault`,
  plus its `alert-reference.json` entry.
- **Census:** a recursive walk of `apps/web-platform/{server,app,lib}/**/*.ts(x)`.
  - It excludes `*.test.*` and `*.spec.*`, and strips `//`, `/* */` and JSDoc comments first.
  - It matches the **writer shape** `["']?pin_fault["']?\s*:`, and requires that it occurs only in
    `server/git-data-pin-fault.ts`.
  - A second check requires that `reportGitDataPinFault` is imported only by
    `server/git-data-replication.ts`.
  - Its floor requires that the walk **visited** `server/git-data-pin-fault.ts` and at least one
    file two directories deep, which proves it recursed.
- **Reference mirror:** the test also set-compares `alert-reference.json`'s
  `."git-data-host-key-pin-fault".actionFilters[0].conditions[0].comparison.value` against the
  constant.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `ssh_client_absent` from the rule's `in` value | RED (set-compare with the imported constant) |
| 2 | Add `unreachable` to the rule's `in` value | RED (the set is not equal) |
| 3 | `match = "eq"`, or `logic_type = "none"` (not `any-short`, which is equivalent to `all` over one condition), or a second condition added | RED (it asserts `all` and exactly one condition) |
| 4 | Comment out the condition line | RED (comments are stripped; no filter is found) |
| 5 | Add `tags: { pin_fault: "pin_absent" }` to the erasure report in `server/account-delete.ts` | RED (census: a second writer, which would double-email) |
| 6 | Point the census walk at an existing directory with no `.ts` files | RED (floor: `git-data-pin-fault.ts` and a depth-2 file not visited) |
| 7 | Set `frequency_minutes = 1442`, a value `spawn_agent_dead_letter` already uses | RED (this rule's own value must be unique) |
| 8 | Change `fallthrough_type` to `NoOne` | RED |
| 9 | Remove `event_frequency_count` from the rule's triggers | RED |
| 10 | `event_frequency_count` `value = 1`, or `interval = "1d"` | RED (strict `>` per group: `value = 1` never pages a single event, #8708 learning) |
| 11 | `enabled = false` | RED |
| 12 | Drop `ssh_client_absent` from `alert-reference.json`'s `in` value only | RED (reference mirror) |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Must-PASS: reorder the `in` value to `pin_absent,host_key_mismatch,ssh_client_absent,pin_invalid` | PASS (the comparison is a set, not a string) |
| H2 | Make the rule-block extractor miss the block | RED (the extractor throws "fixture: … not found"; zero conditions read is never a PASS) |

**Anchor.** A single diff can edit the constant, the rule and the test together. It cannot hide a
change to `alert-reference.json`'s `in` value, which the `plan_pr` gate holds equal to the plan and
review reads. After the apply, `sentry-alert-live-fidelity.sh` holds live Sentry equal to that
plan. H1's set identity blocks count-preserving substitutions.

### Guard 2 — Art. 17 rule 1b stays unnarrowed and re-paging

**Property.** `sentry_alert.art17_erasure_incomplete` routes every outcome the emitter can send,
including `unconfigured` with any `erasure_reason`, and keeps re-paging while events continue.

**Assembly.**

- **Emitters:** the two `reportSilentFallback(null, { feature: "account-delete", op:
  "git-data-bare-repo-erasure", … })` calls in `server/account-delete.ts`, the outcome report and
  the throw arm.
- **Consumer:** the rule 1b block in `issue-alerts.tf`, plus its reference entry.
- **The absence the test checks:** the block's `conditions` list has **exactly two entries of any
  kind**, both `tagged_event` on `feature` and `op`, under `logic_type = "all"`. So a non-tag
  narrowing condition, such as a level filter, also turns it red (test-design review).
- **The presence the test checks:** `event_frequency_count {1h, 0}` among the triggers.
- **Literal equality:** `ART17_ERASURE_FEATURE` and `ART17_ERASURE_OP` are imported from
  `server/account-delete.ts` and compared to the rule's values.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `{ tagged_event = { key = "erasure_outcome", match = "in", value = "refused,unauthorized,unreachable" } }` | RED (narrowing) |
| 2 | Remove `event_frequency_count` from rule 1b | RED |
| 3 | After the compliant `feature` filter, add a second, narrowing `erasure_reason` filter | RED (exactly two conditions, each checked) |
| 4 | Change the `op` value to `git-data-erasure` | RED (the imported constant differs) |
| 5 | Add a non-tag condition (e.g. a `level` filter) | RED (exactly two conditions) |
| 6 | Rule 1b `event_frequency_count` `value = 1` | RED |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | The block extractor returns an empty string | RED (throws; a zero-condition read is not a PASS) |
| H2 | Must-PASS: reorder rule 1b's triggers so `event_frequency_count` comes first | PASS (the triggers are compared as a set) |

**Anchor.** Same as Guard 1: the `plan_pr` reference gate and post-apply live fidelity.

## Files to Edit

- `apps/web-platform/server/git-data-replication.ts`
- `apps/web-platform/server/account-delete.ts` (two exported constants used at the two erasure sites, behavior-neutral; dated comment)
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`
- `apps/web-platform/infra/sentry/README.md`
- `apps/web-platform/test/git-data-host-key-pin.test.ts`
- `apps/web-platform/test/account-delete.test.ts`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/audits/2026-09-counsel-reattestation-5914.md`

## Files to Create

- `apps/web-platform/server/git-data-pin-fault.ts`
- `apps/web-platform/test/git-data-pin-fault.test.ts`
- `apps/web-platform/test/git-data-pin-fault-event.test.ts`
- `apps/web-platform/test/sentry-git-data-pin-fault-alert-op-contract.test.ts`

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was run, with a `jq` body search for every
path above.

## Architecture Decision (ADR/C4)

No new ADR. This is an alert route, the same class as #8505 and #8719 (CTO ruling). The records
whose statements become false get dated append-only notes (ADR-237 addendum, ADR-220 precondition
list; see §D).

### C4 views

All three model files were read.

- **External actors:** the founder/operator is modeled (`founder`).
- **External systems:** Sentry is modeled (`sentry`, with the `sentry -> founder` edge). No new
  vendor.
- **Containers:** the web-platform container already reports to Sentry. No new store.
- **Access relationships:** unchanged.

The only falsified text is the derived count on the `sentry -> founder` edge. Update it with AC8's
formula and regenerate `model.likec4.json`. `plugins/soleur/test/c4-count-parity.test.sh` gates the
`github -> sentry` counts, not this one. It must stay green, and AC8 checks this count.

## Deferrals

- **Unify the erasure and push pin-fault classifiers.** Characterization tests over the **current**
  `removeGitDataRepo` classification land first. They must include the inputs where old and new
  logic differ: exit 128 plus host-key text via ssh must be `refused`; empty stderr must fall back
  to `err.message`. Only then refactor. Re-evaluate when the erasure path next changes, or before
  #8211's post-flip re-erasure path lands. Tracked in **#9152**.
- **Start the Art. 12(3) one-month clock automatically from the page** (CPO note). Today it starts
  when a `clo-attestation` issue is filed by hand. Tracked in **#9153**.
- **Pre-existing, found at deepen:** the **non-pin** push failure report (Error path) still carries
  raw worktree and workspace ids in `err.message` (Node's `Command failed:` argv, and
  `ensureGitDataRemote`'s message). This PR does not change that path. Tracked in **#9154**.

## Review & Consult Provenance

- **Domain leaders:** CTO, CLO and CPO (sign-off).
- **Advisor consult (plan Step 4.5):**
  - Taken out of this PR: the Art. 17 refactor.
  - Replaced `frequency_minutes` 1443 with 240, because it is a per-issue interval covering all
    triggers.
  - Asserted `update in-place` for rule 1b.
  - Asserted exactly one capture per failure.
  - Rejected "action_match any": `sentry_alert` has no trigger logic type, and triggers are always
    OR'd.
- **gdpr-gate:** 0 Critical, 0 Important. It raised 2 Suggestions, both already covered here
  (scope the pseudonymization claim to this event; the marker is conditional).
- **Plan-review panel** (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow):
  - A per-transport exit code (`via`).
  - A real-path event test in place of the mock-argument sweep.
  - The AC8 count formula.
  - The three boot `toEqual` edits named.
  - The new module.
  - `extra.pinFault` for pino.
  - Cut `hostKeyReason`, the erasure refactor and the heavy census.
  - A push pin-fault runbook row, plus the post-flip #8211 dependency.
  - Both deploys gate the close and the #8211 check.
  - The live-literal PASS match.
  - A red-path issue link.
  - AC5 reads every filter.
  - AC7 regex fixed.
  - An `account-delete.ts` comment, rule 1b "Keys on erasure_outcome" and a soak-query note.
  - P3 reworded to the 5-min throttle.
  - **Deepen pass (2026-09-28):** the observability, security, test-design, user-impact and
    Terraform reviews (see Enhancement Summary).
  - Taste findings that were not applied are recorded in
    `knowledge-base/project/specs/feat-one-shot-8572-git-data-pin-fault-paging/decision-challenges.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: This command passes, including every Phase 1 case and the unmodified erasure cases:

  ```bash
  cd apps/web-platform && ./node_modules/.bin/vitest run test/git-data-host-key-pin.test.ts \
    test/git-data-replication.test.ts test/git-data-pin-fault.test.ts \
    test/account-delete.test.ts test/sentry-git-data-pin-fault-alert-op-contract.test.ts
  ```

- [ ] AC2: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] AC3: `git grep -nE "[\"']?pin_fault[\"']?[[:space:]]*:" -- apps/web-platform/server apps/web-platform/app apps/web-platform/lib ':!*.test.*'` matches only `apps/web-platform/server/git-data-pin-fault.ts`. Comment mentions are allowed; the contract-test census is the precise check.
- [ ] AC4: This command prints `git-data-host-key-pin-fault`, `240`, `host_key_mismatch,pin_absent,pin_invalid,ssh_client_absent`, `ActiveMembers` and `1h/0`:

  ```bash
  jq -r '."git-data-host-key-pin-fault" | [.name, .frequency, (.actionFilters[0].conditions[0].comparison.value), .actionFilters[0].actions[0].fallthroughType, (.triggerConditions[] | select(.type == "event_frequency_count") | .comparison | "\(.interval)/\(.value)")] | @tsv' \
    apps/web-platform/infra/sentry/alert-reference.json
  ```

- [ ] AC5: This command prints `{"t":["event_frequency_count","first_seen_event","reappeared_event","regression_event"],"k":["feature","op"],"f":["1h/0"]}`:

  ```bash
  jq -c '."art17-erasure-incomplete" | {t: ([.triggerConditions[].type] | sort), k: ([.actionFilters[].conditions[].comparison.key] | sort), f: [.triggerConditions[] | select(.type == "event_frequency_count") | .comparison | "\(.interval)/\(.value)"]}' \
    apps/web-platform/infra/sentry/alert-reference.json
  ```

- [ ] AC6: The `apply-sentry-infra.yml` `plan_pr` job is green on the head SHA. Its plan shows **exactly** `1 to add, 1 to change, 0 to destroy`: `sentry_alert.git_data_host_key_pin_fault` is created and `sentry_alert.art17_erasure_incomplete` is updated in place (`~`, never `-/+`). Any other drift in the full-root plan blocks the merge. The reference gate and `sentry-destroy-required` are green.
- [ ] AC7: This command prints `0` (append-only: no deleted tokens in dated records):

  ```bash
  git diff origin/main...HEAD --word-diff=porcelain -- \
    knowledge-base/legal/article-30-register.md \
    knowledge-base/legal/audits/2026-09-counsel-reattestation-5914.md \
    knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md \
    knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md \
    | grep -E '^-' | grep -vE '^--- (a/|/dev/null)' | wc -l
  ```

- [ ] AC8: Let `S(f)` be the file with comment lines stripped (`grep -v '^\s*#' f`) and `M = S(issue-alerts.tf) | grep -c '^resource "sentry_alert"'`.
  - The `model.c4` edge reads "N of the M", where N = M − `S(issue-alerts.tf) | grep -c 'fallthrough_type = "NoOne"'`. Expected "33 of the 35".
  - The README total is M + `S(cron-monitor-alerts.tf) | grep -c '^resource "sentry_alert"'` (expected 36).
  - The README's `issue-alerts.tf` Terraform-owned figure is M − `S(issue-alerts.tf) | grep -c 'ignore_changes = all'` (expected 33).
  - `bash plugins/soleur/test/c4-model-freshness.test.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] AC9: `git grep -n 'none pages until #8572' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` returns nothing. The runbook names `git-data-host-key-pin-fault` and has a push pin-fault row.
- [ ] AC10: The PR body's first line states that the merge mutates production through `apply-sentry-infra.yml` and `web-platform-release.yml`. The body carries `Ref #8572`, not `Closes`, and notes the `GitDataHostKeyPinError` grouping-name change.
- [ ] AC11: Every required check passes by name on the exact head SHA before the admin merge.

### Post-merge (automated in `soleur:ship`)

- [ ] AC12: The first successful `apply-sentry-infra.yml` run whose head contains the merge SHA logs the live literal `sentry_alert live fidelity: PASS (all` (not the FIXTURE literal). The first successful `web-platform-release.yml` run for the merge SHA completes. Both run ids are recorded on #8572.
- [ ] AC13: #8211 carries the Phase 6 comment: the two-part check, boot-only before the flip, and the re-erasure dependency. #8572 is closed with both run URLs.
- [ ] AC14: The evidence-only PR appends the dated verification lines to the register and the audit, and merges. On the red path, it records the failed state instead.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Sound and small (hours). Adopted: tag unification on `pin_fault` with a
single-condition `all` rule; a typed resolver error; `spawn ssh` tightening; 4 triggers; dated
ADR-237 and ADR-220 notes; derived counts. The CTO's shared-classifier recommendation was deferred
on the advisor's and the panel's risk finding (see Deferrals). Named risks: only the boot arm fires
before the flip; the message path loses the stack; `SSH_HOST_KEY_MISMATCH` also matches an absent
known_hosts file.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Rule 1b's first-seen-only paging is not an adequate Art. 12(3) control. Add
`event_frequency_count` rather than double-routing. The register marker and the audit addendum land
in this PR, conditioned on the merge and the deploys, and the verification is appended afterwards.
No new processing activity. Pseudonymized is not anonymized. Tag vocabulary is fixed. No counsel
re-attestation. `docs/legal/**` is untouched. #9121 is out of scope.

### Product/UX Gate

**Tier:** none. No UI surface: the mechanical scan found no `components/**`, `app/**/page.tsx` or
`app/**/layout.tsx` in the Files lists. The CPO signed off on the user-facing promise (the login
page's "will be completed") and on the email volume.

## Test Scenarios

- **Boot, pin absent:** given an armed container with `GIT_DATA_SSH_HOST_KEY` unset, when the server
  boots, then one `captureMessage` event "git-data host-key pin absent at startup" carries
  `pin_fault=pin_absent`.
- **Push, host re-keyed:** given the store is enabled and the git-data host was re-keyed, when the
  provision ssh fails with 255 and "Host key verification failed.", then one message event carries
  `pin_fault=host_key_mismatch`, and the push rejects.
- **Push, remote exit 128:** given the provision's remote command exits 128 and prints host-key
  text, then it is **not** a pin fault (via ssh), and it stays on the Error path.
- **Push, ssh missing:** given the image has no `ssh`, then `spawn ssh` ENOENT on provision gives
  `pin_fault=ssh_client_absent`.
- **Push, git missing:** given `git` is missing (`spawn git` ENOENT), then it is not a pin fault.
- **Push, fence reject:** given a fence reject, then exactly one Error-path report goes out
  (unchanged), and the pin-fault rule cannot match it.
- **Art. 17, issue still open:** given a `pin_absent` erasure issue is open, when a second user's
  erasure returns `unconfigured` `pin_absent` more than 5 minutes later, then
  `art17_erasure_incomplete` emails again.
- **No raw ids:** given the real `reportSilentFallback` path, then the built event contains no raw
  workspace, worktree or user id.
- **API verify (post-merge, read-only):** `gh run list --workflow apply-sentry-infra.yml --branch
  main --limit 1 --json conclusion,headSha` expects `success` on the merge SHA.

## Dependencies & Risks

- **#8629 is fixed later.** Non-pin push failures will then carry `feature=worktree_lease` but no
  `pin_fault`, so this rule stays quiet on them. They will also start counting in the soak query,
  as intended. The Phase 1 row "first arg `null`, one capture" is what keeps this rule
  independent of that change.
- **Rule 1b is updated in place** on a live compliance pager. AC6 requires `~`, not `-/+`. A partial
  apply (new rule created, 1b update failed) still leaves 1b paging on first-seen, and the red path
  records it.
- **The throttle windows.** A resolve followed by a recurrence inside 4 h (pin-fault rule) or 5 min
  (Art. 17) is silent. The runbook's post-resolve query covers this.
- **Sentry's default high-priority rule** also emails a first-seen error-level event. This already
  happens for every rule in the root.
- **Only the boot arm can fire before the flip**, and only on an armed container. The #8211 check
  verifies the live rule content and the deployed emitter. It does not wait for a firing.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty, placeholder-only or missing the threshold fails
  `deepen-plan` Phase 4.6. This one is filled.
- `resolveGitDataHostKeyPin`'s messages stay byte-identical when it switches to
  `GitDataHostKeyPinError`.
- The `via` transport decides whether 128 counts as a host fault. Keep provision **before** the git
  push: a missing `ssh` only reads as `spawn ssh` there.
- Never tag the Art. 17 erasure report with `pin_fault` (see the Reconciliation table).
- `discoverability_test.command` avoids `| ; & < > $` and backticks (preflight Check 10).
- The register's PA-36 TOM (g) cell is one very long table row. Insert markers inline and check
  them with AC7.
- When adopting the reference gate's expected artifact, copy only the two changed entries.

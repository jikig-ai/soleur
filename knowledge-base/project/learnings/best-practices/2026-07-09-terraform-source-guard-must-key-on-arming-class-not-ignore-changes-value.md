---
title: A terraform-source CI drift-guard must key on the immutable arming CLASS, not a lifecycle{ignore_changes}-decoupled source value
date: 2026-07-09
category: best-practices
module: infra-ci-guards
tags: [terraform, ci-guard, ignore_changes, drift-guard, betteruptime, heartbeat, review, static-analysis]
issue: 6242
pr: 6251
related:
  - knowledge-base/engineering/architecture/decisions/ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md
  - knowledge-base/project/learnings/best-practices/2026-07-08-verify-sentinel-hardcoded-count-breaks-on-new-counted-object.md
---

# Learning: a static-source CI guard keyed on a `lifecycle { ignore_changes = [X] }` value is blind in exactly the case it exists to catch

## Problem

#6242 added `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — a static-analysis CI guard
that parses every `betteruptime_heartbeat` block in `apps/web-platform/infra/*.tf` and enforces:
*a non-paused heartbeat armed by a dedicated host's boot-time provisioning MUST have a
`<host>-host-replace` reprovision path* (the recurrence guard for the #6238 false-positive class).

The first implementation keyed the path requirement on the `paused` value **read from the `.tf`
source**: `requiresPath = arming === "dedicated-host-boot" && !source.paused`.

Two independent review agents (security-sentinel P3 + pattern-recognition F4) caught the hole: **4
of the 6 heartbeats carry `lifecycle { ignore_changes = [paused] }`.** That directive is the whole
point of the codebase's arming pattern — a boot-armed heartbeat ships `paused = true` in source,
then an operator UI-unpauses it in Better Stack after first deploy, and Terraform **never**
reconciles the source value back. So `source.paused` is permanently `true` while the live heartbeat
is active. A future `dedicated-host-boot` heartbeat added `paused = true` + `ignore_changes=[paused]`
+ UI-unpaused, with no reprovision path, would sail through the guard **green** — the exact #6238
shape the guard was written to prevent.

## Solution

Key the requirement on the **arming CLASS** (a structural, source-immutable property), not on the
mutable-and-ignored `paused` value:

```ts
// stricter + paused-INDEPENDENT: the arming class is what determines whether the remediation
// is a dedicated-host reprovision, and it cannot be UI-mutated behind ignore_changes.
const requiresPath = e.arming === "dedicated-host-boot";
```

This is strictly stronger and stays green today (inngest is `paused=true` but HAS
`inngest-host-replace`; `registry_disk_prd` is `paused=false` and HAS `registry-host-replace`). Add
a non-vacuity fixture proving a **paused** boot-armed heartbeat with no path now FAILS (mutation
check: reverting to `&& !d.paused` flips it green). The source-vs-manifest `paused` **drift** check
is kept — it is still valuable for detecting manifest staleness — but it is no longer load-bearing
for the path requirement.

## Key Insight

**When a CI guard reads a value from Terraform source, first ask: is this value under
`lifecycle { ignore_changes = [...] }`? If so, the source value is a LOWER BOUND on the live state,
not the truth — the operator mutates it out-of-band and Terraform never reconciles it. Gate on a
property that cannot be decoupled that way (the resource's structural class / arming mechanism / a
ForceNew attribute), never on the ignored value.** The same reasoning applies to any operator-mutable
runtime state a static-source scan cannot see: `ignore_changes` is the machine-readable *declaration*
that "source lies about this field on purpose."

General form of the review lens: for any static-source drift-guard, grep the guarded resource for
`ignore_changes` and confirm the guard does not depend on any listed attribute. If it does, the guard
fails open exactly when the ignored attribute drifts — which is precisely when you needed it.

## Session Errors

- **Planning subagent stopped by user mid-run (before its Session Summary).** Recovery: partial-artifact recovery per one-shot's fallback path — the fully-deepened plan was already on disk (frontmatter + Overview + ACs + Domain Review), so it was loaded and the pipeline continued from `/work` rather than re-running plan/deepen. Prevention: already covered — one-shot's Step 1-2 fallback + `knowledge-base/project/learnings/2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md`.
- **`./node_modules/.bin/vitest` exited 127 on a `plugins/soleur/test/*.ts` file.** The repo runs plugin tests via `bun test plugins/soleur/` (root has no vitest; vitest is the `apps/web-platform` runner). Recovery: switched to `bun test`. Prevention: for `plugins/soleur/test/*.test.ts` use `bun test <path>`; reserve `./node_modules/.bin/vitest` for `apps/web-platform`.
- **Foreground `sleep 25` blocked by the harness (chained-sleep guard).** Recovery: read the background command's output file directly instead of sleeping to poll. Prevention: use `run_in_background` + the completion notification, or a Monitor until-loop, never a foreground `sleep` to poll.
- **Two `Edit` calls failed "string not found"** on anchor lines with trailing whitespace / adjacent context. Recovery: re-read the exact lines and used a smaller, unique anchor. Prevention: one-off; standard re-read.
- **Plan carried an internal 5-vs-7 `-target` count inconsistency** (detailed Technical Approach said 5 targets / 5-member allow-set; Deliverable-C-step-3 + AC5 said "7"). Recovery: implemented the authoritative detailed spec (5) and reconciled the stale "7" references. Prevention: already covered by "plan-quoted numbers are preconditions to verify" — the detailed spec section is authoritative over a summary count.

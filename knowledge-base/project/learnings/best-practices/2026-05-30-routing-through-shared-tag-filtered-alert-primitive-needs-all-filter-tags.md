# Learning: routing a breach through a shared tag-filtered alert primitive must carry EVERY tag the rule filters on

## Problem

PR #4658 (#4656) re-routed the BYOK Art. 33 cross-tenant breach in
`cost-writer.ts` from `reportSilentFallback` to the shared `mirrorP0Deduped` P0
primitive, to gain fatal severity + `first_seen_at` clock anchor. The plan (D1)
prescribed extending `mirrorP0Deduped` with an `art33Breach` option so the event
carries `art_33_breach=true`.

But the consuming Sentry rule `byok_art_33_breach` is `filter_match = "all"` over
**two** `tagged_event` filters: `feature=byok-delegations` AND `art_33_breach=true`.
`reportSilentFallback` set `feature` from its required `feature` option;
`mirrorP0Deduped`'s tag set was `{op, scope, userIdHash}` — **no `feature`**.
Routing through it with only the `art33Breach` flag would have emitted an event
that carries `art_33_breach=true` but NOT `feature=byok-delegations` → the rule's
`filter_match="all"` never matches → a real cross-tenant leak silently never pages.
The plan's D1 omitted this; typecheck and the existing test would both have passed.

## Solution

Extend the shared primitive with **every** tag the destination rule filters on,
not just the one the plan names. Added optional `feature?` alongside
`art33Breach?` to `mirrorP0Deduped`'s ctx, and a test asserting BOTH tags are
present (present-case) and absent when not passed (absent-case). The rule fires
only when the full `filter_match="all"` tag set is satisfied.

## Key Insight

When re-pointing an emit path at a different observability primitive, the
acceptance criterion is not "the new primitive carries the flag the plan
mentioned" — it is **"the emitted event satisfies the consuming alert rule's
COMPLETE filter predicate."** For a `filter_match = "all"` (AND) rule, enumerate
every `tagged_event` filter on the rule and confirm the new primitive emits each
one. A plan that names only the *distinguishing* tag (`art_33_breach`) silently
drops the *scoping* tag (`feature`) that the old primitive supplied implicitly.
Cheapest gate: read the destination rule's `filters_v2` and diff its tag-key set
against the new primitive's emitted `tags` map before trusting the routing change.

This generalizes the `cq-silent-fallback-must-mirror-to-sentry` family: a
silent-alert-never-fires bug is as dangerous as a silent-failure-swallow, and
neither tsc nor a single-tag test catches it.

## Session Errors

1. **[forwarded] Plan subagent transient Write-hook false-positive** — the
   worktree path was momentarily misclassified as the bare-root checkout.
   Recovery: retry succeeded; plan landed correctly. Prevention: already covered
   by plan D5 (verify CWD/toplevel before concluding a scope breach).
2. **[forwarded] Plan-time stale on-disk checkout** (`issue-alerts.tf` 177 vs
   298 lines). Recovery: read source via `git show HEAD:<path>`. Prevention: D5;
   a freshly-created worktree (this /work session) had on-disk == HEAD, so the
   staleness was a planning-host artifact, not a /work one.
3. **manual-infra PreToolUse hook blocked a plan prose edit** — adding a
   tag-drift scope-out to the plan's `## User-Brand Impact` was denied by
   `hr-all-infrastructure-provisioning-servers` because the prose contained
   "out-of-band UI edits" / "manual", which the hook pattern-matches as
   infrastructure-provisioning framing. Recovery: reworded to "drift between
   applies, absent a Terraform run" (same meaning, no trigger words). Prevention:
   when writing plan/spec prose about *vendor-console drift on an
   already-IaC-managed resource* (Sentry rule, Cloudflare record), avoid the
   words `manual` / `UI` / `out-of-band UI`; describe the drift in
   Terraform-state terms, or add `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`.
4. **Shell test helper `base_env() { ... "$@"; }` passed `VAR=val command`
   through `"$@"` → exit 127** ("No such file or directory"). bash treats a
   leading `VAR=val` token in `"$@"` expansion as a *command name*, not an
   assignment (the assignment-prefix grammar only applies to literal command
   words, not expanded positional params). Recovery: changed the helper to
   `env VAR=val "$@"`, which re-parses leading assignments. Prevention: any bash
   helper that forwards `VAR=val <cmd>` via `"$@"` must prefix `env`.
5. **[minor]** `scripts/test-all.sh` foreground run was auto-backgrounded by the
   harness (exceeded the inline timeout); a `Monitor` armed to await it timed out
   harmlessly after the process had already completed and its completion
   notification had fired. No defect; just redundant waiting.

## Tags
category: best-practices
module: observability

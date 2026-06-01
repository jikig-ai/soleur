# Learning: a "make-the-silence-loud" breadcrumb floods Sentry when its condition is the default steady state

## Problem

Production fired a Sentry **warning** (`op=ignored-repo-has-workspaces`, feature
`workspace-reconcile-push`) on **every push** to `jikig-ai/soleur`. The
`workspace-reconcile-on-push` Inngest handler emitted
`warnSilentFallback(new Error("ignored repo has connected workspaces"))` whenever
a repo on the reconcile ignore-list (`WORKSPACE_RECONCILE_IGNORE_REPOS`, default
`jikig-ai/soleur`) still had a connected workspace.

This was the **third iteration** on the same Sentry-noise surface:
- #4623 — per-repo debounce on the warn mirror (defeated by container churn: the
  in-process debounce map resets on every new worker).
- #4666 — zero-match suppression (ignored repo + NO workspace → fully silent).
- #4706 — fixed a real functional bug (the ignore check ran *before* workspace
  resolution and silently starved a real connected workspace for ~5 weeks) and
  added a Sentry **warning** on the shadowed-workspace sub-case "to make the prior
  silence loud."

## Root cause

The #4706 breadcrumb guarded a condition that is **permanently true under the
default config**: the founder dogfoods their KB out of `jikig-ai/soleur`, which is
*also* the default ignore entry. So "ignored repo has a connected workspace" is the
**expected steady state**, not a misconfiguration — and active development means one
zero-signal Sentry alert per push. A breadcrumb added to surface a *prior* silent
failure over-corrected into an alert flood.

## Solution

Downgrade that one branch from `warnSilentFallback` (Sentry warning, level 40) to
`logger.info(...)` (pino → Better Stack, level 30 — below the Sentry-breadcrumb
floor, so no Sentry surface), mirroring the existing benign `skip-no-workspace-match`
info-log in the same file. The reconcile still happens; the four genuine failure
modes (`op=sync`, `op=skip-not-ready`, `op=resolve-workspaces`,
`op=deadletter-schema-version`) keep paging. The `warnSilentFallback` import stays —
the deadletter path still uses it.

## Key Insight

When you add a "make-the-silence-loud" signal (Sentry warn, page, alert) to surface a
state that was previously silent, **check whether that state is permanently true under
the default/dogfood config**. If it is, you have not surfaced a failure — you have
built an alert flood with zero signal. The right altitude for a benign, by-design,
self-resolving state is a **durable pull-not-push log** (pino/Better Stack `info`),
not a push alert. This does NOT violate `cq-silent-fallback-must-mirror-to-sentry`:
that rule governs *swallowed errors on fallback paths*; a benign steady state that is
still durably logged is not a swallowed error.

Corollary for severity choice: `info` (not `debug`) keeps the audit trail queryable —
an operator can still pull "which ignored repos have live workspaces" on demand;
`debug` may be filtered out of the default ingest.

## Session Errors

1. **Plan-write hook false-positive on a negation.** The IaC-routing PreToolUse
   guard matched the literal phrase `doppler secrets set` inside a *negation* ("no
   `doppler secrets set` step is introduced") in the plan's Infrastructure section
   and blocked the write. **Recovery:** reworded to "no secret mutation" and added the
   `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out comment (correct for a
   pure code change with zero new infrastructure). **Prevention:** when a plan section
   must *deny* introducing an infra command, avoid quoting the literal command verb
   that the routing guard greps for — describe the absence semantically ("no secret
   mutation", "no IaC change") rather than echoing `doppler secrets set` /
   `terraform apply` / `systemctl`. The guard is substring-based and does not parse
   negation context.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
related: "#4623 #4666 #4706"

# Learning: a feature gated on a predicted external-vendor policy date needs its rationale re-confirmed when the date arrives — re-frame the spent gate, don't remove it

## Problem

The operator-cc-oauth feature (merged 2026-06-02, PR #4824) let the operator fund
their own agent runs with a Claude Code subscription OAuth token. Its legal basis
was pinned to a **predicted** Anthropic policy transition: that on 2026-06-15, a
per-user "Agent SDK credit" would *explicitly permit* third-party-app subscription
use. The code encoded a hard `CC_OAUTH_EFFECTIVE_DATE = 2026-06-15` gate, and the
brainstorm's CLO verdict was "permitted-with-guardrails on/after June 15."

On 2026-06-16 Anthropic emailed that the change was **paused** — "nothing has
changed; Agent SDK / claude -p / third-party usage still draws from your
subscription's usage limits." The predicted permission never landed. The feature's
recorded rationale was now asserting a **false legal basis** across four surfaces
(code comments, `.env.example`, brainstorm, and implicitly the verdict).

## Solution

1. **The brainstorm had pre-registered the re-review trigger** ("the verdict is null
   and void if Anthropic amends the article"). When the trigger fires, run a fresh
   CLO assessment against the *amended* source — don't assume the original verdict
   still holds.
2. **Re-frame, don't remove, the spent gate.** The `CC_OAUTH_EFFECTIVE_DATE` constant,
   both error classes, and the fail-closed branches stayed byte-for-bit unchanged
   (removing the date branch would be a runtime change and would break the lease
   test). Only the *comments* changed: the date is recast from "legal floor / the
   date the conduct becomes permitted" to a **spent gate** — a now-passed boundary
   that no longer corresponds to any policy transition. The live load-bearing gates
   are the kill-switch + owner-only routing.
3. **Downgrade the basis honestly:** permitted → "tolerated / metered subscription
   use, owner-only no-share enforced in code, operator-borne risk-acceptance." A
   stale "permitted" claim is a worse liability than an honest "tolerated, risk-
   accepted" one.
4. **Record the re-review as a durable audit** (`knowledge-base/legal/audits/`) and
   supersede the original verdict *in place* (annotate, don't delete) so the audit
   trail of *why* the verdict changed survives.

## Key Insight

When a feature's correctness or legality is gated on a **predicted external event
at a fixed date** (a vendor policy change, a regulation effective date, an API
deprecation), the date constant is a *liability that needs re-confirmation when it
arrives*, not a fact. Pre-register the re-review trigger at build time; when the
date passes, verify the predicted event actually happened. If it didn't, the gate
becomes "spent" — keep it fail-closed for behavior-preservation, but correct every
comment/doc that described the date as conferring permission. The single most
important review lens for the correction PR is **cross-artifact accuracy**: the
corrected prose (comments, env, docs, audit) must match the actual code AND each
other — verified here by security-sentinel (claim-by-claim vs code) and
code-quality-analyst (four-surface consistency).

A secondary insight surfaced at review: **don't embed the verbatim external quote
that is itself the re-review trigger into source comments** — it creates a drift
surface for the exact sentence whose change you're watching for. Keep the verbatim
quote in the single audit-of-record; reference it elsewhere.

## Session Errors

1. **IaC-routing hook false-positive on Sharp-Edge prose** ("operator restarts
   container") — Recovery: documented `<!-- iac-routing-ack -->` opt-out (plan
   provisions zero infra). Prevention: working as designed; the opt-out is the
   sanctioned escape for prose that names infra without provisioning it.
2. **Worktree-write guard required `.worktrees/` path** — Recovery: retargeted the
   write. Prevention: working as designed (hr-when-in-a-worktree-never-read-from-bare).
3. **`sleep 30`-chained Bash blocked by harness** — Recovery: used the Monitor tool
   with an until-loop. Prevention: already harness-enforced; use Monitor/`run_in_background`
   to wait on conditions, never chained `sleep`.
4. **Review agent observed stale bare-repo CWD between Bash calls** — Recovery: agent
   self-recovered with absolute worktree paths. Prevention: already documented
   (Bash CWD does not persist reliably across calls in worktrees); use absolute paths.

All four are one-offs or already-enforced — none warranted a fix or a new issue.

## Tags
category: workflow-patterns
module: byok / legal-audit / operator-cc-oauth

# Learning: A framing-split probe + live vendor-ToS verification can flip a triad "PROHIBITED" verdict

## Problem

A brainstorm ("add CC/Claude-subscription login alongside API key") drew a fast, convergent
**PROHIBITED** verdict from the CPO+CLO+CTO triad: customer-facing subscription auth violates
Anthropic's Consumer Terms (credential sharing / pooling) and the onboarding win is illusory
for a non-technical ICP. That verdict was *correct for the framing it was given* — but it was
not the only framing, and it was premised on the terms as they stood **today**.

Two moves changed the answer:

1. **Framing split.** The user re-asked: "could *we* (the operator) use it ourselves to build
   Soleur in the web app?" — operator self-use, not a customer feature. That instantly removes
   the two fatal clauses (credential *sharing* and *pooling*), because the operator's own
   subscription funds only the operator's own runs.
2. **Live vendor-ToS check.** Anthropic shipped a policy change effective **June 15, 2026**
   (13 days after the session): Pro/Max/Team/Enterprise plans get a monthly Agent SDK credit
   that explicitly covers *"third-party apps that authenticate with your Claude subscription
   through the Agent SDK,"* per-user, no pooling. Training data (and the triad's first pass)
   reflected the *pre-June-15* regime. Verifying the official support article live
   (support.claude.com article 15036540) flipped the operator-self-use verdict to
   **permitted-with-guardrails**.

## Solution

- On any **credentials / auth / ToS** brainstorm, probe the **customer-facing vs.
  operator-self-use** framing split *before* accepting a blanket prohibition. The two have
  different ToS surfaces (sharing/pooling/reselling clauses apply to the former, not the
  latter).
- **Verify external-vendor commercial/ToS terms against the live official source dated to the
  present**, not training data — vendor terms drift and can flip within days. WebFetch the
  primary source (the vendor's own legal/support page), quote the governing clause, and note
  the effective date.
- Re-scoped to operator self-use, the build reused Soleur's existing BYOK lease/encryption/RLS
  machinery: a `credential_type` column on `api_keys` + a mutually-exclusive env-injection
  branch, gated to internal accounts, behind a flag, with a hard effective-date gate and a
  hard owner-only-routing guard.

## Key Insight

A domain-leader "PROHIBITED" is a verdict on **one framing under one snapshot of the rules**.
Before banking it, ask (a) "is there a narrower actor/scope that dissolves the fatal clause?"
and (b) "are the rules I'm citing the *current* rules?" Both are cheap; both can invert the
outcome.

Secondary insight — the **both-keys precedence trap**: if both `ANTHROPIC_API_KEY` and
`CLAUDE_CODE_OAUTH_TOKEN` are set, the API key silently wins and bills API rates while the user
believes they're on subscription. Subscription-vs-API credential injection MUST be mutually
exclusive (exhaustive `: never`-railed branch), never an allowlist add.

## Session Errors

- **Explore agent concluded subscription-OAuth is "not viable server-side"** — it was unaware
  of `CLAUDE_CODE_OAUTH_TOKEN` / `claude setup-token`, which the Agent SDK honors. Recovery:
  corrected from first principles; CTO agent confirmed the SDK reads the var from the spawned
  subprocess env. **Prevention:** when a subagent asserts an external capability is "not
  viable / not supported," verify the *specific* mechanism (env var, SDK option, CLI flag)
  against live docs before propagating it into brainstorm artifacts.
- **`SendMessage` tool unavailable** when trying to continue the CLO agent in-context for the
  re-scope. Recovery: re-spawned a fresh CLO with the full updated framing carried in the
  prompt. **Prevention:** don't assume SendMessage is registered; default to a fresh spawn
  with carried context for agent re-queries.
- **Subagent transient empty greps** (CTO: "earlier empty greps were a cwd-reset env quirk,
  not missing files"). Recovery: agent self-corrected. **Prevention:** already covered by
  existing bare-repo grep learnings.

## Tags
category: workflow-patterns
module: brainstorm

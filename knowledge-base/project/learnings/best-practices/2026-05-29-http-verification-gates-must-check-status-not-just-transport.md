---
title: HTTP verification gates must check status, not just transport (curl -sS fails open on 4xx/5xx)
date: 2026-05-29
category: shell-scripting
tags: [verification-gate, fail-open, curl, http-status, flagsmith, eval-verify, single-user-incident, review-finding]
symptoms: [A verification step passes (exit 0) during an upstream API error, A control-negative / leak assertion reads an error body as the safe state, "✓ verified" printed while the real state was never observed]
module: flag-tooling (plugins/soleur/skills/flag-set-role)
problem_type: silent_failure
resolution_type: code_fix
root_cause: missing_validation
---

## What happened

PR-2 of #4581 added an **evaluation-layer re-verify** to `flip.sh --org`: after writing
per-org segment membership it evaluates the flag for a transient identity (the production
`getIdentityFlags` path, `POST edge.api.flagsmith.com/api/v1/identities/`) and asserts the
target org is enabled AND a **control org is NOT enabled** (the load-bearing "no leak to a
second org" gate, at a `single-user incident` brand-survival threshold).

The first implementation called `curl -sS` (no `-f`, no status inspection) and parsed the
JSON with a fall-through: "flag absent from `flags[]` → print `false` (disabled)". Two
multi-agent reviewers (user-impact-reviewer + code-reviewer) independently flagged that this
**fails open**: `curl -sS` exits `0` on a 4xx/5xx, the error body has no `flags[]`, so the
parser returns `false` — and `false` is exactly the value the control-negative assertion
(`[[ "$GOT_CONTROL" != "false" ]]`) and the `off`-case target assertion treat as **pass**.
An operator running the enable during an edge-API blip would get a green `✓ eval-verified`
having observed nothing. The unit tests all used well-formed `200` bodies, so the suite
never exercised the error path — the fail-open was invisible.

## The rule

**A verification/gate that reads an external HTTP response must require a success status
before interpreting the body, and must treat any non-2xx (or transport error) as
UNVERIFIED → fail loud, never as the safe/negative outcome.** Concretely for shell+curl:

- `resp=$(curl -sS -w '\n%{http_code}' …)`; split the trailing code; `[[ "$code" =~ ^2[0-9][0-9]$ ]] || return <err>`.
- Only after a 2xx may "field absent → negative" be treated as authoritative.
- Add a test that returns a 5xx / `{}` and asserts the gate exits non-zero. A gate whose
  tests only feed healthy bodies is not testing the gate's failure semantics.

`curl -sS` silences progress, NOT HTTP errors; `curl -f` turns 4xx/5xx into a non-zero exit
but discards the body. When you need both the body and a hard failure, capture
`%{http_code}` explicitly.

## Secondary finding (same review): isolate what the gate measures

The eval identity originally carried `role=prd|dev`, which also matches the `role-prd`/
`role-dev` segments — so a flag with a role-segment override would evaluate enabled for
*every* identity and the control-negative would fire spuriously. Fix: use a sentinel role
trait (`__flag-verify__`) that matches no role segment, so the per-org assertion measures
the **per-org segment gate** specifically, decoupled from any role rollout. General lesson:
a verification identity/fixture should activate exactly the gate under test and nothing else.

## Follow-on (caught at the live cutover): tolerate propagation SYMMETRICALLY

The first fix added an HTTP-status gate and an `eval_until` retry on the **target**
assertion (poll until enabled), but left the **control-negative** as a single-shot read.
At the real byok@jikigai cutover this false-positived: immediately after creating the
segment + override, the eventually-consistent edge environment document briefly reported
the *non-member* control org as enabled for one refresh window, and the single-shot
control read aborted a correct enable (exit 3 "control leak"). Direct re-eval a moment
later, and an idempotent re-run, both showed the correct state (target ON, control OFF).

Lesson: when a verification gate reads an eventually-consistent source, **every** leg of
the assertion must tolerate propagation the same way — poll until the value *settles*, not
a single read. Fix: control now `eval_until … false` (polls until it settles to disabled;
a genuine leak never settles → budget exhausts → fail loud; an HTTP error still returns
non-zero). A one-sided retry (happy path tolerant, negative path single-shot) is itself a
flake/false-positive vector.

## Why it matters

The fail-open turned the single automated barrier between an operator command and a
legally-sensitive `byok-delegations` flag reaching a non-opted-in org into a no-op under
the exact condition (upstream flakiness) where you most need it. Caught pre-merge by
adversarial multi-agent review; the cheap permanent guard is the HTTP-error test, not the
reviewers. See [[2026-05-29-feat-flag-org-scoping-plan]] (FR8), ADR-043 §"Per-feature
segment scoping".

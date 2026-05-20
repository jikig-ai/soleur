---
name: online-write-on-source-of-truth-breaks-detection-invariant
description: When an architecture proposal adds an online write path to a config/store that an existing detection primitive reads from, the detection's invariant silently regresses. The detector now reads what an online attacker can plant.
date: 2026-05-20
category: architecture
module: engineering
tags: [security, detection, drift-guard, threat-model, brainstorm, doppler]
related_issues: [4115, 3187, 3244]
related_brainstorms:
  - knowledge-base/project/brainstorms/2026-05-20-github-app-manifest-brainstorm.md
  - knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md
---

# Learning: Online write on a detection's source-of-truth silently regresses the detection's invariant

## Problem

Brainstorm #4115 proposed an HMAC-gated callback that would receive 5
GitHub-App credentials from a third-party POST and write them directly
into Doppler `prd`. The sibling drift-guard
(`scheduled-github-app-drift-guard.yml`, shipped via #3187) asserts the
App's identity by reading `id` and `client_id` from Doppler-sourced GH
Actions secrets and comparing them against `gh api /app`.

The framing in the issue body treated these as orthogonal additions
("automate provisioning" + "existing drift-guard catches identity
swaps"). They are not orthogonal: the drift-guard's value depends on
the App credentials being **immutable from any online actor's
perspective**. Today, an attacker cannot rewrite Doppler `prd` without
operator-supplied tokens. Adding an HMAC-gated callback that writes 5
credentials on receipt of a GitHub POST converts that offline-only
surface into an online-writable one. An attacker who (a) acquires the
init route's HMAC key or (b) coerces the operator into initiating a
parallel manifest flow could plant their own App's credentials in the
config the drift-guard reads — and the drift-guard would happily
assert `live App id == planted Doppler value` (both attacker-controlled),
silencing the alert.

## Solution

CTO surfaced this at brainstorm Phase 0.5; the response was a scope cut.
Approach A (manifest JSON only, no callback) preserves the airgap. The
generalized pattern matters more than the specific case: **before
adding any online write path to a config/store/file, enumerate which
existing detection primitives read from it, and ask whether the
detector's "expected" side needs to move out-of-band.**

If the online write is unavoidable, three mitigations stack:

1. **Move the detector's "expected" side out of the writable store.**
   Sign a manifest in the repo; have the detector compare live state
   against the signed file, not against the rewritten config.
2. **One-shot the write path.** After first successful write in a given
   env, the route returns 410 forever. Requires a separate persistent
   flag (NOT in the writable config — that flag is also rewriteable).
3. **Out-of-band attestation.** A scheduled job that POSTs deliberately
   forged callbacks against production and asserts 401 (Art. 32(1)(d)
   "regular testing" — CLO surfaced this as a mandatory companion if
   the callback ever ships).

None of these mitigations are needed when the write path simply
doesn't exist.

## Key Insight

A detection primitive's threat model is load-bearing on what the
"expected" side of the comparison cannot be rewritten by an online
actor. Adding any feature that lets an online actor write to the
"expected" side regresses the detection silently — the detector keeps
running, keeps reporting "no drift", and looks healthy in CI. The
regression is invisible at PR review unless a reviewer holds both the
detector's threat model AND the new write path in their head
simultaneously.

This applies beyond drift-guards: any "compare live state X to
config-stored expected Y" detector — schema validators, allowlists,
flag-gate audits, IP-allowlist drift, certificate-pin checks — assumes
Y is offline-writable-only. Sanity check at brainstorm time, before
the write path lands.

## When to Apply

At brainstorm Phase 0.5 / Phase 1.1, when an architecture proposal:

- Adds a new write surface (HTTP endpoint, CLI tool, API call) to any
  Doppler config, GitHub Actions secret, Supabase table, repo-tracked
  file, or DNS record, AND
- An existing detection primitive (cron, hook, validator, audit) reads
  from that same surface.

Force the question: "Does the detector's expected side need to move
out-of-band?" If yes, that motion is part of the in-scope work for the
write-surface PR — not a follow-up.

## Anti-Pattern

Treating the detector's continued existence as evidence the detector
still works. A detector that reads attacker-writable inputs has
degraded to a tautology checker (`x == x`).

## References

- Issue #4115 (originating brainstorm)
- Issue #3187 (drift-guard implementation)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-20-github-app-manifest-brainstorm.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`
- Rule: `hr-weigh-every-decision-against-target-user-impact`

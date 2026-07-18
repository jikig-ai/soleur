---
title: "A 'remove the stale/dead X' infra issue is a premise to VERIFY, not an instruction to execute"
date: 2026-07-12
issue: 6357
pr: 6358
category: workflow-patterns
tags: [infra, terraform, cloudflare-tunnel, premise-verification, incident-derived]
---

## Problem

Issue #6357 (incident-derived, filed after a transient 2026-07-11 deploy-tunnel 502)
asked to **remove or repoint** a `registry.soleur.ai → tcp://10.0.1.30:5000` Cloudflare
tunnel ingress rule, on the stated premise that it was a **"stale leftover pointing at a
dead origin"** from a "registry migration nbg1→hel1 (#6288)."

Executing that ask literally would have **broken CI registry push**: the rule is the LIVE
ADR-096/#6122 registry-push path, and removing it takes down `cloudflared access tcp
--hostname registry.<base>`.

## Root Cause / Reality

The issue's premise was false on every sub-claim, verified against git history + config:
- **"Stale leftover"** → the rule was deliberately added in #6120/#6122 (ADR-096) with a
  dedicated CF Access app + service token; `git log tunnel.tf` shows active work through #6202.
- **"Dead origin, moved to a new host per #6288"** → #6288 moved the registry **region**
  (nbg1→hel1) and recreated the store volume, but the **private IP `10.0.1.30:5000` is
  unchanged** (`10.0.1.0/24` spans hel1; `zot-registry.tf:40 registry_private_ip="10.0.1.30"`).
  Repointing is a no-op.
- **"#6288 is a migration PR"** → #6288 is an **OPEN issue** ("zot registry restart-loops ~4/min,
  likely OOM"); it is the registry-**stability** tracker. The `dial … canceled` errors mean the
  origin was transiently **down**, not that the config is wrong.

## Solution

Re-scope from *remove* to *correct-the-premise + fail-fast hardening* (a 2-field, in-place
`tunnel.tf` edit):
1. Correct the false "stale rule" comment in-line so the next reader does not delete the live
   push path (defuse the destructive-mis-fix footgun the issue itself requested).
2. Add `origin_request { connect_timeout = 5; no_happy_eyeballs = true }` scoped to the
   registry ingress rule — bounds the TCP dial so a DOWN origin can't pile up ~30s-held dials
   that saturate the shared tunnel daemon and degrade the sibling deploy-webhook route.
3. Root cause (registry stability) → #6288; deploy-tunnel decoupling + metrics → #6178. Neither
   fixed here.

## Key Insight

An incident-derived "delete/repoint the stale/dead thing" issue is a **claim to verify against
git history + the actual config**, not an instruction to execute — the same class as
`hr-verify-repo-capability-claim-before-assert` and the go-routing "external-bug claim is a
claim to VERIFY" sharp edge, applied to *remove-requests*. Before removing infra an issue calls
"stale": `git log --oneline -- <file>` the rule to find its introducing PR/ADR, and grep the
origin address (`registry_private_ip`, endpoint locals) to confirm the "moved/dead" claim.
Cheapest gate; the downside of skipping it is a self-inflicted outage on the exact path the
issue thought it was cleaning up.

## Session Errors

- **Local `terraform plan` failed twice during pre-merge verification.** — Recovery: (1) first
  attempt omitted `--name-transformer tf-var`, so every `var.*` was "No value for required
  variable" — the CI workflow (`apply-web-platform-infra.yml`) injects vars via
  `doppler run -c prd_terraform --name-transformer tf-var --`; (2) the corrected attempt then hit
  "No valid credential sources found" because the R2 state backend + providers need the full CI
  AWS-SSO credential set, not replicable in a local session. — Prevention: for an infra-only edge-
  config change, `terraform validate` + `fmt -check` + the AC greps are the authoritative LOCAL
  gates (the plan itself designates `validate` as the arbiter for the `connect_timeout` type); the
  live plan+apply is exercised by the merge-triggered apply workflow — do not burn cycles
  replicating the CI cred env locally.
- **Orphan plan draft from a mid-run date rollover.** — Recovery: `/plan` wrote
  `2026-07-11-...plan.md`; the date rolled to 07-12 before `/deepen-plan`, which emitted a NEW
  canonical `2026-07-12-...` file (referenced by `tasks.md`) and left the 07-11 draft untracked.
  Removed the orphan during /work so a single plan file remains. — Prevention: on a
  plan→deepen-plan run that crosses UTC midnight, expect two dated plan files; keep the deepened
  one (matches `tasks.md` `plan:` frontmatter) and drop the orphan.
- **Forwarded (plan/deepen phase, one-off):** an SSH-in-command grep false-positive matched the
  prose "without SSH" in the Observability `expected_output` (reworded); `connect_timeout` type
  disagreement between research sources (resolved: integer, verified by `terraform validate`).

---
title: "GHCR installation-token minter (#6031) — hard-dependency gate, ADR-ordinal drift, and CI-as-empirical-evidence"
date: 2026-07-05
tags: [supply-chain, ghcr, github-app, inngest, dependency-sequencing, adr, one-shot]
issue: 6031
pr: 6034
---

# feat #6031 — control-plane GHCR installation-token minter (ADR-088)

Session learnings from resuming a hard-blocked one-shot after its dependency merged.

## 1. A fail-closed dependency gate is a real terminal state — halt cleanly, don't improvise

`#6031` layered onto artifacts that only existed in the unmerged PR #6011 (`ghcr-read-credential.tf`,
the deploy/boot consumers, and the ADR itself). The plan's Phase-0.1 precondition gate (assert
those artifacts are on `origin/main`) failed. The correct move was to **halt the whole one-shot
pipeline before building anything**, preserve the deepened plan on the draft PR, record the block
in `decision-challenges.md`, and report — NOT to re-author #6011's artifacts (double-authoring
`ghcr-read-credential.tf` + the ADR would collide at merge). The apparent "deadlock" (the other
session offered to "skip the PAT by doing #6031 first") was illusory: the dependency is strictly
linear (#6011 → #6031), and #6031 structurally cannot precede #6011's merge. The interim PAT is
the load-bearing bridge that lets #6011 ship and keeps deploys working until the minter is proven.

## 2. Plan-quoted ADR ordinals are stale after sibling PRs land — verify at resume

The plan referenced the minter ADR as "ADR-086" throughout. By the time #6011 merged, three
UNRELATED sibling PRs had each claimed the ADR-086/087 ordinals, and #6011 shipped the minter ADR
as **ADR-088**. The Phase-0.1 gate's literal `grep 'ADR-086-*.md'` would have PASSED falsely (three
086 files exist — none the minter's). Same class as `hr-when-a-plan-specifies-relative-paths` and
the "plan-quoted numbers are preconditions to verify" rule, extended to ADR ordinals: **at resume,
find the ADR by CONTENT (`git grep 'installation.token.minter'`), not by the plan's ordinal.**

## 3. The repo's own CI is stronger empirical evidence than a live spike you can't run

The plan's plan-defining blocking risk (R1: "does GHCR accept App *installation* tokens for
`docker pull`, or only classic PATs?") was framed as a live mint+pull spike. But that spike
CANNOT run pre-cutover — the App lacks the `packages` grant until an org-owner re-consents (a
downstream operator step). R1 was instead settled decisively by the repo's own production CI:
`reusable-release.yml` pushes the `soleur-*` images with the Actions `GITHUB_TOKEN` (which *is* an
App installation token), and `apply-web-platform-infra.yml` `docker login`s + pulls the PRIVATE
package with it. Code-tracing proven CI behavior is the valid substitute for a live repro that
needs hard-to-synthesize state (the `packages:read` install grant).

## 4. "Five-registry lockstep" was actually SIX — trust the failing test, not the plan's list

The plan enumerated a "five-registry Inngest lockstep" (route / cron-manifest / count-test /
sentry-tf / apply-workflow). Adding the cron to `EXPECTED_CRON_FUNCTIONS` broke a SIXTH surface the
plan never listed: `routine-metadata-parity.test.ts` requires a `ROUTINE_METADATA` sidecar entry
per cron id. The full-suite exit gate (not the touched-file loop) caught it. Lesson: a plan's
enumerated lockstep set is a starting hypothesis; the authoritative work-list is the full suite.

## 5. Plan-vs-landed-code contradictions in an IaC security model route to the CTO agent

Phase-2's Doppler design had two contradictions that only surfaced against #6011's LANDED code:
(a) the plan's prd→prd_ghcr cross-config reference secrets collide with #6011's `doppler_secret`
resources (which own those prd keys with `ignore_changes=[value]`); (b) injecting the prd_ghcr
write token into the minter runtime without it landing in `prd` needs a host-provisioning change.
Both are security-model forks on the deploy critical path at a `single-user incident` threshold →
routed to the `cto` agent (not the operator). Ruling: **option B** — put `GHCR_MINTER_DOPPLER_TOKEN`
in `prd` (surfaced via the existing single `--env-file` path, zero cloud-init change), keep the
token `prd_ghcr`-*scoped* (the at-rest bound that matters), reject a second cloud-init download (it
would leak a control-plane write cred onto every tenant host — the #5274 escalation). The
`prd_ghcr` runtime isolation buys nothing today because the org-wide-WRITE App key is already
co-resident in the same `prd` container env. The cross-config flip is a live-Doppler op (permitted
by `ignore_changes=[value]`), mint-first-ordered, deferred to the Phase-6 cutover.

## 6. Output-aware heartbeat must classify EVERY failure class, incl. the transport reject

Review P1 (security-sentinel + observability converged): the Doppler `fetch()` sat outside the
mint try/catch, so a network-layer reject (DNS/TLS/timeout/ECONNRESET — "Doppler unreachable")
bypassed BOTH the terminal error heartbeat AND `reportSilentFallback`, degrading a Doppler outage
on the deploy critical path from an immediate `error` page to a ~40-min missed-checkin. An
output-aware heartbeat's failure enumeration must include the transport-reject class, not just
non-2xx; wrap the whole write in a numeric-safe catch (`fetch` errors carry no body/token) and add
an `AbortSignal.timeout` so a hung socket also classifies rather than hangs.

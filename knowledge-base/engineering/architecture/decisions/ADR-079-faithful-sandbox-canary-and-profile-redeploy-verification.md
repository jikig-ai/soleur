# ADR-079: Faithful SDK sandbox canary + profile-apply→redeploy verification contract

- **Status:** Adopting
- **Date:** 2026-07-01
- **Deciders:** Jean (operator), CTO agent (binding rulings: `aggregate pattern` threshold; PR1 phase-guard mechanism), Engineering domain review
- **Relates to:** #5875 (this hardening), #5873 / #5874 (the P0 + its fix), #5849 (the SDK bump 0.2.85→0.3.197 that split `unshare()`), #4932 / #4941 (the false-rollback lesson), ADR-031 (Sentry-as-IaC), ADR-068 (cron drain — since renumbered ADR-078), ADR-075 (agent-sandbox config the canary imports), ADR-072 (adaptive deploy gate), ADR-027 (single-replica swap invariant)

> **Ordinal note.** This ADR was planned as ADR-077, but siblings #5766 (ADR-077 routine-run lifecycle) and #5669 (ADR-078 graceful cron drain) landed that window on `main` first. Renumbered to **ADR-079** at work-start per `scripts/check-adr-ordinals.sh`.

## Context

On 2026-07-01, #5849 bumped `@anthropic-ai/claude-agent-sdk` 0.2.85→0.3.197. The
new SDK **split** its bubblewrap setup into `unshare(CLONE_NEWUSER)` followed by
a second `unshare(CLONE_NEWPID|CLONE_NEWNS)`. The container seccomp profile only
allowed `unshare` when `CLONE_NEWUSER` was set, so the second call `EPERM`'d and
the Concierge Bash sandbox was down for **every tenant** until #5874 added two
allow-rules. Three independent amplifiers turned a routine dependency bump into a
silent, fleet-wide outage:

1. **The deploy canary validated a code path the SDK no longer uses.** It probed
   `bwrap --unshare-pid` directly, never exercising the split `unshare()`, so
   #5849 shipped green. A prior attempt (#4932) hand-rolled bwrap argv, which
   *also* mismatched the real SDK argv and false-rolled-back every deploy — it
   was reverted (#4941). Faithfulness to the SDK's actual argv is the crux.
2. **Zero server-side signal.** The catch sites tagged only the SDK's
   missing-binary preflight substring (`"sandbox required but unavailable"`). A
   seccomp `EPERM` has a different stderr (`bwrap: … Operation not permitted`),
   so it fell through to a bare untagged `captureException` — invisible to
   on-call filters. The failure was visible only in the agent transcript.
3. **"Applied" ≠ "loaded".** A seccomp-profile edit auto-applies to the host, but
   the container only loads a new `--security-opt` at `docker run`. The redeploy
   that loads it fires concurrently and unordered on the same merge, so a fix
   deploy can run the *stale* profile and go green while every tenant stays
   broken — worst during a *recovery* (a #5874-style fix must actually load).

Phase-0 spike findings (recorded in #5875), verified against the installed
`@anthropic-ai/claude-agent-sdk@0.3.197`:

- **Error shape:** the bwrap/seccomp stderr (incl. `Operation not permitted`) is
  merged into the thrown `Error.message` (plain `Error`; no `.stderr`/`.cause`).
  So classification keys on the message text.
- **No-model-round-trip: NO.** Sandbox init is gated behind `query()` (an
  Anthropic API call) and the internal Bash tool is always model-driven, so a
  *faithful* canary needs creds + network and must handle model
  non-determinism. This turns the PR2 canary into a mechanism fork (model-turn
  vs. capture-and-replay argv) routed to the CTO agent at PR2 kickoff.

## Decision

Harden the agent-sandbox against SDK-bump breakage across three PRs, governed by
two load-bearing invariants and one coupling contract.

### 1. Observability first (PR1 — this ADR is authored here, status `adopting`)

Every sandbox-startup failure emits a structured, `feature:"agent-sandbox"`,
`op:"sdk-startup"` Sentry event carrying `sandboxKind`
(`missing_binary | seccomp_or_userns_denial | other`), a low-cardinality
`sandboxErrorCode`, the installed `sdkVersion`, and the raw stderr. A single
decoding site — `server/sandbox-startup-classifier.ts`, mirroring the
`abort-classifier.ts` precedent — replaces the scattered substring checks.

**Emit-decision mechanism (CTO-ruled).** Both catch sites tag
`feature:"agent-sandbox"` **iff** `classifySandboxStartupError(err).sandboxKind
!== "other"` — the error SIGNATURE, with **no stream-phase gate**. The signature
match (a bwrap/unshare/seccomp/`CLONE_NEW*` namespace token, or the SDK's
missing-binary preflight phrase) is necessary and sufficient to exclude a
mid-conversation model/API error (`overloaded_error`, context-length, generic
5xx carry no such token → `"other"` → untagged), **even though
`streamStartSent === true` at the catch**. A `streamStartSent === false` gate was
**rejected**: `streamStartSent` is set unconditionally *before* the SDK iterator
loop (`agent-runner.ts:2111`), so it is always true at the catch, and the #5873
seccomp denial surfaces *after* `stream_start` (the sandbox wraps the
model-driven Bash tool, Phase-0 §0.2) — the gate produced a silent no-op (zero
emits on the exact incident shape), the #5875 User-Brand-Impact failure mode.
Because the signature is now the *only* mis-tag guard, the load-bearing
invariant is that a **bare EPERM / "operation not permitted" with no namespace
token stays `"other"`** (`OPERATION_NOT_PERMITTED` only refines `errorCode`
inside an already-namespace-matched branch — it never independently triggers
tagging; pinned by a unit test). *Accepted edge:* the classifier keys on the full
`err.message`, so a mid-conversation Bash command that *itself* fails invoking
`bwrap`/`unshare` would tag as `sdk-startup` — low-frequency and arguably a
correct sandbox signal; not suppressed. The emit is **per-user** (agent-runner via undebounced `reportSilentFallback`;
cc-dispatcher via `mirrorWithDebounce` keyed per-`(userId, class)`) — never a
global-key debounce — so Sentry's **native affected-users threshold**
(`event_unique_user_frequency`, ≥3 tenants / 1h) can distinguish a one-tenant
blip from a fleet outage. **That threshold counts distinct Sentry *users*, not
`extra` keys** — so `reportSilentFallback` promotes the pseudonymized
`userIdHash` to the event's `user.id` (`observability.ts` `userScopeFromExtra`);
without it the count stays 0 and the alert can never fire (caught at PR1 review by
`observability-coverage-reviewer`). Attribution is pseudonymized: raw `userId` is
passed and auto-hashed to `userIdHash` at the emit boundary (`user.id =
userIdHash` keeps Recital-26 intact); raw `workspacePath` is never emitted. Only
`sandboxKind` + `sdkVersion` are searchable **tags**; `sandboxErrorCode` (a
refinement recoverable from stderr) rides in `extra` to avoid a redundant tag.
The alert is IaC (ADR-031): `apps/web-platform/infra/sentry/issue-alerts.tf`.

### 2. Faithful canary (PR2 — dark-launch, non-blocking)

A payload (`apps/web-platform/scripts/sandbox-canary.mjs`, baked into the image)
**imports `agent-runner-sandbox-config.ts`** and feeds that exact options object
into the SDK, so its bwrap argv *is* the SDK's argv, version-locked to the tree.
Hand-rolled argv is disqualified (it caused both #5849's false-green and #4932's
false-rollback). Wired non-blocking alongside the legacy `ci-deploy.sh` probe,
which stays the gate during dark-launch; a "faithful FAIL + legacy PASS"
disagreement is the promote-readiness signal. Exit-code classification
distinguishes `canary_infra_error` (125/126/127/ENOENT — do NOT roll back) from
`sandbox_broken` (`bwrap … Operation not permitted`). Promotion to blocking is
soak-gated (5 green verdicts over ≥3 days).

### 3. SDK-bump guard + profile→redeploy coupling (PR3)

- A `pull_request` CI job detects a resolved-version change of the two
  `@anthropic-ai/*` SDK packages in **`package-lock.json`** (deploy-authoritative
  via `npm ci`) — plus a `bun.lock`↔`package-lock.json` parity assertion — and
  runs the faithful canary via `docker run` on the *committed* profile (blocking
  at PR-time).
- The **apply workflow itself** redeploys after applying the seccomp/apparmor
  profile (a sequenced step, not a shared concurrency group — which serializes
  but does not order), then asserts the running container's
  `seccomp_profile_sha256` equals `sha256(committed)` + canary pass; fail loud
  (`::error::` + `exit 1` + Sentry) otherwise. `flock` in `ci-deploy.sh` dedupes
  the concurrent release deploy (idempotent, ADR-078-drained). No self-healing
  control loop.
- AppArmor apply-parity: `terraform_data.apparmor_bwrap_profile` is folded into
  the workflow's `-target=` set + `on.push.paths` (identical bug class).

Flip this ADR to `accepted` in PR3.

## Consequences

- **Positive.** A future SDK bump that breaks the sandbox is caught pre-merge
  (SDK-bump gate) or, failing that, produces a filterable `feature:agent-sandbox`
  Sentry event within seconds instead of the "invisible" MTTR of #5873. A
  recovery fix is proven to actually *load* (loaded==committed assert), not just
  apply. The canary tracks the SDK's real argv, so it cannot drift into
  false-green (#5849) or false-rollback (#4932).
- **Negative / risks.** A broadened classifier could false-tag → mitigated by
  signature-based detection (a model/API error carries no bwrap/seccomp token →
  `other` → untagged). A flaky canary could false-roll-back → mitigated by
  dark-launch-before-blocking (`wg-dark-launch-deploy-gates`) + exit-code
  classification. The CI SDK-bump gate's runtime is bounded per the CTO-chosen
  canary mechanism (PR2).
- **Scope.** This ADR adds gates + observability only; #5874's hardened seccomp
  rules are untouched. No new `TF_VAR_*`; the redeploy reuses existing Doppler
  secrets.

## Alternatives Considered

- **Hand-rolled bwrap argv canary** — rejected: can't track the SDK; caused
  #5849 (false-green) and #4932 (false-rollback).
- **Item-4 self-healing verify loop** (poll→detect-drift→retrigger) — rejected
  as overbuilt vs. one graceful, idempotent, sequenced redeploy.
- **Item-4 via shared GHA `concurrency:` group** — rejected: serializes but does
  not order; different groups.
- **Item-4 via `docker restart`** — rejected: cannot reload a `docker run`-time
  `--security-opt`.
- **Custom distinct-tenant aggregate alert** — rejected (YAGNI): Sentry's native
  `event_unique_user_frequency` suffices; the only real requirement is not to add
  a global-key debounce.
- **Detect SDK bump via `bun.lock`** — rejected: `package-lock.json` is
  deploy-authoritative; key on it + parity-assert `bun.lock`.

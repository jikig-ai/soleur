# ADR-079: Faithful SDK sandbox canary + profile-apply→redeploy verification contract

- **Status:** Adopting
- **Date:** 2026-07-01
- **Deciders:** Jean (operator), CTO agent (binding rulings: `aggregate pattern` threshold; PR1 phase-guard mechanism; PR2 canary mechanism — hybrid capture-in-CI / replay-at-deploy), Engineering domain review
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

**Mechanism (CTO-ruled at PR2 kickoff — the Phase-0 §0.2 fork): HYBRID —
capture-in-CI, replay-at-deploy.** The two runtime contexts are not two competing
mechanisms; they are the **capture** end and the **replay** end of one
faithfulness pipeline. A single payload
(`apps/web-platform/scripts/sandbox-canary.mjs`, baked into the image) has two
modes:

- **`--capture` / `--verify` (CI only, PR3, creds-gated).** Puts a
  bwrap-intercepting shim on `PATH`, **imports the real
  `buildAgentSandboxConfig` from `agent-runner-sandbox-config.ts`** (lazily — a
  dynamic `import()` kept out of the replay graph), feeds that exact options
  object into the SDK `query()`, runs one no-op Bash op so the SDK builds+spawns
  its real split-unshare argv, and snapshots the bwrap **SETUP** argv to the
  committed fixture `apps/web-platform/infra/sandbox-canary-argv.json`. `--verify`
  re-captures and byte-diffs against the committed fixture, failing the PR on
  drift. The argv is a pure function of `(SDK version, sandbox config)` — both
  in-tree — so PR3's gate re-captures whenever **`package-lock.json` OR
  `agent-runner-sandbox-config.ts` OR `sandbox-canary.mjs`** changes (a plan
  correction: keying re-capture on `package-lock.json` alone would let a config
  reshape stale the fixture silently). This decouples faithfulness from the
  model turn and confines the paid/nondeterministic Anthropic call to CI.
- **`--replay` (DEFAULT, deploy-time, PR2).** `ci-deploy.sh` runs
  `docker exec <canary> node /app/scripts/sandbox-canary.mjs --replay` INSIDE the
  running canary container, which reads the committed fixture and runs
  `bwrap <captured-setup-argv> -- true` against the **loaded** `--security-opt`
  profile. Creds-free, network-free, deterministic — it never reaches `query()`
  (the host has no ANTHROPIC key and no node; the replay is pure JS). The
  replayed argv *is* the SDK's captured argv, version- and config-locked.

Wired non-blocking alongside the legacy `ci-deploy.sh` probe, which stays the
gate during dark-launch; a "faithful FAIL + legacy PASS" disagreement is the
promote-readiness signal (Sentry event on a faithful FAIL — never journald-only).
Exit-code classification distinguishes `canary_infra_error` (125/126/127/ENOENT —
do NOT roll back) from `sandbox_broken` (`bwrap … Operation not permitted`).
**Dark-launch bootstrap:** the committed fixture ships as an `{"status":
"uncaptured"}` sentinel (never a hand-authored argv — the #4932 trap); until
PR3's CI capture lands the real SDK argv, the deploy-time replay records
`canary_infra_error` / `fixture_uncaptured` (non-blocking; no green soak verdicts
accrue). Promotion to blocking is soak-gated (5 green verdicts over ≥3 days).

**Faithfulness guarantee.** It cannot repeat #5849's false-green because the
replayed argv *is* the SDK's own captured argv — re-captured and byte-diffed on
every SDK-or-config change — so a bump that breaks the profile makes the
deploy-time `bwrap … -- true` EPERM red; and it cannot repeat #4932's
false-rollback because the argv is never hand-guessed and non-EPERM failures
classify as `canary_infra_error` (never `sandbox_broken`).

### 3. SDK-bump guard + profile→redeploy coupling (PR3)

- The **profile→redeploy coupling (item 4)** ships in full. The **apply workflow
  itself** redeploys after applying the seccomp/apparmor profile (a sequenced
  `if: success()` step — not a shared concurrency group, which serializes but does
  not order), then asserts the running container's `seccomp_profile_sha256`
  (recorded by `ci-deploy.sh` at container start, surfaced on `/hooks/deploy-status`
  by `cat-deploy-state.sh`) equals `sha256(committed)`; fail loud (`::error::` +
  `exit 1`) otherwise. `flock` in `ci-deploy.sh` dedupes the concurrent release
  deploy (idempotent, ADR-078-drained). No self-healing control loop. The redeploy
  is conditional-by-construction (loaded==committed → no-op), so it fires only on an
  actual seccomp change. AppArmor needs no redeploy — `apparmor_parser -r` at apply
  reloads the kernel profile for the running container; only seccomp is bound at
  `docker run`.
- **AppArmor apply-parity:** `terraform_data.apparmor_bwrap_profile` is folded into
  the workflow's `-target=` set + `on.push.paths` (identical auto-apply bug class as
  the #5873 seccomp gap).

### Interim mechanism (PR3, option (b) — binding CTO ruling)

The higher-fidelity claim *"the committed profile is valid for the newly-bumped
SDK's **real** argv"* requires a model turn (Phase-0: no no-model-round-trip path)
and was **NOT** forced into the merge-blocking path as a paid, non-deterministic,
`ANTHROPIC_API_KEY`-dependent gate — that is the exact failure mode the #4932 lesson
and the deterministic-LLM-SDK-invocation learning warn against. Instead PR3 closes
the incident **class** deterministically:

- **BLOCKING (deterministic, no creds/model):** resolved-version bump-detection +
  `bun.lock`↔`package-lock.json` parity for both SDK packages
  (`apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, run in the required
  `lockfile-sync` job). On a detected bump, the merge is gated on a maintainer
  `sdk-bump-verified:` acknowledgement (guardrail 2 — **no silent green**; a silent
  skip would re-create #5849). This alone forces a human to look at every SDK bump,
  which is the whole failure the #5849 class was.
- **Would-have-caught regression:** a **structural** proof (always-on, blocking via
  the `test` shard) that the synthesized `seccomp-pre-5874.json` fixture is exactly
  the committed profile minus the two #5874 rules, plus a **runtime** `docker run`
  bwrap discrimination (`sandbox-canary-regression.test.sh`, opt-in from
  `infra-validation.yml` on profile changes; sets `apparmor_restrict_unprivileged_userns=0`
  on the ephemeral GH-hosted runner ONLY — guardrail 3) that replays a synthesized
  split-unshare argv (a file **distinct** from the prod `sandbox-canary-argv.json`,
  which stays `status:"uncaptured"` — guardrail 1) and asserts EPERM under pre-5874
  but pass under committed. The runtime layer is self-validating (SKIPs rather than
  false-fails where the runner cannot do bwrap userns).

### Deferred (tracked) and Adopting → Accepted criteria

Two load-bearing pieces remain **open**, so this ADR **stays `adopting`** (it is NOT
flipped to `accepted` in PR3):

- **Deferral B — creds-gated real `--capture` wiring** — **LANDED (#5913).** Drives
  the real SDK `query()` + `buildAgentSandboxConfig()` via a bwrap-intercepting PATH
  shim to populate `sandbox-canary-argv.json` with the SDK's real bwrap SETUP argv.
  `ANTHROPIC_API_KEY` confirmed as a repo secret; the model-turn non-determinism is
  bounded by retry-N + per-attempt wall-clock timeout + reserved exit `4`, keeping
  the LLM out of the assertion path. B was a hard prerequisite of A: #5889's soak
  held at `fixture_uncaptured` until this real fixture landed. **See the #5913
  amendment below — the "verbatim snapshot, no normalization" mechanism this ADR
  originally specified was empirically falsified and is superseded.**
- **Deferral A — promote the `ci-deploy.sh` faithful canary to BLOCKING**
  (`sandbox_broken` → rollback). Owned by **#5889** (soak: 5 green verdicts / ≥3
  days). Its `earliest=2026-07-06` is necessary-but-not-sufficient — promotion also
  requires B to land first (ordering: **B → soak → A**). Because the canary is still
  non-blocking dark-launch, item 4's redeploy assert treats `pass` /
  `canary_infra_error` / `fixture_uncaptured` as pass-through and fails loud ONLY on
  a faithful `sandbox_broken` (or a loaded≠committed hash mismatch) — NOT on a
  literal "canary pass".

**Flip to `accepted`** only when BOTH land: real-capture wired (B — **now landed,
#5913**) AND the canary promoted-to-blocking after #5889's soak proves green (A),
citing both tracking issues. **Still `adopting`** — A remains open.

### Amendment (#5913, 2026-07-03) — canonical projection supersedes verbatim snapshot

Wiring the real `--capture` empirically **falsified** deferral B's core premise that
"the captured argv is a pure function of (SDK version, sandbox config), byte-repro-
ducible by construction." The real `@anthropic-ai/claude-agent-sdk@0.3.197` bwrap
SETUP argv (176 tokens) embeds three axes the ADR did not anticipate: (a) **per-run
random paths** — a network-proxy socket `/tmp/claude-http-<hex>.sock` and ~12
`/tmp/claude-empty-<rand>` bind sources (change every capture, same machine); (b)
**host-specific binds** (`/home/<user>/.npm/_logs`, `/tmp/claude-<session>/…`, absent
in the prod canary container → a verbatim replay `canary_infra_error`s every time);
(c) **26 `--setenv NAME VALUE` env-forwarded vars**, some secret-shaped (e.g. an
empty `CLOUDSDK_PROXY_PASSWORD`). So a verbatim fixture is neither byte-reproducible
nor replayable off-host, and the `--verify` byte-diff + `normalizeCapturedArgv`-
dropped design were unworkable.

**Resolution (CTO ruling, binding — supersedes the "verbatim snapshot, no
normalization" clause of deferral B):** commit a **canonical projection**
(`normalizeCapturedArgv`, schema `canonical-bwrap-v1`). It KEEPS the seccomp-relevant
structure (all `--unshare-*`, `--dev`, `--tmpfs`, deterministic-const binds `/` `/proc`
`/dev/null`, ws-relative binds), NORMALIZES the hermetic ws root → `${CANARY_WS}` and
the random empty-dir source → `${CANARY_EMPTY}` (substituted back at replay), and
DROPS the non-deterministic/host/secret axes (all `--setenv`, random socket, host
binds; counts recorded in a non-diffed `droppedForDeterminism` audit block). This is
byte-reproducible (two independent captures produce identical canonical fields) AND
replayable off-host. The projection is NOT the ADR's rejected "silent-strip normalizer":
it is a structured projection with a **proof obligation** — the always-on exact
`--unshare-*` multiset assertion — that fails CI if it ever over-drops or the SDK
narrows the sandbox. Two-staged secret-scrub (raw literal-value + canonical
names+value backstop) is retained; reject-never-strip.

**§2d proof-obligation refinement (bwrap-version reality).** The ADR's replay end
cannot reproduce the #5849 split-unshare EPERM via `bwrap <argv> -- true`: bwrap
0.11.x **combines** all `--unshare-*` into one `unshare(…|NEWUSER)` which the #1557
allow-rule permits under BOTH profiles (empirically, the real canonical argv passes
the committed AND the pre-#5874 profile). The #5849 split is a property of the claude
CLI's **nested-process structure**, not any bwrap-argv token, so no argv fidelity
reproduces it. Therefore §2d splits into two argv-independent signals:
1. **#5849 split-unshare discrimination** stays the already-shipped layer-B
   nested-unshare probe (`sandbox-canary-regression.test.sh`; `unshare --user
   --map-root-user unshare --mount --pid`) under both profiles. Unchanged; the only
   thing that discriminates that class.
2. **Real-argv replay** is a **bwrap-level profile-fidelity canary**: "does the SDK's
   real bwrap setup survive the committed profile on the deploy-side bwrap/kernel?"
   The **deploy-time prod-container replay is authoritative** (#5873-shape fleet-
   outage detector); the CI capture-gate self-replay-green is only a capture-sanity
   precheck (runner bwrap/kernel differ from prod, so CI-green ≠ prod-green).
3. **Always-on deterministic guard on the committed fixture:** exact `--unshare-*`
   multiset assertion (A5b) + `--verify` byte-diff drift.

**Recorded residual (follow-up, NOT #5913).** The deploy-time real-argv replay
CANNOT catch a prod-side kernel/bwrap-version regression that re-breaks *specifically*
the nested split (the #5849/#5873 shape) — bwrap replay can't reproduce the nested
unshare. In CI that class is covered at merge by layer-B against the committed profile
file, but a kernel/bwrap regression on the prod host would pass the deploy-time canary
(false-green for that one class). Closing it means running the argv-independent
nested-unshare probe under the deployed profile **inside the prod canary container** at
deploy time. That is a distinct capability, not "wire the real `--capture`" — tracked as
**#5941**, out of #5913 scope.

The CI capture gate is **dark-launch** (non-blocking / not a required status check)
until a cross-environment-determinism soak proves a CI-runner capture reproduces the
committed canonical argv; only its `argv_drift` byte-diff is a candidate block signal
(a captured `sandbox_broken` is unreachable via argv replay, per the refinement above).

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
- **Pure model-turn-driven canary at deploy-time** (PR2 mechanism option (a),
  the alternative to the chosen hybrid) — rejected: it forces ANTHROPIC creds +
  network egress + model non-determinism onto *every routine host deploy*, which
  the Hetzner host cannot reliably satisfy (no node, no key) and which turns a
  deterministic deploy gate into a flaky, paid, creds-dependent one (violates the
  deterministic-LLM-SDK-invocation learning). The hybrid confines the one model
  turn to CI (capture) and replays creds-free at deploy. A secondary rejection:
  a **hand-authored** replay fixture — the fixture MUST be SDK-captured, never
  written by hand (the #4932 trap), which is why the dark-launch bootstrap ships
  an explicit `uncaptured` sentinel rather than a guessed argv.
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

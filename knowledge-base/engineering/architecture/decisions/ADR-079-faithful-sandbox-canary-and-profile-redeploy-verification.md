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
until it has soaked; only its `argv_drift` byte-diff is a candidate block signal (a
captured `sandbox_broken` is unreachable via argv replay, per the refinement above).

**Capture-env invariant (CTO ruling, binding — the stronger invariant behind the
canonical projection).** The canonical projection closed *cross-run* non-determinism
within one environment, but the real invariant is **capture-env == verify-env ==
replay-env == the deploy runtime base image (`node:22-slim`)**. The SDK's bwrap setup
is a pure function of (SDK version, sandbox config, **host filesystem**): host-
conditional tokens like `--tmpfs /etc/ssh/ssh_config.d` are emitted only when the host
has `/etc/ssh` (a *security hardening* mount that hides host SSH config from the
sandbox), and other host-conditional tokens (CA bundles, `/etc/machine-id`, `/run`,
locale files) are latent. Capturing on any other host (a dev laptop, or the
`ubuntu-latest` runner — both have `/etc/ssh`) produces an argv that is a **superset**
of what prod runs and that **infra-errors** the `node:22-slim` deploy replay
(`bwrap: Can't mkdir parents for /etc/ssh/ssh_config.d: Read-only file system`) — so
the #5889 soak would accrue `canary_infra_error`, never green. Therefore both
`--capture` and `--verify` are pinned to run **inside the deploy base image**, never on
`ubuntu-latest`. This was rejected-alternative **B** (a projection rule that drops
"non-universal `/etc/…`" tokens): B requires enumerating an open-ended host-conditional
set and its failure mode is exactly the over-drop the §2d guard exists to prevent —
silently dropping a *load-bearing hardening mount* that IS present in prod. A (capture
in-image) eliminates the entire host-conditional class by construction. Bonus: an
in-image capture also erases the dev-host noise (`/home/<user>/.npm/_logs`, host
`/etc/ssh`, `/tmp/claude-<session>`), so the committed fixture is *closer to verbatim*
than an off-image capture — honoring the plan's original minimal-transform spirit as
far as physics allows.

**Producing the fixture without hand-authoring (guardrail 1 / #4932) — DONE.** The
committed fixture is a real in-image capture, generated by the generated-artifact
bootstrap (`docker run <node:22-slim + web-platform deps> …/sandbox-canary.mjs
--capture` with `SANDBOX_CANARY_CAPTURE=1` + creds), verified byte-identical across
two independent in-image captures (84 tokens, no `/etc/ssh`, full `--unshare-*`
multiset, zero secrets/host data). Two headless-in-image fixes (the de-risk the
ruling called for) were required and are the reason an off-image capture "worked"
while the in-image one initially did not:
1. **permissionMode `default`, not `bypassPermissions`.** `bypassPermissions` maps
   to `--dangerously-skip-permissions`, which `claude.exe` **refuses under root**
   ("cannot be used with root/sudo privileges") — and the in-image/CI capture runs
   as root. The `canUseTool` force-allow + `autoAllowBashIfSandboxed` already
   auto-allow the single Bash op, so `default` is sufficient and root-compatible.
   (An off-image capture on a non-root dev user silently avoided this.)
2. **The bwrap PATH shim answers `bwrap --version`** like the real binary, so the
   SDK's availability probe (`failIfUnavailable`) passes and proceeds to the real
   SETUP spawn instead of skipping the sandbox.
CI auth uses `ANTHROPIC_API_KEY` (repo secret); the in-image `--verify` runs via
`scripts/sandbox-canary-verify-in-image.sh` inside `node:22-slim`. **Fidelity note:**
the helper uses `node:22-slim` + `npm ci` (the deploy `FROM` base), not the fully
built web-platform image; they share the base OS filesystem so the host-conditional
token set is identical — a follow-up could pin to the built image for exactness.

### Amendment (#5955, 2026-07-03) — the seccomp reload resolves the running semver from `/health`; the deploy contract stays semver-only

The "item 4" redeploy step (`apply-deploy-pipeline-fix.yml`) originally read the tag to
redeploy from `/hooks/deploy-status` `.tag`. That field is the ci-deploy **state file**'s
last-ATTEMPT tag (`cat-deploy-state.sh` reads `/var/lock/ci-deploy.state`), not the running
container's real image. The Terraform bootstrap default runs `...:latest` (`variables.tf`),
and `ci-deploy.sh:713` requires `^v[0-9]+\.[0-9]+\.[0-9]+$` — so the redeploy re-sent
`latest`, was rejected with `reason=tag_malformed`, and the rejection **re-stamped**
`.tag=latest`, a self-perpetuating wedge that reddened the pipeline (surfaced once PR #5950
cleared the #5877 reboot wedge that had masked it; #5955).

**Decision (CTO ruling 2026-07-03).** The redeploy resolves the running container's version
from the **public `/health` endpoint** (`.version` = the baked `BUILD_VERSION`, a bare
semver) and redeploys `v<version>`. The release pipeline pushes `:v<version>` and `:latest`
to the **same digest** (`reusable-release.yml`), so `v<version>` is a true same-image reload
that `ci-deploy.sh` accepts — no version change, no risk beyond the already-intended graceful
seccomp reload. The step's tag validation is **tightened to the exact `^v[0-9]+\.[0-9]+\.[0-9]+$`
shape** so a non-released image (`BUILD_VERSION` unset → `"dev"` → `"vdev"`) fails loud with a
remediation instead of perpetuating the loop.

**Rejected:** (a) `docker inspect .Config.Image` — returns `:latest` for the bootstrap
container, same unhelpful answer, and a digest-redeploy would force a `ci-deploy.sh` guard
change; (b) relaxing `ci-deploy.sh`'s semver guard to accept `latest`/digest — the guard
deliberately rejects floating tags and backs the wrong-image-tagged-with-right-version check
(`web-platform-release.yml:683`); a resolution bug in one caller must not widen the deploy
contract. **The deploy contract stays semver-only.** Single-file change:
`.github/workflows/apply-deploy-pipeline-fix.yml`.

**Reader inventory (#6147, 2026-07-07).** The `web_2_recreate` pin-gate in
`apply-web-platform-infra.yml` was a second, un-swept reader of `/hooks/deploy-status` `.tag` —
a non-web writer (an inngest watchdog restart stamping `{component:inngest,tag:latest}`) wedged
it and hard-aborted the recreate with `got 'latest'`. It now resolves web-1's running tag from
`app/health` `.version` via the pure `resolve-web1-known-good-tag.sh` (same strict-semver guard),
adopting this amendment's source. Host-targeting is safe because `cloudflare_record.app`
(`dns.tf:13`) is a single A record hard-pinned to web-1; if the multi-host rewire (#5274) lands,
that resolver must switch to a web-1-pinned health path.

**Third reader (#6353, 2026-07-11).** The shared off-host web-2 acceptance verify
`apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` (used by BOTH the `web_2_recreate`
and `warm_standby` dispatch jobs) was the third un-swept reader of `/hooks/deploy-status` `.tag`.
It seeded the tag it re-POSTs (`DEPLOY_TAG`) from that slot, so an inngest `restart … latest`
writer's `latest` stamp made the fan-out POST `deploy web-platform <image> latest` → `ci-deploy.sh`
rejects it as `tag_malformed` (`exit_code:1`), aborting **every** web-host recreate and blocking the
#6178 Inngest cutover. **BOTH** its baseline seed AND its `_trigger_fanout` retrigger now resolve
web-1's re-swap tag from `app/health` `.version` via the same pure `resolve-web1-known-good-tag.sh`
(the two former `.tag` tag-sources are both removed — the retrigger's prior `.tag` re-read used a
*looser* regex than the deploy contract, so a `v1.2.3-rc1`-shape pollutant was a latent third seam).
The `latest`-tolerating baseline band-aid is deleted. **Invariant (now honest against the shipped
code): `app/health` `.version` is the canonical running-tag source; the shared deploy-status `.tag`
is acceptance-proof-only, never a tag source; the deploy contract stays semver-only.** The verify
poll's acceptance-match `.tag` reads stay (they compare against the `/health`-resolved semver);
after a genuine web-2 deploy the slot reflects that semver. Host-targeting invariant carried from
the pin step (`app/health` must resolve to web-1; web-2 rides at weight 0) — the #6178 cutover this
unblocks is the exact REVISIT TRIGGER for a web-1-pinned health path.

### Amendment (#5960, 2026-07-03) — loaded proof read live from the running container; poll validates the swap terminal and treats lock_contention as non-terminal

Once #5955 cleared the `tag_malformed` wedge, the item-4 assert failed on
`LOADED != COMMITTED` with an **empty** loaded hash. Two latent defects: (a) the redeploy
poll accepted any `exit_code>=0` frame with `start_ts>PRIOR_START` — no `component`/`tag`/
`reason` guard — so it latched a foreign-component, stale, or **`lock_contention`** terminal
(a flock loser stamps *our* `component`+`tag` with `exit_code=1`, since `START_TS` and
`COMPONENT`/`TAG` are set pre-flock at `ci-deploy.sh:207`/`:674`, and that frame persists for
the winner's whole multi-minute swap); (b) the assert read only the **ephemeral recorded**
`.seccomp_profile_sha256` (tmpfs, reboot-cleared per #5877), which cannot discriminate
not-delivered / host-stale / not-reloaded.

**Decision (CTO + 5-agent panel, 2026-07-03).** The "loaded" proof is read **live** from the
running container: `cat-deploy-state.sh` adds `seccomp_profile_loaded_matches_host` (docker
inspect `HostConfig.SecurityOpt` inlined JSON `jq -cS`-equals the on-host file, computed with
ONE host jq — reusing the `audit-bwrap-uid.sh:105-146` technique), plus
`seccomp_profile_host_sha256` (raw `sha256sum`) and `seccomp_profile_host_present`. The
assert becomes the STATE invariant "*the running container is enforcing the committed
profile*" = `host_sha256==COMMITTED_SHA` (raw==raw, delivery leg) **AND**
`loaded_matches_host` (host-jq, reload leg) — **no cross-jq comparison** on the load-bearing
path. The poll accepts a terminal only when `component==web-platform && tag==TARGET_TAG &&
start_ts>PRIOR_START`, keeps polling on `lock_contention`/`adr027_prod_already_running`/
`running`, and on exhaustion does one STATE check (a concurrent release loading the *same*
committed profile satisfies the invariant). Adds a marginal second `docker inspect` per
`/hooks/deploy-status` GET (same pattern as `container_restart_json`). The recorded
`seccomp_profile_sha256` field/writer stays as a permanent inert diagnostic (no gate).
**Rejected:** a deploy nonce for redeploy provenance — the assert verifies host STATE, not
"our POST caused it"; the timeout STATE check achieves correctness without threading a nonce.
No new `TF_VAR_*`; `aggregate pattern` threshold unchanged. Files:
`apps/web-platform/infra/cat-deploy-state.sh` + `.github/workflows/apply-deploy-pipeline-fix.yml`.

### Amendment (#6512, 2026-07-17) — reload survives a both-registries-fail via the local image; an unenforced profile becomes a standing, plain-language alarm

On 2026-07-16 the item-4 redeploy (this ADR's PR3 mechanism) terminated
`image_pull_failed` on `v0.214.7`, leaving `seccomp_profile_host_present=false` — the control
unenforced, and the ONLY signal one red job among a page of green (the #6454 invisible-gate
shape). Phase-0 diagnosis + two composable fixes:

**Phase-0 findings (in-session, no SSH).**
- **Q1 ("state-file `.tag='latest'` aimed the remediation at a stale image") is SUPERSEDED, not a
  bug.** The #5955 amendment already resolves the redeploy target from `/health` `.version`
  (`apply-deploy-pipeline-fix.yml:631-643`); `CURRENT_TAG` (`.tag`, read at `:589`) feeds only the
  diagnostic log strings (`:592/:640/:643`). `v0.214.7` was the *correct* running version at 21:03
  (v0.215.x released later). **Do not re-open Q1** — "fix the tag" fixes a non-bug.
- **The image was pullable.** A live authenticated GHCR manifest fetch of `v0.214.7` returns HTTP
  200 — GHCR retains it. The failure was a transient/auth leg failure (the #6090 stale-baked-cred
  class or GHCR degradation), consistent with zot GC'ing the several-releases-old tag from its
  5-`v*` keep-set (`variables.tf:176`, #6246) and the GHCR fallback leg then also failing.
- **Fix-2b gate → DEFER.** No non-merge unenforcement path is confirmable in-session that Fix 2a
  would not already catch: `terraform_data.docker_seccomp_config` (`server.tf`) is keyed on BOTH
  the profile hash AND `server_id`, so a host replacement re-runs the provisioner (re-delivers the
  file) and the container re-enforces at `docker run`; a reboot preserves the durable file +
  `--security-opt`. The standing probe (Fix 2b) is filed as a tracked follow-up (#6628), not built
  speculatively (code-simplicity); the deep delivery-leg RCA (why `host_present=false`) is filed
  separately as #6629 (a discovered defect, live-state-dependent).

**Fix 1 — a `local-cache` last-resort tier in `ci-deploy.sh`'s `pull_image_with_fallback`.** The
item-4 redeploy targets `v<running_version>` — the image the container is ALREADY running
(cosign-verified at its original deploy, immutable @sha256, always in the host's local docker
store), so a registry round-trip for the reload is an unnecessary single point of failure. On
BOTH-registries-fail for a `web` immutable-semver reload, the tier reuses the RUNNING container's
image ID (keyed off the literal container name `soleur-web-platform`) as `VERIFIED_REF` and
**skips re-verify with an EXPLICIT `cosign_reused_local_reload` decision** — this is a deliberate
amendment to the **ADR-087** cosign contract (re-verifying identical @sha256 bits is a no-op;
skipping it explicitly is the honest posture vs. silently falling through the `warn`-mode
fail-open), and a THIRD tier on **ADR-096**'s zot→GHCR pull chain (a future §5.3 GHCR-retirement
editor must see it). Blast radius for any genuine version change is zero (a re-pushed tag / stale
leftover / new-version deploy is never the running image ID → hard `image_pull_failed` unchanged).
Usage is a MONITORED `registry=local-cache level=warning` emit → the DEDICATED
`local_cache_reload_rate` issue-alert (NOT folded into `zot_mirror_fallback_rate`, whose
`ghcr-fallback` signal gates the irreversible ADR-096 §5.5 GHCR retirement — `local-cache` means
*neither* registry served, a different meaning), plus the `scheduled-zot-restart-loop.yml`
pull-health runbook grep extended to `local-cache` (a host silently on local-cache must not read
CLEAN and fire a blind registry-replace).

**Fix 2a — an unenforced profile becomes a plain-language, operator-readable alarm (SHIP).** On any
item-4 terminal failure that leaves the profile unenforced (redeploy `image_pull_failed` /
`diagnose_and_fail`), `scripts/seccomp-unenforced-alert.sh` (sourced by the item-4 step, fail-open)
files/updates a deduped plain-language `ci/seccomp-unenforced` GitHub issue (the surface
`operator-digest` harvests — never PR bodies or red CI jobs) AND emits a
`op:seccomp-remediation-failed` Sentry event → the dedicated `seccomp_remediation_failed`
issue-alert. It is EVENT-driven, deliberately NOT a cron-monitor check-in (an event-driven check-in
to a cadence slug resets its missed-beat clock and masks a genuinely-missed beat).

**Fix 2b — DEFERRED (standing 6h enforcement watchdog, tracked in #6628).** Filed as a tracked
follow-up to build if a non-merge unenforcement path is ever observed (a `ci/seccomp-unenforced`
issue with `host_present=false` outside a known item-4 run). **Loop-vs-watchdog reconciliation:** this ADR
rejected an *item-4* self-healing verify-LOOP; a SEPARATE standing watchdog firing ONE bounded,
age-gated, idempotent re-dispatch (the accepted `inngest-watchdog` pattern) is the distinct,
sanctioned mechanism — NOT the rejected loop.

**Tracked residual (arch P2):** a host that reboots/replaces onto a stale-but-*enforcing* profile
(`host_present=true, loaded_matches=true, host_sha!=committed`) is not paged until the next item-4
run — filed to close the window (page on a `host_sha!=committed` mismatch persisting across ≥2
probes). **Status stays `adopting`** (Deferral A / #5889 still open); `aggregate pattern` threshold
unchanged; no new `TF_VAR_*`. Files: `apps/web-platform/infra/ci-deploy.sh` (+`.test.sh`),
`scripts/seccomp-unenforced-alert.sh` (+`.test.sh`), `apps/web-platform/infra/sentry/issue-alerts.tf`
(two dedicated alerts), `.github/workflows/{apply-deploy-pipeline-fix,scheduled-zot-restart-loop}.yml`.

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

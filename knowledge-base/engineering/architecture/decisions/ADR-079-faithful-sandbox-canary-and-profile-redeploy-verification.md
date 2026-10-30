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
  `package-lock.json` PRESENCE for both SDK packages (**amended 2026-08-16, ADR-191:**
  the `bun.lock`↔`package-lock.json` parity arm is retired — `bun.lock` no longer exists.
  The PRESENCE arm is retained and is load-bearing: bump detection short-circuits to green
  on an empty resolved version, so it is the only remaining catch for an SDK package that
  vanishes from the lockfile, which is the #5849 class this gate exists to close)
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
   as root. The canary's `allowedTools: ["Bash"]` rule and its `canUseTool` force-allow allow the single Bash op (the hosted sandbox config no
   longer auto-allows it, #10054), so `default` is sufficient and root-compatible.
   (An off-image capture on a non-root dev user silently avoided this.)
2. **The bwrap PATH shim answers `bwrap --version`** like the real binary, so the
   SDK's availability probe (`failIfUnavailable`) passes and proceeds to the real
   SETUP spawn instead of skipping the sandbox.
CI auth uses `ANTHROPIC_API_KEY` (repo secret); the in-image `--verify` runs via
`scripts/sandbox-canary-verify-in-image.sh` inside `node:22-slim`. **Fidelity note:**
the helper uses `node:22-slim` + `npm ci` (the deploy `FROM` base), not the fully
built web-platform image; they share the base OS filesystem so the host-conditional
token set is identical — a follow-up could pin to the built image for exactness.
Addendum (#7007, 2026-07-28): whoever next regenerates the fixture with `--capture`
should know that `/build` is now a *filtered* copy of the checkout —
`scripts/lib/in-image-copy-src.sh` excludes `node_modules` (deleted and rebuilt by
the very next `npm ci`), `.terraform`, `.next` and `out` (read by nothing here).
This is outside the argv projection surface **by construction, not by token census**:
`computeCanaryPaths()` roots the capture workspace at
`/tmp/soleur-sandbox-canary/<fixed uuid>` and the SDK `query()` runs with
`cwd: resolvedOwn`, so `/build` is neither the workspace, nor the cwd, nor a sibling,
and cannot contribute a token at *any* SDK version. The committed fixture corroborates
(it carries only paths rooted at `/`, `/proc`, `/dev`, `/dev/null`, `${CANARY_WS}` and
`${CANARY_EMPTY}`), but the structural reason is the durable one — a token census
expires silently the day an SDK version emits a cwd-conditional token.
Note the change moves `/build` *toward* the deploy image, not away from it:
`apps/web-platform/.dockerignore` already excludes `node_modules`, `.next`, `out` and
`infra/`, so the deploy build context never carried them. The previous full-fat
`cp -r` made `/build` less like the deploy context than the filtered copy does.

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
**skips re-verify with an EXPLICIT reused-image decision** (emitted via `cosign_verify_event` with
`verify_result=reused_local_reload` — reusing the verify emitter for the audit breadcrumb is
intentional; its `IMAGE_VERIFY_FAIL` logger prefix is a known cosmetic artifact of that reuse, and
no issue-alert is keyed on `op:image-verify`) — this is a deliberate
amendment to the **ADR-087** cosign contract (re-verifying identical @sha256 bits is a no-op;
skipping it explicitly is the honest posture vs. silently falling through the `warn`-mode
fail-open), and a THIRD tier on **ADR-096**'s zot→GHCR pull chain (a future §5.3 GHCR-retirement
editor must see it). Blast radius for any genuine version change is zero: the tier fires ONLY for a
**same-version reload** — the running container's image must itself carry a `<ref>:$TAG` RepoTag
(it was pulled under that tag at its original deploy). A NEW-version deploy whose tag both registries
failed to serve is NOT on the older running image, so it falls through to the existing hard
`image_pull_failed` — reusing the running image there would silently serve stale bits and report the
new release as "deployed" (ci-deploy runs no post-deploy version assertion; this same-version guard
is the encoded form of that safety invariant, not prose). Any tag ambiguity fails SAFE (hard fail →
Fix 2a alarms), never a stale-bits deploy.
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
  deploy-authoritative; key on it + parity-assert `bun.lock`. **(Superseded
  2026-08-16 by ADR-191: `bun.lock` is deleted, so there is nothing left to
  parity-assert against. The rejection's premise — that `package-lock.json` is the
  deploy-authoritative lockfile — is what ADR-191 generalized to the whole repo.)

## Amendment — 2026-09-24 (#8623): server-private deny roots are placeholdered

`buildAgentSandboxConfig` now adds a second deny entry outside the workspace: the C4 re-render's
staging root (`server/c4-staging-root.ts`, default `~/.cache/soleur-c4-render`), so one tenant's
agent cannot read another tenant's staged diagram sources during a render (ADR-050 amendment of the
same date). That path lives under the server's HOME, which differs between the capture container
(`/root`) and the prod replay (`/home/soleur`, read-only root), so a literal in the fixture would
fail every replay as `canary_infra_error`. The projection contract therefore gains a third
placeholder, `${CANARY_C4_STAGING}`, alongside `${CANARY_WS}` and `${CANARY_EMPTY}`.

**Rule for any `denyRead` path the builder adds outside the workspace.** It must be (a)
env-overridable; (b) pointed at a `mkdtemp` directory during `--capture` (never under the hermetic
workspaces root, where it would become a sibling and break the zero-sibling invariant); (c)
replaced by a named placeholder that is listed in `prepDirs` and substituted at replay; and (d)
produced by a module in the capture-input trigger set (`ci.yml` `sandbox-canary-capture-gate` and
`sdk-bump-sandbox-gate.sh` section 3 now include `server/c4-staging-root.ts`).

**Two guards added with it.** `normalizeCapturedArgv` refuses to project any kept token under
`/root` or `/home` (a `host_path` projection error) — the class, not this one path. `runReplay`
refuses with `canary_infra_error` / `unsubstituted_placeholder` when any `${CANARY_*}` token
survives substitution, so a future fourth placeholder fails visibly instead of reaching bwrap as a
literal path.

**Fixture refresh.** Captured in-image (`SANDBOX_CANARY_MODE=capture` on
`sandbox-canary-verify-in-image.sh`, which now copies the fixture out through a writable mount);
a second in-image run (`--verify`) returned `verify_ok`. The only change: one
`--tmpfs ${CANARY_C4_STAGING}` after `--tmpfs /proc`, plus the new `prepDirs` entry. The real-bwrap
replay proof (`SDK_SANDBOX_REGRESSION_DOCKER=1 sandbox-canary-regression.test.sh`) passed.
Status stays `adopting`.

## Amendment — 2026-10-06 (#9614/#9618): SDK-internal HOME-derived dirs are placeholdered via a capture-computed root

SDK 0.3.284 emits `--tmpfs <homedir>/.claude/bridge-spawn` — an SDK-internal dir
(`join(homedir(), ".claude", "bridge-spawn")` in the bundled CLI; no env
override exists, so the 2026-09-24 rule's sub-clauses (a) env-overridable and
(b) mkdtemp-redirected cannot apply). The projection gains a fourth named
placeholder, `${CANARY_BRIDGE_SPAWN}`, mapped from a `bridgeSpawnRoot` that
`doCapture` derives with the same `homedir()` expression the SDK evaluates and
passes into `normalizeCapturedArgv`. The host_path fail-loud guard is
unchanged: any OTHER `/root`|`/home` token still throws, including the
bridge-spawn dir itself when `bridgeSpawnRoot` is not supplied. Clauses (c)
and (d) of the 2026-09-24 rule carry over unchanged: the placeholder is listed
in `prepDirs` and substituted at replay, and the derivation already lives in
`sandbox-canary.mjs`, a capture-input trigger path.

The same re-capture surfaced a second replay-precondition class the "directory
roots only" prepDirs rule missed: placeholder-subpath bind **sources**
(`${CANARY_WS}/.claude`, `…/.cc-writes` — bwrap never creates sources) and
literal mount targets a fresh replay host may lack (`--tmpfs
/tmp/claude-0/bash-edit-diff` — uid-derived, `claude-${process.getuid()}`,
byte-stable only because capture and verify both run as uid 0 in the pinned
image). `prepDirs` now carries both; a structural test pins "every mount
target and placeholder-subpath bind source resolves under a prepDirs entry".
Status stays `adopting` (Deferral A).

## Addendum — 2026-10-16 (#10445): the faithful replay must exercise the command-side wrapper

The faithful canary replays the captured bwrap SETUP argv and ends in `-- true`
(`parseShimSetupArgv` documents the command tail as model-chosen and never
replayed). It therefore never runs the process the Agent SDK wraps around every
sandboxed Bash command: `ARGV0=apply-seccomp /proc/self/fd/<N> <shell> -c <cmd>`.
From the first production deploy of `web-v0.324.3` (2026-10-06) the shim's
seccomp filter denied `unshare(CLONE_NEWUSER)`, which that embedded helper needs,
so every hosted Bash call failed while `sandbox_canary` stayed green
(`consecutive_pass=108` at the 2026-10-16 readback). The canary's own
`nested_userns_deny` probe asserted the denial that broke the helper. See
`knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`.

**Rule to be added (planned, with #10453).** A pass verdict from the faithful canary would have to be backed by a probe
that executes a real Bash command through the SDK's real command-side path (the
wrapper the SDK emits, not a captured tail) inside the production container, under
the production run tuple and the shipped shim. A replay that ends in a command
which never reaches the wrapper certifies the setup argv only and must not be
described, in a verdict or in a runbook, as proof that Bash works (that part holds
today). The probe would report a coverage field in the verdict so a replay-only
pass is distinguishable from a wrapper-exercising pass.

**Promotion (planned, unchanged and still the ADR's).** The new probe (`sdk_bash_smoke`)
would ship non-blocking first (`wg-dark-launch-deploy-gates`) and be promoted to the
blocking lane under this ADR's own soak criterion: 5 green verdicts over at least
3 days, with the coverage field present. `smoke_infra_error` would hold the soak and
never roll back. This addendum introduces no new soak number.

**Scope.** This amends the Decision's canary contract (section 2) only. It does not
change the profile-to-redeploy coupling (section 3), the interim mechanism, or the
Adopting to Accepted criteria. Status stays `adopting` (Deferral A).

**Status.** The `sdk_bash_smoke` probe described above does not exist yet; it is deferred to #10453, the successor to #5941 (the earlier tracker of the nested-unshare-in-the-production-canary gap, still open) (time-boxed per the CTO's 2026-10-16 ruling). Until it ships, the wrapped-command guard is pre-merge only: `test/sandbox-wrapped-command-runtime.test.ts` (CI runner) and the wrapped-command control/treatment arms of `infra/sandbox-masked-proc-docker.test.sh` (production run tuple, driven by `infra/lib/sdk-bash-probe.mjs`). The faithful canary's replay is still blind to the command-side wrapper, which is exactly why the probe is required before this ADR's blocking promotion.

## Addendum — 2026-10-19 (#10454): the outer-wrap canary is retired

**Decision.** Ruled by CTO agent, 2026-10-19: DEMOTE. The deploy-time outer-wrap canary (`run_outer_wrap_canary`,
the `outer_wrap_canary` key on `/hooks/deploy-status`, the `/mnt/data/ci-deploy-outer-wrap-canary.json` ledger,
Sentry `op=sandbox-canary-outer-wrap`, and the `tenant-outer-wrap-soak-5863` follow-through with its tests and
registrations) is removed. Tracker #9797 is to be closed as won't-fix and Sentry issue 152662657 resolved with a link
to this addendum, both at ship (the PR's ship step performs them; this text is not evidence that they are done).

**Why.** The arm's pass condition requires `elevation=privileged`. ADR-075's 2026-10-09 addendum (#9874,
operator-ratified) dropped that elevation for good, and `AGENT_OUTER_WRAP` is flag-off in production, so
`wrong_elevation_userns` was the designed state of production on every deploy, not a regression, and a pass was
unreachable by design. Relaxing the check to accept `elevation=userns` was rejected: it would turn the canary green on
the mechanism its own code comment calls wrong. A permanently red report-only signal also trains the team to ignore
report-only signals, and the runbook's first move for it ("check `getcap` / `--cap-add SYS_ADMIN`") contradicted
ADR-075.

**Kept, each with a live consumer.**

| Kept piece | Live consumer |
|---|---|
| `sandbox-canary.mjs --replay-outer`, `classifyOuterWrapReplayVerdict` | test-only (re-introduction path, #9773): `test/sandbox-canary.test.ts`; no production caller remains |
| `infra/agent-outer-wrap-argv.json` fixture and its Dockerfile/`.dockerignore` bakes | Read by `test/agent-outer-wrap.test.ts` and `test/c4-render-argv-fixture.test.ts`, by `scripts/sandbox-canary.mjs` (the default fixture path of `--replay-outer` / `--smoke-outer`) and by the `sandbox-canary-soak.test.sh` fixture checks. `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` only NAMES the file (in its trigger regex and its error text); it does not read it |
| `scripts/tenant-isolation-inner-probe.sh` payload | `agent-outer-wrap.ts` boot self-probe, `test/agent-outer-wrap.test.ts` |
| `agent-outer-wrap.ts` | the `AGENT_OUTER_WRAP` flag path (off in production) |
| `sandbox-canary.mjs --smoke-outer` | `sandbox-canary-verify-in-image.sh`, the CI capture-gate job |

The masked-proc docker suite does not run `--replay-outer` (its header records why), so it is not a consumer.

**Defense removal.** The arm bounded one property: the privileged-elevation outer mount table. That elevation was
dropped on purpose and the wrap is flag-off. Cross-workspace read/write isolation is still measured per deploy by
`run_workspace_isolation_probe`. The outer-wrap realized mount table is no longer replayed per deploy; only the static
pins (`test/agent-outer-wrap.test.ts`, `test/c4-render-argv-fixture.test.ts`) cover it until the arm returns.

**Inert ledger.** `/mnt/data/ci-deploy-outer-wrap-canary.json` remains on every host, inert (nothing reads or writes it any more). A
re-introduction of the arm must use a new ledger name or delete that file first, otherwise it would inherit the old soak counters.

**Re-evaluate or delete.** On 2026-12-19, or when #9773 Stage 1 (the executor topology) ships, whichever comes first:
bring the arm back with a pass criterion defined by that topology (own ledger, deploy-state key, soak script and a new
addendum), or delete the kept pieces. Reverses sooner if `AGENT_OUTER_WRAP` is ever enabled in production.

**Scope.** This amends the Decision's canary contract (section 2) only: the faithful inner canary
(`run_faithful_sandbox_canary`), its `sandbox-canary` ledger and its journald emitter format are unchanged. Status
stays `adopting` (Deferral A). The operator-facing note lives in
`knowledge-base/engineering/operations/runbooks/canary-probe-set.md`.

## Addendum — 2026-10-19 (#10453): the deploy-time SDK Bash smoke is implemented (non-blocking)

Appended, not edited. This updates the **Status** paragraph of the 2026-10-16 addendum above, which said the `sdk_bash_smoke`
probe "does not exist yet". It now does, as the dark-launch that addendum specified.

**What shipped.** `run_sdk_bash_smoke` in `ci-deploy.sh` runs after `run_faithful_sandbox_canary` and after the GitHub App key gate (its own
`if [[ "$CANARY_HEALTHY" == "true" ]]` block, CTO ruling 2026-10-19: the canary runs with `--memory 1536m` and already hosts the Next server, so a probe OOM or a
probe still running after a host-cap timeout must not be able to fail the last promotion gate and roll back a healthy deploy; the pre-existing
workspace-isolation probe still runs before that gate and is out of scope here) and executes the baked probe
(`/app/infra/lib/sdk-bash-probe.mjs`, `SMOKE=1`) inside the CANARY container (never the live prod container): one real Bash call
through the real Agent SDK, the shipped shim and the production sandbox config, under `/usr/bin/env -i` with an explicit
allowlist, a decoy `ANTHROPIC_API_KEY`, the container's real `HOME` and a 150 s host `timeout` (`SDK_BASH_SMOKE_TIMEOUT`; the pre-exec has its own
20 s cap, `SDK_BASH_SMOKE_PREEXEC_TIMEOUT`, so the smoke's total is bounded by the two caps summed, 170 s, plus the bounded DIAG bundle). The call site is
`run_sdk_bash_smoke || true`: no verdict rolls back, aborts or changes the deploy's exit code (`wg-dark-launch-deploy-gates`).

**Verdicts (computed by the probe in JavaScript, unit-tested under node).** The smoke makes two canary `docker exec`s, each under its own host cap:
one pre-exec (`test -f <probe> || exit 66; printf %s "$HOME"`; ONLY rc 66 = `probe_absent`, a 124 there = `smoke_infra_error`
`host_timeout_before_dispatch: preflight`, any other non-zero rc = `smoke_infra_error` `preflight_rc_<N>`) and the probe run. The Bash command is `echo SDK_SMOKE_$(printf %s '<nonce>' | tr 0-9a-f a-f0-9)`,
so `pass` needs the TRANSFORMED per-run nonce back in the real tool_result (a result that only quotes the command text cannot pass), the
result not error-flagged, and the `coverage` field equal to
`sdk_wrapper_shim_prodtuple` (the shim is the `bwrap` on `PATH` and the artifact at the pinned path is sock_filter-sized).
The verdict is `sdk_bash_smoke_failed` when Bash was dispatched and no verified nonce came back (an error result, a clean result without the
nonce, a thrown SDK error, a hang, or ANY non-zero `docker exec` rc, the 150 s host cap's 124 included, whose output already carries the
`SDK_BASH_DISPATCHED` marker line: `host_timeout_<N>s` for 124, `probe_rc_<N>_after_dispatch` otherwise, except rc 137 and 143, SIGKILL / SIGTERM (the OOM
killer, a container stop), which are `smoke_infra_error` `probe_killed_rc_<N>`), independent of any error signature, so a new wording of a failure cannot go silent; a sandbox
that cannot start (`sandbox required but unavailable`) is also a failure, not an infra hiccup. `smoke_infra_error` only when Bash
was never dispatched (probe absent in an old image, docker rc 125/126/127, a crashed probe, stub or ledger failure, no usable
`/dev/urandom` nonce, or a host-cap timeout that fired BEFORE the probe printed `SDK_BASH_DISPATCHED`: `host_timeout_before_dispatch`, a daemon
stall or a wedged node start, never a Bash verdict), and for a
pass-shaped result whose coverage is `replay_only`: a HOLD that does not move `consecutive_pass`. This is the "coverage field"
requirement of the 2026-10-16 addendum, implemented: a replay-only pass is distinguishable from a wrapper-exercising pass and
never counts toward promotion.

**Ledger and surfaces.** Its own durable ledger (`/mnt/data/ci-deploy-sdk-bash-smoke.json`, ledger stamp `sdk-bash-smoke`), written
in ONE atomic write through `write_sandbox_canary_state` (the verdict, `coverage` and `consecutive_infra_error` land together; a
failed write, detected by reading the ledger back, is reported `smoke_infra_error reason=ledger_write_failed`, never a coverage-less
pass, ALSO emits the stale warning at once with its own wording, "SDK smoke ledger write failed (consecutive_infra_error not advanced)" (prior counter + 1: a
ledger that cannot be written cannot accumulate the counter that would otherwise raise it), and, for a `sdk_bash_smoke_failed` verdict whose
write failed, tries to delete the stale ledger so an old `consecutive_pass` cannot keep reading as a soak the failure should have reset. The
deletion needs the directory permission whose absence usually broke the write and only removes a record that carries this ledger's stamp and is older
than the run; when the directory is not writable the old record survives and the next pass can read its stale counters, while the page and the
stale warning still fire), surfaced as
`sdk_bash_smoke` on `/hooks/deploy-status`. The smoke reads and writes only this ledger, never the shared deploy frame. A failure
pages through the unchanged `sandbox_canary_sentry_event` journald format
(`SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed: ... (op=sandbox-canary; ...)`) into the new Better Stack
alert `faithful_canary_sandbox_broken` (ADR-218 amendment of the same date) plus a Sentry event. Three consecutive
`smoke_infra_error` verdicts emit `SDK_BASH_SMOKE_STALE`: recorded in journald and Sentry (a warning), flagged on the #10548 tracker
by the follow-through (`sdk-bash-smoke-verdict-10548.sh` exits 1 at `consecutive_infra_error >= 3`), not emailed (CTO ruling,
2026-10-19; no alert predicate covers it).

**Probe configuration.** The production image has no TypeScript sources, so the probe carries a literal sandbox config and a
literal seccomp-selector path, pinned to `buildAgentSandboxConfig` / the shim default by `test/sdk-bash-probe-parity.test.ts`
(deep equality for the no-egress shape; the failure prints the diff and the exact fix). Ruled by CTO agent, 2026-10-19: literal
config with a parity test rather than a second esbuild bundle of the builder.

**Promotion (unchanged and still this ADR's).** 5 green verdicts over at least 3 days with the coverage field present, tracked in
#10548 and enrolled in the sweeper through `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh`, which NEVER exits 0 (the sweeper
closes a tracker on exit 0, and #10548 also tracks the promotion and the operator-authorized flag decision, which no script can observe).
It exits 5 (ACTION REQUIRED, notify-only: `scripts/sweep-followthroughs.sh` comments and leaves the issue open) on a complete soak
(`consecutive_pass >= 5`, span >= 3 days, latest verdict `pass`, coverage `sdk_wrapper_shim_prodtuple`), so the tracker stays open until the
promotion and the flag decision are done; 1 (FAIL) on a recorded `sdk_bash_smoke_failed` OR `consecutive_infra_error >= 3` (the stale
escalation); 2 (TRANSIENT) otherwise. The directive's `earliest=2026-10-26T00:00:00Z` means the sweeper does not run it for the first
~7 days, during which a blind probe is visible only in journald and Sentry.
This addendum introduces no new soak number. The promotion itself is a code change (a red-verdict-to-rollback path and dropping the
call-site `|| true`), not a flag flip.

**Scope.** This amends the Decision's canary contract (section 2) only; the faithful inner canary, its ledger and its journald
emitter format are unchanged (the new alert's drift guard reads them). Status stays `adopting` (Deferral A) until #10548 closes.
The operator-facing decode lives in `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`.

**Coverage of the smoke (what it does and does not run).** The deploy smoke runs the VARIANT (unixdeny) artifact under the NO-EGRESS shape only. It does not run the base artifact that production uses while the flag is OFF, and it does not run the egress shape. Those are covered, respectively, by the blocking legacy sandbox probe plus the canary `base_af_unix_control` probe, and by the pre-merge egress arm of `test/sandbox-wrapped-command-runtime.test.ts`.

Coverage means the shim on PATH, the pinned `buildAgentSandboxConfig` literal and the variant artifact under the no-egress shape. It does not cover the SDK child env, query options, the outer-wrap spawn, or the flag-OFF base. The smoke workspace is also a `mkdtemp` under `/tmp` (`infra/lib/sdk-bash-probe.mjs`), not a path under the denied `/workspaces` root that `buildAgentSandboxConfig` masks, so the production mount shape (a tmpfs mask of the denied workspaces root, then a re-bind of the session's own workspace) is not exercised by the smoke; the real-bwrap tests exercise it (`test/sandbox-isolation.test.ts` direct tier and `test/sandbox-wrapped-command-runtime.test.ts`, which points `WORKSPACES_ROOT` at a temp root and places the own workspace under it).

**Scope of the runtime signal (CTO ruling E, 2026-10-19).** The agent_sandbox_bash_denial alert and the notice rewrite cover cc-soleur-go sessions only. The legacy runner has no tool_result observer, so a helper EPERM there is neither mirrored nor paged. A variant-induced AF_UNIX EPERM has no signal on either runner. The #10455 open item "Legacy agent-runner loop has no tool_result observer" stays open and gains "variant-EPERM signal".

**Flag rollout (CTO ruling G, 2026-10-19).** The `agent-sandbox-unix-deny` flag stays global; enabling it follows the staged, operator-attended procedure in `canary-probe-set.md` ("Enable request must contain"). A per-organisation cohort was deferred, not built.

## Addendum — 2026-10-22 (#10455 b): the runtime Bash synthetic

**Status:** `adopting` (this ADR's Deferral A is unchanged). Amends the Decision's detection contract only: the deploy-time smoke
(addendum 2026-10-19, #10453) sees a sandbox that is broken at DEPLOY; the 2026-10-06..16 outage (#10445) lasted ten days because nothing
saw one that broke BETWEEN deploys.

**What shipped.** A systemd timer on every web host (`web-bash-synthetic.{sh,service,timer}`, every 15 minutes) runs one real wrapped Bash
call in the RUNNING `soleur-web-platform` container, with the same probe, nonce proof and decoy-key `env -i` envelope as the deploy smoke,
and pings a per-host Better Stack heartbeat (`betteruptime_heartbeat.web_bash_synthetic`, period 900 s, grace 1800 s) ONLY on a verified pass.
A verified fail pings `<url>/fail` (immediate incident). Any run that cannot make a claim either way is `no_ping reason=<…>` and sends
nothing: deploy lock held, container down or restarted during the run, container memory at or above 70 % or the HOST short of memory (see "Safety
toward the shared container"), the flag read not answered (`selector_unresolved`), probe or resolver absent from the running image, an infra error. The journal line `SOLEUR_WEB_BASH_SYNTHETIC verdict=… reason=… selector=… coverage=… masks_missing=… consecutive_no_ping=…`
ships through Vector Source 4 (`SyslogIdentifier=web-bash-synthetic`). The grace is deliberately coarse (a skipped run plus jitter must not
page): the dead-man beat reports a dead DETECTOR, the `/fail` ping reports a broken SANDBOX.

**Rulings (CTO agent, plan review 2026-10-20).**

- *Selector.* The synthetic asks the dispatcher's own resolver which seccomp artifact a no-egress session would get right now
  (`server/resolve-sandbox-selector-cli.ts`, a 26 kB esbuild bundle of `resolveSandboxUnixDeny` with `--packages=external`, built in the Dockerfile
  builder stage), in the container's FULL env so the live flag read works, then passes the NAME (`base` | `unixdeny`) to the `env -i` probe exec.
  Never the env mirror: after the #10548 flip a mirror-driven probe would test an artifact production no longer selects. The one-shot resolver is a
  COLD process (no warm client, no 30 s snapshot cache), so its flag read gets a long budget, and a read that did not answer is OBSERVABLE rather
  than silently `base`: the resolver (3 s budget) prints `SOLEUR_SELECTOR=unresolved` and the host journals `no_ping reason=selector_unresolved` (the
  env-mirror fallback inside `lib/feature-flags/server.ts` is never turned into a pass for the wrong artifact). The host also compares the probe's
  echoed `.selector` with the name it asked for (`no_ping reason=selector_mismatch` on a difference). Coverage
  (`sdk_wrapper_shim_prodtuple`) now names the artifact that was asked for, not a pinned one. The deploy smoke is unchanged and still runs
  `unixdeny`.
- *Verdict mapping.* The rc 124 / `SDK_BASH_DISPATCHED` / result-line mapping is extracted from `run_sdk_bash_smoke` into one sourced function
  (`infra/sdk-bash-verdict.sh`, next to `ci-deploy.sh` in both layouts) used by both callers; a parity row fails if either stops calling it.
  Behaviour of the deploy smoke is unchanged (its behavioural tests pass unmodified; the one source-text anchor in `ci-deploy.test.sh` and the one in `sdk-bash-probe-parity.test.ts` follow the moved text).
- *Split and sprawl.* The `masked-dir-precreate` routed alert and the persisted-CLI-output measurement moved to a separate PR (no shared files);
  the table-driven host-timer registry (the parity sprawl this PR again pays) is one debt issue, not a refactor here.

**Arming budget.** Each `arm_one` deadline of `period + grace − 40` would be 2660 s per host. The two literal calls use 300 s (the first run starts
within about 90 s of an install, and 300 s is far inside the 2700 s before a first absence alert), with the same soft landing as `inngest_consumer`:
the first merge can precede the image that carries the resolver, and the unit then correctly sends nothing. The ARM-gate ladder is re-derived
`2020 < 2100 < 2460` to `2790 < 2820 < 3180` seconds and the fleet-wide apply mutex from 47 to 59 minutes (worst case only; a healthy arm returns in
seconds). ARMING IS PROBABILISTIC: the cadence is 900 s (start-based, plus `RandomizedDelaySec` jitter, about 93 runs a day) against a 300 s
window, so a healthy synthetic lands a beat inside one apply's window with p ~ 1/3 per host per apply, and the first run after an install usually
precedes the ARM step. A soft landing therefore CAN leave a beat paused for several applies. No `soleur:postmerge` check watches it (none exists; an
earlier draft of this paragraph claimed one). The nets are the twice-daily `heartbeat-live-reconcile` job in `scheduled-terraform-drift.yml`, whose
`fed-but-paused` class flags a paused beat whose manifest feeder is a working feeder (the manifest row carries no `arming_pending`), and the
operator-readable `arm-heartbeats.sh --status soleur-web-bash-synthetic-<host>`; the `::warning::` names `reason=probe_absent` (journal) as the
discriminator between "the image has no probe yet" and "healthy, window missed". Making arming deterministic (a window of at least cadence plus
jitter plus run, about 960 s, with the two hosts armed concurrently) would re-derive the ladder and is deferred (#10777).

**Safety toward the shared container.** The synthetic execs into the container that serves tenants, so it skips (never fails) while a deploy holds
`/var/lock/ci-deploy.lock` (read from `/proc/locks`, never taken: a `flock -n` race would fail a real deploy), when memory is high, and when the
container id or start time changed during the run (a deploy swap kills the probe mid-run). MEASURED (perf review, 2026-10-22): the exec'd tree
peaks at 172-293 MB of container cgroup memory, the resolver process is about 108 MB RSS, and the probe needs about 330 MB of headroom. The
container is capped at 4096m (`PROD_MEMORY_CAP`, swap equal), so a cgroup OOM would kill the largest process in it, i.e. the tenant-serving server.
The first guess of 85 % (about 614 MB left) was too thin once a tenant spike lands during the run, so the threshold is `MEM_PCT_MAX` 70 (about
1.2 GB left, ~3x the peak), AND a HOST gate skips when `/proc/meminfo` `MemAvailable` is below 700 MB (`reason=memory_pressure_host`): on a 4 GB web
host the container's cap is the whole host, so only the host number protects the kernel's other tenants. Both gates, and the deploy-lock check, are
re-sampled immediately before the probe exec, and the exec'd tree runs at `oom_score_adj` 1000 so that, if memory does run out, the kernel picks the
probe before the server. They are time-of-check guards, not caps. The heartbeat URL is pinned to the Better Stack heartbeat host and path (no query);
the unit runs the script as `bash -p` with a scrubbed environment and a 0700 runtime directory. The probe creates nothing outside its own scratch dirs in
runtime mode: the masked dirs belong to real sessions, so the ones that exist are masked and the rest are counted as `masks_missing`. *(Superseded 2026-10-23, #10455: see the addendum below; the runtime probe now creates the closed set of production masked dirs when absent.)* In-container
`timeout -k` (130 s) sits between the probe's 120 s cap and the host's 150 s cap so a hang cannot leave orphan node trees. The script's test seams
are inert unless started with `--fixture-seams` (it runs as root with the whole prd root injected).

**Residuals, stated.** (1) The exec runs as the container's own user (no `-u`), so a pass proves the sandbox for that user, not necessarily uid 1001.
(2) A pass proves the no-egress shape only (same limit as the deploy smoke). (3) A compromised host can ping a false green. (4) web-2's env file is
derived on the host from the probe env file written at its birth, so a rotation of `doppler_service_token.web_probes` reaches web-2 only on a host
replacement, exactly like its three sibling probes. (5) Live Better Stack inventory re-measured read-only 2026-10-22: 7 monitors + 12
heartbeats = 19 objects; this adds two heartbeats (one per host), so 21. The decode lives in `runbooks/canary-probe-set.md` ("Runtime Bash synthetic").

**Known limitation: the deploy smoke is transitionally blind until the verdict lib lands.** `ci-deploy.sh` ships through `apply-deploy-pipeline-fix.yml`
(FILE_MAP `CI_DEPLOY_SH_B64`, the webhook channel), while `sdk-bash-verdict.sh` is delivered ONLY by the two `web_bash_synthetic_install[_web2]` SSH install
blocks (and by cloud-init + `soleur-host-bootstrap.sh` on a fresh host). The two workflows are independent, with no ordering between them. From the moment
a new `ci-deploy.sh` is live until the SSH stage installs the lib, every deploy's SDK Bash smoke takes the lib-absent branch and returns
`smoke_infra_error reason=verdict_lib_absent` (non-blocking: no rollback, the soak counters HOLD); after three consecutive such results
`sdk_bash_smoke_stale` goes to Sentry ("the deploy-time Bash check is blind"). The window is the mutex wait plus the apply (up to 59 minutes) and does not close
if the SSH stage is skipped green or fails. ACCEPTED rather than fixed here: delivering the lib through the `deploy_pipeline_fix` channel (a FILE_MAP entry,
the `push-infra-config.sh` payload, both `deploy_pipeline_fix[_web2]` `triggers_replace`, the workflow `paths:` list and its TRIGGER_FILES parity test) is a
cross-workflow delivery change that does not belong in this PR (#10777). RE-EVALUATE when the lib is delivered through the same channel as `ci-deploy.sh` (#10777), when the first merge after this lands shows `verdict_lib_absent` in the
deploy ledger for longer than one apply, when `sdk_bash_smoke_stale` fires, or when the smoke is next edited. The state is observable, never silent: the
reason is journaled and ledgered, and a ci-deploy.test.sh row pins the branch. A fresh host born from an image that predates this change cannot be born
silently without the detector: `soleur-host-bootstrap.sh` installs `web-bash-synthetic.sh` and `sdk-bash-verdict.sh` under `set -e` with an EXIT trap that
emits a fatal Sentry event naming `failed_file=`, and cloud-init's fail-closed gate powers the host off before the `systemctl enable --now
web-bash-synthetic.timer` line is reached (so no `|| soleur-boot-emit` was added to that line: it also has no spare bytes under the user_data budget).

## Addendum — 2026-10-23 (#10455 PR-B): the runtime probe creates the production masked set

**Status:** `adopting`. Reverses one sentence of the 2026-10-22 addendum ("the probe creates nothing outside its own scratch dirs in runtime mode").

**Why.** All 85 passing runtime synthetic runs on both web hosts since the last deploy read `masks_missing=3`, so the synthetic could never claim the full production tuple. The production builder creates the masked dirs before every dispatch (idempotent `mkdirSync`, not gated on a first one), and a quiet container has had no dispatch, so none exist; a Sentry query for `op:masked-dir-precreate` was empty over 14 days, so this is a probe coverage gap, not a pre-create defect (strongest hypothesis; the first post-merge run on a cold container confirms or refutes it). A fourth production dir, `/tmp/.cs`, was invisible to the probe.

**Decision.** In runtime mode only, the probe creates the closed set `precreateDirs(uid, home)` (the three masked dirs plus `/tmp/.cs`), only when its uid equals PID 1's real AND effective uid (the first two `Uid:` fields of `/proc/1/status`), only when the path is absent, with production's own `mkdir` call (recursive, 0700; no chmod, no chown, never replacing an existing non-directory). A HOME guard refuses the HOME-derived dir when PID 1's `HOME` differs. `masks_created` and `masks_note` are journaled apart from production's behaviour: the synthetic proves the namespace can mount over the dirs, not that the app created them.

**`masks_missing` redefined.** It used to count a masked dir as missing when `statSync` (which follows symlinks) found nothing. It now counts a dir that, after the probe's own create attempt, is not a real directory by `lstat` (a symlink or a file), is owned by another uid, or is still absent. A `pass` with `masks_missing>0` still journals `coverage=prodtuple_partial`. The synthetic journal line now reads `SOLEUR_WEB_BASH_SYNTHETIC verdict=… reason=… selector=… coverage=… masks_missing=… masks_created=… masks_note=… consecutive_no_ping=… detail=…`; the line quoted in the 2026-10-20 section above omits the two new fields, which sit between `masks_missing` and `consecutive_no_ping`.

**Architectural exception (CTO ruling E2, plan review, 2026-10-23).** The deploy smoke and the runtime synthetic both run the probe under `env -i` with a decoy `ANTHROPIC_API_KEY`, so that the real key is never reachable from the probe. To decide whether it shares the app's `HOME`, the runtime probe now reads `/proc/1/environ`, which in the production container holds every Doppler `prd` secret. That is a deliberate exception to that invariant, taken because `/etc/passwd` answers the default `HOME` and not the app's actual one. Controls, each pinned by a unit test with a sentinel secret: the read is capped at 256 KiB and requested as cap plus one byte, so a full read is told apart from one that fit and is treated as unreadable, never parsed; only five names are considered (`HOME` and `CLAUDE_CONFIG_DIR`, `XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR`); the only outputs are two booleans (HOME equals the probe's; some other base is set to an absolute path); values are compared as bytes and never decoded to strings, logged, journaled or returned; the buffer is zero-filled before the function returns. The read happens in runtime mode only, never in the deploy smoke. Accepted residual: a defect in that one function could still leak a value into the probe's process memory, which is the same process that already runs as the container user and can read `/proc/1/environ` of its own container whatever the probe does.

**PID 1 is not the app.** The container starts with `docker --init`, so PID 1 is the init process, running as the container user and passing the environment through to the app. Its uid (real and effective) and `HOME` stand in for the app's because the app is its child, not because PID 1 is the app.

**Alternatives.** Never create (permanently partial coverage under alpha traffic). Create at app boot (changes production for a monitoring need and hides the builder's own mkdir path, the one that now has a routed Sentry alert). Both rejected on the CTO's ruling.

**Accepted limits.** After the first probe run the synthetic can no longer observe a cold-start mkdir failure; the Sentry rule `masked-dir-precreate-failed` is the detector for that. The app's env subset (`CLAUDE_CONFIG_DIR`, `XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR`) is not modelled. Probe-created dirs persist after a revert and are harmless. The #10548 soak reads the deploy-time ledger, which this change does not alter.

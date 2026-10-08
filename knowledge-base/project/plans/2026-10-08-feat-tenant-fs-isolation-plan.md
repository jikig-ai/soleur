---
title: "agent-sandbox: true per-tenant filesystem isolation for the Concierge (ADR-075 Option B; not capacity #4891)"
date: 2026-10-08
slug: feat-tenant-fs-isolation
branch: feat-5863-tenant-fs-isolation
issue: 5863
closes: 5863
type: feat
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

## Overview

Give each Concierge agent session a filesystem view containing only that
session's own workspace. Instead of masking siblings with a `--tmpfs` deny over
a shared mount (the #5862 deny-then-restore baseline), wrap the **entire
`claude` CLI child process** in a self-authored outer bwrap namespace whose
mount table contains only what the session needs. The boundary covers both
agent tool tiers — sandboxed Bash and the file tools (Read/Write/Edit/Glob/
Grep/LS/Notebook*) that execute inside the otherwise-unsandboxed CLI child —
because the wrap happens at the process spawn, not inside the sandboxed
command surface.

Mechanism: the SDK's officially supported `Options.spawnClaudeCodeProcess`
interpose (`sdk.d.ts:2431`, added for "VMs, containers, or remote
environments"). The server receives `{command, args, cwd, env, signal}` and
returns `spawn("/usr/bin/bwrap", <outer argv> -- command ...args)` — no wrapper
script, no vendored-argv surgery, and the isolation property is authored by us
and therefore immune to SDK-bump argv drift (#5849 class).

Closes #5863; folds in #9723 (`/proc` cross-tenant environ channel) and #9725
(deny-root divergence) by construction; leaves #9724 (canary machinery gaps on
the *current* argv path) and #9773 (per-tenant executor end-state) open.

## Research Insights

### Premise Validation (Phase 0.6)

All cited references verified live on 2026-10-08: #5863 OPEN; #5862 CLOSED via
PR #9709 (merged 2026-10-07, `web-platform-release` green since); #9723/#9724/
#9725 OPEN; ADR-075 `accepted` with Option B deferred to this issue; #4891
CLOSED (capacity, out of scope); `spawnClaudeCodeProcess` and
`SpawnedProcess`/`SpawnOptions` confirmed in installed SDK 0.3.284
(`sdk.d.ts:2431`, `:9328`, `:9380`); `getWorkspaceWorktreeRoot` at
`workspace-resolver.ts:69`. One stale reference corrected: "the #5849
split-unshare discriminator" resolves to the #5873 incident / #5941 probe gap
(#5849 is the Sonnet-5 toolchain PR that *caused* #5873).

### Property List (Phase 0.6b)

- P1: no sibling workspace present — content, existence, or mount entry — on
  any agent fs surface (Bash AND file tools).
- P2: session `/proc` shows only session processes.
- P3: mount table derives from the workspace resolver root (survives the
  git-data cutover).
- P4: isolation argv authored by Soleur (SDK-drift-immune).
- P5: failure to construct the namespace fails the session loudly.
- P6: realized-state verification exists (in-sandbox probe, not argv diff).
- P7: per-session `/tmp` and config/`HOME` scope — no cross-tenant scratch or
  transcript visibility.

### Cut List (Phase 0.6b)

- Shim `--args` payload rewrite → P1 (Bash tier only) → cannot reach the
  file-tool tier; cut as primary, retained as contingency.
- Per-tenant subprocess/container executor → P1 + credential boundary →
  overshoots this issue's scope; filed as deferred #9773.
- Idmapped mounts / `setns` / new mount API → P1 → EPERM under the container
  seccomp profile (compile-time cap-gated); impossible without a profile
  change.
- `pathToClaudeCodeExecutable` wrapper script → P1+P4 → superseded by
  `spawnClaudeCodeProcess` (typed argv/env/cwd/signal, no shebang/`existsSync`/
  env-replacement pitfalls); cut in favor of the official interpose.

### Repo research (brainstorm + plan fan-out, consolidated)

- Spawn chain: `cc-dispatcher.ts`/`agent-runner.ts` → `buildAgentQueryOptions`
  (`agent-runner-query-options.ts:204`) → SDK `query()` → vendored CLI child
  (unsandboxed; file tools here) → per-Bash bwrap via `--args <fd>` (opaque to
  the `bwrap-shim` PATH interceptor).
- `buildAgentSandboxConfig` (`agent-runner-sandbox-config.ts:254`) emits
  constant `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...]` →
  vendored builder emits `--tmpfs <landing>` then rw restore binds.
- Sibling-observable surfaces today: `/proc` mount table + same-uid environ
  (#9723), shared `/tmp` (container tmpfs + `/tmp/claude-1001` rw),
  `~/.npm/_logs` + `~/.claude/debug` rw, `~/.claude` ro-visible incl.
  `projects/` transcripts, `denyRead` root divergence under
  `GIT_DATA_STORE_ENABLED` (#9725).
- Reuse inventory (functional-overlap agent): `c4-render.ts` ›
  `buildLikeC4SandboxArgv` is the argv-composition pattern to copy (not
  reusable — wrong mounts/env/net); `bwrap-shim` is the exec-interpose
  precedent (bypass it via absolute `/usr/bin/bwrap`); `classifySandboxStartupError`
  (`sandbox-startup-classifier.ts:136`) is reusable as-is for fail-closed
  classification; `test/helpers/sandbox-isolation-fixtures.ts` is the
  ready-made test harness; `sandbox-canary.mjs` capture/verify/replay
  machinery extends to an outer-wrap fixture.

### External research

- `spawnClaudeCodeProcess` (sdk.d.ts:2412-2431) is the documented interpose;
  `signal` fires only after the SDK's stdin-EOF + ~2 s grace. Caveats:
  custom spawners emit plain `exit` (no stderr drain), spawn ENOENT can hang
  `query()` (anthropics/claude-agent-sdk-typescript#255) — preflight the bwrap
  path.
- Minimal-mount argv composition (bwrap upstream + flatpak-run prior art):
  `--ro-bind /usr /usr` + merged-usr links, ld.so cache + `/etc` minimal set
  (resolv.conf/hosts/nsswitch/ssl/passwd/group), `--dev /dev`, terminfo +
  locale binds, `--clearenv` + explicit `--setenv` allowlist.
- `/proc`: fresh `--proc /proc` inside the new pid ns is the correct close for
  #9723 — but Docker's masked `/proc` can make `mount proc` EPERM inside a
  userns (bubblewrap#284); must be measured in-container at spike time. Never
  fall back to `--bind /proc /proc`.
- Signals: released bwrap has no `--forward-signals`; monitor does not relay
  SIGTERM. Teardown = kill the bwrap process group (monitor+children share
  pgid) or read `child-pid` from `--json-status-fd`. `--die-with-parent` is
  convenience, not enforcement.
- Never `--ro-bind /run` or `$XDG_RUNTIME_DIR` — ro binds do NOT block
  `connect(2)` on socket inodes (delegated-authority escape).
- No `--unshare-net` on the outer wrap (inner SDK sandbox owns egress);
  loopback stays shared container-wide → record as residual (cross-tenant
  127.0.0.1 channel incl. other sessions' socat bridges).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "`pathToClaudeCodeExecutable` wrapper" (spec FR1) | Works, but `spawnClaudeCodeProcess` is the documented interpose and strictly less fragile | Plan adopts `spawnClaudeCodeProcess`; FR1 mechanism updated |
| "exec the real bwrap by absolute path" (spec FR1) | Still correct at the spawn layer — spawn `/usr/bin/bwrap` directly, bypassing the PATH shim | Kept |
| "`--unshare-pid` scopes bound /proc to session processes" (spec FR3) | Correct, but only if the inner argv's `--bind /proc /proc` tail lands on a procfs that is itself session-scoped — and a fresh `--proc` mount may EPERM under Docker masked paths | Phase 0 spike verifies; fallback is outer `--proc` + inner bind landing on it |
| Fresh per-session `$HOME`/`~/.claude` | `~/.claude/projects/` holds resume transcripts — a bare tmpfs breaks `resume`/`continue` | Per-tenant config dir under the workspace root (tenant-scoped, not session-scoped) |

## User-Brand Impact

- **Artifact:** the per-tenant agent filesystem boundary (what a tenant's
  agent can or cannot see, across both tool tiers).
- **If this lands broken, the user experiences:** either a silent isolation
  regression (sibling workspace reachable by another tenant's agent) or a
  hard session-startup outage (fail-closed spawn failure on every Concierge
  run).
- **If this leaks, the user's data is exposed via:** sibling workspace content
  and `/proc/<pid>/environ` credentials (GIT_INSTALLATION_TOKEN-class) readable
  by a co-tenant's agent.
- **Brand-survival threshold:** `single-user incident`.

CPO sign-off required at plan time (brainstorm carry-forward: CPO assessed
2026-10-08 — "gates the first hosted arms-length tenant"; claim ceiling is
"process-level filesystem isolation for sandboxed agent commands", never
unqualified "tenant isolation"). `soleur:engineering:review:user-impact-reviewer`
runs at review time per the review-skill conditional block.

## Implementation Phases

### Phase 0 — Spike gates (pre-merge evidence, no prod change)

- S0.1 In a `node:22-slim`-equivalent local container (the same image family
  the deploy uses): spawn `bwrap` with a minimal mount table wrapping the
  vendored `claude` binary; confirm session startup, `--unshare-pid` + fresh
  `--proc /proc` (or measure the masked-/proc EPERM and select the fallback),
  and nested inner-sandbox bwrap still works (the split-unshare discriminator
  class).
- S0.2 Verify `spawnClaudeCodeProcess` round-trip against a stubbed API
  (`test/helpers/hermetic-cli-env.ts` pattern): SDK calls it once per session
  spawn including resume; stdin/stdout protocol flows through bwrap fds 0-2;
  `options.signal` arrives post-grace.
- S0.3 Kill-semantics probe: SIGKILL the spawned bwrap; assert no orphaned
  `claude` survives (process-group kill on teardown; `--die-with-parent` as
  belt).
- S0.4 Re-measure the prod bwrap version and the container's masked-/proc
  state (evidence conflicts between 0.8.0 and 0.12.0 across issues; the outer
  argv must be valid on the deployed version). Recorded outcome feeds the
  argv feature flags.

### Phase 1 — Failing tests (contract first)

- T1.1 Unit: `buildOuterWrapArgv({workspacePath, sessionId, configDir, ...})`
  produces a table with NO mount under the workspaces parent except the own
  workspace bind; contains `--unshare-pid`; mounts `/proc` fresh or
  session-scoped; `--clearenv` + allowlisted `--setenv`; never binds `/run`
  or `$XDG_RUNTIME_DIR`; workspace path derived from
  `workspacePathForWorkspaceId`'s root (both `WORKSPACES_ROOT` and
  `WORKTREE_ROOT` arms).
- T1.2 Integration (direct-bwrap, `sandbox-isolation-fixtures.ts` style):
  inside a spawned outer wrap, sibling dirs under a stub workspaces root are
  absent from `ls`, `stat`, and `/proc/self/mounts`; `/proc` shows only
  session processes; `/proc/<other-pid>/environ` absent.
- T1.3 Mid-session sibling creation stays invisible (the TOCTOU regression
  shape from `sandbox-isolation.test.ts`, re-pointed at the outer wrap).
- T1.4 Fail-closed: missing bwrap/binary/mount-source → session refuses to
  spawn; stderr marker classifies via `classifySandboxStartupError`.
- T1.5 Fixture pin: committed outer-wrap argv fixture + ordering/shape
  assertions (mirroring `denyBeforeRestoreViolations` for the inner argv).

### Phase 2 — Implementation

- T2.1 New module `apps/web-platform/server/agent-outer-wrap.ts`:
  `buildOuterWrapArgv()` (pure, parameterized on the workspace resolver root)
  + `makeSandboxedSpawn(workspacePath, opts)` returning a
  `spawnClaudeCodeProcess` implementation: computes the mount table, spawns
  `/usr/bin/bwrap` (absolute — never PATH-resolved; the #8752 shim's
  NEWUSER-deny filter must not inject into the outer namespace), returns the
  ChildProcess as `SpawnedProcess`, applies the fd-hygiene discipline (TR5)
  and process-group teardown on `options.signal`/`kill`.
- T2.2 Mount table contents (TR3): `--unshare-user --unshare-pid
  --unshare-uts --unshare-ipc` (NOT `--unshare-net`); `--ro-bind /usr /usr` +
  merged-usr links + ld.so set; minimal `/etc` (resolv.conf, hosts,
  nsswitch.conf, ssl, passwd/group via `--file`); `--dev /dev`; fresh
  `--proc /proc`; `--tmpfs /tmp` + session tmp dirs; tenant-scoped config
  dir (per-tenant `CLAUDE_CONFIG_DIR`/`HOME` view rooted under the workspace
  parent so resume transcripts stay tenant-isolated); the vendored `claude`
  binary + its node_modules/lib deps; the socat/proxy socket the inner
  sandbox needs; `--clearenv` + allowlist.
- T2.3 Wire `spawnClaudeCodeProcess` into `buildAgentQueryOptions` — behind a
  rollout flag (env, default off in the same image; dark-launch per
  `wg-dark-launch-deploy-gates`).
- T2.4 Simplify `buildAgentSandboxConfig` post-wrap: the workspaces-parent
  `denyRead` becomes vestigial (siblings are never mounted); keep `/proc` and
  `c4StagingRoot` denies as inner-layer defense-in-depth (they cannot widen).
  Record the residual: container loopback remains shared (cross-tenant
  127.0.0.1 channel) — named residual, not hidden.
- T2.5 Support/`readOnly` persona parity: same outer wrap for the support
  persona (workspacePath → pluginPath cwd per ADR-113); assert no regression
  to the `allowRead` arm.

### Phase 3 — Canary + observability

- T3.1 Extend `sandbox-canary.mjs` with an outer-wrap arm: capture the
  self-authored argv once (deterministic fixture), replay it at deploy inside
  the canary container, classify EPERM→`sandbox_broken`. **Non-blocking at
  first deploy** — report-only, promoted to gating only after a green soak
  (`wg-dark-launch-deploy-gates`).
- T3.2 In-sandbox realized-state probe (FR6): a probe command inside the outer
  wrap asserts `/proc/self/mounts` carries no sibling-bearing path and `/proc`
  pid set is session-scoped; emits `feature:agent-sandbox` structured event +
  Sentry mirror.
- T3.3 Structured log `op:"tenant-outer-wrap"` per session spawn:
  `{workspace, root, mounts, procMode, outcome}` — discriminating fields for
  the host-vs-sandbox-mount root-cause split (affected-surface rule, Phase
  2.9.2).
- T3.4 Boot self-probe: `verifyAgentSandboxHardening` gains an outer-wrap row
  (bwrap reachable at absolute path, argv builder smoke).

### Phase 4 — ADR-075 amendment + register

- T4.1 Amend ADR-075: Option B adopted in the outer-wrap form; move the
  deferred alternative into Decision consequences; record the loopback
  residual and the file-tool-tier coverage change explicitly.
- T4.2 Art. 30 register entry (honest tense, `adopting` status until
  prod-measured; names the loopback residual and the shared-heap residual
  class deferred to #9773). No public claim (per #9603 discipline).

## Files to Create

- `apps/web-platform/server/agent-outer-wrap.ts` — argv builder + spawn factory.
- `apps/web-platform/test/agent-outer-wrap.test.ts` — unit/integration contract.
- `apps/web-platform/infra/agent-outer-wrap-argv.json` — committed outer argv fixture.
- `knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh` — founder-check realized-state probe (pinned; frozen in this plan's freeze commit).
- `knowledge-base/engineering/architecture/decisions/ADR-075-*.md` amendment (edit, not create).

## Files to Edit

- `apps/web-platform/server/agent-runner-query-options.ts` — wire
  `spawnClaudeCodeProcess` under the rollout flag.
- `apps/web-platform/server/agent-runner-sandbox-config.ts` — vestigial-deny
  simplification + comments.
- `apps/web-platform/server/cc-dispatcher.ts` — pass tenant-scoped config-dir /
  session identity through to options builder if needed.
- `apps/web-platform/scripts/sandbox-canary.mjs` — outer-wrap capture/replay arm.
- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` — in-image
  verify for the outer fixture.
- `apps/web-platform/test/sandbox-isolation.test.ts` — outer-wrap cases.
- `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` — outer-wrap
  spawn helper.
- `apps/web-platform/test/sandbox-canary.test.ts` — fixture pin extension.
- `apps/web-platform/Dockerfile` — only if the canary needs it (no wrapper
  script to COPY under the `spawnClaudeCodeProcess` design).
- `knowledge-base/legal/article-30-register.md` — new TOM row (adopting).

## Scope Check

### Ask Mapping

| # | User ask (verbatim, [issue #5863]) | Plan item | Status |
|---|-----------------------------------|-----------|--------|
| 1 | "Design per-tenant filesystem isolation for the in-process multi-tenant runner (mount-namespace-per-session, or per-agent workspace-only mount, or a topology change to per-tenant subprocess/container)." | Phases 0–3; `agent-outer-wrap.ts`; FR1–FR8 in spec | mapped |
| 2 | "Once shipped, the sandbox `denyRead` for `/workspaces` becomes unnecessary — simplify `buildAgentSandboxConfig`." | T2.4; AC7 (spec) | mapped |
| 3 | [operator] "Tenants are coming" → full end-state bar (content, existence, mount table, /proc) | P1/P2; T1.2 assertions; FR2/FR3 | mapped |
| 4 | [operator] "Both tiers" — file tools covered | spawn-at-CLI-process design; AC1 covers both surfaces | mapped |
| 5 | [operator] "Fold into #5863" — #9723 + #9725 | G2/G3; T2.2 proc handling; resolver-root derivation | mapped |
| 6 | [operator] "1 now, 3 tracked" | #9773 filed at brainstorm; ADR amendment records deferral | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Outer-wrap module + spawn wiring | "mount-namespace-per-session, or per-agent workspace-only mount" | asked |
| Canary/probe extension (T3.1–T3.3) | — | inferred — dark-launch verification is mandated for new deploy-affecting surfaces (`wg-dark-launch-deploy-gates`) and the affected-surface observability rule (2.9.2) requires an in-surface probe |
| Per-tenant config dir | — | inferred — required for resume without re-leaking `~/.claude/projects` transcripts cross-tenant (P7) |
| ADR-075 amendment + Art.30 row | — | inferred — `wg-architecture-decision-is-a-plan-deliverable` + CLO gate requirement |
| `buildAgentSandboxConfig` simplification | "the sandbox denyRead for /workspaces becomes unnecessary — simplify" | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/server`, `apps/web-platform/{scripts,test}`, `knowledge-base` (ADR/legal)
- Planned files: ~10 | Estimated changed lines: ~600-900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (borderline on lines; splitting code from canary would strand the guard unvalidated)

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** (CTO, brainstorm carry-forward) Outer-CLI bwrap wrap is the
sweet spot — covers both tiers, dissolves #9725 and narrows #9723 to session
scope, self-authored argv immune to SDK drift, failure scoped to session
startup. Plan refines the mechanism to `spawnClaudeCodeProcess` (the SDK's
documented interpose — strictly better than a wrapper script).

### Legal

**Status:** reviewed
**Assessment:** (CLO, brainstorm carry-forward) No commitment breached; #9723
is a cross-tenant channel that must close or be recorded as an open residual —
this design closes it. Plan must run `soleur:gdpr-gate` (Phase 2.7), write the
register entry in honest tense (`adopting` until prod-measured), hold public
claims, and ship an observability probe since `/proc` reads leave no audit
trail.

### Product

**Status:** reviewed
**Assessment:** (CPO, brainstorm carry-forward) Zero alpha-tester perception
today; value is claim-enabling. Under "tenants are coming" this gates the
first hosted tenant — sequencing agreed. Claim ceiling: "process-level
filesystem isolation for sandboxed agent commands".

**Brainstorm-recommended specialists:** none (no specialist named in the
brainstorm's Domain Assessments).

## Observability

```yaml
liveness_signal:
  what: "op=tenant-outer-wrap outcome=ok per-session spawn log + feature:agent-sandbox probe verdict"
  cadence: per session spawn; probe per deploy
  alert_target: "Sentry feature:agent-sandbox"
  configured_in: "apps/web-platform/server/agent-outer-wrap.ts; scripts/sandbox-canary.mjs"
error_reporting:
  destination: "pino + reportSilentFallback → Sentry"
  fail_loud: "spawn refusal throws; classifySandboxStartupError surfaces bwrap_eperm/launcher classes"
failure_modes:
  - mode: "outer wrap cannot build (bwrap missing/EPERM/masked-proc)"
    detection: "in-surface: wrapper stderr marker + op=tenant-outer-wrap outcome=fail {reason}"
    alert_route: "Sentry feature:agent-sandbox"
  - mode: "mount table under-binds (session breaks) vs over-binds (leak)"
    detection: "in-surface: realized-state probe asserts no sibling-bearing mount AND required binds present"
    alert_route: "Sentry feature:agent-sandbox + sdk-startup classifier"
  - mode: "SDK stops calling spawnClaudeCodeProcess (silent unwrapped spawn)"
    detection: "boot self-probe asserts the interpose is installed; per-session log proves the wrap ran"
    alert_route: "deploy-time verify + Sentry"
  - mode: "orphaned claude survives kill"
    detection: "process-group teardown assert in tests; session-reaper count metric"
    alert_route: "Sentry feature:agent-sandbox"
logs:
  where: "stdout pino → journald; Sentry mirrors"
  retention: "journald default"
discoverability_test:
  command: "bash apps/web-platform/scripts/sandbox-canary.mjs --verify"
  expected_output: "verify_ok"
```

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-075** (`ADR-075-agent-sandbox-tenant-read-isolation.md`): Option B
  adopted in the outer-wrap form — move Option B from deferred alternatives
  into the decision record; record the new residuals (container loopback
  sharing; shared in-process heap → #9773; inner-layer file masks unchanged);
  note Option C's machinery becomes vestigial for the workspaces root.

### C4 views

- Checked `model.c4`/`views.c4`/`spec.c4` during the C4 completeness pass: the
  change is an internal namespace boundary inside the existing web-platform
  container — no new external actor, external system, container, or data
  store. The tenant↔workspace relationship is already modeled; the isolation
  *mechanism* changes, not the graph. **No C4 impact** (actors/systems/
  relationships enumeration: tenant user, Concierge container, workspaces
  volume, Sentry — all already modeled; none added).

### Sequencing

The ADR amendment ships in the same PR, status `accepted` for the isolation
claim only after the deploy-time probe is green; interim `adopting` wording
per the register discipline.

## Guard Contract

### Guard 1 — outer-wrap realized-isolation probe

**Property.** A sandboxed agent session observes no filesystem entry under the
workspaces parent other than its own workspace, and `/proc` contains only
session processes.

**Assembly.** The probe runs INSIDE the outer wrap (the only vantage where the
property is decidable): it enumerates `mountinfo` entries + `ls`/`stat` of the
parent + `/proc` pid set — the structural chokepoint is the spawned namespace
itself, so the guard sits in the deploy canary replay plus an opt-in boot
self-probe.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a sibling bind to the outer argv | probe reports sibling-visible → RED |
| 2 | Remove `--unshare-pid` while keeping host-proc bind | probe reports host pid set → RED |
| 3 | Reorder own-ws bind before a later parent tmpfs | session ws unwritable/absent → RED |
| 4 | Probe body replaced by `exit 0` (vacuous harness row) | dispatch-count assertion: `mounts==0 && exit 0` is FAIL — the guard's own dispatch is floored |
| 5 | Valid but different table: extra `/usr/local` bind (non-parent, no sibling) | must-PASS — pins that the guard discriminates by *sibling-bearing* mounts, not by argv diff |

### Guard 2 — committed outer-argv fixture pin

**Property.** The outer argv emitted by `buildOuterWrapArgv` matches the
committed fixture under placeholder substitution — drift in the mount set is a
reviewable diff, never a silent one.

**Assembly.** `buildOuterWrapArgv` is the sole producer; the pin compares its
output to `infra/agent-outer-wrap-argv.json` (same canonical-projection idiom
as `sandbox-canary-argv.json`). No second producer exists.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a mount covering the workspaces parent | pin diff → RED |
| 2 | Reorder deny/restore pairs | ordering assertion → RED |
| 3 | Fixture regenerated from the mutated code (self-certify) | anchor fails: fixture SHA is itself pinned in the test; regeneration without an explicit ACK step → RED |
| 4 | Test that only diffs against the fixture (harness vacuity) | floor: fixture must contain ≥1 `{{WS}}` placeholder AND zero absolute sibling paths → RED if either absent |

## Acceptance Criteria

- AC1: In a spawned session, `ls`/stat/`findmnt` under the workspaces parent
  shows only the session's own workspace — via Bash AND via a file-tool read
  attempt on a sibling path (both denied by absence, not by hook).
- AC2: `/proc` inside the session lists only session pids; a concurrent
  sibling session's environ is unreachable.
- AC3: A sibling workspace created mid-session remains invisible.
- AC4: No cross-tenant readable/writable scratch remains under `/tmp` or
  `HOME`; resume works from the tenant-scoped config dir.
- AC5: Outer-wrap construction failure refuses the session with a classified
  startup error (`classifySandboxStartupError` vocabulary) — no degraded spawn.
- AC6: The outer-wrap canary arm ships report-only and records green on ≥1
  real deploy before any gating promotion (`wg-dark-launch-deploy-gates`).
- AC7: `denyRead` no longer carries the workspaces root (or is demonstrably
  vestigial and documented as such); `/proc` + c4-staging denies remain.
- AC8: ADR-075 amended; Art. 30 register row written in `adopting` status.
- AC9: Rollout flag defaults off; enabling is an image+env change with no
  schema migration.

```
founder_check:
  kind: command
  text: "Two-tenant realized probe — done = a runtime probe shows tenant A's session cannot see tenant B's workspace on any surface (mounts, stat, /proc, file tools)."
  command: bash knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh
  expected: isolation_ok
  pins:
      knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh: 6c66253f6faa78a29c6b204780efd1294349e31c
  approved_by: deruelle
  approved_at: 2026-10-08
```

## Test Scenarios

- Given a two-workspaces fixture root, when a session spawns for workspace A,
  then workspace B is absent from `ls <root>` and `/proc/self/mounts` inside.
- Given the outer wrap active, when `cat /proc/<sibling-agent-pid>/environ` is
  attempted (pid from the host's view), then the pid does not exist inside.
- Given `GIT_DATA_STORE_ENABLED=true` arm, when the resolver returns a
  `WORKTREE_ROOT` path, then the outer table binds under that root and no
  `/workspaces` assumption leaks.
- Given bwrap absent or EPERM (profile regression), when a session starts,
  then spawn refuses with `bwrap_eperm`-class error and a Sentry event fires.
- Given resume (`options.resume`), when the session spawns, then the same
  outer table applies and the transcript dir resolves under the tenant config
  dir.

## Open Code-Review Overlap

- `#3243` arch: decompose cc-dispatcher.ts — **Acknowledge.** Our edit is a
  narrow pass-through (option field wiring); the decomposition scope-out is a
  different concern that stays open.
- `#3242` review: tool_use WS event lacks raw name field — **Acknowledge.**
  Unrelated surface in the same file; no interaction with spawn options.

## Risks / Sharp Edges

- **Nested bwrap on the deployed kernel/profile** — the #5873 split-unshare
  class lives here; Phase 0 spike is the gate, and the deploy canary replays
  the real argv before the flag flips.
- **`--proc` vs masked-paths EPERM** (bubblewrap#284) — measured at spike;
  fallback keeps `--bind /proc /proc` but only *after* `--unshare-pid`, which
  is still session-scoped.
- **Under-binding breaks the CLI** — footprint enumeration is exhaustive
  (TR3): binary + libs, ld config, terminfo, locale, `/etc` set, plugin root,
  config dir, sockets. The dev-loop verification is a real session, not argv
  review.
- **Kill propagation** — teardown kills the bwrap process group; orphan check
  in T1/S0.3.
- **Loopback residual** — the container's `127.0.0.1` remains shared across
  sessions (inner sandboxes' socat bridges included). Named residual; full
  closure belongs to #9773's topology work or per-session netns design.
- **Shared-heap residual** — the runner still holds all tenants' session
  state/BYOK leases in one process; fs isolation does not change that
  (#9773).
- **Flag mechanics** — rollout env flag read at dispatch, not module load;
  cutover mid-flight is not supported (in-flight sessions keep their birth
  isolation).

## Session Summary (evidence notes)

- Premise probes: `gh issue view` on 5863/5862/9723/9724/9725/4891/5733/6641;
  `gh pr view 9709`; release runs green post-merge.
- SDK surface: `sdk.d.ts:2431` `spawnClaudeCodeProcess`, `:9328` SpawnedProcess,
  `:9380` SpawnOptions.
- Overlap check: `gh issue list --label code-review --state open` scanned
  against the Files lists.

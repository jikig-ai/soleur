---
title: "fix(c4): staleness banner states the save diagnostic; likec4 render child runs inside bwrap with wasm layout pinned"
date: 2026-09-24
slug: fix-c4-stale-banner-diagnostic-and-likec4-bwrap-sandbox
branch: feat-one-shot-8695-8696-c4-banner-bwrap
issue: 8696
closes: [8695, 8696]
type: fix
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deepened: 2026-09-24
---

# fix(c4): staleness banner states the save diagnostic; likec4 render child runs inside bwrap with wasm layout pinned

## Enhancement Summary

**Deepened on:** 2026-09-24. **Inputs folded:** plan-review panel (architecture-strategist, Kieran, spec-flow-analyzer — saved findings), then a deepen round of security-sentinel, test-design-reviewer, code-simplicity-reviewer, observability-coverage-reviewer, learnings-researcher and a verify-the-negative pass, plus replica measurements of bwrap 0.8.0 under the production seccomp profile. Every finding and its disposition is in **Review Findings Disposition** (one row each; rationale lives there, not repeated).

**Key changes from the pre-deepen plan.**

1. **Host-side output read (new Guard 5, P0).** The host opens the child's output with `O_NOFOLLOW|O_NONBLOCK`, `fstat`s it and caps its size before reading. It also waits for the child to fully exit before cleanup, so a live child can't redirect the host's `rm`.
2. **Tighter sandbox.** Read-only root plus sized tmpfs for `/tmp`, `/c4-home` and `/dev/shm`; `--unshare-ipc/uts`; `/usr/bin/bwrap` by absolute path; a production pin that keeps every binary under `/usr`; source-pinned binds.
3. **One spawn site.** The boot probe is now a real fixture render through the same path as a save. It runs after `listen` and reports success as a Sentry info event, because info logs never reach Better Stack.
4. **Sentry.** Failures are reported with `err = null`, so the pino mirror no longer swallows the tags (#8629), with a fixed message per reason and a `detail_class` tag. AC-P1 is now two concrete event-count reads.
5. **Banner copy.** The no-reason line names the supersede instead of promising a refresh; a resync failure now carries a diagnostic; the reason resets on a folder change.
6. **Render pool.** Shared across the two bundles and bounded by a slot-wait deadline.

## Overview

Two follow-ups to the C4 re-render security fix (#8623, merged 2026-09-24 as PR #8687), shipped together on one branch (draft PR #8732):

1. **#8695 (UI copy).** The C4 editor's staleness banner (`C4Diagnostics`, the amber `stale` strip, today in `apps/web-platform/components/kb/c4-shared.tsx`) always says the diagram "is precomputed" and "refreshes after the model is re-rendered" later. It shows that line even when the save response carries a `rerenderDiagnostic`, which means no refresh is coming until the user acts. Fix: line 2 shows the diagnostic itself (first letter capitalised) when one is present, and an honest no-promise sentence when none is (Phase 1 item 1).
2. **#8696 (defence in depth).** The `likec4 export json` child spawned by `apps/web-platform/server/c4-render.ts` runs as the app container's uid with no sandbox, so a likec4 parser defect would reach `/workspaces` (every tenant's clone) and `/proc/<server-pid>/environ` (the server's secrets, readable by the same uid). Fix: exec the child inside bubblewrap with an allowlisted root, no network, no `/proc`, a cleared environment, and fail closed; the host stops trusting what the child leaves behind (Guard 5).

**Folded-in latent bug, found while measuring #8696 (Research Reconciliation row 3).** likec4 1.50.0 defaults `--use-dot` to true when it detects a container (`/.dockerenv`). The runner image has no graphviz `dot`, so today's production render lays out every view with a missing binary: the export exits 0 with 80 elements and **0 views**, passes the elements-only gate, and is committed, which blanks the diagram. The fix pins wasm layout (`--no-use-dot`) and refuses a zero-view export (`layout_failed`, keeps the previous model).

## Research Reconciliation — Spec vs. Codebase

| # | Claim (issue / code comment) | Reality (measured 2026-09-24) | Plan response |
|---|---|---|---|
| 1 | #8696: bubblewrap is "already present in the runner image" | TRUE. `apps/web-platform/Dockerfile` runner stage installs `bubblewrap` (apt line with `git bubblewrap socat qpdf jq`); Debian bookworm package = **bwrap 0.8.0**. The container runs with `--security-opt seccomp=soleur-bwrap.json` + `apparmor=soleur-bwrap` (`apps/web-platform/infra/ci-deploy.sh`, `docker run` block) because the Agent SDK sandbox uses bwrap in prod, and the deploy canary replays the SDK argv (`--unshare-net`, `--unshare-pid`, `--unshare-user`) inside the canary container on every deploy (ADR-079). | Use the system `/usr/bin/bwrap`; no image package change. Dockerfile edit is comment-only. |
| 2 | #8696: "no `/proc` of the parent" | `--proc /proc` is impossible in this container: `bwrap: Can't mount proc on /newroot/proc: Operation not permitted` (Docker's masked `/proc` paths; learning `security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`). The SDK works around it by binding the PARENT `/proc` (`--bind /proc /proc` in `sandbox-canary-argv.json`), which is exactly what #8696 forbids. | Mount no `/proc` at all. Measured: node + likec4 + wasm layout run fine without it. |
| 3 | `c4-render.ts` comment "Real prod model exports in <1s (verified 2026-06-05)" and Dockerfile "exits 0 with no dot on PATH, ~0.8s" | Both describe the FAILED-layout path. In a container, likec4's `--use-dot` defaults to `isInsideContainer()` (cli/index.mjs: option `use-dot` `default: w()`), so it uses `GraphvizBinaryAdapter`, finds no `dot`/`unflatten`, logs ~20k stderr lines and exports `views: {}`. With `--no-use-dot`: 82 views, 3.8-7.2 s at 2 CPUs. | Pin `--no-use-dot`; add a views gate; correct both comments; bound the slot wait (Phase 2 item 8). |
| 4 | #8695: the banner "always says" the precomputed/refresh line | TRUE (`C4Diagnostics`, second `<p>`). Also: `components/kb/c4-diagram.tsx` `onSaved` calls `setTab("diagram")`, which unmounts `C4CodePanel` and its `Saved — <diagnostic>` header message, so in the embedded viewer the banner is the ONLY surface that could show the reason. | Reword (not hide) line 2 with the diagnostic. |
| 5 | #8695 Fix-Size "2 lines / 1 file" | The diagnostic never reaches `C4Diagnostics`: `C4CodePanel.onSaved(rerendered)` passes only a boolean, and both parents (`c4-workspace.tsx`, `c4-diagram.tsx`) hold only `stale: boolean`. | Thread the diagnostic through `onSaved` → parent state → a new optional `C4Diagnostics` prop. |
| 6 | (deepen) `rerendered:false` with no diagnostic means "a refresh is coming" | FALSE. `c4-writer.ts` `rerenderAndCommit` returns `{ rerendered:false }` with no diagnostic on exactly two paths: `superseded("sources-changed")` and the resync-after-commit failure (`op: "resync"`); every other `rerendered:false` return carries one (verify-the-negative pass). The only client reload is the one-shot `reload()` inside `onSaved`; nothing reloads this view when another actor (Concierge, another tab, a direct push) supersedes the save. | Resync failure gets `RETRY_DIAGNOSTIC` (existing copy); the no-reason line names the supersede and makes no refresh promise (Phase 1 item 1); a writer test pins "supersede is the only no-diagnostic return". |
| 7 | (deepen) `c4-render.ts` is one module instance | FALSE. It is bundled twice into one process: `build:server` (esbuild; `server/index.ts` → `cc-dispatcher.ts` → `c4-concierge-tools.ts` → dynamic `import("@/server/c4-writer")`) and `next build` (`app/api/kb/c4/[...path]/route.ts` imports `writeC4Diagram`). `POOL_SIZE` and any module-level memo exist once per bundle, so today up to 4 layouts can run at once. Precedent for sharing: `server/inngest/functions/_cron-claude-eval-substrate.ts` keeps its in-flight map on `globalThis[Symbol.for(...)]`. | Render pool on `globalThis[Symbol.for("soleur.c4RenderPool")]` (Phase 2 item 8). |
| 8 | (deepen) an info-level pino line is a Better Stack liveness signal | FALSE. `infra/vector.toml` `app_container_warn_filter` ships only app-container lines at WARN+; the existing boot liveness uses `Sentry.captureMessage(…, { level: "info", tags: { event_type: "server-startup" } })` in `server/index.ts`. | Probe success = a Sentry info event with `event_type: "c4-sandbox-probe"` (Phase 2 item 10). |
| 9 | (deepen) `reportSilentFallback(new Error(…), { tags })` delivers the tags | FALSE. The pino mirror (`server/logger.ts` `mirrorToSentry`) captures the same Error first as `feature=pino-mirror`, and Sentry drops the tagged second capture (`server/anthropic-credit.ts` header, tracking #8629). `server/readiness.ts` `verifyWorkspacesMountOnce` and `anthropic-credit.ts` pass `err = null`. | Every new or changed c4 Sentry report passes `err = null` with a fixed message (Phase 2 item 9). |

## Research Insights

**Premise Validation.** #8695 and #8696 are OPEN (`gh issue view`), both labelled `deferred-scope-out`, both "Ref #8623". #8623 is CLOSED by PR #8687 (MERGED 2026-09-24T12:48Z). Every cited path exists on `origin/main`: `server/c4-render.ts` (468 lines; carries `// Residual: the child still runs as the app's uid (bwrap wrapping: #8696).`), `components/kb/c4-shared.tsx` (`C4Diagnostics`), ADR-050 amendment 2026-09-24 (**Residuals** paragraph names #8696 and #8695). ADR corpus grep for the mechanism: ADR-050 amendment lists "Rendering inside the bwrap agent sandbox" under **Alternatives rejected** — that rejected *replacing* staging with the AGENT sandbox on the save path; this plan keeps staging and adds a dedicated, render-only bwrap, which the same amendment's Residuals paragraph tracks as #8696. ADR-079 records that a hand-rolled bwrap argv (#4932) false-rolled-back every deploy when used as a deploy GATE — this plan's argv is never a deploy gate (the boot self-probe is report-only).

**Property List (Phase 0.6b).**

- P1. After a save whose re-render was skipped with a stated reason, the banner tells the user that reason and does not promise an automatic refresh.
- P2. After a save that a newer change superseded (no reason), the banner says so and does not promise an automatic refresh.
- P3. A later save replaces or clears a previous save's reason, and the reason never carries over to another diagrams folder.
- P4. The likec4 child cannot read `/workspaces`, `/app`, the server's `/proc`, or `$HOME`; cannot write its input; has no network; inherits no server env; gains no privilege (`no_new_privs`).
- P5. A sandbox that cannot start fails the render closed (source still committed, user told), never degrades to an unsandboxed spawn in production, and reaches Sentry with a discriminating tag.
- P6. A sandbox break introduced by a host/profile/image change is visible within minutes of a container start, not only on the next tenant save.
- P7. The server never commits a layout-failed (zero-view) model.
- P8. The server never reads, commits or deletes through anything the child leaves in its output dir: it reads only a regular file opened without following links, within a size cap, and cleans up only after every sandbox process has exited.

**Cut List.** None of the issues' named mechanisms is redundant: bwrap already exists in the image (reused); `rerenderDiagnostic` already exists server-side (reused; the only new copy is the supersede line). Cut at planning: a new sandbox-canary row (P6 is covered by the boot self-probe — Alternatives), a new IaC Sentry alert rule (Alternatives), and the bwrap-version capture (a third spawn site for data the release tag already pins).

**Measurements (Phase 0.6c; faithful replica image).** Image: `node:22-slim@sha256:4f77a690…` (the runner stage digest) + `npm install -g likec4@1.50.0` + apt `bubblewrap socat` + `useradd --uid 1001 soleur`, run as `docker run --init --security-opt seccomp=apps/web-platform/infra/seccomp-bwrap.json --tmpfs /tmp` on this repo's own diagrams (82 views). AppArmor `soleur-bwrap` was NOT loaded (host lacks AppArmor); it allows `mount`/`umount`/`pivot_root` broadly, and the boot self-probe closes that residual in the real container. Scripts and logs: session scratchpad `bwrap-probe/probe*.sh`. The argv measured here is the planning shape; Phase 2 item 1 is the final target, and item 0 re-measures it.

| Measurement | Result |
|---|---|
| bare spawn, prod env (`env -i PATH HOME TMPDIR`), no flag | rc 0, **0 views**, 20,303 stderr lines (`FAILED GraphvizBinaryAdapter … not found: dot`), 1.3-2.0 s |
| bare spawn `--no-use-dot` | rc 0, 82 views, 4.3-5.7 s |
| bwrap `--no-use-dot`, 8 interleaved iterations vs bare | bwrap 3.8-5.2 s vs bare 4.5-5.7 s: **no measurable latency penalty**; bwrap setup alone 11 ms |
| bwrap output vs bare output | **byte-identical** after the `/c4-sources` path rewrite |
| single render, `--cpus 2 --memory 2g` | 7.2 s, cgroup `memory.peak` 183 MiB |
| two concurrent renders | 12.5 s wall, `memory.peak` 366 MiB |
| `--proc /proc` | `Can't mount proc on /newroot/proc: Operation not permitted` |
| no `/etc/passwd` in sandbox | likec4 crashes at import: `uv_os_get_passwd returned ENOENT` (`atomically.mjs` calls `os.userInfo()`) → bind `/etc/passwd` + `/etc/group` read-only |
| isolation inside sandbox | `/workspaces`, `/app`, `/proc` absent; `touch /c4-sources/x` → Read-only file system; `http.get` → `ENETUNREACH` |
| SIGKILL of bwrap with a detached grandchild inside | 2 node processes before, **0 after** (pid-ns teardown + `--die-with-parent`) |
| broken source inside sandbox | rc 0, `Invalid /c4-sources/model.c4 … Could not resolve reference to ElementKind named 'foo'` on stderr (the writer's regex still matches) |
| source with NO `views {}` block | likec4 still emits `index` + scoped views → a successful layout always yields ≥1 view |

**Deepen measurements (2026-09-24, `debian:bookworm-slim` + apt `bubblewrap` = 0.8.0, `--security-opt seccomp=apps/web-platform/infra/seccomp-bwrap.json`, child as uid 1001 via `setpriv`, `/bin/sh` payloads — no node/likec4 in this image).**

| Measurement | Result |
|---|---|
| bwrap 0.8.0 `--help` | has `--size`, `--unshare-ipc`, `--disable-userns`, `--json-status-fd`, `--perms`; `prlimit` present (util-linux) |
| `--unshare-ipc`, `--unshare-uts` (each, and both) | rc 0 — the seccomp rule "Allow clone with CLONE_NEWUSER" (`MASKED_EQ 0x10000000`) admits any extra namespace flag in the same clone |
| `--disable-userns` | `bwrap: cannot open /proc/sys/user/max_user_namespaces: Read-only file system` → not usable here |
| default root (no `--remount-ro /`) | `/` is a tmpfs owned by uid 1001: `touch /x` succeeds → unbounded RAM write surface |
| `--remount-ro /` + `--size 1048576 --tmpfs /c4-home` + `--size 1048576 --tmpfs /tmp` | `/` read-only; `/c4-home`, `/tmp`, `/c4-out` writable; `dd` of 3-4 MiB into a 1 MiB tmpfs stops at 1 MiB |
| child plants `ln -s /etc/shadow /c4-out/l` | succeeds — the host sees a symlink in `<stage>/out` (Guard 5) |

**Relevant files (content anchors, not line numbers).**

- `apps/web-platform/server/c4-render.ts` — `runLikeC4` (the only `spawn(`; the timeout handler calls `child.kill("SIGKILL")` then `settle` without waiting for `close`; `stderrChunks` is unbounded until `close`), `renderToValidatedModel` (elements gate; `readFile(tmpOut, "utf8")` by path), `renderC4Model`'s `finally` (`rm(dir, { recursive })`), `acquire`/`release` (module-level `inFlight`/`waiters`, no wait bound), `STABLE_SOURCE_ROOT = "/c4-sources"`, `LIKEC4_BIN` (env override "for tests / local dev only").
- `apps/web-platform/server/c4-writer.ts` — `buildRerenderDiagnostic` maps every reason except `empty_model`/`unsafe_source`/stage-phase to `INTERNAL_DIAGNOSTIC`, so new reasons `sandbox_error`/`layout_failed` need no copy change; `reportSilentFallback(new Error(render.detail ?? render.reason), { tags: { reason, phase } })` (variable message, and tags lost per Reconciliation row 9); `rerenderAndCommit` `resync` failure and `superseded()` return `{ rerendered:false }` with no diagnostic.
- `apps/web-platform/components/kb/c4-shared.tsx` — `C4Diagnostics` (banner), `C4CodePanel.save` (`setSaveMsg(... Saved — ${diagnostic})`, the no-diagnostic `"Saved — diagram will update after re-render."`, `await onSaved(rerendered)`). The PUT awaits the whole re-render (`writeC4Diagram` awaits `rerenderAndCommit`), so "Saving…" already spans the render.
- `apps/web-platform/components/kb/c4-workspace.tsx`, `c4-diagram.tsx` — `const [stale, setStale] = useState(false)`; `onSaved={async (rerendered) => { await reload(); setStale(!rerendered); … }}`. `app/(dashboard)/dashboard/kb/[...path]/page.tsx` renders `<C4Workspace dirPath={c4DirPath} …>` with no `key`.
- `apps/web-platform/server/index.ts` — `app.prepare().then(() => { … verifyWorkspacesMountOnce(); … server.listen(port, () => { … Sentry.captureMessage(…, { tags: { event_type: "server-startup" } }) … }) })`; `const dev = process.env.NODE_ENV !== "production"`.
- `apps/web-platform/infra/sandbox-canary-argv.json` — SDK-captured argv (never hand-authored); its `--unshare-*` set is exactly user, pid, net.
- `.github/workflows/ci.yml` test-webplat — installs `likec4@1.50.0`, sets `LIKEC4_REQUIRED: "1"`; runner `ubuntu-latest`; no bubblewrap step, no userns sysctl. `apps/web-platform/scripts/sandbox-canary-regression.test.sh` is the precedent for `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` on an ephemeral GH-hosted runner.
- Tests: `test/c4-render.test.ts` (hoisted `vi.mock("node:child_process")` + `vi.mock("node:fs/promises", () => fsMock)`; `fsMock.mkdtemp` always returns `/tmp/c4-render-abc123`; asserts `args[0..4]`, `opts.cwd`, env allow-list, `HOME === TMP_DIR`; two ok-path fixtures carry `views: {}` — "replaces the random stage path inside rendered file:// URIs…" and "maps a canonicalize failure to io_error…"), `test/c4-render-boundary.test.ts` (row 1: c4-render.ts fs imports exactly `lstat/mkdir/mkdtemp/readFile/readdir/rm`; row 8: `LIKEC4_BIN` only in c4-render.ts; `renderC4Model` importers exactly c4-render.ts + c4-writer.ts), `test/c4-render-tenant-config.test.ts` (REAL likec4, `LIKEC4_REQUIRED`), `test/c4-writer-rerender.test.ts` (AC2b resync failure asserts only `rerendered:false`; mocks a `"non_zero_exit"` render result), `test/c4-writer-concurrency.test.ts` (mocks `renderC4Model` returning `{ ok, durationMs, json }`), `test/c4-shared.test.tsx`, `test/c4-workspace.test.tsx` + `test/c4-diagram.test.tsx` (mock `C4Diagnostics` exposing `data-stale`; mock `C4CodePanel` calling `onSaved(true|false)`).

**RenderReason consumers (hr-type-widening-cross-consumer-grep, three patterns).** Type names `RenderReason|RenderFailure|RenderResult|renderC4Model`: `server/c4-render.ts`, `server/c4-writer.ts`, tests `c4-render*.test.ts`, `c4-writer-rerender.test.ts`, `c4-writer-concurrency.test.ts`. Literal reason strings (`"spawn_error"`, `"non_zero_exit"`): `c4-render.ts`, `c4-render.test.ts` and `c4-writer-rerender.test.ts` (a mocked render result); the `kb-upload*.test.ts` hits are pdf-linearize's own union. No `switch` over `RenderReason` anywhere. Adding `sandbox_error` and `layout_failed` is safe; `c4-writer.ts` needs no branch for them. The internal `SpawnResult` union also gains `"sandbox_error"`.

**Institutional learnings applied.**

- `security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md` and `docker-seccomp-blocks-bwrap-sandbox-20260405.md` — seccomp + AppArmor + masked `/proc` are the three layers; `--proc` fails in Docker. Confirms "no /proc".
- `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` — never ship a deploy-GATING probe validated only against a mock; dark-launch report-only first. → the boot self-probe is report-only.
- `2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md` — validate argv inside the deploy base image, not the host. → replica-image measurements; the boot self-probe runs in the real container.
- `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` — env allow-list. → `--clearenv` + explicit `--setenv`. (Its "CI=true for likec4" advice is WRONG here — Sharp Edges.)
- `best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md` — exit 0 is not success; gate on the output shape. → views gate.
- `bug-fixes/2026-06-12-c4-save-revert-stale-clone-optimistic-apply.md` — the optimistic `savedContentRef` flow must stay untouched; the banner change is parent-state only.
- `2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md` — the banner already appears only after a failed re-render; the change makes it actionable, not louder.
- `best-practices/2026-06-05-llm-facing-claim-correction-must-sweep-tool-desc-and-prompt-addendum.md` — swept: `RERENDER_OUTCOME_GUIDANCE` in `server/c4-concierge-tools.ts` already says "nothing updates it until a later save renders successfully"; the banner now agrees with it.
- (deepen) `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md` — a pre-open `lstat` reintroduces the CodeQL `js/file-system-race` window; classify from the `ELOOP` of the `O_NOFOLLOW` open instead. → Guard 5 has no pre-open `lstat`.
- (deepen) `2026-04-17-stream-response-toctou-across-fd-boundary.md` — never re-open the same path within one operation. → one fd for `fstat` and read.
- (deepen) `test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` — hoisted mocks and module state leak across reused workers. → the pool's `globalThis` key is deleted in `afterEach` (Guard rows).

**Domain leader input (Phase 2.5).** CTO: agrees with fail-closed, `--no-use-dot`, realpath exec; flagged (a) CPU load ~5× the failed-layout path and slot-wait outside the 25 s timer, (b) the `--unshare-*` subset test alone does not cover mount ops or AppArmor — recommended a canary row, (c) pin `LANG`, (d) record bwrap version, (e) measure RSS. Folded: (a) slot-wait bound + `queueWaitMs` + one pool per process, (b) boot self-probe = a real render through the exact argv in the real container, (c) `--setenv LANG C.UTF-8`, (e) 183 MiB / 366 MiB. (d) changed at deepen: the version is pinned by the image (bookworm `bubblewrap` 0.8.0, stated in the ADR amendment) and every Sentry event carries the release, so no `bwrap --version` spawn. CPO: approved with 4 conditions (Domain Review).

**Advisor consult (Phase 4.5).** Folded: resolve binaries lazily; bound the whole render budget (Phase 2 item 8); land the `--no-use-dot` + views gate in its own commit so a latency/memory regression can be reverted without undoing the sandbox; views-less source measured. Not folded: deploy-gating the probe (Alternatives).

**Functional overlap.** Community-registry discovery skipped: an internal hardening of one spawn and one banner line; no skill/agent could implement or replace it.

## User-Brand Impact

- **If this lands broken, the user experiences:** every C4 diagram save (Code tab with `c4-edit` ON, or a Concierge `edit_c4_diagram` edit) commits the source but the diagram never updates, and the banner/Concierge relays "diagram not updated: the diagram could not be rendered this time. Save again to retry; if it keeps happening, contact support." Saves also take 4-15 s longer than today (a real layout instead of the failed one; measured 3.8-7.2 s single, 12.5 s for two concurrent), under the existing "Saving…" label, which already spans the whole PUT. For the banner half: a wrong or stale reason in the amber strip (a previous save's rate-limit message after a later success, or on another folder's diagram).
- **If this leaks, the user's data is exposed via:** (1) a sandbox allowlist that accidentally binds `/workspaces`, `/app`, `$HOME` or the parent `/proc` into the likec4 child — combined with any likec4 parser code-execution defect on tenant-authored `.c4` DSL, that child could read other tenants' workspace clones or the server's environment (Supabase service key, GitHub App key) through `/proc/<server-pid>/environ` (Guard 1); (2) the host following a symlink the child plants in `/c4-out` — a compromised child points `model.likec4.json` at another tenant's committed model, which passes both gates and is committed into the attacker's repo, or swaps an output subdirectory for a symlink while the host's `rm` walks it, deleting another tenant's files (Guard 5).
- **Brand-survival threshold:** `single-user incident` (same as #8623: the surface is a cross-tenant boundary on tenant-derived input). `soleur:engineering:review:user-impact-reviewer` runs at review.

## Implementation Phases

### Phase 1 — #8695 banner (UI copy + plumbing)

1. `components/kb/c4-diagnostics.tsx` (new) + `components/kb/c4-shared.tsx`
   - Move `C4Diagnostics` into `c4-diagnostics.tsx` (re-exported from `c4-shared.tsx`, so every import site is unchanged) together with `SUPERSEDED_LINE`, so tests can render the real banner without pulling CodeMirror/Mantine/`@likec4/diagram` through `vi.importActual("@/components/kb/c4-shared")`.
   - `C4Diagnostics` gains `staleDiagnostic?: string | null`. Line 1 unchanged ("Source edited — rendered diagram may be out of date"). Line 2: when `staleDiagnostic` is a non-empty string → the diagnostic with its first character upper-cased (a tiny local `capitalizeFirst`), rendered as a React text node; otherwise `SUPERSEDED_LINE` = "A newer change to the diagram source was saved before this one was rendered. Reopen the diagram to see the latest version." (Research Reconciliation row 6). Same `<p>`, same classes — no new element, no layout change. Update the doc comment (it still says the model "is regenerated … never at runtime", false since #4964).
   - `C4CodePanel` prop: `onSaved: (rerendered: boolean, diagnostic?: string) => void | Promise<void>`. In `save`, call `diagnostic ? onSaved(rerendered, diagnostic) : onSaved(rerendered)` so the existing `toHaveBeenCalledWith(true|false)` assertions keep their exact-arg meaning.
   - The no-diagnostic save message (`"Saved — diagram will update after re-render."`) becomes `"Saved — a newer change replaced this one before it was rendered."` (same false promise, same fix).
2. `components/kb/c4-workspace.tsx` and `components/kb/c4-diagram.tsx`: add `const [staleDiagnostic, setStaleDiagnostic] = useState<string | null>(null)`; in `onSaved={async (rerendered, diagnostic) => { … setStale(!rerendered); setStaleDiagnostic(!rerendered && diagnostic ? diagnostic : null); … }}` — every save overwrites the previous reason (CPO condition 1 / P3); pass `staleDiagnostic` to `C4Diagnostics`.
3. `components/kb/c4-workspace.tsx`: reset `stale`/`staleDiagnostic` when `dirPath` changes, with React's "adjust state on prop change" pattern (`const [prevDir, setPrevDir] = useState(dirPath); if (prevDir !== dirPath) { setPrevDir(dirPath); setStale(false); setStaleDiagnostic(null); }`). The KB page renders `C4Workspace` with no `key`, so today the state survives client navigation to another diagrams folder. Staleness is per model (one folder = one model), so views of the same folder keep it. Chosen over `key={c4DirPath}` on the page: unit-testable without mounting the dynamic KB page, and it does not remount the Concierge.
4. Tests (write first — `cq-write-failing-tests-before`):
   - `test/c4-shared.test.tsx` `C4Diagnostics`: (a) `stale` + `staleDiagnostic="diagram not updated: GitHub's rate limit…"` → text `Diagram not updated: GitHub's rate limit…` present AND `SUPERSEDED_LINE` absent AND `/precomputed/i` absent; (b) `stale` without diagnostic → `SUPERSEDED_LINE` present, `/will refresh|precomputed/i` absent; (c) `stale={false}` with a leftover `staleDiagnostic` → renders nothing; (d) a diagnostic containing `<script>` renders as literal text (no element).
   - `test/c4-shared.test.tsx` `C4CodePanel`: the existing "failed re-render WITH a diagnostic" case asserts `onSaved` called with `(false, "<the diagnostic>")`; the no-diagnostic cases keep `toHaveBeenCalledWith(false)` / `(true)`; the no-diagnostic save message matches the new text.
   - `test/c4-workspace.test.tsx` + `test/c4-diagram.test.tsx`: the `C4Diagnostics` mock imports the REAL component from `@/components/kb/c4-diagnostics` and wraps it in a div carrying `data-stale` / `data-stale-diagnostic`, so existing attribute assertions keep working and the visible text is real. Add a mock-panel button `c4-save-fail-diag` calling `onSaved(false, "diagram not updated: x")`; assert the attribute AND the rendered text `Diagram not updated: x` (in `c4-diagram.test.tsx`: after the `setTab("diagram")` switch, with the Diagram tab showing), then CLEARED after a following `c4-save-ok` and replaced by `SUPERSEDED_LINE` after a following `c4-save-fail`.
   - `test/c4-workspace.test.tsx` folder-change row: render with `dirPath` A, fail-with-reason, `rerender` with `dirPath` B → no banner; `rerender` back to A → still no banner.

### Phase 2 — #8696 sandbox + wasm pin (server)

All in `apps/web-platform/server/c4-render.ts` unless noted. Write the Guard 1-5 tests first (Guard Contract).

0. **Measurement gate (before coding the builder).** In the replica image of Research Insights → Measurements, run the repo's own diagrams (82 views) through the item 1 argv. Record in the ADR amendment: rc, view count, byte-identity vs the bare render, render latency, and peak usage of `/tmp`, `/c4-home` and `/dev/shm` (`du -sb` from a wrapper after the export). Set `SANDBOX_TMPFS_BYTES` = max(16 MiB, 4× the largest peak), default 64 MiB if all are under 16 MiB. Also measure, each as adopt-if-it-works (adopt → argv + Guard 1 in the same commit; fails → one line in the ADR residuals):
   - (a) `--json-status-fd <n>`: bwrap writes a `child-pid` record only after setup succeeds, and a payload inside the sandbox cannot `fstat` that fd number.
   - (b) `/usr/bin/prlimit --nproc=<N> --` as the first element of the command, inside the sandbox: a fork loop in the payload is capped while a concurrent host `spawn` still succeeds (per-user-namespace counting). Pick N = 4× the measured likec4 process count.
   - (c) `/usr/bin/choom -n 1000 --` wrapping `/usr/bin/bwrap` outside the sandbox (it needs `/proc`): the sandbox processes carry `oom_score_adj = 1000`, so the kernel picks the render over the server under the container `--memory` cap.
   - (d) `--size <SANDBOX_TMPFS_BYTES> --tmpfs /dev/shm` + `--remount-ro /dev`: node/likec4 still render.
   - (e) `/usr/bin/setpriv -d` as the payload prints `no_new_privs: 1`.

   If a core flag of item 1 breaks the render, drop it, record why, and edit Guard 1/Guard 4 in the same commit.
1. **Argv builder (pure, exported for tests):** `buildLikeC4SandboxArgv({ stageDir, nodeBin, likec4Entry, extraRoBinds, command })` returns: `--die-with-parent --new-session --unshare-user --unshare-pid --unshare-net --unshare-ipc --unshare-uts`, allowlisted root (`--ro-bind /usr /usr`, merged-usr `--symlink`s for `/bin /lib /lib64 /sbin`, `--ro-bind` of `/etc/ld.so.cache`, `/etc/passwd`, `/etc/group` with source == destination), each `extraRoBinds` path as `--ro-bind p p`, `--dev /dev`, `--size <SANDBOX_TMPFS_BYTES> --tmpfs /dev/shm`, `--size … --tmpfs /tmp`, `--size … --tmpfs /c4-home`, `--ro-bind <stageDir>/src /c4-sources` (= `STABLE_SOURCE_ROOT`), `--bind <stageDir>/out /c4-out`, `--remount-ro /dev`, `--remount-ro /` (last setup ops — close the writable root and `/dev` tmpfs, measured for `/`), `--chdir /c4-sources`, `--clearenv`, `--setenv` for exactly `PATH` (`dirname(nodeBin)` + `/usr/local/bin:/usr/bin:/bin`), `HOME=/c4-home`, `TMPDIR=/tmp`, `LANG=C.UTF-8`, plus `--json-status-fd <n>` if item 0(a) held, then `--` and `command`. The render passes `RENDER_COMMAND(nodeBin, likec4Entry)` = (item 0(b) prefix, if adopted) + `[nodeBin, likec4Entry, "export", "json", "--no-use-dot", "-o", "/c4-out/model.likec4.json", "."]`; Guard 1 pins that tail exactly at the spawn chokepoint, and `command` exists only so the real-bwrap isolation test can swap in a payload with everything before `--` identical. Plain `--ro-bind` for the three `/etc` files (fail loud); switch one to `--ro-bind-try` only if a CI runner is measured to lack it, adding that option to Guard 1's allowlist in the same commit.
2. **Binary resolution (lazy, memoized on success only, never at import):** `BWRAP_BIN = "/usr/bin/bwrap"` (absolute; never resolved through the server's `PATH`); `nodeBin = realpath(process.execPath)`; `likec4Entry = realpath(LIKEC4_BIN)` when absolute, else the first `realpath(join(dir, LIKEC4_BIN))` over `PATH` entries that resolves (prod: `/usr/local/lib/node_modules/likec4/bin/likec4.mjs`). Uses `fs/promises` `realpath` only (added to the test `fsMock`). `extraRoBinds` = the node install prefix (`dirname(dirname(nodeBin))`) and the likec4 package root, each only when not under `/usr/`. **Production pin:** with `NODE_ENV=production`, `realpath(BWRAP_BIN)`, `nodeBin` and `likec4Entry` must all be under `/usr/` and `extraRoBinds` must be empty, else the render returns `sandbox_error` detail `binary outside /usr` without spawning (a stray `LIKEC4_BIN` can never widen the prod sandbox). Resolution failure → `{ ok:false, reason:"sandbox_error", phase:"spawn", detail:"likec4 not resolvable" }` (phase `spawn` so the writer maps it to `INTERNAL_DIAGNOSTIC`).
3. **One spawn site; exit before cleanup:** `runLikeC4` keeps the only `spawn(` call. Its `(cmd, args, cwd)` comes from one function: sandboxed → `(BWRAP_BIN, buildLikeC4SandboxArgv({…, command: RENDER_COMMAND(…)}), dir)` (or `/usr/bin/choom` + `["-n","1000","--", BWRAP_BIN, …argv]` if item 0(c) held); dev opt-out (item 7) → `(nodeBin, [likec4Entry, "export","json","--no-use-dot","-o", <dir>/out/model.likec4.json, "."], <dir>/src)`. `stdio: ["ignore","ignore","pipe"]` (plus the status-fd pipe if adopted); bwrap's OWN env = the existing allow-list (`PATH, LANG, LC_ALL, TMPDIR` + `HOME: dir`) so bwrap never sees secrets. `mkdir(<dir>/out, 0o700)` before the spawn. Keep the `raw.split(srcDir).join(STABLE_SOURCE_ROOT)` rewrite (a no-op under bwrap, load-bearing in the dev opt-out). **stderr cap:** stop appending chunks once 512 bytes are held (the listener stays attached so the pipe keeps draining). **Timeout:** after `SIGKILL`, wait for the child's `close` event (fires only when every sandbox process holding the stderr pipe is gone) for up to `KILL_GRACE_MS = 5_000` before settling `timeout`; if `close` never comes, settle `{ reason:"sandbox_error", detail:"sandbox did not exit" }` and mark the stage so `renderC4Model`'s `finally` skips the `rm` (the stale-stage sweep removes it later). The recursive `rm` therefore never runs while a sandbox process can still rewrite `<dir>/out`.
4. **Classification:** `RenderReason` and `SpawnResult` gain `"sandbox_error"`: in sandboxed mode, any child `error` event (the spawned binary is bwrap, e.g. `ENOENT`); a non-zero exit with no `child-pid` status record (if item 0(a) held); otherwise a non-zero exit whose RAW stderr's first line (bytes before the first `\n`) starts with `bwrap:` followed by a space; plus the item 2/3 failures. Everything else non-zero stays `non_zero_exit`. `RenderReason` also gains `"layout_failed"` (item 6). Detail keeps the sanitized 512-byte stderr. The tag is diagnostic only: both reasons map to `INTERNAL_DIAGNOSTIC`, and no security or copy decision reads it. Under the plan's threat model a compromised child CAN forge the first-line form (it writes its own stderr), which is why the status fd is preferred where it measures clean. The worst a forged tag does is mislabel a Sentry event, and AC-P1's `sandbox_error` count must be read with that in mind.
5. **Output read (P8, Guard 5):** replace `readFile(tmpOut)` with `readRenderOutput(outDir)` (exported, with `RAW_MODEL_READ_CAP` = 20 MiB; the writer's 4 MiB `MAX_C4_MODEL_BYTES` still caps the canonical bytes it commits): `open(<outDir>/model.likec4.json, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)` (`constants` from `node:fs`, `open` from `node:fs/promises`; no pre-open `lstat`), `fh.stat()` must be a regular file with `size ≤ RAW_MODEL_READ_CAP`, then `readFile(fh, "utf8")` and `fh.close()` in a `finally`. Symlink (`ELOOP`), FIFO/dir/socket, oversize, or absent → `io_error` detail `model output rejected: <why>`. At read time the child's pid namespace is gone (the success path settles on `close`). Hard links into `/c4-out` fail with `EXDEV` (link(2) across mounts).
6. **Views gate (P7):** after the elements gate, require `model.views` to be a non-empty plain object; otherwise `{ ok:false, reason:"layout_failed", phase:"spawn", detail: "model has <n> elements and no views" + stderr }`. A successful layout always emits at least `index` (measured), so zero views is always our layout failing, never the user's source (CPO condition 3). Give the two existing `views: {}` ok-path fixtures (Relevant files) an `index` view.
7. **Fail closed + dev opt-out:** `C4_RENDER_SANDBOX=off` selects the direct spawn (still `--no-use-dot`) ONLY when `NODE_ENV !== "production"`; in production the value is ignored. Both variables are read only in `c4-render.ts` (boundary row). There is no other path to an unsandboxed spawn.
8. **Render pool + slot-wait bound:** move `inFlight`/`waiters` to `globalThis[Symbol.for("soleur.c4RenderPool")]` (Research Reconciliation row 7) so both bundles share one `POOL_SIZE` (default 2 per process). `acquire()` gets `SLOT_WAIT_MS = 10_000`: on expiry it removes the waiter and the render returns `{ ok:false, reason:"timeout", phase:"spawn", detail: RENDER_SLOT_WAIT_DETAIL }` (exported; value `"render slot wait"`). The ok result gains optional `queueWaitMs` (optional so `c4-writer-concurrency.test.ts`'s mock needs no change). **Budget before the model commit:** stage ≤ 10 s (`STAGE_DEADLINE_MS`) + slot wait ≤ 10 s + spawn ≤ 25 s (`RENDER_TIMEOUT_MS`) + kill grace ≤ 5 s (timeout path only) + `rm` (≤ 3 retries × 100 ms) ≈ 50.3 s worst case. `STAGE_SETTLE_GRACE_MS` (2 s) is only spent after a stage deadline, a path that never spawns. That leaves ~10 s for the two Contents-API commits and syncs inside the PUT route's `maxDuration = 60`, which is a platform hint only (`app/api/kb/c4/[...path]/route.ts`: the custom Node server does not enforce it).
9. **Writer changes (`c4-writer.ts`):** (a) the non-`unsafe_source` render failure becomes `reportSilentFallback(null, { feature: "c4-rerender", op: "render", message: "c4 re-render failed: " + render.reason, tags: { reason, phase, detail_class }, extra: { userId, relativePath, detail: render.detail } })`. `err = null` keeps the tags (Reconciliation row 9); the fixed message per reason restores grouping; `detail_class` is a low-cardinality tag computed in `c4-render.ts` and returned on the failure (`bwrap-setup`, `bwrap-enoent`, `outside-usr`, `not-resolvable`, `sandbox-no-exit`, `output-rejected`, `zero-views`, `slot-wait`, `likec4-exit`, `other`), so a new failure class opens a new Sentry issue and fires the first-seen email. (b) a `timeout` whose detail is `RENDER_SLOT_WAIT_DETAIL` reports through `warnSilentFallback(null, …)` (load, not a defect), same `INTERNAL_DIAGNOSTIC`. (c) the `op: "resync"` failure returns `{ rerendered:false, diagnostic: RETRY_DIAGNOSTIC }` (existing copy: the model is committed on GitHub but not on this clone, and a re-save re-syncs it). (d) `queueWaitMs` on the `c4_rerender` info log. `superseded()` is unchanged.
10. **Boot self-probe (P6):** export `verifyC4RenderSandboxOnce(): Promise<void>` from `c4-render.ts` (keeps `LIKEC4_BIN` single-module). It calls `renderC4Model(PROBE_STAGE)`, where `PROBE_STAGE` writes a module-constant fixture (`spec` + 2 elements + 1 relationship + one `view index`) and returns its `paths`/`sourceKey`. The probe is therefore a REAL export through the one spawn site and the exact render argv, exercising the `/c4-out` write, the `/etc/passwd` read and wasm layout (~4 s, once per start, holding one render slot).
    - **Success:** `Sentry.captureMessage("c4 render sandbox probe ok", { level: "info", tags: { event_type: "c4-sandbox-probe" }, extra: { durationMs, views } })` (the `server-startup` precedent), plus the pino info line `{ event: "c4_render_sandbox_probe", ok: true, … }`.
    - **Failure:** `reportSilentFallback(null, { feature: "c4-rerender", op: "sandbox-selfprobe", message: "c4 render sandbox self-probe failed: " + reason, tags: { reason, detail_class }, extra: { detail } })`.
    - **fd scan (same probe, host side):** read `/proc/self/fdinfo/*` and report, via `warnSilentFallback(null, { op: "sandbox-selfprobe-fds", extra: { count, kinds } })`, any fd ≥ 3 whose `flags` lack `O_CLOEXEC` (02000000 octal) and whose `/proc/self/fd/<n>` target is a file or directory. Only the count and the target kind are reported, never paths. This is what a spawned child would inherit, observed in the real server process (native modules such as `sharp` open their own fds). It is a boot-time snapshot; fds opened later are covered only by the CI H4 row.

    `server/index.ts` calls it inside the `server.listen` callback, only when `!dev`: `void Promise.resolve().then(verifyC4RenderSandboxOnce).catch((err) => reportSilentFallback(null, { feature: "c4-rerender", op: "sandbox-selfprobe", message: "c4 render sandbox self-probe threw", extra: { err: String(err) } }))`. It is never called before `listen` and never awaited, so a synchronous throw cannot reject `app.prepare().then`. It runs on every production container start, including the canary container before traffic cutover, under the real seccomp + AppArmor profile, and is report-only.
11. **Comments:** update the `c4-render.ts` header (SECURITY paragraph: residual resolved; check-update containment now comes from the sandbox — inside bwrap `isInsideContainer()` is false, so likec4's detached `check-update` spawn may start, but it has no network and dies with the pid namespace; do NOT add `CI=true`), the `RENDER_TIMEOUT_MS` comment (real layout 3-7 s at 2 CPUs), the pool comment (shared across bundles), and the Dockerfile likec4 comment (remove "~0.8s … no dot needed"; `--no-use-dot` is passed because in-container detection would otherwise pick the absent `dot`).

### Phase 3 — CI, ADR, census, follow-up

1. `.github/workflows/ci.yml` test-webplat: before "Run webplat tests", add a step `sudo -n apt-get update && sudo -n apt-get install -y --no-install-recommends bubblewrap && sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 && bwrap --version` (comment: ephemeral GH-hosted runner only, same guardrail as `scripts/sandbox-canary-regression.test.sh`; ubuntu-latest ships a newer bwrap than prod's 0.8.0, and every option the argv uses exists in 0.8.0 — measured), and add `C4_BWRAP_REQUIRED: "1"` to the run step's env.
2. `test/c4-render-tenant-config.test.ts`: bwrap availability = actually running `bwrap --unshare-user --unshare-pid --unshare-net --ro-bind /usr /usr -- /usr/bin/true` (not a PATH lookup). Available → the #8623 acceptance rows run THROUGH real bwrap, plus the H4 rows (Guard 1). Unavailable → FAIL under `C4_BWRAP_REQUIRED`; otherwise the file sets `C4_RENDER_SANDBOX=off` before importing c4-render (acceptance rows still exercise real likec4) and skips only the bwrap rows with an install hint.
3. `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`: new dated amendment "render child sandboxed; wasm layout pinned (#8696, #8695)". It covers:
   - the argv and why each mount/flag exists; the no-`/proc` rationale; fail-closed, the dev opt-out and the production `/usr` pin;
   - the host-side output read and exit-before-cleanup, citing AP-020 in spirit: `principles-register.md` scopes AP-020 to the hook-stdin envelope, so the amendment names this extension to child-written files rather than claiming the letter;
   - the boot self-probe; the `--use-dot` finding (production had been committing zero-view models since #4964); the views gate; the shared pool;
   - the item 0 measurements, bwrap 0.8.0 as the pinned version (CI runs newer), and the Alternatives table below.

   **Residuals:**
   - The disk-backed `/c4-out` is unsized: a compromised child can fill disk for ≤ 25 s.
   - Memory is bounded by the container `--memory` cap, not per render; process count too if item 0(b)/(c) did not hold.
   - The child can create nested user namespaces (seccomp allows `CLONE_NEWUSER`, `--disable-userns` fails), so kernel privilege-escalation bugs remain in scope. This is equally exposed by the agent sandbox, so it is not a regression.
   - The first-line classification is forgeable (item 4).

   Edit the 2026-09-24 **Residuals** paragraph to point at the new amendment. Follow `soleur:architecture` conventions.
4. **Zero-view census (CPO condition 4), read-only:** before marking the PR ready, list GitHub App installations' connected repos (existing App-token helper, read-only `GET` only) and for each fetch `knowledge-base/engineering/architecture/diagrams/model.likec4.json`; count files with ≥1 element and 0 views, split internal (jikig-ai org) vs external. Record the counts (never content) in the PR body. If any external repo is affected, file a tracking issue for a one-time re-render and a `/project` "has elements but no views" diagnostic (milestone per `knowledge-base/product/roadmap.md`); if all internal, record that here.
5. **Follow-up issue (`wg-when-deferring-a-capability-create-a`):** file "C4 workspace: reload the diagram and clear the stale banner when a Concierge `edit_c4_diagram` completes for this folder" (pre-existing: `C4Workspace` has no listener for Concierge edits, banner or not), with the re-evaluation criterion "when the Concierge tool result is exposed to the KB page", milestoned per the roadmap. Link it in the PR body.

## Files to Edit

- `apps/web-platform/server/c4-render.ts` — Phase 2 items 1-8, 10, 11.
- `apps/web-platform/server/c4-writer.ts` — Phase 2 item 9.
- `apps/web-platform/server/index.ts` — Phase 2 item 10 call inside `server.listen`.
- `apps/web-platform/components/kb/c4-shared.tsx` — Phase 1 item 1 (re-export, `C4CodePanel` changes).
- `apps/web-platform/components/kb/c4-workspace.tsx`, `apps/web-platform/components/kb/c4-diagram.tsx` — Phase 1 item 2; `c4-workspace.tsx` also item 3.
- `apps/web-platform/Dockerfile` — likec4 comment only.
- `.github/workflows/ci.yml` — Phase 3 item 1.
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` — Phase 3 item 3.
- `apps/web-platform/test/c4-render.test.ts` — spawn assertions move to the bwrap argv (`lastSpawn()[0] === "/usr/bin/bwrap"`, tail after `--` = `RENDER_COMMAND`); `fsMock` gains `open` (returning a `{ stat, close }` handle) and a `realpath` that answers by input path; `mkdtemp` returns a counter-suffixed path; the two `views: {}` fixtures get an `index` view; plus the Guard 1-3 and Guard 5 unit rows that need the spawn/fs mocks.
- `apps/web-platform/test/c4-render-boundary.test.ts` — row 1's expected list becomes `constants, lstat, mkdir, mkdtemp, open, readFile, readdir, realpath, rm, writeFile` (why: `constants`/`open` for the no-follow read, `realpath` for binary resolution, `writeFile` for the probe fixture), in the same commit as the imports. Add rows: exactly one `spawn(` call site in c4-render.ts; `C4_RENDER_SANDBOX` and the sandbox `NODE_ENV` decision read only in c4-render.ts; in comment-stripped `server/index.ts`, `verifyC4RenderSandboxOnce` appears only inside the `server.listen(` callback body under a `!dev` guard.
- `apps/web-platform/test/c4-render-tenant-config.test.ts` — Phase 3 item 2 + the H4 rows.
- `apps/web-platform/test/c4-writer-rerender.test.ts` — `sandbox_error`/`layout_failed` → `INTERNAL_DIAGNOSTIC`; `reportSilentFallback` called with `null` and the fixed message, tags `reason` + `detail_class`, `extra.detail`; slot-wait → `warnSilentFallback`; AC2b also asserts `rerenderDiagnostic === RETRY_DIAGNOSTIC`; a table-driven row asserting that every `rerendered:false` return except `superseded("sources-changed")` carries a diagnostic.
- `apps/web-platform/test/c4-shared.test.tsx`, `apps/web-platform/test/c4-workspace.test.tsx`, `apps/web-platform/test/c4-diagram.test.tsx` — Phase 1 item 4.

## Files to Create

- `apps/web-platform/components/kb/c4-diagnostics.tsx` — `C4Diagnostics` + `SUPERSEDED_LINE` (Phase 1 item 1; moved, re-exported from `c4-shared.tsx`).
- `apps/web-platform/test/c4-render-sandbox.test.ts` — mocked `node:child_process` + `node:fs/promises`: Guard 1 (a test-local pure `checkSandboxArgv(argv, ctx) → reasonCode | "ok"` over the spawn mock's ACTUAL args), Guard 3, Guard 4, probe unit rows (success Sentry info event, failure event with `err = null`, fd-scan report shape, a throwing resolution never rejecting the caller).
- `apps/web-platform/test/c4-render-output-read.test.ts` — REAL filesystem, no mocks, no bwrap: Guard 5 against `readRenderOutput`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) matched no body containing any planned path (`server/c4-render.ts`, `server/c4-writer.ts`, `components/kb/c4-shared.tsx`, `c4-workspace.tsx`, `c4-diagram.tsx`, `.github/workflows/ci.yml`, `ADR-050`, `c4-render`).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Hide banner line 2 when a diagnostic is present | In `c4-diagram.tsx` the save switches to the Diagram tab and unmounts the only place the reason is shown; hiding leaves "may be out of date" with no cause or action (CPO agreed). |
| Client re-fetches `/project` a few times after a supersede | New client polling for a rare path whose newer change may never be rendered (a direct push); honest copy covers it without new behaviour. |
| `--ro-bind / /` then mask `/workspaces`, `/app`, `/home`, `/mnt` (deny-list root) | A deny-list misses the next mount added to the container; the allowlist root (`/usr` + 3 `/etc` files) is closed by construction and measured sufficient. |
| `--proc /proc` (new procfs for the new pid ns) | EPERM in this Docker setup (measured). |
| Bind the parent `/proc` like the SDK argv | Exposes `/proc/<server-pid>/environ` — the exact exposure #8696 exists to remove. |
| `--disable-userns` | Fails here: `cannot open /proc/sys/user/max_user_namespaces: Read-only file system` (measured). |
| `RLIMIT_AS` / an outside-the-sandbox `RLIMIT_NPROC` | `RLIMIT_AS` breaks V8/wasm, which reserve large virtual ranges; an NPROC limit set outside the sandbox counts the uid the server also runs as. The inside-the-sandbox `prlimit --nproc` and the `choom` OOM priority are measured in Phase 2 item 0 instead. |
| Container `--pids-limit` in `ci-deploy.sh` | A prod host config change for every workload in the container; out of scope for a render hardening. Recorded as a residual if item 0(b) does not hold. |
| Child writes the model to stdout instead of a bound `/c4-out` | Removes the writable host bind, but `/dev/stdout` resolves through `/proc/self/fd`, which the sandbox does not have; unmeasured. Guard 5 closes the read side instead. |
| Add the C4 argv as a row in the deploy sandbox canary (CTO suggestion) | Couples deploy rollback to a new, unproven probe (learning 2026-06-04: dark-launch report-only first) and needs the builder importable from `scripts/sandbox-canary.mjs`. The boot self-probe gives the same fidelity (real render, exact argv, real container, real seccomp + AppArmor, every start incl. the canary container) without gating. Promotion criterion: after the probe has logged ok on real deploys with zero `op=sandbox-selfprobe` failures, a follow-up may add it to the canary as a gate. |
| Dedicated IaC Sentry alert rule for `reason=sandbox_error` | The Sentry-default first-seen route already emails the operator on a new issue; `detail_class` makes each failure class a new issue. A new `sentry_alert` would also move the rule counts gated by `c4-count-parity`. |
| Fall back to an unsandboxed spawn when bwrap fails | Turns every sandbox break into a silent downgrade; fail closed instead (P5). |
| Install graphviz `dot` in the image instead of `--no-use-dot` | Adds an apt package and a second layout engine that differs from the one the plugin's own regenerator (`plugins/soleur/scripts/render-c4-model.sh`, run outside containers → wasm) uses, so server and repo renders could diverge. |

## Risks & Mitigations — Precedent Diff (deepen-plan 4.4)

| Pattern | Precedent | This plan | Diff |
|---|---|---|---|
| No-follow read of an untrusted-writer file | `server/dsar-export.ts` workspace walk: `openSync(abs, O_RDONLY \| O_NOFOLLOW)` → `fstatSync(fd).isFile()` → read from the fd; `server/context-queries-hook.ts`: `readFileSync(p, { flag: O_RDONLY \| O_NOFOLLOW })` | async `open(…, O_RDONLY \| O_NOFOLLOW \| O_NONBLOCK)` → `fh.stat()` isFile + size cap → `readFile(fh)` | Adds `O_NONBLOCK` (FIFO) and a size cap. `context-queries-hook.ts` avoided `fs.open` because CodeQL `js/insecure-temporary-file` flagged it when a test fixture's `mkdtemp(os.tmpdir())` reached the sink; our staging root is under `~/.cache` (`c4-staging-root.ts`), but if CodeQL flags `readRenderOutput`, dismiss with that citation rather than dropping the `fstat` (the `readFileSync` form cannot check the type or size before reading). |
| State shared across the two server bundles | `_cron-claude-eval-substrate.ts` `IN_FLIGHT_KEY = Symbol.for("soleur.claudeEvalInFlight")` on `globalThis` | `Symbol.for("soleur.c4RenderPool")` holding `{ inFlight, waiters }` | Same shape; ours is a counter + queue, not a map. |
| Boot one-shot check | `readiness.ts` `verifyWorkspacesMountOnce()` (sync, before `listen`, `reportSilentFallback(null, …)`) | async, inside `server.listen`, `void`-ed | Moved after `listen` because it spawns and takes ~4 s; same `err = null` reporting. |
| Boot liveness event | `index.ts` `Sentry.captureMessage(…, { level: "info", tags: { event_type: "server-startup" } })` | same call, `event_type: "c4-sandbox-probe"` | None. |

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-050** (new dated amendment; the 2026-09-24 Residuals paragraph points to it). Decision: the likec4 render child runs in a render-only bwrap with an allowlisted root, no network, no `/proc`, cleared env, read-only root with sized tmpfs, fail-closed, with a report-only boot self-probe; the host reads the output only through a no-follow, size-capped fd and cleans up only after the sandbox has exited; wasm layout pinned by `--no-use-dot`; zero-view exports refused. Content per Phase 3 item 3.

### C4 views

No C4 element or relationship change. Checked against all three files (`model.c4`, `views.c4`, `spec.c4`): external actors (founder / tenant repo owner) unchanged; external systems (GitHub — the `api -> github` edge prose describing "render in a private staging dir … the repo's likec4 config, symlinks and submodules are refused … does not read the workspace clone (ADR-050 amendment 2026-09-24)" stays true; Sentry — the boot probe reuses the existing api-container Sentry emission path); containers/data stores: the render stays inside the `api` container and writes no new store; access relationships unchanged. `bash plugins/soleur/test/c4-count-parity.test.sh` → `Passed: 12 Failed: 0` (run 2026-09-24 on this branch), and the plan adds no Sentry rule, so no edge cardinality moves.

### Sequencing

ADR amendment ships in this PR.

## Observability

```yaml
liveness_signal:
  what: "Sentry info event 'c4 render sandbox probe ok' (tag event_type=c4-sandbox-probe, release-tagged) emitted once per production container start by verifyC4RenderSandboxOnce after a real fixture render; one per server-startup event of the same release"
  cadence: "every production container start (deploy, canary, restart)"
  alert_target: "failure path only: Sentry issue (feature=c4-rerender, per reason/detail_class) -> Sentry-default first-seen high-priority route -> operator email"
  configured_in: "apps/web-platform/server/c4-render.ts (verifyC4RenderSandboxOnce, renderC4Model) and apps/web-platform/server/index.ts (call inside server.listen)"
error_reporting:
  destination: "Sentry web-platform project via reportSilentFallback / warnSilentFallback with err=null (captureMessage path, tags preserved), DSN from the container env"
  fail_loud: "Sentry error event: feature=c4-rerender, op=render|sandbox-selfprobe, message 'c4 re-render failed: <reason>' or 'c4 render sandbox self-probe failed: <reason>', tags reason + detail_class, extra.detail = sanitized 512-byte stderr"
failure_modes:
  - mode: "bwrap cannot create namespaces (seccomp profile edit, AppArmor profile drift, host userns sysctl drift)"
    detection: "boot self-probe in the container itself -> reportSilentFallback(null) -> Sentry (layer 5 release context) and the pino error line -> Vector app_container_warn_filter -> Better Stack (layer 3); every later save emits reason=sandbox_error detail_class=bwrap-setup the same way"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "bwrap missing, or bwrap/node/likec4 resolved outside /usr in production"
    detection: "reason=sandbox_error detail_class=bwrap-enoent|outside-usr|not-resolvable at boot probe and per save; Sentry (layer 5) + pino error -> Vector -> Better Stack (layer 3)"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "likec4 or node cannot run inside the allowlisted root (missing /etc file, tmpfs too small, node prefix not bound)"
    detection: "boot self-probe real export fails -> reason sandbox_error|non_zero_exit|io_error|layout_failed with detail_class; Sentry (layer 5) + pino error -> Vector -> Better Stack (layer 3)"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "layout failure (zero views), e.g. a future likec4 bump changes layout defaults"
    detection: "views gate -> reason=layout_failed detail_class=zero-views per save and at boot; model not committed; Sentry (layer 5) + Better Stack via Vector (layer 3)"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "child leaves a symlink / FIFO / oversize file as the model output, or does not exit after SIGKILL"
    detection: "reason=io_error detail_class=output-rejected, or reason=sandbox_error detail_class=sandbox-no-exit; model not committed, stage left for the sweep; Sentry (layer 5) + Better Stack via Vector (layer 3)"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "render slot starvation under burst saves"
    detection: "warnSilentFallback(null) reason=timeout detail_class=slot-wait -> Sentry warning (layer 5) + pino warn -> Vector -> Better Stack (layer 3); queueWaitMs on the c4_rerender log"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "probe never runs for a started server (dev true in prod, listen callback path changed)"
    detection: "AC-P1 read: count of event_type:c4-sandbox-probe events != count of event_type:server-startup events for the release (both Sentry events, layer 5)"
    alert_route: "soleur:postmerge AC-P1 verdict for the deploy (no standing alert; the boundary-test row pins the call site pre-merge)"
  - mode: "server process holds a non-CLOEXEC file/dir fd that a spawned child would inherit"
    detection: "boot probe fd scan -> warnSilentFallback(null) op=sandbox-selfprobe-fds -> Sentry warning (layer 5) + pino warn -> Vector -> Better Stack (layer 3)"
    alert_route: "Sentry-default first-seen route -> operator email"
logs:
  where: "container stdout (pino JSON) -> journald -> Vector (apps/web-platform/infra/vector.toml app_container_warn_filter: WARN+ only) -> Better Stack; info lines (c4_rerender, the probe's ok line) stay in the container journal, so the probe's success signal is the Sentry info event"
  retention: "Better Stack source retention for the web-platform source; Sentry event retention for the error path and the probe event"
discoverability_test:
  command: "grep -c -e 'event: \"c4_render_sandbox_probe\"' apps/web-platform/server/c4-render.ts"
  expected_output: "1"
```

The discoverability probe confirms the one emitter of the probe's event name. It deliberately declares no `credentials_required`: declaring one moves the `BASELINE_DECLARED_PROBES` ratchet in `plugins/soleur/test/preflight-discoverability-test.test.ts` the moment this plan is committed. The production read runs in `soleur:postmerge` with its own credentials (AC-P1).

## Guard Contract

### Guard 1 — likec4 child mount/env/namespace closure

**Property.** Every likec4 exec in production (saves and the boot probe — both through the one spawn site) goes through `/usr/bin/bwrap` with exactly the allowlisted mounts at pinned sources, the Guard 4 namespace set, no `/proc`, read-only `/` and `/dev`, every tmpfs sized, and no environment beyond `PATH, HOME, TMPDIR, LANG`; the only writable bind from the host is `/c4-out` (the sized tmpfs mounts are sandbox-private).

**Assembly.** One spawn site in `server/c4-render.ts` (`runLikeC4`), used by saves and by `verifyC4RenderSandboxOnce` via `renderC4Model`. The chokepoint is the `(cmd, args)` passed to `spawn`, observed through the `node:child_process` mock, NOT the builder's return value (a mount added at the call site bypasses the builder). The `fs/promises` mock's `realpath` answers by input path with prod-shaped results (`/usr/bin/bwrap`, `/usr/local/bin/node`, `/usr/local/lib/node_modules/likec4/bin/likec4.mjs`), `LIKEC4_BIN` is stubbed absolute, and `mkdtemp` returns `<root>/c4-render-<n>` from a counter, so the expected argv is deterministic and `extraRoBinds` is empty. A test-local pure `checkSandboxArgv(argv, { stageDir, root })` returns a reason code or `ok`, and every row asserts the specific code:

- It parses the argv up to `--` against an OPTION ALLOWLIST with arities (`--ro-bind 2, --bind 2, --symlink 2, --tmpfs 1, --size 1, --dev 1, --remount-ro 1, --chdir 1, --setenv 2, --clearenv 0, --die-with-parent 0, --new-session 0, --unshare-user 0, --unshare-pid 0, --unshare-net 0, --unshare-ipc 0, --unshare-uts 0`, plus `--json-status-fd 1` if Phase 2 item 0(a) held). Any other option (`--bind-try`, `--dev-bind`, `--proc`, `--ro-bind-try`, `--overlay`, `--share-net`, `--dir`, …) is `forbidden-option`.
- Mount destinations must equal the allowlist set exactly (set identity, not a count).
- Sources are pinned. `/usr`, the three `/etc` files and every extra ro-bind have source == destination. `/c4-sources`' source is `<X>/src` and `/c4-out`'s source is `<X>/out` for the SAME `X`, which must equal the first `mkdtemp` result and start with `c4RenderStagingRoot()`.
- Ordering: every `--tmpfs` is immediately preceded by `--size <SANDBOX_TMPFS_BYTES>`, and `--remount-ro` appears exactly for `/dev` and `/`, after every mount op.
- The tail after `--` equals `RENDER_COMMAND` exactly, and `cmd` is `/usr/bin/bwrap` (or the `choom` wrapper around it, if adopted).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | builder adds `--bind /workspaces /workspaces` | RED `extra-destination` |
| 2 | builder adds `--ro-bind / /` | RED |
| 3 | builder adds `--proc /proc`, or `--ro-bind /proc /proc` | RED |
| 4 | source bind changed from `--ro-bind` to `--bind` | RED `writable-bind` |
| 5 | `--unshare-net` removed, or `--share-net` added | RED |
| 6 | `--clearenv` removed, or `--setenv SUPABASE_SERVICE_ROLE_KEY x` added | RED |
| 7 | a compliant `--ro-bind /usr /usr` followed by a SECOND bind `--ro-bind /app /app` | RED |
| 8 | render site splices `"--bind", "/home", "/home"` into the argv BEFORE `--` at the `spawn(` call, builder untouched | RED `extra-destination` (not the tail check) |
| 9 | source swap with destinations intact: `--ro-bind /workspaces /c4-sources`, `--bind /tmp /c4-out`, `--ro-bind /app /usr`, or `/c4-out` source from the second `mkdtemp` result | RED `source-mismatch` (each) |
| 10 | `--remount-ro /` or `--remount-ro /dev` removed, or moved before a mount op | RED `order` |
| 11 | command tail changed: `--no-use-dot` dropped, or `-o` pointed outside `/c4-out` | RED `tail` |
| 12 | guard's own dispatch: the parser returns zero options (e.g. reads the argv after `--`) | RED (asserts ≥ 25 parsed options and that `--` was found) |
| 13 | production pin removed: `NODE_ENV=production` with `realpath` of node (or bwrap) mocked to `/opt/...` still spawns | RED (must be zero spawns and `sandbox_error` `binary outside /usr`) |
| 14 | a `--tmpfs` without its `--size`, or with a different size | RED `unsized-tmpfs` |
| 15 | `BWRAP_BIN = "bwrap"` (PATH lookup) | RED (`cmd` must be `/usr/bin/bwrap`) |
| 16 | binaries resolved at import, or a failed resolution memoized | RED (rejecting `realpath` → zero calls at import and `likec4 not resolvable` on the first render; fixed mock → the next render spawns) |

**Harness rows:**

- (H1) must-RED, built from the observed passing argv with one splice: the forbidden bind in the LAST option position before `--`, so a parser that stops early cannot pass.
- (H2) must-PASS: two independent `--ro-bind` ops swapped (order among binds is free; the ordering rules above are the only order constraints).
- (H3) must-PASS with `NODE_ENV=test`: an `extraRoBinds` of `/opt/hostedtoolcache/node/22/x64` as `--ro-bind p p` passes, while the same path as `--bind`, or with a different destination, is RED with the expected code.
- (H4) real bwrap, in `c4-render-tenant-config.test.ts`, positive controls first. The test creates a sentinel file under a fresh `mkdtemp(os.tmpdir())` directory, sets `C4_SANDBOX_SENTINEL=<random>` in its own env and holds the sentinel open. On the host it proves the file is readable and that `/proc/<test pid>/environ` contains the sentinel. It then spawns `/usr/bin/bwrap` with the builder's argv (a stage under a test `C4_RENDER_STAGING_ROOT`, only `command` swapped) and the test's FULL env.
  - A `node -e` payload reports: sentinel file unreadable, `/proc` absent, `/proc/<test pid>/environ` unreadable, sentinel env var absent, writes to `/c4-sources`, `/` and `/dev` fail, `http.get` fails with `ENETUNREACH`, and no fd 3..255 `fstat`s as a file/dir with the sentinel's `ino`.
  - A `/usr/bin/setpriv -d` payload prints `no_new_privs: 1`.
  - A third payload plants `/c4-out/model.likec4.json` as a symlink to the sentinel, and the host's `readRenderOutput` returns `io_error`.

**Anchor.** The allowlist lives in the test, not derived from the builder; weakening needs the test and the builder edited together, which review sees as one diff. The ADR-050 amendment names the allowlist so a reviewer can compare against an artifact outside the test.

### Guard 2 — no zero-view model is ever returned ok

**Property.** `renderC4Model` returns `ok:true` only when `elements` AND `views` are non-empty plain objects.

**Assembly.** `renderToValidatedModel` is the only producer of `{ ok:true, json }`; the test drives it through `renderC4Model` with the fs/spawn mocks.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove the views gate | RED (fixture `{elements:{a:{}}, views:{}}` must be `layout_failed`) |
| 2 | gate on truthiness (`if (!model.views)`) | RED (fixture `views: {}` is truthy) |
| 3 | gate via `Object.keys(views).length` without the plain-object check | RED (fixtures `views: ["x"]` and `views: "x"`) |
| 4 | map zero views to `empty_model` instead of `layout_failed` | RED (writer must return `INTERNAL_DIAGNOSTIC`, not the "empty or invalid" copy) |

**Harness rows:** must-PASS `VALID_MODEL` (2 elements, 2 views); must-PASS a model with elements and exactly one view `index`.

### Guard 3 — no unsandboxed spawn in production

**Property.** With `NODE_ENV=production`, no code path spawns likec4 (or node) directly — including on bwrap `ENOENT`, bwrap EPERM, resolution failure, or `C4_RENDER_SANDBOX=off`.

**Assembly.** The one spawn site and the `(cmd, args, cwd)` selector that feeds it; the `C4_RENDER_SANDBOX`/`NODE_ENV` reads (only in c4-render.ts, boundary row). Each row stubs env with `vi.stubEnv` and re-imports the module dynamically.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | on bwrap spawn `ENOENT`, retry with a direct likec4 spawn | RED (spawn mock: exactly one call, cmd `/usr/bin/bwrap`; result `sandbox_error`) |
| 2 | honour `C4_RENDER_SANDBOX=off` regardless of `NODE_ENV` | RED (production + off → the only spawn cmd is still `/usr/bin/bwrap`) |
| 3 | bwrap exit 1 with raw stderr `bwrap: Can't …` classified as `non_zero_exit` | RED (must be `sandbox_error`) |
| 4 | classify on any stderr line instead of the first | RED (raw stderr `Invalid /c4-sources/model.c4 …\nbwrap: x` + exit 1 must be `non_zero_exit`) |

**Harness rows:** must-PASS: `NODE_ENV=test` + `C4_RENDER_SANDBOX=off` → direct spawn, still carrying `--no-use-dot`.

### Guard 4 — namespace set is exactly the proven set

**Property.** The `--unshare-*` set in the C4 argv is exactly {user, pid, net, ipc, uts}. user/pid/net are a subset of the SDK-captured canary fixture (proved on every deploy); ipc/uts are proved in the real container by the boot probe (a real render through the same argv) and admitted by the seccomp CLONE_NEWUSER rule (measured).

**Assembly.** The spawn mock's observed argv vs `apps/web-platform/infra/sandbox-canary-argv.json` `bwrapSetupArgv` plus the literal {ipc, uts}.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | builder adds `--unshare-cgroup` or `--unshare-all` | RED |
| 2 | builder drops `--unshare-ipc` or `--unshare-uts` | RED |
| 3 | fixture edited to drop `--unshare-net` | RED |
| 4 | test reads a fixture path that does not exist / parses zero flags | RED (asserts the fixture's set is non-empty and contains `--unshare-user`) |

**Harness rows:** must-PASS: the current fixture (user, pid, net) + {ipc, uts}.

**Anchor.** The fixture is produced only by `scripts/sandbox-canary.mjs --capture` driving the real SDK and byte-verified by `--verify` in CI (ADR-079) — it cannot be hand-edited to widen this guard without the canary's own drift check going red.

### Guard 5 — the host never follows, over-reads, or deletes through the child's output

**Property.** `renderToValidatedModel` obtains the model bytes only from `readRenderOutput`, which returns bytes only for a regular file of at most `RAW_MODEL_READ_CAP`, opened with `O_NOFOLLOW | O_NONBLOCK`; and `renderC4Model`'s recursive `rm` of a stage runs only after the spawn settled on the child's `close`.

**Assembly.** `readRenderOutput(outDir)` is the only reader of `<dir>/out`; `c4-render-output-read.test.ts` drives it on the real filesystem. In `c4-render.test.ts`, a row asserts `open` is called with both flags and `readFile` is never called with a string path for the model, and a call-order row covers the timeout path's `rm`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `readFile(path)` instead of the fd | RED (fixture: `model.likec4.json` → symlink to a sentinel file holding a valid model; result `io_error` detail `model output rejected: symlink`, sentinel bytes never returned) |
| 2 | drop `O_NOFOLLOW` | RED (same fixture) |
| 3 | drop the regular-file check or `O_NONBLOCK` | RED (FIFO fixture: the call is raced against a 1 s timer and must return `io_error` first; `afterEach` opens the FIFO `O_WRONLY \| O_NONBLOCK` and closes it so a blocked reader never hangs the worker) |
| 4 | drop the size cap | RED (a `RAW_MODEL_READ_CAP + 1` byte sparse file must be `io_error` without reading it) |
| 5 | timeout path settles right after `SIGKILL` (no wait for `close`) | RED (mock child emits `close` 100 ms after `kill`; `rm` must be called after `close`, checked by mock call order under fake timers; a child that never emits `close` → `sandbox_error` `sandbox did not exit` and no `rm` of that stage) |

**Harness rows:** must-PASS: a regular file holding `VALID_MODEL`; must-PASS: a directory named `model.likec4.json` returns `io_error` (not a throw).

### Test-harness notes (apply to Guards 1-5)

- **Shared-pool row** (`c4-render.test.ts`). Instance A (fresh import) holds `POOL_SIZE` slots with children that never close. Instance B (after `vi.resetModules()` + re-import) renders; advance fake timers by `SLOT_WAIT_MS` with `advanceTimersByTimeAsync`. B must return `timeout` / `RENDER_SLOT_WAIT_DETAIL` with the spawn count still equal to `POOL_SIZE`. `afterEach` closes held children, asserts the pool is empty, and deletes the `Symbol.for("soleur.c4RenderPool")` key (learning: vitest cross-file leaks).
- **stderr cap row.** Stream 64 KiB in 1 KiB chunks. Assert, via a spy on the concat input, that the retained chunks total ≤ 512 bytes plus at most one chunk, and that `child.stderr.listenerCount("data") === 1` afterwards. The detail string's existing `.slice(0, 512)` alone would pass without the cap.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO — direction sound; biggest risk is the CPU cost of real layouts with the pool and slot-wait outside the 25 s timer; wants production-profile fidelity for the exact argv; pin locale; record bwrap version; measure RSS. Folding per Research Insights → Domain leader input. Review panel findings: Review Findings Disposition.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface) — copy-only exemption, see wireframe decision below

#### Findings

CPO sign-off: **approved with conditions**, all folded in:

1. Each save replaces or clears the previous reason — Phase 1 items 2-3 + test rows.
2. Sandbox start failure reaches Sentry with its own tag and alerts — `reason=sandbox_error` / `op=sandbox-selfprobe` with `detail_class`, first-seen email via the Sentry-default route, surfaced at container start by the boot probe (dedicated IaC rule not added — Alternatives; decision-challenge 2).
3. Zero-view causes separated — zero views is always `layout_failed` → internal copy, never "empty or invalid" (measured).
4. Census before relying on "the next save fixes it" — Phase 3 item 4.

CPO's optional no-reason line ("It will refresh once the new version finishes rendering.") was replaced at deepen by `SUPERSEDED_LINE` because nothing on the page refreshes (Research Reconciliation row 6); decision-challenge 5 asks CPO to re-confirm at review.

**Wireframe gate decision (`wg-ui-feature-requires-pen-wireframe`): exempt — copy-only.** The rule excludes "copy/style" changes, and `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` §Excluded lists "Pure copy or style tweaks with no structural/layout change". This change swaps the TEXT inside the existing second `<p>` of the existing amber strip (same element, same classes, same position, same show/hide condition `stale`), one save-message string, moves the unchanged component into its own file, and adds non-visual state plumbing. No new element, interaction, state surface, route, modal or layout. The `.tsx` files match the mechanical glob only because they host the banner. Explicit override naming the surface shipped without a new wireframe: **`C4Diagnostics` stale strip line 2 text (`components/kb/c4-diagnostics.tsx`, moved from `c4-shared.tsx`), the `C4CodePanel` no-diagnostic save message, and the `onSaved` plumbing + folder-change reset in `c4-workspace.tsx` / `c4-diagram.tsx`**. If a reviewer rejects the exemption, the fallback is `soleur:product:design:ux-design-lead` producing a `c4-stale-banner-diagnostic` Pencil file in the `kb-viewer` design folder (two states: with reason / without) before `soleur:work` Phase 1.

## Test Scenarios

Guard rows (Guard Contract) and Phase 1 item 4 are the test list; this section adds only flows neither covers.

- Banner, reason present: amber strip line 2 = `Diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.`
- Embedded viewer (`c4-diagram.tsx`): after a failed save the tab switches to Diagram and the real `C4Diagnostics` shows the reason text.
- Writer: resync failure after a committed model → `rerenderDiagnostic === RETRY_DIAGNOSTIC`; the Sentry call is `reportSilentFallback(null, …)` with message `c4 re-render failed: <reason>`, tags `reason` + `detail_class`, and `extra.detail` holding the stderr; a slot-wait timeout reports as a warning.
- Real bwrap + real likec4 (CI, `C4_BWRAP_REQUIRED`): the #8623 acceptance rows green through bwrap; a 2-element fixture renders with ≥ 1 view; H4.
- Boot probe: success emits the Sentry info event and the pino line; render failure → one Sentry event `op=sandbox-selfprobe` with reason + `detail_class` tags; a non-CLOEXEC file fd opened by the test before the probe produces one `op=sandbox-selfprobe-fds` warning with `count ≥ 1` and no path; a throwing resolution never rejects the caller.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Do NOT add `CI=true` to the child env (likec4 switches reporter; the writer's `Could not resolve` match breaks) — `c4-render.ts` header documents it; one learning says the opposite and is wrong for this binary.
- Do NOT pass a real `Error` to `reportSilentFallback`/`warnSilentFallback` on the new c4 paths: the pino mirror captures it first and Sentry drops the tagged capture (#8629). Use `err = null` and put the error text in `extra`.
- `toHaveBeenCalledWith(false)` in `c4-shared.test.tsx` compares ALL args: call `onSaved(rerendered)` (one arg) when there is no diagnostic.
- `c4-render.test.ts` mocks the WHOLE `node:fs/promises` module: every new import (`open`, `realpath`, `writeFile`) must be added to `fsMock` in the same commit, or the module under test gets `undefined`. The real-bwrap and real-fs rows therefore cannot live in a file with that hoisted mock — they go in `c4-render-tenant-config.test.ts` and `c4-render-output-read.test.ts`.
- GitHub runners' node is under `/opt/hostedtoolcache`, not `/usr`: without `extraRoBinds` the CI real-bwrap rows fail with `execvp … No such file`, which would look like a sandbox break. The production `/usr` pin applies only under `NODE_ENV=production`; vitest runs with `NODE_ENV=test`.
- bwrap processes setup ops in order: the two `--remount-ro` ops must come after every mount op, and `--size` binds only to the next `--tmpfs`.
- `choom` and anything else that needs `/proc` must run OUTSIDE the sandbox; `prlimit` works inside (syscall, no `/proc`).
- The file:// icon rewrite: under bwrap the stage path is already `/c4-sources`; keep the split/join for the dev opt-out path.

## Review Findings Disposition

Sources: `knowledge-base/project/specs/feat-one-shot-8695-8696-c4-banner-bwrap/spec-flow-findings.md` (SF), `plan-review-findings.md` (architecture = AR, Kieran = K), and the deepen round: security-sentinel (SEC), test-design-reviewer (TD), code-simplicity-reviewer (SIM), observability-coverage-reviewer (OBS), verify-the-negative (VN), learnings-researcher (LRN). Overlaps applied once.

| Finding | Sev | Disposition |
|---|---|---|
| SF1 / AR1 — host follows a child-planted symlink; FIFO hang; oversize read | P0 | Adopted: Phase 2 item 5, Guard 5, H4 third payload, ADR cites AP-020 in spirit. |
| SF2 — no resource bounds | P1 | Adopted: stderr cap (item 3), sized tmpfs + read-only `/` and `/dev` (items 0-1), stat-before-read (item 5), `prlimit --nproc` / `choom` measured (item 0). Rejected: `RLIMIT_AS`, container `--pids-limit` (Alternatives). Residuals in the ADR (Phase 3 item 3). |
| SF3 — "It will refresh" promises what the UI never does | P1 | Adopted: resync → `RETRY_DIAGNOSTIC` (item 9c); `SUPERSEDED_LINE` (Phase 1 item 1). Rejected: client re-fetch (Alternatives). |
| SF4 — Concierge edit while the banner is up changes nothing | P1 | Deferred with issue (Phase 3 item 5): pre-existing for every Concierge edit; needs chat-to-workspace wiring outside #8695's copy scope (decision-challenge 6). |
| SF5 / AR5 — boot probe proves too little | P1 | Adopted: real fixture render through the one spawn site (item 10). |
| SF6 / AR7 — real-bwrap isolation row vacuous on CI | P1 | Adopted: H4 with positive controls, sentinel file + env + test pid, fd sweep. |
| AR2 — Guard 1 pins destinations, not sources | P1 | Adopted: source pinning + row 9. |
| AR3 — `extraRoBinds` can widen the prod sandbox | P1 | Adopted: production `/usr` pin (item 2) + row 13. |
| AR4 — probe before `listen` can block boot | P1 | Adopted: inside `server.listen`, `void`-ed (item 10). |
| K1 — builder fixes the command tail | P1 | Adopted: `command` param; tail pinned (row 11). |
| K2 — spawn count (`bwrap --version`, opt-out) | P1 | Adopted: one spawn site for render, probe and opt-out (item 3); version spawn cut. |
| K3 — `fs/promises` mock breaks on new imports | P1 | Adopted: Files to Edit + Sharp Edges; resolution rows (row 16). |
| K4 — two `views: {}` fixtures go RED | P1 | Adopted: item 6. |
| K5 — real-bwrap row cannot share the hoisted-mock file | P1 | Adopted: `c4-render-tenant-config.test.ts`; Guard 5 in its own real-fs file. |
| SEC1 — `rm` runs while sandbox processes may be alive after a timeout | P1 | Adopted: wait for `close` before settling (item 3), Guard 5 row 5, budget updated (item 8). |
| TD1-TD4 — stderr-cap, source-pinning, shared-pool and NODE_ENV-flip rows could not go red | P1 | Adopted: Test-harness notes, `mkdtemp` counter (Guard 1 Assembly). TD4 moot: the module-load-read row was cut (SIM3). |
| OBS1 — info probe line never reaches Better Stack | P1 | Adopted: Sentry info event (item 10, Reconciliation row 8). |
| OBS2 — `new Error(…)` loses the tags to the pino mirror | P1 | Adopted: `err = null` everywhere new (item 9a, item 10, Sharp Edges). |
| OBS3 — failure modes lack a layer citation | P1 | Adopted: every `detection` names layers 3 and 5. |
| SF7 — AC2 proof uses a mocked `C4Diagnostics` | P2 | Adopted via TD10: real component from the new `c4-diagnostics.tsx` module. |
| SF8 — stale state leaks / disappears; zero-view committed models | P2 | Adopted: reset on `dirPath` change (Phase 1 item 3). Rejected: persisting the reason across page reloads (session-local like today's `stale`; the reason was also shown in the Code panel / Concierge). Deferred to the census: `/project` zero-view diagnostic (Phase 3 item 4). |
| SF9 — saves slower with no feedback | P2 | Latency stated (User-Brand Impact). Premise corrected: "Saving…" spans the whole PUT including the render; no new copy. |
| SF10 — Sentry grouping | P2 | Adopted: fixed message per reason + `detail_class` (item 9a). |
| SF11 — classify on raw stderr first line | P2 | Adopted: item 4, Guard 3 row 4; status fd preferred (SEC2). |
| AR6 — double bundle: version and pool per bundle | P2 | Adopted: shared pool; version capture cut; budget restated. |
| AR8 — kernel surface | P2 | Adopted: `--unshare-ipc/uts`, exact-set Guard 4, `--size`. Rejected: `--disable-userns` (measured failure). |
| K6-K10 — expected-set construction, resolution phase, CI apt/skip check, optional `queueWaitMs`, probe in dev | P2 | Adopted: Guard 1 Assembly, item 2, Phase 3 items 1-2, item 8, item 10. |
| SEC2 — child can forge the `bwrap:` first-line prefix | P2 | Adopted: `--json-status-fd` preferred where measured clean (item 0(a), item 4); sentence corrected; residual in ADR. |
| SEC3 — fork bomb / OOM kills the server; `/dev` tmpfs unsized | P2 | Adopted: item 0(b)-(d), argv (`/dev/shm` sized, `/dev` read-only), row 14. |
| SEC4 — nested userns reaches kernel bug surface | P2 | Adopted: ADR residual; `no_new_privs` proved in H4. |
| SEC5 — fd inheritance checked in the wrong process | P2 | Adopted: boot-probe fd scan in the real server process (item 10). |
| SEC6 — bwrap found via `PATH` | P2 | Adopted: `/usr/bin/bwrap`, in the prod pin, row 15. |
| TD5 — "sanitized" part of Guard 3 row 5 is an equivalent mutant | P2 | Adopted: row reworded (now row 4, "any line"). |
| TD6 — row 8 splice landed after `--` | P2 | Adopted: splice before `--`. |
| TD7 — harness fixtures can go red for the wrong reason | P2 | Adopted: `checkSandboxArgv` reason codes; must-RED fixtures built by one splice. |
| TD8 — unsized tmpfs, host-PATH-dependent realpath, resolution timing | P2 | Adopted: rows 14 and 16, `realpath` by input, absolute `LIKEC4_BIN` stub. |
| TD9 — FIFO row can hang the worker | P2 | Adopted: Guard 5 row 3 race + `afterEach` release; `RAW_MODEL_READ_CAP` exported. |
| TD10 — `vi.importActual(c4-shared)` is heavy | P2 | Adopted: `c4-diagnostics.tsx` module (Phase 1 item 1). |
| TD11 — no test owns the `index.ts` call site | P2 | Adopted: boundary row (Files to Edit). |
| OBS4 — a probe that never runs goes unnoticed | P2 | Adopted: AC-P1 startup-vs-probe count + failure mode. |
| OBS5 — AC-P1 not executable; detail unsearchable after the move | P2 | Adopted: AC-P1 names the endpoint, token and queries; `detail_class` tag. |
| SIM1 — split pool/slot-wait into its own issue | — | Rejected: the folded-in `--no-use-dot` fix is what makes renders 5× costlier in this PR, and the double bundle allows 4 concurrent layouts near the 25 s timeout; shipping the cost without the bound regresses save latency (decision-challenge 4 covers the scope fold). |
| SIM2 — merge Guard 4 into Guard 1 | — | Rejected: Guard 4's value is its anchor to the canary fixture that CI byte-verifies, which Guard 1's in-test allowlist does not have. |
| SIM3 — cut the "NODE_ENV read at module load" row | — | Adopted: row and requirement removed; production safety is carried by Guard 3 rows 1-2 and Guard 1 row 13. |
| SIM4 — always call `onSaved(rerendered, diagnostic)` | — | Rejected: the one-line ternary keeps every existing `toHaveBeenCalledWith(true\|false)` assertion unchanged. |
| SIM5 — census as postmerge | — | Rejected: CPO condition 4 asks for it before relying on the next save; it is read-only. |
| SIM6 — double guard on the probe; boundary row "stages only PROBE_STAGE" | — | Adopted: that boundary row dropped; the caller's `.catch` kept as the backstop for a synchronous throw (AR4). |
| SIM8 — restatement across sections | — | Adopted: measured-argv paragraph, Test Scenarios and Disposition now point instead of repeating. |
| SIM (claim) — pin "supersede is the only no-diagnostic return" | — | Adopted: table-driven writer row (Files to Edit). |
| VN — `"non_zero_exit"` literal also in `c4-writer-rerender.test.ts` | — | Adopted: RenderReason consumers paragraph corrected. |
| LRN — kb-share `lstat` TOCTOU, single-fd read, vitest module leaks | — | Adopted: Institutional learnings (deepen bullets), Guard 5, Test-harness notes. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 (#8695): `C4Diagnostics` with `stale` and a `staleDiagnostic` renders the diagnostic (first letter upper-cased) as line 2 and no refresh promise; without a diagnostic renders `SUPERSEDED_LINE`; Phase 1 item 4 `c4-shared.test.tsx` rows (a)-(d) green.
- [ ] AC2 (#8695): both parents clear/replace the reason on every save; the real `C4Diagnostics` text is asserted after the tab switch in `c4-diagram.test.tsx`; the folder-change row is green.
- [ ] AC3 (#8696): Guard 1 rows 1-16 and H1-H3 are encoded in `test/c4-render-sandbox.test.ts`, each asserting its reason code, and each was observed RED against its mutation during implementation.
- [ ] AC4 (#8696): Guard 3 rows green.
- [ ] AC5: Guard 2 rows green; `c4-writer-rerender.test.ts` maps `sandbox_error`/`layout_failed` to `INTERNAL_DIAGNOSTIC`.
- [ ] AC6: Guard 4 rows green.
- [ ] AC7: CI test-webplat installs bubblewrap, relaxes the userns sysctl, sets `C4_BWRAP_REQUIRED=1`, and `test/c4-render-tenant-config.test.ts` (acceptance rows through bwrap + H4 with its positive controls) runs (not skips) and passes on the PR.
- [ ] AC8: `verifyC4RenderSandboxOnce()` runs a real fixture render and is called inside `server.listen` only when `!dev`, never awaited (boundary row green). Unit rows cover: the success Sentry info event `event_type: "c4-sandbox-probe"` plus exactly one `event: "c4_render_sandbox_probe"` emitter (the discoverability probe prints `1`); the failure event via `reportSilentFallback(null, …)` with reason + `detail_class`; the fd-scan warning; and a throwing resolution not rejecting the caller.
- [ ] AC9: the Test-harness shared-pool row and slot-wait row are green; `c4_rerender` log carries `queueWaitMs`.
- [ ] AC10: ADR-050 amendment merged in this PR with the Phase 3 item 3 content; Residuals paragraph points to it; `plugins/soleur/test/c4-count-parity.test.sh` still green.
- [ ] AC11: zero-view census counts (internal vs external) recorded in the PR body; a tracking issue exists if any external repo is affected.
- [ ] AC12: Dockerfile and `c4-render.ts` comments corrected; the Phase 2 item 0 measurements and adopt/residual verdicts for (a)-(e) are recorded in the ADR amendment; `bash scripts/test-all.sh webplat` and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (tsc is the enumerator for any `RenderReason` consumer the grep missed).
- [ ] AC13: Guard 5 rows 1-5 green; resync failure returns `RETRY_DIAGNOSTIC`; the supersede-only table row green.
- [ ] AC14: the Phase 3 item 5 follow-up issue exists, is milestoned, and is linked in the PR body.

### Post-merge (automated in `soleur:postmerge`)

- [ ] AC-P1: over the 24 h after deploy, with `SENTRY_ISSUE_RO_TOKEN` from Doppler `soleur/prd` against `https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/` (the endpoint `scripts/sentry-issue.sh` documents as honouring tag queries on the RO token), GET with `field=count()` and `statsPeriod=24h`:
  - (1) `query=event_type:c4-sandbox-probe release:<deployed release>` equals (2) `query=event_type:server-startup release:<deployed release>`, and both are ≥ 1;
  - (3) `query=feature:c4-rerender op:sandbox-selfprobe` returns 0;
  - (4) `query=feature:c4-rerender reason:sandbox_error` returns 0, and any non-zero count is triaged by `detail_class` (a `bwrap-setup` count after a clean (3) may be a forged tag — item 4).

  All reads are HTTP GETs with no host access.

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
---

# fix(c4): staleness banner states the save diagnostic; likec4 render child runs inside bwrap with wasm layout pinned

## Overview

Two follow-ups to the C4 re-render security fix (#8623, merged 2026-09-24 as PR #8687), shipped together on one branch (draft PR #8732):

1. **#8695 (UI copy).** The C4 editor's staleness banner (`C4Diagnostics`, the amber `stale` strip in `apps/web-platform/components/kb/c4-shared.tsx`) always says the diagram "is precomputed" and "refreshes after the model is re-rendered" later. It shows that line even when the save response carries a `rerenderDiagnostic`, which means no refresh is coming until the user acts. Fix: line 2 shows the diagnostic itself (first letter capitalised) when one is present, and a plainer "will refresh" sentence when none is.
2. **#8696 (defence in depth).** The `likec4 export json` child spawned by `apps/web-platform/server/c4-render.ts` runs as the app container's uid with no sandbox, so a likec4 parser defect would reach `/workspaces` (every tenant's clone) and `/proc/<server-pid>/environ` (the server's secrets, readable by the same uid). Fix: exec the child inside bubblewrap with an allowlisted root (read-only `/usr`, read-only staged sources, one writable output dir), no network, no `/proc` at all, a cleared environment, and fail closed.

**Folded-in latent bug, found while measuring #8696 (see Research Reconciliation row 3).** likec4 1.50.0 defaults `--use-dot` to true when it detects a container (`/.dockerenv`). The runner image has no graphviz `dot`, so today's production render lays out every view with a missing binary: the export exits 0 with 80 elements and **0 views**, passes the elements-only gate, and is committed, which blanks the diagram. The fix pins wasm layout (`--no-use-dot`) and refuses a zero-view export (`layout_failed`, keeps the previous model).

## Research Reconciliation — Spec vs. Codebase

| # | Claim (issue / code comment) | Reality (measured 2026-09-24) | Plan response |
|---|---|---|---|
| 1 | #8696: bubblewrap is "already present in the runner image" | TRUE. `apps/web-platform/Dockerfile` runner stage installs `bubblewrap` (apt line with `git bubblewrap socat qpdf jq`); Debian bookworm package = **bwrap 0.8.0**. The container runs with `--security-opt seccomp=soleur-bwrap.json` + `apparmor=soleur-bwrap` (`apps/web-platform/infra/ci-deploy.sh`, `docker run` block) because the Agent SDK sandbox uses bwrap in prod, and the deploy canary replays the SDK argv (`--unshare-net`, `--unshare-pid`, `--unshare-user`) inside the canary container on every deploy (ADR-079). | Use the system `bwrap`; no image package change. Dockerfile edit is comment-only. |
| 2 | #8696: "no `/proc` of the parent" | `--proc /proc` is impossible in this container: `bwrap: Can't mount proc on /newroot/proc: Operation not permitted` (Docker's masked `/proc` paths; learning `security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`). The SDK works around it by binding the PARENT `/proc` (`--bind /proc /proc` in `sandbox-canary-argv.json`), which is exactly what #8696 forbids. | Mount no `/proc` at all. Measured: node + likec4 + wasm layout run fine without it. |
| 3 | `c4-render.ts` comment "Real prod model exports in <1s (verified 2026-06-05)" and Dockerfile "exits 0 with no dot on PATH, ~0.8s" | Both describe the FAILED-layout path. In a container, likec4's `--use-dot` defaults to `isInsideContainer()` (cli/index.mjs: option `use-dot` `default: w()`), so it uses `GraphvizBinaryAdapter`, finds no `dot`/`unflatten`, logs ~20k stderr lines and exports `views: {}`. With `--no-use-dot`: 82 views, 3.8-7.2 s at 2 CPUs. | Pin `--no-use-dot`; add a views gate; correct both comments; add a slot-wait bound (see Phase 2). |
| 4 | #8695: the banner "always says" the precomputed/refresh line | TRUE (`C4Diagnostics`, second `<p>`). Also: `components/kb/c4-diagram.tsx` `onSaved` calls `setTab("diagram")`, which unmounts `C4CodePanel` and its `Saved — <diagnostic>` header message, so in the embedded viewer the banner is the ONLY surface that could show the reason. | Reword (not hide) line 2 with the diagnostic. |
| 5 | #8695 Fix-Size "2 lines / 1 file" | The diagnostic never reaches `C4Diagnostics`: `C4CodePanel.onSaved(rerendered)` passes only a boolean, and both parents (`c4-workspace.tsx`, `c4-diagram.tsx`) hold only `stale: boolean`. | Thread the diagnostic through `onSaved` → parent state → a new optional `C4Diagnostics` prop (3 components, all copy/plumbing). |

## Research Insights

**Premise Validation.** #8695 and #8696 are OPEN (`gh issue view`), both labelled `deferred-scope-out`, both "Ref #8623". #8623 is CLOSED by PR #8687 (merged 2026-09-24T12:48Z). Every cited path exists on `origin/main`: `server/c4-render.ts` (468 lines; carries `// Residual: the child still runs as the app's uid (bwrap wrapping: #8696).`), `components/kb/c4-shared.tsx` (`C4Diagnostics`), ADR-050 amendment 2026-09-24 (**Residuals** paragraph names #8696 and #8695). ADR corpus grep for the mechanism: ADR-050 amendment lists "Rendering inside the bwrap agent sandbox" under **Alternatives rejected** — that rejected *replacing* staging with the AGENT sandbox on the save path; this plan keeps staging and adds a dedicated, render-only bwrap, which is what the same amendment's Residuals paragraph tracks as #8696. Not a rejected mechanism. ADR-079 records that a hand-rolled bwrap argv (#4932) false-rolled-back every deploy when used as a deploy GATE — this plan's argv is never a deploy gate (boot self-probe is report-only).

**Property List (Phase 0.6b).**

- P1. After a save whose re-render was skipped with a stated reason, the banner tells the user that reason and does not promise an automatic refresh.
- P2. After a save whose re-render is pending (no reason), the banner says it will refresh, in plain words.
- P3. A later save replaces or clears a previous save's reason (no stale "rate limit" after a success).
- P4. The likec4 child cannot read `/workspaces`, `/app`, the server's `/proc`, or `$HOME`; cannot write its input; has no network; inherits no server env.
- P5. A sandbox that cannot start fails the render closed (source still committed, user told), never degrades to an unsandboxed spawn in production, and reaches Sentry with a discriminating tag.
- P6. A sandbox break introduced by a host/profile/image change is visible within minutes of a container start, not only on the next tenant save.
- P7. The server never commits a layout-failed (zero-view) model.

**Cut List.** None of the issues' named mechanisms is redundant: bwrap already exists in the image (reused, not added); `rerenderDiagnostic` already exists server-side (reused verbatim, no new copy). Cut at planning: a new sandbox-canary row (P6 is covered by the boot self-probe — see Alternatives), a new IaC Sentry alert rule (the Sentry-default first-seen route already notifies on a new error group; a new rule would move the rule counts `c4-count-parity` gates on the Sentry notification edge in `model.c4`).

**Measurements (Phase 0.6c; faithful replica image).** Image: `node:22-slim@sha256:4f77a690…` (the runner stage digest) + `npm install -g likec4@1.50.0` + apt `bubblewrap socat` + `useradd --uid 1001 soleur`, run as `docker run --init --security-opt seccomp=apps/web-platform/infra/seccomp-bwrap.json --tmpfs /tmp` on this repo's own diagrams (82 views). AppArmor `soleur-bwrap` was NOT loaded (host lacks AppArmor); it allows `mount`/`umount`/`pivot_root` broadly, and the boot self-probe closes that residual in the real container. Scripts and logs: session scratchpad `bwrap-probe/probe*.sh`.

| Measurement | Result |
|---|---|
| bare spawn, prod env (`env -i PATH HOME TMPDIR`), no flag | rc 0, **0 views**, 20,303 stderr lines (`FAILED GraphvizBinaryAdapter … not found: dot`), 1.3-2.0 s |
| bare spawn `--no-use-dot` | rc 0, 82 views, 4.3-5.7 s |
| bwrap (argv below) `--no-use-dot`, 8 interleaved iterations vs bare | bwrap 3.8-5.2 s vs bare 4.5-5.7 s: **no measurable latency penalty**; bwrap setup alone 11 ms (10× `-- /bin/true`) |
| bwrap output vs bare output | **byte-identical** after the `/c4-sources` path rewrite |
| single render, `--cpus 2 --memory 2g` | 7.2 s, cgroup `memory.peak` 183 MiB |
| two concurrent renders (POOL_SIZE=2) | 12.5 s wall, `memory.peak` 366 MiB |
| `--proc /proc` | `Can't mount proc on /newroot/proc: Operation not permitted` |
| no `/etc/passwd` in sandbox | likec4 crashes at import: `uv_os_get_passwd returned ENOENT` (`atomically.mjs` calls `os.userInfo()`) → bind `/etc/passwd` + `/etc/group` read-only |
| isolation inside sandbox | `/workspaces`, `/app`, `/proc` absent; `touch /c4-sources/x` → Read-only file system; `http.get` → `ENETUNREACH` |
| SIGKILL of bwrap with a detached grandchild inside | 2 node processes before, **0 after** (pid-ns teardown + `--die-with-parent`) |
| broken source inside sandbox | rc 0, `Invalid /c4-sources/model.c4 … Could not resolve reference to ElementKind named 'foo'` on stderr (the writer's regex still matches) |
| source with NO `views {}` block | likec4 still emits `index` + scoped views → a successful layout always yields ≥1 view |
| `node likec4.mjs --version` inside the sandbox | `1.50.0`, rc 0, ~1.0 s (boot self-probe cost) |

Measured argv (the plan's target shape): `--die-with-parent --new-session --unshare-user --unshare-pid --unshare-net --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/sbin /sbin --ro-bind /etc/ld.so.cache /etc/ld.so.cache --ro-bind /etc/passwd /etc/passwd --ro-bind /etc/group /etc/group --dev /dev --tmpfs /tmp --ro-bind <stage>/src /c4-sources --bind <dir>/out /c4-out --dir /c4-home --chdir /c4-sources --clearenv --setenv PATH … --setenv HOME /c4-home --setenv TMPDIR /tmp --setenv LANG C.UTF-8 -- <node> <likec4.mjs> export json --no-use-dot -o /c4-out/model.likec4.json .`

**Relevant files (content anchors, not line numbers).**

- `apps/web-platform/server/c4-render.ts` — `runLikeC4` (the only `spawn(`), `renderToValidatedModel` (elements gate), `acquire`/`release` (POOL_SIZE gate, no wait bound), `STABLE_SOURCE_ROOT = "/c4-sources"`, `LIKEC4_BIN` (env override "for tests / local dev only").
- `apps/web-platform/server/c4-writer.ts` — `buildRerenderDiagnostic` maps every reason except `empty_model`/`unsafe_source`/stage-phase to `INTERNAL_DIAGNOSTIC`, so new reasons `sandbox_error`/`layout_failed` need no writer copy change; `reportSilentFallback(new Error(render.detail ?? render.reason), { tags: { reason, phase } })` carries the bwrap stderr in the message.
- `apps/web-platform/components/kb/c4-shared.tsx` — `C4Diagnostics` (banner), `C4CodePanel.save` (`setSaveMsg(... Saved — ${diagnostic})`, `await onSaved(rerendered)`).
- `apps/web-platform/components/kb/c4-workspace.tsx`, `c4-diagram.tsx` — `const [stale, setStale] = useState(false)`; `onSaved={async (rerendered) => { await reload(); setStale(!rerendered); … }}`.
- `apps/web-platform/server/index.ts` — `app.prepare().then(() => { … verifyWorkspacesMountOnce(); … })`: the boot-time one-shot probe precedent (`server/readiness.ts` `verifyWorkspacesMountOnce`).
- `apps/web-platform/infra/sandbox-canary-argv.json` — SDK-captured argv (never hand-authored), the anchor for Guard 4.
- `.github/workflows/ci.yml` test-webplat — installs `likec4@1.50.0`, sets `LIKEC4_REQUIRED: "1"`; runner `ubuntu-latest`; no bubblewrap step, no userns sysctl. `apps/web-platform/scripts/sandbox-canary-regression.test.sh` is the precedent for `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` on an ephemeral GH-hosted runner.
- Tests: `test/c4-render.test.ts` (spawn mock; asserts `args[0..4]`, `opts.cwd`, env allow-list, `HOME === TMP_DIR`), `test/c4-render-boundary.test.ts` (c4-render.ts fs imports exactly `lstat/mkdir/mkdtemp/readFile/readdir/rm`; `LIKEC4_BIN` only in c4-render.ts; `renderC4Model` importers exactly c4-render.ts + c4-writer.ts), `test/c4-render-tenant-config.test.ts` (REAL likec4, `LIKEC4_REQUIRED`), `test/c4-shared.test.tsx` (banner: `/out of date/i`; code panel: `toHaveBeenCalledWith(false)` / `(true)`), `test/c4-workspace.test.tsx` + `test/c4-diagram.test.tsx` (mock `C4Diagnostics` exposing `data-stale`; mock `C4CodePanel` calling `onSaved(true|false)`).

**RenderReason consumers (hr-type-widening-cross-consumer-grep, three patterns).** Type names `RenderReason|RenderFailure|RenderResult|renderC4Model`: `server/c4-render.ts`, `server/c4-writer.ts`, tests `c4-render*.test.ts`, `c4-writer-rerender.test.ts`, `c4-writer-concurrency.test.ts`. Literal comparisons (`"spawn_error"`, `"non_zero_exit"`): only `c4-render.ts` and `c4-render.test.ts` (the `kb-upload*.test.ts` hits are pdf-linearize's own union). No `switch` over `RenderReason` anywhere. Adding `sandbox_error` and `layout_failed` is safe; `c4-writer.ts` needs no branch.

**Institutional learnings applied.**

- `security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md` and `docker-seccomp-blocks-bwrap-sandbox-20260405.md` — seccomp + AppArmor + masked `/proc` are the three layers; `--proc` fails in Docker. Confirms "no /proc".
- `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` — never ship a deploy-GATING probe validated only against a mock; dark-launch report-only first. → the boot self-probe is report-only.
- `2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md` — validate argv inside the deploy base image, not the host. → plan-time probe used the runner digest; the boot self-probe runs in the real container.
- `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` — env allow-list. → `--clearenv` + explicit `--setenv`. (Its "CI=true for likec4" advice is WRONG here: `c4-render.ts` documents that `CI=true` switches likec4's reporter and breaks the writer's `Could not resolve` match. Do not add it.)
- `best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md` — exit 0 is not success; gate on the output shape. → views gate.
- `bug-fixes/2026-06-12-c4-save-revert-stale-clone-optimistic-apply.md` — the optimistic `savedContentRef` flow must stay untouched; the banner change is parent-state only.
- `2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md` — the banner already appears only after a failed re-render; the change makes it actionable, not louder.
- `best-practices/2026-06-05-llm-facing-claim-correction-must-sweep-tool-desc-and-prompt-addendum.md` — swept: no prompt/tool text repeats the banner's refresh claim (`grep -rn -i "precomputed"` plus the banner's refresh phrase over server/lib/components/app hits only code comments). `RERENDER_OUTCOME_GUIDANCE` in `server/c4-concierge-tools.ts` already tells the Concierge not to promise a refresh when a diagnostic is present — the banner now agrees with it.

**Domain leader input (Phase 2.5).** CTO: agrees with fail-closed, `--no-use-dot`, realpath exec; flagged (a) CPU load ~5× the failed-layout path with POOL_SIZE 2 and slot-wait outside the 25 s timer, (b) the `--unshare-*` subset test alone does not cover mount ops or AppArmor — recommended a canary row, (c) pin `LANG`, (d) record bwrap version, (e) measure RSS. All folded in: (a) slot-wait bound + `queueWaitMs`, (b) boot self-probe with the exact argv in the real container, (c) `--setenv LANG C.UTF-8`, (d) probe logs `bwrap --version`, (e) measured 183 MiB / 366 MiB. CPO: approved with 4 conditions — folded in (see Domain Review).

**Advisor consult (Phase 4.5).** Folded: resolve binaries lazily (not at import); bound the whole render budget (slot wait lowered to 10 s so stage + wait + spawn ≤ 45 s); land the `--no-use-dot` + views gate in its own commit so a latency/memory regression can be reverted without undoing the sandbox; zero-view check against a views-less source (already measured: `index` is always emitted); `--json-status-fd` considered for classification (prefer only if measured). Not folded: deploy-gating the probe (see Alternatives) and dropping Guard 4 (it is cheap and states only the namespace claim; mounts are Guard 1's job).

**Functional overlap.** Community-registry discovery skipped: the change is an internal hardening of one spawn and one banner line; no skill/agent could implement or replace it.

## User-Brand Impact

- **If this lands broken, the user experiences:** every C4 diagram save (Code tab with `c4-edit` ON, or a Concierge `edit_c4_diagram` edit) commits the source but the diagram never updates, and the banner/Concierge relays "diagram not updated: the diagram could not be rendered this time. Save again to retry; if it keeps happening, contact support." For the banner half: a wrong or stale reason shown in the amber strip (e.g. a previous save's rate-limit message after a later success).
- **If this leaks, the user's data is exposed via:** a sandbox allowlist that accidentally binds `/workspaces`, `/app`, `$HOME` or the parent `/proc` into the likec4 child — combined with any likec4 parser code-execution defect on tenant-authored `.c4` DSL, that child could read other tenants' workspace clones or the server's environment (Supabase service key, GitHub App key) through `/proc/<server-pid>/environ`. Guard 1 exists for exactly this.
- **Brand-survival threshold:** `single-user incident` (same as #8623: the surface is a cross-tenant boundary on tenant-derived input). `soleur:engineering:review:user-impact-reviewer` runs at review.

## Implementation Phases

### Phase 1 — #8695 banner (UI copy + plumbing)

1. `components/kb/c4-shared.tsx`
   - `C4CodePanel` prop: `onSaved: (rerendered: boolean, diagnostic?: string) => void | Promise<void>`. In `save`, call `diagnostic ? onSaved(rerendered, diagnostic) : onSaved(rerendered)` so existing `toHaveBeenCalledWith(true|false)` assertions keep their exact-arg meaning.
   - `C4Diagnostics` gains `staleDiagnostic?: string | null`. Line 1 unchanged ("Source edited — rendered diagram may be out of date"). Line 2: when `staleDiagnostic` is a non-empty string → the diagnostic with its first character upper-cased (a tiny local `capitalizeFirst`), rendered as a React text node; otherwise the CPO-suggested plain sentence "It will refresh once the new version finishes rendering." (replaces the "precomputed … re-rendered" sentence). Same `<p>`, same classes — no new element, no layout change.
   - Update the `C4Diagnostics` doc comment (it still says the model "is regenerated … never at runtime", false since #4964).
2. `components/kb/c4-workspace.tsx` and `components/kb/c4-diagram.tsx`: add `const [staleDiagnostic, setStaleDiagnostic] = useState<string | null>(null)`; in `onSaved={async (rerendered, diagnostic) => { … setStale(!rerendered); setStaleDiagnostic(!rerendered && diagnostic ? diagnostic : null); … }}` — every save overwrites the previous reason (CPO condition 1 / P3); pass `staleDiagnostic` to `C4Diagnostics`.
3. Tests (write first — `cq-write-failing-tests-before`):
   - `test/c4-shared.test.tsx` `C4Diagnostics`: (a) `stale` + `staleDiagnostic="diagram not updated: GitHub's rate limit…"` → text `Diagram not updated: GitHub's rate limit…` present AND `/will refresh/i` absent AND `/precomputed/i` absent; (b) `stale` without diagnostic → `/will refresh once the new version finishes rendering/i` present, `/precomputed/i` absent; (c) `stale={false}` with a leftover `staleDiagnostic` → renders nothing (no banner when not stale); (d) diagnostic containing `<script>` renders as literal text (no element).
   - `test/c4-shared.test.tsx` `C4CodePanel`: the existing "failed re-render WITH a diagnostic" case asserts `onSaved` called with `(false, "<the diagnostic>")`; the no-diagnostic cases keep `toHaveBeenCalledWith(false)` / `(true)`.
   - `test/c4-workspace.test.tsx` + `test/c4-diagram.test.tsx`: extend the `C4Diagnostics` mock to expose `data-stale-diagnostic`; add a third mock-panel button `c4-save-fail-diag` calling `onSaved(false, "diagram not updated: x")`; assert the attribute is set after it, then CLEARED after a following `c4-save-ok` and after a following `c4-save-fail` (no diagnostic).

### Phase 2 — #8696 sandbox + wasm pin (server)

All in `apps/web-platform/server/c4-render.ts` unless noted. Write Guard 1-4 tests first (Guard Contract below).

1. **Argv builder (pure, exported for tests):** `buildLikeC4SandboxArgv({ srcDir, outDir, nodeBin, likec4Entry, extraRoBinds })` returns the bwrap argv exactly as measured above: `--die-with-parent --new-session --unshare-user --unshare-pid --unshare-net`, allowlisted root (`--ro-bind /usr /usr`, merged-usr `--symlink`s, `--ro-bind` of `/etc/ld.so.cache`, `/etc/passwd`, `/etc/group`), `--dev /dev`, `--tmpfs /tmp`, `--ro-bind <srcDir> /c4-sources` (= `STABLE_SOURCE_ROOT`), `--bind <outDir> /c4-out`, `--dir /c4-home`, `--chdir /c4-sources`, `--clearenv`, `--setenv` for exactly `PATH` (`dirname(nodeBin)` + `/usr/local/bin:/usr/bin:/bin`), `HOME=/c4-home`, `TMPDIR=/tmp`, `LANG=C.UTF-8`, then `--`, `nodeBin`, `likec4Entry`, `export json --no-use-dot -o /c4-out/model.likec4.json .`. Default is plain `--ro-bind` for the three `/etc` files (fail loud); switch one to `--ro-bind-try` only if a CI runner is measured to lack it, and add that option to Guard 1's allowlist in the same commit.
2. **Binary resolution (lazy, memoized on first render or probe — never at import, so importing the module touches no filesystem and a failure surfaces as a classified result):** `nodeBin = realpath(process.execPath)`; `likec4Entry = realpath(<LIKEC4_BIN resolved on PATH>)` (prod: `/usr/local/lib/node_modules/likec4/bin/likec4.mjs`). `extraRoBinds` = the node install prefix (`dirname(dirname(nodeBin))`) and the likec4 package root, each ONLY when not already under `/usr` (GitHub runners' setup-node lives under `/opt/hostedtoolcache`). Resolution failure → the render returns `sandbox_error` with detail `likec4 not resolvable` (the memo caches success only, so a later render retries).
3. **Spawn through bwrap:** `runLikeC4` spawns `BWRAP_BIN` (`"bwrap"`, fixed; no env override in production) with the builder's argv, `cwd` = the private `dir` (not the stage — the child's cwd is set by `--chdir`), `stdio: ["ignore","ignore","pipe"]`, and bwrap's OWN env = the existing allow-list (`PATH, LANG, LC_ALL, TMPDIR` + `HOME: dir`) so bwrap itself never sees secrets. `mkdir(<dir>/out, 0o700)` before the spawn; read the model from `<dir>/out/model.likec4.json`. Keep the `raw.split(srcDir).join(STABLE_SOURCE_ROOT)` rewrite (a no-op under bwrap, load-bearing in the dev opt-out).
4. **Classification:** `RenderReason` gains `"sandbox_error"` (bwrap missing — spawn `ENOENT` on the bwrap binary — or bwrap exits non-zero with the FIRST stderr line starting `bwrap:` (plus a space)) and `"layout_failed"` (see 5). Detail keeps the sanitized 512-byte stderr plus `bwrap=<version>` (captured once by the boot probe) so Sentry diagnoses a userns/seccomp/AppArmor break without host access. Both map to `INTERNAL_DIAGNOSTIC` in `c4-writer.ts` with no code change (verify with a `c4-writer-rerender.test.ts` case per reason). The classification only picks the Sentry tag, never a security or copy decision: likec4's own stderr lines begin with `Invalid /c4-sources/…` or log prefixes, so a tenant cannot make them start with `bwrap:` (plus a space). If implementation measures that bwrap 0.8.0's `--json-status-fd` separates setup failure from child exit, prefer it (add the option to Guard 1's allowlist in the same commit); do not add it speculatively.
5. **Views gate (P7):** after the elements gate, require `model.views` to be a non-empty plain object; otherwise `{ ok:false, reason:"layout_failed", phase:"spawn", detail: "model has <n> elements and no views" + stderr }`. A successful layout always emits at least `index` (measured), so zero views is always our layout failing, never the user's source (CPO condition 3: our fault → internal copy, not "empty or invalid").
6. **Fail closed + dev opt-out:** `C4_RENDER_SANDBOX=off` skips bwrap (old direct spawn, still `--no-use-dot`) ONLY when `process.env.NODE_ENV !== "production"`, read once at module load; in production the value is ignored and the boot probe logs that it was ignored. There is no other path to an unsandboxed spawn.
7. **Slot-wait bound (CTO a, advisor):** `acquire()` gets a `SLOT_WAIT_MS = 10_000` deadline that removes the waiter on expiry and returns `{ ok:false, reason:"timeout", phase:"spawn", detail:"render slot wait" }`; the ok result carries `queueWaitMs`, and `c4-writer.ts`'s `c4_rerender` info log adds it. Budget: stage ≤ 10 s (`STAGE_DEADLINE_MS`) + slot wait ≤ 10 s + spawn ≤ 25 s = 45 s worst case before the model commit, which leaves room for the two Contents-API commits and syncs inside the PUT route's `maxDuration = 60` (a platform hint only — `app/api/kb/c4/[...path]/route.ts` says the custom Node server does not enforce it). Today the slot wait is unbounded, so this only tightens. Measured real-render cost: 3.8-7.2 s single, 12.5 s for two concurrent at 2 CPUs.
8. **Boot self-probe (P6; replaces a canary row):** export `verifyC4RenderSandboxOnce(): void` from `c4-render.ts` (keeps `LIKEC4_BIN` single-module) and call it from `server/index.ts` next to `verifyWorkspacesMountOnce()`. It builds the SAME argv via `buildLikeC4SandboxArgv` against a throwaway stage under `c4RenderStagingRoot()` and runs `<node> <likec4.mjs> --version` (~1 s, async, never blocks boot, never throws). Success → `logger.info({ event: "c4_render_sandbox_probe", ok: true, bwrap: "<bwrap --version>", likec4: "<version>" })`. Failure → `reportSilentFallback(err, { feature: "c4-rerender", op: "sandbox-selfprobe", tags: { reason: "sandbox_error" }, extra: { stderr, bwrap } })`. Runs on every container start, including the canary container before traffic cutover, in the real seccomp + AppArmor profile — report-only (learning: never gate on an unproven probe).
9. **Comments:** update the `c4-render.ts` header (SECURITY paragraph: residual resolved; check-update containment now comes from the sandbox — inside bwrap `isInsideContainer()` is false, so likec4's detached `check-update` spawn may start, but it has no network and dies with the pid namespace; do NOT add `CI=true`), the `RENDER_TIMEOUT_MS` comment (real layout 3-7 s at 2 CPUs), and the Dockerfile likec4 comment (remove "~0.8s … no dot needed"; state that `--no-use-dot` is passed because in-container detection would otherwise pick the absent `dot` binary).

### Phase 3 — CI, ADR, census

1. `.github/workflows/ci.yml` test-webplat: before "Run webplat tests", add a step `sudo apt-get install -y --no-install-recommends bubblewrap && sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 && bwrap --version` (comment: ephemeral GH-hosted runner only, same guardrail as `scripts/sandbox-canary-regression.test.sh`), and add `C4_BWRAP_REQUIRED: "1"` to the run step's env. The real-likec4 acceptance suite (`test/c4-render-tenant-config.test.ts`) then runs THROUGH real bwrap.
2. `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`: new dated amendment "render child sandboxed; wasm layout pinned (#8696, #8695)": the argv and why each mount/flag exists, no-`/proc` rationale, fail-closed + dev opt-out, boot self-probe, the `--use-dot` finding (production had been committing zero-view models since #4964), the views gate, measured latency/RSS. Edit the 2026-09-24 **Residuals** paragraph to point at the new amendment (uid residual and banner residual resolved). Follow `soleur:architecture` conventions.
3. **Zero-view census (CPO condition 4), read-only:** before marking the PR ready, list GitHub App installations' connected repos (existing App-token helper, read-only `GET` only) and for each fetch `knowledge-base/engineering/architecture/diagrams/model.likec4.json`; count files with ≥1 element and 0 views, split internal (jikig-ai org) vs external. Record the counts (never content) in the PR body. If any external repo is affected, file a tracking issue for a one-time re-render (milestone per `knowledge-base/product/roadmap.md`); if all internal, record that here.

## Files to Edit

- `apps/web-platform/server/c4-render.ts` — Phase 2 items 1-9.
- `apps/web-platform/server/c4-writer.ts` — add `queueWaitMs` to the `c4_rerender` info log (one field). No diagnostic change.
- `apps/web-platform/server/index.ts` — call `verifyC4RenderSandboxOnce()` beside `verifyWorkspacesMountOnce()`.
- `apps/web-platform/components/kb/c4-shared.tsx` — Phase 1 item 1.
- `apps/web-platform/components/kb/c4-workspace.tsx`, `apps/web-platform/components/kb/c4-diagram.tsx` — Phase 1 item 2.
- `apps/web-platform/Dockerfile` — likec4 comment only.
- `.github/workflows/ci.yml` — test-webplat bubblewrap + userns step, `C4_BWRAP_REQUIRED`.
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` — amendment.
- `apps/web-platform/test/c4-render.test.ts` — spawn assertions move to bwrap argv (`lastSpawn()[0] === "bwrap"`, command after `--` is `[nodeBin, likec4Entry, "export","json","--no-use-dot","-o","/c4-out/model.likec4.json","."]`), `readFile` path `<dir>/out/model.likec4.json`, views gate, `sandbox_error` classification, slot-wait timeout.
- `apps/web-platform/test/c4-render-boundary.test.ts` — keep all rows; add: exactly two `spawn(` call sites in c4-render.ts (render + probe), both fed by `buildLikeC4SandboxArgv`; `C4_RENDER_SANDBOX` read only in c4-render.ts.
- `apps/web-platform/test/c4-render-tenant-config.test.ts` — resolve bwrap availability like likec4 (skip with a hint locally; FAIL when `C4_BWRAP_REQUIRED` is set).
- `apps/web-platform/test/c4-writer-rerender.test.ts` — `sandbox_error` and `layout_failed` → `INTERNAL_DIAGNOSTIC`, Sentry tag `reason` carries them.
- `apps/web-platform/test/c4-shared.test.tsx`, `apps/web-platform/test/c4-workspace.test.tsx`, `apps/web-platform/test/c4-diagram.test.tsx` — Phase 1 item 3.

## Files to Create

- `apps/web-platform/test/c4-render-sandbox.test.ts` — Guard 1-4: argv closure over the spawn mock's ACTUAL args (render and probe), namespace-subset vs `infra/sandbox-canary-argv.json`, production-no-fallback, plus a real-bwrap row (runs real `bwrap` + real likec4 on a 2-element fixture; asserts the element set, ≥1 view, and that `/workspaces`/`/proc` are unreadable from a `node -e` payload exec'd through the same argv shape; skip locally when bwrap/userns is unavailable, FAIL under `C4_BWRAP_REQUIRED`).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) matched no body containing any planned path (`server/c4-render.ts`, `server/c4-writer.ts`, `components/kb/c4-shared.tsx`, `c4-workspace.tsx`, `c4-diagram.tsx`, `.github/workflows/ci.yml`, `ADR-050`, `c4-render`).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Hide banner line 2 when a diagnostic is present | In `c4-diagram.tsx` the save switches to the Diagram tab and unmounts the only place the reason is shown; hiding leaves "may be out of date" with no cause or action (CPO agreed). |
| `--ro-bind / /` then mask `/workspaces`, `/app`, `/home`, `/mnt` (deny-list root) | A deny-list misses the next mount added to the container; the allowlist root (`/usr` + 3 `/etc` files) is closed by construction and measured sufficient. |
| `--proc /proc` (new procfs for the new pid ns) | EPERM in this Docker setup (measured). |
| Bind the parent `/proc` like the SDK argv | Exposes `/proc/<server-pid>/environ` — the exact exposure #8696 exists to remove. |
| Add the C4 argv as a row in the deploy sandbox canary (CTO suggestion) | Couples deploy rollback to a new, unproven probe (learning 2026-06-04: dark-launch report-only first) and needs the builder importable from `scripts/sandbox-canary.mjs`. The boot self-probe gives the same fidelity (exact argv, real container, real seccomp + AppArmor, every start incl. the canary container) without gating. The Phase 4.5 advisor also recommended gating deploys on it; promotion criterion: after the probe has logged `ok:true` on real deploys with zero `op=sandbox-selfprobe` events, a follow-up may add it to the canary as a gate. |
| Dedicated IaC Sentry alert rule for `reason=sandbox_error` | The Sentry-default first-seen route already emails the operator on a new error group (`model.c4` `sentry -> founder` edge documents it); a new `sentry_alert` would also move the rule counts gated by `c4-count-parity`. The boot probe makes a fleet-wide break surface at container start. |
| Fall back to an unsandboxed spawn when bwrap fails | Turns every sandbox break into a silent downgrade; fail closed instead (P5). |
| Install graphviz `dot` in the image instead of `--no-use-dot` | Adds an apt package and a second layout engine that differs from the one the plugin's own regenerator (`plugins/soleur/scripts/render-c4-model.sh`, run outside containers → wasm) uses, so server and repo renders could diverge. |

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-050** (new dated amendment; the 2026-09-24 Residuals paragraph points to it). Decision: the likec4 render child runs in a render-only bwrap with an allowlisted root, no network, no `/proc`, cleared env, fail-closed, with a report-only boot self-probe; wasm layout pinned by `--no-use-dot`; zero-view exports refused. The Alternatives table above goes into the amendment's `Alternatives Considered`.

### C4 views

No C4 element or relationship change. Checked against all three files (`model.c4`, `views.c4`, `spec.c4`): external actors (founder / tenant repo owner) unchanged; external systems (GitHub — the `api -> github` edge prose describing "render in a private staging dir … the repo's likec4 config, symlinks and submodules are refused … does not read the workspace clone (ADR-050 amendment 2026-09-24)" stays true; Sentry — the boot probe reuses the existing api-container Sentry emission path); containers/data stores: the render stays inside the `api` container and writes no new store; access relationships unchanged. `bash plugins/soleur/test/c4-count-parity.test.sh` → `Passed: 12 Failed: 0` (run 2026-09-24 on this branch), and the plan adds no Sentry rule, so no edge cardinality moves.

### Sequencing

ADR amendment ships in this PR.

## Observability

```yaml
liveness_signal:
  what: "c4_render_sandbox_probe info log (ok:true, bwrap and likec4 versions) emitted once per container start by verifyC4RenderSandboxOnce; per-save c4_rerender info log with durationMs and queueWaitMs"
  cadence: "every container start (deploy, canary, restart) + every successful re-render"
  alert_target: "failure path only: Sentry issue (feature=c4-rerender) -> Sentry-default first-seen high-priority route -> operator email"
  configured_in: "apps/web-platform/server/c4-render.ts (verifyC4RenderSandboxOnce, renderC4Model) and apps/web-platform/server/index.ts (boot call)"
error_reporting:
  destination: "Sentry web-platform project via reportSilentFallback (server/observability.ts), DSN from the container env"
  fail_loud: "Sentry error event: feature=c4-rerender, op=sandbox-selfprobe or op=render, tag reason=sandbox_error|layout_failed|timeout, extra/message carries the sanitized bwrap stderr and bwrap version"
failure_modes:
  - mode: "bwrap cannot create namespaces (seccomp profile edit, AppArmor profile drift, host userns sysctl drift)"
    detection: "boot self-probe in the container itself: Sentry op=sandbox-selfprobe reason=sandbox_error with stderr 'bwrap: ... Operation not permitted'; every later save also emits reason=sandbox_error"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "bwrap binary missing from the image"
    detection: "spawn ENOENT on bwrap -> reason=sandbox_error detail 'spawn bwrap ENOENT' at boot probe and per save"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "likec4 or node cannot run inside the allowlisted root (missing /etc file, node prefix not bound)"
    detection: "boot self-probe runs likec4 --version through the same argv; non-zero exit -> reason=sandbox_error or non_zero_exit with stderr"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "layout failure (zero views), e.g. a future likec4 bump changes layout defaults"
    detection: "views gate -> reason=layout_failed Sentry event per save; model not committed"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "render slot starvation under burst saves"
    detection: "reason=timeout detail 'render slot wait' Sentry event; queueWaitMs in c4_rerender logs"
    alert_route: "Sentry-default first-seen route -> operator email"
logs:
  where: "container stdout (pino JSON) -> journald -> Vector (apps/web-platform/infra/vector.toml) -> Better Stack"
  retention: "Better Stack source retention for the web-platform source; Sentry event retention for the error path"
discoverability_test:
  command: "grep -c -e 'event: \"c4_render_sandbox_probe\"' apps/web-platform/server/c4-render.ts"
  expected_output: "1"
```

The discoverability probe confirms the one emitter of the liveness event name that Better Stack and Sentry are searched by (`c4_render_sandbox_probe`, `op=sandbox-selfprobe`). It deliberately declares no `credentials_required`: declaring one moves the `BASELINE_DECLARED_PROBES` ratchet in `plugins/soleur/test/preflight-discoverability-test.test.ts` the moment this plan is committed. The production read (the release's `c4_render_sandbox_probe ok:true` line, and zero `reason:sandbox_error` issues) runs in `soleur:postmerge` with its own credentials (AC-P1).

## Guard Contract

### Guard 1 — likec4 child mount/env/namespace closure

**Property.** Every exec of likec4 (render and boot probe) in production goes through bwrap with exactly the allowlisted mounts (read-only except `/c4-out`), `--unshare-user/pid/net`, no `/proc`, and no environment beyond `PATH, HOME, TMPDIR, LANG`.

**Assembly.** Two spawn sites in `server/c4-render.ts` (`runLikeC4` and `verifyC4RenderSandboxOnce`) — the chokepoint is the args array each passes to `spawn`, observed through the `node:child_process` spawn mock, NOT the builder's return value (a mount appended at the call site bypasses the builder). The test parses the observed argv up to `--` against an OPTION ALLOWLIST with arities (`--ro-bind 2, --bind 2, --symlink 2, --dir 1, --tmpfs 1, --dev 1, --chdir 1, --setenv 2, --clearenv 0, --die-with-parent 0, --new-session 0, --unshare-user 0, --unshare-pid 0, --unshare-net 0`); any other option (`--bind-try`, `--dev-bind`, `--proc`, `--ro-bind-try`, `--overlay`, `--share-net`, …) is RED. Mount DESTINATIONS must equal the allowlist set exactly (set identity, not a count); the only writable destination is `/c4-out`. A boundary-test row asserts `c4-render.ts` has exactly two `spawn(` call sites.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | builder adds `--bind /workspaces /workspaces` | RED |
| 2 | builder adds `--ro-bind / /` | RED |
| 3 | builder adds `--proc /proc`, or `--ro-bind /proc /proc` | RED |
| 4 | source bind changed from `--ro-bind` to `--bind` | RED |
| 5 | `--unshare-net` removed, or `--share-net` added | RED |
| 6 | `--clearenv` removed, or `--setenv SUPABASE_SERVICE_ROLE_KEY x` added | RED |
| 7 | a compliant `--ro-bind /usr /usr` followed by a SECOND bind `--ro-bind /app /app` | RED |
| 8 | render site spreads `[...argv, "--bind", "/home", "/home"]` at the `spawn(` call, builder untouched | RED |
| 9 | boot probe builds its own argv instead of calling the builder, adding `--ro-bind /app /app` | RED |
| 10 | guard's own dispatch: the parser returns zero options (e.g. the test reads the argv after `--`) | RED (row asserts at least 14 parsed options and that `--` was found) |

**Harness rows:** (H1) must-RED fixture with the forbidden bind in the LAST option position, so a parser that stops early cannot pass; (H2) must-PASS: the canonical argv with its option ORDER shuffled (order is permitted to vary) passes; (H3) must-PASS: an `extraRoBinds` of `/opt/hostedtoolcache/node/22/x64` (a runner node prefix, read-only) passes, while the same path as `--bind` is RED.

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

**Property.** With `NODE_ENV=production`, no code path spawns likec4 (or node) directly — including on bwrap `ENOENT`, bwrap EPERM, or `C4_RENDER_SANDBOX=off`.

**Assembly.** Both spawn sites; the module-load read of `C4_RENDER_SANDBOX`/`NODE_ENV` (the only env reads for this decision, asserted by the boundary test).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | on bwrap spawn `ENOENT`, retry with a direct likec4 spawn | RED (spawn mock: exactly one call, cmd `bwrap`; result `sandbox_error`) |
| 2 | honour `C4_RENDER_SANDBOX=off` regardless of `NODE_ENV` | RED (production + off → first spawn cmd is still `bwrap`) |
| 3 | read `NODE_ENV` per call instead of at module load, then flip it mid-test | RED (module re-import per row; a per-call read would observe the flip) |
| 4 | bwrap exit 1 with stderr `bwrap: Can't …` classified as `non_zero_exit` | RED (must be `sandbox_error`) |

**Harness rows:** must-PASS: `NODE_ENV=test` + `C4_RENDER_SANDBOX=off` → direct spawn, still carrying `--no-use-dot`.

### Guard 4 — namespace set stays inside what the deploy canary proves

**Property.** The set of `--unshare-*` flags in the C4 argv is a subset of the `--unshare-*` flags in the SDK-captured canary fixture.

**Assembly.** `buildLikeC4SandboxArgv` output vs `apps/web-platform/infra/sandbox-canary-argv.json` `bwrapSetupArgv`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | builder adds `--unshare-ipc` (or `--unshare-cgroup`, `--unshare-uts`, `--unshare-all`) | RED |
| 2 | fixture edited to drop `--unshare-net` | RED |
| 3 | test reads a fixture path that does not exist / parses zero flags | RED (asserts the fixture's set is non-empty and contains `--unshare-user`) |

**Harness rows:** must-PASS: the current fixture (user, pid, net).

**Anchor.** The fixture is produced only by `scripts/sandbox-canary.mjs --capture` driving the real SDK and byte-verified by `--verify` in CI (ADR-079) — it cannot be hand-edited to widen this guard without the canary's own drift check going red.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO — direction sound; biggest risk is the CPU cost of real layouts (about 5× the failed-layout path) with POOL_SIZE 2 and slot-wait outside the 25 s timer; wants production-profile fidelity for the exact argv; pin locale; record bwrap version; measure RSS. Folded: slot-wait bound + `queueWaitMs`; boot self-probe (exact argv, real profiles, report-only) in place of a canary row; `LANG=C.UTF-8`; version in probe log; RSS measured (183/366 MiB).

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface) — copy-only exemption, see wireframe decision below

#### Findings

CPO sign-off: **approved with conditions**, all folded in:

1. Each save replaces or clears the previous reason — Phase 1 item 2 + the workspace/diagram test rows.
2. Sandbox start failure reaches Sentry with its own tag and alerts — `reason=sandbox_error` / `op=sandbox-selfprobe`, first-seen email via the Sentry-default route, surfaced at container start by the boot probe. (A dedicated IaC rule was weighed and not added — see Alternatives; recorded in `knowledge-base/project/specs/feat-one-shot-8695-8696-c4-banner-bwrap/decision-challenges.md` for the operator.)
3. Zero-view causes separated — measured that a user source can never yield zero views on a successful layout, so zero views is always `layout_failed` → internal copy, never "empty or invalid".
4. Census before relying on "the next save fixes it" — Phase 3 item 3.
Optional suggestion adopted: plain no-reason line 2 ("It will refresh once the new version finishes rendering.").

**Wireframe gate decision (`wg-ui-feature-requires-pen-wireframe`): exempt — copy-only.** The rule excludes "copy/style" changes, and `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` §Excluded lists "pure copy or style tweaks with no structural/layout change". This change swaps the TEXT inside the existing second `<p>` of the existing amber strip (same element, same classes, same position, same show/hide condition `stale`), plus non-visual prop plumbing. No new element, interaction, state surface, route, modal or layout. The three `.tsx` files match the mechanical glob only because they host the banner. Explicit override naming the surface shipped without a new wireframe: **`C4Diagnostics` stale strip, line 2 text (`components/kb/c4-shared.tsx`), and the `onSaved` plumbing in `c4-workspace.tsx` / `c4-diagram.tsx`**. If a reviewer rejects the exemption, the fallback is `soleur:product:design:ux-design-lead` producing a `c4-stale-banner-diagnostic` Pencil file in the `kb-viewer` design folder (two states: with reason / without) before `soleur:work` Phase 1.

## Test Scenarios

- Banner, reason present: amber strip line 2 = `Diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.`; no "will refresh", no "precomputed".
- Banner, no reason: line 2 = `It will refresh once the new version finishes rendering.`
- Reason cleared: fail-with-reason → ok → no banner; fail-with-reason → fail-without-reason → line 2 is the no-reason sentence.
- Embedded viewer (`c4-diagram.tsx`): after a failed save the tab switches to Diagram and the banner shows the reason.
- Render: sandboxed spawn argv exact; bwrap `ENOENT` → `sandbox_error`; bwrap stderr `bwrap: …` + exit 1 → `sandbox_error`; likec4 exit 1 → `non_zero_exit`; zero views → `layout_failed`; slot wait > 10 s → `timeout` detail `render slot wait`; production ignores `C4_RENDER_SANDBOX=off`.
- Real bwrap + real likec4 (CI, `C4_BWRAP_REQUIRED`): tenant-config acceptance rows green through bwrap; a benign 2-element tree renders with ≥1 view; a `node -e` payload through the same argv cannot list `/workspaces` or read `/proc/1/environ`.
- Boot probe: success logs `c4_render_sandbox_probe ok:true`; bwrap failure → one Sentry event `op=sandbox-selfprobe`, boot continues.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Do NOT add `CI=true` to the child env (likec4 switches reporter; the writer's `Could not resolve` match breaks) — `c4-render.ts` header documents it; one learning says the opposite and is wrong for this binary.
- `toHaveBeenCalledWith(false)` in `c4-shared.test.tsx` compares ALL args: call `onSaved(rerendered)` (one arg) when there is no diagnostic.
- `c4-render-boundary.test.ts` pins c4-render.ts's fs imports to exactly `lstat/mkdir/mkdtemp/readFile/readdir/rm` — the `out` dir uses the existing `mkdir`. Binary resolution needs a realpath; if it imports `realpathSync` from `node:fs`, that row's regex matches it too — update the expected list in the same commit and say why in the test.
- GitHub runners' node is under `/opt/hostedtoolcache`, not `/usr`: without `extraRoBinds` the CI real-bwrap rows fail with `execvp … No such file`, which would look like a sandbox break.
- The file:// icon rewrite: under bwrap the stage path is already `/c4-sources`; keep the split/join for the dev opt-out path.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 (#8695): `C4Diagnostics` with `stale` and a `staleDiagnostic` renders the diagnostic (first letter upper-cased) as line 2 and no refresh promise; without a diagnostic renders "It will refresh once the new version finishes rendering."; `test/c4-shared.test.tsx` rows (a)-(d) green.
- [ ] AC2 (#8695): both parents clear/replace the reason on every save (`c4-workspace.test.tsx`, `c4-diagram.test.tsx` new rows green); embedded viewer shows the reason after the tab switch.
- [ ] AC3 (#8696): every likec4 exec in production goes through `bwrap` with the Guard 1 allowlist; Guard 1 mutation rows 1-10 and harness rows H1-H3 are encoded in `test/c4-render-sandbox.test.ts` and each was observed RED against its mutation during implementation.
- [ ] AC4 (#8696): Guard 3 rows green — no direct spawn in production on `ENOENT`/EPERM/opt-out.
- [ ] AC5: argv carries `--no-use-dot`; zero-view exports return `layout_failed` and are never committed (Guard 2 rows green); `c4-writer-rerender.test.ts` maps `sandbox_error`/`layout_failed` to `INTERNAL_DIAGNOSTIC`.
- [ ] AC6: Guard 4 subset test green against `infra/sandbox-canary-argv.json`.
- [ ] AC7: CI test-webplat installs bubblewrap, relaxes the userns sysctl, sets `C4_BWRAP_REQUIRED=1`, and `test/c4-render-tenant-config.test.ts` + the real-bwrap rows run (not skip) and pass on the PR.
- [ ] AC8: `verifyC4RenderSandboxOnce()` is called from `server/index.ts`; unit rows cover the success log (exactly one `event: "c4_render_sandbox_probe"` emitter, the discoverability probe prints `1`) and the failure Sentry event (`op=sandbox-selfprobe`, `reason=sandbox_error`), and boot never awaits it.
- [ ] AC9: slot-wait bound returns `timeout`/`render slot wait`; `c4_rerender` log carries `queueWaitMs`.
- [ ] AC10: ADR-050 amendment merged in this PR; Residuals paragraph points to it; `plugins/soleur/test/c4-count-parity.test.sh` still green.
- [ ] AC11: zero-view census counts (internal vs external) recorded in the PR body; a tracking issue exists if any external repo is affected.
- [ ] AC12: Dockerfile and `c4-render.ts` timing comments corrected; `bash scripts/test-all.sh webplat` and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (tsc is the enumerator for any `RenderReason` consumer the grep missed).

### Post-merge (automated in `soleur:postmerge`)

- [ ] AC-P1: for the deployed release, Better Stack carries a `c4_render_sandbox_probe` line with `ok:true` from the production container, and the Sentry issue search `feature:c4-rerender reason:sandbox_error` over the 24 h after deploy returns 0 issues. Both are API reads with credentials pulled from Doppler; neither needs host access.

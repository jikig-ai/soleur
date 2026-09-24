---
title: "fix(security): the C4 re-render renders only the committed LikeC4 sources, fetched from GitHub into a private staging dir, never the tenant workspace"
type: fix
date: 2026-09-24
slug: fix-c4-render-tenant-likec4-config-execution
branch: feat-one-shot-8623-likec4-tenant-config-rce
issue: 8623
closes: 8623
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(security): the C4 re-render must never load a tenant's likec4 config

## Overview

The web-platform server re-renders a tenant's C4 model by running the `likec4` CLI with its
working directory set to the tenant workspace's diagrams directory
(`apps/web-platform/server/c4-render.ts`, `runLikeC4` → `spawn(LIKEC4_BIN, ["export","json","-o",<tmp>,"."], { cwd: diagramsDir })`).
likec4 1.50.0 treats a `likec4.config.{js,cjs,mjs,ts,cts,mts}` anywhere under that directory as
code, reads `.likec4rc` / `.likec4.config.json` / `likec4.config.json` as configuration whose
`include.paths` pull sources from outside the directory, and follows symlinks. So any tenant, and
any prompt-injected agent that can write the workspace from inside its bwrap sandbox, can run code
in the web-platform server's process tree on the next `.c4` save, or pull another directory's
sources into a model the server then commits to the tenant's repo.

This plan (1) measures that on the server's own render function with the pinned binary, as a
failing acceptance test, then (2) changes the render so its only input is **the regular-file
`.c4`/`.likec4`/`.like-c4` blobs of the diagrams subtree of the commit GitHub returned for the
write**, fetched through the GitHub Git Trees/Blobs API into a private `mkdtemp` staging directory,
with likec4 configs, symlinks and submodules refused. The render no longer reads the tenant
workspace (worktree or `.git`) at all.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Issue vs. Codebase

| Issue / premise claim | Reality (verified 2026-09-24) | Plan response |
|---|---|---|
| "Not yet measured on the server itself" | Measured locally with the pinned `likec4@1.50.0` and the server's argv/env shape (table below): a tracked `likec4.config.mjs` in the diagrams dir **executes** (A), as does one in a subdirectory (B). `renderC4Model()` itself is not yet measured. | Phase 1 writes the acceptance test against the current `renderC4Model` first; it must go RED. |
| "copy only tracked sources out of git objects" (ADR-235 2026-09-23 local-resolver pattern) | In the resolver the object store is the operator's own. Here it is not trusted: the agent sandbox runs with `allowWrite: [workspacePath]` (`server/agent-runner-sandbox-config.ts`), and the Agent SDK's built-in write-deny list (strings in `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`, SDK 0.3.197) names `.git/hooks`, `.git/config`, `.git/config.worktree`, `.git/commondir`, `.git/worktrees`, `.git/modules`, `.git/info/exclude` — **not** `.git/objects`, `.git/refs`, `.git/HEAD` or `objects/info/alternates`. A local read would need per-object hash verification, git env hardening, alternates/gitfile/promisor handling. | Keep the pattern's allowlist and refusals; take the bytes from **GitHub** (the trusted party that just created the commit) instead of the local store. The resolver-vs-app difference is recorded in the ADR amendments. |
| The resolver's bash staging could be reused | Not reachable from the app: the Docker build context is `apps/web-platform` only (ADR-235 2026-09-22 amendment, "Why a mirror"). | Re-implement in TypeScript (`server/c4-stage-sources.ts`). |
| "or render inside the agent sandbox" | bwrap exists in the runner image; the allowlist removes the config from the input entirely, which a sandbox would only contain. | Cut (Cut List). |
| ADR-050 SECURITY note: "no command-injection or scope-escape surface here" | True for argv; false for the input directory, which is tenant-controlled. | Amend ADR-050. |

## Research Insights

### Premise Validation

Checked: #8623 is OPEN (P1, `type/security`); draft PR #8687 exists for this branch; PR #8631
(merged 2026-09-23) only filed the issue and does not touch `c4-render.ts`. `c4-render.ts` has the
in-place `cwd: diagramsDir` spawn on this branch (read). The ADR-235 2026-09-23 amendment's last
residual bullet names this gap. `grep -rn 'likec4.config\|likec4rc' apps/` returns nothing. ADR
corpus: ADR-050 is the runtime-render decision; no ADR rejects "stage sources", "render in sandbox"
or "fetch sources from GitHub" (ADR-235 records "web-platform renders at sync time" as out of its
scope, which this is not). Nothing stale.

### Property List (Phase 0.6b)

- **P1 — no config, no code.** No tenant-controlled file other than LikeC4 source content can
  influence the `likec4` process; no likec4 config (code or JSON form) is ever in its working tree.
- **P2 — no reads outside the committed diagrams subtree.** Nothing outside the diagrams subtree of
  the just-written commit reaches the render: not symlinks, `include.paths`, untracked workspace
  files, or anything in the workspace's `.git`.
- **P3 — refusal is honest.** A tree the render will not faithfully render (config, symlink,
  submodule, bad name, over the caps) yields `rerendered:false` plus a class-specific,
  user-actionable diagnostic, never a silently different model and never "will update" copy.
- **P4 — benign trees render as before.** A tree of only LikeC4 sources yields the same canonical
  bytes as the in-place render did.
- **P5 — the acceptance is executable and not vacuous.** A test places a sentinel-writing
  `likec4.config.mjs` in a tenant diagrams dir and asserts the server render never executes it,
  with the real pinned binary; RED on the current code; fails (not skips) in CI without the binary.
- **P6 — bounded.** A hostile tree cannot make staging exhaust server disk, memory or API budget.

### Cut List (Phase 0.6b)

- **Render inside the bwrap agent sandbox** → P1/P2 → bought by the staging allowlist, which removes
  the config from the input instead of containing its execution; a sandbox would add bwrap
  orchestration to a synchronous save path (ADR-050's 25 s budget).
- **A config-name denylist as the security control** → P1 → bought by the extension **allowlist**
  (only regular-file `.c4`/`.likec4`/`.like-c4` blobs are materialized). The name list survives only
  for P3 (refuse vs silently skip), so an incomplete list is a fidelity bug, not a hole.
- **Reading local git objects with Merkle verification** (the first draft of this plan) → P2 → bought
  by fetching from GitHub, which is outside the tenant's write reach; deletes object-hash
  verification, tree parsing, git env hardening, alternates/gitfile/promisor handling and their
  fixtures. Flagged independently by the CTO assessment and the scoped advisor consult.
- **New Sentry instrumentation** → `rerenderAndCommit` already mirrors every `!render.ok` through
  `reportSilentFallback` with `extra.reason`; this plan adds one `extra` field.

### Measurement (local, pinned binary, server-shaped invocation)

Shape: `cd <dir> && env -i PATH HOME LANG=C.UTF-8 likec4 export json -o <out> .` with the cached
`likec4@1.50.0` (`~/.npm/_npx/828032c5e644b3ee/node_modules/.bin/likec4`) — the server's argv and a
subset of its env allow-list.

| Case | Setup | Result |
|---|---|---|
| A | `likec4.config.mjs` (writes a sentinel) in cwd | **executed** — sentinel written, env visible (`PATH,HOME,LANG`), rc 0, model still exported |
| B | same config in a subdirectory of cwd | **executed** |
| C / D | config in the parent / grandparent of cwd | not executed (no walk-up) |
| F | config at the git repo root, cwd = diagrams dir | not executed |
| G | a symlinked directory in cwd pointing at another dir of `.c4` | **that dir's elements in the exported model** |
| H | a symlinked `.c4` pointing outside | **target's elements in the model** |
| I | a `.c4` symlink to a non-LikeC4 file | the file's first token in stderr (`Expecting end of file but found …`) |
| J / K | `likec4.config.json` / `.likec4rc` with `include.paths` out of cwd | **outside sources in the model** |
| L / M | `icon <abs or ../ path>`, `link file://…` | not read; `icon` stored as a `file://` URL string |
| N | `import { zz } from 'otherproj'` with a project `otherproj` (config + sources) outside cwd | not resolved (`Could not resolve reference to Element named 'zz'`) |
| Equivalence | this repo's 3 tracked `.c4` blobs (via `git cat-file`) in a fresh dir vs in-place | canonical bytes **equal** (1,270,581 B) |

Config names from the installed binary (`likec4/dist/_chunks/src.mjs`):
`[".likec4rc", ".likec4.config.json", "likec4.config.json"]` and
`["likec4.config.js", "likec4.config.cjs", "likec4.config.mjs", "likec4.config.ts", "likec4.config.cts", "likec4.config.mts"]`;
source extensions (`dist/_chunks/binary.mjs`): `[".c4", ".likec4", ".like-c4"]`.

### GitHub API shapes (verified 2026-09-24 with `gh api` against this public repo at `ca83c8ed`)

- `GET /repos/{o}/{r}/contents/knowledge-base/engineering/architecture?ref=<commitSha>` → array; the
  `diagrams` entry is `{"type":"dir","sha":"659903c6…"}`, and that sha equals
  `git rev-parse <commit>:knowledge-base/engineering/architecture/diagrams` (the subtree's tree sha).
- **Contents listings misreport symlinks**: `.grok/commands/go.md` (mode `120000`) is listed as
  `{"type":"file"}`. Classification must come from the Trees API, never from a Contents listing.
- `GET /repos/{o}/{r}/git/trees/<treeSha>?recursive=1` → `{ truncated, tree: [{ path, mode, type, sha, size }] }`;
  the same symlink appears as `{"mode":"120000","type":"blob","size":35}`. Accepts a commit sha too
  (returns the root tree).
- `GET /repos/{o}/{r}/git/blobs/<sha>` → `{ encoding: "base64", size, content }`.
- Docs: <https://docs.github.com/en/rest/git/trees#get-a-tree>,
  <https://docs.github.com/en/rest/git/blobs#get-a-blob>,
  <https://docs.github.com/en/rest/repos/contents#get-repository-content>.

### Blast radius

The child runs as the app container's `soleur` user (`apps/web-platform/Dockerfile` `USER soleur`).
The env allow-list keeps secrets out of the child's own environment, but a same-uid process can read
the parent's `/proc/<pid>/environ` and other tenants' checkouts under `/workspaces` (model.c4
`workspacesVolume`, bind-mounted into the app container). Reachable wherever a user has
`c4-visualizer` enabled and a connected repo: the Concierge `edit_c4_diagram` tool
(`server/c4-concierge-tools.ts` → `writeC4Diagram`) and the `c4-edit`-gated `PUT /api/kb/c4/[...path]`.

### Relevant files

- `apps/web-platform/server/c4-render.ts` — `renderC4Model(workspacePath)`, `runLikeC4` (spawn, env allow-list, cwd).
- `apps/web-platform/server/c4-writer.ts` — `writeC4Diagram` (Contents API PUT → `result?.commit?.sha`, `syncWorkspace`), `rerenderAndCommit`, `buildRerenderDiagnostic`, `MAX_C4_WRITE_BYTES = 256 * 1024`.
- `apps/web-platform/server/github-api.ts` — `githubApiGet<T>(installationId, path)`, `GitHubApiError`.
- `apps/web-platform/server/c4-concierge-tools.ts` — `edit_c4_diagram` tool description (relays `rerenderDiagnostic`).
- `apps/web-platform/components/kb/c4-shared.tsx` — renders `Saved — ${diagnostic}`, else `Saved — diagram will update after re-render.`
- `apps/web-platform/lib/c4-constants.ts` — `C4_DIAGRAMS_DIR`, `C4_MODEL_JSON`, `C4_SOURCE_EXT`, `isC4DiagramPath`.
- `apps/web-platform/test/c4-render.test.ts` — mocks `node:child_process` and all of `node:fs/promises`; asserts `writeFile`/`copyFile`/`rename` never called (the staging writes live in the injected `stage` function, so these stay strict for `c4-render.ts`).
- `apps/web-platform/test/c4-writer-rerender.test.ts` — asserts `renderC4Model` called with `("/workspaces/ws-1")`.
- `apps/web-platform/test/c4-likec4-version-pin.test.ts` — `matchAll` over `ci.yml` `npm install -g likec4@` lines.
- `.github/workflows/ci.yml` — `test-webplat` (2-way vitest shard) does not install likec4; `test-scripts`/`test-scripts-heavy` do.
- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh` STAGE block — the allowlist/refusal pattern mirrored.
- `apps/web-platform/server/workspace-sync.ts` — `git pull --ff-only` (sibling surface, Phase 5.4).

### Institutional learnings applied

- `best-practices/2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md` — keep the element-count gate.
- `best-practices/2026-06-05-render-off-tree-return-bytes-and-drop-toctou-with-the-reread.md` — off-tree output stays; staging extends "off-tree" to the input.
- `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` — control row proving the fixture's config is live code; spawn-happened assertion on the happy path.
- `2026-03-20-symlink-escape-cwe59-workspace-sandbox.md` — never materialize a symlink; with API bytes there is none to follow.
- `best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md` — pre-existing element-count-only gate; Non-Goal here.

### Sibling surface (pre-existing, different subsystem)

`syncWorkspace` runs `git pull --ff-only` in the tenant workspace with system/global git config
neutralized but not repo-local config or hooks. The SDK deny-list strings above suggest a sandboxed
agent cannot write `.git/hooks` or `.git/config`, which would close it; that is inferred from binary
strings, not measured. This fix does not depend on the answer (the render no longer reads the
workspace), so the measurement is a non-gating task (Phase 5.4). If it is open: a **private GitHub
Security Advisory** (not a public issue — the repo is public; CLO).

## Proposed Solution

### Shape

```text
writeC4Diagram
  ├─ PUT contents (.c4)  ──►  GitHub returns commit.sha        (trusted: our TLS call, our token)
  ├─ syncWorkspace (git pull --ff-only)                        (unchanged; the viewer reads the clone)
  └─ rerenderAndCommit({ …existing fields…, commitSha })
        ├─ commitSha missing → no render; io_error "no commit sha"; generic retry diagnostic
        ├─ renderC4Model(stage)            stage = (destDir) => stageCommittedC4Sources({ installationId, owner, repo, commitSha, destDir })
        │     ├─ mkdtemp(tmpdir, "c4-render-") = <dir>                       (0700)
        │     ├─ stage(<dir>/src)  — BEFORE acquire(), under a 10 s deadline (→ timeout, detail "stage: deadline")
        │     │    1. GET contents/knowledge-base/engineering/architecture?ref=<commitSha>
        │     │         retry ×2 on 404/422 (read-after-write lag)
        │     │         not an array (a parent is a symlink)  → refuse unsafe_source/symlink
        │     │         no "diagrams" entry                    → io_error "fetch: no diagrams dir"
        │     │         "diagrams" type ≠ "dir" (symlink/submodule list as "file") → refuse unsafe_source/<symlink|gitlink>
        │     │    2. GET git/trees/<diagramsTreeSha>?recursive=1  → full classified listing:
        │     │         truncated                               → refuse unsafe_source/too-large
        │     │         mode 120000                             → refuse unsafe_source/symlink
        │     │         mode 160000                             → refuse unsafe_source/gitlink
        │     │         basename ∈ likec4 config names (9)      → refuse unsafe_source/likec4-config
        │     │         100644|100755 and *.c4|*.likec4|*.like-c4 → source
        │     │         anything else (dirs, .md, .json, images) → skip; never fetched, never materialized
        │     │         > 200 sources, or Σ source size > 16 MiB → refuse unsafe_source/too-large
        │     │       (every offender is collected: first path + count go to the diagnostic)
        │     │    3. Promise.all(GET git/blobs/<sha>) for the sources only
        │     │    4. mkdir <dir>/src; writeFile(<dir>/src/<path>, bytes, { flag: "wx", mode: 0o600 });
        │     │       resolved path asserted under <dir>/src (violation → io_error)
        │     ├─ acquire()  — the render slot is held only around the spawn
        │     ├─ runLikeC4(cwd = <dir>/src, -o <dir>/model.likec4.json)   (argv/env unchanged; -o outside src)
        │     ├─ release()
        │     └─ element gate → canonicalize → return { json, modelSha }   (unchanged gates); rm -rf <dir> in finally
        └─ PUT model.likec4.json with sha = the model blob sha from the step-2 listing (absent → create)
              409/422 → re-list HEAD's diagrams sources (steps 1-2 at HEAD); same source set → retry once with HEAD's
              model sha; different → superseded: rerendered:false, info log, no Sentry, no diagnostic
```

All refusals are decided from the complete listing **before** any blob is fetched or written.
`stageCommittedC4Sources` returns `{ ok: true; files; bytes; modelSha? } | { ok: false; reason: "unsafe_source"; refusalClass: "likec4-config" | "symlink" | "gitlink" | "too-large"; path?: string; more: number } | { ok: false; reason: "io_error" | "timeout"; detail: string }`.

### Why inject the stage function

`renderC4Model(stage)` keeps `c4-render.ts` a pure process runner with no GitHub dependency: it owns
`mkdtemp`, the stage root, `cwd` and cleanup; the writer builds the GitHub-backed `stage`. The
chokepoint (Guard 1) is unchanged, `c4-render.test.ts` passes a fake `stage` instead of mocking a
module, and the signature carries no workspace path, so the render cannot read the workspace.

### Behaviour changes a tenant can see

The UI renders `Saved — ${diagnostic}` as plain text (`components/kb/c4-shared.tsx`), so the copy uses
quotes, not backticks. `<path>` is the offender's path relative to the diagrams folder, capped at 60
characters before insertion; `(and N more)` is appended when `more > 0`.

| Case | Diagnostic (after `Saved — `) |
|---|---|
| likec4-config / symlink / gitlink | `diagram not updated: "<path>" (a likec4 config file / a symbolic link / a submodule) isn't supported in the diagrams folder. Remove it from your GitHub repository to turn automatic updates back on.` |
| too-large | `diagram not updated: the diagrams folder has too many or too large diagram files to update automatically. Split or remove some diagram files to turn automatic updates back on.` |
| stage `io_error`/`timeout`, missing commit sha | `diagram not updated for this save. Save again to retry.` |
| superseded by a newer save | none (the newer save's render updates the diagram, so the existing "will update after re-render" copy is true) |

- The `.c4` commit still lands (unchanged, load-bearing); every row above returns `rerendered:false`.
- Nothing Soleur generates creates configs, symlinks or submodules in the diagrams folder
  (`grep -rn 'likec4.config\|likec4rc' plugins apps scripts` → only the resolver's refusal and its
  test). Users who imported an existing LikeC4 repo with a legitimate `likec4.config.json` are the
  affected population.
- Untracked files in the workspace no longer affect the render.
- A `.c4` with a **relative** `icon` path already bakes an absolute server path into the model; after
  this change it bakes the random staging path. Not a new disclosure; such models differ between
  renders. Residual.
- **Concierge.** `c4-concierge-tools.ts` (tool description) and `cc-dispatcher.ts` (`c4PromptAddendum`,
  which today says the diagram "will refresh after the next re-render" whenever `rerendered` is false)
  both change: when `rerenderDiagnostic` is present, relay it and do not promise a refresh; the
  Concierge cannot fix an unsupported file itself (its only write is `edit_c4_diagram`, `.c4`/`.md`),
  so tell the user to change it in their GitHub repository.

## Technical Considerations

- **Bounded save path.** `RENDER_TIMEOUT_MS` (25 s) covers only the spawn; each `githubApiGet` retries
  5xx (`MAX_RETRIES=2`, 15 s per attempt). Staging therefore gets its own 10 s deadline and runs
  **before** `acquire()`, so a slow GitHub never holds one of the `POOL_SIZE=2` render slots.
  A late blob write after the deadline hits a removed directory with `wx` and fails harmlessly.
- **API budget.** 2 sequential calls + N parallel blob calls (N ≤ 200, typically 3-4) per save, plus
  one re-list on a 409. Trees/Blobs/Contents read under the App's existing `contents` permission
  (`apps/web-platform/infra/github-app-manifest.json`).
- **Concurrent saves.** Pinning the render to its own commit means an older render can finish last.
  The model PUT uses the model blob sha from the rendered commit's listing, so a newer model already
  on HEAD makes the PUT fail (409/422) instead of being overwritten; the re-list decides retry vs
  superseded (Shape). This keeps today's "the newest save wins" outcome.
- **Path handling**: tree paths are `/`-separated relative to the diagrams subtree; `path.join` under
  `<dir>/src` and assert `resolved.startsWith(stageRoot + sep)`; violation → `io_error` (GitHub's own
  push checks reject `..`/`.git` paths, so no user-facing class).
- **RenderReason widening** (`hr-type-widening-cross-consumer-grep`): add `"unsafe_source"` (with
  `refusalClass`, `path`, `more`). Enumerate consumers with `tsc --noEmit` after the edit;
  `buildRerenderDiagnostic` changes from `(detail)` to taking the render result; the writer gains an
  explicit `unsafe_source` branch and a stage-failure branch.
- **Signatures**: `renderC4Model(stage: StageFn)`; `RerenderInput` keeps `installationId, owner, repo,
  workspacePath, userId, relativePath` (resync + Sentry need them) and gains `commitSha`.
- **Observability routing**: `unsafe_source` → `warnSilentFallback` (warning level; a tenant with a
  legitimate config would otherwise raise one error per save), with `extra.refusalClass`; everything
  else keeps `reportSilentFallback`.
- **No `import "server-only"`** in the new module (same reason as `c4-render.ts`).
- **Tests use an in-memory fake GitHub** (`apps/web-platform/test/helpers/fake-github-trees.ts`):
  a `{ path: { mode, bytes } }` map served through `vi.mock("@/server/github-api")` (precedent:
  `test/c4-project-route.test.ts`), parsing `?ref=` and `?recursive=1`, throwing the real
  `GitHubApiError` shape for 404, with the **verified quirks** (Contents listings report symlinks and
  submodules as `"file"`; Trees report true modes) and per-request overrides (`truncated`, stall,
  404-once, 409 on PUT). Its header records the `gh api` commands and date that verified the quirks.
  Synthesized fixtures only (`cq-test-fixtures-synthesized-only`); no git plumbing.

### Attack Surface Enumeration

| # | Path by which tenant content could reach the render | Closed by | Test |
|---|---|---|---|
| 1 | Tracked `likec4.config.{js,cjs,mjs,ts,cts,mts}` in the diagrams dir or a subdir | allowlist (never staged) + refusal | acceptance (real binary); stage table over all 9 names, top level and nested |
| 2 | Tracked `.likec4rc` / `likec4.config.json` / `.likec4.config.json` (`include.paths`) | same | same |
| 3 | Untracked config written into the worktree by an agent | the render takes no workspace path | Phase 1 RED row on the old signature; structural test afterwards |
| 4 | Tracked symlink (file, directory, `diagrams` itself, or a parent) | Trees mode 120000; Contents non-array / type ≠ "dir" | stage |
| 5 | Untracked symlink planted in the worktree | the render takes no workspace path | Phase 1 RED row; structural test |
| 6 | Tracked submodule | mode 160000; `diagrams` type ≠ "dir" | stage |
| 7 | `.git` tampering (objects, refs, HEAD, alternates, config) | not read | structural test |
| 8 | Hostile tree paths | under-root assertion | stage |
| 9 | Huge trees / many or large sources / API exhaustion | `truncated`, ≤ 200 sources, ≤ 16 MiB of sources, 10 s deadline | stage |
| 10 | Config in a parent of the stage dir (shared tmp) | measured C/D: no walk-up | acceptance: `TMPDIR` → a fixture root that holds a config |
| 11 | `icon`/`link`/cross-project `import` in `.c4` | measured L/M/N | none; residual documented |
| 12 | `git pull` hooks/fsmonitor during `syncWorkspace` | out of this fix | Phase 5.4 measures |
| 13 | The KB project route classifies Contents entries by `type === "file"` | reads content for the viewer; executes nothing | none; Non-Goal |

## User-Brand Impact

- **If this lands broken, the user experiences:** a `.c4` save through the Concierge or the diagram
  editor whose diagram stops re-rendering (the save still commits; the save message shows a
  diagnostic), or, if a refusal misfires on a benign tree, every save on their repo reporting
  "diagram not updated". A user who imported a LikeC4 repo with a legitimate `likec4.config.json`
  sees their diagram stay on the last committed render until they remove the config from the
  diagrams folder in GitHub. Under concurrent saves, a regression in the re-list logic could leave
  the diagram one save behind.
- **If this leaks, the user's data is exposed via:** the current code (what this fixes): a
  tenant-authored `likec4.config.mjs` runs as the app container's user, able to read the server's
  process environment (platform secrets) and other tenants' checkouts under `/workspaces`; a symlink
  or `include.paths` can pull another tenant's `.c4` sources into a model committed to the
  attacker's repo. After the fix, the known residual is the `git pull` path (Phase 5.4).
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: **approved-with-changes** at plan time (2026-09-24); the four changes (class-specific
copy, no "will update" copy on a recurring failure, Concierge instruction, the added user cases) are
folded in. `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Sentry events from the c4-rerender feature (op: render): warnSilentFallback for unsafe_source with extra.refusalClass, reportSilentFallback for io_error/timeout/empty_model/non_zero_exit/spawn_error; pino info line event=c4_rerender on success and event=c4_rerender_superseded on a superseded render"
  cadence: "per .c4 save (event-driven)"
  alert_target: "Sentry issue owners (existing c4-rerender grouping)"
  configured_in: "apps/web-platform/server/c4-writer.ts (rerenderAndCommit)"

error_reporting:
  destination: "Sentry web-platform project via @/server/observability (reportSilentFallback / warnSilentFallback)"
  fail_loud: "Sentry message 'c4 re-render failed — source committed, diagram stale' with extra.reason and, for unsafe_source, extra.refusalClass; the save response carries rerendered:false plus rerenderDiagnostic"

failure_modes:
  - mode: "tenant diagrams tree contains a likec4 config, symlink, submodule, or exceeds the caps"
    detection: "Sentry warning extra.reason=unsafe_source, extra.refusalClass in likec4-config|symlink|gitlink|too-large"
    alert_route: "Sentry issue owners; the user sees the diagnostic in the save response"
  - mode: "GitHub Contents/Trees/Blobs call fails, or staging exceeds its 10 s deadline"
    detection: "Sentry event extra.reason=io_error (detail prefix 'fetch:') or timeout (detail 'stage: deadline')"
    alert_route: "Sentry issue owners"
  - mode: "Contents API response carried no commit.sha"
    detection: "Sentry event op=render, extra.reason=io_error, detail 'no commit sha'"
    alert_route: "Sentry issue owners"
  - mode: "a regression refuses benign trees"
    detection: "unsafe_source warnings whose refusalClass does not match the repo tree; the must-PASS rows in CI"
    alert_route: "Sentry issue owners; CI red on the PR"

logs:
  where: "container stdout (pino) shipped to Better Stack; Sentry events"
  retention: "Better Stack plan retention; Sentry 90 days"

discoverability_test:
  command: "grep -o -m1 unsafe_source apps/web-platform/server/c4-render.ts"
  expected_output: "unsafe_source"
```

The Sentry side has no unauthenticated probe; the command proves the reason the events carry exists
in the shipped render module.

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-050** (`knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`),
  `## Amendment — 2026-09-24 (#8623): the render input is the committed source set, fetched from GitHub; never the tenant workspace`.
  State the general invariant — tenant workspace content (worktree **and** `.git`) is untrusted input
  to any server-side tool — and this component's application of it: `renderC4Model(stage)` stages only
  the regular-file LikeC4 source blobs of the diagrams subtree of the commit GitHub returned for the
  write, via the Contents/Trees/Blobs API, into a private `mkdtemp` dir, before taking a render slot,
  under a deadline; configs/symlinks/submodules/oversize are refused as `unsafe_source`; the model PUT
  is conditioned on the rendered commit's model sha. Correct, in the amendment, the Decision's "no …
  scope-escape surface" claim. Alternatives rejected: render in bwrap; local git objects with hash
  verification; in-worktree `lstat` staging; silently skipping configs.
- **Amend ADR-235**'s 2026-09-23 residual bullet on `c4-render.ts` to say it is closed by the ADR-050
  2026-09-24 amendment, recording the one deliberate difference from the resolver (the app takes
  bytes from GitHub because the tenant can write the local object store; the resolver trusts the
  operator's).
- No new ADR: this extends ADR-050 on the same component.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration:

- (a) External human actors: `founder` (the owner committing diagrams) — modeled.
- (b) External systems: `github` — modeled; `api -> github` exists (model.c4, the edge beginning
  "Workstream tab: reads connected-repo issues"). The likec4 CLI is a child process inside the app
  container; ADR-050 did not model it and this does not.
- (c) Containers/stores: `platform.webapp.api`, `connectedRepoKb` (`#external`),
  `platform.infra.workspacesVolume` — modeled.
- (d) Relationship that changes: the app now **reads** the diagrams sources from GitHub (Contents/Trees/
  Blobs) for the re-render, and it already **writes** `.c4` + `model.likec4.json` there via the
  Contents API; neither is described on the `api -> github` edge today.

Task: append to the existing `api -> github` edge's description one clause — `; AND the diagram-editor
re-render: commits the .c4 source and the rendered model.likec4.json (Contents API) and fetches ONLY
the regular-file LikeC4 source blobs of that commit's diagrams folder (Trees/Blobs API) to render in a
private staging dir — the repo's likec4 config, symlinks and submodules are refused, never loaded, and
the workspace clone is not read (ADR-050 amendment 2026-09-24)` — no new edge, so no view or count
change. Then regenerate `model.likec4.json` (`bash scripts/regenerate-c4-model.sh`) and run
`apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`,
`plugins/soleur/test/c4-count-parity.test.sh` and `plugins/soleur/test/c4-model-freshness.test.sh`.

### Sequencing

Single slice; the amendments describe the shipped state.

## Guard Contract

### Guard 1 — render-root allowlist

**Property.** The only files in the `likec4` process's working tree are regular-file `.c4`/`.likec4`/`.like-c4` blobs of the diagrams subtree of the commit GitHub returned for the write, byte-identical to those blobs.

**Assembly.** One chokepoint: `renderC4Model(stage)` creates the stage root and passes it to `stage`, the sole writer of that root, then spawns `runLikeC4` with `cwd` = that root. `runLikeC4` has one caller (`renderC4Model`); `renderC4Model` has one production caller (`rerenderAndCommit` ← `writeC4Diagram`), which both write surfaces funnel through (`PUT /api/kb/c4/[...path]`, the Concierge `edit_c4_diagram` tool), and it passes `stageCommittedC4Sources` as `stage`. `LIKEC4_BIN` appearing in any other file is outside the assembly and is caught by row 8.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `renderC4Model` given back a workspace path and spawning with `cwd` = the workspace diagrams dir | RED — structural test (no `"knowledge-base"` literal, no `readdir`/`opendir`/`lstat` in `c4-render.ts` or the stage module) and the acceptance "tracked config" row writes the sentinel |
| 2 | extension allowlist widened to "any regular file" | RED — stage test asserts the stage root's exact file set |
| 3 | config refusal deleted (config silently skipped) | RED — refusal rows expect `unsafe_source/likec4-config` (P3); security rows stay green via the allowlist |
| 4 | refusal checks only top-level entries; a config in `sub/` after a compliant top level | RED — nested row |
| 5 | config list reduced to `likec4.config.mjs` | RED — table row over all 9 names |
| 6 | symlink detection taken from the Contents listing type instead of the Trees mode | RED — the fake reports nested symlinks as `"file"` in listings, as GitHub does |
| 7 | a blob fetched or written before the full listing is classified | RED — refusal rows assert zero blob GETs and no `<dir>/src` |
| 8 | `LIKEC4_BIN` referenced in a second file under `apps/web-platform/{server,lib}` | RED — structural test |
| 9 | `renderC4Model` returns `ok:true` without spawning (dispatch vacuity) | RED — the real-binary happy path asserts the model's element ids equal the fixture's |
| 10 | staging moved back inside `acquire()` | RED — a stalled-stage row asserts a concurrent render still acquires a slot |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Control: the fixture map written to a directory and the real binary run **in place** | sentinel **written** — the fixture's config is live code |
| H2 | `LIKEC4_REQUIRED=1` without a resolvable binary | acceptance suite **fails**, not skips |
| H3 | Must-PASS non-canonical benign tree: a `.likec4` and a `.like-c4`, a nested source dir, `README.md`, `.gitkeep`, a 5 MiB `model.likec4.json`, a PNG, a `100755` `.c4` | `ok:true`; stage root holds exactly the 4 sources; no `too-large` from non-source bytes |
| H4 | The sentinel path is outside every temp dir the render removes in `finally` | "absent" cannot be satisfied by cleanup |
| H5 | H1 and the staged run use the same fixture map | the two arms render the same committed input |

**Anchor.** Config names and extensions are copied from the installed `likec4@1.50.0` dist; the
version is anchored across Dockerfile, package.json, ci.yml and `render-c4-model.sh` by
`c4-likec4-version-pin.test.ts`. A likec4 bump that adds a config name cannot load it (allowlist), so
staleness degrades only P3. The acceptance asserts against the real binary, not against our list.

## Implementation Phases

### Phase 1 — Measure (RED on current code)

1. `.github/workflows/ci.yml` `test-webplat` (a matrix job — one step covers both shards): add
   `npm install -g likec4@1.50.0` (the same literal as the other jobs, so `c4-likec4-version-pin.test.ts`
   pins it) and `LIKEC4_REQUIRED: "1"` in the "Run webplat tests (vitest --shard)" step's `env`.
2. Write `apps/web-platform/test/c4-render-tenant-config.test.ts` (real likec4; no module mocks of
   `child_process`/`fs`): write a workspace directory `knowledge-base/engineering/architecture/diagrams/`
   holding a valid `model.c4` (elements `u`, `s`) and a `likec4.config.mjs` that writes a sentinel
   **outside** every render temp dir; call the **current** `renderC4Model(workspacePath)`; assert the
   sentinel is absent. Add the untracked-config and untracked-symlinked-dir rows the same way (on the
   old signature these are the same directory). Binary from `LIKEC4_BIN` or PATH; if absent: throw when
   `LIKEC4_REQUIRED` is set, else skip with the install command printed (precedent:
   `test/helpers/engines-floor.ts`). `LIKEC4_BIN` is read at module load, so set it before importing
   (`vi.stubEnv` + dynamic import).
3. Run it on the current code → **must be RED**. Record the pre-fix commit SHA and the failing
   assertion lines (sentinel present/absent only — no config payload; CMO/CLO) for the PR body. Do not
   push Phase 1 alone: with `LIKEC4_REQUIRED` it reds CI; it lands with the fix.

### Phase 2 — Stage module (TDD)

1. `apps/web-platform/test/helpers/fake-github-trees.ts` (Technical Considerations).
2. `apps/web-platform/test/c4-stage-sources.test.ts` first: H3; all 9 config names top level and
   nested; nested symlink file and dir; `diagrams` itself a symlink and a submodule (Contents type
   `"file"`); a symlinked parent (Contents returns a non-array); gitlink; `truncated:true`; 201 sources;
   Σ source bytes > 16 MiB; path escaping the root → `io_error`; 404-once then success; stall → deadline;
   every refusal: zero blob GETs, no `<dir>/src`, `path` = first offender relative to `diagrams/`,
   `more` = the rest.
3. Implement `apps/web-platform/server/c4-stage-sources.ts` (`stageCommittedC4Sources`, the result
   type in Shape).

### Phase 3 — Wire the render

1. `c4-render.ts`: `renderC4Model(stage)`; `mkdtemp` → stage `<dir>/src` under the deadline → `acquire()`
   → `runLikeC4(<dir>/src, <dir>/model.likec4.json)` → `release()`; map stage results onto
   `RenderResult` (pass `modelSha` through); keep the element gate, canonicalize, `finally rm`. Rewrite
   the module's SECURITY comment to state the new boundary.
2. `c4-writer.ts`: `RerenderInput` + `commitSha`; missing sha → no render, `reportSilentFallback`
   (`op: "render"`, `extra.reason: "io_error"`, "no commit sha") + the retry diagnostic; build `stage`
   from `stageCommittedC4Sources`; `unsafe_source` → `warnSilentFallback` + class diagnostic;
   stage `io_error`/`timeout` → retry diagnostic; model PUT with the listing's model sha and the
   409/422 re-list rule; `buildRerenderDiagnostic` takes the render result.
3. `c4-concierge-tools.ts` description and `cc-dispatcher.ts` `c4PromptAddendum`: relay
   `rerenderDiagnostic` when present, never promise a refresh then, and say unsupported files must be
   changed in the GitHub repository.
4. `c4-render.test.ts`: pass a fake `stage` (no `vi.mock` of the stage module); spawn `cwd` asserted
   equal to `<TMP_DIR>/src`; `-o` = `<TMP_DIR>/model.likec4.json`; keep `writeFile`/`copyFile`/`rename`
   never-called (`c4-render.ts` itself writes nothing); stage-failure mapping; row 10 (a stalled stage
   does not hold a slot).
5. `c4-writer-rerender.test.ts`: `commitSha` threaded; missing-sha case; one case per diagnostic row;
   `warnSilentFallback` for `unsafe_source`; PUT sha from the listing; 409 → same sources → retried;
   409 → different sources → superseded (no Sentry, no diagnostic).
6. Acceptance suite switches to `renderC4Model(stage)` with the fake built from the same fixture map
   (H5) and a real `stageCommittedC4Sources`: tracked config → `unsafe_source/likec4-config`, sentinel
   absent; benign fixture → `ok:true`, element ids exactly `{u, s}`; `TMPDIR` pointed at a fixture root
   holding a sentinel-writing `likec4.config.mjs` → not executed; H1 control still writes the sentinel.
7. Structural test `apps/web-platform/test/c4-render-boundary.test.ts` (rows 1 and 8): `c4-render.ts` and
   `c4-stage-sources.ts` contain no `"knowledge-base"` literal and no `readdir(`/`opendir(`/`lstat(`;
   the identifier `LIKEC4_BIN` occurs only in `server/c4-render.ts`.

### Phase 4 — Records

1. ADR-050 amendment; ADR-235 residual bullet.
2. `api -> github` edge clause; regenerate `model.likec4.json`; run the four C4 suites.
3. Exposure assessment (CLO): `knowledge-base/legal/audits/2026-09-24-8623-c4-render-exposure-assessment.md`
   in the REACHABILITY-ONLY form of `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`
   (awareness anchor 2026-09-23, the issue's filing) plus one row in
   `knowledge-base/legal/breach-register.md`. Limbs: **L1** which identities have ever had
   `c4-visualizer` on with a connected repo (Flagsmith, via `soleur:flag-list`); **L2** a read-only
   GitHub App scan of connected repos for the 9 config names, symlinks and gitlinks under the diagrams
   dir, at HEAD and in history (commits API `path=` per name). A limb that cannot run is recorded
   INCONCLUSIVE with the reason, never as clean. No tenant identifiers in either file (public repo).
   Evidence of use → fresh 72 h Art. 33 clock and secret rotation. Non-gating for the code merge.

### Phase 5 — Verify

1. From `apps/web-platform`, with `LIKEC4_BIN` pointing at a `likec4@1.50.0`:
   `./node_modules/.bin/vitest run test/c4-stage-sources.test.ts test/c4-render.test.ts test/c4-writer-rerender.test.ts test/c4-render-tenant-config.test.ts test/c4-render-boundary.test.ts test/c4-likec4-version-pin.test.ts`.
2. `./node_modules/.bin/tsc --noEmit` from `apps/web-platform` (the enumerator for `RenderReason` consumers).
3. Record the CI time the likec4 install adds per `test-webplat` shard in the PR body.
4. Sibling measurement (non-gating): whether a sandboxed agent can write `<workspace>/.git/hooks/*` and
   `<workspace>/.git/config` (the SDK's effective sandbox settings or a dev-session probe). Writable →
   private GitHub Security Advisory; denied → evidence in the PR body.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Render inside the bwrap agent sandbox | Rejected (Cut List): contains execution instead of removing it; sandbox orchestration on the synchronous save path. |
| Local git objects from GitHub's commit sha with per-object hash verification | Rejected after CTO + advisor review: the agent can write `.git/objects`, `refs`, `HEAD`, `objects/info/alternates`; correctness then needs Merkle verification, tree parsing, git env hardening, gitfile/alternates/promisor-fetch handling (git in `node:22-slim` predates `GIT_NO_LAZY_FETCH`). GitHub is outside the tenant's write reach for ~3 calls. |
| Resolver-style `git ls-tree` + `git cat-file blob` from local `HEAD` | Rejected: trusts an agent-writable object store and a movable `HEAD`. |
| Stage from the worktree with `lstat`/`O_NOFOLLOW` | Rejected: includes untracked agent-written files; TOCTOU against a concurrently writing agent. |
| Silently skip configs/symlinks | Rejected: commits a model different from what the repo declares (P3); mirrors the resolver's refusal. |
| One GraphQL `object(expression: "<sha>:<dir>")` call | Not chosen: fixed nesting depth and `Blob.text` truncation semantics to verify; REST is 2 calls + parallel blobs. |
| A likec4 flag to ignore configs | None in 1.50.0's `export json`; would also leave symlink handling to the tool. |
| Model PUT keyed on HEAD's model sha (today) | Rejected with commit pinning: an older render finishing last would overwrite the newer model. |

## Non-Goals

- The element-count-only gate (a trailing syntax error can yield a partial model at rc 0).
- Hardening `syncWorkspace`'s `git pull` (Phase 5.4 measures; private advisory if open).
- Deterministic staging paths for relative `icon` URLs.
- The pre-existing "will update after re-render" copy for render timeouts, spawn errors and oversize models.
- The KB project route's Contents-type classification (`app/api/kb/c4/project/route.ts`): it reads
  content for the viewer and executes nothing.

## Plan Review Revisions (v2, 2026-09-24)

Five-agent eng panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) plus
the named panel (CTO devex, CMO copy). Applied:

- **Cut** (DHH + simplicity converged): blob sha1 re-hash; the `name` refusal class (path violations
  are `io_error`); the git-backed test fake (in-memory map now); post-fix "untracked" acceptance rows
  (they run as Phase 1 RED rows on the old signature; a structural test replaces them); the 2,000-entry
  and per-blob caps; the dedicated missing-sha template; Phase 0 as a merge gate (sandbox measurement is
  Phase 5.4, the legal record Phase 4.3, both non-gating); the new C4 edge (a clause on `api -> github`).
- **Fixed** (Kieran, architecture, spec-flow): staging before `acquire()` under a 10 s deadline; 404/422
  retry on the first read; a ≤ 200-source cap and Σ over sources only; non-array / missing-`diagrams`
  handling; conditional model PUT with re-list on 409 (older render can no longer overwrite a newer
  model); the result type carries `path`/`more`; `RerenderInput` keeps its fields; the diagnostic builder
  signature; injected `stage` function (no GitHub coupling in `c4-render.ts`); `-o` outside `src`
  without an `out/` dir (the test mock has no `mkdir`); the `cc-dispatcher.ts` prompt addendum;
  `warnSilentFallback` for refusals; deterministic `TMPDIR` row; one install step on the matrix job with
  `LIKEC4_REQUIRED` on the run step; pre-fix SHA recorded; discoverability probe prints a literal.
- **Copy** (CPO + CMO + spec-flow): "Saved — diagram not updated: …", quotes not backticks, relative
  path + "(and N more)", "in your GitHub repository", an action on too-large, "Save again to retry".
- **Kept against one reviewer**: `LIKEC4_REQUIRED` (simplicity proposed plain `CI`; `CI` is set in other
  vitest runs, e.g. `tenant-integration.yml`); the real-binary suite in `test-webplat` (DHH proposed
  `test-scripts`, which has no web-platform `npm ci`); "not known to have been exploited; assessment
  pending" in the PR body (CLO over CMO — the qualifier is accurate until the limbs run).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 max) has no body naming
`c4-render.ts`, `c4-writer.ts`, `c4-render.test.ts`, `c4-render` or `likec4`.

## GDPR Gate (plan Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Invoked on trigger (b) (threshold `single-user incident`); no canonical-regex path is in the file
lists (no migration, auth module, `app/api` route or `.sql`). The five v1 checks: `GDPR-Art-6`,
`GDPR-Art-5e`, `GDPR-Art-17`, `GDPR-Art-9` — no schema change, not fired; `GDPR-Chapter-V` — no new
vendor (GitHub is an existing processor already reached by this writer), not fired. One
**Suggestion** (Art. 32/33): the fix narrows processing; the exposure-assessment record and
breach-register row (Phase 4.3) are the Art. 33(5) documentation, per the CLO assessment. No Critical
finding; no `compliance-posture.md` write.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6.
- The Contents API lists symlinks and submodules as `"file"` (verified). Any classification taken from
  a Contents listing instead of Trees modes silently re-opens the symlink path (Guard row 6).
- `c4-render.test.ts` mocks all of `node:fs/promises` (no `mkdir`): `c4-render.ts` must not create
  directories itself — the stage function creates `<dir>/src`.
- The acceptance suite must not `vi.mock` `child_process` or `fs` (it proves real execution); keep it a
  separate file from `c4-render.test.ts`.
- `LIKEC4_BIN` is captured at module load; tests set it before a dynamic import.
- The row-8 structural test must key on the identifier `LIKEC4_BIN`, not the token `likec4`: comments
  in `c4-writer.ts`, `c4-concierge-tools.ts` and elsewhere legitimately name the CLI.
- Enumerate `RenderReason` consumers with `tsc --noEmit` after the union edit (the compiler is the
  enumerator); a grep is a cross-check.
- The model PUT must use the sha from the rendered commit's listing, never a fresh HEAD read, or the
  concurrency guarantee silently disappears.

## Acceptance Criteria

- [ ] `apps/web-platform/test/c4-render-tenant-config.test.ts` places a sentinel-writing `likec4.config.mjs` in a tenant diagrams dir and asserts the server render never executes it, with the real `likec4@1.50.0`; the PR body records it RED at the pre-fix commit SHA (with the untracked-config and untracked-symlink rows) and GREEN after.
- [ ] Same suite: a benign fixture renders `ok:true` with element ids exactly `{u, s}`; with `TMPDIR` pointed at a fixture root holding a sentinel-writing config, the sentinel stays absent; control H1 writes the sentinel in place; the suite throws when `LIKEC4_REQUIRED` is set and no binary resolves (H2).
- [ ] `test-webplat` installs `likec4@1.50.0` and sets `LIKEC4_REQUIRED=1` on its run step; `c4-likec4-version-pin.test.ts` green.
- [ ] `apps/web-platform/test/c4-stage-sources.test.ts` covers every "stage" row of the Attack Surface table and Guard 1 rows 2-7; each refusal returns its `refusalClass`, the first offender's path relative to `diagrams/` and `more`, makes zero blob requests, and creates no `<dir>/src`; H3 stages exactly the 4 sources.
- [ ] `renderC4Model(stage)` takes no workspace path, stages before `acquire()` under a 10 s deadline, and spawns `likec4` with `cwd` = `<dir>/src` and `-o` = `<dir>/model.likec4.json`; `c4-render-boundary.test.ts` (rows 1, 8) and the stalled-stage row (row 10) green.
- [ ] `writeC4Diagram` threads GitHub's `commit.sha`; a missing sha skips the render with the retry diagnostic and a Sentry event.
- [ ] Each diagnostic row in "Behaviour changes a tenant can see" is asserted verbatim in `c4-writer-rerender.test.ts`; `unsafe_source` goes through `warnSilentFallback` with `extra.refusalClass`; no failure row yields the "will update after re-render" copy except superseded.
- [ ] Model PUT carries the rendered commit's model sha; a 409 with an unchanged source set retries once, a 409 with a changed source set is superseded without a Sentry event (both tested).
- [ ] `c4-concierge-tools.ts` and `cc-dispatcher.ts` no longer promise a refresh when `rerenderDiagnostic` is present, and name the GitHub repository as where unsupported files are changed.
- [ ] ADR-050 amended; ADR-235 residual bullet updated; `api -> github` edge clause added; `model.likec4.json` regenerated; `c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness` green.
- [ ] Exposure assessment record and breach-register row exist with every limb run or marked INCONCLUSIVE with its reason, and contain no tenant identifiers.
- [ ] `tsc --noEmit` clean in `apps/web-platform`.

## Domain Review

**Domains relevant:** engineering, legal, product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Approach sound; the ordering gap was the `git pull` question, now a non-gating measurement (Phase 5.4) since the render no longer reads the workspace. Flagged the
local-objects design's repo-local-config/promisor-fetch and gitfile risks and suggested re-comparing
the GitHub fetch; adopted (see Alternatives). Asked for a multi-project `import` check (measured, N),
keeping `-o` outside the stage root (Phase 3.4), and extending the single-site grep to
`execFile`/`execa` (row 10). ADR-050 amendment is the right record. Complexity: medium.

### Legal (CLO)

**Status:** reviewed
**Assessment:** A vulnerability alone is not an Art. 4(12) breach; no Art. 33/34 duty on the facts
given, but "no known exploitation" must be checked: L1 (flag population) and L2 (repo scan) in a
REACHABILITY-ONLY assessment record plus a breach-register row (Phase 4.3). PR body: factual, "not
known to have been exploited; assessment pending", harmless sentinel, no working exploit. A confirmed
`git pull` vector goes to a private security advisory, not a public issue. No Art. 30 change, no
policy edits, no TC_VERSION bump. Low-priority gap noted: no `SECURITY.md`.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo, soleur:marketing:cmo (plan-review named panel, copy lens)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface — server-side diagnostic strings shown in the existing save message)

#### Findings

CPO sign-off **approved-with-changes**; all four changes applied: class-specific diagnostics leading
with the skip and one action; no "will update" copy on a recurring failure; the Concierge tool
instruction against deleting files without confirmation; the legitimate-config user and the
persistent stale-diagram case in User-Brand Impact.

## Test Scenarios

- Given a tracked `likec4.config.mjs` that writes `$SENTINEL`, when `renderC4Model` runs, then it returns `unsafe_source`/`likec4-config` with path `likec4.config.mjs`, no blob is fetched, and `$SENTINEL` does not exist.
- Given the same fixture, when the real likec4 runs in place (control), then `$SENTINEL` exists.
- Given the pre-fix code and a workspace with a config (tracked or untracked) or a symlinked directory, then the Phase 1 rows are RED (measurement).
- Given `TMPDIR` pointing at a directory that holds a sentinel-writing `likec4.config.mjs`, when a benign tree renders, then `ok:true` and `$SENTINEL` does not exist.
- Given each of the 9 config names at top level and in `sub/`, then `unsafe_source`/`likec4-config` with the relative path; given two offenders, then `more: 1` and the diagnostic ends "(and 1 more)".
- Given a nested symlink (file or directory) that the Contents listing reports as `"file"`, then `unsafe_source`/`symlink` from the Trees mode.
- Given `diagrams` itself a symlink or submodule, or a symlinked parent (non-array Contents response), then `unsafe_source`/`symlink` or `gitlink`.
- Given `truncated:true`, 201 sources, or more than 16 MiB of sources, then `unsafe_source`/`too-large` before any blob request; given a 5 MiB `model.likec4.json` and a PNG beside 4 sources, then `ok:true`.
- Given the first Contents call returns 404 once, then the retry succeeds; given a stalled GitHub, then `timeout` "stage: deadline" within the deadline and no render slot is held meanwhile.
- Given a benign tree (H3), then exactly the 4 sources are staged and the render returns `ok:true`.
- Given two saves whose renders finish out of order, then the newer source set's model is on HEAD afterwards (409 → superseded for the older; 409 → retried for the newer when HEAD's sources match).
- Given a Contents API response without `commit.sha`, then no render runs, the diagnostic is "diagram not updated for this save. Save again to retry.", and `reportSilentFallback` fires with `io_error`.

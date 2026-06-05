---
title: "\"Never do X at runtime\" (for a bundle-dep reason) often means \"never IMPORT the toolchain\" — an out-of-process CLI spawn sidesteps it"
date: 2026-06-05
category: best-practices
module: apps/web-platform/server
tags: [architecture, child-process, lockfile, dockerfile, likec4, constraint-precision]
related_pr: 4965
related_issue: 4964
related_adr: ADR-050
---

# "Never do X at runtime" (for a bundle-dep reason) often means "never IMPORT the toolchain"

## Problem

The LikeC4 visualizer had a documented hard constraint — **"never render the diagram
at runtime"** — encoded in `lib/c4-constants.ts` and `app/api/kb/c4/project/route.ts`.
The stated reason: the `likec4`/`@likec4/language-services`/`@likec4/layouts` toolchain
drags vite/esbuild/bundle-require into prod deps and breaks the npm10/npm11
lockfile-sync parity that prod `npm ci` requires.

Taken at face value, that rule blocked the feature the user actually wanted: the
rendered diagram updating after a Code-tab Save (it was regenerated only out-of-band
via a manual `/soleur:architecture render`).

## Solution

Read the constraint precisely. The lockfile-parity reason only bites if the toolchain
becomes a **`package.json` dependency that the bundler resolves** — i.e. if you
`import` it. It says nothing about *running* the toolchain. So:

- **Preinstall the CLI as a Dockerfile global** (`RUN npm install -g likec4@1.50.0`),
  NOT a `package.json` dep. Nothing enters the lockfile; vite/esbuild never reach prod
  deps; `npm ci` parity is untouched.
- **Spawn it out-of-process** with `child_process.spawn` (fixed argv, scoped env,
  bounded timeout — model on an existing spawn helper like `server/pdf-linearize.ts`),
  never `import` it. The server process can run a CLI; only the *bundle* must stay lean.

This reframes the rule from "never render at runtime" to the precise "never **import**
the heavy toolchain into the prod bundle" — and the feature ships at runtime, in-process,
without violating the original concern. (Full decision: ADR-050.)

## Key Insight

When a hard rule is phrased as a *behavior* prohibition ("never X at runtime") but its
stated *reason* is a narrower mechanism ("because it pulls Y into the bundle / lockfile /
client"), the behavior is often achievable by a path that avoids the mechanism. Before
accepting "can't be done," restate the rule as the mechanism it actually protects, then
ask whether a different execution path (spawn vs import, server vs client, out-of-process
vs in-bundle) sidesteps that mechanism. Here: spawn-not-import. The "@anthropic-ai/claude-code"
Dockerfile global was the existing precedent that proved the pattern was already sanctioned.

**Companion guard (mandatory when you do this):** a CLI preinstalled in the Dockerfile
that must match a library version in `package.json` (so its output schema matches what the
library consumes) is a coupling that `tsc` and the lockfile cannot see — it lives across
two files in two languages. Add a source-read drift-guard test asserting the Dockerfile
pin equals the package.json version (`test/c4-likec4-version-pin.test.ts`), or a future
bump of one silently breaks the other.

## Session Errors

- **Test mock had to track a SUT read-API change (readFile → open) introduced during the
  review pass.** The security review flipped `c4-writer.ts` from `readFile(path)` to
  `open(path, O_RDONLY|O_NOFOLLOW)` + fd-stat for symlink/TOCTOU hardening; the
  integration test's `node:fs/promises` mock (`{ readFile }`) then had to become
  `{ open }` returning a fake FileHandle (`stat`/`readFile`/`close`).
  **Prevention:** normal TDD churn — when a review fix changes a module's I/O primitive,
  grep its test files for the old primitive's mock and update in the same edit. One-off,
  not a recurring gap.

## Tags
category: best-practices
module: apps/web-platform/server

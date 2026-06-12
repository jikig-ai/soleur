# Learning: image-baking @playwright/mcp for a firewalled cron + lockfile hygiene when adding a dep

## Problem

Restoring `cron-ux-audit` (#5199) required its Playwright MCP server to actually
launch inside the egress-firewalled cron. The plan assumed "pin `@playwright/mcp`
+ image-bake" was a one-line change. It was not — two packaging traps surfaced,
plus a lockfile-hygiene foot-gun that wasted several cycles.

## Root causes & solutions

### 1. `@playwright/mcp`'s `playwright-core` is an ALPHA that `next`'s peerOptional rejects

`@playwright/mcp@0.0.76` (latest stable tag) depends on
`playwright`/`playwright-core@1.61.0-alpha-1781023400000`. The prod image baked
Chromium `1.58.2` (pinned to `@playwright/test`). So even baking the npm package
left the MCP's playwright-core wanting a *different* Chromium revision → a runtime
browser download against the (non-allowlisted) CDN → blocked egress → cron fails.

**The trap:** bumping `@playwright/test` to the matching alpha breaks `npm ci`:
`next@15.5.18` declares `peerOptional @playwright/test@"^1.51.1"`, and a
prerelease (`1.61.0-alpha-…`) is **excluded from a `^` range** by semver. No
`.npmrc legacy-peer-deps`, so `npm ci` (the Dockerfile deps stage) errors ERESOLVE.

**Solution:** keep `@playwright/test@^1.58.2` (stable, satisfies `next`; the e2e
suite runs in CI, NOT the prod image), add `@playwright/mcp@0.0.76` to
`dependencies`, and bake ONLY the cron's browser revision in the Dockerfile:
`npx playwright@1.61.0-alpha-1781023400000 install --with-deps chromium`. The
e2e `@playwright/test` and the cron's `@playwright/mcp` playwright-core coexist as
two nested `playwright-core` versions in `node_modules` — no peer conflict
(`@playwright/mcp`'s deps are regular, not peer). A drift guard
(`playwright-mcp-version-pin.test.ts`) asserts the Dockerfile install version ==
`@playwright/mcp`'s resolved nested `playwright-core` in the lockfile.

**Generalizable:** to bake a browser for a firewalled runtime, align the baked
revision with the *consuming package's* playwright-core, not the app's top-level
playwright. They are independent; the prod image only runs the consumer.

### 2. NEVER `rm package-lock.json` to add a dependency

To add `@playwright/mcp` I ran `rm -f package-lock.json && npm install
--package-lock-only`. This regenerates the lockfile from scratch → **9379
insertions / 12681 deletions** of reordered/reformatted entries (unreviewable,
risks changing transitive resolutions) AND left `node_modules/.bin` empty
(`tsc`/`vitest` → exit 127).

**Solution:** restore the original (`git checkout package-lock.json`) and run a
plain `npm install` against the *existing* lock — npm makes a **minimal** mutation
(74 insertions, 0 deletions: just `@playwright/mcp` + its nested deps). Then
`npm ci` to rebuild `node_modules/.bin` if a prior botched install emptied it.
Validate the Dockerfile path with `npm ci --dry-run` (catches peer/sync errors
before they fail the image build). This mirrors the surgical-lockfile-edit
discipline in `work-lockfile-bumps.md` but for an intentional dependency ADD.

## Key insight

A "pinned dependency" for a firewalled runtime is a THREE-way coupling
(package.json version ↔ lockfile nested playwright-core ↔ Dockerfile browser
install) with no compiler check — only a source-read drift-guard test catches a
desync, which would otherwise fail only at cron runtime inside the container (the
hardest place to diagnose, per the no-SSH rule). And the lockfile is append-only
for a dep add: `rm`+regenerate is never the move.

## Session Errors

1. **Collision gate aborted first `/one-shot` run on closed contextual ref `#5046`** — Recovery: re-invoked with `#5046` scrubbed to date-anchored prose. Prevention: when routing prose args into one-shot, scrub closed predecessor `#N` refs at args-authoring time (already documented: `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`).
2. **Bash CWD drifted to bare-repo root repeatedly** (`cd: No such file`, `tsc: 127`) — Recovery: absolute paths / single `cd "$W" && …`. Prevention: already covered by `hr-when-in-a-worktree-never-read-from-bare`; never rely on persisted CWD across Bash calls.
3. **`rm package-lock.json` caused 9379/12681-line full-regen churn** — Recovery: `git checkout` + minimal `npm install`. Prevention: never `rm` the lockfile to add a dep (this learning §2).
4. **Full `npm install` left `node_modules/.bin` empty** (tsc/vitest 127) — Recovery: `npm ci`. Prevention: after a lockfile mutation, `npm ci` to rebuild `.bin`; validate with `npm ci --dry-run`.
5. **`@playwright/test`→alpha bump broke `npm ci`** (next peerOptional rejects prerelease) — Recovery: kept `@playwright/test` stable, baked only the cron browser. Prevention: this learning §1.
6. **Plan underestimated the packaging blocker** — Recovery: surfaced to operator via AskUserQuestion before taking on a risky app-wide change. Prevention: when a plan defers a runtime-packaging question to /work ("confirm at /work"), resolve it BEFORE committing to the scope it implies.
7. **Concurrent review agent edited the hook mid-review** — Recovery: re-read on-disk state before applying my fix. Prevention: already documented review sharp-edge (verify `git diff HEAD` after agents return).

## Tags
category: integration-issues
module: apps/web-platform/server/inngest (cron substrate), packaging

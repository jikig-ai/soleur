# Learning: `npm --before` freezes a dependency tree, but it is silently inert without publish times

## Problem

CI run 36726970979 (#9300) died twice on `npm install -g likec4@1.50.0`: `source-map-js-1.2.2.tgz`, then `electron-to-chromium-1.5.443.tgz`, each returned `E404` from npm's CDN minutes after publication. Pinning `likec4@1.50.0` pins one package; its ~190-node transitive tree resolves to the newest releases at run time.

## Solution

Resolve the tree as of a fixed past date at every site that resolves it: `npm install -g likec4@1.50.0 --before=2026-09-28` in the three `ci.yml` install steps and the main-health-monitor, and `--before` on the two plugin `npx` call sites (`render-c4-model.sh`, `generate-c4-from-components.ts`). The version and the date are a pair; the bump procedure lives once under `BUMPING LIKEC4` in `render-c4-model.sh`. A parity guard (`checkLikec4Pins` in `apps/web-platform/test/c4-likec4-version-pin.test.ts`) keeps every site on one date at least 3 days old.

## Key Insight

Four measured facts that were not in the issue and that decided the design:

1. **Pin the `npx` sites too.** `npm i -g` populates the download cache that a later `npx` reuses. An unpinned install followed by an unpinned `npx` fetched 0 tarballs from the network; a `--before` install followed by an unpinned `npx` fetched 4, including the very tarball that 404'd. Pinning only the install step moves the flake onto the `npx` call.
2. **A lockfile is the wrong tool here.** A tools package with `npm ci` hoists likec4's dependencies into sibling `node_modules/*` directories, and `server/c4-render.ts` binds only the likec4 package directory into its bwrap sandbox: 5 of 15 `c4-render-tenant-config` tests failed on the hoisted layout and 15/15 passed on the global layout. A lockfile also cannot be consumed by `npx`.
3. **`--before` is silently ignored when the registry's packument has no `time` field.** Measured against npm's own `npm-pick-manifest`: with no `time` it resolves the newest version with no error, with full `time` it resolves the older one, and only an exact version newer than the date raises `ETARGET`. So a private registry mirror that omits per-version publish times turns the pin off without any signal. The first draft of the header claimed the opposite ("fails with ETARGET"); the claim survived the plan, deepen and the author's own checks and was caught by the architecture seat, then confirmed with a 10-line `node` probe.
4. **A cap on a guard's discovery is a claim about every spelling.** A scanner that finds sites by one regex reports clean for a site spelled `npm i -g`, `--global`, a flag in a trailing comment, or a line the comment-stripper wrongly drops (`*)` is a shell case arm, not a block-comment continuation). Add a census (every non-comment line naming the tool must be a recognised site) and pin the site count.

## Session Errors

1. **A causal claim written into the BUMPING LIKEC4 header (a mirror fails with ETARGET) was never measured.** Recovery: corrected after the architecture seat's report and a direct `npm-pick-manifest` probe. **Prevention:** before writing a sentence about a vendor tool's failure mode, run the 10-line probe that shows it; the existing "falsify every claim your diff adds" rule already covers this and was not applied.
2. **The first `export json` extraction matched a human hint echo as a second site.** Recovery: key the shell extraction on `--ignore-scripts.*export json`. **Prevention:** when extracting one call from a script, run the extractor against the real file before writing the assertion.
3. **A new test row's `replace()` hit the header comment instead of the real line.** Recovery: anchor the replacement on text only the real line carries. **Prevention:** a fixture mutation built with `String.replace` needs a landing assertion on the construct, not on the file.
4. **`tsc --noEmit` ran out of heap at the default limit on `apps/web-platform`.** Recovery: `NODE_OPTIONS=--max-old-space-size=6144`. **Prevention:** none needed beyond the flag.
5. **`gh issue create` was refused by the filing hook (no user-visible consequence).** Recovery: re-filed with `--label meta/machinery`. **Prevention:** none; the hook did its job and its message named the exit.

## Tags

category: integration-issues
module: ci, c4-render, npm

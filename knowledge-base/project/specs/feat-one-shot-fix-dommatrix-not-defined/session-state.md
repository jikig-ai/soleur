# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-dommatrix-not-defined/knowledge-base/project/plans/2026-05-07-fix-pdfjs-dommatrix-bundled-server-plan.md
- Status: complete

### Errors
None.

### Decisions
- Identified actual root cause via live Sentry event lookup. Event `e8225a569fcd4b07a460b5b1bb2a5ee7` shows `runtime: node v22.22.1` (already past engines floor) and stack `/app/dist/server/index.cjs : __init` inside `node_modules/pdfjs-dist/legacy/build/pdf.mjs`. Recent commits 40ba6a27 / 19525cff (engines pin + lockfile) do NOT fix the production failure — they were correct work for an adjacent test-runner-Node-21 problem. The real fix is externalizing `pdfjs-dist` from the esbuild server bundle AND Next.js `serverExternalPackages` so the legacy entry's `if (isNodeJS) { ... DOMMatrix polyfill }` block runs in the correct module-init order under Node's ESM loader instead of being hoisted/reordered by the bundler.
- Three coordinated edits: (a) add `--external:pdfjs-dist` to `apps/web-platform/package.json:scripts.build:server`, (b) add `"pdfjs-dist"` to `serverExternalPackages` in `next.config.ts`, (c) fold in open issue #3342 (Buffer→Uint8Array no-copy view in `kb-preview-metadata.ts`) since it touches the exact same file/lines.
- Two new bundled-server regression tests that bundle a fixture entry with the EXACT `build:server` flag set and exec the resulting `.cjs` via Node — vitest's source-only path cannot catch this class of bug because it never builds the production CJS.
- Verified all citations live: Context7 docs for esbuild `--external` and Next.js `serverExternalPackages`, installed type-defs, `gh pr view`/`gh issue view` for all referenced PRs (#3338/#3353/#3391/#3393 MERGED, #3342/#3377 OPEN), local `npx esbuild --help` for flag form.
- User-Brand Impact threshold: `aggregate pattern`. Every Concierge PDF summarize call has been silently degrading to the unreadable-fallback prompt for the ~3-week life of #3338. No data-exposure path; no `single-user incident` threshold; no CPO sign-off required.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Bash (git/grep/find/jq/curl/gh/doppler/docker)
- Read, Edit, Write
- WebFetch, mcp__plugin_soleur_context7__query-docs
- Live Sentry API call via curl, live `gh issue view` / `gh pr view`

# Learning: post-build token gates false-positive on worktree directory paths

## Problem

`apps/web-platform/scripts/assert-dev-signin-eliminated.sh` (R3 / feat-dev-signin-bypass) is a post-`next build` grep gate that fails the prd Docker image build if forbidden source-level identifiers leak into client chunks. The token list included the bare string `dev-signin` (the feature flag key in `FLAG_VARS`).

When run against a fresh `npm run build` from the worktree at `.worktrees/feat-dev-signin-bypass`, the gate flagged `.next/static/chunks/9b0008ae.<hash>.js` — a Webpack-emitted client chunk for pdfjs-dist. Investigation showed the pdfjs build embeds the *absolute file path* of `pdf.mjs` into a `createRequire("file:///...")` call:

```
file:///home/harry/Documents/Stage/Soleur/soleur/.worktrees/feat-dev-signin-bypass/apps/web-platform/node_modules/pdfjs-dist/build/pdf.mjs
```

The substring `dev-signin` matches inside `feat-dev-signin-bypass`. This is a false positive — the actual flag key never reached client code; only the worktree directory name did.

In CI (Docker context starts at `/app`), the embedded path would be `/app/node_modules/pdfjs-dist/build/pdf.mjs` with no `dev-signin` substring — so the gate would pass. But local dev verification was broken, and any future contributor whose worktree happens to contain a forbidden substring would hit the same false positive.

## Solution

Tighten the token to its quoted source form:

```diff
-  "dev-signin"
+  '"dev-signin"'  # the quoted form as it appears in FLAG_VARS
```

The bundled output for `lib/feature-flags/server.ts` retains the JSON-style quotes around the flag key (`"dev-signin": "FLAG_DEV_SIGNIN"`). Path-substring false positives don't carry the surrounding quotes, so the quoted token is precise.

The header of the script now documents the rationale (`apps/web-platform/scripts/assert-dev-signin-eliminated.sh:11-25`) so a future audit doesn't re-litigate why the bare token isn't sufficient.

## Key Insight

**Post-build forbidden-token gates whose tokens are substrings of the worktree directory name will false-positive in any branch named after the feature.** Module bundlers that bake absolute paths into client output (pdfjs-dist via `createRequire("file:///...")`, sometimes Sentry source maps via `__filename`) propagate the worktree path verbatim.

When designing such a gate:

1. **Prefer tokens with structural delimiters** (JSON quotes, identifier-character boundaries, regex anchors) over bare substrings. `"dev-signin"` is precise; `dev-signin` is not.
2. **Test the gate against a fresh build in a worktree whose name contains the feature slug** — that is the false-positive litmus that CI's `/app` context cannot reproduce.
3. **Treat the worktree path as an attacker** for substring tests: the directory name will appear inside `node_modules/**` artifacts that legitimately ship in client bundles.
4. **Don't narrow scope to dodge a false positive** unless the narrowing is independently justified. The R3 gate's scope-narrowing from `.next/server/**` to `.next/static/**` + `server-reference-manifest.js` was justified separately (App Router compiles route handlers into the server bundle unconditionally — server-bundle inclusion of dev-only route is by design).

## Session Errors

- **Parallel Bash CWD desync** — two parallel `Bash(cd ...)` calls fired before CWD was committed, the second errored. Recovery: chained `cd ... && <cmd>` in single calls. Prevention: never split `cd` and dependent commands across parallel calls.
- **TS rejects `process.env.NODE_ENV = "production"`** (TS2540 readonly). Recovery: switched to `vi.stubEnv("NODE_ENV", ...)`. Prevention: adopt the codebase's existing `vi.stubEnv` precedent (`test/validate-origin.test.ts`) from the start when writing NODE_ENV-sensitive tests.
- **TS narrowing makes `=== "production"` impossible after Layer A early return** (TS2367). Recovery: hardcoded `false` with comment explaining the narrowing. Prevention: when copy-pasting an expression from another file, account for type narrowing at the new call site.
- **Grep-gate false-positive on worktree path** (the topic of this learning).
- **CSRF coverage gate caught new POST route after route-specific tests passed** — `lib/auth/csrf-coverage.test.ts` is the codebase's gate over every state-mutating route. Recovery: added `validateOrigin + rejectCsrf` in a follow-up commit. Prevention: for any new state-mutating route, run the full vitest suite (not just the route's own tests) before considering it green.
- **Plan path paraphrase** — plan said "edit `sentry.server.config.ts`" but canonical redaction list lives in `server/sensitive-keys.ts`. Recovery: caught by plan's own Sharp Edges rule about path paraphrasing. Already-load-bearing prevention.

## Tags

category: build-errors
module: web-platform/build-gates
related: feat-dev-signin-bypass (R3), assert-dev-signin-eliminated.sh

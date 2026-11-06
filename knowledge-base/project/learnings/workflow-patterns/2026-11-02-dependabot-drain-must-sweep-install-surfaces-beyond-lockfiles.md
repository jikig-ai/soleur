---
title: "A Dependabot drain is not done when the lockfiles are clean — the vulnerable copy can live in an install surface the lockfile never records"
date: 2026-11-02
category: workflow-patterns
pr: 11823
tags: [dependabot, supply-chain, drain-guard, review-panel, dockerfile, vitest]
---

# A Dependabot drain is not done when the lockfiles are clean

## What happened

PR #11823 drained 15 medium/low npm alerts by bumping lockfile floors and
adding `overrides` (minimatch 11, glob 14, @hono/node-server 2, vitest/@vitest/mocker
4.1.12, hono, ip-address, fast-uri, fast-copy). The lockfile census was clean and every
alert's patched floor resolved — yet the review panel's structural-enumeration and
pattern-recognition seats independently found a **PR-introduced P1**: `apps/web-platform/Dockerfile:108`
still ran `npm install -g vitest@4.1.11 --before=2026-08-19`, globally installing a
vulnerable `@vitest/mocker@4.1.11` inside the canary image — and the repo's own pin-parity
guard (`test/dockerfile-vitest-version-pin.test.ts`) REDed on it.

## Lessons

1. **Enumerate every surface that resolves an npm tree, not just lockfiles.** `npm
   install -g`, `npm install --no-save`, `npx pkg@ver`, `.mcp.json` server pins,
   Dockerfile `RUN npm …`, and manifest-only `package.json` files (e.g.
   `packages/opencode-plugin`) all produce dependency trees no `package-lock.json`
   records. The enumeration map for this repo is filed in issue #11855
   (deferred-scope-out, CONCUR code-simplicity-reviewer) — ~15 ad-hoc sites plus the
   `@playwright/mcp` 0.0.78-vs-0.0.75 divergence, which is a *direction* decision, not
   a sync (compliance-posture.md attests argv refusals against 0.0.78).
2. **Version-parity guards are the load-bearing tripwire.** The Dockerfile pin was only
   caught because a test asserts the pin equals the lockfile version. When a dep bump
   lands, grep the diff's package names against `Dockerfile`, `.github/workflows/`,
   `.mcp.json`, and `scripts/` for sibling pins — one grep would have surfaced it pre-review.
3. **Fix commits need their own adversarial round (ADR-267 confirmed again).** Three
   P2s landed *in* the first fix commit: a fixture-mirror arm that couldn't see table
   growth, a name-disagreement check blind to watched↔watched swaps, and a lockfile
   census whose basename skip-set hid committed files under `dist/`. Each was caught by
   a fix-round seat mutating the guard in scratch — verifying "the arm reds for the
   reason it names" beats verifying "the arm exists".
4. **A blanket `overrides` pin can arm dormant consumers.** `minimatch@11`'s CJS export
   is non-callable; `eslint-plugin-react/-import/-jsx-a11y` call it as a function and
   would TypeError if their rule families are ever enabled. The enablement trap is now
   documented at `apps/web-platform/eslint.config.mjs` — check call-shape compatibility,
   not just declared-range compatibility, before forcing a major re-resolution.
5. **Pre-existing guard-boundary gaps file cleanly when each criterion is named.**
   Cross-cutting (≥3 unrelated files) + architectural-pivot findings went to one
   CONCUR-adjudicated scope-out issue; everything on the guard itself stayed inline —
   the net-issue-flow gate then needed an explicit `gate-override` line in the PR body.

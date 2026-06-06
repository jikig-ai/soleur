---
lane: "single-domain"
issue: 4987
---

# Spec — Fix cron-content-generator skill + build-validation degradation (#4987)

## Problem

`cron-content-generator` (Inngest claude-eval producer) is **quality-degraded but
watchdog-invisible**: it still files its `scheduled-content-generator` audit issue
(the #4960 silence fix works), but the eval cannot use the `/soleur:*` skills or the
build-validation its prompt depends on. Observed on the 2026-06-05 run (issue #4982):
"Content-writer skill unavailable; distribution content written manually … Build
validation could not be run (bash unavailable)."

## Root causes (confirmed, not hypothesised)

1. **Skill resolution (`/soleur:content-writer` unavailable).** The eval spawns
   `claude --print` against a freshly `git clone --depth=1`'d repo with a symlinked
   `plugins/soleur` dir. A symlinked plugin dir alone does **not** register the plugin
   in a headless `--print` run — the repo's own `feature-request-plugin-dir-settings.md`
   documents this exactly: `extraKnownMarketplaces`+`enabledPlugins` requires a trust
   dialog that headless mode skips, so plugins never auto-install. The supported
   headless mechanism is the **`--plugin-dir <path>`** CLI flag. Additionally,
   `--allowedTools` is an explicit allowlist — it lists `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch`
   but **not** `Skill`, so even a loaded plugin's skill cannot be invoked. The
   content-writer skill also wants the `Task` tool for its fact-checker subagent.

2. **Build validation (STEP 4) is structurally impossible in the eval.** The ephemeral
   workspace is a shallow clone with **no `node_modules`**. `npx @11ty/eleventy` and
   `scripts/validate-blog-links.sh` (which itself shells `npx --yes @11ty/eleventy`)
   cannot run — npx would have to download Eleventy + the project's plugin chain, which
   the bwrap sandbox's network policy blocks at runtime (Dockerfile: "bwrap sandbox
   blocks apt at handler runtime"). The agent narrated this as "bash unavailable" (Bash
   itself worked — `gh issue create` in STEP 6 succeeded). The correct gate already
   exists: **CI runs the Eleventy build (`ci.yml:519`) and `validate-blog-links.sh`
   (bun-test suite) on every PR**, and the eval's `MANDATORY FINAL STEP` opens a PR with
   `gh pr merge --squash --auto`, which only merges once required checks pass.

## Decision: surgical, content-generator-scoped, no sandbox change

The sandbox does **not** need relaxing. The skills the prompt invokes
(content-writer, social-distribute, growth) use `Read/Write/Edit/Glob/Grep/WebSearch/WebFetch`
and the `Skill`/`Task` tools — none of which are bwrap-sandboxed (bwrap only confines
*Bash subprocess* filesystem/network; WebFetch/WebSearch run in the claude process).
The only sandboxed-Bash need was STEP 4's build, which moves to CI. Keeping the sandbox
ON for content-generator (and unchanged for the other 6 producers) is the minimal,
lowest-review-cost fix.

### Change A — `CLAUDE_CODE_FLAGS` (cron-content-generator.ts)
- Add `Skill,Task` to the `--allowedTools` value (precedent: cron-competitive-analysis,
  cron-legal-audit already add `Task`). `--max-turns 50` unchanged.
- Add `--plugin-dir`, `plugins/soleur` **before** the load-bearing `--` end-of-options
  marker (symlink-safe; the symlink is created by `setupEphemeralWorkspace` at
  `<spawnCwd>/plugins/soleur`).

### Change B — `CONTENT_GENERATOR_PROMPT` STEP 4 (cron-content-generator.ts)
- Replace the local-build imperative with a CI-defers-validation instruction: the agent
  must NOT run a local build (no `node_modules` in the ephemeral clone); CI runs
  `npx @11ty/eleventy` + `scripts/validate-blog-links.sh` on the PR and `--auto` merge
  gates on those checks. Keep `@11ty/eleventy` and `validate-blog-links` as anchor
  strings (now describing the CI gate) so existing anchor tests stay meaningful.

## Non-Goals
1. Relaxing/disabling the bwrap sandbox (not required; higher review cost).
2. Touching the other 6 claude-eval producers (their flags are independent module consts).
3. Bumping the Dockerfile-pinned `claude` version (`2.1.79` already supports `--plugin-dir`,
   per the feature-request doc citing 2.1.56).
4. Running an actual local Eleventy build in the eval (infeasible by design).

## Acceptance Criteria
- AC1: `CLAUDE_CODE_FLAGS` `--allowedTools` value contains `Skill` and `Task`; `--max-turns`
  remains `50`.
- AC2: `CLAUDE_CODE_FLAGS` contains `--plugin-dir` with value `plugins/soleur`, positioned
  before the `--` marker.
- AC3: `CONTENT_GENERATOR_PROMPT` STEP 4 instructs CI-deferred validation (mentions
  `node_modules` absence + CI) and no longer issues a bare local `npx @11ty/eleventy`
  imperative as the validation gate.
- AC4: All pre-existing content-generator / substrate / producer-wiring tests still pass;
  full `tsc --noEmit` + vitest suite green.

## Observability
No new error paths. The existing #4960 handler fallback + output-aware Sentry heartbeat
already cover silence. This change restores skill execution + shifts build validation to
the PR's CI gate (the auto-merge already blocks on failing checks).

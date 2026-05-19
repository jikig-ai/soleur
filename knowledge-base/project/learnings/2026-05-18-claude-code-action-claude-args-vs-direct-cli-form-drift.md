---
date: 2026-05-18
category: integration-issues
tags: [claude-code, inngest, cli, child_process.spawn, plan-vs-reality, npm-packaged-binary]
component: apps/web-platform/server/inngest/functions/cron-daily-triage.ts
issue: "#3948"
pr: "#3985"
parent_adr: "ADR-033"
---

# `claude-code-action`'s `claude_args` ≠ the direct `claude` CLI shape

## Problem

TR9 PR-1 (#3948) migrates `scheduled-daily-triage.yml` to an Inngest cron function that spawns `claude` via `child_process.spawn`. The plan extracted the spawn args from the GitHub Actions workflow:

```yaml
# .github/workflows/scheduled-daily-triage.yml
uses: anthropics/claude-code-action@…
with:
  claude_args: '--model claude-sonnet-4-6 --max-turns 80 --allowedTools Bash,Read,Glob,Grep'
  prompt: |
    You are an issue triage agent…
```

…and prescribed:

```typescript
spawn("claude-code", [
  "--model", "claude-sonnet-4-6",
  "--max-turns", "80",
  "--allowedTools", "Bash,Read,Glob,Grep",
  "--prompt", DAILY_TRIAGE_PROMPT,
])
```

**At work Phase 0.2 (CLI verification), three of those four assumptions failed**:

1. The npm package `@anthropic-ai/claude-code` installs a binary named **`claude`**, not `claude-code`. The package name is just the registry name; `package.json:bin` maps `"claude": "bin/claude.exe"`.
2. There is **no `--prompt` flag**. The CLI signature is `claude [options] [prompt]` — the prompt is a **positional argument**.
3. Non-interactive use requires **`--print` / `-p`**. Without it the CLI starts an interactive session and never exits.
4. `--max-turns` IS accepted, but it's **hidden** (not in `--help` output). Discovered by probing: `claude --max-turns 80 --print "ping"` → exit 0.

The actual working invocation:

```typescript
spawn(CLAUDE_BIN, [
  "--print",
  "--model", "claude-sonnet-4-6",
  "--max-turns", "80",
  "--allowedTools", "Bash(gh issue list:*),Bash(gh issue view:*),…,Read,Glob,Grep",
  DAILY_TRIAGE_PROMPT,  // positional, last
])
```

## Root cause

`claude-code-action` is a **wrapper** that parses `claude_args` as a string and assembles its own CLI invocation — it does not pass them through verbatim. The plan author inherited the wrapper's accepted shape thinking it was the underlying CLI's shape.

This is a general pattern: any time a plan references CLI flags from a GitHub Action's input parameters, those parameters are likely consumed by the action's wrapper, not by the binary itself. Three concrete drift vectors:

- **Binary name**: npm packages can ship binaries with names completely unrelated to the package name (`@anthropic-ai/claude-code` → `claude`, `@biomejs/biome` → `biome`, `prettier` → `prettier`).
- **Flag presence**: wrapper-only flags (`anthropic_api_key:`, `plugin_marketplaces:`, `plugins:`) and reformatted flags (`--prompt` rewritten from `prompt:` input) look like CLI flags but aren't.
- **Argument vs option**: the wrapper may accept `prompt:` as a YAML scalar but pass it as a positional CLI arg, or via stdin, or via a temp file — none of which match a hypothetical `--prompt <text>` flag.

## Solution

**1. At plan time, run `<bin> --help` before binding any spawn-args** — even when a precedent workflow uses the same binary. `npm view <pkg> bin` to get the binary name; then `npx -y <pkg>@<version> --help` (or local `./node_modules/.bin/<bin> --help`) to validate flag shapes.

**2. Probe undocumented flags via exit-code, not via `--help` grep.** `claude --max-turns 80 --print "ping"` exited 0 — confirming `--max-turns` is accepted despite not appearing in `--help`. Doc absence ≠ flag absence for CLIs with hidden options.

**3. When the binary requires platform-specific postinstall** (e.g., `@anthropic-ai/claude-code`'s native binary download via `install.cjs`), resolve the binary path **inside** the consuming `step.run` closure, not at module load. A failed postinstall then surfaces as `spawn ENOENT` → `reportSilentFallback` → Sentry `status=error`, instead of throwing at route-registration time (which silently disables the whole Inngest worker with no operator-visible signal).

```typescript
// Inside step.run("claude-eval", ...):
const claudeBin = resolveClaudeBin();
const child = spawn(claudeBin, [...flags, prompt], opts);
```

**4. When porting a CLI invocation from a GHA wrapper to direct spawn, narrow `--allowedTools` to the specific verbs the prompt actually needs.** The wrapper's `Bash,Read,Glob,Grep` allowlist is permissive-by-default; `claude-code` supports per-Bash-command syntax: `Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh issue comment:*)`. This closes the permissive-tools / restrictive-prompt silent-agent-failure shape.

## Key Insight

**A GitHub Action's input parameters and the underlying CLI's flags are different surfaces.** The action's YAML inputs are parsed by the action's TypeScript or JavaScript wrapper; what reaches the binary is whatever the wrapper assembles. Plans that cite GHA `with:` blocks as the CLI source are citing the wrong surface. Always validate at the binary boundary.

**Three boundaries where wrapper-vs-CLI drift surfaces:**

1. **Binary name** — `package.json:bin` is the authoritative source. `npm view <pkg> bin` resolves it without an install.
2. **Flag shape** — `<bin> --help` is the authoritative source. Hidden flags exist; probe by exit code.
3. **Arg positioning** — the help line `Usage: claude [options] [prompt]` makes `prompt` positional; a wrapper that accepted `prompt:` as a named input is irrelevant.

## Session Errors

- **bun's `minimumReleaseAge=259200` (3-day) blocked `@anthropic-ai/claude-code@2.1.143`** (2 days old at install) — Recovery: pinned to 2.1.142 (3 days, in-window). **Prevention:** before adding any npm dep, check `bunfig.toml` `minimumReleaseAge` and pick a version that satisfies it. `npm view <pkg> time --json` returns publish dates per version.
- **`bun add` skipped postinstall in default config** — Recovery: ran `node node_modules/@anthropic-ai/claude-code/install.cjs` manually. **Prevention:** documented in code comment; addressed via runtime resolve-inside-step.run (binary-missing now surfaces as `spawn ENOENT` → Sentry, not silent registration failure).
- **`bash scripts/test-all.sh 2>&1 | tail -40` masked non-zero exit code** — completion notification reported exit 0 but the underlying script exited 1 (3 failed suites). Pipeline's last command was `tail` (always exits 0); without `pipefail` upstream, that's the exit code the harness sees. Recovery: re-ran capturing exit separately. **Prevention:** when running test runners through pipes in tool calls, use `bash -o pipefail -c '<cmd> | tail -N'` OR capture exit explicitly: `<cmd>; echo "EXIT=$?"`. Adding a `te-*`-style telemetry signal on this would catch it across all `bash | tail` patterns.
- **Adding `SENTRY_PUBLIC_KEY_RE` (`^[a-f0-9]{32}$`) validator broke T1/T2 fixtures** that used 6-char stubs ("abc123") — passed at implementation phase, failed at review-fix phase. Recovery: extended stub to 32-hex. **Prevention:** when adding production env-shape validators, grep all test files that touch the env var (`grep -rln "SENTRY_PUBLIC_KEY" test/`) and update fixtures in the same commit. Add a pre-commit hook? Probably not — too narrow. Code-review checklist item: production env validators MUST come with test fixture audits.
- **TS2741 `NODE_ENV` missing in `ProcessEnv` spawn allowlist** — strict tsconfig requires it. Recovery: added `NODE_ENV: process.env.NODE_ENV`. **Prevention:** when narrowing `process.env` passthrough to a `NodeJS.ProcessEnv` return type, `NODE_ENV` is required. Either include it or cast to `Record<string, string | undefined>`.
- **`signature-verify.test.ts` cold-load tipped over the default 5000ms test timeout** after cron-daily-triage.ts joined the route's import graph. `vi.resetModules()` in `beforeEach` invalidates any `beforeAll` pre-warm. Recovery: raised per-test timeout to 15s via `it(name, fn, 15_000)`. **Prevention:** when adding a function to `/api/inngest` registry, audit any test that imports the route module under `vi.resetModules()` for the default 5s timeout. Document the rationale in code comment so the timeout isn't "mysteriously generous".
- **Plan's `checkin_margin_minutes` precondition was stale** (plan: `180 → 30`, reality: `240 → 30`). Recovery: applied `30` against the actual `240`. **Prevention:** already covered by `hr-plan-quoted-numbers-are-preconditions-to-verify` — info-only, no new mechanism needed.

## References

- ADR-033 §I4 (amended in this PR): `claude` binary installed via `apps/web-platform/package.json` dep, NOT cloud-init.
- Plan: `knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md`.
- Implementation commit: `6777f663`.
- Review-fix commit: `ff3311d6`.
- Related learning: `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` — plan-quoted numbers are preconditions class.
- Related learning: `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — wrapper-vs-CLI drift in a different shape (`gh --jq` doesn't forward `--arg` to jq).

## Tags

category: integration-issues
module: apps/web-platform/server/inngest/functions
related-skills: soleur:plan, soleur:work, soleur:architecture

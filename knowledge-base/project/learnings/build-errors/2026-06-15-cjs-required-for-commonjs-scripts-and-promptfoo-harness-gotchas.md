---
title: "CommonJS skill scripts need .cjs in a type:module repo + promptfoo harness gotchas"
date: 2026-06-15
category: build-errors
module: plugins/soleur/skills/eval-harness
tags: [esm, cjs, promptfoo, eval-harness, module-resolution, docs-drift]
pr: 5358
---

# CommonJS skill scripts need `.cjs` + promptfoo eval-harness gotchas

Captured while building the promptfoo eval-harness skill (PR #5358, PR B of the
engineering-quality effort). A cluster of build/methodology traps worth keeping.

## Problem

New skill helper scripts written as `.js` using `module.exports` / `require` failed
at runtime with `Error: Cannot find module './parse-label.js'` and were loaded as
ES modules (`ModuleJobSync.runSync`).

## Root cause

The repo root `package.json` declares `"type": "module"`. Under that, every `.js`
file is treated as ESM, so `module.exports` / `require` (CommonJS) do not work, and
relative `require("./x.js")` resolves against the wrong base. promptfoo custom
asserts and most node helper scripts are written as CommonJS (`module.exports = ...`).

## Solution

Name CommonJS helper/assert scripts `.cjs` (not `.js`). Node treats `.cjs` as
CommonJS regardless of the nearest `package.json` `type`. Update every `require()`
target's extension too (`require("./parse-label.cjs")`), and any test harness /
config path that references the file (`file://scripts/foo.cjs`,
`ASSERT="$DIR/foo.cjs"`).

## Key insight

In a `type:module` repo, **default to `.cjs` for any script using `module.exports`/
`require`**, and `.mjs`/`.js` only for genuine ESM. The failure is a runtime
`MODULE_NOT_FOUND`, not a build error, so it slips past `tsc` and only surfaces when
the script actually runs. promptfoo loads custom-assert files via `require`, so its
asserts must be `.cjs` here.

## promptfoo harness gotchas (verified live, PR #5358)

- **`repeat:` IS a valid top-level config key** — `promptfoo validate config` accepts
  it. If docs claim "N repeats" and quote a per-run cost that assumes N, the config
  MUST set `repeat: N` or the run does 1 iteration and the cost/median methodology is
  a lie. (Caught at review as a P1 cost-drift: configs lacked `repeat` while SKILL.md
  claimed ×3.)
- **Providers can load from a generated file** — `providers: file://models.generated.json`
  (a JSON array of `"anthropic:messages:<id>"` strings) validates. This keeps model-ID
  literals out of config-class files (and off the model-launch-review auto-fixer);
  generate the file from the TS registry with a bash `grep`-based generator.
- **Provider id prefix is `anthropic:messages:<id>`** — the bare `anthropic:<id>` form
  is wrong.
- **No native median** — `repeat: N` yields N runs + per-cell aggregate pass rate;
  compute the median/rate in the measurement assert + post-processing.
- **`validate config` is the no-spend check** — bare `validate` / `validate target`
  spend API credits; `validate config` is config-only and free. Use it as the CI/QA
  gate; the live `eval` run is operator-gated (Anthropic spend).
- **Classifier-parse tie-break must be earliest-in-text, not enum-order** — a
  word-boundary fallback that returns the first enum *member* (by declaration order)
  rather than the first label *mentioned* biases the control arm's measurement. Pin
  and test the tie-break; document that hedged/negated prose is inherently ambiguous.

## Session Errors

- **`.js` ESM trap** — Recovery: renamed 3 scripts to `.cjs`, fixed requires + test/config paths. **Prevention:** default to `.cjs` for CommonJS scripts in this repo; routed a note to the `skill-creator` skill.
- **`repeat`/cost-doc drift** (review P1) — Recovery: added `repeat: 3` to both configs. **Prevention:** when docs quote a cost/methodology that assumes a config value, set that value in the config and re-validate.
- **`extractLabel` enum-order bias** (review P2) — Recovery: earliest-in-text tie-break + dedicated `parse-label.test.sh`. **Prevention:** pin and test classifier-parse tie-break semantics explicitly.
- **docs/_data/skills.js categorization drift** — 4 sibling-PR skills (`cron-delete`, `cron-list`, `flag-delete`, `flag-list`) were never added to `SKILL_CATEGORIES`, rendering as "Uncategorized" on the docs site; the "86 skills" header was stale. Recovery: registered them under Workflow + corrected counts to 91 (eleventy build confirms Uncategorized==0). **Prevention (recurring gap, guard needs design):** a test asserting every skill dir with `SKILL.md` has a `SKILL_CATEGORIES` entry would catch this, BUT `docs/_data/skills.js` must stay **default-export-only** (a sibling `export { SKILL_CATEGORIES }` silently breaks Eleventy data-module registration — see the existing AGENTS.md Eleventy rule), so the obvious import-based test is blocked. A guard would have to parse the file or assert on the eleventy-built `_site/skills/index.html` `Uncategorized` count in CI. Low-severity (cosmetic docs), so left as a documented future-hardening item rather than a tracked issue.
- **Comment rot** — `.js`→`.cjs` in 2 test headers, "6 disclosures"→7 in components.test.ts. Recovery: fixed at review.
- **Forwarded (plan subagent):** a false-positive IaC-routing hook block (resolved with the `iac-routing-ack` marker — plan adds no infra) and a Write path resolving to the bare-repo root (resolved with an absolute worktree path). One-off.
- **One-off env noise:** shell-snapshot `ZSH_VERSION` unbound under `set -u`; background wait commands exited early on mid-stream log grep matches. Self-resolved.

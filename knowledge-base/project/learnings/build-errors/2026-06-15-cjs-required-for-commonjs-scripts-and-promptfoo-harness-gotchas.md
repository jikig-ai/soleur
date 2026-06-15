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

## promptfoo harness gotchas (verified live, PR #5358 + corrected by the live run in PR B.1)

- **CORRECTION (PR B.1): a config-level `repeat:` key is a NO-OP.** `promptfoo validate
  config` *accepts* `repeat: N` (so it passes validation), but `promptfoo eval` IGNORES
  it — each cell runs once. The first live run produced 18 results, not 54, despite
  `repeat: 3` in the config. The ONLY working mechanism is the `--repeat N` CLI flag.
  Lesson: `validate config` accepting a key does NOT mean the key is honored at eval
  time — only a live run proves it. Document `npx promptfoo eval --repeat N`; do not put
  `repeat:` in the YAML.
- **promptfoo's `defaultTest.vars` `file://*.json` handling is VERSION-DEPENDENT — it may
  pass EITHER the literal unresolved ref string (`"file://enums/go-routes.json"`) OR the
  RESOLVED FILE CONTENTS (the JSON array text as a string).** A custom JS assert must handle
  both, plus a direct array, and fail closed to `[]`. (B.1's first run got the literal-ref
  shape and failed 100% with `Array.isArray(vars.enum)?vars.enum:[]`→`[]`; a later run got
  the resolved-contents shape.) `loadEnum` must: return a direct array; else if the string
  starts with `[`, `JSON.parse` it (resolved contents / array literal); else strip `file://`
  and read the file. **The stub tests must exercise EVERY shape promptfoo can send — a test
  that passes only one shape (or a convenient stand-in array) hides the others.**
- **A "no caller produces this shape" simplification is unsafe when the caller is an external
  tool's undocumented / version-dependent behavior.** In B.1 a reviewer flagged loadEnum's
  JSON-array-text branch as YAGNI ("nothing passes a JSON literal string") and it was dropped;
  promptfoo's resolved-contents shape IS exactly that input, so dropping it silently vacuumed
  the gate on the already-merged go/triage targets (100% out-of-enum) — caught only when the
  next target was eval'd live. The unit tests passed (they used the OTHER shape). **Verify a
  "dead branch" against the real external caller's actual output, not against the unit-test
  fixtures, before deleting it.** Fixed in the follow-up that restored the branch + added a
  contents-shape regression guard.
- **Golden tasks must DISCRIMINATE skill from baseline, not merely be answerable.** The
  POC's first task set was too easy: the label-only baseline scored 89–100%, so the
  skill-vs-baseline delta was ~0 and the harness proved nothing. Hardening to adversarial
  cases (live outage→incident not fix; backlog sweep→drain; DSAR→legal-threshold;
  `URGENT!!` cosmetic→P3; no-new-user-activation→P1) produced a real delta: go-routing
  +19pts (skill 100% vs baseline 81%), ticket-triage +6pts. **A near-zero delta means the
  tasks don't separate the arms — fix the tasks before concluding the prose is dead weight.**
- **But after a genuine hardening attempt, a persistent +0 IS a valid finding — the harness is
  saying this surface's prose adds no measurable model-behavior signal.** Two attempted expansion
  targets (incident brand-survival threshold, ship semver bump) came back +0 / +0 even with
  deliberately adversarial tasks (40-line-new-skill→`minor`, 600-line-refactor→`patch`,
  token-in-logs→`single-user incident`): the models classify these correctly from the input
  description alone, so the criteria/rules prose isn't producing the behavior. The
  enum-LLM-classifier space worth harnessing is SMALL (routing discriminates strongly, triage
  modestly, others not) — and the disciplined response to a +0 target is to NOT ship it as
  permanent fixture-sync debt, per the "verify it pays off before investing in coverage" gate.
  Also: most Soleur "classifiers" are deterministic scripts (gdpr-gate, skill-security-scan,
  brainstorm lane) — already unit-tested; an LLM-arm eval there tests the wrong thing.
- **Providers can load from a generated file** — `providers: file://models.generated.json`
  (a JSON array of `"anthropic:messages:<id>"` strings) validates. This keeps model-ID
  literals out of config-class files (and off the model-launch-review auto-fixer);
  generate the file from the TS registry with a bash `grep`-based generator.
- **Provider id prefix is `anthropic:messages:<id>`** — the bare `anthropic:<id>` form
  is wrong.
- **No native median** — `--repeat N` (the CLI flag) yields N runs + per-cell aggregate
  pass rate; compute the median/rate in the measurement assert + post-processing.
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

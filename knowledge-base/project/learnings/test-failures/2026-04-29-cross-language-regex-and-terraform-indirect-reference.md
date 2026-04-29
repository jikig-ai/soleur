---
module: System
date: 2026-04-29
problem_type: test_failure
component: testing_framework
symptoms:
  - "JS RegExp.source escaped forward slashes broke string equality with bash regex literal in markdown"
  - "Terraform triggers_replace assertion failed because one trigger file is referenced indirectly via local.X + templatefile()"
root_cause: wrong_api
resolution_type: test_fix
severity: medium
tags: [regex, cross-language, terraform, triggers_replace, parity-tests, ship-gate]
---

# Cross-Language Regex Parity & Terraform Indirect-Reference Tracking in Parity Tests

## Problem

PR #3038 (`feat-one-shot-3034-2881`) added a parity test asserting:

1. The `DPF_REGEX` literal documented inside `plugins/soleur/skills/ship/SKILL.md` matches the regex computed by `buildTriggerRegex(TRIGGER_FILES).source` in the test file — so a typo in either side fails the suite.
2. The `terraform_data "deploy_pipeline_fix"` resource in `apps/web-platform/infra/server.tf` actually tracks each trigger file's contents — so dropping a basename from the resource fails the suite.

Both assertions failed on first run despite SKILL.md and server.tf being correct:

```
Expected: "^apps\/web-platform\/infra\/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$"
Received: "^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$"
```

```
Could not locate terraform_data.deploy_pipeline_fix triggers_replace block in server.tf
```

## Root Cause

**(1) Cross-language regex `.source` divergence.** JavaScript's `RegExp.source` escapes forward slashes (`/` → `\/`) so that the string can be re-evaluated as a regex literal between `/.../`. Bash regex literals (assigned via `DPF_REGEX='...'` and consumed by `grep -E`) have no such delimiter and never escape `/`. A pure string compare therefore always fails, even when the two regexes are semantically identical.

**(2) Terraform indirect references via `local.X` + `templatefile()`.** The `triggers_replace = sha256(join(",", [...]))` block in `apps/web-platform/infra/server.tf` holds three direct `file("${path.module}/<basename>")` calls AND `local.hooks_json`. The `hooks.json.tmpl` source file is not named anywhere inside the resource block — it is rendered by `templatefile("${path.module}/hooks.json.tmpl", ...)` in a top-of-file `locals` block, and the rendered string flows into `triggers_replace` via `local.hooks_json`. A test that scopes its search to the resource's `triggers_replace` block therefore sees only 3 of the 4 trigger files.

Both failures are silent at the source-code level — SKILL.md and server.tf are correct — and only surface when a parity test asserts a stricter contract than the source's authors had in mind.

## Solution

**Cross-language regex compare.** Normalize the JavaScript-side `.source` before comparing to the bash literal:

```ts
const expected = buildTriggerRegex(TRIGGER_FILES).source.replace(/\\\//g, "/");
expect(regexMatch![1]).toBe(expected);
```

The escape-stripping is intentional and explained in a comment on the test ("Bash regex literals don't escape forward slashes; JS's RegExp.source does. Normalize the JS source for the comparison.").

**Terraform indirect-reference tracking.** Allow `file()` OR `templatefile()` calls and search the whole file rather than the resource block:

```ts
const escaped = basename.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
const referenced = new RegExp(
  `(file|templatefile)\\(\\s*"\\$\\{path\\.module\\}/${escaped}"`,
).test(serverTf);
expect(referenced).toBe(true);
```

The widened search trades "scoped to one block" for "matched via a stronger semantic predicate" (must be a `file()` or `templatefile()` call referencing the basename via `${path.module}`). Plain `tf.contains(basename)` would still pass on a comment mentioning the basename — the regex form rejects that without forcing the test to chase the resource boundary.

## Prevention

- **Cross-language regex parity tests** must explicitly normalize escape conventions before string comparison. Document the normalization in a code comment so a future reader doesn't think the `.replace` is dead code.
- **Terraform parity tests** asserting "this resource tracks file X" should accept indirect references through `local.*` and `templatefile()`, not just direct `file()` calls inside the resource block. The semantically meaningful predicate is "Terraform reads this file's contents," not "this string appears in this block."
- When code-quality reviewers prescribe "tighten the scope to inside the block" for a test, verify that the block actually contains all the artifacts the test asserts about — Terraform's locals/templatefile indirection is a common counter-example.

## Session Errors

- **JS RegExp.source escapes forward slashes; bash regex literals do not.** Recovery: normalize `.source.replace(/\\\//g, "/")` before string compare. Prevention: when asserting cross-language regex parity (TS regex against bash regex literal in markdown), normalize `\/` in `.source` before string compare.
- **Terraform `triggers_replace` may reference files indirectly via `local.X` + `templatefile()`.** Recovery: relax assertion to `(file|templatefile)("${path.module}/<basename>"` regex over the whole file. Prevention: when asserting Terraform-tracks-this-file, allow either `file()` or `templatefile()` — both prove terraform tracks the contents.
- **Code-quality reviewer flagged `tf.contains(basename)` as too loose** — basename appearing in a comment would pass vacuously. Recovery: replaced with the stronger `(file|templatefile)("${path.module}/...")` regex. Prevention: when "tighten this assertion" is the right fix but the obvious tightening (scope to a block) excludes legitimate values, prefer a stronger predicate over a tighter scope.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-04-29-fix-deploy-pipeline-fix-ship-gate-and-postapply-contract-plan.md`
- PR: #3038 (Ref #2881, #3034)
- Related: `knowledge-base/project/learnings/test-failures/2026-04-02-lazy-regex-semicolons-typescript-structural-tests.md` — same parity-test class (asserting structural invariants in markdown documentation via regex)
- Resource definition: `apps/web-platform/infra/server.tf` (`terraform_data "deploy_pipeline_fix"` + `locals.hooks_json`)

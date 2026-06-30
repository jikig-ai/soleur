---
name: constraint-scaffold
description: "This skill should be used when generating the Layer 1 dependency-cruiser import-boundary gate (client modules importing server secrets) into a Next.js product codebase's CI."
---

# constraint-scaffold

Generates **one** deterministic, no-LLM Layer-1 structural gate into a Next.js product
codebase: a [dependency-cruiser](https://github.com/sverweij/dependency-cruiser) **import-boundary
gate** that fails closed when a `"use client"` module takes a **value** (non-`type-only`) import on
the server-only tree (`server/**`) — i.e. a server secret leaking into the browser bundle. The gate
runs in CI and rejects the violation *before* the LLM-judged review layer (`soleur:review`). See
ADR-071 (mechanism = Option D) and `knowledge-base/project/plans/2026-06-30-feat-constraint-scaffold-l1-gate-generator-plan.md`.

v1 = this one gate only, CI-only, direct-edge only, Next.js-only. Naming / contract / pre-commit /
multi-stack / transitive coverage are deferred (ADR-071 Consequences).

## Agent-owns-gates recovery model (load-bearing)

The gate is **fail-closed**, and the target user is a non-technical founder who can never hand-edit
a `.cjs` config, a baseline, or a workflow. So the agent — never the founder — owns gate
maintenance and recovery:

1. **The agent authors and maintains the gate.** The founder never touches `.dependency-cruiser.cjs`,
   `.dependency-cruiser-known-violations.json`, the shared runner, or the workflow.
2. **When the agent's own change trips the gate:**
   - real leak → the agent fixes the offending import;
   - legitimate new cross-boundary import → the agent runs
     `constraint-scaffold.sh --refresh-baseline` (clean-tree + `origin/main` merge-base capture, so a
     same-PR violation is never grandfathered); the baseline diff is PR-reviewable.
3. **In-code escape hatch (agent-owned, used sparingly):** dependency-cruiser's native
   `// dependency-cruiser-disable-next-line` comment on the importing line.
4. **Founder hotfix with no agent in the loop (the brand-survival deadlock).** A GitHub-web hotfix
   or a machine without the repo tooling can trip the gate with no agent present. The
   single-account recovery is to comment **`/soleur fix constraints`** on the PR — the
   `fix-constraints.yml` dispatcher (#5791) is **wired**: an `issue_comment` handler dispatches the
   agent to fix the import (or `--refresh-baseline`) and push the fix to the PR head. The gate stays
   **informational / non-blocking** — it is NOT promoted to a required check (promotion is now
   blocked on #5778 only), so it cannot deadlock a founder hotfix. **No override label, no `.cjs`
   edit, no second human required.**
5. The founder is **never** required to read or unblock the gate.

## Usage

Generate the gate into `apps/web-platform` (default mode — detect Next.js, emit config + shared
runner + CI workflow, capture the initial baseline). Non-destructive: refuses to overwrite an
existing `.cjs`, runner, or workflow (there is no `--force`); the baseline JSON is the only
re-writable artifact, and only via `--refresh-baseline`:

```bash
bash plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh
```

Refresh the baseline after a legitimate new cross-boundary import (agent-only; clean tree required;
captures against the `origin/main` merge-base):

```bash
bash plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh --refresh-baseline
```

## What it emits (into `apps/web-platform/`)

| Artifact | Role |
|---|---|
| `.dependency-cruiser.cjs` | Executable CommonJS config. Computes the `"use client"` from-set at require-time (recomputed every run, **never** committed static), regex-escaping route-group paths. `tsConfig.fileName` + `tsPreCompilationDeps` give `@/*` alias resolution and the type-only/value distinction. |
| `.dependency-cruiser-known-violations.json` | dependency-cruiser native baseline (`--output-type baseline` / `--ignore-known`). Grandfathers only pre-existing violations. |
| `apps/web-platform/scripts/constraint-gates.sh` | Shared runner — owns the single pinned `depcruise --ignore-known … --output-type err` invocation. Fails closed on any non-zero depcruise rc; CI (and future pre-commit) both exec this. |
| `.github/workflows/constraint-gates.yml` | Always-runs + internal path-check (reports a real conclusion on every PR; no pending-forever deadlock). On failure prints the recovery path (comment `/soleur fix constraints` on the PR). Informational/non-blocking until promoted (promotion now blocked on #5778 only). |
| `.github/workflows/fix-constraints.yml` | The `/soleur fix constraints` recovery dispatcher (#5791). An `issue_comment`-triggered workflow that, on an authorized PR comment, dispatches the agent to fix the tripped gate (or `--refresh-baseline`) and push to the PR head. Author-association + collaborator-permission gated; head==base (no fork pushes); plain `issue_comment` (never the privileged pull-request-target trigger). |

## Self-tests

`test/boundary.test.sh` (scripts shard) proves the gate is not vacuous: a value import of `server/**`
via the `@/server/…` alias FAILS, an `import type` of the same PASSES, route-group/metacharacter
paths are matched (regex-escaping), an empty from-set while `"use client"` files exist is a hard
error, and a broken `.cjs` fails the runner closed.

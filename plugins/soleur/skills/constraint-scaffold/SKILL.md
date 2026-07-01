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

This gate covers this one boundary only, CI-only, Next.js-only. It catches BOTH direct
client→server-secret value imports AND transitive ones (a `"use client"` module reaching a
server secret through a chain of value imports, e.g. a non-client `lib/` helper) — the transitive
`reachable` rule was added in the 2026-07-01 #5777 amendment (ADR-071 §Amendment). Naming /
contract / pre-commit / multi-stack coverage remain deferred (ADR-071 Consequences).

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
   or a machine without the repo tooling can trip the gate with no agent present. Recovery is
   **automatic and zero-touch**: the two-stage auto-recovery dispatcher (`fix-constraints-stage-a`
   → `fix-constraints-stage-b`, **ADR-074**) fires on the PR, fixes the offending import, and opens
   a **draft follow-up PR** the founder can merge — no comment, no command, no agent-in-the-loop
   required. (A real leak the agent cannot fix is surfaced for a maintainer; auto-recovery is
   fix-only and never grows the suppression baseline.) The gate stays **informational /
   non-blocking** — it is NOT promoted to a required check (promotion is now blocked only on #5778;
   the #5791 dispatcher half is satisfied by ADR-074), so it cannot deadlock a founder hotfix.
   **No override label, no `.cjs` edit, no second human required.**
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
| `.github/workflows/constraint-gates.yml` | Always-runs + internal path-check (reports a real conclusion on every PR; no pending-forever deadlock). On failure the two-stage auto-recovery dispatcher (`fix-constraints-stage-a/b`, ADR-074) auto-opens a follow-up PR when the gate is auto-fixable. Informational/non-blocking until promoted (now blocked only on #5778; the #5791 dispatcher half is satisfied by ADR-074). |
| `.github/workflows/fix-constraints-stage-a.yml` | Untrusted `pull_request` producer (ADR-074): `contents: read` only. Runs the gate, dispatches the fix-only agent, re-verifies green, uploads the fix as a full-post-image-contents artifact (per-file sha256 + meta.json). No write token, no commit/push. |
| `.github/workflows/fix-constraints-stage-b.yml` | Privileged `workflow_run` consumer (ADR-074): validates the attacker-controlled artifact (isCrossRepository==false gate, event-sourced identity, charset+traversal+symlink+size allowlist, sha256 byte-verify) and applies it via the Git Data API (blob→tree with mandatory base_tree→commit→ref) — never checks out the untrusted tree, never git-applies. Delivers a draft follow-up PR. |

**Before editing either stage workflow (or its template), read ADR-074 + [[2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps]].** The load-bearing invariants — trigger split (untrusted producer / privileged non-executing consumer), Stage B's `isCrossRepository==false` gate on the *fully attacker-controlled* artifact, event-sourced identity, mandatory `base_tree`, name-coupling (`workflow_run` matches Stage A's `name:`, not its filename), the give-up marker (no terminal state is silent), and `emit()` output-sanitization — are enforced by `test/emit-fix-constraints.test.sh` + `test/parity.test.sh` (which covers the repo-root dogfood copies, not just emitted fixtures). A change that greens those tests but breaks an invariant is the class the tests exist to catch.

## Self-tests

`test/boundary.test.sh` (scripts shard) proves the gate is not vacuous: a value import of `server/**`
via the `@/server/…` alias FAILS, an `import type` of the same PASSES, route-group/metacharacter
paths are matched (regex-escaping), an empty from-set while `"use client"` files exist is a hard
error, and a broken `.cjs` fails the runner closed.

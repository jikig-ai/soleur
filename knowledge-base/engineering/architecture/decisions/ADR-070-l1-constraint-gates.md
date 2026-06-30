---
adr: ADR-070
title: Layer 1 deterministic constraint gates for product code
status: accepted
date: 2026-06-30
---

# ADR-070: Layer 1 deterministic constraint gates for product code

## Context

Soleur has rich deterministic Layer-1 enforcement for its **meta-workflow** (PreToolUse
hooks — `guardrails.sh`, `brand-hex-commit-gate.sh`, `git-commit-secret-scan.sh`, the
change-class classifier) but **no deterministic constraint on the shape of product code**
the agent writes for the founder's SaaS. Every structural check (import/layer boundaries)
is currently LLM-judged in `soleur:review` (`architecture-strategist`,
`pattern-recognition-specialist`) — i.e. ADR-011 tier 2/3, not tier 1. That is
probabilistic, token-costly, and the wrong tier for a mechanical invariant.

The target user is a non-technical founder who can never hand-author or unblock such a
gate, so Soleur must *generate* it. `dependency-cruiser` and any fitness-function
infrastructure are absent from the repo (#3132 / #3133 unbuilt). The brand-survival vector
(threshold: single-user incident) is a `"use client"` module taking a **value** import on a
server-secret module — shipping a server secret into the browser bundle.

## Decision

The `constraint-scaffold` skill generates a deterministic, no-LLM **import-boundary gate**
into the product codebase (`apps/web-platform` first). It runs in CI, fails closed, and
rejects the violation **before** the LLM-judged review layer — the product-code
instantiation of ADR-011 tier 1.

**The agent — never the founder — owns gate maintenance, baseline refresh, and recovery.**
A founder hotfix that trips the gate recovers via one comment, `/soleur fix constraints`
(the existing `/soleur` comment-dispatch runs the agent to fix-or-refresh and push a clean
commit). No override label, no `.cjs` edit, no second human required.

**Mechanism (Option D).** `dependency-cruiser` is the engine — it robustly owns `@/*`
alias resolution (`tsConfig` + `tsPreCompilationDeps`), the type-only/value erasure, and the
native known-violations baseline (`--output-type baseline` / `--ignore-known`). But
dep-cruiser matches modules by **path** and cannot see the `"use client"` directive (it is a
graph tool, not a directive scanner), and this codebase has no `.client.tsx` convention.
Therefore the `.cjs` config is **executable CommonJS that computes the client-module
`from.path` set at config-require time**: it greps `app/**`+`components/**` for the leading
`"use client"` directive, maps each hit to dep-cruiser's cwd-relative posix module-source
format, and **regex-escapes** each path (route groups like `app/(dashboard)/` carry regex
metacharacters). The `forbidden` rule is then `from: { path: <computed escaped set> }`,
`to: { path: <secret-module set>, dependencyTypesNot: ['type-only'] }`, direct edges only.

The from-set is **recomputed on every run and never committed as a static list** — a stale
list would be blind to a newly-added client file (the exact leak the gate exists to catch).
An empty from-set while `"use client"` files exist is a hard error, not a silently-disabled
rule.

## Alternatives Considered

- **A — bespoke AST-lite checker** (custom script resolving imports itself). Rejected: it
  re-implements TS module resolution (`@/*` + tsconfig `paths` + barrels) and the
  type-only/value distinction — the exact correctness work dep-cruiser already solves, and
  the exact leak modes the brand-survival threshold names. Concentrates the highest-consequence
  correctness risk in untested code.
- **B — `server-only` npm package marker** (build throws if a client module imports a marked
  module). Rejected for v1: not baseline-grandfatherable (all-or-nothing → hard-breaks the
  webpack build on all ~13 pre-existing violations at once = the "deploy stranded, no
  engineer-free recovery" outcome the threshold forbids), and a build error bypasses the
  discrete `constraint-gates` check + comment-summon recovery model. Retained as optional
  later defense-in-depth.
- **C — dep-cruiser native `from "use client"` match.** Impossible: dep-cruiser exposes no
  content/directive matcher.

## Consequences

Structural import-boundary violations get deterministic, fail-closed, token-free enforcement
at tier 1 instead of probabilistic LLM review. The agent-owns-gates contract keeps the
fail-closed gate from stranding a non-technical founder. v1 is Next.js-only, direct-edge
only, single gate (client→server-secret); the naming gate, contract gate, pre-commit surface,
multi-stack support, and transitive-edge coverage are deferred (#5774–#5778). The content-scan
adds a small amount of executable logic to the `.cjs` config that must stay correct (regex
escaping, module-source format) — covered by self-tests. Cross-reference: ADR-011 (the
three-tier model this instantiates at tier 1 for product code).

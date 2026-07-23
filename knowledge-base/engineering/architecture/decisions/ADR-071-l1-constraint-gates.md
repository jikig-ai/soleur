---
title: Layer 1 deterministic constraint gates for product code
status: accepted
date: 2026-06-30
---

# ADR-071: Layer 1 deterministic constraint gates for product code

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
Founder-hotfix recovery is **automatic and zero-touch** via the two-stage auto-recovery
dispatcher (`fix-constraints-stage-a` → `fix-constraints-stage-b`, **ADR-074**): a tripped
gate on a PR triggers a fix-only agent run that delivers the fix as a **draft follow-up PR**
— no comment, no command, no head-push. (The held `/soleur fix constraints` comment-dispatcher
that this superseded ran untrusted PR-head code in a privileged `issue_comment` trigger; ADR-074
replaced it with an untrusted producer / privileged non-executing consumer split.) Auto-recovery
is fix-only and never grows the suppression baseline; a real leak it cannot fix is surfaced for a
maintainer (who re-runs `constraint-scaffold` locally: fix the import, or `--refresh-baseline`).
The gate stays **informational / non-blocking** — it is NOT promoted to a required check.
Promotion to a REQUIRED check is now **blocked only on #5778** (monorepo/multi-stack follow-up);
the #5791 "no agent-free recovery for a tripped required gate" blocker is **satisfied by ADR-074**
(auto-recovery is agent-free from the founder's perspective). No override label, no `.cjs` edit,
no second human required.

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
  webpack build on all 10 pre-existing violations at once = the "deploy stranded, no
  engineer-free recovery" outcome the threshold forbids), and a build error bypasses the
  discrete `constraint-gates` check + comment-summon recovery model. Retained as optional
  later defense-in-depth.
- **C — dep-cruiser native `from "use client"` match.** Impossible: dep-cruiser exposes no
  content/directive matcher.

## Consequences

Structural import-boundary violations get deterministic, fail-closed, token-free enforcement
at tier 1 instead of probabilistic LLM review. The agent-owns-gates contract keeps the
fail-closed gate from stranding a non-technical founder. v1 is Next.js-only, single gate
(client→server-secret); the naming gate, contract gate, pre-commit surface, and
multi-stack support are deferred (#5774–#5776, #5778). **Transitive-edge coverage (#5777/NG5)
is now CLOSED** — see §Amendment 2026-07-01. The content-scan adds a small amount of executable
logic to the `.cjs` config that must stay correct (regex escaping, module-source format) —
covered by self-tests. Cross-reference: ADR-011 (the three-tier model this instantiates at
tier 1 for product code).

## Amendment 2026-07-01 (#5777) — transitive client→helper→server-secret coverage

The v1 gate matched **direct** edges only, so a `"use client"` module that imports a non-client
helper (e.g. in `lib/`) which value-imports a `server/**` secret still shipped that secret into
the browser bundle undetected (NG5, deferred from #5765). This amendment adds a dependency-cruiser
`reachable` rule to catch `client → helper → … → server-secret` value chains. The original
Context / Decision / Alternatives above are preserved intact — this is an EXTENSION of the v1
decision, not a rewrite.

**Decision (added).** The gate now enforces **transitive** reachability via a second forbidden
rule (`no-client-to-server-secret-transitive`, `to.reachable: true`) alongside the direct rule.
Two load-bearing sub-decisions, both verified against the installed dependency-cruiser@16.10.x
source:

- **`options.tsPreCompilationDeps` flipped `true → false`.** dependency-cruiser v16 `reachable`
  rules are schema-locked to `{path, pathNot, reachable}` (`additionalProperties: false`) and
  CANNOT filter `dependencyTypesNot` per-rule, so the ONLY way to stop reachability from following
  a build-time-erased `import type` hop is to elide type-only edges from the graph GLOBALLY. With
  type-only edges gone, the direct rule no longer needs its `dependencyTypesNot:["type-only"]`
  filter — its violation set is **byte-identical** before and after the flip (proven empirically at
  build time). Because a flip regression could only *shrink* the value-edge set (value edges are
  never erased; only type-only edges are), a `boundary.test.sh` assertion floors the direct baseline
  at **≥10** (a legitimate new value-safe direct import may grow it). Both rules therefore ignore
  type-only imports.
- **The reachable baseline is kept EMPTY.** The zero-baseline invariant is enforced by keying on the
  transitive rule NAME, not on `type:"reachability"`: dependency-cruiser softens `reachability`
  violations **per-origin** (`soften-known-violations.mjs` matches on `from` + rule name only,
  ignoring `to`/`via` **and the entry `type`**), so a hand-authored `type:"module"` entry naming the
  transitive rule suppresses it identically to a `type:"reachability"` entry. The runner guard and
  `boundary.test.sh` both reject any baseline entry that is `type:"reachability"` OR names the
  transitive rule (any type), and fail closed on a non-array baseline. So baselining even one
  value-safe transitive path would blind that client to EVERY
  future transitive secret. Instead, the known value-safe server modules are excluded from the
  reachable **target** via `to.pathNot` (never from the `from` set — that would blind the client to
  all secrets), and any real transitive leak is FIXED, never grandfathered. A guard in the shared
  runner AND `boundary.test.sh` fails closed on any committed `type:"reachability"` baseline entry.

**Alternatives Considered (added).** (i) per-rule `dependencyTypesNot` on the reachable rule —
**impossible** (schema-forbidden in v16.10.x); (ii) baselining pre-existing transitive paths —
**rejected** (per-origin suppression = permanent blind spot); (iii) a separate reachable-only
second config with `tsPreCompilationDeps:false` isolated to it — retained as the fallback had the
flip changed the direct-rule set (it did not, so the single-config design shipped).

**Consequences (added).** The `to.pathNot` value-safe allowlist
(`domain-leaders`, `providers`, `team-names-validation`, `scope-grants/action-class-map` — the
4 modules any client reaches today, verified value-safe: no `process.env` value read, no secret
import) is a hand-maintained fail-open: if one later gains a real secret it ships green on both the
direct (baseline-suppressed) and transitive (`pathNot`-excluded) paths. Mitigated by a mandatory
D4 content-invariant drift guard in `boundary.test.sh` (each listed module must read no
`process.env` value / take no value import). The structural fix — relocating the 4 modules out of
`server/**` so the exclusion is enforced by LOCATION — is tracked in #5850 (`SOLEUR-DEBT` marker at
the `VALUE_SAFE_PATH` definition). The gate remains informational/non-blocking; the reachable rule
adds no new CI job (same shared runner, same version pin `^16.10.0`). NG5/#5777 moves from
deferred → closed.

# Learning: at a brand-survival gate, verify every assumed capability before documenting it as load-bearing

**Date:** 2026-06-30
**Feature:** constraint-scaffold L1 import-boundary gate (#5765, PR #5770)
**Threshold:** single-user incident

## Problem

Building a deterministic CI gate that fails closed when a `"use client"` module value-imports
a server-secret module (server secret → browser bundle). Across brainstorm → plan → build →
review, **seven distinct defects shared one root cause: a capability or behavior was assumed
correct and written into the plan/ADR/artifacts as load-bearing, before anyone verified it.**
The brand-survival threshold (`single-user incident`) is exactly the regime where an unverified
assumption is most expensive — each one was a silent-leak or founder-deadlock vector.

## The seven, and where each was caught

1. **Tool-feature assumption.** The plan + 4 plan-review agents all reasoned about a
   dependency-cruiser rule `from "use client" → to server/`. dep-cruiser matches modules by
   **path** and cannot see the `"use client"` directive (it's a graph tool, not a content
   scanner); this codebase has no `.client.tsx` convention. The rule text was *un-buildable*.
   Caught only at /work by a de-risk probe → routed to the CTO agent → **Option D** (ADR-070):
   the `.cjs` config is executable CommonJS that computes the client `from.path` set at
   require-time (regex-escaped, **recomputed every run, never committed static** — a stale list
   is blind to a newly-added client file).
2. **Recovery-handler assumption (P1).** ADR-070 + SKILL.md + every emitted artifact told a
   stranded founder to comment `/soleur fix constraints`, calling it *"the existing /soleur
   comment-dispatch."* **No such `issue_comment` handler exists** in the repo (only
   `cla.yml`/`cla-evidence.yml`). The named brand-survival mitigation was fictional. Caught at
   review by two orthogonal agents (code-quality + user-impact). Fixed: honest "planned (#5791),
   not yet wired" wording + the gate stays informational + promotion-to-required is blocked on
   #5791.
3. **Exit-code-semantics assumption.** The plan asserted depcruise `rc ∉ {0,1}` = config error.
   Empirically, dependency-cruiser@16 exits with the **violation count** (rc=10 for ten), and
   rc=1 on a config error. A literal `rc∉{0,1}` rule would mislabel a 10-violation leak as a
   config error. Caught at build; the runner fails closed on **any** non-zero and discriminates
   config-error via the report summary line.
4. **Content-gate edge assumption.** `isUseClient` matched only when the directive was the exact
   first non-empty line — a valid Next.js file with a leading license/eslint comment before
   `"use client"` was misclassified non-client → its server value-import shipped unflagged
   (silent leak). Caught at security + user-impact review (0/170 affected today, latent).
5. **CI-execution-model assumption.** The generator emits its workflow to
   `<target>/.github/workflows/`; GitHub Actions only runs **repo-root** `.github/workflows/`,
   so in a monorepo the emitted workflow is a dormant artifact. Caught by the build agent; fixed
   with a repo-root live (non-blocking) copy.
6. **Gate-self-coverage assumption.** AC4 claimed "baseline capture refuses on a dirty tree +
   merge-base," but only `--refresh-baseline` did so — the default *generation* path captured
   the live working tree, so a same-PR leak could be grandfathered. Caught at user-impact review;
   unified generation onto the merge-base path.
7. **Multi-copy-drift assumption.** The skill emits byte-identical template→artifact copies (+ a
   third repo-root workflow copy) with nothing tying them — a template edit (or the recovery path
   editing the emitted copy) drifts silently while tests stay green. Caught at pattern review;
   fixed with a parity test.

## Key Insight

**`hr-verify-repo-capability-claim-before-assert` is not only about *cited* references — it
applies to your OWN claims: a tool feature, a recovery handler, an exit-code contract, a CI
execution model, an AC's self-coverage claim.** At `single-user incident` threshold, before any
capability is written into a plan/ADR/artifact as load-bearing, *exercise it*: grep for the
handler, read the tool's actual rule schema, run the binary and read its real exit code, confirm
where CI actually executes the file. The cost of one verification is seconds; the cost of an
unverified brand-survival assumption is a silent leak or a stranded founder — and plan-time
multi-agent review does **not** catch tool/behavior assumptions (it reasons about plan text, not
the installed tool). The de-risk-the-highest-uncertainty-piece-first probe at /work, and the
security + user-impact lenses at review, are where these surface — keep both even after a heavy
plan-time review.

Mechanism corollary (reusable): to enforce a **content-determined** boundary (`"use client"`,
directive-keyed, no naming convention) with a **path-based** graph linter, compute the content
set inside the linter's executable config at evaluation time — recomputed every run, never
persisted. (ADR-070, CTO Option D.)

## Session Errors

1. **dep-cruiser can't match `"use client"`** (plan rule un-buildable) — Recovery: CTO Option D (compute from-set in `.cjs` at require-time). Prevention: verify a tool's rule schema before writing a rule that depends on a feature it may not have.
2. **`/soleur fix constraints` handler assumed existing** — Recovery: honest "planned (#5791)" wording + promotion gate. Prevention: grep for the handler before naming it as the mitigation (`hr-verify-repo-capability-claim-before-assert` on own claims).
3. **depcruise exit-code semantics wrong in plan** (`rc∉{0,1}`) — Recovery: fail-closed on any non-zero + report-summary discrimination. Prevention: run the binary and read `$?` before encoding exit-code logic.
4. **`isUseClient` first-line-only fail-open** — Recovery: strip leading comments + allow trailing comment; 3 new fixtures. Prevention: content-gate detectors must enumerate valid-but-non-canonical forms.
5. **Workflow emitted to non-executing path in monorepo** — Recovery: repo-root copy. Prevention: confirm where CI executes a generated file before counting it as wired.
6. **Same-PR grandfather on generation path** — Recovery: unify onto merge-base capture. Prevention: an AC's self-coverage claim ("captures from merge-base") must be verified on EVERY code path that claim covers, not just one.
7. **Template↔emission no parity guard** — Recovery: parity test. Prevention: any generator emitting byte-identical copies needs a parity test or they drift green.
8. **`ws-abort.test.ts` full-suite flake** (pre-existing, passes 3/3 in isolation; not in diff) — Recovery: confirmed pre-existing per `wg-when-tests-fail-and-are-confirmed-pre`. Prevention: re-run the failing file in isolation + check main CI before treating a full-suite failure as a regression. One-off.
9. **scratchpad temp dir absent** — Recovery: `mkdir -p`. Prevention: none needed (trivial). One-off.

## Tags
category: workflow-patterns
module: constraint-scaffold, review, plan
related: ADR-070, hr-verify-repo-capability-claim-before-assert, #5765, #5791

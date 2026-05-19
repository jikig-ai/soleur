---
date: 2026-05-12
category: best-practices
module: observability, planning, legal
tags: [helper-boundary-transform, plan-ac-design, pa8-disclosure, multi-agent-cross-reconcile, gdpr-recital-26]
related_prs: [3685, 3638, 3696, 3698]
related_learnings:
  - 2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md
  - 2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md
  - 2026-05-11-plan-research-reconciliation-must-grep-full-render-tree.md
---

# Learning: Centralized-at-helper-boundary transforms over-claim coverage in ACs and disclosures

## Problem

PR #3685 pseudonymized `userId` at the Sentry/pino emit boundary in `apps/web-platform/server/observability.ts`. The design centralized the transform inside three helper functions (`reportSilentFallback`, `warnSilentFallback`, `mirrorP0Deduped`) so that ~40 silent-fallback call sites could continue to pass raw `userId` in `extra` — the helper renames `userId → userIdHash` on emit.

Two parallel over-claims slipped through plan time and were caught only at /work + /review:

1. **Plan AC2 grep gate over-broad.** The plan asserted that `rg "(extra|tags):\s*\{[^}]*\buserId\b" apps/web-platform/server/` must return zero production matches. In reality the regex matches every helper-invocation call site (by design — the helper expects raw `userId` in `extra`). At /work phase, the gate returned ~40 hits, all legitimate. The "intended" gate was actually "no direct `Sentry.captureMessage`/`Sentry.captureException` outside `observability.ts` passes raw `userId` in extras."

2. **Article 30 PA8 §(c) disclosure over-broad.** The PR's PA8 update read "user identifiers are HMAC-SHA256-pseudonymized at the emit boundary" for both Sentry AND pino-on-Hetzner. This is true for the helper-routed emit paths, but ~27 pre-existing direct `logger.error({ userId, ... })` sites across `apps/web-platform/server/` (ws-handler.ts × 14+, agent-runner.ts × 3) and `apps/web-platform/app/` (api/* × 8, (auth) × 2) bypass the helpers entirely. Under a regulator-style read, the disclosure overstates coverage.

Both failures share one root cause: **"at the emit boundary" overgeneralizes when only one specific emit boundary (the helper) carries the transform.** The boundary is *a* boundary, not *the* boundary.

## Solution

Two-layer fix at /review time:

### Layer 1 — narrow the disclosure language inline

PA8 §(c) was tightened to scope the pseudonymization claim to the helper boundaries explicitly:

> "User identifiers passed through the centralised silent-fallback helpers (`reportSilentFallback`, `warnSilentFallback`, `mirrorP0Deduped` in `apps/web-platform/server/observability.ts`) are HMAC-SHA256-pseudonymized at the emit boundary. Legacy direct `Sentry.captureException(err)` / `Sentry.captureMessage(...)` call sites pass single-arg errors only or no `userId` field in `extra` — relying on Sentry's key-based scrubbing for any incidental `user_id` substring in error messages; migration to the helpers is tracked under the follow-up issue."

Similarly for §(c)(ii) pino: explicit "at the silent-fallback / P0-mirror helper boundaries; remaining direct `logger.error({ userId, ... })` call sites continue to log raw `user_id` pending follow-up migration."

The forward-reference points to a `deferred-scope-out` follow-up issue (#3698) enumerating all 27 sites with file:line refs. Code-simplicity-reviewer CONCUR co-signed the scope-out under `cross-cutting-refactor` + `pre-existing-unrelated` (the sites span two top-level subtrees, predate the PR per git-history, and the PR no longer over-claims compliance after the narrowing).

### Layer 2 — clarify the plan AC

Plan AC2 was annotated inline to distinguish the literal regex from the intended gate, explaining why the centralization design renders the literal regex over-broad:

> "Grep gate refinement: the plan's literal `rg "(extra|tags):\s*\{[^}]*\buserId\b"` regex returns matches at helper-invocation call sites (by design — the transform is centralized inside the helpers, so call sites legitimately pass raw `userId` in `extra`). The intended gate is 'no DIRECT `Sentry.captureMessage`/`Sentry.captureException` outside `observability.ts` passes `userId` in extra' — verified by `grep -rn "Sentry\.captureMessage\|Sentry\.captureException" apps/web-platform/server/`."

## Key insight

**Multi-agent cross-reconcile catches over-broad disclosures that a single agent would miss.** Four orthogonal agents — architecture-strategist, data-integrity-guardian, security-sentinel, user-impact-reviewer — independently flagged the PA8 §(c) over-claim. This is exactly the pattern in `knowledge-base/project/learnings/2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`: pattern-recognition / code-quality / architecture agents read code in isolation and approve each diff; only an agent that reads BOTH the code AND the disclosure file flags the contradiction.

The user-impact-reviewer's "name a concrete user-facing exposure vector" mandate is what made the disclosure-vs-code mismatch concrete (a user invoking Art. 17 erasure under the PA8 claim would find their identifier still resident in pino → regulator complaint vector). Generic pattern-matching agents would have approved the diff in isolation.

## Process insight: where to bind the gate

For plan ACs that prescribe a verification command (grep, glob, test invocation), the AC text must specify **both** (a) the command AND (b) the *intent* in a way that survives design choices that re-shape the command's output. When the design pivots (helper centralization, redaction layer, schema rewrite), the AC command needs re-derivation, not a literal-text comparison.

Two patterns help:

1. **"Negative-space + design exception" framing.** Instead of "command X returns zero matches", write "command X returns zero matches except at sites that route through `<helper>` — verified separately by command Y restricted to `<scope>`." Embeds the exception in the AC itself.

2. **Plan-time AC re-derivation gate.** When a plan adopts a centralizing helper / boundary / redaction layer, the AC for "no leaks anywhere" must be split into (i) "no leaks through the centralized path" (regex over helper output) AND (ii) "no direct-bypass leaks" (regex restricted to sites that do NOT route through the helper). The two-clause form is the only form that survives the centralization choice.

## Prevention

Add to plan SKILL.md Sharp Edges (or constitution): when a plan AC prescribes a grep gate over a security/PII surface AND the design centralizes the transform inside a helper, the AC must explicitly distinguish "helper-routed call sites" from "direct-bypass call sites." A single regex over the whole codebase will over-match (helper invocations look identical to direct emits).

Equally: when a plan or PR updates a disclosure (PA8, privacy policy, security overview) that claims coverage of a surface (Sentry, pino, browser bundle), the claim language must scope to *the specific boundary that carries the transform*, not the abstract category. "Pseudonymized at the silent-fallback helper boundary" is true; "pseudonymized at the emit boundary" overstates.

## Related findings (this session)

- **Multi-agent hallucinated specific file:line citations.** user-impact-reviewer claimed direct `Sentry.captureException` sites at `apps/web-platform/app/api/webhooks/stripe/route.ts:183` and `apps/web-platform/app/api/keys/route.ts:64`. Verified via `grep -c "Sentry" <files>` → 0 hits. The agent's broader finding (PA8 over-disclosure) was correct, but specific citations needed verification. Pattern matches `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md`: trust the cross-reconcile concur (architecture + data-integrity also flagged the disclosure issue with verifiable citations), not individual-agent-only specifics.

- **vi.spyOn after import misses module-init `console.warn`.** Initial pepper-unset test used `vi.spyOn(console, "warn")` AFTER the static import of the SUT. The module-init `console.warn(...)` fired during the static import, before the spy was attached. Fix: wrap `console.warn` via `vi.hoisted(() => { console.warn = vi.fn(); ... })` so the wrapper exists BEFORE module init. Same hoisting concern as `vi.hoisted` for `process.env` mutations.

- **Frozen golden vectors decouple tests from SUT formula.** When a test recomputes the SUT's HMAC formula via `expectedHashFor(userId)`, the assertion is technically tautological — a primitive swap (scrypt, blake2, truncation) would silently pass both sides. One frozen golden vector (`hashUserId("u1") === "<known-hex>"`) catches drift. The per-call helpers stay useful for assertion-shape clarity, but the golden vector is the load-bearing falsifier.

## Session errors

1. **Bash CWD doesn't persist across calls** — repeated `cd apps/web-platform && ...` retries. Recovery: switch to fully-qualified `/home/jean/.../apps/web-platform/node_modules/.bin/<tool>` invocations. **Prevention:** AGENTS.rest already documents this; surfaced again here as a repeat-offender pattern. Defense-in-depth would be a CWD-aware shim, but the operational cost is low.

2. **`gh issue create --repo Jikigai-AI/soleur`** — wrong repo casing. Recovery: `gh repo view --json nameWithOwner` discovered canonical `jikig-ai/soleur`. **Prevention:** when filing the FIRST gh issue of a session, omit `--repo` to let gh auto-detect from the current git remote, OR run `gh repo view` once to confirm.

3. **`gh issue create --label "domain/observability"`** — non-existent label. Recovery: `gh label list` to enumerate, retry with verified labels. **Prevention:** when filing an issue with new-feel labels, run `gh label list | grep <label-prefix>` first.

4. **Plan AC2 grep gate over-broad** — covered in main body above. **Prevention:** the two-clause AC framing in §"Process insight" above; routed to plan SKILL.md via direct-edit in Phase 7 below.

5. **Pepper-unset test boot-warning capture race** — `vi.spyOn` after static import misses module-init warning. Recovery: moved interception into `vi.hoisted`. **Prevention:** when a test needs to capture a module-init side-effect, the spy/mock must live in `vi.hoisted` — covered already in test-related learnings; surfaced here.

6. **Made-up golden hash vector** — wrote a fake HMAC value initially. Recovery: computed via `node -e "..."`. **Prevention:** before pinning a frozen vector, compute it. No tooling can prevent this — operator discipline.

7. **Review-agent hallucinated file:line citations** — user-impact-reviewer flagged specific stripe/keys route lines that have zero Sentry calls. Recovery: spot-verified via `grep -c "Sentry" <files>` before applying fixes. **Prevention:** review skill already has a "Sharp Edges: agent suggestions must be verified" section; the spot-verify-before-fix-inline discipline applied here is the right pattern.

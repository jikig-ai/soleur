---
date: 2026-05-11
category: best-practices
tags: [skill-budget, token-budget, heuristic-design, test-design, gdpr-gate]
problem_type: test-heuristic-drift
component: plugins/soleur/skills/gdpr-gate
pr: 3522
issue: 3518
---

# Token-budget heuristics must model the runtime prompt, not full SKILL.md

## Problem

PR #3522 extended `plugins/soleur/skills/gdpr-gate/SKILL.md` with a new operator-mode section (`## --repo-scan mode` + sharp-edges + reorganized reference-layers list). The existing v1 `plugins/soleur/test/gdpr-gate.test.ts` carried a heuristic token-budget test asserting the gate's input fits within ADR-026 TR3's ≤4k tokens-per-Haiku-call budget:

```ts
const promptInput =
  skillContent + "\n\n--- DIFF ---\n" + SYNTHETIC_DIFF +
  "\n\n--- PLAN EXCERPT ---\n" + SYNTHETIC_PLAN_EXCERPT;
const estimatedTokens = Math.ceil(promptInput.length / 4);
expect(estimatedTokens).toBeLessThanOrEqual(4000);
```

After v2 SKILL.md grew from 11956 → 17562 bytes (+5606 chars ≈ +1402 tokens), the test failed with `Expected: <= 4000 / Received: 4572`. The growth was intentional and load-bearing — `## --repo-scan mode` documents operator-mode behavior that AC-SKILL-2 / AC-SKILL-3 explicitly require.

## Root cause

The v1 heuristic used **full SKILL.md as the worst-case proxy** for what the gate sends to the model. This was always over-conservative — the actual runtime prompt is a curated subset (per SKILL.md's own `## Prompt template — what the gate sends to the model` section: disclaimer + canonical regex + 5 v1 check definitions). v2 grew SKILL.md with operator-facing prose (`## --repo-scan mode`, sharp-edges) that **never enters the model call**, so including it in the heuristic gave a false-positive budget overrun.

The deeper failure: the v1 plan didn't anticipate that SKILL.md would grow with operator-mode docs. The v2 plan's Phase 6 specified `bun test plugins/soleur/test/components.test.ts` (description word-count budget) but did NOT mention the token-budget test in `gdpr-gate.test.ts`. The plan-quoted "≤4k tokens per invocation" precondition was correct for the runtime call; the test that approximated it was the wrong proxy.

## Solution

Refactored the heuristic to extract only the runtime-prompt subset from SKILL.md:

```ts
function extractRuntimePromptSubset(skill: string): string {
  const sectionsToInclude = new Set([
    "Disclaimer (always first)",
    "Path globs (canonical)",
    "5 mandatory v1 checks (FR4)",
    "Output format",
    "Prompt template — what the gate sends to the model",
  ]);
  const out: string[] = [];
  let include = false;
  for (const line of skill.split("\n")) {
    const m = line.match(/^##\s+(.+)$/);
    if (m) {
      include = sectionsToInclude.has(m[1].trim());
    }
    if (include) out.push(line);
  }
  return out.join("\n");
}
```

The new heuristic asserts the same `≤ 4000` budget but against an accurate model of runtime input. After the refactor, the test passes at ~2900 estimated tokens (well under budget) and remains useful as a catastrophic-bloat detector for the runtime-prompt sections specifically.

## Key insight

**A test heuristic's proxy must match what the rule it's enforcing actually measures.** ADR-026 TR3's `≤4k tokens per invocation` is about the **runtime input to the model**, not about SKILL.md's size on disk. The v1 heuristic conflated the two because at v1 they were close-enough — SKILL.md was small and most of it WAS sent. v2 introduced operator-only docs that broke the equivalence.

When a SKILL.md grows with operator-facing or contributor-facing prose that's not part of the runtime prompt, the proxy needs explicit subsetting. Otherwise the test becomes a soft cap on **all** doc growth rather than a meaningful cap on the actual budget. That's the same anti-pattern as a description-word-count test that includes YAML framing (see `2026-04-19-skill-description-word-budget-tokenizer.md`).

## Prevention

- When extending a SKILL.md with operator-only / manual-mode / sharp-edges sections, audit the existing test suite for tests whose heuristic uses the full SKILL.md as a proxy. Refactor those heuristics in the SAME PR — don't defer.
- New token-budget tests should be constructed against the **literal subset that flows into the runtime call**, not "everything we wrote in SKILL.md". The Prompt-template section is the source of truth for what's actually sent.
- Plan-write-time precondition checklists should explicitly enumerate which existing tests depend on SKILL.md size and require updating.

## Session Errors

- **Worktree `.git` is a file, not a directory** — review skill's classification gate prescribed `.git/review-changed.txt` as a scratch path; in worktrees this errored `Not a directory (os error 20)`. Recovery: used `/tmp/`. **Prevention:** update review SKILL.md to use `/tmp/review-changed.txt` (or a worktree-safe alternative) per `hr-when-in-a-worktree-never-read-from-bare`. Routes to `plugins/soleur/skills/review/SKILL.md`.

- **Token-budget heuristic over-conservative after SKILL.md growth** — described in full above; primary subject of this learning.

- **Plan-quoted hit counts drifted between write-time and implement-time** — plan §"v2 deny-list contents" claimed pattern 2 (`secrets/`) had 4 hits; actual = 0. Pattern 7 claimed 2386; actual = 2389. **Prevention:** already covered by `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`; no new rule needed.

- **Pre-existing marketing-content-drift flake surfaced during verification** — `beforeAll` running `npm run docs:build` exceeds bun-test default 5s hook timeout intermittently. Filed #3531. **Prevention:** rule already exists (`wg-when-tests-fail-and-are-confirmed-pre`); no new rule needed.

- **Symlink-leakage vector not anticipated by v2 plan threat model** — security-sentinel flagged that D1-D5 didn't enumerate symlinks. A contributor adding `apps/web-platform/lib/auth/foo.ts -> ../../.env` would have leaked target content via downstream readers. Recovery: added D6 to `repo-scan.sh` (`[[ -L "$path" ]]` guard). **Prevention:** plan-time security review for filesystem-walking scripts must explicitly enumerate symlink behavior in the threat model. Routes to `plugins/soleur/skills/plan/SKILL.md` Sharp Edges (or to `plugins/soleur/agents/engineering/review/security-sentinel.md`).

- **`shopt -s nocasematch` is NOT function-scoped** — using it inside `path_is_denied()` without paired `shopt -u nocasematch` before return would leak into the caller (`is_allowed()` uses `[[ == ]]`, which is ALSO affected by `nocasematch`, and must stay byte-exact for allow-list correctness). Recovery: explicit set-then-unset pattern in the helper. **Prevention:** bash `shopt` is process-global. When toggling `nocasematch` (or any shopt option) inside a helper that's called by callers with different case-sensitivity needs, always pair `shopt -s X` with `shopt -u X` before every return path. This is bash-specific lore that `set -euo pipefail` doesn't catch.

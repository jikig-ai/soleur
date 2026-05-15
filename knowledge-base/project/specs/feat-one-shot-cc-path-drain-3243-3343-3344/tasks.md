---
title: "tasks: drain cc-path cluster — #3343 + #3344 (split #3243)"
plan: knowledge-base/project/plans/2026-05-15-refactor-cc-path-drain-3343-3344-plan.md
branch: feat-one-shot-cc-path-drain-3243-3343-3344
lane: single-domain
---

# Tasks

## Phase 0 — Preconditions

- [ ] 0.1 — `git status --short` clean.
- [ ] 0.2 — `wc -l apps/web-platform/server/cc-dispatcher.ts` ≈ 1904.
- [ ] 0.3 — `grep -c 'replaceAll("</document>"' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns 3+3 = 6.
- [ ] 0.4 — `grep -n 'CC_PATH_DISALLOWED_TOOLS' apps/web-platform/server/cc-dispatcher.ts` returns lines 668, 1052.
- [ ] 0.5 — Baseline: `cd apps/web-platform && bun run test:ci -- test/cc-dispatcher.test.ts` green. STOP on RED.

## Phase 1 — RED (failing tests first)

- [ ] 1.1 — Add 3 case-variant rows (`</Document>`, `</DOCUMENT>`, `</document >`) to `apps/web-platform/test/agent-runner-system-prompt.test.ts`. Confirm RED.
- [ ] 1.2 — Add 3 case-variant rows to `apps/web-platform/test/read-tool-pdf-capability.test.ts`. Confirm RED.
- [ ] 1.3 — Create `apps/web-platform/test/cc-dispatcher-bash-safe-allowlist.test.ts` with:
  - 1.3.1 — Row A: `command: "pwd"` against cc-path canUseTool → expect `behavior: "allow"`. Confirm RED.
  - 1.3.2 — Row B: `command: "find . -name '*.pdf'"` → expect `review_gate` routing. Confirm GREEN (already current behavior).
- [ ] 1.4 — Commit checkpoint: `test(cc-path): RED rows for case-insensitive </document> escape + cc-path safe-bash widening`.

## Phase 2 — GREEN #3343

- [ ] 2.1 — Replace 6 `replaceAll("</document>", "<\\/document>")` sites with `.replace(/<\s*\/\s*document\s*>/gi, "<\\/document>")`:
  - 2.1.1 — `apps/web-platform/server/soleur-go-runner.ts:1031`
  - 2.1.2 — `apps/web-platform/server/soleur-go-runner.ts:1147`
  - 2.1.3 — `apps/web-platform/server/soleur-go-runner.ts:2441`
  - 2.1.4 — `apps/web-platform/server/agent-runner.ts:980`
  - 2.1.5 — `apps/web-platform/server/agent-runner.ts:1089`
  - 2.1.6 — `apps/web-platform/server/agent-runner.ts:1112`
- [ ] 2.2 — Verify §Risks R8: Edit `old_string` must NOT span the adjacent `[\x00-\x1f\x7f  ]/g` sanitizer char class.
- [ ] 2.3 — AC1 grep: `grep -nE 'replaceAll\("</document>"' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns 0 matches.
- [ ] 2.4 — AC2 grep: `grep -nE 'replace\(/<\\s\*\\/\\s\*document\\s\*>/gi' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns 6 matches.
- [ ] 2.5 — Re-run case-variant tests — all GREEN.
- [ ] 2.6 — Existing lowercase `</document>` tests still GREEN.
- [ ] 2.7 — Commit checkpoint: `fix(cc-path): case-insensitive </document> escape parity (Closes #3343)`.

## Phase 3 — GREEN #3344

- [ ] 3.1 — Edit `apps/web-platform/server/cc-dispatcher.ts:668`: drop `"Bash"`. Final: `["Edit", "Write"]`.
- [ ] 3.2 — Update doc-comment block at lines ~634-670: explain routing through canUseTool + safe-bash allowlist + structural mitigations (#3338, #3430). Reference §Research Insights "Cap-coupling".
- [ ] 3.3 — Row A (Phase 1.3.1) flips RED→GREEN.
- [ ] 3.4 — Row B (Phase 1.3.2) stays GREEN.
- [ ] 3.5 — Existing `cc-dispatcher-bash-gate.test.ts` still GREEN.
- [ ] 3.6 — Existing `cc-mcp-tier-allowlist.test.ts` still GREEN.
- [ ] 3.7 — Commit checkpoint: `feat(cc-path): widen Bash via safe-bash allowlist (Closes #3344)`.

## Phase 4 — Bundle gates

- [ ] 4.1 — `cd apps/web-platform && bun run typecheck` clean.
- [ ] 4.2 — `cd apps/web-platform && bun run test:ci` full suite green.
- [ ] 4.3 — `cd apps/web-platform && bun run lint` clean.
- [ ] 4.4 — Create `apps/web-platform/scripts/3243-status-comment.md` (body template for #3243 status comment).
- [ ] 4.5 — Create `apps/web-platform/scripts/safe-bash-extension-followup.md` (body template for the follow-up issue).
- [ ] 4.6 — Commit checkpoint: `chore(cc-path): post-merge templates for #3243 + safe-bash follow-up`.

## Phase 5 — PR + Ship

- [ ] 5.1 — Open PR with body containing: `Closes #3343`, `Closes #3344`, `## #3243 Disposition` section linking to PRs #3608 + #3670, reference to PR #2486 as bundle-closure pattern.
- [ ] 5.2 — /soleur:review (multi-agent — security-sentinel + architecture-strategist + user-impact-reviewer mandatory).
- [ ] 5.3 — Address review-fix inline.
- [ ] 5.4 — /soleur:ship — handles `gh pr ready` + post-merge `gh issue comment 3243` (AC17) + `gh issue create` for safe-bash follow-up (AC18).

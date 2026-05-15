---
title: "refactor(cc-path): drain deferred-scope-out cluster — #3343 + #3344 (split #3243)"
type: refactor
status: draft
branch: feat-one-shot-cc-path-drain-3243-3343-3344
issues: [3343, 3344]
issues_split_out: [3243]
bundle_closure_reference: 2486
lane: single-domain
requires_cpo_signoff: false
created: 2026-05-15
deepened: 2026-05-15
---

# Plan: Drain deferred-scope-out cluster #3343 + #3344 — case-insensitive `</document>` escape parity + cc-path safe-bash widening

## Enhancement Summary

**Deepened on:** 2026-05-15
**Sections enhanced:** 5 (Test Strategy, Acceptance Criteria, Risks, Research Reconciliation, Implementation Phases)
**Verification passes:**
- All 3 issues verified live via `gh issue view --json state` (all `OPEN`).
- All 3 cited PRs verified live via `gh pr view --json state` (all `MERGED`: #2486, #3430, #3608, #3670).
- Cited AGENTS.md rule `cq-regex-unicode-separators-escape-only` verified active at `AGENTS.rest.md`.
- 5 prescribed labels verified existent via `gh label list`.
- Milestone `Post-MVP / Later` verified existent via `gh api repos/jikig-ai/soleur/milestones` (`number: 6, state: open`).
- 6 case-sensitive `</document>` sites verified via `grep -nE 'replaceAll\("</document>"'` (3 in `soleur-go-runner.ts`, 3 in `agent-runner.ts`).
- `CC_PATH_DISALLOWED_TOOLS` location verified at `cc-dispatcher.ts:668`.
- `safe-bash.ts` allowlist contents verified (find/grep intentionally omitted).
- Existing test framework verified as **vitest** (not `bun test`) via `apps/web-platform/package.json` and `cc-dispatcher-bash-gate.test.ts` imports.

### Key Improvements

1. **Corrected test runner commands.** v1 prescribed `bun test`/`bun run tsc`/`bun run lint`; `apps/web-platform/package.json` confirms `vitest`/`tsc --noEmit`/`next lint`. AC11-13 rewritten.
2. **Bash-modal UX tradeoff made explicit.** The existing doc-comment at `cc-dispatcher.ts:634-647` states the original hard-block existed because Bash "pops the review_gate modal in the end-user Concierge surface (the bug this PR fixes)." #3344's widening reintroduces the modal for non-allowlist verbs — but safe-bash auto-approves the common KB-exploration verbs (`pwd`/`ls`/`cat`/`git status`), so the modal cascade #3338 originally mitigated (`find` / `apt-get install`) does not return for those verbs. The plan's new §Risks R7 captures the residual modal exposure for verbs that ARE rejected by safe-bash and routes through review_gate.
3. **Bash decision-chain enumerated** in §Research Insights so the implementer doesn't have to trace `permission-callback.ts:280-460` to understand what flips on #3344.
4. **AGENTS.md rule-id citation hygiene** verified — all cited rule IDs grep-resolve in `AGENTS*.md` and none appear in `scripts/retired-rule-ids.txt`.
5. **Cap-coupling check** added: #3338 (PDF cap 24 MB) + #3430 (page-count gate) are confirmed as the structural mitigations for the cascade the original hard-block addressed. The narrative in §AC7's doc-comment update reflects this.

## Overview

This is a bundle-closure PR for the `apps/web-platform` cc-path / dispatcher cluster, following the #2486 pattern (close more than you open). Two scoped fixes land together because they share the same blast radius (cc-router + leader prompt builders + permission-callback), share the same test surface (`apps/web-platform/test/cc-*`), and share the same review-pivot risk (security-sentinel + architecture-strategist coverage).

**Scope:**

- **#3343** — Replace 6 case-sensitive `replaceAll("</document>", ...)` sites with a case-insensitive `/<\s*\/\s*document\s*>/gi` regex across `soleur-go-runner.ts` (3 sites) + `agent-runner.ts` (3 sites). Add regression tests pinning `</Document>`, `</DOCUMENT>`, `</document >`.
- **#3344** — Drop `"Bash"` from `CC_PATH_DISALLOWED_TOOLS` so the cc-router routes Bash through `canUseTool` (sharing the legacy path's existing `safe-bash` allowlist). Add an E2E test pinning that a benign read-only Bash command (`pwd` / `ls`) auto-approves without a modal.

**Closes:** #3343, #3344
**Stays open with status comment:** #3243 (rationale in §"AC Tension — #3243 Disposition" below).

**Reference closure pattern:** PR #2486 — 3 closes / 13-file scope / vitest+typecheck+build gates. This PR follows the same shape (2 closes / ~6 file scope / same gates).

## AC Tension — #3243 Disposition

**Decision: split #3243 out of this drain entirely.**

### Why (the three triggers)

1. **The "smallest, most self-contained" target named by the issue is already done.** The issue body (filed against #3235) recommended "mirrorWithDebounce first — smallest, most self-contained." That extraction landed in PR #3608 (`fix(cc): V2 Command Center hardening — safe-bash module, mirror debounce, idle-reaper, wall-clock budget`) and was further consolidated in PR #3670 (`refactor(cc-dispatcher): cluster drain (#3639 + #3640 + #3641 + #3642)`). Today `mirrorWithDebounce` lives in `apps/web-platform/server/observability.ts:331`; `cc-dispatcher.ts:64` only imports it.

2. **The issue author explicitly forbade bundling.** Issue body §Acceptance Criteria states: "One PR per extraction (`mirrorWithDebounce` first — smallest, most self-contained)." Drain attempting any extraction beyond mirrorWithDebounce — let alone all 5 — would directly violate the issue's own AC.

3. **Active code-coupling collision with #3344.** #3344 modifies `CC_PATH_DISALLOWED_TOOLS` at `cc-dispatcher.ts:668`. Any extraction that moves `_ccBashGates` (concern #5 in #3243) to a sibling module would re-thread Bash review-gate registration through cc-dispatcher's main file in the exact window where #3344 is widening the cc-path's Bash surface. Co-shipping risks a silent merge-time gap between the new `cc-bash-gates.ts` module and the Bash review-gate fired by the new safe-bash allowlist — exactly the kind of pivot a refactor PR should avoid.

### Action

- Post a status comment on #3243 (post-merge, via `gh issue comment`) noting (a) the mirrorWithDebounce extraction is already complete (#3608, #3670), (b) the remaining 4 sibling extractions each need an ADR per the issue body, and (c) the next sibling-extraction PR's smallest unit will be `cc-workflow-end-messages.ts` (~15 LoC, pure data + exhaustiveness rail, near-zero behavior risk — see `cc-dispatcher.ts:585-610`).
- Update #3243's re-evaluation criteria with a one-line note that an ADR + smallest-extraction PR is the next concrete step. Re-evaluation criteria stay otherwise as filed.
- #3243 remains labeled `deferred-scope-out` + `code-review` + Post-MVP/Later. The cleanup drain's net-impact stays positive (2 closes / 0 new scope-outs).

## Research Reconciliation — Spec vs. Codebase

Three drift points between the issue bodies and `main` were caught at plan time. The plan tracks reality, not the issue bodies.

| Spec/Issue Claim | Reality (verified on `main`) | Plan Response |
|---|---|---|
| #3343: 4 case-sensitive `</document>` escape sites at `soleur-go-runner.ts:554, 572` + `agent-runner.ts:736, 755`. | **6 sites total.** `grep -nE 'replaceAll\("</document>"' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns: `soleur-go-runner.ts:1031, 1147, 2441` + `agent-runner.ts:980, 1089, 1112`. Files grew past the issue's snapshot. | Plan §"Files to Edit" lists **all 6 sites**; AC verification grep is bounded to those two files and asserts `0` matches of the case-sensitive form post-fix. |
| #3243: cc-dispatcher.ts is 937 lines (~10 mixed concerns); mirrorWithDebounce is the "smallest" extraction. | **cc-dispatcher.ts is 1904 lines** (`wc -l apps/web-platform/server/cc-dispatcher.ts`). `mirrorWithDebounce` is already imported from `./observability` (line 64); the in-file definition is gone. Confirmed by `git log --oneline -- apps/web-platform/server/cc-dispatcher.ts` showing PR #3608 + #3670 land the extraction. | Plan splits #3243 out (§"AC Tension"). No code touched for #3243; status comment on the issue refreshes re-evaluation criteria. |
| #3344: "re-introduce Bash on the cc-router with curated safe-bash allowlist — `find` (path-scoped), `grep`, `rg`, `wc`, `sort`, `uniq`, `head`, `tail`, `cat`, `git status/log/diff`." | **`safe-bash.ts` already exists** (`apps/web-platform/server/safe-bash.ts:69`) with: `pwd, whoami, id, date, hostname, cd, ls, cat, head, tail, wc, file, stat, which, uname, git (status/log/diff/show/branch/rev-parse/config --get), echo`. The file's own comments **intentionally OMIT `find` and `grep`** — "both accept `-exec` and could shell out. `find` is also redundant with the SDK's `Glob` tool which is auto-allowed via FILE_TOOLS." `sort`/`uniq`/`rg` are not in the allowlist either. | Plan adopts the **already-shipped allowlist verbatim** for the cc-path. The widening is **wiring-only**: drop `"Bash"` from `CC_PATH_DISALLOWED_TOOLS` and let cc-path route through the same `canUseTool` → `isBashCommandSafe` chain the legacy path uses. **`find`/`grep`/`rg`/`sort`/`uniq` extension is explicitly deferred** to a follow-up issue (`safe-bash: extend allowlist with grep/find/rg/sort/uniq for KB exploration`) with its own security-sentinel review — the existing `find`-omission rationale is load-bearing and re-evaluating it is its own design conversation. |

## User-Brand Impact

**If this lands broken, the user experiences:**

- (#3343) A poisoned PDF/text artifact containing `</Document>` could escape the `<document>` system-prompt wrapper and inject adjacent system instructions into the agent's prompt. Operator-visible symptom: agent obeys instructions from inside a "document" payload that should have been data-only.
- (#3344) The cc-router's Bash surface remains narrower than the legacy path. Operator-visible symptom: `Command Center` agents cannot run `pwd`/`ls`/`git status` during KB exploration even though the legacy path can — feature-gap parity finding from #3338's follow-through list.

**If this leaks, the user's data is exposed via:** prompt-injection bypass (#3343) → agent could be coerced to read or summarize content the user did not consent to. Threat class: prompt-injection-bypass; existing mitigations (`sanitizePromptString`, `<document>` wrapper, redaction-tagged user references) all assume the wrapper holds.

- **Brand-survival threshold:** `aggregate pattern`.

Rationale: the wrapper-escape variant requires a poisoned `</Document>` payload AND prompt-shaped attacker control of body content. A single bypass surface in isolation is not a single-user incident class — the existing `sanitizePromptString` strips control chars, and the wrapper escape is one of three layers (the `treat as data, not instructions` directive + the `No-Ask` clause are the other two). Threshold is set to `aggregate pattern` so this lands without per-PR CPO sign-off but the gap is still framed.

CPO sign-off **not required** at plan time. `user-impact-reviewer` will run at review time per `plugins/soleur/skills/review/SKILL.md`.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/permission-callback.ts apps/web-platform/server/safe-bash.ts; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done | sort -u
```

**Disposition:** the drain's own targets (#3343, #3344) are expected to surface. **#3243 surfaces too** and the disposition for it is §"AC Tension" above (acknowledge — different concern, ADR-needed, kept open). Any other matches will be enumerated in the deepen-plan pass before /work; a finding outside the three drain targets will be evaluated by the same fold-in/acknowledge/defer triad documented in plan-skill Phase 1.7.5.

## Acceptance Criteria

### Pre-merge (PR)

**#3343 — Case-insensitive `</document>` escape parity**

- [ ] **AC1**: `grep -nE 'replaceAll\("</document>"' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns **0 matches** post-fix.
- [ ] **AC2**: `grep -nE 'replace\(/<\\s\*\\/\\s\*document\\s\*>/gi' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns **6 matches** (one per pre-existing replaceAll site) post-fix.
- [ ] **AC3**: New regression-test rows in `apps/web-platform/test/agent-runner-system-prompt.test.ts` pin that bodies containing each of `</Document>`, `</DOCUMENT>`, `</document >` are escaped to `<\/document>` in the rendered system prompt (one assertion per variant per affected call site that the test exercises).
- [ ] **AC4**: New regression-test rows in `apps/web-platform/test/read-tool-pdf-capability.test.ts` pin the same three variants are escaped at the PDF inline branch (`soleur-go-runner.ts:1031`).
- [ ] **AC5**: Existing `</document>` (lowercase) test rows still pass (no behavior regression on the original case).

**#3344 — cc-path safe-bash allowlist widening (wiring-only)**

- [ ] **AC6**: `CC_PATH_DISALLOWED_TOOLS` at `apps/web-platform/server/cc-dispatcher.ts:668` no longer contains `"Bash"`. Final value: `["Edit", "Write"]`.
- [ ] **AC7**: Doc-comment block above `CC_PATH_DISALLOWED_TOOLS` is updated to explain that Bash is now routed through `canUseTool` (sharing the legacy path's safe-bash allowlist + review_gate fallback) and that the previous hard-block existed to mitigate the `find . -name '*.pdf'` / `apt-get install poppler-utils` modal cascade — which is now mitigated by (a) the PDF page-count gate (#3430) and (b) the safe-bash allowlist's intentional `find`/`apt-get` omission.
- [ ] **AC8**: New E2E test `apps/web-platform/test/cc-dispatcher-bash-safe-allowlist.test.ts` exercises the cc-router's `canUseTool` path with a benign Bash input (`{command: "pwd"}`) and asserts the result is `{behavior: "allow", ...}` (auto-approved-safe-bash branch) without firing a review-gate modal.
- [ ] **AC9**: Same test exercises an out-of-allowlist input (`{command: "find . -name '*.pdf'"}`) and asserts the result routes to `review_gate` (i.e., the existing modal path still gates non-allowlist verbs). This pins the `find`-omission invariant.
- [ ] **AC10**: Existing `cc-dispatcher.test.ts`, `cc-mcp-tier-allowlist.test.ts`, `cc-dispatcher-bash-gate.test.ts` all still pass — no behavior change to the legacy path or to existing cc-path tool routing.

**Bundle gates**

- [ ] **AC11**: `cd apps/web-platform && bun run typecheck` clean (resolves to `tsc --noEmit` per `package.json scripts.typecheck`).
- [ ] **AC12**: `cd apps/web-platform && bun run test:ci` green (resolves to `vitest run` per `package.json scripts.test:ci`). Full web-platform suite.
- [ ] **AC13**: `cd apps/web-platform && bun run lint` clean (resolves to `next lint`).
- [ ] **AC14**: PR body contains exactly: `Closes #3343`, `Closes #3344` (one per line). **NOT** `Closes #3243`.
- [ ] **AC15**: PR body contains a `## #3243 Disposition` section referencing this plan's §"AC Tension" and linking to PR #3608 + #3670 (which landed mirrorWithDebounce).
- [ ] **AC16**: PR body references PR #2486 as the bundle-closure pattern (per drain instructions).

### Post-merge (operator — automated where possible)

- [ ] **AC17**: `gh issue comment 3243 --body "$(cat ./scripts/3243-status-comment.md)"` — status comment refreshing re-evaluation criteria (next-extraction = `cc-workflow-end-messages.ts`, ADR required). Comment template lives at `apps/web-platform/scripts/3243-status-comment.md` (created in this PR; see §"Files to Create"). Automation: `gh` CLI via Bash; handled by `/soleur:ship` post-merge step.
- [ ] **AC18**: `gh issue create --title "safe-bash: extend allowlist with grep/find/rg/sort/uniq for KB exploration" --label deferred-scope-out --label code-review --label domain/engineering --label type/chore --label priority/p3-low --milestone "Post-MVP / Later" --body-file ./scripts/safe-bash-extension-followup.md` — file the deferred portion of #3344's original ask (the `find`/`grep`/`rg` extension was intentionally omitted from this PR; see §"Research Reconciliation"). Body template lives at `apps/web-platform/scripts/safe-bash-extension-followup.md`. Automation: `gh` CLI via Bash.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — 3 sites: lines `1031`, `1147`, `2441`. Replace `.replaceAll("</document>", "<\\/document>")` with `.replace(/<\s*\/\s*document\s*>/gi, "<\\/document>")`.
- `apps/web-platform/server/agent-runner.ts` — 3 sites: lines `980`, `1089`, `1112`. Same replacement.
- `apps/web-platform/server/cc-dispatcher.ts` — line `668`: `const CC_PATH_DISALLOWED_TOOLS: readonly string[] = ["Bash", "Edit", "Write"];` → `["Edit", "Write"]`. Update the surrounding doc comment (lines `~640-670`) to reflect the new routing rationale.
- `apps/web-platform/test/agent-runner-system-prompt.test.ts` — add 3 test rows pinning each `</Document>` / `</DOCUMENT>` / `</document >` variant at the test's existing `<document>`-wrapper exercise (see test at line ~214 already pins `<document>` injection shape for `#3338`).
- `apps/web-platform/test/read-tool-pdf-capability.test.ts` — add 3 test rows for the PDF inline branch (line ~214 currently pins documentKind=pdf with documentContent; extend with the case-variant fixtures).

## Files to Create

- `apps/web-platform/test/cc-dispatcher-bash-safe-allowlist.test.ts` — new vitest E2E test exercising the cc-router's `canUseTool` for Bash routing (AC8, AC9). Test fixture pattern: existing `cc-dispatcher-bash-gate.test.ts` is the closest sibling (vitest + standard `vi.mock` shape for `@anthropic-ai/claude-agent-sdk`, `@sentry/nextjs`, `@/server/ws-handler`, `@/server/notifications`, `@/server/observability`, `@/server/logger`). Reuse that mock prelude verbatim to keep drift low.
- `apps/web-platform/scripts/3243-status-comment.md` — body template for the post-merge status comment on #3243 (AC17).
- `apps/web-platform/scripts/safe-bash-extension-followup.md` — body template for the safe-bash extension follow-up issue (AC18).

## Implementation Phases

### Phase 0 — Preconditions (verify, do not code)

- `git status --short` clean on the feature branch.
- `wc -l apps/web-platform/server/cc-dispatcher.ts` confirms ~1904 lines (sanity check vs. issue-body's 937).
- `grep -c 'replaceAll("</document>"' apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns **3+3 = 6**.
- `grep -n 'CC_PATH_DISALLOWED_TOOLS' apps/web-platform/server/cc-dispatcher.ts` returns lines 668, 1052.
- `cd apps/web-platform && bun run test:ci -- test/cc-dispatcher.test.ts` green (baseline; vitest run via package.json script). If RED, **STOP** and report — pre-existing failure must be triaged before any edit.

### Phase 1 — Failing tests first (RED)

1. Add the 3 regression rows to `agent-runner-system-prompt.test.ts` exercising `</Document>`, `</DOCUMENT>`, `</document >`. Expected: **all RED** — current `replaceAll` is case-sensitive and won't escape these variants. Each test asserts the rendered system prompt contains exactly `<\/document>` after substitution (i.e., the escape fired).
2. Add the same 3 rows to `read-tool-pdf-capability.test.ts` for the PDF inline branch. Expected: **all RED**.
3. Create `cc-dispatcher-bash-safe-allowlist.test.ts` with two test rows: (a) `pwd` auto-approves (AC8), (b) `find . -name '*.pdf'` routes to review_gate (AC9). Expected: **(a) RED — currently denied because Bash is in `CC_PATH_DISALLOWED_TOOLS`**; **(b) GREEN — find is already not in safe-bash allowlist, so review_gate routing is the current behavior**.
4. Commit checkpoint: `test(cc-path): RED rows for case-insensitive </document> escape + cc-path safe-bash widening`.

### Phase 2 — GREEN (#3343)

5. Replace 6 `replaceAll` sites with the case-insensitive regex form. Apply uniformly — same regex literal at all sites.
6. Re-run the 6 case-variant test rows from Phase 1 — expect **all GREEN**.
7. Re-run existing `</document>` (lowercase) rows — expect **still GREEN** (no regression).
8. Commit checkpoint: `fix(cc-path): case-insensitive </document> escape parity (Closes #3343)`.

### Phase 3 — GREEN (#3344)

9. Edit `cc-dispatcher.ts:668` — drop `"Bash"` from `CC_PATH_DISALLOWED_TOOLS`.
10. Edit the doc-comment block above the constant to explain the new routing.
11. Re-run `cc-dispatcher-bash-safe-allowlist.test.ts` — expect **AC8 row flips RED→GREEN**; **AC9 row stays GREEN**.
12. Re-run existing `cc-dispatcher-bash-gate.test.ts` — expect **still GREEN** (review-gate registration for non-allowlist Bash is unchanged).
13. Re-run `cc-mcp-tier-allowlist.test.ts` — expect **still GREEN** (MCP tier check is independent of CC_PATH_DISALLOWED_TOOLS).
14. Commit checkpoint: `feat(cc-path): widen Bash via safe-bash allowlist (Closes #3344)`.

### Phase 4 — Bundle gates

15. `cd apps/web-platform && bun run typecheck` — clean (tsc --noEmit).
16. `cd apps/web-platform && bun run test:ci` — full vitest suite green.
17. `cd apps/web-platform && bun run lint` — clean (next lint).
18. Create `apps/web-platform/scripts/3243-status-comment.md` + `apps/web-platform/scripts/safe-bash-extension-followup.md` (templates only; not yet posted).
19. Commit checkpoint: `chore(cc-path): post-merge templates for #3243 + safe-bash follow-up`.

### Phase 5 — Domain Review carry-forward + PR

20. PR body uses `Closes #3343` + `Closes #3344` + `## #3243 Disposition` section + `## Bundle-closure pattern: PR #2486` reference.
21. /soleur:ship handles `gh pr ready` + post-merge `gh issue comment 3243` + `gh issue create` for the safe-bash follow-up (per AC17 + AC18).

## Test Strategy

**Framework:** **vitest** (canonical for `apps/web-platform/` — `apps/web-platform/package.json scripts.test = "vitest"`, `scripts.test:ci = "vitest run"`). Confirmed via sibling test header: `cc-dispatcher-bash-gate.test.ts` imports `{ describe, it, expect, vi, beforeEach } from "vitest"`. No new test framework; no new dev dependency.

**Test corpus:**

- `agent-runner-system-prompt.test.ts` (≥10 existing test rows; +3 new) — exercises `buildSoleurGoSystemPrompt` and `buildAgentSystemPrompt` factories.
- `read-tool-pdf-capability.test.ts` (≥10 existing; +3 new) — exercises the PDF-gated branch.
- `cc-dispatcher-bash-safe-allowlist.test.ts` (new; 2 rows) — new E2E test exercising `canUseTool` Bash routing.
- Full `apps/web-platform/test/` suite as the regression gate (AC12).

**RED-test discipline:** each new test row is verified RED before its corresponding GREEN edit lands. The Phase 1 commit checkpoint captures the RED state so a reviewer can verify the test would have caught the bug.

**No LLM in assertion path:** all assertions are on **direct string substring checks** of the rendered system prompt (#3343) or on the synchronous `canUseTool` return value (#3344). No `query()` round-trip. See AGENTS.md learning `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`.

## Hypotheses

None — no SSH/firewall/network surface. Plan-network-outage-checklist does not apply.

## Research Insights

### #3344 Bash decision chain (post-widening)

Once `"Bash"` is removed from `CC_PATH_DISALLOWED_TOOLS`, the cc-router's Bash routing flows through `permission-callback.ts:createCanUseTool` in this exact order (verified by reading `permission-callback.ts:284-440`):

1. **Empty-command deny** (`permission-callback.ts:292-302`). Defense-in-depth against malformed inputs.
2. **`isBashCommandBlocked`** (`permission-callback.ts:307-330`). Hard-deny on `BLOCKED_BASH_PATTERNS` — `curl|wget|nc|sh -c|eval|base64 -d|/dev/tcp|sudo`. **This is unchanged** by #3344. Unsafe commands still cannot reach the model.
3. **`isBashCommandSafe`** (`permission-callback.ts:336-355`). Auto-approve via the existing `SAFE_BASH_PATTERNS` allowlist in `safe-bash.ts:69`. Verbs covered: `pwd`, `whoami`, `id`, `date`, `hostname`, `cd`, `ls`, `cat`, `head`, `tail`, `wc`, `file`, `stat`, `which`, `uname`, `git status/log/diff/show/branch/rev-parse/config --get`, `echo`. **No modal fires** for these.
4. **`SAFE_BASH_NEAR_MISS_PREFIX`** (`permission-callback.ts:364-390`). Telemetry-only — emits `safe-bash-near-miss` for verbs whose leading token starts with an allowlist verb but extends past it (`lsof` vs `ls`, etc.). Per-ctx 32-event budget; PII-safe (32-char slice on leading token). Does NOT change the decision.
5. **`bashApprovalCache`** (`permission-callback.ts:395-413`). Batched-approval cache (#2921) — if the user previously hit "Approve all `<prefix>`", subsequent matching commands auto-approve.
6. **`review_gate`** (`permission-callback.ts:418-450`). Modal — user sees `Run Bash command?\n\n`<preview>`` with 2 or 3 options (`Approve` / `Reject` / optionally `Approve all `<prefix>``). If user is offline, `notifyOfflineUser` is invoked. This is the **only step that pops a modal**.

**Net effect of #3344:** verbs covered by step 3 (the allowlist) auto-approve silently — the explicit goal of the change. Verbs NOT covered (e.g., `find`, `grep`, `rg`, `apt-get install`, `npm install`) route to step 6 and pop a modal — exactly what #3338's hard-block was preventing. The plan's residual exposure is in §Risks R7.

### `</document>` regex — case-insensitive escape pattern (#3343)

`/<\s*\/\s*document\s*>/gi` decomposes as:

- `<` — literal open-angle.
- `\s*` — optional whitespace (covers `< /document>` and `<  / document  >`).
- `\/` — literal forward-slash (the escape is required only inside `/.../` regex literals; not strictly required here but harmless and matches the issue body verbatim).
- `\s*` — same.
- `document` — literal verb.
- `\s*` — covers `</document >` (the issue body's third pin).
- `>` — literal close-angle.
- `/gi` — global + case-insensitive (covers `</Document>`, `</DOCUMENT>`, `</DocUmEnT>`).

This is structurally a sequence pattern, not a character class, so AGENTS.md rule `cq-regex-unicode-separators-escape-only` does NOT apply directly to the new regex. However, **the surrounding lines on `agent-runner.ts:980`, `1089`, `1112` contain literal U+2028/U+2029 character classes** (`[\x00-\x1f\x7f  ]`). The Edit tool MUST NOT span those character classes when patching the `replaceAll → replace(...)` change. Make the Edit tool's `old_string` start AFTER the `[\x00-\x1f...]/g, "")` substring and end before any other regex literal. The same precaution applies to `soleur-go-runner.ts:1031, 1147, 2441`.

### Cap-coupling — why the cc-path modal cascade is no longer a #3344 concern

The original `CC_PATH_DISALLOWED_TOOLS: ["Bash", "Edit", "Write"]` was added in #3338 explicitly to prevent the `find . -name "*.pdf"` / `apt-get install poppler-utils` modal cascade triggered when the agent tried to summarize a large PDF. Two structural mitigations have since landed:

- **#3338** itself: workspace PDF Read ceiling (24 MB) + workspace path scoping (`apps/web-platform/server/safe-bash.ts` PATH_TOKEN denylist on traversal).
- **#3430** (`feat(cc-concierge): page-count gate on PDF soft-route — bridge fix for #3429`): page-count gate on the PDF soft-route. Large PDFs are now classified before the agent attempts inline read.

Net: the agent no longer has a structural reason to try `find` or `apt-get` against user-content paths. The remaining modal exposure under #3344 is for legitimate exploratory verbs the agent emits during KB exploration — exactly what the issue body asks for. The §Risks R7 entry documents what residual modal cascades operators may still see in telemetry.

## Risks & Sharp Edges

- **R1 — Edit-tool U+2028/U+2029 silent rewrite.** The regex literal `<\s*\/\s*document\s*>` does NOT contain U+2028/U+2029, so AGENTS.md rule `cq-regex-unicode-separators-escape-only` does NOT directly apply. But: the SURROUNDING code at `soleur-go-runner.ts:980` contains a `[\x00-\x1f\x7f  ]` character class. If `Edit` is applied at a span that overlaps that line, verify the literal ` ` / ` ` escape forms survive the edit. Recovery: byte-form Python replacement per learning `2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md` §Edit-Tool Sharp Edge.
- **R2 — Case-insensitive regex global flag.** The fix uses `/gi`. The `g` flag is essential — without it, only the first `</document>` variant in a body would be escaped, leaving subsequent ones live. AC2 grep verifies the `gi` modifier survives the edit at all 6 sites.
- **R3 — `find`-omission rationale is load-bearing.** `safe-bash.ts:97` comment: "`find` and `grep` are intentionally OMITTED — both accept `-exec` and could shell out." This rationale predates #3344 and is independent of cc-path vs. legacy. The drain's wiring-only fix preserves it. **Do NOT extend the allowlist in this PR**; the follow-up issue (AC18) is the right place.
- **R4 — Subagent context.** The cc-path's allowedTools list (`CC_PATH_ALLOWED_TOOLS`) does NOT include `"Bash"`. Per `agent-runner-query-options.ts:131` and the SDK docs, `allowedTools` is auto-approve (not restriction), so omitting Bash there means Bash will route through `canUseTool` — exactly the intended behavior. Verify in Phase 3 that the test exercises this routing path.
- **R5 — Telemetry near-miss firing on normal cc-router exploration.** Once Bash is enabled on the cc-path, the `safe-bash-near-miss` telemetry (`permission-callback.ts:368`) will fire for non-allowlist verbs the cc-router emits (e.g., `find`, `rg`, `sort`). This is **the correct signal**, not a regression — operator dashboards keyed on `safe-bash-near-miss` should expect a baseline shift. Note in the PR body that the near-miss telemetry baseline is expected to rise.
- **R6 — `</Document>` in lowercase-only test fixtures.** Existing test rows may have used the literal `</document>` form as both fixture input AND assertion target. After the fix, the fixture still escapes correctly (lowercase still matches the new `/gi` regex). The new uppercase variants are additional rows, not replacements. Verify in Phase 2 that the lowercase row is still GREEN.
- **R7 — Bash modal residual exposure for non-allowlist verbs (load-bearing).** The existing doc-comment at `cc-dispatcher.ts:634-647` explicitly states the original hard-block existed because Bash "pops the review_gate modal in the end-user Concierge surface (the bug this PR fixes)." #3344's widening **does NOT eliminate that surface** — it merely moves the bar so that **allowlist verbs auto-approve** while **non-allowlist verbs still pop a modal**. This is the intended behavior per #3344's AC ("user asks 'find all my notes about X' → cc-router emits Bash with `find` verb → auto-approved → no modal"), but the issue body's example case (`find`) is itself **NOT** in the existing allowlist — so a literal `find` invocation will still modal. The plan's stance: (a) the structural cascade triggers (PDF page-count, workspace cap) are mitigated by #3338 + #3430, (b) the safe-bash allowlist covers KB-exploration verbs the cc-router actually emits in practice (`ls`, `cat`, `git status`, `pwd`), (c) the `find`/`grep`/`rg` extension is the explicit follow-up filed by AC18. Operator dashboards keyed on `review_gate` rate may see a baseline shift for the cc-path; expected behavior per §Research Insights "Net effect of #3344".
- **R8 — Edit-tool span hazard on U+2028/U+2029.** `agent-runner.ts:980, 1089, 1112` and `soleur-go-runner.ts:1031, 1147, 2441` all contain literal U+2028/U+2029 in adjacent code (`[\x00-\x1f\x7f  ]/g` sanitizer at the start of the same statement). Make the Edit tool's `old_string` exclude the sanitizer char class — match only from `.replaceAll("</document>"...` onward — to prevent the Edit-tool U+2028/U+2029 silent rewrite documented in AGENTS.md `cq-regex-unicode-separators-escape-only` and learning `2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md` §Edit-Tool Sharp Edge.
- **SE7 — `</document>` in regex character class is NOT possible** — the regex `<\s*\/\s*document\s*>` is a sequence pattern, not a char class. The U+2028/U+2029 sharp-edge from R1 only applies to surrounding code, not this regex.
- **SE8 — `.replace(regex, ...)` is NOT idempotent if the regex matches the replacement** — the replacement string `<\/document>` does NOT match `/<\s*\/\s*document\s*>/gi` (the literal `\` is a non-document char by the `<...>` shape), so calling `replace` twice is safe.
- **SE9 — Plan-prescribed labels exist:** `deferred-scope-out`, `code-review`, `domain/engineering`, `type/chore`, `priority/p3-low`, milestone `Post-MVP / Later` all verified via `gh label list --limit 200` + `gh api repos/:owner/:repo/milestones`.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **(a) Close #3243 with just the mirrorWithDebounce extraction in this PR.** | mirrorWithDebounce is already extracted (PR #3608, #3670). There is no extraction work left at that target. Adopting this alternative would close #3243 with a comment-only "already done"; a cleaner shape is the status-comment-on-issue path (AC17) because the remaining 4 extractions (cc-query-factory, cc-bash-gates, cc-sentry-mirror, cc-singletons, cc-workflow-end-messages) still each need their own ADR per the issue body. The issue stays open as a roadmap pointer, not as un-done work. |
| **(b) Co-ship one new extraction (`cc-workflow-end-messages.ts`, ~15 LoC) alongside #3343 + #3344 in this drain.** | The issue body's "one PR per extraction" rule applies. Even the smallest extraction needs its own focused review (typed exhaustiveness rail at the consumer site) that doesn't blend with #3343's regex change or #3344's permission-callback change. Co-shipping risks a confused PR review where the extraction's behavior-equivalence claim distracts from the security-sensitive `</document>` parity. |
| **(c) Extend the safe-bash allowlist with `find`/`grep`/`rg`/`sort`/`uniq` in this PR.** | The existing comment at `safe-bash.ts:97` says `find` and `grep` are intentionally omitted. Re-evaluating that decision needs its own security-sentinel review pass (does the SDK's `Glob` cover the `find` use cases? what about `grep -exec`?). Deferred to the follow-up issue filed by AC18. |
| **(d) Bundle #3343 alone (drop #3344).** | Bundle-closure pattern (PR #2486) target is "close more than you open." #3344 is wiring-only (~5 lines), shares the cc-path code surface, and shares the test corpus. Splitting them would file two PRs for what is naturally one drain. |

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (carry-forward inline — no domain-leader agent invoked since this is a wiring-only / regex-parity refactor with no architecture-level changes).

**Assessment:**

- **Module-boundary impact:** zero new modules; zero re-thread of types/exports; zero new dependencies.
- **Test surface:** +3 rows in 2 existing test files; +1 new test file (~30 LoC). Bun test framework already in use.
- **Security review needed:**
  - **#3343** prompt-injection-bypass class. Mitigation is wrapper-escape regex + existing `sanitizePromptString` + `treat as data, not instructions` directive (3-layer defense). New regex strengthens the wrapper layer.
  - **#3344** cc-path tool-surface widening. Mitigation is the existing `safe-bash.ts` allowlist (curated by #3608 V2 hardening) + review_gate fallback for non-allowlist verbs. **The change is wiring-only — no new verbs added to safe-bash.**

Both findings warrant a security-sentinel review at PR time (`/soleur:review` will spawn it automatically).

## GDPR / Compliance Gate

`/soleur:gdpr-gate` triggers: the canonical regex (schemas, migrations, auth flows, API routes, `.sql` files) does **not** match — no schema/migration/route changes. The four expanded triggers from §2.7 also do not apply:

- (a) No new LLM/external API processing of operator-session-derived data — the regex change is structural, not a new pipeline.
- (b) Brand-survival threshold is `aggregate pattern`, not `single-user incident`.
- (c) No new cron/workflow reading from `knowledge-base/`.
- (d) No new artifact distribution surface.

**Skip silently.**

## Post-Generation Notes

- **No new agents, skills, or user-facing components.** AGENTS.md tier-gate does not apply.
- **No new external services.** No Doppler, Cloudflare, Stripe, Supabase config changes.
- **No new dependencies.** package.json untouched.
- **Telemetry baseline expected to shift:** `safe-bash-near-miss` event volume will rise as cc-router agents emit non-allowlist Bash verbs that previously could not reach the telemetry hook. Note in PR body so operator dashboards expect the shift.

## Sources

- Issue #3243 (closed-as-deferred): `arch: decompose cc-dispatcher.ts into focused modules (Ref #3235)`.
- Issue #3343: `review: case-insensitive </document> escape across cc + leader prompt builders`.
- Issue #3344: `chore(safe-bash): widen cc-path safe-bash allowlist for KB exploration parity`.
- PR #2486: `refactor(kb): extract workspace helper + shared test mocks + ETag support` (bundle-closure pattern reference).
- PR #3608: `fix(cc): V2 Command Center hardening — safe-bash module, mirror debounce, idle-reaper, wall-clock budget` (where mirrorWithDebounce was extracted).
- PR #3670: `refactor(cc-dispatcher): cluster drain (#3639 + #3640 + #3641 + #3642)` (cc-dispatcher cluster drain pattern reference).
- Learning: `knowledge-base/project/learnings/2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md` — informs the Phase 1 RED-first discipline and the regex sharp-edge in §Risks R1.
- `apps/web-platform/server/safe-bash.ts:97` (find/grep omission rationale — load-bearing for §Research Reconciliation row 3).

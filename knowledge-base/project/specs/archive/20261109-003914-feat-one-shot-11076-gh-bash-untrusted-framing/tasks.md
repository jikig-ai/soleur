# Tasks: gh Bash untrusted framing (Ref #11076, epic #9601)

Plan: `knowledge-base/project/plans/2026-11-08-feat-gh-bash-untrusted-framing-plan.md`. PR body uses `Ref #11076` only.

## Phase 0 - Shape verification (no code)

- 0.1 Re-read `BashOutput`/`BashInput` (`sdk-tools.d.ts`) and `PostToolUseHookInput`/`PostToolUseHookSpecificOutput` (`sdk.d.ts`) for the installed SDK; record version + facts for the hook header comment.
- 0.2 Baseline: run `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` (expect `anchors: all 356 rows apply`).

## Phase 1 - RED tests first

- 1.1 `apps/web-platform/test/untrusted-content.test.ts`: `ghReadVerbOf` table (verb / none / shape / oversize rows, each with an `expect` shape, plus a collection-time `registered` floor); hook behaviour rows (one note, byte-equal preamble, non-gh and non-read gh get none and no log, frozen input still framed, no `updatedToolOutput`/`classifierContext`, unknown shapes, throwing getter, 300 KB stdout with `persistedOutputPath`, `PostToolUseFailure` input returns `{}`); preamble pin incl. the "task you were given and the user's own messages decide" clause; telemetry exact key sets per outcome + canary test (real gh command); safe-bash verb-table pin (Guard 3: `admitted` floor = explicit nine-verb positive-control list, `gh api` superset row); fallback rows (comment/heredoc apostrophe, 8193-char padding, past-64-KiB padding); logger-spy assertions filter by `op` and `mockClear()` first; canary rows on shape/error paths.
- 1.2 `apps/web-platform/test/untrusted-content-wiring.test.ts`: Bash registration matrix + legacy-never; options identity against same-egress twins (egress changes other option fields); ordered PostToolUse census (Guard 1) with `registered` counter; rewriter sweep over every hook with WebFetch and gh-Bash inputs; same-input leg (framing note + git-lock `{}`); `includeHookEvents` grep; `sessionIdHash` HMAC value under hoisted pepper.
- 1.3 `apps/web-platform/test/hosted-playwright-mcp-absence.test.ts` (Guard 2, legs 1-5 with floors) and add it to `apps/web-platform/test/repo-wide-suites.ts`.

## Phase 2 - Implementation

- 2.1 `apps/web-platform/server/untrusted-content.ts`: `GH_READ_VERBS`, `GH_FRAME_VERBS`, `ghReadVerbOf` (single forward pass, 8192 cap), `emitGhFrame` (op last), `createGhBashFramingHook`; two Sentry ops `gh-frame-shape` / `gh-frame-error` (debounce classes prefixed `untrusted-content-gh-frame-`); outcomes `annotated|skipped|shape|error`; `ghFallbackScan` (64 KiB, `charCodeAt`, frame anyway past the window) for tokenizer `shape`/`oversize`; telemetry key `fallback`; header comment with Phase 0 facts and no mention of Playwright.
- 2.2 `apps/web-platform/server/agent-runner-query-options.ts`: one conditional spread right after the git-lock Bash entry under `args.webEgress && args.enableUntrustedContentClassify`; update adjacent comments and the classify JSDoc only. No `cc-dispatcher.ts` edit.

## Phase 3 - Architecture record

- 3.0 ADR wording: attacker-reachable bypasses named (bash -c, wrappers, redirect-then-cat, forced non-zero exit via PostToolUseFailure, curl/gh alias); inactive in prd until enabled; delivery unverified; enablement preconditions incl. PA-8(c) + retention period and a measured under-action comparison.
- 3.1 Append `## Addendum 2026-11-08 (Ref #9601, #11076): gh output framing through Bash` to ADR-287 (via `soleur:architecture`): unmeasured framing; covers only `gh` invoked through Bash; cron Bash, Read/attachments, PDF, Playwright and the other named limits uncovered; prd enablement is an operator action. Append-only; no public claim; avoid the forbidden PR-body words.
- 3.2 Extend the one hook-list sentence in the Next.js API container description in `model.c4`; run `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`.

## Phase 4 - Verify and push

- 4.1 Targeted vitest (see plan Phase 6) + `tsc --noEmit`; the slow local `--affected` battery is not awaited because CI is the ship gate.
- 4.2 `--check-anchors` still says all 356 rows apply; eslint `no-control-regex` baseline stays 19.
- 4.3 Before EVERY push both restricted-token greps (plan Phase 6) print nothing.
- 4.4 PR: `Ref #11076` only; `closingIssuesReferences` stays `[]`; no flag/environment change; no public claim.

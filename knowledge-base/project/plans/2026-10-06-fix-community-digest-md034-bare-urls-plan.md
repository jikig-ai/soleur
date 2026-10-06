---
title: "fix: Render community digest URLs as markdown links (MD034 no-bare-urls)"
date: 2026-10-06
slug: community-digest-md034-bare-urls
branch: feat-one-shot-community-digest-md034-bare-urls
issue:
type: fix
lane: cross-domain
---

# fix: Render community digest URLs as markdown links (MD034 no-bare-urls)

## Overview

`renderCommunityPublication` in
`apps/web-platform/server/inngest/functions/_cron-community-publication.ts` (handler-side
publication shipped 2026-10-06 via #9596, commit `ed60833`, ADR-273) emits three bare
`https://github.com/<repo>/…` URLs across two fixed templates: the committed `digestMarkdown`
carries `Review inbound items: ${issuesUrl} and ${pullsUrl}`, and `issueBody` carries
`${DIGEST_FILE_LINE_PREFIX}${digestUrl}` plus `Inbound items: ${issuesUrl} and ${pullsUrl}`.
The digest commits to `knowledge-base/support/community/<YYYY-MM-DD>-digest.md`, which is inside
the markdownlint corpus, and `.markdownlint.json` does not disable MD034. Both digest PRs opened
2026-10-06 (#9586 and #9647 — themselves a same-day duplicate pair) fail the required
`markdown-lint` check with `MD034/no-bare-urls` on the `Review inbound items` line
(`2026-10-06-digest.md:31:23` and `:31:69`).

A digest PR that can never pass CI never merges, so `digestCommittedOnDefaultBranch` stays false,
the same-day dedup gate never satisfies, and a same-day manual re-fire produced the duplicate
digest PR. The asymmetry itself is tracked separately (#6739, non-goal here); this plan fixes the
lint defect that keeps the whole chain stuck.

**Chosen form: markdown link syntax `[label](url)`.** Verified against the repo's pinned
markdownlint-cli 0.49.1 binary: `[t](u)` passes, `<u>` autolinks pass, code spans/blocks pass,
bare URLs (including inside blockquotes and bare `www.`) fail. Link syntax is the corpus-majority
idiom (3,237 `](https` occurrences vs 710 `<https` autolinks), matches prior committed digests
(`knowledge-base/support/community/2026-04-03-digest.md` used `[#1070](https://…/issues/1070)`),
and matches sibling crons that already emit link-form runbook URLs (`cron-ruleset-bypass-audit.ts`,
`cron-cloud-task-heartbeat.ts`). Angle-bracket autolinks were the alternative; they are compliant
but the minority corpus idiom and read worse in the GitHub-rendered digest.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited claim verified live on 2026-10-06:

- `_cron-community-publication.ts` exists on `origin/main` (926 lines); `renderCommunityPublication`
  at ~line 519; bare-URL emit sites at line 588 (`digestMarkdown`) and 606-607 (`issueBody`);
  `issuesUrl`/`pullsUrl`/`digestUrl` consts at 543-545.
- The brief says `.markdownlint.jsonc`; the actual file is `.markdownlint.json` (markdownlint parses
  it as JSONC). MD034 is absent from the disabled set (disabled: MD013/024/025/018/028/026/029/
  033/036/040/041/056/060). Claim held in substance.
- `.markdownlintignore` excludes `knowledge-base/project/`, `knowledge-base/marketing/distribution-content/`,
  fixture dirs and vendored dirs — `knowledge-base/support/community/` is in the swept corpus.
  `scripts/markdown-lint.sh --repo-sweep` is the single invoker for hook and CI.
- Both digest PRs confirmed failing: `gh run view --job 112411068768` shows
  `2026-10-06-digest.md:31:23` and `:31:69` MD034 errors on PR #9647; #9586 fails the same job.
- Sibling PR #9652 (`fix-community-stargazers-read-token`) confirmed to touch the same source file
  at disjoint hunks (`@@ -386` in `buildExampleDraftLine`, `@@ -442` in `effectivePlatform` —
  ours are ~588/606-607). It does also touch `cron-community-monitor-publication-flow.test.ts` at
  ~line 294 (`expectedRender` signature) and ~642 (new describe block) — new assertions in that
  file must be placed away from those lines.
- Same-day dedup asymmetry is tracked by open issue #6739 — non-goal, confirmed still open.
- No markdownlint fixture/golden for digests exists: the flow test reads the real committed file
  from the spawn workspace and compares to `expectedRender().digestMarkdown`; nothing stores
  golden digest bytes.

**Property List (Phase 0.6b).**

1. Committed digest markdown passes MD034 → the required `markdown-lint` check goes green on
   digest PRs → auto-merge unblocks → `digestCommittedOnDefaultBranch` can satisfy → the
   same-day dedup gate works again.
2. `issueBody` renders the same compliant form — parity between the two surfaces so they cannot
   drift apart in future template edits.
3. A pin prevents regression to bare-URL emission: a positive pin on the exact link form plus a
   negative pin on the bare-URL shape.

**Cut List (Phase 0.6b).** None — the brief proposes no mechanism beyond the render change and
test pins. The repo's detector already works (`markdown-lint` fired correctly on both digest PRs);
no new gate, lint, or CI machinery is needed or proposed.

**Test pins that break under the fix** (sweep over `Inbound items` / `Review inbound` /
`Digest file:` / `github.com` assertions across `apps/web-platform/test/`):

- `cron-community-publication.test.ts:996` — asserts `"Inbound items: https://github.com/jikig-ai/soleur/issues"`;
  literal prefix does not survive link syntax.
- `cron-community-monitor-heartbeat.test.ts:151` — asserts `"Inbound items: https://github.com/"` inside
  `expectNoticeBody`; does not survive link syntax.
- `cron-community-publication.test.ts:791-796` — `toContain` on the raw URL strings still passes
  under link syntax (substring) but must be strengthened to pin the compliant form.
- `cron-community-monitor-publication-flow.test.ts` — needs no edit for correctness:
  `expectedRender()` derives expected bodies from the real `renderCommunityPublication`.
  One negative-assertion line is added for end-to-end coverage, placed away from #9652's hunks.

**Learnings applied:**

- `2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md` — suites that pin
  URL-bearing bytes break under either fix form; the three pins above are the complete affected
  set (verified by grep sweep, not guessed).
- ADR-273 (`schema-constrained-handler-side-publication`) — the renderer's contract; prescribes
  no URL format, so link syntax does not amend the ADR.
- Corpus convention: link syntax is already the codebase's own precedent for handler-emitted
  GitHub URLs (`event-cf-token-expiry-check.ts:188`, `cron-ruleset-bypass-audit.ts:420`,
  `cron-cloud-task-heartbeat.ts:325`).

**Research decision (Phase 1.6).** No external research — a closed template edit verified against
the pinned linter binary locally; codebase context fully determines the fix.

**Community discovery / functional overlap (Phases 1.5/1.5b).** TypeScript stack is covered by
built-in agents (skip). Functional-overlap agent could not be spawned in this headless subagent
context; assessed inline — this is a lint-compliance fix on existing code, no new capability a
community artifact could supply.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `.markdownlint.jsonc` does not disable MD034 | File is `.markdownlint.json` (parsed as JSONC); MD034 correctly absent | Fix proceeds; plan names the real file |
| issueBody "emits the same pattern" | issueBody carries THREE bare URLs (`digestUrl` once + `issuesUrl`/`pullsUrl`), not the same two | All three lines get link form |
| "the publication tests (…publication-flow.test.ts and siblings)" | Three files pin the affected text: `cron-community-publication.test.ts`, `cron-community-monitor-heartbeat.test.ts`, plus the flow test via the real renderer | All three enumerated in Files to Edit |

## User-Brand Impact

- **If this lands broken, the user experiences:** the daily community digest keeps failing the
  required `markdown-lint` check, so `knowledge-base/support/community/<date>-digest.md` never
  reaches main — community metrics stop publishing and duplicate digest PRs accumulate in the
  merge queue (two opened on 2026-10-06).
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the change
  relabels three public `github.com/jikig-ai/soleur` URLs; the digest records counts only
  ("Names, quotes and message text are not recorded in this digest").
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the worst outcome is a cosmetic markdown defect in a
  committed doc, caught by required CI before merge; no user data, money, or auth surface moves.
- `threshold: none, reason:` the touched path (`apps/web-platform/server/`) is flagged sensitive
  by the preflight `SENSITIVE_PATH_RE` as a class, but this edit rewrites URL presentation inside
  an already-handler-rendered template — no credential, session, payment, or user-data path is
  involved.

## Observability

```yaml
liveness_signal:
  what:            # required `markdown-lint` CI check on each daily digest PR + existing Sentry cron monitor for the handler
  cadence:         # per-PR (lint gate) / daily (cron monitor scheduled_community_monitor)
  alert_target:    # GitHub required check on the digest PR; Sentry alert route for the cron monitor
  configured_in:   # .github/workflows/pr-quality-guards.yml (markdown-lint job); apps/web-platform/infra/sentry/cron-monitors.tf:355

error_reporting:
  destination:     # Sentry web-platform project (handler silent-fallback events) + the red required check
  fail_loud:       # `markdown-lint` job fails on the digest PR; audit "Automated FAILED self-report" issue on handler failure

failure_modes:
  - mode:          # bare-URL regression in the committed digest
    detection:     # `markdown-lint` required check on the digest PR (proven: #9586, #9647) + new negative pin in cron-community-publication.test.ts
    alert_route:   # failed required check blocks the digest PR; no merge possible
  - mode:          # digest PR merges but dedup gate still unsatisfied (downstream chain, #6739)
    detection:     # duplicate same-day digest issues/PRs visible via the scheduled-community-monitor issue label
    alert_route:   # Sentry cron monitor + issue-label inspection (tracked by #6739, out of scope here)

logs:
  where:           # Inngest run logs for cron-community-monitor; GitHub Actions markdown-lint job log
  retention:       # Inngest/GitHub defaults

discoverability_test:
  command:         grep -Fn 'Review inbound items: [issues](' apps/web-platform/server/inngest/functions/_cron-community-publication.ts
  expected_output: "issues]("
```

## Guard Contract

One assertion-shaped check is added — the negative bare-URL pin on rendered output. It is a
vitest assertion, not a standalone gate; the contract is declared because the deliverable
includes an assertion-based CI check.

### Guard 1 — no bare URL in rendered publication surfaces

**Property.** `renderCommunityPublication` never emits a bare `http(s)` URL into `digestMarkdown`
(the linted surface) or `issueBody` (the parity surface) — every URL sits inside a link
destination `(…)`, an autolink `<…>`, a code span, or link text `[…]`.

**Assembly.** The sole chokepoint is `renderCommunityPublication`'s two template arrays in
`_cron-community-publication.ts` (`digestMarkdown` at ~line 564, `issueBody` at ~line 596) — the
handler is the only writer of the committed digest (ADR-273: the agent has no write capability).
The pin covers both returned strings; issue bodies are not linted but are pinned for parity.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert line ~588 to `Review inbound items: ${issuesUrl} and ${pullsUrl}` (the shipped defect) | RED via negative pin |
| 2 | Compliant first URL + bare second: `Review inbound items: [issues](${issuesUrl}) and ${pullsUrl}` — a second member after a compliant first | RED via negative pin |
| 3 | Delete both URL-bearing lines from the renderer (guard's own dispatch: emit nothing) | RED via positive `toContain` link-form pin — a vacuous "no URLs, no violation" cannot satisfy the pair |
| 4 | Harness edit: weaken the negative regex to a never-matching pattern (e.g. `not.toMatch(/zzz/)`) | suite stays green = vacuous; caught by review, and rows 1-3 prove the pin discriminates today |
| 5 | Harness edit: pin the wrong label in the positive expectation (`[tickets](…)`) | RED — proves the positive pin checks the exact compliant form, not just URL presence |
| 6 | Must-PASS non-canonical input: `issueBody` under the same negative pin (a surface the linter never sees) | PASS while compliant — parity coverage is not a copy of the linted assertion |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "render the URLs in an MD034-accepted form in the committed digest markdown (markdown link syntax or angle-bracket autolinks — pick whichever the repo's lint corpus and digest style best support)" | Phase 1 edit at line ~588 | mapped |
| 2 | "keep issueBody consistent (issue bodies are not linted, but parity avoids drift — check `withDigestNotice` and any test that pins exact body text)" | Phase 1 edits at lines ~606-607; Phase 2 items 2-3 (the two exact-body pins found: publication.test.ts:996, heartbeat.test.ts:151); `withDigestNotice` prefix contract verified unchanged | mapped |
| 3 | "Extend the publication tests (…/cron-community-monitor-publication-flow.test.ts and siblings) to pin the compliant form AND add a negative assertion that rendered digestMarkdown contains no bare URL" | Phase 2 items 1 and 4 | mapped |
| 4 | "If a markdownlint fixture/golden exists for digests, update it" | — | descoped — justification: verified none exists; the flow test compares the real committed file to the real renderer's output |
| 5 | "keep the diff tight so rebases stay trivial" (coordination note re sibling PR #9652) | Three-line source edit disjoint from #9652's hunks; flow-test assertion placed away from its ~294/~642 hunks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `_cron-community-publication.ts` line ~588 | "render the URLs in an MD034-accepted form in the committed digest markdown" | asked |
| Edit `_cron-community-publication.ts` lines ~606-607 | "keep issueBody consistent" | asked |
| Update `cron-community-publication.test.ts` (two sites) | "pin the compliant form AND add a negative assertion"; "check … any test that pins exact body text" | asked |
| Update `cron-community-monitor-heartbeat.test.ts:151` | "check `withDigestNotice` and any test that pins exact body text" | inferred — justification: this pin asserts the same exact body text and goes red under the fix; updating it is required for a green suite, not added scope |
| One assertion in `cron-community-monitor-publication-flow.test.ts` | "Extend the publication tests (…/cron-community-monitor-publication-flow.test.ts and siblings)" | asked |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 4 | Estimated changed lines: ~20
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — In `_cron-community-publication.ts`, `digestMarkdown` renders
  `Review inbound items: [issues](https://github.com/<repo>/issues) and [pull requests](https://github.com/<repo>/pulls)`
  and `issueBody` renders `Digest file: [<runDate>-digest.md](https://github.com/<repo>/blob/main/knowledge-base/support/community/<runDate>-digest.md)`
  and `Inbound items: [issues](…) and [pull requests](…)` — no bare URL in either string.
- [ ] AC2 — A negative assertion pins the property: rendered `digestMarkdown` does not match the
  TS regex `/(?<![(<` + "`" + `])https?:\/\//` — a negative lookbehind over the four legal URL
  contexts `(` (link destination), `<` (autolink), backtick (code span), `[` (link text). The
  same pin covers `issueBody` for parity.
- [ ] AC3 — The two exact-body pins updated to the link form: `cron-community-publication.test.ts`
  ~line 996 and `cron-community-monitor-heartbeat.test.ts` line 151.
- [ ] AC4 — One end-to-end negative assertion on the COMMITTED digest bytes in
  `cron-community-monitor-publication-flow.test.ts`, placed away from sibling PR #9652's hunks
  (~lines 294 and 642).
- [ ] AC5 — `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-publication.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-community-monitor-publication-flow.test.ts` green;
  `./node_modules/.bin/tsc --noEmit` clean. (NOT `bun test` — `apps/web-platform/bunfig.toml` sets
  `pathIgnorePatterns = ["**"]`.)
- [ ] AC6 — A rendered digest file linted by the pinned binary reports 0 errors:
  `./node_modules/.bin/markdownlint --config .markdownlint.json <rendered-digest.md>` exits 0
  (render produced via the test workspace write or a reconstructed copy of the template output).
- [ ] AC7 — `withDigestNotice` invariant preserved: `issueBody` still contains exactly one line
  starting with `Digest file: ` (existing test at publication.test.ts:1008 stays green without
  modification).
- [ ] AC8 — Code diff scope: `git diff --name-only origin/main...HEAD -- apps/` touches exactly
  4 files — the renderer and the three test files — and `git diff origin/main...HEAD --
  apps/web-platform/server/inngest/functions/_cron-community-publication.ts` shows no hunks
  near `effectivePlatform`/`keepMetrics` (sibling PR #9652's surface). Planning artifacts under
  `knowledge-base/project/plans/` and `knowledge-base/project/specs/` are pipeline outputs and
  are excluded from the 4-file count by the `apps/` pathspec.

## Test Scenarios

- Given `renderCommunityPublication` with a valid draft, when the digest renders, then
  `digestMarkdown` contains `[issues](https://github.com/jikig-ai/soleur/issues)` and
  `[pull requests](https://github.com/jikig-ai/soleur/pulls)` and no bare `https://` match
  outside `(`, `<`, backtick, `[` contexts.
- Given the `withDigestNotice` swap, when the notice replaces the `Digest file:` line, then every
  other byte survives — including the new link-form `Inbound items:` line (heartbeat + notice
  tests pin this).
- Given a reverted bare-URL line, when the negative assertion runs, then the suite goes RED
  (mutation matrix row 1, verified manually during work by temporary revert).

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-community-publication.ts` — three template
  lines (~588, ~606, ~607); URL consts and `DIGEST_FILE_LINE_PREFIX` unchanged.
- `apps/web-platform/test/server/inngest/cron-community-publication.test.ts` — strengthen the
  click-through test (~788-797) to the exact link form + add the negative bare-URL pin; update
  the `Inbound items:` assertion (~996).
- `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts` — update
  `expectNoticeBody` line 151 to the link form.
- `apps/web-platform/test/server/inngest/cron-community-monitor-publication-flow.test.ts` — one
  added negative-URL assertion on committed digest bytes, adjacent to the existing
  `expect(atCommit).toBe(expectedRender().digestMarkdown)` (~line 440), away from #9652's hunks.

## Files to Create

None.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a three-line template-string fix inside an existing
engineering surface plus test pins. No UI surface (mechanical UI-surface override did not fire:
no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit).

## Non-Goals

- The stargazers read-token permission regression — sibling PR #9652 is the fix in flight
  (disjoint hunks in the same file; coordination verified).
- The same-day dedup / liveness asymmetry — tracked by open issue #6739.
- Collector retry hardening — explicitly out of scope per the brief.
- Linting `issueBody` — issue bodies are not committed files; parity link form is applied for
  drift-avoidance only, per the brief.
- `.markdownlintignore` / `.markdownlint.json` changes — the fix is content-side, not config-side;
  excluding the digest directory would silence the gate the corpus wants.

## Sharp Edges

- The `Digest file:` line MUST keep its `Digest file: ` prefix before the link — `withDigestNotice`
  replaces it by `startsWith(DIGEST_FILE_LINE_PREFIX)`; moving the label inside the link text
  (e.g. `[Digest file: x.md](u)`) silently breaks the notice swap. Use
  `Digest file: [name](url)`, never `[Digest file: name](url)`.
- `issueBody` must never start with `AUDIT_SELF_REPORT_BODY_PREFIX` (dedup predicate) — the edit
  does not touch the first line; keep it that way.
- The negative-pin regex is a proxy for MD034, not the rule itself: the real gate is
  `scripts/markdown-lint.sh` over the committed file in CI. The lookbehind set must include
  `[` (URL-as-link-text `[u](u)` is legal) and backtick (code spans) or the pin false-positives.
- Sibling PR #9652 touches `cron-community-monitor-publication-flow.test.ts` at ~294 and ~642 —
  put the new flow-test assertion near ~440 and nowhere else in that file.
- Empty `## User-Brand Impact` / missing threshold fails deepen-plan Phase 4.6; the section above
  is filled including the sensitive-path scope-out bullet (path matches `apps/web-platform/server/`).
- `spec.md` does not exist for this branch, so `lane:` defaulted to `cross-domain` (TR2
  fail-closed) — recorded here per the Save Tasks convention.

## Context

- Root cause chain: handler-side publication (#9596) introduced fixed templates with bare URLs →
  committed digest lands in the lint corpus → required `markdown-lint` fails → digest PR cannot
  merge → `digestCommittedOnDefaultBranch` stays false → same-day dedup (#6739's surface) produces
  duplicate digest PRs (#9586 + #9647 on 2026-10-06).
- `cq-write-failing-tests-before`: the new negative pin is RED against `origin/main`'s renderer
  (bare URLs present) before the fix is applied — verify by running the updated tests pre-edit.

## References

- Defect evidence: `gh run view --job 112411068768` (markdown-lint on PR #9647) —
  `knowledge-base/support/community/2026-10-06-digest.md:31:23` and `:31:69` MD034.
- Digest PRs: #9586, #9647. Sibling fix: #9652. Dedup-asymmetry tracker: #6739.
- Renderer contract: ADR-273 (`knowledge-base/engineering/architecture/decisions/ADR-273-schema-constrained-handler-side-publication.md`).
- Learning: `knowledge-base/project/learnings/2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`.

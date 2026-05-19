---
title: Stage 6 cc-soleur-go visual-QA rubric (one-time)
date: 2026-05-15
issue: 2939
pr: 3779
retire_after: pr-c-merge
lane: cross-domain
---

# Stage 6 cc-soleur-go — visual-QA rubric (one-time, pre-merge)

One-time manual rubric supporting spec FR5.1-FR5.6. Captured by the operator
just before marking PR #3779 ready for review. Retires when PR-C merges —
future visual regressions get their own scoped capture lists.

The redaction helper at `apps/web-platform/e2e/helpers/screenshot-redact.ts`
applies opaque-black rectangles over avatar + email regions on each PNG
BEFORE the operator pastes them into the PR description (FR5.6 / CLO ask).
Raw screenshots leaking the canonical mock-Supabase test identity (see
`apps/web-platform/e2e/mock-supabase.ts:MOCK_USER` for the values to
redact) MUST NOT be committed; per Phase 6 guard grep, those literals are
checked against this rubric doc.

## Capture environment

- Worktree-rooted screenshot directory: `$(pwd)/tmp/screenshots/` (absolute
  path; see 2026-02-17 learning + spec TR5 — relative paths land in the
  bare repo root).
- Playwright headed run or any manual browser session against the dev
  server is acceptable — the rubric is operator-driven, not CI.
- Theme toggle: switch via the dashboard theme control. The 8 FR5.5
  screenshots cover 4 bubble shapes × 2 themes (light + dark).

## FR5.1 — Avatar render correctness

Verify each leader's bubble renders the canonical avatar (no yellow-square
fallback). The yellow-square is the catch-all when `LEADER_COLORS` /
`LeaderAvatar` cannot resolve the leader id; if it shows, the avatar
pipeline regressed.

| Leader id   | Status (pass = canonical avatar; fail = yellow-square) | Screenshot |
|-------------|---------------------------------------------------------|------------|
| `cc_router` | [ ]                                                     |            |
| `cmo`       | [ ]                                                     |            |
| `cto`       | [ ]                                                     |            |
| `cfo`       | [ ]                                                     |            |
| `cpo`       | [ ]                                                     |            |
| `cro`       | [ ]                                                     |            |
| `coo`       | [ ]                                                     |            |
| `clo`       | [ ]                                                     |            |
| `cco`       | [ ]                                                     |            |

The leader enum is the source of truth: `server/domain-leaders.ts`
(re-verify at QA time — adds/removals do not auto-update this rubric).
`system` is intentionally excluded; it is not a chat-surface leader.

## FR5.2 — Markdown renders post stream_end

Single screenshot of a completed assistant bubble containing rendered
markdown — bold, an unordered list, and a code fence. Expected outcome:
all three formats render; no stuck "loading" / spinner overlay remains
after the assistant emits `stream_end`. The bubble's status transitions
from `streaming` → `done`.

- [ ] Pass / Fail
- Screenshot:

## FR5.3 — Document / PDF context-aware reply

Capture flow:

1. Open a fresh conversation.
2. Upload a small PDF (an existing fixture under
   `apps/web-platform/test/fixtures/` is fine — verify at QA time; if no
   fixture exists, a one-off synthesized PDF is acceptable so long as the
   filename does NOT contain a test-user identifier).
3. Ask: *"what is this document about?"*
4. Capture the assistant reply.

Expected: the reply references the document's title or specific content,
not a generic acknowledgment ("I see a document"). If the reply ignores
the document entirely, FR5.3 fails — file a scope-out.

- [ ] Pass / Fail
- Screenshot:

## FR5.4 — AC11 Continue-Thread tab reload

Capture flow:

1. Open a cc-router OR KB-Concierge conversation.
2. Send a user message; wait for the assistant to emit `stream_end`.
3. Reload the tab (`Cmd-R` / `Ctrl-R`).
4. Capture the chat surface after rehydration.

Expected: both the user message bubble AND the assistant response bubble
re-render. A missing assistant response on reload is the AC11 regression
class — file a scope-out.

- [ ] Pass / Fail
- Screenshot (post-reload):

## FR5.5 — Light + dark theme spot-check

Eight screenshots — 4 bubble shapes × 2 themes — embedded as
GitHub user-attachments inside the PR-C description (NOT committed to the
repo per spec NG1 "no `toHaveScreenshot` baselines"):

| Bubble shape                         | Light | Dark |
|--------------------------------------|-------|------|
| user message                         | [ ]   | [ ]  |
| assistant message (cc_router)        | [ ]   | [ ]  |
| tool-use chip                        | [ ]   | [ ]  |
| interactive-prompt-card              | [ ]   | [ ]  |

Theme toggle path: dashboard settings (verify exact selector at QA time).
After capture, run the redaction helper on each PNG to overlay avatar +
email regions before pasting into the PR description.

## FR5.6 — Redaction workflow (CLO ask)

Per the CLO domain assessment carried forward from spec §139-147:

1. Capture raw screenshot to `$(pwd)/tmp/screenshots/<name>.png` (absolute,
   worktree-rooted).
2. Identify avatar + email coordinates in browser devtools — copy the
   bounding-box `(x, y, width, height)` of each region to be redacted.
3. Run the helper:

   ```typescript
   import { redactScreenshot } from "@/e2e/helpers/screenshot-redact";

   await redactScreenshot(
     "tmp/screenshots/raw.png",
     "tmp/screenshots/redacted.png",
     [
       { x: 16, y: 240, width: 32, height: 32, label: "avatar" },
       { x: 56, y: 260, width: 200, height: 20, label: "email" },
     ],
   );
   ```

   Or invoke from a one-line script — the helper is a function so a 2-line
   operator wrapper is the cheapest interface.
4. Visually verify the output (`xdg-open <redacted>` on Linux,
   `open <redacted>` on macOS). The avatar + email regions must be
   opaque black; surrounding content must be intact.
5. Only AFTER redaction: drag the PNG into the PR-C description textbox
   on GitHub. The image uploads as a GitHub user-attachment — it is NOT
   committed to the repo.

Phase 6 guard greps the mock-user literals (per
`apps/web-platform/e2e/mock-supabase.ts:MOCK_USER`) against this rubric
file's directory; the guard must return 0 hits.

## Retirement

This rubric is one-time pre-merge for PR-C / issue #2939. When PR-C
merges, the rubric is considered retired. A future visual regression
should be filed as a fresh issue with its own scoped capture list rather
than reactivating this document.

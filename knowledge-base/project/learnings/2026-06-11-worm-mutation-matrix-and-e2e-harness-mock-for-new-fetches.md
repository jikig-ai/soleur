# Learning: WORM mutation matrix as a plan artifact + e2e harness mocks for new page fetches

## Problem

The operator-inbox-delegation feature (#5103, PR #5125) shipped a WORM-protected
table written by a multi-step pipeline (stub insert → finalize UPDATE), a new
dashboard fetch, and a 3rd webhook ingress. Three distinct failure classes
surfaced across the pipeline phases:

1. **Plan-level design contradiction (2 P0s):** the reviewed plan prescribed a
   single WORM freeze-list (`message_id, sender, subject, summary, mail_class,
   statutory_class, rule_id, received_at`) AND a stub→finalize pipeline that
   UPDATEs four of those frozen columns. As written, the trigger would have
   P0001'd the pipeline's own finalize on 100% of emails. Separately,
   `ON DELETE CASCADE` + WORM either aborts the owner's Art. 17 deletion (if a
   no-delete trigger exists) or silently destroys statutory evidence.
2. **Miscited precedents survived plan review:** the plan cited
   `cron-compound-promote.ts` as the Anthropic SDK client precedent (it uses
   raw `fetch`) and `soleur-go-runner.ts`'s `sanitizePromptString` as the
   sanitizer import (file-private + `.slice(0, 256)` — would truncate email
   bodies). Three plan-review agents (DHH/simplicity/spec-flow) missed both.
3. **e2e harness gap shipped green through unit tests:** the new
   `dashboard/page.tsx` fetch to `/api/inbox/emails` was the only authed API
   route in the nav-states e2e suite that actually reached the real dev server
   (every sibling fetch is `page.route`-mocked). The server-side Supabase
   client points at a fake URL in the e2e env, so the request hung, wedged the
   throttled dev server, and failed the structural-UI gate — reproducibly on
   the test rendering the modified surface, masked as goto-timeouts elsewhere.

## Solution

1. The deepen-plan pass (data-integrity-guardian reading mig 075's two trigger
   shapes) converted the freeze-list into an explicit **per-column mutation
   matrix**: hard-frozen | one-time-set (NULL→value once, mig 075 `accepted_at`
   shape) | transition-constrained (RPC-only) | anonymise-only (GUC bypass) |
   delete-gated. The matrix became a plan section that Phase 1 implemented and
   tested class-by-class. Stubs insert SQL NULL — never `''` (an empty-string
   stub makes the one-time-set gate reject the finalize).
2. The deepen pass re-read every cited precedent file at the cited line: both
   miscitations were caught before implementation (the test-design reviewer
   independently flagged that copying the raw-fetch precedent would force a
   global fetch mock colliding with the body-fetch mock).
3. Mocked `/api/inbox/emails` in `setupNavMocks` like every sibling dashboard
   fetch. Diagnosis discriminator: the failing test was the ONLY one failing in
   all runs (others were the documented #5009 shifting-set crash flake), and in
   isolation it progressed from goto-timeout to a real assertion failure.

## Key Insight

- **A WORM freeze-list is not a design until every writer is mapped to a
  mutation class.** Any plan that pairs a column-freeze trigger with a
  multi-step writer (stub→finalize, claim→adopt, draft→publish) must carry a
  per-column matrix (column → {hard-frozen | one-time-set | RPC-gated |
  bypass-gated}) naming each writer and its mechanism. The single-list shape is
  the contradiction class; the matrix makes every P0 fall out mechanically.
- **Plan-cited precedents are hypotheses until re-read at the cited line.**
  Client-construction shapes and helper-import paths are the highest-drift
  citation class because they look authoritative and nothing type-checks them
  until implementation.
- **A new client-side fetch on an e2e-covered page requires a harness mock in
  the same PR.** Offline-mock e2e suites route-mock every API the page calls;
  the unmocked newcomer reaches the real dev server with fake backing-service
  env and hangs — failing tests far from the diff (goto timeouts) before
  failing the obvious one. Grep the e2e helpers for the page's existing mocks
  when adding any `fetch` to a covered surface.

## Session Errors

1. **git-history-analyzer hit an external session limit mid-review** —
   Recovery: proceeded with 11/12 agents per the rate-limit fallback gate;
   its provenance lens partially covered by code-quality's legal-drift check.
   **Prevention:** none needed (external limit; fallback gate worked as
   designed).
2. **Edit-before-Read tool rejections (3x)** — Recovery: Read then Edit (once
   via sed). **Prevention:** mechanical — the tool itself enforces; no rule
   change.
3. **Ambiguous CWD on first test-all.sh background launch** — Recovery:
   killed, relaunched from confirmed worktree CWD. **Prevention:** existing
   work-skill rule (chain `cd <worktree-abs-path> && <cmd>` in one call)
   covers this; followed on retry.
4. **live-repo-badge.test.tsx failed under parallel load, passed standalone**
   — Recovery: classified as the known #5113 parallel-load flake (not in
   diff; main CI green). **Prevention:** existing learning covers the class.
5. **New dashboard fetch unmocked in nav-states e2e harness** — Recovery:
   added the `page.route` mock; gate's diff-surface test went green.
   **Prevention:** qa-skill Sharp Edge added this session (see Route to
   Definition): when a diff adds a client-side fetch to a page covered by the
   offline-mock e2e suite, the harness mock lands in the same PR.
6. **Literal hex introduced in new email-template branch** — Recovery:
   anti-slop scanner (BRAND-RAW-HEX, blocking) caught it; tokenized into
   `BRAND_EMAIL_COLORS`. **Prevention:** already-enforced (scanner is the
   gate; in-file precedent was itself the source — fixed both).
7. **Plan miscited two precedents (SDK client + sanitizer import)** —
   Recovery: deepen-plan verification pass re-read the cited files and
   corrected before implementation. **Prevention:** already-enforced
   (deepen-plan's read-the-cited-line bullet is what caught it).
8. **Inline scanner fix left uncommitted while 12 review agents ran** —
   Recovery: 3 agents flagged working-tree drift; committed mid-review and
   synthesized against HEAD. **Prevention:** review-skill Sharp Edge added
   this session: commit pre-review inline fixes (scanner/lint corrections)
   BEFORE spawning file-reading review agents.

## Tags

category: best-practices
module: email-triage, supabase-migrations, e2e-harness, deepen-plan
related: #5103, PR #5125, migration 102, ADR-055

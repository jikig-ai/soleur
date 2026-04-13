# Learning: Billing code-review fixes — race condition, accessibility, duplication

## Problem

PR #2036 code review surfaced four issues in the billing/settings area:

1. **#2046 — Checkout race window**: The checkout route reads `subscription_status` then creates a Stripe session — not atomic. Two rapid requests can both read `null` and create duplicate sessions.
2. **#2047 — Modal accessibility**: `CancelRetentionModal` used `role="presentation"` on the backdrop but lacked `role="dialog"`, `aria-modal`, focus trapping, Escape key handling, and focus restoration.
3. **#2048 — Duplicated fetch-redirect**: `handlePortalRedirect` and `handleSubscribe` in `billing-section.tsx` were near-identical, differing only in URL and error message.
4. **#2065 — Unapplied migration**: Migration 020 (subscription billing columns) needed production verification.

## Solution

1. **Race condition**: Added migration 021 with a partial unique index: `CREATE UNIQUE INDEX idx_users_stripe_subscription_id_unique ON public.users (stripe_subscription_id) WHERE stripe_subscription_id IS NOT NULL`. This makes the webhook handler's write fail-safe at the DB level.
2. **Accessibility**: Added `role="dialog"`, `aria-modal="true"`, `aria-labelledby="retention-heading"` to the dialog container. Added `useEffect` with focus trapping (Tab cycle), Escape key handler via `onCloseRef` pattern, and focus restoration to trigger element on close.
3. **Duplication**: Extracted `redirectTo(endpoint, fallbackError)` helper. `handlePortalRedirect` and `handleSubscribe` now delegate to it.
4. **Migration**: Verified via Supabase REST API — columns exist, 200 response. Closed #2065.

All three code fixes shipped in one PR to minimize review overhead.

## Key Insight

Partial unique indexes (`WHERE col IS NOT NULL`) are ideal for optional foreign keys like `stripe_subscription_id` — they prevent duplicates on populated rows without blocking the default NULL state. This is the right level for race condition defense: DB constraints survive concurrent requests that application-level checks cannot.

Modal accessibility requires five things working together: `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, focus trapping, and Escape-to-close with focus restoration. Missing any one breaks the experience for screen reader and keyboard users.

## Prevention

- **Race conditions on payment endpoints**: Ask "does this endpoint handle concurrent requests safely?" during review. Enforce partial unique indexes or idempotency keys for payment-related writes.
- **Modal accessibility**: Consider a shared `<Modal>` base component with accessibility built in, or add `eslint-plugin-jsx-a11y` rules requiring `role="dialog"` and `aria-modal` on modal patterns.
- **Code duplication**: When review spots two instances of the same pattern, extraction should be mandatory before merge.
- **Unapplied migrations**: The existing workflow gate (verify via REST API post-merge) caught this. Continue enforcing.

## Session Errors

1. **Stale local main in worktree creation** — The `worktree-manager.sh create` reported "Could not fast-forward local main — using origin/main" but the worktree was created at the old local main commit (`613169a5`), missing all PR #2036 files. Required manual `git rebase origin/main`. **Prevention:** The worktree manager's origin/main fallback may not be working as intended — investigate whether the script actually checks out from origin/main when local fast-forward fails.

## Cross-References

- `knowledge-base/project/learnings/2026-03-20-websocket-first-message-auth-toctou-race.md` — analogous TOCTOU race pattern
- `knowledge-base/project/learnings/2026-03-21-kb-migration-verification-pitfalls.md` — migration verification approach
- `knowledge-base/project/learnings/2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md` — `validateOrigin` pattern used in billing routes

## Tags

category: code-review
module: apps/web-platform/billing
issues: #2046, #2047, #2048, #2065
pr: #2036

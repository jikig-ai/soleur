# Tasks: fix(community) cmd_fetch_metrics bypasses x_request() hardening

Status: **Already Fixed** -- no implementation work required.

## Phase 1: Verification (Complete)

- [x] 1.1 Read current `cmd_fetch_metrics` implementation
- [x] 1.2 Verify it uses `get_request()` (confirmed: lines 354-365)
- [x] 1.3 Verify `get_request()` delegates to `handle_response()` (confirmed: lines 331-332)
- [x] 1.4 Verify `handle_response()` includes 429 retry, JSON validation, retry_after clamping (confirmed: lines 169-234)
- [x] 1.5 Trace git history to identify fixing commit (`dcd8f7e`, PR #500)

## Phase 2: Closure

- [ ] 2.1 Close Issue #478 with comment explaining it was fixed by PR #500
- [ ] 2.2 Remove `bot-fix/attempted` label (the bot was correct -- the fix is in place)

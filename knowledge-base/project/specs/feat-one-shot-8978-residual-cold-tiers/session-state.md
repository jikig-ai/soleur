# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8978-residual-cold-tiers/knowledge-base/project/plans/2026-09-27-perf-dashboard-residual-cold-tiers-plan.md
- Status: complete (plan + deepen-plan; commits a9c0ae7bfa, aea47f9abb; pushed)

### Errors
None. (Deepen agents ran sequential-fallback — no Task fan-out in this runtime; halt gates and verifications applied inline.)

### Decisions
- Bound every Supabase-facing leg with `.abortSignal(AbortSignal.timeout())` mapped onto existing verdict arms (grace / `db_unavailable` / identity-degrade) — no new semantics; plus in-flight dedup Map for revocation misses.
- Post-middleware 23–38 s tier is measurement-gated: Sentry `http.client` span pull (conditional in-surface probe) must name the tier before choosing mechanism; warm-up is conditional on H1/H2 evidence.
- #8985 deferred-with-data (fetch-count-dominance criterion unmet); #8978 stays `issue:` not `closes:` since the ≲500 ms FCP AC may remain unmet.
- #8993 fix mirrors the enumerate-watchdog precedent on the non-enumerate path (identity-pinned kill, children-first); #8940 uses `tee` + `${PIPESTATUS[0]}` + durable tails under `$XDG_STATE_HOME`.
- #8926 sweep limited to pure `user.id` sites; 5 rich-field sites keep `getUser()` or use `sessionJwtEmailForVerifiedUser` with documented exceptions + CI census ratchet.

### Components Invoked
- plugins/soleur/skills/plan/SKILL.md (phases 0-7)
- plugins/soleur/skills/deepen-plan/SKILL.md (halt gates 4.5-4.11)
- scripts/lint-guard-contract.py, markdownlint-cli2, gh CLI, live curl probes

## Work Phase (2026-09-27)

### Phase 0 — DONE
- Probe re-run: PASS (5 cold + 1 warm, chromium workaround). Cold TTFB 2.5–43.4 s; measurement table posted to #8978 (comment-5855962627) + PR #9034.
- Sentry spans named the tier: `check_my_revocation` 26.4–28.5 s, `resolveIdentity` `users`/`workspace_members` 20.7–37.5 s, `auth/v1/user` 3–6 s, `user_session_state` 12.5 s — all remote Supabase stalls, no queueing. Conditional in-surface probe skipped (0.3) — spans already discriminated.
- `AbortSignal.timeout` available (smoke: `function true`).

### Phase 1 — DONE (all arms fired)
- Bounds: `SOLEUR_MW_RPC_TIMEOUT_MS` (8 s) on revocation RPC + T&C select via postgrest `abortSignal` → existing grace/`db_unavailable` arms; `op=revocation_gate.rpc_timeout` via `isAbortShapedError`.
- `SOLEUR_MW_AUTH_TIMEOUT_MS` (10 s Promise.race) on `getUser()` — arm fired (recurring 2.6–4.9 s stalls); timeout → `!user`→/login; throws still propagate; `op=mw_auth.timeout`.
- `SOLEUR_IDENTITY_SELECT_TIMEOUT_MS` (8 s) on `resolveIdentity` users/workspace_members → existing degrade arm.
- Revocation in-flight dedup `Map<key, Promise>` (children share work, not verdicts; deleted on settle).
- `server/supabase-edge-warmer.ts`: ~18 s bounded `GET /rest/v1/` anon-key tick, unref'd, failure-tolerant, ~6 min heartbeat. Wired in `server/index.ts` after boot checks.
- ADR-253 second amendment committed.
- Tests: `test/middleware.bounded-legs.test.ts` (8: timeout→grace/db_unavailable/login, dedup 6→1 RPC, census row-4) + `test/server/supabase-edge-warmer.test.ts` (6: never-throw, bounded, armed/disarmed, heartbeat) — all green; mock surfaces updated (rpc `abortSignal` wrapper, `eq` abortSignal pass-through, `mockQueryChain.abortSignal`).

### Phase 3 — DONE (subagent dc5f5bd4)
- 71 → 6 `auth.getUser` route files. ~65 migrated to `verifiedUserId(req)`.
- Keepers: `repo/setup`, `workspace/{accept-invite,invite-member}` (user_metadata); `checkout`, `workspace/{decline-invite,pending-invites}` (email claim fast path, getUser fallback).
- `test/server/route-getuser-census.test.ts` ratchets the 6-entry allowlist. `request-auth.ts` fails closed on `{data:null}`. tsc clean; 68 route test files green.

### Phase 4 — DONE
- `test-all.sh` run-path parent-death watchdog (pre-`tc_acquire` arm; zombie stat + lstart pid-reuse guards; children TERM'd before runner; `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` announced opt-out; EXIT-trap disarm).
- #8940: `run_suite` tees into scratch root; non-ok classes copy to `SOLEUR_TEST_ALL_LOG_DIR`-overridable durable dir + `log=<path>` on summary lines; EXIT-trap retains in-flight logs before scratch cleanup.
- `scripts/test-all-orphan-log-retention.test.sh`: 22 assertions, all green. Sibling suites re-verified: killed-classification 77, runtime-ceiling 23, test-contention 163.
- Registered in the runner's explicit registration block.

### Gate note
- Commit gate degraded to MODE=full (runner-changed) → sibling-full-run refusal fired (3 sibling gates in flight); retried with `SOLEUR_ALLOW_FULL_GATE=1` per the banner's sanctioned override; gate queued ~26 min inside `tc_acquire` at write time. Watchdog observed armed+polling on the real run (production-shaped confirmation of the #8993 arm site).

### Gate round-1 postmortem (all 6 reds root-caused + fixed)

1. `scripts/test-all-affected` (every arm ran=0, missing rec-* files): the exported
   `SOLEUR_SCRATCH_SESSION_ROOT` is inherited by nested runner sandboxes; my
   `_suite_log_dir` keyed on presence → sandboxes took the NEW tee branch →
   the splice-replaced `  "$@" || rc=$?` RAN-record else-branch never ran.
   Fix: owner-gate — `_suite_log_dir` only when `SOLEUR_SCRATCH_OWNER_PID == $$`
   (a nested run keeps the parent's root by design and must not tee into it).
2. `scripts/test-all-killed-classification` AC9 byte-shape: same leak — sandbox
   emitted `log=` on the [FAIL] line. Owner-gate restores the anchor path.
3. `lint-orphan-test-suites` + mutations-a/b: new suite was UNCLASSIFIED →
   registered `scripts/test-all-orphan-log-retention` as a runner-SUT
   always-on suite in `test-affected-paths.sh`.
4. `apps/web-platform [unit]` kb-security census: `hasInlineAuth` only
   matched `supabase.auth.getUser` → accept `verifiedUserId(` (stronger check).
5. Hermeticity: my test's sandbox invocations now `env -u` the three
   SOLEUR_SCRATCH_* vars so they self-allocate under an outer gate.

Re-verified under simulated inherited-root env: affected 43/43,
killed-classification 77/77, orphan-log-retention 22/22, lint-orphan
68+44+32, kb-security 10/10.

### Review round (PR #9034) — ALL P2s RESOLVED, commit `d9e93bb2e6` pushed

Panel: design-validity + security + data-integrity + performance + arch +
code-quality + patterns + git-history + semgrep (in-line, 0 findings).
Notable results: history HIGH narrative fidelity; security no P1/P2
(header model airtight); all red fixed inline.

Fixes landed in `d9e93bb2e6` (18 files):
- `boundedAuthGetUser` shared helper — verifiedUserId fallback,
  resolveIdentity fallback, email fallbacks (checkout/decline-invite/
  pending-invites → census keepers 8→5); timeout breadcrumb; reject→null.
- middleware getSession() raced (hidden remote refresh on expired token)
  → session_get.timeout/threw ops; sessionJwtEmailForVerifiedUser bounded
  internally (session-jwt-email.session_timeout).
- Helper sweep: kb-route-helpers → verifiedUserId (holds Request);
  dsar-reauth/team-membership/workspace-identity/members-tab → bounded.
- Watchdog: children TERM→grace→KILL before runner-TERM (EXIT-trap disarm
  can't abort escalation); runner-death arm (polls runner, reaps
  snapshotted children, exits — closes gone-but-held-pipe deadlock);
  _wd_descendants transitive reap (grandchildren held lock fd); suite-log
  probe-create (SIGPIPE phantom-KILLED); durable-copy WARNING; LOG_DIR
  scratch validation; in-flight clear after copy; --help docs.
- decline-invite: both-emails-non-null guard (null===null authz hole).
- Bounded fail-open: MW_GRACE_STRIKE_LIMIT=20 per-sub LRU — sustained
  outage escalates to /login?error=revocation_unavailable (session
  preserved); op revocation_gate.grace_window_exceeded; ok resets.
- Dedup joiner own bound + op revocation_gate.dedup_joiner_timeout.
- Warmer consumes body; heartbeat guarded. RPC bound 8s→10s (T&C headroom).
- Env bounds Math.max(…,1). Census regex widened + honest scope comment.
- verifiedUserId docblock: deliberate single-control residual recorded.

Test deltas: bounded-legs +3 (joiner op, session timeout, strike
escalation — now 11); identity +2 (16); orphan-test SLEEPTOK scoping.
Verified: tsc clean; ~360 targeted assertions green incl. orphan 22/22,
killed-classification 77/77 (inherited-root), middleware family 74/74.

Deferred items (filed/recorded):
- RPC NULL invitee_email hole (check_my_revocation fn) — noted, sibling
  surface, needs SQL diff (deferred, tracked in decline-invite comment).
- Leader-side shared-promise residual — leader bound = postgrest abort;
  abort-ignoring leader keeps its request pending (documented, worst-
  case shape; joiners bounded).
- Durable-log GC — documented residual (var/tmp hygiene).
- ADR advisory (watchdog/FD contract) — comments + test file carry the
  contract; full ADR deferred to a docs pass.

Remaining: post-deploy live probe re-run (Phase 2 acceptance evidence),
PR ready/merge, post-merge verify. PR #9034 remains draft.

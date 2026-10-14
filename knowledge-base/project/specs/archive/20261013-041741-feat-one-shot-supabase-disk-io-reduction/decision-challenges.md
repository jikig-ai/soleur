# Decision Challenges — feat-one-shot-supabase-disk-io-reduction

Recorded during headless plan/deepen-plan (no interactive operator). `ship` renders these into the PR body
and files an `action-required` issue for the operator.

## DC-1 — Split the disk-IO PR into 3 PRs (challenges "one PR, 3 workstreams")

- **Operator's stated direction (default):** one PR containing all three workstreams (drop unused indexes,
  wrap RLS auth calls, back off heartbeats).
- **Challenge (multi-agent plan review — code-simplicity + security-sentinel + data-integrity-guardian +
  architecture-strategist):** split into 3 PRs — (1) migration 132 index drops, (2) migration 133 + TS
  heartbeat backoff, (3) migration 134 RLS initplan wrap.
- **Why:** the RLS workstream is a different optimization axis (read/CPU initplan, not WAL) that the PR's own
  AC12 write-count metric cannot measure; it carries an independent cross-tenant-exposure risk (CRITICAL-1:
  stale-source `ALTER POLICY` could drop the `is_workspace_member` WITH CHECK on `conversations`/`kb_files`,
  regressing #6334); and its benefit on the churn-priority tables is marginal because their hot writes go
  through the RLS-bypassing `SECURITY DEFINER` `touch_conversation_slot`. Bundling two disjoint
  `single-user incident` risks (false-reap + RLS drift) maximizes blast radius and defeats granular rollback.
- **Status:** SURFACED — operator decides. Plan supports either path (workstreams are already independent
  migrations). If kept together, RLS stays capped to advisor-confirmed policies (Phase 2).

## DC-2 — Cap-hit lockout window doubles (240 s) — mitigation added

- **Note (not a scope challenge, a correction):** backing off the concurrency-slot heartbeat 30 s→60 s raises
  the staleness threshold 120 s→240 s, which doubles a real post-crash self-lockout for a cap-hit user
  (spec-flow E3). Plan adds an in-scope mitigation (Phase 3e / AC14: reap slots with no live local socket,
  threshold-independent). Operator should be aware the alternative — accept the 240 s lockout — was rejected
  at the `single-user incident` threshold.

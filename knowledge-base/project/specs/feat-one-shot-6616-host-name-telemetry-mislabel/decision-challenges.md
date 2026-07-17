# Decision Challenges — feat-one-shot-6616-host-name-telemetry-mislabel

Recorded during headless one-shot planning (deepen-plan 4-agent review). `ship` renders these into
the PR body and files as an `action-required` issue for operator visibility.

## DC-1 — Cut the standing cross-label detector (scope / taste; 2-2 panel split)

**Decision (applied):** Cut the standalone `scheduled-hostname-mislabel` alarm (script + test + workflow
+ `sentry_cron_monitor`) from the plan; deliver the same identity check as a single read-only
follow-through (`hostname-mislabel-web1-6616.sh`) riding the existing Sentry-monitored sweeper.

**Why applied:**
- **code-simplicity-reviewer** + **spec-flow-analyzer**: the standalone alarm is *born-firing* — web-1
  carries the stale label now and recreate is blocked indefinitely, so it opens a perpetually-FIRE
  `action-required` issue (alarm fatigue by construction), while computing the **same** `host_name→host`
  query as the follow-through (~1300 LOC of redundancy). The bug class is structurally closed for fresh
  hosts (#6396/#6344), so a generic multi-host detector is YAGNI.

**Recorded dissent (did NOT apply their keep-it position, but logging it):**
- **architecture-strategist**: judged the scoping "proportionate" and the standing detector a way to
  "convert a silently-poisoned attribution surface into a paged one."
- **observability-coverage-reviewer**: found the alarm's mechanics sound and precedent-faithful (no P0/P1).

**Resolution rationale:** the "silent→paged" benefit is illusory for *this* bug — it is already known and
diagnosed (Phase 0), and paging on a known, expected, indefinitely-blocked condition is noise, not signal.
The paging value would only materialize for a *novel* non-web-1 collision, which is the YAGNI case.

**Reversal trigger:** if a non-web-1 `host_name` collision is ever observed in source 2457081, build the
generic standing detector then (the cut design is preserved in this plan's git history).

**Operator ask:** none required — this is an internal engineering scope call. Surfaced for awareness only.

## DC-2 — Live diagnosis refuted the plan's pinned dedicated-node identity (correctness fix, applied at /work)

**Decision (applied):** The deepened plan pinned the dedicated Inngest node's telemetry `host` as
`soleur-inngest-server-prd` (the Hetzner resource `name`, `inngest.tf:291`) and keyed the follow-through
as an allowlist ("PASS iff `soleur-inngest-prd` emitted only by that host"). The Phase-0 **live query
(creds were available in-session) refuted this**: `soleur-inngest-server-prd` never appears in telemetry;
the dedicated node's real `host` is `soleur-inngest` (confirmed by its `inngest-heartbeat` service
fingerprint, not by trusting the group-by). I re-keyed the follow-through inline to **FAIL on
authoritative web-host identities** (`soleur-web-platform`/`soleur-web-2`, `server.tf:225`) with a
positive `soleur-inngest` liveness marker gating PASS.

**Why applied (≤10-line correctness fix, not an architecture fork):** the plan's allowlist would have
**false-FAILed forever** on the dedicated node's own generic early-boot rows
(`host=Ubuntu-2404-noble-64-minimal`, kernel-only, reappears every reboot before the hostname is set),
making the follow-through unable to ever PASS. The corrected predicate is what the issue title actually
names ("a web host self-labels soleur-inngest-prd"), is strictly better-scoped, and aligns with DC-1's
YAGNI descope. Verified live: the follow-through returns FAIL, correctly naming `soleur-web-platform`.

**Operator ask:** none — an internal engineering correctness fix. Full record in `session-state.md`.

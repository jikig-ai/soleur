# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-11-fix-registry-zot-log-shipping-plan.md`
- Status: **recovered from partial-artifact** (planning subagent died on an API connection error
  mid-response after 78 tool uses / ~42 min; the plan body, the deepen-plan sections, and the
  five-reviewer panel dispositions were all already on disk).
- Plan artifact: `recovered` (selector=`branch` — frontmatter `branch:` matched, non-recursive over
  `plans/*.md`, so `plans/archive/` excluded by construction)

### Recovery evidence
The recovery predicate (`## Acceptance Criteria` present) held. Beyond the predicate, the three
corrections the subagent's final partial message said it was "applying" are all verifiably on disk,
so nothing was lost to the crash:

| Late correction | Finding | On disk |
|---|---|---|
| C4 edge exists at `model.c4:562` (the earlier grep was case-broken against `zotRegistry`) | A10 | 3 refs |
| ADR-178 also taken → moved to ADR-179 | A12 | 11 refs |
| Infra suites register via `.github/workflows/infra-validation.yml`, not `scripts/test-all.sh` | A11 | 5 refs |

**`plan-review` was NOT re-run.** The generic recovery arm says "continue from `/soleur:plan-review`",
but plan-review demonstrably already ran: `## Panel Findings That Changed the Architecture` carries 14
findings (A1–A14) each with a disposition, and the Overview records the plan "was revised substantially
after a five-reviewer panel". Re-running it would re-spend the operator's budget to re-derive findings
already incorporated (token-discipline #4: re-run a suite only when its inputs changed). Recorded here
rather than left implicit, since it is a deviation from the literal recovery text.

**Inherited-measurement caveat (token-discipline #4, resume inversion).** Every live measurement in
this plan was self-pulled by the crashed subagent ~40 min before this entry. The plan does not rely on
that: Phase 0.1 mandates re-probing the delivery window (`boot_id`, `zot_uptime_s`, `pcent`) at
implementation time rather than inheriting it, and AC 18 mandates re-deriving the ADR ordinal
immediately before merge. Both re-probes are owed by `/work`, not satisfied by this file.

### Errors
- Planning subagent terminated early: `API Error: Connection lost mid-response` (subagent tokens
  406,552; 78 tool uses; 2,524,643 ms). No Session Summary was emitted — recovered from on-disk
  artifacts per the `plan-artifact-recovery` block. Recovery ran **once**; no re-invocation of
  `soleur:plan` was needed.
- Scope check clean: `git status` showed the plan file as the only change, so the subagent did not
  breach its plan-only mandate.

### Decisions
- **Shape change from the issue's literal framing.** The issue says "follow the existing Vector
  source/allowlist pattern"; the registry host runs **no Vector agent**, so there is no allowlist entry
  to add. The deliverable is a purpose-built journald→ingest shipper (ADR-179), adopting Vector's
  *discipline* (exact-value field match, explicit quota budget, redaction before egress) but not its
  agent.
- **The binding reason against the shared Vector config is payload destruction, not credentials.**
  `vector.toml:298` deletes any top-level `message` key as an Art-9 user-content key, and zerolog's
  log text *is* a top-level `message` — a Vector-shipped zot line would arrive with its message
  deleted. The earlier pepper/isolation-guard argument is explicitly retracted as false.
- **This is a shipping problem, not an instrumentation problem.** The zot container already runs with
  `--log-driver journald` under the container name `zot`, so the lines are already on the host.
- **The verification gate asserts a POSITIVE, host-isolated envelope**, not a negation of the
  heartbeat prefix (which would be fail-open and would auto-PASS on exactly today's production state).
  The issue's suggested tokens (`routes.go`, `blobs/uploads`) are rejected as generic — all hosts
  multiplex into Logs source 2457081.
- **Ships inert-until-provisioned, and says so.** The registry host is cloud-init-only; delivery rides
  the pending step-6 `registry-host-replace` on the open zot-pin ordered path. Liveness is owned by a
  follow-through probe on a **dedicated tracker** (never the issue the PR closes, where the sweeper
  would make it a permanent silent no-op).
- Zero Terraform changes — a deliberate risk reduction that keeps the change clear of the
  untargeted-apply hazard on `hcloud_server.registry`.

### Components Invoked
- `soleur:plan` (inside the crashed planning subagent) — completed
- `soleur:deepen-plan` (same subagent) — completed; research fan-out, premise validation,
  User-Brand Impact (Phase 4.6), Encryption Posture
- `soleur:plan-review` (same subagent) — completed; five-reviewer panel, 14 findings A1–A14
- `scripts/betterstack-query.sh` via `doppler run -p soleur -c prd_terraform` — falsification table
  re-measured independently (`hr-no-dashboard-eyeball-pull-data-yourself`)

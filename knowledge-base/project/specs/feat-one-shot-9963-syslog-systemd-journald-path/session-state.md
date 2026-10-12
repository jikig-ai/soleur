# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9963-syslog-systemd-journald-path/knowledge-base/project/plans/2026-10-12-chore-pin-syslog-systemd-journald-path-plan.md
- Status: complete

### Errors
- No Task/Skill/Agent tool in the planning subagent's harness — plan + deepen-plan ran in-process; research fan-outs, plan-review panel, and CTO ruling spawns could not be dispatched from inside it. Parent pipeline owns the technical-ruling gate spawn.

### Decisions
- Root cause verified: Vector's journald `contains_match` is OR-over-record-fields, so Source 1's `PRIORITY ∈ {0..4}` arm admits `SYSLOG_IDENTIFIER=systemd` failure rows regardless of unit; they ship via `sinks.betterstack` → Logs source 2457081.
- Scope: document + positive control only; semantic re-architecture deferred to sibling open issues.
- Control design: `SOLEUR_SYSTEMD_JOURNALD_CONTROL` hourly emit as `logger -t systemd -p err` inside `inngest-server-probe.sh`; `--control-require` + field-true `--control-require-field` (JSONExtractString) on `betterstack-assert-absence.sh`; jq own-field control-count arm in rehearsal capture.
- Delivery staging: vector.toml reaches web-1 via `terraform_data.journald_persistent` replace; inngest host emits control only after next `apply_target=inngest-host-replace` dispatch.
- New ADR (provisional 286) planned; technical assumptions logged as `pending - assumed:` rows in decision-challenges.md.

### Components Invoked
- `soleur:plan` (in-process, all phases)
- `soleur:deepen-plan` (in-process, gates 4.5–4.12)
- Artifacts: tasks.md, decision-challenges.md (commits `9e9d3db425`, `87fc180393`)

## Technical-Ruling Gate
- cto_spawns=1 (batched, 5 rows — all confirmed assumed defaults; 3 caveats already captured in plan §Proposed Solution/Guard Contract)
- Gate verdict: PASS (6 rows)
- Operator decision: continue past open-PR file overlap (sibling PR editing journald-config.test.sh on disjoint egress scope; parked PR on rehearsal-capture files) — collision risk accepted, conflicts resolve via merge of origin/main

## Work Phase (complete)
- Tier B subagent fan-out (3 disjoint file-groups), lead-verified independently.
- Mutation matrix exercised: all 7 mutants verified RED.
- Focused suites green; commit c7756141b9; --affected gate queued/drained — only known operator-gated GuardA carrier identity failure (vinngest-v1.1.51 re-bake pending).

## Review Phase
- Class panel at PANEL_SHA=3c4ef84129: design pass + 6 seats (git-history, pattern-recognition, security-sentinel, code-quality, test-design, structural-enumeration replacing path-triggered performance-oracle). Structural-cause roll-up: guard windows were narrower than the properties they named.
- Fix commits: ca08ceaa41 (jq own-field count + empty-value refusal), c2fc290d9e (run-window CONTROL_ROWS, guard hardening, tokenized never-add, fixture validity, floor), f14ecab16e (comment refresh).
- Fix-round 1: 7 targeted seats spawned at HEAD bf4665b+f14ecab16e against diff 3c4ef84129..HEAD + local shellcheck conditional (info/style only).
- Fix commits (cont.): 6e9ad1aab1 (lazy CONTROL_ROWS fetch, ADR mechanism refresh, ac12 consistency), f59ebcaea4 (closed-form 9963e, argv/ census widening, semantic spelling/VRL pins, window floor).
- Fix-round 2: 6 targeted seats at HEAD f59ebcaea4 against diff 3c4ef84129..HEAD. New round-2 findings closed in the f59+ follow-up commit: r-since discrimination witness arm (dropped --since now verifiably flips the verdict), octal-safe --window math + test arms, whole-file SYSLOG_IDENTIFIER canonical-form pin (sub-table headers, multiline inline tables, asymmetric whitespace, VRL forge forms), bare include_matches container refusal, PRIORITY-arm scoping (9963l), EMIT_SEP extended to [;&|<>] (&&-continuation, <<'X' swallow, > redirect), argv end-anchor (trailing --socket), CLOSER_LINE_CLEAN rider check, whole-body net depth (spanning wraps), tail-code census, ORDER BY dt DESC (newest-rows-survive-truncation), pii_scrub_drop_userdata exact head anchor, ACTUAL_TAGS charset parity, N1 inner-parse guard, docs/count staleness sweeps.
- Tally: seats=22, fix_rounds=2 (cap reached — any further round escalates to a full class panel).

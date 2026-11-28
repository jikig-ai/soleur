# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-28-feat-bastion-host-replace-route-plan.md
- Status: complete
- run_health_dir: .soleur/runs/feat-one-shot-12879-bastion-host-replace-route-20261128T101017Z
- cto_spawns=1

### Errors

- First gh issue create blocked by a hook (variable body-file path); recovered with a literal path.
- Chained sleep waits blocked; recovered with Monitor.
- lint-encryption-posture.py does not accept a plan path; skipped.

### Decisions

- Route lives in a new reusable workflow bastion-host-replace.yml with a thin caller job; apply workflow ends at or under 488,000 bytes (CTO Q4/Q4b, first slice of #8385).
- Three sources must agree on the server id (dispatch input, Hetzner API, state), plus NIC and firewall-attachment pins; per-address allowed-action table.
- Pre-apply bastion ids are never powered off on cancel or failed apply, on both routes; replace plan JSON holding the host private key is written umask 077, masked, never printed, deleted always.
- Shared birth/replace checks move to bastion-gate-common.sh in their own commit; birth suite mutation count stays 11.
- PR uses Ref for #12879, #9421 and #12008; #12879 closes after the post-merge plan_only run passes.

### Components Invoked

- soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, review and research agents.

## Operator Constraints

- constraint: never SSH
- constraint: never read a live secret
- constraint: use Ref, never Closes, for 12008 and 9421
- constraint: no production dispatch without the owners typed go naming the exact command
- constraint: end with Needs-you and a resume prompt

## Work Phase

- Status: complete (implementation by one delegated agent, lead verified)
- Affected gate: rc=1 under contention (load 27). Own defect fixed: missing weight row for the new suite. Isolated re-runs green: tmp-purge, check-deps-adapter-drift, ci-head-verdict, lint-orphan-test-suites rows 19-40, decide-boundary, c4-render-argv-fixture, sandbox-wrapped-command-runtime, compound-promote-create-persist. redirect-tombstones and roster-entry-gate were red because the shared repo had been made shallow (tracked class 8607); unshallowed, both green. pencil-adapter-stub-repl two-sessions hang is tracked in 12853. approval-guard1-mutation timed out at 580s under load (UNRESOLVED, contention); CI required test context is the merge gate.
- Apply workflow bytes after rebase: 487285

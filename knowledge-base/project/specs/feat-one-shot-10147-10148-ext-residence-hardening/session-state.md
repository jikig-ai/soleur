# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10147-10148-ext-residence-hardening/knowledge-base/project/plans/2026-10-12-fix-ext-residence-hardening-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- lint-guard-contract.py initially rejected Guard 2's mutation matrix label (`**Mutation matrix (probe-driven):**` parses to a zero-row span); fixed by renaming the label. No other errors. No Agent/Task tool in the planning subagent's harness — research fan-out and CTO-ruling spawns ran inline; technical forks recorded `pending - assumed` per technical-ruling-delegation.md.

### Decisions
- #10147 bound = declared `pin` field: mandatory repo-relative `*.test.*` path per EXT_RESIDENCE entry, verified `(REPO / pin).is_file()` at guard runtime.
- #10148 = `unclassifiable` arm over ALL `blocks` outside server.tf: empty `dialed_hosts` -> finding unless `(fpath, addr)` entry carries `unclassifiable: true`; G2-C6 converts to `expect_red` G2-38; G2-39/G2-40 isolate the arm; G2-C3 converts green->red for `.tf.json` coverage.
- Table-internal invariants get `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` (additive-only) driving probe rows X1-X7 incl. P4-analog negative control; hygiene arm gains >=1-swept-block per entry.
- `root_authorized_keys` seed pin = `terraform-target-parity.test.ts`.
- Named residual: non-`terraform_data` indirect dialers inside server.tf remain out of scope.

### Components Invoked
- soleur:plan, soleur:deepen-plan (manual execution by planning subagent)
- gh, git, python3 scripts/lint-guard-contract.py

### Technical Ruling Gate
- cto_spawns=1 — all 8 `pending - assumed` rows ruled `Ruled by CTO agent, 2026-10-12` (all confirmed, zero overrules); gate re-run: PASS (8 rows examined).

## Work Phase
- Status: complete — guard + battery implemented and green.
- Guard: EXT_RESIDENCE `pin`/`unclassifiable` fields, unclassifiable-dial arm, ext_residence_hygiene() (pin shape/existence, >=1 swept block, hosts-empty-only-under-flag), SOLEUR_PARITY_EXT_RESIDENCE_PROBE.
- Battery: G2-C6->G2-38 (red), G2-39/40, G2-C3->red, G2-C7 green, probe pair + X1-X7, G2_PIN_INPUTS sandbox copies.
- Result: guard 14/14 GREEN on real tree; battery 125/125 cases, RC=0.
- Floors re-derived from the battery log: FLOOR=98, PROBE_FLOOR=14, PROBE_RED_FLOOR=12 (plan estimated 13; measured is 14 — 7 existing + 7 EXT probes share probes_run).
- Deviations: none. First battery run caught a battery-side bug (G2-40 needles landed in the mutator slot — the exact arg-order trap apply_mutation warns about); fixed by moving needles after the mutator.

# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9939-inngest-luks-boot-failures/knowledge-base/project/plans/2026-10-10-chore-inngest-luks-first-boot-envfile-ordering-plan.md
- Status: complete

### Errors
- IaC write-guard hook initially blocked the plan write (detected `systemctl` in prose); resolved with the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out.
- No Task/subagent tool in the subagent's environment; skill-mandated research/review agent fan-outs ran as inline fallbacks, disclosed in the plan's Enhancement Summary with `Reviewed-Coverage: sequential-fallback`.
- `deepen-plan` Phase 4.5 triggered on the literal `SSH` substring (false positive); resolved via required telemetry + deep-dive section.
- `deepen-plan` Phase 4.55 triggered (cloud-init edit forces `hcloud_server.inngest` replace); resolved via `## Downtime & Cutover` section.
- `BASELINE_DECLARED_PROBES` must move 53→54 (plan declares `credentials_required`); added to Files to Edit + AC5.

### Decisions
- `ConditionPathExists=` on all three units (each covering every `EnvironmentFile=` path), keeping fail-closed unprefixed `EnvironmentFile=` — chosen over `-` prefix, earlier runcmd staging, bootstrap `[ -f ]` gate, `ExecCondition=`, `.path` units, ordering directives.
- Acceptance made mechanical via a `Failed to start inngest-luks` forbidden row in `scripts/followthroughs/inngest-provision-rehearsal-capture.sh`'s `viol()` path.
- `closes: []` + PR body `Ref #9939` disposition — acceptance evidence is post-merge (rehearsal dispatch / next prod replace).
- Delivery: carrier-edit → auto-minted `vinngest-v*` tag → build/sign → `bump-cloud-init-pin`; GuardA advisory drift expected mid-pipeline.
- Timer gets its own condition (evaluated at activation) so an abort-host never arms the 30 s tick storm; service condition covers non-timer triggers.

### Components Invoked
- `soleur:plan` skill (inline agent fallbacks, sequential-fallback disclosure)
- `soleur:deepen-plan` skill (halt gates 4.5/4.55/4.6-4.12, `lint-guard-contract.py` RC=0)
- `scripts/betterstack-query.sh`, `scripts/betterstack-assert-absence.sh`, `npx markdownlint-cli2`, `gh`, systemd condition harness

## Review phase (session resumed 2026-10-11)

- Work phase: TDD — RED on all 3 suites, GREEN after impl; commits 27a7fa7, c22c3ab, c7d6e68.
- Panel: 9 seats (tier none, plan-declared scope-out; design-risk no). PANEL_SHA=9fc3f8d071.
- Panel findings: 2 P2 + ~15 P3. Fix round 1 = 772c63d379 ([Unit]-scoping, SIGPIPE-safe predicates, parity asserts, comment accuracy). 7-seat targeted round.
- Fix round 1 findings: 1 new P2 (timer alternation counted either needle) + convergent P3s (EF [Service]-scoping, cardinality-vs-identity, /etc/default infix, vacuity guard, MIN slack). Fix round 2 = 1a59a4b529 (path-set identity via _luks_sec/_luks_sec_vals, per-literal c==1, SVCSEC extraction, MIN=30).
- Follow-ups filed: #9962 (sibling same-class units), #9963 (unexplained systemd-row shipping path), #9964 (ensure-semgrep broken-binary blind spot).
- Affected-gate `test-all.sh --affected` queued on repo-global flock behind sibling worktree runs (position 3; measured >1h).
- Suites green after round 2: 426/426 inngest, 63/63 redis-luks, 30/30 capture (floors exact).

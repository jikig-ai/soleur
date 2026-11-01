# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-01-feat-inngest-flip-token-split-plan.md
- Status: complete

### Errors
- No blocking errors. The mint-inngest-bootstrap-tag dry-run needs an unshallowed clone (plan acceptance says so).
- A CTO ruling named `systemctl --root cat`, which systemd refuses; corrected by measurement.

### Decisions
- Gate lockstep: replace gate `def allow` and shape gate admit the new token; the `inngest_host` job gets a `-target` (parity floor 15 to 16); the replace job gets none.
- Byte budget: INNGEST_GZIP_BUDGET stays 32,300; stubs become high-entropy 58-char tokens; budget script enforces a 512 B headroom floor; prototype 32,196 stored, 572 B headroom. #11265 (STAGED keeper) is a separate PR; #11266 adds nothing here.
- Drop-in: `[Service] EnvironmentFile=/etc/default/inngest-flip`, flip file written under umask 0177, flip token scrubbed by value in inngest-redact.sh.
- Tests: new inngest-flip-token.test.sh, finding 1b rewritten, gate and parity rows, mutation matrices on three guard contracts.
- Follow-ups filed: #11816 (docker-group/sudo review), #11817 (metadata egress block), #11820 (flip-unit silence alert).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO (3 rounds), CPO, plan-review panel, deepen reviewers.

cto_spawns=3 (plan phase)

## Review ledger: PR #11815, panel SHA 10118fd1d8 (12 seats, tier single-user incident)

dedup: ~63 raw -> 14 unique. structural-cause roll-up: one cause recurs across K5-K8: "numbers and pins measured on stubs or by presence/count, not on the real values or on blocking/membership". Seats that should have enumerated it: structural-enumeration (did), test-design (did).

| key | canonical defect | reporting seat(s) | planned fix |
|---|---|---|---|
| K1 | Runbook "First flip: op=arm" is wrong (host inherits `done`; first flip-token write is the on-host `flushed` arm after `op=resume`); abort rule lacks a branch for a refused/odd resume; claim that G3/G3.7 liveness catches a dead flip token is unproven (reader keys on the tag, so a failing flip unit's stderr may count as audible) | agent-native P2, user-impact P2, data-integrity P2 x2 | runbook + ADR + plan text; abort branch: confirm a script-emitted FSM marker from the NEW instance before op=resume |
| K2 | Recovery-route matrix: absent host with pending boot-token replace closes both routes; mid-replace recovery line names a route the replace gate refuses; Doppler-side failure shape; budget step hard-fails a recovery dispatch | architecture F1,F2,F3; data-integrity P3 x2 | runbook state->dispatch matrix; budget-step-on-recovery to CTO |
| K3 | Guard-refusal route rotates only the flip token though the guard covers both | agent-native P2 | runbook sentence |
| K4 | LUKS key-continuity probe is emitted only from the flip unit's terminal arms, so a flip-token defect silences it; no alert | user-impact P2 | ADR + runbook name it; widen #11820 scope |
| K5 | Stub-measured margins presented as real: only 2 of 5 stubs are high-entropy (zot, Better Stack, DSN stubs are repeated filler: honest headroom ~424-484 B < 512 floor); real margin to floor is 64 B not 108/576; `INNGEST_GZIP_BUDGET` not tied to script number; 44 vs 60 B per stub; shared `SECRET_LENGTHS.doppler_token` moved 48->58 for all host models; header/figures stale | performance P2/P3, code-quality P3 x4, pattern P2 | CTO ruling on floor/headroom; then C1 |
| K6 | Pins: 512 B floor value not pinned (default 0/100 survives, `-lt`->`-le` survives); override accepts 0; budget step pinned by presence+order, not by blocking (`continue-on-error`, `if: false` survive) | pattern P2, test-design P2 x2, performance P3, security P3, architecture F3, structural P2 | clamp floor >=512, one literal, emit effective floor in --json; pin no `continue-on-error`/`if:` on the step |
| K7 | New flip suite: 15 of 27 assertions never RED, no pristine-control count pin; drop-in pinned as "has the line" not "is only the line"; token count reads only runcmd+write_files (other cloud-config key survives); glob EnvironmentFile / glob source reach; tripwire denylist narrow (bare export, declare -x, /proc/*/environ, compgen); runtime *.service.d drop-ins unread | pattern P2/P3, test-design P2/P3 x5, structural P2 x2, security P3 | C1 test additions |
| K8 | Counts: replace-gate suite floor 49 vs 54 run; `INNGEST_HOST_MIN_ASSERTIONS` 191 vs 214; replace gate passes any action on the flip address (shape gate aborts them); nothing pins `inngest_flip.key` single reference | structural P3 x3, test-design P2, pattern P3 | C1; any-action question to CTO |
| K9 | Overclaim wording: "read only by inngest-cutover-flip.service" false (redactor reads it by value); "anyone with host access" understates (any local process via metadata); stale "NEVER baked into user_data"; "zot write below" is above; #6178 vs #6889 citation; ADR condition-5 correction | code-quality P3, security P2/P3, history P3 x2 | C2 wording |
| K10 | Runbook structure: heading splits the Production Envelope (A3/A2 text now under it); A1 row still "300 B margin"; owner route lacks `-chdir` + doppler wrapper; no list of agent read-only checks; rehearsal path | code-quality P2, user-impact P3, agent-native P3 x3 | C2 |
| K11 | Bookkeeping: tasks.md "53-char" and unrecorded 7.2/7.5 ticks; model.c4 edge text has no removal trigger; ADR build record should say the `inngest_host` -target narrows "not a -target"; redactor comment overlong/imprecise; workflow file 403 B headroom | pattern, history, architecture F4-F6, code-quality | C2 |
| K12 | N10 dissent (rationale only): charset guard passes a value line equal to the heredoc terminator; boot file sourced as root | security P3 | CTO upholds/amends |
| K13 | Sibling collisions: open #11766 also bumps BASELINE_DECLARED_PROBES 90->91 (post-both value 92); draft #10905 rewrites model.c4/json | history P2/P3 | PR body note; regenerate json, never hand-merge |
| K14 | Pre-existing, left: baked-script stale comments (image carriers), drift auto-text "run terraform locally", 43 shellcheck warnings in 4 older suites | security, user-impact, semgrep | none (recorded) |

## Review round

- Panel SHA `10118fd1d8`: 12 seats, then the batched CTO spawn (R7-R11, recorded in `decision-challenges.md`) and a coverage consult. Tier: single-user incident.
- Coverage-consult leads: (1) assembled runcmd shell semantics, REFUTED (the 39 rendered runcmd items pass `dash -n` and `bash -n`, both guard loops and the flip write in place); (2) plan JSON with unknown keys, not a defect (the gates read only address and actions for the token entries; residual: no recorded real plan of the token-replace shape); (3) no positive proof of capability inversion, CONFIRMED as a documentation gap (rehearsal root aliases both tokens to one read-only token; covered by the runbook plan check and the ADR limits); (4) boot-time flip-write abort has no push signal, CONFIRMED and accepted under N2 (#11820 scope widened to flip unit stalled, boot-time flip-write abort, and the key-continuity probe going silent).
- The plan-phase lines above that state a 512 B floor, 572 B headroom, or that G3.7 catches a dead flip token are superseded by R7 (floor 384 B) and R11 (the liveness gates count error rows); the plan carries a dated correction note at its top.
- Fix round 1 (X tests, Y docs, commits through `90f4558b1a`) was reviewed by 7 fix-round seats (user-impact, data-integrity, architecture, code-quality, security, test-design, semgrep-sast): verdict no P1; every first-panel finding closed or accepted; the new findings were P2/P3 wording and test-strength items.
- CTO batch 2 (2026-11-02) ruled R12 (the write-guard residual: document only, with the amended rationale and the 50 B trigger), R13 (the 384 B floor is a PR-visible policy check, not a merge gate, #6480) and R14 (delete the `T-flipsh` text tripwire, add a runtime canary scan, narrow the S-glob, close R-g structurally). Recorded in `decision-challenges.md` as R12-R14.
- Fix round 2 is pending: X2 (scripts, tests, workflow) and Y2 (docs: runbook, ADR build record, plan banner, tasks.md, decision-challenges, this file). Y2 verified against the repo, not a live host: the owner-run command form (post-cutover Tier-B nested loaders, per `infra-credential-tiers-8209.md`), the `--since` format, G3.7 belongs to `op=arm` and G3 to `op=resume`, and that the flip script dual-emits the `cutover-flip-noop-done` phone-home row. Unverified: that row's queryability on Better Stack, the exact failure point of the old single-loader form, and whether a replace recovers an `aborted` flag.
- Remaining: lead re-runs the combined suites -> commit -> final verification pass -> qa -> compound -> ship

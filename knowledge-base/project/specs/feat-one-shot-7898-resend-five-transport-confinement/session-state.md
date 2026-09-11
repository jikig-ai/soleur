# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-11-fix-resend-five-infra-scripts-transport-confinement-plan.md
- Status: complete
- Plan artifact: complete (selector=subagent-summary)

### Errors
- Two plan writes denied by PreToolUse hooks (`iac-plan-write-guard`) on descriptive prose; resolved with the sanctioned `iac-routing-ack` opt-out and rewording. No content lost.
- Three plan-review agents stalled ~25 min; nudged and all returned before consolidation.

### Decisions
- Re-derived counts: D baseline file on origin/main (8be1ba1a9, PR 8023 still open) = 67 lines -> 62 after this PR; A/B/C 103 -> 98. Linter summary counts firing files (66 D / 100 A/B/C today -> 61 / 95). ACs assert "main - 5", never a literal.
- resend-inbound-bootstrap.sh is NOT hashed into any triggers_replace/user_data (only a dns.tf comment) -> in scope; laptop one-shot under `doppler run -c prd`.
- The four monitors ARE hashed into terraform_data SSH provisioners + local.host_script_files: merge fires apply-web-platform-infra.yml and web-platform-release.yml; hcloud_server is not recreated (established IaC path, not a host-replacement window).
- Invocation contexts: disk-monitor + resource-monitor = 5-min systemd timers (key from ENV_FILE); container-restart-monitor = doppler-wrapped timer; cron-egress-alarm = OnFailure= unit (env from doppler); bootstrap = laptop. Monitors keep `exit 0`; refused/failed send emits one `emit_refusal()` (stdout SOLEUR_* marker + stderr + `logger -p user.crit` -> Vector Source 2).
- Rule D findings beyond the ask: Sentry SENTRY_INGEST_DOMAIN/PROJECT_ID/PUBLIC_KEY adjudicated in two files; bootstrap `$path` allowlist + key-shape check close a measured curl --config directive-injection vector. Classifier untouched; every prescribed shape passes it.
- Observability: monitor units not in Vector Source 4, but Source 2 ships PRIORITY 0-2 from any unit; one `logger` line per branch buys the off-box path. Better Stack alert rule on SOLEUR_*_SEND_FAILED is the one follow-up ship files.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Plan-phase agents: repo-research-analyst, learnings-researcher, functional-discovery, cto, cpo, general-purpose (advisor consult)
- Plan-review panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto
- Deepen-plan agents: security-sentinel, observability-coverage-reviewer, silent-failure-hunter, test-design-reviewer, git-history-analyzer, pattern-recognition-specialist, user-impact-reviewer, general-purpose (verify-the-negative sweep)

## Work Phase
- Status: complete (commits df58024b5 RED harnesses, fd2fb974f GREEN scripts, 1859fb4e0 baselines + local-split reversal)
- RED baseline (task 1.2): per-file classifier on the unedited five = 22 violations; repo-wide summary on origin/main 8be1ba1a9 = `100 baselined (A/B/C), 66 baselined (D)`; baseline files 67 / 103; harness totals 11 / 11 / 18 / 218.
- GREEN: per-file `OK: 5 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`; repo-wide `OK: 1040 scanned file(s), 95 baselined (A/B/C), 61 baselined (D)`; baseline files 62 / 98; harnesses 14/14, 14/14, 25/25, 226/226, new bootstrap suite 5/5; doppler-injection-bound 31/31; vitest resend-sender-domain + sentry-container-restart-alert-op-contract 12/12; linter self-test 61/61 (file identical to main); fixture-relative-assert 62/62 after `--write-baseline` (rows moved only for the five harness files); lint-orphan-test-suites clean.
- AC8 probe (task 3.9): `bash -x disk-monitor.sh` with a fixture env file and a no-op logger on PATH → exit 78, `SOLEUR_DISK_MONITOR_HALT reason=xtrace-credential-bound` on stdout, 0 `RESEND_API_KEY=` lines in the trace.
- Phase 2 exit shard gate: `TEST_GROUP=scripts bash scripts/test-all.sh` exited 4 (REFUSED — a sibling full-gate run was in flight in another worktree; `--capacity` reported CAPACITY_CONTENDED reason=sibling_runs,sibling_suites). Not a pass, not a red: the targeted suites above are the Phase 2 evidence; the full battery runs at ship Phase 4 (ADR-183).

### Mutation evidence (task 4.5) — control green, every mutation cmp-verified as landed, every restore cmp-verified against a pristine copy
| Guard | Mutation | Result |
|---|---|---|
| G2 r2 | move `--disable` after `-s` (disk-monitor) | RED 10/14 |
| G2 r3 | second `--noproxy ''` appended (disk-monitor) | RED 10/14 (NOPROXY_COUNT) |
| G2 r6 | delete the SEND_FAILED emit (disk-monitor) | RED 12/14 |
| G2 r1 | remove `--disable` from the Sentry curl (crm) | RED 24/25 (checked==2 sees the second member) |
| G1 r4 | delete the `sentry_dest_ok=1` arm (crm / alarm) | RED 13/25 / 223 of 226 (must-PASS rows) |
| G1 | host limb deleted (crm / alarm) | RED 11/25 / 222 of 226 |
| G1 | host regex loosened to `^[a-z0-9.-]+$` (alarm) | RED 223/226 |
| G1 r2 | host regex admits `%` (crm) | RED 24/25 |
| G1 | host regex without `$` anchor (path suffix admitted) (crm) | RED 24/25 |
| G1 | trailing-dot strip removed (crm) | RED 24/25 |
| G1 | fold dropped: raw `${SENTRY_INGEST_DOMAIN}` in the URL (crm) | RED 24/25 |
| G1 r3 | key regex loosened / project regex widened | RED 24/25 / 224 of 226 |
| G1 | refusal note not appended in resend_email (crm) | RED 24/25 |
| G1 | delete one END sentry-dest-pin marker (alarm) | RED 225/226 (parity row) |
| G1 r5 | second unguarded Sentry curl appended (crm) | RED in the Rule D linter (1 violation) |
| G3 r1 | key-shape check loosened to `^re_` (bootstrap) | RED 4/5 |
| G3 r2 | path allowlist loosened to `^/` / deleted (bootstrap) | RED 4/5 (harness) AND RED in the Rule D linter (2 violations) — ONLY with the `local` on one line, see below |
| G3 | `-g` dropped from both resend_api curls | RED 4/5 |
| static | the three alarm static anchors on the pre-edit alarm (origin/main) | confined=0, bare `curl -s`=2, grammar=0 (all three would FAIL) |

Axes NOT edited: assertion-helper dispatch (the harnesses' PASS/FAIL counters were not neutered — the plan pins the results-line count as the floor instead), fixture cardinality beyond the rows above, the harness stubs themselves.

### Findings that corrected the plan
1. **The Rule D linter is NOT an oracle for the Sentry host pin** (plan Guard 1 row 5 "deleting the host `=~` re-flags `sends to $SENTRY_INGEST_DOMAIN`" is false). Measured: with the host limb deleted, `lint-shell-trace-credential-refusal.py cron-egress-alarm.sh` still prints OK, because the URL interpolates the DERIVED `_si_host` (`${SENTRY_INGEST_DOMAIN%.}` → `,,`), and the classifier's env-settable test does not follow a derivation from the curl operand back to its env-settable source (only the reverse walk in `_adjudicated()`). The exec harness rows are the only guard for that limb (all killed above). Row 5 as written in the plan (a SECOND raw `${SENTRY_INGEST_DOMAIN}` curl) IS caught — it is the raw-var case. Classifier untouched (forbidden by the ask); recorded as an upgrade trigger for the classifier: a destination operand DERIVED one hop from an env-settable variable should inherit env-settability.
2. **The bootstrap `local` split was inverted.** Plan: "split the three `local`s so `path` is an in-file assignment the classifier can see — measured necessary AND harmless". Measured here: with `local path="$2"` on its own line the classifier reads `path` as assigned-from-non-env and PASSES with the path allowlist deleted; on ONE line (`local method="$1" path="$2" body="${3:-}"`) it reads `path` as never-assigned → env-settable → REQUIRES the pin (2 violations without it). Kept on one line, documented in the function comment.
3. The alarm's cooldown log suffix "(Sentry check-in still posted)" is conditioned on `sentry_dest_ok` (a post was attempted), a superset of the plan's "note empty" condition — also true after the triple-unset path, where the plan's condition would still have printed the false claim.
4. `EMAIL_COOLDOWN_FILE` in cron-egress-alarm.sh is now `${EMAIL_COOLDOWN_FILE:-/run/cron-egress-alarm.last-email}` — required for the committed exec rows (a harness cannot write /run); a cooldown-stamp path, not a destination pin, so ADR-214 is not engaged.
5. The parity row compares the `sentry-dest-pin` region with leading indentation stripped (the monitor's copy sits inside `sentry_event()`); the plan said "byte-identical", which holds modulo indentation.

# Tasks: production-HOME census mechanism (Ref #10455)

Plan: knowledge-base/project/plans/2026-10-31-feat-prod-home-census-plan.md. Rulings: knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/decision-challenges.md (the "Plan-review round" rows supersede earlier rows).
All PRs and comments use `Ref #10455`, never `Closes`. Building and merging does not run the census. The purge and PR 2 are not part of this work.
Fixtures are synthesized only (cq-test-fixtures-synthesized-only); no test scans a real HOME. The census result is bucketed counts only.

## Phase 0: Read-only confirmation before any code

- [ ] 0.1 Read `server/agent-outer-wrap.ts` and `server/agent-runner-sandbox-config.ts`; record where the CLI actually writes under the production posture (`outer_wrap=false`, shared HOME) and whether the three roots (`env_home`, `home_soleur`, `root`) cover it; stop and re-plan if not
- [ ] 0.2 Confirm the class directory layout (`history.jsonl`, `debug/`, `todos/`, `tasks/`, `projects/`, `sessions/`, `shell-snapshots/`, `backups/`, `statsig/`, `file-history/`) against the vendored CLI's own writer code, not a hypothesis
- [ ] 0.3 Confirm with a real `Sentry.init` and a capturing transport (`@sentry/nextjs` 10.59.0) that `withIsolationScope` + `withScope` + an event processor removes `server_name`, `contexts`, `request`, `user`, `breadcrumbs`, `extra`
- [ ] 0.4 Confirm `/health` reports `build_sha` without credentials
- [ ] 0.5 Record the results in the PR body

## Phase 1: Failing tests first (RED)

- [ ] 1.1 `apps/web-platform/test/server/home-census.test.ts`: allowlist over the REAL serialized output of the three sinks (response, Sentry event via a capturing transport, pino bytes via a stream); asserts three sinks captured; fails on any extra key, free string, unbucketed count, `pid`, `hostname`, `server_name`, request data
- [ ] 1.2 fs-call unit tests: import-form test over `server/home-census.ts` and its repository imports (no `open`, `readFile`, `readlink`, `realpath`, `stat`, streams, `child_process`, dynamic fs import) with a floor of at least one module scanned; zero-call spy on the real fs in `dry_run`; a symlinked class directory is counted and never opened
- [ ] 1.3 Synthesized HOME (in-memory fake fs and an on-disk tmp tree with canary names and contents) with exact bucketed counts per class, a symlink, an EACCES directory, an over-cap case, an empty tree; canaries never appear in any sink
- [ ] 1.4 Error path: `lstat` throws an error whose message embeds a path; only the enum is emitted
- [ ] 1.5 Positive control and canary: stubbed all-zero scanner turns `control` RED and `real` is refused; a canary that is hard-coded true is caught; early exit after the first class is caught by a visited-all-classes floor
- [ ] 1.6 Stalled fake fs: the 20 s wall-clock cap fires and returns `truncated`
- [ ] 1.7 Class-table drift test: explicit dash-to-underscore id map; parse the `REQUIRED_HOME_STATE` / `OPTIONAL_HOME_STATE` locals from the sandbox test's source with a count-above-zero positive control; import the exported `HOME_SESSION_DIRS`
- [ ] 1.8 `apps/web-platform/test/server/internal/home-census-route.test.ts`: uniform 401/404, 503 missing secret, default `dry_run`, 409 concurrent real (blocking scanner stub, second request observed while the first is mid-scan), 409 build mismatch, 410 after the sunset, 503 `control_failed`, `Cache-Control: no-store`, no `Access-Control-*`; the in-flight flag survives `vi.resetModules()` and a re-import
- [ ] 1.9 `apps/web-platform/scripts/home-census-trigger.test.sh`: xtrace refusal, token-shape refusal, token absent from argv, `--mode` required, claim-ledger refusal (run id at or below the last marker, two claims), discharged-sha path check, `--self-check` output

## Phase 2: Scanner and emitter (GREEN)

- [ ] 2.1 `server/home-census.ts`: injected fs interface (`lstat`, `opendir` only), `lstat` first and `opendir` only for real directories, one `lstat` per entry, one in-flight fs op, `setImmediate` every 256 entries
- [ ] 2.2 Class table (15 classes), bucketing function (`0`, `1-4`, `5-19`, `20-99`, `100-999`, `1000+`), per-class `n_entries`, `n_mode_bits_group_r`, `n_mode_bits_other_r`, `n_symlink`, `errors`, `absent`; roots by label with presence booleans, `roots_distinct`, `os.homedir()` in try/catch, `claude_config_dir_set`, constant `outer_wrap_cohorts`
- [ ] 2.3 Caps (20,000 entries, 20 s, depth 3), `truncated` and `truncation_reason`, no early exit before every class is visited
- [ ] 2.4 Positive control (in-memory known-answer fs plus the real-adapter canary, folded into `control`); `evidence` from exact uptime (`young` under 24 h); emit only `evidence` and `uptime_bucket`
- [ ] 2.5 Allowlisted builder for every response and refusal with constant `interpretation`; the single emitter: dedicated `pino({ base: null, level })` instance on the same destination; isolation-scoped Sentry event with a stripping processor, constant message and run-level tags only
- [ ] 2.6 `globalThis[Symbol.for("soleur.homeCensus.inflight")]` flag claimed before the scan; `SUNSET_UTC` constant (ready date + 30 days)

## Phase 3: Route and registration

- [ ] 3.1 `app/api/internal/home-census/route.ts`: `POST` only; Bearer via `readInternalBearerSecret` / `bearerMatches`; order: authenticate, sunset, parse, mode, build match, claim flag, control, scan
- [ ] 3.2 `lib/routes.ts` exact path; `lib/auth/csrf-coverage.test.ts`; `test/middleware.test.ts` (including the negative row for `/api/internal/home-census-x`); export `HOME_SESSION_DIRS` in `server/agent-outer-wrap.ts`
- [ ] 3.3 Confirm no change to Inngest `route.ts`, `server/index.ts`, `function-registry-count.test.ts`, `execution-placement.ts`, `cron-manifest.ts`, `vector.toml`, `test/repo-wide-suites.ts`, shared `server/logger.ts`, global Sentry `beforeSend`

## Phase 4: Trigger script, runbook, follow-through probe

- [ ] 4.1 `apps/web-platform/scripts/home-census-trigger.sh` modeled on `plugins/soleur/skills/trigger-cron/scripts/trigger.sh`: `--mode` (no default), `--run-id`, `--discharged-sha`, `--pr`, `--self-check`, `--c9-fallback`; refuses xtrace; token on curl's stdin config; `--max-time 60`; distinct exit codes; dry-run-first for `real`; discharged-commit path diff check against the served build; write-ahead claim comment on #10455; build_sha re-compare after the POST; text names only the preflight command
- [ ] 4.2 `knowledge-base/engineering/operations/runbooks/home-census.md`: the canonical command, decode table, result handling (named owner, same-day report, bucketed object only into the public tracker), the CLO wording lists, the holding line and no-ad-hoc-replies rule, the canonical re-open procedure, retention, "uptime means since last container start", sunset and the C9 terminal state, the unmeasured list
- [ ] 4.3 `scripts/followthroughs/home-census-run-10455.sh` and its test: minimal notify-only probe (exit 2 before `earliest`, exit 5 naming the preflight command after it, never 0 or 1, never touches the secret); credential posture header and `RETIREMENT:` line

## Phase 5: Mutation battery (run by the REVIEWER, not the author)

- [ ] 5.1 `apps/web-platform/scripts/home-census-mutations.test.sh`: apply each Guard 1 and Guard 4 mutation to a copy of the module and require RED; baseline green; a run that applies zero mutations fails; the full battery behind an env gate with a fast always-on baseline and vacuity check
- [ ] 5.2 The reviewer runs every Guard 1 and Guard 4 mutation (including: shared logger restored, Sentry processor removed, a spy substituted for the capturing transport, control removed, canary hard-coded true, early exit) and records each as RED in the PR
- [ ] 5.3 Harness rows and must-PASS non-canonical inputs run and recorded

## Phase 6: Records and review

- [ ] 6.1 ADR-075 dated addendum (mechanism, why the Inngest candidates lost, container-ephemeral HOME, allowlist, CLO conditions by reference, sunset; notes the `lib/routes.ts` entry is removed with #11714)
- [ ] 6.2 `knowledge-base/legal/compliance-posture.md` dated entry; `knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md` carrying the C8 DISCHARGED entry only, citing decision-challenges.md for C1-C10
- [ ] 6.3 Run `plugins/soleur/test/c4-count-parity.test.sh` and the C4 validation tests (no C4 change expected)
- [ ] 6.4 PR body in the future tense with `Ref #10455`; states web-2, `/workspaces`, `/tmp/.cs`, `CLAUDE_CONFIG_DIR`, outer-wrap cohorts and the canary container are unmeasured, not safe; no real identifier, pid, hostname or container id anywhere
- [ ] 6.5 `soleur:engineering:review:user-impact-reviewer`, the security and observability reviewers run at review time
- [ ] 6.6 The CLO re-reads the final scanner and emitter diff against the ruling and records DISCHARGED naming the reviewed commit (C8); set `SUNSET_UTC` to the ready date + 30 days and correct it before merge if the merge slips

## Phase 7: Post-merge (tracked; the merge itself does not run the census)

- [ ] 7.1 Record C8 DISCHARGED on #10455 naming the reviewed commit; verify the deploy is served; run the `dry_run` smoke: `bash apps/web-platform/scripts/home-census-trigger.sh --mode dry_run --run-id <N>`
- [ ] 7.2 File the follow-through tracker (label `follow-through`, directive `earliest` = shipping deploy + 24 h) as a checklist: C8 DISCHARGED with sha, preflight `uptime_bucket` past `lt_24h`, next unused `run_id`, result recorded as `home-census run_id=N`
- [ ] 7.3 A later engineering session (`soleur:go #<tracker>`) runs the real run under C9: `bash apps/web-platform/scripts/home-census-trigger.sh --mode real --run-id <N> --discharged-sha <sha> --pr <PR>`; at most two real runs in total, the second only after a recorded `young` result; terminal state "unmeasured at maturity"
- [ ] 7.4 Report the bucketed object with `interpretation` to the operator and the CLO the same day on #10455; amend the breach-register row in-cell and mark superseded sentences
- [ ] 7.5 A nonzero in `history_jsonl`, `debug`, `todos` or `tasks` starts the re-open procedure (runbook)
- [ ] 7.6 #11714: the sunset disables the route at merge + 30 days (earlier if last real run + 30 days is sooner); delete the dead code and record the date of the last real run

# Tasks — fix: port UNKNOWN STEP attribution-expiry recovery to sibling step-anchored probes

Plan: `knowledge-base/project/plans/2026-11-01-fix-followthrough-sibling-probes-attribution-expiry-plan.md`
Issues: #11607 (Closes), #11609 (Closes via PR body) | Context only: #11583 (standing — never `Closes`) | Precedent: `web-first-deploy-10585.sh` post-26ec69c3, `git-data-boot-poll-8178.sh`

## Phase 1 — Fixture RED: web-fresh-boot-zot-8651 (write failing cases first)

- [ ] 1.1 In `scripts/followthroughs/web-fresh-boot-zot-8651.test.sh`, extend `job()` (~:53) to emit a `steps` array on the job object — trail step `name` (prefix `Surface fresh-host Sentry breadcrumb trail`), `conclusion`, `startedAt`, `completedAt`; `startedAt: null` arm for the absent case.
- [ ] 1.2 Add UNKNOWN STEP builders per `web-first-deploy-10585.test.sh:145-183`: `GH_LOG_BOM=$'\357\273\277'`; `ul()` (`<job>\tUNKNOWN STEP\t<bom?><ts> <line>`); `ulog()` faithful document — bare `Set up job` head, BOM'd prelude `##[group]Run` stamped BEFORE `startedAt`, BOM'd trail-step `##[group]Run` AT `startedAt`, payload lines, BOM'd next-step bound (`ULOG_NO_BOUND`/`ULOG_EARLY_HDR` arms as needed).
- [ ] 1.3 Add failing cases per plan Test Scenarios (zot block): recovered PASS; recovered FAIL (DARK/GHCR on failure job — conclusion-agnostic); unrecoverable success job → 3 `TRANSIENT:`; missing `startedAt` → 3 `TRANSIENT:`; `skipped` step → 2 NOT YET; ANSI-echoed-only region → 2; EOF-bound region must-PASS.
- [ ] 1.4 Run `bash scripts/followthroughs/web-fresh-boot-zot-8651.test.sh` — new cases RED, old green. Commit: `test(followthroughs): RED — UNKNOWN STEP fixtures for web-fresh-boot-zot-8651`

## Phase 2 — zot probe implementation

- [ ] 2.1 Extend the jobs jq (`web-fresh-boot-zot-8651.sh:51-53`) to TSV `databaseId\t<step conclusion // "absent">\t<step startedAt // "-">` (camelCase `startedAt` on `gh run view --json jobs`); `IFS=$'\t' read -r jid jstep jstart`.
- [ ] 2.2 Designed-absence `continue` when `jstep` is `skipped`/`absent` (plan_only / pre-step runs).
- [ ] 2.3 `log=${log//$'\r'/}; log=${log//$'\357\273\277'/}` after fetch; shared `emit_content` awk (ts strip + ANSI-drop) for named path AND region.
- [ ] 2.4 Recovery on patternless named trail: 8178-verbatim region awk (`ts >= ${jstart:0:19}`, next-header/EOF bound) → `emit_content` → replace trail only when it carries `TRAIL_PATTERN`; else `recovery_cause`.
- [ ] 2.5 Post-recovery tripwire `jcon == "success" && -z trail` → `TRANSIENT:` exit 3 with cause; non-success keeps `continue`; header comment updated.
- [ ] 2.6 Re-run suite — all green incl. pre-existing; bump `MIN_CASES` (:101). Commit: `fix(followthroughs): zot probe recovers trail from UNKNOWN STEP logs via startedAt region slice (#11607)`

## Phase 3 — rehearsal collector: fixture RED then implementation

- [ ] 3.1 In `git-data-rehearsal-evidence.test.sh`, add `startedAt` to `run-<id>.json` fixture step objects and UNKNOWN STEP `log-<id>.txt` builders (multi-job whole-run shape: two job sections, bare head, BOM'd headers, prelude, bound) — new cases RED per plan Test Scenarios (rehearsal block).
- [ ] 3.2 `fetch_run` (`:170`): normalize `${WORK}/<slot>.log` once — CR + exact 3-byte BOM strip (`sed -i 's/\r//g;s/\xef\xbb\xbf//g'` or bash `${var//…/}`; NEVER `tr -d '\357\273\277'` — byte-wise delete corrupts UTF-8).
- [ ] 3.3 New `step_region <slot> <prefix>`: jobs-JSON lookup → rc 1 absent/skipped; rc 0 region sliced (field-1 job-name pre-filter + 8178 awk verbatim) re-attributed to `<slot>-<pfx>.region.log` (`<job>\t<step>\t<ts> <content>`); rc 2 unrecoverable.
- [ ] 3.4 `lcount`/`lfirst` signature → `<slot> <prefix> <regex>`; two-phase named-then-region eval (rc 0 re-run shared awk, rc 1 report original zero, rc 2 return 1); update call sites `:261-262,275,304,441-442`; `refs_msgs` two-phase at `:484-485`; header comment `:196-199`.
- [ ] 3.5 Re-run suite — all green; bump floor. Commit: `fix(followthroughs): rehearsal collector re-attributes UNKNOWN STEP log regions per step (#11607)`

## Phase 4 — docs, verification, ship inputs

- [ ] 4.1 `followthrough-convention.md` §"Sharp edges for `gh run view --log` probes": name all three consumers + the whole-run job-scoping variant.
- [ ] 4.2 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-01-fix-followthrough-sibling-probes-attribution-expiry-plan.md` clean; markdownlint clean on plan + tasks.
- [ ] 4.3 Run the mutation spot-checks from both Guard Contracts (BOM single-strip, dropped `ts >=` gate, recovery deleted, missing job pre-filter) — each reddens its suite.
- [ ] 4.4 Both suites + `scripts/test-all.sh` rows green; `scripts/suite-durations.tsv` floors unchanged.
- [ ] 4.5 PR body (`ship` authors it): `Closes #11607` and `Closes #11609` each on its own line; verify `Closes #11583` appears NOWHERE in title/body/commits; restate the two lookback conclusions (zot spans/dormant-latent; rehearsal spans-by-construction) in the body or a #11607 comment.

# Tasks: P7 on the Playwright-MCP path — redacting stdio proxy (#7980)

Plan: `knowledge-base/project/plans/archive/20260914-230848-2026-09-14-feat-playwright-mcp-snapshot-redaction-proxy-plan.md`. Each task cites the plan phase it implements; the plan's Guard Contract rows and FR/NFR/QG numbers are the acceptance surface.

## Phase 0: Preconditions and measurement (gate)

- [x] 0.1 Run the importlib probe on `redact-a11y-snapshot.py` and confirm `- textbox "Token" [ref=e1]: <redacted>` (plan Phase 0.1).
- [x] 0.2 Write `plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py` (stdlib; serves the synthesized page; drives the server over stdio; writes one JSON per message; asserts the newline framing) (Phase 0.2).
- [x] 0.3 Run the driver against `npx @playwright/mcp@0.0.78 --headless --isolated --output-dir <tmp>`; reproduce probe-record rows 1–8 and capture rows 9–16 (`roots/list` with `roots` advertised, `browser_close` — expect NO `isClose` on the wire, config-vs-flag, raw framing, `_meta.json` / `_meta.raw`, `browser_find` with the sentinel, default `tools/list` without `browser_start_tracing`/`browser_pdf_save`). The page uses `ZZQP-SENTINEL-7980` only in credential-named inputs and `ZZQP-BENIGN-7980` in Notes (Phase 0.2).
- [x] 0.4 Commit the captures under `plugins/soleur/skills/agent-browser/test/fixtures/playwright-mcp-0.0.78/` (sentinel `ZZQP-SENTINEL-7980` retained); make the suite derive the directory from the `.mcp.json` pin (Phase 0.2).
- [x] 0.5 Reaper discrimination row scoped to the captured pgid, including the wrapper self-match assertion (Phase 0.3).
- [x] 0.6 Fleet-copy row on the 0.0.75 copy: measure where `browser_navigate` writes `page-*.yml` with no `--output-dir`, that the sentinel is in it, and that `--snapshot-mode none` is accepted and stops the write (Phase 0 step 4).
- [x] 0.7 Write `knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/phase-0-measurement.md` with every row above.

## Phase 1: Guard contract first (RED)

- [x] 1.1 `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py` — table-driven stub (`FAKE_PW_RESULT_FILE`, `FAKE_PW_ROOTS_COLLIDE`, `filename` write, `FAKE_PW_ARGV_OUT`, `FAKE_PW_REQUEST_LOG`, `FAKE_PW_EXIT_CODE`, `FAKE_PW_HOLD`), under 80 lines; plus `fake-passthrough-proxy.py` (~10-line known-negative relay) and stub self-test rows driven without the proxy (Phase 1.1, instrument rows).
- [x] 1.2 Odd-shape fixture files: two text blocks, link result, `structuredContent`, `resource` block, `_meta` in result, invalid UTF-8 byte, list line with two pending results, `error` with/without `data`, `tools/list` without `tools`, result with both `result` and `method` (Phase 1.1).
- [x] 1.3 `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` — redactor-suite shape (`ok`/`bad`, instrument self-test, helper controls that REJECT incl. `assert_stderr_marker`, `MIN_ASSERTIONS` bound adjacent to the floor block); Guard 1 rows 1–39, harness rows H1–H2, must-PASS rows P1–P7 with P6's population enumerated (floor ≥ 4, `snapshot-meta-json` excluded with reason, `{`-canary included); mutations as standalone `.py` copies asserted landed with `diff -q` AND inside the named function's `ast` range; process rows poll `pgrep -g <logged child pgid>` with `PLAYWRIGHT_MCP_PROXY_GRACE_S=1`; `grep -q` only on herestrings/files (Phase 1.2).
- [x] 1.4 Guard 2 executable row: run `.mcp.json` `args[1]` under `bash -c` with `HOME=<scratch>` and an `npx` shim on `PATH`; assert parent = proxy, argv has `@playwright/mcp@0.0.78`, `--user-data-dir=<scratch>/.cache/playwright-mcp-profile`, `--config=.claude/playwright-mcp.config.json`, ends with `--snapshot-mode none` (Phase 1.3).
- [x] 1.5 Drive every RED row against the pre-fix stub/proxy and record the observed RED in `phase-0-measurement.md` (QG5). *Record: `runs/suite-red-passthrough.txt` (81 passed / 83 failed against `fake-passthrough-proxy.py`), summarised in `phase-0-measurement.md`.*

## Phase 2: The proxy (GREEN)

- [x] 2.1 `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py` implementing B1–B10: argv parse; `load_redactor` (four names, fail loud); `refuse_argv_and_env` (`--save-session`, config `saveSession` from `--config` else `$PLAYWRIGHT_MCP_CONFIG`, `DEBUG` matching `*`/`pw:mcp*`, `DEBUG_FILE`); `self_test`; `spawn_child` (`--snapshot-mode none`, binary pipes, `start_new_session`, child pgid logged); single `selectors` loop with `os.read` per-fd buffers, `MAX_LINE_BYTES` discard + `oversize` answers, per-iteration `try/except` that logs `pump error:`; `write_line`; `pump_client_to_server` + `refuse_request` (`filename` key, `arguments._meta` key; client list lines dropped); `classify` (response iff `result`/`error`; unknown key dropped; `result`+`method` withheld); `rewrite_result` (shape whitelist incl. block-level keys, cap, whole-line link arm without deletion and without naming a path, trailer block, re-serialize only on change); `annotate_tools_list` (fail-safe); `error_result` (one builder, pinned stderr vocabulary, caveat wording checked against `_is_credential_name`); `teardown` (SIGTERM → SIGKILL after `GRACE_S`, exit-code clamp, stderr flush, `os._exit` after drain) (Phase 2.1).
- [x] 2.2 Suite green; every matrix row observed GREEN on the shipped proxy; lifecycle rows green against the stub's pgid (Phase 2.2).
- [x] 2.3 NFR1 stdlib-only AST check; NFR2 every stdout line is JSON-RPC; NFR3 no `threading`.

## Phase 3: Wire the dogfood surface

- [x] 3.1 `.mcp.json`: proxy `pkill` inserted BEFORE the child `pkill`; `exec env … python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 --user-data-dir=$prof --config=.claude/playwright-mcp.config.json`; two comment sentences in `.claude/playwright-mcp.config.json` (Phase 3.1).
- [x] 3.2 Live verification with the capture driver against the real `npx` chain: FR2/FR3/FR4/FR10/FR10b reproduce; EOF, SIGTERM, and SIGKILL + wrapper reaper each leave the child's pgid empty; record in `phase-0-measurement.md` §Live verification — BEFORE Phase 4 prose (Phase 3.2). *Done via the session driver (not the capture driver) and recorded in `runs/live-verify.md`, cited from `phase-0-measurement.md`; the Phase 4 prose was written in parallel by a subagent, so the ordering clause was not honoured literally — the live run confirmed the prose's claims after the fact (tree redacted, Notes intact, trailer, no `### Snapshot` on navigate, 0 `page-*.yml`, three teardown paths → group empty).*
- [x] 3.3 `cron-ux-audit.ts`: append `"--snapshot-mode", "none"` with a comment citing PA-31 §(g) and Phase 0 step 4; add the `zero-screenshots` `warnSilentFallback` beside the upload step's `logger.info`; add the unconditional `toMatch` rows (flag + `op: "zero-screenshots"`) to `cron-ux-audit.test.ts`; vitest green (Phase 3.3, FR22).

## Phase 4: Teeth alignment — lint, prose, comments, contract

- [x] 4.1 `scripts/lint-credential-path-literals.py`: new `MCP_GAP_MARKER_RE` (structural prescription), `S2_RECIPE` verbatim, failure message quotes the canonical sentence; suite rows (old sentence RED, wrapped new marker GREEN, second non-compliant file RED, old regex kept as a constant); M5 comment updated (Phase 4.1, FR16, Guard 3).
- [x] 4.2 Five S2 files rewritten to the structural disclosure (`filename:` + redactor + shred first; refusal ⇒ wrapped ⇒ bare call, after every action tool); startup-failure sentence (CPO E1); `widen-playbook.md` keeps the `browser_evaluate` + `filename` residual; `reproduce-bug/SKILL.md` prefix relic fixed (Phase 4.2, FR17). *Population is six files, not five: `agent-browser/SKILL.md`'s verify sentence names `mcp__playwright__browser_snapshot`, which puts it in S2's population, so it carries the canonical sentence too.*
- [x] 4.3 `agent-browser/SKILL.md` "Wrapping the server" subsection (dogfood-only label, `${CLAUDE_PLUGIN_ROOT}` form + substitution sentence, three arms, startup-failure sentence, Linux-only wrapper vs POSIX proxy, restart + `ToolSearch` verification) (Phase 4.3).
- [x] 4.4 `redact-a11y-snapshot.py`: public `looks_like_a11y_tree` + alias, `__all__`, contract comment, docstring bypass sentence; one contract row in `redact-a11y-snapshot.test.sh`; hook header comment (Phase 4.4, FR24).
- [x] 4.5 `apps/web-platform/test/plugin-root-anchoring.test.ts`: proxy added to `GATE_SCRIPT_RE` and `EXPECTED_GATE_REFS`; vitest green (Phase 4.5, FR24).

## Phase 5: Records — ADR-213 addendum, register, C4, attestation

- [x] 5.1 ADR-213 addendum (three resolution tables incl. the plan-review cuts, measured rows, reach, residuals, S2 class change, enumerative closure) + the `[Superseded 2026-09-14 …]` pointer line after the §Consequences sentence (Phase 5.1, FR18).
- [x] 5.2 Register appends at the CURRENT cell tails (PA-8 after the 2026-09-11 bracket; PA-31 after `…about those tools**.**]`), from the CLO-drafted text as amended in the plan; every claim verified against the shipped body; no `<…path>` slot left; FR19 substring-identity check with the tested patterns (Phase 5.2).
- [x] 5.3 C4: `playwrightMcp` (#external) + `platform.plugin.snapshotGuard` (ships-vs-wires description) + three edges in `model.c4`; `components`/`containers`/`context` includes in `views.c4`; regenerate `model.likec4.json`; four gates green (Phase 5.3, FR20).
- [x] 5.4 Invoke the `clo` agent against the shipped body → `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md`; `compliance-posture.md` Completed row + `last_updated` (Phase 5.4, FR23).

## Phase 6: Verification

- [ ] 6.1 `bash scripts/test-all.sh` scripts shard; `python3 scripts/lint-credential-path-literals.py` (no args, scanned > 0); `python3 scripts/lint-guard-contract.py <plan>`; `bash scripts/guard-vacuity-floor.test.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; the four C4 gates; `plugin-root-anchoring` + `cron-ux-audit` vitest (Phase 6.1, QG1–QG6).
- [ ] 6.2 Walk FR1–FR24 (incl. FR2b, FR7b, FR10b, FR11b) and NFR1–NFR3 with their commands; confirm #8156 state (FR21).
- [ ] 6.4 Post-merge (`/soleur:postmerge`): `doppler run -p soleur -c prd -- scripts/betterstack-query.sh --since 24h --grep zero-screenshots` after the first `cron-ux-audit` fire — observation only (Phase 3.3).
- [ ] 6.3 PR body: `Closes #7980`, `Ref #7981`; name Phase 3.3 as the CLO finding folded outside #7980's literal scope (Phase 6.2).

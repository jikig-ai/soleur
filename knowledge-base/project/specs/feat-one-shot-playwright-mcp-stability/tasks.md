# Tasks: fix Playwright MCP browser closing on its own

Plan: `knowledge-base/project/plans/2026-10-04-fix-playwright-mcp-browser-closing-on-its-own-plan.md`
Branch: `feat-one-shot-playwright-mcp-stability`

## Phase 0: RED first

- [ ] 0.1 Create `plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh` skeleton (ok/bad helpers, instrument self-test, vacuity floor, printf verdict) with the rows from the plan's Test Scenarios
- [ ] 0.2 Write Guard 1 and Guard 2 mutation rows (plan Guard Contract) before the implementation
- [ ] 0.3 Prove RED on the current tree using a scratch `PATH` with a `pgrep` shim that prints only the decoy pid and the old hook text from `git show HEAD:...` (never run the old hook unshimmed)

## Phase 1: Root cause (item A)

- [ ] 1.1 Delete `plugins/soleur/hooks/browser-cleanup-hook.sh`
- [ ] 1.2 Remove its `Stop` entry from `plugins/soleur/hooks/hooks.json`
- [ ] 1.3 Remove its row from `.claude/hooks/devin-dispositions.tsv`
- [ ] 1.4 Remove its entry and comment from `REGISTRY` in `apps/web-platform/test/plugin-stop-hooks-web-parity.test.ts`
- [ ] 1.5 Update the `cq-after-completing-a-playwright-task-call` breadcrumb in `scripts/retired-rule-ids.txt`
- [ ] 1.6 Run `.claude/hooks/devin-matcher-parity.test.sh`, the parity test, `python3 scripts/lint-rule-ids.py ...`

## Phase 2: Slot lease (item B)

- [ ] 2.1 Create `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh` (flock slots 0..31, slot-0 7s wait, owner-alive skip, stale cleanup, no-flock/no-fs-support/exhaustion fallbacks, `return` not `exit`, `. script || exit 1`, no kills)
- [ ] 2.2 Rewrite the `.mcp.json` launch string to source it; keep the Guard 2 anchors and the pin in `args[1]`
- [ ] 2.3 Replace the two `reaper:` rows in the proxy suite's Guard 2 with rows for the new string
- [ ] 2.4 Make Guard 2 behaviour rows green in the lifetime suite

## Phase 3: Proxy flag and registrations (items C and D)

- [ ] 3.1 Implement `--chromium-fallback` (+ `PLAYWRIGHT_MCP_PROXY_CHROME_PATHS` seam) in `playwright-mcp-redact-proxy.py`; update its docstring
- [ ] 3.2 Add proxy-suite rows (flag absent unchanged; Chrome absent appends once; unknown platform appends nothing; present appends nothing; explicit browser appends nothing; ping env reaches the child)
- [ ] 3.3 Extend `fake-playwright-mcp.py` to log the ping env variable to stderr
- [ ] 3.4 Extend `g3_shape` and mutants for `--chromium-fallback` and `env`; bump `EXPECTED_MUTANTS`, `EXPECTED_RED_ROWS`, `MIN_ASSERTIONS`
- [ ] 3.5 Add `env` `PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0` to `.mcp.json` and `plugins/soleur/.mcp.json`; add the flag to the plugin argv

## Phase 4: Records

- [ ] 4.1 ADR-271 via `soleur:architecture` (re-verify ordinal against `origin/main`)
- [ ] 4.2 Learning `knowledge-base/project/learnings/bug-fixes/2026-10-04-stop-hook-killed-live-playwright-chrome-heartbeat-theory-refuted.md`
- [ ] 4.3 Correction note in the 2026-04-03 browser-cleanup learning
- [ ] 4.3b Dated note in ADR-093 that the Stop hook it lists is removed
- [ ] 4.4 `agent-browser/SKILL.md` playbook updates (verified `install-browser` command)
- [ ] 4.5 C4: read all three `.c4` files; edit the `playwrightMcp` description; regenerate `model.likec4.json`

## Phase 5: Verify and ship prep

- [ ] 5.1 Run: proxy suite, redactor suite, lifetime suite, c4-count-parity, c4-model-freshness, c4 syntax/render tests, `python3 scripts/lint-guard-contract.py`
- [ ] 5.1b Scratch probe: SIGKILL a proxy (own temp profile, bundled Chromium, headless) and observe Chrome exit; record in the learning
- [ ] 5.2 File the deferral issue for the proxy's server-ping handling
- [ ] 5.3 PR body per AC8 (proven vs not proven, inert env var, restart needed, "Ref #9281", no closing keyword)

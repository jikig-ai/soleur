# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8156-8250-mcp-proxy-time-port/knowledge-base/project/plans/2026-09-18-feat-proxy-wrapped-playwright-mcp-default-plan.md
- Status: complete

### Errors
- `Can't find lefthook in PATH` on both planning `git commit` invocations (hook binary absent; commits succeeded).
- Task/AskUserQuestion tools unavailable inside the planning subagent — research, advisor consult, plan review, and deepen fan-out ran inline/sequential (`Reviewed-Coverage: sequential-fallback` disclosed in the plan); deepen-plan post-enhancement options prompt could not be presented.
- The issue's cited plan path was stale (archived under `plans/archive/`); recorded in the plan's Research Reconciliation table.

### Decisions
- Chose a dedicated `plugins/soleur/.mcp.json` registering a wrapped `playwright` stdio server (`mcp__plugin_soleur_playwright__*`, `command: python3`, `${CLAUDE_PLUGIN_ROOT}`-anchored proxy argv, `@playwright/mcp@0.0.78` pin) over inline `plugin.json` — the codex deep-equality and devin parity tests make inline registration break sibling harnesses.
- Cut the "auto-wrap the customer's existing registration" arm (issue Option B): no consented manifest mechanism exists; the only implementable form is an unconsented `.mcp.json`/`.claude.json` mutation that fails P7 in the session it lands.
- Chose a proxy-side `--user-data-dir-name <basename>` flag (mirroring `scripts/lib/scratch-root.sh` XDG semantics) over a `bash -c` launch string, with refusal on relative-XDG/unresolvable-`~`/separator/`..`/conflicting-dir inputs.
- Deferred Option C (hook net on `mcp__playwright__.*`) with re-evaluation criteria; a `deferred-scope-out` issue filing is AC9.
- Engines-floor probe (`>=2.1.139`) is a gating Phase 0; a failed floor forces an `engines` bump flagged for CPO. CPO sign-off required before `/work` (threshold `single-user incident`).

### Components Invoked
- `/soleur:plan` (phases 0–6, inline in subagent)
- `/soleur:deepen-plan` (sequential-fallback coverage)
- `scripts/lint-guard-contract.py` (green)
- `gh` CLI
- git (two path-scoped commits under `knowledge-base/**`: `4c407ff25`, `c8cca8845`)

## Sign-off Phase (pre-/work)
- Threshold: `single-user incident` → CPO + user-impact-reviewer sign-off required.
- Sign-off question: "the fix for #8156 ships a stdio MCP server that spawns `python3`+`npx` on every customer session, with a persistent browser profile under the user cache dir."
- **CPO verdict: APPROVE-WITH-CONDITIONS** — (1) Phase-0 probe is a hard gate before any manifest edit; an engines-floor bump returns to CPO. (2) Degradation prose must not assume the plugin server exists (file-form fallback on `/mcp` toggle-off / precondition failure). (3) AC9 Option-C deferral issue ships in the same PR.
- **user-impact-reviewer verdict: SIGN-OFF-WITH-CONDITIONS** — Finding 1 (blocking): orphan-on-own-profile (SIGKILLed session leaks the plugin's playwright-mcp child → SingletonLock contention on the soleur profile) was uncovered → bound into plan as Phase-0 probe item 5 + `failure_modes` row + playbook note. Finding 2 (minor): `disclosed_as` reconciled to docs-claimed-on-merge. Findings 3–4 covered.
- Plan amendments committed at `52dd7718c`.

## Work Phase (/work — resumed 2026-09-18)
- Rebased onto origin/main pre-Phase-1 (legal-doc plan, Phase 0.5 check 6).
- Phase 0 probe on Claude Code **2.1.139 exactly** (mise store install): plugin `.mcp.json` registers `plugin:soleur:playwright`, `${CLAUDE_PLUGIN_ROOT}` expands, user+plugin registrations coexist — floor holds, no engines bump. Orphan-reaping measured end-to-end: playwright-mcp self-terminates on stdio EOF; Chrome reaped even on child SIGKILL; stale SingletonLock stolen on pid-liveness. Live orphan-on-own-profile shape refuted → user-impact Finding 1 discharged by measurement.
- T1.1–T1.4 done: `--user-data-dir-name` flag + refusals (63 mutants), `plugins/soleur/.mcp.json`, Guard-3 rows, SKILL.md §"Wrapping the server" rewrite.
- T2 done: 13 literals swept; survivors pinned at agent-browser/SKILL.md:65,416 (customer-own-registration scope); preference clauses outside S2 canonical; `EXPECTED_GATE_REFS` unchanged (G3 deduped identity).
- T3 done: ADR-213 addendum, model.c4 + regen, PA-8 §(g) re-append + PA-31 §(g) assessment, CLO audit §Addendum — #8156, compliance-posture in-cell correction + comment, Option-C issue **#8286** filed.
- Gates green: proxy suite 316/316 (63 mutants); credential-path lint 41/41 + full scan; plugin-root-anchoring 26/26; codex+devin-plugin 14 pass; c4 gates 4/4; cron-ux-audit 30/30; components+skill-security-scan 1353; lint-legal-registers 11/11; adr-frontmatter 2/2; lint-workflow-install-sites OK.
- AC1–AC11 verified; AC12 pending PR body.

## Review Phase (/review — 2026-09-18)
- Classification: code (23 files) → 8-agent panel; design-risk pass ran first (new mechanism surface).
- **code-simplicity-reviewer: SOUND-WITH-NITS** (all P2). Fixed inline: duplicate `--user-data-dir-name` last-win → refuse; leading-dash basename → refuse; `expanduser("~")` → `HOME/.cache` (mutant 62 retargeted to the refusal-message contract); unreachable false branch → `if profile_dir is not None:`; dead Guard-3 literal assert folded into `g3_shape`'s exact argv equality; README MCP table completed (`playwright` row + missing `cloudflare`/`stripe` rows + count 3→5); alternatives analysis now carries the unconditional-inject arm.
- **architecture-strategist: SOUND-WITH-NITS** with one **P1 (resolved)**: the hosted agent-runner loads the vendored plugin tree via `plugins:[{type:"local"}]` on claude-code 2.1.219 — a vendored `plugins/soleur/.mcp.json` would register a guaranteed-failed `plugin:soleur:playwright` on the prod image (no `python3`, no `@playwright/mcp@0.0.78`, firewalled egress). Resolution: **vendored-tree exclusion** — `rm -f "$DEST/.mcp.json"` in both vendor steps (`ci.yml`, `reusable-release.yml`), so reach (c) holds by exclusion, not absence. `SdkPluginConfig.skipMcpDiscovery` rejected (would unregister the plugin's sanctioned HTTP `mcpServers`). Pinned by two new Guard-3 suite rows; ADR-213 addendum, CLO audit addendum, PA-8 §(g) correction, model.c4 all record the new basis.
- **P1-2 (resolved)**: preference prose over-promised the plugin server for stored-profile/operator-MFA flows — scoped at `cf-token-scope/references/widen-playbook.md` (headed + dedicated persistent profile; drive the registration owning the stored session), and the `work`/`plan` routing tables (dedicated-profile caveat).
- **Stale namespace literal (fixed)**: `compound/SKILL.md` `mcp__plugin_playwright_playwright__*` (never a real namespace) → any-registration `browser_navigate` evidence check.
- **semgrep-sast seat**: 0 findings, 151 Python rules on both `.py` files (re-run post-fix; no bash registry pack exists).
- Post-fix gates re-run green: proxy suite **323/323 cases, 65 mutants, 65 mutation rows**; credential literals 41/41; anchoring 26/26; codex+devin 14 pass; C4 4/4; legal lint 11/11; workflow shards (reusable-release ×3, deploy-invariants 70, canonical-parity, drift-step-order) all green; dockerfile parity 19 pass; plugin-mount/path/containment 27 pass; cf-token-scope 41 pass; skill-security-scan 22 pass; AC4 sweep = the 2 permitted survivors only.
- Commit `dd085a96a`, pushed. PR #8275 body verified: `Closes #8156`, `## Changelog`, MINOR, #8286.

## Review Phase — second round (/review panel + hardening, 2026-09-18)
- 10 remaining seats reported. **Fixes landed inline** (each disposition: fix):
  - **Headed premise inversion (P1, corrected):** `@playwright/mcp@0.0.78` defaults HEADED (`headless: false`) on `channel: "chrome"` — the plan's "(headless, bundled Chromium)" was measured wrong on the npm-cached package. Corrected in plan §Deliberately-absent + C4-views spec, SKILL.md registration paragraph + playbook, model.c4 playwrightMcp description. No `--headless` added — credential-handoff flows need a visible window; `PLAYWRIGHT_MCP_HEADLESS` documented as the customer opt-out. Headed system-Chromium probe on this Wayland host: 4/5 calls, zero Vulkan/ozone/crash lines → 2026-06 dogfood crash class does not reproduce there.
  - **Fleet `--strict-mcp-config` (measured):** plugin-root `.mcp.json` discovery is suppressed under the flag (TOOL-ABSENT vs TOOL-PRESENT, claude 2.1.273) — strict-mode clone path stays free of the registration while the flag holds. Recorded in ADR-213 caveats + CLO audit addendum.
  - **Devin reach (corrected):** Devin CLI's own documentation honors plugin-root `.mcp.json` + `${CLAUDE_PLUGIN_ROOT}` — the "read only by Claude Code"/"tools do not exist on Devin" claims were false (reach is benign: still the wrapped proxy). Corrected in SKILL.md preconditions, ADR-213 ×2, plan ×3, audit addendum. Codex unverified → claimed in neither direction.
  - **Env/argv/config sink surface (real gap, widened to default-on):** upstream `config.js` enumerates ~37 `PLAYWRIGHT_MCP_*` vars + argv options; the proxy vetted ~6. Now refused via table-driven SINK_FLAGS (argv + env twin): save-session, storage-state, secrets, output-dir, init-script/page, cdp-endpoint, endpoint, extension, executable-path, allow-unrestricted-file-access, grant-permissions — plus the second-pass finds `--save-trace`/`PLAYWRIGHT_MCP_SAVE_TRACE`, `--save-video`/`PLAYWRIGHT_MCP_SAVE_VIDEO`, `--no-sandbox`/`PLAYWRIGHT_MCP_SANDBOX`, `--ignore-https-errors`, hidden `--daemon`; SINK_ENV_ONLY: USER_DATA_DIR, SNAPSHOT_MODE; config: saveSession/saveTrace/saveVideo/secrets/outputDir/aufa/extension/caps/server.port+host/browser.{cdpEndpoint,remoteEndpoint,initPage,initScript,userDataDir-conflict,contextOptions.{storageState,permissions,ignoreHTTPSErrors},launchOptions.{executablePath,chromiumSandbox:false,remote-debugging args}}. Trailing valued flags refused (VALUE_FLAGS incl. `--daemon`, `--save-video`).
  - **Log control-char injection:** `_LOG_SCRUB` translates control chars + U+2028/2029 to spaces in `log()` — tool names/serverInfo can no longer forge stderr lines.
  - **`vet_error` bounds:** integer-code check (bool excluded), error frame REBUILT from safe fields only — `data`/stolen keys never forwarded.
  - **`vet_other_result`:** non-`tools/call` results scanned for tree-shaped/redactable strings; withholds when unsafe (defeats the method-only-routing mutant by defense-in-depth).
  - **realpath profile root** + `argv.index("--")` hoist + docstring corrections.
- **Mutation-suite maintenance:** 4 stale needles updated to refactored source; mutants 31/48 retargeted (rebuild/vet_other_result now catch the old leaks — observable is delivery-vs-withhold); +2 mutants for the new config arms. Final: **419/419 cases, 77 mutants, 77 mutation rows, vacuity floor 419**.
- **Prose follow-through:** session-rules-loader MCP roster reads all THREE committed sources (+ `plugins/soleur/.mcp.json`, comment updated, 31/31 test green); help.md MCP row adds `playwright` (Claude+Devin blocks); guard.sh staleness fixed (#8156 shipped → residual named #8286); review-e2e-testing.md prefer bullet; reproduce-bug absent-server file-form fallback; SKILL.md arm-1 enumerates the full refusal surface; SKILL.md playbook covers display-less/Chrome-absent/Wayland launch-degradation modes.
- Gates re-run green: proxy suite 419/419; session-rules-loader 31/31; browser-snapshot-credential-guard 38/38; C4 4/4 (+model.likec4.json regenerated); lint-legal-registers 11/11 + unit; plugin-root-anchoring 26/26; guard-vacuity-floor 23/23; credential-path-literals --changed clean; components.test.ts 1331 pass. Dogfood config verified untriggered by new refusals (chromiumSandbox: true, no contextOptions).

## Ship / post-merge (2026-09-18)
- **PR #8275 MERGED** — squash `0bb97c229` on `main` at 16:37:50 UTC (auto-merge, merged by deruelle). Required checks all green on head `250086e0b`; the one red check was non-required and environmental (`deploy-script-tests` AC6: repo pin `v1.1.35` vs `vinngest-v1.1.37` published mid-flight by #8248 — repo-wide drift, unrelated to this diff).
- **Post-merge workflows on `0bb97c229`: 12/12 settled — 11 success, 1 conditional skip** (Follow-through closure guard: no callback URL). Web Platform Release, Version Bump and Release, CI, vendor-pin-verify, Tenant integration, secret-scan, skill-security-scan ×2, Deploy Documentation, CodeQL ×2 all success.
- **Hosted vendored exclusion verified in the real run** (Web Platform Release `35369612030`): the vendor step executed `cp -a --no-dereference plugins/soleur "$DEST"` then `rm -f "$DEST/.mcp.json"`; 1086 files vendored; docker build proceeded from that context — the hosted agent-runner image bakes a plugin tree with no plugin-root `.mcp.json`.
- **Release cut**: `v3.278.17` tagged AT the merge commit (`0bb97c229`); `git show v3.278.17:plugins/soleur/.mcp.json` carries the intended registration (python3 + `${CLAUDE_PLUGIN_ROOT}` proxy + `--user-data-dir-name soleur-playwright-mcp-profile` + `npx @playwright/mcp@0.0.78`). `web-v0.276.19` also cut at 17:00 UTC.
- **Open residual (as designed)**: customer-owned `mcp__playwright__*` registrations remain unwrapped; closer tracked at #8286. #8172/#8228 Devin Cloud residuals untouched by this ship.

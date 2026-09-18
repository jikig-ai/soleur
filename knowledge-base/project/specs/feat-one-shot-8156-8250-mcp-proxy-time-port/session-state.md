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

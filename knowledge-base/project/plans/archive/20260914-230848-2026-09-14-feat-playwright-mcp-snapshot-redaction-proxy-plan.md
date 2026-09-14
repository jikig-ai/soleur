---
title: "P7 on the Playwright-MCP path: a redacting stdio proxy for browser_snapshot"
date: 2026-09-14
slug: feat-playwright-mcp-snapshot-redaction-proxy
branch: feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy
issue: 7980
closes: [7980]
type: security
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); no `spec.md` exists for this branch (the one-shot path entered `plan` directly).

Property P7 — the browser-snapshot credential guard holds without the acting agent
having to remember it — is achieved on the `agent-browser` Bash path by the PreToolUse
interceptor from #7947 and is not achieved on the Playwright-MCP path. This plan
closes that residual with a runtime control on the MCP transport itself: a stdio
JSON-RPC proxy declared in `.mcp.json` that launches the real Playwright MCP server,
relays every message, and rewrites the text of every tool result through the existing
redactor's predicate before the model sees it. The proxy withholds a result when it
cannot redact; it never forwards a raw tree. The three design questions the issue left
open are resolved here, recorded as an addendum to ADR-213, and the Article 30
register brackets at PA-8 §(g) and PA-31 §(g) are re-appended to say the residual is
closed on the registration this repository controls and what remains open elsewhere.

## Enhancement Summary

**Deepened on:** 2026-09-14 (same session as the plan; headless one-shot path).
**Sections enhanced:** Behaviour B2/B4/B5/B6/B8/B9/B10, Research Reconciliation, residuals, Phase 0/1/3, Guard 1 (rows 32–39 + instrument rows), Guard 2, Observability, Acceptance Criteria (FR2b, FR5, FR7b, FR14, FR22), Edge Cases, learnings citations, the plan-time probe record (corrections appended).
**Research agents used:** verify-the-negative sweep (14 claims, all confirmed at source), post-edit self-audit (11 consistency fixes applied), security-sentinel (bypass search against the pinned bundle), test-design-reviewer (Farley scoring, 5 edits applied), observability-coverage-reviewer (4 findings applied), git-history-analyzer (every `#N`, ADR and learning path verified live), framework-docs-researcher (Python `selectors`/`os.read`/`killpg`/`_exit`, MCP 2025-11-25 stdio + tools schema, Claude Code `.mcp.json` semantics, `@playwright/mcp` options — all confirm), learnings pass (10 files; 4 new citations). The mechanical gates 4.6–4.11 all passed before the fan-out.

### Key Improvements

1. **A second inline tree path found and covered:** `browser_find` emits matched tree lines and bypasses `--snapshot-mode`; the "exactly one path" claim was corrected in the plan, the probe record and the register text, and a must-REDACT row (P7, row 39) now proves Q1's "by shape, no tool-name allowlist" against it.
2. **Two more raw sinks refused at startup:** `DEBUG` matching `*`/`pw:mcp*` and `DEBUG_FILE` make the server print every unredacted result on the inherited stderr that Claude Code persists; the config the server will actually load (`--config`, else `$PLAYWRIGHT_MCP_CONFIG`) is read for `saveSession`.
3. **The suite can now fail:** sentinels split (`ZZQP-SENTINEL-7980` credential-only, `ZZQP-BENIGN-7980` benign), a known-negative passthrough relay as the pre-fix artefact for QG5, stub self-tests, a `FAKE_PW_HOLD` mode so the group-kill rows exercise SIGKILL-after-grace, P6's population pinned with a floor, and rows for the cap (32), "never quotes input" (33), the `except` arm (34), and the line cap (37).
4. **Every failure arm is visible in the durable artifact:** a pinned stderr vocabulary (B9) that every refusal/withhold/drop/teardown writes and the suite greps; the fleet flag gets a `zero-screenshots` `warnSilentFallback` because the Sentry cron monitor is liveness, not success.
5. **Hostile-page hardening:** whole-line `startswith` for the drift arm (a page cannot pin the tool by embedding the substring), a 64 MiB line cap with pending calls answered `oversize`, no directory or path named in reasons, and client list lines dropped.

### New Considerations Discovered

- `isClose` never reaches the wire (deleted server-side); the whitelist keeps it harmlessly and the Phase 0 row expects its absence.
- Non-tree disk sinks the server writes without agent action (console logs, screenshot PNGs, downloads, opt-in `devtools` tracing, `pdf`) and prose the predicate is inert on (`- Page URL:` with magic-link tokens, titles, dialog messages, link hrefs) are named residuals in the plan, the ADR addendum and the PA-8 bracket.
- `browser_network_request` returns `Cookie`/`Authorization` headers and, on request, the submitted form body — named precisely rather than as "values the agent extracts".

## Research Reconciliation — Spec vs. Codebase

Every row below was measured at plan time against the pinned `@playwright/mcp@0.0.78`
(playwright-core 1.62.0-alpha) over raw stdio, with no Claude Code in the loop. The
captures are in
`knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/plan-time-probe-record.md`
and are the source of the Phase 1 fixtures.

| Issue / prior-art claim | Reality (measured or read at source) | Plan response |
|---|---|---|
| "pipes `browser_snapshot` tool responses through the redactor" — the tree arrives in the snapshot tool's response. | Two tools inline tree lines: a **bare** `browser_snapshot` (`### Snapshot` + a ```` ```yaml ```` fence) and `browser_find`, which calls `page.ariaSnapshot({mode: "ai"})` directly and emits the matched tree lines under `### Result`, bypassing `--snapshot-mode` entirely (security review, deepen pass) — both are covered by SHAPE, which is why Q1 is whole-server. `browser_navigate` / `browser_click` / every action tool, and `browser_snapshot` **with** `filename:`, write the RAW tree to disk (`<output-dir>/page-*.yml` or the named file) and return `- [Snapshot](<path>)`. Confirmed in `Response._build` for both 0.0.78 and the fleet's 0.0.75 (probe record rows 1, 3, source cross-check). | The proxy redacts the inline path by SHAPE on every tool result (no tool-name allowlist), and closes the disk sink on the two paths that write it: it appends `--snapshot-mode none` to the child argv (measured: last flag wins; action tools then write nothing and explicit snapshots stay inline — row 6) and refuses `browser_snapshot` calls carrying `filename:`. A result that still carries a `- [Snapshot](` link is withheld as drift. |
| "pipe through the existing redactor" — reuse the CLI as-is. | The CLI's `main()` locates the first `{` in its input and fails closed when the tail does not parse; a `browser_evaluate` object result is refused at exit 2 (`Extra data`) — row 4. Its JSON arm is agent-browser `--json` envelope plumbing, not the predicate. | Design question 3 resolves to **in-process**: the proxy loads `redact-a11y-snapshot.py` with `importlib.util.spec_from_file_location` and calls `redact_text` — the one predicate, the one file the hook anchors on, no copy. The CLI file gets a small provider-contract edit (public `looks_like_a11y_tree`, `__all__`, docstring — Phase 4.4), not a predicate change. |
| "an `.mcp.json` stdio proxy … one predicate for both surfaces, not a second drifting copy." | `.mcp.json` on main execs `npx @playwright/mcp@0.0.78 --config=.claude/playwright-mcp.config.json` inside a `bash -c` wrapper that also reaps orphan servers (`pkill … [b]in/playwright-mcp …$prof`) and forces X11 at the environment level. No proxy exists anywhere in the repo; the only MCP-shaped script is `pencil-mcp-adapter.mjs`, a full SDK server, not a relay. | Keep the wrapper verbatim (its pkill pattern still matches the child, whose argv keeps `--user-data-dir=$prof`), insert the proxy between `exec env …` and `npx`, and add a sibling `pkill` for a stale proxy. |
| "Recorded … at PA-31 §(g) with four pinned re-evaluation triggers" and "the register bracket at PA-8 §(g) is updated" (Done when). | Verified: PA-8 §(g) (`article-30-register.md`, the bracket beginning `**[2026-09-09 (#7947): credential rendering at the browser-automation boundary`) ends "deferred and tracked at #7980"; PA-31 §(g) carries (t1)–(t4) and the sentence "this cell must be re-appended, never edited". | Both cells get a dated bracket APPENDED (never edited); PA-31's triggers stand and (t1) gains its remedy. |
| ADR-213 Alternatives: "A PostToolUse hook that redacts snapshot output — structurally impossible." | Confirmed in `.claude/hooks/README.md` §PostToolUse: these run after the tool's write and cannot block or rewrite output. The stdio proxy is not in the rejected set; ADR-213 §Consequences names it as the deferred closer. | Addendum to ADR-213, not a new ADR — this is the fourth control of the same decision, with the same predicate. |
| The corpus lint's S2 rule requires the literal disclosure "no runtime guard on the Playwright-MCP path" in any plugin file that prescribes `browser_snapshot` in an authentication context (`scripts/lint-credential-path-literals.py`, `MCP_GAP_MARKER_RE`); five plugin files carry it (one wrapped across a line, undercounted by a literal grep). | After this PR that sentence is FALSE on every registration routed through the proxy and still TRUE on an unwrapped one. A lint that keeps enforcing an unconditional false claim is the defect class ADR-213 records ("a false property claim is worse than none"). | The marker becomes a CONDITIONAL disclosure the agent conditions on at runtime (the prose prescribes the file form first; the proxy's refusal of `filename` is the structural signal that the registration is wrapped, the `browser_snapshot` description carries an optional pre-call hint, and every tree-carrying result carries a post-hoc trailer), the recipe and the four files move in the same commit, and the lint's own suite gains a RED row for the old sentence alone. |
| The plugin protects "a Soleur operator". | `plugins/soleur/.claude-plugin/plugin.json` registers four HTTP servers and NO Playwright server; the plugin cannot wrap a server it does not register. The hosted agent-runner registers only `soleur_platform`; the cron fleet writes its own per-fire overlay (`cron-ux-audit.ts`, `@playwright/mcp@0.0.75`) that grants no `browser_snapshot`. | Reach is stated per surface, not implied: P7 holds on every registration routed through the proxy — this repo's `.mcp.json` today. The proxy ships in the plugin; the documented `.mcp.json` shape is a one-time configuration, not per-call memory. A plugin-registered, pre-wrapped server is a deferred capability with its own issue (see Deferrals). |
| The issue's stated fixtures came from the surface (ADR-213 round-3 lesson). | Claude Code persists every MCP server's stderr to `~/.cache/claude-cli-nodejs/<project>/mcp-logs-<server>/<ts>.jsonl` (row 9). `.mcp.json` edits load only on a full Claude Code restart, never on `/mcp` reconnect (learning 2026-07-18 in `.claude/playwright-mcp.config.json`). | The refuse-to-start arm cites that log as its durable layer-7 artifact. Verification drives the proxy directly over stdio, so no Claude Code restart is in the loop. |

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 7980`: OPEN, `priority/p1-high` + `domain/engineering` + `type/security`, no closing PR. PR #7975 (merged, closes #7947 only) shipped the redactor + hook + lint and filed #7980 as its residual; it touched no MCP file. Premise holds.
- `.mcp.json` on this branch execs `npx @playwright/mcp@0.0.78` directly — no wrapper. Holds.
- `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py` exists (400 lines), exposes module-level `redact_text`, `MAX_INPUT_BYTES = 4 MiB`, `REDACTED`, guards `main()` behind `__name__ == "__main__"` — importable without side effects. Holds.
- `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` exists and its header states the MCP gap. Holds.
- ADR-213 exists with three addenda; §Consequences names the deferred proxy. Holds.
- `@playwright/mcp` README/`config.d.ts`: `secrets` "is a convenience and not a security feature" — quoted verbatim from the pinned package. Holds.
- Mechanism-vs-ADR-corpus: grep of `decisions/` for `proxy`, `stdio`, `MCP` — ADR-213 is the only hit that touches this mechanism, and it defers rather than rejects it. ADR-162 (one PreToolUse rewriter) is not engaged: the proxy is not a hook. ADR-179 (`${CLAUDE_PLUGIN_ROOT}` bare, quoted) constrains any SKILL.md reference to the proxy. ADR-095 (fail-closed: exit 2, stdout empty, reason never quotes input) is the contract the proxy inherits.
- Stale prefix noted, not in scope: `reproduce-bug/SKILL.md` names `mcp__plugin_soleur_pw__browser_*`, a rebranding-era relic for a server the plugin never ships. Recorded under Deferrals as an observation for the S2-file edit to correct in passing.

### Property List and Cut List (Phase 0.6b)

Properties:

- **P7-MCP** — on a Playwright-MCP registration routed through the proxy, no accessibility tree reaches the model or the workspace disk with a credential-shaped value in clear, and no agent action is required for that to hold.
- **P-FC** — when the redaction cannot be performed (redactor missing, predicate broken, oversize result, exception, drift in the server's response shape), the raw tree is withheld and the failure is visible to the agent and in a durable log; the proxy never silently degrades to pass-through.
- **P-ONE** — the predicate applied on the MCP path is the same object the Bash path uses (`redact_text` from `redact-a11y-snapshot.py`), verified behaviourally (byte-equal output on a shared fixture) and structurally (the proxy defines no credential pattern of its own).
- **P-TRUTH** — every shipped instruction and record that states the MCP-path reach is true on every surface it runs on: the corpus lint enforces the conditional disclosure, ADR-213 and the register carry the new reach, and the agent can tell at runtime which case it is in.

Mechanisms the ask names → property → prior coverage:

| Mechanism | Buys | Already covered on `origin/main`? |
|---|---|---|
| `.mcp.json` stdio proxy | P7-MCP, P-FC | No. `git grep -n "PostToolUse" .claude/hooks/README.md` — PostToolUse cannot rewrite output; `git grep -n "updatedInput" plugins/soleur/hooks/` — the one rewriter is `grep-rewrite.sh` (ADR-162) and a PreToolUse rewrite of `browser_snapshot` args to force `filename:` would only move the leak to disk. `--secrets` (config) masks values named in advance only. |
| Reuse of `redact-a11y-snapshot.py` | P-ONE | The file exists; nothing loads it as a module today. |
| ADR-213 amendment | P-TRUTH | ADR-213 states the gap; nothing states the closure. |
| Register PA-8 / PA-31 update | P-TRUTH | Both cells state the gap; append-only convention. |

Cut list: **none of the named mechanisms is cut.** Two mechanisms the ask did not name were considered and cut before research: (a) a kill-switch env var mirroring `SOLEUR_DISABLE_SNAPSHOT_GUARD` — buys nothing that editing one's own `.mcp.json` does not, and adds a silent fail-open vector; (b) an in-place rewrite of the `page-*.yml` file the server writes after action tools — dissolved by appending `--snapshot-mode none`, which removes the write entirely (row 6).

### Relevant files (all verified on this branch)

- `.mcp.json` — the surface being wrapped; `bash -c` wrapper with orphan reaper + X11 forcing; comment in `.claude/playwright-mcp.config.json` `_regression_2026_07_18` records that edits load only on full restart.
- `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py` — `redact_text(text) -> str` (line-based, bullet-anchored), `_looks_like_a11y_tree`, `MAX_INPUT_BYTES`, `REDACTED = "<redacted>"`, `die()` exit 2. Docstring lists "every node on the Playwright-MCP runtime path" as a stated bypass — comment becomes stale and is edited.
- `plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh` — the 61-row suite; shape to mirror (`ok`/`bad` helpers, instrument self-test, helper controls, `MIN_ASSERTIONS` bound adjacent to the floor block so `scripts/guard-vacuity-floor.test.sh` can construct its mutant).
- `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` — header comment "P7 … NOT achieved on the Playwright-MCP runtime path, where the interceptor is deferred" becomes stale and is edited (comment only; its suite `.claude/hooks/browser-snapshot-credential-guard.test.sh` is envelope-driven and unaffected).
- `scripts/lint-credential-path-literals.py` — `MCP_SNAPSHOT_RE`, `AUTH_CONTEXT_RE`, `MCP_GAP_MARKER_RE`, `S2_RECIPE`, `scan_snapshot_rule`; suite `scripts/lint-credential-path-literals.test.sh` (row M5 comment says "The MCP interceptor is deferred"). Backs the required `credential-path-guard` check.
- Files carrying the S2 disclosure today: `plugins/soleur/skills/qa/SKILL.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`, `plugins/soleur/skills/review/references/review-e2e-testing.md`, `plugins/soleur/skills/ux-audit/SKILL.md`. Files prescribing the `filename:` + redactor + shred form: the first three plus `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md`.
- `apps/web-platform/test/plugin-root-anchoring.test.ts` — `GATE_SCRIPT_RE = /^(?:redact-.+\.(?:sh|py)|digest-scrub\.sh)$/` and an identity set `EXPECTED_GATE_REFS`. The proxy is deliberately NOT named `redact-*` so a repo-relative `.mcp.json` snippet in a SKILL.md does not enter that population; a SKILL.md reference to the proxy therefore needs no row there.
- `scripts/test-all.sh` — auto-discovers `plugins/soleur/skills/*/test/*.test.sh` (the `SUITE_GLOBS` array), so the new suite carries no `run_suite` line.
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — read in full. Modeled: `platform.engine.claude` (Agent Runtime, Claude Code), `platform.engine.hooks` (Hook Engine), `platform.plugin` (Soleur Plugin, L3 components are skills/agents), `connectedRepoPlugin`. NOT modeled: any Playwright MCP server, any browser, the agent-browser CLI, or the stdio MCP transport. C4 edits are in scope (see Architecture Decision).
- `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts` — the C4 gates known at plan-write time; plan review added the fourth, `plugins/soleur/test/c4-model-freshness.test.sh`, which byte-diffs the committed `model.likec4.json`.
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` — the fleet's per-fire `.mcp.json` overlay (`@playwright/mcp@0.0.75`), five granted tools, no `browser_snapshot`; NOT wrapped by this plan.
- `~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl` — Claude Code's persisted MCP stderr (verified).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-09-every-defect-was-in-the-guard-and-my-own-prescribed-command-defeated-it.md` — test the guard against the exact shape agents are steered onto; the prescribed form is the highest-traffic input. Here: fixtures are the real 0.0.78 captures, and the must-PASS rows include the `browser_evaluate` object result that would have broken a subprocess-of-CLI design.
- `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md` — verify the instrument before the measurement: startup predicate self-test; helper controls in the suite; mutations as standalone files asserted landed with `diff -q`.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — mutation matrix written before the code; own-dispatch and second-member rows; harness rows.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-05-playwright-mcp-orphan-server-profile-lock-contention.md` — keep the reaper; the proxy must exit when its child exits or its stdin closes so it never becomes the next orphan; bracket-trick `pkill` pattern for the proxy.
- `knowledge-base/project/learnings/2026-05-12-hyphenated-python-modules-and-plan-precondition-verification.md` — `from redact-a11y-snapshot import` is a parse error; `importlib.util.spec_from_file_location` is the mechanism, and the 1-line import probe is a Phase 0 precondition.
- `knowledge-base/project/learnings/workflow-patterns/2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md` and `knowledge-base/project/learnings/2026-05-15-playwright-mcp-headed-and-persistent-profile.md` — the `env -u WAYLAND_DISPLAY …` forcing and the headed pin are load-bearing; the proxy inherits and passes the environment through untouched.
- `knowledge-base/project/learnings/integration-issues/2026-04-07-bare-repo-mcp-json-not-available.md` — `.mcp.json` is read from the CWD at startup; a worktree carries its own copy, which is why the command uses repo-relative paths.
- ADR-213 round-3 addendum — "a guard's fixtures must come from the surface, not from the author." Applied literally: the plan-time probe record is the fixture source.
- `knowledge-base/project/learnings/2026-09-10-i-graded-lines-when-the-unit-was-the-command.md` — classify by the executed unit, not by grepping a compound shell line: Guard 2 records what the `npx` shim actually received rather than regex-parsing the `bash -c` string.
- `knowledge-base/project/learnings/2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md` — structured errors do not cross a process boundary; tag by a stderr substring: the pinned `playwright-mcp-redact-proxy:` vocabulary in B9 and the Phase 4.2 "find the `refusing to start:` line" sentence.
- `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` — `producer | grep -q` under `pipefail` is a false negative on early match; the suite greps herestrings and files only.
- `knowledge-base/project/learnings/test-failures/2026-07-05-bash-return-contract-change-blast-radius-includes-subprocess-ts-suites.md` — a changed command literal has consumers in other languages' suites; enumerated before Phase 3.1 edits `.mcp.json`.
- `knowledge-base/project/learnings/2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md` and `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — `|| true` + explicit sentinel on optional-fail command substitutions; nounset guards on positionals — suite-authoring constraints for Phase 1.2.

### External references

- MCP specification 2025-11-25 §Transports › stdio: messages are newline-delimited JSON-RPC and MUST NOT contain embedded newlines; a server MAY write logs to stderr; the client closes stdin and terminates the subprocess on shutdown. §Tools: a tool-execution failure is a `result` with `isError: true` and text content; a protocol error is a JSON-RPC `error` object. (Fetched via context7, `/websites/modelcontextprotocol_io_specification_2025-11-25`.)
- `@playwright/mcp@0.0.78` `README.md` / `config.d.ts` (`~/.npm/_npx/…/node_modules/@playwright/mcp`): `--snapshot-mode <full|none>`; `secrets` "is a convenience and not a security feature".

### Scoped advisor consult (Step 4.5, ADR-083, advisor tier)

Verdict: approach sound; two rework-preventing changes, both folded — (1) measure and pin the newline-delimited framing (Phase 0 row 12) and state the pump discipline once (B4: `os.read` into a per-fd buffer split on `\n`, one `write_line` that writes and flushes together); (2) route every synthesized `isError` result through one `error_result` builder (B9, matrix row 22) and bind `_looks_like_a11y_tree` at startup so a renamed helper fails loud at exit 2 instead of silently withholding every result (B2/B3). Smaller notes: the live process-group row is ordered before Phase 4 prose; the drift-arm removal branch and the `instructions` annotation the consult also noted were subsequently CUT at plan review (see Domain Review), so their rows do not exist.

### Research decision (Phase 1.6)

High-risk topic (credential exposure, `single-user incident`) — external research was performed inline: the MCP transport and tools contracts were fetched from the specification, and the pinned server was read at source and driven live rather than reasoned about. No further best-practices fan-out was spawned; the transparent-relay shape is fully specified by the transport contract above and the design is constrained by the measured rows, not by community patterns.

## Problem Statement

An accessibility snapshot serializes the VALUE of input fields. On the Playwright-MCP path the tree
reaches the model inside a tool result, and nothing between the server and the model applies the
credential predicate. The PreToolUse hook cannot see `mcp__playwright__browser_snapshot` (it gates
`Bash`), PostToolUse cannot rewrite output, and `--secrets` only masks values it was told about. So
the surface that leaks BOTH credential classes (the measured worse one) is the surface with no
runtime control, and a non-technical operator has no reason to suspect that "snapshot the page"
prints their password into the transcript.

## Proposed Solution

A single-file, stdlib-only Python 3 transport proxy, shipped in the plugin next to the redactor:

```text
Claude Code ──stdin/stdout (JSON-RPC lines)──▶ playwright-mcp-redact-proxy.py ──pipes──▶ npx @playwright/mcp@0.0.78 … --snapshot-mode none
                                                     │
                                                     └─ importlib-loads redact-a11y-snapshot.py → redact_text()
```

### The three open design questions, resolved

**Q1 — wrap the whole server or only the snapshot tool?** Whole server, transport-level; the
predicate is applied by SHAPE to every `tools/call` text result, with no tool-name allowlist.
Measured: the tree reaches a client-bound message on exactly one code path, but naming that tool is
a standing bet on a name and a version (the redactor already learned this lesson with
`data.snapshot` vs `data.diff`), and `redact_text` is inert on prose (row 5: `browser_navigate`
text comes back byte-identical). The cost is one regex pass per response over kilobytes. Two
non-inline paths write the raw tree to DISK and return a link; those are closed structurally
(injected `--snapshot-mode none`; `filename:` refused) with a belt-and-braces drift arm (a
`- [Snapshot](` link in a result is withheld).

**Q2 — fail open or fail closed?** Fail closed, in three arms, and LOUD in each: (i) at startup,
if the redactor cannot be loaded or its built-in self-test does not redact a sentinel row, the
proxy prints a plain-language reason to stderr and exits 2 before spawning the server — Claude Code
records the failed connection in `mcp-logs-playwright/*.jsonl` and `/mcp` shows the server down;
(ii) per result, any exception, the 4 MiB cap, or a link-shaped result replaces the result with an
`isError: true` text result that names the tool, states why the snapshot was withheld, and never
quotes the input; (iii) at the transport, a dead child ends the proxy with a non-zero exit and a
closed stdin terminates the child. There is no kill switch: one's own `.mcp.json` is the off
switch, and a silent env-var bypass is exactly the fail-open the issue forbids.

**Q3 — in-process or subprocess?** In-process. The proxy loads
`redact-a11y-snapshot.py` by path with `importlib.util.spec_from_file_location` and calls its
`redact_text`. Measured (row 4): the CLI's `main()` JSON-envelope arm refuses a `browser_evaluate`
object result at exit 2, so a subprocess-of-CLI proxy would either over-refuse legitimate results
(whole-server) or need the tool-name allowlist Q1 rejects (snapshot-only). Renaming the CLI to an
importable name or extracting a `_lib.py` was rejected: the filename is the anchor in the hook
(`REDACTOR_ANCHOR`), the lint (`REDACTOR_ANCHOR_RE`), `EXPECTED_GATE_REFS`, ADR-213, the register
and eight SKILL.md prescriptions — a sweep with no property gain. The "one predicate" claim is
enforced by two rows: byte-equal output against the CLI on every tree-carrying fixture, and an AST
walk that finds no `re.*` call, no `def redact_text`, and no string literal the redactor's own
`_is_credential_name` accepts.

### Behaviour, precisely (each item names its implementation site)

| # | Behaviour | Site |
|---|---|---|
| B1 | `python3 playwright-mcp-redact-proxy.py -- <server argv…>`; no `--` or empty argv → usage on stderr, exit 2. | `playwright-mcp-redact-proxy.py:main` |
| B2 | Load the sibling `redact-a11y-snapshot.py` by path; bind `redact_text`, `looks_like_a11y_tree`, `MAX_INPUT_BYTES`, `REDACTED` — ALL FOUR at startup, so a redactor refactor that renames the tree-shape helper fails loud at exit 2 rather than as a per-result `AttributeError` that B6 would "catch" as a withhold of every result (fail-closed but indistinguishable from an outage). The four names are the redactor's declared consumer contract (Phase 4.4 adds `__all__` + a header comment on the provider side and one redactor-suite row importing them, so the contract is tested where it is provided). Any failure → stderr `playwright-mcp-redact-proxy: refusing to start: <reason>`, exit 2, no child. Also refuse to start when the wrapped argv carries `--save-session`, or when the config file the server will actually load (`--config=X` / `--config X`, else `$PLAYWRIGHT_MCP_CONFIG`, read as JSON) sets `saveSession` truthy; and when the environment carries `DEBUG` matching `*` or any `pw:mcp` namespace (the server's `pw:mcp:server:response` debug prints every UNREDACTED result on the inherited stderr, which Claude Code persists in clear) or `DEBUG_FILE` — the reason names the variable, never its value; a silent strip would be the kill-switch class Q2 rejects: that option makes the server append every response, values included, to a `session.md` on disk (`SessionLog.logResponse`), a raw sink no transport rewrite can reach. (`--save-trace` was checked and does not exist in 0.0.78.) | `:load_redactor`, `:refuse_argv` |
| B3 | Self-test: `redact_text('- textbox "Token" [ref=e1]: ZZQP-SENTINEL-7980')` must contain `<redacted>` AND must not contain the sentinel, and `looks_like_a11y_tree` must return True for that row and False for `### Page\n- Page URL: x`; else refuse to start (exit 2). | `:self_test` |
| B4 | Spawn `<server argv…> + ["--snapshot-mode", "none"]` with stdin/stdout piped in BINARY mode, stderr inherited (MCP: server logs on stderr; the proxy never writes to stdout except protocol lines), `start_new_session=True` so the whole `npx → playwright-mcp → chrome` tree is one process group; the child's pgid (`== child.pid` under a new session) is logged to stderr as `playwright-mcp-redact-proxy: child pgid <n>` so the suite reads the group it must assert on. **Single-threaded `selectors` loop** over `sys.stdin.buffer` and `child.stdout` — no threads, no locks, no daemon-thread exit dance (POSIX only; the plugin's `.mcp.json` wrapper is already Linux-only and the SKILL.md says so). **Pump discipline, stated once:** framing is one `\n`-terminated JSON message per line with no embedded newlines and no `Content-Length` header (measured on the pinned server in Phase 0 row 12, not assumed from the spec); reads accumulate raw bytes and split on `\n` only — never a text-mode wrapper; every write goes through one `write_line(bytes)` that does `write` + `flush` together, so a line is never split across two writes. Every loop iteration is wrapped in `try/except BaseException` that writes `playwright-mcp-redact-proxy: pump error: <type>: <msg>` to stderr and continues, so a malformed line can never kill the pump (a dead pump is a silent hang) and never dies silently either. A buffered line exceeding `MAX_LINE_BYTES = 64 MiB` is discarded up to the next `\n` (CWE-400: a hostile page can push a tree toward Node's string limit and an OOM-killed proxy runs no teardown), every pending `tools/call` is answered by `error_result(…, "oversize")`, and the stderr line carries the byte count only. Every stderr line the pumps write about a dropped/unparsable/oversize line carries byte length and id only — never content (ADR-095 applies to stderr too; the jsonl persists it). Reads use `os.read(fd, 65536)` into a per-fd `bytearray` split on `\n` (a `BufferedReader.readline()` after `select` can block on an incomplete line — CPython #101053). | `:spawn_child`, `:write_line`, `:main` |
| B5 | Client→server: forward the ORIGINAL bytes of every line; for a line that parses to a request (`method` and `id`), record `(type(id).__name__, id) → (method, name, arguments)` — EVERY request method, not only `tools/call`, so every later response can be classified by the request that caused it; a new request reusing a pending key deletes the stale entry first. A line that does not parse → forwarded raw + stderr note (the server answers with its own parse error; if the client sent invalid UTF-8 the server's lossy decoder may execute what the proxy could not parse, and the unknown-key drop then withholds the reply — named under Edge Cases). A client line that parses to a LIST → dropped with a stderr note, never forwarded (the SDK's stdio decoder rejects arrays anyway; the proxy must not be the more permissive side). Two request shapes are REFUSED — answered by `error_result` with the request's id, never forwarded, never recorded: (a) `browser_snapshot` whose arguments carry the `filename` KEY (any value, including `""`/`null`, because the server keys on truthiness and the proxy must not); (b) ANY `tools/call` whose `params.arguments` carries a `_meta` key (the protocol-level `params._meta`, e.g. `progressToken`, is NOT refused — only the argument-level hook) — measured at plan time (probe record row 13): `arguments._meta.json: true` makes the server return the tree as ONE JSON-escaped string inside the text block (`{"snapshot": "- generic …\n  - textbox \"Token\" [ref=e6]: ZZQP…"}`), which the line-anchored predicate cannot see, and `_meta.raw`/`_meta.cwd` are the same undocumented hook. The refusal reason names the replacement call literally (`call browser_snapshot with no filename`) and says the file form is only for an unwrapped registration, so an agent on older prose recovers in one turn. | `:pump_client_to_server`, `:refuse_request` |
| B6 | Server→client: decode each line with `errors="replace"` (the TypeScript SDK's `ReadBuffer` is lossy-UTF-8, so the proxy's decoder must be at least as permissive — a strict decoder that raised on one bad byte would forward the tree raw). **Classification:** a JSON object carrying `result` or `error` is a RESPONSE; one without is a server→client request or notification (`roots/list` — the server's ids are an independent counter and can collide with a pending client id) and is forwarded byte-for-byte without touching the map. A response whose key is not pending → DROPPED with a stderr line (the client is not waiting for it; forwarding an untracked `result` raw is the fail-open this rule closes). A response carrying BOTH `result` and `method` → withheld (`unrecognised result shape`). A pending response is popped and dispatched on its request method: `tools/call` → rewrite; `tools/list` → annotate (B7); anything else → forward raw. **Rewrite**, inside ONE `try` that wraps classification and rewrite alike: accept the result only if its shape is one the pinned surface emits — `result` is an object whose keys ⊆ {`content`, `isError`, `isClose`} (`isClose` is real: `browser_close` carries it; `_meta` is NOT accepted — measured, 0.0.78 reads `_meta` from arguments and never emits it), `content` is present and a list of objects, every block's `type` ∈ {`text`, `image`, `audio`}, text-block keys ⊆ {`type`, `text`, `annotations`} with `text` a `str`, image/audio keys ⊆ {`type`, `data`, `mimeType`, `annotations`}. Any other shape — `structuredContent`, an `EmbeddedResource` block, `content` missing or not a list, `result` a string — is withheld with reason `unrecognised result shape`. For an accepted result, rewrite every `text` block: bytes > `MAX_INPUT_BYTES` → withhold; a LINE of `text` starts with `- [Snapshot](` (whole-line `startswith`, so page text containing the substring cannot pin the tool; no regex, FR13 intact) → withhold (drift arm: the raw file the server already wrote is NOT touched — a relay does not delete — and the reason says only "the server wrote a raw file under its output directory; do not read it", naming no path, since the path is server-emitted text); else `redact_text(text)`; any exception (`BaseException`) → withhold. **Every result whose text carries a tree** (`looks_like_a11y_tree`) gets the trailer appended as a NEW final text block `[Soleur: redacted in flight by playwright-mcp-redact-proxy]` whether or not a value changed, so the transcript shows the proxy was on the path (post-hoc only — page content can forge the literal, so it is never a pre-call signal). If anything changed, re-serialize compactly with `separators=(",", ":")` and `ensure_ascii=True` (always encodable — a lone surrogate the server sent as `\udXXX` round-trips as the same escape) and `write_line` the bytes; if nothing changed, forward the original bytes. Pending `error` responses: `error` with no `data` → forward raw; any `data` → withhold (tree lines reach the client only inside `tools/call` results — source cross-check — so this arm buys fail-closed at zero cost). A server line that parses to a JSON LIST → every element that is a response to a pending key is popped and answered with `error_result` (no pending call is left to hang), the line is dropped, stderr line. A line that does not parse at all → dropped with a stderr line (unconsumable by the client either; nothing pending is touched). | `:rewrite_result`, `:classify`, `:withhold` |
| B7 | Pending `tools/list` result: append to the `browser_snapshot` tool's `description` the marker ` [Soleur: output is redacted in flight by the a11y-snapshot redactor; filename is refused — call browser_snapshot with no filename.]` (inside a `try`: on any failure forward the original bytes + stderr note — a missing marker only routes the prose to the `filename` form, which B5 refuses, so the failure is safe). Pending `initialize` result: forward raw, and log `serverInfo.name`/`version` + `protocolVersion` to stderr (`playwright-mcp-redact-proxy: wrapping <name> <version>`) so `mcp-logs-playwright` records what was wrapped. (An `instructions` annotation was cut at plan review: one pre-call signal suffices, and the refusal in B5 is the structural signal.) | `:annotate_tools_list` |
| B8 | Everything else — server→client requests and notifications, responses to non-`tools/call`/`tools/list` requests — is forwarded byte-for-byte. Rationale: tree lines reach a client-bound message only inside a `tools/call` result — via `browser_snapshot` (bare) or `browser_find`, both `tools/call` results (source cross-check, corrected at deepen: two inline paths, not one). | `:pump_server_to_client` |
| B9 | Every client-bound `isError` result the proxy synthesizes — both B5 refusals, every withhold arm — is built by ONE function `error_result(id, tool, reason)`: it preserves the id's JSON type, names the tool, prefixes `snapshot withheld:` or `refused:`, never quotes input, and appends one caveat line: "A screenshot is safe for a masked input (the browser renders dots) and NOT for a panel displaying a freshly-minted value, which renders in clear. A page over the redactor's cap cannot be snapshotted on this path — narrow it with target: or depth:. The filename form is only for an unwrapped registration; behind this proxy call browser_snapshot with no filename." Every literal in the proxy was checked at plan time against the redactor's own `_is_credential_name` (all False), which is FR13's oracle — so the wording above is load-bearing and `type=password` must not appear as a literal. One builder means one vocabulary and one site. It also writes exactly one stderr line per call — `playwright-mcp-redact-proxy: <refused|withheld> tool=<name> id=<id> reason=<reason>` (never quoting input) — so every per-result refusal reaches the persisted jsonl and not only the transcript. **Pinned stderr vocabulary** (the suite greps these literals; nothing else is emitted): `refusing to start:`, `child pgid`, `wrapping`, `refused tool=`, `withheld tool=`, `dropped unknown-id response`, `dropped unparsable server line`, `dropped list line`, `forwarded unparsable client line`, `annotate failed`, `pump error:`, `child exited rc=`, `group <pgid> survived SIGTERM; SIGKILL sent`. | `:error_result` |
| B10 | Lifecycle, all inside the one loop: stdin EOF → close child stdin, then SIGTERM the group, then SIGKILL after a 5 s grace (`GRACE_S = 5`, one constant, cited to the 2026-07-05 orphan learning; Chrome can exceed 5 s on SIGTERM alone); SIGTERM/SIGINT to the proxy → same teardown; child stdout EOF → drain what is buffered, `child.wait()`, flush, `os._exit(rc if rc >= 0 else 128 - rc)` (a signal-killed child has a negative `returncode`; `_exit` avoids the interpreter's own teardown hanging on a pipe). Teardown emits `child exited rc=<n> signal=<s>` and, when the grace expires, `group <pgid> survived SIGTERM; SIGKILL sent`; every stderr write ends in `\n` and `sys.stderr.flush()` runs immediately before `os._exit`. `GRACE_S` is overridable for the suite only via `PLAYWRIGHT_MCP_PROXY_GRACE_S` (a timing knob, not a bypass — it cannot disable teardown). A SIGKILLed proxy (OOM, the wrapper's reaper) runs no handler: the child is then a session leader on its own, and the wrapper's `pkill` lines are the only backstop — which is why Phase 3.1 orders the proxy `pkill` BEFORE the child `pkill`. | `:main`, `:teardown` |

### What the proxy does NOT do (named residuals, restated in ADR + register)

- `browser_take_screenshot` returns an `image` block; the ADR-213 measurement that a screenshot renders a readonly credential panel in clear is unchanged. The `error_result` caveat and the skill prose keep saying so.
- Values the agent deliberately extracts are outside the snapshot mechanism and outside the redactor's stated role set, and the proxy does not read them: `browser_network_request` (a `core` tool) returns request headers — `Cookie`, `Authorization` — and, with `part: request-body`, the submitted form body, i.e. the password the agent just typed; `browser_run_code_unsafe` and `browser_evaluate` return anything the agent asks for (including the `filename` form the 2026-07-18 learning prescribes in `widen-playbook.md`, which writes raw values to disk behind the proxy); all three accept `filename` and none is tree-shaped. `browser_console_messages` likewise. `--secrets` remains the only control there. `### Ran Playwright code` echoes the agent's own `fill('…')` argument — the same exposure class as the tool-call input already in the transcript, not new. The playbook keeps its residual sentence.
- The predicate's own stated bypasses (localised names, non-input roles, segmented inputs) carry over unchanged — same predicate, same ceiling. Prose the predicate is inert on passes in clear: `- Page URL:` (emitted on every navigate even under `--snapshot-mode none`, and a magic link or OAuth redirect carries `?token=` / `code=` / `#access_token=`), `- Page Title:`, `### Modal state` dialog messages (page-authored), and `/url:` children of links.
- Registrations not routed through the proxy — a customer's own `.mcp.json`, the fleet's per-fire overlay — are unchanged by the proxy (the fleet overlay gets `--snapshot-mode none` directly, Phase 3.3). The prose is now truthful on BOTH surfaces by construction: it prescribes the `filename:` + redactor + shred form, and a refusal of `filename` is the structural signal that the registration is wrapped, after which the bare call is the redacted one. The `tools/list` marker is an optional pre-call hint; the per-result trailer is a post-hoc trace. Neither is a verification.
- The drift arm cannot un-write what the server already wrote: when a `- [Snapshot](` link is withheld, the raw file the server produced persists on disk. The proxy does not delete it (a relay does not delete; the path is server-emitted text); the reason names the enclosing directory only. Named in the ADR addendum and the PA-8 bracket. Under the pinned 0.0.78 with `--snapshot-mode none` and the `filename`/`_meta` refusals in place, no code path produces that link — the arm exists for the next bump.
- The disk-sink closure covers the TREE sinks only and is enumerative (`--snapshot-mode none`, `filename` refusal, `_meta` refusal, `--save-session`/`saveSession`/`DEBUG`/`DEBUG_FILE` refusals), bound to the 0.0.78 pin; the drift arm and the Phase 0 re-capture on every bump are the complement. Non-tree disk sinks the server writes WITHOUT agent action remain, named rather than closed: every console message at or above `console.level` goes to `<output-dir>/console-*.log` regardless of snapshot mode (and every action result links it); `browser_take_screenshot` always writes the PNG to disk; downloads land as `download-*.bin`; the opt-in `devtools` capability (`--caps` / `PLAYWRIGHT_MCP_CAPS`) adds `browser_start_tracing`, whose trace snapshots carry input values, and `pdf` renders the panel in clear — Phase 0 asserts the default `tools/list` carries neither `browser_start_tracing` nor `browser_pdf_save`. The default output dir is `<cwd>/.playwright-mcp/` (gitignored, verified). Stated in the ADR addendum so the next bump re-enumerates.

## Technical Approach

### Architecture

Transparent relay; two byte pumps; one rewrite site for results, one for `tools/list`, one refusal
site for requests. No MCP SDK, no dependencies beyond the Python 3 standard library (floor: 3.8 —
the redactor's `from __future__ import annotations` already sets that). The child's stderr is
inherited so Playwright's own diagnostics keep reaching Claude Code's `mcp-logs-playwright` log
untouched; the proxy's own diagnostics are prefixed `playwright-mcp-redact-proxy:` on the same
stream.

### Implementation Phases

#### Phase 0 — Preconditions and measurement (gate; nothing else starts until it is green)

1. Import probe, the one-liner the hyphenated-module learning prescribes:
   `python3 -c "import importlib.util,sys; s=importlib.util.spec_from_file_location('redact_a11y_snapshot','plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m.redact_text('- textbox \"Token\" [ref=e1]: ZZQP-SENTINEL-7980'))"` must print `- textbox "Token" [ref=e1]: <redacted>`.
2. Write the committed capture driver `plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py` (stdlib; args: `<output-dir> -- <server argv…>`; serves the synthesized page itself on `127.0.0.1`, drives the server over stdio, writes one JSON file per captured message, and asserts the framing) and run it against the pinned server (`npx @playwright/mcp@0.0.78 --headless --isolated --output-dir <tmp>`). It must reproduce rows 1–8 of `plan-time-probe-record.md` and add: row 9 — the driver advertises `roots` in `initialize.capabilities` so the server's `roots/list` request is captured (Claude Code advertises roots; a real `mcp-logs-playwright` file on this machine records `Received ListRoots request from server`); row 10 — `browser_close` so the `isClose` result shape is captured; row 11 — one run with a `--config` file pinning `"snapshot": {"mode": "full"}` plus the appended `--snapshot-mode none`, showing the CLI flag wins over the config file (the bundle merges `default → global config → --config → env → CLI`; this row measures it); row 12 — the RAW stdout bytes of the whole session: every message is one `\n`-terminated line, no embedded newline inside a message, no `Content-Length` header anywhere; row 13 — `browser_snapshot` with `arguments: {"_meta": {"json": true}}` returns the tree as ONE JSON-escaped string inside the text block (measured at plan time: 2 newlines in the whole text, sentinel present, `redact_text` cannot see it) and `{"_meta": {"raw": true}}` returns the bare tree — the row that makes B5's `_meta` refusal mandatory. Rows added at deepen: row 14 — `browser_find` with `text: "Token"` returns matched tree lines under `### Result` with the sentinel (the second inline path); row 15 — the default `tools/list` carries neither `browser_start_tracing` nor `browser_pdf_save`; row 16 — `browser_close`: the result reaches the wire WITHOUT `isClose` (the server's `createServer` deletes it before sending — the whitelist keeps the key anyway, harmlessly) and the earlier row-10 expectation is corrected accordingly. The synthesized page puts `ZZQP-SENTINEL-7980` ONLY in the credential-named inputs and `ZZQP-BENIGN-7980` in `Notes` (and a benign address in `Email address`), so a redaction assertion can count both. The captured messages (navigate, bare snapshot, snapshot+filename, snapshot+`_meta.json`, evaluate, close, `tools/list`, `initialize`, the `roots/list` request) land in `plugins/soleur/skills/agent-browser/test/fixtures/playwright-mcp-0.0.78/` as JSON files, sentinel `ZZQP-SENTINEL-7980` retained (synthesized). The suite derives that directory name from the version pinned in `.mcp.json`, so a bump that forgets to re-capture reddens loudly instead of testing stale captures. Record the run in `knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/phase-0-measurement.md`.
3. Reaper discrimination, scoped to the group the suite spawned: launch the proxy with a captured pid, read the `child pgid` line it logs (B4), list that group (`ps -o pid,ppid,args -g <pgid>`), and assert that the row whose args contain `bin/playwright-mcp` carries the profile path (the existing reaper pattern hits it) and is not the proxy's row; that the proxy's own row carries the profile path (the new `[p]laywright-mcp-redact-proxy.py .*$prof` pattern hits it); and that NEITHER pattern matches the `bash -c` wrapper's own command line (it holds the literal, unexpanded `$prof`). Every process assertion in this plan is scoped to a captured pgid — never a machine-wide name match, which a sibling session's browser can flip.
4. Fleet-copy row (CLO finding, PA-31): drive the 0.0.75 copy at `apps/web-platform/node_modules/@playwright/mcp` with the same driver (`node apps/web-platform/node_modules/@playwright/mcp/cli.js --headless --isolated`, no `--output-dir`, from a scratch cwd): record where `browser_navigate` writes the raw `page-*.yml` (expected `<cwd>/.playwright-mcp/`, from `outputDir()` — measure, do not assume), that the sentinel is in it, and that `--snapshot-mode none` is accepted by 0.0.75 (`grep -c 'snapshot-mode'` on its bundle returns 1 at plan time) and stops the write. This row is the citation the PA-31 bracket needs; the register must not cite a bundle read.

#### Phase 1 — Guard contract first: the suite and the stub server (RED)

1. `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py` — a stub MCP server under 80 lines, table-driven: answers `initialize`, `tools/list` and `tools/call` from the fixture directory by default, or from the file named by `FAKE_PW_RESULT_FILE` for the odd shapes (two text blocks, link result, `structuredContent`, `resource` block, `_meta` in result, invalid UTF-8 byte, list-shaped line with two pending results, `error` with and without `data`, `tools/list` without a `tools` key, result with both `result` and `method`) — each odd shape is a fixture file the must-PASS/parity rows can reuse, not a boolean flag. Behaviour flags only where a file cannot express it: `FAKE_PW_ROOTS_COLLIDE=1` (emit a `roots/list` request whose id equals the pending id before the real result), the `filename` write (on `browser_snapshot` with `filename` it WRITES the raw fixture tree to that path, so the refusal arm has something to prove), `FAKE_PW_ARGV_OUT` (records its argv, so `--snapshot-mode none` injection is observable), `FAKE_PW_REQUEST_LOG` (records every request it receives, so a refused call is shown never to have arrived), `FAKE_PW_EXIT_CODE` (exit with that code after the first call, for the exit-code row), `FAKE_PW_HOLD=1` (ignore stdin EOF, trap SIGTERM, hold a `sleep 300` grandchild in the same group — models Chrome — so the group-kill rows cannot pass on a child that merely exits at EOF). Otherwise exits on stdin EOF. Companion fixtures: `fake-passthrough-proxy.py` (the known-negative relay, ~10 lines) and a `MAX_INPUT_BYTES + 1` text block generated at run time. Suite-authoring constraints carried from the learnings: `grep -q` only on herestrings or files (never `producer | grep -q`, learning 2026-07-18 #6992), `|| true` + explicit sentinel on every optional-fail command substitution under `set -euo pipefail` (learnings 2026-04-23, 2026-03-03), and the `.mcp.json` command literal's existing consumers enumerated before Phase 3.1 edits it (`git grep -lE '\.mcp\.json|mcpServers\.playwright' -- '*.test.ts' '*.test.sh'` — at plan time: `.claude/hooks/session-rules-loader.test.sh` reads server KEYS only, unaffected; learning 2026-07-05 bash-return-contract blast radius).
2. `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` — mirrors the redactor suite's shape: `ok`/`bad`, instrument self-test, helper controls (`assert_redacted_result`, `assert_byte_identical`, `assert_withheld`, `assert_refused_start` must each be shown to REJECT), the Guard Contract matrix below driven against the pre-fix stub (every RED row observed RED, recorded in the measurement file), the must-PASS rows, and `MIN_ASSERTIONS` bound adjacent to the floor block. Mutations are standalone `.py` copies of the proxy with one edit each, asserted landed via `diff -q` against the pristine file. Process assertions read the pgid the proxy logs and use `pgrep -g`.
3. One repo-level drift row in the same suite, executable rather than string-shaped: run `.mcp.json`'s `mcpServers.playwright.args[1]` under `bash -c` with `HOME=<suite scratch dir>` (so `$prof` resolves to an empty scratch path and every `pkill`/`rm` line in the prelude matches nothing — running it against the real profile would SIGKILL a sibling session's live browser, the 2026-07-05 incident class) and an `npx` shim first on `PATH` that records its argv and its parent's command line, then assert: the shim's parent is the proxy (`ps -o args= -p $PPID` from inside the shim contains `playwright-mcp-redact-proxy.py` — a pid-anchored check, not a name match over the machine); the recorded argv contains `@playwright/mcp@0.0.78` (a bump forces the Phase 0 re-capture), `--user-data-dir=<scratch>/.cache/playwright-mcp-profile`, `--config=.claude/playwright-mcp.config.json`, and ends with `--snapshot-mode none`.

#### Phase 2 — The proxy (GREEN)

1. `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py` implementing B1–B10; module docstring states P7 reach, the three arms, the enumerative closure, and the residuals, in the same voice as the redactor's header.
2. Suite green; matrix rows re-run against the shipped proxy and observed GREEN; the lifecycle rows (exit-code clamp, stdin EOF, SIGTERM) asserted against the stub's pgid.

#### Phase 3 — Wire the dogfood surface

1. `.mcp.json`: keep the `prof=…` prelude; insert `pkill -9 -f "[p]laywright-mcp-redact-proxy.py .*$prof" 2>/dev/null || true` BEFORE the existing child `pkill` (a SIGKILLed proxy runs no handler, so the child reaper must run after it); change the `exec env … npx @playwright/mcp@0.0.78 …` tail to `exec env … python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 --user-data-dir=$prof --config=.claude/playwright-mcp.config.json`. `.claude/playwright-mcp.config.json` is unchanged in substance; its `_comment` gains two sentences: the proxy is why `snapshot.mode` must not be pinned to `full` here (the appended CLI flag wins, measured — a reader must not "fix" the config into fighting it), and an edit to `.mcp.json` is live only after a full Claude Code restart, never on `/mcp` reconnect.
2. Live verification without Claude Code in the loop (no restart needed): drive `python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 --headless --isolated --output-dir <tmp>` with the capture driver; assert the bare snapshot result carries `<redacted>` for the password and Token rows, the email row in clear and the trailer block; the `filename` and `_meta` calls are refused; navigate writes no `page-*.yml`; `tools/list` carries the marker; and — against the REAL `npx` chain, reading the `child pgid` line — after stdin EOF, separately after SIGTERM to the proxy, and separately after SIGKILL to the proxy followed by the wrapper's reaper lines run with the same `$prof`, `pgrep -g <that pgid>` is empty within 5 s + grace. **Run this live row BEFORE Phase 4's prose is written** — a failure here changes the `.mcp.json` shape, and the prose describes that shape. Record in `phase-0-measurement.md` §Live verification.
3. Fleet overlay (`apps/web-platform/server/inngest/functions/cron-ux-audit.ts`, the per-fire `mcpConfig.mcpServers.playwright.args` array): append `"--snapshot-mode", "none"` after `--user-data-dir=…`, with a comment citing PA-31 §(g) and Phase 0 step 4 (the fleet-copy row). This is the CTO-chosen remedy for the CLO finding that `browser_navigate` (granted to `cron-ux-audit`, which also holds `Read`/`Glob`/`Grep` per its `--allowedTools` string) writes the raw tree of an authenticated bot-session page under the fleet's cwd — one `Read` away from Anthropic-bound content. Not the proxy: the image would need `python3` on the cron path and a second launch shape for a fleet that holds no `browser_snapshot`; the flag removes the write with no new dependency. `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts` today asserts only `toContain("@playwright/mcp@0.0.75")` — add, unconditionally, a whitespace-tolerant row `expect(SUT_SOURCE).toMatch(/--user-data-dir=\$\{playwrightProfileDir\}`,\s*"--snapshot-mode",\s*"none"/)`. The pin test `apps/web-platform/test/playwright-mcp-version-pin.test.ts` is untouched. The Sentry cron monitor is LIVENESS, not success (the file's own comment says so): if the pinned 0.0.75 rejected the flag, the MCP server would fail to connect, `claude -p` would still exit 0, and the audit would run with zero screenshots at a green monitor — the only trace is the `logger.info({ screenshotCount })` line next to the upload step, which Vector's WARN+ filter drops. So the same edit adds ONE line beside that `logger.info`: `warnSilentFallback(new Error("cron-ux-audit captured zero screenshots"), { feature: "cron-ux-audit", op: "zero-screenshots" })` when `screenshots.length === 0` (the helper is already imported in the file), asserted by a `toMatch(/op:\s*"zero-screenshots"/)` row in the same test. Post-merge, `/soleur:postmerge` runs `doppler run -p soleur -c prd -- scripts/betterstack-query.sh --since 24h --grep zero-screenshots` after the first fire (layer 2 pino→Sentry + layer 3 Vector WARN+); it is an observation, not a close criterion for #7980 (the flag is measured on 0.0.75 in Phase 0 step 4).

#### Phase 4 — Teeth alignment: lint, prose, comments

1. `scripts/lint-credential-path-literals.py`: the S2 disclosure changes CLASS — from a statically-true sentence ("no runtime guard on the Playwright-MCP path") to a claim whose truth depends on the registration, which the walker cannot see and only the runtime can settle. The new prescribed disclosure is therefore structural rather than conditional-on-a-lookup: **"Use the `filename:` + redactor + shred form. If the server refuses `filename`, the registration is wrapped by `playwright-mcp-redact-proxy.py` and the bare `browser_snapshot` call is redacted in flight; call it bare for the rest of the session. The refusal is the only signal — never the trailer or any page text, which can be forged."** `MCP_GAP_MARKER_RE` anchors on that claim (whitespace-tolerant, e.g. `refuses\s+`filename`.*redacted\s+in\s+flight`); `S2_RECIPE` prescribes it verbatim and the lint's failure message quotes the canonical sentence so a copy-edit in one file shows the phrase to restore; the old sentence alone must now FAIL S2, and the OLD marker regex is kept in the test suite as a constant so FR17 can assert its absence with the same whitespace tolerance. `scripts/lint-credential-path-literals.test.sh`: M5's comment updated; a RED row for a file carrying only the old marker; a PASS row for the new marker wrapped across a line break; a RED row for a second non-compliant file after a compliant first.
2. The five S2 files (`qa/SKILL.md`, `reproduce-bug/SKILL.md`, `review/references/review-e2e-testing.md`, `ux-audit/SKILL.md`, `cf-token-scope/references/widen-playbook.md` — the fifth already carries the old marker across a line wrap, which is why a literal grep undercounts it): replace the unconditional gap sentence with the structural disclosure above; keep the `filename:` + redactor + shred form as the FIRST prescription (it is safe on an unwrapped registration and refused on a wrapped one — the prose is truthful on both surfaces by construction, and no pre-call lookup is required); add "behind the proxy, call `browser_snapshot` bare **after every action tool** — action results no longer carry a snapshot link"; keep "capture neither on a page displaying a credential" everywhere; keep the `widen-playbook.md` residual that `browser_evaluate` + `filename` writes raw values to disk behind the proxy. Each file also gains the startup-failure sentence (CPO E1): "If the `playwright` server shows as failed in `/mcp`, read the newest `~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl`, find the `playwright-mcp-redact-proxy: refusing to start:` line, and tell the user the reason in plain language; a missing redactor means the plugin install is drifted and must be reinstalled." In `reproduce-bug/SKILL.md`, correct the relic prefix `mcp__plugin_soleur_pw__` to `mcp__playwright__` in the same edit.
3. `plugins/soleur/skills/agent-browser/SKILL.md` §"vs Playwright MCP": add a "Wrapping the server" subsection labelled **dogfood repository only; a customer registration is #8156**, showing the `.mcp.json` shape with the proxy referenced as `"${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py"` (bare, quoted, per ADR-179) followed by one sentence: Claude Code does not expand `${CLAUDE_PLUGIN_ROOT}` inside a project `.mcp.json`, so substitute the installed plugin root there — this repository's own `.mcp.json` uses the repo-relative path because it is the dogfood checkout. Add: the three-arm fail-closed statement; the startup-failure sentence; "the wrapper's `pkill`/`env -u` prelude is Linux-only, the proxy itself is POSIX-portable"; and "an `.mcp.json` edit is live only after a full Claude Code restart — after the merge, verify with `ToolSearch select:mcp__playwright__browser_snapshot` and look for `redacted in flight` in the description". Because the proxy's basename is now in `GATE_SCRIPT_RE` (Phase 4.5), this reference must be `${CLAUDE_PLUGIN_ROOT}`-anchored, which is exactly what `apps/web-platform/test/plugin-root-anchoring.test.ts` asserts. No `description:` change (budget check not engaged).
4. `redact-a11y-snapshot.py` (provider-side contract, small but not comment-only): rename `_looks_like_a11y_tree` → `looks_like_a11y_tree` keeping `_looks_like_a11y_tree = looks_like_a11y_tree` as an alias, add `__all__ = ["redact_text", "looks_like_a11y_tree", "MAX_INPUT_BYTES", "REDACTED"]` with a header comment naming the consumer (`playwright-mcp-redact-proxy.py`) and the reason the contract is declared here; update the docstring's stated bypass ("every node on the Playwright-MCP runtime path" → "a Playwright-MCP registration not routed through `playwright-mcp-redact-proxy.py`"); add ONE row to `redact-a11y-snapshot.test.sh` importing the four names (the contract is tested where it is provided). The 61 existing rows stay green. `browser-snapshot-credential-guard.sh` header: the P7 reach sentence only (comment-only; its suite is envelope-driven and unaffected).
5. `apps/web-platform/test/plugin-root-anchoring.test.ts`: add `playwright-mcp-redact-proxy\.py` to `GATE_SCRIPT_RE` and the row `plugins/soleur/skills/agent-browser/SKILL.md -> playwright-mcp-redact-proxy.py` to `EXPECTED_GATE_REFS` — the proxy IS a gate script and the anchoring rule must apply to it; choosing a non-matching filename to stay out of that population was an evasion the architecture review caught.

#### Phase 5 — Records: ADR-213 addendum, register, C4

1. ADR-213: append `## Addendum — 2026-09-14 (#7980): the Playwright-MCP residual is closed by a transport proxy` with: the three questions and their resolutions (tables, including the plan-review cuts — no `instructions` annotation, no file deletion, no threads — and why), the measured rows that decided them (rows 4, 6, 12, 13), the reach per surface, the residuals, the note that the corpus lint's S2 rule changes class (static disclosure → structural prescription whose truth the runtime settles), and the enumerative-closure statement (`--snapshot-mode none`, `filename`, `_meta`, `--save-session` — bound to the 0.0.78 pin; the drift arm and the Phase 0 re-capture on every bump are the complement). Insert ONE pointer line immediately after the §Consequences paragraph that says the proxy "is deferred": `[Superseded 2026-09-14 — see the #7980 addendum below; the proxy is now the fourth control on the wrapped registration.]` — the original sentence stays verbatim. Status stays `accepted`; no new ordinal is claimed.
2. Register (`knowledge-base/legal/article-30-register.md`), append-only, CLO-reviewed format: same line, same row, one space after the CURRENT cell tail — PA-8: after the `**[2026-09-11 (#7946 / #7993)…` bracket whose tail reads `…tracked at #8090.]**` (NOT after the #8016 bracket, which is mid-cell); PA-31: after `…not Jikigai undertakings about those tools**.**]`; shape `**[2026-09-14 (#7980): <title> — <one-line characterisation>.** … **]**`; superseded sentences quoted verbatim in italics, never edited; pinned-version disclaimer (`@playwright/mcp@0.0.78` / `playwright-core` 1.62.0-alpha; 0.0.75 for PA-31); cite the ADR-213 addendum, the probe record, `phase-0-measurement.md` and the attestation by path; leave `last_reviewed` alone. Reach (a) reads "**declared** in this repository's `.mcp.json` and asserted by an executable suite row" — the row proves the declaration, not a loaded session (`.mcp.json` loads on restart only). **Every claim in both brackets is verified against the shipped body before commit, not against this plan.** The CLO-drafted text to start from, amended for the plan-review cuts (no `instructions` marker; no deletion in the drift arm; `_meta` refusal added):
   - **PA-8 §(g):** `**[2026-09-14 (#7980): the Playwright-MCP residual named in the 2026-09-09 bracket above is CLOSED on the registration this repository controls — and only there.** The superseded sentence is quoted rather than edited: *"The `.mcp.json` stdio proxy that would close it is deferred and tracked at #7980."* `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py` is a stdio JSON-RPC relay declared in this repository's `.mcp.json` in front of `@playwright/mcp@0.0.78`; it rewrites the text of every `tools/call` result through the same `redact_text` the redactor in (i) exposes (loaded by path; the proxy defines no predicate of its own) — by shape, on every tool, because two tools inline tree lines on the pinned version (`browser_snapshot` and `browser_find`, the latter bypassing `--snapshot-mode`), appends `--snapshot-mode none` so no tree is written to disk by action tools, refuses `browser_snapshot` with `filename` and any call carrying an undocumented `_meta` argument (measured: `_meta.json` returns the tree as one escaped string the line-anchored predicate cannot see), refuses to start under `--save-session`, and withholds any result it cannot rewrite (`isError`, reason never quotes input) — fail-closed in three arms, no bypass variable; a proxy that cannot load or self-test the redactor refuses to start. "Redacted in flight" — the runtime marker the proxy appends — means rewritten at the stdio transport boundary, between the server's stdout and the client's stdin, before the model reads the result: a content rewrite, not encryption and not transport security. **Reach, per surface:** (a) this repository's `.mcp.json` — declared there and asserted by an executable suite row (a declaration, not a loaded session: `.mcp.json` loads on restart only); (b) a customer's own registration — the plugin ships the proxy but registers NO Playwright server, so a customer is wrapped only by their own configuration (tracked at #8156), and the plugin's skills prescribe the file form first and treat the proxy's refusal of `filename` as the structural signal that the registration is wrapped (the marker the proxy appends to the `browser_snapshot` tool description is an optional pre-call hint; the trailer it appends to every tree-carrying result is a post-hoc trace) — organisational measures in PA-31 (9)'s sense, not a verification; (c) the hosted agent-runner registers no Playwright server; (d) the Inngest fleet's per-fire overlay is NOT wrapped — see PA-31 §(g). **What remains open, restated rather than implied:** `browser_take_screenshot` returns image content and still renders a readonly credential panel in clear — unchanged; values an agent deliberately extracts are outside the snapshot mechanism and outside this control — `browser_network_request` returns request headers and, on request, the submitted form body; `browser_evaluate` / `browser_run_code_unsafe` return what they are asked for; console messages, screenshots (always written to disk) and downloads are non-tree sinks the server writes without agent action; URL query/fragment tokens, page titles and dialog messages are prose to the predicate; the redactor's own stated bypasses (localised names, non-input roles, segmented inputs) carry over — same predicate, same ceiling; and when the drift arm withholds a link-shaped result, the raw file the server already wrote persists on disk — the proxy does not delete it, and no code path of the pinned version produces that link once the flag and refusals are in place. The `--snapshot-mode` and result-shape behaviours cited are dated observations of `@playwright/mcp@0.0.78` (`playwright-core` 1.62.0-alpha), not undertakings about those tools. Decision: ADR-213 addendum 2026-09-14; measurement: <probe record path>, <phase-0-measurement path>; attestation: <audit path>.**]**`
   - **PA-31 §(g):** `**[2026-09-14 (#7980): the fleet overlay is NOT wrapped, one finding above is narrowed, and (t1)'s remedy is named.** The proxy recorded at PA-8 §(g) is declared in the repository's `.mcp.json`; `cron-ux-audit` writes its own `.mcp.json` per fire (`@playwright/mcp@0.0.75`) and does not route through it. (t1)–(t4) stand; (t1)'s remedy is now named: granting `browser_snapshot` to any member requires that member's per-fire overlay route through `playwright-mcp-redact-proxy.py` first. **Narrowed, with the superseded sentence quoted:** *"the Playwright-MCP residual named at PA-8 §(g) is not live on this Activity today."* That rested on no member holding `browser_snapshot`. Measured on the pinned 0.0.75 (<phase-0-measurement path>, Phase 0 step 4, the fleet-copy row): `browser_navigate`, which `cron-ux-audit` holds, does not inline the tree but WRITES it raw to `<measured path>` and returns a link, and the member holds `Read`/`Glob`/`Grep` — so the tree of an authenticated bot-session page was one `Read` away from Anthropic-bound content, within measure (8)'s stated absence of any scrub. Remedy in this change: `--snapshot-mode none` appended to the overlay argv in `cron-ux-audit.ts`, measured on 0.0.75 to stop the write. Dated observation of the pinned 0.0.75, not an undertaking.**]**`
3. C4 (see Architecture Decision): `model.c4` adds `playwrightMcp` (external system) and `platform.plugin.snapshotGuard` (component, whose description states the plugin SHIPS the proxy while only this repository's `.mcp.json` WIRES it — `plugin.json` registers no Playwright server, #8156); `views.c4` includes both in `components`, and `playwrightMcp` in `containers` AND `context` (every other external system is in the L1 view, and this is the L1 trust boundary the feature introduces; edges derive to `platform`, so no disconnected box — #7332). Regenerate the tracked `knowledge-base/engineering/architecture/diagrams/model.likec4.json` via `scripts/regenerate-c4-model.sh`. FOUR C4 gates run green: `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` (new edge prose must avoid an "Of N …"/"one of ten …" clause shape) and `plugins/soleur/test/c4-model-freshness.test.sh` (byte-diffs the committed JSON against a render — the one that actually reds on this change).
4. The prior attestation `knowledge-base/legal/audits/2026-09-counsel-review-7947.md` pins "#7980 lands" as a re-evaluation trigger. So, after Phases 2–4 are green and against the SHIPPED body: invoke the `clo` agent inline to write `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` (precedent shape: `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`), and add a row under `## Completed Compliance Work` in `knowledge-base/legal/compliance-posture.md` plus its `last_updated` bump. No SKILL.md or ADR sentence may read as a Jikigai safety undertaking — reach statements stay in the "on a registration routed through the proxy" form (#7981's under-inclusion reasoning survives this PR; `Ref` only).

#### Phase 6 — Verification

1. Full suites: `bash scripts/test-all.sh` scripts shard (new suite auto-discovered), `python3 scripts/lint-credential-path-literals.py` with NO arguments (the parser keeps only `.md` files; a directory argument scans zero files and exits 0 — the bare invocation is what CI runs) asserting `scanned file(s)` > 0, `python3 scripts/lint-guard-contract.py <this plan>`, the four C4 gates, `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts test/server/inngest/cron-ux-audit.test.ts`.
2. PR body `Closes #7980` and `Ref #7981`; state that Phase 3.3 (the fleet overlay flag) is a CLO finding folded in, outside #7980's literal scope, at two argv strings.

## Files to Create

- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`
- `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py`
- `plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py` (the committed capture driver every `@playwright/mcp` bump re-runs)
- `plugins/soleur/skills/agent-browser/test/fixtures/playwright-mcp-0.0.78/{navigate,snapshot,snapshot-filename,snapshot-meta-json,find,evaluate,close,tools-list,initialize,roots-list-request}.json` plus the odd-shape fixture files Phase 1.1 names and `fake-passthrough-proxy.py`
- `knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/phase-0-measurement.md`
- `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` (written by the `clo` agent, Phase 5.4)

## Files to Edit

- `.mcp.json`
- `.claude/playwright-mcp.config.json` (two comment sentences)
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` (two argv strings + comment), `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts` (one unconditional row)
- `apps/web-platform/test/plugin-root-anchoring.test.ts` (`GATE_SCRIPT_RE` + one `EXPECTED_GATE_REFS` row)
- `knowledge-base/legal/compliance-posture.md` (Completed row + `last_updated`)
- `scripts/lint-credential-path-literals.py`, `scripts/lint-credential-path-literals.test.sh`
- `plugins/soleur/skills/qa/SKILL.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`, `plugins/soleur/skills/review/references/review-e2e-testing.md`, `plugins/soleur/skills/ux-audit/SKILL.md`, `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md`
- `plugins/soleur/skills/agent-browser/SKILL.md`
- `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py` (public `looks_like_a11y_tree` + alias, `__all__`, contract comment, docstring) and `plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh` (one contract row)
- `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` (comment)
- `knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `knowledge-base/engineering/architecture/diagrams/views.c4`, `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)

Not edited: `plugins/soleur/.claude-plugin/plugin.json` (no server registered there; see Deferrals, #8156), `plugins/soleur/hooks/hooks.json` (the proxy is not a hook), `apps/web-platform/test/playwright-mcp-version-pin.test.ts` (the fleet's version pin is unchanged), `docs/legal/**` (#7981 stays `Ref` only — folding an AUP edit would engage the five `docs/legal/**` gates and the `BODY_EQUIVALENCE_DOCS` enrolment, per CLO).

## Alternative Approaches Considered

| Alternative | Property it targets | Why not |
|---|---|---|
| Redact only `browser_snapshot` results (tool-name allowlist) | P7-MCP | A name is a standing bet; the redactor already paid for that bet once (`data.snapshot` vs `data.diff`). Shape-based costs nothing extra and is inert on prose (row 5). |
| Shell out to the redactor CLI per result | P-ONE | Measured: the CLI refuses a `browser_evaluate` object result at exit 2 (row 4). Whole-server + CLI over-refuses; snapshot-only + CLI needs the allowlist above. |
| Rename the CLI to `redact_a11y_snapshot.py` or extract `_lib.py` | P-ONE | The filename is the anchor in the hook, the lint, `EXPECTED_GATE_REFS`, ADR-213, the register and eight SKILL.md files; a sweep with no property gain and a 61-row suite to re-anchor. The consumer contract is declared on the provider instead (Phase 4.4). |
| Strip `filename:` and forward as a bare call (DHH) | ergonomics | The refusal IS the structural signal the prose relies on ("if the server refuses `filename`, you are wrapped"); stripping would make an unwrapped-vs-wrapped registration indistinguishable to the agent. Kept, with a one-line reason. |
| Honour `filename:` by redacting inline and writing the file ourselves | token economy on huge pages | Adds path validation and file writing to a guard for a use no skill has today. Refusal is five lines and teaches; revisit if a real large-page need appears. |
| Rewrite (or delete) the `page-*.yml` the server writes | disk sink | Dissolved by `--snapshot-mode none` (row 6). A contained `os.remove` in the drift arm was drafted and cut at plan review: a relay does not delete, the path is server-emitted text, and the file cannot be un-leaked once written — withhold and name the directory only. |
| Annotate `initialize.instructions` as a second pre-call signal | P-TRUTH | Cut at plan review (DHH + code-simplicity): one pre-call signal (the tool description) plus the structural refusal suffices; a second site is a second vocabulary to keep in sync for no property gain. |
| Two pump threads with locks | transport | Cut at plan review: a single `selectors` loop needs no stdout lock, no map lock, no daemon-thread `_exit` dance; the wrapper is Linux-only already and the proxy stays POSIX-portable. |
| PreToolUse hook on `mcp__playwright__browser_snapshot` rewriting args to force `filename:` | P7-MCP | Moves the leak from the transcript to disk; ADR-162 permits one rewriter and `grep-rewrite.sh` holds it. |
| Kill-switch env var like the hook's | ergonomics | One's own `.mcp.json` is the off switch; an env var is a silent fail-open vector on a control whose whole point is not depending on memory. |
| Register a pre-wrapped Playwright server in `plugin.json` | P7 for every customer | Changes the tool prefix every skill names, collides with an existing `playwright` entry in a user's own config, and spawns `npx` on every customer session. Deferred as #8156 (p1, Phase 4). |
| New ADR instead of an ADR-213 addendum | P-TRUTH | Same decision, same predicate, fourth control; ADR-213 already carries three dated addenda and names the proxy as the deferred closer. A pointer line at the superseded sentence keeps the record honest in place. |

## User-Brand Impact

- **If this lands broken, the user experiences:** one of three things. (a) Fail-closed per result: `browser_snapshot` returns "snapshot withheld: <reason>" instead of a tree and the browser workflow stalls until the reason is acted on. (b) Fail-closed at startup: the proxy refuses to start, the `playwright` server shows as failed in `/mcp`, and every Soleur browser skill (qa, reproduce-bug, ux-audit, review-e2e, cf-token-scope) is dead for the session while the only reason sits in a jsonl log the founder will not open — mitigated by the skill prose in Phase 4 that tells the agent where the reason is and how to say it in plain language. (c) The forbidden case this plan's matrix exists to make impossible: a snapshot that LOOKS redacted while a row is not — a green-looking transcript with a password in it.
- **If this leaks, the user's data (credentials) is exposed via:** the founder's password, a freshly-minted API token or a 2FA code rendered in clear into the tool result — which is transmitted off the founder's machine inside the model request before any redaction can occur — and then persisted in the Claude Code transcript (`~/.claude/projects/…`), in any shared session, and in any file the agent writes the result to; this is the one surface that leaks both credential classes. A customer whose own `.mcp.json` is not wrapped receives no new protection from this PR; their exposure is unchanged from today (Deferrals, #8156).
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: **approved with edits** at plan time (2026-09-14; edits E1–E4 applied — the startup-failure prose, the after-every-action prose, this section's rewrite, and the deferral's milestone/priority); `user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: the proxy is on the path — a `filename` call is refused (the structural signal the
        prose relies on), every tree-carrying result ends with the trailer block
        `[Soleur: redacted in flight by playwright-mcp-redact-proxy]` (post-hoc, transcript
        trace), the `browser_snapshot` description carries the marker (optional pre-call hint),
        and the suite's executable `.mcp.json` row asserts the wrap survives edits
  cadence: every refused/rewritten result, and every CI run (executable row, scripts shard)
  alert_target: the agent transcript (no refusal on `filename` → unwrapped registration → the
        prose's file form applies) and the required `test` check (row RED)
  configured_in: plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh

error_reporting:
  destination:
    - "Observability layer 7 (cli-stdout-artifact): the proxy runs on the customer's or
       dogfooder's own machine inside Claude Code. The synchronous signal is the tool
       result the agent renders (`isError` text beginning `### Error` / `snapshot withheld`)
       and the proxy's stderr line prefixed `playwright-mcp-redact-proxy:`. The durable
       artifact is Claude Code's own persisted MCP log,
       `~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/<ts>.jsonl`, which
       records `Server stderr:` lines and `Connection failed` events (verified on this
       machine at plan time). The artifact is local to the customer's machine (not committed, not shipped) —
       accepted for a transport proxy that cannot commit — and is read by
       `ls -t ~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl | head -1`
       + `grep 'playwright-mcp-redact-proxy:'`, the same two commands Phase 4.2's
       startup-failure sentence prescribes; every refusal, withhold, drop and teardown
       event writes one pinned-vocabulary line there (B9). There is no Soleur-side sink by
       design, and this plan adds none. The proxy is NOT loaded on the hosted path: the agent-runner registers only
       `soleur_platform`, and the cron fleet's per-fire overlay is not wrapped (recorded
       at PA-31 §(g))."
    - "CI: layer 6 — the scripts shard log for the new suite, and the required
       `credential-path-guard` check for the corpus lint."
  fail_loud: yes — refuse-to-start exits 2 with a stderr reason; every per-result failure
        is an `isError` result the model must read; there is no pass-through arm.

failure_modes:
  - mode: redactor file missing or not importable in a drifted install
    detection: proxy exits 2 before spawning; Claude Code logs `Server stderr:
        playwright-mcp-redact-proxy: refusing to start: …` and `Connection failed`;
        `/mcp` lists the server as failed; the skill prose (Phase 4.2/4.3) tells the
        agent to read the newest mcp-logs-playwright jsonl, find that line, and say the
        reason in plain language (a missing redactor = drifted plugin install)
    alert_route: layer 7 — cli-stdout-artifact (stderr line + persisted mcp-logs jsonl)
  - mode: predicate drift — the loaded redactor no longer redacts a credential-named row
    detection: startup self-test (B3) fails → refuse to start, same stderr + jsonl trail;
        in CI the suite's parity row (proxy output == CLI output) reddens
    alert_route: layer 7 at runtime; layer 6 in CI
  - mode: a tool result cannot be redacted (exception, > 4 MiB, serialization failure)
    detection: the model receives `isError` text `snapshot withheld: …`; stderr line
    alert_route: layer 7 — cli-stdout-artifact
  - mode: the server writes a tree to disk anyway (flag renamed/ignored on a future bump,
        or a bypassed filename refusal)
    detection: the link-shaped drift arm withholds the result and names the path; the
        Phase 0 live row (`glob(page-*.yml)` empty) reddens on the next bump
    alert_route: layer 7 at runtime; layer 6 on the pinned-version re-probe
  - mode: `.mcp.json` edited back to the unwrapped command
    detection: suite drift row RED in the scripts shard
    alert_route: layer 6 — required `test` check
  - mode: child dies or hangs
    detection: proxy writes `child exited rc=<n> signal=<s>` and exits with the clamped
        code (Claude Code shows the server closed); a hang is the same as today's (the
        proxy adds no timeout and none existed)
    alert_route: layer 7 — persisted mcp-logs jsonl
  - mode: fleet overlay flag rejected or ignored by the pinned 0.0.75 → Playwright MCP
        fails to connect → cron-ux-audit runs with zero screenshots at a GREEN cron monitor
        (the monitor is liveness, not success)
    detection: the new `warnSilentFallback({ feature: "cron-ux-audit", op: "zero-screenshots" })`
        beside the upload step's `logger.info` (Phase 3.3); postmerge query
        `scripts/betterstack-query.sh --since 24h --grep zero-screenshots` after the first fire
    alert_route: layer 2 (pino → Sentry breadcrumb + captureException) and layer 3 (Vector
        WARN+); the Sentry monitor (layer 1) covers only the FATAL class

logs:
  where: stderr → `~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl`
  retention: Claude Code's own (one file per session; not rotated by this plan)

discoverability_test:
  command: bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh
  expected_output: last line `<N> passed, 0 failed, <M> cases` with M >= MIN_ASSERTIONS (the redactor suite's shape; the vacuity floor prints a separate `[FATAL]` line when it fires)
```

## Guard Contract

### Guard 1 — playwright-mcp-redact-proxy (the transport control)

**Property.** No text a Playwright-MCP tool returns through the proxy reaches the client with a credential-shaped input value in clear, and no tree is written to the workspace disk by the wrapped server, on any tool and on every result, without any client-side action.

**Assembly.** The chokepoint is the single `selectors` loop in `playwright-mcp-redact-proxy.py`: every byte the child writes to stdout passes through `pump_server_to_client`, every line that parses to a response is classified by `classify` against the pending map, and a pending `tools/call` response must go through `rewrite_result` before `write_line` — the write site for pending results accepts only `rewrite_result`'s return value, never the original line; a response whose key is unknown is dropped, never forwarded. The pending map is fed by `pump_client_to_server` for EVERY client request (`tools/call`, `tools/list`, `initialize`, and any other method), so there is no class of response the classifier cannot name. The disk sink has two producers in the server (`Response._build`: the `_includeSnapshot !== "explicit"` branch and the `_includeSnapshotFileName` branch) plus two argument-level hooks (`filename`, `_meta`) closed by two sites (`spawn_child` appends `--snapshot-mode none`; `refuse_request` answers `browser_snapshot`+`filename` and any `tools/call`+`_meta` without forwarding) and one detector (`rewrite_result`'s link arm). Every synthesized client-bound `isError` result flows through `error_result`. The predicate has exactly one source: the four names bound in `load_redactor` from the sibling `redact-a11y-snapshot.py`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `rewrite_result` returns `text` unchanged (redaction skipped) | RED — bare-snapshot fixture: sentinel present in proxy stdout |
| 2 | `rewrite_result` processes only `content[0]` | RED — two-text-block fixture: second block still carries the sentinel (second-member row) |
| 3 | `pump_client_to_server` records ids for `method == "tools/cal"` (dispatch broken; map stays empty) | RED — the real result arrives for an unknown key and is DROPPED, so the client hangs: the row asserts the redacted result IS delivered (own-dispatch row; a dropped result is as RED as a raw one) |
| 4 | `redact_text` is made to raise (mutant wraps the bound function in a raiser) | RED — expected `isError` withheld result and NO sentinel; mutant forwards raw |
| 5 | `load_redactor` swallows the import error and continues (proxy copied to a directory with no sibling redactor) | RED — must refuse to start with exit 2; mutant starts and answers `initialize` |
| 6 | `spawn_child` does not append `--snapshot-mode none` | RED — stub's argv file lacks the flag; live row: `page-*.yml` written |
| 7 | `refuse_request` forwards a `browser_snapshot` carrying `filename` | RED — stub writes the named raw file and its request log shows the call |
| 8 | link arm removed from `rewrite_result` | RED — link-result fixture forwarded instead of withheld |
| 9 | `self_test` asserts only `<redacted>` present (not sentinel absent) | RED — a redactor mutant that appends `<redacted>` without removing the value starts the proxy |
| 10 | proxy carries its own predicate (mutant adds `if "password" in name` before calling `redact_text`) | RED — FR13's AST row: a string literal for which the redactor's `_is_credential_name` is True |
| 11 | `annotate_tools_list` skipped | RED — `tools/list` result lacks the marker |
| 12 | stdin-EOF teardown removed | RED — the child's pgid (read from the proxy's stderr) still has a member 5 s + grace after the client closes stdin |
| 13 | `classify` keys on "id is pending" alone (drops the `result`/`error`-present test) | RED — stub `FAKE_PW_ROOTS_COLLIDE=1` emits `{"jsonrpc":"2.0","id":<pending id>,"method":"roots/list"}` BEFORE the real result: the mutant pops the map on the request, the real result then arrives for an unknown key; expected: request forwarded byte-identical, result still redacted and delivered |
| 14 | decoder made strict (`errors="strict"`) | RED — invalid-UTF-8-byte fixture: mutant drops or forwards raw; expected: still redacted |
| 15 | `refuse_argv` removed | RED — proxy launched with `-- <stub> --save-session` starts; expected: exit 2 before spawn. Companion: a `--config` file with `"saveSession": true` must also refuse |
| 16 | shape whitelist widened to "any object" | RED — `structuredContent` fixture (tree under `structuredContent`, prose in `content`) forwarded; expected: withheld `unrecognised result shape`. Companions: `_meta` in the result (mutant accepts it) → withheld; `browser_close` (`isClose: true`) → forwarded (must-PASS) |
| 17 | `text` blocks rewritten but a `resource` block ignored | RED — resource-block fixture forwarded; expected: withheld |
| 18 | trailer appended only when a value changed | RED — a tree with no credential-named field comes back without the trailer block; expected: trailer present on every tree-carrying result |
| 19 | `refuse_request` keys `filename` on truthiness (`if args.get("filename")`) | RED — `{"filename": ""}` reaches the stub; expected: refused on key presence |
| 20 | `refuse_request` does not check `_meta` | RED — `arguments: {"_meta": {"json": true}}` reaches the stub, whose `snapshot-meta-json` fixture returns the JSON-escaped tree: sentinel present in proxy stdout; expected: refused, never forwarded |
| 21 | list-shaped server line forwarded (or dropped without answering) | RED — list fixture with two pending results: expected both ids answered by `error_result`, nothing forwarded; mutant forwards raw or leaves a client hanging |
| 22 | one refusal arm builds its own dict instead of calling `error_result` (mutant: the `filename` refusal hand-builds a result with no `isError`) | RED — the "every synthesized result has `isError: true`, the tool name, and the caveat" row fails on that arm; a second mutant removing a field from `error_result` reddens EVERY withhold/refuse row at once |
| 23 | unknown-key response forwarded raw instead of dropped | RED — a result for an id the client never sent (stub emits it unprompted) carrying the tree: mutant forwards the sentinel; expected: dropped, stderr line |
| 24 | response with BOTH `result` and `method` treated as a normal result | RED — fixture: pending id, `result` AND `method`; expected: withheld `unrecognised result shape` |
| 25 | `annotate_tools_list` not wrapped in `try` | RED — `tools/list` result without a `tools` key kills the loop; expected: original bytes forwarded, stderr note, session continues |
| 26 | client→server pump not wrapped | RED — client sends `not json\n`: expected forwarded raw + stderr note and the next request still relayed; mutant's loop dies (the session hangs) |
| 27 | SIGTERM handler removed | RED — SIGTERM to the proxy: child's pgid still has a member after 5 s + grace |
| 28 | exit-code clamp removed / child exit ignored | RED — stub `FAKE_PW_EXIT_CODE=3` → proxy must exit 3; stub killed by SIGTERM → proxy must exit 143, not −15 |
| 29 | `self_test` drops the `looks_like_a11y_tree` checks | RED — a redactor mutant whose `looks_like_a11y_tree` returns False for everything starts the proxy and never appends the trailer |
| 30 | pending map keyed on the bare id | RED — client sends `id: 1` (`tools/list`) then `id: "1"` (`browser_snapshot`): expected both classified by their own request; mutant misroutes one |
| 31 | pending `error` with structured `data` forwarded raw | RED — error-with-data fixture; expected withheld. Companion must-PASS: `data`-less error forwarded byte-identical |
| 32 | `MAX_INPUT_BYTES` check removed | RED — a text block of `MAX_INPUT_BYTES + 1` bytes (fixture generated by the suite) is forwarded; expected withheld with `withheld tool=` on stderr |
| 33 | `error_result` includes `text[:100]` in the reason | RED — the sentinel appears inside the `isError` text or the stderr line; expected: neither |
| 34 | the `except BaseException` arm around the rewrite removed (input: a sibling redactor mutant whose `redact_text` raises only when `len(text) > 200`, so B3's self-test still passes) | RED — the pump dies or the raw result is forwarded; expected: withheld, session continues (row 4 is the same input against the shipped arm and must be GREEN) |
| 35 | `refuse_argv_and_env` ignores `DEBUG` | RED — proxy launched with `DEBUG=pw:mcp:server:response` starts; expected: exit 2 before spawn, reason names the variable only |
| 36 | drift arm keys on the substring instead of a whole-line `startswith` | RED — a tree fixture whose textbox value contains `- [Snapshot](x` must be delivered redacted; mutant withholds it (page-controlled DoS) |
| 37 | `MAX_LINE_BYTES` discard removed | RED — a 64 MiB + 1 line from the stub: expected discarded, pending id answered `oversize`, stderr carries the byte count only; mutant buffers it (memory observed above the cap) |
| 38 | client list line forwarded | RED — client sends `[{...tools/call...}]`: expected dropped + stderr, stub request log empty; mutant forwards |
| 39 | `browser_find` result not redacted (mutant special-cases `browser_snapshot` by name) | RED — the `browser_find` fixture (row 14) still carries the sentinel; expected redacted (the row that proves Q1's "by shape, no tool-name allowlist") |

**Instrument rows** (the suite must prove its own instruments before the matrix runs): the stub is driven WITHOUT the proxy once — `filename` → file written, `FAKE_PW_REQUEST_LOG` records the call, `FAKE_PW_ARGV_OUT` records argv, `FAKE_PW_HOLD=1` keeps a `sleep`-shaped grandchild alive past stdin EOF — so rows 6/7/12/19/20/27 assert on artefacts the stub is shown to produce; and a 10-line known-negative relay `fake-passthrough-proxy.py` (spawn child, pump both ways, no rewrite) is the pre-fix artefact for QG5: every redaction/withhold/refuse row must be RED against it and every must-PASS row GREEN. Sentinels are SPLIT: `ZZQP-SENTINEL-7980` appears only in credential-named values, `ZZQP-BENIGN-7980` in `Email address`/`Notes`; `assert_redacted_result` asserts sentinel count == 0 AND benign count == N per fixture, so its negative half can actually reject (with one sentinel in both, the H1 control passes while the helper cannot discriminate). Mutants are asserted landed by `diff -q` AND by the changed hunk falling inside the named function's `ast` line range. Every `grep -q` in the suite reads a herestring or a file, never a pipe from a producer (`pipefail` + early match = SIGPIPE = false negative; learning 2026-07-18). Process rows poll `pgrep -g <pgid>` every 0.2 s until `GRACE_S + 5`, with `PLAYWRIGHT_MCP_PROXY_GRACE_S=1` so the suite stays fast; row 12/27 stubs run with `FAKE_PW_HOLD=1` (ignore EOF, trap SIGTERM, hold a grandchild) so a mutant that merely lets the child exit at EOF cannot pass, and the SIGKILL-after-grace arm is actually exercised. Row 28's observable: the mutant exits `241` (raw `-15 & 0xff`) or `0`; the suite sends `kill -TERM <pgid>` (== the stub's pid under `start_new_session`).

**Harness rows** (edits to the SUITE that must drive it RED, plus non-canonical must-PASS inputs):

- H1: neuter `assert_redacted_result` to a no-op — the helper control (driven with a fixture that still carries the sentinel) must REJECT; the instrument self-test must see both counters move.
- H2: neuter `assert_withheld` — its control (a raw forwarded result) must REJECT.
- P1 must-PASS: the `browser_navigate` fixture (no tree, `### Ran Playwright code` fence) passes byte-identical.
- P2 must-PASS: the `browser_evaluate` object result (lines beginning `{`) passes byte-identical — the row that distinguishes in-process `redact_text` from the CLI's envelope arm.
- P3 must-PASS: the bare-snapshot fixture keeps `Email address` and `Notes` values (`ZZQP-BENIGN-7980`) in clear while `Enter your password` and `Token` read `<redacted>` and the sentinel count is 0.
- P4 must-PASS: a `browser_take_screenshot` fixture (`text` + `image` blocks) — the image block is byte-identical.
- P5 must-PASS: a `data`-less JSON-RPC `error` response to a pending id, a server notification, and the `roots/list` server request are forwarded byte-identical; a `browser_close` result (as captured — no `isClose` on the wire) is forwarded.
- P7 must-REDACT: the `browser_find` fixture comes back with `<redacted>` on the credential-named line and the sentinel absent.
- P6 parity: the population is every fixture file for which `looks_like_a11y_tree(text)` is True, enumerated at run time with an asserted floor of ≥ 4 (an empty glob is zero cases and invisible to the vacuity floor), EXCLUDING `snapshot-meta-json` with the stated reason (the CLI's JSON arm redacts `{"snapshot": …}`; in-process `redact_text` does not — an expected divergence, refused upstream by B5) and INCLUDING one canary fixture whose value contains `{` (the CLI's envelope sniff must not trip on it). For each: the proxy's rewritten text — trailer block removed, and for the invalid-byte variant the text as the proxy decoded it (`errors="replace"`, re-encoded UTF-8; the CLI's own `main()` dies on invalid UTF-8) — equals `python3 redact-a11y-snapshot.py < text` byte-for-byte, and the CLI arm exits 0 (P-ONE).

### Guard 2 — `.mcp.json` routing (executable)

**Property.** The `playwright` server declared in this repository's `.mcp.json` is launched through the proxy, at the pinned version, with the config pin and the profile intact.

**Assembly.** One file, `.mcp.json`, one key path `mcpServers.playwright.args[1]` (the `bash -c` string), executed by the suite under `HOME=<scratch>` with an `npx` shim first on `PATH` that records its argv and parent; the assertion reads what the shim recorded, not the string.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove the proxy from the command | RED (the shim's parent is `bash`, not the proxy) |
| 2 | move the proxy AFTER the server (`npx … -- python3 proxy`) | RED (recorded argv is the proxy's, not the server's) |
| 3 | drop `--config=…` from the wrapped command | RED |
| 4 | bump `@playwright/mcp@0.0.78` in `.mcp.json` alone | RED (the version literal asserted here is the one the fixture directory is named after — a bump forces the Phase 0 re-capture) |
| 5 | rename the server key from `playwright` | RED (key lookup fails loudly, not silently passes) |

### Guard 3 — corpus lint S2, structural disclosure

**Property.** Every shipped plugin document that prescribes `browser_snapshot` in an authentication context carries the structural prescription (the `filename:` + redactor + shred form first; a refusal of `filename` means the registration is wrapped by the proxy and the bare call is redacted in flight), and the old unconditional "no runtime guard" sentence alone no longer satisfies the rule.

**Assembly.** `scripts/lint-credential-path-literals.py` `scan_snapshot_rule` S2 branch (`MCP_GAP_MARKER_RE`, `AUTH_CONTEXT_RE`, `MCP_SNAPSHOT_RE`) over `SNAPSHOT_RULE_DIRS`; backed by the required `credential-path-guard` check; the failure message quotes `S2_RECIPE` verbatim.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | a fixture file with `browser_snapshot` + "password" + only the OLD sentence | RED (S2 hit, message quotes the canonical sentence) |
| 2 | the new marker present but wrapped across a line break | GREEN (whitespace-tolerant), asserted |
| 3 | `MCP_GAP_MARKER_RE` reverted to the old pattern | RED — the suite's new-marker PASS row fails and the old-marker RED row passes vacuously |
| 4 | a second `browser_snapshot` file added without the marker after a compliant first | RED (per-file, not first-file-only) |

## Acceptance Criteria

### Functional Requirements

- [ ] FR1 — `python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- <fake server>` relays `initialize`/`tools/list`/`tools/call` end-to-end (suite rows).
- [ ] FR2 — Bare `browser_snapshot` result: `Enter your password` and `Token` rows read `<redacted>`; `Email address` and `Notes` rows unchanged; sentinel count in proxy stdout for that result is 0 and the benign count (`ZZQP-BENIGN-7980`) equals the fixture's (`rewrite_result`).
- [ ] FR2b — `browser_find` result (row 14 fixture): credential-named matched line reads `<redacted>`, sentinel count 0 (`rewrite_result`, by shape).
- [ ] FR3 — `browser_snapshot` with a `filename` key (value `"x.yml"`, and separately `""`), and any `tools/call` with a `_meta` key, are answered by the proxy with `isError: true` under the request's id (type preserved) and never reach the server: the stub's `FAKE_PW_REQUEST_LOG` lacks the call and the would-be file does not exist (`refuse_request`).
- [ ] FR4 — The child argv recorded by the stub ends with `--snapshot-mode none`; live row: `browser_navigate` writes no `page-*.yml` (`spawn_child`).
- [ ] FR5 — Proxy copied beside no redactor refuses to start with exit 2 and a stderr line beginning `playwright-mcp-redact-proxy: refusing to start:`; no child process is spawned (`load_redactor`). Same for `--save-session` in argv, `"saveSession": true` in the config the server will load (`--config`, else `$PLAYWRIGHT_MCP_CONFIG`), `DEBUG` matching `*`/`pw:mcp*`, and `DEBUG_FILE` set — each reason names the option or variable, never its value (`refuse_argv_and_env`).
- [ ] FR6 — A redactor mutant that returns its input unchanged, and one whose `looks_like_a11y_tree` is constant-False, each make the proxy refuse to start (`self_test`).
- [ ] FR7 — When `redact_text` raises, the result is replaced by `isError` text containing `snapshot withheld` and no sentinel (`error_result`).
- [ ] FR7b — For every refusal/withhold (FR3, FR7, FR8, FR9, FR11b) the captured proxy stderr contains exactly one matching pinned-vocabulary line (`refused tool=` / `withheld tool=` …); `assert_stderr_marker` is a helper shown to REJECT (`error_result`, B9).
- [ ] FR8 — A text block over `MAX_INPUT_BYTES` is withheld, not forwarded (`rewrite_result`; mutation row 32).
- [ ] FR9 — A result whose text contains `- [Snapshot](` is withheld; the reason names the enclosing directory and NOT the server-emitted path; no file is removed (`rewrite_result` link arm).
- [ ] FR10 — `tools/list` result: the `browser_snapshot` description ends with the marker `[Soleur: output is redacted in flight by the a11y-snapshot redactor; filename is refused — call browser_snapshot with no filename.]`; a `tools/list` result without a `tools` key is forwarded unchanged with a stderr note (`annotate_tools_list`).
- [ ] FR10b — Every tree-carrying result (bare snapshot with credential rows; bare snapshot of a page with none) ends with a NEW final text block `[Soleur: redacted in flight by playwright-mcp-redact-proxy]`; the `browser_navigate` result (no tree) carries no trailer (`rewrite_result`).
- [ ] FR11 — `browser_navigate`, `browser_evaluate` (object result), screenshot (`text`+`image`), `browser_close` (`isClose`), a `data`-less JSON-RPC `error`, a notification, the `roots/list` server request, and a response to a non-`tools/call`/`tools/list` request are forwarded byte-identical (`cmp` against the fixture line).
- [ ] FR11b — A `roots/list` request whose id equals a pending `browser_snapshot` id, sent before the result, leaves the result redacted and delivered (`classify`); a result with `structuredContent`, a `resource` block, `_meta`, both `result` and `method`, or a missing `content` is withheld; a response for an unknown key is dropped with a stderr line; a list-shaped server line answers every pending id it contains with `error_result` and is not forwarded.
- [ ] FR12 — Parity: for every tree-carrying fixture, proxy output with the trailer block removed (invalid-byte variant compared on the proxy's decoded text) equals the CLI's output byte-for-byte, CLI exit 0.
- [ ] FR13 — Structural, by AST with the redactor as oracle: `ast.walk` over the proxy finds no call to `re.compile`/`re.search`/`re.match`/`re.fullmatch`/`re.sub`, no `def redact_text`, exactly one `spec_from_file_location` call, and no `ast.Constant` string literal `L` for which `redact_a11y_snapshot._is_credential_name(L)` is True (tested at plan time: `"password"`, `"type=password"` → True; `"filename"`, `"snapshot withheld: "`, the marker, the trailer and the B9 caveat sentence → False — so a mutant predicate `"password" in name` is caught while the shipped prose is not).
- [ ] FR14 — Lifecycle, in the suite against the stub, scoped to the pgid the proxy logs on stderr (`pgrep -g <pgid>`; never a machine-wide name pattern): stdin EOF → the group is empty within 5 s + grace; SIGTERM to the proxy → the group is empty within 5 s + grace; stub exit code 3 → proxy exit code 3; stub killed by SIGTERM → proxy exit 143 (a mutant exits 241 or 0); the stderr trail carries `child exited rc=` and, on the HOLD rows, `survived SIGTERM; SIGKILL sent`. The same three arms against the REAL `npx` chain are the Phase 3.2 recorded live row (network + Chrome are ambient in CI, so that row is a measurement record, not a suite row).
- [ ] FR15 — Guard 2's executable shim row passes on this branch under `HOME=<scratch>` and each of its five mutants is observed RED (recorded in `phase-0-measurement.md`).
- [ ] FR16 — `python3 scripts/lint-credential-path-literals.py` (no arguments — a directory argument scans zero files) exits 0 on this branch and reports `scanned file(s)` > 0; its suite carries the Guard 3 rows; the old sentence alone is RED (`scan_snapshot_rule`).
- [ ] FR17 — Using the OLD marker regex kept as a constant in `scripts/lint-credential-path-literals.test.sh` (whitespace-tolerant — the `widen-playbook.md` copy wraps across a line and a literal grep misses it): zero files under `plugins/soleur/skills` match it; the NEW `MCP_GAP_MARKER_RE` matches exactly the five prose files named in Phase 4.2; `! git grep -q "no runtime guard on the Playwright-MCP path" -- plugins/soleur/skills` also holds; and `git grep -l "refusing to start:" -- plugins/soleur/skills | wc -l` returns 6 (the five files + `agent-browser/SKILL.md`, the CPO E1 sentence).
- [ ] FR18 — ADR-213 carries `## Addendum — 2026-09-14 (#7980)` with the three resolution tables; `grep -c 'stdio proxy that would close it is deferred' knowledge-base/engineering/architecture/decisions/ADR-213-*.md` stays `1` (history is not edited) and the `[Superseded 2026-09-14 — see the #7980 addendum below` pointer line is present exactly once, on the line after that sentence's paragraph.
- [ ] FR19 — Register: PA-8 §(g) contains `[2026-09-14 (#7980)` exactly once, appended after the `[2026-09-11 (#7946 / #7993)` bracket (the cell tail); PA-31 §(g) contains it exactly once; append-only asserted by substring identity, NOT by diff lines (both cells are single-line table rows, so any in-cell append is one `-` and one `+` line): extract the #7947 bracket of each cell on `origin/main` and on the branch with patterns TESTED at plan time against the current file (PA-8: `grep -o '\*\*\[2026-09-09 (#7947): credential rendering.*tracked at #7980\*\*\.\*\*\]'` → 4842 bytes; PA-31: `grep -o '\*\*\[2026-09-09 (#7947): the browser-snapshot credential mechanism.*undertakings about those tools\*\*\.\*\*\]'` → 3390 bytes), require each extraction to be non-empty (`test -s`, so a drifted anchor fails loud instead of empty-equals-empty), and `cmp` the two extractions per cell; every `<measured path>` / `<audit path>` slot in the drafted text is resolved to a real path before commit (`grep -c '<[a-z0-9 -]*path>' knowledge-base/legal/article-30-register.md` returns 0 — the class includes a digit so `<phase-0-measurement path>` cannot ship unresolved).
- [ ] FR20 — C4: `model.c4` defines `playwrightMcp` (tag `#external`) and `platform.plugin.snapshotGuard` (description states ships-vs-wires); `views.c4` includes both in `components`, and `playwrightMcp` in `containers` and `context`; `model.likec4.json` is regenerated; the FOUR C4 gates pass (`c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness`).
- [ ] FR21 — Deferral issue **#8156** ("Customers never edit .mcp.json: ship the proxy-wrapped Playwright MCP path by default…") exists, OPEN, milestone "Phase 4: Validate + Scale", labels `deferred-scope-out`, `domain/engineering`, `type/security`, `priority/p1-high` (filed at plan time; verify with `gh issue view 8156 --json state,milestone,labels`).
- [ ] FR22 — `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`: the per-fire overlay's `args` array ends with `"--snapshot-mode", "none"` and the upload step emits `warnSilentFallback(…, { feature: "cron-ux-audit", op: "zero-screenshots" })` when zero screenshots were captured (both asserted by source-shape rows); `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts` asserts it with the whitespace-tolerant `toMatch` row (`cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-ux-audit.test.ts` green); Phase 0 step 4 (the fleet-copy row) measured on the 0.0.75 copy that the flag is accepted and stops the write.
- [ ] FR23 — `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` exists, written by the `clo` agent against the shipped body (frontmatter `disposition:` present, and it names every register claim it verified); `knowledge-base/legal/compliance-posture.md` has a new row under `## Completed Compliance Work` citing #7980 and its `last_updated` is 2026-09-14 or later.
- [ ] FR24 — Provider contract: `redact-a11y-snapshot.py` exports `looks_like_a11y_tree` (with the `_looks_like_a11y_tree` alias) and `__all__` naming the four consumer names; `redact-a11y-snapshot.test.sh` carries one row importing the four and stays green at its prior row count + 1; `apps/web-platform/test/plugin-root-anchoring.test.ts` has the proxy in `GATE_SCRIPT_RE` and the `agent-browser/SKILL.md -> playwright-mcp-redact-proxy.py` row, and passes.

### Non-Functional Requirements

- [ ] NFR1 — stdlib-only; `python3 -c "import ast,sys; t=ast.parse(open('plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py').read()); print(sorted({(n.names[0].name if isinstance(n, ast.Import) else n.module).split('.')[0] for n in ast.walk(t) if isinstance(n,(ast.Import,ast.ImportFrom))}))"` prints only standard-library module names.
- [ ] NFR2 — The proxy writes NOTHING to stdout that is not a protocol line; startup diagnostics are stderr-only: a suite row captures a full stub session's stdout and asserts every line parses as a JSON-RPC object (not only the first byte).
- [ ] NFR3 — Single-threaded: `grep -c "threading" playwright-mcp-redact-proxy.py` returns 0; the loop is `selectors`-based (POSIX).

### Quality Gates

- [ ] QG1 — `bash scripts/test-all.sh --print-suite-globs` lists `plugins/soleur/skills/*/test/*.test.sh`; the new suite runs in the scripts shard and reports its floor.
- [ ] QG2 — `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/archive/20260914-230848-2026-09-14-feat-playwright-mcp-snapshot-redaction-proxy-plan.md` exits 0.
- [ ] QG3 — `bash scripts/guard-vacuity-floor.test.sh` classifies the new suite's floor as constructible (not UNCLASSIFIED).
- [ ] QG4 — `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [ ] QG5 — Every RED row in Guards 1–3 was driven against the pre-fix artefact and observed RED; the observation table is in `phase-0-measurement.md`.
- [ ] QG6 — No acceptance criterion in this plan depends on a process the plan does not spawn (every process assertion is `pgrep -g <captured pgid>`; the executable `.mcp.json` row runs under a scratch `HOME`).

## Domain Review

**Domains relevant:** engineering, legal, product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Sound; proceed. The transport proxy is the only deterministic chokepoint between server and model that lives in the plugin's shipping surface; injecting `--snapshot-mode none` in the proxy (not the config) is correct for P7; in-process `importlib` is right given probe row 4 and the anchor fan-out. Five concerns, all folded: (1) HIGH — server→client requests (`roots/list`, ids from an independent counter) could pop a pending id and turn the real result into a raw forward → response classification requires `result`/`error` AND no `method`; matrix row 13. (2) MEDIUM — the TypeScript SDK decodes lossy UTF-8; a strict Python decoder would forward raw on one bad byte → `errors="replace"`, binary I/O, stderr note; row 14. (3) MEDIUM — the proxy holds `npx`'s pid, `playwright-mcp` is a grandchild → process group + `os.killpg`, `os._exit` after flush, live FR14 row. (4) MEDIUM — annotate `initialize.result.instructions` too (Claude Code injects server instructions into the system prompt) — folded, then CUT at plan review by DHH + code-simplicity (one pre-call signal suffices; the `filename` refusal is the structural signal). (5) LOW — `ensure_ascii=True` for rewritten lines; refuse `--save-session` (a raw `session.md` sink); `--save-trace` was checked and does not exist in 0.0.78.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Direction sound; three corrections folded. (1) HIGH — FR19's diff-line append-only check was false by construction (single-line table rows) → substring identity via `grep -o` + `cmp`. (2) HIGH — PA-31's "not live on this Activity today" is narrowed by this plan's own source cross-check: 0.0.75's `browser_navigate` writes the raw tree under the fleet's cwd and the member holds `Read`/`Glob`/`Grep` → own dated bracket quoting the superseded sentence, Phase 0 step 4 measured row on the 0.0.75 copy, remedy `--snapshot-mode none` appended to the overlay (Phase 3.3, CTO-chosen). (3) HIGH — `2026-09-counsel-review-7947.md` pins "#7980 lands" as a re-evaluation trigger → CLO attestation audit + `compliance-posture.md` Completed row (Phase 5.4, FR23). MEDIUM: define "redacted in flight" in the register as a content rewrite at the transport boundary, not encryption; the marker is a liveness signal the prose conditions on (PA-31 (9) organisational measure), never "a disclosure the agent verifies"; #7981 stays `Ref` only. Format rules for the appends recorded in Phase 5.2, with the CLO-drafted bracket text carried verbatim as the starting point, to be verified against the shipped body.

### Product/UX Gate

**Tier:** advisory (no UI surface; the CPO sign-off is the `single-user incident` requirement, not the UX gate)
**Decision:** reviewed — CPO sign-off **approved with edits**, all applied (E1 startup-failure prose and observability row; E2 "call `browser_snapshot` bare after every action tool"; E3 `## User-Brand Impact` rewrite; E4 deferral re-milestoned to Phase 4 with `priority/p1-high` — filed as #8156)
**Agents invoked:** cpo, spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

spec-flow-analyzer (Phase 3, run with the flow-walk prompt): P0-1 `roots/list` id collision (same as CTO (1), folded); P0-2 unrecognised result shapes forwarded raw → shape whitelist (`content`/`isError`/`isClose`, `_meta` rejected; block types text/image/audio with block-level key sets; text is `str`), whole classification inside one `try`, rows 16–17; P1-1 lifecycle (daemon threads, `BrokenPipeError`, killpg — folded); P1-2 dead ends → oversize reason names `depth:`/`target:`; the drift-arm `os.remove` it proposed was folded and then CUT at plan review (the arm withholds and names the directory only), residual named; P1-3 config-vs-flag measured, not read (Phase 0 row 11); P1-4 runtime signal strengthened with the per-result trailer; the `ToolSearch` pre-call ritual it proposed was superseded at plan review by the `filename` refusal as the structural signal; P1-5 `filename` refused on key presence, id type preserved, request-log assertion; P2 id keying, stale-entry deletion, list handling (final: every pending id in a list answered by `error_result`), two-way `error.data` handling (no `data` → forward, any `data` → withhold), startup identity log, refusal text for older prose. AC rewrites: FR13 by AST (not grep), NFR3 every line, FR14 live process tree, FR15 executable shim row, liveness signal reworded. Brainstorm-recommended specialists: none (no brainstorm preceded this plan).

### Plan review panel (consolidated, headless — Mechanical findings auto-applied)

Six lenses ran in parallel on the revised plan: DHH, Kieran, code-simplicity (per mechanism against the Property List), architecture-strategist, spec-flow-analyzer (re-validation), and CTO on a devex lens. Consolidation treated DHH + code-simplicity as the simplification axis and Kieran + architecture + spec-flow as the correctness axis; where both fired on one scope, delete won.

**Deleted (both axes fired):** the contained `os.remove` in the drift arm (DHH: a relay does not delete; simplicity: cleanup cannot restore P7; spec-flow: cwd-relative resolution was wrong for the dogfood `.mcp.json`, which passes no `--output-dir`) — withhold, name the directory only; the `initialize.instructions` annotation (one pre-call signal suffices; the `filename` refusal is the structural signal); the three-way `error.data` arm (collapsed to no-`data` → raw, any `data` → withhold); the standalone list arm (folded into classification: every pending id in a list is answered); two pump threads with locks (single `selectors` loop); NFR2 timing row (a printed number asserts nothing); Guard 2's string row (the executable shim row is the invariant). **Kept against DHH:** the `filename` refusal (it IS the runtime signal the prose now relies on — prose prescribes the file form first, and a refusal means "wrapped"); the per-result trailer (code-simplicity, CTO-devex and CLO: the only transcript-persistent trace, load-bearing for the register's "declared" claim; page content can forge it, so it is post-hoc only).

**Correctness folds:** `roots/list` id collision (all three correctness lenses; row 13 reworded per Kieran so the mutant is actually RED); `_meta` argument hook measured at plan time and refused (own probe, row 13 of Phase 0); response classification requires `result`/`error` present, a response with both `result` and `method` is withheld, an unknown-key response is DROPPED (the previous "forward raw" was a fail-open); block-level key whitelists and `_meta` rejected in results (0.0.78 never emits it); `saveSession` in the `--config` file refused alongside `--save-session`; `start_new_session` makes the child the group leader, so the proxy logs the child's pgid and every process assertion reads it (FR14/row 12 were asserting the wrong group); SIGTERM then SIGKILL after grace; exit-code clamp; every pump iteration wrapped; `annotate_tools_list` fail-safe; `(type, id)` keying and stale-entry deletion promoted from Edge Cases to rows 30/13; FR19 patterns tested (the drafted one matched 0 bytes; the PA-8 cell tail is the 2026-09-11 bracket, not #8016); FR18 grep was vacuous (string lives in the register, not the ADR); FR16 bare invocation (a directory argument scans zero files); FR13 uses the redactor's `_is_credential_name` as oracle instead of a hand-copied word list (every shipped literal tested False at plan time); P6 parity input for the invalid-byte row is the decoded text; Guard 2 runs under a scratch `HOME` (the real prelude would SIGKILL a sibling session's browser — Kieran and architecture both caught it); `model.likec4.json` + `c4-model-freshness` are the fourth C4 gate; `playwrightMcp` joins the `context` view; the proxy joins `GATE_SCRIPT_RE`/`EXPECTED_GATE_REFS` instead of evading them; `looks_like_a11y_tree` promoted to a declared provider contract with a provider-side row; `cron-ux-audit.test.ts` row made unconditional (the file asserts no argv today); ADR-213 gets a pointer line at the superseded sentence; S2 changes class (static disclosure → structural prescription) and the lint failure quotes the canonical sentence; a committed capture driver replaces "re-run the probe"; fixture directory derived from the `.mcp.json` pin; stub made table-driven.

**Taste / User-Challenge routed to `decision-challenges.md`:** none — no finding argued for changing the operator's stated direction (own PR, closes #7980 only, proxy shape per the issue). The Phase 3.3 fleet-overlay edit is a CLO finding folded at two argv strings and is named as such in the PR body; the CPO's re-milestoning of the deferral (#8156, Phase 4, p1) was applied at Phase 2.6 and is recorded above.

## GDPR / Compliance Gate

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

Invoked at Phase 2.7 on trigger (b) (`single-user incident`). `gdpr-gate.sh` path scan: 1 examined, 0 matched the canonical regulated-data regex (no migration, no auth code, no API route, no `.sql`). The five v1 checks against the plan prose:

- `GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17`, `GDPR-Art-17-caller`: no new column, table, FK or RPC — not engaged.
- `GDPR-Chapter-V`: no new vendor, SDK or env var. The tool result still reaches Anthropic through Claude Code exactly as today; the proxy strictly REDUCES the content that crosses (values rewritten before the model request). Not engaged.
- `GDPR-Art-9`: no column-name match — not engaged. No Critical finding; no escalation block.
- Suggestion (Art. 32 record-keeping): the proxy is a technical measure and must be recorded where the mechanism it mitigates is recorded — PA-8 §(g) and PA-31 §(g) appends plus the CLO attestation are in scope (Phase 5).
- Suggestion (TS-01..05, fixtures): every fixture is synthesized; the sentinel is `ZZQP-SENTINEL-7980`; the 0.0.78 captures contain no real credential and no real origin (`127.0.0.1:8748`).

Pre-existing, not this PR's: the gate printed `POSTURE_FAIL: gdpr-gate rules >90 days stale` — the corpus-freshness binding is inert since its workflow moved to an Inngest cron, tracked at #7255 (and the enforcement-chain gap at #7852). Per the skill's own chain, this PR is not paused on it.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Bare snapshot through the proxy → password and Token `<redacted>`, email in clear (fixture from the surface).
- `filename` refused (`"x.yml"` and `""`); `_meta` refused; stub request log lacks both; stub file absent.
- Stub argv ends with `--snapshot-mode none`.
- Two-text-block result → both redacted.
- Raising `redact_text` → withheld, no sentinel.
- Proxy without sibling redactor → exit 2, no child; `--save-session` / `saveSession: true` → exit 2, no child.
- `roots/list` with a colliding id → request forwarded, result still redacted and delivered.
- Unknown-key response carrying a tree → dropped; list line with two pending results → both answered by `error_result`.

### Regression Tests

- `browser_navigate`, `browser_evaluate`, screenshot, error response, notification → byte-identical.
- Redactor suite green at 61 + 1 rows (the provider-contract row) and hook suite unchanged in count and green.
- Corpus lint suite: existing rows green; new S2 rows as in Guard 3.

### Edge Cases

- A server line that is not JSON → dropped with a stderr line; a client line that is not JSON → forwarded raw with a stderr note; a JSON list from the server → every pending id inside it answered by `error_result`, the line dropped.
- A `tools/call` id reused by the client for a later request → the stale entry is deleted when the new request is recorded; ids are keyed `(type, value)`.
- A server→client REQUEST (`roots/list`) with a colliding id → forwarded unchanged, map untouched; a response for a key the client never sent → dropped; a response with both `result` and `method` → withheld.
- A result with `content: []` → forwarded unchanged; a `text` block whose text is empty → unchanged; a result carrying `isClose: true` → accepted; a result carrying `_meta`, `structuredContent`, a `resource` block, or no `content` → withheld.
- Lone surrogates survive as `\udXXX` escapes under `ensure_ascii=True`; nothing can raise at the write.
- One invalid UTF-8 byte inside a text block → decoded with replacement, still redacted.
- A client line with invalid UTF-8 → forwarded raw; the server's lossy decoder may execute it; the reply arrives for a key the proxy never recorded and is dropped (withheld by construction, named here).
- A line over `MAX_LINE_BYTES` → discarded; pending ids answered `oversize`.
- `browser_close` result carries no `isClose` on the wire (deleted server-side); the whitelist tolerates it either way.

### Integration Verification (for `/soleur:qa`)

- Live run of the proxy in front of `npx @playwright/mcp@0.0.78 --headless --isolated` against the synthesized page via the committed capture driver: rows FR2/FR3/FR4/FR10/FR10b reproduce with the real server, and the three lifecycle arms (EOF, SIGTERM, SIGKILL + wrapper reaper) leave the child's pgid empty (no Claude Code restart required).
- Guard 2's executable shim row (scratch `HOME`) exits 0 on the branch's `.mcp.json`.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-213** (`knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md`) with a dated addendum: the fourth control (transport proxy), the three design-question resolutions with their alternatives, the reach per surface, the residuals, the S2 class change, the enumerative-closure statement, and a pointer line at the superseded §Consequences sentence. No new ordinal; status unchanged. Domain-model register: no business rule changes — skipped.

### C4 views

All three model files were read in full. Enumeration for this feature: external human actor — none new (the founder/operator is `founder`); external system — the **Playwright MCP server** (a Chrome instance driven over stdio on the operator workstation, reaching arbitrary origins) is NOT modeled (`grep -n -i "playwright\|mcp server\|browser" model.c4` returns only the `codex -> platform.plugin` "MCP connections" edge prose and a `shape browser` style); container/data-store — the proxy is a new plugin-shipped component on the path between `platform.engine.claude` and that external system; access relationship — `platform.engine.claude` now reaches the browser THROUGH the plugin component rather than directly (the new trust boundary). Edits, in this feature's lifecycle:

- `model.c4`: add `playwrightMcp = system "Playwright MCP server" { #external … }` with a description naming the pinned package, the stdio transport and the headed Chrome profile; add `platform.plugin.snapshotGuard = component "browser-snapshot credential guard"` (redactor + PreToolUse deny + transport proxy, ADR-213); edges `platform.engine.claude -> platform.plugin.snapshotGuard "MCP tools/call over stdio; every tool result's text passes the credential predicate before the model reads it"`, `platform.plugin.snapshotGuard -> playwrightMcp "Relays JSON-RPC lines; appends --snapshot-mode none; refuses filename"`, `platform.engine.hooks -> platform.plugin.snapshotGuard "Bash-path deny routes agent-browser snapshot through the same predicate"`.
- `views.c4`: `components` view includes `platform.plugin.snapshotGuard` and `playwrightMcp` (both endpoints of the new edges); `containers` AND `context` views include `playwrightMcp` (every other external system is in L1; edges derive to `platform`, no disconnected box — #7332). The `snapshotGuard` description states the plugin SHIPS the proxy while only this repository's `.mcp.json` WIRES it (#8156), so the diagram does not assert the customer gap closed.
- `model.likec4.json` regenerated via `scripts/regenerate-c4-model.sh` (tracked; byte-diffed by the freshness gate).
- Gates (four): `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` (new edge prose avoids the counted "Of N …" clause shape), `plugins/soleur/test/c4-model-freshness.test.sh`.

### Sequencing

The decision is true the moment the PR merges (the wrapped `.mcp.json` is the dogfood surface); no soak, no `adopting` status.

## Open Code-Review Overlap

None — the `code-review`-labelled open set (65 issues) contains no body naming any planned file. Acknowledged related open issue, not folded: **#7981** ("AUP §2 scope names only agent-browser; the plugin also drives the Playwright MCP") — a legal-document scope statement, owned by the CLO lane; this PR cites it with `Ref #7981` because the register append names the Playwright surface, and leaves it open.

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| A future `@playwright/mcp` bump changes the response shape (section title, fence) or the `--snapshot-mode` flag | The predicate is bullet-anchored (shape, not section title); the flag is asserted by the live Phase 0 row and an unknown flag makes the server refuse to start (loud); the link arm withholds any reappearance of the disk sink. `.mcp.json` pins the version; the pin test in `apps/web-platform/test/playwright-mcp-version-pin.test.ts` covers the fleet's copy only. |
| Over-redaction of a benign field named like a credential (the redactor's known trade-off) | Unchanged predicate, unchanged must-PASS rows; the withheld/redacted text tells the agent what happened; a screenshot remains available for `type=password` pages. |
| Orphan proxy or child processes after Claude Code exits | Proxy exits on stdin EOF and on child exit and tears the child's group down (SIGTERM, then SIGKILL after grace); the wrapper reaps a stale proxy by pattern BEFORE the child reaper, so a SIGKILLed proxy (which runs no handler) still leaves no server behind. |
| The dogfood browser workflow loses post-action snapshot links | Measured equivalence: the agent calls `browser_snapshot` (one tool call, redacted) instead of `Read`ing a `page-*.yml` link (one tool call, raw). Documented in the SKILL.md subsection. |
| The lint change breaks the required check on files this PR does not touch | The five S2 files are the entire population (found with the lint's own whitespace-tolerant `MCP_GAP_MARKER_RE`, not a literal grep, which undercounts `widen-playbook.md`); all edited in the same commit. |
| Portability of the proxy | Python stdlib `selectors` + `subprocess` on POSIX (Linux, macOS); no `pkill`/`awk` in the proxy itself (those stay in the Linux-only `.mcp.json` wrapper, as today, and the SKILL.md says which part is which). Windows is not a supported surface for the wrapper today. |

## Deferrals

1. **Customers never edit `.mcp.json`: ship the proxy-wrapped Playwright path by default** — filed at plan time as **#8156** (`deferred-scope-out`, `domain/engineering`, `type/security`, `priority/p1-high`, milestone "Phase 4: Validate + Scale" per the CPO ruling that qa/reproduce-bug/ux-audit already prescribe `mcp__playwright__browser_snapshot` to customers, so the wrapped path is a prerequisite of shipped skills rather than a Phase 5 capability). Re-evaluate before any release that markets those skills to non-dogfood customers. Whether the fix is auto-registration or auto-wrapping the user's entry is decided at that issue's spec time.
2. Observation for the S2-file edit: `reproduce-bug/SKILL.md` names `mcp__plugin_soleur_pw__browser_*`, a prefix no shipped server produces; correct it to `mcp__playwright__browser_*` in the same edit (no separate issue — it is a line in a file this PR already rewrites).

## References

- Issue #7980; predecessor PR #7975 (closes #7947); related #7981.
- `knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md`, ADR-095, ADR-162, ADR-179, ADR-202.
- `knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md` (the #7947 measurement) and `knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/plan-time-probe-record.md` (this plan's).
- `knowledge-base/legal/article-30-register.md` PA-8 §(g), PA-31 §(g).
- MCP specification 2025-11-25, §Transports (stdio) and §Tools.

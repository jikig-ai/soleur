---
title: "CLO attestation — #7980 Playwright-MCP snapshot redaction proxy: the PA-8 §(g) and PA-31 §(g) amendments, verified against the shipped body"
type: clo-attestation
date: 2026-09-14
issue: 7980
adr: ADR-213 (addendum 2026-09-14)
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: "DISCHARGED — RE-ATTESTED 2026-09-14 against the review-round body (§Re-attestation). The #7947 counsel review's `#7980 lands` trigger stays discharged and its carve-out lifted, on the registration this repository controls and only there. The first DISCHARGED below (superseded_disposition) was issued on commit `cb7a0af83`, on which four bracket claims were FALSE — the PA-8 'CLOSED' for credential labels Playwright single-quotes, the startup closure (`DEBUG=pw:*` and an INI `saveSession` both started the proxy), the withhold list (a JSON-escaped tree and server notifications were forwarded), and the `filename` refusal as a structural signal — and three were understated or too narrow (the `browser_network_request` residual, the PA-31 member's tool list, PA-31 (t1)'s remedy). Each is corrected IN-CELL with a dated marker quoting the superseded wording (C2–C10, plus C1's successor), and each fix was verified against the shipped body by reading it, by reproducing the defect against the attested files and its absence against the shipped files on a stub server, and by the finished review-round suite records. No Art. 33 duty; no Art. 34 duty; NO breach-register row. #7981 stays Ref-only. TWO evidentiary limbs open, neither bearing on the ruling."
re_attested_at: 2026-09-14
relay_rebuild_addendum: "2026-09-14 — a same-day code change after the re-attestation (the relay rebuild in `relay_server_message`, gated by `plain_id`) is folded into the C4 cell and recorded in §Addendum — relay rebuild, which also supersedes every proxy and redactor LINE citation in this file with a function or constant name. Disposition unchanged: DISCHARGED."
aup_7981_addendum: "2026-09-15 — the `#7981 lands` trigger fires on the merge of PR #8207 (AUP §2 names a Playwright MCP server); DISCHARGED, unchanged. See §Addendum — #7981 re-evaluation trigger. The NOT ATTESTED #7981 item and the trigger below are left as written (append-only)."
mcp_8156_addendum: "2026-09-18 — #8156 ships `plugins/soleur/.mcp.json`, so row 18's evidence ('no `plugins/soleur/.mcp.json` exists') is superseded as to the fact it recorded. See §Addendum — #8156 plugin-root registration. Disposition unchanged: DISCHARGED. Row 18 and its cell stay as written (append-only)."
re_attested_body: "working tree of `feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy` on top of `7b69b7399`, with the ten-seat review's changes uncommitted at the time of reading: `playwright-mcp-redact-proxy.py` 663 lines, `redact-a11y-snapshot.py` 443 lines"
superseded_disposition: "DISCHARGED — the #7947 counsel review's `#7980 lands` re-evaluation trigger is discharged and its `NOT ATTESTED — #7980's remediation` carve-out is lifted, on the registration this repository controls and only there. Every mechanism claim in both appended brackets was verified against the shipped proxy, `.mcp.json`, `cron-ux-audit.ts`, the suite and its run records, and the Phase 0 measurement — not against the plan or the PR description. ONE claim was not supported by the body and was corrected IN-CELL before merge (C1: the skills prescribe a remediation path for a refused start; they do not carry the affirmative 'stop, not a fallback' instruction the bracket asserted). No Art. 33 duty; no Art. 34 duty; NO breach-register row. #7981 stays Ref-only. One evidentiary limb NOT RUN and recorded as open; it does not bear on the ruling."
superseded_frontmatter: "Superseded 2026-09-14 (#7980, review round): `open_limbs` now carries TWO limbs (§Re-attestation R6); `tier_classification`'s 'one in-cell correction' is now C1 plus nine review-round corrections; `attests` covers the brackets as corrected by C1 AND C2–C10; the re-evaluation trigger reading 'Any `- [Snapshot](` link observed in a wrapped session's withheld result' is superseded by the trigger below naming the do-not-read notice, because the drift arm no longer withholds the result."
review_round_re_evaluation_triggers:
  - "The do-not-read notice `Snapshot withheld by playwright-mcp-redact-proxy` observed in a wrapped session's result — the drift arm has fired, a raw tree file is on disk, and the enumerative closure of the disk sink has been broken by a version or a server change."
  - "`agent-browser` is measured to render single-quoted YAML keys — the #7947 redactor on `main` then had the quoted-key bypass on the Bash path too, and the PA-8 §(g) 2026-09-09 bracket's 'P7 achieved on the agent-browser Bash path' must be narrowed by a new dated bracket."
  - "Any cron in `CRON_MCP_ALLOWLISTS` gaining a Playwright tool the `cron-ux-audit.test.ts` ban list forbids, or the ban list shrinking."
signed_off_at: 2026-09-14
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
awareness_anchor: "2026-09-14 — the date the CLO read the shipped body and re-ran the suite. No Art. 4(12) event is found, so this is an evidence date, not an awareness anchor; see §Why there is no awareness anchor to run a clock from."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose. This is a control landing (Art. 32(1)(b) confidentiality; Art. 32(1)(d) effectiveness), recorded under Art. 30(1)(g). The PA-31 narrowing records a path that EXISTED before this change (a raw tree written under cwd by `browser_navigate`, one `Read` away from Anthropic-bound content); it is a record of exposure-shaped topology, not an observed disclosure of personal data, and its egress ceiling is a registered processor over a seeded fixture account. See §Finding 3."
open_limbs: "ONE. The transcripts of historical `cron-ux-audit` fires were NOT read to establish whether any fire actually `Read` a `.playwright-mcp/page-*.yml`. The ruling does not depend on that fact — the worst case is a seeded fixture account's page tree reaching Anthropic, a PA-31 registered recipient — so the limb is recorded as open rather than as a condition. Closure and reopening conditions in §The open evidentiary limb."
tier_classification: "Tier 1 — an internal determination and two additive register amendments, plus one in-cell correction to a bracket that has not yet merged. No `docs/legal/**` document is edited and no published page changes (verified: zero diff on `docs/legal/` and `plugins/soleur/docs/pages/legal/` against origin/main). The five `docs/legal/**` CI gates are NOT engaged."
semver: "No TC_VERSION bump."
attests:
  - knowledge-base/legal/article-30-register.md (the two `**[2026-09-14 (#7980): …` brackets appended at PA-8 §(g) and PA-31 §(g) ONLY, as corrected by C1)
  - knowledge-base/legal/compliance-posture.md (the #7980 Completed-Compliance-Work row and the `last_updated` bump ONLY)
  - knowledge-base/legal/breach-register.md (ONE §Excluded records waiver row for this file, required by `scripts/lint-legal-registers.sh` (c)/(d), plus the preamble row-count restated from "thirteen" to "sixteen" — the table held fifteen before this row)
  - scripts/lint-legal-registers.sh (the matching `NOT_TRANSCRIBED` entry ONLY)
carve_outs:
  - "NOT ATTESTED — the engineering design. Whole-server-by-shape, three fail-closed arms, in-process binding of four names, the cut `os.remove` in the drift arm, and the `filename` refusal kept as the structural signal are settled decisions at the ADR-213 2026-09-14 addendum, reviewed here only for whether the register describes them truthfully."
  - "NOT ATTESTED — the proxy as a control that makes snapshotting a credential page safe. It is attested as recorded: a content rewrite at the stdio boundary through a name-predicate redactor whose ceiling (localised names, non-input roles, segmented inputs) carries over unchanged, with six named residuals restated in §Finding 4."
  - "NOT ATTESTED — any registration other than this repository's `.mcp.json`. A customer registration (#8156), the hosted agent-runner (registers no Playwright server) and the Inngest fleet overlay (NOT wrapped) are attested only as to what the register SAYS about their reach, which is verified."
  - "NOT ATTESTED — a loaded session. The `.mcp.json` declaration is asserted by an executable suite row; `.mcp.json` loads on a full Claude Code restart only, and no live-session probe was part of this attestation."
  - "NOT ATTESTED — #7981 (AUP §2 names only `agent-browser`). Stays Ref-only; not fixed, not closed here."
  - "NOT PROMOTED — external counsel review. This is the v1 internal sign-off under the Soleur-as-tenant-zero posture."
re_evaluation_triggers:
  - "The `@playwright/mcp@0.0.78` pin in `.mcp.json` moves → Phase 0 re-capture is owed before the bracket's `--snapshot-mode` / result-shape / `_meta` / `browser_find` observations may be relied on; the suite's fixture directory is derived from the pin and fails loudly on a bump without a re-capture."
  - "#8156 lands (customer-registration wrapping) — reach (b) at PA-8 §(g) changes from 'wrapped only by their own configuration' to whatever ships, and must be re-APPENDED, never edited."
  - "#7981 lands or is closed without landing — the published AUP §2 scope statement changes either way."
  - "Any grant of `mcp__playwright__browser_snapshot` (or `browser_find`) to a fleet member — PA-31 (t1): that member's per-fire overlay must route through `playwright-mcp-redact-proxy.py` FIRST, and python3 is not on the cron image path today, so the overlay cannot be wrapped as it stands."
  - "The `@playwright/mcp@0.0.75` fleet pin moves — the 'accepted and stops the write' observation at PA-31 §(g) is dated to 0.0.75 and binds on no other version."
  - "Any `- [Snapshot](` link observed in a wrapped session's withheld result — the drift arm has fired, the raw file is on disk, and the enumerative closure of the disk sink has been broken by a version or a server change."
  - "The open limb being run with an adverse finding (a historical fire that `Read` a page tree carrying a non-fixture data subject's values)."
  - "First arms-length (non-Jikigai-affiliate) data subject affected by a browser-automation capture; any data subject outside the EEA/UK; a regulated-industry tenant. These are the standing triggers for EXTERNAL counsel re-review of this attestation and the amendments it covers."
related:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/audits/2026-09-counsel-review-7947.md
  - knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md
  - knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md
  - knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/phase-0-measurement.md
  - knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/plan-time-probe-record.md
  - plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py
  - plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py
  - plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh
  - plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh
  - knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/runs/suite-review-round.txt
  - knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/runs/suite-red-passthrough-review-round.txt
  - apps/web-platform/test/server/inngest/cron-ux-audit.test.ts
  - .mcp.json
  - apps/web-platform/server/inngest/functions/cron-ux-audit.ts
---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**

# CLO attestation — #7980, the ADR-213 addendum, and the PA-8 / PA-31 amendments

This is the v1 internal counsel-review sign-off required by the ship Phase 5.5
Counsel-Review CLO-Attestation Gate (plan Phase 5.4 for #7980). It is performed
by the CLO agent, not by the operator, per the recurring-bug record at
`knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`.
It is an **internal** sign-off. External counsel re-review is reserved for the
re-evaluation triggers in the frontmatter.

## What was referred, and what I actually ruled on

The 2026-09-09 counsel review of #7947 (`2026-09-counsel-review-7947.md`) pinned
"`#7980` lands, or is closed without landing" as a re-evaluation trigger and
recorded "NOT ATTESTED — #7980's remediation" as a carve-out, because the register
then said P7 was NOT achieved on the Playwright-MCP runtime path and that the
`.mcp.json` stdio proxy which would close it was deferred. #7980 has landed. This
attestation discharges that trigger and lifts that carve-out — **on the
registration this repository controls, and only there** — by verifying every
claim the two new register brackets make against the bytes that ship.

The referral's framing ("the residual is CLOSED") is narrower than what the PA-31
bracket actually does: it **narrows** a prior finding by recording a disk-sink path
on the fleet that the 2026-09-09 cell's "not live on this Activity today" did not
see. That narrowing is the part of this change with any Art. 33 shape to it, and
it is ruled on separately at Finding 3.

## Verification actually performed

Everything in this section was run by me on 2026-09-14 in the worktree
`feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy`. Figures are from
those runs, not restated from the ADR, the plan, or the run logs — where a run
log is cited, I re-ran the thing it records and state both numbers.

### 1. The register diff is additive, and the #7947 brackets are byte-identical to origin/main

`git show origin/main:knowledge-base/legal/article-30-register.md` (read-only)
against the worktree file: 776 lines on both sides; exactly two lines differ
(181 and 628); on each, the `origin/main` line minus its trailing pipe cell
terminator is a byte-prefix of the worktree line, so nothing before the new bracket moved; the
`**[2026-09-09 (#7947)` bracket text on each line is byte-identical on both
sides; escape-aware cell counts are 4/4 on both lines before and after. The
`--word-diff=porcelain` deletion count is **0**. The register's "re-appended,
never edited" contract holds. Re-verified after applying C1 below.

### 2. The proxy, line by line, against the PA-8 §(g) bracket

Each register claim is listed with the line(s) of
`plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
(528 lines) or the other body file that carries it. "Verified" means I read the
lines; where a suite row asserts the same fact I name it, but the suite is
corroboration, not the source.

| # | Register claim (PA-8 §(g), #7980 bracket) | Verified against | Holds |
|---|---|---|---|
| 1 | Stdio JSON-RPC relay declared in this repository's `.mcp.json` in front of `@playwright/mcp@0.0.78` | `.mcp.json` line 7: `exec … python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 --user-data-dir=$prof --config=.claude/playwright-mcp.config.json`; suite Guard 2 rows read the recorded argv under a scratch `HOME` + `npx` shim | yes |
| 2 | Rewrites the text of every `tools/call` result through the same `redact_text` the redactor exposes | `rewrite_result` lines 339–393 is reached for every `method == "tools/call"` (line 321) with no tool-name check; line 371 `new_text = self.redact_text(text)` | yes |
| 3 | Loaded by path at startup, four bound names | `load_redactor` lines 134–149: `spec_from_file_location` on the sibling `redact-a11y-snapshot.py` (`REDACTOR_BASENAME` line 85); the four names `redact_text`, `looks_like_a11y_tree`, `MAX_INPUT_BYTES`, `REDACTED` checked at line 146, refusal at 147–148 | yes |
| 4 | Self-tested on a sentinel row | `self_test` lines 155–169: the row `- textbox "Token" [ref=e1]: ZZQP-SENTINEL-7980`; refuses if `REDACTED` absent or the sentinel survives (161–162); also checks the tree/prose discriminator (163–169); called from `main` line 521 before spawn | yes |
| 5 | The proxy defines no predicate of its own | No `import re`, no `re.*` call, no `def redact_text` in the file; exactly one `spec_from_file_location` (line 139); suite FR13 AST row exempts only the docstring and `self_test` from the credential-literal scan | yes |
| 6 | By shape, on every tool, because two tools inline tree lines on the pinned version (`browser_snapshot` and `browser_find`, the latter bypassing `--snapshot-mode`) | `phase-0-measurement.md` §0.1 (`browser_find` inlines the tree) and §0.2 (the flag governs ACTION tools only); the committed flag-mode fixture `test/fixtures/playwright-mcp-0.0.78/find.json` carries the sentinel twice under `### Result` — I decoded it | yes |
| 7 | Appends `--snapshot-mode none` so no tree is written to disk by action tools | `spawn_child` line 205 `argv = list(server) + ["--snapshot-mode", "none"]`; `phase-0-measurement.md` §0.2: navigate under the flag writes 0 `page-*.yml`; the CLI flag wins over the config file's `snapshot.mode` | yes |
| 8 | Refuses `browser_snapshot` with a `filename` key and any call carrying an undocumented `_meta` argument before they reach the server | `refuse_request` lines 235–248: `_meta` at 244–245 (any tool), `filename` at 246–247 (`browser_snapshot`); called at line 280 and the refusal is written to the client at 282 with an early return, so the child never sees the line; suite FR3 row (line 283) asserts neither string reaches the stub's request log | yes |
| 9 | Measured: `_meta.json` returns the tree as one escaped string the line-anchored predicate cannot see | `phase-0-measurement.md` §0.1 row `arguments._meta: {json: true}` (2 newlines in the text, sentinel present); fixture `snapshot-meta-json.json` | yes |
| 10 | Refuses to start under `--save-session`, a config `saveSession`, `DEBUG` matching `*`/`pw:mcp*`, or `DEBUG_FILE` | `refuse_argv_and_env` lines 175–198: 176–177, 178–193 (`--config=`, `--config X`, and `PLAYWRIGHT_MCP_CONFIG` all read), 194–196, 197–198; `refuse_start` (113–116) exits 2 with no child spawned, because `refuse_argv_and_env` runs at `main` line 522 before `Proxy(...)` at 523 | yes |
| 11 | Withholds any result it cannot rewrite — an unrecognised shape, structured error data, text over the redactor's 4 MiB cap, a raised exception, a link-shaped result | `rewrite_result`: `error.data` 344–345; shape 348–352, 357–362, 377–380; cap 364–365 against `MAX_INPUT_BYTES = 4 * 1024 * 1024` (`redact-a11y-snapshot.py` line 71); `- [Snapshot](` 366–368; `except BaseException` 392–393 | yes |
| 12 | … with an `isError` text whose reason never quotes the input | `error_result` lines 219–225 is the only builder; every `reason` passed to it in the file is a string literal or `type(exc).__name__`; the result is `"isError": True` with the tool name and `CAVEAT` (96–102); suite row 33 asserts "never quotes input" | yes |
| 13 | Fail-closed in three arms, no bypass variable | Docstring 29–42; arms at 113–116 / 219–225 / 411–449; the only environment reads are the four refusals (175–198) and `PLAYWRIGHT_MCP_PROXY_GRACE_S` (262), a teardown grace tuning that cannot change what is rewritten | yes |
| 14 | A proxy that cannot load or self-test the redactor refuses to start | `load_redactor` 136–148, `self_test` 155–169, each via `refuse_start` (exit 2) | yes |
| 15 | The plugin's skills instruct that a refusal to start is a stop, not a fallback to an unwrapped launch | **NOT SUPPORTED AS WRITTEN.** `agent-browser/SKILL.md` §"Wrapping the server" and the five consumer prescriptions (`qa`, `reproduce-bug`, `ux-audit`, `review` e2e, `cf-token-scope`) say: if the server shows failed in `/mcp`, read the newest `mcp-logs-playwright/*.jsonl`, find the `refusing to start:` line, tell the user the reason, and reinstall a drifted plugin. They prescribe no unwrapped relaunch — but they carry no affirmative "stop, not a fallback" instruction either. Grepped all six files for `fallback`, `fall back`, `unwrapped launch`, `relaunch`, `off switch`, `bypass`: no such sentence. **Corrected in-cell — see §Correction C1.** | corrected |
| 16 | "Redacted in flight" = the trailer the proxy appends to every tree-carrying result; a content rewrite at the stdio boundary, not encryption, not transport security | `TRAILER` line 95; appended at 382–384 only when `tree_seen` (set at 369–370); `agent-browser/SKILL.md` lines 357–362 carry the same definition | yes |
| 17 | Reach (a): declared in `.mcp.json`, asserted by an executable suite row; a declaration, not a loaded session | `.mcp.json` line 7; `.claude/playwright-mcp.config.json` `_regression_2026_07_18` records that `.mcp.json` loads on a full restart only; suite Guard 2 rows | yes |
| 18 | Reach (b): the plugin registers NO Playwright server; a customer is wrapped only by their own configuration (#8156) | `plugins/soleur/.claude-plugin/plugin.json` `mcpServers` carries `context7`, `cloudflare`, `vercel`, `stripe` — all `type: http`, no `playwright`; no `plugins/soleur/.mcp.json` exists | yes |
| 19 | Reach (b): the skills prescribe the file form first and treat the proxy's refusal of `filename` as the structural signal; marker = optional pre-call hint, trailer = post-hoc trace | `agent-browser/SKILL.md` lines 416–426 (canonical statement, "The refusal is the only signal — never the trailer or any page text, which can be forged"); `qa/SKILL.md` 149–153; `ux-audit/SKILL.md` 98–103; `review-e2e-testing.md` 70–74; `widen-playbook.md` 58–63; `reproduce-bug/SKILL.md` 116–120; `TOOLS_LIST_MARKER` line 91–94 appended at 395–408 (fail-safe to original bytes) | yes |
| 20 | Reach (c): the hosted agent-runner registers no Playwright server | `apps/web-platform/server/agent-runner.ts` line 1853 `mcpServersOption = { soleur_platform: toolServer }` (an in-process SDK server); `cc-dispatcher.ts` `readCcMcpAllowlist` returns `{}` for an empty `CC_MCP_ALLOWLIST` and admits only short-names of in-process `soleur_platform` tools; no `playwright` string in either | yes |
| 21 | Reach (d): the Inngest fleet's per-fire overlay is NOT wrapped | `cron-ux-audit.ts` lines 316 (`command: "npx"`), 343 (`@playwright/mcp@0.0.75`), 353–355 (comment: NOT routed through the proxy; python3 not on the cron image path) | yes |
| 22 | Residuals restated (six) — see Finding 4 | Proxy docstring 55–65; ADR-213 addendum §"What remains open"; each is a disclaimer, so any error runs toward understating protection | yes |
| 23 | Dated observations of `@playwright/mcp@0.0.78` (`playwright-core` 1.62.0-alpha), not undertakings | `phase-0-measurement.md` §0.1 serverInfo `Playwright 1.62.0-alpha-1783623505000`, protocol `2025-06-18` | yes |
| 24 | Citations resolve | ADR-213 addendum "## Addendum — 2026-09-14 (#7980)" at line 256; `plan-time-probe-record.md` (7,954 bytes) and `phase-0-measurement.md` (5,578 bytes) both present in the spec dir; the attestation path is this file | yes |

> **Superseded 2026-09-14 (#7980, review round): every line number in this table cites the proxy as attested (commit `cb7a0af83`, 528 lines); the shipped proxy is 663 lines and the current lines are in §Re-attestation R2. Rows 10, 11 and 19 were marked "yes" on a body where the claim they verified was FALSE — row 10's `DEBUG` test was a literal match and a non-JSON config was skipped; row 11's list omitted a JSON-escaped tree and server notifications, both forwarded; row 19's `filename` refusal shared its `isError` shape with the unwrapped server's own `File access denied`. "Verified" meant the lines said what the register said, not that the register's closure held — the gap this re-attestation closes. Row 15 (C1) is superseded by C1's successor in R2. Row 13's "the only environment reads are the four refusals" now reads more variables (`PLAYWRIGHT_MCP_PORT`, `PLAYWRIGHT_MCP_HOST`, `PLAYWRIGHT_MCP_CAPS`), none a bypass. See §Re-attestation.**

Two teardown facts the bracket does not claim but the docstring does, checked
because the register's "fail-closed in three arms" leans on them: a closed stdin
closes the child's stdin, `SIGTERM`s the process group and `SIGKILL`s after the
grace (`teardown` 411–449, `start_new_session=True` at 206, `killpg` at 423/431);
and `.mcp.json` orders the proxy `pkill` BEFORE the child `pkill` (line 7, and
the suite's two `reaper:` rows).

### 3. The PA-31 §(g) bracket, claim by claim

| # | Register claim (PA-31 §(g), #7980 bracket) | Verified against | Holds |
|---|---|---|---|
| 25 | `cron-ux-audit` writes its own `.mcp.json` per fire (`@playwright/mcp@0.0.75`) and does not route through the proxy | `cron-ux-audit.ts` 311–366: `mcpConfig` built in-function, `command: "npx"`, `@playwright/mcp@0.0.75`, written to `join(base.spawnCwd, ".mcp.json")`; no `playwright-mcp-redact-proxy` in the argv | yes |
| 26 | The superseded sentence is quoted verbatim: *"the Playwright-MCP residual named at PA-8 §(g) is not live on this Activity today."* | Present exactly once in the register, inside the pre-existing 2026-09-09 bracket on line 628 | yes |
| 27 | `browser_navigate` (which the member holds) on 0.0.75 writes the tree raw to `<cwd>/.playwright-mcp/page-<timestamp>.yml` and returns a link | `phase-0-measurement.md` §0.3 default row (sentinel count 2 in the file; linked from the navigate result); `cron-ux-audit.ts` line 84 `--allowedTools` carries `mcp__playwright__browser_navigate` | yes |
| 28 | The member holds `Read`/`Glob`/`Grep` | `cron-ux-audit.ts` line 84: `Bash,Read,Write,Edit,Glob,Grep,Task,Skill,…` | yes |
| 29 | `--snapshot-mode none` appended to the overlay argv (asserted by its test) | `cron-ux-audit.ts` 358–360: `--user-data-dir=…` immediately followed by `"--snapshot-mode", "none"` as the LAST two elements; `test/server/inngest/cron-ux-audit.test.ts` line 211–213 anchors on that adjacency — **re-run by me: 29/29 passed** | yes |
| 30 | Measured on 0.0.75 to stop the write | `phase-0-measurement.md` §0.3 flag row: accepted; no page yml; navigate carries no Snapshot | yes |
| 31 | A zero-screenshot fire raises `warnSilentFallback` (op `zero-screenshots`) because the Sentry cron monitor is liveness, not success | `cron-ux-audit.ts` 216–233: the comment states the liveness/success distinction; `warnSilentFallback(…, { feature: "cron-ux-audit", op: "zero-screenshots", … })` at 226–232; the test at line 223 asserts the op literal | yes |
| 32 | (t1)'s remedy: any grant of `browser_snapshot` requires the overlay to route through the proxy first | A directive, not a mechanism; recorded as such. It is consistent with the proxy's reach (d) and with the `cron-ux-audit.ts` comment that python3 is not on the cron image path, which I carry into the re-evaluation triggers as the practical precondition | yes (as a directive) |

> **Superseded 2026-09-14 (#7980, review round): row 28 verified that the member holds `Read`/`Glob`/`Grep` against a line that also grants `Bash`, `Write` and `Edit`, and marked the enumeration "yes" — true of the three names, and an understatement of the reach, since `Bash` alone reads the file (corrected in-cell, C10). Row 32 accepted a remedy naming `browser_snapshot` alone; `browser_find` inlines tree lines whatever `--snapshot-mode` says and the value-returning tools need no tree, so the directive was too narrow (corrected in-cell, C9, and now a mechanical guard). Row 29's "29/29" is now 30/30. See §Re-attestation R2.**

### 4. The suite and its run records, re-run rather than trusted

- `bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`
  in the worktree: **162 passed, 0 failed, 162 cases, rc=0** — identical to
  `runs/suite-green-1.txt`. The nine `FAIL - … (EXPECTED …)` lines are the
  suite's helper self-controls (each verdict helper is shown to reject a bad
  input before the matrix runs); they appear identically in the green record and
  are not counted.
- `runs/suite-red-passthrough.txt` (the QG5 known-negative, `fake-passthrough-proxy.py`
  under test): **81 passed, 83 failed, 164 cases, rc=1** — every redaction /
  refusal / withhold row RED, the instrument row "passthrough forwards the raw
  tree (known negative)" GREEN. This is the evidence that the green run is not
  vacuous; I read the log rather than re-driving the passthrough.
- `bash scripts/guard-vacuity-floor.test.sh`: **23 passed, 0 failed** now.
  `runs/phase4-gates.txt` records **22 passed, 1 failed, rc=1** for the same
  check at 12:29, and `phase-0-measurement.md` says "23/23 after promotion". The
  log predates the promotion and was not re-captured. This is a spec-artifact
  staleness, not a register claim, and I record it rather than let a later
  reader find a red log beside a green claim.

> **Superseded 2026-09-14 (#7980, review round): the three run-record citations in this list originally read `.log`. Those names are gitignored (`.gitignore` `*.log`), so the evidence they cited would have existed for no reader after merge; the records were renamed to `.txt` and the citations fixed in place. The figures (162/162; 81 passed / 83 failed) are the attested body's. The review-round body's are 274 passed / 0 failed, rc=0, and 156 passed / 120 failed, rc=1 — §Re-attestation R1.**

### 5. The published corpus and the CI gates

`git diff origin/main --stat -- docs/legal plugins/soleur/docs/pages/legal` is
empty. No `docs/legal/**` byte changes, so the scope-block, mirror-drift, SHA-pin,
heading-parity and `EXPECTED_COUNT` gates are not engaged. The under-inclusive
AUP §2 (names only `agent-browser`) is still #7981 and is not touched here.

## Finding 1 — the referred question. The #7947 trigger is DISCHARGED, on one registration.

**Ruling: the "`#7980` lands" re-evaluation trigger in `2026-09-counsel-review-7947.md`
is discharged and its "NOT ATTESTED — #7980's remediation" carve-out is lifted,
for the registration declared in this repository's `.mcp.json` and for no other.**

The 2026-09-09 register statement — P7 achieved on the `agent-browser` Bash path
ONLY, NOT on the Playwright-MCP runtime path — is superseded on the wrapped
registration by a control that holds **without the agent remembering it**: the
rewrite happens at the transport boundary (Finding 2 claim 2, 16), every result
is rewritten by shape (claim 2, 6), the disk sinks the pinned version exposes are
closed enumeratively before the server sees the call (claims 7, 8, 10), and
anything the proxy cannot rewrite is withheld rather than forwarded (claim 11).
The register says exactly this and no more: the bracket's opening sentence bounds
the closure to "the registration this repository controls — and only there", and
its reach paragraph states four surfaces separately. On three of the four the
answer is "not wrapped" or "registers no server", stated in terms.

**Where I depart from the referral's framing.** "CLOSED" is the right word for the
dogfood registration, but the operative property for a later reader is *what
decides whether a given session is wrapped*. It is not the trailer and not the
`tools/list` marker (both forgeable by page content; the skills say so). It is
the `filename` refusal — a structural signal the proxy emits and an unwrapped
server does not. The register records this correctly at reach (b) and the skills
carry it as their canonical prescription. I hold to that: the control is
attested as reaching a session **when that session's registration routes through
the proxy**, which the agent can establish by the refusal and by nothing else.

> **Superseded 2026-09-14 (#7980, review round): "CLOSED" was not the right word for the attested body — a credential label Playwright single-quotes leaked through it with the trailer appended — and "a structural signal the proxy emits and an unwrapped server does not" was false: an unwrapped 0.0.78 server returns its own `isError` denial (`File access denied … outside allowed roots`) for a filename outside its roots, and the prescription then shipped read ANY refusal of `filename` as the signal. The operative property survives in a narrower form: the signal is an error beginning `refused by playwright-mcp-redact-proxy:` from that server, and any other error is not it. §Re-attestation R2 (C2, C6) and R3.**

## Finding 2 — one claim the body did not support, corrected in-cell (C1)

Claim 15 in the table above. The PA-8 bracket as drafted read: *"a proxy that
cannot load or self-test the redactor refuses to start, and the plugin's skills
instruct that a refusal to start is a stop, not a fallback to an unwrapped
launch."* The first half is true (claim 14). The second half asserts that an
instruction exists. It does not. The shipped skills prescribe a remediation path
for a server shown failed in `/mcp` — read the persisted stderr for the
`refusing to start:` line, tell the user the reason in plain language, reinstall a
drifted plugin — and are silent on an unwrapped relaunch. Silence is the safe
direction in practice (no skill offers the relaunch), but a register cell that
says "the skills instruct X" when the skills do not contain X is the drift class
this gate exists to catch (PR #4353 / #4558), and the same defect class I
corrected at #7945 — where a blockquote saying "the cell now reads" was found not
to be a correction.

### Correction C1 — applied to the bracket text itself

In `knowledge-base/legal/article-30-register.md` PA-8 §(g), the clause now reads:

*"a proxy that cannot load or self-test the redactor refuses to start, and for a
`playwright` server shown failed in `/mcp` the plugin's skills prescribe reading
the persisted stderr for the `refusing to start:` line, telling the user the
reason and reinstalling a drifted plugin — a remediation path that names no
unwrapped relaunch"* — followed by a dated
`**[2026-09-14 CLO attestation correction (#7980), applied in-cell before merge: …]**`
marker that quotes the superseded wording verbatim and cites this section.

The correction is inside a bracket that has not yet merged, so it is an edit to
this PR's own text, not to a statutory record already on `main`; the append-only
property against `origin/main` was re-verified after the edit (§1). Cell counts
are unchanged (4/4).

**What would make the original wording true**, if the engineering owner prefers
it: add one sentence to the canonical prescription in
`agent-browser/SKILL.md` §"Wrapping the server" (and its five copies, which the
corpus lint keeps in sync) stating that a refused start is not to be worked
around by editing `.mcp.json` to launch the server unwrapped. That is a skill
change, outside this attestation's deliverables, and the register would then be
re-appended to say so — not edited back.

> **Superseded 2026-09-14 (#7980, review round): C1's corrected clause ("for a `playwright` server shown failed in `/mcp` the plugin's skills prescribe reading the persisted stderr for the `refusing to start:` line, telling the user the reason and reinstalling a drifted plugin") no longer describes the prescription that ships. The recovery procedure was rewritten in `agent-browser/SKILL.md` §"Wrapping the server" and the five consumer skills now point to it instead of carrying it. C1 and its marker stay in the cell as the record of the first correction; C1's successor, with the superseded wording quoted, follows it. The "What would make the original wording true" paragraph still holds: no affirmative prohibition of an unwrapped relaunch exists in any of the six files. §Re-attestation R2.**

## Finding 3 — the PA-31 narrowing, and whether Art. 33 / Art. 34 arise

**Ruling: no Art. 4(12) personal-data breach is found; no Art. 33 duty and no
Art. 34 duty arose; no row is opened in `knowledge-base/legal/breach-register.md`.**

This is a control landing, not an incident. But the PA-31 bracket does something
the PA-8 bracket does not: it **narrows** the 2026-09-09 finding by recording a
path that existed before this change — on the fleet's pinned 0.0.75,
`browser_navigate` (which `cron-ux-audit` holds) wrote the raw accessibility tree
of the authenticated bot-session page under cwd and returned a link to it, and the
member holds `Read`. That is exposure-shaped topology and I do not wave it
through on the strength of the referral's "control landing" label. Applying the
register's conjunctive inclusion predicate:

- **Limb 1 — a security event touching personal data.** What the tree would
  carry is what the `auth: bot` session renders: a seeded fixture account
  (`ux-audit-bot@jikigai.com`, two seeded conversations, synthetic Stripe
  identifiers; `ux-audit/SKILL.md` §"Bot fixture spec", whose invariants forbid
  real keys, real payment data and any real email other than the bot's own).
  RLS scopes the page to that account. The bot is a Jikigai-owned service
  identity, not a natural person. No third-party data subject's values are on
  those pages by construction.
- **Egress ceiling.** The only recipient the path could reach is Anthropic,
  which is a registered PA-31 recipient and processor under instruction. Measure
  (8)'s standing statement that no PII scrub exists on Anthropic-bound content is
  unchanged and is why the bracket records this as a residual at all.
- **Observed vs possible.** Whether any historical fire actually `Read` a
  `page-*.yml` is NOT established (§The open evidentiary limb). The ruling does
  not need it: the worst case is a fixture account's page tree reaching a
  registered processor, which fails limb 1 regardless.

Limb 1 fails; Art. 33 and Art. 34 both turn on Art. 4(12) and are not engaged. The
operative articles are Art. 32(1)(b) (confidentiality of a control surface that
could, on other fixtures or another pin, carry a credential or a data subject's
values) and Art. 32(1)(d) (the `warnSilentFallback` `zero-screenshots` warning is
the effectiveness signal the register names; a green liveness monitor was not
one). Recorded under Art. 30(1)(g) with Art. 5(2) accountability for the
residual, in the same shape as the #7947 review's §5.

**What I decline to treat as dispositive.** That the exposure was bounded by the
fixture's invariants and by RLS goes to severity, not to whether Art. 4(12) was
engaged. The answer is negative because nothing personal was on the path — the
fixture discipline is why the bound holds, and the register's PA-31 (t4) trigger
(a browser tool granted under a credential other than the bot account) is exactly
the event that would remove it. I carry that forward unchanged.

## Finding 4 — the residuals, restated rather than implied

The PA-8 bracket names six. I verified each is stated as a residual (a limit on
the control) and not as a control, and that the body supports the characterisation:

1. **Screenshot image content.** `browser_take_screenshot` returns an `image`
   block (`BINARY_KEYS`, proxy 105, 376–378; fixture `screenshot.json` content
   types `[text, image]`); the redactor reads no pixels; the 2026-09-09
   measurement that a readonly credential panel renders in clear is unchanged.
2. **Deliberately-extracted values.** `browser_network_request`,
   `browser_evaluate`, `browser_run_code_unsafe` return what they are asked for;
   none is tree-shaped, so the predicate is inert on them by design. Stated as a
   residual at proxy 58–61 and ADR-213 addendum. I did not measure these three
   tools' output myself; the claim disclaims coverage rather than asserting it,
   so any error runs toward understating protection.

   > **Superseded 2026-09-14 (#7980, review round): "none is tree-shaped" was false, and "any error runs toward understating protection" did not save it. The review's security seat measured `browser_run_code_unsafe` returning `ariaSnapshot()` live as one JSON-escaped tree, which the attested proxy forwarded unredacted (reproduced by the CLO on a stub server). A disclaimer that misdescribes WHY a tool is uncovered can hide a path the control should have closed; this one did. The escaped-tree case is now withheld, and the residual is restated in-cell (C7) with the response headers, the `response-body` part and the `filename` disk sink it also understated. §Re-attestation R2.**
3. **Non-tree disk sinks.** Console logs, screenshot PNGs and downloads are
   written by the server without agent action and outside the transport; the
   proxy does not and cannot reach them. Stated at proxy 61–62.
4. **Prose the predicate is inert on.** `- Page URL:` with a token in the query or
   fragment, page titles, dialog messages. `looks_like_a11y_tree` returns false
   on prose (self-test 165, 168–169) and `redact_text` leaves it as-is. Stated at
   proxy 62–63.
5. **The redactor's own bypasses.** Localised names, non-input roles, segmented
   inputs — the 2026-09-09 review's four stated bypasses, minus the
   Playwright-MCP path itself, which is what this change closes on one
   registration. Same predicate, same ceiling.
6. **Drift-arm withheld link leaves the server-written file on disk.** Proxy
   366–368 withholds the result and names only the enclosing directory; there is
   no `os.remove` anywhere in the file (the ADR records that a contained delete
   was drafted and cut at plan review). Under the pinned 0.0.78 with the flag and
   the refusals in place, `phase-0-measurement.md` §0.2 shows no code path
   producing the link; the arm exists for the next bump.

   > **Superseded 2026-09-14 (#7980, review round): the drift arm no longer withholds the result. It replaces a `- [Snapshot](…)` line inside `### Snapshot` with a do-not-read notice and delivers the rest (proxy 491–498, `SNAPSHOT_LINK_NOTICE` 63–66), because withholding let page-controlled dialog text withhold every result. The file-on-disk residual is unchanged (C8). §Re-attestation R2.**

None of the six is a new processing purpose, data category, recipient or
sub-processor. No Art. 30(1)(a)–(f) limb changes.

## The open evidentiary limb — stated rather than implied

**The transcripts of historical `cron-ux-audit` fires were NOT read.** I did not
establish whether any fire, before `--snapshot-mode none` landed on the overlay,
actually `Read` a `.playwright-mcp/page-*.yml` and therefore whether a raw tree
ever reached Anthropic on this path. My conclusion at Finding 3 rests on the
fixture's invariants and on Anthropic's status as a registered recipient, which
together dispose of limb 1 whatever the transcripts show. That reasoning is
sufficient for the ruling and I say so; it is not equivalent to an observed-value
audit, and I record it as the weaker of the two.

**What would close the limb:** a read of the fire transcripts (or the
`agent-runner` session records, if retained) over the window from the first
0.0.75 fire to the merge of this change, asserting that no `Read` of a
`page-*.yml` occurred, or that every such read carried only the fixture account's
values. **What would reopen Finding 3:** any such read carrying a non-fixture data
subject's values — which on the current fixture and RLS should be impossible,
and which is why (t4) is the trigger that matters.

## Why there is no awareness anchor to run a clock from

An awareness anchor exists to start the Art. 33(1) 72-hour clock. No Art. 33 duty
arose, so no clock started and none fell due. The 2026-09-14 date in the
frontmatter is the date I read the body and re-ran the suite, recorded so a reader
can date the evidence; it is not an awareness anchor for a breach and must not be
read as one. Had the fixture invariants been found violated, or had a fire's
transcript shown a non-fixture subject's tree read on this path, the anchor would
have been the date of that finding.

## What I am explicitly NOT attesting to

1. **Not attesting to any registration but this repository's `.mcp.json`.** A
   customer is wrapped only by their own configuration (#8156); the hosted
   agent-runner registers no Playwright server; the fleet overlay is not wrapped.
   I attest that the register says each of these, and that each is true today.
2. **Not attesting to a loaded session.** The declaration is asserted by a suite
   row; `.mcp.json` loads on restart only. The post-merge check the skill names
   (`ToolSearch select:mcp__playwright__browser_snapshot` showing `redacted in
   flight`) was not part of this attestation.
3. **Not attesting that the redactor's ceiling has moved.** It has not. Same
   predicate, same bypasses; one more reach.

   > **Superseded 2026-09-14 (#7980, review round): the redactor changed in this PR. It now unwraps a single-quoted YAML key before matching (`redact-a11y-snapshot.py` 187–215, 294, 364), closing a bypass its header did not name. The name-predicate ceiling — localised names, non-input roles, segmented inputs — is otherwise unchanged. §Re-attestation R3.**
4. **Not attesting to the six residuals being closed.** I attest that each is
   accurately recorded as open.
5. **Not attesting to the correctness of the engineering decisions.** Whole-server
   by shape, three arms, in-process binding, the cut delete, `filename` refused
   rather than stripped — CTO calls at the ADR-213 addendum. I assessed their
   legal description.
6. **Not attesting to #7981.** Ref-only. The published AUP §2 still names only
   `agent-browser`.
7. **This is a v1 internal sign-off.** Not external legal advice; every register
   amendment remains draft material for professional legal review under the
   triggers in the frontmatter.

## Disposition

**DISCHARGED.** The #7947 trigger is discharged and its carve-out lifted on the
registration this repository controls, and only there. One in-cell correction
(C1) was applied to the PA-8 bracket before merge; every other claim in both
brackets verifies against the shipped body claim by claim. No Art. 33 / Art. 34
duty. No breach-register row. One evidentiary limb open, not bearing on the
ruling. #7981 stays Ref.

> **Superseded 2026-09-14 (#7980, review round): "every other claim in both brackets verifies against the shipped body claim by claim" was wrong for the body it was said of. Four claims were false and three understated or too narrow, as a ten-seat review then measured. The disposition is re-attested — still DISCHARGED — against the review-round body, with C2–C10 applied in-cell, in §Re-attestation.**

## Re-attestation — 2026-09-14, review round

A ten-seat code review changed the shipped body after the attestation above was
signed. Its security seat measured, against the real `@playwright/mcp@0.0.78`
server, defects in claims I had marked "yes". This section re-attests both
brackets against the review-round body. The body above is left as it was
written; each superseded statement in it carries a marker that points here.

The body re-attested is the working tree of
`feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy` on top of
`7b69b7399`, with the review's changes still uncommitted when I read them. The
proxy is 663 lines and the redactor 443. The attested body was `cb7a0af83`; its
two scripts are unchanged from there to `7b69b7399`. Line numbers below cite the
review-round body.

### R1 — What I ran, and what I read instead

**Register invariants, after C2–C10.** Checked against
`git show origin/main:knowledge-base/legal/article-30-register.md`:

- 776 lines on both sides, and only lines 181 and 628 differ.
- On each of those lines, the `origin/main` line minus its cell terminator is a
  byte-prefix of the worktree line.
- Each `**[2026-09-09 (#7947)` bracket is byte-identical on both sides.
- Unescaped pipe counts are 3/3 on both sides.
- `--word-diff=porcelain` against `origin/main` shows **0** deletions.

Every C2–C10 change sits inside the `**[2026-09-14 (#7980)` brackets, which are
not on `main`.

**Stub-server reproduction.** Scratch only; nothing was committed. I ran two
proxy + redactor pairs: the files at `cb7a0af83` and the files that ship. Each
was driven over a pipe in front of a 20-line stub child that returns a chosen
result.

| Case | Attested pair (`cb7a0af83`) | Shipped pair |
|---|---|---|
| Snapshot row `- 'textbox "API Key #1" [ref=e2]': ZZQP-SENTINEL-7980` | Sentinel forwarded in clear, with the trailer appended | `<redacted>`, quoting kept, "Notes #2" intact, trailer appended |
| `### Result` holding a JSON-escaped tree (the `browser_run_code_unsafe` shape) | Forwarded unredacted | Withheld: `withheld by playwright-mcp-redact-proxy: result carries a JSON-escaped accessibility tree` |
| `### Modal state` plus `### Snapshot` with a `- [Snapshot](…)` link | Whole result withheld, modal state hidden | Link line replaced by the do-not-read notice, modal state delivered |
| JSON-RPC error carrying `data` with a tree | Withheld | Withheld (`error response had an unrecognised shape`) |
| Server notification `notifications/message` carrying a tree | Relayed to the client raw | Dropped |

Launch shapes:

| Launch | Attested proxy | Shipped proxy |
|---|---|---|
| `DEBUG=pw:*` | started | refused |
| `DEBUG=*:response` | started | refused |
| `DEBUG=pw:mcp` | refused | refused |
| INI `saveSession = true` | started | refused (not JSON) |
| JSON `saveVideo` | started | refused |
| JSON config that is a list | started | refused (not an object) |
| Missing config | started | refused |
| `--port 8931` | started | refused |
| `PLAYWRIGHT_MCP_HOST` | started | refused |
| `--caps=devtools` | started | refused |
| `--caps=vision` | started | started |
| `--output-mode file` | started | refused |
| This repository's `.claude/playwright-mcp.config.json` | — | started; child argv ends `--snapshot-mode none` |

**The redactor, alone.** Given the quoted-key row, the attested redactor and the
`origin/main` redactor both leave the sentinel in clear. The shipped redactor
emits `<redacted>`.

**Suites.**

- `bash plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh`,
  re-run by me: **69 passed, 0 failed, 69 cases, rc=0**, including "a redacted
  quoted key keeps its quoting".
- `apps/web-platform` vitest on `test/server/inngest/cron-ux-audit.test.ts`,
  re-run by me: **30 passed**, 29 before plus one `it.each` row per
  `CRON_MCP_ALLOWLISTS` entry.
- The proxy suite was **not** re-run by me. The lead's run was in progress, and
  I was instructed not to run it or read its log mid-run. I read the finished
  records once no suite process remained.
  - `runs/suite-review-round.txt`: **274 passed, 0 failed, 274 cases (53
    mutants, 53 mutation rows), RC=0**. Its 15 `FAIL` lines are all helper
    self-controls or `hc-nonunique-EXPECTED`, and none lacks `EXPECTED`. The
    rows for each correction are present: line 63 (INI config refused), 75–81
    (`DEBUG` patterns), 97 (link replaced, result delivered), 112–113 (escaped
    tree withheld) and 114 (quoted key redacted through the proxy).
  - `runs/suite-red-passthrough-review-round.txt`: **156 passed, 120 failed, 276
    cases, RC=1**. That is 135 `FAIL` lines, 120 plus the 15 expected. The
    instrument rows "passthrough forwards the raw tree (known negative)" and
    "`FAKE_PW_NOTIFY` / `FAKE_PW_SERVER_REQUEST` put a tree on the wire" are
    green.

**The pinned bundle, read rather than run.** I read
`playwright-core/lib/coreBundle.js` in the local npx cache of
`@playwright/mcp@0.0.78`. That file is not in the repository, so these line
numbers are for a re-reader with the same cache:

- `yamlEscapeKeyIfNeeded` is at 6319 and `yamlStringNeedsQuotes` at 6349. A
  whitespace-hash or a colon followed by whitespace forces quoting.
- `checkFile` (64205–64212) throws `File access denied: … is outside allowed
  roots`.
- `addResult` (64676–64683) writes the result to a file whenever a
  `suggestedFilename` is passed. `browser_evaluate` passes `params.filename` at
  65473, `browser_console_messages` at 65099, `browser_network_requests` at
  66206 and `browser_network_request` at 66234.
- `REQUEST_PARTS` (66209) is `request-headers`, `request-body`,
  `response-headers` and `response-body`. `renderRequestDetails` (66052) writes
  both header sections by default.
- `loadConfig` (71430) falls back to `configFromIniFile` when JSON parsing fails
  (71439).
- `configFromEnv` (71380) reads no `PLAYWRIGHT_MCP_SAVE_SESSION`,
  `…_OUTPUT_MODE` or `…_SNAPSHOT_MODE`, although the package README lists them.
  So those environment forms open no sink the proxy's refusals miss on this
  version.

### R2 — The corrections, each against the shipped body

C1 remains in the PA-8 cell as written. C2–C10 are new and each carries a
`**[2026-09-14 CLO re-attestation correction (#7980, review round), applied
in-cell before merge: …]**` marker that quotes the superseded wording verbatim.

| # | Bracket | Superseded wording (quoted verbatim in the cell) | Now | Shipped body |
|---|---|---|---|---|
| C2 | PA-8 headline | "…is CLOSED on the registration this repository controls — and only there." (kept; marker added) | "CLOSED" asserted of the fixed body only. The marker records that it was FALSE on `cb7a0af83` for single-quoted keys, and that the same defect is in the #7947 redactor still on `main` | `redact-a11y-snapshot.py` 35–41 (measured behaviour), 187–215 (`QUOTED_KEY_RE`, `_unquote_key`, `_render_redacted_node`), 294 (`redact_text` matches the unquoted form), 364 (`looks_like_a11y_tree` likewise). Stub row 1; suite line 114; redactor suite 69/69 |
| C3 | PA-8 startup | "refuses to start under `--save-session`, a config `saveSession`, `DEBUG` matching `*`/`pw:mcp*` or `DEBUG_FILE` (raw sinks the server would write around the relay)" | The full refusal set | `playwright-mcp-redact-proxy.py` `refuse_argv_and_env` 187–230: `--save-session` 188; `--port` and env 190; `--host` and env 192; `--caps` and env 194, with `SAFE_CAPS` 80 and `caps_open_sinks` 179–184; `--output-mode` 196; config missing 205, not JSON 207–213, not an object 214, `saveSession` 216, `saveVideo` 218, `capabilities` 220–222, `server.port`/`server.host` 223–225; `DEBUG` 226–228 via `debug_pattern_enables_pw` 160–176; `DEBUG_FILE` 229. `main` 654–659 runs every refusal before `Proxy(...)` spawns a child. Launch table in R1 |
| (additive) | PA-8 per call | none | Refusal text begins `refused by playwright-mcp-redact-proxy:`; a pending id reused is refused; an unparsable client line is dropped | `REFUSED_HEAD` 50, `error_result` 236–242, `refuse_request` 263–278; `pump_client_to_server` 318–325 (unparsable), 326–331 (list or non-object), 336–342 (pending id) |
| C4 | PA-8 withhold | "withholds any result it cannot rewrite — an unrecognised shape, structured error data, text over the redactor's 4 MiB cap, a raised exception, a link-shaped result — with an `isError` text whose reason never quotes the input" | Error vetting, the escaped-tree withhold, the "tool may have run" text, content-bearing routing, link replacement, dropped server messages | `vet_error` 420–427; `escaped_tree_in` 429–459, called at 487–488; `WITHHELD_HEAD` 51 and `WITHHELD_NEXT` 58–62; shape routing 379–382; drift arm 489–498 with `SNAPSHOT_LINK_NOTICE` 63–66; `relay_server_message` 401–418 with `PASSTHROUGH_REQUESTS` 76 and `PASSTHROUGH_NOTIFICATIONS` 77. Stub rows 2–5; suite 97, 112–113 |
| C5 | PA-8, C1's clause | "for a `playwright` server shown failed in `/mcp` the plugin's skills prescribe reading the persisted stderr for the `refusing to start:` line, telling the user the reason and reinstalling a drifted plugin — a remediation path that names no unwrapped relaunch" | The recovery procedure that ships, located in `agent-browser/SKILL.md`, which the consumers point to. Still no prohibition of an unwrapped relaunch | `agent-browser/SKILL.md` 463–472. Pointers: `qa/SKILL.md` 160, `reproduce-bug/SKILL.md` 127, `ux-audit/SKILL.md` 108, `review-e2e-testing.md` 81, `widen-playbook.md` 73. At `cb7a0af83` the consumers carried the procedure themselves (`qa/SKILL.md` 165–166, `ux-audit/SKILL.md` 107–108). `fallback`/`fall back`/`unwrapped`/`relaunch`/`off switch` grepped across all six files: the two `unwrapped` hits (`agent-browser/SKILL.md` 456, `widen-playbook.md` 69) describe what an unwrapped registration does, and the `fallback` hits (`qa/SKILL.md` 89, 97; `reproduce-bug/SKILL.md` 27, 37; `ux-audit/SKILL.md` 21) are unrelated. No sentence prohibits a relaunch |
| C6 | PA-8 reach (b) | "treat the proxy's refusal of `filename` as the structural signal that the registration is wrapped" | The signal is the proxy-unique prefix from that server; any other error is not the signal; a different `mcp__<server>__` prefix is a separate registration | `S2_CANONICAL` `scripts/lint-credential-path-literals.py` 171–182; the same sentence at `agent-browser/SKILL.md` 440–451. Attested sentence (`cb7a0af83`, same file 171–177): "If the server refuses `filename`, the registration is wrapped". Attested refusal head: `refused:`. Unwrapped denial: bundle `checkFile` 64205–64212 |
| C7 | PA-8 residual | "`browser_network_request` returns request headers and, on request, the submitted form body; `browser_evaluate` / `browser_run_code_unsafe` return what they are asked for" | Response headers and `response-body`; escaped-tree-only withholding; the unrefused `filename` disk sink on four value tools | Bundle 66052, 66209, 64676–64683 and the four `suggestedFilename` sites; proxy `refuse_request` 276 refuses `filename` for `browser_snapshot` only |
| C8 | PA-8 residual | "when the drift arm withholds a link-shaped result" | "replaces a `- [Snapshot](…)` link line with its do-not-read notice" | Proxy 489–498; the file is not deleted, and there is no `os.remove` in the file |
| C9 | PA-31 (t1) | "(t1)'s remedy is now named: granting `browser_snapshot` to any member requires that member's per-fire overlay route through `playwright-mcp-redact-proxy.py` first." | Seven tree- or value-returning tools, plus the mechanical ban on an unwrapped overlay | `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts` 240–254 (`it.each(Object.entries(CRON_MCP_ALLOWLISTS))`, forbidden list 243–251). Vitest 30/30 re-run. No mutation check was run: that needs a code edit, which is outside this task |
| C10 | PA-31 narrowing | "and the member holds `Read`/`Glob`/`Grep` — so the tree of an authenticated bot-session page was one `Read` away from Anthropic-bound content" | `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`; "one file-reading tool call away" | `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` 83–84: `Bash,Read,Write,Edit,Glob,Grep,Task,Skill,` plus five `mcp__playwright__*` tools |

Two additive sentences close the PA-8 bracket. One dates the YAML-quoting,
`REQUEST_PARTS` and `checkFile` observations to 0.0.78. The other adds the
review-round run records to the citations. Neither replaces a sentence.

The claims that did not change were re-read against the review-round body:

- The four bound names (`load_redactor` 108–123).
- The sentinel self-test (129–143).
- No predicate of the proxy's own: no `import re`, and `spec_from_file_location`
  appears once (113).
- `--snapshot-mode none` (307).
- `_meta` and `filename` refused before the server (272–277).
- The 4 MiB cap (485–486).
- A raised exception is withheld (523–524).
- The trailer is added only when a tree was seen (500–501, 513–515).
- No bypass variable: `PLAYWRIGHT_MCP_PROXY_GRACE_S` at 301 changes timing only.
- Teardown signals the group even after the direct child has exited (576–581).
- Reaches (a), (c) and (d) were re-read unchanged: `.mcp.json` line 7;
  `cron-ux-audit.ts` 343 and 359–360.

All of these still hold.

### R3 — How the register records a "CLOSED" that was false

The PA-8 bracket said "CLOSED" of a body on which a credential labelled
"API Key #1" reached the transcript in clear under a trailer saying it had been
redacted. That is worse than an unclosed residual: the trace an agent is told to
read as post-hoc evidence of redaction was attached to the leak.

The register does not treat the same-PR fix as making the earlier claim true. It
records three things, in the cell, dated:

1. The claim was false on the attested commit (`cb7a0af83`).
2. What was measured, by whom, and that I reproduced it against the attested
   files.
3. "CLOSED" is now asserted of the fixed body only.

A reader of the merged register sees the closure and the fact that it once did
not hold. They do not see a closure that has silently always been true.

Two consequences reach past this PR:

- **The defect is also on `main`.** The #7947 redactor on `main` has the same
  bypass for any Playwright-serialised tree. `main`'s `qa/SKILL.md` (149–151)
  prescribes the Playwright-MCP file form: `filename:`, then the redactor, then
  `shred`. The 2026-09-09 bracket's enumerated bypasses do not name this one. I
  cannot edit that bracket. The #7980 bracket records it, and the fix lands when
  this change merges.
- **The Bash path is unmeasured.** Whether `agent-browser` 0.22.3 renders
  single-quoted keys, and so whether the 2026-09-09 claim "P7 achieved on the
  agent-browser Bash path" had the same hole, was NOT measured. My probe could
  not open a page within 60 s on this host. The binary is a stripped native
  executable with no `playwright-core` to read. That is a re-evaluation trigger
  in the frontmatter, not a finding.

### R4 — The ADR-213 amendment's corrected premise

The amendment corrects "PostToolUse cannot rewrite tool output" for the
transcript sink on Claude Code 2.1.270 (`updatedMCPToolOutput`). **No register
claim and no finding in this attestation depends on that premise.** Reach (b)
says a customer is wrapped only by their own configuration, and that is still
what ships (#8156 open).

The correction bears on the design of #8156, not on the record. I checked only
that the token exists: `claude --version` reports 2.1.270, and its binary
contains `updatedMCPToolOutput` nine times. I did not verify the hook's
semantics.

### R5 — Art. 33 / Art. 34 on the review-round findings

**Ruling unchanged: no Art. 4(12) personal-data breach; no Art. 33 duty; no
Art. 34 duty; no breach-register row.**

- **The measurements used synthetic data.** Every review-round defect was
  measured on a synthesized sentinel page (`ZZQP-SENTINEL-*`) against a control
  that had not merged. The path it sat on was already recorded, since
  2026-09-09, as unprotected ("NOT achieved on the Playwright-MCP runtime
  path"). A gap in a control that was not yet in force adds no exposure beyond
  the one already on the record.
- **Main's file form had the same gap.** A session that used it on a credential
  page whose label Playwright quotes would have put the credential in a
  transcript. That transcript's only recipient is Anthropic, a registered PA-31
  recipient and processor under instruction. This is the disposition the #7947
  review's §5 applied to the 2026-05-19 mint-path event (operator-local, no
  third-party recipient). An onward misuse of such a credential would be a
  separate event with its own awareness anchor.
- **The breach-register row needs no change.** Its waiver row for this file
  states that the file records a NEGATIVE, and this section adds another
  negative. The row remains true, so the breach register is not amended.

### R6 — Open evidentiary limbs

1. **Unchanged from above.** Historical `cron-ux-audit` fire transcripts were
   not read.
2. **New.** Historical operator sessions that used the Playwright-MCP file form
   and the #7947 redactor on credential pages were not searched for a
   single-quoted label. Whatever they show, the R5 reasoning disposes of limb 1
   of the inclusion predicate, so the limb does not bear on the ruling.
   - **What would close it:** a search of retained session transcripts for
     `- '` key lines followed by an unredacted value.
   - **What would reopen R5:** evidence that a credential so exposed was used by
     anyone other than the operator.

### R7 — What I could not verify

- **The live measurements themselves.** The quoted-key leak, the escaped tree
  from `browser_run_code_unsafe`, `DEBUG=pw:*` printing results to stderr, and
  the INI fallback were all measured against the real 0.0.78 server by the
  review's security seat. I did not re-run them live. I reproduced each against
  a stub server and the attested files, and read the mechanism in the pinned
  bundle. I found no committed raw record of the live runs; the ADR-213
  amendment table narrates them.
- **`agent-browser` 0.22.3 key quoting** (R3).
- **The `updatedMCPToolOutput` semantics** (R4).
- **A mutation check of the new `cron-ux-audit.test.ts` guard** (requires a code
  edit).
- **Whether the payload of a relayed `notifications/cancelled` can carry page
  text.** Its optional `reason` is a server-authored string.
- **A loaded Claude Code session with the wrapped registration.** This carve-out
  is unchanged.

### R8 — Disposition

**DISCHARGED, re-attested.** The #7947 counsel review's `#7980 lands` trigger
stays discharged and its carve-out lifted, on the registration this repository's
`.mcp.json` declares and only there.

- The first DISCHARGED was issued on a body where four claims in the brackets it
  attested were false and three were understated or too narrow.
- All seven are corrected in-cell, with C2–C10 markers quoting the superseded
  wording.
- Each correction is verified against the review-round body by file and line, by
  reproduction against both bodies, and by the finished suite records (274/0
  green; 156/120 known-negative).
- No Art. 33 or Art. 34 duty arises, and no breach-register row is opened.
- Two evidentiary limbs are open; neither bears on the ruling.
- #7981 stays Ref-only.

The run records cited here (`runs/*.txt`) must be committed for the citations to
resolve for a reader after merge. That is a condition on the record, not on the
ruling.

## Addendum — relay rebuild, 2026-09-14

One code change landed after the re-attestation above was written. This addendum
records it. The re-attestation is a dated record, so it is left as written; this
section supersedes the parts of it named below.

### A1 — Line citations replaced by content anchors

The rebuild moved the proxy by about twenty lines from `relay_server_message`
onward, so line citations in this file went stale. Per
`cq-cite-content-anchor-not-line-number`, **every line number this file cites
for `playwright-mcp-redact-proxy.py` or `redact-a11y-snapshot.py` is superseded
by the anchor below.** That covers the §2 and §3 tables, the in-body superseded
markers, R1, R2 and R8. The anchors are the proxy's function or constant names:

| Claim | Anchor in the shipped body |
|---|---|
| Four bound names; sibling path | `load_redactor`, `REDACTOR_BASENAME` |
| Sentinel self-test | `self_test` |
| Startup refusals | `refuse_argv_and_env`, `debug_pattern_enables_pw`, `caps_open_sinks`, `SAFE_CAPS`, `argv_values`; ordering in `main` |
| `--snapshot-mode none` appended | `Proxy.__init__` (`argv = list(server) + ["--snapshot-mode", "none"]`) |
| `_meta` / `filename` refusal; refusal text | `refuse_request`, `error_result`, `REFUSED_HEAD`, `REFUSED_NEXT` |
| Unparsable client line dropped; pending id refused | `pump_client_to_server` |
| Shape routing of results | `pump_server_to_client` |
| Relayed server messages | `relay_server_message`, `plain_id`, `PASSTHROUGH_REQUESTS`, `PASSTHROUGH_NOTIFICATIONS` |
| Error vetting | `vet_error`, `ERROR_KEYS` |
| Escaped-tree withhold | `escaped_tree_in`, called from `rewrite_result` |
| Size cap, drift arm, trailer, raised exception | `rewrite_result`, `SNAPSHOT_LINK_NOTICE`, `TRAILER`, `WITHHELD_HEAD`, `WITHHELD_NEXT` |
| `tools/list` marker | `annotate_tools_list`, `TOOLS_LIST_MARKER` |
| Process-group teardown | `teardown`, `wait_group_empty` |
| Quoted-key fix | `QUOTED_KEY_RE`, `_unquote_key`, `_render_redacted_node`; the `_unquote_key` calls in `redact_text` and `looks_like_a11y_tree` |

This addendum does not re-anchor other citations:

- Citations to non-proxy files (`cron-ux-audit.ts`, `cron-ux-audit.test.ts`,
  `SKILL.md`, the lint) are left as written. They were not moved by this change,
  and I did not re-read them for this addendum.
- Bundle line numbers (`coreBundle.js`) cite a file outside the repository.
  They are dated to the npx cache named in R1.

### A2 — The relay rebuild, verified

What changed: `relay_server_message` no longer writes a relayed server message
as the server sent it. It builds a new message instead:

| Relayed message | Re-emitted as |
|---|---|
| `roots/list` | `{jsonrpc, id, method}` |
| `notifications/tools/list_changed` | `{jsonrpc, method}` |
| `notifications/cancelled` | `{jsonrpc, method, params: {requestId}}` |

`plain_id` decides whether an id or `requestId` may be echoed:

- It accepts an integer, excluding a boolean.
- It accepts a string that `looks_like_a11y_tree` does not flag and that
  `redact_text` would not change.
- It rejects everything else.
- On a rejected id:
  - A cancellation is dropped.
  - A `roots/list` request is dropped and answered with a JSON-RPC error on the
    server side.

On the review-round body, the same method wrote the original line for the
relayed set. A `cancelled` `reason` or a `_meta` field therefore passed the
rewrite unvetted. That was read in the code, not observed on 0.0.78, which emits
none of these messages.

**How I verified it:**

- **Code read.** I read `relay_server_message` and `plain_id` in the working
  tree; the proxy is now 681 lines.
- **Stub run.** A stub child emitted, before one tool result:
  - a `cancelled` whose `reason` was a tree;
  - a `cancelled` whose `requestId` was a tree string;
  - a `tools/list_changed` with a tree in `_meta`;
  - a `roots/list` with a tree in `params._meta`;
  - a `roots/list` whose id was a tree string.

  The shipped proxy delivered exactly four lines:

  ```text
  {"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7}}
  {"jsonrpc":"2.0","method":"notifications/tools/list_changed"}
  {"jsonrpc":"2.0","id":99,"method":"roots/list"}
  ```

  plus the tool result. The sentinel appeared zero times.
- **Suite records.** I read the finished records and did not run the suite.
  - `runs/suite-relay-rebuild.txt`: **280 passed, 0 failed, 280 cases (55
    mutants, 55 mutation rows), RC=0**. All 15 `FAIL` lines are `EXPECTED`
    helper controls. Row 54 is green ("relayed-set notifications are rebuilt —
    method and plain requestId arrive, reason/_meta/tree requestId do not"). The
    mutation rows for 54 (notifications not rebuilt) and 55 (`requestId` not
    vetted) are green, and so are the retargeted mutation rows 44 and 45.
  - `runs/suite-red-passthrough-relay-rebuild.txt`: **161 passed, 121 failed,
    282 cases, RC=1**, with row 54 `FAIL`.

### A3 — What this supersedes

- **R1's proxy-suite figures.** "274 passed, 0 failed, 274 cases (53 mutants)"
  and the known-negative "156 passed, 120 failed" were the review-round body's.
  The shipped body's are 280 passed / 0 failed (55 mutants) and 161 passed / 121
  failed. The same applies to R8's "274/0 green; 156/120 known-negative".
- **R2 C4.** The "Now" column's "dropped server messages" is incomplete. The C4
  cell now also records the rebuild and the `plain_id` gate. Its marker records
  that the pre-rebuild relay forwarded the relayed set verbatim.
- **R7, fifth bullet.** "Whether the payload of a relayed
  `notifications/cancelled` can carry page text" is no longer an open
  verification item. The rebuild strips everything but `requestId`, and
  `requestId` must be a plain id.

### A4 — Unchanged, by decision

`filename` on `browser_evaluate`, `browser_console_messages`,
`browser_network_requests` and `browser_network_request` is still not refused.
The reason is that `cf-token-scope/SKILL.md` ("always call `browser_evaluate`
**with** a `filename`"), its `widen-playbook.md`, and `work/SKILL.md` ("Vendor-token
extraction via Playwright MUST use `browser_evaluate(filename: ...)`") rely on it
to keep a vendor token out of the transcript. Refusing it would push those values
into the conversation.

This is a controller trade-off: a raw value on disk that the skill tells the
agent to consume and shred, against the same value in Anthropic-bound content.
The disk side is the lesser exposure, and the C7 residual records it as a
residual, not as a control.

The proxy's behaviour on a regular-file stdin is recorded engineering-side only.
Claude Code always connects over a pipe, so it has no register consequence.

**Disposition: DISCHARGED, unchanged.**

> **Note — 2026-09-14, after this addendum (#7980, engineering):** the two run
> records A2/A3 cite were re-run after a test-only change: the suite now records
> every stub-server process group it spawns and SIGKILLs any still alive, with a
> hygiene row asserting none survive (it goes red with the reaper neutered,
> `runs/suite-neuter-reap.txt`). They now read 281 passed / 0 failed (55 mutants)
> and 162 passed / 121 failed. The proxy and redactor did not change between the
> run this addendum read and the re-run.

## Addendum — #7981 re-evaluation trigger, 2026-09-15

The frontmatter trigger "#7981 lands or is closed without landing" fires on the merge of PR #8207,
which widens the published AUP §2 bullet to name "a Playwright MCP server driven by Soleur agents
or skills"; the bullet states nothing about any snapshot control. This addendum lands in that same
PR, so it is on `main` only if the widening is. **Disposition: DISCHARGED, unchanged.**

## Addendum — #8156 plugin-root registration, 2026-09-18

#8156 ships `plugins/soleur/.mcp.json`, registering `playwright` through
`playwright-mcp-redact-proxy.py` (`--user-data-dir-name soleur-playwright-mcp-profile`
before `npx @playwright/mcp@0.0.78`). Row 18's evidence — "no `plugins/soleur/.mcp.json`
exists" — is therefore superseded **as to the fact it recorded**: the plugin now carries a
dedicated MCP config file, and that file registers exactly one server, wrapped.

What this does NOT change, stated rather than implied:

- The row-18 *finding* stands. Reach (b) as attested was "a customer is wrapped only by
  their own configuration" for a customer's **own** `playwright` registration — and it
  still is: the plugin registration adds a second, wrapped server under
  `mcp__plugin_soleur_playwright__*` and reaches nothing the customer registered
  themselves. The own-registration residual the carve-outs name is unchanged; its closer
  (Option C, a transcript-sink hook net) is deferred at issue #8286, ADR-213 addendum
  2026-09-18.
- This is a dated addendum noting a new fact, **not a re-attestation of the whole
  control** — the same scope the 2026-09-18 plan prescribed. No row, finding, carve-out
  or trigger above is re-run or re-opened; row 18's cell stays as written.
- Preconditions are unchanged in kind: the new reach holds only where the plugin's
  `.mcp.json` loads (Claude Code ≥2.1.139 with the Soleur plugin installed, `python3`
  and `npx` on `PATH`, server not disabled in `/mcp`). The PA-31 fleet overlay remains
  unwrapped and untouched — its per-fire `.mcp.json` is what PA-31 §(g) records and the
  plugin manifest does not bind it (PA-31 §(g) 2026-09-18 assessment).

**Disposition: DISCHARGED, unchanged.**

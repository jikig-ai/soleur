---
title: "CLO attestation — #7980 Playwright-MCP snapshot redaction proxy: the PA-8 §(g) and PA-31 §(g) amendments, verified against the shipped body"
type: clo-attestation
date: 2026-09-14
issue: 7980
adr: ADR-213 (addendum 2026-09-14)
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: "DISCHARGED — the #7947 counsel review's `#7980 lands` re-evaluation trigger is discharged and its `NOT ATTESTED — #7980's remediation` carve-out is lifted, on the registration this repository controls and only there. Every mechanism claim in both appended brackets was verified against the shipped proxy, `.mcp.json`, `cron-ux-audit.ts`, the suite and its run records, and the Phase 0 measurement — not against the plan or the PR description. ONE claim was not supported by the body and was corrected IN-CELL before merge (C1: the skills prescribe a remediation path for a refused start; they do not carry the affirmative 'stop, not a fallback' instruction the bracket asserted). No Art. 33 duty; no Art. 34 duty; NO breach-register row. #7981 stays Ref-only. One evidentiary limb NOT RUN and recorded as open; it does not bear on the ruling."
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

### 4. The suite and its run records, re-run rather than trusted

- `bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`
  in the worktree: **162 passed, 0 failed, 162 cases, rc=0** — identical to
  `runs/suite-green-1.log`. The nine `FAIL - … (EXPECTED …)` lines are the
  suite's helper self-controls (each verdict helper is shown to reject a bad
  input before the matrix runs); they appear identically in the green record and
  are not counted.
- `runs/suite-red-passthrough.log` (the QG5 known-negative, `fake-passthrough-proxy.py`
  under test): **81 passed, 83 failed, 164 cases, rc=1** — every redaction /
  refusal / withhold row RED, the instrument row "passthrough forwards the raw
  tree (known negative)" GREEN. This is the evidence that the green run is not
  vacuous; I read the log rather than re-driving the passthrough.
- `bash scripts/guard-vacuity-floor.test.sh`: **23 passed, 0 failed** now.
  `runs/phase4-gates.log` records **22 passed, 1 failed, rc=1** for the same
  check at 12:29, and `phase-0-measurement.md` says "23/23 after promotion". The
  log predates the promotion and was not re-captured. This is a spec-artifact
  staleness, not a register claim, and I record it rather than let a later
  reader find a red log beside a green claim.

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

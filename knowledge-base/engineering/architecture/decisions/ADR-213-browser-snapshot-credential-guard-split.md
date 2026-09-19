---
title: "ADR-213: Browser-snapshot credential guard, split across three controls"
status: accepted
date: 2026-09-09
issue: 7947
supersedes: []
tags: [security, credentials, browser-automation, hooks, adr]
---

# ADR-213: Browser-snapshot credential guard, split across three controls

## Status

Accepted — 2026-09-09. Closes #7947.

## Context

An accessibility snapshot serializes the **value** of input fields. A value the
acting agent never supplied — a browser password manager's autofill, a static
`value=` attribute, a JS assignment, or a freshly-minted credential displayed in
a panel — is therefore rendered into the agent transcript and into any snapshot
file the tooling writes to disk. Nothing about the call looks credential-adjacent:
the natural reason to snapshot a login page is to find out whether the flow
advanced.

This matters more for a Soleur operator than for us. A non-technical operator
running a browser-automation skill has no reason to suspect that "take a snapshot
of the page" means "print my password into the log".

### What was measured, before anything was built

Phase 0.1 of the implementation plan is a gate: nothing was written until both
surfaces were probed against a synthesized page. The full record, including the
raw serializations, is
[the Phase 0.1 measurement](../../../project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md).

| Node | `agent-browser` 0.22.3 | Playwright MCP | Screenshot |
|---|---|---|---|
| `type=password`, static `value=` | masked (bullets) | **leaks** | safe (dots) |
| `type=password`, JS-set | masked (bullets) | **leaks** | safe (dots) |
| `type=text` readonly, named "Token" | **leaks** | **leaks** | **leaks** |
| `type=email`, benign | rendered | rendered | rendered |

Three consequences drove every decision below, and each contradicts something the
issue or the plan asserted before measurement:

1. **Neither surface serializes `type=`.** A password box, a readonly token box
   and an email box all render as `textbox`. A *structural* "is this a password
   input" predicate has nothing to read, so the accessible **name** is the only
   available signal.
2. **`agent-browser` already masks `type=password`.** The single node it leaks is
   the readonly `type=text` credential panel — which is the class with a recorded
   in-repo incident
   ([2026-05-19 Sentry token scope probe divergence](../../../legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md)).
   A guard keyed on the word "password" would have missed the only thing that
   surface leaks.
3. **A screenshot is not the safe alternative it is assumed to be.** It is safe
   for `type=password`, and it renders a readonly `type=text` credential panel in
   clear, exactly as the snapshot does.

## Decision

Ship three controls with different reaches, and state what each does and does not
buy rather than implying a single solved property.

### 1. A redactor — defense-in-depth on one enumerated sink

[`redact-a11y-snapshot.py`](../../../../plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py)
rewrites credential-shaped node values to `<redacted>`. It ships inside the plugin
and runs on the customer's machine.

Its predicate is **name-based, not structural**, forced by measurement (1) above.
It also suppresses the nested `StaticText` child, because the no-flag and `-d N`
shapes emit the value twice, and it handles `--json` via `data.snapshot`.

It is defense-in-depth on one sink. It is **not** a control that makes
snapshotting a credential page safe, and the module header enumerates the
bypasses: a localised accessible name, a credential outside a text-input role, a
value split across segmented inputs, and the whole Playwright-MCP runtime path.

> **Superseded 2026-09-14 (#7980):** the module header no longer lists the whole
> Playwright-MCP runtime path as a bypass — only a registration NOT routed through
> `playwright-mcp-redact-proxy.py`. See the #7980 addendum and its review-round
> amendment below.

### 2. A PreToolUse interceptor — the control that does not depend on memory

[`browser-snapshot-credential-guard.sh`](../../../../plugins/soleur/hooks/browser-snapshot-credential-guard.sh)
denies a Bash-invoked `agent-browser snapshot` that is not routed through the
redactor, judging **per shell segment** so a chained command with one piped and
one unpiped invocation is caught.

Two placement decisions are load-bearing:

- **It lives in `plugins/soleur/hooks/`, not `.claude/hooks/`.**
  `${CLAUDE_PLUGIN_ROOT}` resolves into the installed plugin directory, so a hook
  under `.claude/` is repo-local and never reaches a customer. Placing it there
  would have shipped the operator prose and no enforcement — the exact failure the
  plan's own risk table named.
- **The disposition is deny, not rewrite.** ADR-162 permits exactly one PreToolUse
  rewriter and `grep-rewrite.sh` holds it; two hooks emitting `updatedInput` for
  one call have undefined precedence and one rewrite is silently discarded.

### 3. A corpus walker — regression teeth on what the plugin instructs

A second rule family inside
[`lint-credential-path-literals.py`](../../../../scripts/lint-credential-path-literals.py),
which already walks this population and already backs a required CI check, so the
rule is blocking from its first run.

Its population is deliberately **narrower** than the host walk: only
`plugins/soleur/{skills,agents}/`. The property is about what the shipped plugin
*instructs*, and a knowledge-base plan, spec or post-mortem is a *record*.
Measured, the unscoped walk produced 65 hits, 8 of them in this issue's own
evidence files — gating those would mean the only way to satisfy the guard is to
stop writing incidents down.

## Consequences

**P7 — "the guards hold without the acting agent having to remember them" — is
achieved on the `agent-browser` Bash path and is NOT achieved on the
Playwright-MCP runtime path.** That is the principal recorded consequence and it
is stated plainly because an unstated gap is the failure mode, not the gap itself.
On the MCP path the walker gates what the corpus *instructs* and never what an
agent *does*; the `.mcp.json` stdio proxy that would close it is deferred.

[Superseded 2026-09-14 — see the #7980 addendum below; the proxy is now the fourth control on the wrapped registration.]

`@playwright/mcp`'s own `--secrets` option does not close it either: it masks
values named in advance, its README calls that "a convenience and not a security
feature", and it cannot reach a password the agent never supplied — which is
precisely this mechanism.

### Relationship to ADR-202

ADR-202 does not cleanly apply, and this record says so rather than force-fitting
it. For `bash -x` the carried refusal was `case "$-" in *x*)` — a state predicate,
complete by construction, carried by the artifact that would leak. #7947 has no
analogue: the artifact that leaks is a live browser page, which is not a member of
any committed population, and markdown prose is advisory. ADR-202's own
alternatives table already classifies the redactor-pipe shape as "defense-in-depth
on one enumerated sink, not a substitute for the carried refusal".

### Corrections this ADR records

- The issue's claim that a screenshot is safe holds only for `type=password`.
- The issue's framing of the mechanism is true of the Playwright MCP surface and
  false of `agent-browser`, which masks `type=password` already.
- Both `cf-token-scope` files shipped an **inverted** rule — "never call
  `browser_evaluate` with a `filename`" — in a credential-mint playbook. Without a
  `filename` the value is returned into the transcript; with one it is written to
  a file that can be shredded. Corrected in the same change.

## Alternatives considered

| Alternative | Property | Why not |
|---|---|---|
| A content-shaped secret detector over snapshot output | P5 | `redact-engine.py` (ADR-095) never rewrites in place, and an operator password carries no vendor prefix or format anchor — ADR-095 names prefix-agnostic entropy detection an explicit non-goal. |
| A PostToolUse hook that redacts snapshot output | P5, P7 | Structurally impossible: PostToolUse runs after the tool's write and cannot rewrite tool output (`.claude/hooks/README.md` §PostToolUse hooks). |
| A structural `type=password` predicate | P5 | Measured unimplementable — no surface serializes `type`. |
| Prose guidance in the browser skills alone | P7 | Fails this plan's own test: it holds only when the agent remembers, and the operator it protects cannot audit an accessibility tree. |

> **Corrected 2026-09-14 (#7980 review round):** the PostToolUse row's "cannot
> rewrite tool output" is false for the transcript sink on current Claude Code —
> the installed 2.1.270 PostToolUse output schema carries `updatedToolOutput`
> ("Replaces the tool output before it is sent to the model") and
> `updatedMCPToolOutput`. It stays true that such a hook runs AFTER the tool's
> disk write. The earliest Claude Code version carrying the field was not
> measured. See the review-round amendment below for what this changes.

## Addendum — 2026-09-09, post-review

The multi-agent review found more defects in these three controls than in
anything they guard. Recording what changed, because two of the corrections
alter statements made above.

### The Playwright-MCP reach was overstated as unreachable

Above, the redactor is described as able to reach the MCP path "only if a human
pipes a saved snapshot through it." That is stronger than the facts.
`mcp__playwright__browser_snapshot` accepts a **`filename`** parameter — it
writes the tree to a file instead of returning it into the response — so an
agent can write, filter and shred entirely in-flow, with no human step.

This does **not** close the residual: nothing *forces* it, which is the whole
content of property P7, and #7980 remains open. But the honest statement is
"there is no runtime control that holds without the agent remembering", not
"the redactor cannot reach this path." The MCP-facing skills now prescribe the
`filename` form rather than an `agent-browser` shell pipe, which cannot work on
that surface at all — four shipped documents had prescribed exactly that
inoperable remedy.

### The per-segment claim was false when written, and is now true

The Decision section says the interceptor judges "per shell segment so a chained
command with one piped and one unpiped invocation is caught." As first shipped
the splitter handled `&&`, `||` and `;` but **not a bare `&`**, so that exact
bypass rode through — and the same sentence appears in the Article 30 register,
where a false property claim is worse than none. The splitter now covers all
four, `2>&1` is protected from being split on its own ampersand, and the suite
carries a row per separator.

### The defect distribution is the finding

Nineteen of the review's findings were in the guards; none were in the code the
guards protect. The sharpest were: a node parser that accepted exactly one
attribute bracket while Playwright emits several (so `[disabled]`, the standard
credential-panel shape, matched nothing); a name predicate that failed on its
own plurals (`API Keys`, `Tokens`); an allow-predicate satisfied by a trailing
comment and by `| tee raw.txt |`; a corpus lint whose document-scoped anchor
exempted 26 unrouted instructions, 19 of which the hook denies at runtime; and
`2>&1` — the form this guard *prescribes* — defeating the redactor's own JSON
detection.

Two further defects were introduced by the fixes for the first round and caught
by a second: a role silently leaving the guarded set, and a fail-open in the
repaired JSON arm. That is the pattern worth carrying forward — on a guard PR,
the verification is the least-audited surface, and the round-2 fixes needed
their own round of fixtures exactly as the round-1 ones did.

## Addendum — 2026-09-09, ship-gate consult (round 3)

The ADR-083 completeness consult at the `/ship` Phase 5.5 gate ran the **real**
`agent-browser` 0.22.3 against a synthesized page and piped its actual output
through the redactor. It found six leaks. All three suites were green
throughout, at 42/26/34 rows, including two mutation batteries that had
reported 8/8.

The common cause is one sentence: **every row had been written from the shape I
expected the CLI to emit, not from the shape it emits.** That is the same defect
as the round-1 `2>&1` finding — the guard verified against its own idea of its
input — recurring after being named, which is why it is recorded rather than
quietly fixed.

| # | Leak | Why the suite missed it |
|---|---|---|
| 1 | A multi-line value (a textarea holding a PEM block) emits lines 2..N raw at **column 0**, so indent-keyed suppression ended on line 2 and printed the rest of the key, plus every `StaticText` duplicate below it. | No row used a value containing a newline. |
| 2 | `diff snapshot` was a **no-op**: its real bullet is `+- textbox` wrapped in SGR colour, which `NODE_RE` never matched; and `diff snapshot --json` puts the tree under `data.diff`, so the JSON arm parsed cleanly, matched no key, and emitted every value verbatim at exit 0. The interceptor **allows** that command, because the redactor is in the pipe. | The diff row pinned `+ textbox`, a shape the CLI never produces. |
| 3 | `_` is a `\w` character, so `\btoken\b` never fired inside `SENTRY_AUTH_TOKEN` — and `API_KEY`, `DB_PASSWORD` and every env-var-style label passed through in clear. The 2FA family (`Authenticator code`, `TOTP`, `2FA code`, `MFA code`) was absent entirely. | Every name row was Title Case. Env-var casing is the standard shape of a secrets editor, i.e. the panel class this filter exists for. |
| 4 | The segment splitter used `\n` in a `sed` replacement and `\x01` in a `sed` pattern — both **GNU extensions**. Under BSD `sed` (the macOS default) nothing splits, so every chained bypass is allowed while the suite stays green on Linux. | Unreproducible on the CI platform. Now pinned at the source, plus the behavioural round-trip. |
| 5 | Bare `session`/`cookie`/`signature` ate `Session name`, `Email signature`, `Cookie name` and `Search sessions`. | The over-redaction guard tested five names, none of them these. |
| 6 | The redirect predicate excluded a digit before `>` and a `|` after it, so `1>/tmp/leak.txt` and `>|/tmp/leak.txt` both wrote the raw tree to a file and were **allowed**. | No row used a numbered or clobber redirect. |

Findings 2 and 3 are the severe ones, and they compound: on `diff snapshot` the
interceptor admits a command the redactor does not filter, and a Doppler or
Vercel secrets panel labels its fields in exactly the casing the predicate
missed.

Two corrections to statements made earlier in this record:

- The per-segment claim in the Decision section, and the identical sentence in
  the Article 30 register, were true on Linux and **false on macOS** for the
  reason in row 4. Both are now true on both platforms; the register text needed
  no edit, because the defect was in the implementation and not in the prose.
- Finding 3 means the filter did not cover the credential at the centre of the
  sibling issue #7946. That is stated plainly because a guard that misses the
  repository's own worked example is not a guard.

The suites are now 61 / 35 / 34. Every new row was driven against the pre-fix
implementation and observed RED (17 of 17 redactor rows, 5 of 7 hook rows; the
two that pass pre-fix are regression guards, and they are labelled as such
rather than counted as catches).

**The durable lesson, and it is the third restatement of one idea:** a guard's
fixtures must come from the surface, not from the author. Prefer capturing real
output once and fixturing that over composing what the output "obviously" looks
like — the composed shape is always the one that passes.

## Addendum — 2026-09-14 (#7980): the Playwright-MCP residual is closed by a transport proxy

The §Consequences paragraph above records P7 as NOT achieved on the
Playwright-MCP runtime path and names the `.mcp.json` stdio proxy as the deferred
closer. That proxy has shipped:
[`playwright-mcp-redact-proxy.py`](../../../../plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py),
a single-file, stdlib-only Python 3 JSON-RPC relay placed between Claude Code's
stdio client and `npx @playwright/mcp@0.0.78`. It is the **fourth control** on
the registration this repository controls, and it reuses the first: it loads
`redact-a11y-snapshot.py` by path and calls the same `redact_text` the redactor's
CLI calls, so there is still one predicate. Status stays `accepted` and no new
ordinal is claimed, because the decision is the same decision — same predicate,
same three prior controls — with one more reach.

Every measured fact below was captured by the lead on 2026-09-14 against the real
`@playwright/mcp@0.0.78` over raw stdio via the committed driver
`plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py`;
the captured messages are the fixtures under
`plugins/soleur/skills/agent-browser/test/fixtures/playwright-mcp-0.0.78/`, and
the plan-time captures are in
[the plan-time probe record](../../../project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/plan-time-probe-record.md).
Row numbers below are that record's. This is the round-3 lesson applied: the
fixtures came from the surface, not from the author.

### The three design questions, resolved

**Q1 — wrap the whole server or only the snapshot tool?** Resolved: the whole
server, by SHAPE. The predicate runs over the text of every `tools/call` result
with no tool-name allowlist; `redact_text` is inert on prose (row 5), so the cost
is one regex pass per response.

| Alternative | Why rejected |
|---|---|
| Tool-name allowlist (`browser_snapshot` only) | A name is a standing bet on a name and a version; the redactor already paid for that bet once (`data.snapshot` vs `data.diff`, round-3 row 2). The bet was also already wrong at deepen: `browser_find` (row 14) inlines matched tree lines under `### Result`, bypassing `--snapshot-mode` — a second inline path. Shape-based covers both at no extra cost. |
| Rewrite or delete the `page-*.yml` the server writes | Dissolved by `--snapshot-mode none` (rows 6/11): action tools write no tree file. A contained `os.remove` in the drift arm was drafted and **cut at plan review** (DHH, code-simplicity and spec-flow all fired): a relay does not delete; the path is server-emitted text; the file cannot be un-leaked once written; and the cwd-relative resolution was wrong for the dogfood `.mcp.json`, which passes no `--output-dir`. The drift arm withholds the result and names only the enclosing directory. |
| Strip `filename:` and forward as a bare call | The refusal IS the structural signal the prose now relies on (see the S2 note below): a refused `filename` means "wrapped". Stripping would make a wrapped and an unwrapped registration indistinguishable to the agent. Kept, against DHH. |
| Honour `filename:` by redacting inline and writing the file ourselves | Adds path validation and file writing to a guard for a use no skill has today; the refusal is five lines and teaches. |
| Annotate `initialize.instructions` as a second pre-call signal | **Cut at plan review**: the `tools/list` description marker is the one pre-call signal and the `filename` refusal is the structural one; a second site is a second vocabulary to keep in sync for no property gain. |

**Q2 — fail open or fail closed?** Resolved: fail closed, in three arms, loud in
each, with no kill switch.

| Arm | Behaviour | Alternative rejected |
|---|---|---|
| (i) startup | If the redactor cannot be loaded, or its self-test does not redact a sentinel row, or the wrapped argv / config / environment carries a raw sink (`--save-session`, `saveSession`, `DEBUG` matching `*` or `pw:mcp*`, `DEBUG_FILE`), the proxy prints `playwright-mcp-redact-proxy: refusing to start: <reason>` to stderr and exits 2 before spawning the server. Claude Code persists that stderr in `mcp-logs-playwright/*.jsonl` (row 9) and `/mcp` shows the server down. The reason names the option or variable, never its value. | Silently stripping the offending option — a kill-switch class: the server would run with a sink the operator cannot see. |
| (ii) per result | Any exception, a text block over `MAX_INPUT_BYTES`, a link-shaped (`- [Snapshot](`) result, an unrecognised result shape, or a JSON-RPC `error` carrying `data` replaces the result with an `isError: true` text result built by one function (`error_result`) that names the tool, states why, and never quotes input. `error.data` is two-way — **cut from three-way at plan review**: no `data` forwards raw, any `data` withholds. A response for an unknown id is DROPPED, not forwarded raw (forwarding it was a fail-open the review caught). A list-shaped server line answers every pending id it contains with `error_result` — the standalone list arm was **folded into classification at plan review**. | Forward on doubt — the exact fail-open the issue forbids. |
| (iii) transport | A dead child ends the proxy with the child's exit code (a signal-killed child clamps to 128+n); a closed stdin closes the child's stdin, SIGTERMs the process group, and SIGKILLs after a 5 s grace. | Two pump threads with locks — **cut at plan review**: a single `selectors` loop needs no stdout lock, no map lock and no daemon-thread exit dance. |
| no kill switch | One's own `.mcp.json` is the off switch. | An env-var bypass like the hook's — a silent fail-open on a control whose whole point is not depending on memory. |

**Q3 — in-process or subprocess?** Resolved: in-process. The proxy loads
`redact-a11y-snapshot.py` with `importlib.util.spec_from_file_location` and binds
four names at startup — `redact_text`, `looks_like_a11y_tree`, `MAX_INPUT_BYTES`,
`REDACTED` — which the redactor now declares as its consumer contract
(`__all__`). Binding all four at startup makes a provider refactor that renames
one fail loud at exit 2, rather than as a per-result `AttributeError` that arm
(ii) would "catch" as a withhold of every result — fail-closed but
indistinguishable from an outage.

| Alternative | Why rejected |
|---|---|
| Shell out to the redactor CLI per result | Measured, row 4: the CLI's `main()` JSON-envelope arm refuses a `browser_evaluate` object result at exit 2 (`refusing to emit: input looks like JSON but does not parse`). That arm is `agent-browser --json` plumbing, not the predicate. Whole-server + CLI would over-refuse every legitimate object result; snapshot-only + CLI needs the allowlist Q1 rejects. |
| Rename the CLI to an importable name, or extract a `_lib.py` | The filename is the anchor in the hook (`REDACTOR_ANCHOR`), the lint (`REDACTOR_ANCHOR_RE`), `EXPECTED_GATE_REFS`, this ADR, the register and eight SKILL.md prescriptions — a sweep with no property gain and a 61-row suite to re-anchor. The contract is declared on the provider instead. |
| A second predicate inside the proxy | Refused structurally: an AST walk over the proxy finds no `re.*` call, no `def redact_text`, exactly one `spec_from_file_location`, and no string literal the redactor's own `_is_credential_name` accepts; parity is byte-equal against the CLI on every tree-carrying fixture. |

### The measured rows that decided them

| Row | Measured on `@playwright/mcp@0.0.78` | What it decided |
|---|---|---|
| 4 | The redactor CLI refuses a `browser_evaluate` object result at exit 2. | Q3: in-process `redact_text`, not subprocess-of-CLI. |
| 6 / 11 | With a `--config` file pinning `snapshot.mode: full` AND `--snapshot-mode none` appended, `browser_navigate` carries no `### Snapshot` section, zero `page-*.yml` are written, and a bare `browser_snapshot` is still inline. The CLI flag wins over the config file. | Q1: the action-tool disk sink is closed by appending the flag, not by deleting files; the explicit-snapshot path stays inline and is redacted. |
| 12 | Every stdout message is one `\n`-terminated JSON object; no `Content-Length` header anywhere. | The pump splits raw bytes on `\n` only — measured on the pinned server, not assumed from the spec. |
| 13 | `arguments._meta.json: true` returns the tree as ONE JSON-escaped string (2 newlines in the whole text, sentinel present); `_meta.raw` returns the bare tree. | The line-anchored predicate cannot see an escaped tree, so any `tools/call` whose `params.arguments` carries `_meta` is refused (the protocol-level `params._meta` is not). |
| 14 | `browser_find` inlines matched tree lines carrying the sentinel under `### Result`, independent of `--snapshot-mode`. | Q1: two inline paths, not one — the reason the predicate runs by shape on every result. |
| 16 | `browser_close` result keys on the wire are `['content']` only (`isClose` is deleted before sending); the server's `roots/list` request id is `0`, an independent counter. | The result-shape whitelist keeps `isClose` harmlessly; a server-to-client request can collide with a pending client id, so classification requires `result` or `error` present and never touches the pending map for a request. |
| fleet, 0.0.75 | From a scratch cwd with no `--output-dir`, `browser_navigate` writes `.playwright-mcp/page-*.yml` under cwd carrying the sentinel (2 occurrences) and links it; `--snapshot-mode none` is accepted and stops the write. | Reach (d): the Inngest fleet overlay gets the flag directly. |

### Reach, per surface

- **(a) This repository's `.mcp.json`** — **declared** there and asserted by an
  executable suite row (the row runs the wrapper under a scratch `HOME` with an
  `npx` shim and reads the recorded argv; it proves the declaration, not a loaded
  session — `.mcp.json` loads on restart only).
- **(b) A customer's own registration** — the plugin SHIPS the proxy but registers
  NO Playwright server (`plugin.json` is unchanged), so a customer is wrapped only
  by their own configuration; tracked at #8156. The skills prescribe the
  `filename:` form first and treat a refusal of `filename` as the structural
  signal that the registration is wrapped.
- **(c) The hosted agent-runner** registers no Playwright server.
- **(d) The Inngest fleet's per-fire overlay** (`cron-ux-audit.ts`,
  `@playwright/mcp@0.0.75`) is NOT wrapped — it gets `--snapshot-mode none`
  appended directly, measured on the 0.0.75 copy (register PA-31 §(g)).

Reach statements stay in the "on a registration routed through the proxy" form;
none is a Jikigai safety undertaking (#7981 stays `Ref` only).

### What remains open, restated rather than implied

- `browser_take_screenshot` returns an `image` block; the measurement above that
  a screenshot renders a readonly credential panel in clear is unchanged.
- `browser_network_request` returns request headers (`Cookie`, `Authorization`)
  and, with `part: request-body`, the submitted form body; `browser_evaluate` and
  `browser_run_code_unsafe` return whatever they are asked for, including a
  `filename` write of raw values to disk behind the proxy. All three accept
  `filename`, none is tree-shaped, and `--secrets` remains the only control there.
- Non-tree disk sinks the server writes without agent action: `console-*.log`
  under the output dir at or above `console.level` regardless of snapshot mode,
  the screenshot PNG (always written), and downloads as `download-*.bin`. The
  opt-in `devtools` capability adds `browser_start_tracing` (trace snapshots carry
  input values) and `pdf` renders the panel in clear — row 15 asserts the default
  `tools/list` (24 tools) carries neither `browser_start_tracing` nor
  `browser_pdf_save`.
- Prose the predicate is inert on passes in clear: `- Page URL:` (emitted on every
  navigate even under `--snapshot-mode none`; a magic link or OAuth redirect
  carries `?token=`, `code=` or `#access_token=`), `- Page Title:`,
  `### Modal state` dialog messages, and `/url:` children of links.
- The predicate's own stated bypasses — a localised accessible name, a credential
  outside a text-input role, a value split across segmented inputs — carry over
  unchanged. Same predicate, same ceiling.
- When the drift arm withholds a `- [Snapshot](` link, the raw file the server
  already wrote persists on disk. The proxy does not delete it; the reason names
  the enclosing directory only. Under the pinned 0.0.78 with the flag and the
  refusals in place no code path produces that link — the arm exists for the next
  bump.
- The `tools/list` marker and the per-result trailer
  `[Soleur: redacted in flight by playwright-mcp-redact-proxy]` are a pre-call
  hint and a post-hoc trace respectively; page content can forge the trailer, so
  neither is a verification.

### The corpus lint's S2 rule changes class

Control 3's S2 disclosure was a statically true sentence ("no runtime guard on
the Playwright-MCP path"). Its truth now depends on the registration, which the
walker cannot see and only the runtime can settle. The prescription therefore
changes class, from a static disclosure to a **structural** one: use the
`filename:` + redactor + shred form first (safe on an unwrapped registration,
refused on a wrapped one); if the server refuses `filename`, the registration is
wrapped by `playwright-mcp-redact-proxy.py` and the bare `browser_snapshot` call
is redacted in flight — call it bare for the rest of the session. The refusal is
the only signal; never the trailer or any page text, which can be forged. The old
sentence alone now fails S2; `MCP_GAP_MARKER_RE` anchors on the new claim, and
the lint's failure message quotes the canonical sentence so a copy-edit in one
file shows the phrase to restore.

> **Superseded 2026-09-14 (#7980 review round):** "if the server refuses
> `filename` … call it bare for the rest of the session" was unsafe as written —
> the unwrapped server refuses an out-of-root filename with its own `File access
> denied`, and a session can hold a second, unwrapped Playwright server. The
> signal is now the proxy-unique refusal text on that one server, and the marker
> is the whole canonical sentence. See the review-round amendment below.

### Enumerative closure, bound to the pin

The disk-sink closure covers the TREE sinks only and is an enumeration, not a
property: `--snapshot-mode none` (action tools), the `filename` refusal (explicit
snapshot to a named file), the `_meta` refusal (the `json` / `raw` / `cwd`
argument hooks), and the `--save-session` / `saveSession` / `DEBUG` /
`DEBUG_FILE` refusals (the `session.md` response log and the
`pw:mcp:server:response` debug stream, both of which carry every unredacted
result). Every item is a dated observation of `@playwright/mcp@0.0.78`
(`playwright-core` 1.62.0-alpha), not an undertaking about that tool. The
complement is the drift arm (any `- [Snapshot](` link that reappears is withheld)
and the Phase 0 re-capture: the suite derives its fixture directory from the
version pinned in `.mcp.json`, so a bump that forgets to re-run the capture
driver reddens rather than testing stale captures. The next bump re-enumerates
this list.

> **Superseded 2026-09-14 (#7980 review round):** the `DEBUG` refusal above was a
> literal match (`*`, `pw:mcp*`) where the `debug` package treats `*` as a
> wildcard, and the enumeration missed INI configs, `saveVideo`, `--caps`,
> `--output-mode file` and the `--port` / `--host` HTTP transport. The drift arm no
> longer withholds. See the review-round amendment below.

## Amendment — 2026-09-14 (#7980), review round

A ten-seat review of the shipped proxy found that the assembly was narrower than
the property the addendum above names. Four of its findings were live on the real
`@playwright/mcp@0.0.78` server, and each is closed in this change with a suite
row and a mutant that proves the row can go red.

**Closed, with the measurement that found each.**

| Finding | Measured | Now |
|---|---|---|
| A credential label containing a space-hash, a colon-space, `{`, `}` or a backtick leaked in clear, with the trailer appended | Live: `- 'textbox "API Key #1" [ref=e2]': <value>` — Playwright's `yamlEscapeKeyIfNeeded` single-quotes the whole key, and every predicate anchored on `- role` | The redactor unwraps a quoted key before matching and re-quotes on output (its suite carries the key strings the server's own function renders) |
| `DEBUG=pw:*`, `pw:api *`, `*:response` started the proxy | Node, against the pinned bundle: `debug('pw:mcp:server:response').enabled` is true under each | Refused: split on whitespace and commas, skip exclusions, `*` as a wildcard anywhere — any pattern that can enable a `pw:` logger |
| An INI config setting `saveSession = true` started the proxy | `loadConfig` falls back to `configFromIniFile` when JSON parsing fails | A named config the proxy cannot parse as a JSON object, or that does not exist, refuses to start |
| "Refuses `filename`" was forgeable in both directions | `checkFile` throws `File access denied: <path> is outside allowed roots` as `### Error` + `isError`, the proxy's own shape | The refusal text begins `refused by playwright-mcp-redact-proxy:`; S2's canonical sentence keys on it, scopes "call it bare" to that one server, and the lint's marker is now the whole sentence |

**Closed, not reachable on 0.0.78 but on the next version's likely path.**

- Server requests other than `roots/list`, and notifications other than
  `notifications/tools/list_changed` and `notifications/cancelled`, are dropped;
  0.0.78 emits none, and a `sampling/createMessage` carrying a tree would otherwise
  have reached the client raw. The three relayed kinds are rebuilt from method and
  ids alone, and a `requestId` or request id carrying a tree row or a redactable
  value is dropped, so no `reason` or `_meta` field carries page text past the
  proxy (raised by the CLO re-attestation; suite rows 54/55).
- A JSON-escaped tree is withheld even when it is a single row with no newline
  (`ariaSnapshot()` on one locator, returned through `browser_evaluate` or
  `browser_run_code`): `escaped_tree_in` no longer requires a newline before asking
  the tree predicate (raised by the ship-gate advisor consult; suite row 56). The
  cost is that a value tool returning one YAML-shaped line is withheld, fail-closed.
- A JSON-RPC error is forwarded only as `{code, message}` with prose; an error that
  also carries `result`, is not an object, carries `data`, or whose message is
  tree-shaped is withheld.
- A JSON-escaped tree inside a result (`browser_run_code_unsafe` returning
  `ariaSnapshot()`, a pretty-printed `browser_evaluate` object) is withheld — the
  same shape the `_meta` refusal exists for. The addendum's residual framing of
  these tools as "not tree-shaped" was false.
- Startup also refuses `saveVideo`, a capability other than `vision` (`--caps`,
  `PLAYWRIGHT_MCP_CAPS`, config `capabilities`), `--port` / `--host` /
  `PLAYWRIGHT_MCP_PORT` / `PLAYWRIGHT_MCP_HOST` / config `server.*` (an HTTP
  transport that serves results around the stdio relay), and `--output-mode file`.
- A request reusing a pending id is refused, and a content-bearing result is
  rewritten whatever request it answers.
- Teardown signals the child's whole process group even when the direct child has
  already exited, so a grandchild that outlives `npx` is still killed.
- An unparsable client line is dropped, never forwarded unvetted (an integer past
  Python's digit limit parsed in Node and not in the proxy).

**Changed rather than hardened: the drift arm.** A `- [Snapshot](…)` line used to
withhold the whole result. A page controls dialog text, and 0.0.78 inserts dialog
messages unescaped, so a page could withhold every result and hide the `### Modal
state` section an agent needs to recover. The arm now replaces only a link line
inside `### Snapshot` with a do-not-read notice and delivers the rest; the file the
server wrote persists either way.

**A premise corrected, with a consequence for #8156.** The Alternatives table's
"PostToolUse cannot rewrite tool output" is false for the transcript sink on Claude
Code 2.1.270 (`updatedMCPToolOutput`). A plugin-shipped PostToolUse hook on
`mcp__playwright__.*` could therefore reach a customer registration without an
`.mcp.json` edit, for the transcript only — the disk-write half of that row still
holds. That is a design input for #8156, not a change to this decision: the proxy
also closes the disk sinks, which a PostToolUse hook cannot.

**The filename coupling, stated where a renamer looks.** The proxy loads the
redactor by the sibling basename `REDACTOR_BASENAME = "redact-a11y-snapshot.py"`,
so a rename must update the proxy alongside the hook, the lint,
`EXPECTED_GATE_REFS`, the register and `agent-browser/SKILL.md`; the proxy suite's
`nosib` and `v-rename` rows red on a missed one.

## Addendum — 2026-09-15 (#8205): harness scope of the Bash matcher

The `PreToolUse` interceptor this ADR ships is registered in
`plugins/soleur/hooks/hooks.json` (and in repo `.claude/settings.json` for
dogfooding) on the matcher `Bash`. Measured in a controlled Devin child
session
(`knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md`),
that matcher is **dead under Devin CLI**: Devin loads the registry but
dispatches the lowercase wire name `exec`, which `Bash` never matches. For
the window during which `plugins/soleur/devin/INSTRUCTIONS.md` asserted the
guard was supported on Devin, the control was absent there — an unstated
gap, which is the failure mode rather than the gap itself.

The guard acts under Devin because #8155 shipped **both halves** in one
commit (merged 2026-09-16): the plugin matcher `Bash` → `^(Bash|exec)$` AND
the in-body gate widened to admit `exec` (`tool_name == "Bash" || "exec"`).
Before #8155 the body self-gated `tool_name == "Bash"` — the
fire-then-no-op defect class — so a matcher-only widening would have fired
the hook and no-opped; at this change's base the guard already acts on
`exec` envelopes. #8214's contribution is replacing the ad-hoc disjunction
with the canonical `HOOK_TOOL_KIND` map (`exec` → `Bash` via
`lib/hook-tool-kind.sh`) — a conformance requirement of this change's own
parity contract (`devin-matcher-parity.test.sh` T9), not a precondition
for this guard's reach.

Until a post-merge runtime trace confirms both halves, Devin coverage is
claimed for the mechanism only (`covered-by-plugin` in
`.claude/hooks/devin-dispositions.tsv`), and `devin/INSTRUCTIONS.md` states
the measured state rather than support. Claude `Bash` coverage is unchanged.

## Addendum — 2026-09-18 (#8156): the wrapped registration is now the shipped default

The #7980 addendum shipped the proxy but left the customer reach open: the
plugin carried `playwright-mcp-redact-proxy.py` while registering no server,
so a customer's registration was wrapped only by the customer's own
configuration — reach (b), the default, was documented rather than delivered.
This change closes reach (b): `plugins/soleur/.mcp.json` registers `playwright`
with `command: "python3"` running
`${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
in front of `npx @playwright/mcp@0.0.78`. On Claude Code ≥2.1.139 (the declared
engines floor, measured at exactly 2.1.139 in the plan-time probe) the tools
arrive as `mcp__plugin_soleur_playwright__*` — already wrapped, no customer
configuration. The `plugin_soleur` namespace cannot collide with a customer's
own `mcp__playwright__*`; both registrations coexist when the customer has one.

**Dedicated `.mcp.json`, not inline `plugin.json` `mcpServers`.** A manifest
entry in `plugin.json` is loaded by every harness that reads the manifest, and
the codex deep-equality and devin `.url`-parity tests would then carry a stdio
entry on harnesses that cannot run it. A plugin-root `.mcp.json` is read by
Claude Code and — per the Devin CLI's own documentation, which states that a
plugin's root `.mcp.json` and `${CLAUDE_PLUGIN_ROOT}` are honored — by Devin's
local substrate as well; Codex's handling of a plugin-root `.mcp.json` was not
verified and is claimed in neither direction. Where a harness does discover
it, the discovered registration is still the wrapped proxy, so the wider
reach is benign; the blast-radius argument is against `plugin.json`
`mcpServers`, whose parity tests would force the entry onto harnesses that
cannot execute it at all.

**Profile isolation.** The registration passes
`--user-data-dir-name soleur-playwright-mcp-profile`, a new proxy flag that
resolves the basename under `$XDG_CACHE_HOME` (default `~/.cache`, XDG
semantics mirroring `scripts/lib/scratch-root.sh`) and injects
`--user-data-dir=<absolute>` into the child argv. A dedicated profile keeps the
wrapped browser's lock, cookies and credential state out of any profile a
customer's own registration uses — the real collision the issue feared, which
is the profile dir, not the tool namespace. The flag refuses to start on a
basename carrying `..` or a separator, on a basename combined with an explicit
`--user-data-dir`, on a relative `XDG_CACHE_HOME`, and when `~` cannot resolve
(HOME unset) — extending arm (i) of the fail-closed design, never loosening
it. A `bash -c` launch (the repo `.mcp.json`'s shape) was rejected: an
unauditable shell string inside a JSON manifest buys nothing the flag does not
do in the file that already owns the child argv.

**What this does not do.** A customer's own `playwright` registration stays
exactly as wrapped or unwrapped as they configured it — the plugin server does
not reach it, and the skills' preference prose plus the S2 refusal signal are
the steering, not a mechanism. Option C, a plugin PostToolUse/PreToolUse hook
net on `mcp__playwright__.*` emitting `updatedMCPToolOutput`, is the residual
closer for that registration and is **deferred**: it covers the transcript
sink only (the server's `filename:`/`page-*.yml` disk writes complete before a
hook sees output, and a hook cannot append `--snapshot-mode none` to a launch
it does not own), and its feasibility is not the blocker — upstream
anthropics/claude-code #47859 and #24788 are CLOSED; #54161 documents the
`updatedMCPToolOutput` shape. The deferral issue is **#8286**, carrying the
re-evaluation criteria: a measured material misroute rate onto customer
registrations, hook-rewrite persistence proven benign on the engines floor, or
an upstream manifest-layer mechanism to wrap a user registration. ADR-162's
one-rewriter rule does not constrain Option C — it constrains `updatedInput`
rewrites on PreToolUse, not `updatedToolOutput` on PostToolUse.

**Caveats, stated.** The plugin server exists only where the plugin's
`.mcp.json` is discovered and can execute — measured on Claude Code ≥2.1.139
with the plugin installed, `python3` and `npx` on `PATH`, and the server not
disabled in `/mcp` (the toggle can switch it off without uninstalling).
Devin's local substrate also discovers the file per its own documentation;
on Codex discovery is unverified; under `claude --strict-mcp-config` the
plugin-root `.mcp.json` is suppressed (measured: `TOOL-ABSENT` under the
flag vs `TOOL-PRESENT` without it on 2.1.273), which is what keeps the
fleet's strict-mode clone path free of the registration. Every absence
degrades to the same shape: `mcp__plugin_soleur_playwright__*`
not present, the file-form path the skills prescribe as the fallback. Degradation
prose in `agent-browser/SKILL.md` §"Wrapping the server" does not assume the
plugin server exists. `npx` runs on every session start; the 0.0.78 pin bounds
that to a cache hit after first install. The orphan-on-own-profile failure
mode was measured and refuted in the plan-time probe: a SIGKILLed Claude
parent leaves the plugin's `playwright-mcp` child reaped within ~0.7 s (stdio
EOF), a SIGKILLed `playwright-mcp` leaves Chrome reaped by the same group
teardown, and a stale `SingletonLock` is stolen by the next launch on a
dead-pid check — the playbook names the live-lock-holder check for the shape
that remains.

**Hosted agent-runner: reach (c) now holds by exclusion, not by absence.**
Architecture review found that the hosted agent-runner loads the vendored
plugin tree via `plugins: [{ type: "local" }]` on `@anthropic-ai/claude-code`
2.1.219 — above the discovery floor — so a vendored `plugins/soleur/.mcp.json`
would register `plugin:soleur:playwright` on the prod image, where `python3`
does not exist and `@playwright/mcp@0.0.78` cannot resolve under firewalled
egress: a guaranteed-failed server on every hosted session. Rather than
suppress MCP discovery on the query path (`SdkPluginConfig.skipMcpDiscovery`
would also unregister the plugin's sanctioned HTTP `mcpServers`), both vendor
steps (`.github/workflows/ci.yml`, `reusable-release.yml`) now `rm -f
"$DEST/.mcp.json"` after `cp -a`, so the hosted image's plugin tree carries no
`.mcp.json` at all — the manifest `mcpServers` in `plugin.json` are unaffected.
Reach (c) stays literally true, restated: **the hosted agent-runner registers
no Playwright server, because the vendored plugin tree excludes the file.**
The exclusion is pinned by two Guard-3 rows in the proxy suite.

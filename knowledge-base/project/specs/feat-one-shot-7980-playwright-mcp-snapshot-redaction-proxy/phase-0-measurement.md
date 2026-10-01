# Phase 0 measurement record — #7980 (2026-09-14)

Live probes against `@playwright/mcp` on this workstation, driven by
`plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py`
(stdlib, serves a synthesized page whose password + Token fields hold
`ZZQP-SENTINEL-7980`, Email holds `probe-user@example.invalid`, Notes holds
`ZZQP-BENIGN-7980`). Every number below was read from the capture directory
named beside it, not from memory. Fixtures committed under
`plugins/soleur/skills/agent-browser/test/fixtures/playwright-mcp-0.0.78/` are
the flag-mode run plus `navigate-link.json` from the default-mode run (temp
path stripped).

## 0.1 — 0.0.78 default mode (`/var/tmp/cap7980-default.Amz0Yi`)

| observable | measured |
|---|---|
| messages captured | 12 (initialize, tools/list, navigate, snapshot, snapshot+filename, `_meta.json`, `_meta.raw`, find, evaluate, screenshot, close, roots/list) |
| framing | newline-delimited JSON; **no `Content-Length`**; every stdout line is one JSON object |
| serverInfo | `Playwright 1.62.0-alpha-1783623505000`, protocol `2025-06-18` |
| tools/list | 24 tools; no `browser_start_tracing`, no `browser_pdf_save` |
| bare `browser_snapshot` | tree INLINE in `content[0].text` (`### Snapshot` + yaml fence); both sentinels present |
| `browser_snapshot` + `filename` | result carries `- [Snapshot](<path>)`; the raw tree is written to that path (server cwd-relative) |
| `arguments._meta: {json: true}` | tree returned as ONE JSON-escaped string (2 newlines in the text); sentinel present — the line-anchored predicate cannot see it |
| `arguments._meta: {raw: true}` | tree returned raw (no `### Page` header) |
| `browser_find` | inlines the tree (same shape as snapshot) |
| `browser_evaluate` | object result, `content[0].text` is the JS value + `### Ran Playwright code` |
| `browser_take_screenshot` | `content` types `[text, image]` |
| `browser_close` | result keys `['content']` only — **no `isClose` on the wire** |
| server request | `roots/list` with **id 0** (colliding-id class is real) |
| navigate (default mode) | carries `- [Snapshot](outdir/page-<ts>.yml)` — the action-tool disk sink |

## 0.2 — 0.0.78 with `--snapshot-mode none` + config `{"snapshot":{"mode":"full"}}` (`/var/tmp/cap7980-flag.ppqRDG`)

| observable | measured |
|---|---|
| navigate | **no `### Snapshot` section**, 0 `page-*.yml` written |
| bare `browser_snapshot` | still inline (the flag governs ACTION tools only) |
| `browser_snapshot` + `filename` | still links a file (the flag does not close this sink — the proxy refuses the key) |
| precedence | the CLI flag wins over the config file's `snapshot.mode` |

## 0.3 — fleet pin 0.0.75 (`cron-ux-audit.ts`)

| run | measured |
|---|---|
| default (`/var/tmp/cap7980-fleet-default.5cQeIl`) | writes `.playwright-mcp/page-*.yml` under cwd (sentinel count 2 in the file) and links it from the navigate result |
| flag (`/var/tmp/cap7980-fleet-flag.dESwK0`) | `--snapshot-mode none` accepted; no page yml; navigate carries no Snapshot |

Consequence: Phase 3.3 appends `--snapshot-mode none` to the fleet argv
(the overlay is NOT wrapped by the proxy; PA-31 §(g)).

## 0.4 — reaper discrimination

The `.mcp.json` wrapper's `pkill -9 -f "[p]laywright-mcp-redact-proxy.py .*$prof"`
is ordered BEFORE the child pattern and neither pattern matches the wrapper's own
literal line (the `[x]` first-character trick). Asserted executable by the suite's
Guard 2 rows (scratch `HOME`, `npx` shim on `PATH`, parent pid-anchored via
`ps -o comm=,args= -p $PPID`).

## FR13 as literally written contradicts B3 — resolution

FR13 ("no credential-shaped literal in the proxy") and B3 ("the startup
self-test drives the predicate with a sentinel row") cannot both hold literally:
the self-test row is `- textbox "Token" [ref=e1]: ZZQP-SENTINEL-7980`, and the
module docstring names `credential`/`token`. Resolution, encoded in the suite's
FR13 AST row: the module docstring (raw, `ast.get_docstring(clean=False)`) and
the `self_test` function body are exempt from the literal scan; `self_test` must
be the ONLY function carrying such a literal and must carry at least one. The
row-10 mutant (`if "password" in text` inside `rewrite_result`) is still caught
(`suite-green-1.txt`).

## Suite measurements (`runs/`)

| record | result |
|---|---|
| `suite-green-1.txt` — shipped proxy | 162 passed, 0 failed, 162 cases, rc=0; 39/39 mutants landed and caught |
| `suite-red-passthrough.txt` — `PROXY_UNDER_TEST=fake-passthrough-proxy.py` (QG5) | 81 passed, 83 failed, rc=1; every redaction/refusal/withhold row RED, every must-PASS row (P1–P5, byte-identical forwards, roots/list passthrough) GREEN |
| `phase4-gates.txt` | lint suite 39/39; bare lint OK over 8323 files; old MCP-gap sentence absent from `plugins/soleur/skills`; vacuity floor 23/23 after promotion |
| vacuity self-measure | `ok()` neutered → `INSTRUMENT BROKEN` rc=1; `bad()` neutered → rc=1; floor 99999 → `[FATAL] vacuity floor: only 162 cases` rc=1 |

## Live verification (Phase 3.2)

Real `npx @playwright/mcp@0.0.78 --headless --user-data-dir=<scratch>` behind the
proxy, three teardown paths: `runs/live-verify.md`. Tree row `textbox "Password"`
→ `<redacted>`, Notes intact, trailer appended, `tools/list` marker present,
navigate carries no `### Snapshot`, 0 `page-*.yml`; EOF / SIGTERM / SIGKILL +
wrapper reaper each leave the child's pgid empty. The only surviving sentinel is in
`- Page URL:` — the test's own `data:` URL, i.e. the named prose residual.

## Line-cap boundary (found while writing row 37)

A server line of EXACTLY `MAX_LINE_BYTES` (64 MiB) parses — the newline arrives
in the same chunk that would have tripped the `> MAX_LINE_BYTES` check — and is
then withheld by the 4 MiB result cap. The row drives 65 MiB so the line-cap arm
itself is what fires (`discarding oversize server line`, pending answered
`oversize`); the row-37 mutant is distinguished by the ABSENCE of that discard
line and of `oversize` in the reason, not by isError alone (both arms withhold).

## Review round (2026-09-14)

Measurements the ten-seat review took against the pinned server bundle
(`~/.npm/_npx/*/node_modules/playwright-core/lib/coreBundle.js`), each closed in
this change with a suite row and a mutant:

| Observable | Measured | Closure |
|---|---|---|
| YAML key quoting | `yamlEscapeKeyIfNeeded` single-quotes a key containing a space-hash, colon-space, `{`, `}`, a backtick or a control character; live through the old proxy, "API Key #1" leaked with the trailer appended | redactor unwraps quoted keys; its suite fixtures were rendered by that function |
| `DEBUG` matching | the `debug` package splits on whitespace and commas and treats `*` as a wildcard anywhere; `DEBUG=pw:*` enables `pw:mcp:server:response` | any pattern that can enable a `pw:` logger refuses to start |
| Config parsing | `loadConfig` falls back to `configFromIniFile`; `saveSession` is a typed INI key | a named config that is missing or not a JSON object refuses to start |
| `checkFile` | an out-of-root `filename` returns `### Error\nFile access denied: …` with `isError`, the old refusal's shape | refusal text carries `refused by playwright-mcp-redact-proxy:` |
| Server notifications | 0.0.78 emits none; its only server request is `roots/list` | everything else dropped (a request answered on the server side) |
| `--caps` / `--port` / `--output-mode` | `devtools`, `pdf`, `storage` write raw page state; `--port` serves SSE around stdio; `--output-mode file` writes snapshots and logs | refused at startup, with the matching env vars and config keys |

Suite records: `runs/suite-review-round.txt` (274 passed, 0 failed, 274 cases,
53 mutants and 53 mutation rows, rc=0); `runs/suite-red-passthrough-review-round.txt`
(the same suite against `fake-passthrough-proxy.py`: 156 passed, 120 failed, rc=1 —
every redaction, refusal and withhold row red; the passing rows are byte-identical
forwards, must-PASS rows, structure rows on the shipped file and Guard 2, which
reads `.mcp.json` rather than `PROXY`); `runs/suite-helper-neuter-review-round.txt`
(`red`, `leaks`, `started`, `delivered_ok` each neutered on a copy →
`HELPER CONTROL BROKEN`, rc=1).

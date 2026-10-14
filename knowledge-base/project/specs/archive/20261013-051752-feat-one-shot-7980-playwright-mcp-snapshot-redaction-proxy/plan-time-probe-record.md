# Plan-time probe record — @playwright/mcp@0.0.78 over raw stdio (#7980)

Captured 2026-09-14 during planning, in this worktree, by driving `npx @playwright/mcp@0.0.78 --headless --isolated --output-dir <tmp>` over its own stdin/stdout with hand-written JSON-RPC (no Claude Code in the loop). Page: a synthesized form served by `python3 -m http.server --bind 127.0.0.1 8748`, torn down after the run. Sentinel `ZZQP-SENTINEL-7980` is invented and never a real credential (`cq-test-fixtures-synthesized-only`). These captures are the SOURCE for the fixtures in Phase 1 — the ADR-213 round-3 lesson is that fixtures composed from the author's expectation are the ones that pass; fixtures must come from the surface.

Server identity from `initialize`: `serverInfo = {name: Playwright, version: 1.62.0-alpha-1783623505000}`, `protocolVersion = 2025-06-18`. Framing observed: one JSON object per line on stdout, no embedded newlines; diagnostics on stderr only.

## Row 1 — `browser_navigate` (default `--snapshot-mode full`): tree goes to DISK, response carries a link

```text
### Ran Playwright code
```js
await page.goto('http://127.0.0.1:8748/page.html');
```
### Page
- Page URL: http://127.0.0.1:8748/page.html
- Page Title: probe 7980
- Console: 1 errors, 0 warnings
### Snapshot
- [Snapshot](out/page-2026-09-14T08-40-55-929Z.yml)
### Events
- New console entries: out/console-2026-09-14T08-40-54-902Z.log#L1-L2
```

The linked `page-*.yml` file contains the sentinel 3 times (password value, Token value, textarea value). Nothing in the RESPONSE carries the tree.

## Row 2 — `browser_snapshot` with no arguments: tree is INLINE, both credential classes leak

```text
### Page
- Page URL: http://127.0.0.1:8748/page.html
- Page Title: probe 7980
- Console: 1 errors, 0 warnings
### Snapshot
```yaml
- generic [ref=e2]:
  - generic [ref=e3]:
    - text: Enter your password
    - textbox "Enter your password" [ref=e4]: ZZQP-SENTINEL-7980
  - generic [ref=e5]:
    - text: Token
    - textbox "Token" [ref=e6]: ZZQP-SENTINEL-7980
  - generic [ref=e7]:
    - text: Email address
    - textbox "Email address" [ref=e8]: probe-user@example.invalid
  - generic [ref=e9]:
    - text: Notes
    - textbox "Notes" [ref=e10]: "{\"k\": \"ZZQP-SENTINEL-7980\"} second line"
  - button "Go" [ref=e11]
```
```

Piped through `redact-a11y-snapshot.py` as-is (exit 0): `Enter your password` and `Token` values become `<redacted>`; `Email address` and `Notes` survive (must-PASS; `Notes` is not credential-named and its JSON-shaped value is rendered by Playwright as ONE double-quoted line, so no line in the tree begins with `{`).

## Row 3 — `browser_snapshot` with `filename:`: tree goes to the NAMED FILE (raw), response carries a link only

```text
### Page
- Page URL: http://127.0.0.1:8748/page.html
- Page Title: probe 7980
- Console: 1 errors, 0 warnings
### Snapshot
- [Snapshot](./explicit-snap.yml)
```

`./explicit-snap.yml` contains the sentinel 3 times.

## Row 4 — `browser_evaluate` returning an object: the REDACTOR CLI REFUSES this text

```text
### Result
{
  "a": 1,
  "b": [
    1,
    2
  ]
}
### Ran Playwright code
```js
await page.evaluate('() => ({a: 1, b: [1,2]})');
```
```

`python3 redact-a11y-snapshot.py < this` → exit 2, stdout empty, stderr `refusing to emit: input looks like JSON but does not parse (Extra data)`. The CLI's `main()` locates the first `{`, fails to parse the tail, sees a line beginning with `{`, and fails closed. That arm is agent-browser `--json` envelope plumbing; it is NOT the predicate. A proxy that shelled out to the CLI for every tool result would therefore refuse every `browser_evaluate` object result — measured, not reasoned. This is the row that decides design question 3 (in-process `redact_text`, not subprocess-of-CLI).

## Row 5 — `browser_navigate` text through `redact_text`: byte-identical

The Row 1 text piped through the CLI comes back byte-identical (`diff` empty, exit 0). The predicate is inert on prose and on `- Page URL:` / `- Page Title:` bullets (`NODE_RE` requires the `<role> "name" [attrs]: value` shape).

## Row 6 — `--snapshot-mode full --snapshot-mode none` (last flag wins): action tools write NO tree file; explicit snapshot still inline

With `--snapshot-mode none` appended AFTER a `--snapshot-mode full`: `browser_navigate` and `browser_click` responses carry `### Page` / `### Ran Playwright code` / `### Events` but NO `### Snapshot` section; `glob(page-*.yml)` in the output dir is EMPTY; a following bare `browser_snapshot` still returns the inline ```` ```yaml ```` tree with the sentinel. So appending the flag closes the action-tool disk sink without touching the explicit-snapshot path.

## Row 7 — `tools/list`: the `browser_snapshot` entry

`description = "Capture accessibility snapshot of the current page, this is better than screenshot"`; `inputSchema.properties = [target, filename, depth, boxes]`. This is the string the proxy annotates so an agent can tell at runtime whether it is behind the proxy.

## Row 8 — `browser_take_screenshot`: content types `[text, image]`

The image block is untouched by any text predicate. The ADR-213 measurement that a screenshot renders a readonly credential panel in clear is unchanged by this plan and is restated as a residual.

## Row 9 — Claude Code persists MCP server stderr

`~/.cache/claude-cli-nodejs/<project-slug>/mcp-logs-playwright/<timestamp>.jsonl` holds one JSON line per event, including `{"error":"Server stderr: ..."}` and `Connection failed (...)` lines. Verified on this machine at plan time. This is the durable, no-SSH artifact for the proxy's refuse-to-start arm (observability layer 7).

## Source-level cross-check (0.0.78 and the fleet's 0.0.75)

In `playwright-core/lib/coreBundle.js` (`Response._build`), the tree reaches a client-bound message on exactly ONE path: `addSection("Snapshot", [tabSnapshot.ariaSnapshot], "yaml")`, taken only when `_includeSnapshot === "explicit"` (the `browser_snapshot` tool) AND no `filename` was given. Every other path (`_includeSnapshot !== "explicit" || _includeSnapshotFileName`) writes the tree with `_writeFile` and adds `- [Snapshot](<relative>)`. The same shape is present in the 0.0.75 copy under `apps/web-platform/node_modules/@playwright/mcp/` (`if (this._includeSnapshot !== "explicit" || this._includeSnapshotFileName)`), so the fleet's `browser_navigate` grant does not inline a tree either — PA-31's trigger (t1) is sound as written.

## Corrections recorded at deepen-plan (2026-09-14, security review against the same bundle)

- **Two inline tree paths, not one.** Besides the explicit `browser_snapshot`, `browser_find` (capability `core`, on by default) calls `page.ariaSnapshot({mode: "ai"})` directly and emits the matched tree lines under `### Result`, independent of `--snapshot-mode` and of `Response._includeSnapshot`. The line shape is the same `- role "name" [ref]: value` form, so the redactor's shape-based predicate covers it — which is the reason the proxy applies the predicate to every tool result rather than to a named tool. Phase 0 row 14 captures it.
- **`isClose` does not reach the wire.** `createServer` deletes `isClose` from the result before sending; the earlier row-10 expectation ("captures the `isClose` shape") will observe its absence. The whitelist keeps the key harmlessly.
- **`DEBUG` is a raw sink.** With `DEBUG` matching `*` or a `pw:mcp` namespace, the server prints every unredacted result to its stderr (`pw:mcp:server:response`), which the proxy inherits and Claude Code persists in clear; `DEBUG_FILE` writes the same to a file. The proxy refuses to start under either.
- **Non-tree disk sinks written without agent action** (console logs under the output dir, screenshot PNGs, downloads, opt-in `devtools` tracing, `pdf`) are named residuals, not closed. Row 15 asserts the default `tools/list` carries neither `browser_start_tracing` nor `browser_pdf_save`.

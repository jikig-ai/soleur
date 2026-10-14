# Phase 0.1 — snapshot provenance measurement (#7947)

Measured 2026-09-09 in worktree `feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction`.
This file is the verdict the plan's Phase 0 gates Phase 1 on. Nothing here is recalled; every row
was produced by the probe described below and the raw captures were read directly.

## Probe

A synthesized page served over `python3 -m http.server --bind 127.0.0.1 8747 --directory <mktemp -d>`,
torn down after the run. Sentinel `ZZQP-SENTINEL-7947` — invented, never a real credential
(`cq-test-fixtures-synthesized-only`). Five nodes:

| Row | Node | Provenance |
|---|---|---|
| A | `input type=password` with static `value=` | autofill-equivalent; agent never typed it |
| B | `input type=password`, value set by inline JS after parse | agent never typed it |
| C | `input type=text`, accessible name "Enter your password", **empty** | name predicate isolated from structural |
| D | `input type=text readonly`, accessible name "Token", holds sentinel | generated-credential panel |
| E | `input type=email`, benign value | must-PASS control |

Row D is the class that has already fired in this repo
(`knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md` records a snapshot
rendering a freshly-minted Sentry token verbatim from exactly such a node), and it is the class
Phase 3.1's own mint page renders.

## Toolchain pinned

| Surface | Version |
|---|---|
| `agent-browser` | 0.22.3 (`~/.local/bin/agent-browser`) |
| Playwright MCP | `playwright-core` 1.58.2 and 1.62.0-alpha-1783623505000 both resolvable under `~/.npm/_npx/` |

`agent-browser` required `AGENT_BROWSER_ARGS="--no-sandbox"` plus clearing a wedged daemon socket
before it would run at all — the remedy already documented in `agent-browser/SKILL.md`
§"Troubleshooting: Chrome fails to launch / `open` hangs".

## Verdict — BOTH surfaces leak a non-agent-supplied value

Plan verdict-table row 1. **All deliverables are kept.** But the two surfaces do not leak the same
nodes, and that distinction is finer than any row of the plan's table anticipated.

| Row | agent-browser 0.22.3 (headed AND headless) | Playwright MCP | Screenshot |
|---|---|---|---|
| A — `type=password`, static value | masked: `••••••••••••••••••` | **LEAKS in clear** | safe (dots) |
| B — `type=password`, JS-set value | masked: `••••••••••••••••••` | **LEAKS in clear** | safe (dots) |
| C — `type=text`, password-named, empty | no value emitted | no value emitted | n/a |
| D — `type=text readonly`, named "Token" | **LEAKS in clear** | **LEAKS in clear** | **LEAKS in clear** |
| E — `type=email`, benign (must PASS) | value rendered | value rendered | rendered |

Headed and headless `agent-browser` produced byte-identical trees, so the Chromium
headed/headless masking variable the plan flagged is settled: it does not apply here.

## Marker shape per surface

`agent-browser snapshot -i`:

```text
- textbox "Enter your password" [ref=e2]: ••••••••••••••••••
- textbox "Token" [ref=e5]: ZZQP-SENTINEL-7947
- textbox "Email address" [ref=e6]: probe-user@example.invalid
```

Playwright MCP (written to `.playwright-mcp/page-*.yml`, not returned inline):

```text
- textbox "Enter your password" [ref=e3]: ZZQP-SENTINEL-7947
- textbox "Token" [ref=e6]: ZZQP-SENTINEL-7947
- textbox "Email address" [ref=e7]: probe-user@example.invalid
```

`agent-browser snapshot` with no flags, or `-d N`, emits the value **twice** — once as the `: value`
tail and again as a nested `StaticText` child:

```text
- textbox "Token" [ref=e5]: ZZQP-SENTINEL-7947
  - StaticText "ZZQP-SENTINEL-7947"
```

`--json` wraps the same text in `data.snapshot` as an escaped string; `data.refs` carries
`{name, role}` only and no values.

## Design consequences — these change what Phase 1 and Phase 2 build

1. **The predicate cannot be structural.** Neither surface serializes `type=`; rows A, B, D and E
   all render as `textbox`. The plan anticipated exactly this ("if a surface prints ... with only
   the label distinguishing it and no serialized `type`, the predicate is name-heuristic rather
   than structural and the filter's design changes"). It is the branch that fired.
2. **Phase 1.1's second RED case is void as written.** "A `type=password` node whose accessible
   name is not password-shaped is redacted too — structural first, name-based second" is not
   implementable against either serialization, because no `type` reaches the filter. Replace it
   with a credential-shaped-name case.
3. **A name predicate keyed on "password" alone is insufficient and would miss the only node
   `agent-browser` leaks.** It must cover credential-shaped names broadly (token, secret, key,
   passphrase, credential, client secret, bearer, api key), because row D is both the sole
   `agent-browser` leak and the class with a recorded in-repo incident.
4. **The must-PASS control is load-bearing.** Row E renders its value on both surfaces and must
   survive unredacted; a filter that redacts every `textbox` value is as broken as one that
   redacts none.
5. **The filter must redact the nested `StaticText` child too**, or the no-flag and `-d N` shapes
   leak through the duplicate. A filter that only rewrites the `: value` tail is half a fix.
6. **`--json` must be handled via `data.snapshot`**, not only the indented-text shape.

## Correction the PR owes the issue text

#7947 asserts "**A screenshot is safe** — the browser renders the field as dots", and its guard
predicate is "never take an accessibility snapshot of a page containing a password input — use a
screenshot instead."

Measured: that holds **only for `input type=password`**. For row D — the generated-credential
panel, a readonly `type=text` — the screenshot renders the value in clear exactly as the snapshot
does. So "use a screenshot instead" is false for the one class with a recorded in-repo incident,
and the shipped skill rule must not say it unqualified.

Correspondingly, the issue's headline framing ("Playwright's accessibility snapshot includes the
`value` of input fields ... a password input that a password manager auto-filled renders in clear")
is true of the Playwright MCP surface and **false of `agent-browser`**, which already masks
`type=password`. The mechanism is real; its stated scope is wrong in both directions.

## `browser_type` echo — separate row, separate disposition

Not reproduced in this run. The plan directs that if it reproduces it gets its own issue rather
than widening this one; there is nothing to file on this evidence. Recorded here so the row is
answered rather than silently dropped.

## Session note — orphan daemon

`agent-browser` was initially unusable: a daemon started 2026-08-20 whose `cwd` resolved to a
**deleted** worktree (`feat-one-shot-7640-cloudflare-pages-migration`) held the socket and did not
answer, so every invocation failed `Resource temporarily unavailable (os error 11) (after 5
retries - daemon may be busy or unresponsive)`. It survived SIGTERM and needed SIGKILL. This is a
tooling defect independent of #7947: any session inherits it, and the CLI gives no hint that a
dead worktree's daemon is the cause.

## Guard 3 H2 — is `2>&1` load-bearing in the approved pipe form?

The Guard Contract states the `2>&1` in `agent-browser snapshot -i 2>&1 | python3 <redactor>` is
"part of the approved form, not decoration", on the rationale that node content written to stderr
would bypass a stdout-only pipe, and defers the question to this phase.

Measured, streams separated (`> out 2> err`) against a page carrying the row-D node:

| Stream | Sentinel hits | Bytes |
|---|---|---|
| stdout | 1 | — |
| stderr | 0 | 0 |

**On the success path `agent-browser` writes no node content to stderr.** So the contract's stated
rationale is not demonstrated: a bare `| python3 <redactor>` without `2>&1` does not leak node
content today.

Keep the `2>&1` in the approved form anyway, but on the honest reason rather than the asserted one:
it costs nothing, it routes any future or error-path output through the redactor too, and a hook
that accepts both forms has a wider allow-predicate to get right. The contract's H2 row stands; its
justification is corrected here rather than left asserting a leak that does not occur.

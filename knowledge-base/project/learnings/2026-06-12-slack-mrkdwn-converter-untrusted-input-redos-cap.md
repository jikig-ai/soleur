# Learning: A markdown→Slack-mrkdwn converter on untrusted CI input needs a pre-conversion length cap

## Problem

Slack release notifications posted the changelog body as raw GitHub-flavored
Markdown. Slack does **not** render GFM — it uses "mrkdwn" (`*bold*` single
asterisk, `_italic_`, `~strike~`, `<url|label>` links, no headings/tables/
inline-images), so `**bold**`, `## H`, `[t](u)`, `~~x~~` all rendered as
literal characters in the team channel.

The fix is a `scripts/md-to-mrkdwn.mjs` converter wired into the one Slack-
sending CI step. But the changelog body is **untrusted** (any PR author writes
it), which creates two non-obvious traps a naive converter walks into.

## Solution

A self-contained zero-dependency Node ESM converter (runs on stock
ubuntu-latest `node`, no `setup-node` — the `secret-scan.yml` bare-`node`
precedent), with three load-bearing properties:

1. **Escape-vs-emit in one context-aware pass.** Text nodes escape `&<>`
   (the only injection defense — Slack has NO `allowed_mentions` equivalent);
   converter-*minted* `<url|label>` delimiters are raw but the url/label
   segments are sub-escaped and `|` is stripped/percent-encoded (a raw `|`
   re-opens the grammar). Code regions are **escape-only, not verbatim** —
   Slack renders `<!channel>` inside backticks in a `text` payload.
2. **Keystone fail-closed invariant:** output contains zero `<!`/`<@`/`<#`/
   `<subteam^`; the only raw `<` begins a URL scheme inside a minted link.
   One assertion backstops every smuggling path, in the unit test AND the
   workflow contract test.
3. **Pre-conversion input length cap (the ReDoS fix).** See Key Insight.

## Key Insight

**A converter that scans untrusted input position-by-position with regexes is
O(n²), and an output-side `--max` cap runs too late to save you.** Several
inline regexes (`/^\[([^\]]*)\]\(([^)]*)\)/` etc.) tail-scan to EOF on a
failed match; at O(n) scan positions that is O(n²). A 64 KB run of `[`
took 5.2s; 100 KB took 13.4s — a malicious changelog hangs the release step.
The workflow's `--max 3000` cap did NOT help because it runs **inside
`truncateMrkdwn`, after `toSlackMrkdwn` has already chewed the full
untruncated input**.

Fix: cap the **raw input** at the top of the converter (`MAX_INPUT = 16384`,
far above any real changelog) BEFORE the scan loop, plus bound the link
label/url char-classes with `{0,K}` as defense-in-depth, plus a timing
regression test. The output cap tidies the rendered tail; the input cap bounds
the O(n²) constant. Generalizes to any tokenizing transform fed
attacker-influenced bytes in CI.

Secondary insight: when validating a numeric CLI arg, use `Number()` not
`parseInt()` — `parseInt("1e9")` silently returns `1` (truncating a release
body to a single ellipsis); `Number("1e9")` correctly returns `1e9`. Validate
with `Number.isInteger(n) && n > 0` and throw on malformed input rather than
coercing to a body-destroying small number.

## Session Errors

- **Test assertion expected `--max 1e9` to throw `RangeError`** — Recovery:
  corrected the assertion to expect `1e9` (a billion). `Number("1e9")` is a
  valid integer-valued number; only the `parseInt` path produced `1`.
  Prevention: when a fix swaps `parseInt`→`Number` specifically to handle
  scientific notation, the test must assert the notation now PARSES, not that
  it rejects. (one-off)

## Tags
category: security-issues
module: ci-release / scripts/md-to-mrkdwn.mjs
related: [[2026-03-05-discord-allowed-mentions-for-webhook-sanitization]]

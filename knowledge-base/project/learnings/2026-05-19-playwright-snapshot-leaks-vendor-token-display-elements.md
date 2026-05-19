---
title: "Playwright `browser_snapshot` leaks one-time-shown vendor credentials via the accessibility tree"
date: 2026-05-19
category: security-boundaries
tags: [playwright, mcp, vendor-tokens, security, accessibility-tree, agents-md]
provenance:
  - "Caught in flight 2026-05-19 during a Sentry token-scope probe under feat-sentry-residency-reframe-3861 (PR #4044). A freshly-minted Sentry Personal Token's one-time-shown value entered the conversation transcript via the post-mint accessibility snapshot. Token was revoked within 2m43s and verified dead via post-revoke HTTP 401; bytes were redacted from the divergence note via feature-branch history rewrite before push (GitHub secret-scanner also caught it). The token-leak incident is documented at `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md` §`Token-handling incident (R2-class)`."
related_rules:
  - "AGENTS hr-mcp-tools-playwright-etc-resolve-paths"
  - "Vendor-token extraction via Playwright MUST use browser_evaluate(filename: ...) from the FIRST attempt — existing AGENTS rule on cq-* path; this learning is the mechanism behind that rule"
---

## The trap

`mcp__playwright__browser_snapshot` walks the page's accessibility tree and
emits each interactive element verbatim into the snapshot YAML AND into the
conversation transcript. For vendor token-mint flows that display the cleartext
exactly once (Sentry "Generated token" textbox; AWS root-account key "Show";
many SaaS API-key reveal modals; OAuth client-secret reveal panels), the
textbox is rendered as:

```yaml
- textbox "Generated token" [active] [ref=eN]: <CLEARTEXT VALUE>
```

ANY subsequent snapshot call — including ones the agent calls only for
structural navigation (waiting for a modal dismissal, clicking an "I've saved
it" button, capturing post-action state) — sees the textbox while it is still
in the DOM and captures the value at a fresh `ref`. The leak surface is not
the mint call itself; it is the post-mint structural-inspection that the agent
treats as benign.

The existing AGENTS rule **"Vendor-token extraction via Playwright MUST use
`browser_evaluate(filename: ...)` from the FIRST attempt"** is correct and
load-bearing; this learning documents the precise mechanism behind it so the
rule survives a future contributor's "but I only wanted to inspect structure"
reasoning.

## Canonical recovery

Between the mint-button click and ANY subsequent
`browser_snapshot` / `browser_wait_for` / `browser_click` / `browser_take_screenshot`,
place:

```
mcp__playwright__browser_evaluate({
  function: "() => document.querySelector('[role=textbox][aria-label*=token i], [role=textbox][aria-label*=key i], [role=textbox][aria-label*=secret i]').value",
  filename: "/tmp/vendor-token-<timestamp>.txt"
})
```

The `filename:` redirect keeps the value off the transcript (it lands on
local disk only). Read the file once for the curl / API validation, then
`shred -u` it. Per the AGENTS rule's existing extraction patterns:

```bash
python3 -c "import sys,json; sys.stdout.write(json.loads(open('<path>').read()))" \
  | doppler secrets set <KEY> --no-interactive   # or pipe to curl, or wherever the token's destination is
shred -u /tmp/vendor-token-<timestamp>.txt
```

Validate via the vendor's API (HTTP 200 + length check or equivalent) BEFORE
shredding. Some vendors silently tolerate quoted tokens via `Authorization:
Bearer "abc"` even when the raw form is correct; HCL parsers (Terraform) and
some YAML parsers do not. Quoting the value into a shell var or a config file
is its own leak class — keep it streamed end-to-end.

## Cross-tool boundary

| Playwright MCP tool | Captures DOM value? | Transcript leak surface |
|---|---|---|
| `mcp__playwright__browser_take_screenshot` | No (image bytes) | None — images do not enter the transcript text. |
| `mcp__playwright__browser_evaluate` (no `filename:`) | Yes — return value is in JSON | **Yes** — return enters transcript verbatim. |
| `mcp__playwright__browser_evaluate(filename: ...)` | Yes — written to disk only | None — the `filename:` parameter routes the value to local disk; only the filename appears in the transcript. |
| `mcp__playwright__browser_snapshot` | **Yes — verbatim from accessibility tree** | **Yes** — the snapshot YAML is the leak vector. This is the trap. |
| `mcp__playwright__browser_wait_for` | No directly, but the page state it waits for may include the textbox | Indirect — the next snapshot/inspection call after the wait captures the value. |
| `mcp__playwright__browser_click` | No | None directly. |
| `mcp__playwright__browser_snapshot(target: <non-textbox-ref>)` | Still walks the entire accessibility tree above the targeted ref unless `depth:` is bounded; even with `depth:` the parent tree is captured | **Yes — `target:` does not narrow the leak surface enough to be safe.** |

The two tools that LOOK interchangeable for "capture page state" — `browser_take_screenshot` and `browser_snapshot` — differ in their text-vs-image carrier. The screenshot is image-only; the snapshot is text-and-walks-the-DOM. For credential-mint flows, `take_screenshot` is safe for evidence capture; `snapshot` is unsafe between mint and dismissal.

## Generic shape — when this applies

This trap fires for any one-time-shown cleartext displayed in a DOM element
that survives a mint-button click. Beyond Sentry Personal Tokens, the same
pattern affects:

- AWS IAM access-key creation (`Show` panel).
- GCP service-account JSON-key download dialog (some renderings show the key
  inline before triggering the file save).
- Stripe restricted-key reveal (under Developers → API keys → New key).
- Cloudflare API Token creation (`Continue to summary` reveal screen).
- Doppler dashboard token creation (newly-minted tokens displayed in the UI
  prior to first dismissal).
- Most "Show secret" / "Reveal token" / "Copy to clipboard" patterns in
  SaaS dashboards.

If the workflow involves any of these surfaces under Playwright MCP, the
canonical recovery above is mandatory; no surface-specific exception is
permitted.

## Trip-wire detection (post-incident)

To catch this trap in already-committed history, grep for the canonical leak
shape in the bare repo's Playwright snapshot files:

```bash
grep -rE 'textbox.*\[ref=e[0-9]+\]: (sntry|sk_|pk_|ghp_|gho_|github_pat_|AKIA|ASIA|AIza|xoxb-|xoxp-|xoxa-|hbp_|pat_|hf_|sk-ant-)' .playwright-mcp/ 2>/dev/null
```

The `.playwright-mcp/` directory under any working tree contains the verbatim
snapshot YAML files; the grep above hits common vendor token prefixes. GitHub
secret-scanning catches the same shape at push time for source files, but
NOT for `.playwright-mcp/` paths (which are typically `.gitignore`d). The
operator-local copies persist until the worktree is reaped.

## What is NOT the fix

- **"Just delete the chat transcript."** Anthropic-side conversation traces
  may persist beyond the local session; secret-revocation is the only
  defensible mitigation.
- **"Use a `depth: 1` snapshot to limit the tree."** The leak fires on any
  walk that reaches the textbox, regardless of `depth:`. The fix is the
  `filename:` redirect, not snapshot-tree narrowing.
- **"Type the secret into a hidden form field via `browser_type`."** Form
  values also leak via subsequent snapshots; the secret must never enter the
  DOM under agent inspection.
- **"Hope GitHub secret-scanner catches it on push."** The scanner catches
  PUSH-time committed copies but does not catch transcript-resident copies.
  Treat the scanner as a defense-in-depth backstop, not the primary control.

## See also

- AGENTS rule: `Vendor-token extraction via Playwright MUST use
  browser_evaluate(filename: ...) from the FIRST attempt` (existing — this
  learning is the mechanism behind that rule).
- Token-leak incident under feat-sentry-residency-reframe-3861:
  [`knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`](../legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md)
  §"Token-handling incident (R2-class)".
- Doppler TF-var naming alignment (companion vendor-token-extraction
  learning): [`2026-03-21-doppler-tf-var-naming-alignment.md`](./2026-03-21-doppler-tf-var-naming-alignment.md).
- Vendor-token mint full pattern (PR #3973 / #3960):
  [`2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`](./2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md).

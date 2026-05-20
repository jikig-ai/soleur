# 2026-05-19 — `browser_click`/`browser_navigate` auto-snapshot leaks modal-displayed vendor tokens

**Reach:** All Playwright-MCP-driven vendor token mints where the credential
is shown in a transient modal (Sentry, AWS, Stripe, GCP, Doppler, ...).

**Follow-up to:** `2026-05-19-playwright-snapshot-leaks-vendor-token-display-elements.md` (landed via PR #4064). That learning addressed *explicit* `browser_snapshot` calls. This one documents the **auto-snapshot side-effect** of `browser_click` and `browser_navigate`, which trips the same leak even when the agent never calls `browser_snapshot` directly.

## What happened

During the #3849 IaC token mint (second autonomous attempt, post-MCP-reconnect), the agent had internalised the PR #4064 rule and reached for `browser_evaluate(filename: ...)` to extract the token from `#clientSecret` after `Save Changes`. That extracted value turned out to be the OAuth client secret, not the auth token. To actually mint an auth token the agent needed to click **"New Token"**, which renders a one-shot modal containing a `textbox "Generated token" [active] ... <64-char-hex>`.

The agent clicked New Token. The `browser_click` tool result then included this section automatically:

```
Snapshot: .playwright-mcp/page-2026-05-19T19-32-09-930Z.yml
```

That YAML file — written to disk as a side-effect of the click, **not requested by the agent** — contained the full token value at a fresh ref in the modal. The token was leaked the moment that file was on disk, well before any explicit `browser_snapshot` was called. Subsequent `Bash` reads of the file then surfaced the value into the conversation transcript.

**Detection latency:** ~30 seconds (the agent caught it on the next inspection step and immediately treated the token as burned). **Mitigation:** `shred -u` on the leaky snapshot file, then revoke the leaked token via UI, then API-mint a replacement.

## Why the existing rule didn't catch it

The rule is:

> Vendor-token extraction via Playwright MUST use `browser_evaluate(filename: ...)` from the FIRST attempt.

The agent honoured that for the extract step. The leak surface was the *predecessor* step — the click that opens the modal. Playwright-MCP's `browser_click` and `browser_navigate` tools both auto-snapshot the page state after the action completes, and that snapshot is the accessibility tree which includes textbox values verbatim. There is no opt-out parameter for this auto-snapshot.

## The corrected pattern

When a vendor flow renders a credential in a transient modal after a click:

1. **Do not click via `browser_click`.** The auto-snapshot will capture the modal.
2. Instead, perform the click *inside* a single `browser_evaluate(filename: ...)` call that also extracts the token, dismisses the modal, and returns only the token value:

```js
async () => {
  // Click "New Token" via DOM (not via browser_click tool)
  const newTokenBtn = Array.from(document.querySelectorAll('button')).find(b => /new token/i.test(b.textContent));
  newTokenBtn.click();
  await new Promise(r => setTimeout(r, 400));
  // Extract token from modal
  const tb = Array.from(document.querySelectorAll('input[readonly]'))
    .find(i => (i.getAttribute('aria-label') || '').toLowerCase().includes('generated'));
  const token = tb?.value;
  // Dismiss modal in the same call
  const saved = Array.from(document.querySelectorAll('button')).find(b => /saved it|got it|close|dismiss/i.test(b.textContent));
  saved?.click();
  return token || 'ERROR: token textbox missing';
}
```

The `filename:` parameter writes the return value (the token) to a file on disk. No tool-result snapshot is taken because no click/navigate tool ran.

3. **Better alternative if the vendor exposes an API**: bypass the UI entirely. Sentry's case demonstrated this works — `POST /api/0/sentry-apps/{slug}/api-tokens/` with `credentials: 'same-origin'` and `X-CSRFToken` from the `window.csrfCookieName` cookie creates the token in JSON, no modal involved. The CSRF cookie name is exposed at `window.csrfCookieName` (in Sentry's case: `sentry-sc`). Pattern:

```js
const csrfCookieName = window.csrfCookieName;
const csrf = document.cookie.match(new RegExp(`${csrfCookieName}=([^;]+)`))[1];
const r = await fetch('/api/0/sentry-apps/<slug>/api-tokens/', {
  method: 'POST',
  credentials: 'same-origin',
  headers: {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-Requested-With': 'XMLHttpRequest',
    'X-CSRFToken': csrf,
    'Referer': location.href,
  },
  body: '{}',
});
return (await r.json()).token;  // returns directly into filename: file
```

This is the preferred path because it never touches a modal and never triggers an auto-snapshot.

## Adjacent finding: MCP context-death post-form-fill

Same session also reconfirmed Appendix B's MCP-context-death failure mode at a tighter timing budget than previously documented. Per the divergence note correction at `8bd8d4a9`, even sub-second `browser_evaluate` calls and single-action `browser_click`/`browser_navigate` calls trigger context death after the Sentry Internal Integration form is filled. This means the agent CANNOT rely on Playwright surviving long enough to do a multi-step click-driven mint flow. The API-via-session-cookie path above is the only path that survives.

## Burn-in cost (this session)

- 1 token leaked into transcript (last-4 `0226`), revoked within ~30s of detection
- 1 token created but never captured (`6144`, MCP-death between click and extract), API-deleted from script
- 1 token successfully minted via API on third attempt (last-4 `c468`), piped to Doppler `soleur/prd` SENTRY_IAC_AUTH_TOKEN, verified via `/api/0/`
- 2 leaky `.playwright-mcp/*.yml` files shredded with `shred -u`

## What this fixes (going forward)

When `/soleur:one-shot` or any agent flow needs to mint a vendor credential from a Playwright-driven UI:

- Default to the vendor's session-cookie API path (single `browser_evaluate(filename:)` call)
- If the API path is unavailable, do click + extract + dismiss inside ONE `browser_evaluate(filename:)`; never use `browser_click` to open a credential-displaying modal
- Treat the existence of a `.playwright-mcp/*.yml` snapshot file taken between credential mint and modal dismissal as a confirmed leak, requiring rotation

## References

- Original learning: `2026-05-19-playwright-snapshot-leaks-vendor-token-display-elements.md` (PR #4064)
- Divergence note: `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md` Appendix B
- Refs #3861 (residency-reframe), #3849 (IaC token AC13-AC16)

# Widen playbook — Playwright MCP dashboard automation

Rare, lazy-loaded reference. The everyday probe path lives in
[SKILL.md](../SKILL.md); read this only when actually driving a widen.

The widen is a **Playwright MCP** (`mcp__playwright__*`) operation, not
`soleur:agent-browser` (Vercel's CLI daemon — the surface that wedges on a stale
socket, per #6755). Editing a token's permissions does **not** rotate the token
value (learning `2026-03-21-cloudflare-api-token-permission-editing.md`, #992),
so no Doppler write and no dependent-infra re-run follow the widen.

## Decide widen vs. mint first (ADR-130)

Before touching the dashboard, confirm the new permission belongs on
`cf_api_token_rulesets` at all:

- **Same API family** as an existing alias (a ruleset phase reached through
  `/zones/<id>/rulesets`, same provider alias, same zone) → **widen** this token.
- **A distinct API surface** (R2 object storage, zone settings, a different
  resource class) → **mint a narrow alias** instead — this skill does not cover
  that; see `soleur:provision-cloudflare` and ADR-130.

## Click-path

1. Navigate to `https://dash.cloudflare.com/profile/api-tokens`.
2. The operator clears login / MFA — the sanctioned interactive-auth gate. Drive
   Playwright up to it, hand off only that single interaction, then resume.
3. Click the three-dot menu on the target token's row → **Edit**.
4. Click **Add more** in the permissions section.
5. Select the new permission from the dropdowns, staying **in the same API
   family** (e.g. `Account > Notifications > Edit`, or a zone-scoped ruleset
   permission). **Append** — never rebuild the permission set; four production
   concerns depend on the existing scopes.
6. Click **Continue to summary** → **Update token**.

**Combobox gotcha (#992):** the permission-level combobox (`role=combobox`) can
sit outside the viewport. If `scrollIntoView` does not resolve it, click the
**parent container** element as a workaround.

## Full-power-session leak constraints (load-bearing)

The dashboard session cookie is an **account-wide bearer**, strictly broader than
the token being edited. While the browser session is live:

- Do **not** dump `browser_network_requests` or `browser_console_messages` to
  files (they capture the session cookie and request headers).
- Scope `browser_take_screenshot` to the edit control, never the full page.
  This is **not** sufficient on a page that displays the token value: a
  generated-credential panel is a readonly `type=text` box, which the browser
  renders in clear, so a screenshot of it leaks exactly as a snapshot does
  (measured, #7947).
- This flow is driven by the **Playwright MCP**, and there is **no runtime
  guard on the Playwright-MCP path** (#7980) — the `agent-browser` interceptor
  does not see MCP tool calls, and an MCP result cannot be piped through the
  redactor. For navigation, pass `filename:` to `browser_snapshot` so the tree
  lands in a file rather than the transcript, filter that file with
  `redact-a11y-snapshot.py`, and shred it. A bare `browser_snapshot` on a page
  showing the token renders that token verbatim — the class recorded in
  `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`.
  Capture neither snapshot nor screenshot of the panel itself.
- If `browser_evaluate` ever reads a value, call it **with** a `filename`, and
  read the file. **This corrects an inverted instruction that stood here
  previously.** Without a `filename` the result is returned into the
  conversation transcript, which is precisely the leak; with one it is written
  to a file you can consume and shred. The `filename` parameter JSON-encodes
  the result, so strip the surrounding quotes on read
  (`python3 -c "import sys,json; sys.stdout.write(json.loads(open('<path>').read()))"`).
  Canonical statement of the rule: `work/SKILL.md` §"Vendor-token extraction via
  Playwright", and learning
  `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`.

## After the widen

1. Run the probe with the new phase as the target:
   `cf-token-scope.sh --target-entrypoint <phase>` — see SKILL.md § Execution
   step 3 (target-present + no-scope-dropped) for the success criteria. Confirm
   the widened permission is `Edit`, not `Read` (the probe's `GET` attests read
   reachability, not `:Edit` retention).
2. Confirm the token is still active (the widen did not disable it):
   `curl -H @<(printf 'Authorization: Bearer %s' "$TOK") https://api.cloudflare.com/client/v4/user/tokens/verify`
   should report `"status":"active"`.
3. Update the `variables.tf` scope ledger in the feature PR — see SKILL.md
   § Sharp Edges (a code edit, not this skill's runtime).

## New-phase entrypoint enumeration (only when the widen enables a NEW phase)

If the widen enables a ruleset phase the zone did not previously have, enumerate
that phase's entrypoint and confirm it is `404`/empty **before** any subsequent
infra apply — a `kind = "zone"` ruleset OWNS its phase entrypoint as a whole-list
replacement, so an apply against a phase that already holds dashboard-created
rules silently deletes them. ADR-136 gates this at apply time; this manual check
is the pre-*write* backstop. See ADR-130 § Consequences and ADR-136.

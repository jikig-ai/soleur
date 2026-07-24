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
- Prefer `browser_snapshot` (accessibility tree) for navigation over screenshots.
- If `browser_evaluate` ever reads a value, call it **without** a `filename`
  (a `filename` JSON-dumps the result to the transcript — learning
  `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`).

## After the widen

1. Run the probe with the new phase as the target:
   `cf-token-scope.sh --target-entrypoint <phase>`. Success = the target flipped
   `403 → authorized` AND every retained control stayed authorized AND the
   account-scheme control is an authorized 200.
2. `curl -H "Authorization: Bearer $TOK" https://api.cloudflare.com/client/v4/user/tokens/verify`
   should report `"status":"active"` (the widen did not disable the token).
3. **Update the scope ledger** — the `variables.tf` description for the widened
   token (ADR-130's scope ledger) must gain the new permission in the feature PR
   that consumes the widen. This is a code edit, not this skill's runtime.

## New-phase entrypoint enumeration (only when the widen enables a NEW phase)

If the widen enables a ruleset phase the zone did not previously have, enumerate
that phase's entrypoint and confirm it is `404`/empty **before** any subsequent
infra apply — a `kind = "zone"` ruleset OWNS its phase entrypoint as a whole-list
replacement, so an apply against a phase that already holds dashboard-created
rules silently deletes them. ADR-136 gates this at apply time; this manual check
is the pre-*write* backstop. See ADR-130 § Consequences and ADR-136.

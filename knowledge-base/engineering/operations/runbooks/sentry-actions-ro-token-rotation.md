---
category: infrastructure
tags: [sentry, credential-rotation, followthroughs, github-actions, adr-031]
date: 2026-09-11
---

# Sentry `actions-read-prd` token rotation (`SENTRY_ACTIONS_RO_TOKEN`)

The repo secret `SENTRY_ACTIONS_RO_TOKEN` is the token of the org-level Sentry **Internal
Integration** `actions-read-prd` on `jikigai-eu` (ADR-031, fourth credential class). Two
consumer classes bind it: every `scripts/followthroughs/*.sh` Sentry reader, forwarded by
`scheduled-followthrough-sweeper.yml`, and `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`,
bound by both host-provisioning jobs in `apply-web-platform-infra.yml`. Its scopes are exactly
`[event:read, org:read, project:read]` — the measured minimum for the union of both classes
(record: `knowledge-base/project/specs/feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md`).

**One store.** The GitHub repository secret, and nowhere else. It is deliberately not
mirrored into Doppler: the name is chosen so that no `doppler run` config can satisfy it by
accident — the canonical vendor name `SENTRY_AUTH_TOKEN` binds a *personal*, human-account-scoped
token under `-c prd_terraform` (#7797, #7946). A workstation run of a followthrough without
the secret exits 2 TRANSIENT from its own presence guard. That is fail-closed by design.

**Cadence.** Rotate on incident or on scope change. ADR-031 records no calendar cadence for
any Internal Integration token and the expiry monitor in this directory covers Cloudflare
only — stated here so nobody infers one.

## Why the API path is closed

Creating an Internal Integration or minting its tokens through the API needs `org:admin` /
`org:integrations` (`POST /api/0/organizations/{org}/sentry-apps/`), or `org:write` for
`POST /api/0/sentry-apps/{slug}/api-tokens/` on an existing integration. No org-level Soleur
credential carries any of those (measured 2026-09-11; only the retiring personal token did,
and using it to mint its own replacement is circular). The `org:write` rung is a *possible*
future login-free rotation path, recorded in ADR-031 and deliberately not minted: it is a
wider grant than the token it would rotate.

## The browser rung

The dashboard mint is proven automatable with no CAPTCHA, MFA or passkey once the session is
authenticated (#5495 / #5496). The one honest handoff: if the browser profile's Sentry
session has expired, the page redirects to login, and clearing login + 2FA is the sanctioned
interactive-auth gate. The agent stops, names which profile's session expired, and resumes
when it is authenticated. **Nothing is ever typed as an MCP tool-call argument** — MCP
arguments are not shell-expanded, so a password on that path lands in the transcript.

**`agent-browser` (Bash path) is primary; the Playwright MCP is the fallback.** The reason is
the trap scope: `scripts/rotate-sentry-actions-ro-token.sh` holds the plaintext from capture
to shred under one `trap … EXIT INT TERM HUP`, which is real only inside one process. On the
Bash path the capture (`agent-browser get value <sel>`) is a subprocess of the script. On the
MCP path the capture is a separate tool call — a trap set before it has already fired — so
the script's `prepare` mode creates the 0700 directory and marker first, and the post-capture
`capture --from-file` call is where the trap scope begins; it also shreds every file under
`.playwright-mcp/` newer than the marker, because `browser_evaluate(filename:)` cannot expand
`$TOKEN_DIR` and `@playwright/mcp` resolves the name under its own output directory.

Under the #7947 discipline throughout: every `browser_snapshot` carries `filename:` and is
filtered through `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py`; on
the Bash path the PreToolUse interceptor denies any un-piped `agent-browser snapshot`; **no
snapshot or screenshot of the Tokens panel, ever**; no `browser_network_requests` /
`browser_console_messages` dumps (they carry the session cookie).

### Recipe

1. **Dry run first, zero writes.** Serve a page carrying the `ZZQP-SENTINEL-7947` sentinel in
   a readonly textbox (`python3 -m http.server --bind 127.0.0.1 <port> --directory <mktemp -d>`),
   `agent-browser open http://127.0.0.1:<port>/ --headless`, then
   `bash scripts/rotate-sentry-actions-ro-token.sh capture --selector '#tok' --dry-run --expect ZZQP-SENTINEL-7947`.
   Expect: byte-identical normalise, a `gh secret set` no-store ciphertext length equal to the
   computed one (48-byte sealed-box overhead + plaintext, base64-expanded), directory removed.
   Nothing is written. Only then go live.
2. **Mint.** `agent-browser open https://jikigai-eu.sentry.io/settings/developer-settings/new-internal/`
   (a redirect to login is the auth handoff above). Name `actions-read-prd` (on rotation the
   integration already exists — open it under `/settings/developer-settings/` instead and use
   its Tokens panel). Permissions: Issue & Event = **Read**, Organization = **Read**, Project =
   **Read**, everything else No Access; no webhook; save. Sentry **auto-issues the first
   token on creation**; on an existing integration click *New Token*. Up to 20 tokens per
   integration.
3. **Capture → normalise → store → verify → shred, one process:**
   `bash scripts/rotate-sentry-actions-ro-token.sh capture --selector '<the readonly token textbox>'`.
   The script stores on **stdin with no body flag** (gh has no body-file flag; a body of `-`
   stores the literal `-` — measured), asserts `gh secret list` shows the name, reads
   `.auth.scopes` and requires it **equal** the triple, probes every consumer's exact host +
   org + path (the header read from a file, never argv), pins the region host, and shreds on
   exit. Any `[FAIL]` blocks the cutover.
4. **Dispatch the sweep, read the verdicts, then revoke the old.** Order is store new →
   `gh workflow run scheduled-followthrough-sweeper.yml` → confirm the affected trackers got a
   fresh `### Sweeper run:` comment with no `HTTP 401`/`403` → revoke the previous token in the
   Tokens panel → assert the panel holds exactly one token (a save can auto-issue one; extras
   are revoked).

### Workstation dry run of the followthroughs

`gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` runs every probe with
the real secret at the real scopes, posts nothing, and needs no local credential. That is the
documented path. The **last resort** is an explicit assignment on one probe —
`SENTRY_ACTIONS_RO_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --plain)" bash scripts/followthroughs/<probe>.sh`
— with its caveat: that is the IaC superset, so a probe can pass locally and 403 in CI. Never
an ambient `doppler run`, and never the old name.

`/tmp` is tmpfs on the maintained workstation (`findmnt -n -o FSTYPE /tmp`), so `shred -u`
of the `mktemp -d` path is effective there; on a journaled or copy-on-write filesystem it is
best-effort, the 0700 directory and the seconds-long lifetime are the primary control, and a
failed shred is logged, not hidden.

## Failure modes

| Symptom | Reading | Next action |
|---|---|---|
| The mint page redirects to login | The browser profile's Sentry session expired | The sanctioned auth handoff: the operator authenticates the profile; the agent types nothing and resumes at the same URL |
| The permission labels on the form do not match the three named above | Sentry renamed or regrouped a resource | Map by resource, not label; after saving, the script's `.auth.scopes` equality is the arbiter — a mismatch blocks |
| The form saved but the capture selector found no textbox | The auto-issued token's one-time display was missed | Create a second token from the Tokens panel, capture that one, revoke the first, assert the panel count is one |
| Two tokens on the Tokens panel after the mint | A save auto-issued one and *New Token* issued another | Keep the captured one; revoke the other in-page; re-run `capture --skip-store --dir <dir>` only if unsure which is stored |
| `[FAIL] .auth.scopes is … expected exactly …` | The permission set selected returned an implied extra or is missing one | Edit the integration's permissions in-page; re-read scopes on the **same** token; if unchanged, revoke, create a new token, re-run the chain |
| A consumer's host or org slug moved (a probe 404s/403s on an org or monitor path that the token can read elsewhere) | The script's literal no longer matches the org's live host or slug | Re-read the consumer script's exact host + org + path against `.links.regionUrl` and the monitor list; fix the script's literal (Rule D pins it) and add the new path to the rotation script's probe list |
| `[FAIL] 403 <consumer endpoint>` at verification with the slug unchanged | The endpoint needs a scope outside the triple | A plan change, never a widening in place: measure the endpoint's `scope_map`, decide on the record (ADR-031), then edit the permission set and re-run the chain |
| `[FAIL] regionUrl is … pinned to https://de.sentry.io` | The org's region host changed | Update `REGION_HOST_PINNED` in the script and the boot-trail's literal together; do not proceed on an unpinned host |
| `[FATAL] gh secret set … failed` | The store did not land; a live token exists that nothing holds | Revoke the token in-page immediately, then retry the chain |
| A probe still posts TRANSIENT after the dispatch | The stored value is wrong (JSON-encoded, truncated, the literal `-`) → 401; or a scope gap → 403 | 401: re-run the chain (the normalise step asserts shape, so re-capture); 403: the scope row above |
| The sweeper run is red with `required secret` | A tracker directive still names the retired credential, or the env key is misspelled | Rewrite the directive's `secrets=` clause (`gh issue edit <n> --body-file …`) or fix the workflow `env:`; the comment on the tracker names which |
| Every Sentry-backed probe posts 401 daily under a green run | The integration or its token was deleted dashboard-side | 401 (deleted) vs 403 (scope edited) is the only discriminator; recreate the integration and re-run the chain |
| `[WARN] shred … failed` on exit | Non-tmpfs `/tmp` or a permission change | Remove the named directory by hand; the plaintext lived seconds under 0700 |

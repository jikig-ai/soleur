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
when it is authenticated. **Nothing is ever typed as a tool-call argument.**

**`agent-browser` (Bash path) is the only supported path.** `scripts/rotate-sentry-actions-ro-token.sh`
holds the plaintext from capture to shred under one trap scope, which is real only inside one
process; its header states why the capture must be a subprocess of the script. The Playwright
MCP is **not** a supported fallback: `@playwright/mcp` emits an inline accessibility snapshot on
every `browser_click`, and the click that reveals the token is a click, so the value would land
in the transcript before any redactor ran.

Under the #7947 discipline throughout: the PreToolUse interceptor denies any un-piped
`snapshot` invocation; **no `snapshot`, `screenshot`, `get html`, `get text` or `eval` against
the Tokens panel, ever** — `get value <sel>` from inside the script is the one sanctioned read,
and `get count <sel>` (a number) is the one sanctioned check. No console or network dumps (they
carry the session cookie).

### Recipe

1. **Dry run first, zero writes.** Serve a page carrying the `ZZQP-SENTINEL-7947` sentinel in
   a readonly textbox (`python3 -m http.server --bind 127.0.0.1 <port> --directory <mktemp -d>`),
   `agent-browser open http://127.0.0.1:<port>/ --headless`, then
   `bash scripts/rotate-sentry-actions-ro-token.sh capture --selector '#tok' --dry-run --expect ZZQP-SENTINEL-7947`.
   Expect: byte-identical normalise, a `gh secret set` no-store ciphertext length equal to the
   computed one, directory removed. Nothing is written. Only then go live.
2. **Mint.** `agent-browser --headed --session-name sentry open https://jikigai-eu.sentry.io/settings/developer-settings/`
   (a redirect to login is the auth handoff above; the `--headed` window is where the operator
   signs in). On rotation the integration `actions-read-prd` already exists — open it and use its
   Tokens panel. On a rebuild use `…/developer-settings/new-internal/`: name `actions-read-prd`,
   Issue & Event = **Read**, Organization = **Read**, Project = **Read**, everything else No
   Access, no webhook, save (the save button needed a DOM `.click()`; measured 2026-09-11).
   **Saving does not auto-issue a token** (measured 2026-09-11: the panel was empty after save).
   Click *New Token* (`scrollIntoView(); click()`); the value appears once in a readonly textbox
   whose measured selector is `input[aria-label="Generated token"]`. Up to 20 tokens per
   integration.
3. **Capture → normalise → store → verify → shred, one process:**
   `bash scripts/rotate-sentry-actions-ro-token.sh capture --selector 'input[aria-label="Generated token"]'`.
   The script stores on **stdin with no body flag**, asserts `gh secret list` shows the name,
   reads `.auth.scopes` and requires it **equal** the triple, probes one endpoint per consumer
   class (header from a file, never argv), pins the region host, and shreds on exit. It logs the
   token's length and **last four characters** — the same four Sentry renders in the masked
   panel row — so the stored one can be told apart later. Any `[FAIL]` blocks the cutover.
4. **Dispatch the sweep, read the verdicts, then revoke the old.** Order is store new →
   `gh workflow run scheduled-followthrough-sweeper.yml` → confirm the run is green and every
   affected tracker's newest `### Sweeper run:` comment reads `PASS` or `NOT YET (exit 2` with no
   `HTTP 401`/`403` in the tail — a `### Sweeper run: REQUIRED SECRET MISSING` comment means the
   binding, not the token, is broken and is a blocker → revoke the previous token in the Tokens
   panel, identified by its masked last four → `agent-browser get count '<token row selector>'`
   must be 1. If more than one row exists after a mint, keep the captured one (its last four are
   in the script's log) and revoke the others.

### Workstation dry run of the followthroughs

`gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` runs every probe with
the real secret at the real scopes, posts nothing, and needs no local credential. It still
**reds on a missing secret** (Guard 3 fires under dry run; only the comment is suppressed), so
it is also the check for a broken binding. That is the documented path. The **last resort** is
an explicit assignment on one probe —
`SENTRY_ACTIONS_RO_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --plain)" bash scripts/followthroughs/<probe>.sh`
— with its caveat: that is the IaC superset, so a probe can pass locally and 403 in CI. Never
an ambient `doppler run`, and never the old name.

Trap scope, shred effectiveness by filesystem, and the argv/xtrace refusals are documented once,
in the script's header — the runbook does not restate them.

## Failure modes

| Symptom | Reading | Next action |
|---|---|---|
| The page redirects to login | The browser profile's Sentry session expired | The sanctioned auth handoff: the operator signs in to the `--headed` window; the agent types nothing and resumes at the same URL |
| The permission labels on the form do not match the three named above | Sentry renamed or regrouped a resource | Map by resource, not label; after saving, the script's `.auth.scopes` equality is the arbiter — a mismatch blocks |
| The capture selector found no textbox, or more than one token row exists after the mint | *New Token* was not clicked, its one-time display was dismissed, or it was clicked twice | Click *New Token* once more and capture that one; keep the captured token (last four in the script's log), revoke every other row, `get count` must be 1 |
| `[FAIL] .auth.scopes is … expected exactly …` | The permission set selected returned an implied extra or is missing one | Edit the integration's permissions in-page; re-read scopes on the **same** token; if unchanged, revoke, create a new token, re-run the chain |
| `[FAIL] <code> <consumer endpoint>` at verification | 404: the consumer's org slug or monitor slug moved — fix the consumer's literal (Rule D pins it) and the probe list. 403 with the slug unchanged: the endpoint needs a scope outside the triple — a plan change on the record (ADR-031), never a widening in place | Re-read the consumer's exact host + org + path; measure the endpoint's `scope_map` before touching the permission set |
| `[FAIL] regionUrl is … pinned to https://de.sentry.io` | The org's region host changed | Update `REGION_HOST_PINNED` in the script and the boot-trail's literal together; do not proceed on an unpinned host |
| `[FATAL] gh secret set … failed` | The store did not land; a live token exists that nothing holds | Revoke the token in-page immediately, then retry the chain. (`gh secret list` failing *after* the write is reported separately and does not mean "not stored" — re-run the list before revoking) |
| A probe posts TRANSIENT after the dispatch, or every Sentry-backed probe posts 401 daily under a green run | 401: the stored value is wrong (JSON-encoded, truncated) or the integration/token was deleted dashboard-side; 403: a scope gap | 401: re-run the chain (the normalise step asserts shape), recreating the integration if the panel is empty; 403: the scope row above |
| The sweeper run is red with `REQUIRED SECRET MISSING` | A tracker directive names a secret the workflow does not bind (retired name, misspelling, or an empty binding) | Rewrite the directive's `secrets=` clause (`gh issue edit <n> --body-file …`) or fix the workflow `env:`; the comment on the tracker names which |
| `[WARN] shred … failed` on exit | Non-tmpfs `/tmp` or a permission change | Remove the named directory by hand; the plaintext lived seconds under 0700 |

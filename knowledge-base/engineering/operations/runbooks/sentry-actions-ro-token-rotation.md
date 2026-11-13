---
category: infrastructure
tags: [sentry, credential-rotation, followthroughs, github-actions, adr-031, iac-terraform-prd]
date: 2026-09-11
---

# Sentry `actions-read-prd` token rotation (`SENTRY_ACTIONS_RO_TOKEN`)

The repo secret `SENTRY_ACTIONS_RO_TOKEN` is the token of the org-level Sentry **Internal
Integration** `actions-read-prd` on `jikigai-eu` (ADR-031, fourth credential class). Two
consumer classes bind it: every `scripts/followthroughs/*.sh` Sentry reader, forwarded by
`scheduled-followthrough-sweeper.yml`, and `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`,
bound by both host-provisioning jobs in `apply-web-platform-infra.yml`. Its scopes are exactly
`[event:read, org:read, project:read]` — the measured minimum for the union of both classes
(record: `knowledge-base/project/specs/archive/20260911-192621-feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md`).

**One store (this `ro` token).** The GitHub repository secret, and nowhere else. It is deliberately not
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
3. **Capture → normalise → verify → store → shred, one process:**
   `bash scripts/rotate-sentry-actions-ro-token.sh capture --selector 'input[aria-label="Generated token"]'`.
   The script reads `.auth.scopes` and requires it **equal** the triple, probes one endpoint per
   consumer class (header from a file, never argv), pins the region host, and only THEN stores on
   **stdin with no body flag** and asserts `gh secret list` shows the name — a token that fails
   verification never overwrites the previous secret (GitHub cannot read one back). It logs the
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

## IaC token rotation (`SENTRY_IAC_AUTH_TOKEN`, `iac-terraform-prd`)

The same script rotates the IaC token with `--profile iac`. The integration is
`iac-terraform-prd` on `jikigai-eu`; its scopes are set by ADR-031 §"Why a dedicated Internal
Integration", and the script's `iac` `EXPECTED_SCOPES` is the executable copy. The browser rung
and the `get value`-only discipline above apply unchanged.

1. **Dry run first, zero writes.** Serve and open the sentinel page exactly as in Recipe step 1,
   then `bash scripts/rotate-sentry-actions-ro-token.sh capture --profile iac --selector '#tok' --dry-run --expect ZZQP-SENTINEL-7947`.
   It also checks Doppler login, both target configs and that the key is readable in both,
   read-only. Doppler has no no-store mode, so the Doppler store form is pinned by the script's
   test, not by the dry run.
2. **Mint.** `agent-browser --headed --session-name sentry open https://jikigai-eu.sentry.io/settings/developer-settings/`
   → `iac-terraform-prd` → Tokens → *New Token*.
3. **Capture → verify → store → shred, one process:**
   `bash scripts/rotate-sentry-actions-ro-token.sh capture --profile iac --selector 'input[aria-label="Generated token"]'`.
   After exact scope equality and one 200 per IaC consumer class, it stores on stdin to three
   targets, in order: the GitHub repo secret `SENTRY_IAC_AUTH_TOKEN` (proven by a changed
   `updatedAt`), Doppler `soleur/prd` and Doppler `soleur/prd_terraform` (each read back by
   digest). A Doppler branch config either inherits the root's value or holds its own copy, so
   `prd_terraform` is written explicitly. The script then classifies every other `prd_*` config
   that lists the key by digest: `follow soleur/prd` (now new) or `own copy` (not the new value;
   no repo code reads it; removal is #12740). Exit 3 means a partial store: read the report.
4. **Prove, then revoke.** Only after the script prints `all three targets hold the new token … at
   <UTC time>`: run `gh workflow run scheduled-sentry-alert-drift.yml` and
   `gh workflow run scheduled-terraform-drift.yml`, and take each run id from the URL that
   `gh workflow run` prints (else the newest `--event workflow_dispatch` run created after that UTC
   time — a run that started earlier proves the OLD token). Both read only the GitHub secret; the
   Doppler copies are already proven by digest. GitHub prints every step's script into the run
   log, so a marker that also appears in a workflow's own source matches on EVERY run: match
   errors only in their rendered `##[error]` form, and require a POSITIVE line, never an absence.
   Revoke only when BOTH hold (the run has completed):
   - alert-drift: the log contains `sentry_alert live fidelity: PASS (all <N> in-scope rules …` or
     `divergence(s) between live Sentry` (a drift verdict reddens the run but still proves the
     token authenticated), and no `##[error]missing required secret` /
     `##[error]the fidelity probe could not complete` line:
     `gh run view "$RUN" --log | grep -E 'sentry_alert live fidelity: PASS \(all |divergence\(s\) between live Sentry|##\[error\](missing required secret|the fidelity probe could not complete)'`.
   - terraform-drift: the `web-platform/sentry` leg's log contains `No drift detected in
     web-platform/sentry` or `Drift detected in web-platform/sentry`, and no
     `##[error]Terraform plan failed in web-platform/sentry` / `##[error]sentry_iac_token_absent`
     line. The plan output itself never reaches the log, so do not search it for a 401:
     `JOB=$(gh run view "$RUN" --json jobs -q '.jobs[] | select(.name | contains("web-platform/infra/sentry")) | .databaseId'); gh run view --job "$JOB" --log | grep -E 'No drift detected in web-platform/sentry|Drift detected in web-platform/sentry|##\[error\](Terraform plan failed in web-platform/sentry|sentry_iac_token_absent)'`.

   Then, in the `iac-terraform-prd` Tokens panel, keep the row whose masked last four the script
   printed and revoke every other row (the previous token, plus any token from an earlier
   partial run); the panel must then show exactly one token row.

## Failure modes

| Symptom | Reading | Next action |
|---|---|---|
| The page redirects to login | The browser profile's Sentry session expired | The sanctioned auth handoff: the operator signs in to the `--headed` window; the agent types nothing and resumes at the same URL |
| The permission labels on the form do not match the three named above | Sentry renamed or regrouped a resource | Map by resource, not label; after saving, the script's `.auth.scopes` equality is the arbiter — a mismatch blocks |
| The capture selector found no textbox, or more than one token row exists after the mint | *New Token* was not clicked, its one-time display was dismissed, or it was clicked twice | Click *New Token* once more and capture that one; keep the captured token (last four in the script's log), revoke every other row, `get count` must be 1 |
| `[FAIL] .auth.scopes is … expected exactly …` | The permission set selected returned an implied extra or is missing one | Edit the integration's permissions in-page; re-read scopes on the **same** token; if unchanged, revoke, create a new token, re-run the chain |
| `[FAIL] <code> <consumer endpoint>` at verification | 404: the consumer's org slug or monitor slug moved — fix the consumer's literal (Rule D pins it) and the probe list. 403 with the slug unchanged: the endpoint needs a scope outside the triple — a plan change on the record (ADR-031), never a widening in place | Re-read the consumer's exact host + org + path; measure the endpoint's `scope_map` before touching the permission set |
| `[FAIL] regionUrl is … pinned to https://de.sentry.io` | The org's region host changed | Update `REGION_HOST_PINNED` in the script and the boot-trail's literal together; do not proceed on an unpinned host |
| `[FAIL] … the cutover is BLOCKED` at verification, or `[FATAL] gh secret set … failed` | Verification failed (the repo secret was NOT touched — the previous token still serves), or the store did not land after a green verification; either way a live token exists that nothing holds | Revoke the token in-page, then retry the chain. (`gh secret list` failing *after* the write is reported separately and does not mean "not stored" — re-run the list before revoking) |
| A probe posts TRANSIENT after the dispatch, or every Sentry-backed probe posts 401 daily under a green run | 401: the stored value is wrong (JSON-encoded, truncated) or the integration/token was deleted dashboard-side; 403: a scope gap | 401: re-run the chain (the normalise step asserts shape), recreating the integration if the panel is empty; 403: the scope row above |
| The sweeper run is red with `REQUIRED SECRET MISSING` | A tracker directive names a secret the workflow does not bind (retired name, misspelling, or an empty binding) | Rewrite the directive's `secrets=` clause (`gh issue edit <n> --body-file …`) or fix the workflow `env:`; the comment on the tracker names which |
| `[WARN] shred … failed` on exit | Non-tmpfs `/tmp` or a permission change | Remove the named directory by hand; the plaintext lived seconds under 0700 |
| `iac`, exit 3 (or 130/141/143 after `interrupted during the store`): `HOLD THE NEW TOKEN … / UNVERIFIED … / UNCHANGED BY THIS RUN …` then `do NOT revoke the old token yet` | A store failed after an earlier target took, or may have taken, the new value, so more than one token may be live | Do not revoke anything yet. Mint a fresh token and re-run the chain (it rewrites all three targets), then keep only the newest row in the Tokens panel. If the SAME target fails twice, fix access to it (e.g. Doppler write permission on that config) before minting again |
| `iac`: `[FATAL] doppler preflight failed (…) -- nothing was stored` | Doppler login expired, `soleur/prd` / `soleur/prd_terraform` is missing or reshaped, or the key is unreadable in one of them | `doppler login`, or check the config names and access; with `--from-file`, shred the named source file or re-run with it |
| `iac`: the terraform-drift `web-platform/sentry` leg prints `##[error]Terraform plan failed in web-platform/sentry` after a store | The stored value is wrong or lacks a scope a Terraform resource needs (or an unrelated plan failure) | Do not revoke the old token; read the leg's `[ERROR]` notification for the cause, re-run the chain if it is auth, and check the scope set against ADR-031 |

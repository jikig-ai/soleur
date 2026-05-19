---
date: 2026-05-19
category: infrastructure
topic: PR-F Inngest substrate — five compounding bugs that silently broke all cron functions in production
trigger_prs:
  - "#4062 (TR9 PR-2 cron-follow-through-monitor — ship-time audit surfaced it)"
related_prs:
  - "#3940 (PR-F substrate)"
  - "#3985 (TR9 PR-1 cron-daily-triage)"
related_issues:
  - "#4017 (P1: PR-1 substrate missed all scheduled fires)"
  - "#4079 (PR-2 follow-through with auto-verification)"
related_rules:
  - "hr-tagged-build-workflow-needs-initial-tag-push (NEW)"
  - "hr-ship-message-no-operator-checklist"
  - "hr-no-dashboard-eyeball-pull-data-yourself"
  - "hr-multi-step-post-merge-bootstrap-script"
---

# The Inngest substrate had five compounding bugs in production

PR-F (#3940) introduced the self-hosted Inngest substrate on the Hetzner VM in 2026-05-18. PR-1 (#3985) and PR-2 (#4062) then migrated GH Actions cron workflows onto it. Both passed CI, both got `ok` Sentry check-ins at merge-time smoke tests, both then missed every subsequent scheduled fire. The first signal that something was wrong arrived via Sentry's `missed` monitor alerts, which were initially mis-categorized as follow-through verification items (#4017) rather than P1 outages.

The substrate had **five separate bugs**. Each individually would have broken production. The combination meant production was never actually working.

## Bug #1 — Inngest server was never installed on the VM

**Symptom:** `systemctl status inngest-server.service` → `Unit could not be found`. No binary at `/usr/local/bin/inngest`. Nothing listening on `127.0.0.1:8288`.

**Root cause:** PR-F shipped a tag-triggered OCI build workflow (`.github/workflows/build-inngest-bootstrap-image.yml` triggered by `vinngest-v*.*.*` tag push), plus a `ci-deploy.sh inngest` branch that pulls + runs the OCI image. The intended flow:
1. Operator pushes `vinngest-v1.0.0` tag
2. GHA builds + publishes `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`
3. Operator triggers deploy webhook with payload `deploy inngest <image> v1.0.0`
4. `ci-deploy.sh` pulls + extracts + runs `inngest-bootstrap.sh` on the host

No `vinngest-v*` tag was ever pushed. The OCI image never existed in ghcr. The webhook deploy was never triggered. So even though the IaC, the script, and the deploy code all existed, the actual install never happened. **The substrate was a half-installed pipeline waiting for an operator click that never came.**

**Codified as rule:** `hr-tagged-build-workflow-needs-initial-tag-push`. Any PR adding a tag-triggered build workflow MUST push the initial tag in the same PR or as an immediate follow-up commit on main.

## Bug #2 — `/api/inngest` route was auth-gated

**Symptom:** Even with Inngest server up, `curl http://127.0.0.1:8288/api/v0/runs` showed zero registered functions. Manual `inngest send` events were accepted but no function executed.

**Root cause:** `apps/web-platform/middleware.ts` runs Supabase auth on every path except those in `lib/routes.ts:PUBLIC_PATHS`. `/api/inngest` wasn't in the list. The Inngest server polls the SDK URL (`http://127.0.0.1:3000/api/inngest`) to discover function definitions. Every poll request got `307 → /login`. The SDK could never register.

ADR-030 invariant I4 stipulates that `/api/inngest`'s `inngest/next.serve` performs its own HMAC signature verification (signingKey from INNGEST_SIGNING_KEY) — so the route is safe to expose publicly. Adding it to PUBLIC_PATHS is the correct fix.

**Fix:** `lib/routes.ts:PUBLIC_PATHS` += `/api/inngest`. Regression test in `test/middleware.test.ts`.

## Bug #3 — Signing-key prefix incompatible between SDK and CLI

**Symptom:** `inngest start --signing-key "signkey-prod-d51ed..."` → `Error: signing-key must be hex string with even number of chars`.

**Root cause:** Terraform-managed Doppler secret `INNGEST_SIGNING_KEY = signkey-prod-${random_id.hex}` (78 chars total). The SDK (`node_modules/inngest/helpers/strings.js`) parses and strips this prefix internally. The Inngest CLI's `--signing-key` arg accepts only the bare 64-char hex. Same secret, two consumers, two parse rules.

**Fix:** Bake `${INNGEST_SIGNING_KEY#signkey-prod-}` strip into the systemd unit's `ExecStart` via a `bash -c` wrapper (systemd escapes `$$` so the parameter expansion runs at exec-time, not at systemd-parse-time).

## Bug #4 — `/var/lib/inngest` not writable by the unit's User

**Symptom:** `doppler[...]: unable to open database file: out of memory (14)`. The "OOM" wording is misleading — SQLite error 14 is `CANTOPEN`, almost always a permission or path issue.

**Root cause:** `inngest-bootstrap.sh` did `mkdir -p /var/lib/inngest` as root. The systemd unit runs as `User=deploy`. SQLite couldn't write the DB file.

**Fix:** Add `chown deploy:deploy /var/lib/inngest && chmod 0750` to the bootstrap script immediately after `mkdir`.

## Bug #5 — `webhook.service` sandbox blocked the bootstrap writes

**Symptom:** Deploy webhook accepted (HTTP 202), then immediately reported `exit_code: 1, reason: inngest_bootstrap_failed`. ci-deploy logs showed `chown: invalid group: 'root:deploy'` — even though the `deploy` group definitely exists on the VM (`getent group deploy` confirms it).

**Root cause:** `webhook.service` has `ProtectSystem=strict`, which makes `/etc/`, `/usr/`, `/boot/` read-only via mount-namespace isolation. The `ReadWritePaths=/mnt/data /var/lock` whitelist did NOT include `/etc/default` or `/etc/systemd/system` or `/usr/local/bin`. When `ci-deploy.sh inngest` invoked `sudo -E env … bash inngest-bootstrap.sh`, sudo elevated the UID to root but did NOT escape the mount namespace. So the script ran as root but couldn't write to `/etc/`. The `printf > /etc/default/inngest-server` redirect silently produced a partial/empty file; the subsequent `chown root:deploy` then errored with a misleading message because the file's state was unexpected.

**Fix:** Widen `webhook.service` ReadWritePaths to include `/etc/systemd/system /etc/default /var/lib/inngest /usr/local/bin`. Update BOTH `apps/web-platform/infra/webhook.service` AND `apps/web-platform/infra/cloud-init.yml` (the cloud-init copy applies to fresh-host provisioning).

**Secondary fix in the same bootstrap path:** the bootstrap originally relied on `DOPPLER_TOKEN` being already-set in the caller env. In the webhook deploy path it isn't — the script needs to read the token from `/etc/default/webhook-deploy` (the sibling service's already-provisioned env file with the same Doppler `prd` scope). Also added `DOPPLER_CONFIG_DIR=/tmp/.doppler` because `ProtectHome=read-only` blocks Doppler CLI's default fallback dir at `~/.doppler/fallback`.

## Why none of this was caught by CI

- **Bug #1** is a tag-push gap. CI doesn't model post-merge operator clicks.
- **Bug #2** is caught by `test/middleware.test.ts` IF the test enumerates `/api/inngest` — it didn't. CI ran the route file directly via `inngest.test.ts`, bypassing middleware.
- **Bug #3** is only surfaced when the actual Inngest CLI (not the SDK) consumes the value. Tests use the SDK.
- **Bug #4** requires running the unit; CI's bootstrap tests run the script as root in a clean Docker container with no `deploy` user, so the chown line runs as root-to-root and the mkdir runs as root in `/var/lib`.
- **Bug #5** requires running the bootstrap UNDER the webhook.service sandbox. CI runs the bootstrap script in a Docker container with the full filesystem writable.

## The detection chain that surfaced the cascade

The bugs were ONLY caught because:
1. User pushed back on a "post-merge operator checklist" pattern in PR-2's ship message (instead of accepting it)
2. I re-ran the verification myself via Doppler→Sentry API (instead of writing it down for them)
3. Sentry showed `missed` for PR-1's most recent fires (the auto-verification surfaced the symptom)
4. SSH into the production VM confirmed the inngest-server was never installed
5. Each subsequent fix attempt surfaced the next bug

Without the user's pushback, all five bugs would have continued unnoticed through PRs 3..N of the TR9 umbrella. The `hr-no-dashboard-eyeball-pull-data-yourself` rule existed but was not being applied during ship. Adding `hr-ship-message-no-operator-checklist` makes it structural.

## Self-check questions to apply going forward

For any future substrate PR:
1. **Does the deploy require a tag push?** If yes, the tag push MUST be in the same PR or a paired follow-up commit, not "the operator will push it later." (`hr-tagged-build-workflow-needs-initial-tag-push`)
2. **Does the runtime invoke an HTTP route protected by middleware?** If yes, add the route to `PUBLIC_PATHS` AND add a regression test.
3. **Does the systemd unit's `User=` differ from the bootstrap's running UID?** If yes, the bootstrap MUST `chown` every writable path it provisioned.
4. **Does the unit's `ExecStart=` reference a secret with a non-standard format?** If yes, normalize at exec-time, not at storage-time (other consumers may need the storage format intact).
5. **Does the bootstrap run under a sandboxed service's mount namespace?** If yes, enumerate every path it writes and add ALL of them to the parent service's `ReadWritePaths`.
6. **Does the bootstrap assume an env var is set by the caller?** Read it from a known on-disk source-of-truth file instead — sudo's env-stripping behavior makes "set by caller" unreliable.

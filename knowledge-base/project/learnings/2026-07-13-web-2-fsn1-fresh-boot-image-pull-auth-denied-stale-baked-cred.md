---
date: 2026-07-13
tags: [infra, ghcr, cloud-init, ci-deploy, observability, diagnosis, credential-staleness]
issues: ["#6090"]
adrs: ["ADR-088"]
category: bug-fixes
---

# web-2 fsn1 warm-standby "image-pull failure" was a DEPLOY-path GHCR auth_denied on a stale baked token — not a cloud-init pull failure

## Symptom (as reported)
web-2's fresh boot in fsn1 (after the #6393 hel1→fsn1 relocation `-replace`) "failed its
container image pull"; web-2 wasn't serving, shipped no logs, and `web-platform-release` went red
on web-2's leg. Framed as the recurring #6090 cloud-init fresh-boot image-pull class.

## What the telemetry actually showed (the hypothesis was wrong)
Pulled in-session, no SSH, no operator ask (`hr-no-dashboard-eyeball-pull-data-yourself`):

- **The cloud-init first boot SUCCEEDED past the image pull.** Sentry `WEB-PLATFORM-4S` (baked
  DSN), host_id `150638239` (= `soleur-web-2`, confirmed via the Hetzner API): timeline
  `bootcmd_start` → `cloudflared_ready` → `webhook_bound` (all **info**, no fatal). The seed/app
  pull is *upstream* of `webhook_bound`, so it worked.
- **The failure was in the release DEPLOY, not the boot.** `ci-deploy.sh exited 1
  (reason=image_pull_failed, tag=v0.213.4)`; the aggregate status JSON was unmistakably web-2
  (fresh host: 70G free, vector+inngest `inactive`).
- **Terminal cause: GHCR auth, not network.** Sentry `WEB-PLATFORM-59` `image pull failed
  (auth_denied) …:v0.213.4`; the deploy failed in **5 s** (excludes a network timeout).
  `WEB-PLATFORM-57 zot gate degraded (probe_unreachable)` (#6288) removed the zot-primary cushion
  → straight to GHCR → 401.
- **The credential itself was VALID.** A live GHCR basic→bearer exchange with the current Doppler
  `GHCR_READ_TOKEN` fetched the exact denied tag's manifest → **HTTP 200**. So the fix was
  re-fetch-on-failure, NOT credential rotation.

## Root cause
Both GHCR login sites re-fetched the current Doppler credential **only when the baked
`GHCR_READ_{USER,TOKEN}` was EMPTY** — never when a **present-but-STALE** baked token made
`docker login` *fail* (the failure was non-fatal, just logged). A fresh host's baked
`/etc/default/soleur-ghcr-read` token ages out by deploy time → stale baked login fails →
anonymous private pull → 401 `auth_denied` → `image_pull_failed` → the warm standby never serves.
The proven-failing site was `ci-deploy.sh:ghcr_prelude_and_login`; `cloud-init.yml`'s seed
`ghcr_login` block carried the identical EMPTY-only anti-pattern (it just didn't bite this boot
because the token was fresh at 20:06).

## Fix (§1A)
On a baked/first `docker login` **FAILURE** (not only EMPTY), re-fetch the CURRENT
`GHCR_READ_{USER,TOKEN}` from Doppler (hardened `timeout 45` + 3-try idiom) and retry the login
once. Fail-open in both sites: `ci-deploy.sh` (`ghcr_prelude_and_login`) and `cloud-init.yml` (the
seed-pull block, still inside its `( set +e ) || true` subshell). Amended ADR-088 with the
baked-token-staleness-vs-minter-TTL consumer note (no new ordinal).

## Lessons
1. **A "cloud-init image-pull failure" report is a hypothesis to verify against the boot
   telemetry, not a fact to fix blind.** The `stage` tag distinguishes boot-pull from deploy-pull;
   here the boot sailed past `webhook_bound` and the *deploy* pull is what 401'd. Shipping a
   cloud-init-only fix would have missed the real (deploy-path) site.
2. **The Sentry EVENTS search endpoint did not index the custom `stage` tag** (`has:stage` → 0),
   but the ISSUES surface (`/organizations/<org>/issues/`) + per-issue `tags/<key>/values/` did.
   For baked-DSN boot emits, query issues, not the events endpoint.
3. **A baked short-TTL credential is a cache that expires.** Any consumer of a rotated secret that
   bakes a snapshot at provision time must re-fetch on USE-FAILURE, not only on ABSENCE.
4. **`image_pull_failed` had no per-host tag** — the release aggregate JSON (host shape) and the
   `pull_result` classification were what pinned it to web-2. `pull_failure_event` should carry
   `host_id` (follow-up observability nit).

## Session Errors

1. **AC4 user_data size test failed initially** (rendered gzip 21,148 B > 21,000 B budget) — the §1A cloud-init addition pushed the `base64gzip` web render over the tripwire. Recovery: trimmed the inline comment (→21,060 B) then re-baselined `WEB_GZIP_BUDGET` 21,000→21,500 B with justification (pre-bootstrap seed-block logic can't be baked). **Prevention:** when adding to the cloud-init seed block, budget for the 32 KB/gzip cap up front — the size test is the gate, but expect a re-baseline for legitimately-inline pre-bootstrap logic.
2. **Sentry `has:stage` events-search returned 0** while the boot demonstrably emitted `stage` breadcrumbs. The custom `stage` tag isn't indexed on `/projects/.../events/?query=has:stage`. **Prevention:** for baked-DSN boot emits, query the ISSUES surface (`/organizations/<org>/issues/?query=<text>` + `/issues/<id>/tags/<key>/values/`), not the events endpoint. (Captured as Lesson #2.)
3. **CWD relative-path miss** — `cd apps/web-platform && bun test plugins/soleur/...` failed "did not match any test files" because the path is repo-root-relative. **Prevention:** run repo-root-relative test paths from the repo root, or use an absolute path (the Bash tool does not persist CWD across calls).
4. **hcloud servers JSON parser threw `KeyError: 'datacenter'`** (the list endpoint returns `datacenter: null` unexpanded). **Prevention:** defensive `.get()` chains on vendor JSON; one-off.
5. **Forwarded (session-state.md):** initial Write blocked by the worktree guard (retried at the correct worktree path); deepen-plan gate 4.8 mechanically flagged `var.ghcr_read_token` as PAT-shaped (reconciled false positive — it is the machine-account `read:packages` **PAT** (interim, ADR-087 D1), NOT an App-installation-minted token; the App-token minter is disabled precisely because App installation tokens **cannot pull** private GHCR packages, ADR-088 superseded on that fact — corrected 2026-07-14 per #6400).

# Phase 0 — Diagnosis-first evidence (#6400)

Diagnosis-first, self-pulled (no SSH, no operator fetch). Captured 2026-07-14.

## 0.3 Current prod state

`curl -s https://app.soleur.ai/health | jq .version` → **`0.213.6`**.

The acute outage described in #6400 (prod frozen on `0.213.2` since 12:32 on
2026-07-13) has **self-resolved** — a later deploy (0.213.6) landed. Per the plan
(Root-cause verification gate), the deliverable is the **durable structural
hardening** so the login-ok/pull-deny class cannot recur; the fix ships
regardless of whether the acute outage is currently firing.

## 0.1 Sentry — `op:image-pull pull_result:auth_denied` (14d window)

Query (Sentry API, org `jikigai-eu`, `SENTRY_AUTH_TOKEN` from Doppler
`prd_terraform`): `op:image-pull pull_result:auth_denied`, `statsPeriod=14d`.

**8 `auth_denied` events** across the incident window:

| timestamp (UTC) | tag |
|---|---|
| 2026-07-14T12:47:45 | v0.213.6 |
| 2026-07-13T23:17:01 | v0.213.5 |
| 2026-07-13T23:01:24 | v0.213.2 |
| 2026-07-13T20:39:22 | v0.213.4 |
| 2026-07-13T20:18:00 | v0.213.3 |
| 2026-07-12T21:14:12 | v0.213.1 |
| 2026-07-12T20:57:17 | v0.213.0 |
| 2026-07-12T14:47:28 | v0.212.6 |

Notes:
- The auth_denied class is **live and recent** — the most recent event
  (2026-07-14 12:47) is on the **winning `v0.213.6` tag itself**, i.e. the
  denial fired even on the deploy that ultimately reached prod (a later retry
  or a fan-out host succeeded). This is exactly the recurring class this fix
  targets.
- `host_id` is **empty** on every event — the #6396 `host_id` tag merged only
  in `c749e4e6a` (this branch's base); these events predate the tag reaching
  the emitting host, or `HOST_ID` was unset on the host. Host attribution will
  populate on the next occurrence once the fix + #6396 tag are both live.

## 0.2 Better Stack Vector — `ci-deploy` PRELUDE lines

Query: `betterstack-query.sh --since 48h --grep ci-deploy` (Doppler
`prd_terraform`). The rows returned in-window were from the `soleur-inngest-prd`
host's `ci-deploy` restart path, NOT the `web-platform-release` deploy leg where
the GHCR `docker pull` auth-denial fires. The decisive PRELUDE
`docker login … ok` → `IMAGE_PULL_FAIL … auth_denied` discriminator was not
isolable from the returned window.

**Disposition (per plan):** the login-ok/pull-deny gap is **confirmed by
code-read** — §1A recovery is gated on `docker login` outcome
(`ghcr_prelude_and_login`, `ci-deploy.sh:656-683`) but the production denial
surfaces one step later at `docker pull` inside `pull_image_with_fallback`
(`ci-deploy.sh:750-782`), which has **no** credential re-fetch/relogin/retry. A
credential that logs in but cannot pull bypasses §1A entirely. The plan
explicitly directs: ship the structural fix regardless of whether Phase 0
isolates the branch, because the gap is real in the code. Confirmed.

## Conclusion

Acute P1 self-resolved (prod on 0.213.6); the structural login-ok/pull-deny
recovery gap is real and the auth_denied class fired as recently as today.
Proceed to implement the durable fix (Phases 1–3) + doc/register hygiene
(Phase 5) + soak follow-through (Phase 6). Closure is **soak-gated** post-deploy
(`Ref #6400`, not `Closes`).

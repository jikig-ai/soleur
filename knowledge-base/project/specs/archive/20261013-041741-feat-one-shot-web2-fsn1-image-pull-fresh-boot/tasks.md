# Tasks — fix(infra): web-2 fsn1 fresh-boot image-pull failure

Plan: `knowledge-base/project/plans/2026-07-13-fix-web-2-fsn1-fresh-boot-image-pull-plan.md`
Lane: cross-domain (no spec.md — defaulted). Brand-survival threshold: none.

## Status (2026-07-13)

- **Phase 0 (diagnose): DONE** → verdict **Branch A (deploy-path variant)**. web-2's cloud-init
  boot succeeded past the pull (`webhook_bound` info); the RELEASE DEPLOY (`ci-deploy.sh`, tag
  v0.213.4) failed `image pull failed (auth_denied)` (Sentry WEB-PLATFORM-59) on a stale baked
  GHCR token, zot cushion absent (WEB-PLATFORM-57 / #6288). Live test: current Doppler cred pulls
  the denied tag → HTTP 200 (fix = re-fetch-on-failure, not rotation). Verdict in plan
  `## Root-Cause Verdict`.
- **Phase 1 §1A: DONE + tested.** Re-fetch Doppler creds + retry `docker login` on baked-login
  FAILURE (not only EMPTY), fail-open, in BOTH sites: `ci-deploy.sh` `ghcr_prelude_and_login`
  (proven site) and `cloud-init.yml` seed `ghcr_login` block. Tests: ci-deploy 129/129,
  cloud-init-ghcr-seed-login 7/0, user-data-size 23/0 (budget re-baselined 21,000→21,500 B).
- **Phase 2 (Vector "ships logs"): DEFERRED → follow-up.** See `decision-challenges.md` DC-1
  (attribution/risk rationale: don't add a new fail-open boot surface to the boot Phase 3
  verifies). Follow-up issue filed at ship. C4 `web-2 → Better Stack` edge moves to that PR.
- **Cross-cutting: DONE.** ADR-088 amended (baked-token-staleness note, no new ordinal);
  learning captured; sibling parser tests green (journald 36/0, inngest-bootstrap 49/0,
  host-bootstrap-observability 69/0). tsc clean.
- **Phase 3 (verify on real boot): POST-MERGE** — dispatch `web-2-recreate`, confirm Sentry
  `cloud_init_complete` + green web-2 release leg (no SSH).

## Phase 0 — Diagnose (no SSH, no operator ask; `hr-no-dashboard-eyeball-pull-data-yourself`)

- 0.1 Resolve the Sentry read token read-only from Doppler (`SENTRY_IAC_AUTH_TOKEN` @ `soleur/prd_terraform`, fallback `SENTRY_AUTH_TOKEN` @ `soleur/prd`). If absent → record as an observability-gap finding; do NOT ask the operator.
- 0.2 Query the baked-DSN Sentry project (org `jikigai-eu`, project `web-platform`, eu.sentry.io) for web-2 fresh-boot events since `2026-07-13T20:05:00Z` — **ALL stages (`has:stage`), NOT a pull-only enum** (a post-pull fatal emits stages outside the pull set; a scoped query false-routes to Branch F). Capture latest FATAL `tags.stage`+`detail` AND whether `stage=cloud_init_complete` appears. Verify the events-endpoint shape against the org-subdomain base URL (`2026-05-17-sentry-eu-region…`).
- 0.3 Cross-check zot host health (`SOLEUR_ZOT_DISK` self-report + `/v2/` heartbeat) to rule in/out Hypothesis 2 (#6288 OOM-loop).
- 0.4 Emit the `## Root-Cause Verdict` (PR body + plan) via the decision matrix → select the Phase-1 branch. No fix ships without this verdict.

## Phase 1 — Fix the discriminated stage (only the selected branch)

- 1.A cloud-init.yml `STAGE=ghcr_login` login attempt at `:484-490` (guards at `:481,483`): re-fetch `GHCR_READ_{USER,TOKEN}` from Doppler on baked-login **failure**, not only EMPTY; retry `docker login`; record outcome in `/run/soleur-stage-detail`. Keep the `( set +e … ) || true` subshell fail-open. NOTE: on a `-replace` the baked token is freshly minted (inside 1h TTL), so **Branch B** (post-migration zot miss → GHCR fallback) is the more probable trigger — A+B are one hypothesis; do not pre-anchor on A.
- 1.G (post-pull fatal — `webhook_bound`/`cloudflared_ready`/`webhook_checksum`/`plugin_seed`/poweroff gate): pull succeeded, boot dies later → re-scope to the named stage; do NOT ship §1A.
- 1.A′ baked template vars empty: trace `var.ghcr_read_{user,token}` → `server.tf:165-166` → bake `cloud-init.yml:416-418`; add an apply-time non-empty assertion before `web-2-recreate`.
- 1.C/1.C′ (only on Phase-0 timeout/DNS signal): run the L3→L7 checklist, fix firewall/routing/resolver, paste the artifact.
- 1.D (only on `stage=verify`): re-pin known-good digest via `resolve-web1-known-good-tag.sh` + re-assert `web2-recreate-preflight.sh` (hash == `local.host_scripts_content_hash`). No cloud-init edit.
- 1.E (only on `manifest unknown`): fix effective-ref/manifest selection.
- 1.F (no events): assert `var.sentry_dsn` bake non-empty; treat observability as primary defect → Phase 2.

## Phase 2 — Restore log-shipping on web-2 ONLY ("ships logs"; web-1 = follow-up)

- 2.1 Install Vector on web-2 via the SAME inngest image-extraction path, ungated by `web_colocate_inngest` (preferred — no second delivery path / no lockstep). Respect the 32 KB user_data cap (bake bodies into soleur-host-bootstrap.sh).
- 2.2 Web-host `vector.toml`: `host_name` derived per-host (`soleur-${host_id}`), not the pinned `soleur-inngest-prd`.
- 2.3 **Fail-open + sequenced:** the Vector runcmd MUST run AFTER `:9000` bind / `stage=cloud_init_complete` and be fail-open (`( set +e … ) || true`, warning breadcrumb, never `exit 1`). Observing the boot must not break it.
- 2.4 Ship journald (webhook.service + app container journald + boot runcmd) to the existing Better Stack Logs source.
- 2.5 web-1 log-shipping = explicit follow-up issue (NOT this PR). If ever added: config/immutable-redeploy channel only, never a `-replace`.
- 2.6 When Phase 2 ships: add the `web-2 → Better Stack` C4 Container edge (read all three `.c4` files; a generic "web host" element may already carry it) + `view include` in `views.c4`; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 3 — Verify on a real fresh boot (post-merge, no SSH)

- 3.1 Dispatch `apply-web-platform-infra.yml` `apply_target=web-2-recreate` (scoped `-replace`; preflight-gated).
- 3.2 Confirm Sentry reaches `stage=cloud_init_complete` with no `pull/verify/ghcr_login` fatal (Observability `discoverability_test` curl).
- 3.3 Confirm `web-platform-release` web-2 leg = `ok_peer_fanout` (not `_degraded`); `:9000` bound; web-2 journald present in Better Stack.
- 3.4 `gh issue close`/comment the tracking issue only after 3.2–3.3 pass.

## Cross-cutting

- Amend ADR-088 with the one-line baked-token-staleness-vs-minter-TTL note (no new ordinal).
- Update sibling test guards (enumerate via `git grep`, do not trust a fixed list): `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-user-data-size.test.ts` (32KB cap), raw-YAML parsers (`journald-config.test.sh`, `cloud-init-inngest-bootstrap.test.sh`) IF a col-0 `%{` directive is added, Vector/parity tests.
- Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Run infra `*.test.sh`/`*.test.ts` via the repo's actual runner (check `package.json scripts.test` / `bunfig.toml`).
- Capture a learning at `knowledge-base/project/learnings/` (date + topic at write time) once Phase 0 names the cause.
- PR body: `Ref #6090` / `Ref #6389` (NOT `Closes` — closure is post-merge after the recreate apply).

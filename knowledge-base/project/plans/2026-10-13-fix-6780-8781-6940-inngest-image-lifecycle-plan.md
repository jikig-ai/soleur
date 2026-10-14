---
title: "feat(infra): inngest-bootstrap image lifecycle — ADR-135 host-side consumer bake, pre-merge candidate build lane, post-#6178 cutover follow-ups"
date: 2026-10-13
slug: inngest-image-lifecycle
branch: feat-one-shot-6780-8781-6940-inngest-image-lifecycle
issue: 6780
closes: 8781
refs: 6780,6940
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-13 (manual sequential pass — this harness has no Task/Agent tool; per-section, skills, learnings and review fan-outs ran inline by the author, `Reviewed-Coverage: sequential-fallback` — no independent review is claimed)
**Sections enhanced:** Proposed Solution (zot-direct pull correction vs ADR-135's stale GHCR-direct assumption, after verifying #8036 deleted the host's GHCR read credential), Observability (marker path routed through `inngest-boot-phone-home.sh` — the baked `vector.toml` tag cannot go live before the next image bake), Scope Check (three issues mapped to one PR; #6940 item 1 verified already-landed in #9698).

### Key Improvements

1. **Reality-corrected the ADR-135 v1 pull path.** ADR-135 specifies "GHCR-direct host pull, no `ZOT_*` on the host" — written before #8036 item 1d deleted the dedicated host's GHCR read-cred bake (the PAT is revoked; zot is the ONLY pull path on this host today). The consumer therefore pulls `$ZOT_EP/jikig-ai/soleur-inngest-config@sha256:<pointer>` using the SAME baked `/etc/default/soleur-zot-read` credential the bootstrap image pull already uses — zero new isolated-Doppler secrets, exactly the property GHCR-direct was chosen for. A dated ADR-135 amendment ships in this PR.
2. **Marker channel reality check.** The drift comparator greps Better Stack for `SOLEUR_INFRA_PULL_APPLIED`. The new journald tag `inngest-config-refresh` cannot reach Better Stack until the *next* `vinngest` image bake carries the updated `vector.toml` — the tag is baked into the image, not the cloud-init. v1 markers therefore ride `inngest-boot-phone-home.sh` (a direct Better Stack POST that works on the CURRENT pinned image); the vector.toml tag + `journald-config.test.sh` lockstep pins ship anyway so the journald channel goes live on the next bake.
3. **#6940 item 1 verified landed** in commit `7f23ff853f` (PR #9698): `inngest-registry-probe.sh` emits `functions[].triggers[].type`, `zero_run_cron_ids` exists in `scripts/cutover-inngest.sh`, `CUTOVER_DISCOVERY_LOOKBACK_S` is env-mapped. This PR ships no code for item 1 — the plan records the evidence so the issue's stale checkbox can be ticked.

## Overview

One PR covers three coupled issues in the inngest-bootstrap image lifecycle. A sibling one-shot today hit the motivating defect directly: it wanted to fix `inngest-redis-bootstrap.sh` but had to revert because the script is baked into the pinned `vinngest` image and the only delivery path is a force-replace of the sole production scheduler. These three issues are the machinery that closes that loop:

- **#6780** — the dedicated host (`soleur-inngest-prd`, 10.0.1.40, deny-all-public) has no in-place redelivery channel. ADR-135's pull-based signed config-refresh channel is **producer-complete**: `build-inngest-config-bundle.yml` packs + keyless-signs + dual-publishes the bundle behind a reviewer-gated environment; `inngest-config-digest.tf` holds the count-gated promotion pointer; `inngest-config-drift.yml` + `inngest-config-drift-compare.sh` + `cron-inngest-config-drift.ts` exist dormant. What never landed is the **host-side consumer** (the verify+apply script, the systemd timer/service, the baked cosign anchor, the `applied.version` floor) — it was designed to "ride the #6178 cutover provision (PR #6348)" and the cutover shipped without it. This PR bakes it into `cloud-init-inngest.yml`; it goes live on the next `inngest-host-replace`.
- **#8781** — #8747 makes the publish workflow refuse any `vinngest-v*` tag whose commit is off main, which removed the only pre-merge image build path. Ship option (a): a no-push `docker build` check on PRs that touch the baked carriers. Option (b) — a candidate OCI tag namespace publishing without the ADR-232 bump or AC6 guard — is recorded as a `pending - assumed:` fork and deferred.
- **#6940** — item 1 is already landed (#9698, verified on this branch). Item 2 ships the `CUTOVER_QUIESCE_PROBES` env mapping plus the anchored `CUTOVER_[A-Z_]+` completeness guard the issue specifies, with `CUTOVER_REGISTRY_BASELINE` held on a named deferred list until #6178's AC-V4 is green (latest op=verify, run 35415585389 on 2026-09-19, still detected DOUBLE-FIRE). Item 3 threads a `page_size` query param through `hooks.json.tmpl` → the on-host `INNGEST_GQL_PAGE_SIZE` seam so the deferred measurement dispatch can run it.

## Research Insights

**Premise validation (2026-10-13, this branch).** #6780, #8781, #6940, #9060 all OPEN (`gh issue view`). PR #10257 is this branch's draft. PARKED PR #10081 edits `cloud-init-inngest.yml` (textual overlap expected; do not merge or rebase onto it). PR #10255 (vector journald partition) touches `vector.toml`/`journald-config.test.sh` territory — note as conflict surface. Issue #9705 (open code-review) covers `betterstack-logs-alerts.tf`/`uptime-alerts.tf` — NOT in this plan's edit set.

**Verified on `origin/main` this pass:**

- The producer channel exists and is wired: `build-inngest-config-bundle.yml` (signing job holds `environment: inngest-config-signing`, TF-provisioned with reviewer `54279`, `-target=github_repository_environment.inngest_config_signing` allow-listed in `apply-web-platform-infra.yml`), `inngest-config-bundle-pack.sh` (deterministic manifest, VERSION inside the signed bytes, fail-closed), `inngest-config-digest.tf` (`doppler_secret.inngest_config_digest`, `count`-gated on non-empty digest, no `-target=` route — #9060), `inngest-config-drift.yml` + `inngest-config-drift-compare.sh` + `cron-inngest-config-drift.ts` (manual-trigger only until channel-live).
- `INNGEST_CONFIG_DIGEST` is ALREADY admitted in the boot isolation self-check regex (`cloud-init-inngest.yml`, exact-set `n_total -ne n_inngest`); the floor stays `-lt 5` and bumps 5→6 only in the change that first promotes a digest — **not this PR**.
- The host's only registry read path is zot: `/etc/default/soleur-zot-read` (baked creds) → `docker login` → `docker pull $ZIREF`. The GHCR leg and its read credential are deleted (#8036).
- `infra-config-install.sh` is NOT baked on the inngest host (HARD-12 confirmed) — it must be newly baked, root-invoked, without the web-host webhook/sudoers apparatus. Its `DEST_SPEC` lacks the five dedicated-host dests.
- The seeded `inngest-config-refresh-set.txt` lists 8 scripts that are all **web-host** scripts (verified: zero `/usr/local/bin/<name>` hits in `cloud-init-inngest.yml`; the dedicated host has no webhook). They are the PRODUCER contract only.
- `inngest-config-signing.tf` is applied-path-complete (environment wired into the apply allow-list).
- `inngest-userdata-budget.sh --json`: stored 21,520 B of 32,768 (headroom 11,248 B); `local.inngest_rationale_strip` removes `#` prose lines pre-gzip, so comment prose in the baked script costs ~0 stored bytes.
- AC-V4 is NOT green: latest op=verify run 35415585389 (2026-09-19) detected DOUBLE-FIRE; later dispatches were op=resume/op=doublefire-probe, not verify.
- `#6940` item 1 landed in `7f23ff853f`; the issue's checkbox is stale.

**Property List.**

- P1. A refresh-set change can reach the dedicated host without `inngest-host-replace`: pointer-promoted bundle → host timer pulls from zot → cosign `verify-blob` offline → per-file sha256 → set-atomic install → `applied.version` advances → off-box marker.
- P2. Nothing unverified executes: version is read only from the cosign-verified manifest (HARD-2); every gate fails closed (HARD-10); a rollback/replay/stale bundle is a named `SOLEUR_INFRA_PULL_VERIFY_FAIL`, never a silent no-op (HARD-9).
- P3. The channel engine can never be refreshed by itself (HARD-1): `inngest-config-refresh.sh`, the cosign path, the units, `applied.version`, and `infra-config-install` are NOT in the refresh-set nor in `DEST_SPEC`.
- P4. A carrier-changing PR proves the image builds before merge (option a), with zero new publish surface (contents:read only; no `docker push`, no `id-token`, no `packages: write`).
- P5. Every `CUTOVER_*` name `scripts/cutover-inngest.sh` dereferences is either env-mapped in `cutover-inngest.yml` or pinned on a named deferred list — a new dead knob like #6617's fails structural CI.
- P6. The `page_size` measurement knob is plumbed end-to-end but inert by default (`PAGE_SIZE=100` unchanged); the live measurement is a deferred operator dispatch.
- P7. All four `jikig-ai/soleur-inngest-bootstrap:vX.Y.Z@sha256:` refs across `cloud-init.yml` and `cloud-init-inngest.yml` share one tag+digest — a partial bump fails the new AC6c assertion.

**Cut List (mechanism → property → what already covers it).**

- Extend the web-host infra-config PUSH to the dedicated host (issue option a): cut — the dedicated host has no webhook and is deny-all-public inbound; an inbound push path is the rejected Option C in ADR-135.
- A separate `inngest-config-refresh.service` env seam for the pointer: cut — the pointer is already a promoted Doppler value; `--only-secrets INNGEST_CONFIG_DIGEST` bounds the unit's env to exactly it (the #7761 lesson).
- Making the bundle zot mirror load-bearing (drop `continue-on-error`): cut for now — the drift comparator is the designed detector for a promoted-but-unpullable pointer; flipping the mirror to required is a named follow-up.
- Refresh-set membership for the systemd units (`*.service`/`*.timer`) and `vector.toml`: cut in v1 — unit swaps need daemon-reload/restart semantics the channel deliberately lacks; `vector.toml`'s dest is image-installed and off the `DEST_SPEC` model. Scripts-only v1.
- cloud-init-inline scripts (`inngest-nftables.sh`, `inngest-boot-phone-home.sh`, `inngest-luks-open.sh`) as refresh-set members: impossible in v1 — the packer reads repo files; these live inline in the template. Recorded limitation.
- Extracting the build step into a shared `.github/scripts/` helper consumed by the real publish workflow: cut — the dispatch path checks out the OLD TAG's tree where a helper would not exist (the workflow's own comment); the check lane duplicates the logic under a normalized parity guard instead.
- Better Stack absence-heartbeat monitor (Terraform): deferred to channel-live — keyed on `SOLEUR_INFRA_PULL_APPLIED` rows that cannot exist before first promotion; shipping it earlier alarms permanently.
- Host SSH/serial fallback for any of this: never — `hr-no-ssh-fallback-in-runbooks` stands; all observability is off-box.

**Institutional precedents used.** `inngest-cutover-flip.{service,timer}` (root `doppler run --only-secrets` oneshot + 30s timer + skip-vs-fail `ConditionPathExists` + sandboxing block + `SyslogIdentifier`↔vector-tag lockstep); `inngest-luks-open.service` (baked oneshot inside `cloud-init-inngest.yml` write_files); `ci-deploy.sh` `COSIGN_IMAGE`/`COSIGN_IDENTITY_REGEXP`/`COSIGN_OIDC_ISSUER` (air-gapped keyless verify, ADR-087); `inngest-redis-luks*.test.sh` (heredoc extraction + counted-floor conventions); `inngest-config-bundle-pack.test.sh` (producer-side suite to mirror); the ADR-232 bump's "all four sites atomically + token-equality post-check" (the AC6c shape).

## Hypotheses

No `firewall`/network-outage keyword in the issues — the L3→L7 checklist does not fire. The failure modes are delivery-mechanism gaps (no channel, no candidate lane, dead env vars), each named in the issue bodies with file/line evidence, verified above.

## Research Reconciliation — Spec vs. Codebase

| Brief/issue claim | Reality (read 2026-10-13, this branch) | Plan response |
|---|---|---|
| #6780: "Extend the infra-config push to target the dedicated host" | The push is a webhook POST to `deploy.soleur.ai/hooks/infra-config` on web hosts; the dedicated host runs no webhook and is deny-all-public. The pull-based channel is the designed answer (ADR-135 Option A, producer shipped in #6839). | Bake the host-side consumer; the push is never extended. |
| #6780: "four pin sites … cloud-init-inngest.yml:390 tag+digest, cloud-init.yml:699 IREF, cloud-init.yml:705 ZIREF, inngest-bootstrap.sh:492 comment" | Sites moved but the set is the same: each cloud-init file carries one `IREF=` + one `ZIREF=` `jikig-ai/soleur-inngest-bootstrap:vX.Y.Z@sha256:<64hex>` ref (currently v1.1.52), and `inngest-bootstrap.sh` carries a stale doc literal (v1.1.24, no digest — matches no pin regex). The bump script already rewrites all four real sites atomically with a token-equality post-check. | AC6c pins count==4 / distinct==1 across the two files; the comment literal stays out (it is documentation, not a pull ref). |
| #6780: "the cross-file assertion that would catch a partial bump does not yet exist" | Confirmed — AC6b asserts count==2/distinct==1 on `cloud-init.yml` only; the dedicated host's second ref (`ZIREF`) is unchecked for consistency. | New AC6c block in `cloud-init-inngest-bootstrap.test.sh`. |
| ADR-135: "host pulls GHCR-direct by digest on the same baked read credential it already uses for the bootstrap image" | Stale — that credential was deleted by #8036 (AP-016 lapsed, PAT revoked). The host pulls ONLY from zot via baked `/etc/default/soleur-zot-read`. | Consumer pulls zot-direct; dated ADR-135 amendment. |
| #6940 item 1 "Blocked on: extending inngest-registry-probe.sh to emit trigger type" | Already landed (#9698): `triggers { type value }` selected, `functions` field emitted, `zero_run_cron_ids` + the scoped re-probe wired into op=verify, `CUTOVER_DISCOVERY_LOOKBACK_S` mapped. | Verify-only; checkbox evidence recorded; no code for item 1. |
| #6940 item 2 "Map CUTOVER_REGISTRY_BASELINE + CUTOVER_QUIESCE_PROBES … AFTER AC-V4 is green" | AC-V4 not green (DOUBLE-FIRE 2026-09-19). Mapping the baseline now would arm a dormant `exit 1` upstream of the 2.6 check. | Map `CUTOVER_QUIESCE_PROBES` (harmless retry count) + ship the anchored completeness guard with `CUTOVER_REGISTRY_BASELINE` on a named deferred list. |
| #6940 item 3 "needs a new hook parameter threaded through hooks.json.tmpl plus a host hook-config redeploy" | `hooks.json.tmpl` is in `deploy_pipeline_fix.triggers_replace` (`local.hooks_json`), so the merge's normal apply re-fires the push and redeploys the hook config — no separate redeploy step needed. | Thread `page_size` end-to-end; measurement dispatch deferred. |

## Problem Statement

The dedicated Inngest host's host-script delivery is priced at a full sole-scheduler force-replace: four pin sites move together, the LUKS volume must re-attach, and the tag push reds `main` until all four land. ADR-135 designed the pull-based signed channel that eliminates that loop for `*.sh` operational scripts — but only its CI producer half shipped (#6839). The host-side consumer the whole design depends on was deferred to a cutover that has long since passed, so the channel is dead code on main: a bundle could be signed and promoted today and nothing on the host would ever pull it. In parallel, #8747's ancestry gate removed the pre-merge candidate build (any PR touching a baked carrier now gets no image signal at all), and three post-#6178 cutover follow-ups remain: the registry-sourced discovery (landed), the `CUTOVER_*` env mapping + completeness guard (partially blocked), and the `PAGE_SIZE` measurement (unplumbed).

## Proposed Solution

Rulings are recorded in `knowledge-base/project/specs/feat-one-shot-6780-8781-6940-inngest-image-lifecycle/decision-challenges.md` — every technical row is `pending - assumed:` (no Agent tool on this harness); a `soleur:engineering:cto` ruling at review supersedes them.

### Workstream A — #6780: the host-side consumer bake (ADR-135 Phase 4)

1. **`inngest-config-refresh.sh` — the verify+apply script, inline in `cloud-init-inngest.yml` `write_files`** (`/usr/local/bin/inngest-config-refresh.sh`, 0755 root:root, inside the template like `inngest-nftables.sh`/`inngest-luks-open.sh`, extracted by the new suite via the same heredoc-delimiter convention). Flow, all fail-closed (HARD-10):
   - Read `INNGEST_CONFIG_DIGEST` from env (the unit's `--only-secrets`-scoped `doppler run` injects exactly that). Empty → throttled noop (marker throttle 300 s, mirrors the flip's `NOOP_THROTTLE_S` — cadence strictly under 15 min so the rows stay a liveness witness).
   - Pointer digest == applied digest → throttled noop.
   - Pointer differs → `docker login` from `/etc/default/soleur-zot-read` → `docker pull "$ZOT_EP/jikig-ai/soleur-inngest-config@<digest>"` (bounded `timeout`) → `docker create`/`docker cp` extract `bundle.tar.gz` → untar to PrivateTmp staging.
   - `docker run --rm` the **pinned cosign image** (`gcr.io/projectsigstore/cosign@sha256:57c0e93a…` v3.1.1 — the SAME pin as `ci-deploy.sh`'s `COSIGN_IMAGE`, parity-pinned by the new suite) with staging + `/etc/soleur/cosign-trusted-root.json` mounted `:ro`: `cosign verify-blob --trusted-root … --certificate manifest.txt.cert --signature manifest.txt.sig --certificate-identity-regexp '^https://github\.com/jikig-ai/soleur/\.github/workflows/build-inngest-config-bundle\.yml@refs/heads/main$' --certificate-oidc-issuer https://token.actions.githubusercontent.com manifest.txt`. rc≠0 → `VERIFY_FAIL reason=signature`.
   - Read `VERSION=` only from the now-verified manifest (HARD-2). `VERSION ≤ applied.version` → `VERIFY_FAIL reason=rollback-or-replay` (rejection-as-signal, HARD-9). `applied.version` missing/empty/non-integer → treated as the baked floor `0` with a distinguishable `SOLEUR_INFRA_PULL_FLOOR version=floor` emit (HARD-8 floor marker), never parse-to-0-accept-all as a *silent* state.
   - `sha256sum -c` every manifest row → per-file mismatch → `VERIFY_FAIL reason=sha`.
   - Stage-all → install-all: for each manifest member, `infra-config-install /usr/local/bin/<basename> 755 root:root < member` (the helper's own DEST_SPEC allowlist re-checks the dest). Advance `applied.version` + write `/var/lib/inngest-config/applied.json` state (`applied_version`, `bundle_sha256`, `applied_ts`, `verify_result`) **only after the last file lands** (HARD-5; a mid-set failure leaves `applied.version` un-advanced and the next tick re-drives the whole pull→verify→apply).
   - Emits via BOTH `logger -t inngest-config-refresh` AND `inngest-boot-phone-home.sh <stage> "<SOLEUR_INFRA_PULL_* detail>"` — the phone-home POST is the v1 load-bearing off-box channel (works on the current pinned image; the vector tag goes live on the next bake).
   - Fixture seams (`DOCKER_BIN`, `COSIGN_IMAGE`, `STATE_DIR`, `APPLIED_VERSION_FILE`, `LOGGER_CMD`, `PHONE_HOME_CMD`, `INSTALL_CMD`, pointer env) honoured ONLY under a `--fixture-seams` argv flag, mirroring `inngest-cutover-flip.sh`'s #7761 gate — a Doppler config writer cannot reach argv, and `--only-secrets` keeps ambient secrets out.
2. **`infra-config-install` baked via a base64 templatefile var** — `write_files` entry `encoding: b64`, `path: /usr/local/bin/infra-config-install`, 0755 root:root, `content: ${infra_config_install_b64}` where both `inngest-host.tf` and `inngest-provision-rehearsal/rehearsal.tf` pass `base64encode(file("${path.module}/infra-config-install.sh"))` (the rehearsal renders the same template; an unsupplied key is a render-time FATAL, so both maps must carry it). Single source — the baked copy IS the repo copy; no drift duplicate. Root-invoked only; no sudoers entry (HARD-4).
3. **`/etc/soleur/cosign-trusted-root.json` baked identically** — `${cosign_trusted_root_b64}` var, `file()`-sourced from the committed `apps/web-platform/infra/cosign-trusted-root.json` (the ADR-087 trust anchor; staleness is already gated by `cosign-trusted-root-staleness.test.sh`).
4. **`inngest-config-refresh.service` + `.timer` as inline `write_files` payloads** — service: `Type=oneshot`, runs as root (`Environment=HOME=/root`), `TimeoutStartSec=300`, the sibling sandbox set (`NoNewPrivileges=yes`, `ProtectSystem=strict`, `PrivateTmp=true`), `SyslogIdentifier=inngest-config-refresh`, `ConditionPathExists=/etc/default/inngest-server` (skip-vs-fail — that file is a runcmd write), `EnvironmentFile=/etc/default/inngest-server`, `StateDirectory=inngest-config` (systemd creates `/var/lib/inngest-config` root:root — HARD-3), `ReadWritePaths=/root/.docker` (the `docker login` credential write; `/var/lib/docker` is the daemon's namespace, unaffected), `After=network-online.target docker.service`. ExecStart mirrors the flip's bounded form: `/usr/bin/doppler run --config ${DOPPLER_CONFIG} --only-secrets INNGEST_CONFIG_DIGEST --only-secrets DOPPLER_CONFIG --no-exit-on-missing-only-secrets -- /usr/local/bin/inngest-config-refresh.sh`. Timer: `OnBootSec=60s` + `OnUnitActiveSec=60s` + `Persistent=true` + the same `ConditionPathExists` — enabled via a runcmd `systemctl enable --now inngest-config-refresh.timer` line beside the siblings (60 s assumed; the Doppler read is the same class of poll the flip already runs at 30 s — decision D4).
5. **`/var/lib/inngest-config/applied.version` seeded to `0`** via `write_files` (0644 root:root) — the baked floor in the shared numbering space; first promotion must be version ≥1 (HARD-9 promotion gate is the producer's, not the host's).
6. **Refresh-set membership = the 5 dedicated-host carriers** (decision D3): `inngest-redis-bootstrap.sh`, `inngest-cutover-flip.sh`, `inngest-server-flip-guard.sh`, `cat-inngest-cutover-state.sh`, `inngest-luks-cutover.sh` — the repo files that install to `/usr/local/bin` on this host and whose edits currently cost a replace (the sibling's `inngest-redis-bootstrap.sh` case is exactly this). The 8 seeded web-host scripts move OUT with a comment — they are not dedicated-host dests at all (verified: absent from `cloud-init-inngest.yml`; delivered to web hosts by the webhook push, their real channel).
7. **`DEST_SPEC` + `FILE_MAP` + push payload widened by those 5 dests** — `infra-config-install.sh` `DEST_SPEC` gains `/usr/local/bin/{inngest-redis-bootstrap,inngest-cutover-flip,inngest-server-flip-guard,cat-inngest-cutover-state,inngest-luks-cutover}.sh` at `755 root:root`; `infra-config-apply.sh` `FILE_MAP` gains the matching `*_B64|dest|755|root:root` rows; `push-infra-config.sh` gains the five base64 payload fields; `infra-config-verify`/`cat-infra-config-state`/the status count move 15→20. The web-side delivery is inert (nothing on a web host invokes them) — the ADR-135 scope guard already accepts this widening.
8. **`vector.toml` Source-4 `+ "inngest-config-refresh"`** with the two-sided `journald-config.test.sh` pins (unit `SyslogIdentifier=` ↔ allowlist entry). Additive only — the tag is dead until the next image bake carries this `vector.toml`; the phone-home channel is the v1 authority.
9. **Docs:** dated ADR-135 amendment (zot-direct pull — GHCR read cred deleted by #8036; integrity stays digest-pinned, provenance stays cosign-verified; the bundle's zot mirror `continue-on-error` posture noted, drift comparator is the detector); runbook `inngest-config-refresh.md` updated (the bake lands the consumer; first-promotion procedure stays operator-gated); `inngest-server.md` §Bootstrap-image release cross-ref to the refresh channel for `*.sh` changes.

### Workstream B — #8781: pre-merge candidate build lane (option a)

10. **`check-inngest-bootstrap-build.yml`** — new workflow, `pull_request` trigger `paths:`-filtered to the carrier+pin set (mirroring `mint-inngest-bootstrap-tag.yml`'s path filter minus mint machinery, plus this workflow + its script): `apps/web-platform/infra/inngest*`, `apps/web-platform/infra/vector.*`, `apps/web-platform/infra/cat-inngest-*`, `.github/workflows/check-inngest-bootstrap-build.yml`, `.github/scripts/check-inngest-bootstrap-build.sh`, `.github/scripts/test/test-check-inngest-bootstrap-build.sh`. `permissions: contents: read` — no `packages: write`, no `id-token`, no environment. One job running `.github/scripts/check-inngest-bootstrap-build.sh`. Kept OUT of `build-inngest-bootstrap-image.yml` deliberately — that file's header invariant is "Triggered ONLY by workflow_dispatch" and its whole security commentary assumes it.
11. **`.github/scripts/check-inngest-bootstrap-build.sh`** — reproduces the inline Build step end-to-end, minus publication: read `inngest_cli_version`/`sha256` + `vector_version`/`sha256` from the `*.tf` pins (same greps), download the inngest-cli tarball and SHA256-verify (fail on mismatch), stage the 14 carriers, render the same Dockerfile heredoc, `docker build` with the `org.opencontainers.image.revision` label. **Never** `docker push`, never cosign, never crane, never the bump — a no-push build-only check. It exists as a script (not inline) precisely because `pull_request` checks out the PR's own tree where the script exists — the inverse of the dispatch path's constraint.
12. **Parity guard `.github/scripts/test/test-check-inngest-bootstrap-build.sh`** — normalized logic-parity drift guard (the `plan-review/lib` convention): extracts the `cp` carrier set + Dockerfile `COPY`/`ENV`/`ENTRYPOINT` lines + the sha256-verify block from BOTH the script and the workflow's inline Build step, normalizes whitespace/quoting, and asserts equality; asserts the check workflow carries no `docker push`/`cosign`/`crane`/`id-token`/`packages:` tokens; asserts the PR path filter covers every `cp` source (the mint suite already does this for its own list — cross-assert the shared subset).

### Workstream C — #6940: cutover follow-ups

13. **Item 1 — verify landed.** No code. Evidence: `inngest-registry-probe.sh` selects `triggers { type value }` and emits `functions[]`; `scripts/cutover-inngest.sh::zero_run_cron_ids` derives `registry_cron_ids − observed` and op=verify re-probes that set over `CUTOVER_DISCOVERY_LOOKBACK_S` (default 15897600 s ≈ 184 d) via a `function_ids`-scoped doublefire call — the exact ADR-146 design. Landed in `7f23ff853f` (PR #9698).
14. **Item 2 — map `CUTOVER_QUIESCE_PROBES` + ship the completeness guard.** Workflow env gains `CUTOVER_QUIESCE_PROBES: ${{ vars.CUTOVER_QUIESCE_PROBES }}` (optional repo var; empty ⇒ script default 3 — mapping it carries no dormant `exit 1`, unlike the baseline). `CUTOVER_REGISTRY_BASELINE` stays unmapped — AC-V4 is not green. The #6940 comment block in the workflow is updated to say so. The **completeness guard** lands in `cutover-inngest-workflow.test.sh`: derives every `CUTOVER_[A-Z_]+` dereference in `scripts/cutover-inngest.sh` via the issue's anchored grep `grep -oP '(?<![A-Za-z0-9_])CUTOVER_[A-Z_]+'` (the lookbehind is load-bearing — unanchored, `INNGEST_CUTOVER_FLIP`/`INNGEST_CUTOVER_QUIESCE` Doppler names would false-match), asserts each name is either mapped as `NAME:` in the workflow's step env or listed in a pinned `DEFERRED_CUTOVER_VARS` table that must carry an issue ref and a reason per entry (`CUTOVER_REGISTRY_BASELINE` → "#6940 item 2 — AC-V4 not green"), and makes the `$WF_YAML`/`$BODY_SH` targets env-overridable so "the guard fails against a stale main" is demonstrable in-suite.
15. **Item 3 — `page_size` plumbing.** New optional dispatch input `page_size` (string, default `""` = probe default) → step env `CUTOVER_PAGE_SIZE: ${{ inputs.page_size }}` → `scripts/cutover-inngest.sh` appends `&page_size=${CUTOVER_PAGE_SIZE}` to the doublefire URL when non-empty (integer-validated 1–1000; invalid ⇒ named `::error::` + skip, never a malformed URL) → `hooks.json.tmpl` `pass-environment-to-command` gains `{ "source": "url", "name": "page_size", "envname": "INNGEST_GQL_PAGE_SIZE" }` → `inngest-doublefire-probe.sh` validates `INNGEST_GQL_PAGE_SIZE` is an integer in `1..1000` before it reaches `--argjson first` (fail-closed FATAL otherwise). The hook-config change rides the normal infra-config push post-merge (`local.hooks_json` is in `deploy_pipeline_fix.triggers_replace`).
16. **AC6c — cross-file pin consistency.** `cloud-init-inngest-bootstrap.test.sh` gains a block asserting `grep -oE 'jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}'` across BOTH cloud-init files yields count==4 and distinct==1 — the partial-bump guard #6780 named as missing (AC6b binds to `cloud-init.yml` only; the dedicated host's ZIREF was unguarded for consistency).

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Push-based redelivery (extend the web webhook or an SSH path to the dedicated host) | ADR-135 Option C — opens an inbound/deploy-writable path on a deny-all-public sole scheduler; `hr-no-ssh-fallback-in-runbooks`; AP-002. The pull direction is the designed answer. |
| Bake the refresh engine into the `vinngest` image instead of cloud-init | Functionally equivalent (both land only via replace), but the image is a second release lane (mint → publish → bump → replace) vs one; cloud-init `write_files` is the established home for this host's inline payloads (`inngest-nftables.sh`, `inngest-luks-open.sh`). The engine must not be a bundle member either way (HARD-1). |
| GHCR-direct pull as ADR-135's v1 literally says | The credentialed GHCR read path is deleted on this host (#8036); re-baking a GHCR cred is a new isolated-Doppler secret the exact-set self-check would have to admit. Zot-direct uses the credential already baked for the bootstrap pull — strictly less surface for the same property. |
| Option (b) candidate tag namespace (publish lane) | A real capability but a second security surface: pushing unreviewed-bytes images to GHCR, a tag/ref namespace every guard must be taught to ignore, and — to actually *exercise* it — a rehearsal image-override through `inngest-provision-rehearsal` tf + plan-shape guard. Recorded `pending - assumed:` (D6); the immediate ask ("a candidate-build lane") is satisfied by the no-push check. |
| Map `CUTOVER_REGISTRY_BASELINE` now | Activates a dormant `exit 1` upstream of the 2.6 doublefire check while AC-V4 is red — the exact ordering the issue forbids ("Must land only AFTER AC-V4 is green"). |
| Sweep `CUTOVER_*` in an unanchored grep for the guard | `INNGEST_CUTOVER_FLIP`/`INNGEST_CUTOVER_QUIESCE` are Doppler secret names that must never be mapped — the issue specifies the anchored regex; unanchored is the false-positive it warns about. |

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** `cloud-init-inngest-bootstrap.test.sh`: AC6c block (count==4/distinct==1 across both files — should PASS immediately; write it last of the RED set or note it as a green-guard addition). `inngest-config-refresh.test.sh` (new): extraction of the baked script + unit/timer payloads; structural pins (root service, `--only-secrets` bound, `ConditionPathExists`, `SyslogIdentifier`, `StateDirectory`, timeout, engine-paths-not-in-DEST_SPEC/refresh-set); fixture-driven behavioral arms (noop-empty-pointer, noop-same-digest, happy-path pull→verify→apply→APPLIED, signature fail, rollback reject, sha mismatch, missing/corrupt `applied.version` → floor, partial-apply leaves version un-advanced). `cutover-inngest-workflow.test.sh`: the `CUTOVER_*` completeness guard + mapping pins + `page_size` plumbing pins + overridable targets. `test-check-inngest-bootstrap-build.sh` (new): parity + no-publish pins — expect RED until the lane exists. `inngest-doublefire-probe.test.sh`: `page_size` validation arms — RED until the bound lands.

**Phase 1 — Workstream A bake.** `cloud-init-inngest.yml` write_files: `inngest-config-refresh.sh`, `infra-config-install` (b64 var), `cosign-trusted-root.json` (b64 var), the two units, `applied.version` seed; runcmd `enable --now inngest-config-refresh.timer`; `inngest-host.tf` + `rehearsal.tf` templatefile maps (+2 vars each); `DEST_SPEC`/`FILE_MAP`/payload/count widening; `inngest-config-refresh-set.txt` membership → 5; `vector.toml` tag.

**Phase 2 — Workstream B lane.** New workflow + script + parity test; `infra-validation.yml` path-map comment entries for the new files.

**Phase 3 — Workstream C.** `cutover-inngest.yml` env mappings + comment refresh + `page_size` input; `cutover-inngest.sh` `CUTOVER_PAGE_SIZE` URL plumbing; `hooks.json.tmpl` pass-environment; `inngest-doublefire-probe.sh` `PAGE_SIZE` validation; suite rows.

**Phase 4 — Suites green + floors.** All touched suites re-run; floors moved by MEASURED count only; `inngest-userdata-budget.sh --json` re-measured (pre: stored 21,520 / headroom 11,248).

**Phase 5 — Docs.** ADR-135 dated amendment; runbook updates; `bash plugins/soleur/test/c4-count-parity.test.sh` check (no C4 change expected — no new actor/system/container: the channel reuses zot/GHCR/Doppler/Better Stack, all modeled).

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` — write_files payloads (refresh script, install helper b64, trusted root b64, both units, `applied.version`), `enable --now` line. ~+300 template lines.
- `apps/web-platform/infra/inngest-host.tf` — 2 templatefile vars.
- `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` — 2 templatefile vars.
- `apps/web-platform/infra/infra-config-install.sh` — DEST_SPEC +5.
- `apps/web-platform/infra/infra-config-apply.sh` — FILE_MAP +5.
- `apps/web-platform/infra/push-infra-config.sh` — payload +5 b64 fields.
- `apps/web-platform/infra/infra-config-verify.sh` / `cat-infra-config-state.sh` / `infra-config-gate.sh` — count/lockstep moves (exact deltas at implementation).
- `apps/web-platform/infra/inngest-config-refresh-set.txt` — membership → 5 dedicated carriers + rationale comment.
- `apps/web-platform/infra/vector.toml` — `inngest-config-refresh` Source-4 entry + comment.
- `apps/web-platform/infra/journald-config.test.sh` — two-sided tag pins.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6c block; write_files payload pins.
- `apps/web-platform/infra/inngest-host.test.sh` / `inngest.test.sh` / `cloud-init-inngest-provision-unit.test.sh` — structural pins for the new payloads/unit enablement; floor moves (measured).
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — completeness guard, mapping pins, page_size pins, overridable targets.
- `apps/web-platform/infra/inngest-doublefire-probe.test.sh` — `PAGE_SIZE` validation arms.
- `apps/web-platform/infra/inngest-doublefire-probe.sh` — integer/range validation before `--argjson first`.
- `apps/web-platform/infra/hooks.json.tmpl` — `page_size` pass-environment entry.
- `.github/workflows/cutover-inngest.yml` — `CUTOVER_QUIESCE_PROBES` + `CUTOVER_PAGE_SIZE` mappings, `page_size` input, updated #6940 comment.
- `scripts/cutover-inngest.sh` — `&page_size=` plumbing at both doublefire URL sites + `zero-run` site consistency.
- `.github/workflows/infra-validation.yml` — path-map comment entries for new/edited files.
- `knowledge-base/engineering/architecture/decisions/ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md` — dated amendment.
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` + `inngest-server.md` — channel-live/runbook updates.

## Files to Create

- `apps/web-platform/infra/inngest-config-refresh.test.sh` — the consumer suite (structural + fixture-driven behavioral; auto-registered by the glob per ADR-252 — no workflow edit needed for execution).
- `.github/workflows/check-inngest-bootstrap-build.yml` — the candidate build lane.
- `.github/scripts/check-inngest-bootstrap-build.sh` — the no-push build reproduction.
- `.github/scripts/test/test-check-inngest-bootstrap-build.sh` — the parity + no-publish guard.
- `knowledge-base/project/specs/feat-one-shot-6780-8781-6940-inngest-image-lifecycle/{decision-challenges.md,tasks.md}` — spec artifacts (this delivery).

Not edited, by design: `inngest-bootstrap.sh` (image entrypoint — not a refresh-set member, not re-pinnable mid-flight), the four `vinngest` pin sites (ADR-232 owns them; this PR does not release an image), `build-inngest-bootstrap-image.yml` (dispatch-only invariant preserved), `mint-inngest-bootstrap-tag.yml`, `bump-inngest-bootstrap-pin.sh`, `inngest-config-bundle-pack.sh`/`build-inngest-config-bundle.yml`/`inngest-config-drift-compare.sh` (producer complete), `inngest-config-digest.tf` (count-gated; first promotion is a deferred operator apply), `cloud-init-git-data.yml`/`git-data-bootstrap.sh` (sibling scope), and — beyond minimal conflict-surfacing edits — the pre-cutover LUKS resolver arms (PARKED PR #10081's scope).

## Open Code-Review Overlap

Queried open `code-review` issues (60) on 2026-10-13: **#9705** covers `betterstack-logs-alerts.tf`/`uptime-alerts.tf`/`heartbeat-manifest.ts`/`model.c4`/`inngest-server-probe-heartbeat.test.sh` — none in this plan's edit set. Open PRs: **#10255** (vector journald partition) touches `vector.toml`/`journald-config.test.sh` — textual conflict surface, whoever merges second rebases; **#10081 PARKED** touches `cloud-init-inngest.yml` — do not merge/rebase onto it; keep this plan's edits in the write_files/units regions it does not strip.

## User-Brand Impact

**If this lands broken, the user experiences:** the sole Inngest scheduler running stale host scripts — every statutory-deadline and notification cron fires from it — so a fix the operator believes shipped silently did not (the #6594 latched-false-green class); or, at the worst edge, a verification hole lets a forged bundle run as root on the host that drives every user-facing cron.
**If this leaks/is subverted, the user's [data/workflow/money] is exposed via:** an unsigned/forged/rolled-back bundle executing as root on the sole scheduler — mitigated structurally: version read only from cosign-verified bytes, per-file sha256 manifest, monotonic floor, reviewer-gated signing environment, `--only-secrets`-scoped unit env.
- **Brand-survival threshold:** `aggregate pattern` — the blast radius of a bad channel is fleet-wide scheduler integrity/availability, not a single user record; and every host-side gate fails closed (a broken consumer leaves last-known-good running and emits a named marker). The archived 2026-07-22 plan chose `single-user incident` + CPO signoff for the producer half; the divergence is recorded in decision-challenges (D8, taste).

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INFRA_PULL_APPLIED version=<N> sha256=<digest> verify=ok (per applied promotion); SOLEUR_INFRA_PULL_FLOOR version=floor on the seeded-floor boot; throttled noop rows as the 15-min liveness witness"
  cadence: "timer every 60 s; noop/floor emits throttled to 300 s; APPLIED/VERIFY_FAIL only on transitions"
  alert_target: "Better Stack soleur-inngest source — v1 via inngest-boot-phone-home.sh direct POST (works on the current pinned image); journald tag inngest-config-refresh -> Vector Source 4 goes live on the next image bake (vector.toml shipped in this PR); off-box drift comparator inngest-config-drift.yml alarms applied!=pointer (dormant until first promotion)"
  configured_in: "apps/web-platform/infra/cloud-init-inngest.yml (units + script), apps/web-platform/infra/vector.toml, .github/workflows/inngest-config-drift.yml"
error_reporting:
  destination: "Better Stack via logger -t inngest-config-refresh + inngest-boot-phone-home.sh; /var/lib/inngest-config/applied.json is the on-host state slot"
  fail_loud: "every gate is a named VERIFY_FAIL (signature/sha/rollback/pull/manifest) — a failed decision is never a silent no-op; unit failure surfaces as SyslogIdentifier'd stderr + nonzero exit retried next tick"
failure_modes:
  - mode: "promoted pointer, dead timer"
    detection: "drift comparator: pointer non-empty + no APPLIED marker in window -> DIVERGED no-applied-marker"
    alert_route: "inngest-config-drift.yml executor exit 2 -> alarm (post N-window debounce, wired at channel-live)"
  - mode: "bundle signed by the wrong workflow / forged"
    detection: "cosign verify-blob rc!=0 (identity regexp + OIDC issuer + trusted root) -> VERIFY_FAIL reason=signature"
    alert_route: "Better Stack marker row; host keeps last-known-good"
  - mode: "version rollback or pointer-below-floor"
    detection: "manifest VERSION <= applied.version -> VERIFY_FAIL reason=rollback-or-replay (rejection-as-signal, HARD-9)"
    alert_route: "Better Stack marker row"
  - mode: "zot does not serve the promoted digest (mirror degraded)"
    detection: "bounded docker pull fails -> VERIFY_FAIL reason=pull + drift comparator applied!=pointer"
    alert_route: "Better Stack marker + comparator alarm"
  - mode: "engine drift (refresh script/units/install helper edited out)"
    detection: "structural pins (presence, mode, ExecStart shape, enable line) + HARD-1 absence assertions in CI"
    alert_route: "CI infra-validation reds the PR"
  - mode: "CUTOVER_* env knob added unmapped (the #6617 dead-remediation class)"
    detection: "completeness guard derives script derefs anchored and diffs against workflow env + deferred list"
    alert_route: "CI suite red on the PR adding the knob"
logs:
  where: "journald tag inngest-config-refresh -> Vector Source 4 -> Better Stack soleur-inngest (post-next-bake); phone-home rows queryable today via betterstack-query.sh --grep SOLEUR_INFRA_PULL"
  retention: "Better Stack source retention (inherited); applied.json + applied.version persist on the root disk (StateDirectory) — intentionally NOT on /mnt/data (the LUKS volume): the channel must not stall on a mount"
discoverability_test:
  command: grep SOLEUR_INFRA_PULL_APPLIED apps/web-platform/infra/cloud-init-inngest.yml
  expected_output: SOLEUR_INFRA_PULL_APPLIED
```

## Encryption Posture

```yaml
at_rest:
  - store: "/var/lib/inngest-config/{applied.version,applied.json} (dedicated host root disk)"
    mechanism: none — integrity metadata only (monotonic version + applied digest); holds no secrets, no credentials, no user data
    evidence: "written by the root refresh service after set-atomic install; root:root via StateDirectory=inngest-config"
    defends_against: "deploy-user tampering of the monotonic floor (root:root ownership)"
    does_not_defend: "root compromise of the host (the verifier itself runs as root — the trust anchor is the baked cosign trusted root, not this file); an attacker who can write applied.version can only *lower* the floor — re-driving a re-pull + re-verify, which is why every transition still verifies"
    disclosed_as: "ADR-135 + this plan (internal)"
    live_verification: "the APPLIED marker's sha256= field is checked against the promoted pointer by the off-box comparator"
in_transit:
  - path: "host -> zot (private net, plain HTTP): bundle OCI pull @sha256"
    protection: "digest-pinning (integrity) + cosign verify-blob offline before any byte executes (provenance) — the established ADR-096 posture; plain HTTP acceptable because the pin+signature, not TLS, carry the guarantee"
  - path: "host -> api.doppler.com (TLS): pointer read via scoped --only-secrets doppler run"
    protection: "existing channel; --only-secrets INNGEST_CONFIG_DIGEST bounds the injected env to the pointer"
  - path: "host -> gcr.io (TLS): anonymous pull of the pinned cosign verifier image"
    protection: "image digest pin is the trust anchor (not the registry); anonymous read is the ci-deploy.sh precedent; ADR-052 blocks Fulcio/Rekor egress and this path touches neither"
```

## Guard Contract

### Guard 1 — The refresh channel verifies, then applies atomically; nothing unverified or stale executes

**Property.** Every tick ends in one of: throttled noop (no pointer / pointer == applied), a named `VERIFY_FAIL` (pull/signature/sha/rollback), or a complete verified apply ending in `APPLIED` + advanced `applied.version`. No path applies bytes that did not pass `cosign verify-blob` + `sha256sum -c` + the monotonic gate, and no path leaves a torn mixed-version set latched.

**Assembly.** The single `inngest-config-refresh.sh` body (every code path flows through it) + the unit's `--only-secrets` env bound + `applied.version` written only after the last `infra-config-install` rc==0 (chokepoints: the script itself and the install loop's tail).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `cosign verify-blob` step removed or its rc ignored (`\|\| true` on a decision) | RED: unsigned/forged bundle arm reports VERIFY_FAIL, never applies |
| 2 | `VERSION` read from the OCI tag/pointer instead of the verified manifest | RED: forged-high-version fixture rejected — version read pre-verify is the HARD-2 defect |
| 3 | `applied.version` advanced after the FIRST install instead of the last | RED: mid-set-failure fixture latches a torn set; version must not advance |
| 4 | pointer-equal-to-applied still pulls/applies | RED: noop arm asserts zero docker/pull calls |
| 5 | monotonic gate accepts `VERSION == applied` or `<` | RED: rollback/replay fixture rejected with reason=rollback-or-replay |
| 6 | missing/non-integer `applied.version` parses to 0 *silently* (no floor marker) | RED: fixture asserts `SOLEUR_INFRA_PULL_FLOOR version=floor` emitted |
| 7 | `--only-secrets` bound dropped from the unit's `doppler run` | RED: structural pin asserts the flag list contains exactly the pointer + DOPPLER_CONFIG |
| 8 | engine path added to refresh-set or `DEST_SPEC` | RED: HARD-1 absence assertions fail |
| 9 | `--fixture-seams` honoured without the argv flag | RED: env-injected seam fixture must be inert |

**Harness rows.** (a) Suite-side RED driver: a stub `cosign`/docker pair where verify returns 1 — any arm that applies is the tell. (b) Must-PASS inputs: valid bundle at version floor+1 on a fresh `applied.version=0`; a second identical promotion (pure noop); a floor-missing state file. (c) Floors: `executed >= <measured>` — set after implementation, never estimated.

**Anchor.** The suite extracts the script from `cloud-init-inngest.yml` (the render proxy — what actually boots); the off-box anchor is the drift comparator, whose `applied != pointer` verdict does not depend on host honesty for its non-adversarial paths (all fail-closed).

### Guard 2 — Every `CUTOVER_*` name the cutover script dereferences is env-mapped or pinned-deferred

**Property.** `grep -oP '(?<![A-Za-z0-9_])CUTOVER_[A-Z_]+' scripts/cutover-inngest.sh` yields a set; every member either appears as `NAME:` in `cutover-inngest.yml`'s step env, or is listed in the suite's named `DEFERRED_CUTOVER_VARS` table with an issue ref + reason. No unmapped name ships; no Doppler `INNGEST_CUTOVER_*` name is ever demanded by the guard.

**Assembly.** The new block in `cutover-inngest-workflow.test.sh` (chokepoint: the derivation regex + the deferred table; both in one place).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | new `CUTOVER_X` deref added to the script with no env mapping and no deferred entry | RED: guard lists it as unmapped |
| 2 | derivation unanchored to `CUTOVER_[A-Z_]+` (lookbehind dropped) | RED: fixture workflow still passes but the Doppler-name false-positive arm fails — the guard must not demand `INNGEST_CUTOVER_FLIP` |
| 3 | deferred-list entry without an issue ref/reason | RED: shape check on the table rows |
| 4 | env mapping removed for a mapped name (`CUTOVER_QUIESCE_PROBES`) | RED: guard lists it unmapped |
| 5 | deferred entry silently mapped too (double-listed) | RED: a name may not be both mapped and deferred |

**Harness rows.** `$WF_YAML`/`$BODY_SH` env-overridable: a fixture pair with a stale env block demonstrates "fails against main" (the issue's demonstrability requirement).

**Anchor.** The workflow+script pair is reconstructed into the suite's `$WF` view exactly as today; the guard reads the same two files the ops dispatch reads.

### Guard 3 — The candidate lane cannot publish, sign, or drift from the real build

**Property.** `check-inngest-bootstrap-build.yml` + its script contain no `docker push`, `cosign`, `crane`, `id-token`, `packages:` permission, or `environment:` — the lane can only verify a build, never publish. Its carrier set, Dockerfile body, and sha256-verify are byte-equivalent (normalized) to the publish workflow's inline Build step.

**Assembly.** The parity suite (chokepoint: the normalized extraction over BOTH files; a one-sided edit fails it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `docker push` added to the check script | RED: forbidden-token scan |
| 2 | `packages: write` or `id-token` added to the check workflow | RED: permission pins |
| 3 | a carrier `cp` added to the real Build step but not the check script (one-sided drift) | RED: normalized set diff |
| 4 | the sha256-verify weakened in the check script (e.g. `|| true`) | RED: verify-block parity + a forged-sha fixture exits nonzero |
| 5 | paths filter drops a `cp` source file | RED: paths-coverage assertion over the real cp list |

**Anchor.** The check runs on `pull_request` for every carrier-touching PR — its own green is the external anchor.

## Infrastructure (IaC)

### Terraform changes

Two `templatefile` var-map additions (`infra_config_install_b64`, `cosign_trusted_root_b64`) in `inngest-host.tf` and `inngest-provision-rehearsal/rehearsal.tf`. No new resource, variable, secret, or provider. `inngest-config-digest.tf` is untouched (first promotion is a deferred operator apply; #9060 owns the route).

### Apply path

Code-only at merge. The consumer bake reaches the host on the next sanctioned `inngest-host-replace` dispatch (`user_data` is ForceNew) — the bootstrap paradox: the channel installs through the replace it eliminates, once. The tf var-map edits re-render `user_data` but are inert until that replace. The FILE_MAP/push widening reaches web hosts on the next normal apply push (harmless dead files at `/usr/local/bin`).

### Host fan-out

No `terraform_data` SSH provisioner. The rehearsal root renders the same template — the timer runs there pointing at the scratch config (no pointer → throttled noop), which is also the free Phase-0 arm for the refresh code path.

### Distinctness / drift safeguards

`inngest-userdata-budget.sh` re-measures the stored payload on every infra PR (pre-change headroom 11,248 B). The b64-var mechanism means `infra-config-install.sh` and `cosign-trusted-root.json` have exactly one source — the drift class is absent by construction; the parity suite covers the check-lane↔publish-build drift class.

### Vendor-tier reality check

zot serves `jikig-ai/soleur-inngest-config` when `build-inngest-config-bundle.yml`'s mirror step succeeds (it is `continue-on-error` — a degraded mirror leaves a promoted pointer unpullable, caught by the drift comparator + VERIFY_FAIL pull arm; flipping it to required is a named follow-up). gcr.io anonymous pull of the pinned cosign image is the ci-deploy.sh precedent; the host's egress is unrestricted on the private-net outbound path (api.doppler.com proven at every boot).

## Architecture Decision (ADR/C4)

### ADR

Dated amendment to **ADR-135** (in-PR): (a) the host pull is zot-direct via the baked `/etc/default/soleur-zot-read` credential — the GHCR-direct v1 premise was deleted by #8036's cred removal; integrity stays digest-pinned, provenance stays cosign `verify-blob` offline, no new isolated-Doppler secret; (b) the marker channel's v1 authority is `inngest-boot-phone-home.sh`, with the journald tag going live on the next image bake; (c) refresh-set v1 membership = the five dedicated-host carriers, scripts-only.

### C4 views

No C4 change: no new human actors, no new external systems (zot, GHCR, Doppler, Better Stack, cosign/Sigstore already modeled), no new containers — the refresh unit runs inside the already-modeled `inngest` host. Re-check `model.c4`/`views.c4`/`spec.c4` and run `bash plugins/soleur/test/c4-count-parity.test.sh` at implementation.

### Sequencing

The amendment describes the target state and ships in this PR; ADR-135's `adopting` status stands until the first `SOLEUR_INFRA_PULL_APPLIED` reaches Better Stack off-box.

## Downtime & Cutover

- **Offline-inducing operations:** only the post-merge, separately authorized `inngest-host-replace` dispatch — the existing sanctioned path that this channel exists to make rare. This PR changes code/tests/docs only.
- **Surface affected:** the dedicated Inngest scheduler (sole prod cron substrate). The LUKS AOF volume survives the replace.
- **Zero-downtime evaluation:** the channel IS the zero-downtime mechanism; its one-time install piggybacks the next sanctioned replace and adds no new window.
<!-- lint-infra-ignore start -->
- **Residual downtime acceptance:** none requested; each dispatch is an operator authorization, not a plan step.
<!-- lint-infra-ignore end -->

## Domain Review

**Domains relevant:** none

No cross-domain implications among the eight business domains — internal CI/infra machinery. Technical forks are `pending - assumed:` rows in `decision-challenges.md`. Product/UX gate: no UI-surface file. GDPR gate: no schema/auth/API-route/.sql surface; the refresh-set is operational shell scripts, no regulated data path.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | #6780: "A change to a host script under apps/web-platform/infra/ can reach the dedicated host without apply_target=inngest-host-replace" | Workstream A §1–§9 | mapped (capability lands at next replace; channel-live is a deferred operator gate) |
| 2 | #6780: "The channel is no-SSH" / "Delivery is verifiable off-box (a marker reaching Better Stack)" | A §1 ExecStart shape; A §1 emit path + Observability | mapped |
| 3 | #8781: "(a) A no-push docker build of the bootstrap image on PRs that change baked carriers (a build-only check)" | Workstream B §10–§12 | mapped |
| 4 | #6940 item 2: "Map CUTOVER_REGISTRY_BASELINE + CUTOVER_QUIESCE_PROBES into the step env, plus a completeness guard … anchored grep -oP '(?<![A-Za-z0-9_])CUTOVER_[A-Z_]+' … make the test's $WF target overridable" | Workstream C §14 | partially mapped — BASELINE stays deferred (issue's own AC-V4 precondition, still unmet) |
| 5 | #6940 item 3: "Measure INNGEST_GQL_PAGE_SIZE=500 … needs a new hook parameter threaded through hooks.json.tmpl plus a host hook-config redeploy" | Workstream C §15 + Deferred | mapped (plumbing ships; measurement dispatch deferred) |
| 6 | #6940 item 1: "Registry-sourced missed-tick discovery" | Workstream C §13 | mapped — already landed in #9698 (verify-only) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Host consumer bake (script, units, trusted root, floor, install helper) | "A pull-based config refresh on the host (timer + signed fetch), avoiding an inbound channel into a deny-all-public host" | asked |
| zot-direct pull (amends ADR-135 v1) | — | inferred — justification: #8036 deleted the host's GHCR read cred; ADR-135's premise is stale and zot is the only pull path |
| Candidate build lane (option a) | "(a) A no-push docker build of the bootstrap image on PRs that change baked carriers" | asked |
| Completeness guard + QUIESCE_PROBES mapping + page_size plumbing | issue checklists, quoted in Ask Mapping 4–5 | asked |
| AC6c cross-file pin consistency | "four pin sites must move together … and the cross-file assertion that would catch a partial bump does not yet exist — the existing AC6b binds to cloud-init.yml only" | inferred — justification: the issue names the missing guard explicitly; it is cheap and inside the issue's spirit |
| Refresh-set membership = 5 dedicated carriers (dropping the web-host seed-8) | — | inferred — justification: the seed members are not dedicated-host dests (verified absent from the template); the channel exists to deliver dedicated-host scripts — D3 decision row |
| `inngest-config-refresh` vector tag | — | inferred — justification: observability-as-plan-quality gate; additive dead-tag-until-bake with phone-home as the live channel |
| ADR-135 amendment + runbook updates | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — a stale ADR premise + a runbook that says GHCR-direct would mislead the next operator |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `.github`, `knowledge-base`
- Planned files: ~24 edited + 5 created | Estimated changed lines: ~1,400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the brief fixes this PR to cover all three issues; the three workstreams share the theme (image lifecycle) but are independently reviewable within one diff.

## Acceptance Criteria

- [ ] `cloud-init-inngest.yml` `write_files` carries `/usr/local/bin/inngest-config-refresh.sh` (0755), `/usr/local/bin/infra-config-install` (b64, 0755), `/etc/soleur/cosign-trusted-root.json` (b64, 0644), `/etc/systemd/system/inngest-config-refresh.{service,timer}`, and `/var/lib/inngest-config/applied.version` (0644 root:root, content `0`); `grep -c 'inngest-config-refresh' apps/web-platform/infra/cloud-init-inngest.yml` >= 6 and a runcmd `systemctl enable --now inngest-config-refresh.timer` line exists.
- [ ] `inngest-host.tf` and `inngest-provision-rehearsal/rehearsal.tf` BOTH pass `infra_config_install_b64` and `cosign_trusted_root_b64` — `grep -c 'infra_config_install_b64\|cosign_trusted_root_b64' <each>` == 2 per file.
- [ ] The refresh service's `doppler run` carries `--only-secrets INNGEST_CONFIG_DIGEST` and no bare `doppler run` without `--only-secrets` in the unit; `SyslogIdentifier=inngest-config-refresh`; `ConditionPathExists=/etc/default/inngest-server`; `StateDirectory=inngest-config`.
- [ ] `DEST_SPEC`/`FILE_MAP`/push payload carry the five dedicated dests; `grep -c '_B64|/usr/local/bin/inngest-' infra-config-apply.sh` reflects the +5; the install helper's allowlist rejects a dest outside it (existing rc=3 contract).
- [ ] `inngest-config-refresh-set.txt` lists exactly the five dedicated carriers and no engine path (`inngest-config-refresh`, `infra-config-install`, `cosign-trusted-root`, `applied.version`, the units) appears in it or in `DEST_SPEC` (HARD-1 pin).
- [ ] `vector.toml` Source-4 include list contains `"inngest-config-refresh"` and `journald-config.test.sh` asserts it on both sides.
- [ ] `bash apps/web-platform/infra/inngest-config-refresh.test.sh` exits 0 at its measured floor, including the fail-closed arms (unsigned, wrong-identity, sha mismatch, rollback, missing/corrupt `applied.version`, partial apply).
- [ ] `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` exits 0 incl. AC6c (4 refs, 1 distinct tag@digest across both files).
- [ ] `bash apps/web-platform/infra/inngest-host.test.sh`, `inngest.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `journald-config.test.sh`, `infra-config-install.test.sh`, `infra-config-apply.test.sh`, `infra-config-verify.test.sh`, `ci-deploy.test.sh`, `inngest-config-bundle-pack.test.sh` all exit 0 at measured floors.
- [ ] `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` reports `stored` <= 32,768 (pre-change stored 21,520 / headroom 11,248 — post-change headroom recorded in the PR).
- [ ] `check-inngest-bootstrap-build.yml` exists with `pull_request` paths filter covering every `cp` carrier; `bash .github/scripts/test/test-check-inngest-bootstrap-build.sh` exits 0 (parity + no-publish pins); the check script contains no `docker push`/`cosign`/`crane` tokens.
- [ ] `cutover-inngest.yml` env maps `CUTOVER_QUIESCE_PROBES: ${{ vars.CUTOVER_QUIESCE_PROBES }}` and `CUTOVER_PAGE_SIZE: ${{ inputs.page_size }}`; `CUTOVER_REGISTRY_BASELINE` remains absent from the env block (deferred-list pinned); `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0 incl. the anchored completeness guard with overridable targets.
- [ ] `hooks.json.tmpl` carries the `page_size` → `INNGEST_GQL_PAGE_SIZE` pass-environment entry; `inngest-doublefire-probe.sh` rejects a non-integer or out-of-range `PAGE_SIZE` fail-closed; `bash apps/web-platform/infra/inngest-doublefire-probe.test.sh` exits 0.
- [ ] ADR-135 carries the dated zot-pull amendment; `inngest-config-refresh.md` updated; `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] `git diff --name-only origin/main...HEAD` contains neither `cloud-init-git-data.yml` nor `git-data-bootstrap.sh`.
<!-- lint-infra-ignore start -->
- [ ] PR body's FIRST line answers "does merging this mutate production?" (`no — user_data is ForceNew on the dedicated host and the bundle promotion path is operator-gated; inert until the next sanctioned inngest-host-replace + a promoted pointer`), says `Ref #6780` `Ref #6940` `Closes #8781` (the Closes is contingent on the D6 ruling that option (a) satisfies the ask — drop to `Ref #8781` if (b) is ruled required), and lists unrun operator steps: `inngest-host-replace`, first bundle promotion (`build-inngest-config-bundle` dispatch + TF_VAR + targeted apply + floor 5→6), drift-executor secret wiring.
<!-- lint-infra-ignore end -->

## Test Scenarios

- Given a promoted pointer whose digest differs from `applied.json`, when the refresh service fires, then it pulls the bundle from zot, verifies signature + manifest sha + monotonic version, installs every member via `infra-config-install`, advances `applied.version`, writes `applied.json`, and emits `SOLEUR_INFRA_PULL_APPLIED` via phone-home + logger. (`inngest-config-refresh.test.sh`, fixture-driven)
- Given a pointer naming a bundle signed by a workflow other than `build-inngest-config-bundle.yml@refs/heads/main`, when the service fires, then `verify-blob` fails and the emit is `VERIFY_FAIL reason=signature` with no file installed. (fixture)
- Given a bundle whose manifest `VERSION` is ≤ `applied.version`, when the service fires, then `VERIFY_FAIL reason=rollback-or-replay` — never a silent no-op. (fixture)
- Given a missing or non-integer `applied.version`, when the service fires, then the floor resolves to `0`, `SOLEUR_INFRA_PULL_FLOOR version=floor` is emitted, and a version-1 bundle applies. (fixture)
- Given a mid-set install failure (file 3 of 5), when the tick ends, then `applied.version` is unchanged and `applied.json` records the failure — the next tick re-drives the whole pull→verify→apply. (fixture)
- Given no `INNGEST_CONFIG_DIGEST` in the isolated config (pre-promotion), when the timer fires, then the unit skips cleanly / the script emits a throttled noop and exits 0 — cadence under 15 min preserved. (fixture + structural)
- Given `scripts/cutover-inngest.sh` gains a `CUTOVER_FOO` deref with no env mapping, when the suite runs, then the completeness guard reds naming it; given a stale fixture workflow, the overridable `$WF` demonstrates the same. (`cutover-inngest-workflow.test.sh`)
- Given `INNGEST_CUTOVER_FLIP` present in the script's dereference neighbourhood, when the guard derives names, then it is NOT required to be mapped (anchored lookbehind). (guard fixture)
- Given a PR touching `inngest-redis-bootstrap.sh`, when `check-inngest-bootstrap-build.yml` runs, then the image builds (sha-verified cli + staged carriers) and nothing is pushed/signed/bumped. (the lane itself)
- Given `page_size=500` dispatched on `op=doublefire-probe`, when the workflow builds the probe URL, then `&page_size=500` reaches the hook, the env var reaches the probe, and `first:` is 500; given `page_size=abc` or `0`, the probe fails closed and the workflow-side validation skips the param. (workflow + probe suites)
- Given `cloud-init-inngest.yml`'s ZIREF is bumped while IREF is not (partial bump), when the bootstrap suite runs, then AC6c reds on distinct==2. (structural)

## Dependencies & Risks

- **PARKED PR #10081** strips pre-cutover/plaintext resolver arms inside `cloud-init-inngest.yml`. Mitigation: this plan's edits sit in write_files/units/runcmd regions it does not strip; whichever merges second rebases; never merge or rebase onto it.
- **PR #10255** partitions vector journald admission — touches `vector.toml`/`journald-config.test.sh`. The new tag is a one-line include + assertion block; expect a small conflict.
- **userdata budget.** Headroom 11,248 B pre-change; the bake adds ~2 files (install helper ~12 KB raw, trusted root ~6.8 KB) + the refresh script + units. `inngest_rationale_strip` removes `#` prose pre-gzip — keep rationale comments OUT of the baked script's payload lines and in the template's `#` comment blocks, where the strip removes them for free. Re-measure (AC); if over cap, the fallback is trimming payload prose / moving the install helper to a runcmd `install` of a base64 literal (same bytes, no write_files overhead).
- **The channel cannot be exercised before the replace it rides** (bootstrap paradox) — the fixture suite is the behavioral authority pre-replace; the rehearsal host is the free end-to-end arm post-merge (optional paid dispatch, recorded not required).
- **`docker run` of the cosign image needs a one-time gcr.io pull on the host** — anonymous read, pinned digest, cached thereafter; if gcr.io egress ever proves blocked on this host, the fallback is mirroring the pinned cosign image into zot (a producer-side crane-copy — recorded follow-up, not blocking: the Phase-0 live probe answers it).
- **Bundle zot mirror is `continue-on-error`** — a degraded mirror + promoted pointer = unpullable bundle → VERIFY_FAIL pull + drift comparator DIVERGED. The comparator is the designed detector; flipping the mirror to required is a named follow-up.
- **apply ordering on first promotion** — `TF_VAR_inngest_config_digest` + targeted apply + the 5→6 floor bump are one operator window (the `.tf` file's own DEC-FLOOR note pins it); a partial application bricks nothing today because the regex already admits the name.
- **The seeded refresh-set's web-host members are not dedicated dests** — this plan corrects membership to the five dedicated carriers (D3); if a ruling keeps the seed-8, the only cost is dead files at `/usr/local/bin` on the dedicated host.
- **inngest-config-refresh.sh is a NEW root script on the sole scheduler** — the verify-then-apply order, `--only-secrets` bound, `--fixture-seams` argv gate, and fail-closed arms exist precisely for this; the Guard 1 matrix mutation-tests them.

## Sharp Edges

- The baked refresh script lives INSIDE `cloud-init-inngest.yml` — terraform's templatefile unescape is EXACTLY two transforms (`$${`→`${`, `%%{`→`%{`); write a bare `$` everywhere except where a brace follows (the #6894 syntax-error incident). Payload `#` comment lines are stripped pre-gzip by `inngest_rationale_strip` — put rationale there, not in `echo` payload.
- `--only-secrets` flags sit AFTER `--config ${DOPPLER_CONFIG}` and BEFORE `--` (doppler flags, not script argv); `--no-exit-on-missing-only-secrets` is load-bearing — the pointer is legitimately absent pre-promotion.
- A new `.test.sh` must never emit a bare `<<`/`<<<` token outside a real heredoc (assemble via a var) — the guard-vacuity detector treats it as a phantom span; keep tail floors outside heredoc-blanked spans, self-exiting with printf sentinel + `exit 1`; arm-level `if` lines must not carry the counter words `pass`/`fail`/`executed`/`cases` beside `-lt`/`-le`/`-ge`.
- Suite floors (`executed >=`) move by MEASURED count after arms land — never by estimate.
- `applied.version` is root-only and `/var/lib/inngest-config` is NOT `/var/lib/inngest` (the deploy-writable dir is the wrong root — HARD-3); `StateDirectory=` creates it for the root unit.
- The `page_size` param must be validated twice (workflow-side when building the URL, probe-side before `--argjson first`) — a query param is untrusted input crossing into a GraphQL variable.
- `CUTOVER_REGISTRY_BASELINE` is deliberately NOT mapped: the completeness guard's deferred list is load-bearing documentation, not a shortcut — do not "fix" the deferred entry by mapping it before AC-V4 greens.
- The check-lane script is a deliberate COPY of the inline Build step (the dispatch path cannot source a script from a tag tree); the parity guard is what makes the copy safe — do not inline the lane's logic back into the publish workflow or delete the parity suite.
- `enable --now` on the timer is the sibling convention; `ConditionPathExists=/etc/default/inngest-server` on BOTH unit and timer is the skip-vs-fail pair (#9962) — missing the timer's condition arms a 60 s tick on a half-provisioned host.
- The phone-home emit path uses the SAME bearer-stdin curl shape as `inngest-boot-phone-home.sh` — never argv a token; the script refuses xtrace with the token bound (#7797 pattern).

## Deferred

<!-- lint-infra-ignore start -->
- **`inngest-host-replace` dispatch (operator).** The consumer bake is inert until a sanctioned replace carries the rendered `user_data`. Not run from this branch; listed in the PR body.
- **First bundle promotion (operator window).** `build-inngest-config-bundle.yml -f version=1` dispatch (reviewer-gated), then `TF_VAR_inngest_config_digest=<sha256:…>` + targeted apply of `doppler_secret.inngest_config_digest` + the isolation floor bump 5→6 (in the SAME change — the `.tf` DEC-FLOOR note), then confirm `SOLEUR_INFRA_PULL_APPLIED` off-box. The apply route itself is #9060's scope.
- **Drift-executor go-live wiring (operator).** `INNGEST_CONFIG_DIGEST_READONLY` repo secret (isolated read token — operator mint), `cron-inngest-config-drift` recurring trigger, the Sentry-Crons monitor + N-window debounce, and the Better Stack absence-heartbeat monitor — all meaningful only post-promotion.
- **#6940 item 2 remainder (operator/AC-V4-gated).** `CUTOVER_REGISTRY_BASELINE` mapping lands only after a green op=verify (AC-V4); the deferred-list entry carries the reason so the follow-up cannot get it wrong.
- **#6940 item 3 remainder (operator).** The live `PAGE_SIZE=500` measurement — dispatch `op=doublefire-probe` with `page_size=500` and compare s/page against the 4.2 s/page anchor (run 30121678305); plumbing ships in this PR, the dispatch does not.
- **#8781 option (b) — candidate publish lane (decision fork, D6).** A `candidate-*` OCI tag namespace + publish without the ADR-232 bump/AC6 guard + a rehearsal image-override exercise path. Sketched in decision-challenges; build only if the ruling requires exercisability beyond a build check.
- **zot copy of the pinned cosign verifier image (optional follow-up).** Only if the Phase-0 probe shows gcr.io egress blocked on the dedicated host.
- **Load-bearing bundle mirror (optional follow-up).** Flip `continue-on-error` on `build-inngest-config-bundle.yml`'s zot mirror once the channel is live, so a promoted pointer can never name a digest zot lacks.
<!-- lint-infra-ignore end -->

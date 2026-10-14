# Tasks — deny ghcr.io on the web hosts (#9169)

Plan: `knowledge-base/project/plans/2026-09-30-infra-deny-ghcr-on-web-hosts-plan.md` (deepened
2026-09-30). Follow-up scoped out: #9275 (bridge containers via GitHub CIDRs; `docker.pkg.github.com`).

## Phase 0 — Setup and RED tests

- [x] 0.1 Bump `BASELINE_DECLARED_PROBES` 36 → 37 in
      `plugins/soleur/test/preflight-discoverability-test.test.ts` with the PLACEMENT / TRUTH /
      NO SUBSTITUTE comment for this plan (the plan commit already moved the count).
- [x] 0.2 Measure the web cloud-init gzip render with the deny inserted (scratch copy) against
      `WEB_GZIP_BUDGET` in `plugins/soleur/test/cloud-init-user-data-size.test.ts`; record the delta.
- [x] 0.3 Write `apps/web-platform/infra/web-ghcr-deny.test.sh` (Guard 2) RED — parse, never scan:
  - [x] 0.3.1 Render `cloud-init.yml` and `cloud-init-registry.yml` via `terraform console` (the
        `cloud-init-web-zot-seed.test.sh` render block); skip locally / FAIL under `CI` without
        terraform; `yaml.safe_load` the runcmd lists.
  - [x] 0.3.2 Read copy B by evaluating `local.ghcr_deny_sh` with `terraform console`; assert
        whole-entry parity runcmd[1] (web) == copy B == copy R (registry entry).
  - [x] 0.3.3 Ordering: runcmd[0] contains `trap on_err EXIT`, runcmd[1] is the deny.
  - [x] 0.3.4 Execute copy B once under `bash` with `set -e` against temp files, after asserting no
        literal `/etc/hosts` remains in the substituted script.
  - [x] 0.3.5 Classifier agreement with a per-name `getent` shim: sinkhole only; routable IPv4;
        mixed; IPv6 `2606:50c0:8000::154`; unresolvable; ghcr sinkholed + pkg-containers routable
        (expected difference: classifiers `1`, assertion FAIL).
  - [x] 0.3.6 Wiring by comment-stripped resource span: both locals in `triggers_replace` AND in a
        dedicated last `remote-exec` block with no `var.` / `doppler_` / `hooks_json` / `${`.
  - [x] 0.3.7 Consumer census across all `apps/web-platform/infra/*.tf` (`for h in ghcr.io`, any
        `/etc/hosts` write) — only inside the two locals.
  - [x] 0.3.8 In-suite mutation battery for Guard 2 rows 1-11, assertion floor, Phase-5 retirement
        text in failures.
- [x] 0.4 `ci-deploy.test.sh` RED: default `getent` shim on EVERY harness PATH construction; rows
      for a hanging shim (`unknown` within `timeout 5`, exit status equal to a paired baseline),
      NXDOMAIN under `set -euo pipefail`, and `DEPLOY_SCRIPT_SHA` then `GHCR_DENY` exactly once.
- [x] 0.5 `cloud-init-ghcr-seed-login.test.sh`: Guard 1 rows 1-4 (implemented as rows 17-20, plus
      harness row 21 and the review-round shadow row 22) asserting the specific VIOL kind
      (RED until 1.5).

## Phase 1 — The deny on every route

- [x] 1.1 `cloud-init.yml`: deny (byte copy of copy R's whole entry) as runcmd[1], right after the
      trap-arm entry; one-line comment incl. why `0.0.0.0`/`::`, not `127.0.0.1`.
- [x] 1.2 `server.tf` locals: `ghcr_deny_sh` (heredoc) and `ghcr_deny_assert_sh` (positive form for
      both names; the single FATAL literal ending `(#9169)` with the route back).
- [x] 1.3 `zot_consumer_probe_install`: both locals in `triggers_replace`; NEW last secret-free
      `provisioner "remote-exec"` running them; charter comment; confirm the existing body is
      idempotent.
- [x] 1.4 `deploy_pipeline_fix_web2`: both locals in `triggers_replace` ABOVE the pin line (pin +
      `"dpf-web2-remote-exec-v1",` stay adjacent and unchanged); NEW last secret-free
      `provisioner "remote-exec"` after the block ending in `try-restart webhook`; amend the sentinel
      comment and the header charter.
- [x] 1.5 `cloud-init-ghcr-seed-login.test.sh`: block-anchored `{file: {admitted entry}}` exemption
      for the registry and web entries; re-pin the row-count floor.
- [x] 1.6 Run `web-host-provisioner-parity.test.sh` + `-mutation.test.sh` unchanged.
- [x] 1.7 Do NOT touch `cloud-init-registry.yml` or `zot-registry.tf` (ForceNew `user_data`).

## Phase 2 — The heartbeat field

- [x] 2.1 `ci-deploy.sh`: column-0 `_ghcr_blocked_state()` (fail-open, `ghcr.io` only, `timeout 5`
      when available) + `logger -t "$LOG_TAG" "GHCR_DENY ghcr_blocked=$v"` right after
      `DEPLOY_SCRIPT_SHA`.
- [x] 2.2 `git grep` for closed lists of `ci-deploy` marker names (none found at plan time);
      confirm `scripts/check-deploy-script-parity.sh` is untouched.
- [x] 2.3 Separate commit: fix the stale GHCR `.sig` comment at the cosign verify site.

## Phase 3 — Budgets and records

- [x] 3.1 Raise `WEB_GZIP_BUDGET` (raised to 23,800 ahead of CI from the local render + 32 B, the
      same derivation as the previous lower; re-derive from the CI failure line if it reds).
- [x] 3.2 ADR-096: "Amendment 2026-09-30 (#9169) — the web hosts deny ghcr.io" (routes and the
      in-place rationale for web-1 and web-2, marker + worst-case evidence age, host vs
      bridge-container scope + #9275, `ghcr.io`-only marker vs apply-time proof of both names,
      loopback behaviour, live proof); update the status bullets.
- [ ] 3.3 Run AC1-AC16 (plan § Acceptance Criteria → Pre-merge). AC1-AC7, AC9-AC11, AC14-AC16 green at work exit; AC8/AC12/AC13 are read at ship.

## Phase 4 — Post-merge (pipeline, automated)

- [ ] 4.1 PM1/PM2: both push-triggered apply runs green; the SSH-stage step concluded `success`
      (not `skipped`); no `FATAL: .* (#9169)`. Re-drive red or `cancelled` runs with a fresh commit
      or `gh workflow run`, never `gh run rerun --failed`.
- [ ] 4.2 PM3/PM4: after the first release that follows both applies, `GHCR_DENY ghcr_blocked=1` and
      `IMAGE_VERIFY: ok` from both hosts; no `IMAGE_VERIFY_FAIL` / `cosign_absent`.
- [ ] 4.3 PM5: `check-deploy-script-parity.sh` exits 0.
- [ ] 4.4 PM6: close #9169 with the evidence rows; comment on #8714.

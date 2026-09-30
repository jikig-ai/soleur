# Tasks — deny ghcr.io on the web hosts (#9169)

Plan: `knowledge-base/project/plans/2026-09-30-infra-deny-ghcr-on-web-hosts-plan.md`

## Phase 0 — Setup and RED tests

- [ ] 0.1 Bump `BASELINE_DECLARED_PROBES` 36 → 37 in
      `plugins/soleur/test/preflight-discoverability-test.test.ts` with the PLACEMENT / TRUTH /
      NO SUBSTITUTE comment for this plan (the plan commit already moved the count).
- [ ] 0.2 Measure the web cloud-init gzip render with the deny inserted (scratch copy) against
      `WEB_GZIP_BUDGET` in `plugins/soleur/test/cloud-init-user-data-size.test.ts`; record the delta.
- [ ] 0.3 Write `apps/web-platform/infra/web-ghcr-deny.test.sh` (Guard 2) RED:
  - [ ] 0.3.1 Copy parity A (cloud-init runcmd) == B (`local.ghcr_deny_sh`) == R (registry) after
        dedent; no `${` / `%{` in the heredoc body.
  - [ ] 0.3.2 Execute copy B once under `bash` against synthesized temp files.
  - [ ] 0.3.3 Classifier-agreement table (sinkhole only / routable / mixed / unresolvable) across the
        registry classifier, `_ghcr_blocked_state` and `local.ghcr_deny_assert_sh`.
  - [ ] 0.3.4 Ordering: copy A immediately after the `trap on_err EXIT` entry, before any
        `apt-get` / `docker pull` / `docker run` / `wget` entry.
  - [ ] 0.3.5 Wiring: both locals in `triggers_replace` AND `remote-exec` `inline` of
        `zot_consumer_probe_install` and `deploy_pipeline_fix_web2`; zero `for h in ghcr.io`
        occurrences in `server.tf` outside the two locals.
  - [ ] 0.3.6 Non-vacuity floor (3 non-empty copies); failure text names the active-active Phase 5
        retirement; demonstrate every Guard 2 mutation row RED.
- [ ] 0.4 `ci-deploy.test.sh` RED: default `getent` shim on the harness PATH; fail-open row
      (`getent` absent / NXDOMAIN → `unknown`, exit status unchanged); once-per-invocation row
      (`DEPLOY_SCRIPT_SHA` then `GHCR_DENY ghcr_blocked=…`).
- [ ] 0.5 `cloud-init-ghcr-seed-login.test.sh`: Guard 1 rows 1-3 (RED until 1.5).

## Phase 1 — The deny on every route

- [ ] 1.1 `cloud-init.yml`: deny loop (byte copy of the registry loop) as the second `runcmd:` entry,
      right after the trap-arm entry; one-line comment.
- [ ] 1.2 `server.tf` locals: `ghcr_deny_sh` (heredoc) and `ghcr_deny_assert_sh` (positive-form check
      for both names; the single FATAL literal ending `(#9169)` with the route back).
- [ ] 1.3 `zot_consumer_probe_install`: both locals in `triggers_replace`; both LAST in `inline`;
      charter comment `# also carries the ghcr.io hosts-file deny (#9169; Guard 2)`; confirm the
      existing body is idempotent.
- [ ] 1.4 `deploy_pipeline_fix_web2`: both locals in `triggers_replace` ABOVE the pin line (leave the
      pin line + `"dpf-web2-remote-exec-v1",` adjacent and unchanged); both after the sha256
      assertions in `inline`; update the header charter comment.
- [ ] 1.5 `cloud-init-ghcr-seed-login.test.sh`: generalise the whole-line exemption to a
      `{file: {lines}}` table admitting the deny line in `cloud-init.yml` only; re-pin the row-count
      floor.
- [ ] 1.6 Run `web-host-provisioner-parity.test.sh` and `web-host-provisioner-parity-mutation.test.sh`
      unchanged; re-pin floors only if a measured count moves.

## Phase 2 — The heartbeat field

- [ ] 2.1 `ci-deploy.sh`: `_ghcr_blocked_state` (fail-open, `ghcr.io` only, `timeout 5` when
      available) + `logger -t "$LOG_TAG" "GHCR_DENY ghcr_blocked=$v"` right after `DEPLOY_SCRIPT_SHA`.
- [ ] 2.2 `git grep` for closed lists of `ci-deploy` marker names and extend any; confirm
      `scripts/check-deploy-script-parity.sh` is untouched.
- [ ] 2.3 Separate commit: fix the stale GHCR `.sig` comment at the cosign verify site.

## Phase 3 — Budgets and records

- [ ] 3.1 Raise `WEB_GZIP_BUDGET` from the CI failure line only if it reds.
- [ ] 3.2 ADR-096: "Amendment 2026-09-30 (#9169) — the web hosts deny ghcr.io" (routes, delivery-route
      rationale, marker + worst-case evidence age, scope split, loopback behaviour, live proof);
      update the status bullets.
- [ ] 3.3 Run AC1-AC15 (plan § Acceptance Criteria → Pre-merge), including `terraform validate`,
      `c4-count-parity`, the lints and markdownlint.

## Phase 4 — Post-merge (pipeline, automated)

- [ ] 4.1 PM1/PM2: both push-triggered apply runs green; the SSH-stage step concluded `success`; no
      `FATAL: .* (#9169)`. Re-drive failures with a fresh commit or `gh workflow run`, never
      `gh run rerun --failed`.
- [ ] 4.2 PM3/PM4: after the first release that follows both applies, `GHCR_DENY ghcr_blocked=1` and
      `IMAGE_VERIFY: ok` from both hosts; no `IMAGE_VERIFY_FAIL` / `cosign_absent`.
- [ ] 4.3 PM5: `check-deploy-script-parity.sh` exits 0.
- [ ] 4.4 PM6: close #9169 with the evidence rows; comment on #8714.

---
feature: feat-one-shot-5499-host-stderr-betterstack
issue: 5499
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-18-feat-host-script-stderr-betterstack-queryable-plan.md
---

# Tasks — host-script `logger -t` stderr → Better Stack queryable (#5499)

## Phase 0 — Preconditions (at /work start)

- [ ] 0.1 Verify the `logger -t` tag set: `grep -l 'logger -t' apps/web-platform/infra/*.sh`
      then `grep -rhoP 'LOG_TAG=\K"?[a-z0-9-]+' <those files> | tr -d '"' | sort -u`. Confirm
      exactly: infra-config-apply, infra-config-install, ci-deploy, inngest-enumerate-reminders,
      inngest-rearm-reminders, inngest-wiped-volume-verify, inngest-inventory. (cron-egress-* +
      container-restart-monitor use echo/Sentry, NOT logger -t — exclude.)
- [ ] 0.2 Confirm `VECTOR_BIN` available (or document `vector validate` runs in CI only).
- [ ] 0.3 `grep -A6 'paths:' .github/workflows/apply-web-platform-infra.yml` — determine
      whether a vector.toml-only edit trips the apply trigger. If not, choose the §Apply path
      remedy (add path filter OR document the Doppler prd_terraform apply triplet).

## Phase 1 — Add the dedicated host-script journald source

- [ ] 1.1 Edit `apps/web-platform/infra/vector.toml`: add `[sources.host_scripts_journald]`
      after Source 3 (`app_container_journald`, ~line 69), with the 7-tag
      `include_matches.SYSLOG_IDENTIFIER` array, `type = "journald"`, `journal_directory`,
      `batch_size = 16`, and the documenting comment block (no PRIORITY filter).

## Phase 2 — Wire through the redaction chain

- [ ] 2.1 Edit `apps/web-platform/infra/vector.toml`: append `"host_scripts_journald"` to the
      `inputs` array of `[transforms.pii_scrub_drop_userdata]` (~line 141), mirroring the
      #4773 boundary comment rationale.

## Phase 3 — Config-assertion parity fixture

- [ ] 3.1 Edit `apps/web-platform/test/infra/vector-pii-scrub.test.sh`: add grep-based
      config-assertion cases:
      - source block exists with `type = "journald"`
      - SYSLOG_IDENTIFIER array == scripts'-actual-`logger -t`-tag set (drift guard)
      - NO `include_matches.PRIORITY` in the block (regression guard)
      - source present in `pii_scrub_drop_userdata` inputs (redaction-boundary guard)

## Phase 4 — Verify (pre-merge)

- [ ] 4.1 `vector validate apps/web-platform/infra/vector.toml` passes (AC5).
- [ ] 4.2 Run `vector-pii-scrub.test.sh` green (AC6).
- [ ] 4.3 Run AC1–AC4 grep/awk verifications.
- [ ] 4.4 PR body: `Closes #5499` (AC7).

## Phase 5 — Post-merge (operator / automated)

- [ ] 5.1 Confirm apply reached host (AC8) via apply-web-platform-infra.yml run /
      deploy-status webhook / cat-deploy-state.sh vector tail — no remote-shell.
- [ ] 5.2 Discoverability (AC9): `doppler run -p soleur -c prd_terraform --
      scripts/betterstack-query.sh --since 24h --grep inngest-rearm-reminders
      --grep infra-config-apply --limit 20` returns ≥1 host-script-tagged row after a
      host-script logger -t line fires. Then `gh issue close 5499` if not auto-closed.

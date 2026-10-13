---
feature: feat-one-shot-5499-host-stderr-betterstack
issue: 5499
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-18-feat-host-script-stderr-betterstack-queryable-plan.md
---

# Tasks — host-script `logger -t` stderr → Better Stack queryable (#5499)

## Phase 0 — Preconditions (at /work start)

- [x] 0.1 Verify the `logger -t` tag set: `grep -l 'logger -t' apps/web-platform/infra/*.sh`
      then `grep -rhoP 'LOG_TAG=\K"?[a-z0-9-]+' <those files> | tr -d '"' | sort -u`. Confirm
      exactly: infra-config-apply, infra-config-install, ci-deploy, inngest-enumerate-reminders,
      inngest-rearm-reminders, inngest-wiped-volume-verify, inngest-inventory. (cron-egress-* +
      container-restart-monitor use echo/Sentry, NOT logger -t — exclude.)
- [x] 0.2 Confirm `VECTOR_BIN` available (or document `vector validate` runs in CI only).
- [x] 0.3 Confirm the apply path is OCI-image-rebuild + `deploy inngest` (NOT terraform).
      vector.toml is baked into the soleur-inngest-bootstrap image
      (build-inngest-bootstrap-image.yml:164,183); apply-web-platform-infra.yml is terraform-only
      and a NO-OP for a vector.toml-only change. Do NOT rely on the apply-web-platform-infra.yml
      path filter (it matches but does not deliver — false-confidence trap). Delivery is verified
      via the `vector config installed: sha256=` log (inngest-bootstrap.sh:430).

## Phase 1 — Add the dedicated host-script journald source

- [x] 1.1 Edit `apps/web-platform/infra/vector.toml`: add `[sources.host_scripts_journald]`
      after Source 3 (`app_container_journald`, ~line 69), with the 7-tag
      `include_matches.SYSLOG_IDENTIFIER` array, `type = "journald"`, `journal_directory`,
      `batch_size = 16`, and the documenting comment block (no PRIORITY filter).

## Phase 2 — Wire through the redaction chain

- [x] 2.1 Edit `apps/web-platform/infra/vector.toml`: append `"host_scripts_journald"` to the
      `inputs` array of `[transforms.pii_scrub_drop_userdata]` (~line 141), mirroring the
      #4773 boundary comment rationale.

## Phase 3 — Config-assertion parity fixture

- [x] 3.1 Edit `apps/web-platform/test/infra/vector-pii-scrub.test.sh`: add grep-based
      config-assertion cases:
      - source block exists with `type = "journald"`
      - SYSLOG_IDENTIFIER array == scripts'-actual-`logger -t`-tag set (drift guard)
      - NO `include_matches.PRIORITY` in the block (regression guard)
      - source present in `pii_scrub_drop_userdata` inputs (redaction-boundary guard)

## Phase 4 — Verify (pre-merge)

- [x] 4.1 `vector validate apps/web-platform/infra/vector.toml` passes (AC5).
- [x] 4.2 Run `vector-pii-scrub.test.sh` green (AC6).
- [x] 4.3 Run AC1–AC4 grep/awk verifications.
- [ ] 4.4 PR body: `Ref #5499` (NOT `Closes` — fix is live only post-deploy; AC7).
- [x] 4.5 (optional) Project per-event row count: `journalctl -t ci-deploy -t infra-config-apply
      --since '7 days ago' | wc -l` / 7 < ~1k rows/day, or estimate from deploy frequency.

## Phase 5 — Post-merge (operator / automated; OCI-rebuild path, NOT terraform)

- [ ] 5.1 Cut + push a `vinngest-vX.Y.Z` tag (bump from ~v1.1.14): `git tag vinngest-vX.Y.Z &&
      git push origin vinngest-vX.Y.Z`. Confirm build-inngest-bootstrap-image.yml publishes the
      plain `vX.Y.Z` GHCR image.
- [ ] 5.2 Deploy via release pipeline / deploy webhook (no SSH):
      `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z` (inngest-server.md:336,602).
- [ ] 5.3 Verify (AC8, no remote-shell): cat-deploy-state.sh journal tail shows
      `vector config installed: sha256=<X>` where `<X>` == `sha256sum apps/web-platform/infra/vector.toml`
      of the merged file. Stale sha = not applied (a terraform run is NOT evidence).
- [ ] 5.4 Discoverability (AC9, only after 5.3 sha matches): trigger an inngest-inventory via
      `/soleur:trigger-cron`, then `doppler run -p soleur -c prd_terraform --
      scripts/betterstack-query.sh --since 24h --grep inngest-inventory --grep infra-config-apply
      --limit 20` returns ≥1 host-script-tagged row. Then `gh issue close 5499`.

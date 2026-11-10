# Tasks: first-boot kernel currency + generic web hosts (PR 1 of 7)

Plan: `knowledge-base/project/plans/2026-11-10-feat-first-boot-kernel-currency-web-hosts-plan.md`.
ADR-322 applies to every file, commit and the PR body.

## Phase 1: RED tests

- [x] 1.1 `apps/web-platform/infra/kernel-currency.test.sh`: settle behaviour cases (match; mismatch+no marker; mismatch+marker; unreadable; semaphore absent) with stubs
- [x] 1.2 Same suite: structural rows (apt token in `STAGE=apt_install`, `dpkg --configure -a` retry, settle item right after apt, idempotent allowlist, no Doppler/docker/`/mnt/data`/LUKS before it, semaphore path once, no `power_state:`/`packages:`, marker under `/var/lib/soleur`)
- [x] 1.3 Same suite: budget rows (`DEADLINE` + `SOLEUR_FRESH_BOOT_WINDOW_SECONDS` moved together; create and replace worst cases under their 40 min job limits (create raised 30 -> 40))
- [x] 1.4 Instrument self-test + exact-count anti-vacuity floor
- [x] 1.5 `fresh-boot-ready.test.sh`: kernel predicate rows (match, mismatch, empty target)
- [x] 1.6 Part 2a tests: var validations (one primary profile, one jump, unique in-subnet IP); dynamic LB origins reproduce today's weights and order; `WEB_HOST_PRIVATE_IPS` parity across workflows; `lb-weight-gate.sh` third-key cases; ratchet (web-1 IP literal + `"web-1"`, ceiling = today); host-bound-state census rows
- [x] 1.7 Register new suites: `suite-shard-legs.tsv` (+ `suite-durations.tsv` if required), `scripts/guard-vacuity-floor.test.sh` promotion

## Phase 2: GREEN — Part 1 (kernel currency)

- [x] 2.1 `cloud-init.yml`: `linux-image-generic` on the bounded install line; `dpkg --configure -a` before attempt 2
- [x] 2.2 `cloud-init.yml`: inline settle item (`STAGE=kernel_settle`) right after the apt block
- [x] 2.3 `soleur-host-bootstrap.sh`: verdict `kernel=` field + not-ready `kernel`; window constant + derivation
- [x] 2.4 `scripts/fresh-host-boot-trail.sh`: `DEADLINE` + cost comment
- [x] 2.5 Measure rendered user_data (`bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`); trim comments or re-baseline with the number
- [x] 2.6 Drive every Guard 1–2 mutation row RED once; record results

## Phase 3: GREEN — Part 2a (generic web hosts, no running host changed)

- [x] 3.1 `variables.tf`: `lb_weight`, `luks_monitor_profile`, `jump` fields + validations
- [x] 3.2 `cloudflare-lb.tf`: dynamic origins; `server.tf`: keyed `web_tunnel_connector`
- [x] 3.3 `inngest-host.tf`: derived `WEB_HOST_PRIVATE_IPS`; workflows pinned by parity test
- [x] 3.4 `lb-weight-gate.sh`: drop the literal `web-2`
- [x] 3.5 Census doc (egress-tokens dir at birth, cron state, per-host heartbeat)
- [ ] 3.6 `terraform plan` (web-platform root): no change to servers, volumes, attachments, tunnel, LB pool; quote in PR body

## Phase 4: Docs + ADR

- [x] 4.1 ADR(s) via `soleur:architecture`: kernel currency at birth (ADR-257 exception); dedicated bastion + identical cattle web hosts
- [x] 4.2 Pointer addenda: ADR-263, ADR-220, ADR-100 Decision 1, ADR-143 D2
- [x] 4.3 Runbooks: `host-kernel-patch-cadence.md`, `web-host-replace.md` (new failure rows, red replace not a serving target, explicit `-f image_tag=`)
- [x] 4.4 Spec FR2/FR3/TR4 to ruling C; Part 2 scope
- [ ] 4.5 Re-run trail/window-pinning suites; `plugins/soleur/test/c4-count-parity.test.sh`
- [x] 4.6 File the shared-project 100-event page truncation issue; update #9421 with the 7-PR sequence

## Phase 5: Ship

- [ ] 5.1 Review, compound, ship (ADR-322 wording; `Ref #12008`, `Ref #9421`)
- [ ] 5.2 Operator acts after merge (each needs the owner's typed go): web-2 `web-host-replace` (`plan_only` then real, explicit `-f image_tag=`); agent reads the trail, reader and live LB pool

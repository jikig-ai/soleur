---
feature: feat-one-shot-6966-web2-cpx22-repin
issue: 6966
pr: 6967
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-26-fix-web2-cpx22-repin-unwedge-main-plan.md
---

# Tasks — repin web-2 cx23 → cpx22 and unwedge main (#6966)

## Phase 1 — the value change (`variables.tf`)

- [ ] 1.1 `var.web_hosts` default: web-2 `server_type` `"cx23"` → `"cpx22"`
- [ ] 1.2 Re-derive the `:101-118` block comment — delete the two false claims (`:106` cx23 sizing
      line, `:109-111` "cx23 is the cheapest orderable 4g x86 in hel1"); carry the 2026-07-26 probe
      date, the reduced choice set, the cpx12-rejected-on-headroom note, and the
      `.available`-vs-`.supported` trap pointer
- [ ] 1.3 Confirm NO `server_type` prefix validation and NO `data.hcloud_server_type.web` were added
      (both deliberately scoped out — see plan Alternatives Considered)

## Phase 2 — falsified stock prose in the blast radius (prose only)

- [ ] 2.1 `zot-registry.tf:50` — correct the "whichever of cax11 / cx23 has Hetzner stock" claim
- [ ] 2.2 `cloud-init-registry.yml:731` — same claim, same correction
- [ ] 2.3 `var.registry_server_type` description/comments (`variables.tf:152-184`) — stock sub-claims
      only; `default = "cx23"` MUST remain untouched
- [ ] 2.4 State the disaster-recovery gap once, near `var.web_hosts`: web-1 (cx33), grok-dogfood
      (cx33), registry (cx23) all run on types that can no longer be ordered — none can be rebuilt
      on its current type

## Phase 3 — ADR-143 addendum + C4 correctness

- [ ] 3.1 ADR-143 addendum dated 2026-07-26 (status stays `adopting`; no new ADR file)
- [ ] 3.2 `model.c4` — `hetzner` description: cx23 → cpx22, drop "in stock in hel1";
      `workspacesVolume` description: the "no plaintext member remains" claim must stop being
      unconditional (cite #6931)
- [ ] 3.3 C4 validators green; confirm no `views.c4` / `spec.c4` change was needed

## Phase 4 — expense ledger + account cap

- [ ] 4.1 `expenses.md` `Hetzner CX23 (web-2)` → `CPX22`: shape, rate (EUR 19.49 net → USD @ ~1.08),
      delta, reason; keep `approved-not-billing`; `estimate verify_by=`; net==gross caveat
- [ ] 4.2 Record the live account server cap `SERVERS 4 / 10` (verified 2026-07-26) with the
      `GET /v1/limits` → 404 note and a `verify_by`

## Phase 5 — verification (pre-merge)

- [ ] 5.1 `terraform validate` + scoped `terraform plan`: web-2 create on `cpx22`, `0 to destroy`,
      no sibling host create/replace
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [ ] 5.3 `bash scripts/test-all.sh` green
- [ ] 5.4 `bash apps/web-platform/infra/run-registered-suites.sh` green (infra suites test-all.sh misses)
- [ ] 5.5 AC1–AC11 all verified

## Phase 6 — post-merge birth (gated dispatch)

- [ ] 6.1 Re-measure `cpx22` orderability in `hel1`; confirm the `web-platform-infra-apply`
      environment has a non-empty required-reviewer set
- [ ] 6.2 Dispatch `web-host-create` for web-2 (no `-f image_tag`)
- [ ] 6.3 Verify `soleur-web-2` / `cpx22` / running via `GET /v1/servers`; `cloud_init_complete`,
      no `fatal`
- [ ] 6.4 Flip the `expenses.md` row → `active` with the provision date
- [ ] 6.5 Confirm the next merge to `main` no longer HALTs on `host_creates`
- [ ] 6.6 Tick 5.1–5.3 in `specs/feat-one-shot-6730-web-host-birth-path/tasks.md`; close #6730 with
      the run URL

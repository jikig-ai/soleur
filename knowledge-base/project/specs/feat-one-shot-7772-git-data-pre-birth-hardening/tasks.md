<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 was run; the plan's `## Infrastructure (IaC)` section is its output. The unit-activation step
  this file prescribes is NOT a human-run step: it is a line inside cloud-init `runcmd`, rendered by
  `module.git_data_userdata` into `hcloud_server.git_data.user_data` and applied by Terraform. git-data has
  NO SSH provisioner by design (the CI runner cannot reach it, so a remote-exec would hang the
  merge-triggered auto-apply) and no baked host-scripts image, so cloud-init IS the IaC route here. The
  identical shape already ships in cloud-init-inngest.yml and in this template's own gc_timer block.
  Likewise the Doppler write in Phase 1 provisions a TF_VAR_* INPUT that Terraform itself reads and
  therefore cannot manage as a doppler_secret resource — the ADR-065 bootstrap pattern, performed by the
  agent over the CLI, with no operator action.
-->

# Tasks — git-data pre-birth hardening (#7772)

Derived from `knowledge-base/project/plans/2026-09-03-feat-git-data-pre-birth-hardening-plan.md`, and
**updated after the deepen-plan review round** — several tasks below reverse what the first draft said.
Read the plan's `## Deepen-Plan Verification` (V1, V1b, V2) and `## Design Calls` (D1-D5) first.

**Ordering is load-bearing.** Phase 1 completes before Phase 2 touches any `.tf`: an unprovisioned
no-default variable fails the *whole* merge-triggered apply for `apps/web-platform/infra/`, not just its own
resource (ADR-065). `infra-validation.yml`'s PR-only full-root plan is the mechanical enforcer.

---

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Run the userdata budget script; record `stored`/`headroom` (baseline 13132 B / 19636 B).
- [ ] 0.2 Confirm the template sha256 is `241b47af28fee2951bad76d4c57f49d6220c21907d0b89b19c2bbdca08f7e08f`
      and that `git-data-rung2-boot-evidence.env` does not exist.
- [ ] 0.3 Re-run the credential scope probe (422 vs 403). **Status codes only**, and the API token on
      stdin via `curl -K -`, never argv — see 1.0.
- [ ] 0.4 Confirm `grep -c '169\.254\.169\.254'` is 0 across the template and all nine payloads.
- [ ] 0.5 Confirm `nftables` is absent from `packages:` and no `git-data-nftables*` name collides.

## Phase 1 — Item A: create the source, provision Doppler (BEFORE any .tf edit)

- [ ] 1.0 **Credential hygiene, three rules — see the plan's Phase 1 step 0 for the exact forms.**
      (a) The write-scoped API token goes on **stdin** (`curl -K -`), never argv.
      (b) **No unfiltered API body reaches stdout** — every read pipes through `jq` selecting only
      `.id`, `.attributes.name`, `.attributes.ingesting_host`, `.attributes.table_name`, because a source
      listing returns every source's ingest token including the shared one.
      (c) **The Doppler write is silenced** (`--silent` plus a stdout redirect to `/dev/null`): the CLI
      otherwise prints all remaining secrets in the config, and `prd_terraform` holds ~160 names.
- [ ] 1.1 Find-or-create, idempotent, matching on the source name `soleur-git-data-prd`; create with
      `platform: http`, `data_region: eu-central-1a`, `logs_retention: 90` only when absent.
- [ ] 1.2 Pipe the returned token over stdin into Doppler `soleur/prd_terraform` as
      `GIT_DATA_BETTERSTACK_LOGS_TOKEN` (no `TF_VAR_` prefix). **The only Doppler write** — the ingest URL
      is a `locals` literal, not a secret (**D5**). Record `ingesting_host` and `table_name`.
- [ ] 1.3 Verify the name exists (names-only listing); prove the credential works with the ingest probe.
      Confirm token length > 20 without hard-coding the number.

## Phase 2 — Item A wiring (contract before consumers)

- [ ] 2.1 `variables.tf`: add `git_data_betterstack_logs_token` (sensitive, no default). **One variable
      only** — the URL is not a variable (D5).
- [ ] 2.2 `git-data.tf`: add `local.git_data_betterstack_ingest_url` as a plain literal, mirroring
      `zot-registry.tf`'s `betterstack_logs_ingest_url` including its comment shape.
- [ ] 2.3 `git-data-luks.tf`: the `doppler_secret` value moves to `var.git_data_betterstack_logs_token`.
      Keep `ignore_changes = [value]`; do not rename the resource (it is birth target #20).
- [ ] 2.4 `git-data.tf`: the module block's two args move onto the new local and the new variable.
- [ ] 2.5 **`rung2-rehearsal/variables.tf`: RENAME the token variable** to
      `git_data_betterstack_logs_token` (no default). Without this the rehearsal keeps resolving the
      **shared** token by Doppler name transformation and D1 silently fails. Also re-point the
      `betterstack_ingest_url` default and rewrite its comment.
- [ ] 2.6 `rung2-rehearsal/rehearsal.tf`: the module block binds the renamed variable.
- [ ] 2.7 `.github/workflows/git-data-rung2-rehearsal.yml`: its pre-dispatch Doppler-name preflight must
      assert the new secret name. **Preflight-name edit only — do NOT dispatch the workflow.**
- [ ] 2.8 Update the ingest-URL stub in the budget script (safe: the parity test compares strip
      *expressions*, not stub values).
- [ ] 2.9 `terraform validate` both roots.

## Phase 3 — Gate + harness updates (D1)

- [ ] 3.1 Arm 7: re-point the prod-side extraction to `git-data.tf`'s new local — same `locals`-literal
      shape, different file. Keep by-shape extraction on both sides.
- [ ] 3.2 Arm 72: update the `value = var.…` regex. Its five predicates move together — the bake and the
      `doppler_secret` must both reach the new variable, or the arm stays green on four of five while its
      stated invariant is broken.
- [ ] 3.3 Arms 74/75: variable names in **both** roots; keep the no-default assertions.
- [ ] 3.4 **Add a same-variable-name parity arm** — the only statically checkable proxy for "same sink"
      once the value is a secret.
- [ ] 3.5 Arm 5.6a: reword the premise to say both roots ship to the **git-data** sink. **Do not touch the
      allowlist.**
- [ ] 3.6 Verify (do not assume) the 12-member module-input pin is unaffected.
- [ ] 3.7 Evidence-capture script: query the new table.
- [ ] 3.8 Suite still reports >= 75 cases, 0 failures.

## Phase 4 — Item B: metadata egress closure (the ForceNew change)

- [ ] 4.1 Add `nftables` to `packages:`.
- [ ] 4.2 Inline `write_files:` the nft script at `0755 root:root`. **Use the three-line replace idiom**
      (`table` / `delete table` / `table { … }`) — a bare declaration MERGES rather than replaces (**V1b**,
      measured: two loads left 2 duplicate rules; the idiom left 1). Rule body:
      `meta skuid != 0 ip daddr 169.254.169.254 drop` plus the IPv6 line, in
      `chain output { type filter hook output priority -10; policy accept; }`.
- [ ] 4.3 Inline the unit at `0644 root:root`: `Type=oneshot`, `RemainAfterExit=yes`,
      `After=`/`Wants=network-online.target`, `WantedBy=multi-user.target`, `SyslogIdentifier` **without**
      the `.sh` suffix.
- [ ] 4.4 **Add both inline paths to `INLINE_ALLOWLIST`** in `git-data-runcmd-rehearsal.test.sh` — without
      this, arm B1 hard-fails them. The first draft wrongly claimed this file was untouched.
- [ ] 4.5 `runcmd` item after `gc_timer`: `STAGE=gitdata_nftables_metadata`, activating the unit with the
      **`--now`** form (the bare enable leaves the control inert for the host's life — git-data never
      reboots), inside a guarded rc-capture in the exact `gc_timer` substitution-plus-`if` shape, emitting
      `gitdata_nftables_metadata_warn` at **warning** on failure. It is **inside** the `set -e` region and
      fail-open by the `|| _rc=$?` idiom, not by placement.
- [ ] 4.6 Add `nft_metadata_drop=yes|no` as a fifth boolean on `stage:boot_complete` in
      `git-data-bootstrap.sh` — the only positive signal the control loaded, and the only one that survives
      the ruleset disappearing later.
- [ ] 4.7 Do **not** activate the packaged `nftables.service` (its stop action flushes the whole ruleset).
- [ ] 4.8 Re-run the budget script; record the new template sha256.

## Phase 5 — Item C: route the stages

- [ ] 5.1 Add `gitdata_nftables_metadata` to `git_data_boot_fatal`'s `filters_v2` — it is trap-reachable at
      **fatal**, and without this a boot-aborting failure there pages nobody (D4).
- [ ] 5.2 Add the new low-severity rule: `IS_IN "betterstack_ingest,gitdata_nftables_metadata_warn"`,
      `fallthrough_type = "NoOne"`, `event_frequency {count, value=0, interval="1h"}` (**not**
      `first_seen_event` — V2), `lifecycle { ignore_changes = [environment] }`, unused `frequency`
      (6-9, 28-29, 31-59, 64+; not 15).
- [ ] 5.3 Ship the stage-route guard in the **sibling shape** (~83 lines, literal list + loop), not a
      general extraction engine. Property: every `STAGE=` name appears in `git_data_boot_fatal`'s filters.
- [ ] 5.4 Add `nft -c -f` syntax validation of the rendered ruleset to `infra-validation`.

## Phase 6 — Item D: stale-prose corrections

- [ ] 6.1 `terraform-target-parity.test.ts`: correct the `doppler_secret.git_data_ssh_host` comment (the
      tree reads `hcloud_server_network.git_data.ip`, per ADR-149's DC-5 **reversal**), its now-backwards
      final sentence, and the sibling "static local" claim in the `OPERATOR_APPLIED_EXCLUSIONS` comment.
- [ ] 6.2 `git-data-host-birth-gate.sh`: make the ABORT text say **three** entailed members without
      changing the loop. Sweep **four** stale sites — the header, the mid-file restatement, the ABORT
      string, and `Exactly these four` directly above the loop. Cite by content anchor, not line number.

## Phase 7 — Records

- [ ] 7.1 ADR-198 amendment, four parts. **Amendment 2 must be scoped**: the metadata closure restores the
      category for the two `0600` credentials only — `sentry_dsn` sits at `0755` and is unaffected, so it
      stays an open residual needing its own tracker before #7772 closes. State the `meta skuid` boundary
      (socket-creation-time UID; a setuid-root helper bypasses it) so the ADR is not readable as claiming
      defence against a root-capable adversary.
- [ ] 7.2 `scripts/encryption-posture-ledger.json`: add a row for the new store (with `attestation_url` +
      `retrieved_on`), and correct `git_data.baked_credentials_on_host`, whose `does_not_defend` this PR
      falsifies and whose `tracking_issue` this PR closes.
- [ ] 7.3 `model.c4`: correct the `betterstack` description (two sources now). Run the C4 tests.
- [ ] 7.4 Amend the 2026-07-18 learning (the Read-scoped claim is stale — R2).
- [ ] 7.5 Correct the false *"replaces atomically -> idempotent"* nft comment in `cloud-init-inngest.yml` —
      it is the precedent this plan copied, and it is measured wrong.
- [ ] 7.6 Comment on #7772: Item E's disposition, the ADR-198 fourth-item triage-out, the corrected Item A
      reasoning, and the `sentry_dsn`-at-0755 residual.

## Phase 8 — Verification and ship

- [ ] 8.1 Work the plan's Acceptance Criteria 1-21 in order.
- [ ] 8.2 Full battery, or report skipped-for-contention on rc=4.
- [ ] 8.3 PR body: the R4 correction (this **is** a template change), old + new template sha256,
      `Closes #7772`, and that no rehearsal dispatch was fired.
- [ ] 8.4 Arm auto-merge; sync on BEHIND.
- [ ] 8.5 Post-merge: confirm the Sentry infra apply succeeded and the new rule is live — that root 410s
      during Sentry brownouts, and a brownout would silently mean Item C never shipped.

---

## Do NOT

- Do **not** create `apps/web-platform/infra/git-data-rung2-boot-evidence.env`.
- Do **not** dispatch the rung-2 rehearsal workflow (2.7 edits its preflight only).
- Do **not** widen `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` (D1 makes it unnecessary; arm 5.6a refuses it).
- Do **not** add a 10th `file()` payload (D2).
- Do **not** change the 20-address birth fan-out (R6).
- Do **not** make the ingest URL a variable or a Doppler secret (D5).
- Do **not** re-point `local.betterstack_logs_ingest_url` in `zot-registry.tf` — the web hosts and registry
  stay on source 2457081.
- Do **not** put any credential on argv, let an unfiltered Better Stack API body reach stdout, or run an
  unsilenced Doppler write.

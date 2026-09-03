# Tasks — git-data pre-birth hardening (#7772)

Derived from `knowledge-base/project/plans/2026-09-03-feat-git-data-pre-birth-hardening-plan.md`.
Read the plan's **Design Calls** (D1-D4) and **Research Reconciliation** (R1-R14) before starting: several
tasks below only make sense against corrections the plan established, and two of them reverse what the
issue text says.

**Ordering is load-bearing.** Phase 1 must complete before Phase 2 touches any `.tf`: an unprovisioned
no-default variable fails the *whole* merge-triggered apply for `apps/web-platform/infra/`, not just its own
resource (ADR-065).

---

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Run `bash apps/web-platform/infra/git-data-userdata-budget.sh`; record `stored` and `headroom`
      (baseline: 13132 B / 19636 B).
- [ ] 0.2 Confirm `sha256sum apps/web-platform/infra/cloud-init-git-data.yml` is
      `241b47af28fee2951bad76d4c57f49d6220c21907d0b89b19c2bbdca08f7e08f`.
- [ ] 0.3 Confirm `apps/web-platform/infra/git-data-rung2-boot-evidence.env` does not exist.
- [ ] 0.4 Re-run the credential scope probe: `POST /api/v2/sources` with `{}` under
      `BETTERSTACK_API_TOKEN` (expect 422) and `BETTERSTACK_API_TOKEN_READONLY` (expect 403).
      **Print status codes only** — `GET /sources` bodies carry every source's ingest token.
- [ ] 0.5 Confirm `grep -c '169\.254\.169\.254'` returns 0 across `cloud-init-git-data.yml` and all nine
      `file()`-bound payloads.
- [ ] 0.6 Confirm `nftables` is absent from the template's `packages:` list and no `git-data-nftables*`
      name collides.

## Phase 1 — Item A: create the Better Stack source, provision Doppler (BEFORE any .tf edit)

- [ ] 1.1 `GET /api/v2/sources`; find-or-create on name `soleur-git-data-prd` (idempotent — a retry must
      not create a duplicate).
- [ ] 1.2 If absent, `POST /api/v2/sources` with
      `{"name":"soleur-git-data-prd","platform":"http","data_region":"eu-central-1a","logs_retention":90}`.
- [ ] 1.3 Extract `token` and `ingesting_host` with `jq` in the same shell; pipe the token over **stdin**
      into Doppler `soleur/prd_terraform` as `GIT_DATA_BETTERSTACK_LOGS_TOKEN`. Never `cat`, never echo,
      never `--plain` to stdout. The repository is public.
- [ ] 1.4 Set `GIT_DATA_BETTERSTACK_INGEST_URL` = `https://<ingesting_host>/` in the same config.
- [ ] 1.5 Verify both names exist via `doppler secrets --only-names` (names only, never values).
- [ ] 1.6 Prove the credential works: `scripts/betterstack-ingest-probe.sh` against the new URL (exit 0).
- [ ] 1.7 Confirm token length > 20 (the module's own validation) and record the new `table_name` for 3.6.

## Phase 2 — Item A wiring (contract before consumers)

- [ ] 2.1 `variables.tf`: add `git_data_betterstack_logs_token` (sensitive, no default) and
      `git_data_betterstack_ingest_url` (no default), mirroring the sibling description convention
      including the literal `No default (hr-tf-variable-no-operator-mint-default)`.
- [ ] 2.2 `git-data-luks.tf:132`: `value` → `var.git_data_betterstack_logs_token`. Keep
      `lifecycle { ignore_changes = [value] }`; do not rename the resource (R6 — the address is birth-target
      #20 and the fan-out must not move).
- [ ] 2.3 `git-data.tf:303-304`: point both module args at the new variables.
- [ ] 2.4 `rung2-rehearsal/variables.tf`: re-point the `betterstack_ingest_url` default and rewrite its
      comment, which currently justifies itself by pointing at `zot-registry.tf`.
- [ ] 2.5 `git-data-userdata-budget.sh`: update the stub ingest URL for accuracy.
- [ ] 2.6 `terraform validate` in both roots.

## Phase 3 — Item A gate + harness updates (D1: both roots ship to the new source)

- [ ] 3.1 Arm 7: extract prod's URL from git-data's new source of truth **by shape**, not from
      `zot-registry.tf` by name.
- [ ] 3.2 Arm 72: update the `value = var.…` regex for the renamed variable.
- [ ] 3.3 Arms 74/75: update variable names in both roots; keep the no-default assertions.
- [ ] 3.4 Arm 5.6a: reword the premise label to say both roots ship to the **git-data** sink; record the D1
      reasoning in the surrounding comment. **Do not touch the allowlist.**
- [ ] 3.5 Verify (do not assume) that the 12-member module-input pin at `:599-604` is unaffected.
- [ ] 3.6 `scripts/followthroughs/git-data-rung2-evidence-capture.sh`: query
      `t520508_<new_table_name>_logs`.
- [ ] 3.7 Confirm the suite still reports ≥ 75 cases, 0 failures.

## Phase 4 — Item B: metadata egress closure (the ForceNew, hash-invalidating change)

- [ ] 4.1 Add `nftables` to `packages:`.
- [ ] 4.2 Inline `write_files:` the nft script at `0755 root:root` (D2 — inline, **not** a 10th `file()`
      payload), modelled on `cloud-init-inngest.yml:55-101`: `command -v nft` preflight, then
      `nft -f - <<'NFTEOF'` declaring its own `table inet soleur_git_data` with
      `chain output { type filter hook output priority -10; policy accept; }` and two drops qualified by
      `meta skuid != 0` (IPv4 `169.254.169.254`, IPv6 `fe80::a9fe:a9fe`).
- [ ] 4.3 Inline the systemd unit at `0644 root:root`: `Type=oneshot`, `RemainAfterExit=yes`,
      `After=`/`Wants=network-online.target`, `WantedBy=multi-user.target`, and a `SyslogIdentifier`
      **without** the `.sh` suffix.
- [ ] 4.4 Add a `runcmd` item after the `gc_timer` block that enables the unit with rc capture and emits
      `stage:nftables_metadata` at **warning** on failure (D3 — outside the `set -e` region; never a bare
      `|| true`).
- [ ] 4.5 Re-run `git-data-userdata-budget.sh`. If headroom is insufficient, stop and re-shape before
      committing.
- [ ] 4.6 Record the **new** template sha256 for the PR body.

## Phase 5 — Item C: route the two warning stages

- [ ] 5.1 Add a `sentry_issue_alert` per D4: `fallthrough_type = "NoOne"`, `filter_match = "all"`, one
      `tagged_event` with `match = "IS_IN"` and value `betterstack_ingest,nftables_metadata`,
      `conditions_v2 = [{ first_seen_event = {} }]`, `lifecycle { ignore_changes = [environment] }`, and a
      `frequency` not already used (free: 6-9, 28-29, 31+).
- [ ] 5.2 Create `apps/web-platform/test/sentry-git-data-warning-stages-op-contract.test.ts` — the Guard 1
      reconciliation suite. Assert both directions (stage is a live `tagged_event` value **and** is
      actually emitted), anchored on the HCL attribute construct rather than a bare token, and cover the
      two inline `curl` mirrors as well as the emitter call sites.

## Phase 6 — Item D: stale-prose corrections in birth-critical artifacts

- [ ] 6.1 `plugins/soleur/test/terraform-target-parity.test.ts`: correct the
      `doppler_secret.git_data_ssh_host` comment — the tree reads `hcloud_server_network.git_data.ip`
      (`git-data.tf:274`), which is what ADR-149's DC-5 **reversal** mandates. Fix the now-backwards final
      sentence too, and sweep the same false "static local" claim in the `OPERATOR_APPLIED_EXCLUSIONS`
      comment.
- [ ] 6.2 `tests/scripts/lib/git-data-host-birth-gate.sh:411`: make the ABORT text say **three** entailed
      members, matching the loop at `:402-405`, **without changing the loop**. Sweep the same stale four at
      `:30` and `:52`. The PASS line at `:503` is already correct — use it as the model.

## Phase 7 — Records

- [ ] 7.1 Amend ADR-198, four parts: per-source token ADOPTED with the *reason* corrected (the provider gap
      is real at v0.21.14; the operator-mint claim is not); the `0600` concession gains its closure; the
      boot-refresh alternative retired with the once-per-instance finding; cross-host blast radius
      re-measured.
- [ ] 7.2 `model.c4`: correct the `betterstack` element description — two Logs sources now, git-data on its
      own. Run `c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 7.3 Amend `knowledge-base/project/learnings/workflow-patterns/2026-07-18-playwright-evaluate-filename-allowed-roots-and-token-transcript-fallback.md`
      to correct the Read-scoped claim (R2).
- [ ] 7.4 Comment on #7772 with three dispositions: Item E re-stated against the unchanged allowlist, the
      ADR-198 fourth-item triage-out plus its re-evaluation trigger, and the corrected Item A reasoning.

## Phase 8 — Verification and ship

- [ ] 8.1 Work through the plan's Acceptance Criteria 1-22 in order.
- [ ] 8.2 `bash scripts/test-all.sh` (TEST_GROUP=all), or report skipped-for-contention on rc=4 rather than
      forcing an untrustworthy run.
- [ ] 8.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own
      invocation, not a hand-enumerated path list).
- [ ] 8.4 PR body must state: the R4 correction (this **is** a template change, not a .tf firewall change),
      the old and new template sha256, `Closes #7772`, and that no rehearsal dispatch was fired.
- [ ] 8.5 Arm auto-merge; sync on BEHIND rather than hand-merging.

---

## Do NOT

- Do **not** create `apps/web-platform/infra/git-data-rung2-boot-evidence.env`.
- Do **not** dispatch `.github/workflows/git-data-rung2-rehearsal.yml` from this PR.
- Do **not** widen `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` (D1 makes it unnecessary; arm 5.6a refuses it).
- Do **not** add a 10th `file()` payload (D2).
- Do **not** change the 20-address birth fan-out (R6).
- Do **not** re-point `local.betterstack_logs_ingest_url` in `zot-registry.tf` — the web hosts and registry
  stay on source 2457081.
- Do **not** echo any credential value to stdout, a log, an artifact, or the diff.

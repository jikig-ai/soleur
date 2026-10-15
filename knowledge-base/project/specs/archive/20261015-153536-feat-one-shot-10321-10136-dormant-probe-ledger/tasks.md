# Tasks — fix-dormant-probe-ledger-10321-10136

Derived from `knowledge-base/project/plans/2026-10-15-fix-dormant-probe-ledger-10321-10136-plan.md`.
Constraints: no `hcloud_volume.git_data` edits, no `docs/legal/**` edits, no terraform apply,
no workflow_dispatch, no Doppler writes, do not reopen #7455. Watch overlap with open PRs
#10320 (betterstack-logs-alerts.tf/ADR-218/ADR-184/mutation-test), #10352 (ledger stores row),
#10356 (no file overlap).

## Phase 1 — Inngest raw-key fix (code)

- 1.1 `apps/web-platform/lib/inngest/list-runs.ts`: add module-private `hashSigningKey`
  (strip `signkey-[\w]+-` prefix, `sha256` over the hex-decoded remainder, re-prepend prefix;
  fail closed on non-hex), comment pinning parity to `node_modules/inngest/helpers/strings.js`;
  send `Bearer ${hashSigningKey(signingKey)}` on both fetch calls.
- 1.2 Create `apps/web-platform/test/lib/inngest-list-runs-signing-key.test.ts` (vitest, stubbed
  fetch): exact-digest assertion for a `signkey-prod-<64hex>` fixture, raw-key absence assertion,
  bare-hex and non-hex arms.
- 1.3 Run the new suite green; observe the raw-key mutation RED first.

## Phase 2 — Ledger wording reconciliation (data)

- 2.1 `scripts/encryption-posture-ledger.json` `connections[]` Inngest row only: rewrite
  `does_not_defend` (hashed bearer true post-fix with date; event payloads; step-output transport
  "not asserted on this link (#9139)"). Leave `exception.*` strings verbatim (history per #10326).
  Do not touch `stores[]`, `hcloud_volume.git_data`, or the two zot connection rows' exceptions.
- 2.2 `python3 scripts/lint-encryption-posture.py` green; `git diff origin/main...HEAD` on the file
  touches only that one row.

## Phase 3 — Standing credential-shape alert (infra)

- 3.1 `apps/web-platform/infra/betterstack-logs-alerts.tf`: append `local`, `logtail_exploration`,
  `logtail_exploration_alert` `registry_zot_log_credential_shape` at the logtail-section end —
  `SOLEUR_ZOT_LOG` envelope anchor on `local.vector_prd_source_id`, three disjuncts
  (unmasked `Authorization`, `dp.(pt|st|sa|ct).` + >=16-char run, `$2[aby]$`), paging semantics
  per `registry_store_not_luks`/`registry_clientip_not_rfc1918`.
- 3.2 `.github/workflows/apply-web-platform-infra.yml`: add both `-target=` lines (merge auto-applies
  via push trigger — intended; stated in plan §Apply path).
- 3.3 Create `apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh` (COPIES via
  `REGCREDSHAPE_TF`/`_WF` overrides; the 6-row Guard 1 matrix from the plan); register in
  `.github/workflows/infra-validation.yml`.
- 3.4 Bump the source-count assertion in
  `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` — RE-MEASURE the
  on-main value at write time (13 now; 14 after #10320; this PR makes it +1).
- 3.5 `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: standing-alarms
  row; create `knowledge-base/engineering/operations/runbooks/registry-zot-credential-shape-10321.md`
  (rotate-first rule, counts-only, three shape definitions).

## Phase 4 — Dormant-detector contract + audit (docs/scripts)

- 4.1 `scripts/followthroughs/zot-log-channel-7440.sh`: correct the "stays enrolled as a REGRESSION
  detector" header claim; name the alert as the standing check and the sweeper read-set bound.
- 4.2 `ADR-184`: dated amendment correcting the ~line-321 enrollment paragraph.
- 4.3 `followthrough-convention.md`: dormant-detector clause (closed tracker + 14-day lookback =
  probe dead; a check meant to outlive its tracker is a standing alert, ADR-218 pattern).
- 4.4 Re-run the audit enumeration (`gh issue view` over each probe's tracker); apply header status
  notes to `dashboard-cold-tiers-8978.sh`, `inngest-watchdog-functions-query-6407.sh`,
  `web2-standby-soak-6459.sh`, `cla-evidence-hardening-3950.sh`; delete
  `luks-monitor-host-timer-8706.{sh,test.sh}` per its `RETIREMENT:` line.
- 4.5 `ADR-218`: dated amendment (new managed alert, credential-shape signal class, the
  dormant-probe rule — re-derive the count at write time).

## Phase 5 — Residuals and close-out

- 5.1 PR body: `Closes #10321`, `Ref #10136` `Ref #7455` `Ref #7530` `Ref #9139`;
  `## Residuals on #10136` (TLS, nftables re-read [operator-gated], CLO 10-24 re-ruling, NFR-026,
  signing-key rotation, `/v1` reachability #9073); `## Sequencing` (#10320/#10352/#10356).
- 5.2 Post-merge: comment on #10136 recording scope done/residual (no close);
  `gh issue edit 8706 --remove-label follow-through` + retirement comment; read the next
  sweeper run log; confirm `terraform plan` shows only the two new logtail resources pending
  (the push-apply creates them at merge — verify the run, don't trigger it).

## Gates

- `bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh` green.
- `vitest`/`bun test` on the new list-runs suite green.
- `python3 scripts/lint-encryption-posture.py`, `lint-guard-contract.py <plan>`,
  `lint-shell-trace-credential-refusal.py` (touched shells), `lint-orphan-test-suites.sh`,
  `check-adr-ordinals.sh`, `npx markdownlint-cli2` on touched markdown — all green.
- Repo-wide ratchets per the work skill's file-selected-set warning.

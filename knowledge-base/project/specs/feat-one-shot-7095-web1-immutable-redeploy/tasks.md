---
plan: knowledge-base/project/plans/2026-08-01-fix-web1-credential-delivery-channel-dark-plan.md
issue: 7095
followup_issue: 7103
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: pending
---

# Tasks — restore the web-1 credential delivery channel

Derived from the plan **after** Revisions R1–R5. Read the plan's `## Revisions applied after review`
and `## Execution Order` before starting: the draft's Phase 3 was **cut** and must not be
re-introduced, and the phases do not execute in their authored order.

**Standing constraint:** this must not become a third code patch. Nothing under
`apps/web-platform/infra/**` is edited (AC6). The infra code on `main` is already correct via #7097 —
it has never arrived.

**Standing constraint:** every prod write in Phases 1 and 2 needs its own explicit per-command
go-ahead (`hr-menu-option-ack-not-prod-write-auth`). Plan approval is not write approval, and
approval of Phase 1 does not extend to Phase 2.

---

## Phase 0 — Preconditions (read-only; no writes)

- [x] 0.1 Pull `https://app.soleur.ai/health`; record `version`, `build_sha`, `uptime`, `supabase`.
      **Stop** if `version` ≥ `0.247.0` — prod recovered by another path and this plan is stale.
- [ ] 0.2 Re-run the H6 control triad (probe A ssh + ci_ssh creds; probe B ssh + bogus secret;
      probe C deploy + deploy creds). All three outcomes must reproduce.
      **Stop** if probe C now fails — the webhook channel has also gone dark and the blast radius has changed.
- [ ] 0.3 Re-verify `cx33` (`server_type id 115`) stock via the Hetzner `/v1/datacenters` endpoint.
      Record availability; do **not** switch to a host `-replace` even if stock returns.
- [ ] 0.4 Run `scripts/check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN` locally and
      record the verdict. This is the same check Phase 4.1 wires into the bridge — confirm its
      three-valued exit contract (0/1/2) before depending on it.
- [x] 0.5 Read the last 6 `scheduled-terraform-drift.yml` runs and confirm the `dead` verdict history
      (runs `30686984837`, `30653453432`, `30608371251` are the cited evidence). Attach to the PR body.
- [ ] 0.6 Confirm `secrets.DOPPLER_TOKEN_WRITE` is present and `doppler_write_check.skip_sync != 'true'`,
      or the existing sync step — the sole republish path after R1 — silently no-ops.
- [ ] 0.7 Determine which Doppler config the sync step writes (`prd` root vs `prd_terraform` branch).
      The detector's remedy line says *"Set the live value on the 'prd' ROOT config; branch configs
      inherit it."* Resolve this before Phase 1, not after.
- [x] 0.8 Confirm no bridge-consuming workflow is mid-run (`git-data-cutover`,
      `workspaces-luks-cutover`, `workspaces-luks-verify`) — they share the `ci_ssh` credential.

## Phase 1 — Re-mint the `ci_ssh` Access token

- [x] 1.1 **Resolve the open P0 first:** no workflow arm can run an arbitrary `-replace`. Add a narrow
      `ci-ssh-token-replace` arm to `apply-web-platform-infra.yml`'s `apply_target` enum, with a
      typo-guard `confirm` token, reusing the existing non-SSH `-target` allow-list plus
      `-replace=cloudflare_zero_trust_access_service_token.ci_ssh`. Do **not** add a general
      `-replace` input; the dispatch-input budget is near its 10-input cap.
- [ ] 1.2 Verify by reading the plan output that the `-target` set drags in no `terraform_data`,
      `hcloud_*`, or `tls_private_key` node. (`-target` is transitive on **dependencies**.)
- [ ] 1.3 Dispatch. Confirm the existing `Sync CF Access CI-SSH service token to Doppler` step ran and
      wrote both keys — with `-target` runs it can no-op and `exit 0` (`"Falling back to operator sync"`).
- [ ] 1.4 **Halt gate (AC10).** Assert Access **admits** the new credential — `verdict: clean`.
      A positive assertion only; a 502/timeout/DNS failure is **not** a pass.
      If it still denies, H6 was wrong: **stop and re-diagnose. Do not proceed.**
- [ ] 1.5 Assert exactly one `github-actions-ci-ssh` service token exists at Cloudflare — if
      `create_before_destroy`'s destroy leg failed, an orphaned root-SSH token is still live.

## Phase 2 — Land the already-merged #7097 payload

- [ ] 2.1 Re-dispatch `apply-deploy-pipeline-fix.yml`. Both `terraform_data` resources are absent from
      state (destroyed by run `30650564509`), so both are created.
- [ ] 2.2 Require `infra-config-gate.sh`'s per-file sha256 content assert to pass on its own terms.
      **A content mismatch is terminal — do not retry it away.**
- [ ] 2.3 If it fails again, the route forward is an explicit
      `-replace=terraform_data.infra_config_handler_bootstrap` or a nonce bump in
      `push-infra-config.sh` — a plain re-run does **not** fix it.

## Phase 3 — CUT

- [ ] 3.1 **Do not implement.** Confirm no `doppler_secret` for any Cloudflare Access token was
      created (AC17). See plan §Revision R1 for why: the `.deploy` half would have published a dead
      secret over the live one and left zero write paths to an unreplaceable host.

## Phase 4 — Make the existing verdict block, and reach a human

- [x] 4.1 Add one step to `.github/actions/cf-tunnel-ssh-bridge/action.yml` (after the forward opens,
      after `::add-mask::`): `bash scripts/check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN`.
      Fail with terminal reason `ci_ssh_access_denied` on exit 1. One edit, six callers (AC5d).
- [x] 4.2 Add `action-required` issue creation/update on verdict `dead` to
      `scheduled-terraform-drift.yml`, alongside the existing email, carrying the detector's remedy
      line (AC5e). Email alone failed three times over three days.
- [x] 4.3 Leave `apply-web-platform-infra.yml`'s existing presence gate intact — its `absent → skip`
      arm is a correct first-bootstrap accommodation. (Verified untouched; it was done-but-unchecked.)
- [x] 4.4 Probe hygiene: creds via `env:` at the gate step (NOT end-to-end — the detector
      passes them to curl as `-H` argv; comment corrected to say so); no `-v`/`-i`/`--trace*`/
      `set -x`; annotations carry the enum + counts only, never the response body.
      **`--max-redirs 0` is NOT present** and was claimed here in error — the detector's two
      curl calls carry only `--max-time 20`. The intent holds by construction (curl does not
      follow redirects without `-L`, and T18 pins that a 302 does not grade LIVE), so this is
      a corrected claim, not new work.
- [x] 4.5 Extend the **existing** `scripts/check-cloudflare-token-drift.test.sh` (already registered
      in `scripts/test-all.sh`). Do **not** create a new suite. Fixtures synthesized, never captured
      live (`cq-test-fixtures-synthesized-only`).

## Phase 4b — Make the credential take effect

- [ ] 4b.1 `systemctl try-restart inngest-heartbeat.service vector.service` — **vector last**
      (restarting it blinks the telemetry stream used to verify the outcome).
- [ ] 4b.2 Assert `systemctl show vector.service -p DropInPaths` contains the new drop-in path and
      `ExecMainStartTimestamp` is later than the Phase 2 apply (AC16). This is what distinguishes
      *delivered* from *active*.

## Phase 5 — Prove recovery

- [ ] 5.1 Choose and record the deploy mechanism. Recommended: `gh workflow run
      web-platform-release.yml -f bump_type=patch` (mints a new patch and rebuilds; it bypasses the
      CI gate by design, so dispatch only once CI is green on `main`). File a follow-up issue for a
      `deploy-web-image.yml` that can redeploy an **existing** tag — its absence is why a
      already-built, already-signed image sat unreachable for three days.
- [ ] 5.2 Poll `/health` with the **Monitor** tool (never `run_in_background`) until AC14's full
      predicate holds: `version >= 0.247.0` **and** `uptime < 900` **and** `supabase == "connected"`.
- [ ] 5.3 Assert per-`ci-deploy`-invocation (not per wall-clock window): no
      `Doppler Error: Invalid Auth token` across the next 3 invocations (AC12); the next run emits the
      post-#7097 honest message and neither legacy string (AC13).
- [ ] 5.4 Re-run the drift detector; require `verdict: clean` (AC10 closure).
- [ ] 5.5 `gh issue close 7095` **only after 5.2 passes**. PR body uses `Ref #7095`, never `Closes`.
- [ ] 5.6 Comment on #7103 with the two new ledger items: (a) CI-side credential liveness belongs in
      B2's probe, not only host-side; (b) `.deploy`'s Terraform state value is **stale/dead** and any
      future untargeted output-sync republishes it over the working one — needs its own PR
      enumerating all three holders (Doppler, `secrets.CF_ACCESS_CLIENT_*` GitHub Actions repo
      secrets, operator-env consumers).

## Phase 6 — Records

- [x] 6.1 Write ADR-154 (ordinal verified free on freshly-fetched `origin/main`; `/ship` re-verifies).
      Three propositions only — zero-stock ⟹ `-replace` unavailable; a detector firing into an unread
      channel has not detected anything; probe the transport before the destroy. The draft's
      propositions on the "copy invariant" and `ignore_changes` are **cut** (see plan §ADR).
- [x] 6.2 C4: read all three `.c4` files in full before concluding impact. Enumerate external actors,
      external systems (is **Cloudflare Access** modelled distinctly from Cloudflare Tunnel? this
      incident turned on their separability), data stores, and changed access relationships.
      A bare "no C4 impact" is a reject condition.
- [x] 6.3 File the two deferrals as issues with re-evaluation criteria: `deploy-web-image.yml`, and
      the `cpx`-family host-type migration for the `cx33` stock constraint.
      **Done as a consolidated comment on #7103, not as two new issues.** #7103 is literally the
      "#7095 follow-ups" tracker, so two fresh issues would be net +2 backlog for one incident
      against a tracker that already exists for it (the `/work` net-issue-flow gate). The comment
      adds them as B6 and B7 with re-evaluation criteria, plus two addenda (B2 is host-side only
      and would not have caught this CI-side credential; `.deploy` is a live landmine in state),
      and reconciles an ordinal collision — #7103's B5 had reserved ADR-154 for the copy
      invariant, which plan review cut from this ADR.
- [ ] 6.4 Capture the learning: *a plan's diagnosis of "why nobody noticed" deserves the same
      evidentiary standard as its diagnosis of "what broke" — this draft measured the outage
      correctly and asserted the monitoring gap from imagination, and the remedy built on that
      assertion would have caused a worse outage.*

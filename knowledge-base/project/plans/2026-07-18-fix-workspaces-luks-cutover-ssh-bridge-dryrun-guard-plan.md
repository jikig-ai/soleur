---
title: "fix: workspaces-luks cutover SSH bridge skipped on dry-run path"
type: fix
date: 2026-07-18
branch: feat-one-shot-cutover-ssh-bridge-dryrun-guard
lane: single-domain
issue: 6649
epic: 6604
adr: ADR-119
brand_survival_threshold: none
---

# 🐛 fix: `CF Tunnel SSH bridge` skipped on the workspaces-luks dry-run path (blocks the #6649 rehearsal)

## Overview

The first-ever dry-run of the `/workspaces` LUKS header-escrow cutover (workflow run
`29644526137`, #6649) failed with `ssh: connect to host 10.0.1.10 port 22: Connection timed out`
(exit 255) **before** `apps/web-platform/infra/workspaces-cutover.sh` ever ran.

Root cause is a single mis-copied step guard in
`.github/workflows/workspaces-luks-cutover.yml`. The `CF Tunnel SSH bridge` step is guarded:

```yaml
- name: CF Tunnel SSH bridge
  # Needed for any host-touching run: a real cutover OR a rollback recovery.
  if: ${{ !inputs.dry_run || inputs.rollback }}
```

That expression evaluates **false** in exactly one case — `dry_run=true, rollback=false`, the
rehearsal case — so the bridge is skipped. But the very next step, `Run workspaces-luks cutover`,
is **unconditional** and always pipes the script to web-1 over SSH:

```yaml
${WEB_HOST_SSH:-ssh} "$WEB_HOST" "sudo DRY_RUN='${DRY_RUN}' ROLLBACK='${ROLLBACK}' bash -s" \
  < "${INFRA_DIR}/workspaces-cutover.sh"      # WEB_HOST=10.0.1.10 (private IP)
```

`10.0.1.10` is a private-net address reachable **only** through the bridge's `iptables -t nat OUTPUT
REDIRECT SERVER_IP:22 → 127.0.0.1:2222` over the Cloudflare Tunnel (the runner's egress IP is not —
and by design cannot be — in the host firewall allowlist; see
`.github/actions/cf-tunnel-ssh-bridge/action.yml`). With the bridge skipped there is no NAT/route to
`10.0.1.10:22`, so the connect times out (exit 255) at L3, before any authentication.

Independently, `workspaces-cutover.sh` runs `ensure_aws` → `load_escrow_creds` → `escrow_probe`
**host-side, OUTSIDE the `DRY_RUN != 1` gate BY DESIGN** (script lines 274–280; OPERATOR NOTE lines
83–84). This is the #6649 design: the escrow probe-PUT and the negative over-scope probe run in
BOTH arms so a GREEN escrow signal lands during the rehearsal, before any irreversible freeze. So a
`dry_run=true` invocation is genuinely host-touching and **requires** the bridge — the exact
opposite of what the guard assumes.

### Why the guard is wrong here but correct in the sibling

The workflow header says it "Mirrors `git-data-cutover.yml`", and that sibling carries the
byte-identical guard `if: ${{ !inputs.dry_run || inputs.rollback }}` on its own bridge step
(`git-data-cutover.yml:112`). There the guard is **correct**, because the two workflows have
different SSH topologies:

| | git-data-cutover.yml | workspaces-luks-cutover.yml |
|---|---|---|
| Where SSH happens | **inside** the script (`git-data-cutover.sh` calls `${WEB_HOST_SSH:-ssh}` per step) | **in the workflow step** (`… ssh "$WEB_HOST" … < cutover.sh`) |
| Dry-run host contact | none — every step short-circuits under `DRY_RUN=1` *before* any ssh (`git-data-cutover.sh:198,214,231,290,330,374,421`) | **yes** — the run step always SSHes, and `escrow_probe` runs before the `DRY_RUN` gate |
| Bridge needed on dry-run? | No → guard correctly skips it | **Yes** → guard wrongly skips it |

The guard was copied verbatim from the mirror without accounting for the different SSH pattern (and
for the #6649 escrow probe that deliberately runs in the dry-run arm). **This fix is
workspaces-specific; `git-data-cutover.yml` must NOT be changed** — its guard is correct for its
topology.

### The fix

Remove the `if: ${{ !inputs.dry_run || inputs.rollback }}` line from the workspaces-luks `CF Tunnel
SSH bridge` step so it runs on **every** invocation (dry-run, real cutover, rollback), and update
the step's leading comment to state that the dry-run is host-touching. Removing the guard is a
strict **superset** of the prior behaviour: the bridge already ran for `dry_run=false` and for
`rollback=true`; the only newly-covered case is the rehearsal (`dry_run=true, rollback=false`) that
was broken. No cutover/rollback path loses the bridge.

This is a workflow-YAML-only change. It does not touch `workspaces-cutover.sh` logic, the
already-provisioned R2 escrow creds (`WORKSPACES_HEADER_R2_ACCESS_KEY_ID` /
`WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY` in `prd_workspaces_luks`, verified present, wired by
#6650), or the #6604 cutover epic issue.

## User-Brand Impact

**If this lands broken, the user experiences:** the #6649 escrow dry-run rehearsal keeps failing at
`ssh … Connection timed out` (exit 255) before `cutover.sh` runs, so the operator cannot rehearse
the header-escrow path and the #6604 cutover epic stays blocked. (The dry-run does **not** freeze,
wipe, or repoint anything — those steps stay `DRY_RUN`-gated — so a broken landing costs a blocked
rehearsal, never user data.)

**If this leaks, the user's data is exposed via:** no new exposure vector. The change only removes a
step guard; the bridge already ran on the real-cutover and rollback paths with the same creds and
same tunnel. No secret, argv, env, or data-handling surface changes.

**Brand-survival threshold:** `none`.
`threshold: none, reason:` this diff removes one `if:` guard so an existing step runs in one
additional (rehearsal) case; it is a strict superset of prior bridge behaviour, opens no destructive
path (freeze/rsync/repoint/wipe remain `DRY_RUN != 1`-gated in `workspaces-cutover.sh`), and changes
no credential/data-exposure surface. This bullet is present because the touched file
(`*luks*cutover*.yml`) may match preflight Check 6's sensitive-path regex.

## Hypotheses

The feature description matches the SSH/`timeout` network-outage trigger, so per
`hr-ssh-diagnosis-verify-firewall` the L3→L7 layers are addressed before any service-layer
hypothesis. The diagnosis is already conclusive from run `29644526137` and is an **L3-reachability**
cause, not sshd/service:

1. **L3 — private-net routing / NAT bridge absent (CONFIRMED, root cause).** `WEB_HOST=10.0.1.10`
   is reachable only via the bridge's `iptables -t nat OUTPUT REDIRECT …:22 → 127.0.0.1:2222` over
   the CF Tunnel (`.github/actions/cf-tunnel-ssh-bridge/action.yml`). The guard skipped the bridge
   on the dry-run, so no NAT/route existed. The observed error is `connect … port 22: Connection
   timed out` (exit 255) — a **connect-time timeout**, the signature of a missing route/NAT, NOT an
   auth/`kex`/handshake failure (which would implicate sshd/keys). Verification artifact: the run
   `29644526137` step log + the workflow diff showing the bridge step evaluated to `if: false`.
2. **L3 — firewall allow-list drift (N/A, with artifact).** The classic admin-IP-drift hypothesis
   does not apply: the runner's egress IP is *deliberately not* in `var.admin_ips` (the action
   header states the 5000+ rotating GH-runner IPs cannot be allowlisted); reach is *only* via the
   tunnel bridge. So there is no firewall entry to drift — the bridge presence, not the allowlist,
   is the reachability control.
3. **L3 — DNS/routing to a public host (N/A).** `10.0.1.10` is a private RFC-1918 address, not
   DNS-resolved; there is no public route to verify.
4. **L7 — sshd config / fail2ban / service drift (REJECTED).** Rejected by hypothesis 1's artifact:
   a connect-time *timeout* means the packet never reached sshd. sshd/fail2ban would surface as a
   reset/handshake/auth error, not a timeout. No sshd change is proposed.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Codebase reality (verified) | Plan response |
|---|---|---|
| Bridge guarded `if: ${{ !inputs.dry_run \|\| inputs.rollback }}`; only skips dry_run=true | Confirmed — `.github/workflows/workspaces-luks-cutover.yml:86` | Remove the guard (Phase 1) |
| Run step always pipes `cutover.sh` to web-1 over SSH; WEB_HOST=10.0.1.10 | Confirmed — same file lines 94–111 (unconditional step, `< cutover.sh`) | No change (correct as-is) |
| `escrow_probe()` runs host-side OUTSIDE the DRY_RUN gate by design | Confirmed — `workspaces-cutover.sh:274–280` (probe before the `DRY_RUN != 1` gate at :282); OPERATOR NOTE :83–84 | Do NOT modify the script (in scope of guard: bridge only) |
| No sentinel/test pins the old `if:` | Confirmed — see "Sentinel / Test Sweep" below | No test update required |
| R2 creds already provisioned in `prd_workspaces_luks` | Confirmed present (#6650), and `workspaces-luks-header.test.sh` H4/H12 assert the wiring | No creds work; do not touch |
| Mirrors `git-data-cutover.yml` (same guard) | Confirmed — `git-data-cutover.yml:112` has identical guard, but its dry-run is host-free (in-script per-step `DRY_RUN=1` short-circuits) | Leave `git-data-cutover.yml` UNCHANGED — its guard is correct for its topology |

### Sentinel / Test Sweep (verify-before-ship)

Every file that reads `.github/workflows/workspaces-luks-cutover.yml` or asserts on its steps was
checked; **none pins the bridge step's `if:` condition**, so no test needs updating:

- `apps/web-platform/infra/workspaces-luks-header.test.sh` — reads the YAML only in **H7**
  (`p_creds_not_in_workflow`: escrow creds absent from workflow argv/env). It `strip_comments` the
  file first (`:128`), so a YAML `#` comment cannot affect it, and it greps only for cred tokens —
  removing the `if:` line and editing the comment leave H7 unchanged. No `if:`/`dry_run`/bridge
  assertion exists anywhere in H1–H12 or S6–S9.
- `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` — asserts only
  `group: web-1-swap` + `cancel-in-progress: false` on the freeze workflow (`:113,:118`). Does not
  read the bridge step.
- `apps/web-platform/infra/workspaces-luks.test.sh` — no reference to the freeze YAML (A11 cardinality
  guard is on `workspaces-luks.tf`).
- `tests/scripts/test-workspaces-luks-cutover-gate.sh` + `tests/scripts/lib/workspaces-luks-cutover-gate.sh`
  — guard the `apply-web-platform-infra.yml` `-target` set for the +create apply_target; no
  reference to the freeze YAML or its bridge step.

**Comment-wording guard (belt-and-suspenders):** the replacement comment must avoid the literal
tokens `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `WORKSPACES_HEADER_R2_ACCESS_KEY_ID`,
`WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY`, `WORKSPACES_HEADER_BUCKET` (H7's forbidden set). H7
strips comments before matching so a `#`-prefixed line is safe regardless, but keeping the wording
token-free removes any doubt.

## Files to Edit

- `.github/workflows/workspaces-luks-cutover.yml` — remove the `if: ${{ !inputs.dry_run ||
  inputs.rollback }}` line from the `CF Tunnel SSH bridge` step (line 86); rewrite the step's
  leading comment (line 85) to state the bridge runs on every invocation because the run step always
  SSHes to web-1 and the escrow probe runs on web-1 in the dry-run arm.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open issue whose body references
`.github/workflows/workspaces-luks-cutover.yml`.

## Implementation Phases

### Phase 1 — Remove the dry-run guard + fix the comment (the only phase)

In `.github/workflows/workspaces-luks-cutover.yml`, change the `CF Tunnel SSH bridge` step from:

```yaml
      - name: CF Tunnel SSH bridge
        # Needed for any host-touching run: a real cutover OR a rollback recovery.
        if: ${{ !inputs.dry_run || inputs.rollback }}
        uses: ./.github/actions/cf-tunnel-ssh-bridge
```

to (guard line deleted; comment rewritten):

```yaml
      - name: CF Tunnel SSH bridge
        # Runs on EVERY invocation (dry-run, real cutover, rollback): the "Run workspaces-luks
        # cutover" step below always pipes the script to web-1 (private 10.0.1.10) over SSH, and the
        # escrow probe runs on web-1 in the dry-run arm too (before the DRY_RUN freeze gate), so a
        # GREEN escrow signal lands during the #6649 rehearsal. A dry-run is host-touching; skipping
        # the bridge here timed out ssh at connect (exit 255) — run 29644526137.
        uses: ./.github/actions/cf-tunnel-ssh-bridge
```

No other step changes. With the `if:` removed, the step uses the default implicit `if: success()`,
so it still runs only after the preceding `Verify required secrets present` step succeeds — correct.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — the `CF Tunnel SSH bridge` step in `.github/workflows/workspaces-luks-cutover.yml` no
  longer carries `if: ${{ !inputs.dry_run || inputs.rollback }}`. Verify:
  `awk '/name: CF Tunnel SSH bridge/{f=1} f&&/uses:/{print;exit} f' .github/workflows/workspaces-luks-cutover.yml`
  shows the step reaching `uses:` with **no** intervening `if:` line, and
  `grep -c 'if: ${{ !inputs.dry_run || inputs.rollback }}' .github/workflows/workspaces-luks-cutover.yml`
  returns `0`.
- [ ] AC2 — the step's leading comment states the bridge runs on every invocation / the dry-run is
  host-touching (contains `EVERY invocation` and references the escrow probe or `29644526137`).
- [ ] AC3 — the `Run workspaces-luks cutover` step is unchanged (still unconditional; still
  `< "${INFRA_DIR}/workspaces-cutover.sh"`).
- [ ] AC4 — `git-data-cutover.yml` is **unchanged**: `git diff --name-only origin/main` lists only
  `.github/workflows/workspaces-luks-cutover.yml` and this plan/spec artifact set (no
  `git-data-cutover.yml`, no `workspaces-cutover.sh`, no `*.tf`).
- [ ] AC5 — `workspaces-cutover.sh` is unchanged (the escrow probe / DRY_RUN gate logic is out of
  scope): `git diff --name-only origin/main | grep -c workspaces-cutover.sh` returns `0`.
- [ ] AC6 — `bash apps/web-platform/infra/workspaces-luks-header.test.sh` passes (H7 and all others
  still green — the comment/guard edit does not perturb the cred-in-workflow assertion).
- [ ] AC7 — `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` passes (concurrency
  invariants intact).
- [ ] AC8 — the workflow YAML still parses: `actionlint .github/workflows/workspaces-luks-cutover.yml`
  is clean (or, if actionlint is unavailable, `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/workspaces-luks-cutover.yml` exits 0). Do NOT use `bash -n` on a workflow file.
- [ ] AC9 — PR body uses `Ref #6649` (NOT `Closes #6649`): closure is gated on a green
  `dry_run=true` re-run performed after merge, per the task scope. The #6604 epic issue is not
  referenced for closure.

### Post-merge (verification, no operator SSH)

- [ ] AC10 — re-dispatch the rehearsal and confirm it now reaches the host:
  `gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=true`
  then `gh run watch <id>` / `gh run view <id>` — the run must progress past the `CF Tunnel SSH
  bridge` and into `Run workspaces-luks cutover` (no `Connection timed out` / exit 255 at the SSH
  step). A GREEN escrow probe (`escrow probe OK …`) in the step log confirms #6649 is satisfied.
  This AC is the trigger for closing #6649; it is performed by whoever runs the rehearsal after
  merge, not baked into this PR.

## Test Scenarios

| # | Invocation | Old behaviour | New behaviour |
|---|---|---|---|
| T1 | `dry_run=true, rollback=false` (the rehearsal) | bridge skipped → ssh exit 255 (BUG) | bridge runs → reaches web-1 → escrow probe GREEN |
| T2 | `dry_run=false` (real cutover) | bridge runs | bridge runs (unchanged) |
| T3 | `rollback=true` | bridge runs | bridge runs (unchanged) |
| T4 | `dry_run=true, rollback=true` | bridge runs | bridge runs (unchanged) |

The fix changes only T1; T2–T4 are a strict superset-preserving no-op. No test row loses the bridge.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change (a single CI-workflow step guard removal). No user-facing surface —
`## Files to Edit` contains no `components/**`, `app/**/page.tsx`, or other UI-surface path, so the
Product/UX gate does not fire (mechanical UI-surface override: no match). No new data model, auth
flow, pricing, or content surface.

## Infrastructure (IaC)

Not applicable — no new infrastructure. This change removes one `if:` guard on an existing workflow
step; it provisions no server, secret, service, vendor, DNS record, or firewall rule. The R2 escrow
creds and the encrypted volume were provisioned earlier (#6650 / the `apply_target=workspaces-luks-cutover`
apply). No Terraform files change. Phase 2.8 IaC routing gate: skipped (no operator-provisioning
phrases introduced).

## Observability

The change surfaces *more* signal than before rather than adding a new failure surface — the
existing, already-instrumented dry-run path now actually runs.

```yaml
liveness_signal:
  what: the workspaces-luks-cutover.yml workflow-run conclusion (dry-run rehearsal)
  cadence: on-demand (workflow_dispatch); the #6649 rehearsal + the daily luks-monitor probe
  alert_target: GitHub Actions run status; escrow-probe emit_drift → Sentry (feature=workspaces-luks)
  configured_in: .github/workflows/workspaces-luks-cutover.yml + workspaces-cutover.sh escrow_probe()
error_reporting:
  destination: Sentry op=workspaces-luks-drift (escrow_probe_put_failed / escrow_creds_overscoped /
    escrow_probe_readback_failed / escrow_negprobe_inconclusive) + the step's ::error:: annotation
  fail_loud: yes — escrow_probe die's fail-closed; the run step re-emits rc via ::error:: (existing)
failure_modes:
  - mode: bridge cannot establish (tunnel/token failure)
    detection: the CF Tunnel SSH bridge step fails in the Actions run log
    alert_route: GitHub Actions run conclusion = failure
  - mode: ssh still times out after the fix (unexpected)
    detection: "Run workspaces-luks cutover" step ::error:: with exit 255 in the run log
    alert_route: GitHub Actions run conclusion = failure
  - mode: escrow path unusable during the rehearsal (the #6649 false-green this enables catching)
    detection: escrow_probe die → emit_drift → Sentry event (feature=workspaces-luks)
    alert_route: Sentry op=workspaces-luks-drift
logs:
  where: GitHub Actions run log + $GITHUB_STEP_SUMMARY (Cutover summary step) + Sentry
  retention: GitHub Actions default; Sentry per project retention
discoverability_test:
  command: "gh run view <run-id> --log | grep -E 'CF Tunnel|escrow probe OK|timed out'"
  expected_output: "post-fix: the bridge + 'escrow probe OK' lines appear; no 'timed out'"
```

The discoverability test uses `gh run view` only — no SSH is required to observe the outcome
(`hr-no-ssh-fallback-in-runbooks`).

## Architecture Decision (ADR/C4)

Not applicable — no architectural decision. This is an implementation-defect fix (a mis-copied step
guard) that brings the workflow into line with the already-recorded ADR-119 design: the #6649
escrow probe running in both arms is documented in `workspaces-cutover.sh` and asserted by
`workspaces-luks-header.test.sh` (H8). A competent engineer reading ADR-119 + the existing tests
would not be misled by this fix. No external actor, external system, container, or access
relationship changes, so no `.c4` model edit is needed. Phase 2.10 gate: skipped.

## GDPR / Compliance

Not applicable — no regulated-data surface is touched (no schema, migration, auth flow, API route,
or `.sql`). The change alters CI-workflow step gating only; it introduces no new processing
activity, no new LLM/external-API call on user data, and no new distribution surface. Phase 2.7
gate: skipped.

## Deepen-Plan Enhancements (2026-07-18)

### Precedent-Diff — how sibling CF-Tunnel-SSH-bridge workflows guard the bridge step

`git grep` of every workflow that uses `./.github/actions/cf-tunnel-ssh-bridge` shows the fix
(unconditional bridge) matches the dominant precedent — a host-touching step runs the bridge with no
dry-run guard:

| Workflow | Bridge-step guard | Relevance |
|---|---|---|
| **`workspaces-luks-verify.yml`** | **none (unconditional)** | Closest sibling — same #6604 epic, same web-1 host, read-only host-touching. Direct precedent for the fix. |
| `apply-deploy-pipeline-fix.yml` | none (unconditional) | Host-touching apply; bridge always runs. |
| `apply-web-platform-infra.yml` | `if: steps.ssh_token_gate.outputs.ssh_apply_skip != 'true'` | Gated by an SSH-token-availability gate, NOT by `dry_run`. Different, apply-specific condition. |
| `git-data-cutover.yml` | `if: ${{ !inputs.dry_run \|\| inputs.rollback }}` | The **only** workflow with the dry-run guard — and it is **correct** there (in-script per-step `DRY_RUN=1` short-circuits before any ssh → dry-run is host-free). |
| `workspaces-luks-cutover.yml` (this fix) | `if: ${{ !inputs.dry_run \|\| inputs.rollback }}` → **removed** | Aligns with the verify-sibling precedent; its dry-run IS host-touching. |

Conclusion: removing the guard is the well-precedented shape (matches `workspaces-luks-verify.yml`
verbatim — no `if:`), not a novel one. The `git-data-cutover.yml` guard is left untouched.

### Deepen hard-gate results

- **4.5 Network-Outage deep-dive (SSH/timeout trigger):** the `## Hypotheses` section verifies
  L3→L7 in order with artifacts. Root cause is L3 (missing NAT/tunnel to `10.0.1.10`), confirmed by
  the connect-time *timeout* signature (not a handshake/auth error) in run `29644526137`. Firewall
  allow-list is N/A with artifact (runner egress IP is deliberately not allowlisted; reach is
  bridge-only per the action header). No sshd/service hypothesis is proposed. `hr-ssh-diagnosis-verify-firewall` satisfied.
- **4.55 Downtime & Cutover:** not triggered — this diff does not reboot/replace a host, take a DB
  lock, or restart a serving connector. The dry-run it enables is non-destructive (freeze/rsync/
  repoint/wipe stay `DRY_RUN != 1`-gated in `workspaces-cutover.sh`).
- **4.6 User-Brand Impact halt:** section present; threshold `none` with a scope-out reason bullet.
  (The touched path `workspaces-luks-cutover.yml` does not match the preflight sensitive-path regex —
  none of its `.github/workflows/…(doppler|secret|token|deploy|release|…)` tokens appear — so the
  scope-out bullet is defensive, not required.)
- **4.7 Observability gate:** all 5 schema fields present, non-placeholder; `discoverability_test.command`
  uses `gh run view` (no SSH).
- **4.8 PAT-shaped variable halt:** no `var.*_token` / `TF_VAR_(GITHUB|GH)_*` / literal `ghp_` /
  `github_pat_` references. Pass.
- **4.9 UI-wireframe halt:** not triggered — no UI-surface file in Files to Edit.

## Sharp Edges

- **Do NOT "fix" `git-data-cutover.yml` too.** Its identical guard is *correct* for its topology
  (in-script per-step `DRY_RUN=1` short-circuits → dry-run never SSHes). Changing it would run the
  bridge on a git-data dry-run for no reason. The fix is workspaces-specific.
- **Do NOT make the `Run workspaces-luks cutover` step conditional and do NOT gate the escrow probe
  behind `DRY_RUN`.** The escrow probe running in the dry-run arm is the #6649 design (it kills the
  false-green where a green dry-run hides an unusable escrow). Gating it would reintroduce the exact
  bug #6649 fixed and would be caught by `workspaces-luks-header.test.sh` H8.
- **Keep the replacement comment free of H7's cred tokens** (`AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`, `WORKSPACES_HEADER_R2_ACCESS_KEY_ID`,
  `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY`, `WORKSPACES_HEADER_BUCKET`). H7 strips comments before
  matching so it is safe regardless, but avoid the tokens for zero ambiguity.
- **`Ref #6649`, not `Closes #6649`.** Closure is gated on the post-merge green `dry_run=true`
  re-run (AC10). Auto-closing at merge would produce a false-resolved state before the rehearsal is
  proven green.
- **A plain step with no `if:` inherits `if: success()`**, so the bridge still runs only after the
  secret-verification step passes — do not add an explicit `if: always()` (that would try to bridge
  even when secrets are missing).

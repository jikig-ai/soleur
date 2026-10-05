# Tasks — fix(registry): zot's 60s HTTP deadlines cut large-layer blob uploads

Derived from
[`knowledge-base/project/plans/2026-08-13-fix-zot-mirror-large-layer-upload-timeout-plan.md`](../../plans/2026-08-13-fix-zot-mirror-large-layer-upload-timeout-plan.md)
after 5-agent plan review. Read the plan's `## Measured Diagnosis` before starting — the cause is
established and must not be re-derived.

**Lane:** cross-domain (fail-closed default; no spec.md). **Threshold:** single-user incident.

---

## Phase 0 — Setup

- [x] 0.1 File the distinct tracker issue: *"P1: releases blocked at the zot mirror — large-layer
      blob uploads are cut at zot's 60 s HTTP deadline"*. Labels `priority/p1-high`, `type/bug`,
      `domain/engineering`. Record its number as `<new-issue>` = **#7555**.
- [x] 0.2 File a **second, dedicated** follow-through tracker (`<tracker>` = **#7556**), label `follow-through`.
      It must NOT be `<new-issue>` — the PR closes that one and `sweep-followthroughs.sh` lists
      `--state open`, so a probe hosted there would never run.
- [x] 0.3 Comment on #7341 with the two refutations (stale `100% full`; `zot_restarts=0` across 48 h).
      Do **not** close it; do **not** touch `scripts/followthroughs/zot-fill-rate-7341.sh`.
- [x] 0.4 Push an `ADR-190` stub early to claim the ordinal. Re-verify across **all** `origin/*` refs
      first — ADR-187 is already double-claimed on two branches.

## Phase 1 — Make the copy arm diagnose itself (no host replace)

- [x] 1.1 **RED:** add a test asserting `degraded()` emits the upload-ceiling pointer for `copy_v`.
      Confirm it fails against current `main`.
- [x] 1.2 Retarget `degraded()`'s trailing telemetry pointer in
      `.github/workflows/reusable-release.yml` to branch on `$reason`. `copy_*`/`verify` → upload
      evidence; `bridge`/`crane_install` → host health. Anchor: the line beginning
      `Registry-host health (disk AND zot_restarts/exit_code`.
      **Do not** add a stage parameter to `zot_mirror_diagnosis()` — the copy path never calls it.
- [x] 1.3 Repair the bridge arm's read (anchor: the comment beginning `# BOOT-SCOPED.`): require all
      three `BETTERSTACK_QUERY_*` values; treat an error payload as a failed read.
- [x] 1.4 Sweep the three `zot_mirror_diagnosis` **invocation** sites — one in `reusable-release.yml`,
      **two** in `.github/actions/cf-tunnel-registry-bridge/action.yml`. Derive the set with
      `grep -rn 'zot_mirror_diagnosis' --include=*.yml --include=*.sh`.
- [x] 1.5 Add `# MEASURED-BY:` markers to any new causal sentence; confirm
      `bash scripts/lint-diagnosis-claims.sh` passes with its `.highwater` baseline unchanged.
- [x] 1.6 Guard 1 mutation matrix rows 1-5 + harness H1: apply each, observe RED/PASS, revert.
- [x] 1.7 Correct the stale *"pulls fall through to GHCR"* comment in
      `apps/web-platform/infra/variables.tf` (false since #7071).

## Phase 2 — Raise the deadline and keep the paired evidence (ONE host replace)

Everything in this phase lands in one merge — it is one `user_data` ForceNew replace of the fleet's
sole pull path.

- [x] 2.1 **RED first:** write the rendered-config guard (Guard 3) and confirm it fails against the
      current config, which has no timeout keys.
- [x] 2.2 Set BOTH `"readTimeout": "1800s"` and `"writeTimeout": "1800s"` in the `"http"` block of
      `apps/web-platform/infra/cloud-init-registry.yml` (anchor `"compat": ["docker2s2"]`).
      **Never one without the other** — Arm C yields a zot-side `202` with no response to the client.
- [x] 2.3 Add the `#7282`-house-style comment: what was measured (the Arm A/B/C table), the `gcDelay`
      upper bound, and *re-measure on every zot bump, never re-word*.
- [x] 2.4 Widen `JQ_TICK` to carry `statusCode` and `path`, appended **after** `zmsg`, and widen the
      `read -r` in the **same edit**. A mismatch folds fields into `zmsg` and prefix-matching keeps
      returning 0 — green over a corrupted record.
- [x] 2.5 Add `is_upload_failure_evidence "$zstatus" "$zpath"` as a sibling predicate at the single
      call site (`if is_cap_exempt "$zmsg" || …`). Match the `/blobs/uploads/` **pairing**, not all
      5xx — a broad 5xx arm starves crash traces in the shared 17-slot exempt lane.
      Do **not** change `is_cap_exempt()`'s signature.
- [x] 2.6 Guard 2 mutation matrix rows 1-7 + harness H1: apply each, observe RED/PASS, revert.
- [x] 2.7 Guard 3 mutation matrix rows 1-6 + harness H1, including the typo'd-key negative control.
- [x] 2.8 Update the shadow reader `scripts/followthroughs/zot-log-channel-7440.sh` (and its pin
      `tests/scripts/test-zot-log-channel-probe.sh`) — or record in-file why it stays four-class.
- [x] 2.9 `bash apps/web-platform/infra/registry-userdata-budget.sh --json` — confirm `stored_bytes`
      under `cap` with headroom above the ADR-185 floor.
- [x] 2.10 `bash apps/web-platform/infra/zot-log-shipper.test.sh` passes with its `>= 150` floor and
      `CANARY_OK` canary **intact** — do not lower the floor.

## Phase 3 — Build the dispatcher

- [x] 3.1 Create `.github/workflows/registry-host-replace-dispatch.yml`, modelled on
      `inngest-watchdog-restart-dispatch.yml` / `registry-zot-inventory-dispatch.yml`.
- [x] 3.2 Pre-check pull-path health via `scripts/registry-pull-path-health.sh` before firing.
      Firing blind is the #6400 hazard — a degraded fallback turned a registry outage into a total
      deploy outage.
- [x] 3.3 Fire `apply-web-platform-infra.yml` with `apply_target=registry-host-replace` and a `reason`
      naming the merge commit; source the ack token rather than requiring it typed.
- [x] 3.4 Fail loudly on a red pre-check; file nothing silently.
- [x] 3.5 Test the pre-check against a synthesized red reading (T7).
- [x] 3.6 `actionlint` the new workflow. Do **not** run `actionlint` against the composite action.

## Phase 4 — Record and enrol

- [x] 4.1 Write `ADR-190-zot-http-deadlines-sized-to-largest-layer.md`. Cite ADR-166 for the
      message-honesty half rather than restating it. Status `adopting` until the soak passes.
      State the ADR-167 relationship (this measurement fires its re-open trigger); do not decide it.
- [x] 4.2 Write `scripts/followthroughs/zot-upload-ceiling-<tracker>.sh` with the numeric exit
      contract from the plan's Observability block: `0` PASS (≥7 d window, ≥12 samples on the newest
      `boot_id`, both deadlines `1800000000000`, zero `i/o timeout` pairings), `1` FAIL, `2`
      TRANSIENT with a distinct `reason=`. `${VAR:?msg}` is banned.
- [x] 4.3 Add the `<!-- soleur:followthrough script=… earliest=<replace+7d> secrets=… -->` directive
      to `<tracker>`. Confirm those secrets are already wired in
      `.github/workflows/scheduled-followthrough-sweeper.yml` — do not re-add.
- [x] 4.4 C4: read all three `.c4` files in full against the plan's enumeration. Expected outcome is
      no edit — the change alters a property of an existing edge, not the graph.

## Phase 5 — Verification

- [x] 5.1 Walk every pre-merge AC (1-18) and record its command + output.
- [x] 5.2 `python3 scripts/lint-guard-contract.py <plan path>` (path-scoped).
- [x] 5.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [x] 5.4 `grep -rn '<new-issue>\|<tracker>'` over the diff returns nothing.
- [x] 5.5 Re-verify the ADR ordinal across all `origin/*` refs immediately before merge; on any
      renumber, sweep the plan, this file, and every AC naming it.
- [ ] 5.6 PR body: `Closes #<new-issue>` and `Ref #7341`; **not** `Closes #7341`.

## Phase 6 — Post-merge (dispatcher-driven, no human step)

- [ ] 6.1 Confirm the dispatcher fired and the replace run concluded successfully.
- [ ] 6.2 Query Better Stack for zot's boot `configuration settings` line; confirm both deadlines
      read `1800000000000` ns.
- [ ] 6.3 Confirm the follow-through probe is enrolled and its first sweep reports a verdict.
- [ ] 6.4 Note: the release that fires on merge runs against the **un-replaced** host and is
      explicitly not evidence for or against this change.

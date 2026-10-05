# Tasks — feat-one-shot-d10-health-url-derivation

Derived from
[`knowledge-base/project/plans/2026-08-06-fix-registry-luks-recut-d10-health-url-derivation-plan.md`](../../plans/2026-08-06-fix-registry-luks-recut-d10-health-url-derivation-plan.md)
(v3, post six-reviewer panel).

`lane: cross-domain` · `brand_survival_threshold: single-user incident`

**Read the plan's `## Sharp Edges` before starting.** Three of them are the difference
between a working fix and a silently broken one: the `export X=$(cmd)` exit-status
swallow, the byte-fragile mutation anchor, and the merge-commit kill switch.

---

## Phase 0 — Preconditions

- [x] 0.1 Confirm `apps/web-platform/infra/variables.tf` still declares `app_domain_base`
      with a default, and that `server.tf` and `tunnel.tf` still consume it.
- [x] 0.2 Confirm `TF_VAR_app_domain_base` / `APP_DOMAIN_BASE` is still absent from
      Doppler `prd_terraform`. If present, it is the value Terraform applied and the
      script's override tier must return it.
- [x] 0.3 Record the current hash of `scripts/registry-pull-path-health.sh`. It must be
      byte-identical at the end (AC5 compares against this hash, not a moving
      `origin/main` tip).
- [x] 0.4 Establish the baseline green:
      `bash tests/scripts/test-registry-pull-path-health.sh` (verified 60/0 at plan time)
      and `bash tests/scripts/test-registry-gate-mutation-battery.sh`.
- [x] 0.5 Complete the plan's `## Reversible Mitigation` conclusion — confirm the volume-grow
      path is still blocked by the state drift described, and record the finding.

## Phase 1 — RED: derivation unit suite

- [x] 1.1 Create `scripts/derive-app-domain-base.test.sh` (failing). Placement under
      `scripts/*.test.sh` is deliberate — `scripts/lint-orphan-test-suites.sh` globs it
      and mechanically requires registration.
- [x] 1.2 Implement rows T1–T12 from the plan's Test Scenarios, including the four
      separate malformed-shape cases and the CWD-independence case.
- [x] 1.3 Confirm the suite fails for the right reason (no script yet), not a harness fault.

## Phase 2 — GREEN: `scripts/derive-app-domain-base.sh`

- [x] 2.1 Resolve the `variables.tf` path independently of CWD (script location or
      `git rev-parse --show-toplevel`, with a `$GITHUB_WORKSPACE` override and `$1`).
- [x] 2.2 Read the `TF_VAR_app_domain_base` override first; fall back to the committed
      default. This is what makes the source "what Terraform applied" rather than "what
      Terraform would apply absent an override".
- [x] 2.3 Parse with the `read_default` awk idiom, **anchored on the variable name plus
      its opening brace**. Do **not** trust the pipeline's exit status — it ends in
      `head`/`sed` and exits 0 even when the variable is absent; test for emptiness.
- [x] 2.4 Shape-guard: must contain a dot; no scheme, slash, or whitespace; must not
      begin with `app.`. A malformed value must be fatal, never passed into a URL.
- [x] 2.5 stdout carries only the base; diagnostics and the machine-greppable resolution
      line go to stderr; non-zero exit with `::error::` naming the file and variable.
- [x] 2.6 Use `local x; x=$(cmd) || x=""` throughout — never `local x=$(cmd)`.
- [x] 2.7 Suite green.

## Phase 3 — Rewire both D10 arms

- [x] 3.1 In the `Derive restore inventory (D10 PREPARE)` step, replace the Doppler block
      with a **bare assignment** from the script, a `-z` guard, and `export` on its own
      line. Never `export APP_DOMAIN_BASE=$(…)`.
- [x] 3.2 Same in the `Pre-destroy authorization gate (D10 VERDICT)` step.
- [x] 3.3 Delete `DOPPLER_TOKEN_PRD` — the whole `env:` block in PREPARE (it holds nothing
      else), and only that line in VERDICT (`DOPPLER_TOKEN`, `REHEARSE_TARGET`, and the
      `ZOT_PUSH_*` entries stay).
- [x] 3.4 Replace the false `is a DOPPLER SECRET` comment with one or two sentences
      naming only what was measured. Keep it short — long prose is what forced the
      comment-stripping harness.
- [x] 3.5 Confirm both bodies still open with `set -euo pipefail` (without it the bare
      assignment does not propagate the script's failure).

## Phase 4 — Convert the restore leg's dark read

- [x] 4.1 In `.github/actions/cf-tunnel-registry-bridge/action.yml`, replace the
      `2>/dev/null || echo "soleur.ai"` read with the shared derivation. This runs inside
      `registry_store_restore` — the recut's own refill leg.
- [x] 4.2 Keep it non-fatal at this site: the leg runs *after* the destroy, so a new hard
      abort would strand an empty registry.
- [x] 4.3 Do **not** touch `cf-tunnel-ssh-bridge` or the web-host birth/replace sites —
      deferred to D4.

## Phase 5 — Workflow-wiring suite

- [x] 5.1 Create `tests/scripts/test-registry-d10-workflow-wiring.sh`, modelled on
      `test-preapply-entrypoint-gate.sh` (`_workflow_code()`, `_gate_step_body()`).
      Separate file — never append to `test-registry-pull-path-health.sh`, whose sandbox
      has no `.github/` directory.
- [x] 5.2 Vacuity floor first: assert both step bodies extract non-empty.
- [x] 5.3 Implement W1–W7 as a loop over both bodies. Strip comments before every
      assertion.
- [x] 5.4 Scope the residual-zero sweep (W4) over the workflow **and**
      `.github/actions/**/action.yml`, with a commented allowlist entry for the
      deferred `cf-tunnel-ssh-bridge`.

## Phase 6 — Register both suites

- [x] 6.1 Add `run_suite` lines in `scripts/test-all.sh` inside `if want_scripts; then` —
      nothing auto-discovers `tests/scripts/test-*.sh`.
- [x] 6.2 Place the wiring suite next to its D10 siblings with the same orphan-trap comment.
- [x] 6.3 `bash scripts/lint-orphan-test-suites.sh` exits 0.

## Phase 7 — Runbook corrections

- [x] 7.1 Repoint the `registry-pull-path-health: A0 ABORT` row. Name the measured cause
      (the HTTP read), not the derivation — pointing an operator whose `/health` did not
      answer at `variables.tf` would itself violate ADR-166.
- [x] 7.2 Add a live-input line to cold-vehicle check 1, plus an assertion that
      `TF_VAR_app_domain_base` is absent.
- [x] 7.3 Record both live blockers in the residual-blockers section, and fix the
      pre-existing self-contradiction there (`#7309` marked RESOLVED two lines above a
      "This is the live blocker" sentence).
- [x] 7.4 State the reversible-mitigation finding so a fixed gate does not read as an
      endorsement of firing the recut.

## Phase 8 — ADR work

- [x] 8.1 Amend `ADR-096` cold-vehicle item 3 to name the real provenance chain and record
      that the secret it named never existed. Cite the `cf-tunnel-registry-bridge` comment,
      which already stated the true fact.
- [x] 8.2 Amend `ADR-169` — extend its independence criterion from components to
      authorizing inputs. Amend regardless of whether it mentions Doppler sourcing; it also
      does not model the PREPARE/VERDICT split.
- [x] 8.3 Do **not** cite ADR-164 as the parent (category error) and do **not** mint a new ADR.
- [x] 8.4 Do NOT fold the `validation` block in — D3 stays deferred with a corrected
      rationale (see the plan's D3). The script's shape guard covers the consumption point.

## Phase 9 — Deferrals, tracker, and merge procedure

- [x] 9.0 **Merge procedure — do not lose this.** The workflow lists its own path in
      `on.push.paths`, so merging fires a production `terraform apply`. The merge commit
      message must contain `[skip-web-platform-apply]` on its own line. Verify the
      `apply:` job reports skipped.
- [x] 9.1 File D1 (live Doppler-name sweep + the `ADR-007` convention, together).
- [x] 9.2 File D4 with the re-enumerated grep (8 remaining instances, plus the
      no-fallback read in `plugins/soleur/skills/ship/SKILL.md`).
- [x] 9.3 File D5 — link `#7316` from `#6929` and the runbook as the recut's second
      precondition (`REGISTRY_LUKS_KEY`).
- [x] 9.4 D6 tracker corrections: relabel `#6929` `priority/p3-low`→`priority/p1-high`,
      `type/chore`→`type/bug`; move `#7287` and `#7340` from Post-MVP / Later into Phase 4.
- [x] 9.5 File D7 — the brand-survival ladder inversion (declaring the higher tier drops
      both sign-off gates).
- [x] 9.6 Verify every label with `gh label list --limit 200` before use.

## Exit

- [x] All Acceptance Criteria AC1–AC12 met (AC13 is explicitly post-merge).
- [x] `bash scripts/test-all.sh scripts` exits 0.
- [x] Mutation battery exits **0**, not 2 (2 = harness fault, no verdict).
- [x] PR body cross-references `#7098` without claiming to close it, and does not imply
      the incident is remediated.

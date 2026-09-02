---
title: "fix: migrate sentry_issue_alert -> sentry_alert off the deprecated alert-rule API (#7650)"
issue: 7650
type: fix
classification: infrastructure-iac
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-08-25
---

# Migrate off the deprecated alert-rule API (#7650)

## Decision headline

The blocker that deferred this since May has lifted, and the migration is **25 + 4**, not 29.

`sentry_alert` is the `workflows/` replacement. Its `monitor_ids` requirement — the #4610
blocker — is now satisfiable: `sentry_project_error_monitor` and
`sentry_project_issue_stream_monitor` data sources exist and are documented by the provider
for exactly this binding. They are present in **0.15.4**, so no bump is required to unblock.

What is NOT yet established is whether a **pure-frequency** rule fires faithfully once bound
to a default monitor. That is a semantic change to live paging under a single-user-incident
threshold, so it is Phase 0 and it gates everything else.

## The 29 resources, classified

Derived by parsing `issue-alerts.tf`, not from memory. Regenerate with the classifier in
Phase 0.1.

| Group | N | Disposition |
|---|---|---|
| Lifecycle-triggered (`first_seen_event` / `regression_event` / `reappeared_event` / high-priority) | 16 | Expected to bind cleanly to a default monitor |
| **Pure-frequency**, no lifecycle trigger | 9 | **Fidelity risk — Phase 0 gates these** |
| `auth_*` with `conditions_v2 = []` | 4 | **Cannot be migrated by Terraform alone** |

Pure-frequency set: `sandbox_startup_failure` (`event_unique_user_frequency`),
`zot_mirror_fallback_rate`, `web_terminal_boot_fatal`, `git_data_boot_fatal`,
`web_private_nic_boot_gate`, `workspaces_luks_drift`, `local_cache_reload_rate`,
`seccomp_remediation_failed`, `gh_pages_cert_reissue_failed`.

### Why the four `auth_*` rules are a separate problem

`auth_exchange_code_burst`, `auth_callback_no_code_burst`, `auth_per_user_loop`,
`auth_signout_burst` declare `conditions_v2/filters_v2/actions_v2` as `[]` and carry
`ignore_changes = [conditions_v2, filters_v2, actions_v2, environment, frequency]`.
**Terraform does not own their configuration.** `configure-sentry-alerts.sh` is their only
executable definition, and that script's WRITE path against `workflows/` has no known shape
(#7634). Migrating their Terraform blocks would move an empty shell and leave the real
definitions stranded against a dying endpoint.

Do not attempt these four until #7634 resolves the write shape. A file-level grep for
`ignore_changes` cannot tell this set apart from the other 25 — resolve per resource block.

## Phase 0 — COMPLETE (2026-08-26): PASS

Evidence: `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase0-fidelity-evidence.md`

The risk did not materialise, and the question was answerable by reading rather than by
building a scratch experiment: **Sentry has already migrated all 29 rules server-side**,
so `rules/` and `workflows/` are two views of the same objects and the faithful
translation already exists, authored by the vendor.

- **All 30 workflows bind to the same detector** `1213799` (`issue_stream`) — lifecycle,
  pure-frequency, and Sentry's own default alike. `monitor_ids` is therefore not a
  semantic differentiator, and binding a pure-frequency rule to the issue-stream monitor
  is exactly what Sentry does. The 9 pure-frequency rules need no special handling.
- **Frequency is a first-class trigger type**, not an action filter: 11
  `event_frequency_count` + 2 `event_unique_user_frequency_count` in `triggers.conditions`,
  while `actionFilters` carry `tagged_event` and nothing else (65/65). **This refutes the
  translation mapping in Phase 2.1 below, which is corrected accordingly.**
- The four `auth-*` rules' live definitions are now readable from the API rather than only
  from `configure-sentry-alerts.sh`. This does not unblock #7634 (a WRITE-shape problem)
  but removes the reverse-engineering step from verifying a future migration.

Consequence for the shape of the work: this is **closer to an import than a re-creation**.
The target objects already exist with correct semantics; the task is getting Terraform to
manage them. Materially lower risk than this plan originally assumed.

<details><summary>Original Phase 0 steps, kept as the dated record of what was planned</summary>

## Phase 0 (as planned) — fidelity measurement

- [ ] **0.1** Regenerate the classification from `issue-alerts.tf` and commit the classifier
      so the counts above are reproducible rather than asserted.
- [ ] **0.2** In a **scratch Sentry project** (never prod), create one `sentry_alert` bound via
      `data.sentry_project_issue_stream_monitor` carrying a single `event_frequency` action
      filter equivalent to `zot_mirror_fallback_rate`.
- [ ] **0.3** Drive synthetic events and record **when it fires** versus the existing
      `sentry_issue_alert` with the same threshold. The question is not "does it fire" but
      "does it fire on the same events, at the same threshold, with the same window".
- [ ] **0.4** Decide per group:
      - fires faithfully -> proceed to Phase 1 for all 25
      - fires differently -> the 9 pure-frequency rules stay on `sentry_issue_alert`, and
        #7650 closes only for the 16, with the remainder re-scoped to a follow-up
- [ ] **0.5** Record the measurement in the spec as a dated artifact with the probe commands,
      so the next reader can re-run it rather than trust it.

**Do not accept a clean `terraform plan` as evidence here.** That is what produced the
retracted 2026-07-17 finding: a plan run outside a brownout window is consistent with both
"it works" and "we sampled the wrong moment".

</details>

## Phase 1 — destroy-guard extension (BEFORE any sentry_alert enters a plan)

- [ ] **1.1** Extend `tests/scripts/lib/destroy-guard-filter-sentry.jq` with a
      `select(.type == "sentry_alert")` clause counting nested-block shrink across
      `action_filters[].conditions[]`, `action_filters[].actions[]`, `trigger_conditions[]`.
- [ ] **1.2** Allow `sentry_alert` in `test-destroy-guard-sentry-scope-guard.sh`.
- [ ] **1.3** Add a fixture to `test-destroy-guard-counter-sentry.sh` and **mutation-prove**
      it: remove a nested block, confirm the guard reds and names it.

ADR-031's sharp edge: the filter counts nested-block shrink per-type with no `walk()`, so a
new type has its shrink counted as **0** and slips the guard silently. This must land before,
not with, the migration.

## Phase 2 — translate and import (16 resources, NOT 25)

> **Re-scoped 2026-09-02.** The provider cannot express a frequency TRIGGER. Importing one
> routes it through `legacy_trigger_conditions` (List of String), which discards the
> `comparison`, and the next apply rewrites it as the boolean `true` — destroying the
> threshold and interval on a live paging rule. Measured in the provider source at v0.15.5;
> see `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-provider-cannot-express-frequency-triggers.md`.
>
> **No guard can catch this, including Phase 1's.** The destroyed value lives only
> server-side and never appears in the `.tf`, so `terraform plan` shows no diff to count.
> Invisible to the destroy gate by construction.
>
> In scope: the **16 lifecycle-triggered** rules (`first_seen_event` / `reappeared_event` /
> `regression_event`), whose trigger comparisons are already `true` and round-trip
> losslessly. Out of scope until the provider gains frequency-trigger support: the 13
> frequency-triggered rules, which stay on `sentry_issue_alert`. Never import Sentry's own
> default workflow.

- [ ] **2.1** Translate, per the mapping MEASURED in Phase 0 (this corrects the mapping
      originally written here, which sent frequency conditions to `action_filters` — a
      place Sentry never puts them):
      - lifecycle conditions (`first_seen_event` / `reappeared_event` / `regression_event`)
        -> `trigger_conditions`, `logic_type = any-short`
      - **frequency conditions: NOT MIGRATABLE at v0.15.5.** The API carries them as
        triggers; the provider models them only under `action_filters[].conditions` and
        cannot represent a frequency *trigger* at all. An earlier revision of this line
        sent them to `trigger_conditions`, which is wrong for the provider — corrected
        twice now, so state the source: provider docs + `resource_alert_impl.go` at the
        pinned tag, not the API shape and not this plan's prose.
      - `tagged_event` / `level` filters -> `action_filters[].conditions` — measured to be
        the only condition type Sentry puts there
      - `filter_match` -> `action_filters[].logic_type`
      - `actions_v2` + `frequency` -> `action_filters[].actions` + `frequency_minutes`
      - `monitor_ids` -> the issue-stream default monitor, uniformly. Measured: all 30
        live workflows bind to `1213799`; do not branch this per rule class.
- [ ] **2.2** **Preserve every `name` byte-for-byte.** `assert-byok-rules-exist.sh`'s
      `EXPECTED_RULES` and operator dashboard queries both key on names.
- [ ] **2.3** State surgery via a one-time `workflow_dispatch` (never SSH): `state rm` then
      `import`. `state rm` is refresh-free and therefore survives a brownout; `removed {}`
      blocks are likely DOA because a refresh hits the 410.
- [ ] **2.4** Sequence the surgery BEFORE the merge that lands the `sentry_alert` blocks, or
      the post-merge full-root apply creates duplicates.

## Phase 3 — verification

- [ ] **3.1** `terraform plan` full-root no-op (0/0/0) across all types.
- [ ] **3.2** `assert-byok-rules-exist.sh` still lists all four `EXPECTED_RULES` by name,
      enabled, post-apply.
- [ ] **3.3** Confirm the brownout retry from PR #7693 is now **unreachable** for migrated
      resources — no `sentry_issue_alert.` in a failing plan means the conjunct cannot arm.
- [ ] **3.4** Remove the retry only once **zero** `sentry_issue_alert` resources remain, and
      not before. While the 4 `auth_*` rules remain, the retry is still load-bearing.

## Observability

Added after review found this block missing, which is the root cause of everything it
found: without it nobody was forced to name the layer, and the retry shipped
marker-only. `SOLEUR_*` is a host-journald convention — every source in
`apps/web-platform/infra/vector.toml` is scoped to the Hetzner host's
`SYSLOG_IDENTIFIER` — and these markers are emitted on a GitHub-hosted runner whose
stdout no Vector source ships. **An `::error::` annotation and a marker in an Actions
log are detail lines inside a signal, not a signal.** That correction was already made
once on this same workflow (2026-07-17 sentry-iac delete-path plan); this plan
reintroduced it and is corrected here.

| Field | Value |
|---|---|
| `failure_modes` | (1) brownout absorbed by the retry — previously a red required check, now a green run; (2) brownout wider than the retry budget, or the family fully retired — `outcome=exhausted`; (3) the migration changes when a pure-frequency rule fires |
| `detection` | (1)+(2) `scripts/followthroughs/sentry-brownout-frequency-7650.sh` on the existing daily sweeper, reading run logs from OUTSIDE the workflow it observes; (3) Phase 0 measurement against a scratch project, before any prod change |
| `alert_route` | (2) sweeper marks the follow-through FAIL and comments on #7650 — a real channel, unlike the marker. (1) is counted, not paged: the retry is absorbing it and a threshold picked without data would be a number invented to look rigorous |
| `layer` | GitHub Actions run logs, reached via `gh run view --log` by an external prober. Explicitly NOT layers 1-7: no Vector source ships GitHub-runner stdout |
| `discoverability_test.command` | `GH_TOKEN=$GH_TOKEN bash scripts/followthroughs/sentry-brownout-frequency-7650.sh` |

Before the retry, `gh run list --json conclusion` WAS the frequency meter (measured: 89
success / 3 failure / 8 cancelled over 100 runs). The retry greens the runs that clear
on attempt 2-3, decaying that counter toward zero. The probe above is what keeps the
count from disappearing, and it is why `outcome=cleared` is emitted at all — without it
the log shows "we retried" and never "it worked", so a resolved brownout and one still
in progress are indistinguishable.

## Sharp edges

- **A clean plan is not evidence of vendor state.** See the retracted 2026-07-17 finding and
  ADR-031 §Amendment 2026-08-19.
- **`ignore_changes` inverts ownership.** Resolve per resource block; the file holds two
  disjoint sets and `grep -l` collapses them.
- **The destroy guard is `.tf ∪ state`-scoped.** A new nested-block type slips it silently.
- **`0.15.5` does not move `sentry_issue_alert` off `rules/`.** Verified in source at the tag,
  not in release notes. Do not re-derive this from a changelog.
- **The retry has a shelf life.** When the family is fully retired it exhausts and fails,
  which is correct. Raising the attempt count is not a response to that.

Refs #7650. Refs #7634. Refs #4610.

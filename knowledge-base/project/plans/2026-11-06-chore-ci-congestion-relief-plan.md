---
title: "chore: CI congestion relief — small-guard consolidation (lever 3), merge-queue param ruling (lever 1), oracle-lane activation deferral (lever 2)"
date: 2026-11-06
slug: chore-ci-congestion-relief
branch: feat-one-shot-12089-congestion-relief
issue: 12089
closes: 12089
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# chore: CI congestion relief — guard consolidation + queue-param ruling + oracle-lane sequencing

Tracker #12089 (`ci-wallclock-p90: required-check wall-clock report`, epic #11556 Lever E)
reported 15 bound breaches on 2026-11-06 — all wait-time, not work (`p90` ≫ `p90_dur`
everywhere; `test` dur=4s vs p90=3848s on `pull_request`, p90=3241s on `merge_group`).
Three levers were prescribed from the dispatch-run-42231989547 table: merge-queue
batching (lever 1), oracle-lane activation (lever 2), small-guard consolidation
(lever 3). This plan implements lever 3, records an evidence-based ruling that lever 1's
prescribed mechanism was already rejected by a six-day-old CTO ruling (re-scoped to a
no-change plus a measured deferral), and sequences lever 2's activation as the separate
authorized PR the runbook and ruling T1 require.

## Research Insights

**Relevant file paths.**

- `infra/github/ruleset-ci-required.tf:356-364` — the `merge_queue {}` block (7 explicit params; comments at 320-355 carry the rollback recipe and the wait=0 rationale).
- `scripts/create-ci-required-ruleset.sh:113-123` — DR skeleton `merge_queue` rule (byte-parity with the .tf via Guard-2 T-mq-1).
- `infra/github/README.md:106-114` — params table (third parity member) + kill-switch recipe at 151-181.
- `tests/scripts/test-audit-ruleset-bypass.sh` — Guard-2/T-mq-*: seven-param three-way parity + `max_entries_to_merge ∈ {1,3}` sanctioned pin (m9 mutates to unsanctioned value).
- `scripts/ci-oracle-lane.sh:73` — `readonly ORACLE_LANE_LOCKED=1` activation lock; `scripts/ci-oracle-lane.test.sh` — the sentinel; `scripts/ci-oracle-lane-suites.txt` — validation manifest.
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` §Activation — the authorized sequence (var arm → would_skip audit → lock-removal PR → ADR-276 dated line).
- `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` — Decision 3(a) (no required context renamed/removed/left pending/skipped-green), Decision 2 (merge_group is the full-battery authority), oracle-lane amendment 2026-11-05.
- `knowledge-base/engineering/architecture/decisions/ADR-032-*.md` §Negative/Sharp-Edges — job-name contract: renames require a paired Terraform edit in the same PR.
- `knowledge-base/engineering/architecture/decisions/ADR-270-*.md` + `## Addendum 2026-10-31 (#11678)` + `## Addendum 2026-11-01` — raise checklist, "Merge limits do not combine merge_group builds", and the grouped-candidate canary (members=3 observed on one candidate build).
- `knowledge-base/project/brainstorms/archive/20261031-173135-2026-10-31-merge-queue-batching-queue-jump-brainstorm.md` — prior CTO rulings on the exact param set (min=1/wait=0/ALLGREEN/max_build=2).
- `scripts/required-checks.txt` — required synthetic names SSOT (drives `bot-pr-with-synthetic-checks` CHECK_NAMES; #6049 auto-fabrication guard).
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — ruleset context SSOT (all `integration_id: 15368`); parity-pinned to required-checks.txt by `plugins/soleur/test/required-checks-canonical-parity.test.sh`.
- `scripts/required-check-wallclock-bounds.tsv` + `scripts/watch-wallclock-p90-11774.sh` + `.github/workflows/wallclock-p90-watch.yml` — the instrument of record; population derives from required-checks.txt; a bound row with no required-checks.txt row warns "stale bound".
- `scripts/probe-merge-group-coverage.sh` + `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` — proves every required context reports on `merge_group`.
- `.github/workflows/ci.yml` — guard jobs at lines 591 (credential-path-guard), 608 (lint-bot-statuses, already-folded precedent), 838 (encryption-posture), 871 (marketplace-manifest-guard), 893 (service-role-allowlist-gate), 914 (tc-document-sha-guard), 940 (adr-ordinals), 963 (rule-body-lint), 1004 (lockfile-sync), 1114 (sandbox-canary-capture-gate), 1162 (plugin-root-propagation-gate), 1226 (lint-webplat), 1951 (grok-fidelity), 2034 (harness-discovery), 517 (affected-index-ratchet).
- `.github/workflows/pr-quality-guards.yml` — 15+ jobs incl. required `enforce` (587), `markdown-lint` (470), `Bash fixture tests for guard scripts` (94), `dependency-review` (502), `skill-security-scan PR gate` (712); advisory `Block *` family (113-468) + `constraint-gates` (928) + `auto-close-scan` (972) + `detect` (44).
- `.github/workflows/secret-scan.yml` — required `gitleaks scan` (118), `lint fixture content` (290), `waiver discipline` (356), `rename-guard` (422), `allowlist-diff` (463); advisory smoke (513, 586). **Sensitive-path token `secret` in filename → preflight Check 6 fires.**
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — derives CHECK_NAMES from required-checks.txt; Phase-4 ceiling already reproduces `credential-path-literals`, `gitleaks scan`, `lint fixture content` over bot diffs.
- `.github/workflows/merge-queue-cla-synthetics.yml` + `scripts/merge-queue-cla-verify.sh` — precedent that API-posted check_runs satisfy required contexts on merge_group (CLA contexts only).

**Institutional learnings applied.**

- `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` — a required context with no merge_group producer pends the entry forever (the June-30 deadlock class).
- `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` — pins must name the property, not the shape.
- `2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md` (ADR-176) — mechanism-minimality: compare against machinery already on main before inventing.
- ADR-032 §Negative — job-name fragility is the *documented* contract: renames + paired TF edit in the same PR are contemplated, not forbidden.

**Premise Validation (Phase 0.6).** Checked: #12089 OPEN (weekly-rewritten tracker, 15 breaches this window); #10865 OPEN (observation window for the advisory ratchet; oracle evidence attaches here per runbook); all cited files exist on `origin/main`; `CI_ORACLE_LANE` confirmed `value: "on"` (armed 2026-11-06T14:30:42Z by parent agent — operator row O2 done); collision precheck — only draft PR #12250 (this pipeline) names #12089, no PRs name #10865, one unrelated `test-all.sh` process in the `feat-one-shot-10390-residual-chores` worktree (no file overlap). ADR corpus grepped for the proposed mechanisms: lever-1 batching hits ADR-270's raise-checklist surface AND a directly-on-point 2026-10-31 brainstorm with CTO rulings (see Reconciliation); lever-3 composite-job mechanism (Checks-API check_run posting) exists in-repo as an accepted pattern (CLA synthetics, bot synthetics) but only for *synthetic* greens, never for real guard verdicts on fork heads. **Stale premise found: the lever-1 mechanism as briefed.**

**Property List (Phase 0.6b).** (P1) Reduce wall-clock p90 of required contexts on pull_request and merge_group surfaces toward the epic goal (PR ≤1200s, MQ ≤900s). (P2) Free hosted-runner concurrency slots consumed by ~20-30 small guard jobs per run. (P3) Activate the oracle lane only on the blocking would_skip audit (ruling T1). **Cut List:** no proposed mechanism buys a property an existing mechanism already covers — but lever 1's prescribed param raise buys P1 via "shared merge_group builds", which the 2026-11-01 canary shows GitHub already performs opportunistically at `min_entries_to_merge=1` (members=3 shared one candidate build), so the param mechanism as briefed is cut; the queue-side demand knob it was reaching for is re-expressed as the `max_entries_to_build ↓` candidate deferred to measurement.

**Value-Proposition Measurement (Phase 0.6c).** Claimed saving: ~25 runner slots/run. Measured census (this session, `grep`/`gh`): required small guards = 8 in ci.yml + 5 in pr-quality-guards.yml + 5 in secret-scan.yml = 18; advisory small jobs ≈ 8-10 more (lint-bot-statuses[13 steps], detect-changes, harness-discovery, sandbox-canary-capture-gate, plugin-root-propagation-gate, Block-* family ~10). Fold to ~6 umbrella jobs frees ≈18-22 concurrent slots per run — consistent with the brief's ~25 upper bound once dependency-review/skill-scan stay separate. Commands: `grep -n 'name:' .github/workflows/{ci,pr-quality-guards,secret-scan}.yml`; issue #12089 table (`test` p90 3848s vs bound 3300s; merge_group p90 3241s vs 2820s; 15 breaches). Job population measured from `scripts/required-checks.txt` (25 contexts: 23 CI + 2 CLA).

**Oracle-lane evidence state (lever 2 prerequisite).** `gh run list` + jobs-API reads, 2026-11-06 ~14:35Z: `CI_ORACLE_LANE=on` since 14:30:42Z; `oracle-selection` jobs are *queued* on post-arm PR runs (42235226130, 42235175522) — the arm took effect; **zero completed `SOLEUR_ORACLE_LANE` notices exist yet** (pre-arm merge_group run 42229514276 carries no oracle-selection job at all, consistent with the var resolving at job scheduling). The blocking would_skip audit cannot complete until traffic flows; expected within the work phase given ~300 PR runs/day.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (brief) | Reality (verified) | Plan response |
|---|---|---|
| "LEVER 1 — batch entries into shared merge_group builds — raise min_entries_to_merge to 2-3 AND/OR wait ~10-15; consider ALLGREEN→HEADGREEN" | Grouped candidate builds already form opportunistically at min=1 (canary 2026-11-01: members=3 on ONE merge_group run). "Merge limits do not combine merge_group builds" (ADR-270 addendum, quoting GitHub docs). A 2026-10-31 CTO ruling already fixed min=1/wait=0 ("solo PRs never wait; grouping stays opportunistic") and ALLGREEN ("HEADGREEN lets members merge on the head's cumulative build with no per-PR verification — CLA hole"). | **No merge_queue param change in this PR.** All 7 params carry rulings <7 days old (min/wait/ALLGREEN 10-31; max_merge=3 raised 10-31; timeout=120 raised 11-03; max_build=2 is the canary-gated runner knob). The un-ruled direction `max_entries_to_build 2→1` halves queue-side speculative demand but serializes drain — net sign unmeasured — deferred to a measured follow-up on #12089/#11556 (tracked, see Deferred). |
| "LEVER 2 — the PR then removes ONLY the lock line" | Runbook: activation is "a separate, explicitly authorized step" + the audit is BLOCKING evidence (T1); zero SOLEUR_ORACLE_LANE notices exist yet. | **Lever 2 is a separate activation PR** once ≥1 real oracle-only run's notice verifies against its reconstructed diff. This plan defers it with the evidence state recorded. |
| "~30 small-guard consolidation" | 18 required small guards + ~10 advisory across 3 workflows (census above). | Fold per-workflow into ~6 umbrella jobs; rename affected required contexts with the full paired-edit set (Phase 2). |

## Design Decisions (ruled in-process as acting ruling seat — subagents cannot nest)

Rulings recorded to `knowledge-base/project/specs/feat-one-shot-12089-congestion-relief/decision-challenges.md`.

1. **Q1 — merge-queue params: no change (keep all seven).** ALLGREEN retained (prior CTO ruling stands: HEADGREEN lets a member ride the head's cumulative build with no per-PR verification — CLA hole + weakens the merge_group authority invariant). min_entries_to_merge=1 / wait=0 retained — grouped candidate builds already form opportunistically (measured), so the raise buys build-sharing that exists and adds up-to-N-minute waits to solo traffic. `max_entries_to_build 2→1` is the only un-ruled demand lever and is deferred pending measurement — bundling it would confound lever 3's before/after numbers and could worsen merge_queue-surface dwell (the epic's own metric).
2. **Q2 — lever-3 shape: fold into per-workflow umbrella jobs + rename required contexts (atomic swap, same-PR paired edits).** The Checks-API composite alternative is rejected: (a) fork `pull_request` runs get a read-only GITHUB_TOKEN — a composite job cannot post the required check_runs, so fork PRs would pend forever unless a privileged `workflow_run` poster workflow or a minted App token inside untrusted-PR jobs is added (a permanent security-sensitive mechanism, or a check-forgery escalation — either violates mechanism-minimality); (b) a mid-job runner loss leaves un-posted contexts silently pending (today: job death reports one red check); (c) renames are a contemplated ADR-032 operation (paired-edit contract), and the consumer set is enumerable and guarded (canonical-parity test, coverage probe, derived synthetics/watch population). Folding preserves per-gate blocking semantics with GitHub-native failure reporting, zero new machinery, fork-safe.
3. **Q3 — lever 2 in a separate activation PR.** Runbook requires the unlock PR to remove ONLY the lock line, gated on the blocking would_skip audit; bundling would either delay levers on oracle-repair traffic or ship the unlock without its blocking evidence.

## User-Brand Impact

- **If this lands broken, the user experiences:** a required-context rename whose producer never reports → the ruleset entry pends *forever* → every queued merge stalls — the June-30 merge-queue deadlock incident class, now self-inflicted by rename drift instead of a missing merge_group producer. Second artifact: a folded guard silently skipped inside an umbrella → a real gate un-enforced while its required context still reports green (the #8450 fabricated-green class).
- **If this leaks, the user's [data / workflow / money] is exposed via:** a weakened required gate (secret-scan fold) that stops blocking leaked-secret diffs — exposure vector: secrets committed under a fabricated or vacuous umbrella green.
- **Brand-survival threshold:** `single-user incident` — one wrong rename/pending-producer deadlocks the entire merge path (org-wide delivery outage), matching the prior queue work's threshold (`USER_BRAND_CRITICAL unconditional per #5175`, cross-domain lane).
- **Threshold decision (challengeable):** `single-user incident` and not `aggregate pattern` — a permanent-pending required context is a single deterministic incident (100% merge blockage), not a statistical pattern.
- `requires_cpo_signoff: true` — CPO sign-off required at plan time before work begins (invoke CPO domain leader if not covered; `soleur:engineering:review:user-impact-reviewer` runs at review time).
- Sensitive-path scope-out (preflight Check 6 token `secret` matches `.github/workflows/secret-scan.yml`): `threshold: single-user incident applies — the secret-scan fold is in scope precisely because a weakened secret gate is the exposure vector; no `none`-tier scope-out claimed`.

## Hypotheses

Phase 1.4 fired on the `timeout` token (`check_response_timeout_minutes=120` in the brief — a config token, not a connectivity symptom). The network-outage checklist's L3→L7 diagnostic order is **not applicable**: no SSH/firewall/connectivity hypothesis exists in this plan; the only connectivity-adjacent surface is the GitHub REST API for ruleset reads (already exercised by existing probes). Telemetry emitted: `SOLEUR_RULE_APPLIED rule=hr-ssh-diagnosis-verify-firewall`. No SSH-provisioning steps are prescribed anywhere below (lever 3 is YAML+JSON edits; the ruleset apply rides the existing `apply-github-infra.yml`).

## Implementation Phases

### Phase 1 — Lever 3a: umbrella design + membership census (gate)

- Enumerate the exact fold membership per workflow (candidates below; refine in work, keeping `runs-on`, permissions, checkout depth, and install needs homogeneous inside each umbrella):
  - `ci.yml` umbrella A `guards-ruleset` (required): adr-ordinals, rule-body-lint, tc-document-sha-guard, marketplace-manifest-guard, service-role-allowlist-gate, credential-path-guard.
  - `ci.yml` umbrella B `guards-env` (required): lockfile-sync, grok-fidelity (install-heavier members isolated so the docs-only umbrella stays ~2-3 min).
  - `ci.yml` umbrella C `guards-advisory` (advisory, same `lint-bot-statuses` folded shape): sandbox-canary-capture-gate, plugin-root-propagation-gate, harness-discovery — absorbed as named steps preserving the `lint-bot-statuses` fold precedent (`if: ${{ !cancelled() }}` on absorbed steps).
  - `pr-quality-guards.yml` umbrella `quality-guards` (required): enforce, markdown-lint, Bash fixture tests for guard scripts. Advisory `Block *` family + constraint-gates + auto-close-scan fold into one advisory umbrella `quality-advisory`; `detect` stays (it feeds the gated-guard flags); `dependency-review` and `skill-security-scan PR gate` stay separate (distinct permissions/toolchains).
  - `secret-scan.yml` umbrella `secret-guards` (required): gitleaks scan, lint fixture content, waiver discipline, rename-guard, allowlist-diff — 5→1 (homogeneous: diff-scan guards over the same checkout; gitleaks keeps its pinned-install step).
  - **Do NOT fold:** `affected-index-ratchet` (PR3a observation window; must remain its own context per #10448/#10865), `encryption-posture` (inside `test`'s needs), `oracle-index-check`, `oracle-selection`, `pr-selection`, `draft-light`, `push-dedupe`, `detect-changes`, `lint-webplat` (heavier; candidate for a later fold), `e2e`, `test`, `critical-css-gate`, `tenant-integration-required`, `sentry-destroy-required`, `vendor-pin-required` (single-job aggregator workflows), `cla-check`, `cla-evidence` (CLA ruleset, separate mechanism), `dependency-review` (distinct action), `skill-security-scan PR gate` (Bun toolchain + diff-scoped).
- Umbrella step contract: members run as named steps (never silent `run:` chains that lose the failing gate's name); every member step runs even after a sibling fails (`if: ${{ !cancelled() }}` per the lint-bot-statuses precedent) and a final aggregate step exits non-zero iff any member failed, printing the member names — the per-gate blocking semantics and the operator's red-row→log-path are preserved.
- Every umbrella `name:` reports on `pull_request`, `push`, AND `merge_group` (no event `if:` — the pend-forever precondition).

### Phase 2 — Lever 3b: required-context ABI swap (atomic, same PR)

- `infra/github/ruleset-ci-required.tf`: remove the 16 folded context names from `required_status_checks`; add the umbrella names. Paired-edit contract per ADR-032 — lands atomically with the workflow edits in the same merge.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json`: same context swap (15368 throughout). DR skeleton needs no edit (it slurpfiles this JSON) but T-rsc parity and the canonical-parity test must stay green end-to-end.
- `scripts/required-checks.txt`: replace the 16 entries with the umbrella names, each with a **#6049 compound justification**: the umbrella's synthetic-green soundness = union of member justifications — unreachability members documented per-gate; intersecting members (credential-path-guard → weakness-digest.md; gitleaks + lint fixture content → already reproduced in the action's Phase-4 ceiling) explicitly re-derived; umbrella entries whose members include a reproduction must name the reproduced member set.
- `scripts/required-check-wallclock-bounds.tsv`: replace the 16 rows with umbrella rows — seed `pr_bound = max(member pr_bound) + Σ member p90_dur` (serialized-member latency bound; margin 0.30 unchanged), annotate the seeding method per the file's method comment; tighten after the post-merge soak. Stale-name rows are removed in the same diff (a bounds row without a required-checks.txt row warns).
- `infra/github/README.md` + `scripts/create-ci-required-ruleset.sh` comments: context-count/inventory text updates; the merge_queue block stays byte-identical to the skeleton (lever 1 = no change — T-mq-1 unaffected).
- Consumer sweep (`git grep` for each renamed context): `scripts/pr-fanout-ledger.txt` job counts, `plugins/soleur/skills/ship/scripts/battery-owed.sh` (reads the LIVE ruleset — verify no name list hard-codes), `plugins/soleur/scripts/monitor-pr-checks.sh`, `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`, `plugins/soleur/scripts/ci-head-verdict.sh`, `scripts/post-bot-statuses.sh`, `lefthook.yml`, `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`, ship SKILL.md references — most derive from required-checks.txt and follow automatically; hard-coded name literals are edited or justified.
- Guard inputs: `scripts/lib/test-affected-paths.sh` edge declarations for the touched files (workflow files + required-checks.txt already declare consumer edges — verify the umbrella suites' edges cover the renamed-name consumers per the lint-ratchet's own rules).
- `scripts/probe-merge-group-coverage.sh`: verify the new umbrella `name:` fields are greppable as merge_group producers before the ruleset swap is required (probe derives required names from the ruleset/canonical — a producer it cannot find is the pend-forever defect).
- ADR-032 amendment (append-only dated entry): record the umbrella consolidation as a deliberate required-context rename with the paired-edit contract satisfied; note the 23→10 context reduction and the transition-hazard recipe.

### Phase 3 — Transition canary + measurement

- Merge-time recipe: `apply-github-infra.yml` applies the ruleset swap ~minutes post-merge; in-flight queue entries whose builds produced old names pend under the new ruleset — documented re-queue step (dequeue via GraphQL `dequeuePullRequest` or let `check_response_timeout_minutes=120` eject; `merge-queue-stall-check.yml` files a suspected-stall issue at 45 min as the detection net). Expected blast radius: ~1-4 entries (one battery window).
- Post-merge canary: verify the umbrella contexts report `success` on the first post-merge `merge_group` run (the merge_group producer precondition proven on the live queue, not just PR surface).
- Measurement: `bash scripts/ci-demand-census.sh` before/after windows on ci.yml+pr-quality-guards.yml+secret-scan.yml (`--summary`), plus the #12089 tracker table — expect folded-surface slot count −18-22/run and wallclock p90 movement toward epic goals. `scripts/pr-fanout-ledger.txt` counts updated in-diff.

### Phase 4 — Deferred follow-ups (filed, not in this PR)

- Lever 2 activation PR (separate): once ≥1 real oracle-only run emits a verifiable `SOLEUR_ORACLE_LANE … would_skip=<legs>` notice — reconstruct the classified diff per runbook (pull_request: head_sha merge-ref parents; merge_group: payload head/base) → remove ONLY `readonly ORACLE_LANE_LOCKED=1` from `scripts/ci-oracle-lane.sh:73` → `bash scripts/ci-oracle-lane.test.sh` + `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` + `bash scripts/ci-push-dedupe.test.sh` → attach audit evidence to #10865 → append dated line to ADR-276 `### Stage status`. First-live-run canary: `ORACLE-ONLY-SKIP` names exactly the would_skip legs; `oracle-index-check` success.
- `max_entries_to_build 2→1` measured experiment (issue on #11556 epic): re-evaluate queue-side speculative demand after lever 3's soak data exists; instrument = wallclock-p90 watch + queue dwell; rollback trivial ({1,3} pin does not cover max_build — parity only).
- `secret-scan` smoke/`lint-webplat`/`detect-changes` further folds: deferred pending this PR's measured win.

## Files to Edit

- `.github/workflows/ci.yml` — fold ~8 required guards + ~3 advisory jobs into umbrella jobs A/B/C.
- `.github/workflows/pr-quality-guards.yml` — fold required `enforce`/`markdown-lint`/`Bash fixture tests` + ~10 advisory Block-family into umbrellas; keep dependency-review/skill-security-scan/detect separate.
- `.github/workflows/secret-scan.yml` — fold 5 required guards into `secret-guards` (keep smoke jobs separate).
- `infra/github/ruleset-ci-required.tf` — required_status_checks context swap only (merge_queue block untouched).
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — same swap.
- `scripts/required-checks.txt` — 16 entries → 3 umbrella entries with #6049 compound justifications.
- `scripts/required-check-wallclock-bounds.tsv` — 16 rows → umbrella rows, re-seeded.
- `infra/github/README.md` — context inventory + table notes.
- `scripts/create-ci-required-ruleset.sh` — header comments only (context count/inventory).
- `knowledge-base/engineering/architecture/decisions/ADR-032-*.md` — appended dated amendment.
- `scripts/pr-fanout-ledger.txt` — per-workflow job counts.
- Consumer files found by the rename sweep (e.g., `scripts/post-bot-statuses.sh`, `lefthook.yml`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `plugins/soleur/scripts/monitor-pr-checks.sh`, ship SKILL.md prose) — edit only where a hard-coded context name exists.
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — comments/doc only if the compound-justification text needs the umbrella names (CHECK_NAMES is derived — no code change expected; verify Phase-4 reproduction coverage for umbrella members).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12089-congestion-relief/tasks.md` — task breakdown.
- `knowledge-base/project/specs/feat-one-shot-12089-congestion-relief/decision-challenges.md` — ruling rows (created this session).
- Follow-up issues: `max_entries_to_build` measurement experiment (epic #11556); oracle-lane activation PR record (attaches to existing #10865 + runbook, no new tracker needed).

## Domain Review

**Domains relevant:** Engineering only.

### Engineering

**Status:** reviewed (in-process — subagent nesting unavailable; single-pass assessment per brainstorm-domain-config assessment questions)
**Assessment:** Pure CI/infrastructure change: GitHub Actions job topology, ruleset required-context set, DR skeleton parity. Engineering-domain invariants engaged: ADR-032 job-name contract, ADR-276 Decision 3(a) (no required context renamed/removed/left pending/skipped-green — satisfied by atomic rename + merge_group producers proven pre-swap), merge-queue rollback recipe preserved, Guard-2 T-mq-1 parity surface untouched. Marketing/Legal/Finance/Sales/Support/Product/Operations sweeps negative — no copy, no legal doc, no spend, no customer surface. Legal adjacent check (CLA): contexts untouched (separate ruleset, separate mechanism). Operations adjacent: queue-transition ops recipe is documented, not delegated.

### Product/UX Gate

**Tier:** none — no user-facing surface; Files-to-Edit match no UI-surface glob (`.github/workflows/*.yml`, `infra/github/*.tf`, `scripts/*`, `knowledge-base/**`).
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Observability

```yaml
liveness_signal:
  what: "required-context wallclock p90 per surface (the #12089 weekly tracker table) + merge-queue stall probe + scheduled-ruleset-bypass-audit context-set audit"
  cadence: "weekly (wallclock-p90-watch.yml), */10min requested (merge-queue-stall-check.yml), daily (ruleset audit)"
  alert_target: "issue #12089 in-place rewrite + drift comment; suspected-stall issue filing"
  configured_in: ".github/workflows/wallclock-p90-watch.yml, .github/workflows/merge-queue-stall-check.yml, .github/workflows/scheduled-ruleset-bypass-audit.yml"

error_reporting:
  destination: "GitHub Actions check annotations + the tracker's breach list"
  fail_loud: "a renamed required context with no producer pends forever → entry never merges (visible as pending check + stall-probe issue at 45min)"

failure_modes:
  - mode: "umbrella job dies mid-run → all member gates absent that run"
    detection: "job conclusion failure on the umbrella context (red check, not silent pending)"
    alert_route: "PR check row + merge_queue stall probe"
  - mode: "renamed context missing a merge_group producer"
    detection: "probe-merge-group-coverage.sh (pre-merge, fail-closed) + queue entry pending (post-merge)"
    alert_route: "CI red on the PR itself; suspected-stall issue if it reaches the queue"
  - mode: "bot-PR synthetic posts umbrella green while a member gate would fail over a bot-reachable file"
    detection: "required-checks-canonical-parity.test.sh Test 8 + the umbrella's compound #6049 justification"
    alert_route: "CI red; review of the compound justification"

logs:
  where: "workflow run logs (umbrella job prints per-member verdicts + aggregate line); wallclock tracker body is the p90 record"
  retention: "GitHub default (90d run logs); tracker body rewritten weekly"

discoverability_test:
  command: bash -c 'rg -l "name: (guards-ruleset|guards-env|quality-guards|secret-guards)" .github/workflows/ | sort'
  expected_output: ".github/workflows/ci.yml"
```

## Encryption Posture

Detection fired via `infra/github/ruleset-ci-required.tf` (`.tf$` glob). The change edits ruleset *context names* — no persistent store is introduced and no new cross-component/network connection is created (the ruleset already exists; the workflows already post check runs on the same events under the same token).

```yaml
at_rest: "none — no persistent store introduced"
in_transit: "unchanged — same GitHub Actions runners and check-run reporting over the platform TLS channel; no new endpoint, credential, or connection"
exception: ~
```

## Architecture Decision (ADR/C4)

### ADR

- **Amend** `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` — append a dated amendment recording the required-context consolidation (16 contexts → 3 umbrella contexts across ci.yml/pr-quality-guards.yml/secret-scan.yml), reaffirming the paired-edit contract (rename + Terraform in the same merge) and recording the transition-hazard recipe and the new context-name ↔ umbrella-job-name inventory. In-scope plan task, not a follow-up.
- ADR-270: no amendment — the merge_queue block is unchanged (lever 1 ruled no-change; the 2026-10-31/11-01 rulings and canary already record why).
- ADR-276: no amendment — lever 2's activation PR (separate) appends its own dated Stage-status line per runbook step 4.

### C4 views

**No C4 impact**, verified against all three model files (`model.c4`, `views.c4`, `spec.c4`, read this session): the change reorganizes GitHub Actions *jobs* — an operational detail below the model's abstraction. External actors enumerated (untrusted contributor — its PR-head code still runs under pull_request isolation; public GitHub reader; founder/operator) — unchanged. External systems (github, code-hosting/CI as a platform edge) — unchanged; no new vendor, webhook, or credential edge is added (the Checks-API alternative that would have added a posting path was rejected). Containers/data stores — none touched. Access relationships — none change. The `plugin -> github` and `github -> tunnel` edges are unaffected.

### Sequencing

The ADR-032 amendment is authored in this PR describing the as-merged state (status stays its current value; append-only convention).

## Guard Contract

The deliverable modifies guarded surfaces and relies on existing guards; the **one new enforcement-shaped artifact** is the umbrella step-aggregation contract plus the rename-swap — covered below.

### Guard 1 — Umbrella aggregation reports every member failure (no silent skip)

**Property.** An umbrella job's required context reports `success` iff every member guard exited 0 — a member red must red the context, and a member skipped/cancelled without running must never report as a member pass.

**Assembly.** The chokepoint is the umbrella's final aggregate step — every member step result must flow through it (member steps are the only producers of member verdicts; the aggregate step is the only place the job conclusion is decided). The member set is the committed step list; a member added as a step but not counted by the aggregate is the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Inject an `exit 1` into one member guard's script/step | umbrella context RED; aggregate line names the member |
| 2 | Drop the aggregate step (guard's own dispatch — job exits green on member failures) | RED — vacuity probe suite/PR fixture asserts the aggregate is required |
| 3 | Add a second member step after a compliant first but omit it from the aggregate's member list | RED — the uncounted member's failure never reaches the conclusion |
| 4 | Member step `continue-on-error: true` removed so a member red skips all later members | RED on the run-all assertion (later members must still produce verdicts — the report-all shape) |
| 5 | Harness row: aggregate counts `steps.*.conclusion == 'success'` over a synthetic context where one member is `skipped` | RED — skipped ≠ success |

### Guard 2 — Rename-swap parity (context set consistency across the five surfaces)

**Property.** The required-context name set is identical across `ruleset-ci-required.tf`, canonical JSON, required-checks.txt, bounds TSV names, and reporting workflow `name:` fields — a name present on any single side is a drift defect.

**Assembly.** Chokepoints: `required-checks-canonical-parity.test.sh` (file-vs-JSON), Guard-2 T-rsc rows (tf vs JSON), `probe-merge-group-coverage.sh` (ruleset contexts → workflow producers), `watch-wallclock-p90-11774.sh` (bounds rows ↔ required-checks.txt population).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename a context in the workflow `name:` but not required-checks.txt | RED (parity + coverage probe) |
| 2 | Delete the canonical JSON row for an umbrella name (vacuous-dispatch arm — set shrinks silently) | RED |
| 3 | Add a second umbrella `name:` to ci.yml without adding it to required-checks.txt | RED — second-member-after-first |
| 4 | Bounds TSV row left for a removed context name | RED/stale-bound warning asserted by the watch probe fixture |
| 5 | Harness row: must-PASS — the post-swap set where every name appears on all five surfaces | PASS — proves the suite does not red a coherent state |

## Infrastructure (IaC)

### Terraform changes

- `infra/github/ruleset-ci-required.tf` — `required_status_checks` context list only (remove 16, add umbrella names). No new resources, no provider changes, no variables. `github` provider `~> 6.10` pin unchanged.
- Apply path: existing `.github/workflows/apply-github-infra.yml` post-merge apply (app_auth, soleur-ai App) — no operator `terraform apply`. The diff is an in-place update of the ruleset resource (`update`, not `destroy`) — the destroy-guard's `[ack-destroy]` requirement does not fire on a context-list change, but the plan output is read pre-merge to confirm `0 destroy`.
- Distinctness/drift: `scheduled-terraform-drift.yml` already covers `infra/github`; no new state surface.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "LEVER 1 — merge-queue batching … raise min_entries_to_merge to 2-3 AND/OR min_entries_to_merge_wait_minutes to ~10-15; consider ALLGREEN→HEADGREEN" | Design Decision 1 (no-change ruling) + Deferred (`max_entries_to_build` measurement) | descoped — justification: mechanism already ruled against 2026-10-31 (CTO) and refuted by 2026-11-01 canary (grouped builds already opportunistic); brief's premise stale |
| 2 | "LEVER 2 — oracle lane activation … the PR then removes ONLY the lock line" | Phase 4 deferred activation PR + evidence-state record | descoped to separate PR — justification: runbook mandates a separate authorized step gated on blocking would_skip audit; zero notices exist yet |
| 3 | "LEVER 3 — ~30 small-guard consolidation … every context in ruleset-ci-required.tf required_status_checks is public ABI" | Phases 1-3, Files to Edit | mapped |
| 4 | "the block must stay byte-equal to the DR skeleton … AND the table in infra/github/README.md — all three in the same diff" | Phase 2 (merge_queue block untouched; T-mq-1 unaffected) | mapped |
| 5 | "check whether any oracle-only CI run has flowed since CI_ORACLE_LANE was armed" | Research Insights evidence-state record | mapped |
| 6 | "collect the would_skip audit (blocking, ruling T1)" | Phase 4 deferred activation PR (audit is its precondition) | mapped (to follow-up) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Umbrella fold design (Phases 1-2) | "~30 small-guard consolidation … Guards run 20-30s each but burn a runner slot and queue behind 38-min shards — ~25 slots freed per run" | asked |
| Required-context rename + paired-edit set | "contexts must ALSO report on merge_group or entries pend forever (documented hard precondition)" | asked |
| `max_entries_to_build` deferral issue | — | inferred — justification: the only un-ruled queue-side demand lever; bundling an unmeasured-sign change would confound lever 3's before/after numbers and could worsen the merge_queue-surface metric |
| ADR-032 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — a required-context-set change is an architectural decision record, not deferrable |
| Transition re-queue recipe | — | inferred — justification: pend-forever is the documented incident class (ADR-032 escape hatch, June-30 deadlock) |

### Split Assessment

- Subsystems touched: 4 — `.github`, `infra`, `scripts`, `knowledge-base`
- Planned files: ~14 core + consumer-sweep tail (~5-15 more) | Estimated changed lines: ~900-1400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines → **borderline: 4 roots + likely >800 lines**
- Recommendation: single PR — the diff is atomic by construction (the rename swap must land in one merge; splitting strands either the workflow side or the ruleset side into the pend-forever hazard). The consumer-sweep tail is the only splittable tail and rides the same diff by necessity.

## Acceptance Criteria

- [ ] AC1: Every required context in the post-swap `required_status_checks` set reports `success` on `pull_request` AND `merge_group` — `probe-merge-group-coverage.sh` exits green on the PR and the first post-merge `merge_group` run shows the umbrella contexts green (no pend-forever).
- [ ] AC2: `bash tests/scripts/test-audit-ruleset-bypass.sh` passes (T-mq-1 seven-param parity intact — merge_queue block byte-equal to DR skeleton and README; T-rsc tf↔JSON parity on the renamed set).
- [ ] AC3: `plugins/soleur/test/required-checks-canonical-parity.test.sh` passes — required-checks.txt ≡ canonical JSON (15368-filtered) + CLA names.
- [ ] AC4: Each umbrella job runs every member step on a member failure (`if: ${{ !cancelled() }}` + aggregate step) — a synthetic member-red drive produces a RED umbrella context whose log names the failing member (Guard 1 matrix rows 1-5 driven locally or in a fixture suite committed in the PR).
- [ ] AC5: `scripts/required-checks.txt` umbrella entries each carry a #6049 compound justification naming which members are unreachability-sound and which are Phase-4-reproduced.
- [ ] AC6: `scripts/required-check-wallclock-bounds.tsv` carries umbrella rows (no stale-name rows) and `watch-wallclock-p90-11774.sh --dry-run` reports zero stale-bound warnings.
- [ ] AC7: The context count drops 25→12 (23→10 CI + 2 CLA unchanged) — measured by `jq 'length' scripts/ci-required-ruleset-canonical-required-status-checks.json` and `grep -cv '^#\|^$' scripts/required-checks.txt`.
- [ ] AC8: Slot saving measured: `bash scripts/ci-demand-census.sh --workflow ci.yml --summary` (and pr-quality-guards.yml, secret-scan.yml) job count per run drops ≥18 against the pre-merge baseline window; recorded on #12089.
- [ ] AC9: ADR-032 carries an appended dated amendment naming the consolidation, the paired-edit contract, and the transition recipe.
- [ ] AC10: No merge_queue parameter value changed — `git diff origin/main -- infra/github/ruleset-ci-required.tf` shows only required_status_checks edits; `git diff origin/main -- scripts/create-ci-required-ruleset.sh` shows no skeleton-param edits.
- [ ] AC11: Lever-2 deferral recorded: decision-challenges.md row + the deferred activation sequence documented (this plan Phase 4); evidence state from Research Insights attached (comment or file) so the activation PR inherits it.
- [ ] AC12: All CI green on the PR itself, including the renamed contexts (the PR's own run is the first live exercise of the umbrella producers — its `merge_group` run happens when this PR queues).

## Test Scenarios

- Given a member guard exits 1 inside an umbrella, when the umbrella job concludes, then the umbrella context is RED and its log names the member (`unit`/fixture — Guard 1 row 1).
- Given the aggregate step is deleted or a member is omitted from its count, when the vacuity fixture runs, then the guard reds (Guard 1 rows 2-3 — `unit`).
- Given a renamed context exists in a workflow `name:` but not required-checks.txt, when parity/probe suites run, then RED (Guard 2 rows 1-3 — `unit`).
- Given a bot PR diff touching only `knowledge-base/project/weakness-digest.md`, when the composite action posts synthetics, then each umbrella synthetic is justified by the compound #6049 note (reproduction coverage: credential-path, gitleaks, lint-fixture — `integration` via the action's own tests).
- Given a queue entry in flight during the apply window, when the ruleset swaps names, then the entry pends and the documented re-queue recipe is executed (post-merge ops scenario — `e2e`, `pyramid-justified: production-transition canary, cannot be staged`).
- Regression: the June-30 deadlock class — every required context still has a merge_group producer (probe suite + AC1); the CodeQL-absence invariant of T-mq-1 still holds.

## Open Code-Review Overlap

Check deferred to `soleur:work` start (the `## Files to Edit` list is final here; the two-stage `gh issue list --label code-review` + `jq --arg` sweep runs against these paths then) — recorded so the check is not silently skipped. Expected surface: any open scope-out naming `.github/workflows/*.yml`, `scripts/required-checks.txt`, `infra/github/`.

## Dependencies & Risks

- **Pend-forever class (top risk):** a renamed context missing a merge_group producer deadlocks the queue — mitigations: coverage probe pre-merge (fail-closed), atomic same-merge swap, first-post-merge-merge_group canary, documented re-queue recipe.
- **Umbrella granularity loss:** a red umbrella hides which member failed for readers that see only the check name — mitigated by the aggregate step's named-member output (same contract as `test` aggregator and `lint-bot-statuses`).
- **Serial-time growth inside umbrellas:** ~6 members × ~30s ≈ ~3min per umbrella — still ≪ any bound; measured on the canary.
- **#6049 fabrication surface:** umbrella synthetic greens cover member surfaces a bot cannot reach — the compound justification must be re-derived per umbrella, never inherited.
- **Fork PRs:** unaffected by construction (job checks are native; no API posting).
- **Apply-window stalls:** ~1-4 in-flight entries; recipe documented (dequeue or 120-min ejection; stall probe files at 45 min).

## Success Metrics

- Required contexts: 25 → 12 (10 CI + 2 CLA).
- Jobs per ci.yml/pr-quality-guards.yml/secret-scan.yml run: −18 to −22 (census before/after).
- #12089 tracker: breach count drops toward ≤5 next weekly rewrite; `test` p90 moves toward the 1200s/900s epic goals (not guaranteed by this lever alone — the watch is the instrument).
- Zero pend-forever required contexts post-swap (queue drains normally).

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Composite job posting per-guard check_runs via Checks API (brief's option A) | Rejected — fork PRs get read-only tokens (required contexts would pend); safe posting needs a privileged workflow_run poster or App-token-in-PR-job (check-forgery hazard); permanent security-sensitive machinery for a YAML-consolidation win |
| Keep individual required jobs; fold only advisory guards | Rejected — delivers ~8-10 of ~22 slots; the required set is where the slot spend lives |
| `min_entries_to_merge` raise + wait (brief's lever 1) | Rejected — already ruled 2026-10-31; grouped builds are already opportunistic; pure added latency |
| ALLGREEN → HEADGREEN | Rejected — prior CTO ruling (CLA per-PR verification hole); weakens the merge_group authority invariant |
| `max_entries_to_build` 2→1 in this PR | Deferred — net sign unmeasured; confounds lever-3 measurement; filed for the epic |
| Split: infra rename PR then workflow fold PR | Rejected — a split strands one side of the ABI and guarantees the pend-forever window; the swap is atomic by construction |

## References & Research

- Tracker: issue #12089 (wallclock-p90 table, dispatch run 42231989547); epic #11556
- Prior ruling: `knowledge-base/project/brainstorms/archive/20261031-173135-2026-10-31-merge-queue-batching-queue-jump-brainstorm.md`; ADR-270 addenda 2026-10-31/11-01
- Oracle lane: ADR-276 amendment 2026-11-05 (#12156); runbook `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md`; observation tracker #10865
- Contracts: ADR-032 (job-name/rename pairing, escape hatch), ADR-276 Decision 3(a), required-checks.txt #6049 guard
- Parity guards: `tests/scripts/test-audit-ruleset-bypass.sh` (T-mq-1/T-rsc), `plugins/soleur/test/required-checks-canonical-parity.test.sh`, `scripts/probe-merge-group-coverage.sh`
- Fold precedent: `lint-bot-statuses` job (`.github/workflows/ci.yml:608-699`, #8149)
- Checks-API precedent (synthetics only): `.github/workflows/merge-queue-cla-synthetics.yml`, `scripts/merge-queue-cla-verify.sh`

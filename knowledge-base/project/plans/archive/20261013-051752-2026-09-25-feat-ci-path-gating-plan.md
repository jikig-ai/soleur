# Plan: path-gate file-scoped PR workflows (required-safe mechanism)

Date: 2026-09-25
Branch: `feat-one-shot-ci-path-gating` · PR: #8897 (draft)
Arc: CI-efficiency item 3 of 5 (item 1 = #8854 concurrency baselines, merged;
item 2 = #8891 cancel-in-progress coverage, merged). Prior art: ADR-032
(required-checks ABI), #5585/#6589/#8203 (always-run aggregator over a
path-gated heavy job), #8450 (ci.yml step-level e2e gating), ADR-216
(`scripts/pr-fanout-ledger.txt`), #4384 (`enforce` surface_hit short-circuit).

## Overview

Re-derived the scope against the tree: the brief's "already done" claims check
out, and the residual is smaller than the candidate list suggested — **two
files change**:

1. **`dependency-review.yml`** — a REQUIRED context that runs the third-party
   `actions/dependency-review-action` on every PR push although it can only
   produce output when a dependency manifest/lockfile changed. Add an in-job
   `detect` step (`gh api …/pulls/N/files`, fail-open-to-scan) and `if:` the
   pull_request action step. The job still runs every push, so the required
   context always reports green when skipped — the required-check-safe
   mechanism the brief prescribes.
2. **`pr-quality-guards.yml`** — one new `detect` job (same fail-open file
   list) gating the five **advisory** jobs whose scan surface is a fixed path
   set. The two required jobs stay always-run.

No `on.pull_request.paths` is added anywhere: every gatable non-required job
shares a file with required jobs (a trigger-level filter would suppress the
required contexts on the same trigger), and every standalone required-check
file must keep always-run jobs. The mechanism is uniformly
detect-then-`if:`, matching the repo's existing #5585-family convention.

## Verification-first premises (each re-verified on this branch)

### Required-check status — verified against the LIVE ruleset, not just IaC

`gh api repos/jikig-ai/soleur/rulesets/14145388` ("CI Required", active)
returns 24 contexts; `gh api …/rulesets/13304872` ("CLA Required", active)
returns `cla-check` + `cla-evidence`. Both match
`infra/github/ruleset-*.tf` and `scripts/required-checks.txt` modulo the
file's own documented deltas (CodeQL is intentionally omitted from the file —
GHAS `integration_id` 57789 can never be satisfied by a synthetic;
cla-check/cla-evidence live in the other ruleset). **The canonical JSON
(`scripts/ci-required-ruleset-canonical-required-status-checks.json`) and the
live ruleset agree; nothing in this plan changes the required set.**

Consequence for mechanism choice: `dependency-review` (job `dependency-review`
in dependency-review.yml), `skill-security-scan PR gate` (skill-security-scan-
pr-trailer.yml), `markdown-lint` + `Bash fixture tests for guard scripts`
(pr-quality-guards.yml), `enforce` (legal-doc-cross-document-gate.yml), all
secret-scan jobs, all ci.yml contexts, `cla-check`, `cla-evidence` are
REQUIRED → `on.pull_request.paths` would deadlock merges on skipped PRs.
GitHub reports a job skipped by job-level `if:` as success, which is exactly
why the detect+`if:` pattern is the only permitted mechanism for them.

### Per-workflow verdicts (unfiltered PR workflows — the full census)

Completeness: `scripts/pr-fanout-ledger.txt` enumerates every workflow firing
on a PR push (the ledger test reddens on an unrowed firing workflow); the
three lifecycle-only workflows (board-status-sync, cleanup-unmerged-bot-
branches, dev-ledger-reconcile) were read directly.

| Workflow | Verdict | Reason |
|---|---|---|
| `dependency-review.yml` | **GATE** | Required context; only dependency manifests/lockfiles can produce a review delta. In-job detect + step `if:`. |
| `pr-quality-guards.yml` | **GATE (partial)** | 5 of 10 jobs are advisory and file-scoped (below). Required `markdown-lint` (deliberately whole-corpus — #7927 comment + ruleset note) and `Bash fixture tests for guard scripts` (surface unbounded: suites reference `scripts/`, `apps/`, `plugins/` real files — a static path set would silently un-test a guard) stay always-run. `pii-grep` (Linear CDN URLs can appear in ANY file), `pr-body-vs-diff` (PR-body metadata), `auto-commit-message-density` (commit messages, incl. the folded CI-skip scan #8405) are not file-scoped. |
| `skill-security-scan-pr-trailer.yml` | Already gated — **no change** | Required `skill-security-scan PR gate`; the `diff` step already identifies added SKILL/agent MDs and `if:`-gates both scan steps (`no_new_skills`). Residual = ~20-25 s of checkout(fetch-depth 0)+bun per push; tightening it would duplicate the gate's deliberately fail-closed AMRT-diff semantics through a second mechanism (API file list ≠ git AMR rename semantics) AND collides with open PR **#8878** editing this exact file. Deferred, reasons recorded. |
| `secret-scan.yml` | Deliberately ungated | Content security floor (#3121): gitleaks + fixture lint + allowlist-diff + rename-guard + waiver discipline must see EVERY diff; all five are required contexts anyway. |
| `ci.yml` | Deliberately ungated | Carries ~11 required contexts; `test` is a required `if: always()` aggregator over the full suite (a green `test` must mean the suite ran). In-job gating already present: `detect-changes`→`critical-css-gate`, step-level e2e `detect.applicable` (#8450). |
| `cla.yml`, `cla-evidence.yml` | Deliberately ungated | pull_request_target identity/evidence gates — every PR's author needs the CLA check regardless of which files changed; both are CLA-Required contexts; ledger records `no cancel`/privileged-trigger policy. |
| `board-status-sync.yml` | Ungateable | All-PR lifecycle bookkeeping (opened/closed/ready/draft — no `synchronize`, so outside fan-out anyway). A docs-only PR still needs its board card; not file-scoped. |
| `cancel-superseded-pr-runs.yml` | Ungateable | It IS the per-push reaper; gating it on paths would skip the cancellation on exactly the pushes that create superseded runs. |
| `cleanup-unmerged-bot-branches.yml` | Ungateable | `types: [closed]` only + job-level `if:` already narrows to unmerged same-repo bot-prefix branches. |
| `dev-ledger-reconcile.yml` | Ungateable | `pull_request_target: [closed]` only; the reconcile check IS the work (it determines whether a closed-unmerged PR left dev-ledger rows). |
| `pr-auto-close-scanner.yml` | Ungateable | Scans PR title/body/commit messages — the squash commit is built from commit messages, so every push must be scanned; not file-scoped. |
| `fix-constraints-stage-b.yml` | Already gated (transitively) | `workflow_run` chains off stage-a, whose `paths:` filter means no stage-a run → no workflow_run event → stage-b never fires on out-of-scope PRs. |
| `legal-doc-cross-document-gate.yml` | Already gated (in-job) | Required `enforce`; trigger `paths:` was deliberately REMOVED in #4384 and replaced with the `surface_hit=false` short-circuit (O(seconds) on non-DSAR PRs). |
| `constraint-gates.yml` | Deliberately ungated | Always-run is the template's promotable-to-required property (header comment); in-job `Detect target changes` already short-circuits; body parity-locked to the constraint-scaffold template. |
| `claude-code-review.yml` | Deliberately ungated | Disabled on GitHub's side since 2026-02-12 (state not in the tree); Art. 30 register PA-33 member — re-enable/delete only with a dated register correction. A `paths:` hint is already commented in the file for whoever re-enables it. |

Already gated (no action — verified, not assumed): `tenant-integration.yml`,
`apply-sentry-infra.yml`, `vendor-pin-verify.yml` (detect + always-run required
aggregators); `infra-validation.yml`, `gdpr-gate-self-test.yml`,
`rls-authz-fuzz.yml`, `sentry-audit-gate.yml`, `skill-security-scan-corpus.yml`,
`validate-vector-config.yml`, `fix-constraints-stage-a.yml` (`on.paths`);
`post-merge-monitor.yml` / `git-data-pin-redeploy.yml` / `deploy-docs.yml` /
`web-platform-release.yml` (workflow_run-chained to main-side parents).

### Open-PR collision check

`gh pr list --state open` × `.github/workflows/` overlap: **#8878** touches
`skill-security-scan-pr-trailer.yml` (part of why it is deferred), #6778 and
#8873 touch `infra-validation.yml`, #8886 `cutover-inngest.yml`, #7390/#8831
`apply-web-platform-infra.yml`/`reusable-release.yml`, #7999
`git-data-rung2-rehearsal.yml`. **No open PR touches `dependency-review.yml`,
`pr-quality-guards.yml`, or `scripts/pr-fanout-ledger.txt`.**

## Proposed Change

### 1. `dependency-review.yml` — in-job detect + step `if:`

The `dependency-review` job must keep running on every `pull_request` (it is
the required context). Inside it, BEFORE checkout (no checkout needed):

```yaml
      - name: Detect dependency-manifest changes
        id: detect
        if: github.event_name == 'pull_request'
        env:
          GH_TOKEN: ${{ github.token }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          GH_REPO: ${{ github.repository }}
        run: |
          set -uo pipefail
          # FAIL-OPEN TOWARD SCANNING: any failure to obtain the file list
          # emits deps=true — the gate runs the real review rather than skip
          # it on uncertainty. A required check may only skip on PROOF.
          files=$(gh api --paginate "repos/$GH_REPO/pulls/$PR_NUMBER/files" \
            --jq '.[].filename' 2>/dev/null || true)
          if printf '%s\n' "$files" | grep -qE '<MANIFEST_RE>'; then
            echo "deps=true" >> "$GITHUB_OUTPUT"
          elif printf '%s\n' "$files" | grep -qE '^\.github/workflows/dependency-review\.yml$'; then
            echo "deps=true" >> "$GITHUB_OUTPUT"   # self-trigger: gate edits run the gate
          elif [ -z "$files" ]; then
            echo "deps=true" >> "$GITHUB_OUTPUT"   # empty = unresolvable or truly empty; run anyway
          else
            echo "deps=false" >> "$GITHUB_OUTPUT"
          fi
```

`<MANIFEST_RE>` is a SUPERSET of every ecosystem dependency-review-action
recognises: `package.json`, `package-lock.json`, `npm-shrinkwrap.json`,
`yarn.lock`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `bun.lock`, `bun.lockb`,
`deno.lock`, `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `Pipfile*`,
`setup.py`, `setup.cfg`, `go.mod`, `go.sum`, `go.work*`, `Cargo.toml`,
`Cargo.lock`, `Gemfile*`, `*.gemspec`, `composer.json`, `composer.lock`,
`pom.xml`, `*.gradle`, `*.gradle.kts`, `gradle.lockfile`,
`gradle/libs.versions.toml`, `*.csproj`, `*.fsproj`, `*.vbproj`, `*.sln`,
`packages.config`, `pubspec.yaml`, `pubspec.lock`, `Package.swift`,
`Package.resolved`, `Podfile*`, `mix.exs`, `mix.lock`, `environment.yml`,
`conda-lock.yml` — matched as `(^|/)name$` so they hit at any depth. The
comment must say: when a new ecosystem lands, extend the regex; a miss means
a manifest change skips review (fail-open keeps the failure direction safe —
the only unsound direction is a missing pattern, so the list errs wide).

Then gate ONLY the pull_request step:

```yaml
      - name: Dependency Review (pull_request)
        if: github.event_name == 'pull_request' && steps.detect.outputs.deps == 'true'
```

The `merge_group` step stays unconditional (queue dormant since #5780 revert,
but if re-adopted the candidate re-scan must not depend on PR-side state).

Measured: job-time 13–18 s today (5 sampled runs; the ~470 s run-level average
is runner-queue wait, not billed time). After: ~5–7 s (one API call + skipped
steps). 0 of the last 25 merged PRs touched any manifest → ~100% skip rate.
Secondary win: removes a third-party action with a `retry-on-snapshot-warnings`
flakiness history from the every-push critical path.

### 2. `pr-quality-guards.yml` — one `detect` job + 5 job-level `if:`

New first job (advisory, ~8 s, no checkout):

```yaml
  detect:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      settings_json: ${{ steps.f.outputs.settings_json }}
      worktrees:     ${{ steps.f.outputs.worktrees }}
      webplat:       ${{ steps.f.outputs.webplat }}
      client_pii:    ${{ steps.f.outputs.client_pii }}
      sweep:         ${{ steps.f.outputs.sweep }}
    steps:
      - id: f
        env:
          GH_TOKEN: ${{ github.token }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          GH_REPO: ${{ github.repository }}
          EVENT_NAME: ${{ github.event_name }}
        run: |
          # FAIL-OPEN: non-PR events, API errors, or a truly-unresolvable list
          # emit 'true' for every surface — the gates run, never blind-skip.
```

Output semantics (each `true` when matched, all `true` on any error /
non-`pull_request` event; a legitimately empty diff legitimately emits
`false`):

| Output | Trigger pattern | Gates | Coverage argument |
|---|---|---|---|
| `settings_json` | `^\.claude/settings\.json$` | `settings-json-integrity` | `check-settings-integrity.sh` compares exactly `.claude/settings.json` base-vs-head; unchanged file → exit 0 anyway. |
| `worktrees` | `^\.claude/worktrees/` | `stray-worktree-marker-block` | The gate greps the diff name-list for that exact prefix — identical surface. |
| `webplat` | `^apps/web-platform/` (superset of `(server\|app)/`) | `userid-bypass-lint` | The gate flags added lines only under `apps/web-platform/(server\|app)/`; a wider trigger is conservative, not wrong. |
| `client_pii` | `^apps/web-platform/(lib\|components\|app)/` | `client-pii-grep` | `check-client-pii-sentry.sh` `find`s exactly those three roots — the scanned tree cannot change without a diff under them. |
| `sweep` | `^\.github/enforcement-contracts\.json$` **OR** any path in that file's `sibling_sets[].trigger[]` (fetched at PR head via `gh api …/contents`, `jq`-extracted) | `sweep-completeness` | The gate fails iff a registered trigger changed; the registry itself changing is always a trigger (a new set must be exercised). Registry fetch/jq failure → `true`. |

Self/dependency triggers — a change to the checking machinery must run the
gates: `^\.github/workflows/pr-quality-guards\.yml$` or `^\.github/scripts/`
→ all five outputs `true`.

Gate the five jobs: add `needs: detect` and extend each existing
`if: github.event_name == 'pull_request'` to
`github.event_name == 'pull_request' && needs.detect.outputs.<x> == 'true'`.
The `merge_group` behaviour is unchanged (those jobs never ran there; detect
emits all-true there anyway). The existing opt-out-label logic inside
`settings-json-integrity` / `stray-worktree-marker-block` /
`auto-commit-message-density` is untouched — it still governs the runs that
do happen. NOT gated: `guard-script-fixture-tests`, `markdown-lint`
(required), `pii-grep`, `pr-body-vs-diff`, `auto-commit-message-density`
(whole-diff/metadata surfaces).

Measured (runs 36158193413 / 36155885239 / 36152743033): gateable sum ≈
60–75 runner-s/push (settings 19–21 s, worktrees 4–5 s, userid 14–17 s,
client-pii 11–14 s, sweep 11–19 s); measured would-run rates over the last 25
merged PRs: settings 0%, worktrees 0%, webplat 40%, client_pii 12%, sweep
(trigger set) 0% → expected saving ~45–55 s/push after the ~8 s detect.
Wall-clock is unchanged — `markdown-lint` (~65 s) and
`guard-script-fixture-tests` (~40–77 s) remain the critical path, which is
fine: the prize here is runner-minutes and failure-surface, not latency.

### 3. `scripts/pr-fanout-ledger.txt`

- `pr-quality-guards.yml` row: jobs `10 → 11`, consequence gains a clause
  naming the `detect` job (fail-open PR-file-list detector gating the five
  file-scoped advisory jobs; required jobs stay every-push).
- `dependency-review.yml` row: jobs/paths/cancel unchanged (`paths` stays `no`
  — in-job gating is invisible to the ledger's trigger-level enumeration, the
  convention ci.yml's row already documents); append a short clause noting the
  in-job manifest detect.

### 4. Structural test — `plugins/soleur/test/ci-path-gating.test.sh` (new)

Pin the properties that make this safe (the repo's convention is CI structure
guarded by fixture tests, e.g. `pr-fanout-ledger.test.sh`):

- dependency-review.yml has a `detect` step and the pull_request action step's
  `if:` references `steps.detect.outputs.deps`; the job has NO job-level `if:`.
- pr-quality-guards.yml `detect` job exists; each of the five gated jobs has
  `needs: [.., detect]` and an `if:` containing its output name; the two
  required jobs carry no `needs.detect` edge.
- The manifest regex includes the repo's real manifest set
  (`package.json`, `package-lock.json`, `requirements.txt` at minimum) and
  the workflow self-path.
- Each gated script's scanned path set ⊆ its detect pattern (assert
  `check-settings-integrity.sh` names `.claude/settings.json`,
  `check-client-pii-sentry.sh`'s `find` roots ⊆ the `client_pii` regex, etc.
  — grep-anchored, same shape as existing pins).
- The fail-open branches exist (`deps=true`/`all-true` on error) — grep for
  the error branch rather than trusting review.

## Acceptance Criteria

1. `gh api …/rulesets/14145388` and `…/13304872` contexts unchanged (24 + 2);
   `scripts/required-checks.txt` and the canonical JSON untouched.
2. On a PR touching no manifest: `dependency-review` check reports **success**
   (job ran, action step skipped). On a PR touching a manifest: the action
   runs. Same for the five gated guard jobs w.r.t. their surfaces.
3. Every detect failure mode (API error, missing PR number, non-PR event)
   resolves to RUN, never skip.
4. `plugins/soleur/test/pr-fanout-ledger.test.sh` green with the 11-job row.
5. No `paths:`/`paths-ignore:` key added to any workflow carrying a required
   context; no workflow's trigger `types:` narrowed.
6. `merge_group` behaviour byte-identical for every touched job.
7. Post-merge measurement recorded: `gh api` job-time for
   `dependency-review.yml` + `pr-quality-guards.yml` on ≥10 subsequent runs
   vs the baselines in this plan.

## Non-Goals

- Gating `skill-security-scan-pr-trailer.yml` further (deferred: #8878
  collision + fail-closed-diff-semantics duplication for ~20 s).
- Gating `guard-script-fixture-tests` (required + fixture surface spans
  `scripts/`, `apps/`, `plugins/` real files — a static path set cannot be
  bounded honestly).
- Gating `ci.yml` suites (`test` must mean "the suite ran").
- Any `on.pull_request.paths` addition (no standalone non-required gatable
  file exists — every gatable job shares a file with required contexts).
- Re-enabling or deleting `claude-code-review.yml` (Art. 30 register PA-33;
  separate decision).

## Risks

- **False-skip**: a path set narrower than a gate's true surface silently
  disables it. Mitigations: fail-open on detect error; superset patterns;
  the §4 test asserting script-surface ⊆ detect-pattern; self-trigger paths
  for the checking machinery itself.
- **Required-context stall**: the prescribed mechanism avoids it (job runs,
  steps skip, check reports success). The §4 test pins "no job-level `if:` on
  the dependency-review job" so a later edit can't convert it into a
  skipped-job deadlock shape… a skipped JOB also reports success, but the
  detect-inside-job form keeps the cost paid visible in the check log.
- **Ledger/test churn**: bounded — one row delta (10→11) + one consequence
  clause; the enumerator reads the file, so a wrong jobs column fails loudly
  at A-checks rather than silently.

## Measurements

| Workflow | Before (job-time) | After (expected) | Evidence |
|---|---|---|---|
| `dependency-review.yml` | 13–18 s/push (runs 33308683651, 33178051096, 33084122211, 32418589463, 32415810920 — `jobs[].started_at→completed_at`) | ~5–7 s on ~96–100% of pushes | Job-level timing; run-level 470 s avg is queue wait, not billed minutes. Would-run rate 0/25 recent merged PRs. |
| `pr-quality-guards.yml` (gateable sum) | ~60–75 s/push across 5 parallel jobs | ~8 s detect + rare gated runs | Per-job timing from runs 36158193413 / 36155885239 / 36152743033; would-run rates 0–40% per surface. |
| `skill-security-scan-pr-trailer.yml` | ~23–29 s/push (recent) | unchanged (no change made) | Existing in-job `no_new_skills` gating already skips the scan steps. |
| Ungated-by-design workflows | — | unchanged | Verdicts table above. |

Post-merge verification recipe (for the tasks file): for each gated workflow,
`gh api "repos/jikig-ai/soleur/actions/workflows/<wf>/runs?per_page=10&status=completed"`,
then `…/actions/runs/<id>/jobs` — record started_at→completed_at per job and
the skipped-run rate.

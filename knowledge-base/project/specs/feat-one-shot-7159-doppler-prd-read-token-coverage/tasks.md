# Tasks — feat-one-shot-7159-doppler-prd-read-token-coverage

Derived from
`knowledge-base/project/plans/2026-08-02-feat-token-drift-prd-root-token-and-coverage-denominator-plan.md`
(v3, post-panel). Phase order is dependency-correct: every contract lands before its consumers.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-read `scripts/check-cloudflare-token-drift.sh` argument loop (`:73-93`),
      enumeration (`:99-107`), the four read sites (`:138`, `:223`, `:505`, `:506`), and
      `emit_json` (`:567-610`). Confirm the line anchors still hold.
- [ ] 0.2 Confirm `ADR-155` is still the next free ordinal against a freshly fetched
      `origin/main`. If not, renumber and sweep the plan, spec, this file and every AC:
      `grep -rn 'ADR-15[45]' knowledge-base/project/{plans,specs}/feat-one-shot-7159-doppler-prd-read-token-coverage/`
- [ ] 0.3 Re-check the two anti-vacuity floors (`token-drift-workflow-causes.test.sh:525`
      `-lt 28`; `check-cloudflare-token-drift.test.sh:1084` `-lt 53`). Both suites run at
      exactly their floor, so any added assertion forces a raise.
- [ ] 0.4 Confirm the `-target=` default block still runs `:465`–`:573` in
      `apply-web-platform-infra.yml`.

## Phase 1 — Contract: the detector (RED first)

- [ ] 1.1 Producer tests P1, P10 (zero-config invocation unchanged; unknown flag exits 2). RED.
- [ ] 1.2 Replace the argument loop's `*) shift ;;` catch-all with an error + exit 2. GREEN.
- [ ] 1.3 Producer tests P2, P4, P5, P9 (two-credential union; unset/empty name is a failed
      credential with no ambient fallback; non-empty credential enumerating nothing exits 2 with
      stderr visible; no credential value reaches child argv). RED.
- [ ] 1.4 Implement `DOPPLER_TOKEN_ENVS` (names, whitespace-separated, default `DOPPLER_TOKEN`),
      per-name unset/empty handling (record the NAME, never the value), env-prefix credential
      delivery, and removal of the `2>/dev/null` on the enumeration. GREEN.
- [ ] 1.4b Producer tests P11–P15 (sentinel absent from all six sinks; a bogus credential's
      stderr does not echo it; `::add-mask::` emitted per distinct scanned value under
      `GITHUB_ACTIONS=true`; `DOPPLER_TOKEN`/`DOPPLER_CONFIG` unset once the map is built).
      RED, then implement.
- [ ] 1.4c `unset DOPPLER_TOKEN DOPPLER_CONFIG` immediately after snapshotting the named
      credentials into the map — a missed read site must fail loudly, not bind the ambient
      credential.
- [ ] 1.5 Producer test P3: every one of the four `doppler secrets` reads uses the credential
      that enumerated that config. Include the mutation check (swap the map, confirm RED). RED
      then GREEN.
- [ ] 1.6 Build the config-to-credential map and thread it through all four read sites.

## Phase 2 — Contract: the ladder moves into the detector

- [ ] 2.1 Producer tests P6, P7, P8 (`configs_unread`, `coverage_ratio`, `inventory_age_days`;
      a short inventory changes the ratio and nothing else; a missing inventory still derives
      `coverage` from the floor). RED.
- [ ] 2.2 Add `--inventory <path>`; compute `configs_floor`, `configs_expected`,
      `configs_unread`, `coverage`, `coverage_ratio`, `inventory_age_days`.
      Evaluation order: `unknown` → `degraded` → `at-floor`.
- [ ] 2.3 Extend `emit_json` with the new fields. Give the third and fourth variable-length
      lists **distinct argv sentinels** — `rest.index("--")` cannot serve two — and re-index the
      five leading scalars.
- [ ] 2.3b Move `emit_json` **before** every exit-2 return (the enumeration guard at `:104-107`
      and the non-vacuity gate at `:184-192`), so a revoked credential still publishes
      `configs`, `configs_floor` and `coverage`. Exit codes unchanged.
- [ ] 2.4 Update the human report line (`configs scanned:`) to carry the enumerated names.
- [ ] 2.5 Correct the falsified remedy at `scripts/check-cloudflare-token-drift.sh:629`.
- [ ] 2.6 Raise the producer floor to 62.

## Phase 3 — The credential (IaC)

- [ ] 3.1 Create `apps/web-platform/infra/token-drift-read-token.tf` from the
      `web-arm-write-token.tf` / `kb-drift.tf:92-113` template: the resource pair, the BLAST
      RADIUS note, `autonomy-considered: provider-mint-applied`, the rotation recipe, and the
      reason no `ignore_changes` is present.
- [ ] 3.2 Add the two `-target=` lines to the **default** block only. Do not touch
      `terraform-target-parity.test.ts`.
- [ ] 3.3 `terraform fmt` and `terraform validate` in `apps/web-platform/infra`.
- [ ] 3.4 Create `apps/web-platform/infra/doppler-config-inventory.txt` with the
      `# generated:` ISO-8601 header, the `# command:` line, and the 13 sorted names.

## Phase 4 — Consumers: the workflow

- [ ] 4.1 Consumer-suite rewrites (T6, T7, T8, T8b, T13, T13b, T14, T14b, T14c, T14d, T16,
      T16b, T17, T19) plus the new cases. RED.
- [ ] 4.2 `token_drift` step: publish the new outputs; remove `DOPPLER_CONFIG`; add
      `DOPPLER_TOKEN_ENVS`. The empty-list guard **writes `coverage=unknown` and
      `verdict=unavailable` to `$GITHUB_OUTPUT` first, then fails** — failing first leaves every
      arm unmatched and the Sentry check-in still `ok`. Add the external `configs_floor >= 2`
      assertion (downgrade to `degraded`). Keep `configs` last-and-greedy in `read -r`, add
      non-empty guards on every new field, and move the fallback arity in lockstep.
- [ ] 4.2b Update the verdict echo line (`:251`) to carry `floor:` and `ratio:` — the
      discoverability test and AC27 both assert those fields.
- [ ] 4.3 `::warning::` arms for `degraded` and `unknown`; delete the retired arms.
- [ ] 4.4 Coverage filer: positive `if:` over `degraded`/`unknown`; per-class TITLE/LEAD;
      `degraded` body lists `configs_unread` and the ratio; **create-or-update-body** via
      `gh issue edit --body-file` on the existing-issue path; no `gh issue comment`.
- [ ] 4.5 Filer Remedy prose (`:461-476`) and Closing prose (`:481-485`).
- [ ] 4.6 Close arm → `coverage == 'at-floor'`; update its comment body.
- [ ] 4.7 DEAD ops email (`:280`) and DEAD issue body (`:584`, `:595`) — the inheritance
      remedy and the closing condition.
- [ ] 4.8 Both `<em>Scan coverage: …</em>` spans (`:280`, `:645`) — carry `coverage_ratio`,
      byte-identical to each other.
- [ ] 4.4b Branch on `gh issue edit`'s exit status; emit
      `token_drift_coverage_update_failed` on failure. Keep the label re-assert as a separate
      `|| true` call so the body edit's status is not swallowed into it.
- [ ] 4.4c Add an ops-email fallback step gated on a filer output flag set by any named
      `::error::`, so a dead issue channel still reaches the operator.
- [ ] 4.9 FR7: the `_cfgs=` pipeline (`:1115-1116`) — drop `2>/dev/null` and `|| true`,
      capture status explicitly (the block is `set -euo pipefail`), publish it as its **own**
      step output, and give it its **own** filer with its own title and lead. Do NOT fold it
      into `steps.sweep.outputs.orphans` — that filer is gated `orphans != '0'` plus an
      implicit `success()`, and its body claims the listed items are paying hosts.
- [ ] 4.10 Raise the consumer floor to 34.

## Phase 5 — Consumers: docs and comments

- [ ] 5.1 `knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md:87` — replace
      the `coverage: multi-config` exit condition.
- [ ] 5.2 One-line premise corrections: `apps/web-platform/infra/tunnel.tf:277`,
      `apps/web-platform/infra/workspaces-luks.tf:78,114`. Do not re-derive their blast-radius
      arguments.
- [ ] 5.3 Write `ADR-155`. Provenance cites the per-config census, not the inheritance
      metadata. `## Decision` must contain the literal `credential count, not config count`.

## Phase 6 — Verification

- [ ] 6.1 Walk AC1–AC23 and AC29–AC32 in order, running each command and recording its output.
- [ ] 6.2 `bash scripts/test-all.sh` — the gate's own invocation, not a subset.
- [ ] 6.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 6.4 `bun test plugins/soleur/test/terraform-target-parity.test.ts` and confirm
      `grep -c 'token_drift'` on that file is 0.
- [ ] 6.5 Confirm `actionlint` is clean on both edited workflows, and `bash -c` the extracted
      `run:` snippets (never `bash -n` a workflow file).

## Phase 7 — Ship

- [ ] 7.1 PR body uses `Closes #7159` (the decision is implemented at merge; the post-merge
      steps are automatic once the environment gate releases).
- [ ] 7.2 File the UC-2 deferred-capability issue with its re-evaluation criteria, labelled
      `deferred-automation`.
- [ ] 7.3 `/ship` renders `decision-challenges.md` into the PR body and files the
      `action-required` issue for UC-1 and UC-2.
- [ ] 7.4 Post-merge: AC24–AC28 against the infra run and the first scheduled scan after the
      credential lands.

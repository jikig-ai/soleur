# Tasks — feat-one-shot-7159-doppler-prd-read-token-coverage

Derived from
`knowledge-base/project/plans/2026-08-02-feat-token-drift-prd-root-token-and-coverage-denominator-plan.md`
(v4, retargeted 2026-08-03 to the project-scoped service-account shape). Phase order is
dependency-correct: every contract lands before its consumers.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-read `scripts/check-cloudflare-token-drift.sh` argument loop (`:73-93`),
      enumeration (`:99-107`), the four read sites (`:138`, `:223`, `:505`, `:506`), and
      `emit_json` (`:567-610`). Confirm the line anchors still hold.
- [ ] 0.2 Re-run probe D against the pinned provider and confirm the three resource types and
      their attribute names — in particular that the token's value attribute is **`api_key`**,
      not `key`. A schema drift here changes FR1 and AC1.
      `terraform -chdir=apps/web-platform/infra providers schema -json`
- [ ] 0.3 Confirm `ADR-158` is still the next free ordinal against a freshly fetched
      `origin/main`. If not, renumber and sweep the plan, spec, this file and every AC:
      `grep -rn 'ADR-15[0-9]' knowledge-base/project/{plans,specs}/feat-one-shot-7159-doppler-prd-read-token-coverage/`
- [ ] 0.4 Re-check the two anti-vacuity floors (`token-drift-workflow-causes.test.sh:525`
      `-lt 28`; `check-cloudflare-token-drift.test.sh:1084` `-lt 53`). Both suites run at
      exactly their floor, so any added assertion forces a raise.
- [ ] 0.5 Confirm the `-target=` default block still runs `:465`–`:573` in
      `apply-web-platform-infra.yml`, and that it has room for **four** new lines.
- [ ] 0.6 Re-run probe G and confirm the live config count is still 13. It is the value of
      `DOPPLER_CONFIGS_FLOOR` and the length of the inventory; if it has moved, both move with
      it before anything else is written.

## Phase 1 — Contract: the detector (RED first)

- [ ] 1.1 Producer tests P1, P10 (zero-config invocation unchanged with `--configs-floor` and
      `--inventory` absent; unknown flag exits 2). RED.
- [ ] 1.2 Replace the argument loop's `*) shift ;;` catch-all with an error + exit 2. GREEN.
- [ ] 1.3 Producer tests P2, P2b, P4, P5, P9 (13 configs at floor 13 → `at-floor`; 14 at floor
      13 → still `at-floor`; unset/empty `DOPPLER_TOKEN` is a failed credential with no ambient
      fallback; a non-empty credential enumerating nothing exits 2 with stderr visible; no
      credential value reaches child argv). RED.
- [ ] 1.4 Implement the single-credential path: env-prefix delivery, unset/empty handling
      (record the failure, never the value), and removal of the `2>/dev/null` on the
      enumeration. **Do not** add `DOPPLER_TOKEN_ENVS` or any credential-iteration surface —
      the detector loops configs, not credentials. GREEN.
- [ ] 1.4b Producer tests P11–P15 (sentinel absent from all six sinks; a bogus credential's
      stderr does not echo it; `::add-mask::` emitted per distinct scanned value under
      `GITHUB_ACTIONS=true`, exercised at 13 configs; `DOPPLER_TOKEN`/`DOPPLER_CONFIG` unset
      once the credential is snapshotted). RED, then implement.
- [ ] 1.4c `unset DOPPLER_TOKEN DOPPLER_CONFIG` immediately after snapshotting the credential
      into a local — a missed read site must fail loudly, not bind the ambient config.
- [ ] 1.5 Producer test P3: every one of the four `doppler secrets` reads passes an explicit
      `-c <cfg>` matching the config being graded. Include the mutation check (shuffle the
      config at one site, confirm RED). RED then GREEN.
- [ ] 1.6 Thread the enumerated config list through all four read sites.
- [ ] 1.7 Producer tests P5b, P5c (the three narrowings produce `degraded` at `0/13`, `7/13`,
      `1/13`; and 13 enumerated with every read failing yields `configs=0`, not 13). RED, then
      make `configs` count configs whose read **succeeded**. Include the mutation check: count
      listings instead and confirm P5c goes red.

## Phase 2 — Contract: the ladder moves into the detector

- [ ] 2.1 Producer tests P6, P7, P7b, P8 (`configs_unread`, `coverage_ratio`,
      `inventory_age_days`; a short inventory changes the ratio and nothing else; a long
      inventory likewise; a missing inventory still derives `coverage` from the floor). RED.
- [ ] 2.2 Add `--inventory <path>` and `--configs-floor <n>` (default 1); compute
      `configs_floor`, `configs_expected`, `configs_unread`, `coverage`, `coverage_ratio`,
      `inventory_age_days`. Evaluation order: `unknown` → `degraded` → `at-floor`, with the
      gate as `configs >= configs_floor` — **`>=`, not `==`**, so legitimate growth (C9) is not
      a regression.
- [ ] 2.3 Extend `emit_json` with the new fields. Give the third and fourth variable-length
      lists **distinct argv sentinels** — `rest.index("--")` cannot serve two — and re-index the
      leading scalars.
- [ ] 2.3b Move `emit_json` **before** every exit-2 return (the enumeration guard at `:104-107`
      and the non-vacuity gate at `:184-192`), so a revoked credential still publishes
      `configs`, `configs_floor`, `coverage` and `coverage_ratio`. Exit codes unchanged.
- [ ] 2.4 Update the human report line (`configs scanned:`) to carry the enumerated names — all
      13 in the steady state.
- [ ] 2.5 Correct the falsified remedy at `scripts/check-cloudflare-token-drift.sh:629`.
- [ ] 2.6 Raise the producer floor to 68 (confirm against the realized `PASS + FAIL` count and
      raise further if it is higher).

## Phase 3 — The credential (IaC)

- [ ] 3.1 Create `apps/web-platform/infra/token-drift-service-account.tf` with the four
      resources: `doppler_service_account.token_drift`,
      `doppler_project_member_service_account.token_drift` (`role = "viewer"`),
      `doppler_service_account_token.token_drift` (with
      `depends_on = [doppler_project_member_service_account.token_drift]`), and
      `github_actions_secret.doppler_token_drift` fed from **`.api_key`**.
- [ ] 3.1b Header content, all load-bearing: `autonomy-considered: provider-mint-applied`; the
      rotation recipe `-replace=doppler_service_account_token.token_drift`; the reason no
      `ignore_changes` is present; why `expires_at` is unset; and a BLAST RADIUS block in the
      `workspaces-luks.tf:77-89` shape stating that the credential reads the **whole `soleur`
      project** and is **wider** than `DOPPLER_TOKEN_PRD`. The v3 sentence "adds no new
      capability" must **not** appear (AC30).
- [ ] 3.1c Adjacent comments explaining each deliberate absence — `environments`,
      `workplace_role`, and the empty `workplace_permissions` — carrying the literal `deliberately unset`
      (AC33). An unexplained absence reads as an oversight and invites a "fix".
- [ ] 3.2 Add the **four** `-target=` lines to the **default** block only, including the
      membership. Do not touch `terraform-target-parity.test.ts`.
- [ ] 3.3 `terraform fmt` and `terraform validate` in `apps/web-platform/infra`.
- [ ] 3.4 Create `apps/web-platform/infra/doppler-config-inventory.txt` with the
      `# generated: 2026-08-03…` ISO-8601 header, the `# command:` line, and the 13 sorted
      names from probe G.

## Phase 4 — Consumers: the workflow

- [ ] 4.1 Consumer-suite rewrites (T6, T7, T8, T8b, T13, T13b, T14, T14b, T14c, T14d, T16,
      T16b, T17, T19) plus the new cases. RED.
- [ ] 4.2 `token_drift` step: repoint `DOPPLER_TOKEN` to `${{ secrets.DOPPLER_TOKEN_DRIFT }}`
      (a literal swap — `secrets.DOPPLER_TOKEN` must not remain in the step); remove
      `DOPPLER_CONFIG`; add `DOPPLER_CONFIGS_FLOOR: 13`; publish the new outputs. The
      unset/empty/unparseable-floor guard **writes `coverage=unknown` and `verdict=unavailable`
      to `$GITHUB_OUTPUT` first, then fails** — failing first leaves every arm unmatched and the
      Sentry check-in still `ok`. Add the external `configs_floor >= 13` assertion (downgrade to
      `degraded`). Keep `configs` last-and-greedy in `read -r`, add non-empty guards on every
      new field, and move the fallback arity in lockstep.
- [ ] 4.2b Update the verdict echo line (`:251`) to carry `floor:` and `ratio:` — the
      discoverability test and AC26 both assert those fields.
- [ ] 4.2c **The floor pin (AC29.3).** In
      `plugins/soleur/test/token-drift-workflow-causes.test.sh`, read `DOPPLER_CONFIGS_FLOOR`
      out of the workflow, assert it parses as an integer `>= 13` (a named integer), and assert
      it **equals** `grep -cE '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt`.
      This is the CI check that fails when floor and inventory drift apart. No credential, no
      network.
- [ ] 4.3 `::warning::` arms for `degraded` and `unknown`; delete the retired arms.
- [ ] 4.4 Coverage filer: positive `if:` over `degraded`/`unknown`; per-class TITLE/LEAD;
      `degraded` body lists `configs_unread` and the ratio; **create-or-update-body** via
      `gh issue edit --body-file` on the existing-issue path; no `gh issue comment`.
- [ ] 4.4b Branch on `gh issue edit`'s exit status; emit
      `token_drift_coverage_update_failed` on failure. Keep the label re-assert as a separate
      `|| true` call so the body edit's status is not swallowed into it.
- [ ] 4.4c Add an ops-email fallback step gated on a filer output flag set by any named
      `::error::`, so a dead issue channel still reaches the operator.
- [ ] 4.5 Filer Remedy prose (`:461-476`) and Closing prose (`:481-485`). The remedy names the
      service account and the `viewer` membership — the literal `project-scoped read token` must
      be gone (AC7) — and describes the three narrowings rather than telling the reader to widen
      a token that is already project-wide.
- [ ] 4.6 Close arm → `coverage == 'at-floor'`; update its comment body to name `13/13`.
- [ ] 4.7 DEAD ops email (`:280`) and DEAD issue body (`:584`, `:595`) — the inheritance
      remedy and the closing condition.
- [ ] 4.8 Both `<em>Scan coverage: …</em>` spans (`:280`, `:645`) — carry `coverage_ratio`,
      byte-identical to each other.
- [ ] 4.9 FR7: the `_cfgs=` pipeline (`:1115-1116`) — drop `2>/dev/null` and `|| true`,
      capture status explicitly (the block is `set -euo pipefail`), publish it as its **own**
      step output, and give it its **own** filer with its own title and lead. Do NOT fold it
      into `steps.sweep.outputs.orphans` — that filer is gated `orphans != '0'` plus an
      implicit `success()`, and its body claims the listed items are paying hosts. Do NOT wire
      `DOPPLER_TOKEN_DRIFT` into that job: the new credential keeps exactly one consumer.
- [ ] 4.10 Raise the consumer floor to 37 (confirm against the realized `PASS + FAIL` count and
      raise further if it is higher).

## Phase 5 — Consumers: docs and comments

- [ ] 5.1 `knowledge-base/engineering/operations/runbooks/ci-ssh-token-replace.md:87` — replace
      the `coverage: multi-config` exit condition with `coverage: at-floor`.
- [ ] 5.2 One-line premise corrections: `apps/web-platform/infra/tunnel.tf:277`,
      `apps/web-platform/infra/workspaces-luks.tf:78,114`. Do not re-derive their blast-radius
      arguments.
- [ ] 5.3 Write `ADR-158`. Provenance cites the 2026-08-02 census and the 2026-08-03 probes,
      not the inheritance metadata. `## Decision` must contain the literals
      `declared floor, reported ratio` and `project-scoped service account`, and must record the
      falsified #7159 premise.

## Phase 6 — Verification

- [ ] 6.1 Walk AC1–AC23 and AC29–AC34 in order, running each command and recording its output.
- [ ] 6.2 `bash scripts/test-all.sh` — the gate's own invocation, not a subset.
- [ ] 6.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 6.4 `bun test plugins/soleur/test/terraform-target-parity.test.ts` and confirm
      `grep -c 'token_drift'` on that file is 0.
- [ ] 6.5 Confirm `actionlint` is clean on both edited workflows, and `bash -c` the extracted
      `run:` snippets (never `bash -n` a workflow file).
- [ ] 6.6 Confirm the union is fully gone: `grep -rc 'DOPPLER_TOKEN_ENVS' .github/ scripts/`
      = 0, and the token-drift step contains no `secrets.DOPPLER_TOKEN` reference (AC5).

## Phase 7 — Ship

- [ ] 7.1 PR body uses `Closes #7159` (the decision is implemented at merge; the post-merge
      steps are automatic once the environment gate releases).
- [ ] 7.2 `/ship` renders `decision-challenges.md` into the PR body and files the
      `action-required` issue for UC-1 (superseded), UC-2 (adopted) and UC-3. **No
      deferred-capability issue is filed for UC-2** — it was adopted, not deferred.
- [ ] 7.3 Post-merge: AC24–AC28 against the infra run and the first scheduled scan after the
      credential lands. AC24 requires `4 to add`; `3 to add` is a failure, and the missing leg
      is almost certainly the project membership.

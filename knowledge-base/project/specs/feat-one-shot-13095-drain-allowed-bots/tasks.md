# Tasks — feat-one-shot-13095-drain-allowed-bots (#13095)

Derived from `knowledge-base/project/plans/2026-11-27-fix-scheduled-machinery-drain-allowed-bots-plan.md`.

## Phase 1: Implementation

- [x] 1.1 Edit `.github/workflows/scheduled-machinery-drain.yml` — in the
      `with:` block of the `Drain the machinery ledger` step, add
      `allowed_bots: "soleur-ai[bot]"` immediately after the
      `anthropic_api_key:` line, preceded by the explanatory comment drafted
      in the plan's `## Implementation` section. No other line changes
      (AC2: `uses:` pin, `prompt`, `claude_args`, `continue-on-error`,
      permissions and all other steps byte-identical).

## Phase 2: Local verification

- [x] 2.1 YAML parses and the input is present (selects the step by name,
      not position):
      `python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/scheduled-machinery-drain.yml")); s=[x for x in d["jobs"]["measure-and-drain"]["steps"] if x.get("name")=="Drain the machinery ledger"][0]; print(s["with"]["allowed_bots"])'`
      prints `soleur-ai[bot]`.
- [x] 2.2 `bash plugins/soleur/test/machinery-drain-floor.test.sh` — green.
- [x] 2.3 `bash plugins/soleur/test/claude-code-action-auth.test.sh` —
      green (job-level `id-token: write` still resolves the step).
- [x] 2.4 `bun test apps/web-platform/test/claude-pin-lockstep.test.ts` —
      green (`uses:` SHA→tag pair unchanged).
- [x] 2.5 `bash scripts/lint-scheduled-show-full-output.sh
      .github/workflows/scheduled-machinery-drain.yml` — green (no
      `show_full_output` added).
- [x] 2.6 `python3 scripts/lint-infra-no-human-steps.py
      knowledge-base/project/plans/2026-11-27-fix-scheduled-machinery-drain-allowed-bots-plan.md`
      — clean.

## Phase 3: Ship

- [ ] 3.1 Commit the one-file diff; PR body carries `Closes #13095`.
- [ ] 3.2 Confirm `actionlint` and the required `test` context green on the
      PR before merge.

## Phase 4: Post-merge verification (acceptance — see plan §Post-Merge Verification)

- [ ] 4.1 On the next weekly Monday 09:00 UTC Inngest dispatch (default —
      no authorization needed), or an authorized
      `cron/machinery-drain.manual-trigger` fire, read the `Drain the
      machinery ledger` step's LOG on the dispatched run:
      `gh run view <run-id> --log | grep -n "non-human actor"` — expect no
      match. (AC3 — read the step log, never `conclusion`.)
- [ ] 4.2 Confirm the run reports `closed > 0` on `meta/machinery` issues,
      or a floor verdict naming a different diagnosed failure. (AC4)
- [ ] 4.3 Confirm the verdict comment landed on standing issue #9508. (AC5)
- [ ] 4.4 Optional supplementary (delegable, proves pipeline health not the
      allowlist): `gh workflow run scheduled-machinery-drain.yml` then poll
      the run. Caveat: a human dispatch passes the actor gate trivially —
      do not read it as allowlist verification.

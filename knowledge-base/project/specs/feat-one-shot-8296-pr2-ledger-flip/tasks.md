# Tasks: PR-2 of #8296 (the record)

These tasks come from
`knowledge-base/project/plans/2026-09-21-chore-8296-pr2-flip-inngest-luks-ledger-record-plan.md`
after plan review. Parent tasks: `knowledge-base/project/specs/feat-one-shot-8296-ledger-flip-arm-alert/tasks.md`
Phase 5 (5.1–5.12). Gate met: PR-1 `b53173a04`, apply run 35605929787, alert 2988582970
`paused=false`.

**Hard constraints.**

- Touch nothing under `apps/web-platform/infra/**`, `.github/workflows/**`, or `infra/sentry/**`.
- Make no production mutation.
- Ask the operator before merging. Do not auto-merge.

## Phase 0: Setup

- [ ] 0.1 Re-verify that the facts still hold on the final diff: AC-G2, AC-G3, AC-38.
- [ ] 0.2 File **D1** (the dead-probe heartbeat, trigger 2026-10-22). Run a dedup search first and
      set a milestone. Record its number. Its body names "cite this issue inside
      `logtail_exploration_alert.inngest_luks_wrong_volume` in the next PR that edits that file" as
      its first task.

## Phase 1: Ledger (5.1–5.3)

- [ ] 1.1 Dry-run both row rewrites against a scratch ledger copy with
      `lint-encryption-posture.py --ledger`, then edit in place.
- [ ] 1.2 `hcloud_volume.inngest_redis_luks`:
      - set `mechanism: luks` and delete the `exception` block;
      - write a single content-anchored `evidence` string;
      - update `defends_against`;
      - make `does_not_defend` name `hcloud_volume.inngest_redis` and D1;
      - set `live_verification` to `unavailable:` plus the cipher-half gap, citing #8423's
        `store_luks` as the precedent.
- [ ] 1.3 `hcloud_volume.inngest_redis`:
      - keep `plaintext-exception` and rewrite it as the retained backstop;
      - `tracking_issue` → `#8285`;
      - `reassessed_on` → `2026-09-21`;
      - add `INNGEST_LUKS_CUTOVER=rolled-back` to `reevaluate_when`;
      - leave `expires_on` and `expires_on_not_extended` **byte-untouched**.
- [ ] 1.4 Assert AC-1…AC-10 and AC-6/AC-6b (re-baselined: floor `2`, `available` count `2`).

## Phase 2: Records (5.4–5.7)

- [ ] 2.1 Article 30 register, PA-21 §(f), PA-22 §(f) and PA-13 §(e):
      - write `[2026-09-20 AMENDMENT (#8296)` / `[Superseded 2026-09-20 (#8296)` brackets;
      - keep "Two copies, bounded" and the EXPIRED clause verbatim;
      - include `the apply that follows` in each cell;
      - record that the apply ran (35605929787) and the alert read back unpaused.
      Check AC-18…AC-22.
- [ ] 2.2 `model.c4`: replace the description of `platform.infra.inngestRedis`. Then run
      `bash scripts/regenerate-c4-model.sh` and check AC-23, AC-24 and AC-24b.
- [ ] 2.3 ADR-142: append an amendment covering the observed cutover and the correction to
      apparatus scope item 8. Check AC-27.
- [ ] 2.4 ADR-218: append an amendment saying "It ships PAUSED" is falsified. Check AC-27b.
- [ ] 2.5 Update `betterstack-log-query.md` line 47. In runbook §5 step 4, add the new wording:
      #8285 enrollment, #8296 closed by hand, D1. Leave step 2 alone. Check AC-28.

## Phase 3: Scripts (5.8, 5.9)

- [ ] 3.1 `scripts/followthroughs/inngest-luks-cutover-6894.sh`: re-point `NEXT` at #8285 and
      set `RETIREMENT:` to 2026-10-04 with no sibling. Change comment and echo text only; exit
      statements stay as they are (AC-32b).
- [ ] 3.2 `scripts/cutover-inngest.sh`: add one `NEXT (not automatic):` line that names the
      ledger and the register. Place it right after the `FSM confirmed '$LK_EXPECT'` notice, behind
      an explicit `[[ "$OP" == luks-rollback ]]` guard, because `luks-cutover` shares that notice.
- [ ] 3.3 Run the `cutover-inngest-workflow.test.sh` floor (665/665).

## Phase 4: Property probe (5.10, notify-only)

- [ ] 4.1 **RED first.** Write `scripts/followthroughs/inngest-luks-property-8296.test.sh` from
      Guard 3:
      - copy the fake-tree stub and `run_probe()` sandbox from `registry-luks-live-8386.test.sh`;
      - every Decision-table row, with a branch marker per case;
      - harness rows H1–H5;
      - the never-0/1 allowlist scan (strip comments, exclude quotes), fall-through and
        unset-variable cases, and `assert_never_close_verb`;
      - an "output never contains `exit`" check;
      - the rollback-NEXT placement check for `scripts/cutover-inngest.sh` (AC-32), including the
        label-found-once and non-empty extraction assertions;
      - **committed** code-mutation rows 5, 7, 8, 9 and 10 on scratch copies, each with a landing
        assertion, after a known-positive and known-negative self-test;
      - pin `SOLEUR_FT_NOW` in every fixture, with times kept away from the 3 h and `expires_on`
        edges;
      - a hard-coded `FLOOR` literal.
- [ ] 4.2 **GREEN.** Write `scripts/followthroughs/inngest-luks-property-8296.sh`:
      - carry the `NOTIFY-ONLY` / `never closes #8285` header;
      - use `set -uo pipefail`, the xtrace refusal (78), and
        `--since 26h --limit "${SOLEUR_FT_LIMIT:-5000}"`;
      - derive `REPO_ROOT` from the script's own dirname, not `git rev-parse`;
      - take the newest row by `.dt`, with a 3 h staleness check;
      - read the clock from `SOLEUR_FT_NOW`; a malformed value exits 3 `clock_malformed`;
      - map unreadable values to 3 and require the devid;
      - read the ledger after the measurement;
      - fire `backstop_expired` (exit 5) ONLY when the ledger claims luks, the store is on the LUKS
        mapper, and `expires_on` has passed, and check it before `agree`;
      - otherwise, the equivalence `claims_luks == on_luks_mapper` gives exit 2;
      - install an EXIT trap that remaps 0/1 to 3 (precedent: `inngest-soak-6178.sh`);
      - make the final line `exit 3`;
      - write `RETIREMENT:` to say coverage ends when #8285 closes;
      - on exit 5, output "backstop is the LIVE store — do NOT destroy" and point to runbook §5.
- [ ] 4.3 Register `run_suite "scripts/inngest-luks-property-8296"` in `scripts/test-all.sh`. Run
      `lint-orphan-test-suites.sh` and `lint-followthrough-varq-ban.sh`.
- [ ] 4.4 Check that the committed mutation rows go red. Record each verdict in the PR body
      (AC-29).
- [ ] 4.5 **Mandatory live read (AC-29d).** Run one read-only invocation with the Better Stack
      query credentials from Doppler `prd_terraform`. Expect `agree` with exit 2. Paste it into the
      PR body.

## Phase 5: Deletion (5.11)

- [ ] 5.1 `git rm scripts/followthroughs/inngest-luks-staging-6894.sh`. Check AC-31. In the PR
      body, call it "obsolete", not "permanently falsified".

## Phase 6: Verification

- [ ] 6.1 Check every PR-2 AC in the plan: AC-G2/G3, AC-1…AC-10, AC-6b, AC-18…AC-24b, AC-27/27b,
      AC-28, AC-29/29b/29d, AC-31, AC-32/32b, AC-33, AC-35, AC-37, AC-38, AC-40.
- [ ] 6.2 Unchanged-gate floors: 96/96, 57/57, 665/665, 160/160, 79/79.
- [ ] 6.3 Run `python3 scripts/lint-encryption-posture.py --repo-sweep`,
      `bash scripts/lint-encryption-posture.test.sh` and
      `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 6.4 Run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exactly
      as written.
- [ ] 6.5 PR body (AC-39):
      - **First line:** merging this alone mutates nothing in production (fact (c)).
      - Say `Ref #8296`.
      - Do not mention #7529.
      - Put no closing keyword next to any `#N` (AC-39b).
      - Include the mutation REDs and the live verdict.
      - Include the decision challenges.
- [ ] 6.6 **Ask the operator before merging. Do not auto-merge.**

## Phase 7: Post-merge (agent-run, GitHub writes only)

- [ ] 7.1 Enroll on #8285:
      - add the `follow-through` label;
      - add the column-0 directive with `earliest=<merge+1d>`;
      - add the line "Do NOT close before the backstop is destroyed";
      - add the retirement line.
      Read it back (AC-30).
- [ ] 7.2 Dedup-search, then file D3, D4, D5, D8, D10, D11, D2, D6, D7 and D12 with milestones.
      Put D9's evidence in a comment on #6907.
- [ ] 7.3 Strip the directive from the #8294 body.
- [ ] 7.4 Close #8296 with `gh issue close 8296` once AC-P8's gates hold. List every deferral
      number in the closing comment.
- [ ] 7.5 Compound, including the deferred Step E archival of the parent spec dir and plan.

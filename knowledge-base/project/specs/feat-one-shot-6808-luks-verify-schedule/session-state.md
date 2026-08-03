# Session State

## Where this stopped, and why it is NOT ready to ship

**Implementation is COMPLETE and verified. The REVIEW is not.** All 11 review agents failed to
return: the session hit its API limit (resets 21:00 Europe/Paris) and the three spawned agents
terminated mid-run with no findings. Coverage is recorded honestly in the commit trailer as
`Reviewed-Coverage: inline-fallback 0/11 agents`.

The plan declares `brand_survival_threshold: single-user incident`, and `/soleur:review` Gate 2a
forbids marking a PR ready at that threshold with zero agents. **The next step is therefore NOT
`/compound` → `/ship`.**

**Resume with: re-run `/soleur:review` with the agent panel once the limit resets.**

Do not read the green gates below as a substitute for that. #7146 is the precedent: a 0-of-10
review labelled itself degraded, left `/ship` as the next step anyway, and the eventual re-run
found ~60 findings, 15 P1, 3 of them merge blockers.

## Verified green (all re-run at HEAD)

| Gate | Result |
|---|---|
| `scripts/test-all.sh` | **253/253**, rc=0, infra dir covered via the nested runner |
| `run-registered-suites.sh` | 88/88 |
| `workspaces-luks-verify-workflow.test.sh` | **75/75** (69 → 75 after the review fixes) |
| `function-registry-count` + `sentry-monitor-iac-parity` | 18/18 |
| `scripts/lint-workflows.sh` | rc=0; repo-wide findings unchanged at **107** (this PR adds 0) |
| `scripts/check-adr-ordinals.sh` | pass |
| shellcheck on the new suite | clean |
| sentry-root `terraform plan` | **1 to add, 0 to change, 0 to destroy**; create + destroy gates pass, no ack |

Mutation evidence: 13 mutations RED against a GREEN baseline (alarm `if:` conjuncts, classifier
direction, seed guard, crontab parity, …), plus a 14th proving the newly-covered
refuse-to-lower-baseline guard. Every run restored the workflow byte-identical to a pristine
backup, verified with `diff -q` against that backup rather than against HEAD.

## One earlier RED, resolved — do not re-litigate

`run-migrations-schema-probe.test.sh` failed in one full run. Confirmed **contention, not this
diff**, three ways: isolated re-run 4/4; it passed in the prior full run; the failing run logged
`git fetch origin main failed` and the passing one did not. The final clean run is 253/253. The
suite shells out to a live `git fetch` inside a unit test — filed as **#7235**.

## Findings fixed inline during the degraded pass

1. **P2 — a shadowed stub arm hid a data-safety guard.** `*WORKSPACES_COUNT=*` preceded the
   baseline-read arm, and the read command embeds that literal, so the read arm was unreachable and
   the workflow's *refuse-to-lower-baseline* guard had zero coverage behind 69 green assertions.
   That guard is what stops an operator staring at a `workspace_count_shortfall` from re-seeding
   down to the observed count and certifying a real data-loss finding green. Reordered the arms,
   added 3 assertions, mutation-proven (`if false` → all 3 RED).
2. **3× shellcheck SC2034** — unused captures converted into assertions rather than deleted
   (no-seed and dispatch-seed runs still classify `pass`; the alarm body completes under
   `set -euo pipefail`, pinning the classify-then-file-nothing case).
3. Confirmed, no change needed: all three new step conditions are explicitly parenthesized, so
   GitHub's `&&`/`||` precedence cannot affect them.

## Corrections the operator caught mid-session (both real)

- **The Inngest claim was wrong in 4 places.** The *scheduler* moved to `hcloud_server.inngest`
  (10.0.1.40) at the #5450 cutover; *execution* is still pinned to web-1 via
  `sdk_url = "http://10.0.1.10:3000/api/inngest"`. The anti-circularity conclusion survives and is
  sharper — a dispatching cron would execute on the subject itself — but "the Inngest dispatcher
  runs on web-1" conflated scheduler with executor. Fixed in the workflow header, ADR-033,
  `model.c4` and the drift-guard comment.
- **Filed #7230** to decouple Inngest execution from web-1, scoped to execution rather than the
  scheduler. 34 of 53 cron functions spawn `claude-code` and several operate on the sole-copy
  `/mnt/data` volume, so the realistic shape is a split, not a move.

## Deliberate deviations from the plan — review should challenge these

- **AC1 contradicts Decision 2.** AC1 demands the `workflow_dispatch:` block be byte-identical to
  main; Decision 2 mandates adding `alarm_selftest` to that same block. Resolved by keeping
  `seed_workspace_count` byte-identical (asserted by the suite) and adding the sibling input.
- **AC4's verification method was changed.** "no modified `::error::` line" is unsatisfiable
  alongside the exit-site map, since several exits are inline `|| { echo …; exit 1; }` one-liners
  that must gain an `emit_class`. Verified instead as set-equality over the *messages* and *exit
  codes*: zero removed or altered, `LC_ALL=C` sorted.
- **Phase 1.1's reopen-not-recreate bullet is stale** relative to Decision 2, which deleted
  auto-close and with it the reopen path. Deliberately not implemented.

## Follow-ups filed (net issue flow: 0 closed / 3 filed)

- **#7226** — cf-tunnel-ssh-bridge accepts web-1's host key unverified on every connection (TOFU
  with no persistence). Pre-existing; shared with three other workflows.
- **#7230** — Inngest function execution pinned to web-1.
- **#7235** — `run-migrations-schema-probe` depends on a live `git fetch` inside a unit test.

## Non-negotiables still intact

`Ref #6808`, never `Closes` — this satisfies only the "schedule exists" half of that issue's
recorded closure condition, and the counsel audit's §A3.4 rec 2 was corrected to read as a
conjunction precisely so the schedule cannot be used to close it. No published `docs/legal/*` file
is touched (verified: 0). The four grep-shape couplings to the workflow (freeze AC7/AC10,
luks-monitor case (y), header H15b/H20) all re-run green.

---

## Plan Phase (unchanged, retained for provenance)

- Plan file: `knowledge-base/project/plans/2026-08-03-feat-luks-verify-scheduled-with-alarm-plan.md`
- Tasks: `knowledge-base/project/specs/feat-one-shot-6808-luks-verify-schedule/tasks.md`
- Draft PR: #7196
- Status: complete

### Errors
None. All premises validated live: #6808 OPEN, PR #7196 draft, 8 prior runs all `workflow_dispatch`, baseline `workspace_count=8 expected=8`, no `ci/luks*` label. All deepen-plan gates (4.5–4.10, 4.55) pass; 4.5 fired on keywords and produced an L3→L7 deep-dive.

### Decisions
- **Daily at `41 4 * * *`.** Justified on two facts rather than "minutes are free" (that argument was deliberately excluded per CTO): while #6808 is open this is the compensating channel for a *daily* heartbeat push, and the readyz+inventory dimension has **zero** host-side coverage (`LUKS_MONITOR_ASSERT_READYZ` is default-OFF because `RequiresMountsFor=/mnt/data` makes the daily unit inert in the reboot hazard). The steelmanned counter — boot-immutable ⇒ event hook + weekly — is recorded and rejected because half the probe is not boot-immutable.
- **Three alarm classes, one label, three titles:** `drift` (counsel re-evaluation trigger 3) / `readiness` / `unavailable`; dedupe by label + exact title, per the documented reason `--search` was abandoned. Classification is **reason-first, rc-second** — an rc-first classifier would have fired a p0 `type/security` legal alarm for `mapper_path_override_refused`, a config fault that exits 1.
- **`checkin_margin_minutes = 420` paired with `failure_issue_threshold = 2`.** Margin 1440 blinds the monitor to a single missed fire (its whole purpose); dropping the margin alone re-introduces the #4189 false page. The threshold reconciles them.
- **Three blocking legal items folded in (CLO):** the Article 30 register and the counsel audit's `claim_decay_trigger` both become false on merge; absence detection is required because the decay trigger's defeat condition is *absence*, not failure. Published `docs/legal/*` must NOT be edited.
- **Cut on the simplicity panel:** extracted classifier + suite, a new ADR ordinal (ADR-033 amended instead), the follow-through probe, the green-close step and the two anti-spam mechanisms it forced. 13 files → 9; 2 new files → 1.

### Two defects the plan would otherwise have shipped
- The prescribed alarm `if:` cited the *heartbeat* half of its precedent — unreachable on every failure run.
- `infra-validation.yml`'s `paths:` omits `.github/workflows/workspaces-luks-verify.yml`, so every guard would have been born unreachable on a YAML-only PR. **Independently re-verified by the parent** — the workflow file is not a `paths:` entry; the `workspaces-luks-verify*.test.sh` occurrences in that file are `run:` steps, not path filters.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`, `soleur:work`, `soleur:review` (degraded); agents: `Explore` ×4, `soleur:legal:clo`, `soleur:engineering:cto`, `soleur:engineering:review:code-simplicity-reviewer`, `soleur:product:spec-flow-analyzer`; `gh`, `git`, `terraform`, `doppler`, `emit_incident`.

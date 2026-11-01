---
title: CLO ruling record, counts-only production-HOME census method (#10455)
date: 2026-10-31
status: C8 pending
---

# CLO ruling record: counts-only production-HOME census method

The CLO approved the exact census mechanism with conditions C1-C10 on 2026-10-31. The reasoning, the later rulings (C9 terminal
state, field cuts, sunset bound, executor, result publication) and the CTO rulings are recorded in
`knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/decision-challenges.md`; this file does not restate them.

This file carries one thing only: the C8 entry. C8 requires the CLO to re-read the final scanner, emitter and class-table diff
against the ruling before any real run. The entry is appended (append-only), naming the reviewed commit, after that re-read, as ONE line
that consists only of the word DISCHARGED, a space, and `sha=` followed by the 40 lowercase hex characters (the trigger script matches that
whole line exactly, so it must stand alone, with no other text on it); the trigger script refuses a real run unless the same commit is named here, in a `home-census C8 DISCHARGED`
comment on #10455 from a pinned author, and the served build's census paths equal that commit.

## Conditions the CLO set before recording C8 (dissent round, 2026-10-31)

1. The D1-D9 rulings are swept into the runbook, the ADR-075 addendum, the plan and compliance-posture with Superseded markers, and the absence greps are clean.
2. Test floors present: `account_state` alone reads `inconclusive`; an all-inconclusive result reads `inconclusive`, not `false`; a truncated or erroring class mixed with others reads `unknown`; the witness mutant is killed in the reviewer-run battery.
3. The `interpretation` change is mirrored in the server validator, the jq schema and the tests' independent allowlist.
4. The sunset constant is at most merge date + 30 days.
5. The script's working-tree self-check is present and tested.
6. A fresh DISCHARGED is needed if any bound file changes after the CLO's re-read, including a sunset-only change.

## C8 entries

C8 re-read: pending. No commit is discharged yet.

### 2026-10-31, C8 re-read (CLO, dissent-round conditions 1-6)

Reviewed commit: `8c77db1af6b83270129e132cfafe20774c1cfcfd` (branch `feat-one-shot-10455-prod-home-census`, PR #11712). Its bound code is identical to
`5a4e3f2327`; the later commit adds only a learning document. I read the commit with `git show` and `git diff origin/main...8c77db1af6`, not from the earlier
rulings. This entry is an attestation of the mechanism as written. Nothing has been run against production; the census remains unrun.

What I read, against D1-D9 and C1-C10:

- **Scanner, class table, caps, control and canary** (`server/home-census.ts`): `lstat` and `opendir`/`read` only; names matched in the loop and never retained;
  symlinks counted and not followed; dev/ino re-checked after `opendir`; caps 20,000 entries, 20 s, per-class budgets, load shed; the four trigger classes scan first,
  then the witness classes; a symlinked, unlistable, cut-off or erroring class reads `unknown`, never zero; the positive control runs against an in-memory tree with
  per-class known answers, and the real-adapter canary is bounded. `real` is refused with 503 `control_failed` unless both passed. Roots are `env_home`, `home_soleur`,
  `root`; `CLAUDE_CONFIG_DIR`, `/workspaces` and `/tmp/.cs` are not scanned, and the outer-wrap cohorts are the constant `unmeasured`.
- **`classResult` / `buildResult`** (D1, D2, D4): the witness is `sessions_json` or `shell_snapshots` only; `account_state` is counted and is not a witness.
  `trigger_class_nonzero` is four-valued with precedence true, unknown, inconclusive, false, and `false` only when every trigger class read `none_counted`.
  `INTERPRETATION` reads "counted in this container's writable layer at the run; not a statement about earlier containers, other hosts, or any time before or after the run".
- **Validators**: the server's `assertAllowlisted` (key set, run_id, build_sha, mode, data_source, truncation_reason, four-state headline, per-class buckets and
  `class_result`, roots; the failure shape is checked against `INTERPRETATION`), the trigger script's jq `body_valid` and `failure_class` (exact key sets, closed enums,
  class order, `.interpretation == $interp`), and the independent allowlist in `test/server/home-census.test.ts` (includes the new string and the four-state enum);
  a parity test extracts the jq programs and the script's `INTERPRETATION` from the script and checks them against server output.
- **Emitters**: one pino line at level `warn` from a dedicated instance (`base: undefined`, no timestamp, synchronous destination); one Sentry event built from an
  allowlist inside `withIsolationScope` and `withScope` with a processor that returns a rebuilt event; no `err` field; constant messages; dry_run Sentry throttled.
- **Handler gate order**: 401/503 auth, sunset 410, content-length then bounded parse, strict key set, mode, build match, young gate, then in-flight flag and limiter
  claimed in one synchronous step with no `await` between check and set, control, canary, scan; the slot is refunded for any exit before the scan starts;
  `assertAllowlisted` runs before every sink; every catch returns a constant body.
- **Route, `lib/internal-auth.ts`, `server/sentry-scrub.ts`, `sentry.server.config.ts`**: the route is a one-line wrapper (HTTP exports only); the bound auth, scrub and
  Sentry-init files are unchanged by this PR, and the PR's only edit to `server/agent-outer-wrap.ts` is the `export` keyword on `HOME_STATE_FILES` and
  `HOME_SESSION_DIRS`, which the census module does not import.
- **Trigger script** (`apps/web-platform/scripts/home-census-trigger.sh`): `CENSUS_PATHS` binds `server/home-census*`, the route directory, `lib/internal-auth.ts`,
  `server/sentry-scrub.ts`, `sentry.server.config.ts` and the script; `cd` to the repository root before any pathspec check; `ls-tree` non-vacuity check; working-tree
  and `git status` self-check of the script against the discharged commit; this record is read from the served commit and the line must match whole; governance comments
  count only when the whole body is one governance line and the author id and association are pinned (I confirmed user id 54279 is the author of comment 6546444433,
  association MEMBER); two-claim cap, run_id above the last claim, write-ahead claim with up to three read-backs and fail-closed `gh`; exact jq schema; secret passed
  to curl on its stdin config only; every refusal on stderr and the body on stdout only after it validates.
- **Follow-through probe** (`scripts/followthroughs/home-census-run-10455.sh`): reads no secret and calls no network endpoint; its sunset constant equals the module's
  and a test pins the equality.
- **Sunset arithmetic** (condition 4): `SUNSET_UTC` is `2026-11-30T00:00:00Z`; today is 2026-10-31, so this is merge date plus 30 days at the earliest merge and less than
  that for any later merge. It is at the maximum and not above it.
- **Runbook, ADR-075 census addendum, compliance-posture entry, plan amendments** against my dissent-round text: the lifecycle wording (wiped when the container is recreated,
  not on a restart-policy restart; process uptime errs toward young), the four-state label never quoted, the three zero variants, the never-say list including "no activity",
  "nothing happened" and "negative result", "one real run, at most two; the second only after a recorded young result", governance self-attested, and the tense of
  unrun work ("will run" only when the conditions are met; "built but not run"). The retired phrases `since its last start`, `wiped at every`, `will run once` and
  `Earlier containers no longer exist` are absent outside `archive/` (`git grep` at the reviewed commit).

Evidence I produced myself, in sandbox copies of `apps/web-platform` (never the working tree): the full mutation battery
(`HOME_CENSUS_MUTATIONS=1 bash apps/web-platform/test/home-census-mutations.test.sh`) reported 22 red, 0 survived, 1 unresolved of 23 executed; the unresolved one (G4-3,
early exit after the first class) hit the script's 280 s vitest timeout under load, and I re-ran that mutation alone with a longer timeout and it is killed. Re-run alone:
G4-8 (`account_state` counted as a witness) fails three tests; G4-9 (all-inconclusive collapses to `false`) fails the inconclusive test. Condition 2 is met.

Residuals I accept (none voids this entry):

1. The server's `assertAllowlisted` does not assert the value of builder-constant strings on the success path (`interpretation`, `snapshot`, `mode_bits_semantics`,
   `outer_wrap_cohorts`, `control`, `evidence`, `uptime_bucket`, `sunset_utc`); only the failure shape carries the `INTERPRETATION` check. Every data-derived field is
   checked, the constants come only from the bound file, and both the test's independent allowlist and the trigger script's jq assert them.
2. On refusal under shell tracing the script prints a constant `HOME_CENSUS_TRIGGER_HALT` marker to stdout; it carries no data and the existing test pins exit 78.
3. `agent-outer-wrap.ts` is not a bound path; its only change here is the two `export` keywords and the census module does not import it.
4. `pino` and `@sentry/*` version bumps are not bound (D7, accepted residual). Governance is self-attested (D8).
5. The two-run cap and "second run only after a recorded young result" are enforced by the claim count and the runbook, not by a stored result; the public tracker gets only `done`.

Docs-only corrections required before merge. They touch no bound path and do not need a fresh DISCHARGED, but they must land with a `Superseded` marker under each
superseded sentence: `knowledge-base/project/plans/2026-10-31-feat-prod-home-census-plan.md` (the limiter sentence "resets on a restart (which also wipes the HOME)",
and "the HOME does not persist across container starts" in the premise-validation paragraph) and the Deepen-plan limiter row of
`knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/decision-challenges.md` ("resets on restart which also wipes the HOME"). Per D4 a restart-policy restart
resets the per-process limiter and keeps the HOME; only container recreation (a deploy) wipes it.

A fresh DISCHARGED is required if any bound file changes after this re-read, including a sunset-only change (condition 6). This entry does not authorize a run
by itself: the trigger script also needs the matching `home-census C8 DISCHARGED` comment from the pinned author, a served build whose bound paths equal this commit,
a mature container and the claim cap.

DISCHARGED sha=8c77db1af6b83270129e132cfafe20774c1cfcfd

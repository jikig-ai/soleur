---
title: The explained pin was columns, not members — and the credential path the probe depends on had not been exercised in 79 days
date: 2026-09-19
category: logic-errors
tags: [followthrough, inngest, exactly-once, mutation-testing, bash-subshell, doppler, review]
issue: 6178
pr: 8346
module: scripts/followthroughs
severity: P1
---

# Learning: pin an explained anomaly by its member identities, not by the columns that summarise it

## Problem

The #6178 soak probe had to report "SOAK CLEAN outside the explained bucket". The first cut pinned
the two explained groups as `(functionID, bucket, count)` — the columns the `op=verify` arm prints.
Ten-seat review found the two strongest findings had ONE structural cause: a column pin is satisfied
by ANY four runs of that function in that 20-minute bucket, so a genuine double-fire landing in the
catch-up bucket, or a replay with the same count, reads as explained. The attribution (`26e6836b` =
cron-ghcr-token-minter, `2e625d3c` = cron-anthropic-credit-probe) was inferred from counts matching
missed ticks, not proven.

Second, independent P1 (architecture seat): the plan enrolled the tracker with `earliest=SOAK_END`, so
the sweeper's repo-secret copies of `WEBHOOK_DEPLOY_SECRET` / `CF_ACCESS_CLIENT_*` — last exercised
when #5875 closed on 2026-07-02 — would first be tried on the day the verdict is due.

## Solution

- Pin the explained groups as exact run-id SETS (six production ULIDs, joined to
  `routine_runs.run_id` on #6178 comment 5738682595). `explained` now requires functionID AND bucket
  AND count AND `(.ids|sort) == $g.ids`; any other membership is UNEXPLAINED. C5d pins the bucket
  conjunct, C5f pins the member set, and mutation rows 4a/4b (`count ==` → `<=`/`>=`) became
  EQUIVALENT because the set conjunct subsumes the count — the labelling records why they survive.
- Enrol with `earliest=` at the enrollment instant (DC1 flipped). The ship-time `dry_run=true`
  sweeper dispatch then EXECUTES the probe under the real runner env and must print `exit=2`; a
  `credentials_unprovisioned` there is found 3 days early instead of on verdict day.
- Registry growth reports `unmeasured_fns=N` and QUALIFIES the verdict rather than refusing; only a
  vanished pinned id refuses (`registry_drift`).

Live QA reading after the pass: rc=2, `runs=850 explained=2 UNEXPLAINED=0 unmeasured_fns=0`, the two
groups are exactly the pinned sets.

## Key Insight

An "explained anomaly" allowlist keyed on the SUMMARY of the anomaly (its columns) is a hole the
exact shape of the defect it exists to distinguish. Key it on the IDENTITIES of the members, and
prove the attribution by a join, not by counts that happen to match. Corollary for follow-throughs:
a probe that depends on a credential path exercised by nothing else must be dispatched once at
enrollment, not first on the day its verdict is due.

## Session Errors

1. **Stale brief premises** (PR #8321 read as open, "archived" plan path absent) — Recovery: merged
   `origin/main`, corrected the path. **Prevention:** re-verify every brief premise with one
   command (`gh pr view --json state`, `ls`) before the plan restates it.
2. **First draft called the 09-15 verify fsm-anchored** (it was `floor(override)` QUALIFIED) —
   Recovery: deepen attribution pass. **Prevention:** quote the run's own `anchor_source=` line,
   never a paraphrase.
3. **`gh issue create` denied twice by guardrails** (heredoc-in-call; missing `meta/machinery`
   label) — Recovery: third attempt filed #8349. **Prevention:** already hook-enforced; write the
   body to a file first and add the machinery label in the same call.
4. **`'"'"'` inside a double-quoted string broke bash parse** — Recovery: plain `'`.
   **Prevention:** the probe now runs `bash -n "$BASH_SOURCE"` before `set -uo` (a parse error is
   rc 2 = NOT YET with no trap, silently).
5. **`CURL_RC` assigned inside `$(hook_get …)` was lost** — Recovery: globals, called directly.
   **Prevention:** a helper that sets a status variable is never called in command substitution.
6. **`cannot_establish` inside `$(run_jq …)` exited only the subshell**, so a jq failure fell
   through to NOT YET (C23), and jq's stderr republished a host value + the runner tmp path on the
   public issue — Recovery: `jqv` with `printf -v`, stderr captured to a file, exit from the parent.
   **Prevention:** any function that may `exit` is called in the parent shell; `lint-shell-capture-exit.py`
   was green because the pattern was a call inside `$(…)`, not a pipe — cover it with a harness case
   that forces the failure (C23), not with the lint alone.
7. **`${x%%.*}Z` produced `…ZZ`** on whole-second timestamps — Recovery: strip the trailing `Z`
   first. **Prevention:** fixture mixed fractional precision (3, 6 digits, none) in one slice (C5g).
8. **`local k="$1" f="$WORK/slice-$k.json"` expanded `$k` before it was bound** — Recovery: two
   `local` lines. **Prevention:** one `local` per variable when a later one references an earlier.
9. **First mutation battery landed zero mutants** (three-layer quoting made every anchor miss) —
   Recovery: file-based mutator with an md5 landing check. **Prevention:** every battery row asserts
   the mutant's md5 differs from pristine before running the suite; a control row runs first and last.
10. **Backtick in a double-quoted assertion label was command-substituted away** — Recovery: removed.
    **Prevention:** single-quote labels; backticks are not literal in double quotes.
11. **P1b ratchet flagged `rm -rf "$WORK"` because `WORK` was assigned twice** — Recovery: single
    `mktemp` assignment before the trap. **Prevention:** the ratchet is the prevention.
12. **Battery row 2 survived** (`exit 3` → `exit 1` was remapped to 3 by the EXIT trap, so the suite
    stayed green) — Recovery: C6 `expect_absent "unmapped_exit"`. **Prevention:** when an EXIT trap
    normalises codes, assert the ABSENCE of its remap marker on every path that must exit correctly.
13. **shellcheck SC2154 on `printf -v` targets, SC2046 on unquoted `$(…)`** — Recovery: file-wide
    SC2154 disable with the reason, `mapfile`. **Prevention:** noted in the probe header.
14. **`Write` refused twice with "modified since read"** — Recovery: re-Read then Write.
    **Prevention:** one-off tooling; re-read before a full-file rewrite after any Bash edit.
15. **Fixture ids collided** (`T1`+pad == `T10`+pad) so `unique_by(.id)` silently dropped 52 runs and
    the suite reported `population_thin` — Recovery: zero-padded indices. **Prevention:** synthesised
    ids are generated by a single function with fixed-width fields; C1 pins `runs=833` exactly.
16. **Fixture appended `$OTHER` runs to slice 2 by literal**, tripping the new `foreign_function_id`
    guard — Recovery: `append_runs "$(slice_of $OTHER)"`. **Prevention:** fixtures compute the dealt
    slice from the same rule the probe uses.
17. **P-D scratch mutant resolved the population from its own directory** — Recovery: pass
    `POPFILE`. **Prevention:** scratch copies get every input path explicitly.
18. **Stop hook fired on forward-looking closing text while agents ran** — Recovery: applied the
    pending edit, used `<stop>BLOCKED: …</stop>`. **Prevention:** already hook-enforced.
19. **Monitor expired twice (30-min cap) on the shard gate** — Recovery: re-armed; scripts shard
    passed 435/439 after the advisory lock. **Prevention:** arm a Monitor per 30-min window on
    long gates; the expiry is not a verdict.
20. **QA live run under `doppler run -c prd` returned `credentials_unprovisioned`**, then a
    names-scan using a non-existent `doppler secrets names` subcommand grepped table output and
    reported "0 of 3" in EVERY config — a false negative that nearly recorded the three credentials
    as absent from Doppler — Recovery: `doppler secrets --only-names` is a table; the runbook
    `inngest-server.md` §deploy-status already names `prd_terraform`. **Prevention:** the qa skill
    now says which config holds the deploy-webhook triple; treat a zero count from an unfamiliar
    CLI subcommand as "the command failed" until its output shape is inspected.

## Addendum — 2026-09-19 (ship phase of PR #8346, post-merge)

Five more session errors from the ship phase, recorded after the merge (the branch was already
squashed, so they travel in a docs PR):

21. **`guard-vacuity-floor` (a repo-global ratchet) scored the new harness floor "mutant not
    constructible"** — first seen in the ship battery, invisible to every file-selected suite —
    Recovery: `FLOOR=117` moved to the line IMMEDIATELY above `if [[ "$passes" -lt "$FLOOR" ]]`
    (24d8d7ff1). **Prevention:** the ratchet slices the floor block backward over CONTIGUOUS simple
    assignments only, so any non-assignment line (`[[ "$fails" -eq 0 ]] || exit 1`) between the
    threshold binding and the `if` leaves the mutant unbound. Bind the threshold adjacent to its
    floor, and run `scripts/guard-vacuity-floor.test.sh` whenever a suite gains a floor.
22. **My own mid-run fix commit tripped the battery's repo-write boundary FATAL** (`HEAD before
    089e129ae / after 24d8d7ff1`, counted as the run's second "failed") — Recovery: read the FATAL's
    before/after SHAs and matched them to my commit; the final tree was attested by CI
    (`battery-owed.sh` rc 42). **Prevention:** a commit during a running `test-all.sh` is a write the
    runner cannot distinguish from a suite's; batch fixes before launch, or accept that the run's
    verdict becomes "record only" and re-attest the final SHA.
23. **The sweeper dry-run job concluded `failure` while #6178's row was perfect** — the sweeper
    fails any run in which ANY tracker carries a fenced directive, and #8210 does — Recovery: read the
    per-issue lines, not the job conclusion. **Prevention:** a green/red job is not a per-tracker
    verdict; grep the tracker's own `directive found → exit= → would comment` lines. #8210's fence is
    the sweeper's to report (it did) and its owner's to unfence.
24. **`gh issue create --body-file <scratchpad path>` was refused twice by the guardrails hook**
    ("this gate cannot read") and a third time for naming no user-visible consequence —
    Recovery: write the body under `/var/tmp` with the Write tool, add `meta/machinery`.
    **Prevention:** the hook reads the body file itself; keep issue bodies outside the session
    scratchpad, and a decision-challenge record is a machinery filing.
25. **Two auto-close traps in PR prose** (`close #6178 LAST` in the verb list; a literal
    `Closes|Fixes|Resolves #6178` in the gate record) — Recovery: reworded before `gh pr edit`;
    `closingIssuesReferences` asserted `[]` after every body edit. **Prevention:** run
    `auto-close-scan.sh` on the body FILE before editing the PR, and assert the FIELD, not the scan.

## Related

- `knowledge-base/project/learnings/2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md`
- `knowledge-base/project/learnings/2026-09-17-evidence-verdicts-need-verbatim-provenance-not-summarized-attribution.md`
- `knowledge-base/project/learnings/2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md`
- ADR-100 addendum 2026-09-19 (#6178); `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`

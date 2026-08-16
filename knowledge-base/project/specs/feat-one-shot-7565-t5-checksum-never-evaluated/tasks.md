---
title: "Tasks — T5 must prove the CHECKSUM aborted the chain"
branch: feat-one-shot-7565-t5-checksum-never-evaluated
issue: 7565
plan: knowledge-base/project/plans/2026-08-16-fix-t5-checksum-never-evaluated-plan.md
lane: cross-domain
---

# Tasks

Plan: [`2026-08-16-fix-t5-checksum-never-evaluated-plan.md`](../../plans/2026-08-16-fix-t5-checksum-never-evaluated-plan.md)

The only code file is `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`. Line numbers are
against `origin/main` and will drift as edits land — re-locate by content anchor, not by number
(`cq-cite-content-anchor-not-line-number`).

## Phase 1 — Setup and baseline (no edits)

- [x] 1.1 Confirm branch `feat-one-shot-7565-t5-checksum-never-evaluated`, rebased on a freshly
      fetched `origin/main`.
- [x] 1.2 Run the suite unmodified and record the terminal line
      `git-data-runcmd-rehearsal: N passed, M failed (T assertions)`. This is the baseline the new
      floor is derived from.
- [x] 1.3 Confirm `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      exits 0 **before** any edit. Use `--baseline`; a bare invocation exits 1 by design.
- [x] 1.4 Re-read the plan's `## Cut List`. Nine mechanisms were considered and cut on measurement;
      do not re-introduce any of them.

## Phase 2 — Core implementation

### 2.1 Condition the `CHMOD_RAN` marker (plan Phase 1)

- [x] 2.1.1 In the python transform (anchor: `open(p, "w").write(s.replace(old, old + "; echo CHMOD_RAN"))`),
      change `"; echo CHMOD_RAN"` to `" && echo CHMOD_RAN"`. Leave the `s.count(old) != 1`
      cardinality assert untouched.
- [x] 2.1.2 Replace the post-transform check (anchor: `grep -q 'echo CHMOD_RAN' "$TMP/doppler-dl.sh"`)
      with a line-anchored check over the whole emitted construct
      `chmod +x /usr/local/bin/doppler && echo CHMOD_RAN`.
- [x] 2.1.3 Add the same anchored check against the **mounted** artifact `$TMP/dl.case.sh`, placed in
      the mutation arm immediately after its `cp "$TMP/doppler-dl.sh" "$TMP/dl.case.sh"` + `sed -i`
      pair. **Do not** place it at the instrumentation site (the file does not exist yet) or inside
      `run_case` (T17's mounted copy is `printf 'true\n'` and carries no marker — it would hard-exit
      the suite).
- [x] 2.1.4 Name T17's exemption in the adjacent comment.

### 2.2 Assert the checksum's own verdict (plan Phase 2)

- [x] 2.2.1 Leave the `run_case "T5 wrong-checksum aborts" … 1` call and `run_case` itself
      **unmodified** (AC6).
- [x] 2.2.2 After the `"level":"fatal"` assertion and before the `CHMOD_RAN`-absent assertion, add
      one counted assertion:
      `if grep -q '/tmp/doppler\.tar\.gz: FAILED$' "$TMP/out/stdout"; then pass; else fail "T5: sha256sum never rejected the tarball — the abort was not the checksum" "$(tail -3 "$TMP/out/stdout")"; fi`
- [x] 2.2.3 Verify the `$` anchor and the escaped `.` are both present. Without the anchor,
      `FAILED open or read` satisfies the assertion and the bug returns in a new disguise.
- [x] 2.2.4 Use `if grep -q … ; then` form only. No `var=$(grep -c …)` capture — it would add a
      finding to `lint-shell-capture-exit.py`'s baseline.

### 2.3 Floor, comments, tracking issue (plan Phase 3)

- [x] 2.3.1 Raise the floor from 46 to the measured total (predicted 47) and itemise the raise in the
      existing in-file style, naming the new assertion.
- [x] 2.3.2 Correct the stale "four plain `docker run --rm`" comment to the measured count in the
      same edit.
- [x] 2.3.3 Update the instrumentation comment block to record why the marker is `&&`-chained and
      that bash does not fire errexit on a failing **non-final** member of an AND-OR list — so the
      next reader does not reach for a heavier `|| { rc=$?; …; ( exit $rc ); }` tail.
- [x] 2.3.4 Update the T5 primary comment: "the checksum is the ONLY thing that can stop the chain"
      holds only when the environment is healthy, and the new assertion is what makes the arm say so.
- [x] 2.3.5 File a tracking issue for the pre-existing `set -u` / unset-`CAPTURE` hazard (anchor:
      D1's `[ -s "$CAPTURE" ]`, which runs before any `run_case` call has defined `CAPTURE`).
      Reference the issue number in a code comment at that site. **Do not fix it here.**

## Phase 3 — Testing and verification

- [x] 3.1 Full healthy run: the suite prints `… 0 failed …` and exits 0.
- [x] 3.2 Set the floor to the measured `total` from 3.1 and re-run to confirm.
- [x] 3.3 Execute Guard 1 mutation rows 1-5 against a scratch copy; record edit, terminal line and
      exit status for each.
- [x] 3.4 Execute Guard 2 mutation rows 1-5 the same way. Row 1's detector is the anchored
      post-transform check, **not** the arm's verdict — behaviourally `;` and `&&` are
      indistinguishable when the CDN is reachable.
- [x] 3.5 Execute harness rows H1-H4. H2 is expected GREEN and that is the finding; H3 and H4 are
      must-PASS rows.
- [x] 3.6 Confirm no mutation row is left applied to the committed file.
- [x] 3.7 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      exits 0, and `git diff --stat origin/main -- scripts/lint-shell-capture-exit.baseline.txt` is
      empty.
- [x] 3.8 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-08-16-fix-t5-checksum-never-evaluated-plan.md`
      exits 0. Pin the path — a bare invocation sweeps every non-archived plan.
- [x] 3.9 `bash .github/scripts/test/test-infra-suite-registration.sh` exits 0.
- [x] 3.10 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [x] 3.11 Guard-rail greps: `grep -Fc -- '"; echo CHMOD_RAN"'` returns 0;
      `grep -Fc -- '" && echo CHMOD_RAN"'` returns 1;
      `grep -Ec 'arm_skip|SKIPPED_ASSERTIONS|_SKIP_CEILING'` returns 0.
- [x] 3.12 `git diff origin/main -- apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` shows
      no change inside `run_case`.
- [ ] 3.13 Run `bash scripts/test-all.sh` for information; disposition any pre-existing unrelated
      failure per `wg-when-tests-fail-and-are-confirmed-pre`.

## Phase 4 — Ship

- [ ] 4.1 PR body carries `Closes #7565` and **not** `Closes #7291`.
- [ ] 4.2 PR body carries the row-by-row mutation transcript from 3.3-3.5.
- [ ] 4.3 PR body records probes (e)/(f)/(g) as evidence contributed to #7291.
- [ ] 4.4 Post-merge: confirm the first `deploy-script-tests` run on `main` is green with the printed
      total at or above the floor.
- [ ] 4.5 Post-merge: comment on #7291 with probes (e)/(f)/(g), the note that `&&`-conditioned
      `CHMOD_RAN` makes a CDN-blocked run reach PR 7510's `else` branch, and the caveat that curl
      rc 22 (asset deleted or retagged) must never be routed to a decline.

---
title: "feat: git-data-cutover mode=refs_assert so REFS-CONFIRMED can be attained"
type: feat
date: 2026-10-29
slug: git-data-cutover-refs-assert
branch: feat-one-shot-11431-refs-assert
issue: 11431
closes: 11431
lane: cross-domain
requires_cpo_signoff: true
---

# feat: git-data-cutover mode=refs_assert so REFS-CONFIRMED can be attained

Ref #8211 (epic). Draft PR #11567. The PR body may say `Closes #11431` because this plan builds the mode whole
(workflow, host verb, tests, runbook); commits and the PR title say `Ref #8211`. The PR body's FIRST line states:
"Merge fires apply-web-platform-infra.yml (path filter apps/web-platform/infra/**); no .tf and no file()-bound
payload changes, so its plan is a no-op - verify by reading the run's plan, never dispatch it from here."

## Enhancement Summary

**Deepened on:** 2026-10-29. **Gates run:** 4.6 user-brand, 4.7 observability, 4.8 PAT sweep, 4.11 guard contract (lint green), 4.12 scope check; 4.9, 4.10, 4.13 not triggered (no UI surface, no `.tf` or store, no new workflow file). **Agents used:** plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex), CPO sign-off, sharp-edges verification, and deepen passes by security-sentinel, observability-coverage-reviewer, user-impact-reviewer and test-design-reviewer; technical forks ruled by `soleur:engineering:cto` (rows F1-F22 of `decision-challenges.md`).

### Key improvements
1. Host script hardened: broken refs that git skips silently are caught through the non-empty-stderr rule, fds 3/4 closed for the git child, hardened `env -i` and `-c` flags, one NUL-delimited enumeration for count and name, `RA_MOUNT` identity and TOCTOU checks, `shallow` refusal, fail-closed field self-check.
2. Answer line shrunk to counts plus at most two numerically smallest branch-tip shas (less fingerprint surface); verdicts carry a FAILED / INCONCLUSIVE class printed in the annotation and driving two notify words.
3. Cross-consumer ripples closed: run-title classifier, vacuity ledger and shard map, the AC9 flag-precheck pin, the C4 edge sentence and its generated JSON, the apply-workflow path filter.
4. Test strategy made buildable: fixtures git can actually hold, shims that match the absolute/bare command shapes, ordering and boundary rows, named print-scan helper.

### New considerations

- A merge fires `apply-web-platform-infra.yml` (no-op plan expected); the PR body says so first.
- The provenance residual (one repository, not proven to be the synthetic account's) is stated in the runbook with its three-part argument and detector; the dead end after a FAILED stop is parked on #8211 (F17).

## Overview

The rehearsal runbook (`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, rows R3 and
R6) defines REFS-CONFIRMED as a ref name under `refs/soleur/worktrees/<worktreeId>/` of the synthetic account's
`<id>.git` plus its 40-hex sha, read by a `refs_assert` mode it calls "a #8211 follow-up, not yet built". Without
it the owner has no route to the refs that is not SSH, an owner-typed listing is never evidence, and R6, the account
deletion and any real flip cannot proceed.

This plan adds `mode=refs_assert` to `.github/workflows/git-data-cutover.yml` (job `cutover`) and a host verb to
`apps/web-platform/infra/git-data-cutover.sh`, delivered as a new stdin-sent host script
`apps/web-platform/infra/git-data-refs-assert.sh` (the `wipe_assert` pattern: not `file()`-bound into user_data).
It is read-only, runs with the store flag off, prints counts and up to two branch-tip commit shas on one
anchored line, has its own typed confirm token `REFS-ASSERT-GIT-DATA`, sits behind the same
`web-platform-infra-apply` reviewer environment, and needs no SSH from the operator. It also fixes one
cross-consumer ripple found in planning: the wipe's run-title classifier would read a `git-data refs_assert` run
as unparseable and refuse.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality (grepped) | Plan response |
|---|---|---|
| "follow the existing hashed-name convention in git-data-cutover.sh" | `git-data-cutover.sh` hashes no name. The in-family convention is the opposite: `git-data-wipe-assert.sh` header "NO NAME LEAVES THE HOST ... no per-name hash ... no listed name is printed, hashed or stored". The keyed `hashUserId` (HMAC-SHA256 with `SENTRY_USERID_PEPPER`, Doppler `prd`) lives in the app (`git-data-replication.ts`) and the script reads no secret store | Print no id in any form: counts and shas only. Ruled by CTO agent, 2026-10-29 (F3/F4) |
| Issue: "for a given synthetic id" | A dispatch input is readable by repo readers and persisted in run metadata, so a typed id breaks "never a workspace id in the clear" | Ruled by CTO agent, 2026-10-29 (F3): no `synthetic_id` input; the host enumerates repositories and requires exactly one |
| Issue and runbook: REFS-CONFIRMED names `<syntheticId>.git` | The host cannot know the id: `QUIET_WINDOW_EXEMPT_USER_ID` lives only in Doppler `prd`, is read only by the web container and must be UNSET before R4 (`apps/web-platform/server/quiet-window.ts` header; runbook quiet-window section) | Ruled by CTO agent, 2026-10-29 (F8): drop the `<syntheticId>.git` wording; the runbook states the weaker provenance. No binding added |
| "runs after R4 with the flag off" | `git-data-flag-precheck.sh` `FLAG_MODE=proof` refuses `flag_already_true` and passes on off/unset; `FLAG_MODE` is a closed set (proof, flip, rollback, unfreeze, wipe, wipe_check, wipe_reread, pin_only), so `refs_assert` as a `FLAG_MODE` is refused `flag_mode_invalid` | Workflow maps `refs_assert` to `FLAG_MODE=proof`; the precheck script is not edited (F2) |
| "the proof also checks the store" | `proof` refuses a non-empty store (`store_not_empty`), and the synthetic repository IS on the store after R5 | `refs_assert` reuses only the `verified-only` store probes (mounted, on the mapper, marker bound, not frozen), as `mode_probe` does. `verified-only` skips the repositories-directory checks, so the host script repeats them |
| Prior ruling (2026-10-27): "unverified assumption: rollback leaves the refs intact" | The rollback's erasure probe removes only `cutover-probe-<lineage>.git` (`mode_probe`) | Stated as a premise in the runbook; `refs_none` after R4 means the rollback destroyed the evidence or replication never landed |
| "same environment gate" | Job `cutover` already declares `environment: web-platform-infra-apply` and `concurrency: web-1-swap` | Reused unchanged; no new job, bridge `uses:` or credential binding |
| "P3 definer population lives in git-data-wipe-assert.test.sh" (first draft) | P3 is `case_parity` in `git-data-cutover-access.test.sh`; the wipe-assert suite's P3 is its own verdict-word header check | The new script must not assign `STORE_DEVICE`, `STORE_VERIFIED`, `cutover_freeze`, `MOUNT_ROOT`, `GIT_DATA_ROOT` or `REPO_ROOT` (`REFS_REPOS` is fine) |

## Research Insights

**Premise Validation (Phase 0.6).** #11431 is OPEN (type/feature, p2, domain/engineering, meta/machinery); the only
open PR naming it is our own draft #11567 (collision pre-check also listed foreign `test-all.sh` processes in other
worktrees, none touching these files). ADR corpus grep on the mechanism nouns (`knowledge-base/engineering/architecture/decisions/`):
`refs_assert`, `REFS-CONFIRMED`, `FLAG_MODE=proof` appear in no ADR; `wipe_assert` and `store_not_empty` appear in
ADR-239/237/220 as the accepted design this plan extends, with no rejected-alternatives entry for a refs read. Verified-at
2026-10-29: all 20 paths in Files to Edit/Create that exist are tracked (`git ls-files`); the roster derivation matches 16
`file()` bindings.

**Property List (Phase 0.6b).**

1. A dispatch proves a replicated commit ref exists on the store (a branch tip under a worktree namespace) without the operator holding any route to the host.
2. The mode can never change a host, the store, the flag or any credential.
3. No workspace id, repo name or worktree id (in the clear or hashed) reaches any log, summary, output, run title or notification.
4. A false pass is harder than a false refusal: a malformed ref, an unreadable or wrong-type object, a tags-only namespace, two repositories, a foreign-owned repository or a held freeze all refuse.
5. The rung-2 boot evidence hash stays valid (no hash-bound file changes).
6. Every consumer that enumerates the workflow's modes (run-title classifier, census suites, runbook, C4 edge text) still tells the truth.

**Cut List (Phase 0.6b).**

- New `synthetic_id` input -> property 3 -> cut by CTO F3.
- Edit to `git-data-flag-precheck.sh` -> properties 2/4 -> covered by `FLAG_MODE=proof`.
- New job / bridge / credential binding -> properties 1,2 -> covered by the `cutover` job chain.
- Hashing worktree ids -> property 3 -> cut (brute-forceable; breaks the in-family convention).
- A new ADR -> no architectural decision is made; the record is `decision-challenges.md`.
- `commit_refs` and `tags` answer fields, a `$GITHUB_OUTPUT` write, an extra `::notice`, a permanent hash-roster guard matrix, a verdict-word generator -> no property they alone buy -> cut at plan review (F12, F13, F14, F15).

**Institutional learnings applied** (knowledge-base/project/learnings/): census-that-stubs-the-host-verb (2026-10-15:
run the step's real env allow-list; capture to a file and match the emitter line anchored at line start);
counter-field (2026-10-18: fixtures where counts differ from flag form, a zero beside a non-zero neighbour, WHOLE-line
assertions); redact-then-cap and `::stop-commands::` (2026-09-14, 2026-07-11: relayed host stderr goes through
`_access_stderr`); "an ssh stub that never reads stdin hides the script-delivery path" (2026-10-05);
`set -euo pipefail` capture pitfalls; mutation-harness learnings (every row proves its edit landed; every guard needs
a must-PASS non-canonical fixture); 2026-10-27 technical-fork-as-operator-item (all forks went to the CTO).

## Hash-bound paths (DO NOT TOUCH)

The rung-2 evidence (`apps/web-platform/infra/git-data-rung2-boot-evidence.env`, `RUNG2_TEMPLATE_SHA256`) binds the
cloud-init template plus every `file()`-bound payload in `modules/git-data-userdata/main.tf`. Derived from the
bindings (16 payloads + the template), all under `apps/web-platform/infra/`:

`cloud-init-git-data.yml`; `git-data-bootstrap.sh`; `git-data-pre-receive.sh`; `git-data-provision.sh`;
`git-data-transport-wrapper.sh`; `git-data-remove.sh`; `git-data-gc.sh`; `git-data-gc.service`;
`git-data-gc-failure.service`; `git-data-gc.timer`; `git-data-luks-reopen.sh`; `git-data-luks-reopen.service`;
`git-data-luks-reopen-failure.service`; `git-data-luks-reopen.timer`; `git-data-liveness.sh`;
`git-data-liveness.service`; `git-data-liveness.timer`. Also frozen by owner rule: `modules/git-data-userdata/**` and
`git-data-rung2-boot-evidence.env`.

None of the planned files is in that set: the new host script is delivered on stdin to `bash -s` and is never named by
a `file()` binding. AC1 proves both facts mechanically (one-shot command, count asserted as a number).

## Proposed Solution

### Design (the CTO rulings as the build spec)

**Dispatch.** `gh workflow run git-data-cutover.yml --ref main -f mode=refs_assert -f confirm=REFS-ASSERT-GIT-DATA`,
dispatched from the runbook's step, never by this session. Run title `git-data refs_assert` (no id).

**Runner side (`git-data-cutover.sh`, new verb `mode_refs_assert`, copied from the shape of `mode_wipe_assert`).**
Order: `refuse_if_config_unsafe` -> `access_gate` -> `refuse_if_unmounted` -> `refuse_if_not_on_mapper` ->
`refuse_if_store_unverified_or_not_empty verified-only` (a held freeze refuses `cutover_frozen`, no bypass; the
step sets no `CUTOVER_LINEAGE`, so a sentinel is never tolerated as arm-A resume) -> ONE `gd_capture` that sends
`git-data-refs-assert.sh` on stdin to `bash -s` with `REFS_REPOS=<%q-quoted $OLD_REPOS>` in front, bound 60 s,
answer matched in full by:

```text
^refs_assert ok repos=1 namespaces=[1-9][0-9]* refs=[1-9][0-9]* heads=[1-9][0-9]* shas=[0-9a-f]{40}(,[0-9a-f]{40}){0,1}$
```

Emitters `_refs_emit` / `_refs_refuse` wrap `_store_emit` / `_store_refuse` with probe `refs-assert` (as
`_wipe_emit` / `_wipe_refuse` do). Success prints `STORE probe=refs-assert verdict=ok` (which already emits the
`::notice`), `REFS-CONFIRMED` and `REFS_ASSERT <line>` to the log and `$GITHUB_STEP_SUMMARY`. Every refusal prints
`::error title=git-data-cutover refs::verdict=<word> class=<FAILED|INCONCLUSIVE>` (plus the fixed-digit
`rc=27|96` suffix for `refs_shape_failed`) and the same to the step summary; the class is looked up from the
script's exit-code table. The only `$GITHUB_OUTPUT` write is on the refusal path: `_refs_refuse` appends `refs_class=<FAILED|INCONCLUSIVE>` for step id `refs`, and the `cutover` job's `outputs:` gains `refs_class: ${{ steps.refs.outputs.refs_class }}` for notify-failure; there is none on success.

**Host side (`git-data-refs-assert.sh`, root, one session, read-only).** Shape copied from
`git-data-wipe-assert.sh`: the whole body inside one function (`ra_main`) invoked as `ra_main; exit $?`, then
`exec 3>&2 4>&1 1>/dev/null 2>/dev/null </dev/null` so no child can read the rest of the script from stdin (fd 3 carries
the one reason word/digits, fd 4 the one answer line), and an xtrace refusal at the top (rc 16). Steps, with the
session's rc being the verdict (the header `# EXIT CODES` table is the only authored list, sorted by rc, with a class column):

| rc | runner word | class | meaning |
|---|---|---|---|
| 0 | `refs_confirmed` | REFS-CONFIRMED | the one answer line printed |
| 16 | `probe_failed` | INCONCLUSIVE (retryable) | an input, an instrument or a read failed, or xtrace is on (never a host verdict) |
| 20 | `refs_repo_absent` | FAILED | zero `*.git` entries (repos=0) |
| 21 | `refs_repo_not_single` | INCONCLUSIVE (not retryable) | repos>1, or an entry that is not a real `*.git` directory (symlink, file, non-empty `lost+found`), or the repositories directory is a symlink / not on the store mount; stderr carries digits `repos=<n>` only |
| 23 | `refs_none` | FAILED | the repository exists and holds no ref under `refs/soleur/worktrees/` ("provisioned, not replicated"; an unborn HEAD or a ref outside the namespace does not count) |
| 24 | `refs_no_branch_tip` | FAILED | refs exist but none under `heads/` (tags-only never passes: the 2026-10-27 failure was a rejected push to `heads/main`) |
| 26 | `refs_unreadable` | INCONCLUSIVE (retryable) | `git for-each-ref` failed (a missing object, a foreign-owned repository, dubious ownership) or returned a 201st line (the bound) |
| 27 | `refs_shape_failed` | INCONCLUSIVE (not retryable) | a ref under the namespace whose name is not `refs/soleur/worktrees/<id>/(heads\|tags)/<name>` (id `^[A-Za-z0-9._-]+$`, not `.`/`..`; name `[A-Za-z0-9._/-]+`, no `..`, no trailing `/` or `.lock`) |
| 28 | `refs_bad_sha` | FAILED | a ref whose value is not 40-hex, whose `heads/` object is not a commit, or whose `tags/` object does not peel to a commit |
| (96) | `refs_shape_failed` | INCONCLUSIVE | gd_capture got an answer that is not the one anchored line (runner-side; shares the word with rc 27, suffix `rc=96`) |

Every runner-side refusal (the access-gate words, `old_store_unmounted`, `store_not_on_mapper`, `store_unverified`,
`cutover_frozen`, `flag_already_true`, `probe_failed rc=124/255/other`) is INCONCLUSIVE: no verdict on the refs.
`cutover_frozen` after R4 means the unfreeze did not land and takes the existing `FREEZE_HELD` Abort path; it is not
re-dispatched. Retry rule: only `probe_failed` and `refs_unreadable` may be re-dispatched, at most twice; after that
ONE `action-required` issue naming the ACTION is filed (CTO F11). FAILED is not retried until a new rehearsal.

Host logic (security pass applied):

1. Validate `REFS_REPOS` and refuse xtrace; a hardcoded constant `RA_MOUNT=/mnt/git-data` is the store root, `readlink -f "$REFS_REPOS"` must equal `$RA_MOUNT/repositories` and `stat -c %m` of it must equal `$RA_MOUNT` (the argument supplies no root of its own; `..` is not admitted).
2. Repeat the repositories-directory checks the runner's `verified-only` skips (not a symlink, a directory, on the store mount). Record `stat -c %d:%i:%F` of the repositories directory and of the repository now and again after the read; any difference is rc 16 (bounded TOCTOU).
3. ONE NUL-delimited enumeration, `find -H "$REFS_REPOS" -mindepth 1 -maxdepth 1 ! \( -type f \( -name '.*.init.lock' -o -name '.init.lock' \) \) ! \( -type d -name lost+found -empty \) -printf '%y\t%f\0'` (the typed predicate of `git-data-wipe-assert.sh`), read into shell variables only and refusing any control character; the same enumeration yields both the count and the single name (no second `find`, no glob). 0 entries -> rc 20; more than one, or any entry that is not a `d` named `*.git` -> rc 21 - all BEFORE any ref or sha is read. The repository is passed as ONE argv element `--git-dir="$REFS_REPOS/$name"`.
4. Read refs as the `git` user: `cd / && runuser -u git -- /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat /usr/bin/git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat --git-dir=<repo> for-each-ref --count=201 --format='%(refname)%09%(objectname)%09%(objecttype)%09%(*objecttype)' refs/soleur/worktrees/ 3>&- 4>&-`. `runuser` is called bare (resolved by root's PATH, as the push line in `mode_probe` is) so a PATH shim reaches it; the suite's `runuser` shim rewrites the inner command to the shim directory, accepts exactly the modeled argv and exits 64 with a logged refusal on any other (no test seam in the script, ADR-214). `3>&- 4>&-` keeps the answer fds out of the git child. git's stderr goes to a root-owned `mktemp -d` file under `/dev/shm`, is never printed, and ANY non-empty stderr - even with rc 0 - is rc 27 `refs_shape_failed`, because git silently skips a broken ref (`heads/a..b`, a garbage loose file) with only a `warning: ignoring ...` on stderr. There is no `-c safe.directory`: `GIT_CONFIG_NOSYSTEM=1` means the bootstrap's system `safe.directory` is never read, a repository owned by uid `git` passes, and a foreign-owned one fails as rc 26. Capture as `out="$(...)" || rc=$?` on its own statement; parse with a here-string loop (no subshell pipe), counters in the current shell. If `<repo>/shallow` exists the result is rc 26 (`test -e`, no extra git verb).
5. Classify each line (name regex above under `LC_ALL=C`; 40-hex sha; `heads/` object `commit`; `tags/` peeled type `commit`); name variables appear only as the quoted left side of `[[ =~ ]]`, never in `eval`, an unquoted expansion, a printf format or as a leading-`-` argv; count distinct worktree ids with a pipe that never prints; take the two numerically smallest distinct `heads/` shas, sorted by sha value (never by ref name), by array slice (no `head` under pipefail) - the cap is 2 (CTO F22); before printing, a fail-closed self-check (rc 26 `refs_unreadable`) asserts shas count == min(distinct heads shas, 2), namespaces <= refs and heads <= refs (CTO F21).
6. Refuse in order rc 23, 27, 28, 24 and print the line. stderr of every command is discarded except the file above; the only stderr the script writes is a fixed reason word and digits. Only `for-each-ref` is run against the repository (the `%(*objecttype)` peel replaces any per-ref `rev-parse`).

Runner side: `_refs_refuse` derives the word and class from the exit-code table by rc, never from host text; the relayed `repos=<n>` must match `^repos=[0-9]{1,6}$`; relayed stderr passes `_access_stderr` unchanged.

**Workflow (`git-data-cutover.yml`, job `cutover`).** (a) `mode` options + description gain `refs_assert`; (b) the
confirm `case` gains `refs_assert) want="REFS-ASSERT-GIT-DATA"` (`lineage`/`volume_id`/`origin_run` stay refused for it);
(c) `Flag precheck` env becomes `FLAG_MODE: ${{ steps.confirm.outputs.mode == 'refs_assert' && 'proof' || steps.confirm.outputs.mode }}`
(the `flag_write` step is unchanged: its `if` never matches `refs_assert`); (d) new step `Host-side refs assertion` after
`Host-side proof`, `if: steps.confirm.outputs.mode == 'refs_assert' && steps.flag_precheck.outputs.nothing_to_rollback != '1'`,
env `WEB_HOSTS`, `GIT_DATA_SSH`, `MODE: refs_assert`, run `bash apps/web-platform/infra/git-data-cutover.sh`, id `refs`;
(e) job output `refs_class` set from that step only on the refusal path; notify-failure: `refs_assert` joins the `case "$MODE"`
list and gets `REFS_ASSERT_FAILED` / `REFS_ASSERT_INCONCLUSIVE` words ("read-only: nothing on any host changed"; verdict word
and class only, never a sha), each word appearing once in `words=` and once in `swords=` and in no comment; (f) `Run summary`
prints "Nothing on any host was changed." for `refs_assert`; (g) header comment counts six cutover-job modes. The job `if:`
(wipe-family exclusion), `run-name`, inputs and credential bindings are unchanged.

**Run-title classifier.** `scripts/lib/git-data-wipe-runs.sh`: the `other` family regex becomes
`^git-data (proof|flip|rollback|unfreeze|redeploy|refs_assert)\z`, and both stale "five non-wipe modes" comment lines
(header lines 8 and 17) are reworded; `git-data-wipe-runs.test.sh` gains `tc 'git-data refs_assert' other`, an
after-the-stamp row, and a `git-data refs_assertX` -> `unparseable` row that pins the `\z` anchor.

## Files to Create

- `apps/web-platform/infra/git-data-refs-assert.sh` - host-side body, stdin-delivered. Not hash-bound.
- `apps/web-platform/infra/git-data-refs-assert.test.sh` - verb suite (registered by presence): real `git` bare-repo fixtures, PATH shims for `ssh`/`timeout`/`runuser`, parity, print scan, read-only shim, stdin-delivery, mutation rows.

## Files to Edit

- `.github/workflows/git-data-cutover.yml` - mode option, confirm token, FLAG_MODE mapping, new step, job output, notify words, run summary, header.
- `apps/web-platform/infra/git-data-cutover.sh` - `MODE` validation list, `refuse_legacy_modes` remedy text, `mode_refs_assert`, `_refs_emit`/`_refs_refuse`, `main()`, header MODES paragraph.
- `apps/web-platform/infra/git-data-cutover-access.test.sh` - restate: mode options 9 -> 10; the AC9 flag-precheck pin (`FLAG_MODE` env now the mapped expression); `WF-cutover-if`/`WF-runname`/D-6 ordered steps/`WF-gating` for the new step; G5 census (name allow-list `mode_wipe_assert|mode_refs_assert` for the stdin/bound parameters, one more `gd_capture` site); `N-body`/`N-exprs`; a P4-style row that the new script's exclusion predicate equals `_repo_count`'s; floors (`MUTANT_FLOOR`, `FLOOR`) from printed totals.
- `apps/web-platform/infra/git-data-wipe-access.test.sh` - `MODES`, `NOTIFY_MODES`, the executed cutover confirm table (`refs_assert:REFS-ASSERT-GIT-DATA`), `WS-modes`, `G10-env-contract` if it names the host-step env.
- `scripts/lib/git-data-wipe-runs.sh`, `scripts/lib/git-data-wipe-runs.test.sh` - classifier (above).
- `scripts/guard-vacuity-floor.test.sh` - `PROMOTED_FILES` entry for the new suite and the hand-ratcheted `MIN_FIRING_SUITES` bump (+1) with its comment.
- `apps/web-platform/infra/suite-shard-legs.tsv` - a row for the new suite (`--incremental --write`).
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` - Phase 4.
- `knowledge-base/engineering/architecture/diagrams/model.c4`, regenerated `model.likec4.json` - the `github -> gitDataStore` edge text.
- `apps/web-platform/infra/run-registered-suites.sh` - only if the measured runtime exceeds the default bound.

Globs: the roster derivation matches 16 bindings; no other glob is used.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` was searched for each planned path (workflow,
cutover.sh, both access suites, wipe-runs.sh, the runbook, model.c4, wipe-assert.sh): zero hits.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Technical forks ruled by `soleur:engineering:cto` on 2026-10-29 (rows F1-F18 of
`knowledge-base/project/specs/feat-one-shot-11431-refs-assert/decision-challenges.md`). No Product/UX surface, no
legal surface (the synthetic account is the owner's own throwaway; output carries commit shas and counts only).
CPO plan-time sign-off for the `single-user incident` threshold is recorded below; the plan review panel (DHH, Kieran,
code-simplicity, architecture-strategist, spec-flow, CTO devex) ran on 2026-10-29 and its findings are applied or ruled.

## User-Brand Impact

- **If this lands broken, the user experiences:** a FALSE REFS-CONFIRMED lets the rehearsal close and the first real
  flip proceed on a store that does not replicate, so a real user's session work, held only in the container's working
  tree until session end, is discarded at the next rollback redeploy and appears as a missing workspace. A false
  refusal only delays the rehearsal.
- **If this leaks, the user's workflow is exposed via:** the Actions run log, step summary, run title and notify
  issue/email if a workspace id, repo name or worktree id were printed; the design prints none, in any form, and the
  print-scan row fails on any fixture identifier.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** single-user, not aggregate: one false pass loses one real user's unreplicated work, and the mode exists to gate exactly that; the CPO agreed at plan time (below).

## CPO Sign-off

`soleur:product:cpo`, 2026-10-29 (plan time): **YES, conditional**; threshold `single-user incident` agreed (the
2026-10-27 provision-succeeded / push-rejected failure is the precedent). `soleur:engineering:review:user-impact-reviewer`
runs at review time; a deepen-plan pass follows this plan.

| CPO condition | Landing |
|---|---|
| C1 bind the repository to the synthetic id, or drop the wording | CTO F8: dropped; runbook states the weaker provenance and the `op:exempt-pass` detector (Phase 4, AC12) |
| C2 provisioning seeds nothing; negative cases | `git-data-provision.sh` runs only `git init --bare` (the `git init --bare --quiet "$repo_path"` line); suite rows on a REAL `git init --bare` fixture (Phase 1, AC4) |
| C3 refuse on repo count != 1 before any ref/sha is read; a refusal emits only a code | host logic order (3) before (4); refusal stderr is a fixed word and digits (AC4, AC6) |
| C4 no ancestry / content comparison | out of scope; stays the parked "known latent behaviours" item |
| C5 REFS-CONFIRMED / FAILED / INCONCLUSIVE, diagnosable without SSH | exit table class column, `class=` in the annotation and summary, two notify words (AC10, AC12) |
| C6 necessary, not sufficient | runbook sentence (Phase 4, AC12) |
| C7 evidence binding | runbook (Phase 4, AC12) |
| C8 runbook edits in the same PR | Phase 4 |
| C9 the PR does not deliver REFS-CONFIRMED; track the re-run | runbook note (Phase 4); Phase 6 |

## Observability

```yaml
liveness_signal:
  what: the dispatched run's own conclusion plus the STORE probe=refs-assert line (verdict and class) in the step log and step summary (an on-demand mode, no resident process)
  cadence: per dispatch
  alert_target: the ci/git-data-cutover issue and ops email opened by the notify-failure job for a failed run (notify-failure, layer 6 workflow run log)
  configured_in: .github/workflows/git-data-cutover.yml job notify-failure (REFS_ASSERT_FAILED and REFS_ASSERT_INCONCLUSIVE words)
error_reporting:
  destination: GitHub Actions annotations (::error title=git-data-cutover refs) plus the notify-failure issue and Resend email; Sentry is not in this surface (CI-only)
  fail_loud: exit 5 with a fixed verdict word and class=FAILED|INCONCLUSIVE (refs_none, refs_no_branch_tip, refs_bad_sha, refs_repo_absent, refs_repo_not_single, refs_unreadable, refs_shape_failed, cutover_frozen, probe_failed rc=<n>)
failure_modes:
  - mode: no replication reached the store (refs_none, refs_no_branch_tip, refs_repo_absent)
    detection: the host session counts repositories, refs under refs/soleur/worktrees/ and branch tips
    alert_route: red run -> notify-failure issue "REFS_ASSERT_FAILED"; layer 6: workflow run log (step log + ::error:: annotation carrying verdict=<word> class=<FAILED|INCONCLUSIVE>)
  - mode: a malformed ref, wrong-type object or unreadable repository (refs_shape_failed, refs_bad_sha, refs_unreadable)
    detection: per-ref regex and type checks, plus the for-each-ref exit code, on the host
    alert_route: red run -> notify-failure issue (REFS_ASSERT_FAILED for refs_bad_sha, REFS_ASSERT_INCONCLUSIVE otherwise); layer 6: workflow run log (step log + ::error:: annotation carrying verdict=<word> class=<FAILED|INCONCLUSIVE>)
  - mode: more than one repository or an off-list entry (refs_repo_not_single)
    detection: typed find over the repositories directory
    alert_route: red run -> notify-failure issue "REFS_ASSERT_INCONCLUSIVE"; routes to the Store not empty section; layer 6: workflow run log (step log + ::error:: annotation carrying verdict=<word> class=<FAILED|INCONCLUSIVE>)
  - mode: the host or transport cannot be read (access_gate verdicts, probe_failed rc=124/255)
    detection: access gate and gd_capture exit codes
    alert_route: red run -> notify-failure issue "REFS_ASSERT_INCONCLUSIVE"; layer 6: workflow run log (step log + ::error:: annotation carrying verdict=<word> class=<FAILED|INCONCLUSIVE>)
logs:
  where: GitHub Actions run log and step summary of the dispatched run (counts and shas only)
  retention: GitHub Actions default log retention (90 days); the runbook evidence block pastes the anchored result line next to the run URL
discoverability_test:
  command: grep -c -e REFS_ASSERT_INCONCLUSIVE .github/workflows/git-data-cutover.yml
  expected_output: "2"
```

No resident process is added, so there is no heartbeat. The `discoverability_test` is a static wiring probe: the base
tree prints `0` and the implemented tree prints `2` (a line count: the `words=` line and the `swords=` line, the word in
no comment). It proves the notify word is wired, not that a dispatch passes; the live signal is the runbook dispatch
(`STORE probe=refs-assert`), which this session never runs. The count is re-measured after Phase 3 and restated if it
differs. The affected-surface rule (2.9.2) is met by the host session's design: on success the answer line carries
`repos`, `namespaces`, `refs`, `heads` and the shas; on refusal the discriminator is the exit-code word plus digits
(`repos=<n>` at rc 21). `refs_unreadable` may be deterministic (a foreign-owned repository, a missing object), so the
Verdict map says a second identical result stops the retries.

## Guard Contract

### Guard 1 — refs_assert pass criterion

**Property.** Exit 0 / `refs_confirmed` is printed only when the store holds exactly one real repository, every ref under `refs/soleur/worktrees/` is well formed with a 40-hex sha of the right object type (heads: commit; tags: peels to a commit), and at least one ref is a `heads/` branch tip.

**Assembly.** One chokepoint on the host: the final print, reached only after the sequence repositories-directory identity -> repo count/typed entries -> `for-each-ref` -> per-ref shape -> per-ref sha/type -> branch tip -> bound; every ref flows through the one classification loop (no second path reads refs). A second chokepoint on the runner: the anchored regex (a different line, `repos=` other than 1, or a zero count can never match). A third: `cutover_frozen` and the store probes precede the script. Members that drift: the verdict words (derived from the script's exit-code table by one parity row, not hand-listed) and the ref population (all lines of one `for-each-ref`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the `heads` requirement (accept tags-only) | RED (tags-only fixture) |
| 2 | the loop stops after the first compliant ref while a second ref is malformed (a name git accepts and the regex rejects, for example `heads/a+b`) | RED (second-member fixture) |
| 3 | the runner regex loses its `repos=1` anchor or its `[1-9]` minima; or the verb stops sending the script and a shim forges a line (`repos=2`, `heads=0`, `refs=0`) | RED (forged-line rows) |
| 4 | drop `%(objecttype)` (or `%(*objecttype)`) from the format: a ref to a missing object or a tag to a tree is skipped or typed wrongly | RED (missing-object and tag-to-tree fixtures; the format is also pinned literally) |
| 5 | raise or remove the 200-ref bound | RED (201-ref fixture) |
| 6 | precondition satisfied, property failed: exactly one repository, well-formed names, one ref's object missing | RED (`refs_unreadable`) |
| 7 | drop the repositories-directory identity check | RED (symlinked repositories directory fixture) |

**Harness rows.** (a) Break the SUITE: the fixture builder creates no refs; the happy-path row must go RED. (b) A must-PASS non-canonical input: two worktree namespaces, a `heads/feature/x.y` branch, an annotated `tags/` tip beside `heads/` tips (namespaces=2 differs from refs=3 differs from heads=2), plus lock dotfiles and an empty `lost+found`. (c) The suite's own floor: a `MIN_ASSERTIONS` count reported with printf+exit, not through `pass()`.

**Anchor.** The stored values are the exit-code table and the verdict words; they are compared across the script header table and the runbook Verdict map by one parity row, so a weakening must edit both in one reviewed diff; the runner regex is pinned by a literal row and a mutation row. A `>= N` floor is paired with set identity (the exact word set), not a count alone.

### Guard 2 — no name leaves the host, no write reaches the host

**Property.** No workspace id, repository name, worktree id or ref name (in the clear or hashed) reaches stdout, stderr, step summary, run title or notify body, and the only command run against the store is `git for-each-ref` (read).

**Assembly.** Every output sink of the verb (`log`, `step`, `_store_emit`, `_access_stderr`, `$GITHUB_STEP_SUMMARY`, the notify body) and the host script's stderr (the only host byte stream a refusal relays); chokepoints: `gd_capture` (stdout never printed raw) and `_access_stderr` (filters and `::stop-commands::`-wraps relayed stderr).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | the host script echoes a refname or the repository basename to fd 3 or fd 4 (the only relayed channels; stderr itself goes to /dev/null) on a refusal | RED (print scan on a failure row) |
| 2 | the host script runs `git gc`, `update-ref`, `rm`, `chown`, `mount` or `systemctl` | RED (the write-verb shim fires; shims exist for every listed verb) |
| 3 | the runner prints `$GD_CAPTURED` on the failure path, or before the regex match | RED (print scan on a malformed-answer row) |
| 4 | a second repository whose directory name is hostile (`.git`-suffixed, containing `::error::`) beside a clean first | RED unless the name is classified and discarded (`refs_repo_not_single`, name absent from every sink) |

**Harness rows.** Break the scanner (empty its identifier list): the scan row must go RED. Must-PASS non-canonical: identifiers containing `.`, `_`, `-` and digits only, through both a success and a refusal path. The identifier list is built from the fixture builder's own variables, never hand-listed.

**Anchor.** The identifier list derives from the fixtures (anything used to name a repository or ref is scanned automatically).

## Architecture Decision (ADR/C4)

### ADR

No ADR is created or amended: the change adds a read-only verb to an accepted design (ADR-220 access path, ADR-239
LUKS-served store, ADR-241 environment gate) and makes no ownership, trust-boundary or substrate decision. The
decisions that shaped it are CTO rulings in `decision-challenges.md`. Test: a competent engineer reading ADR-220/239
and the C4 would not be misled, except for the one C4 edge sentence below.

### C4 views

Read in full: `model.c4`, `views.c4`, `spec.c4`. Checked: (a) external human actor - the owner dispatching through GitHub
is already modeled, unchanged; (b) external system - GitHub Actions -> git-data over the existing root-SSH edge, no new
vendor; (c) container/data-store - `gitDataStore` already modeled; (d) actor-surface access relationship - unchanged
(same reviewer environment, same key). One element description IS falsified: the `github -> gitDataStore` edge text says
"None of those five modes copies or mounts a volume". In-scope tasks (CTO F16): replace it with "None of the cutover-job
modes", add `refs_assert` to the read-only sentence (job `cutover`, counts and shas only, flag off), regenerate
`model.likec4.json` with `scripts/regenerate-c4-model.sh` (CI byte-diffs it against a render of the `.c4` sources), run
`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`
(green on the base tree today).

### Sequencing

Nothing is soak-gated; the edge sentence is true as of merge.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "build mode=refs_assert in .github/workflows/git-data-cutover.yml and its script git-data-cutover.sh" | Proposed Solution: workflow + `mode_refs_assert` + host script | mapped |
| 2 | "read-only, run with the flag off, lists ref names under refs/soleur/worktrees/<worktreeId>/ of <syntheticId>.git plus 40-hex shas, printed as counts and ids only" | Host-script design, F4/F5/F12 (branch-tip shas printed; ref and worktree names counted never printed) | mapped (names are classified and counted, not listed: CTO F4; `<syntheticId>.git` binding dropped: CTO F8) |
| 3 | "own typed confirm token, same environment gate, no SSH from the operator" | Workflow (b), job `cutover` reuse, `REFS-ASSERT-GIT-DATA` | mapped |
| 4 | "Update the runbook ... where it says refs_assert is \"not yet built\" (REFS-CONFIRMED definition, R3 and R6 rows)" | Phase 4 | mapped |
| 5 | "Plan must list the hash-bound paths and verify no planned file is among them" | Hash-bound paths section, AC1, one suite row | mapped |
| 6 | "never workspace ids in the clear: follow the existing hashed-name convention in git-data-cutover.sh" | Research Reconciliation row 1 (the family convention is no name at all) | mapped, premise corrected |
| 7 | "Do not run scripts/test-all.sh unscoped; plan only scoped tests" | Phase 5 | mapped |
| 8 | "PR body may say \"Closes #11431\" only if the mode is fully built" | Header, AC16 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| host script `git-data-refs-assert.sh` | "build mode=refs_assert in .github/workflows/git-data-cutover.yml and its script git-data-cutover.sh" | asked (the verb needs a body; stdin delivery keeps the hash roster untouched) |
| run-title classifier edit | "Do not touch cloud-init-git-data.yml ..." (the mode must not break the wipe's guards) | inferred - justification: a `git-data refs_assert` run after the stamp would make the wipe refuse `wipe_precondition_run_title_unparseable` |
| C4 edge sentence + regenerated JSON | "Update the runbook ..." | inferred - justification: the edge text enumerates the cutover modes ("five modes"); leaving it falsifies the recorded architecture, and CI byte-diffs the JSON |
| restating census pins | "plan only scoped tests for the touched workflow/script/runbook tests" | asked |
| `guard-vacuity-floor.test.sh` + `suite-shard-legs.tsv` rows | — | inferred - justification: a new suite with a `MIN_ASSERTIONS` floor in `apps/web-platform/infra/` trips the vacuity ledger (`PROMOTED_FILES`, absolute `MIN_FIRING_SUITES`) and the shard map |
| notify words, `refs_class` output, `class=` in output | "no SSH from the operator" (diagnosable without logs-by-SSH) | inferred - justification: the CPO's C5 and the CTO's F14 require the FAILED/INCONCLUSIVE class to be readable without SSH |
| Phase 6 comment on #8211 | — | inferred - justification: CPO C9 (the PR delivers no live-host change) |

### Split Assessment

- Subsystems touched: 4 - `.github/workflows`, `apps/web-platform/infra`, `scripts`, `knowledge-base`
- Planned files: 14 | Estimated changed lines: ~850 (host script ~170, verb ~110, new suite ~400, pin restatements ~80, runbook ~50, workflow ~50, C4 ~5 plus generated JSON)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the thresholds trip on roots and lines, but no seam is separable: the mode is useless without its host verb and tests, the classifier edit must land in the same merge so the wipe never meets an unparseable title, and the runbook and C4 sentence are true only together with the code.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: tests (RED) -> host script -> verb -> workflow -> docs -> scoped runs.

### Phase 0 - read before writing (no edits)

- Read `case_parity` (P1-P4), `case_capture_census`, `case_verb_census`, `case_rb`, D-6, `WF-gating`, `N-body`/`N-exprs` and the AC9 flag-precheck pin in `git-data-cutover-access.test.sh`, and the `MODES`/confirm-table/`WS-*` lines in `git-data-wipe-access.test.sh`, to list each literal to restate. Read `git-data-wipe-assert.test.sh` P1-P7 as the template for the new suite's parity rows.
- If the wipe-assert suite's P3 is wipe-specific, no edit is needed there and the new suite derives its own parity.

### Phase 1 - RED tests

1. `git-data-refs-assert.test.sh` (fixtures with real `git`, synthesized identifiers only): the happy path and the must-PASS non-canonical fixture (Guard 1 harness b); every refusal row asserting the WHOLE stdout/stderr line, not a substring: `refs_repo_absent`, `refs_repo_not_single` (two repositories; a symlink entry; a plain-file entry; a symlinked `repositories` directory; stderr digits only), `refs_none` (a REAL never-pushed `git init --bare` fixture; also a lone unborn HEAD and a loose ref outside `refs/soleur/worktrees/`, neither counts), `refs_no_branch_tip`, `refs_unreadable` (a missing object; a 201-ref repository; a wrong-owner repository via a `git` shim returning dubious ownership, no root needed), `refs_shape_failed` (a ref outside heads/tags; an id outside the charset; `heads/a..b`; the `rc=27|96` suffix; a shim answer with an extra line), `refs_bad_sha` (a tree under heads; a tag to a non-commit); `heads/feature/x.y` passes; runner-side `cutover_frozen`/`old_store_unmounted`/`store_not_on_mapper`/`store_unverified`/`probe_failed rc=124/255`; the format pin and "drop `%(objecttype)`" mutation; the stdin-delivery row (the ssh shim feeds the real body through a real `bash -s` and a `git` shim that reads stdin; the script is not `file()`-bound); the read-only shims for every write verb in the mutation list; the print scan over stdout+stderr+summary of EVERY row; one parity row (script exit-code table with classes <-> runbook Verdict map); the exclusion-predicate parity row; the guard matrices; `MIN_ASSERTIONS`.
   - 1.1.5 Harness requirements (deepen pass, test-design review): fixtures run with `HOME` and `TMPDIR` under a `mktemp -d` scratch directory, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, fixed author/committer variables, `ulimit -c 0`, a cleanup trap, no fixed paths or ports; the 201-ref fixture is built with `git update-ref --stdin` from a template repository copied per row; fixture identifiers are long and unique (16+ characters mixing `.`, `_`, `-` and digits, for example `wt-7f3a.k_91x`) and the print scan is one named `assert_clean <row>` helper so a failure names its row; the scan also covers the relayed `_access_stderr` output and the fd 3 / fd 4 channels. Real git refuses `update-ref` of names containing `..`, a leading `.` or a `.lock` suffix and `for-each-ref` silently skips such loose refs with only a stderr warning, so (i) the broken-ref rows are built by writing loose files by hand (`heads/a..b`, a file containing `garbage`) and must reach rc 27 through the non-empty-stderr rule; (ii) the regex-rejection rows use one ref per hostile class git accepts (`heads/a+b`, `heads/a,b`, `heads/x$y`, a backtick name, `heads/-dash`, a non-ASCII name, a worktree id containing `+`), each asserting rc 27 and a clean print scan; (iii) the `.lock` / leading-dot branches are exercised through a `git` shim that fakes the `for-each-ref` output, labelled "parser-level"; (iv) a row where the ssh stub returns stderr `::error::x`, `::stop-commands::` and `::add-mask::` with rc 21 asserts the whole output (no workflow command survives); (v) a `<repo>/shallow` file gives rc 26. The missing-object row uses a `git` shim exiting 128 with fatal text (real git aborts with a version-dependent rc such as 134); a real-git row stays only if it tolerates 128 or 134. Added rows from the design: a `git` shim logs invocations so the rc 20 and rc 21 rows assert zero `for-each-ref` calls (and a mutation moves the read ahead of the count); the `exec ... </dev/null` removal turns the stdin-reading shim RED; a fixture with 4 heads (two branches on the same sha) pins the 2-sha cap, sort-by-sha and de-duplication, plus a mutation row that breaks the self-check invariants; a 200-ref must-PASS row sits beside the 201-ref row; a fixture violating two conditions at once pins the refusal order 23, 27, 28, 24; mutation rows for `-c safe.directory`, `GIT_NO_REPLACE_OBJECTS` and `HOME`; Guard 1 #3 is two rows (regex anchors; a forged line with the script not sent). AC10 is tested by running the extracted notify body with a poisoned environment and step-summary file carrying a fixture sha and id and asserting neither appears. AC1 and AC16 use `$(git merge-base origin/main HEAD)` rather than `origin/main...HEAD`. A local SKIP of the wipe-assert loopback tier without root is not evidence.
2. Restate the pins in `git-data-cutover-access.test.sh`, `git-data-wipe-access.test.sh`, `git-data-wipe-runs.test.sh` (red until the code lands).

### Phase 2 - host script and verb

3. Write `git-data-refs-assert.sh` per the design; copy the `git-data-wipe-assert.sh` header sections (HOW IT RUNS, WHAT IT PROVES, NO NAME LEAVES THE HOST, EXIT CODES). It assigns none of `STORE_DEVICE`, `STORE_VERIFIED`, `cutover_freeze`, `MOUNT_ROOT`, `GIT_DATA_ROOT`, `REPO_ROOT`.
4. Add `mode_refs_assert` + emitters to `git-data-cutover.sh` by copying the `mode_wipe_assert` / `_wipe_emit` structure; extend the `MODE` validation `case`, the `refuse_legacy_modes` remedy words and `main()`; the new `gd_capture` is the only added remote read.

### Phase 3 - workflow and classifier

5. Edit the workflow (a)-(g); re-measure the `discoverability_test` count. 6. Edit `git-data-wipe-runs.sh` (+ header lines 8 and 17, + test rows). 7. Add the vacuity-ledger and shard-map rows.

### Phase 4 - runbook and C4

8. Runbook (`git-data-luks-cutover-5274.md`), shaped per CTO F16: one new subsection `### Reading REFS-CONFIRMED` holds the semantics; R3, R6 and Abort carry one line plus a link each.
   - `### Reading REFS-CONFIRMED` contains: the dispatch string; the verification command for the evidence (`gh run view <id> --json conclusion,createdAt,headSha,event,name`: conclusion `success`, event `workflow_dispatch`, `headSha` the main commit containing `refs_assert`, `createdAt` later than R5's completion and than R4's run id; a re-run attempt of an older run id does not count); dispatch only after the last synthetic push and after replication has had time to complete (replication is asynchronous; paste the push time and the run `createdAt`); an R6 gate that the R3 `op:exempt-pass` Sentry read for the rehearsal window shows no event from any hashed id other than the synthetic account's, stating the query; a line that a tip sha the owner happens to hold is extra corroboration, never a requirement (F19); the plain residual that the printed branch-tip shas are visible to repo readers and the pass attests what the git-writable store holds, not authenticity; and 'tree and history completeness are not proven here beyond git receive-pack's own connectivity check at push time' (F20); the definition ("the store holds exactly one repository, and it has at least one well-formed commit ref under refs/soleur/worktrees/<id>/heads/"; no `<syntheticId>.git`); the residual stated plainly (the host does not prove the repository is the synthetic account's; provenance rests on (1) the store empty at flip, R0 proof `clear`, (2) the quiet window refusing everyone but the one exempt account, R3 evidence exemptConfigured=true on both hosts and refused_since_last>0, (3) R7 as the after-the-fact check, a real user's repository would survive the deletion and R7 would read `store_not_empty`; the R3 `op:exempt-pass` Sentry event with its hashed id is the detector if the exemption failed open); evidence binding (CPO C7: only a completed run with conclusion `success` and `STORE probe=refs-assert verdict=ok`, dispatched after THIS rehearsal's R4 AND after R5 reads `disabled` on both hosts, with the flag off, before the account deletion; `queued`, `cancelled`, `skipped` and awaiting-approval mean `not read`; wait for the R4 run to finish; paste the anchored `refs_assert ok ...` line next to the run URL before the deletion, because logs expire and the deletion removes the repository); necessary-not-sufficient (C6: it does not clear the "Known latent behaviours" real-flip block); the FAILED / INCONCLUSIVE meanings and the retry rule (only `probe_failed` and `refs_unreadable`, twice, then one `action-required` issue naming the ACTION; `refs_repo_not_single` and `refs_shape_failed` are INCONCLUSIVE but not retryable and route to Store not empty steps 1-4 and the CLO); `refs_repo_absent` is FAILED before the deletion and expected after it; a dispatch with the flag on is red `flag_already_true`, not a verdict, and its issue is closed with a comment before the next dispatch; a wrong token is refused at the confirm step (state its word) and `CUTOVER-GIT-DATA` is refused for this mode; ordering: dispatch `refs_assert` immediately after R5 and BEFORE the R6 proof, and a red `refs_assert` is never an expected red (no proof dispatch, no planned-run comment, its issue is genuine); a queued `refs_assert` can displace a pending recovery dispatch in the one-pending `git-data-state` group, so dispatch only when `gh run list --workflow git-data-cutover.yml --status in_progress,queued` is empty; it holds `web-1-swap` and blocks deploys for its duration, like `proof`; merging changes no live host (the 2026-10-27 shallow-update rejection is fixed only through the owner-gated `git-data-host-replace` dispatch; C9); the dead end after a FAILED stop (the synthetic account stays, the next R0 proof reads `store_not_empty`, the next move is a new decision; F17).
   - R3 row: replace "(a #8211 follow-up, not yet built) after R4 with the flag off" by the link; the sentence "No other read confirms it inside the window (`proof` refuses while the flag is on, and no SSH read is permitted)" is reworded so it no longer implies REFS-CONFIRMED has no route; keep "A ref listing typed by the owner is never evidence" and the "`<id>.git` existing ... never count" sentence.
   - R6 row: edit the text containing "BEFORE the deletion (EXPECTED red": `refs_assert` runs after R5 and before the proof; REFS-CONFIRMED means that run is green.
   - Abort paragraph: "(`refs_assert` is not built)" becomes "without REFS-CONFIRMED (`refs_assert` not run, FAILED or INCONCLUSIVE)"; the clause about closing the proof's expected-red issue applies only if the proof was dispatched.
   - r3-verdicts template: `REFS-CONFIRMED <yes: refs_assert run <url>, repos=1 refs=<n> heads=<n>|FAILED <word>|INCONCLUSIVE <word>|not read>` plus "words and classes: see Verdict map".
   - `### The modes` table row (`refs_assert` / `REFS-ASSERT-GIT-DATA`), the mode list near the top of the runbook (header lines 3-6, and `snapshot_clear` missing today), and a `### Downtime and blast radius` row (nothing stops, read-only).
   - `## Verdict map`: one row per word (`refs_repo_absent`, `refs_repo_not_single`, `refs_none`, `refs_no_branch_tip`, `refs_unreadable`, `refs_shape_failed`, `refs_bad_sha`) with class, cause and next step, each naming `probe=refs-assert verdict=<word>` in one table; every word is emitted by a non-test file.
9. C4: edit the `github -> gitDataStore` sentence in `model.c4` (F16); run `scripts/regenerate-c4-model.sh`.

### Phase 5 - scoped verification (no `scripts/test-all.sh`)

```bash
bash apps/web-platform/infra/git-data-refs-assert.test.sh
bash apps/web-platform/infra/git-data-cutover-access.test.sh      # bound 600 s
bash apps/web-platform/infra/git-data-wipe-access.test.sh
bash apps/web-platform/infra/git-data-wipe-assert.test.sh          # sudo env WIPE_ASSERT_REQUIRE_LOOPBACK=1 in CI; SKIPs the loopback tier without root
bash scripts/lib/git-data-wipe-runs.test.sh
bash tests/scripts/test-git-data-root-token-census.sh
bash scripts/check-cloudflare-token-drift.test.sh                  # W7 counts unchanged
bash scripts/guard-vacuity-floor.test.sh
bash scripts/lint-orphan-test-suites.sh
bash plugins/soleur/test/c4-count-parity.test.sh
( cd apps/web-platform && npx vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts )
actionlint .github/workflows/git-data-cutover.yml
shellcheck apps/web-platform/infra/git-data-refs-assert.sh apps/web-platform/infra/git-data-cutover.sh
python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-29-feat-git-data-cutover-refs-assert-plan.md
python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main
bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch
npx markdownlint-cli2 <the plan, tasks.md, the runbook>
git diff --quiet origin/main...HEAD -- apps/web-platform/infra/git-data-flag-precheck.sh
```

Restate the suite floors (`MUTANT_FLOOR`, `FLOOR`, `MIN_ASSERTIONS`) from the printed totals after the last edit and paste the totals into the commit message. The workflow's `run:` snippets are exercised with `bash -c` on extracted bodies, never `bash -n` on the YAML. Never dispatch any workflow, never write Doppler, never run `flip.sh`.

### Phase 6 - ship-time follow-through (no operator step is added by this PR)

- Before the PR is marked ready, `gh issue list --state open --search "git-data-host-replace rehearsal re-run"` and a read of #8211's open comments: cite an existing tracker if one covers "host replace -> rehearsal -> `refs_assert`"; otherwise add ONE comment on #8211 naming that sequence, that merging changes no live host (C9), and the parked F17 dead end (after a FAILED stop the synthetic account stays; deleting it as cleanup is a runbook policy change touching Art. 17 and the CLO's sequencing). The dispatches themselves are the runbook's steps and are never run by this session.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1 - Hash-bound roster untouched: `grep -o 'file("${path.module}/../../[^"]*")' apps/web-platform/infra/modules/git-data-userdata/main.tf | wc -l` prints `16`; `git diff --name-only origin/main...HEAD` intersected with those 16 plus `cloud-init-git-data.yml`, `modules/git-data-userdata/**` and `git-data-rung2-boot-evidence.env` is empty; one suite row proves `git-data-refs-assert.sh` appears in no `file()` binding.
- [ ] AC2 - Mode wiring: the `mode` input has exactly the ten options; `REFS-ASSERT-GIT-DATA` is the only accepted token for `refs_assert` and every other mode's token is refused for it; `lineage`/`volume_id`/`origin_run` are refused with it; the input set is unchanged (`{confirm, lineage, mode, origin_run, volume_id}`).
- [ ] AC3 - Flag handling: with the flag `true` the run refuses `flag_already_true` before any host is dialed; with off/unset it proceeds; `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/git-data-flag-precheck.sh` exits 0; the AC9 flag-precheck pin in the cutover-access suite is restated for the mapped `FLAG_MODE` expression and the `flag_write` step's `if` is unchanged and never matches `refs_assert`.
- [ ] AC4 - Pass criterion and ordering: repository count is decided BEFORE any ref or sha is read (a count != 1 refusal prints a fixed word and digits only); exit 0 / `verdict=refs_confirmed` only for exactly one real repository, every ref well formed, each `heads/` object a commit, each `tags/` object peeling to a commit, at least one `heads/` tip; every refusal in the exit-code table is reproduced by a fixture with its fixed word, asserted on the WHOLE line; a REAL never-pushed `git init --bare` fixture refuses `refs_none`; a lone unborn HEAD or a loose ref outside the namespace does not count; the anchored regex rejects `repos=2`, `heads=0`, `refs=0`, `namespaces=0`.
- [ ] AC5 - Read-only: the shim set contains one failing shim for every write verb in Guard 2 mutation 2 (an anchor row asserts the shim list equals the verb list) and none fires; the only command run against the repository is `git for-each-ref`.
- [ ] AC6 - No name leaves: the print scan finds no fixture repository name, worktree id, ref name or workspace id in stdout, stderr, step summary, run title or notify body of any row (success or refusal); the only 40-hex strings are inside the matched `shas=` field.
- [ ] AC7 - Same gate, no SSH from the operator: the workflow change adds no `environment`, job, secret binding or bridge `uses:`; `tests/scripts/test-git-data-root-token-census.sh` and `scripts/check-cloudflare-token-drift.test.sh` (W7) are green with counts unchanged; the runbook contains no operator SSH step for the mode.
- [ ] AC8 - Host delivery: the ssh shim row proves the body arrives on stdin to a real `bash -s` with `REFS_REPOS` `%q`-quoted in front, with a `git` shim that reads stdin and does not consume the script, and that the gd_capture bound is 60 s.
- [ ] AC9 - Run-title classifier: `git-data refs_assert` classifies `other`; a `refs_assert` run after the stamp leaves the wipe guard `ok`; `git-data refs_assertX` stays `unparseable`; both stale "five non-wipe modes" comment lines are reworded.
- [ ] AC10 - notify-failure: `refs_assert` is a known `MODE`; a failed run produces `REFS_ASSERT_FAILED` or `REFS_ASSERT_INCONCLUSIVE` per `refs_class` and a body without any sha; the annotation and summary carry `class=`; `grep -c -e REFS_ASSERT_INCONCLUSIVE .github/workflows/git-data-cutover.yml` prints `2` and the same count for `REFS_ASSERT_FAILED` prints `2` (so a stray comment mention cannot pass by accident).
- [ ] AC11 - Census pins restated and green: `git-data-cutover-access.test.sh` (mode options, AC9 pin, ordered steps, G5 name allow-list, floors), `git-data-wipe-access.test.sh` (MODES, confirm table), `guard-vacuity-floor.test.sh` (`PROMOTED_FILES` + `MIN_FIRING_SUITES`), `lint-orphan-test-suites.sh`, and the shard-map row.
- [ ] AC12 - Runbook: `grep -c -e 'follow-up, not yet built' -e 'refs_assert not built' -e 'refs_assert. is not built' <runbook>` prints `0` (the unrelated re-erasure "is not built" sentences stay and are not matched); `### Reading REFS-CONFIRMED` carries every item listed in Phase 4 (definition without `<syntheticId>.git`, residual, C6, C7, retry rule, flag-on red, ordering, queue displacement, C9, F17 dead end); R3, R6 and Abort link to it; the modes table, the mode list near the top, the downtime table and the Verdict map carry `refs_assert`; the single parity row (script table <-> Verdict map) is green; `awk` over the new section and the Verdict-map rows for `ssh|docker exec|journalctl|systemctl` counts `0` (no SSH fallback wording).
- [ ] AC13 - C4: the `github -> gitDataStore` edge text no longer says "five modes" and names `refs_assert`; `model.likec4.json` is regenerated; `c4-code-syntax`, `c4-render`, `c4-count-parity` green.
- [ ] AC14 - Guard Contract rows exist as named rows in the new suite and each mutation goes RED with its landing asserted; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC15 - Phase 6 is done or recorded: an existing tracker is cited or one #8211 comment is added; no workflow was dispatched.
- [ ] AC16 - Process: commits and the PR title use `Ref #8211`; the trailer is `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; the PR body ends with the Claude Code line, may say `Closes #11431`, and opens with the apply-workflow note; no Doppler write, no `git stash`, no `git add -A`; `git diff --name-only origin/main...HEAD` is a subset of Files to Create + Files to Edit + this plan + `knowledge-base/project/specs/feat-one-shot-11431-refs-assert/**`.

## Test Scenarios

- Given one repository with `refs/soleur/worktrees/<a>/heads/main` at a commit, then `refs_assert ok repos=1 namespaces=1 refs=1 heads=1 shas=<40hex>` (integration).
- Given two namespaces, `heads/feature/x.y` and an annotated tag, then `namespaces=2 refs=3 heads=2` and only the two `heads/` shas are printed (counter-field row).
- Given zero repositories -> rc 20; two, a symlink entry, or a symlinked `repositories` directory -> rc 21 with digits-only stderr; a never-pushed repository -> rc 23; tags-only -> rc 24; a missing object, 201 refs or a foreign-owned repository -> rc 26; a malformed name -> rc 27; a tree under `heads/` or a tag to a tree -> rc 28.
- Given a held freeze sentinel, the runner refuses `cutover_frozen` before the script is sent.
- Given any refusal, stdout+stderr contain none of the fixture identifiers.
- Given the flag `true`, the precheck refuses `flag_already_true` (workflow-body row executed as the suite executes the precheck step today).
- Regression: the wipe guard with a `git-data refs_assert` run after the stamp returns `ok`, not `wipe_precondition_run_title_unparseable`.
- Pyramid layers: all rows `unit`/`integration` (PATH shims + real `git`); no `e2e` row (a live dispatch is a runbook step, never run by this session).

## Dependencies & Risks

- **Provenance weakness (documented, not hidden).** `repos=1` proves "the store's only repository holds a replicated commit branch tip", not "it is the synthetic account's"; the runbook states the three-part provenance and the detector (CTO F8).
- **Refs may not survive R4.** If the rollback leaves the repository with no refs the read is `refs_none` and R3 stays unmet ("replication unproven"); after a FAILED stop the synthetic account stays and the next R0 `proof` reads `store_not_empty` (F17, parked on #8211).
- **Census suites are brittle by design.** G5 now uses a name allow-list so the next stdin verb is a one-token edit; floors are restated from printed totals each time.
- **Merge fires `apply-web-platform-infra.yml`** (path filter `apps/web-platform/infra/**`); with no `.tf` and no `file()`-bound payload change its `-target` plan is a no-op - read the run's plan, never dispatch it from here.
- **Hash roster.** Any accidental edit of a roster file re-HOLDs `git_data_rung2_rehearsal_gate`; AC1 runs before every commit.
- **Concurrency.** The mode inherits `web-1-swap` and `git-data-state`: it queues behind a flip or rollback (wanted) but can displace a pending recovery dispatch (documented in the runbook, with a `gh run list` gate).
- **Provisioning seeds nothing** (verified: `git init --bare` only), so `refs_none` is a real "not replicated" signal.

## References

- Issue #11431; epic #8211; draft PR #11567.
- Prior ruling: `knowledge-base/project/specs/archive/20261027-122137-feat-one-shot-8211-git-data-remote-url-path/decision-challenges.md`.
- Model verb: `mode_wipe_assert` in `apps/web-platform/infra/git-data-cutover.sh`; model host script `apps/web-platform/infra/git-data-wipe-assert.sh` (stdin delivery, fixed-shape line, exit code = verdict, `exec` fd redirection).
- Runbook: `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (R3, R6, Abort, r3 verdicts, Verdict map).
- Run-title classifier: `scripts/lib/git-data-wipe-runs.sh`.
- Learnings: 2026-10-15 census-that-stubs-the-host-verb; 2026-10-18 counter-field; 2026-10-27 technical-fork-as-operator-item.

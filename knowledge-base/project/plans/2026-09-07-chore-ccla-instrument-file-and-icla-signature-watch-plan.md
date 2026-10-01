---
title: "chore(cla): --instrument-file for ccla-add.sh, and an epoch-aware watch for the CCLA representative's ICLA signature"
date: 2026-09-07
slug: chore-ccla-instrument-file-and-icla-signature-watch
branch: feat-one-shot-7909-7910-ccla-instrument-file-icla-watch
issue: 7909
closes: [7909, 7910]
type: chore
priority: p2-medium
domain: [engineering, legal]
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
lane: cross-domain
---

## Enhancement Summary

**Deepened:** 2026-09-07. **Panels:** six plan-review agents (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, CTO-devex) then seven deepen passes
(verify-the-negative, security-sentinel, test-design-reviewer, observability-coverage-reviewer,
git-history-analyzer, user-impact-reviewer, data-integrity-guardian). All deepen-plan halt gates
(4.5 scoped out, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11) pass.

**Nine claims this plan made were falsified by measurement and corrected here**, which is the
deepening that mattered:

1. The probe's own prototyped `jq` predicate **returned PASS on an unreadable coverage map**
   (`count=1 rc=0`, reproduced) — a process substitution's exit status is invisible, so a broken
   roster and an empty roster were byte-identical. It would have auto-closed the tracker
   permanently while telling the operator the opposite of the truth.
2. **The probe could never legitimately take exit 0.** The epoch is today and this repo requires
   contributors to sign, so the first unrelated signer latches PASS forever. The probe is now
   notify-only.
3. The parity arm was **vacuous against the live repo** (one anchor match ⇒ `--first-parent` is a
   no-op, `head == tail`) and **unrunnable on its own shard** (`ci.yml` checks out `test-webplat`
   shallow). It now runs over a family of synthetic fixtures.
4. The count form removed *direct* naming and left **derivable** naming intact — a dated public
   transition next to an organisation's name joins against a public git-versioned ledger. The
   tracker now names no counterparty.
5. `sla_business_days` reaches Guard B only; **Guard C's 30-day close-as-`not planned` is
   hardcoded**, so the first draft's resolution did not resolve the finding it named.
6. Two Guard 2 mutation rows were **unbuildable or miscoded**, and the `--` drift vector was
   covered by no fixture while `-S`→`-G` was uncoverable in principle.
7. `discoverability_test.expected_output` was **satisfied by both branches**, so it asserted
   nothing.
8. "The probe binds no credential" is false on the runner — `actions/checkout` persists a token
   into `.git/config` that `env -i` does not remove.
9. `--no-tags` is not the fetch's bound; `FETCH_HEAD`, `gc --auto` and submodule recursion all
   write into the shared common dir.

**Also measured and folded in:** this worktree is *already* shallow from a prior `ccla-add.sh`
fetch (which is why the `--is-shallow-repository` control was cut — it would have false-positived
on a machine where the derivation works); `git clone --depth=1` silently ignores `--depth` on a
local path; `date -u -d ""` returns today rather than erroring.

**Larger than this PR, recorded not lost:** see `## Deepen-Plan Findings`, whose blocker is that
no correction path exists for a wrong hash on an unerasable public record — a decision that is free
today and a schema migration after the first row.

## Overview

Two changes on the same surface — the Corporate CLA recording path — shipped together because
both are wanted before the in-flight counterparty's designated representative signs the
Individual CLA, not after.

**#7909** removes the one hash in `apps/cla-evidence/scripts/ccla-add.sh` still transcribed by
hand. `--instrument-sha256` takes 64 hex characters that land in a permanent, world-readable
roster row about a third party, and a wrong value there is the one field nothing else in the
repository can contradict. A new `--instrument-file` flag hashes the file directly, reusing the
pattern the script already applies to the Corporate CLA document itself at `ccla-add.sh:301`.

**#7910** replaces a by-eye check with a probe. Since PR #7828 the entry gate is temporal: an
account enters the roster only if its ICLA signature is dated at or after the coverage-map
notice epoch, derived from git rather than written down. Both accounts in the live ledger
predate it, so "have they signed?" no longer answers the question.

The probe asks the real question **without naming anyone**: *is there any ICLA signature dated
at or after the notice epoch that no live roster row already covers?* Measured today: 0. It
becomes ≥ 1 the moment the designated representative signs. The sweeper posts probe output
verbatim into a public issue comment every sweep, so a probe holding no personal data is not a
nicety — it is the constraint the CLO review imposed, and the count form satisfies it by
construction rather than by care.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed): no `spec.md`
exists for this branch, so the domain fan-out is not narrowed.

## Research Insights

### Premise Validation (plan Phase 0.6) — every row measured, not asserted

| Cited | Result |
|---|---|
| #7909, #7910 | both OPEN, `type/chore` |
| #7846 (the counterparty) | OPEN; the CCLA reply is **unsent**, `status: awaiting-operator-send` — the signatory is not yet named, which is why the probe must work without one |
| #3210 / PR #7828 | closed / merged; `96d8501fa30288d6ac2b8dea66a353adb7a77eaa` introduces the notice anchor |
| ADR-201 | exists and is the governing decision |
| `ccla-add.sh:292-303` hashes a file already | confirmed verbatim, including the `^[0-9a-f]{64}$` re-validation |
| `MIN_ASSERTIONS=40` is tight | suite run: `Total: 40 passed, 0 failed` — zero slack |
| `ccla-add.test.sh` is in `want_webplat` | `test-all.sh:1964`, rationale `:1946-1954` |
| the epoch | `2026-09-07T15:16:45Z` — **exactly one match** |
| `%cI` vs `%aI` on that commit | `…T15:16:45Z` vs `…T17:16:45+02:00` |
| control operands | parent of the anchor is `c774f2317807acd8b6cd707a8028bfa27fc4a474`; anchor occurrences: parent **0**, anchor commit **1**, HEAD **1** |
| the ledger | two accounts, `2026-02-27` and `2026-05-04` — both pre-epoch |
| the roster | `{"schema_version":"1.0","organizations":[]}` |
| **the probe's own predicate, prototyped** | the `jq` in §"The probe" run against the real ledger, roster and epoch returns **0** — the correct answer today |
| `MIN_PROBES` | `68` at `followthrough-exec-bit.test.sh:85`; the glob matches **78** (including the 11 `.test.sh` companions, all `100755`) — already 10 stale |
| labels | `follow-through`, `type/chore`, `domain/legal`, `priority/p2-medium`, `action-required` all exist |
| sweeper `secrets=` semantics | `sweep-followthroughs.sh:367` is `[[ -n "${!name+x}" ]]` — a *set* test, so a set-but-empty `${{ secrets.X }}` passes through as `""` and only a genuinely unset name aborts |
| **the sweeper's checkout** | `scheduled-followthrough-sweeper.yml:50-52` — `timeout-minutes: 10`, `actions/checkout` with no `fetch-depth` (depth 1) |
| **CI's `test-webplat` checkout** | `ci.yml:743-749` — a 2-shard matrix, `actions/checkout` with **no `fetch-depth`**, i.e. also shallow, and both shards run `test-all.sh webplat` |
| **this worktree is already shallow** | `git rev-parse --is-shallow-repository` → `true`; `.git/shallow` (41 bytes) exists in the **common dir** and equals `origin/cla-signatures` — written by a prior `ccla-add.sh` ledger fetch |
| **a second monitor polls the same label set** | `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` — `sla_business_days` default 5 (public "manual intervention required" comment), and Guard C closes as `not planned` at **30 business days** |
| open `follow-through` issues | **51**, against the sweeper's hard `--limit 50` |
| remote tags | `git ls-remote --tags origin \| wc -l` → **over 3,000** (a drifting count — measured twice minutes apart at 3084 and 3085; the "157 tags" figure at `ccla-add.test.sh:54` is stale by more than an order of magnitude, and the conclusion `--no-tags` is unchanged and strengthened) |

**Mechanism-vs-ADR check.** The ADR corpus has one hit for `coverage map` / `ccla` /
`Corporate CLA`: ADR-201, which *is* the decision both changes sit inside. Neither reverses or
extends it.

### Property List (plan Phase 0.6b)

| # | Property |
|---|---|
| P1 | The instrument hash written into the roster is the hash of the instrument file, not a value a human retyped. |
| P2 | `--instrument-sha256` continues to work for the hash-only case. |
| P3 | Missing, empty, not-a-regular-file and unreadable are each refused with a message naming which fault it is. |
| P4 | The two flags cannot both take effect in one invocation. |
| P5 | The operator is told, without asking, how many ICLA signatures satisfy the temporal gate and are unknown to the coverage map. The probe reports; it does not close. |
| P6 | "Measured, not yet" reads differently from "could not measure", in both message and exit code. |
| P7 | The epoch the watch uses is the same moment the merge gate uses, and is never hardcoded. |
| P8 | The watch creates no tags and no local branches in the repository it reads, and leaves no repository-wide state change behind. |
| P9 | No surface this plan creates publishes — or lets a reader **derive** — an association between a named GitHub account and a corporate designation. Derivability is the operative half: the ledger it measures is public and git-versioned, so a dated public transition next to an organisation's name is a join, not a hint. |
| P10 | The bytes hashed are the executed instrument as received on the encrypted operator drive, not a copy inside the repository. |
| P11 | The `Instrument hash` in `knowledge-base/legal/ccla-register.md` and the `executed_instrument_sha256` in the roster cannot silently diverge. |

P9 came from the CLO review, P10 from its finding P2, P11 from the spec-flow review — see
§"What plan review changed". P8 was narrowed from "writes no refs" (false by design: the ledger
fetch writes `refs/remotes/…`) to the property that is actually true and actually checkable.

### Cut List (plan Phase 0.6b, extended by plan review)

| Cut | Property it would buy | Why (verified) |
|---|---|---|
| A bespoke scheduled workflow or reminder for the watch | P5 scheduling | The sweeper already polls, comments and auto-closes. Only the predicate was missing. |
| A roster field recording which flag produced the hash | none | The schema is `.strict()` (`ccla-add.sh:20-25`), and it would break the P1/P2 output equality the agreement arm rests on. |
| Reading the ledger via `gh api .../contents` | "read the ledger" | The `git show origin/cla-signatures:signatures/cla.json` idiom is already at three sites. |
| Exit code 1 in the probe | none | Exit 1 = FAIL in the sweeper contract **and** the reopen trigger on a closed issue. A not-yet condition must never take it. |
| **Watching a named login** (probe constant / issue-body marker / Actions secret) | P5 with account precision | **Cut.** Two panels fired on the same scope. The count form satisfies P5 and satisfies P9 *by construction*, and deletes: the secret, the workflow `env:` line, the operator's `gh secret set` step, login-grammar validation, the never-print control, `secrets=GH_TOKEN`, `gh api /users/<login>` (whose stderr publishes the login on 404 — an unenumerated leak on the one unmasked channel), the `gh` stub, two verdict states and two mutation rows. The precision given up is which account signed — which FR13 and CLO P5 already disclaim. |
| **A `--is-shallow-repository` control** | P7 | **Cut.** Measured: the ledger fetch's `--depth=1` writes `.git/shallow` into the **common dir**, so it is repository-wide and shared by every worktree — and this checkout is *already* in that state from a prior `ccla-add.sh` run. The control would therefore print `the sweeper needs fetch-depth: 0` on a machine where the derivation demonstrably works, naming an unmeasured cause. Control B measures the real property directly and catches strictly more (a `--depth=50` boundary, a `git replace` graft, a filtered history, a squash rewrite). |
| **An "anchor still present at HEAD" control** | P7 | **Cut.** It would give the probe a refusal condition the authority does not have, so the two would differ in their *refusal sets* while parity compares only values — the instrument-that-cannot-tell-clean-from-never-ran class. If it is a real hazard it belongs in `roster-entry-gate.ts`, where it would block a write. |
| **A flag-presence grep arm** | P7 | **Cut.** Two of the seven elements of the TS argv array are identifiers, not literals, and "present in the probe" is satisfied by the probe's own header comment. The synthetic-fixture differential arm below subsumes it honestly. |
| **`INVOCATION_CWD` capture and relative-path support** | P3 | **Cut.** `--instrument-file` must be **absolute**. `$PWD` is logical while `git rev-parse --show-toplevel` is physical, so the inside-repo comparison would be unsound; the runbook already tells the operator to pass an absolute path; and the supported relative case was "stand inside a repo subdirectory and type `../../../media/…`". One check and one message replaces four artifacts. |
| `command -v sha256sum` pre-flight | none | The `|| die "…" 2` on the substitution already fails loudly. |
| `TRACKER` asserted against `basename "$0"`; duplicate-id ledger handling | none | Guard a copy-paste that has not happened, and a ledger that is append-only and id-keyed. |
| A generated, CI-derived epoch file read by both the gate and the probe | P7 with one implementation | Cut. Cleanest on paper, but it changes `roster-entry-gate.ts` — the merge gate the CLO blocked #7828 on twice — from deriving to reading. Larger blast radius on the load-bearing surface than the drift it removes. |
| A fifth trigger shape and a general `earliest=` rule in `followthrough-convention.md` | none yet | Doctrine generalised from one probe that has not run once. |

### What plan review changed (six agents, 2026-09-07)

Recorded rather than quietly amended, because five of these were **measurements that falsified
claims this plan made**.

1. **The parity arm was vacuous, and its shard cannot run it.** The live repo returns exactly
   one anchor match, so `--first-parent` is a no-op and `head -1 == tail -1`; against it the arm
   would pass with two of the mutations it exists to catch, plus `-S`→`-G` and a dropped `--`.
   And `ci.yml:743-749` checks out `test-webplat` **shallow**, where `--print-epoch` would refuse
   and the TS authority would return the graft date — so a real-repo arm can never be green, and
   deleting the refusal to make it green would have both sides agreeing on a wrong value.
   `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts:288-295` already states this
   ("a 1-of-1 quantification") and already solves it with synthetic repos. **Fix: a differential
   over a family of synthetic fixtures.**
2. **The prescribed pipeline could not build its own control.** `--format=%cI` discards the SHA
   that control B needs — the plan's own measurement used `--format='%H %cI'`. And `git log` with
   a non-matching pickaxe exits **0** with empty stdout, so `|| exit 3` does not catch "anchor
   never found"; an explicit emptiness check is required. The TS side has one
   (`roster-entry-gate.ts:115-122`); this was a parity gap in the admitting direction.
3. **The login-keyed design was cut** on convergent findings from both panels, and a leak path
   nobody had enumerated: `gh api /users/<login>` prints the request URL — containing the login —
   to stderr on failure, which `sweep-followthroughs.sh:378` captures and `:505` publishes.
4. **Two mutation rows were unbuildable.** `TMP_FILES=()` at `ccla-add.sh:191` is *after* the
   compute block, so a mutant appending there is reset before `cleanup()` — NFR3 is satisfied
   structurally, which is stronger, but the row could not fire. And the commit-message / PR-body
   clauses of FR8 are unreachable under `CCLA_ADD_DRY_RUN=1`, which every suite arm sets.
5. **`[[ -f ]]` reports a directory as "no such file"** — the measured-bad-for-could-not-measure
   collapse this script exists to refuse.
6. **Both new files must be committed `100755`**; `followthrough-exec-bit.test.sh` globs
   `*.sh`, which subsumes `*.test.sh`.
7. **#7909 makes the register↔roster hash divergence worse, not better** — see P11 and Phase 5.
8. **A second monitor can close this tracker as `not planned` at 30 business days**, and comment
   "manual intervention required" publicly at 5 — see §"The second monitor".
9. **`## Observability` overstated its alert routes**: `fail()` in the sweeper is
   `printf … >&2` with no `::error::`, so "script missing", "not executable" and "required
   secret not set" all leave the run **green**.

### Mechanical gates the new files enrol in

| Gate | Requirement |
|---|---|
| `scripts/lint-orphan-test-suites.sh` | `scripts/followthroughs/` matches **no** `SUITE_GLOBS` entry (`test-all.sh:77-90`, stated at `:1880`); an explicit `run_suite` is required. **The suite must be `git add`ed before this gate is run** — it enumerates via `git ls-files '*.test.sh'`, so an untracked new suite passes **vacuously**. |
| `scripts/followthrough-exec-bit.test.sh` | Every `scripts/followthroughs/*.sh`, **including `*.test.sh`**, committed mode `100755`, asserted on the git index. `MIN_PROBES` 68 → the measured post-change count. |
| `scripts/lint-followthrough-varq-ban.sh` | No `${VAR:?}` / `${VAR?}` on an executable line of the probe (`.test.sh` is out of scope). |
| `scripts/lint-shell-trace-credential-refusal.py` | The baseline is a drawdown list and new files may not join it. The count-form probe binds no credential, so the refusal may not be required — **measured at /work** by running the lint, and the block added if and only if it asks. |
| `scripts/guard-vacuity-floor.test.sh` | `COVERED_DIRS='^(scripts/\|plugins/soleur/test/)'` — the companion suite is covered and needs a sliceable floor (threshold on a contiguous simple-assignment line, `-lt` opener, `printf` to stderr plus `exit 1`, never through `fail()`). `ccla-add.test.sh` is in `PROMOTED_FILES`, so its floor is mutated and must FIRE. |
| `scripts/lib/repo-write-boundary.sh` | `--no-tags` on every fetch (`_repo_boundary_dim_refs` samples heads and tags; `refs/remotes/**` is excluded by design, tags are FATAL). Synthetic fixtures pass identity and signing as `git -c` flags, never `git config` writes (the 2026-08-20 shared-config incident). `export TMPDIR="${TMPDIR:-/var/tmp}"`. **Known blind spot:** `_repo_state` samples head, worktree, local config and heads+tags — **not `.git/shallow`**, which lives in the common dir and is shared across worktrees. Filed separately; QG10 asserts it locally. |
| `scripts/lint-guard-contract.py:73` | `MIN_MUTATION_ROWS = 3` per guard entry. |

## Problem Statement

**#7909.** `ccla-add.sh` validates only that `--instrument-sha256` is 64 lowercase hex (`:170`).
Those characters become `executed_instrument_sha256` on the default branch of a public
repository; the instrument is off-repo, so the hash is the only tamper-evidence link, and
nothing in the repository can contradict a wrong value. The same hash is hand-written into the
`Instrument hash` column of `knowledge-base/legal/ccla-register.md`. Meanwhile `:301-303`
already refuses a hand-typed value for the *other* hash the script records.

**#7910.** `resolveCoverageMapNoticeEpoch` derives from git the moment the coverage-map
paragraph reached `docs/legal/individual-cla.md` on the first-parent line —
`2026-09-07T15:16:45Z` — and refuses any account signing earlier. Both live ledger accounts
predate it. The operator cannot answer "can I record this row yet?" by looking: the question is
membership-at-or-after a moment written down nowhere. Wrong in one direction is an unexplained
`rc=4`; in the other it is a false Art. 13 claim on a permanent public surface about a real
person.

## Technical Approach

### `--instrument-file`

Parsing adds `--instrument-file) need "$@"; INSTRUMENT_FILE="$2"; shift 2 ;;` and — load-bearing
— `INSTRUMENT_FILE=""` to the initialiser at `:129-130`, because under `set -euo pipefail` the
first `[[ -n "$INSTRUMENT_FILE" ]]` on an unset variable aborts with a bare rc=1 and no message,
the exact class the comment at `:132-134` was written about.

In the `add` branch, **before** the existing `-n "$INSTRUMENT_SHA"` requirement, with mutual
exclusion first so an operator passing both gets the right message (mirroring `:171-174`):

- both set → `die` 64, naming which artifact is of record in each case
- neither set → the existing message, reworded to name both flags
- `INSTRUMENT_FILE` set:
  - `[[ "$INSTRUMENT_FILE" = /* ]]` → else `die "--instrument-file must be an absolute path — the executed instrument lives on the encrypted operator drive, outside this repository" 64`
  - `[[ -e ]]` → else `die "no such instrument file: <path>" 64`
  - `[[ -f ]]` → else `die "not a regular file: <path>" 64` *(separate, because `-f` alone would report a directory as "no such file")*
  - `[[ -s ]]` → else `die "instrument file is empty: <path> — an empty file hashes to a well-known constant and evidences nothing" 64`
  - `[[ -r ]]` → else `die "instrument file is not readable: <path>" 64`
  - `realpath -e` both the path and `$REPO_ROOT`, compare with a trailing `/` so `/repo-backup` is not read as inside `/repo`; if inside → `die "…held off-repo on the encrypted operator drive…" 2` (P10)
  - `INSTRUMENT_SHA="$(sha256sum < "$RESOLVED" | awk '{print $1}')" || die "…" 2`
  - echo the resolved path, byte size and computed hash to **stderr**
- then fall through to the **existing, unmodified** `^[0-9a-f]{64}$` assertion at `:170`.

Five hazards this shape avoids, each from a named finding:

- **`sha256sum "$path"` is wrong; `sha256sum < "$path"` is right.** GNU `sha256sum` prefixes its
  output with `\` for a filename containing a backslash or newline, shifting the fields.
- **The resolved path must never join `TMP_FILES`.** `cleanup()` (`:196-201`) `rm -f`s that
  array. The ordering already makes this structurally impossible — `TMP_FILES=()` is at `:191`,
  *after* the compute block — and that ordering is the real control; the suite asserts it
  statically rather than by a mutation that cannot fire.
- **The path must reach no committed or pushed artifact.** The instrument's filename plausibly
  carries a legal name, which is what `--sole-trader` exists to keep off-repo. The commit
  heredoc (`:399-408`) and `gh pr create --body` (`:421-427`) are unreachable under the suite's
  unconditional `CCLA_ADD_DRY_RUN=1`, so this is asserted at **source level**: grep those two
  spans for `INSTRUMENT_FILE` / `RESOLVED` and assert zero hits.
- **A substitution inside `[[ ]]` is exempt from `set -e`** (`:265-270`).
- **The retained 64-hex assertion is near-tautological** after `sha256sum` and will read as dead
  code; the comment says it fires only if field extraction is wrong.

### The probe

**The predicate — and the fail-open the first draft shipped.** The prototype in the first draft
sourced the roster id set through a **process substitution**:

```bash
--slurpfile r <(jq '[.organizations[]?...]' "$ROSTER")   # WRONG — DO NOT IMPLEMENT
```

A process substitution's exit status is invisible to both `set -e` and `pipefail`. If that inner
`jq` fails — roster missing, truncated, an HTML error page, `.organizations` not an array — it
writes nothing, `$r` binds to `[]`, `$r[0]` is `null`, and `null | index($i)` is `null` rather than
an error, so **every ledger entry reads as uncovered**. Reproduced against a malformed roster and a
single post-epoch ledger entry:

```
count=1 rc=0      # -> exit 0 -> PASS -> the sweeper posts PASS and CLOSES the tracker
```

and `closed_precheck` then refuses to re-litigate an issue carrying the sweeper's own PASS block,
so the watch is **permanently dead** while the operator has been told the opposite of the truth on
the only channel that exists. Worse, it is invisible in the output: the legitimate empty roster
(today's live state) also yields `[]`, so a broken roster and an empty roster are byte-identical in
the count.

**The form to implement** materialises every operand, checks its status, and asserts its shape —
the same discipline `ccla-add.sh:222-229` already applies to the ledger:

```bash
roster_ids=$(jq -c '[.organizations[]?.representatives[]?
                     | select(.removed_at == null) | .id]' "$ROSTER" 2>/dev/null) \
  || cannot_establish "the coverage map at $ROSTER is not readable as JSON" 3
[[ "$roster_ids" == \[* ]] || cannot_establish "the coverage map did not yield an id array" 3

# Malformedness is a COUNTED PREDICATE, never a caught exception: `fromdateiso8601` on a bad
# value puts that value in jq's error message, and that message is published verbatim.
read -r n_bad n_hits < <(jq -r --argjson epoch "$epoch_s" --argjson r "$roster_ids" '
  ([ .signedContributors[]
     | select((.created_at | type) != "string"
              or (.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") | not)) ]
   | length) as $bad
  | ([ .signedContributors[]
       | select((.created_at | type) == "string")
       | select(.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
       | select((.created_at | fromdateiso8601) >= $epoch)
       | select(($r | index(.id)) == null) ]
     | length) as $hits
  | "\($bad) \($hits)"' "$LEDGER" 2>/dev/null) \
  || cannot_establish "the ICLA signature ledger is UNUSABLE — this is NOT a finding about any account" 3
(( n_bad == 0 )) || cannot_establish "$n_bad ledger entr(ies) carry no parseable created_at" 3
```

`$r`, not `$r[0]`. The malformed count is reported as a **number**, never as the offending value —
which is what makes FR15 hold by construction rather than by suppressing a message the
implementer will be tempted to keep. Run against the real ledger, roster and epoch the hit count is
**0**, the correct answer today; it becomes >= 1 the moment a post-epoch signature exists that no
live roster row covers. `removed_at == null` is load-bearing: a *withdrawn* designation must not
mask a new signature.

**Exit contract — the probe is NOTIFY-ONLY and never takes exit 0.**

```
0   (never)    exit 0 is the sweeper's CLOSE verb, and this probe cannot establish the fact that
               would justify closing — see below
1   (never)    exit 1 is the sweeper's FAIL verb AND its reopen trigger on a closed issue
2   REPORT     the measurement was made; the line carries the count
3   CANNOT     the measurement could not be made
```

**Why exit 0 is refused, measured.** The epoch is *today*, and this repository requires
contributors to sign the ICLA, so **every future signature by anyone is post-epoch by
construction**. The first unrelated contributor to sign satisfies "a post-epoch signature no roster
row covers" — and the condition never clears, because that person is not a corporate representative
and never will be. So exit 0 would fire, the sweeper would post PASS and close, `closed_precheck`
would then refuse to re-litigate an issue carrying the sweeper's own PASS block, and a reopened
tracker would be re-closed on the next sweep. DC-2's price ("the operator reads one comment and
reopens") is not a one-time cost — it is a daily manual loop for the whole remaining wait, and it
reaches the same terminal outcome the `## User-Brand Impact` section names (the CCLA is never
recorded) by the opposite route from the one that section enumerates.

The same latch is reachable a second way: a representative withdrawn under `remove` and never
re-added is post-epoch and permanently not-live, so their id sits in the count forever. **"Covered"
is therefore narrowed to *known to the roster at all* — live OR withdrawn** — which removes that
cause; the absorbing-unrelated-signer cause is removed only by refusing the close verb.

What #7910 asks for is that *the operator is told without having to look*. A daily comment delivers
that. Auto-closing is a bonus the probe has not earned: its own PASS text already says it is not
authority to record, and the close is the irreversible verb on a legal tracker. The operator closes
it when they record the row, which is the human decision point the design already insists on.

Exit 2 vs 3 costs one integer and buys the only unexpanded signal the operator sees:
`sweep-followthroughs.sh:487` renders `TRANSIENT (exit $rc, …)` in the comment heading while the
body sits behind a `<details>` fold. Precedent for a third code:
`scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`, documented in the sweeper workflow
at `:94`.

**One `CANNOT ESTABLISH: <reason>` line, not six branches**, each ending with a fixed addressee
tag — `Operator: <exact command>` or `Operator: no action — engineering fault, file it` — so the
four states with no operator remedy read as "not mine" rather than as jargon:

| State | rc |
|---|---|
| epoch underivable, or the log is empty | 3 |
| the anchor commit has no parent, or its parent already contains the anchor | 3 |
| ledger unreachable or not `{signedContributors: [...]}` | 3 |
| a ledger entry's `created_at` is absent or unparseable | 3 |
| roster missing or unparseable | 3 |
| any network call exceeds `timeout 30` | 3 |
| count == 0 | 2 — `NOT YET: <n> signature(s) checked against epoch <e>; none is at-or-after it and uncovered.` |
| count >= 1 | **5** — `ACTION: <count> signature(s) satisfy the temporal gate and are covered by no roster row (epoch <e>; <n> entr(ies) checked).` plus the line naming the executed instrument's § 4(c) designation list as the authority for WHICH account to record. |

**The `0` in the row above was a leftover from the pre-notify-only draft and is
corrected here.** It contradicted the exit-contract block three paragraphs up,
which already refused exit 0. Resolved at /work in favour of a THIRD code rather
than folding ACTION into 2: `sweep-followthroughs.sh:487` renders
`TRANSIENT (exit $rc, …)` in the comment HEADING and folds the body behind a
`<details>`, so the exit code is the only signal the operator sees unexpanded.
One code for both measured outcomes would post a byte-identical heading every
day forever — including the day the answer changed, which is the silent
never-notice this probe exists to remove. The sweeper treats every code other
than 0 and 1 as TRANSIENT, so 5 is inert to it and legible to the operator.

Every `CANNOT ESTABLISH` is a statement about **us**, never about the counterparty. The `NOT YET`
line carries the count of signatures *checked*, so "0 uncovered" and "0 examined" cannot render
identically.

**No output stream contains a login, a name, an id, or an individual timestamp.** That is not
achieved by discipline in the probe's own `echo`s alone — third-party diagnostics are the real
leak. `date -u -d "$bad"` prints `date: invalid date '<value>'`; `jq` echoes ledger content on a
parse error. **Every external command that touches ledger content has its stderr suppressed and
replaced by a probe-authored line**, and the no-naming arm drives the **failure** paths of the
stubs, not only the success paths.

### Ordering, and why it is load-bearing

The epoch derivation runs **before** the ledger fetch. Measured: `git fetch --no-tags --depth=1`
writes `.git/shallow` into the **common dir**, flipping the whole repository — every worktree —
to shallow. Since the ledger branch is exactly one commit (`git rev-list --count
origin/cla-signatures` = 1), `--depth=1` buys nothing, so the probe fetches **without** it.

`--no-tags` is not the bound. The explicit refspec is what confines the write to
`refs/remotes/origin/cla-signatures` (so a hostile origin cannot steer it elsewhere); `--no-tags`
only stops tag refs. Three further writes into the shared common dir are unbounded by either, and
each is one flag:

```bash
timeout 30 git -c gc.auto=0 fetch --no-tags --no-recurse-submodules --no-write-fetch-head -q \
  origin '+refs/heads/cla-signatures:refs/remotes/origin/cla-signatures' 2>/dev/null \
  || cannot_establish "could not fetch the ICLA signature ledger ref" 3
```

`--no-write-fetch-head` (FETCH_HEAD is written to the common dir, the same shared surface as
`.git/shallow`), `-c gc.auto=0` (a `gc --auto` triggered by fetch runs in the operator's live
repository and outlives the `timeout`), and `--no-recurse-submodules` (the default is `on-demand`,
and `.gitmodules` on the fetched branch is content controlled by whoever writes that branch — no
`.gitmodules` exists today, so the risk is latent rather than live).

The `2>/dev/null` is load-bearing and generalises the suppression rule: git relays the server's
sideband verbatim as `remote: <arbitrary text>` on stderr, `sweep-followthroughs.sh:378` captures
`2>&1`, and `:506` republishes it into a public comment. **The rule is therefore "every external
command's stderr is suppressed and replaced by a probe-authored line", full stop — not "every
command that touches ledger content"**, which is the narrower phrasing that let the transport
layer through.

### The epoch derivation and its single control

```bash
raw=$(timeout 30 git log --first-parent -S"$NOTICE_ANCHOR" --format='%H %cI' -- "$NOTICE_DOC") || exit 3
line=$(printf '%s\n' "$raw" | sed '/^$/d' | tail -n 1)
[[ -n "$line" ]] || exit 3          # a non-matching pickaxe exits 0 with EMPTY stdout
anchor=${line%% *}; epoch=${line#* }
```

The status is checked before `tail` (`cmd | tail` discards it), `--format='%H %cI'` keeps the
SHA the control needs, and the emptiness check is the branch `|| exit 3` cannot provide.

**Control B — the anchor commit has a first parent, and that parent's copy of `NOTICE_DOC` does
not contain the anchor.** A *differential* assertion: not "did I find something" but "did the
thing I found actually introduce the anchor", which is what `-S` claims and what a graft breaks.
Measured on the live repo: parent `c774f231…`, anchor occurrences 0 there against 1 at the
anchor commit; on a depth-1 clone `git rev-parse --verify '<graft>^'` exits 1. Note `grep -c`
exits 1 when the count is 0 — which is control B's **success** case — so it must not be chained
to `|| die`.

Epochs are compared as integers (`date -u -d … +%s` on both sides) and a parse failure is a
refusal, never a default of 0. `sweep-followthroughs.sh:107-112` uses `|| echo 0`, correct there
(an unparseable `earliest` means "run now") and catastrophic here.

### Parity with the authority — a differential over synthetic fixtures

`resolveCoverageMapNoticeEpoch(repoRoot?)` takes a repo root, and
`roster-entry-gate.test.ts` already passes synthetic paths at `:336`, `:407`, `:440`, `:456` for
exactly this reason. The companion suite builds a **family** of fixtures — one-touch, two-touch,
merge-commit, rebase-replay, squash, grafted — and asserts the probe's `--print-epoch` is
byte-equal to the TS authority **per fixture**. That is hermetic, shard-independent (it does not
care that `test-webplat` checks out shallow), and non-vacuous by construction: every drift
vector (`--first-parent`, `%cI`, oldest-vs-newest, the `--` separator, `-S`→`-G`, the
fail-closed direction) reddens on at least one fixture. It is a strictly stronger discharge of
CLO B2-b than a real-repo comparison, which is worth saying to the CLO explicitly because the
first draft offered the weaker one.

`--print-epoch` is not a test seam of the kind `ccla-add.sh:110` refuses: it substitutes no
operand and changes no verdict. Any unrecognised argv exits 64, so a mistyped `--print-epock`
cannot fall through to the verdict path.

### The second monitor, and the tracker's survival

`cron-follow-through-monitor.ts` (Inngest, `0 9 * * 1-5`) polls the same
`--label follow-through --state open` set but parses a `## Verification` YAML block, not the
HTML directive. Default `sla_business_days: 5` posts a public *"manual intervention required"*
comment; Guard C closes as **`not planned`** at 30 business days — and
`sweep-followthroughs.sh:576` filters `NOT_PLANNED` out of the closed set, so the tracker would
become invisible to both systems while still waiting. The wait here (unsent reply + a
counterparty's turnaround + a third party opening a PR) is comfortably past 30 business days.

**Resolution — and the correction the first draft needed.** `sla_business_days` is read at
`cron-follow-through-monitor.ts:125` and consumed by **Guard B only** (`:163-165`). Guard C's
30 business days is a **hardcoded constant in the prompt** (`:167`, `:172`, `:205`), so setting
`sla_business_days` mitigates the 5-day public "manual intervention required" comment and does
**not** reach the close-as-`not planned` at 30. The first draft's resolution therefore did not
resolve the finding it named.

The structural fix is to take sweeper-owned trackers out of that monitor's issue set: an issue
carrying a `<!-- soleur:followthrough -->` directive already has an owner with its own cadence and
its own close semantics, and two pollers with different formats and opposite close rules on one
issue is the defect. This plan narrows `cron-follow-through-monitor`'s query to exclude issues
bearing the directive, and adds the `## Verification` block as belt-and-braces for Guard B.
**Phase 0's measurement of whether that monitor is dispatching gates enrolment** rather than
merely being recorded — "it is dark today" is not a design, and a legal tracker closed
`not planned` becomes invisible to both systems (`sweep-followthroughs.sh:576` filters
`NOT_PLANNED` out of the closed set).

### `earliest=`, and the noise it does not suppress

`earliest=` is set to the **filing date**, per `followthrough-convention.md:81-86`. The first
draft set it far in the future to suppress daily comments; that trades away the notification
channel across exactly the window in which the operator must act, and the convention forbids it
in terms. With the count-form output the daily comment carries no personal data, so the residual
cost is noise — and the noise is a substrate defect (one existing tracker carries 33 identical
sweeper comments), not this probe's to fix locally. Filed as its own tracker along with the
sweeper's missing per-probe `timeout` and its hard `--limit 50` against 51 open trackers.

### Enrolment sequencing

`.claude/hooks/follow-through-directive-gate.sh:81-90` fires only on `gh issue create` **with**
`--label follow-through`; `gh issue edit --add-label` is ungated. `sweep-followthroughs.sh:307-312`
resolves the script against the **default branch**, so a label applied pre-merge yields a daily
"script missing" stderr line nobody reads. #7910 cannot be the tracker — this PR closes it,
because building the watch is its deliverable.

1. `gh issue create` the tracker **unlabeled** (`type/chore`, `domain/legal`,
   `priority/p2-medium`), body carrying the `## Verification` block. **The tracker names no
   counterparty and no person, and does not reference #7846** — it describes only the mechanism
   ("watch for an ICLA signature at or after the coverage-map notice epoch that no live roster row
   covers"). This is what closes the derivable-association class: the probe's daily comment flips
   from `NOT YET` to `PASS` on a dated, permanent, world-readable comment, and the ledger it
   measured is itself public and git-versioned — so a reader who knows *which organisation the
   tracker is about* can diff `signatures/cla.json` at that date and recover the name, id and PR
   number of the account that flipped the count. An opaque tracker makes that join yield nothing,
   and it is also what stops a PASS fired by an **unrelated** post-epoch signer from publicly and
   permanently correlating an arbitrary contributor with a counterparty they have no relationship
   to. If the PR is abandoned, close the tracker in the same session.
2. Land `scripts/followthroughs/ccla-representative-icla-7922.sh` and its companion suite,
   **both** committed `100755`, and substitute the resolved `7922` back into this plan in
   the same commit so the shipped file is greppable from the plans corpus.
3. Post-merge, via a committed `scripts/bootstrap-ccla-watch-7922.sh`
   (`hr-multi-step-post-merge-bootstrap-script` — four scriptable steps): read-modify-append the
   body (never a bare `--body-file` over a body you did not first fetch), `--add-label
   follow-through`, dispatch `-f dry_run=true`, and assert the log line. With `earliest=` at the
   filing date the assertion is the `running` line; the far-future case that would have made it
   unreachable is gone.

### Filename

`ccla-representative-icla-7922.sh`, not `ccla-convergence-…`. #7910's `<counterparty>` is a
placeholder, and the counterparty's status under the sole-trader rule is unknown until the
instrument arrives — a legal name that is a natural person's name would make the filename an
identity field in a tracked file (CLO re-evaluation trigger 4). The neutral name forecloses it.

## Implementation Phases

**Phase 0 — preconditions, no edits.** Re-run every Premise Validation row. Re-measure the
depth-1 epoch hazard and paste it into the PR body. Re-run the probe's `jq` predicate against
live data. Record the measured floors (`Total:` from `ccla-add.test.sh`; `checked` from
`followthrough-exec-bit.test.sh`) — **do not guess either**. Determine whether
`cron-follow-through-monitor` is dispatching. **And measure whether the existing temporal arm at
`ccla-add.test.sh:234-248` is already vacuous in CI** — `test-webplat` checks out shallow, so the
epoch there may be HEAD's own date, which would make every ledger entry pre-epoch and that
assertion pass for the wrong reason. If so, say so; it is a pre-existing defect in a file this
PR edits.

**Phase 1 — RED for `--instrument-file`.** Synthesized fixtures under `$WORK`
(`cq-test-fixtures-synthesized-only`), then the agreement arm in its **non-vacuous** form:

```bash
digest=$(sha256sum < "$WORK/instrument.bin" | awk '{print $1}')
rc_file=$(run_sut … --instrument-file "$WORK/instrument.bin"); cp "$WORK/out.txt" "$WORK/a.json"
rc_sha=$(run_sut … --instrument-sha256 "$digest");            cp "$WORK/out.txt" "$WORK/b.json"
# BOTH must have SUCCEEDED first: two identical FAILURES emit two empty files and `cmp` passes.
[[ "$rc_file" == 0 && "$rc_sha" == 0 ]] || fail …
jq -e . "$WORK/a.json" >/dev/null || fail …
cmp -s "$WORK/a.json" "$WORK/b.json" || fail …
```

(`--instrument-sha256 $(sha256sum X)` — the form #7909 sketches — expands to three argv words and
exits 64; written that way the arm asserts nothing.) Then the value arm, the
stderr-transcripts-differ arm, the refusal arms (both / neither / relative / missing / directory
/ empty / unreadable / inside-repo), the caller's-file-survives arm, the source-level
path-never-published arm, and the organisation-named-fixture arm.

**Phase 2 — GREEN.** Implement as above, including the `INSTRUMENT_FILE=""` initialiser, the
absolute-path requirement, `realpath -e` on both operands, the stdin `sha256sum`, the stderr
echo, and the `usage()` and header updates.

**Phase 3 — Guard 1 mutations + floor.** Each mutation arm asserts the mutation **landed** before
asserting its effect. Set `MIN_ASSERTIONS` to the measured total, keeping the floor's syntactic
shape so `guard-vacuity-floor.test.sh` can slice it.

**Phase 4 — the probe.** Create the tracker; write the probe (header carrying the full exit
contract, why exit 1 is never used, why the epoch derivation must precede the ledger fetch, and
why the fetch omits `--depth=1`); run the credential lint and add the xtrace block only if it
asks; `chmod +x` **both** files; write the companion suite (synthetic fixture family, `git -c`
flags only, `env -i`, three counters, Guard 2's rows, the per-fixture parity arm that FAILs
rather than skips without `tsx`, floor + conservation); `git add` **before** running the orphan
lint; register in `want_webplat` with the `tsx` rationale, plus a one-line note at
`test-all.sh:1884` that one companion lives in that shard and why, and a back-pointer comment in
`roster-entry-gate.ts` naming the probe; raise `MIN_PROBES` to the measured count **and add a
sentence to its comment naming the lowering procedure**, because retiring a probe when its
tracker closes is the normal end of life and the comment currently forbids it.

**Phase 5 — sweeper, register, docs.**
`.github/workflows/scheduled-followthrough-sweeper.yml`: `fetch-depth: 0` with a comment naming
the probe and the measured reason, and `timeout-minutes: 15`. No `env:` change.
**P11:** extend `scripts/lint-legal-registers.sh`'s `REGISTER_FILES` to include
`ccla-register.md` and add a roster↔register `Instrument hash` parity assertion, so the two
values cannot silently diverge once one is computed and the other is typed.
`cla-signature-evidence-retrieval.md`: §10.1 step 2 rewritten to pass `--instrument-file` with an
absolute path on the encrypted drive (and its `sha256sum <file>` argv form corrected to the stdin
form), §10.2's example switched, §10.4's table extended, and a short §10.6 covering the watch —
its exit classes, that a PASS is not authority to record, and `--print-epoch` as the one command
distinguishing "waiting" from "broken".

**Phase 6 — enrolment**, via the committed bootstrap script.

## Domain Review

**Domains relevant:** legal, engineering. **Product/UX:** an independent mechanical scan of the
Files lists matches no UI-surface glob or term — two shell scripts, two suites, one workflow,
two knowledge-base files. Tier **NONE**.

### Legal (CLO)

**Status:** reviewed. Five findings; both blockers resolved, one by a redesign the review's own
reasoning implies.

- **P1 (resolved).** The exposure is **ordering**, not the timestamp: a daily public comment
  naming a designated account publishes the employer↔account association before that person has
  signed and before they have been told anything — the disproportion `gdpr-policy.md` §3.4 limb
  (2) calls "decisively for proportionality", from which limb (3) derives the Art. 13 (not
  Art. 14) route. In the interval the population is Art. 14 with a one-month outer limit and no
  address to serve it. **Resolution: the probe holds no account at all.** No PA-7 §(d) and no
  §3.4 amendment is required.
- **P2 (resolved).** Absolute path required, inside-repo refused with a custody message,
  resolved path + size + hash echoed to stderr. The flag turns the runbook's named hazard — a
  mail-client re-export rather than the bytes as received — into a one-word mistake, so the
  runbook sentence moves in the same PR.
- **P3 (adopted).** Runbook §10.1/§10.2/§10.4 and a new §10.6.
- **P4 (diverged, recorded).** See `## Decision Challenges`.
- **P5 (adopted).** The PASS output names the §4(c) list as the authority.
- **Carve-outs not cleared by this PR.** The counsel review's *"NOT ATTESTED — the outbound
  correspondence leg to Pakistan"* is open at #7846 and must be discharged in
  `privacy-policy.md` §§4.5/10, `gdpr-policy.md` §§3.4/6 and
  `data-protection-disclosure.md` §§2.3(d)/6.4 **before the reply is sent**; a probe watching for
  the consequence of sending is not authority to send. And the review's first re-evaluation
  trigger — the first arms-length corporate representative written to the roster — ends the
  tenant-zero v1 internal-attestation posture. Neither change writes a row, but the write this
  probe unblocks is that event.

### Engineering (CTO + the five-agent eng panel)

**Status:** reviewed. Findings are folded in above and enumerated in §"What plan review changed".
The `--instrument-file` half was found proportionate with no ship-blocking defects; every P0 and
P1 lands in the probe half, and five of them were measurements rather than opinions. No ADR is
warranted; no capability gaps.

## Decision Challenges

Persisted to `knowledge-base/project/specs/<branch>/decision-challenges.md`; `ship` Phase 6
renders them into the PR body and files the `action-required` issue.

- **DC-1 — CLO P4: call the TypeScript authority, or re-derive in bash?** The sweeper has no
  `tsx`, so the literal instruction makes the probe permanently inert. Discharged instead by a
  merge-blocking differential over a family of synthetic fixtures. The first draft offered a
  real-repo comparison, which measurement showed to be vacuous for four of six drift vectors and
  unrunnable on its own shard; the fixture family is the stronger form.
- **DC-2 — the login-free redesign.** P9 is the CLO's own property and the count form satisfies
  it by construction. Honest cost: an unrelated post-epoch signer would PASS and auto-close the
  tracker; the operator reads one comment and reopens, and no roster row is written by the probe.
- **DC-3 — one PR or two.** The eng panel recommends splitting; the operator asked for both
  together with both issues closed. Operator direction is the default and is not overridden; the
  parts share no file, so the split stays available.

## User-Brand Impact

- **If this lands broken:** a permanent, world-readable roster row carrying a wrong
  `executed_instrument_sha256` for a named third-party account — the integrity anchor for an
  off-repo document that nothing in the repository can contradict and that cannot be erased from
  any clone or fork.
- **If this lands broken (second artifact):** a tracker that never closes and a Corporate CLA
  never recorded, because a silently-wrong epoch made every signature read as pre-epoch —
  measured as the actual behaviour of a shallow checkout, with a plausible daily message.
- **If this leaks:** the probe's output is posted verbatim into a public, permanent issue
  comment. The exposure would be an association between a named account and a corporate
  designation published before that account has signed. The probe therefore reads no name,
  resolves no account, and suppresses the stderr of every command that touches ledger content.
- **If this leaks (third vector):** the instrument's filename, which plausibly carries a legal
  name, reaching a commit message or a public PR body. Confined to stderr, asserted at source
  level.
- **Brand-survival threshold:** `single-user incident`. `user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "scheduled-followthrough-sweeper run, which logs `issue #7922: running <script>` and `exit=<rc>` and posts the probe's output as a tracker comment"
  cadence: "daily at 18:00 UTC (cron '0 18 * * *'); earliest= is the filing date, so the channel is live from day one"
  alert_target: "the tracker issue comment thread"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml"

error_reporting:
  destination: "the per-issue comment body; plus GitHub Actions run logs"
  fail_loud: "the exit code appears unexpanded in the comment heading while the body sits behind a details fold. NOTE, measured: sweep-followthroughs.sh `fail()` is `printf >&2` with NO `::error::`, so 'script missing', 'not executable' and 'required secret not set' leave the workflow run GREEN with only a stderr line. Those three modes are therefore detected at merge time by the gates below, not at run time by the sweeper."

failure_modes:
  - mode: "sweeper or CI checkout is shallow, so the epoch derivation returns the graft commit's date"
    detection: "control B (parent exists and lacks the anchor) exits 3; and the per-fixture parity arm covers the class at merge time"
    alert_route: "tracker comment (daily), exit 3 in the heading; merge-blocking CI"
  - mode: "the anchor was never found — a non-matching pickaxe exits 0 with empty stdout"
    detection: "the explicit emptiness check on the derived line; exit 3"
    alert_route: "tracker comment"
  - mode: "the bash derivation drifts from resolveCoverageMapNoticeEpoch"
    detection: "byte-equality against the TS authority per synthetic fixture (one-touch, two-touch, merge, rebase-replay, squash, grafted)"
    alert_route: "merge-blocking CI (webplat shard)"
  - mode: "origin/cla-signatures unreachable, or the ledger is an HTML error page"
    detection: "the jq shape assertion; exit 3 saying the reference set is UNUSABLE and that this is NOT a finding about any account"
    alert_route: "tracker comment"
  - mode: "a ledger entry carries no parseable created_at"
    detection: "date -u -d parse failure is a refusal, never a default of 0; exit 3, with date's own stderr suppressed so the value is not published"
    alert_route: "tracker comment"
  - mode: "a network call hangs, taking the rest of the sweep with it"
    detection: "every network call is wrapped in `timeout 30`; a timeout is exit 3"
    alert_route: "tracker comment"
  - mode: "probe or companion suite committed without the executable bit, so the sweeper never runs the probe"
    detection: "scripts/followthrough-exec-bit.test.sh asserts the git INDEX mode of every scripts/followthroughs/*.sh"
    alert_route: "merge-blocking CI"
  - mode: "the probe emits a name, id or individual timestamp into a public comment"
    detection: "a companion-suite arm drives the FAILURE paths of the date/jq stubs and asserts no fixture name, id or timestamp appears in either stream"
    alert_route: "merge-blocking CI"
  - mode: "the register's Instrument hash and the roster's executed_instrument_sha256 diverge"
    detection: "scripts/lint-legal-registers.sh extended to cover ccla-register.md with a roster parity assertion"
    alert_route: "merge-blocking CI"
  - mode: "a wrong --instrument-file hash is written to the roster"
    detection: "the agreement arm (both exit 0, both parseable, byte-identical) and the value arm"
    alert_route: "merge-blocking CI (webplat shard)"

logs:
  where: "GitHub Actions run logs for scheduled-followthrough-sweeper.yml; the tracker issue comment thread"
  retention: "Actions logs 90 days (repo default); issue comments indefinitely"

discoverability_test:
  command: "bash scripts/ccla-icla-watch-discoverability.sh"
  expected_output: "EPOCH-OK 2026-09-07T15:16:45Z"
  # NO `credentials_required`. The earlier draft carried one, and that is how a plan
  # claiming the probe `exits 0` for a command that exits 2 reached review with the gate
  # green: the declaration makes Check 10 SKIP WITHOUT EXECUTING, so the error was caught
  # by a person rather than by the gate that exists to catch it. Nothing here needs a
  # credential -- `--print-epoch` derives the epoch from local git history and returns
  # before any fetch -- so there was nothing to waive.
  #
  # Check 10 reaches PASS only on rc == 0, and the probe NEVER exits 0 on any path (0 is
  # the sweeper close verb). `scripts/ccla-icla-watch-discoverability.sh`, committed in
  # this PR, inverts that once and ASSERTS the invariant rather than waiving it: the probe
  # must exit 2 AND print one ISO-8601 UTC epoch. Both halves matter -- a probe that
  # REFUSED would also "not exit 0", so a bare rc check would pass on a derivation that
  # could not run at all. Measured in this checkout: `EPOCH-OK 2026-09-07T15:16:45Z`, rc 0.
```

## Encryption Posture

Skipped per Phase 2.11: no persistent data store and no new cross-component or network
connection. `ccla-add.sh` writes only to the existing git-tracked roster and to `mktemp` files it
already creates; the probe reads an existing git ref and two files in the checkout. No `.tf`, no
`supabase/migrations/*.sql`, no `cloud-init*.yaml`, no `docker-compose*.yaml`. The redesign
removed the one new secret the first draft introduced.

## Architecture Decision (ADR/C4)

**No ADR.** Neither change makes or reverses an architectural decision; ADR-201 remains accurate
after both land. Both the CTO and the architecture reviewer reached this independently.

**No C4 impact — enumerated against all three model files**
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the
counterparty and its representative are actors ADR-201's roster already models and neither change
adds or removes one; no external system or vendor is added (the probe speaks only to GitHub,
already modelled); no container or data store is added; no actor↔surface access relationship
moves. **Derived cardinalities** are not reached by that rubric, so the claim is backed by a green
`plugins/soleur/test/c4-count-parity.test.sh` at /work — no cron monitor, heartbeat slug or
workflow is added.

## Guard Contract

### Guard 1 — the instrument hash is computed, not transcribed

**Property.** When `--instrument-file X` is given, the emitted roster's
`executed_instrument_sha256` equals the SHA-256 of X's bytes, and that roster is byte-identical
to the one emitted by passing the same digest as `--instrument-sha256`, both invocations having
succeeded.

**Assembly.** Every path that can set `INSTRUMENT_SHA` before it reaches
`jq --arg isha "$INSTRUMENT_SHA"` in `ORG_JSON` (`ccla-add.sh:312-323`) — the **chokepoint**, and
it is single: the `--instrument-sha256` parse arm (`:143`) and the new compute block, both
required to pass the shared `^[0-9a-f]{64}$` assertion at `:170`. *One variable, one validation,
one embedding site.* The suite asserts against the chokepoint's **output**, never either arm's
internals, so a future third arm is covered without editing the assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the computed digest with a constant | RED — the agreement and value arms both fail |
| 2 | Delete the `-s` non-empty check | RED — the empty-file arm no longer returns 64 |
| 3 | Collapse the `-e` / `-f` split back to `-f` alone | RED — the directory arm gets "no such instrument file", which the arm asserts against |
| 4 | **Guard's own dispatch:** make the compute block unreachable (`if false`) | RED — `--instrument-file` alone leaves `INSTRUMENT_SHA` empty and the happy-path arm fails |
| 5 | Accept a relative path (drop the `/*` check) | RED — the relative-path arm no longer returns 64 |
| 6 | Compare the resolved path to `$REPO_ROOT` without `realpath` | RED — the symlink-into-repo arm passes custody when it must be refused |
| 7 | Interpolate the resolved path into the `gh pr create --body` string | RED — the **source-level** span assertion fails (the runtime path is unreachable under the suite's unconditional dry-run, so this is asserted by grepping the two spans, not by executing them) |
| 8 | **Added at /work.** `sha256sum "$RESOLVED"` instead of `sha256sum < "$RESOLVED"` | RED on the backslash-basename fixture — GNU sha256sum prefixes its line with `\`, the awk fields shift, and the result is not 64 hex. Paired with a must-PASS on an ordinary basename, so the row isolates the hazard rather than reddening for any reason. No listed row covered the argv/stdin hazard the design devotes a paragraph to. |
| 9 | **Added at /work.** Delete the mutual-exclusion block | RED — both flags together are silently accepted and one wins. P4/FR2 had no row. |

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Delete any **one** assertion without lowering `MIN_ASSERTIONS` | RED — the floor fires with `ANTI-VACUITY`. Corrected at /work: the floor is set to the measured total with ZERO slack, so it fires on one, not two. |
| H2 | Drop the `rc == 0` precondition from the agreement arm, then apply mutation 1 in a form making both arms exit 64 | RED — the arm must not compare two empty outputs; this is the vacuity it exists to avoid |
| H3 | **must-PASS, non-canonical:** a second fixture with different bytes and length | PASS |
| H4 | **must-PASS, non-canonical:** a fixture whose basename is a synthesized organisation name | PASS, and that string appears in neither the roster nor stdout |

### Guard 2 — the watch closes only on a corroborated post-epoch, uncovered signature, and names no one

**Property.** The probe exits 0 only when at least one ledger entry has a parseable
`created_at >= E` and an id no **live** roster representative carries, where `E` is derived at
run time from git history corroborated as parent-bearing and anchor-introducing — and no output
stream on any branch, including the failure paths of its subprocesses, contains a name, id or
individual timestamp.

**Assembly.** Three operands feed one count: (a) `E`, from the derivation plus its emptiness
check and control B; (b) the ledger, from the `--no-tags` fetch and the shape assertion; (c) the
live roster id set. The **chokepoint** is the single `jq` predicate and the single
`(( count >= 1 ))` branch reading it — every `CANNOT ESTABLISH` arm returns before reaching it,
and a second verdict site would be the defect. The no-naming property quantifies over a different
assembly — **every subprocess's stderr**, not only the probe's own `echo`s — which the suite
covers by asserting absence in the union of streams while driving the stubs' failure paths.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Hardcode `E` to a far-past constant | RED — the all-pre-epoch fixture exits 0 when it must exit 2 |
| 2 | Drop `--first-parent` | RED on the **merge-commit** fixture (it would NOT redden against the live single-match repo — measured) |
| 3 | Replace `%cI` with `%aI` | RED on the **rebase-replay** fixture |
| 4 | Take the newest match instead of the oldest | RED on the **two-touch** fixture |
| 5 | Drop `--format='%H %cI'` back to `%cI` | **RESTATED at /work — the original expectation was backwards.** Without `%H` both `${line%% *}` and `${line#* }` return the WHOLE string, so the SHA assertion fails and the probe refuses on EVERY fixture, including the healthy one where the baseline reports a verdict. Asserted as: rc=3 on the one-touch fixture, with the SHA-shape reason, where the baseline is rc=2. Still discriminating, just not via the graft. |
| 6 | Remove the emptiness check on the derived line | RED — the reworded-anchor fixture yields an empty epoch and exits 0 or 2 instead of 3 |
| 7 | Delete control B | RED — the grafted fixture derives a false epoch instead of exiting 3 |
| 8 | **Guard's own dispatch:** `exit 0` before any operand is read | RED — the unusable-ledger arm and the count==0 arm both fail |
| 9 | Drop the roster term from the `jq` predicate | RED — the fixture whose only post-epoch signer is already a live representative exits 0 when it must exit 2 |
| 10 | **INVERTED at /work.** Add `select(.removed_at == null)`, i.e. treat a withdrawn row as NOT covering | RED — the withdrawn fixture reports ACTION where the baseline reports NOT YET. The original row predated the decision to narrow "covered" to live-OR-withdrawn: a live-only term leaves a withdrawn representative's id uncovered forever, so the count latches at >= 1 and the probe's only signal is destroyed. |
| 11 | Default an unparseable `created_at` to 0 instead of refusing | RED — the malformed-timestamp fixture exits 0 or 2 when it must exit 3 |
| 12 | **RESTATED at /work.** Remove the `wellformed` guard AND the evaluation's `2>/dev/null` | RED — the malformed value appears in the captured stream. Measured: jq's PARSE error carries only a line and column and echoes nothing, so the original row could not fire; it is jq's RUNTIME error (`fromdateiso8601`) that prints the offending value. Both the counted predicate and the suppression are mutated, because either alone leaves the other holding. |
| 13 | Move the ledger fetch **before** the epoch derivation | **CONVERTED at /work to a SOURCE-ORDER assertion, with a known-positive control.** Once `--depth=1` is gone the fetch no longer flips the fixture to shallow, so an execution-order mutation has no observable left and the behavioural row could not fire. Stating it as source order is honest; keeping the behavioural row would have been a row that cannot redden. |
| 14 | Drop `--no-tags` from the ledger fetch | RED — the tag-carrying-origin fixture shows tags created in the sandbox |

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Zero the suite's counters without lowering its floor | RED — `guard-vacuity-floor.test.sh` requires the floor to FIRE |
| H2 | Run the parity arm against the **live** repo instead of the fixture family | RED-detecting-capability lost — rows 2, 3 and 4 go green; the suite asserts each fixture's shape (match count, merge presence) before using it |
| H3 | Make the parity arm skip instead of fail when `tsx` is absent | RED — a missing dependency must fail loud, per `ccla-add.test.sh:74-79` |
| H4 | **must-PASS, non-canonical:** `created_at` equal to the epoch exactly | PASS with exit 0 — pins `>=`, not `>` |
| H5 | **must-PASS, non-canonical:** a fixture with a different anchor phrase and the probe's constant changed to match | PASS — the derivation is not pinned to one literal's presence in the live repo |

## Acceptance Criteria

### Functional Requirements

- **FR1** `--instrument-file <abs path>` records the SHA-256 of that file's bytes.
- **FR2** Both flags → 64, naming both. **FR3** Neither flag → 64, naming both.
- **FR4** A relative path → 64, saying an absolute path is required.
- **FR5** A non-existent path, a directory, an empty file and an unreadable file each → 64, with
  four **distinct** messages.
- **FR6** A path resolving (through symlinks) inside `$REPO_ROOT` → 2, naming custody.
- **FR7** Diagnostics echo the resolved path, byte size and computed hash to **stderr**.
- **FR8** `grep -c` over the `git commit --file` heredoc span and the `gh pr create --body` span
  for `INSTRUMENT_FILE|RESOLVED` returns 0, and the path is absent from the roster and stdout.
- **FR9** Every pre-existing arm in `ccla-add.test.sh` passes without edit to its expectations.
- **FR10** `usage()` documents `--instrument-file`, the mutual exclusion and the absolute-path
  requirement.
- **FR11** Both new files are committed mode `100755`, and
  `grep -cE '^\s*exit 1\b' <probe>` returns 0.
- **FR12** `--print-epoch` byte-equals `resolveCoverageMapNoticeEpoch(<fixture>)` on **every**
  fixture in the family, and the family contains at least one two-touch, one merge-commit and one
  rebase-replay repo.
- **FR13** The PASS output names the §4(c) designation list as the authority.
- **FR14** Exit 3 covers every could-not-measure state with a single `CANNOT ESTABLISH: <reason>`
  shape ending in an addressee tag; exit 2 is measured-not-yet and carries the checked count.
- **FR15** No output stream contains a ledger `name`, `id` or `created_at` — asserted while
  driving the subprocesses' failure paths.
- **FR16** The probe fetches with `--no-tags` and **without** `--depth=1`, after the epoch
  derivation; a tag-carrying-origin fixture shows zero tags created.
- **FR17** Any unrecognised argv exits 64.
- **FR18** `scheduled-followthrough-sweeper.yml` has `fetch-depth: 0` and `timeout-minutes: 15`.
- **FR19** `scripts/test-all.sh` registers the companion suite inside `want_webplat` — verified
  with `awk '/^if want_webplat; then/,/^fi$/' scripts/test-all.sh | grep -c ccla-representative`
  ≥ 1, **not** a whole-file grep, which answers "registered somewhere".
- **FR20** `scripts/lint-legal-registers.sh` covers `ccla-register.md` and asserts
  register↔roster `Instrument hash` parity.
- **FR21** *(post-merge, verified by the bootstrap script, not by the PR gate)* the tracker
  carries the directive with `earliest=` at the filing date, a `## Verification` block with a
  stated `sla_business_days`, the `follow-through` label, and names no person.

### Non-Functional Requirements

- **NFR1** The companion suite makes no network call; fixtures are synthetic and local; the probe
  runs under `env -i`.
- **NFR2** The probe declares no `secrets=` and holds no credential **in its environment**. Its
  `git fetch` uses whatever credential `actions/checkout` persisted into `.git/config`
  (`http.<host>.extraheader`), which `env -i` does not remove — so "binds no credential" would
  be an overstatement, and Phase 5 decides `persist-credentials` deliberately rather than
  inheriting it.
- **NFR3** The resolved `--instrument-file` path is never added to `TMP_FILES` — satisfied
  structurally by the ordering (`TMP_FILES=()` at `:191` follows the compute block) and asserted
  statically.
- **NFR4** No `${VAR:?}` / `${VAR?}` on an executable line of the probe.
- **NFR5** Synthetic git fixtures use `git -c` flags only; the suite performs no `git config`
  write.
- **NFR6** Every network call in the probe is bounded by `timeout 30`.

### Quality Gates

- **QG1** `bash apps/cla-evidence/test/ccla-add.test.sh` exits 0 with `0 failed`, and
  `MIN_ASSERTIONS` equals the measured total. *(The suite's floor is `-lt`, so this is a
  plan-time statement about the ratchet, not a stricter runtime condition.)*
- **QG2** `bash scripts/followthroughs/ccla-representative-icla-7922.test.sh` exits 0 with
  its floor and `passes + fails == cases`.
- **QG3** `bash scripts/lint-orphan-test-suites.sh` exits 0 — **run after `git add`**.
- **QG4** `bash scripts/followthrough-exec-bit.test.sh` exits 0 with `MIN_PROBES` at the measured
  count.
- **QG5** `bash scripts/lint-followthrough-varq-ban.sh` exits 0.
- **QG6** `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
  exits 0 with no new baseline entry.
- **QG7** `bash scripts/guard-vacuity-floor.test.sh` exits 0 with both floors `FIRES`.
- **QG8** `python3 scripts/lint-guard-contract.py` exits 0 against this plan.
- **QG9** `bash scripts/test-all.sh` full battery green at the `/ship` Phase 4 checkpoint.
- **QG10** After a local probe run against a synthetic sandbox,
  `[[ ! -e "$(git rev-parse --git-common-dir)/shallow" ]]` holds in the sandbox and its
  `git show-ref --tags` is empty.
- **QG11** `plugins/soleur/test/c4-count-parity.test.sh` green; `actionlint` clean on the
  modified workflow.

## Test Scenarios

**`--instrument-file`:** agreement (both exit 0, both parseable, `cmp` identical); value equals
`sha256sum <` of the fixture; stderr transcripts differ; both flags → 64; neither → 64; relative
→ 64; missing → 64; directory → 64 with its own message; empty → 64; unreadable → 64; symlink to
a valid file outside the repo → 0; symlink whose target is inside the repo → 2; caller's file
survives; source-level span grep returns 0; organisation-named fixture leaks nothing; a second
fixture also agrees.

**The probe:** all-pre-epoch (the live shape) → 2 with the checked count; one uncovered
post-epoch signature → 0; one post-epoch signature already a live representative → 2; covered
only by a **withdrawn** row → 0; `created_at` exactly at the epoch → 0; unparseable ledger → 3
with `UNUSABLE` and no phrase blaming an account; entry with absent/unparseable `created_at` → 3
**with the value absent from both streams**; malformed roster → 3; grafted fixture → 3; empty
pickaxe result → 3; `--print-epoch` parity per fixture (and the arm FAILs without `tsx`); each
fixture's shape asserted before use; unrecognised argv → 64; tag-carrying origin leaves zero
tags; ledger fetch after the derivation leaves the fixture's `.git/shallow` absent.

**Regression.** Every existing arm in `ccla-add.test.sh` passes unchanged; the shared `add_args`
at `:105-107` is not mutated, so new arms build their own argv.

**Integration (for `/soleur:qa`).** `CCLA_ADD_DRY_RUN=1 … --instrument-file <synthetic>` end to
end against the real validator → 0 and a schema-valid roster. `--print-epoch` on a
history-complete checkout → `2026-09-07T15:16:45Z`. Post-merge, the bootstrap script's dispatch
log names the probe.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| An unrelated contributor signs post-epoch and the tracker auto-closes early | Accepted, named in DC-2. The operator reads one comment and reopens; the probe writes no roster row, and the PASS text says it is not authority to record. |
| The second monitor closes the tracker as `not planned` at 30 business days | The tracker carries a `## Verification` block with a stated `sla_business_days`; Phase 0 measures whether that monitor is dispatching and records the answer either way. |
| `fetch-depth: 0` slows the daily sweeper | Measured +20-60 s against a worst recent run of 3 m 51 s; `timeout-minutes` 10 → 15 in the same edit. No existing probe reads git history (grepped: the only git usage across all 78 files is `rev-parse --show-toplevel`), so nothing else changes behaviourally. `filter: blob:none` is the priced fallback. |
| The parity arm silently degrades to the vacuous case | Each fixture's shape is asserted before use, and H2 makes running against the live repo a RED-detecting-capability loss. |
| The probe's ledger fetch mutates repository-wide state | `--depth=1` dropped (the branch is one commit), the fetch runs after the derivation, and QG10 asserts `.git/shallow` absence in the sandbox. The `repo-write-boundary` blind spot is filed separately. |
| Floors raised by guesswork | Phase 0 records measured counts; the plan states no target number. |
| The existing temporal arm may already be vacuous in CI | Phase 0 measures it. If confirmed it is a pre-existing defect in a file this PR edits, and is fixed here rather than inherited. |
| Daily comments accumulate; the sweeper caps at `--limit 50` against 51 open trackers; no per-probe `timeout` | All three are substrate defects this PR does not cause. Filed as their own trackers; the probe bounds its own calls with `timeout 30`. |
| The probe is read as authorising the CCLA reply to be sent | Stated in the Domain Review and the probe header. |

## Files to Edit / Create

**Edit:** `apps/cla-evidence/scripts/ccla-add.sh`; `apps/cla-evidence/test/ccla-add.test.sh`;
`scripts/test-all.sh`; `scripts/followthrough-exec-bit.test.sh`;
`scripts/lint-legal-registers.sh`; `.github/workflows/scheduled-followthrough-sweeper.yml`;
`apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts` (back-pointer comment only);
`knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`.

**Create:** `scripts/followthroughs/ccla-representative-icla-7922.sh` (100755);
`scripts/followthroughs/ccla-representative-icla-7922.test.sh` (100755);
`scripts/bootstrap-ccla-watch-7922.sh`.

## Future Considerations

- Under the count form a second counterparty needs **no** new probe — only a second tracker
  referencing the same script. A direct benefit of cutting the login.
- `gh issue edit --add-label follow-through` is ungated while `gh issue create --label
  follow-through` is gated — a real gap in the enrolment guard, out of scope here.
- Sweeper comment de-duplication, a per-probe `timeout`, the hard `--limit 50`, and adding
  `.git/shallow` to `repo-write-boundary`'s sampled dimensions: four substrate improvements this
  PR surfaces and does not attempt.

## References & Research

`apps/cla-evidence/scripts/ccla-add.sh` (`:56-77`, `:97`, `:110`, `:129-136`, `:143`, `:159`,
`:163-164`, `:170-174`, `:191`, `:196-201`, `:212-220`, `:222-229`, `:249`, `:265-270`,
`:286-291`, `:292-303`, `:312-323`, `:399-408`, `:421-427`);
`apps/cla-evidence/test/ccla-add.test.sh` (`:19-22`, `:53-63`, `:74-79`, `:96-107`, `:137-148`,
`:219-232`, `:234-248`, `:290-345`, `:347-393`, `:398-408`);
`apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts` (`:41-42`, `:44-68`, `:69`,
`:84-101`, `:102`, `:115-122`, `:219-222`);
`apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` (`:288-295` the 1-of-1
quantification, `:336`/`:407`/`:440`/`:456` the synthetic-root pattern);
`scripts/sweep-followthroughs.sh` (`:107-112`, `:307-312`, `:338-342`, `:359`, `:367-371`,
`:378`, `:483-506`, `:576`); `.github/workflows/scheduled-followthrough-sweeper.yml` (`:50-52`,
`:94`); `.github/workflows/ci.yml` (`:743-749`); `.github/workflows/cla-evidence.yml:70`;
`apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`;
`scripts/lib/repo-write-boundary.sh` (`:200-213`, `:216-260`);
`scripts/lint-orphan-test-suites.sh`, `scripts/followthrough-exec-bit.test.sh`,
`scripts/lint-followthrough-varq-ban.sh`, `scripts/lint-shell-trace-credential-refusal.py`,
`scripts/guard-vacuity-floor.test.sh`, `scripts/lint-guard-contract.py`,
`scripts/lint-legal-registers.sh`;
`scripts/followthroughs/cla-evidence-hardening-3950.sh`,
`scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`;
`knowledge-base/engineering/architecture/decisions/ADR-201-corporate-cla-is-a-repo-tracked-roster-not-an-allowlist-entry.md`;
`knowledge-base/legal/ccla-register.md`;
`knowledge-base/legal/audits/2026-09-counsel-review-3210.md`;
`knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`;
`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`,
`knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`;
learnings `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`,
`2026-09-04-every-verification-i-wrote-passed-and-three-of-them-proved-nothing.md`,
`2026-09-04-an-agent-will-confidently-restate-the-position-your-corpus-already-corrected.md`,
`workflow-patterns/2026-09-04-a-deferrals-clock-based-trigger-fires-silently-date-check-every-criterion.md`.

**Related work:** #7909, #7910 (closed by this PR); #7846 (stays open); #3210 and PR #7828;
and #7797 and #7220.

## Deepen-Plan Findings (2026-09-07, seven verification passes)

Seven passes ran after plan review: a mechanical verify-the-negative sweep, `security-sentinel`,
`test-design-reviewer`, `observability-coverage-reviewer`, `git-history-analyzer`,
`user-impact-reviewer` and `data-integrity-guardian`. The design changes above were made in
response; what follows is the complete finding set with its disposition, because several findings
are larger than this PR and must not be lost by being folded silently into prose.

**Applied above** (design changed): the critical process-substitution fail-open; the notify-only
exit contract; "covered" narrowed to live-or-withdrawn; the tracker naming no counterparty; the
`--` fixture and the struck `-S`→`-G` vector; the grafted fixture moved out of the parity subset;
the fetch flag set and the "every external command's stderr" rule; the NFR2 credential wording;
the second monitor's Guard C correction; the `discoverability_test` pinned so it can fail; four
new `failure_modes`; the layer citation; the drifting tag figure.

### Still to apply at `/work` — carried here verbatim so nothing is lost

| Sev | Finding | Source |
|---|---|---|
| BLOCKER | **No correction path exists for a wrong `executed_instrument_sha256`** (or `signed_at`, `authorized_from`). `remove` only stamps `removed_at`; `add` refuses a duplicate `record_ref`; there is no `amend`. The two available repairs are a hand-edit of the file whose whole premise is that it is never hand-edited, or a withdrawal that records a legal fact that did not occur. The register has a documented convention for this (append a dated correction); the roster has none. **Decide the affordance while `organizations` is `[]` and the schema change is free** — after the first row it is a `.strict()` migration over published rows. | data-integrity F2.1 |
| HIGH | **Phase 5.3's "parity" is the wrong relation.** The correct one is asymmetric: `roster ⊆ register` on `record_ref`, hash equality **on the intersection only**, and `register ⊄ roster` is legal and must not be asserted — the register row is written when the instrument is executed, months before the roster row the ICLA signature gates. A symmetric assertion reds on the correct interim state, and the operator's escapes from a red required check are both worse than the defect. | data-integrity F1.2 |
| HIGH | **The parity assertion is vacuous until the first row.** Both sides of the join are empty today, so it would report pass while comparing nothing, then run against real data for the first time at the exact moment it matters. Needs the three-state form (`0 roster orgs` = not decided and say so / joined = pass / unjoined = fail) plus a fixture arm in `lint-legal-registers.test.sh`. `lint-legal-registers.sh` legislates against exactly this vacuity three times in its own voice (`:341-346`, `:418-420`, `:44-47`). | data-integrity F1.1 |
| HIGH | **`record_ref` integrity must land before or with the hash check.** Without it a mistyped or duplicated ref produces an *empty join*, which passes — precisely in the scenario the check exists for. Assert: register refs match the format or are the placeholder; register refs are unique; every roster `record_ref` appears in the register exactly once; the join cardinality is reported. | data-integrity F4.3 |
| HIGH | **S3's natural repair turns the parity check into a tautology.** If the roster merges without a register row, the obvious fix is to copy the hash out of the roster — after which the two stores no longer corroborate each other and nothing records that the independence was lost. The failure message must say *re-hash the instrument on the drive*, never *copy the other cell*. | data-integrity F2.3 |
| HIGH | **Roster validity is permanently coupled to an upstream-maintained branch.** `assertContributionTriggeredEntry` re-validates every roster account against `origin/cla-signatures` on every CI run, including withdrawn ones. If an entry is ever removed or rewritten there (an Art. 17 request is the obvious route), the merge gate bricks and both unblocking moves damage a legal record. The `failure_modes` block covers "unreachable or an HTML error page" and not "reachable, well-formed, and an entry we depend on is gone." | data-integrity F5.1 |
| HIGH | **`persist-credentials`.** `actions/checkout` writes an `http.<host>.extraheader` carrying the workflow token into `.git/config`, which `env -i` does not remove — so every probe can recover a credential with `issues:write`, the identity `closed_precheck` treats as unforgeable. Phase 5 is the first edit to that step; decide `persist-credentials: false` there deliberately, and **measure** whether the probe's fetch still succeeds unauthenticated before doing it. | security F2 |
| HIGH | **The public comment has an integrity property the plan models nowhere.** The sweeper reads back two control markers from comments authored by `github-actions` — the reopen marker (substring) and the PASS prefix. The author gate closes direct forgery, not *laundering*: content that reaches a probe's stdout is republished under that identity. This is the first probe to read third-party-controlled content. Two one-line fixes at the sweeper protect all 78 probes: neutralize `<!--` alongside the existing `^+` strip, and lengthen the fence so a probe line of three backticks cannot break out. | security F3 |
| MEDIUM | Guard 2 rows to fix before RED: **row 5 is miscoded** (dropping `%H` makes both `${line%% *}` and `${line#* }` return the whole string, so the probe exits 3 on *every* fixture — it reddens for the wrong reason and its stated expectation is backwards); **row 13 cannot fire** once `--depth=1` is gone (retire it or state the ordering as a source-order assertion); **G1 H1 says "any two"** when a zero-slack floor fires on one. | test-design |
| MEDIUM | **Four Guard 2 rows assert only `rc == 3`, and six branches produce 3.** The discriminator is already designed and unused — every exit-3 row must assert the `CANNOT ESTABLISH: <reason>` substring. `ccla-add.test.sh:376-391` is the in-repo model for proving a mutation on the *producer* of a refusal rather than on its code. | test-design |
| MEDIUM | **No Guard 1 row covers the `sha256sum` argv/stdin hazard** the plan devotes a paragraph to. One fixture whose basename contains a backslash reddens a mutant that swaps the forms; without it that mutant passes every listed arm. Also missing: a row for mutual exclusion (P4/FR2). | test-design |
| MEDIUM | **Fixture pre-use assertions must be discriminator-shaped, not build-shaped.** Two-touch: N==2 *and* the two `%cI` differ. Merge: ≥2 parents *and* the non-`--first-parent` log yields a different oldest. Rebase: `%aI != %cI` *and* one parent. Grafted: `.git/shallow` exists *and* `HEAD^` fails. Tag origin: tags non-empty *before* the fetch. And **`git clone --depth=1` silently ignores `--depth` on a local path** — measured; the grafted fixture must use `file://` or it is not grafted and its row reports the baseline. | test-design |
| MEDIUM | **Pin `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` on every fixture-building git call**, and `GIT_COMMITTER_DATE` on the `git rebase` itself — without the latter the replayed committer date is "now", both sides shift together, and the `%cI`→`%aI` row does not redden. A differential is blind to any drift the two sides share. | test-design |
| MEDIUM | **Port the instrument self-test** (`ccla-add.test.sh:109-119`) into the companion suite. `passes + fails == cases` catches an unpaired assertion site; it does **not** catch an arm that never runs (both sides decrement equally) nor an unconditional `pass` after a discarded predicate. Describe it accurately and let the floor carry absence. | test-design |
| MEDIUM | **`--instrument-file` closes transcription error, not selection error.** The operator can pass `~/Downloads/ccla-signed.pdf` and the script hashes the wrong bytes perfectly; nothing downstream can detect it. Add **mtime and byte size** to the stderr diagnostic (a re-export differs in both) and have QA paste that line into the PR body so provenance is a reviewable artifact. P1's wording overclaims and should say so. | data-integrity F5.2, CLO P2 |
| MEDIUM | **The §4(c) verification step does not exist.** Runbook §10.1 has four steps and none instructs the operator to open the instrument and match `--login` against the designation list — yet that check is the plan's only named mitigation for a wrong roster row. Add the step, naming the file, the section and the comparison, plus a recorded acknowledgement. | user-impact F4 |
| MEDIUM | **§4(c) lists usernames; the roster stores numeric ids.** A handle released and re-registered binds a stranger, and an operator performing the check exactly as instructed cannot see it. Pin the id at designation time, or refuse a login whose account creation post-dates `--authorized-from`. | user-impact F3 |
| MEDIUM | **`gh pr create` at `ccla-add.sh:419` has no failure handler**, unlike the push at `:409-418` — and its state is worse, because the branch carrying the association is already on the public remote. Mirror the four-line resume/abandon block. | data-integrity F2.2 |
| MEDIUM | **`ccla-add.sh` never asserts its branch point** while its PR body claims, verbatim, a single-file change — a false statement made by the tool itself in the body of the PR that establishes a legal record. It also means the duplicate-`record_ref` and duplicate-`id` checks run against a stale local roster. | data-integrity F5.4 |
| MEDIUM | **Resolve the instrument path once.** The `-e`/`-f`/`-s`/`-r` checks run against the argument while `sha256sum` hashes an independent second resolution; nothing asserts the thing hashed is the thing checked. Resolve once, then check and hash the same string (or open once and use the fd). | security F7 |
| MEDIUM | **`MIN_CHECKS=7` in `lint-legal-registers.sh` has zero slack** — raise it with the new assertion or the assertion is deletable without signal. The `(none yet)` placeholder is a parse hazard; delegate to `tenant-dpa-register-guard.sh --placeholder` rather than hand-rolling a fifth table parser, and pin the register's hash cell format to `^[0-9a-f]{64}$` in its Schema table. The lint gains its first `jq` dependency and needs a fail-closed pre-flight. | data-integrity F1.3-F1.5 |
| MEDIUM | **Guard C's 30 business days is hardcoded**, so the `## Verification` block reaches Guard B only. Narrow `cron-follow-through-monitor`'s query to exclude issues bearing a `soleur:followthrough` directive, and add a companion-suite arm asserting that exclusion. | observability 1 |
| MEDIUM | **No detection that the probe runs at all**, and **no drift gate on `fetch-depth: 0`**. The failure signature of both is the *absence* of a comment, which is also the signature of the `--limit 50` truncation — one staleness detector would cover the class. | observability 3, 7, 8 |
| LOW | Convert FR8, FR11 and FR19 from greps to behaviour: stub `gh`/`git` on a sandbox PATH and assert captured argv (pattern at `anthropic-admin-key-6297.test.sh:268-281`); assert `rc != 1` across the fixture family; add a known-positive control to FR19's awk range before grepping for absence. | test-design |
| LOW | Do not describe the retained 64-hex assertion as "near-tautological" — a comment saying an assertion is dead code is how assertions get deleted. Write it as load-bearing. Add a duplicate-flag refusal on the new arm. Sanitize `die()`'s `::error::` interpolation. Note in the runbook that the instrument path lands in shell history and in `/proc/<pid>/cmdline`. State that the inside-repo custody refusal is a typo catcher, not a boundary (a bind mount, a hardlink, or a sibling worktree defeat any path check). | security F9-F13, user-impact F10 |
| LOW | Run the authority **once** over all fixtures rather than paying six `tsx` cold starts. `.removed_at == null` also matches an *absent* key — pin against a future `.optional()`. | test-design, data-integrity F3.1 |

### The single highest-leverage change

`data-integrity` names it and it collapses six of the findings above: **make `ccla-add.sh` the
producer of the register row** — a separate `register` mode gated on the instrument alone (because
`add` cannot run until the ICLA signature exists, months later), which emits six of the register's
seven columns from operands it already computes; then make the roster write conditional on a
register row for that `record_ref` existing and already agreeing. That converts F1.1, F1.2, F1.4,
F2.3, F4.2 and F4.3 from a post-hoc lint on a public surface into a refusal at the write path —
which is the doctrine `ccla-add.sh:9-18` already commits this file to, and the only control that
has a remedy on a surface where nothing can be taken back. It is larger than #7909's scope; it
should be decided, not defaulted.

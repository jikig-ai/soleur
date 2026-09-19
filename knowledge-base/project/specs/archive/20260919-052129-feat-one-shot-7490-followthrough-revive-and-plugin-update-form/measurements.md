# Phase 0 preconditions — measured 2026-09-18

Every number below was produced by the command shown, in this worktree, at work time.
Plan-quoted figures are preconditions; where a reading contradicts the plan it is recorded
here and the plan's prose is corrected rather than propagated.

## 0.1 CLI (the surface the docs describe)

```console
$ claude --version
2.1.273 (Claude Code)
$ claude plugin update --help | head -3
Usage: claude plugin update [options] <plugin>

Update a plugin to the latest version (restart required to apply)
$ claude plugin marketplace update --help | head -3
Usage: claude plugin marketplace update [options] [name]

Update marketplace(s) from their source - updates all if no name specified
```

The two commands are distinct verbs with distinct help text, which is the whole of the
docs correction: `marketplace update` refreshes the catalogue, `update <plugin>` updates
the install. `<plugin>` is the positional the qualified `soleur@soleur-marketplace` form fills.

## 0.2 The published marketplace name is `soleur-marketplace`

```console
$ bash scripts/marketplace-manifest-validate.sh infra/github/soleur-marketplace-manifest.json
marketplace-manifest-validate: OK — every delivery-contract assertion holds
$ jq -r '.name, (.plugins[0].name)' infra/github/soleur-marketplace-manifest.json
soleur-marketplace
soleur
```

So the recommended path's qualified form is `soleur@soleur-marketplace`. A monorepo-direct
install names its marketplace `soleur`, which is why `plugin-delivery-recovery.md`'s
`soleur@soleur` is correct for that path and is out of scope.

## 0.3 / 0.6 Tracker census — 56 open `follow-through` issues

Bodies fetched with `gh issue view <n> --json body -q .body`, classified with the SHIPPED
fence predicate (dialect-safe form, column-0 directive anchor):

| Class | Count | Members |
|---|---|---|
| Fenced-only directive (the target) | 6 | 5813, 6488, 6617, 6678, 7490, 7985 |
| No directive at all, but ≥1 fence (must stay quiet) | 19 | — |
| Unfenced directive (healthy) | 25 | — |
| Neither a directive nor a fence | 6 | — |

6 + 19 + 25 + 6 = 56. Matches the plan's census exactly; the fenced-only set is unchanged.

## 0.7 awk dialect reading — the plan's stated rationale is WRONG; the decision is unchanged

Fixture: a 3-space-indented ```` ```html ```` fence around a column-0 directive.

| awk | safe form `[ ]?[ ]?[ ]?` | interval form `{0,3}` |
|---|---|---|
| gawk 5.4.1 (default) | fenced_seen=1 | fenced_seen=1 |
| gawk `--traditional` | 1 | 1 |
| gawk `--posix` | 1 | 1 |
| **mawk 1.3.4 20260302** (built from source; the ubuntu-24.04 dialect) | **1** | **1** |

A direct probe confirms it: a line whose literal bytes are ` {0,3}```html ` is NOT matched by
`/^ {0,3}(```|~~~)/` under mawk 1.3.4 — so mawk **honours** the interval and does not fall back
to matching the literal bytes.

**Correction to the plan.** The Guard Contract argued the safe form was required because a
dialect "would" decline the interval, leaving `fence` at 0 and silently disabling the #4200
fence skip across all 56 trackers. That failure is **not reachable on today's runner**: mawk
1.3.4 supports intervals (mawk gained them in 1.3.4; 1.3.3 did not). The safe form is still
what ships, for two reasons that survive the measurement — it removes the dependency on a
version fact nobody re-checks at upgrade time, and it is the repo's standing convention
(`scripts/followthroughs/zot-last-err-redact-7500.sh` states it verbatim;
`git grep -nE "awk.*\{[0-9],[0-9]\}" -- scripts/ .claude/hooks/` returns zero hits). The
shipped header says that, not the false version.

mawk is not installed on this machine and `docker info` fails here, so the reading was taken
against mawk 1.3.4 built from source (`invisible-island.net/datafiles/release/mawk.tar.gz`).

## 0.4 / 0.8 Baselines (green before any edit)

| Suite | rc | Total | Floor today |
|---|---|---|---|
| `scripts/lint-followthrough-varq-ban.sh` | 0 | 74 probes scanned; retired-name rule over 93 files | — |
| `scripts/lint-followthrough-varq-ban.test.sh` | 0 | 34 asserted | `MIN_ASSERTIONS=34` |
| `scripts/sweep-followthroughs.test.sh` | 0 | 118 | `MIN_ASSERTIONS=118` |
| `.claude/hooks/ship-soak-followthrough-gate.test.sh` | 0 | 19 | `MIN_ASSERTIONS=19` |
| `.claude/hooks/follow-through-directive-gate.test.sh` | 0 | 16 | **none — added by this change** |
| `tests/commands/test-sync-producer-reachability.sh` | 0 | 13 | — |
| `scripts/guard-vacuity-floor.test.sh` | 0 | 23 | `unclassified: 0`, `n_nofire: 0`, mutant-not-constructible **15**, deferred-not-constructible **16** |

The guard-vacuity-floor `mutant not constructible: 15` figure is the AC9b baseline: rule 3's
rows join that suite's derived population by shape, and its construction-failure ceiling
ratchets down only.

## 0.5 Rule-3 floors

Deferred to Phase 2 by construction: the plan's own finding is that the regex is the artefact
and three plan-time reconstructions gave 32 / 24 / 46. The floors are set from a single run of
the COMMITTED regex, recorded in the Phase 2 section below.

---

# Work-phase measurements and plan corrections

## Rule-3 census (deferred from 0.5, taken from the COMMITTED regex)

One run of the regex as shipped, over `scripts/followthroughs/*.sh` minus `*.test.sh`:

```
rule 3 walked 74 file(s), extracted 44 repo-path ref(s), 0 missing
```

29 of the 74 walked files carry at least one reference. Floors are set from the WALK and the
EXTRACTION separately — `MIN_REF_FILES=70`, `MIN_REFS=40` — because they count different things
and a broken glob and a broken regex are different vacuity modes.

Before the repoint the same command was RED on exactly two files, the plan's two:
`plugin-delivery-canary-7490.sh` (genuine rot) and `inngest-cutover-flip-rollout-7761.sh`
(the runtime artefact, now annotated per line).

**Two corrections to the plan's census reasoning**, both found by running it:

1. **A directory reference is legitimate and `git ls-files` lists no directories.** Four probes
   cite a directory (`apps/cla-evidence/scripts`, `knowledge-base/legal/audits`, …). Without
   ancestor directories in the membership set they read as rot. The set is files PLUS every
   ancestor of a tracked file.
2. **A seventh arm exists that the plan's six did not name:** `${OVERRIDE:-literal/path}` — a
   `:-` default whose fallback is a bare repo-relative literal rather than a `$VAR/` expansion
   (`QUERY="${FT8076_QUERY:-scripts/betterstack-query.sh}"`). It ships as the `literal-default`
   arm.

**A `pipefail` false-negative caught in the first implementation.** The membership test was
`printf '%s\n' "$set" | grep -qxF -- "$cand"`. Under this script's `set -o pipefail`, `grep -q`
closes the pipe on its first match, the ~18k-line producer takes SIGPIPE (141), and the pipeline
exits non-zero although grep MATCHED. Measured: **22 tracked paths reported MISSING on a clean
tree**. It greps a file operand now. This is the repo's own documented `grep -q`-on-a-pipe trap,
hit inside the file implementing a guard.

## AC7's verification command is broken as written

The AC prescribes `sed -n 's/^REPORTS="\?//; s/"\?$//p'`. The `p` flag is on the SECOND
substitution and `"\?$` matches the empty string at the end of EVERY line, so it prints the whole
file. Measured: the AC's own command emits 130 lines and `test -r` fails.

The correct extraction is a single anchored substitution:

```console
$ sed -n 's/^REPORTS="\(.*\)"$/\1/p' scripts/followthroughs/plugin-delivery-canary-7490.sh
knowledge-base/project/specs/archive/20260813-114111-feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md
$ test -r "$p" && echo readable
readable
```

AC7's INTENT (the literal is double-quoted, so an extraction that leaves the quotes in fails)
holds and is satisfied. The command was fixed, not the criterion.

## AC8 — the repointed probe under the sweeper's own shape

```console
$ env -i PATH=<sweeper PATH + gh> HOME="$HOME" GH_TOKEN=<token> GH_REPO=jikig-ai/soleur \
    bash scripts/followthroughs/plugin-delivery-canary-7490.sh; echo rc=$?
PASS: canary green on run 35365847886 (compared>0), and every upstream posting slot is recorded.
rc=0
```

## AC13b — reader census, classified

`git grep -l 'soleur:followthrough' -- ':!knowledge-base' ':!*.md'` returns 31 paths, not the
five the AC anticipated. Classified rather than inherited:

| Class | Count | Disposition |
|---|---|---|
| The sweeper + its suite | 2 | The consumer. Changed here. |
| The two hooks + their suites | 4 | Producers. Changed here. |
| The sweeper workflow | 1 | Comment corrected here. |
| Plugin-side mirror suites (`ship-followthrough-directive.test.sh`, `ship-soak-followthrough-enrollment-gate.test.ts`) | 2 | Assert the ship contract. Both re-run green. |
| The ship stub template | 1 | Producer; emits an unfenced directive already. |
| Probes citing their OWN directive in a header comment | 18 | Not readers. Prose. |
| `apps/web-platform/.../\_predicate-validator.ts` + `cron-follow-through-monitor.ts` + their tests + `lib/workstream.ts` | 5 | **A DIFFERENT GRAMMAR.** `parsePredicateYaml` parses `type:`/`url:` predicates for the Inngest monitor, not `script=`/`earliest=`. It reads the HTML comment first and does not consult fences. Unaffected; the six bodies use the sweeper grammar. |

## The `secrets=` and honoured-directive populations

Measured through the SHIPPED `parse_directive` over all 56 open trackers:

| | before | after |
|---|---|---|
| trackers with an HONOURED directive | 25 | **31** |
| of those, declaring `secrets=` | 24 | **28** |

The plan (and the workflow comment) said "8 to 12". Counting `secrets=` with a plain grep gives
28 before AND after, because prose mentions it too — a third, wrong answer. The workflow comment
now carries the measured figures and names the parser they came from.

## Probe repairs, measured before and after

| Probe | before | after | cause |
|---|---|---|---|
| `inngest-doublefire-reading-6617.sh` | rc=2 (permanent TRANSIENT) | **rc=0 PASS** | `--comments` and `--json` are mutually exclusive on current gh |
| `gh-pages-cert-reissue-6657.sh` (#6678) | rc=2 (permanent TRANSIENT) | **rc=3 CANNOT ESTABLISH** | the API answers 200 with `https_certificate: null`; an absence, not a failure |

The six enrolled probes as they stand, under `env -i`:

| Tracker | rc | meaning |
|---|---|---|
| #7490 | 0 | PASS — will close on the first sweep on/after 2026-09-21 |
| #7985 | 1 | FAIL — waiting on an upstream release; daily comment expected (commented on the tracker) |
| #6678 | 3 | CANNOT ESTABLISH — actionable message instead of a silent retry |
| #6617 | 0 | PASS |
| #6488 | 2 | TRANSIENT locally only — `SUPABASE_ACCESS_TOKEN` is a sweeper-provided secret |
| #5813 | 1 | FAIL — measured live state |

## AC26 — the tracker the plan said to file already exists

#7923 (`Follow-through sweeper: comment de-duplication, a per-probe timeout, and the ungated
--add-label enrolment path`, OPEN). Its §1 is precisely the deferred scope and records a tracker
carrying 33 identical comments. No issue filed; it is cited in the plan's `## Not in scope`.

---

# Review-round corrections (2026-09-18) — figures the panel falsified

Ten agents reviewed the implementation. Every counted claim in the record above was re-derived
independently; nine reproduced exactly. These did not, and are corrected here rather than left
standing.

## The `secrets=` population was 22 → 28, not 24 → 28

The `24` was **back-derived** (`28 − 4`, the four probes that gained the clause) rather than
measured, and it is internally inconsistent with the PR's own honoured-directive figure:

- honoured directives grew 25 → 31, i.e. by exactly **6**;
- all six newly-honoured trackers declare `secrets=` after the edit;
- therefore the declaring population must grow by 6, and `24 → 28` grows by 4.

Measured through the shipped `parse_directive` over all 56 live bodies, with the six pre-edit
bodies restored for the before-state: **22 → 28**. The missing two are #6488 and #6678, which
already carried `secrets=` **inside their fence** — where no parser could read it — and joined
the declaring population purely by being unfenced. The workflow comment now says so.

The adjacent claim ("counting with grep gives 28 before AND after") is also wrong: grep gives
**26 before / 28 after** by file. The point it makes — that grep answers a different question —
survives; the number did not.

## AC17 is MET: the sweeper dry run completed and was read

Run `35371156340` sat queued ~28 minutes behind a repo-wide Actions backlog (13 of the 15 most
recent runs were queued), then ran. Read from the LOG, not the conclusion — though the
conclusion is trustworthy here, since the workflow carries no `continue-on-error`:

```
sweep done (no_directive=27 fenced_directive=0)
```

`no_directive` fell 33 → 27, exactly the six trackers this change unfenced, and zero fenced
verdicts fired. Per-tracker, as the sweeper itself measured them:

| Tracker | sweeper verdict | matches the local reading? |
|---|---|---|
| #7490 | not run — `earliest=2026-09-21` not reached | yes (by design) |
| #7985 | exit 1 FAIL | yes |
| #6678 | exit 3 CANNOT ESTABLISH | yes |
| #6488 | exit 1 FAIL | n/a locally (no `SUPABASE_ACCESS_TOKEN`; it ran for real in CI) |
| #5813 | exit 1 FAIL | yes |
| **#6617** | **exit 1 FAIL** | **NO — local reads rc=0 PASS** |

## UNEXPLAINED: #6617 reads PASS locally and FAIL under the sweeper

This is recorded as a divergence rather than resolved, because the cause was not established.

The probe looks for a `^RESULT: (PASS|FAIL)\b` line in comments whose `authorAssociation` is
OWNER/MEMBER/COLLABORATOR. That comment exists on #6617 (`RESULT: PASS`, author `deruelle`,
association `MEMBER`), and the probe returns rc=0 PASS locally — measured both WITH and WITHOUT
`GH_REPO` forwarded, so repo resolution is not the difference. Under the sweeper it returns
rc=1 with "no verdict is recorded on #6617", i.e. its comment query came back without the line.

The remaining difference is the identity: the operator's token locally, `GITHUB_TOKEN`
(`github-actions[bot]`) in CI. `authorAssociation` is a property of the comment's author and
should not vary by reader, so that hypothesis is not confirmed — it is simply what is left.

**The PR body and this record therefore state the SWEEPER's verdict, not the local one.** The
sweeper is the authority; a local reading that contradicts it is not evidence that the tracker
will close. The probe is enrolled and will report daily, which is the fastest way to settle it.

## Smaller corrections

- The AC7 `sed` prints **134** lines (the whole file), not 130. The finding it supports — `p` is
  on the second substitution and `"\?$` matches empty at every line end — is unchanged.
- The AC13b reader census sums to 31, not 33: the "probes citing their own directive" row is
  **16**, not 18 (one of the counted files is a `*.test.sh`, and one is
  `scripts/bootstrap-ccla-watch-7922.sh`, which is neither a probe nor in that directory).
- "50 quiet, 0 false positives" was measured in-session and is now sourced here: of the 56 open
  trackers, 6 were fenced-only and the other **50** emit no fenced verdict under the shipped
  predicate.

## Defects the panel found in code this change ADDED

Recorded because all three were in the verification, not the fix — the pattern this repo's own
rules predict for a guard-shaped PR.

1. **The create-time gate's fence grep matched EVERY line.** `'^[ ]?[ ]?[ ]?(\`\`\`|~~~)'` written
   with backslash-escaped backticks inside a single-quoted shell word: a backtick is already
   literal there, and GNU grep reads `\`` as the buffer-start anchor, so the alternation
   degenerated and the branch fired on any body reaching it. Caught by the indented-directive
   row whose deny reason never appeared — not by reading.
2. **Rule 3's `literal-default` arm dropped any path with a hyphen in its first segment.** The
   backward walk to the nearest `-` finds the `-` of `:-` only when segment one is hyphen-free,
   so `${OV:-knowledge-base/…}` — this repo's commonest prefix — yielded `base/…`, failed the
   tracked-top-dir test, and vanished with no diagnostic. Now captured directly, with a
   fixture pair (R3-M7d absent / R3-M7e present).
3. **The `claude plugin list` assertion was satisfied by the prose explaining it.** The sync
   suite flattened the WHOLE of `sync.md`, so the sentence "that is why `claude plugin list` is
   named in the same breath" pinned the property. Proven by deleting the literal from the
   runtime message only: 13/13 still green. The haystack is now the runtime messages alone —
   and the FIRST attempt at that fix was vacuous the same way, because a bare `*"` opener also
   matched inside a bash snippet and swallowed 79 lines of prose.

---

## Addendum — 2026-09-18: the test-design panel found a live defect the PR's own guards could not see

A `test-design-reviewer` pass over the branch returned four HIGH findings. All are fixed inline;
each fix is mutation-verified in both directions against a green in-sandbox baseline.

### HIGH-1 — a stray fence INSIDE the canonical multi-line directive erased `earliest=`

`plugins/soleur/skills/ship/SKILL.md` emits the directive over four lines, and
`plugins/soleur/test/fixtures/followthrough-directive/expected-issue-body.md` is that exact
golden body. **No fixture in any of the five suites instantiated it** — all 181 + 73 + 24 + 24 +
35 assertions drove the single-line spelling. So the shape this repo actually produces was
unrepresented in its own oracle.

`parse_directive`'s `fence { next }` runs before the `in_dir` field accumulator, so a fence
delimiter landing between `script=` and `earliest=` dropped every continuation line after it.
`script` survived (it is above the fence), `earliest` did not, and `run_one` rendered it through
`${earliest:-now}` → `iso_to_epoch ""` → **the soak gate was skipped entirely and the tracker
closed PASS on day 0.** Measured against the shipped sweeper with a matched control:

| body | sweeper behaviour |
|---|---|
| multi-line, `earliest=2099-01-01`, one stray ` ``` ` between `script=` and `earliest=` | `directive found (… earliest=now …)` → `would close with verdict=PASS` |
| same body, stray fence line removed (control) | `earliest=2099-01-01T00:00:00Z not yet reached — skipping` |

`fence_unbalanced` was emitted but only appends a sentence to the fenced-directive comment,
which never fired here because `script` was honoured. The run stayed green.

**Fix.** A fence cannot OPEN inside an unterminated directive — `<!-- ... -->` is an HTML
comment, so its continuation lines are directive content, not markdown. Mirrored into all three
parsers (`scripts/sweep-followthroughs.sh`, `.claude/hooks/follow-through-directive-gate.sh`,
`.claude/hooks/ship-soak-followthrough-gate.sh`) and the anomaly is counted and reported as a
new `__sweeper_meta__ directive_fence_interrupted` warning rather than swallowed.

Two details were load-bearing and only surfaced by running the suites:

- The soak gate's copy needed `!fence &&` on its directive-scope rule. Without it a FENCED
  directive set `in_dir` and then suppressed its own strip, inverting every deny row. Caught by
  its own suite (24 → 22, floor 24) and by the parity oracle (12 divergences).
- The create gate diverged in the **false-DENIAL** direction — it would have blocked
  `gh pr ready` on a body the sweeper honours. That is the direction an author cannot work
  around.

**Pinned by the FIELD, not by enrolment.** The first absolute assertion written for this was
vacuous in the same way the assertion it replaced was: `authority_enrolled` answers "is there a
directive", a bit this defect does not flip. Removing the guard from the authority left the
oracle at **68/0 green**. Only asserting the extracted `earliest=` value reds it. This is the
second time in this session that the fix for a vacuous assertion was vacuous the same way, and
it is why `plugins/soleur/skills/review/SKILL.md` now carries the two-direction rule.

### HIGH-2/3/4 — a conservation identity plus an assertion floor is not dispatch coverage

In three of the four suites both backstops were computed from a counter the disarmed helper
still moves. Measured, each byte-identical to the honest run at exit 0:

| suite | one-function mutation | reported |
|---|---|---|
| `lint-followthrough-varq-ban.test.sh` | `check() { asserted=$((asserted+1)); pass "$2"; }` | `73 passed, 0 failed … PASSED` |
| `follow-through-directive-gate.test.sh` | `assert_deny() { PASS=$((PASS+1)); return 0; }` | `24/24 passed, 0 failed` |
| `sweep-followthroughs.test.sh` | all three assert conditions → `[[ 1 == 1 ]]` | `PASS=181 FAIL=0 TOTAL=181` |

`varq`'s header claimed `asserted` "moves at the call site so a neutered verdict helper drops the
verdict without dropping the count" — true of `pass`/`fail`, **false of `check` itself**. And
`guard-vacuity-floor.test.sh` promoted the directive gate on the stated grounds that its floor
reads "an independent count incremented at the assert call sites"; `TOTAL` was incremented at the
`run()` call sites, so that rationale described a suite shape the file did not have.

**Fix.** The template already existed in this PR — `ship-soak-followthrough-gate.test.sh` and the
new parity oracle both carry an instrument self-test. Ported into all three, each with an
append-only `FAILURES` ledger the verdict reads alongside the counter. Every mutation above now
exits 1 naming which observable failed to move.

### MEDIUM-1 — parity is satisfied when every reader is wrong the same way

The mirrored widening the SUT's own comment instructs (`/^[ ]*(```|~~~)/` in all three places)
left all four suites green. Closed with a `declare -A absolute` table asserting what the
**authority** must say on seven rows, including CommonMark's 0–3-space far side. Re-measured:
the mirrored widening now reds the oracle (2 divergences).

### MEDIUM-2 — the create gate is now the third reader

It agreed with the authority on all 18 shapes but 12 of those agreements were unasserted. Driven
end to end in the oracle's walk loop. Verified biting: reverting only the create gate's half of
the HIGH-1 fix reds exactly one row, in the false-denial direction.

### LOW-1 — the conservation identity misattributed its own fail-closed branches

The six direct `fail "…mutation did not land…"` call sites bypass the assert helpers, the only
other place `TOTAL` moves, so a fired landing check skewed the identity by +1 and the operator
got `accounting: PASS+FAIL (179) != TOTAL (178)` instead of the author's diagnosis. **The first
fix moved `TOTAL` into `fail()` and `guard-vacuity-floor.test.sh` correctly rejected it** — a
case counter inside a verdict helper makes conservation a tautology. Corrected to a call-site
increment. Verified: stubbing `g4_mutate` now prints the author's "mutation did not land" lines
with no accounting FATAL.

### Counts after the round

`sweep` 181, `varq` 73, `parity` 35 → **68** (floor raised), `directive-gate` 24, `soak-gate` 24,
`guard-vacuity-floor` 23/23.

### Not fixed, recorded

- **LOW-2** — adding a novel `__sweeper_meta__` kind logs the fallthrough but no row reads it, so
  the header's "an additive parser change cannot quietly no-op here" claim is unpinned. Fail-open
  with no verdict impact; the new `directive_fence_interrupted` kind added here IS read and
  warned on.
- **`G4-4b` asserts only `rc != 0`**, which a syntax error in a future mutant would also satisfy.
  It is the one row built without `g4_mutate`.

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

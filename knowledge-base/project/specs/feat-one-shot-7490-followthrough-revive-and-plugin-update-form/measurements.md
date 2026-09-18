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

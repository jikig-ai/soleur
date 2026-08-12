---
title: "perf(test-all): relevance-gate the C4 producer end-to-end suite and the .github fixture runner"
date: 2026-08-12
slug: perf-test-all-gate-c4-producer-and-github-scripts
branch: feat-one-shot-7494-test-all-diff-gate-suites
issue: 7494
closes: 7494
type: enhancement
lane: single-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Verification Ledger (deepen-plan, 2026-08-12)

Every load-bearing claim in this plan was probed live rather than asserted. The four
**negative** claims are the ones that would silently justify unnecessary work if wrong, so each
carries its command and result. All halt gates passed.

| Claim | Probe | Result |
|---|---|---|
| The `TEST_RELEVANCE_PREFIXES` invariant is enforced by nothing | `grep -c TEST_RELEVANCE_PREFIXES scripts/lint-orphan-test-suites.sh` | **0** — confirms. Phase 4c buys a property nothing else buys. |
| `SOLEUR_TEST_FORCE_ALL` appears once in the runner and is printed nowhere | `grep -n 'SOLEUR_TEST_FORCE_ALL' scripts/test-all.sh`; `grep -nE '(echo\|printf).*SOLEUR_TEST_FORCE_ALL'` | one hit (the early return), **zero** print sites — confirms. Phase 2c is needed. |
| `MIN_ASSERTIONS` enumerates two of four arrays | `grep -n 'MIN_ASSERTIONS=' scripts/test-all-infra-coverage-notice.test.sh` | `MIN_FIXED + ${#W7_FILES[@]} + ${#REGISTRY_BATTERY_PATHS[@]} + ${#CF_TUNNEL_BATTERY_PATHS[@]}` — confirms. Phase 3b is needed. |
| The proposed pairing grep matches neither existing array | the grep, run verbatim against `scripts/test-all.sh` | **NO MATCH ×2** — the cut was correct, not merely cautious |
| The linter's **blocking** CI route is its suite registration, not the advisory `lint-bot-statuses` step | `grep -n 'run_suite "scripts/lint-orphan-test-suites"' scripts/test-all.sh` | line 761 — confirms `## Observability` |
| lefthook does not run the linter | `grep -c orphan lefthook.yml` | **0** — the earlier draft's claim was false and is recorded in Premise Validation |
| `325a1a5c0` is ADR-181's commit and an ancestor of HEAD | `git log -1`, `git merge-base --is-ancestor` | `perf(test-all): path-gate the heavy mutation batteries… (#7441)`; ancestor: yes; touched `test-relevance-paths.sh` (+121) and `test-all.sh` (+273) |
| #7494 / #7402 / #7484 / #7429 exist with the titles cited | `gh issue view` ×4 | all **OPEN**, titles match |
| Cited AGENTS rule IDs are active, not retired or fabricated | `grep -E '\[id: <id>\]' AGENTS.md` for each | `cq-write-failing-tests-before`, `cq-ac-must-not-depend-on-concurrent-sessions` — both **ACTIVE** |
| All nine declared pathspecs resolve, including four directory forms | the Phase 0.2 loop | no `UNRESOLVED:` output |

**Halt gates.** 4.6 User-Brand Impact — heading, valid threshold, scope-out bullet: **PASS**.
4.7 Observability — all five fields present with children; probe verb `bash` is allowlisted; no
`ssh`: **PASS**. 4.8 PAT-shaped variable — no matches: **PASS**. 4.11 Guard Contract —
`python3 scripts/lint-guard-contract.py` → *"scanned 1 plan file(s), 1 with a Guard Contract,
2 guard entries"*: **PASS**. 4.5 (network), 4.55 (downtime/cutover), 4.9 (UI wireframe) and
4.10 (encryption posture) did not trigger — no network symptom, no serving surface taken offline,
no UI surface, no persistent store or new cross-component connection.

**Precedent-diff (Phase 4.4).** Every mechanism this plan adds copies a precedent in the same
tree rather than inventing a form: the derived floor mirrors `MIN_ASSERTIONS`'s "DERIVED, not a
hand-typed integer" and `.github/scripts/test/run-all.sh`'s `MIN_SUITES`; the source anchors mirror
the existing `--name-status -M` anchor; the `${a[@]+"${a[@]}"}` guard mirrors the `EXCLUSIONS`
loop; the append-only ADR section mirrors the seven `## Addendum — <date>` sections in the corpus,
including the one ADR-181 itself wrote into ADR-177; and the `if`-block form mirrors what
`_diff_touches`'s own header mandates. **No mechanism here is novel** — which is the point of D1.

---

## Overview

`scripts/test-all.sh` already declines suites whose subjects a run's diff cannot reach. ADR-181
shipped that mechanism (commit `325a1a5c0`, 2026-08-12); this worktree's base is exactly that
commit. This work extends the same mechanism — unchanged — to the two most expensive suites still
registered unconditionally, and records a **measured** refusal on a third.

| Suite | Cost | Status at `325a1a5c0` | This plan |
|---|---:|---|---|
| `tests/scripts/registry-gate-mutation-battery` | ~860–978 s | **gated** (`REGISTRY_BATTERY_PATHS`) | untouched |
| `apps/web-platform` (vitest, 1098 files) | ~516 s | ungated | **refused — 7 % skip rate**, D3 |
| `plugins/soleur/test/c4-from-components.test.sh` | ~429 s | ungated | **gate** — 96 % skip rate |
| `scripts/cf-tunnel-liveness-gate-mutations` | ~189–204 s | **gated** (`CF_TUNNEL_BATTERY_PATHS`) | untouched |
| `.github/scripts/test/run-all.sh` | ~95 s | ungated | **gate** — 56 % skip rate |

Two figures are given for the already-gated batteries because the repo carries two: the issue
measured 978 s / 204 s, while `scripts/lib/test-relevance-paths.sh` and `scripts/test-all.sh`
record ~860 s / ~189 s. Phase 1 writes comments next to those, so the discrepancy is named rather
than silently contradicted.

**Expected saving: ~465 s per local full-gate run.** Stated as an absolute, deliberately. The
issue's 3020 s is *pre*-`325a1a5c0` summed registered-suite time and ADR-181's "≈45 min → ≈28 min"
was measured over a different scope (~289 suites); the two must not be arithmetically combined.
465 s is an **expected value across a commit distribution, not any single run's saving**:

| Outcome | Share of recent commits | Saving |
|---|---:|---:|
| both decline | ~54 % | 524 s |
| c4 only | ~42 % | 429 s |
| `.github` only | ~2 % | 95 s |
| neither | ~2 % | 0 |

The issue's non-goal is preserved verbatim: **no skip is silent.** Every decline goes through the
existing `skip_suite` helper — label, machine-readable reason, exact re-run command, `skipped`
counter, and a labelled `skip=<reason>` field in `TEST_TIMING_LOG`. `TEST_GROUP=all`,
`SOLEUR_TEST_FORCE_ALL=1` and CI still run everything; under CI the decline is unreachable by
construction. Phase 2c additionally makes the force-all lever **discoverable**, which it is not
today.

---

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified how | Verdict |
|---|---|---|
| #7494 is OPEN | `gh issue view 7494` → `OPEN`, `deferred-scope-out` | holds |
| "gates exactly ONE of them" | read `scripts/test-all.sh` at HEAD | **STALE** — three are gated (both batteries + the infra runner). The issue predates `325a1a5c0`. |
| "the top three are ~63 %" | re-derived | **PARTIALLY STALE** — the largest is already gated; 1040 s of the top-5 remains |
| ADR-181 governs this surface | read the ADR | holds — it is the amendment target |
| "`VITEST_SHARD` is plumbed … a docs/legal diff needs ~12 files" | read the registration + `--shard` semantics | **FALSE PREMISE** — `--shard=K/N` partitions the *collected* set arithmetically and cannot select by path. See D3. |
| `main-health-monitor` "runs the full un-gated gate" | repo research claimed it inherits the gates on an empty diff | **that research finding is WRONG** — `_diff_touches` returns 0 unconditionally when `CI` is set, before any diff is consulted (ADR-181 Decision 4) |
| "the linter runs under lefthook" (an earlier draft of this plan's own Observability block) | `grep -c orphan lefthook.yml` → **0** | **FALSE, self-inflicted.** lefthook runs it at no stage. Corrected in `## Observability`. |

### Property List and Cut List (Phase 0.6b)

**Properties:**

- **P1.** A local run on a diff touching none of an expensive suite's subjects does not pay it.
- **P2.** Every decline is announced (what / why / exact re-run) and counted as a non-pass verdict.
- **P3.** CI, `TEST_GROUP=all` and an explicit force still run everything.
- **P4.** A diff that *does* reach a suite's subjects still runs it — including via untracked
  files, renames, and an undeterminable diff.

**Cut List.** Six of the nine cuts came from review. The pattern — *this plan re-deriving machinery
the repo already has, then defending the derivation* — is the finding, not the individual rows.

| Mechanism | Property | Already bought by | Cut |
|---|---|---|---|
| "Give each suite a path predicate" | P1 | `_diff_touches` + `scripts/lib/test-relevance-paths.sh` | **reuse** — only the two arrays are new |
| "Keep the epilogue contract" | P2 | `skip_suite` already prints "Nothing in this run is evidence for it. Re-run with:" | ✂ nothing to build |
| "Full run in CI and on demand" | P3 | `_diff_touches`'s two unconditional early returns | ✂ nothing to build (but see Phase 2c — the lever exists and is *undiscoverable*) |
| Rename / untracked / undeterminable safety | P4 | `_diff_names` already unions four sources with a fail-SAFE arm | ✂ one prefix to add |
| "Shard `apps/web-platform` via `VITEST_SHARD`" | P1 | nothing — and `--shard` cannot select by path | ✂ **on measurement**, D3 |
| A "narrowed" fourth verdict class | P2 | — | ✂ a partial run reported `[ok]` is the green-that-is-not-evidence shape ADR-181 closes |
| A new `scripts/test-all-relevance-gate.test.sh` *(invented by this plan)* | P1/P2/P4 verification | `scripts/test-all-infra-coverage-notice.test.sh` — `build_sandbox`, `run_gate_arm`, `check_element_arms` (**array-driven**), the rename fixture **and its source anchor**, the fail-SAFE arm, the CI-decline arm, and `MIN_ASSERTIONS` **derived from the array cardinalities** | ✂ extend it (Phase 3) |
| A static `skip_suite` pairing check in the linter *(invented by this plan)* | site-(iv) coverage | the same suite's `fail "the registry battery was declined silently"` — behavioural, and strictly stronger than a static grep | ✂ **and it was broken** — see below |
| Hoisting the c4 suite out of the glob loop + a `REQUIRED_RUNNERS` entry *(invented by this plan)* | "one gating shape, so the pairing anchor can be literal" | nothing needs it once the pairing check is cut; an **in-loop literal label** gives the same shape at zero cost | ✂ |

**The pairing check was not merely redundant — it was broken on arrival, and running it is what
proved that.** `RELEVANCE_ARRAYS` maps an array to the battery's **file path** (that field is
already load-bearing for the self-inclusion check, which requires it to be an element of the path
array). `skip_suite`'s first argument is a **display label**, and in this repo they differ:

| `RELEVANCE_ARRAYS` battery | actual `skip_suite` label |
|---|---|
| `tests/scripts/test-registry-gate-mutation-battery.sh` | `tests/scripts/registry-gate-mutation-battery` |
| `scripts/cf-tunnel-liveness-gate-mutations.test.sh` | `scripts/cf-tunnel-liveness-gate-mutations` |

Verified: the proposed grep returns **NO MATCH for both existing arrays** at HEAD. It would have
reddened a clean tree for two correctly-wired suites — and because the two *new* arrays happen to
have `label == path`, 2 of 4 would have passed, so the failure would have read as "the linter found
real drift" when it found none. Four of five reviewers found this independently.

Roughly forty lines of an earlier draft — the hoist, the `REQUIRED_RUNNERS` entry, four mutation
rows, three acceptance criteria, two risk rows — were scaffolding on that unverified premise. All of
it goes with the check. *Ceremony is not rigor; running the check is rigor.*

### Value-Proposition Measurement (Phase 0.6c)

Skip rates were derived by replaying each candidate predicate against the file list of the **last 80
commits on `origin/main`**:

```bash
for sha in $(git log --format=%H -80 origin/main); do
  git show --pretty=format: --name-only "$sha" | sed '/^$/d' | grep -qE '<predicate>' || skips=$((skips+1))
done
```

| Suite | Cost | Honest predicate | Skips | Expected |
|---|---:|---|---:|---:|
| c4 producer e2e | 429 s | `plugins/soleur/{scripts/generate-c4-from-components.ts, lib/, test/test-helpers.sh, test/fixtures/component-docs, self}` | **77/80 = 96 %** | ~412 s |
| `.github` fixture runner | 95 s | `.github` + `apps/web-platform/infra` | **45/80 = 56 %** | ~53 s |
| `apps/web-platform` | 516 s | `apps/web-platform`, `plugins/soleur`, `.github`, `scripts`, `AGENTS(.rules).md`, `knowledge-base/{product,overview,engineering}` | **6/80 = 7 %** | ~36 s |

**These rates are CEILINGS.** The replay matcher (`grep -E`, per commit) is narrower than the
runtime matcher (unanchored `grep -F` over a unioned blob), which skips strictly less often; and the
runtime unit adds uncommitted and untracked work, which can only reduce the rate. `origin/main` is
linear with one squash per PR, so per-commit ≈ per-PR. Phase 6 re-replays with runtime semantics.

Two further measurements shaped the plan:

- **Predicate shape.** Declaring the whole `plugins/soleur/lib/` **directory** — closed under any
  future import the producer gains — costs nothing: 96 % either way, because that directory appears
  in 1 of 80 commits. Structural beats enumerated at equal price.
- **The counterfactual behind D3.** 41 of the same 80 commits (**51 %**) touch no
  `apps/web-platform/` file at all. That is what makes the refusal a *sized deferral*.

### Relevant repository anchors

- `scripts/test-all.sh` — `skip_suite()` ("A SIBLING of run_suite, deliberately NOT an option on
  it"; `$1 = label (must match the label the suite would have run under)`); `_diff_touches()` ("The
  two bypasses are UNCONDITIONAL early returns"; "Written as explicit `if` blocks rather than
  `[[ … ]] && return 0`"); the two existing gates; the glob loop `for f in
  plugins/soleur/test/*.test.sh …`; `run_suite ".github/scripts/test/run-all.sh" bash
  .github/scripts/test/run-all.sh` under its `MIN_SUITES` floor comment; the terminal marker
  `=== $((suites - failed - killed - skipped))/$suites suites passed ===`.
- `scripts/lib/test-relevance-paths.sh` — "DECLARATIONS ONLY"; "EVERY LIST ALSO CONTAINS *THIS*
  FILE"; the "KNOWN LIMIT — … LOWER BOUND, not a closed set" precedent; `TEST_RELEVANCE_PREFIXES`
  and its prose invariant ("the union of the top-level prefixes every declared path lives under") —
  **which nothing currently enforces**. Header says "for the two heavy mutation batteries" and "to
  guard two run_suite calls" — both go stale at four.
- `scripts/lint-orphan-test-suites.sh` — `RELEVANCE_ARRAYS` and its **five** per-array checks
  (declared / non-empty / resolves / self-includes / de-reference anchor); the `${a[@]+"${a[@]}"}`
  idiom and its bash-3.2 reason; `REQUIRED_RUNNERS`, anchored on the **command** not the label; the
  `cmd_seen < 1` floor precedent for `tests/commands/`.
- `scripts/test-all-infra-coverage-notice.test.sh` — the gate harness: `build_sandbox()`,
  `run_gate_arm()`, `check_element_arms()` under its `COMPLETENESS: every declared predicate path
  must actually ARM its battery` comment, `REGISTRY_LABEL`/`CFTUNNEL_LABEL`, the
  `docs-only`/`force-all`/`ci-set`/`undeterminable`/`rename-old-path` arms, `MIN_FIXED=44` and the
  derived `MIN_ASSERTIONS`. **Its seam `[[ -n "${SANDBOX_DIFF_NAMES:-}" ]] && _diff_names=…`
  replaces the blob wholesale**, which is why its rename arm is paired with a *source anchor*.
- `plugins/soleur/test/c4-from-components.test.sh` — `PRODUCER=`, `FIXTURES=`, `source
  "$SCRIPT_DIR/test-helpers.sh"`, `seed()`, and the `reason=likec4-unavailable` → SKIP degrade. It
  never reads the real tree (the producer takes its root from `process.argv[2]`), which is what
  makes its dependency set enumerable. `plugins/soleur/lib/c4-from-components.ts` has zero relative
  imports, so the closure claim holds today.
- `.github/scripts/test/test-infra-suite-registration.sh` — `git -C "$REPO_ROOT" ls-files
  "${INFRA_PREFIX}/*.test.sh"` with `INFRA_PREFIX=apps/web-platform/infra`. The one real-tree read
  in that runner, and why `apps/web-platform/infra` is load-bearing in its predicate.

### Institutional learnings applied

- `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` — a static grep is weaker than
  a behavioural assertion that the skip *fires with the right label*. Decided the pairing-check cut.
  It also convicts the sandbox seam: `SANDBOX_DIFF_NAMES` **is** the gate's input, so a
  fixture-driven arm alone pins the input, not the gate. Hence Phase 3d's source anchors.
- `2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md` — an
  enumerated set rots on the next arrival. Drove the directory pathspecs, Phase 4d's structural
  re-point, and Phase 3b's derived floor.
- `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` — mutate the
  property, not the logic. Drove cutting every mutation row that exercises unchanged code.
- `test-failures/2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md` — a loop over a
  zero-cardinality list fail-opens to `exit 0`. Produced the dispatch-floor finding.
- `2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md` — dogfood the gate on its own PR
  (Phase 6, AC5).

### Open Code-Review Overlap

**None.** A `jq … contains($path)` sweep over all 64 open `code-review` issues matched none of the
five files in `## Files to Edit`.

Three adjacent `test-all.sh` issues are **acknowledged, not folded in**: **#7402** (glob blind
spots — registration coverage; this plan leaves the glob's `run_suite "$f" bash "$f"` byte-for-byte
unchanged), **#7484** (the advisory lock delivers no isolation — the correct layer for the issue's
contention argument, D3), **#7429** (KILLED absorbed by wrappers — classification).

### Functional / community discovery

Not applicable, by inspection: the deliverable edits this repository's own bash test runner. No
community skill or package can supply a predicate over this repo's directory layout.

---

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality at HEAD | Plan response |
|---|---|---|
| "gates exactly ONE of them on the diff" | three are gated | Overview restates the true baseline |
| "the top three are ~63 %" | the largest is already gated; 1040 s remains | scope is the gateable 429 s + 95 s |
| "Shard `apps/web-platform` by path. `VITEST_SHARD` is already plumbed." | plumbed, but `--shard=K/N` partitions arithmetically | rejected, mechanism named (D3) |
| "A docs/legal diff needs ~12 files, not 1100" | true as a wish; the *derivation* is unsound — a source grep cannot separate `knowledge-base/x.md` and 40+ synthetic in-memory fixture paths from `knowledge-base/product/roadmap.md`, a real read | rejected; the sound alternative (a dedicated vitest project) is the deferral's scope |
| "134 suites run unconditionally" | `TEST_GROUP` partitions the registry; the count varies by shard | not load-bearing; no AC depends on it |

---

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-181` via an append-only dated section — do not edit its body in place.** The corpus
convention is `## Addendum — <date> (<ref>)`, present in seven ADRs including
`ADR-177 … ## Addendum — 2026-08-11 (ADR-181)`, which ADR-181 itself wrote. Editing `## Decision`
in place would destroy the distinction between what was decided on 2026-08-11 and what was added on
2026-08-12 — the same record-forking harm that argues against minting a new ADR, inverted — and it
breaks citation-by-date, which `principles-register.md` relies on.

Add **`## Addendum — 2026-08-12 (#7494)`** to
`knowledge-base/engineering/architecture/decisions/ADR-181-local-gate-declines-are-counted-verdicts.md`,
carrying all of:

1. **The gated set grows from two batteries to four suites**, naming the two new arrays and their
   ceiling-qualified skip rates. Plus the predicate-shape rule this change establishes: **prefer a
   directory pathspec over a file enumeration when the skip rate is unchanged** — a directory is
   closed under future additions, a file list is a snapshot.
2. **`N-3/N` is now `N-5/N`.** The original Decision states *"the marker now reads `N-3/N`, so
   `N/N` is no longer the ordinary local green spelling"*, and its worked example shows
   `3 skipped`. With four gated suites plus the infra runner it is five. This is the
   highest-traffic sentence in the ADR — an operator anchored on `N-3/N` reads a healthy run as a
   defect. Correct it in the addendum rather than silently in the body.
3. **Mitigation layer 3 does not generalise.** The Consequences list gives *"Both batteries already
   hard-abort on a missing declared path"* as one of four stale-predicate mitigations. The c4 suite
   does the opposite — it **degrades** (`status=degraded reason=likec4-unavailable` → SKIP). So the
   four-layer stack is a three-layer stack for the two new suites, and the addendum must say which
   layers apply per suite. A corollary worth stating: **the re-run command `skip_suite` prints for
   the c4 suite can exit green while producing no evidence**, in a degraded likec4 state — the
   recovery path itself carries the green-that-is-not-evidence shape.
4. **The soundness gap this change closes**: `RELEVANCE_ARRAYS` had no dispatch floor, so emptying
   it made the entire anti-rot block iterate zero times while printing `orphan test suites: none`.
   And the `TEST_RELEVANCE_PREFIXES` invariant, stated in that file's own prose, was enforced by
   nothing — and now is.
5. **The declaration contract is five sites, not four**, and the fifth is
   `TEST_RELEVANCE_PREFIXES`. Decision 3 currently enumerates the contract; the next engineer
   adding a gate needs the full list recorded in the ADR, not only in a merged plan file.
6. **Alternatives Considered** — *"Gate the `apps/web-platform` vitest suite"* (REJECTED: 7 %/516 s,
   the `--shard` refutation, the derived-subset unsoundness) and *"A static `skip_suite` pairing
   check in the linter"* (REJECTED: the label and the battery path are different strings, so the
   check reds correctly-wired suites; and the property is already asserted behaviourally).
7. **Consequences** — the **absolute** expected saving (~465 s/run, ceiling-qualified) and the
   per-run distribution. Do **not** restate a wall-clock endpoint derived by combining the issue's
   3020 s with ADR-181's 45-minute figure; the two were measured over different scopes. Also record
   the **asymmetric** CI protection of the two newly-declinable suites (see `## User-Brand Impact`).

The ordinal is not at risk — this amends an existing ADR.

### C4 views

**No C4 impact.** Enumerated against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:

- **(a) External human actors** — the only actor is the operator running `scripts/test-all.sh`
  before pushing. `founder` and the untrusted-contributor actor are both already modelled; neither
  gains nor loses a capability.
- **(b) External systems / vendors** — none added. The c4 suite shells out to the pinned `likec4`
  CLI, a pre-existing dependency of a suite this change only *gates*; no vendor edge is created,
  removed, or re-pointed.
- **(c) Containers / data stores** — none. `TEST_TIMING_LOG` is a developer-local file already
  written by `run_suite` and `skip_suite`.
- **(d) Actor ↔ surface access relationships** — none change. No credential, boundary, or admission
  decision. The model's CI edges (`engine -> github "Git operations and CI"`) describe the product
  pipeline, not the local runner.

### Sequencing

None. The decision is true at merge — no soak, no dark launch, no `adopting` state.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a `/soleur:one-shot` run whose local exit gate ends
`N-5/N suites passed` (four `relevance` declines plus the infra runner's `not_in_diff`) and — worst
case — declines `plugins/soleur/test/c4-from-components.test.sh` on a commit that *did* change the
C4 producer, so a broken `/soleur:sync` producer reaches the PR instead of being caught before push.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The change
reads `git diff --name-only` and decides which local shell suites to execute. It writes no user
data, opens no network path, touches no credential.

**Brand-survival threshold:** `none`.

- `threshold: none, reason: the merge authority is CI, where the decline is unreachable by
  construction — the first two statements of _diff_touches return 0 unconditionally when
  SOLEUR_TEST_FORCE_ALL=1 or CI is set, before _diff_detect_ok or the match loop is reached. Both
  newly-gated suites have CI homes, so the worst case of a stale predicate is a slower, noisier PR
  — never a merged regression.`

**The two suites' CI protection is ASYMMETRIC, and that decides which AC is load-bearing.**
`.github/scripts/test/run-all.sh` has a **second, independent** CI home — the
`guard-script-fixture-tests` job in `.github/workflows/pr-quality-guards.yml`, running it directly
on `pull_request` + `merge_group` with no `paths:` filter, as a required context. The c4 suite has
**exactly one**: `bash scripts/test-all.sh scripts` in `ci.yml`'s `test-scripts` job. Its CI
coverage therefore rests entirely on the `CI` early return *inside the file this change edits* —
which is why **AC4 (the three helpers byte-identical to the merge base) is the load-bearing
criterion**. If those early returns were altered, the c4 suite would run in zero runners everywhere
at once and nothing outside this file would notice.

---

## Implementation Phases

### Phase 0 — Preconditions

0.1 `grep -c '_diff_touches "\${' scripts/test-all.sh` → `2` (the two existing gates).

0.2 Confirm every path about to be declared resolves as a pathspec, including the directory forms
(the linter uses exactly this call):

```bash
for p in plugins/soleur/scripts/generate-c4-from-components.ts plugins/soleur/lib \
         plugins/soleur/test/test-helpers.sh plugins/soleur/test/fixtures/component-docs \
         plugins/soleur/test/c4-from-components.test.sh .github apps/web-platform/infra \
         .github/scripts/test/run-all.sh scripts/lib/test-relevance-paths.sh; do
  git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 || echo "UNRESOLVED: $p"
done
```

Expected: no output. (Verified at plan time — all nine resolve.)

0.3 Re-verify the `.github` runner's dependency closure has not moved:
`grep -nE 'git -C "\$REPO_ROOT"|\$REPO_ROOT/[A-Za-z.]' .github/scripts/test/test-*.sh`. At plan
time only `test-infra-suite-registration.sh` and its mutations sibling read the real tree, both via
`git ls-files "${INFRA_PREFIX}/…"`. A third hit means the predicate needs a third element.

### Phase 1 — Declare the predicates

Edit `scripts/lib/test-relevance-paths.sh`.

**1a. Add a HOW-TO block at the top of the file.** Review found three of the declaration sites are
discoverable only by reading an archived plan. This is where a reader lands, so the trail belongs
here:

```bash
# HOW TO ADD A RELEVANCE GATE — five sites, all of them enforced (ADR-181 + its 2026-08-12 addendum):
#   1. Declare <NAME>_PATHS here, self-including the suite's own file AND this file.
#   2. Add "<NAME>_PATHS|<suite-file>" to RELEVANCE_ARRAYS in scripts/lint-orphan-test-suites.sh.
#   3. Wrap the run_suite call in scripts/test-all.sh with `if _diff_touches "${<NAME>_PATHS[@]}"`.
#   4. Give it a skip_suite else-arm — the decline must be a counted verdict, never an absence.
#   5. Ensure every path in 1 lives under a TEST_RELEVANCE_PREFIXES entry below; add the prefix if
#      not, or the untracked-file arm is blind to it. The linter now checks this.
# Sites 1-3 and 5 red in lint-orphan-test-suites.sh; site 4 reds in
# scripts/test-all-infra-coverage-notice.test.sh, behaviourally.
```

**1b. Update the header.** "Relevance predicates for the two heavy mutation batteries" and "sources
it at TOP LEVEL to guard two run_suite calls" both go stale at four arrays.

**1c. Declare the arrays**, following the file's comment discipline (why each element; what breaks
without it):

```bash
# plugins/soleur/test/c4-from-components.test.sh (test-all.sh, scripts shard) — ~429 s, the most
# expensive suite the local gate still runs unconditionally.
# Source of truth: the suite's own header — PRODUCER=, FIXTURES=, and the sourced test-helpers.sh.
#
# WHY THIS SET IS CLOSED where the two batteries above are not: the suite NEVER reads the real
# tree. seed() builds throwaway roots under $TMPDIR from $FIXTURES and the producer takes its root
# from process.argv[2], so the dependency set is its subject plus its own inputs.
#
# lib/ IS A DIRECTORY, deliberately. The producer imports one file from it today
# (`from "../lib/c4-from-components"`, which itself has zero relative imports); a second import
# tomorrow would be invisible to a file-level declaration until someone edited this array.
# Measured: the directory form costs nothing — 96 % skip either way, because plugins/soleur/lib/
# appears in 1 of the last 80 commits on main.
#
# KNOWN LIMIT — a LOWER BOUND, not a closed set, exactly as the cf-tunnel block above says of
# itself. Two real dependencies are deliberately NOT declared: `.bun-version` (run_producer invokes
# `bun "$PRODUCER"`) and the likec4@1.50.0 pin, which lives in three places (package.json,
# apps/web-platform/Dockerfile, the ci.yml install step) and none of them here. Declaring them
# would arm this suite on every toolchain bump for no added signal, and the window is bounded three
# ways: the pin trio has its own UNGATED guard (apps/web-platform's c4-likec4-version-pin.test.ts),
# the suite DEGRADES rather than fails when the CLI is unreachable, and CI runs everything.
#
# NOTE the degrade cuts BOTH ways: it is a mitigation here and a hazard in the epilogue, because
# the re-run command this gate prints can exit 0 having rendered nothing. Recorded in the ADR
# addendum so the next reader does not have to rediscover it.
C4_PRODUCER_PATHS=(
  "plugins/soleur/scripts/generate-c4-from-components.ts"  # PRODUCER (the SUT wrapper)
  "plugins/soleur/lib"                                     # its import closure — directory, see above
  "plugins/soleur/test/test-helpers.sh"                    # sourced; absence is a hard abort
  "plugins/soleur/test/fixtures/component-docs"            # the four seeded corpora — directory
  "plugins/soleur/test/c4-from-components.test.sh"         # SELF
  "scripts/lib/test-relevance-paths.sh"                    # THIS FILE
)

# .github/scripts/test/run-all.sh (test-all.sh) — ~95 s. A nested RUNNER, so the predicate covers
# what its ten fixture suites depend on, not just the runner.
#
# apps/web-platform/infra IS LOAD-BEARING AND WAS NOT OBVIOUS. test-infra-suite-registration.sh
# derives its expected set from `git ls-files "${INFRA_PREFIX}/*.test.sh"` against the REAL tree, so
# a commit ADDING an infra suite without registering it in infra-validation.yml is exactly the diff
# that must run this runner — and a `.github`-only predicate would have declined it.
GITHUB_SCRIPTS_SUITE_PATHS=(
  ".github"                                                # the SUTs, the suites, and the workflows they derive from
  "apps/web-platform/infra"                                # the real-tree read above — directory
  ".github/scripts/test/run-all.sh"                        # SELF. Dead for MATCHING (".github" already
                                                           # covers it) — present because the linter's
                                                           # self-inclusion check reads this array.
  "scripts/lib/test-relevance-paths.sh"                    # THIS FILE
)
```

**1d. Add `plugins/soleur` to `TEST_RELEVANCE_PREFIXES`.** Without it the untracked arm
(`git ls-files --others --exclude-standard -- "${TEST_RELEVANCE_PREFIXES[@]}"`) is blind to a
brand-new *uncommitted* fixture corpus, so a session that adds one and runs the gate before
committing has the suite declined on the very diff that needed it. **Phase 3b's linter check is what
pins this** — a sandbox fixture cannot, because the seam replaces the whole blob (see Phase 3d).

### Phase 2 — Wire the two gates

**2a. The c4 suite, in place in the glob loop, with a LITERAL label.** In `scripts/test-all.sh`,
inside `for f in plugins/soleur/test/*.test.sh …`, before `run_suite "$f" bash "$f"`:

```bash
    # RELEVANCE-GATED (ADR-181), ~429 s — the only suite this loop registers whose cost justifies a
    # predicate. A per-file `if` rather than a lookup table: bash 3.2 has no associative arrays and
    # one gated member does not earn a mapping.
    #
    # The label is written LITERALLY, not as "$f". skip_suite's contract is "$1 = label (must match
    # the label the suite would have run under)" and the glob's label IS the path, so the two agree
    # byte-for-byte — TEST_TIMING_LOG rows and any anchored reader stay stable.
    #
    # An `if` block, never `[[ … ]] && continue`: _diff_touches's own header forbids the short form
    # because under `set -e` its exit status depends on the call site.
    if [[ "$f" == "plugins/soleur/test/c4-from-components.test.sh" ]]; then
      if ! _diff_touches "${C4_PRODUCER_PATHS[@]}"; then
        skip_suite "plugins/soleur/test/c4-from-components.test.sh" "relevance" \
          "bash plugins/soleur/test/c4-from-components.test.sh"
        continue
      fi
    fi
```

`run_suite "$f" bash "$f"` is left **byte-for-byte unchanged**, so the glob's discovery and #7402's
registration surface are untouched. An earlier draft hoisted the suite out of the loop; that was cut
with the pairing check that motivated it (see the Cut List). A rename of the suite file is caught
either way — the array self-includes it and the linter's `git ls-files --error-unmatch` reds.

**2b. The nested runner.** Replace the unconditional registration with the ADR-181 if/else,
preserving the command shape `run_suite … bash .github/scripts/test/run-all.sh` that
`REQUIRED_RUNNERS` anchors on:

```bash
  if _diff_touches "${GITHUB_SCRIPTS_SUITE_PATHS[@]}"; then
    run_suite ".github/scripts/test/run-all.sh" bash .github/scripts/test/run-all.sh
  else
    skip_suite ".github/scripts/test/run-all.sh" "relevance" \
      "bash .github/scripts/test/run-all.sh"
  fi
```

Extend the existing `MIN_SUITES` floor comment with one sentence: the floor still applies whenever
the runner runs, and a **decline is a different outcome from an empty run** — the floor is not
evaluated at all when the suite is declined, and `skip_suite`'s output is what distinguishes them.

**2c. Print the force-all lever once, when anything was declined.** `SOLEUR_TEST_FORCE_ALL` appears
exactly once in the whole runner — inside `_diff_touches`'s early return — and is printed **nowhere**.
Before this change a docs-only run declined one suite; after it, five. A developer wanting full
coverage must run five commands by hand or already know an undocumented variable, while the infra
runner advertises its own lever (`Set SOLEUR_INCIDENT_SKIP=1 …`) in two places. In the epilogue,
guarded by `if (( skipped > 0 ))` beside the existing breakdown line:

```bash
  echo "      To run everything regardless of the diff:"
  echo "        SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh"
```

This is the only addition outside the gate mechanism, and it serves the issue's own contract
directly: a decline is only safe while it stays actionable. It touches the epilogue, not the three
helpers AC4 pins.

### Phase 3 — Extend the gate harness (`cq-write-failing-tests-before`)

`scripts/test-all-infra-coverage-notice.test.sh` is already the ADR-181 gate harness in everything
but its filename. **Extend it; do not fork it.** Review found that forking would have duplicated
`build_sandbox`, `run_gate_arm` and the assertion floor for ~300 lines, and would have added an
ungated, sandbox-spawning suite to the very shard this plan optimises.

**3a. Replace the two `*_LABEL` scalars with a table, and drive every existing loop from it:**

```bash
GATED=(
  "tests/scripts/registry-gate-mutation-battery|REGISTRY_BATTERY_PATHS"
  "scripts/cf-tunnel-liveness-gate-mutations|CF_TUNNEL_BATTERY_PATHS"
  "plugins/soleur/test/c4-from-components.test.sh|C4_PRODUCER_PATHS"
  ".github/scripts/test/run-all.sh|GITHUB_SCRIPTS_SUITE_PATHS"
)
```

The `RECORDED_SUITE:` greps in `run_gate_arm`, the `check_element_arms` calls, and the
`docs-only`/`force-all`/`ci-set`/`undeterminable`/`rename-old-path`/denominator arms all become
loops over `GATED`. **This is the completeness half, and it is not optional:** the file's own
`COMPLETENESS: every declared predicate path must actually ARM its battery` comment explains that
the linter's checks cannot see a path silently *removed*, because a shorter list satisfies all five.
Without driving `check_element_arms` from the new arrays, `C4_PRODUCER_PATHS` could be trimmed to
`{self, THIS FILE}` with the linter and the harness both green — and a PR editing only the C4
producer would then decline the suite that exists to test it.

**3b. `MIN_ASSERTIONS` gains `+ ${#C4_PRODUCER_PATHS[@]} + ${#GITHUB_SCRIPTS_SUITE_PATHS[@]}`**,
keeping its "DERIVED, not a hand-typed integer" property. Today that expression enumerates two of
the four arrays; leaving it would reproduce, twenty lines below Phase 4d, the exact
enumerated-vs-structural defect Phase 4d exists to fix.

**3c. Add the one genuinely new fixture arm.** `check_element_arms` feeds each declared element
*literally*, so a directory element proves substring matching on the directory string but not on a
child path. Add `run_gate_arm dir-child 'plugins/soleur/lib/anything.ts'` and assert the c4 suite
runs — the only assertion in the cut Phase-1 draft that the existing harness did not already buy.

**3d. Add two SOURCE ANCHORS, because the seam cannot express these properties.**
`build_sandbox` injects `[[ -n "${SANDBOX_DIFF_NAMES:-}" ]] && _diff_names="$SANDBOX_DIFF_NAMES"`
**after** the four-source assembly, replacing the blob wholesale. So a fixture arm proves that
`grep -qF` works — it cannot prove the assembly fed it. The file already knows this and pairs its
rename fixture with `grep -qE '^\$\(git -c core\.quotePath=false diff --name-status -M ' "$TARGET"`,
commenting *"Without the second, deleting the `--name-status` invocation leaves this fixture green."*
Mirror that precedent:

- the untracked arm's assembly line is anchored (`git ls-files --others --exclude-standard --
  "${TEST_RELEVANCE_PREFIXES[@]}"` still present in `$TARGET`), **and**
- `plugins/soleur` is asserted present in `TEST_RELEVANCE_PREFIXES` — belt to Phase 4c's braces,
  since without either, deleting the Phase 1d line leaves every arm green.

**3e. Widen the file's header comment** to name its real scope (the infra coverage claim **and** the
ADR-181 relevance gate). The filename already under-describes the file at HEAD. Renaming was
rejected: it churns the `run_suite` registration and breaks `git log` continuity for no property
gained.

Run it: the new arms must FAIL before Phase 4.

### Phase 4 — Linter fixes, each buying a property nothing else buys

Sub-steps run in the order written. Edit `scripts/lint-orphan-test-suites.sh` for 4a–4c;
**4d edits a different file** and is last for that reason.

**4a. Extend `RELEVANCE_ARRAYS`:**

```bash
    "C4_PRODUCER_PATHS|plugins/soleur/test/c4-from-components.test.sh"
    "GITHUB_SCRIPTS_SUITE_PATHS|.github/scripts/test/run-all.sh"
```

All **five** existing per-array checks — declared, non-empty, every path resolves, self-inclusion,
de-reference anchor — then apply to the new arrays for free.

**4b. A DERIVED dispatch floor on `RELEVANCE_ARRAYS`.** Today `RELEVANCE_ARRAYS=()` makes the entire
anti-rot block iterate zero times while the script prints `orphan test suites: none`. Do **not** use
a hand-typed `4`: the neighbouring `MIN_ASSERTIONS` comment rejects exactly that (*"a fixed literal
acquires slack every time a list grows"*), and a literal floor is a number someone must remember to
raise, with no trail. Derive it from the runner:

```bash
  # DERIVED from the runner, not a literal — so it needs no bumping and catches TWO failures for
  # one line: RELEVANCE_ARRAYS emptied (every check below passes over nothing while gated suites
  # decline forever), AND a gate added to test-all.sh but never registered here, which a literal
  # floor cannot see at all.
  want=$(grep -cE '_diff_touches "\$\{[A-Z_]+\[@\]\}"' "$RUNNER")
  if (( ${#RELEVANCE_ARRAYS[@]} < want )); then
    echo "ERROR: RELEVANCE_ARRAYS has ${#RELEVANCE_ARRAYS[@]} entries but test-all.sh has ${want} _diff_touches gates -- an unregistered gate rots unchecked, and an emptied list makes every check below pass over nothing." >&2
    fails=$((fails + 1))
  fi
  # `${a[@]+"${a[@]}"}` for the SAME reason the EXCLUSIONS loop above already carries it: under
  # `set -u` on bash 3.2 an EMPTY array under `[@]` aborts. Without it the floor's message is
  # followed two lines later by an `unbound variable` crash, so the mutation exits non-zero for a
  # reason unrelated to the check being tested.
  for entry in ${RELEVANCE_ARRAYS[@]+"${RELEVANCE_ARRAYS[@]}"}; do
```

**4c. A `TEST_RELEVANCE_PREFIXES` coverage check.** `scripts/lib/test-relevance-paths.sh` states the
invariant in prose — *"the union of the top-level prefixes every declared path lives under"* — and
**nothing enforces it**. That is the exact defect class this change introduces: declare an element
outside the prefixes, the untracked arm goes blind for it, and a session adding an untracked file
there has the suite declined on the diff that needed it. Inside the per-array loop:

```bash
    for p in "${rel_elems[@]}"; do
      covered=""
      for pre in "${TEST_RELEVANCE_PREFIXES[@]}"; do [[ "$p" == "$pre"* ]] && covered=1; done
      if [[ -z "$covered" ]]; then
        echo "ERROR: ${arr_name} declares '${p}', which lives under no TEST_RELEVANCE_PREFIXES entry -- an UNTRACKED file there is invisible to the predicate, so the suite declines on the diff that adds it." >&2
        fails=$((fails + 1))
      fi
    done
```

This is the only guard in the plan that buys a property no existing mechanism buys, and it is what
makes Phase 1d enforced rather than remembered — permanently, for every future gate.

**4d. Re-point the CI-decline assertion from enumerated to structural** (in
`scripts/test-all-infra-coverage-notice.test.sh`). At the anchor `a CI run declines neither
battery`, the check names its members:
`grep -qE "^\[skip\] ($REGISTRY_LABEL|$CFTUNNEL_LABEL) "`, with a comment stating *"the two
batteries have no other CI home at all"*.

**The c4 suite is exactly that category.** Leaving the assertion enumerated makes it cover 2 of 3
qualifying suites while its comment silently becomes false. Replace the member list with the
**property**: under `CI=1`, **no** `[skip] … (relevance)` line may appear at all. Verified sound —
in the `ci-set` arm the sandbox runs `TEST_GROUP=all`, `SOLEUR_INCIDENT_SKIP=0`, `_infra_in_diff=0`,
so the only decline present is the infra runner's `not_in_diff`; `incident` requires
`SOLEUR_INCIDENT_SKIP=1`; and `group` never reaches `skip_suite` at all. The reason strings
discriminate, so the structural form excludes the legitimate infra decline by *reason* rather than
by naming members, and covers every future gated suite for free.

Two mechanics: capture `CI_GATE_OUT="$GATE_OUT"` immediately after the `ci-set` arm and assert
against that — the existing check consumes whatever the *last* arm left in `GATE_OUT` and is correct
today only by arm ordering, which the widened surface makes fragile. And the `MIN_FIXED` delta is
**zero unless a second assertion is genuinely added** — this step replaces one fixed assertion with
one, so "bump it" would install a false floor.

### Phase 5 — GREEN and the mutation matrices

`bash scripts/test-all-infra-coverage-notice.test.sh` and `bash scripts/lint-orphan-test-suites.sh`
must both pass. Execute both matrices below, reverting between rows and confirming green after the
last revert. Amend ADR-181 with the `## Addendum — 2026-08-12 (#7494)` section.

### Phase 6 — Verification and the deferral (a phase, not an AC)

Review found four acceptance criteria asserting post-conditions no phase produced. They are steps:

6.1 **Re-replay the skip rates** with `grep -F`-over-blob semantics matching the runtime matcher,
for each predicate **as actually declared**; record as ceilings.

6.2 **Time both suites in isolation**, capturing the c4 run's render markers (`status=ok`,
`relationships=3`, and the absence of `reason=likec4-unavailable`).

6.3 **Run the full gate explicitly**: `bash scripts/test-all.sh`. Not lefthook — its `bun-test` job
is globbed to `*.{ts,tsx,js,jsx}` and this PR touches only `.sh` and `.md`.

6.4 **File the deferral issue** for D3 with `gh issue create --label deferred-scope-out`, carrying
the D3 scoping, the 51 % counterfactual with its command, the dead-trigger note, both unsoundness
findings, D5's runtime observation, **the unresolved file-partition question** (whether the ~60
`server/inngest/cron-*.test.ts` files move into the new vitest project — it decides whether the 51 %
ceiling holds), and a back-reference to `#7494`. Then write its number into the ADR addendum's
Alternatives row and into this plan's D3.

---

## Guard Contract

Both matrices exercise **only logic this change introduces**. An earlier draft carried sixteen rows;
eleven mutated *data* to confirm that unchanged, already-mutation-proven code still ran — a loyalty
oath, not verification. AC4 pins the unchanged helpers independently.

### Guard 1 — relevance-predicate anti-rot (`scripts/lint-orphan-test-suites.sh`)

**Property.** Every gate in `scripts/test-all.sh` has a registered predicate array; every array is
non-empty, resolves, self-includes its suite, is consumed by a `_diff_touches` call, and declares
only paths the untracked-file arm can actually see.

**Assembly.** Structural, not a member snapshot: the chokepoint is the `for entry in
"${RELEVANCE_ARRAYS[@]}"` loop, crossed with the **five** sites a gated suite is named at — the
array, the `RELEVANCE_ARRAYS` mapping, the `_diff_touches` call, the `skip_suite` else-arm, and
`TEST_RELEVANCE_PREFIXES`. Enumerating it produced three findings: the loop had **no floor of its
own**; the prefixes invariant was **enforced by nothing**; and the `skip_suite` else-arm is
**already asserted behaviourally** by `fail "the registry battery was declined silently"`, which
proves the skip *fires with the right label* rather than that a regex matches somewhere in the file.

**Mutation matrix.** Every row must drive `bash scripts/lint-orphan-test-suites.sh` non-zero **with
its own named message** (not merely non-zero — see 4b's bash-3.2 note); green again after revert.

| # | Mutation | Property tested |
|---|---|---|
| M1 | `RELEVANCE_ARRAYS=()` | **the guard's own dispatch** — today this exits 0 and prints `orphan test suites: none` over zero checks |
| M2 | Add a fifth `if _diff_touches "${SOME_NEW_ARRAY[@]}"` gate to `test-all.sh` with no `RELEVANCE_ARRAYS` entry | the floor is **derived**, so it catches an unregistered gate — which a literal `4` cannot see at all |
| M3 | Add `"docs/whatever.md"` to `GITHUB_SCRIPTS_SUITE_PATHS` — the **second** new array, after a compliant first | the prefix-coverage check, and that the loop does not stop at the first compliant entry |
| M4 | Delete `plugins/soleur` from `TEST_RELEVANCE_PREFIXES` | the same check from the other side: it must red because `C4_PRODUCER_PATHS`'s elements are then uncovered. This is what pins Phase 1d — a sandbox fixture cannot (Phase 3d). |

M1 is exercised **against the linter only**. Run against a full `test-all.sh`, an empty array makes
`_diff_touches "${C4_PRODUCER_PATHS[@]}"` abort the runner under bash 3.2 `set -u` — a runner crash,
not a guard verdict, and scoring it as one would be the wrong-property error this matrix prevents.

### Guard 2 — the gate effect (`scripts/test-all-infra-coverage-notice.test.sh`)

**Property.** A relevance-gated suite executes if and only if the run's `_diff_names` blob matches
at least one of its declared paths; when it does not execute, the run announces it, counts it, and
prints a command that recovers it.

**Assembly.** The chokepoint is `_diff_touches()` plus the `_diff_names` blob. **The blob has four
sources and the sandbox seam replaces it wholesale**, so a fixture arm pins the *matcher* and only a
source anchor pins the *assembly* — the existing rename arm already ships both halves, and Phase 3d
adds the untracked pair. What this change adds to the assembly is the `GATED` table: after 3a the
harness quantifies over gated suites structurally rather than naming two.

**Mutation matrix.** Every row must drive `bash scripts/test-all-infra-coverage-notice.test.sh`
non-zero; revert and re-green after each.

| # | Mutation | Property tested |
|---|---|---|
| N1 | `GATED=()` | **the guard's own dispatch** — every loop below it would pass over nothing |
| N2 | Delete the c4 gate's `skip_suite` else-arm, leaving the bare `continue` | the decline is announced and counted for the **new** suite — the else-arm property, now covered by the table rather than two hard-coded labels |
| N3 | Anchor `_diff_touches`'s match (`grep -qF` → `grep -qxF`) | the `dir-child` arm (3c) — a directory pathspec must match a child path, which is the entire basis of the "closed by construction" claim |
| N4 | Trim `C4_PRODUCER_PATHS` to `{self, THIS FILE}` | **the completeness half** (3a) — the linter's five checks all still pass on a shorter list, so only the array-driven `check_element_arms` loop catches a silently removed path |
| N5 | Drop `apps/web-platform/infra` from `GITHUB_SCRIPTS_SUITE_PATHS` — the **second** new gate, leaving c4 correct | `check_element_arms` quantifies over all four gates, not the first; and pins the one non-obvious element in that predicate |
| N6 | Delete the `git ls-files --others` line from the `_diff_names` assembly | the Phase 3d source anchor — a fixture arm cannot see this, because the seam replaces the blob |

---

## Observability

```yaml
liveness_signal:
  what: "the [skip] blocks, the BREAKDOWN line, and the force-all lever emitted by scripts/test-all.sh"
  cadence: "every local full-gate run, plus main-health-monitor's TEST_GROUP=all run every 6h (where declines are unreachable, so a relevance skip there is itself the anomaly)"
  alert_target: "the operator's terminal and the run's TEST_TIMING_LOG; no paging surface — this is a developer-local runner"
  configured_in: "scripts/test-all.sh — skip_suite(), the '=== N suites: … skipped (declined — not relevant to this diff) ===' breakdown, and the Phase 2c lever"
error_reporting:
  destination: "stderr plus a non-zero exit from scripts/lint-orphan-test-suites.sh. It is registered as a SUITE inside test-all.sh (run_suite scripts/lint-orphan-test-suites), which is what makes it BLOCKING via the required test aggregator. NOT lefthook — `grep -c orphan lefthook.yml` is 0. The standalone ci.yml step of the same name lives in lint-bot-statuses, which that job's own comment marks ADVISORY, NOT BLOCKING."
  fail_loud: true
failure_modes:
  - mode: "a predicate goes stale (a declared path is renamed) and the suite is declined locally forever"
    detection: "lint-orphan-test-suites.sh — git ls-files --error-unmatch over every declared element"
    alert_route: "non-zero exit in the test-scripts CI shard (blocking) and in the local gate"
  - mode: "RELEVANCE_ARRAYS emptied, or a gate added to test-all.sh but never registered"
    detection: "the Phase 4b derived dispatch floor (new)"
    alert_route: "same routes"
  - mode: "a declared path lives outside TEST_RELEVANCE_PREFIXES, so the untracked arm is blind to it"
    detection: "the Phase 4c prefix-coverage check (new)"
    alert_route: "same routes"
  - mode: "a predicate path is silently REMOVED — a shorter list satisfies all five linter checks"
    detection: "the array-driven check_element_arms loop (Phase 3a) and the derived MIN_ASSERTIONS floor (3b)"
    alert_route: "same routes"
  - mode: "a gate's skip_suite else-arm is deleted, silently removing the suite from the denominator"
    detection: "test-all-infra-coverage-notice.test.sh — the 'declined silently' assertion, now table-driven over all four gates"
    alert_route: "same routes"
  - mode: "a predicate is too narrow, so a relevant diff declines its suite"
    detection: "not detectable by the linter by construction; bounded by CI running everything and by each array self-including its suite. For the c4 suite that bound is test-all.sh itself — its only CI home — which is why AC4 is load-bearing"
    alert_route: "CI red on the PR — the merge gate, not the local gate"
logs:
  where: "TEST_TIMING_LOG (labelled field 3: skip=relevance), stdout of the run"
  retention: "per-run; not persisted off the workstation"
discoverability_test:
  command: "bash scripts/lint-orphan-test-suites.sh"
  expected_output: "orphan test suites: none"
```

---

## Acceptance Criteria

Six. An earlier draft carried fourteen; the cut ones asserted that a transcript was pasted into a PR
body, that a repo-wide workflow gate applied, or that the implementer had done what the plan says —
receipts, not post-conditions. Four that named real work were promoted to Phase 6, where a step
produces them.

### Pre-merge (PR)

1. **AC1 — the linter is green and its two new checks are real.**
   `bash scripts/lint-orphan-test-suites.sh` prints `orphan test suites: none`, and all four Guard 1
   rows redden it with their own named messages, green again after each revert.
2. **AC2 — the harness is green, table-driven, and complete.**
   `bash scripts/test-all-infra-coverage-notice.test.sh` passes with `MIN_ASSERTIONS` satisfied by
   the grown set; all six Guard 2 rows redden it; and
   `grep -c 'REGISTRY_LABEL\|CFTUNNEL_LABEL' scripts/test-all-infra-coverage-notice.test.sh || true`
   returns `0` — the enumerated labels are gone.
3. **AC3 — the measurement is valid.** The c4 timing output contains `status=ok` and
   `relationships=3` and does **not** contain `reason=likec4-unavailable` (that degraded path exits
   in seconds, so without this the 429 s figure could be a measurement of the wrong thing), and the
   re-replayed skip rates are recorded as ceilings. **No AC gates on wall-clock** — a sibling
   worktree can inflate it (ADR-181 Decision 5 records a measured 1.9× inflation), so a numeric bar
   would measure the machine rather than the change
   (`cq-ac-must-not-depend-on-concurrent-sessions`).
4. **AC4 — no new mechanism.** The three helpers ADR-181 established are byte-identical to the
   **merge base** and no fourth is introduced. Against the merge base, not `origin/main`'s tip —
   three issues are open against this file, so main moving is the expected case, and a two-dot
   comparison would report an unrelated commit as `CHANGED:`. Assert the **bodies**, not the
   definition lines — a changed body does not touch `^name() {`:

   ```bash
   BASE=$(git merge-base origin/main HEAD)
   body() {  # flag-based, NOT awk's /a/,/b/ range (it self-matches on the first line)
     git show "$1:scripts/test-all.sh" \
       | awk -v fn="$2" 'index($0, fn "() {")==1{f=1} f{print} f && /^\}$/{exit}'
   }
   for fn in run_suite skip_suite _diff_touches; do
     diff <(body "$BASE" "$fn") <(body HEAD "$fn") || echo "CHANGED: $fn"
   done
   git diff "$BASE"...HEAD -- scripts/test-all.sh | grep -cE '^\+[a-z_]+ *\(\) *\{' || true   # -> 0
   ```

   Expected: no `CHANGED:` lines and a final `0`. `|| true` because `grep -c` exits 1 on a zero
   count, which would abort a `set -e` script. The trailing `grep` is a smoke test, not a proof —
   the body diffs are the proof.
5. **AC5 — dogfood shows both new suites running.** The Phase 6.3 full-gate run is green and its
   output shows both newly-gated suites **running**: this PR edits
   `scripts/lib/test-relevance-paths.sh`, which both arrays declare, so both predicates must match
   their own PR.
6. **AC6 — the c4 suite is registered exactly once, still by the glob.**
   `grep -cE '^[[:space:]]*run_suite "plugins/soleur/test/c4-from-components' scripts/test-all.sh || true`
   returns `0` (no explicit registration was added) and the glob loop's `run_suite "$f" bash "$f"`
   line is unmodified — the suite is still discovered by the glob, gated in place.

### Post-merge

None. The change is inert until the next local `scripts/test-all.sh` invocation, and CI behaviour is
unchanged by construction.

---

## Decisions

### D1 — Extend ADR-181's mechanism; invent nothing

Every property except P1 is already implemented. What ships: two arrays, one prefix, two `if/else`
wirings, one epilogue lever, two `RELEVANCE_ARRAYS` entries, two linter checks that each buy a
property nothing else buys, one structural re-point of an existing assertion, and a table that makes
the existing harness quantify over gates instead of naming two.

### D2 — Directory pathspecs over file enumerations, where free

`plugins/soleur/lib` and `.github` are declared as directories: a directory is closed under future
additions, a file list is a snapshot that rots on the next arrival. Measured cost: zero.

### D3 — Do NOT gate `apps/web-platform` (measured refusal, tracked as a sized deferral)

1. **The payoff is 7 %.** Its honest predicate is reached by 74 of the last 80 commits, because the
   suite contains genuine repo-wide parity guards (`plugin-path`, `plugin-root-anchoring`,
   `context-queries-shell-parity`, `sentry-monitor-iac-parity`, `github-app-manifest-parity`, ~60
   `server/inngest/cron-*`, `c4-render`, `legal-doc-shas-guard`). Expected saving ≈ 36 s/run, for
   the largest fail-open surface in the change.
2. **The issue's proposed lever does not exist.** `--shard=K/N` partitions the collected file set
   arithmetically; it cannot select by path.
3. **The sound-looking alternative is unsound.** Deriving a "repo-wide guard" subset by grepping the
   1098 test files for repo-root path literals over-matches catastrophically: `knowledge-base/x.md`,
   `knowledge-base/book.pdf` and 40+ siblings are **synthetic in-memory fixture paths** in the app's
   own document model. A grep cannot tell them from `knowledge-base/product/roadmap.md`, a real
   read. Vitest's `--related` walks the *import* graph, and the parity guards reach their subjects
   via `readFileSync`, so it would miss exactly the tests that matter. A hand-curated list is the
   drifting identifier set this plan's Guard Contract exists to reject — on the largest suite in the
   repo, where an error silently drops 949 files of coverage behind a green.

**Sized and actionable, not floored on a number that cannot move.** A first draft set the trigger at
"the honest whole-suite skip rate rises above 40 %". That is **dead by construction** — the union
rate is pinned near 7 % *by* the parity guards — and is recorded here so nobody re-derives it.
Naming a floor that cannot fire is how a refusal quietly becomes permanent. The live number is the
counterfactual: **41/80 = 51 %** of commits touch no `apps/web-platform/` file. So the follow-up is
concrete work, not a wait:

> Relocate the repo-wide parity guards into a dedicated vitest **project** with its own explicit
> `include:` glob — making the subset *structural* rather than grep-heuristic — then gate the
> remaining app-local project on `apps/web-platform`. Measured ceiling: 51 % skip against the
> app-local share of 516 s.

Two things the deferral issue must carry as **open questions**, not as settled numbers: the
app-local share of the 516 s was never measured, so any "~200 s/run" estimate is unmeasured; and
whether the ~60 `server/inngest/cron-*.test.ts` files belong in the new project is what decides
whether the 51 % ceiling holds at all. Phase 6.4 files both.

**What this does not address, stated plainly.** The issue's second argument was
contention-induced false RED. A 7 %-hit-rate gate does not narrow that window; the correct layer is
the advisory lock, open as **#7484**.

### D4 — Gate the c4 suite in place, with a literal label

An earlier draft hoisted it out of the glob loop and added a `REQUIRED_RUNNERS` entry, on the
grounds that a *variable* `skip_suite "$f"` label would dilute the linter pairing check's anchor.
Both were cut: the pairing check itself was cut (broken and redundant — see the Cut List), and
nothing requires the variable in the first place. Writing the literal inside the loop gives the same
uniform shape with no hoist, no exclusion/registration pair to keep in sync, no new zero-runners
window to close, and no `REQUIRED_RUNNERS` entry. It also avoids adopting the shape the adjacent
registry gate's comment forbids (*"no path literal may appear on a `run_suite` line"*) — a conflict
the hoist would have created without explanation. The rename concern that motivated the hoist is
answered identically in both shapes: the array self-includes the suite path and the linter's
`git ls-files --error-unmatch` reds on a renamed element.

### D5 — Not asked here: why the suite costs 429 s

Gating makes the suite run *less often*; it still costs seven minutes **on exactly the diffs that
touch the producer** — the runs where fast feedback matters most. `c4-from-components.test.sh` is
141 lines and calls `run_producer` six times, each spawning `bun` plus a `likec4` render (~70 s
each); two of the six exist solely to prove determinism by comparing two consecutive outputs, which
is ~140 s, over 30 % of the suite. Reducing that is out of scope here and is recorded on the
deferral issue (Phase 6.4) so the observation is not lost — a plan with a measurement section should
not route around a cost without noticing it is routing around it.

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| A new predicate is too narrow → a relevant diff declines its suite | Low | Both arrays self-include; both are dominated by directory pathspecs; CI runs everything; the six-hourly monitor's full run |
| A predicate path is silently **removed**, which all five linter checks tolerate | Medium | Phase 3a drives `check_element_arms` from the new arrays; N4 proves it |
| The enumerated CI-decline assertion silently narrows to 2-of-3 qualifying suites | **High if unaddressed** | Phase 4d replaces the member list with the property; AC2 proves the labels are gone |
| The sandbox seam replaces `_diff_names` wholesale, so fixture arms pin the matcher and not the assembly | Certain | Phase 3d adds source anchors for the untracked line and the `plugins/soleur` prefix, mirroring the existing `--name-status -M` precedent; N6 proves it |
| The 96 %/56 % figures overstate the saving | Certain, bounded | Restated as ceilings everywhere; Phase 6.1 re-replays with runtime semantics |
| The c4 suite self-SKIPs when `likec4` is unreachable, so a naive `time` measures the degraded path — and the printed re-run command can exit green having rendered nothing | Medium | AC3 requires render markers; the degrade's dual nature is recorded in the array comment and in ADR addendum item 3 |
| `.bun-version` and the `likec4@1.50.0` pin trio are real c4 dependencies the predicate does not declare | Low, disclosed | `KNOWN LIMIT` paragraph mirroring the cf-tunnel precedent; bounded by the ungated `c4-likec4-version-pin.test.ts`, the clean degrade, and CI |
| Adding `plugins/soleur` to `TEST_RELEVANCE_PREFIXES` widens the untracked arm for the two existing batteries | Certain, intended | The arm only **adds** names to `_diff_names`, which can only make a gate more likely to RUN — the fail-safe direction, already documented at the `WIDENED from` comment |
| `MIN_SUITES` inside the `.github` runner is not evaluated when the runner is declined | Low | Called out in Phase 2b's comment; bounded by the independent required `guard-script-fixture-tests` job |
| A developer with no resolvable `origin/main` pays the full run with no explanation printed | Low, pre-existing | Not fixed here (the NOTE lives under `if ! want_infra`); Phase 2c's lever at least tells them how to force the behaviour they are already getting |

---

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Agents invoked:** `cto` (Phase 2.5), the Phase 4.5 strong-model consult, and the plan-review panel
(`dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`)

**Assessment.** Build/test-infrastructure change confined to the local exit gate. The "CI is a
strict superset" claim **holds**, verified at `_diff_touches`'s two unconditional early returns, but
the protection is **asymmetric** and the plan now says so. Amending ADR-181 rather than minting a
new ADR was confirmed — though the *shape* was wrong and is now an append-only addendum. Carrying
the linter fixes in this PR was confirmed as correct scope: this is the change that doubles the
surface each gap leaves open.

**Findings folded in.** Review changed the plan's shape rather than polishing it. The panel
converged: both the simplification axis (dhh, code-simplicity) and the correctness axis (kieran,
architecture-strategist, spec-flow) fired on the same three scopes, so those were **deleted rather
than fixed**.

- **BLOCKING, found independently by four reviewers.** The proposed `skip_suite` pairing check
  cannot match either existing array — `RELEVANCE_ARRAYS` holds file paths, `skip_suite` takes
  display labels, and they differ. Verified: NO MATCH for both. It would have reddened a clean tree
  for two correctly-wired suites, and because the two new arrays coincidentally have `label == path`
  the failure would have read as real drift. Cut, along with the hoist, the `REQUIRED_RUNNERS`
  entry, four mutation rows and three ACs that existed only to support it.
- **BLOCKING (kieran, spec-flow).** The sandbox seam replaces `_diff_names` wholesale, so the
  rename-source and untracked arms — and the entire justification for the
  `TEST_RELEVANCE_PREFIXES` change — were asserted by nothing. Phase 3d adds source anchors and M4
  pins the prefix from the linter side.
- **BLOCKING (architecture-strategist).** The completeness half was missing: the linter's five
  checks all tolerate a *shorter* array, so only an array-driven `check_element_arms` catches a
  removed path. Phase 3a, N4.
- **HIGH (dhh, code-simplicity, independently).** The proposed new suite duplicated
  `scripts/test-all-infra-coverage-notice.test.sh` — which already carries every seam, whose
  `MIN_ASSERTIONS` floor grows with the arrays automatically, and which would have added an ungated
  sandbox-spawning suite to the shard being optimised. Cut; Phase 3 extends it.
- **HIGH (cto).** That file was missing from `## Files to Edit` entirely: its CI-decline assertion
  enumerates two labels under a comment the c4 suite falsifies. Phase 4d, AC2.
- **HIGH (dhh, code-simplicity).** Eleven of sixteen mutation rows exercised unchanged,
  already-mutation-proven code. Cut to ten rows testing only new logic.
- **HIGH (spec-flow).** The developer sees five `[skip]` blocks and `N-5/N`, not two — and
  `SOLEUR_TEST_FORCE_ALL` is printed nowhere. Phase 2c, and ADR addendum item 2.
- **MEDIUM (architecture-strategist).** The ADR edit shape was wrong (in-place, not an append-only
  dated addendum) and three consequences were missing: the `N-3/N` literal, that mitigation layer 3
  does not generalise to a degrading suite, and the five-site declaration contract.
- **MEDIUM (code-simplicity).** The literal cardinality floor became a **derived** one, catching an
  unregistered gate a literal cannot see, and needing no hand-maintained bump.
- **MEDIUM (code-simplicity).** The one guard genuinely worth adding — the
  `TEST_RELEVANCE_PREFIXES` coverage check — was missing. Phase 4c.
- **MEDIUM (kieran).** `git diff origin/main` compares against a *moving tip*; AC4 now uses the
  merge base. Also: `[[ … ]] && continue` is the shape `_diff_touches`'s own header forbids — Phase
  2a uses nested `if` blocks. Also: five per-array checks, not four.
- **MEDIUM (cto).** bash 3.2 `set -u` — the floor needed the `${a[@]+…}` guard or its mutation would
  exit non-zero via a crash rather than via the check.
- **MEDIUM (spec-flow).** Four ACs asserted post-conditions no phase produced. Promoted to Phase 6.
- **LOW (spec-flow).** The Observability block claimed lefthook runs the linter;
  `grep -c orphan lefthook.yml` is `0`, and the blocking route is the suite registration, not the
  advisory `lint-bot-statuses` step. Corrected — and recorded in Premise Validation, since it was a
  self-inflicted false claim.
- **LOW (spec-flow).** The plan's cost figures disagreed with the comments they would be written
  beside. Both are now given.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` and `## Files to Create`
matched nothing — every path is `scripts/*.sh` or a `knowledge-base/**.md` record.

---

## Files to Edit

- `scripts/lib/test-relevance-paths.sh` — the HOW-TO block (1a); refresh the stale header (1b); add
  `C4_PRODUCER_PATHS` and `GITHUB_SCRIPTS_SUITE_PATHS` with their why-comments and `KNOWN LIMIT`
  (1c); add `plugins/soleur` to `TEST_RELEVANCE_PREFIXES` (1d).
- `scripts/test-all.sh` — gate the c4 suite in place inside the glob loop with a literal label (2a);
  convert the `.github/scripts/test/run-all.sh` registration to the ADR-181 if/else and extend the
  `MIN_SUITES` comment (2b); print the force-all lever when `skipped > 0` (2c).
- `scripts/test-all-infra-coverage-notice.test.sh` — the `GATED` table driving every existing loop
  (3a); `MIN_ASSERTIONS` gains both new arrays (3b); the `dir-child` arm (3c); two source anchors
  (3d); widen the header (3e); re-point the CI-decline assertion structurally and pin
  `CI_GATE_OUT` (4d).
- `scripts/lint-orphan-test-suites.sh` — extend `RELEVANCE_ARRAYS` (4a); the derived dispatch floor
  and the `${a[@]+…}` guard (4b); the `TEST_RELEVANCE_PREFIXES` coverage check (4c).
- `knowledge-base/engineering/architecture/decisions/ADR-181-local-gate-declines-are-counted-verdicts.md`
  — a new append-only `## Addendum — 2026-08-12 (#7494)` carrying all seven items.

## Files to Create

**None.** The new suite an earlier draft proposed was cut in favour of extending
`scripts/test-all-infra-coverage-notice.test.sh`, whose assertion floor grows with the predicate
arrays automatically.

---

## Test Scenarios

Every scenario is *mutation → guard reddens*, or a gate arm in the harness — never *command →
terminal output*.

| # | Given | When | Then |
|---|---|---|---|
| T1 | a diff touching `plugins/soleur/lib/c4-from-components.ts` | the scripts shard runs | the c4 suite RUNS; `skipped` unchanged |
| T2 | a diff touching only `knowledge-base/project/plans/` | the scripts shard runs | the c4 suite is DECLINED; `[skip]` names it; the re-run command is `bash plugins/soleur/test/c4-from-components.test.sh`; `suites` includes it; `failed` unchanged |
| T3 | the T2 diff with `CI=1`, and separately with `SOLEUR_TEST_FORCE_ALL=1` | the scripts shard runs | the c4 suite RUNS — the decline is unreachable |
| T4 | a diff naming `plugins/soleur/lib/anything.ts` | the scripts shard runs | the c4 suite RUNS — the `dir-child` arm (3c), the only assertion the harness did not already buy |
| T5 | an `R100`-shaped rename row naming a declared path | the scripts shard runs | the c4 suite RUNS. **Fixture pins the matcher; the paired source anchor pins the assembly** — neither half is sufficient alone |
| T6 | the `git ls-files --others` line deleted from the assembly | the harness runs | RED via the Phase 3d source anchor — a fixture arm cannot see this |
| T7 | a diff adding `apps/web-platform/infra/new.test.sh` | the scripts shard runs | `.github/scripts/test/run-all.sh` RUNS — the read that made that prefix load-bearing |
| T8 | a diff touching only `todos/` | the scripts shard runs | `.github/scripts/test/run-all.sh` is DECLINED with its re-run command |
| T9 | `origin/main` unresolvable | the scripts shard runs | both new suites RUN (fail-SAFE) |
| T10 | any run with `skipped > 0` | the epilogue prints | `SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh` appears exactly once (2c) |
| T11–T14 | Guard 1 rows M1–M4, each in isolation and reverted | `bash scripts/lint-orphan-test-suites.sh` | non-zero with the row's named message; green after revert |
| T15–T20 | Guard 2 rows N1–N6, each in isolation and reverted | `bash scripts/test-all-infra-coverage-notice.test.sh` | non-zero; green after revert |

---

## Non-Goals

- **Gating `apps/web-platform`** — refused on measurement (D3); filed as a sized deferral (6.4).
- **Reducing the c4 suite's 429 s** — recorded in D5 and on the deferral issue, not folded in here.
- **Normalising the two existing `skip_suite` labels to their file paths.** Tempting once the
  label/path divergence is visible, but it would move `REGISTRY_LABEL`/`CFTUNNEL_LABEL` and anything
  anchored on those strings for no property gained — the pairing check that wanted the identity is
  cut.
- **Changing CI behaviour.** No workflow file is edited; declines remain unreachable under `CI`.
- **Touching `run_suite`, `skip_suite` or `_diff_touches`.** AC4 pins this; Phase 2c touches the
  epilogue, not the helpers.
- **#7484 (advisory-lock contention), #7402 (glob blind spots), #7429 (KILLED through wrappers).**
  Acknowledged, not folded in.

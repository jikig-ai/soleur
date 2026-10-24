# User-Impact Review — PR #10953 (feat-one-shot-10921-corrupt-ancestry-flake)

**Seat:** `soleur:engineering:review:user-impact-reviewer` — dispatched at aggregate-pattern
tier (explicit seat assignment; the definition's `single-user incident` gate is overridden by
the dispatch, and the meta-workflow enumeration branch applies: the diff modifies the
protective workflow itself, so the enumeration target is the *false-negative* surface — what
reaches a user if this gate fails open).

**Threshold confirmed:** plan §`## User-Brand Impact` declares `aggregate pattern`
(plan:397), with a challengeable decision line pointing at `decision-challenges.md` — where
the CTO ruling records `aggregate pattern` *on condition the diff does not drift into SUT
scripts*. Verified: `git diff --name-only origin/main...HEAD` touches zero files under
`.github/scripts/` outside `.github/scripts/test/` — `bump-inngest-bootstrap-pin.sh` and
`mint-inngest-bootstrap-tag.sh` are byte-identical (AC10 holds). **No re-rule triggered.**

**Settled-ruling check (all consistent — none contradicted):**

- forged-oid over repack-aware `rm`: implemented — `dead_oid` (blob-typed, never written),
  `corrupt_walk_break`, `corrupt_dead_tag` in `plugins/soleur/test/lib/git-corrupt-graph.sh`;
  all five `rm -f .git/objects/…` sites deleted.
- only walk-contract skip-eligible: construction invariants are fail-only/zero-counted at
  every site; the B7a peel is classified invariant-FAIL with an on-site comment per the
  dissent; only the `--merged`/`merge-base` walk-contract probes route to `corrupt_skip`.
- probe extended in this PR: `t5-skip-persistence-bound-7510.sh` gained a second
  event-sampled source + `g1b.`/`g2b.`/`fl.` markers + per-suite banner discriminators;
  monitor title/body/remediation generalized; fed-log rows added in `.test.sh`.
- tier aggregate pattern: no SUT drift (above).

**Section boilerplate check:** PASS — the section names a concrete artifact (g1b refusal
coverage over the inngest bootstrap image tenants run on), a concrete vector (silent coverage
loss → unrefused off-main-tag bump, #8747 shape), and a conditional-exposure statement. Not
rejected under the Step-5 criteria.

## Enumeration by user role

| # | Role | Artifact | Vector | Coverage |
|---|------|----------|--------|----------|
| 1 | Tenant operator | inngest bootstrap image digest (the bytes the fleet runs on) | silent loss of g1b.B7/B7a/B7c + g2b.I6 + fl.walk refusal coverage → a real off-main-tag anomaly merges unrefused (#8747) | mitigated — deterministic construction + fail-only invariants + counted/capped skip + Phase-3 monitor (see FINDING 1 for the load-bearing bound) |
| 2 | Tenant operator | same | all four bump rows skip simultaneously → `SKIPPED_ASSERTIONS=28` = `SKIP_CAP`, not `> cap` → suite stays GREEN with zero corrupt-walk coverage; mint `fl.walk` identical (3 = cap) | mitigated — intended ADR-188 design; the only in-window bound is the daily monitor + `::warning::` annotations (FINDING 1) |
| 3 | Tenant operator | same | walk-contract probe forced absent via `CORRUPT_WALK_PROBE_FORCE=skip` leaking into a workflow `env:` block → every row skips every run | mitigated — counted within cap, markers visible to monitor; only 'skip' is a wired value (other values flag via `fail()`) |
| 4 | Tenant operator | same | skip producer invisible to monitor (unregistered row name) | mitigated — roster-parity self-checks in both suites (call-site prefixes vs probe-registered `g1b.`/`g2b.`/`fl.`); probe `.test.sh` derives banner literals from the probe itself |
| 5 | Tenant operator | same | suite stops emitting rows entirely (row deleted, banner moved) | mitigated — `MIN_ASSERTIONS` floor + per-suite `=== test-*.sh ===` discriminator → TRANSIENT, never clean |
| 6 | Tenant operator | same | a sixth corrupt-walk site bypasses the chokepoint | mitigated within `.github/scripts/test/` (standing census); outside it — FINDING 2 |
| 7 | Tenant operator | same | monitor regression blinds the rehearsal source while widening | mitigated — per-source `observed`, never pooled; unreadable source = TRANSIENT + streak escalation |
| 8 | PR contributor | merge throughput / required check | fixture construction false-reds `guard-script-fixture-tests` → blocked merge, retry cost, alarm-fatigue reflex | mitigated — deterministic construction removes the store-layout class; invariant violations are loud FAILs |
| 9 | PR contributor | same | identical flake returns from the two unconverted sites | scope-outed in plan body (#10956) but NOT in the section — FINDING 2 |
| 10 | On-call operator | monitor alert fidelity | g1b/g2b/fl hit filed under rehearsal title/body → wrong remediation (pre-baked image) → longer coverage-degradation window | mitigated — title/body/verdict strings generalized + per-source FAIL lines name the arm family (workflow diff :233–:304) |
| 11 | On-call operator | same | selftest-poisoning — exercised `SKIP (loud):` reaches real streams → daily false FAIL → operators learn to ignore skip alerts, eroding the row-1 bound | mitigated — all selftest emissions captured to files; Guard-1 mutation row 8 pins it |
| 12 | On-call operator | same | pull_request-leg sampling counts unmerged-branch markers → pre-merge issue for a PR that may never land | scope-outed — acknowledged in plan §Dependencies & Risks ("real evidence, labelled by source"); loud noise, not silent harm |
| 13 | Developer / CI checkout | the developer's REAL repo object graph | `git -C ""` on an empty `<repo>` operand operates on cwd → forged objects written into a real clone | mitigated — `_corrupt_assert_repo` FATALs on empty operand + `assert_fixture_dir` when defined (`git-corrupt-graph.sh`:71–81) — the worst single-artifact hazard, closed |
| 14 | Run-page reader | `::warning::` annotation integrity | observed walk stderr echoed into the reason forges a second annotation line | mitigated — `%`→`%25`, CR/LF stripped in `corrupt_skip` before either stream |
| 15 | Suite integrity | anti-vacuity floor | skips erode the assertion count silently | mitigated — `TOTAL=PASS+FAIL+SKIPPED_ASSERTIONS` + `SKIP_CAP` ceiling in both suites; selftest asserts the fold |
| 16 | Packed-store runner | fixture validity | layout-dependence regresses via a non-`rm` construction the census cannot see | partial — FINDING 3 |
| 17 | Census guard | standing grep | `rm` line with `#` between verb and `.git/objects/` evades `[^#]*` | partial — FINDING 4 |

## Findings

```
[FINDING 1]
Artifact: g1b.B7/B7a/B7c + g2b.I6 + fl.walk refusal coverage over the inngest bootstrap pin
Vector:   full-skip green run — every corrupt-walk row skipping at once charges exactly
          SKIP_CAP (28 bump / 3 mint), which is NOT `> cap`, so the required check stays
          green while the entire #8747-class refusal coverage is absent. The design makes
          the Phase-3 monitor the SOLE cross-run bound on the plan's own named worst case.
Plan section coverage: mitigated — per-suite `=== test-*.sh ===` discriminators (verified:
          run-all.sh:176 emits them), per-source `observed >= 1` never pooled, TRANSIENT
          streak escalation, `::warning::` per skip. No hole — but this is the single
          load-bearing component of the entire user-harm model; any future edit to the
          t5 probe or monitor workflow IS a user-impact change and must re-run this seat.
Recommendation: none blocking. Keep the monitor's per-source FAIL lines naming the arm
          family (they do) and treat any future probe edit as threshold-relevant.
```

```
[FINDING 2]
Artifact: required-check reliability (the `test` check via scripts/ci-pr-selection.test.sh:432;
          infra-validation via apps/web-platform/infra/workspaces-luks-loopback.test.sh:868)
Vector:   the IDENTICAL rm-the-loose-object flake stays live at two sites outside
          `.github/scripts/test/` — a packed-store runner false-reds a required check the
          same way #10921 did, and re-trains the "red fixture = environment noise" reflex
          the plan itself names as the deeper harm.
Plan section coverage: scope-outed in Guard Contract (:452) and Dependencies & Risks
          (#10956) — but the `## User-Brand Impact` section itself never names the
          residual; the protocol requires the scope-out (or a pointer) in the section.
Recommendation: add one line to `## User-Brand Impact`: "Residual: two same-construction
          sites outside `.github/scripts/test/` (ci-pr-selection required check;
          workspaces-luks-loopback) keep the flake class live — scope-outed to #10956;
          worst case is CI friction, not silent coverage loss, since a healthy-graph
          fixture FAILs loudly."
```

```
[FINDING 3]
Artifact: packed-store validity of the fixture construction
Vector:   `SOLEUR_FIXTURE_PACKED=1` is defined in git-corrupt-graph.sh but has ZERO
          consumers — no workflow, suite, or script sets it (grepped .github/, scripts/,
          plugins/soleur/test/). AC4 calls it "a permanent selftest arm"; in fact it ran
          once in Phase-4 local verification and will never run again. A future lib edit
          reintroducing layout dependence in a form the rm-census cannot see (the census
          only greps deletion verbs + the `.git/objects/` literal) returns the flake.
          Worst user experience: required-check false-red — LOUD, not silent coverage
          loss (a healthy-graph fixture fails the refusal assertions).
Plan section coverage: mitigated (partial) — the harm class (CI friction) is named and
          the rm-census bounds the known spelling, but the standing packed-store
          verification the plan promised does not exist.
Recommendation: wire `SOLEUR_FIXTURE_PACKED=1` as a second pass (or matrix leg) of the
          guard-script-fixture-tests job — cheap, reuses the same suites — or downgrade
          the AC4/"permanent" wording so a future editor doesn't assume packed behavior
          is continuously gated.
```

```
[FINDING 4]
Artifact: the standing object-store-deletion census (Guard-1 row 3)
Vector:   `[^#]*` between the deletion verb and `.git/objects/` means a line shaped
          `rm -f "$f" # removes .git/objects/…` (comment before the literal) evades the
          census — the guard misses the reintroduction it exists to catch.
Plan section coverage: mitigated (partial) — realistic reintroductions put the path
          inline before any comment, so the practical gap is narrow; but a one-word
          pattern fix (`[^#"']*` is not needed — allow `#` via reordering or matching
          the literal first) hardens the only standing guard on the construction class.
Recommendation: loosen the grep so a mid-line `#` before `.git/objects/` cannot evade it.
```

## Verdict

No UNCOVERED failure modes — the plan's named worst case (silent g1b refusal-coverage loss
→ unrefused off-main-tag bump reaching the tenant bootstrap image) is bounded end-to-end:
deterministic construction removes the flake class, invariants keep construction defects on
the FAIL rung, skips are counted/capped/loud, and the monitor is the stated cross-run bound
with per-source, never-pooled accounting. **CONCUR**, with two section-level amendments
recommended (FINDING 2: name the #10956 residual in `## User-Brand Impact`; FINDING 3:
either wire the packed arm into CI or stop calling it permanent) and one hardening nit
(FINDING 4). FINDING 1 records, for the merge record, that the extended probe is now the
single load-bearing bound on this PR's entire user-harm model.

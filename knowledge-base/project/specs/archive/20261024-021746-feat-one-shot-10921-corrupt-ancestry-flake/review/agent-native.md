# Agent-Native Architecture Review — PR #10953 (feat-one-shot-10921-corrupt-ancestry-flake)

Seat: `soleur:engineering:review:agent-native-reviewer`
Scope: `git diff origin/main...HEAD` — CI test-infrastructure: corrupt-graph fixture lib, counted-skip machinery, skip-persistence probe extension, monitor workflow copy.
Lens (per dispatch): agent-accessibility of the new mechanisms — are the env knobs (`SOLEUR_FIXTURE_PACKED`, `CORRUPT_WALK_PROBE_FORCE`) discoverable; is the marker/verdict grammar self-describing; is the skip-producer registration contract readable by an agent.

## Summary

The new machinery is unusually self-describing for test infrastructure. `plugins/soleur/test/lib/git-corrupt-graph.sh` carries a complete registration contract, an ENV KNOBS section, stream pinning, and per-helper doc comments; skip reasons embed the measured evidence (walk stderr, merged set, rc) inline; the probe emits per-source labelled verdicts; the monitor alert body names per-family remediation. The residual gaps are at the seams: the packed-store knob is documented but has no driver or invocation contract anywhere in-tree, the probe header still describes a one-source instrument, forced-vs-organic skips are byte-identical, and forge-helper failures at call sites degrade to SKIP rather than FAIL. Verdict: NEEDS WORK — one P1, four P2.

## Capability Map

| Surface | Location | Agent-facing grammar | Discoverability | Status |
|---|---|---|---|---|
| `dead_oid` / `corrupt_walk_break` / `corrupt_dead_tag` | `plugins/soleur/test/lib/git-corrupt-graph.sh:94,114,145` | Per-helper doc comments; FATAL on empty operands | Greppable; sourced at both suites with a pointer comment; census FAIL message names the lib | ✅ |
| `corrupt_invariant_dead_absent` | `git-corrupt-graph.sh:180` | "harness defect, never a skip" in message + doc | ✅ | ✅ |
| `corrupt_skip` (`SKIP (loud):` + `::warning::`) | `git-corrupt-graph.sh:224` | Two-stream grammar pinned in doc comment; cost validated numerically; reason sanitized (`%`→`%25`, CR/LF stripped) | ✅ | ✅ |
| `CORRUPT_WALK_PROBE_FORCE` | `git-corrupt-graph.sh:55-60,200` | `skip` is the only wired value; unwired values `fail()` with rationale | Header + in-suite selftest exercises (`test-bump…:2941,2964`; `test-mint…:1178,1183`) | ✅ |
| `SOLEUR_FIXTURE_PACKED` | `git-corrupt-graph.sh:51-54,103` | Documented semantics | **No driver**: no suite row, run-all arm, or workflow leg sets it; only lib + spec/plan docs reference it | ⚠️ |
| Skip-producer registration contract | `git-corrupt-graph.sh:33-48` | Bulleted contract: registered prefix, declared cost, ceiling, fed-log exercise | Enforced per-suite (`roster:skip-names-registered` on `$0`) + probe-test (p) prefix→producer | ⚠️ |
| Probe verdict grammar | `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` | `PASS|FAIL|TRANSIENT: <source> — <reason>`; exit 0/1/2/78 documented in header | Per-source, never pooled | ✅ (header stale — see P2.1) |
| Monitor alert copy | `.github/workflows/scheduled-rehearsal-skip-monitor.yml:236-288` | Titles/bodies generalized; fail body names arm family + remediation per source | ✅ | ✅ |

## Findings

### P0 (Critical — must fix)

None.

### P1 (Should fix)

1. **`SOLEUR_FIXTURE_PACKED` has no driver — the packed-store arm exists but is never armed.**
   - Location: `plugins/soleur/test/lib/git-corrupt-graph.sh:51-54` (doc), `:102-106` (`_corrupt_maybe_repack`). Repo-wide grep finds the knob only in the lib and in `tasks.md`/the plan; no suite selftest row, no `run-all.sh` arm, no workflow leg sets it.
   - Impact: the `_corrupt_maybe_repack` repack branch is unexecuted code — the one arm that proves the never-written-object construction under the store layout that caused the original flake (packed objects) has no standing exercise. AC4 ("a permanent selftest arm drives an env knob") is written as a *driven* arm and `tasks.md` 5.2 is checked `[x]`, but the shipped diff contains only the knob. Agent-accessibility angle: an agent grepping the knob finds semantics but no invocation contract — no canonical command (`SOLEUR_FIXTURE_PACKED=1 bash .github/scripts/test/run-all.sh`? per-suite?) is spelled out anywhere, and nothing would detect the arm silently breaking (e.g., `repack -adq` failure mode drift).
   - Fix: either add a selftest row that builds a fixture, repacks, forges, and asserts identical row outcomes (the suites already have fixture + capture machinery), or add a documented invocation line in the lib header plus a pinned env leg — and reconcile the AC4/tasks claim with what shipped.

### P2 (Warnings — should fix)

1. **Probe header is stale: it still describes a one-source instrument.**
   - Location: `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` lines ~8-42 — "It reads the ONE signal that already exists — the suite's own loud SKIP line in post-merge `infra-validation.yml` logs" and the Close-criteria block enumerate only the rehearsal source. The body gains a SECOND RUN-SOURCE block (~line 161).
   - Impact: an agent reading the header — the normal first read — builds a wrong model of what the probe measures, where its markers come from, and what TRANSIENT means (per-source, never pooled). The monitor workflow got its scope comment; the probe's own didactic header did not.
   - Fix: amend the "ONE signal" paragraph and Close-criteria list to name both sources and the by-event sampling rule.

2. **Forced-divergence and organic skips are byte-identical markers.**
   - Location: e.g. `test-bump-inngest-bootstrap-pin.sh:1628` (`if corrupt_probe_forced_skip || [[ -z "$walk_err" ]]; then corrupt_skip 'g1b.B7' 8 "runner git does not exhibit …"`) — same shape at B7c, I6, fl.walk.
   - Impact: the emitted `SKIP (loud): <row>` line and `::warning::` read identically whether the environment truly lacked the contract or `CORRUPT_WALK_PROBE_FORCE=skip` forced it. An agent triaging a monitor FAIL cannot tell an AC5 exercise from a genuine runner-git divergence; worse, if any future leg inside `pr-quality-guards.yml` or `infra-validation.yml` runs the suites with the knob set, its expected-marker output files a real alert indistinguishable from a defect.
   - Fix: let the caller emit a distinct reason on the forced branch (`if corrupt_probe_forced_skip; then corrupt_skip … "forced-divergence arm (CORRUPT_WALK_PROBE_FORCE=skip)" elif …`), or have `corrupt_skip` stamp the marker when the knob drove the decision.

3. **Forge-helper return codes are unchecked at every call site — a forge failure degrades to SKIP, not FAIL.**
   - Location: `test-bump-inngest-bootstrap-pin.sh:1619,1659,1683,2656`; `test-mint-inngest-bootstrap-tag.sh:1146` — all bare invocations; both suites run `set -uo pipefail` (no `-e`).
   - Impact: if `corrupt_walk_break`/`corrupt_dead_tag` fails mid-construction (empty operand, unresolvable ref, `update-ref` rejection — all FATAL + return paths in the lib), the helper prints FATAL to stderr and the row proceeds: the walk probe then sees a healthy graph and emits `corrupt_skip`. Per the lib's own stated rung ("harness defects … fail loudly via fail(), charge NOTHING, and never route to corrupt_skip"), a failed construction is a harness defect wearing an environment-divergence label. `corrupt_invariant_dead_absent` cannot catch it — the dead oid is absent whether or not the forge ran — and nothing asserts the ref tip was actually re-pointed at a forged commit.
   - Fix: either check rc at call sites (`corrupt_walk_break "$F_REPO" refs/heads/main || fail '<row>:invariant-forge' …`) or add a `corrupt_invariant_ref_forged <row> <repo> <ref>` rung asserting the tip's parent is the dead oid.

4. **Roster-parity enforcement is per-suite (`$0`-scoped); a new suite's unregistered prefix fails nothing.**
   - Location: `test-bump-inngest-bootstrap-pin.sh` roster check greps `$0` for `g1b.|g2b.`; `test-mint-inngest-bootstrap-tag.sh` greps `$0` for `fl.`. The probe test's row (p) covers the other direction (enumerated prefix → producer exists).
   - Impact: the lib header's registration contract is fully discoverable, but it is only half-mechanized: an agent authoring a third suite with `corrupt_skip 'zz.row' …` gets no failing check unless it also replicates a roster self-check — the skip would be invisible to the monitor and green locally. Notably, the sibling census check (`census:no-object-store-deletion`) IS directory-scoped over all of `.github/scripts/test/` — the directory-scoped shape already exists as precedent.
   - Fix: extend one directory-scoped check (the bump census is the natural home) to enumerate all `corrupt_skip '<name>'` call sites in `.github/scripts/test/` and assert each name opens with a probe-registered prefix, closing producer→prefix globally rather than per file.

### P3 / Observations

1. **The lib contract names no file paths.** "The standing skip-persistence probe" (`git-corrupt-graph.sh:37-44`) requires a grep hop (`SKIP (loud): g1b.` → `t5-skip-persistence-bound-7510.sh`) before an agent can act on "be exercised by a fed-log row in the probe's own test file." One line naming the probe and monitor paths would make the contract one-read complete.
2. **`GUARD_UNITS` record format** (`<unit>|<discriminator>|<markers>`) is documented inline and derived coherently — per-suite banners exist because both suites share one job log; the comment says so. Self-describing. ✅
3. **`gh run view --log` substring matching is sound** for this source: `run-all.sh:176` prints `=== <basename> ===` to stdout and suite stderr reaches the step log unmediated (no capture-relay like `run-registered-suites.sh`), so both the banner discriminator and the stderr `SKIP (loud):` markers are observable. ✅
4. **Selftest hygiene is deliberate and visible**: exercised markers are captured into files precisely so they cannot poison the standing monitor, and selftest row names carry registered prefixes (`g1b.selftest-*`, `fl.selftest-*`) so even an accidental stream leak is roster-valid. ✅
5. **Settled rulings verified, not re-litigated**: forged-oid construction everywhere (no repack-aware `rm`); only walk-contract rows are skip-eligible (invariants fail-only, zero-counted); the probe extension lives in this PR; per-source/per-unit aggregation (never pooled) is implemented. No contradiction found.
6. **`dead_oid`'s constant nonce** is explicitly defended in its doc comment ("the property is absence, not uniqueness"), and the commit-typed refusal on git 2.56 is recorded — an agent does not have to re-derive either. ✅

## Recommendations

1. (P1) Give `SOLEUR_FIXTURE_PACKED` a driver or a written invocation; reconcile AC4/tasks 5.2 with the shipped diff.
2. (P2) Update the probe header to describe both run-sources.
3. (P2) Distinguish forced from organic skip markers in the emitted reason.
4. (P2) Check forge-helper rc at call sites (or add a ref-forged invariant) so construction failures stay on the FAIL rung.
5. (P2) Make prefix→probe registration directory-scoped like the census, not per-suite.
6. (P3) Name the probe and monitor paths in the lib's registration contract.

## What's Working Well

- The lib header is the model for agent-readable mechanism docs: root cause with measured arms, one-spelling rationale with the census, forge-last ordering with the reflog subtlety, a bulleted registration contract with consequences ("an unregistered name is a skip the monitor can never see"), env-knob grammar with the fail-closed rationale for unwired values, and the caller contract (pass/fail/SKIPPED_ASSERTIONS) in one block.
- Marker grammar is pinned and defended: stream assignment explained (stderr for the probe grep, stdout for `::warning::`), reason sanitization against annotation forgery, numeric cost validation with `arm_skip` parity.
- The probe's per-source accounting and labelled verdicts are exactly the self-describing shape an agent needs to act on a TRANSIENT/FAIL without re-reading the implementation.
- The monitor alert copy names the arm family and the owed remediation per family — triageable by an agent without repo context.

## Agent-Native Score

- **6/8 capability surfaces fully agent-accessible** (knobs discoverable and self-describing; two surfaces — PACKED-arm invocation, global prefix registration — require out-of-band knowledge or are unenforced).
- **Verdict**: NEEDS WORK — no P0; one P1 (undriven packed arm / AC4 discrepancy) and four P2s on self-description seams.

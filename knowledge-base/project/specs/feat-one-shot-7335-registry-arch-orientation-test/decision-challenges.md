# Decision challenges - feat-one-shot-7335-registry-arch-orientation-test

Appended by plan on 2026-10-13 (headless pipeline: not asked, persisted for the ship phase to render in the PR body). Every technical
fork below was ruled by the CTO agent per `hr-technical-fork-is-not-an-operator-question`; nothing here is an operator question.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Premise: the brief's headline ask (an A16-style orientation test for `local.registry_arch`) is already on main as `R3` / `p_registry_arch_derivation` in `registry-boot-guard.test.sh` (landed in #7325, the PR that spawned #7335). Measured on a sandbox worktree: INVERT and DELETE each red `registry-boot-guard` (127/1) and leave the other four suites green. What is missing is R3's own durability: it is a bare `assert()` with no mutation arms, so it can be neutered at green | technical | Ruled by CTO agent, 2026-10-13: Option B, kept narrow - add in-suite mutation arms to R3 (INVERT, DELETE, widened prefix, truncated/empty extraction), add one guard that `hcloud_server.registry` carries the amd64-only precondition with its own delete/mutate arms, raise `MIN_ASSERTIONS` by the count added - R3 is the issue's literal ask and already landed; the remaining gap is that nothing proves R3 durable, and the hardcoded-amd64 measurement has no guard on the precondition that makes it sound |
| `local.doppler_sha256` | technical | Ruled by CTO agent, 2026-10-13: scope out as already covered, add no new test, cite `git-data-luks.test.sh` A15 (`p_doppler_checksum_parity`) in the R3 comment block in place of "still uncovered - #7335" - measured: selector-invert, literal-swap, amd64-literal-corrupt and delete mutations on `zot-registry.tf` all red A15 (153/1); the derivation that feeds the ternary is R3's. A second parity test would duplicate A15 |
| `registry-userdata-budget.sh` hardcoded amd64 branch | technical | Ruled by CTO agent, 2026-10-13: cover by a precondition-presence assertion in `registry-boot-guard.test.sh` (R4), not by making the script derive or refuse on arch - the measured size is arch-invariant (`amd64` and `arm64` are both 5 chars, both Doppler checksums 64 hex) so arch logic in the script would be dead code; the hardcode is sound only because `hcloud_server.registry` refuses to plan arm64 (`zot-registry.tf` precondition `local.registry_arch == "amd64"`), and no test asserted that precondition exists |
| Where the pointer comment to the hardcoded branch lives | technical | Ruled by CTO agent, 2026-10-13: leave `registry-userdata-budget.sh` untouched and put the pointer only in the R4 header comment of `registry-boot-guard.test.sh` - the script is a `pull_request` path trigger of `zot-image-mirror.yml`, so even a comment-only edit would run the zot-image rehearsal on this PR for zero behavioral gain (supersedes the same CTO's earlier comment-in-the-.sh suggestion) |
| Work location | technical | Ruled by CTO agent, 2026-10-13: the existing `registry-boot-guard.test.sh`, not a new sibling - R1-R3 live there, the suite is registered by filesystem glob (ADR-252) and a new sibling would need its own floor for three or four arms; the new arms read only `zot-registry.tf` and never `cloud-init-registry.yml` |

## User-Challenge

None. The operator's stated direction is followed. The brief's premise that nothing asserts the orientation is stale (R3 exists), which
changes the shape of the work from "build the orientation test" to "prove the existing one durable and guard the precondition the
budget script leans on". The brief's own instruction "prove with the INVERT and DELETE mutations on a sandbox copy" is honored twice:
once now as a measurement, once permanently as in-suite arms. It is disclosed here rather than challenged because every named
deliverable (the replay table, the mutation proof, the two consumers, no user_data edit) is still delivered.

## Taste

1. **Mutation-arm count.** The DHH and code-simplicity reviewers both recommended cutting arms killed by the same fixture or extraction path as a kept arm. Applied: R3 keeps INVERT, DELETE, WIDEN, must-PASS and NOLAND (5, was 8); R4 keeps baseline, DELETE, WEAKEN, COMMENT-OUT, RESOURCE-RENAME and must-PASS (6, was 7); total 11 new assertions, floor 123 to 134. A reviewer who prefers the wider matrix can restore the true-branch-only, narrow-prefix, comment-out (R3) and FLIP (R4) arms at about 4 assertions of cost.
2. **Kieran review result.** It completed after the first status check and confirmed the line anchors, the R3 fixture set, the R4 awk predicate on the real file, the 128/123 arithmetic and exit-status preservation under an EXIT trap. It found one real defect (an unescaped `?` in a sed -E expression fails with `Invalid preceding regular expression`), fixed by prescribing exact, escaped, anchored expressions for every arm, all verified.

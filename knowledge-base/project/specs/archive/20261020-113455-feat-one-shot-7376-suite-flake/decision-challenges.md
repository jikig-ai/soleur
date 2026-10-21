# Decision Classes — feat-one-shot-7376-suite-flake

Persisted technical rulings and surfaced decisions for the #7376 close-out plan.
No spawn/Task tool exists on this harness (Devin CLI subagent), so the CTO role was
executed inline in the planning process per
`skills/brainstorm-techniques/references/technical-ruling-delegation.md`
(`Reviewed-Coverage: sequential-fallback`).

| Item | Class | Ruling |
|------|-------|--------|
| Resource-exhaustion fix arm — memory-derived `JOBS` cap vs deterministic class-serialisation vs bounds-only | technical | Ruled by CTO agent, 2026-10-20: **deterministic class-serialisation of the named heavy set, evidence-gated** — a memory-derived cap is auto-derived width (varies run-to-run, makes the flake irreproducible and self-masking: the cap silently lowers width exactly when contention rises); the runner cannot source `scripts/lib/test-contention.sh` (ADR-177 §A3 single-file SUT copy + python mutator), so the cap would also be a second inlined capacity implementation. If OOM/kill-class evidence lands (UNACCOUNTED with `XARGS_RC==125`, or signal-shaped `.meta` rc on a heavy suite), serialize the heavy class (docker + terraform + mutation suites) at width 1; contention-slowdown stays owned by `_SUITE_BOUNDS` (rc=124 renders as a named RED). - `run-registered-suites.sh:750` JOBS is already `min(nproc,6)`; `test-contention.sh` `tc_acquire` is CI-exempt by design (`scripts/lib/test-contention.sh:1307`) and serializes *invocations*, not intra-run `-P` width. |
| Attribution instrument — mandatory local `taskset -c 0-3` n≥20 battery vs CI evidence streams | technical | Ruled by CTO agent, 2026-10-20: **CI streams are the instrument; no mandatory local battery** — the prior arm's recorded caveat stands (taskset bounds CPU only; this box cannot reproduce the 4-core/16 GB/14 GB-disk envelope, so a local non-reproduction establishes nothing). The streams already running are the 12-run monitor soak (`scripts/followthroughs/jobs1-stopgap-7432.sh`, `earliest=2026-10-19T18:00:00Z`) and the sharded `deploy-script-tests` leg corpus (688 legs, none parallel-only). Attribution on any new RED is exit-code-first: rc=124 → bound/contention; signal-shaped or UNACCOUNTED → kill/OOM-candidate; marker FAIL → real defect. A local taskset run remains an optional implementer discriminator, not an AC. - prior arm session-state caveat: `specs/archive/20260811-022448-*/session-state.md`. |
| `mktemp -u` regression-guard assembly — execute-set sweep vs named-file pin list | technical | Ruled by CTO agent, 2026-10-20: **two-part guard — zero `mktemp -u` across the derived execute set + file-exact zero-pin on the audited files** — a broad "no `/tmp` writes" line search cannot see the container boundary (docker-heredoc `/tmp` writes are legal and numerous: `git-data-ownership.test.sh` sshd arm, `git-data-cutover-access.test.sh` `/rt` arms), so it would need ~14 deferral rows for legitimate sites. `mktemp -u` is an exact rare shape safe to ban set-wide; the audited hardcoded-`/tmp` files get file-exact zero-pins (FILES_7376 precedent in `grep-q-pipe-guard.test.sh:328`). - measured inventory: 3 executed-suite sites (`git-data-rung2-rehearsal.test.sh` `/tmp/rung2`, `ci-deploy.test.sh` `mktemp -u`, `verify-tunnel-ingress-origin-infradir.test.sh` `mktemp -u`) + 1 privileged (`sandbox-masked-proc-docker.test.sh` `/tmp/c4-status.json`). |
| #7432 (`JOBS=1` stopgap removal) inclusion | operator (scope) | Out of scope per pipeline brief — the soak runs on its own tracker (`#7432`, probe `scripts/followthroughs/jobs1-stopgap-7432.sh`); this plan consumes its verdict as evidence, it does not own it. |
| #7554 (sibling `.meta` rc forge/erase) inclusion | operator (scope) | Out of scope per pipeline brief — distinct contested-design defect; adjacency noted only because the namespacing touch is on the same file. |

## Notes on the rulings (dissent lines)

- Item 1 dissent: the issue body proposes "cap -P by available memory rather than by
  core count". The ruling keeps the deterministic arm; the memory cap remains the
  documented rejected alternative with its refutation (irreproducible width +
  self-masking + single-file-SUT constraint). Evidence that would flip it: repeated
  OOM-class kills that persist under width-1 heavy-class serialization.
- Item 3 dissent: an advocate could argue for deferral-table-style coverage of the
  container-heredoc sites too. Chosen shape covers the shapes that produced live
  defects without paying ~14 rows of deferral debt for legal container paths.

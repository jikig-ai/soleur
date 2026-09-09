# Tasks — confine the shipped plugin scripts, pin the Better Stack destination, partition the BYOK outcomes

Plan: `knowledge-base/project/plans/2026-09-09-fix-credfwd-plugins-betterstack-pin-byok-fixture-plan.md`
Issues: Closes #7055; prose `Ref #7898` (§5 and §6 only — #7898 stays OPEN)

Phase order is load-bearing. Phase 0 before everything, or the drawdown arithmetic is against the
wrong tree. Slice C (Phases 3-4) is ordered last so it can be dropped without unpicking A or B.

## Phase 0 — Preconditions (measure, do not edit)

- [ ] 0.1 Re-run the census over the fifteen literal paths in the plan's `## Files to Edit`.
      Expect `42 violation(s) in 15 scanned file(s)`.
- [ ] 0.2 Pull `BETTERSTACK_QUERY_HOST` read-only from Doppler `soleur/prd_terraform`. Then
      `workflow_dispatch` one cheap query-path followthrough on this branch as a canary against the
      Actions secret, which is the store production actually reads and is unreadable directly.
- [ ] 0.3 Confirm no plugin skill documents a `bash -x` debug path. (Measured at plan time: none.)
- [ ] 0.4 Re-derive the free ADR ordinal across every `refs/remotes/*`, not `origin/main` alone.
- [ ] 0.5 Re-confirm ADR-179 anchor compliance by READING the `CLAUDE_PLUGIN_ROOT:-` hit in
      `community/SKILL.md`, not counting it — it is prose documenting the banned form.

## Phase 1 — Slice B: pin the Better Stack query destination

- [ ] 1.1 In `scripts/betterstack-query.sh`, add authority extraction (strip path, query, fragment,
      refuse userinfo, strip port) then a `*.betterstackdata.com` suffix match. Match the isolated
      host, never the whole value. Keep the existing shape arms ahead of it as the cheaper refusal,
      and keep the credential-presence `exit 3` guard first.
- [ ] 1.2 Rewrite the comment block above it: state the pin that exists, name `curl`-shimming as the
      sanctioned way for a test to exercise egress, and delete the forecast of an opt-in seam.
- [ ] 1.3 `tests/scripts/test-betterstack-query-archive.sh` — vendor-shaped host at all **three**
      sites; add a file-backed `curl` invocation counter (the current shim records nothing and the
      count cannot cross the `bash -c` boundary); add an anti-vacuity case floor.
- [ ] 1.4 `tests/scripts/test-git-data-rung2-evidence-capture.sh` — `curl` shim on `PATH` plus a
      vendor-shaped host at **both** real-transport invocation sites. Verify the arm's `exit 64`
      discrimination still fires and is not preempted by the new `exit 2`.
- [ ] 1.5 Add Guard 2's mutation and must-PASS rows. Reuse the existing `assert_dest` matrix in
      `tests/scripts/test-betterstack-roundtrip-latency.sh` rather than inventing one.

## Phase 2 — Slice A: confine the fifteen shipped scripts

- [ ] 2.1 Add the xtrace refusal to each. **Conditional** arm for the seven community scripts;
      **unconditional** for all eight operator scripts, `provision-doppler.sh` included — its
      linter-emitted conditional arm is empty at guard time because `read -rs` binds the token after
      the prologue. Refusal goes to **stdout** (measured: Rule A does not pin the stream).
- [ ] 2.2 Customer-facing refusal copy from the plan's literal template, with each file's own
      guarded variable list substituted. The remedy must name every variable that file's arm tests.
- [ ] 2.3 `--disable` as the literal first argument and `--noproxy '*'` on all 26 credentialed curls.
- [ ] 2.4 `provision-doppler.sh` — hoist the multi-line `-d` payloads into variables. Do **not** add
      a `readonly DOPPLER_API_PINNED` constant; it adjudicates the wrong variable and pins nothing.
      Also add the confinement flags to the printed manual-fallback curl recipes.
- [ ] 2.5 Add the proxy-aware failure line to the seven, so a proxied founder is not told to check
      their network connection.
- [ ] 2.6 Remove the 15 lines from each baseline **by hand**. Never `--write-baseline-d`: it rewrites
      the whole file from a full-tree scan and would silently re-baseline drift.
- [ ] 2.7 Drop the false "AND its highwater" clause from `--write-baseline-d`'s argparse help. Help
      string only — no predicate, regex or baseline-loading logic.
- [ ] 2.8 Re-run the scoped census over the fifteen literal paths; expect `OK`.

## Phase 3 — Slice C: partition the BYOK outcomes

- [ ] 3.1 Partition `settled` (not `results`) into five classes: rejected, errored, refused-hourly,
      refused-other, admitted. Assert the first three are empty, naming code and message; assert the
      classes sum to N; keep `allFulfilled` ahead of them.
- [ ] 3.2 Partition the ledger channel the same way — `refusedRows(rows, HOURLY_REASON)` has the
      identical blind spot.
- [ ] 3.3 Fold both new partitions into `willFail` **before** `diagIf` is awaited.
- [ ] 3.4 Add the sequential null-change control: B's M calls first (assert B admitted === M), then
      A's N calls (assert A's counts unchanged). Fresh grantee for B, `addMember` first, hourly ≤
      daily. Wire a diag banner. Comment the founder-scoped meter that *does* pool.
- [ ] 3.5 Add a test-count assertion so a silently-deleted control cannot pass as a green run.

## Phase 4 — Slice C: remove the leading cause, and make the skip visible

- [ ] 4.1 `.github/workflows/tenant-integration.yml` — make `concurrency.group` ref-independent,
      keeping `cancel-in-progress: false`.
- [ ] 4.2 `scripts/tenant-integration-gate-verdict.sh` — on the `skipped` arm emit a `::notice::` and
      a step-summary line saying the suite did not execute against this tree.
- [ ] 4.3 Extend `tests/scripts/test-tenant-integration-gate-verdict.sh` with rows for both PASS arms.

## Phase 5 — Record and reconcile

- [ ] 5.1 Write ADR-214 (ordinal provisional) — the **seam corollary only**. Do not restate the four
      confinement flags; they are already enforced executably. Acknowledge the shipped
      `BETTERSTACK_QUERY_SH` exceptions rather than being contradicted by them.
- [ ] 5.2 Mirror the corollary into `check_rule_d`'s docstring and the `betterstack-query.sh` block.
- [ ] 5.3 Correct the stale query host in the Better Stack runbook. It is a tidy-up, not a rescue —
      the runbook itself records that both names are the same cluster.
- [ ] 5.4 Reconcile `model.c4`'s "baselined remainder of N files" against the live count.
- [ ] 5.5 File the deferred follow-ups enumerated in the plan's Non-Goals.

## Phase 6 — Verify

- [ ] 6.1 Walk every acceptance criterion in the plan, running each command as written.
- [ ] 6.2 `bash scripts/test-all.sh` (full battery) and `plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 6.3 PR body: `Closes #7055` on its own line, prose `Ref #7898`, a `## Changelog` section, and
      no closing keyword for #7898 anywhere including code blocks.

# Performance Review — feat-one-shot-10921-corrupt-ancestry-flake (PR #10953)

**Seat:** `soleur:engineering:review:performance-oracle` · report-only
**Diff reviewed:** `git diff origin/main...HEAD` (10 files, +1693/−160)
**Date:** 2026-10-23 · **Verdict: PASS — no P0, no P1; four P2 notes.**

## 1. Performance summary

Two surfaces changed: (a) the corrupt-ancestry test fixtures — a new shared lib
(`plugins/soleur/test/lib/git-corrupt-graph.sh`) replacing `rm -f` on loose-object
paths with forged never-written-object commits/tags, plus counted-skip plumbing in
the bump and mint fixture suites; (b) the daily skip-persistence probe
(`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`), widened from one
run-source (20 `infra-validation.yml` logs) to two (adds ≤20
`pr-quality-guards.yml` logs sampled by `merge_group`/`pull_request` event).

Nothing in the diff is a production hot path: the fixture helpers run inside CI
test suites, the probe runs once daily. The dominant cost driver — full-bundle
`gh run view --log` fetches — was measured live and fits its existing budget.

## 2. Measured evidence (this host, authenticated `gh`, 2026-10-23)

| Call | Wall time | Bytes |
|---|---|---|
| `gh run view --log` ×3 merge_group `pr-quality-guards` runs (ids 40038798088, 40032878062, 40032766597) | **~2 s each** | ~1.5–1.8 MB |
| `gh run view --log` ×3 success `infra-validation` main runs (ids 40025677490, 40007213716, 40001091028) | **~13 s each** | ~4.4 MB |
| `gh run list` per call | ~1–2 s | — |
| Discriminator check on real run 40038798088 | banner `=== test-bump-inngest-bootstrap-pin.sh ===` and `=== test-mint-inngest-bootstrap-tag.sh ===` **both present** in the `--log` stream | — |

**Derived probe budget:** ≤20 iv fetches (~260 s) + ≤20 pg fetches (~40 s) + 3
list calls ≈ **~305 s** against the `timeout 600` wrapper in
`.github/workflows/scheduled-rehearsal-skip-monitor.yml:125` → ~51% consumed, ~295 s
headroom. The old probe consumed ~260 s; this PR adds ~18% wall time, not 2× —
the new source is the *cheaper* per-fetch one. Memory: logs land in a scalar
`$log` one run at a time; ≤ ~4.4 MB each — bounded.

A micro-benchmark of the forge helpers could not run here (the repo's commit
guard blocks scratch `git commit`/`commit-tree` outside the worktree), so §4's
fixture-side numbers are subprocess-count arithmetic, not measurements.

## 3. Critical issues (P0/P1)

**None.** The hypothetical breach — doubling `gh run view --log` calls against a
fixed `timeout 600` — was measured rather than assumed and does not hold: the
added fetches are the fast ones (~2 s vs ~13 s).

## 4. Optimization opportunities (P2)

### P2-1 — Stale budget comment; ~300 s of a 600 s probe budget now consumed
`scheduled-rehearsal-skip-monitor.yml:74` still reads "`gh run view --log` over
20 multi-MB logs" — the probe now issues up to ~43 network calls across two
workflows. Headroom is real today (measured ~51%) but the comment understates
the load, and a timeout (rc 124) files a `broken`-verdict alert issue — the
noisy-false-positive direction. **Recommend:** re-derive the comment to the
two-source shape ("up to 40 log fetches across infra-validation +
pr-quality-guards, measured ~300 s of the 600 s wrap") so future log growth is
evaluated against a true number. No code change needed.

### P2-2 — Whole-bundle log download when one job is needed
`gh run view <id> --log` transfers **all** job logs per run: ~16 jobs for
pr-quality-guards.yml (~1.5 MB) and ~11 for infra-validation.yml (~4.4 MB,
pre-existing shape). The probe greps only `guard-script-fixture-tests` output
(and, for iv, the rehearsal relay lines). Job-scoped fetch —
`gh api repos/{repo}/actions/runs/{id}/jobs --jq 'select(.name=="guard-script-fixture-tests")'`
then `gh api repos/{repo}/actions/jobs/{jid}/logs` — would cut transfer ~80–90%
per run at the cost of one extra cheap API call, and shrink the P2-1 budget
exposure proportionally. At a daily cadence this is a ~30 MB/day egress saving —
worth doing only if the budget tightens; listed for the record, not required.

### P2-3 — Fixture forge helpers: ~6–9 git subprocesses per row (was ~2–3)
`corrupt_walk_break` issues `repack` (packed arm only), `hash-object --stdin`,
`rev-parse ^{tree}`, `cat-file | sed`, `hash-object -w -t commit`, `update-ref`,
and a verify `rev-parse`; `corrupt_invariant_dead_absent` then **recomputes**
`dead_oid` (a second `hash-object`) plus `cat-file -e`; each row's probe adds
1–2 `tag --merged`/`merge-base`. Estimated delta vs the removed `rm -f` path:
~+50–100 ms per corrupt row × 5 rows ≈ +0.3–0.5 s per suite — negligible inside
~700-assertion suites whose rows each spawn `run_bump`/`run_mint` subprocess
trees. `SOLEUR_FIXTURE_PACKED=1` adds one `git repack -ad` per forge (~tens of
ms on ≤3-commit fixtures). **No action.** The extra spawns buy correctness
(assert-empty operand, update-ref verification, invariant independence — the
recompute keeps the invariant honest against a `-w` drifting onto `dead_oid`);
passing the dead sha in from the caller would save one spawn and couple the
check to the thing it checks — correctly rejected by design.

### P2-4 — Per-log marker scans: ~5 full-text greps per sampled run
Per pg log: 2 discriminator `grep -qF` + ≤3 `grep -cF` marker scans over a
~1.5 MB here-string; ~100 single-digit-ms scans per probe run. A single `awk`
pass could collapse them; not worth the churn at this size. Noted so the next
marker-batch addition doesn't grow it unthinkingly.

## 5. Scalability assessment

- **Fixture path at 10× rows:** linear in git spawns; a suite with 50 corrupt
  rows would add ~5 s — still noise. The `repack`-per-forge cost scales with
  fixture object count, which is pinned small by `base_fixture`.
- **Probe at 10×:** the binding constraint is `SAMPLE=20` per source — adding a
  third source adds one list call + ≤20 fetches of whichever workflow; each new
  source should be priced against the 600 s wrap like §2.
- **Sampling bias (non-blocking):** `pg_ids` concatenates merge_group ids first
  then pull_request, `head -20` — pull_request legs are sampled only when
  merge_group yields <20 recent runs. This matches the CTO preference
  (merge_group legs are the landing-gating evidence) and pull_request fills in
  correctly on queue-quiet days. Intentional; recorded so it reads as a choice.
- **Rate limits:** ~85 REST calls/day worst case against the Actions token's
  per-hour budget — negligible.

## 6. Settled-ruling conformance (CTO 2026-10-23)

- **forged-oid over repack-aware rm** — implemented; nothing contradicts it.
- **only walk-contract skip-eligible** — holds: B7/B7c/fl.walk probe non-empty
  walk stderr; I6 probes merge-base rc∉{0,1}+stderr; B7a's silent-drop probe is
  its documented own-shape contract, not a new skip class.
- **probe extended in this PR** — done, with per-source TRANSIENT (never
  pooled), per-suite banner discriminators (verified live, §2), and FAIL-dominates
  verdict.
- **tier aggregate pattern** — `SKIP_CAP` equals the summed declared row costs
  (28 bump = 8+9+8+3; 3 mint), folded into `TOTAL` via `SKIPPED_ASSERTIONS`;
  selftests pin both directions.

## 7. Positive observations

- Here-string greps (`<<<"$log"`) avoid the measured SIGPIPE/pipefail trap —
  and `grep -cF` reads to EOF, the safe shape for counting.
- Selftest `SKIP (loud):`/`::warning::` lines are captured to files, not suite
  streams — a real escaped marker would poison this very monitor daily.
- `st_run` and the mint snapshot driver now save/restore `SKIPPED_ASSERTIONS` —
  selftest exercises cannot leak charges into the floor.
- `timeout 600` wrap predates the PR and correctly maps a hung probe to
  `broken` rather than burning the 15-min job budget silently.
- `dead_oid`'s constant nonce keeps absence a construction invariant — no
  per-call nonce machinery, no `hash-object -w`, verified by
  `corrupt_invariant_dead_absent`.

## 8. Recommended actions (priority order)

1. **P2-1:** refresh the `timeout-minutes: 15` / `timeout 600` comments to the
   two-source, ~300 s measured reality — one-line comment edits, no behavior.
2. **P2-2 (optional, deferred OK):** job-scoped log fetch if the budget ever
   tightens; do not churn now.
3. **No action** on P2-3/P2-4 — recorded to prevent unthinking growth.

# Review notes — PR #12622 (feat-one-shot-12017-soak-read-window)

**Mode:** sequential-fallback — this harness has no spawn/Task surface; every seat the
`soleur:review` panel prescribes ran as an inline sequential pass with the same lens
definitions. No independent parallel review ran or is claimed.

**Panel SHA:** db721ade1bca0f8dc647500707feb9b660b5650f
**Change class:** code (`.sh` source extensions present) — baseline 8-agent panel.
**Risk tier:** `none` (source: plan frontmatter `brand_survival_threshold: none`; no
SENSITIVE_PATH_RE match → no clamp).
**Design-risk:** yes — new `&page=$mg_p`/`mgpages=K` request vocabulary a second file
(the fake gh) must learn, plus the `FX_SEEN` state carrier. Design-validity pass ran
first (simplicity + architecture + performance lenses, deduped from the panel).
All four mechanism choices carry `Ruled by CTO agent, 2026-11-10: APPROVE` rows in
`decision-challenges.md`; no finding below contradicts a ruling.

## Seats run (sequential)

git-history-analyzer · pattern-recognition-specialist · architecture-strategist ·
security-sentinel · performance-oracle (lead-added: the stated justification IS a cost
saving; PERF_RE does not match `scripts/followthroughs/` mechanically) ·
code-quality-analyst · test-design-reviewer (`.test.sh` in diff) ·
structural-enumeration (guard-shaped: plan carries `## Guard Contract`, deliverable
edits a live gate probe) · code-simplicity-reviewer (Step 4) ·
shellcheck (deterministic substitute for semgrep-sast — bash-only diff).
Not triggered: data-integrity-guardian, agent-native-reviewer (no path arm, no judgment
surface), user-impact-reviewer (tier `none`), gdpr-gate (no canonical-path match),
anti-slop (no `apps/web-platform`/docs paths), rails/migration seats, semgrep-sast
(bash-only → shellcheck).

## Verification evidence (lead-run, not agent-reported)

- `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` → **179/179 PASS,
  0 fail, MUTANTS: 68 of 68 caught**, 2m08.7s wall on this host (r_mgcap and
  r_badcreated both green; always-PASS control = exactly 10 red rows; nolink = 11;
  identity = 0).
- `git merge-tree --write-tree origin/main HEAD` → rc 0 (no conflict; branch is
  11 ahead / 3 behind, mergeStateStatus BEHIND-but-MERGEABLE).
- `shellcheck` probe: one NEW warning only — SC2034 `created` unused (line 195);
  test file's single SC2034 (`privact`) is identical on `origin/main` (pre-existing).
- jq probes: `index(x)` ≡ `select(. == x)` presence semantics on the voucher array;
  `@tsv` null→empty field (null head_sha flows identically); `fromdateiso8601` errors
  on `"not-a-date"` and `null` → slice-level rc 3 as designed; `{}.workflow_runs|length`
  → 0 (see F-3).
- Structural ACs re-derived: loop-body `jq -r` sites = 1 (awk window check);
  `CONTROL_ROWS` occurrences = 6; zero `ALL_ROWS` inside `core_rows_quiet` call sites;
  zero `--paginate` in the probe; `MAX_RUNS/IDLE_RUNS/MIN_ELIDED/MIN_DAYS/
  DEADLINE_DAYS/MEAN_LIMIT_HUNDREDTHS_MIN` byte-unchanged (ADR-276 S2 contract).
- Citations (git-history): `pr-battery-gate-saving-9323.sh:242` (`&page=$p` shape),
  `cron-machinery-soak-9272.sh:136` (bounded page loop), `sweep-followthroughs.sh:58-66`
  (FT_PROBE_TIMEOUT, Ref #11215), `f88359a7f8` (sibling retirement), `404e4c626f`
  (PR #12419 pace fix), ADR-276 amendment Decision 3(e) ("trailing sample of at most
  100 push runs"), audit row 11 (254.6s vs 87.9s, +190%) — all resolve against the tree.
- FX_SEEN stale-fixture invariant: grepped every post-build writer — only the fake
  gh's `requests.log`/`refused.log` appends touch fixture dirs (reset on memoized hit).
- PR checks: `test` job red is the draft-light aggregate ("draft: full battery owed
  at ready", `DRAFT_LIGHT: true`, legs oracle-skipped) — expected draft state, NOT a
  suite failure; consequence: the new suite code has no CI run yet (local run above
  is the evidence).

## Lens verdicts on the parent's weighted points

(a) **Verdict-equivalence under merged-jq batching — HOLDS.** Each of the four
per-run jq programs is the original expression verbatim inside parens (`@tsv` join);
`IFS=$'\t' read` splits the 4 fields; `is_elided`/`pd_failed`/`proof_holds`/`secs`
identical. `created_epoch` moved into the runs slice (`fromdateiso8601`) — an
unparseable `created_at` now fails the slice (rc 3, `ci.yml push runs`) instead of a
per-run read; same verdict class, earlier, pinned by `r_badcreated`. Voucher check:
`($m | index($p[1])) == null` ≡ old `map(select(. == $sha)) | length` = 0 (verified
on jq 1.8.2, incl. null-sha edge). Order of wrong_list preserved. FAIL-before-NOT-YET
precedence: check order unchanged (registration → wrong → early → adr → pd_bad →
deadline → mean → census); the new rc-3 arm sits where the `--paginate` fetch sat.

(b) **Mutant-anchor integrity — HOLDS.** Re-anchored `m-no-voucher`
(`select(($m | index($p[1])) == null)`), `m-unmatched-ok` (`elided_pairs+=(...)`),
new `m-mg-cap-silent` (`(( mg_full_at_cap )) && {`) each appear exactly once
(`s.count(old)==1` enforced by the harness — a missed anchor is a loud NOT-LANDED
failure). All jq-subexpression mutants re-pinned inside the merged program
(m-ts-any, m-skipped-filter, m-runner-type, m-negdur, m-step-name, m-heavy-*) —
verified live: 68/68 caught, zero did-NOT-land.

(c) **Bounded pagination — HOLDS.** Pages 1..MG_MAX_PAGES, break on first short
page; full page at index MG_MAX_PAGES sets `mg_full_at_cap` → rc 3 CANNOT ESTABLISH
naming the cap — never a verdict on a truncated voucher set. A listing ending
exactly on a page boundary fetches one extra (empty) page → correct. Both
break-condition mutant directions are covered (`<=` stop-early and never-break
each go red via r_mgcap/normal rows).

(d) **Suite-side bounds honestly weak — HOLDS.** CONTROL_ROWS (12) spans every
verdict class (rc 0/1/2/3, voucher, mean, marker, permission, ADR, registration);
always-PASS floor 10/12 verified live (r_pass + r_needcomplete red-immune exactly
as the comment claims). r_max_cap 60→40 + 2000→2200s arithmetic re-derived:
all-50 mean 31.03 min → FAIL; mutant newest-30 mean 27.28 → pass. Property and
m-max-cap kill preserved.

(e) **Re-price convention — HOLDS.** `suite-durations.tsv` targeted row edit
87919→185400 `measured`; commit ae1e1ce196 names the three merge_group run IDs
(42891735582 / 42887535182 / 42864026488) and documents the CI-scale derivation
and the oracle-selection-skipped caveat.

## Findings

- **F-1 (P3, pr-introduced):** `scripts/followthroughs/ci-push-dedupe-soak-9512.sh:195`
  — `created` read into the loop is now unused (epoch carries the comparison); new
  shellcheck SC2034. Fix: drop `.created_at` from the TSV feeder / the read, or
  rename `_created` (~1 line).
- **F-2 (P3, pr-introduced):** `ci-push-dedupe-soak-9512.test.sh:65-68` — the
  `paginate` flag variable is now dead (its only consumer `(( paginate )) || refuse`
  was removed); the refusal path still works via the no-`page=` refuse. Cosmetic.
- **F-3 (P3, hardening, pr-adjacent):** `ci-push-dedupe-soak-9512.sh:180` — a page
  whose JSON lacks `workflow_runs` yields `mg_n=0` → reads as a short page →
  enumeration ends cleanly on a possibly-truncated set (the malformed-body guard
  catches non-JSON only). Unreachable under GitHub's real response contract
  (non-2xx → `gh api` fails → `fail_api`) and equivalent exposure existed under
  `--paginate`; one-line tighten: require `.workflow_runs` to be an array.
- **F-4 (P3 observation):** the rc-3-at-cap arm fires before the independent
  FAIL checks (deregistered suite, ADR proposed), so a persistent cap masks them
  until the window shrinks — position unchanged from `--paginate` (an API failure
  there also preempted) and within the CTO-ruled design; noting, not dissent.
  Related precision option (also P3): reading `total_count` would let a listing
  ending exactly on the cap proceed instead of a false CANNOT-ESTABLISH.
- **Pre-existing, wontfix:** `privact` SC2034 in the test file (identical on
  `origin/main`; the flag is a call-site readability placeholder).

Structural-cause roll-up: none — F-1/F-2 are independent one-token remnants of the
same mechanical rewrite, not instances of a guard-window gap a seat should have
enumerated.

Disposition: nothing qualifies for scope-out (all ≤4 lines, ≤2 files, pr-introduced
or hardening) → findings ride to the Step-5 resolver; one bundled `code-review`
issue filed for durable tracking.

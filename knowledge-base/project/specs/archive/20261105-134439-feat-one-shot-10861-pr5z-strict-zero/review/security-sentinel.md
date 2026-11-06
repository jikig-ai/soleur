# security-sentinel — PR #12127 (feat-one-shot-10861-pr5z-strict-zero)

Seat: `soleur:engineering:review:security-sentinel`
Reviewed: `git diff origin/main...HEAD` on worktree HEAD `79db88e18b` (merge-base `origin/main`)
Method: code read of the new verdict arm and its surroundings, receipt cross-check, and a live kill-test of the four new mutants run from an exported copy in `mktemp` (`/tmp/soleur-seat.MFZf`), `--rows 458-461`: **715 assertions, 0 failures, 4 of 4 mutants killed**. The live worktree was not modified (git status shows only this review dir as untracked).

## Verdict

No P1/P2 findings. The `baseline-reintroduced` arm is unconditional, correctly placed, and unreachable-by-design in CI's invocation. The 42 deleted accept rows are genuinely orphaned, the widened edge is three literal paths, and the guard-shaped test additions carry real teeth.

## Findings

### P3 — docstring lead sentence still describes the retired equality contract

`scripts/ci-pr-affected-replay.py:135-136` (`RATCHET` help block). The paragraph still opens "the live gap set … must EQUAL a committed, shrink-only baseline (scripts/ci-pr-affected-audit.baseline.tsv …)". Under strict zero there is no committed baseline on the default path; equality is against the empty set. The `BASELINE STATE` table at :151-153 was correctly rewritten ("exit 1 unconditionally (baseline-reintroduced)"), so the block now contradicts itself within five lines — and the runbook defers to this --help text as the contract (`runbooks/ci-pr-affected-activation.md`). Not exploitable; fix on the next touch or in this PR.

### P3 — co-firing tail remedy can mislead under a malformed re-add

`scripts/ci-pr-affected-replay.py:2090-2095`. When a re-introduced baseline is also malformed (`stale-line`/`baseline-dup`/`baseline-order` co-fire — reachable, per the decision log's "up to five verdict lines"), the tail remedy still advises `git checkout origin/main -- <rel>` followed by a `--print-baseline` regeneration. `origin/main` has no copy to restore and regeneration is exactly what `baseline-reintroduced` forbids. The gate itself cannot be weakened by this (exit stays 1), so this is operator-guidance quality only.

### Info — marker names `findings[0]`; a co-firing earlier class masks the token, not the verdict

`scripts/ci-pr-affected-replay.py:2045-2060,2102`. Findings append order is `unaudited, star-row, stale-accept, baseline-reintroduced, baseline-deleted, new-pair, stale-line, baseline-dup, baseline-order, grown`. The marker prints `reason=findings[0]`, so a tree with e.g. an unaudited suite alongside the re-add marks `reason=unaudited`. This cannot be gamed into a weaker outcome: every finding class is exit 1, CI gates on `rc` alone (`.github/workflows/ci.yml:444,452`), and the full report still prints every class with its remedy. `baseline-reintroduced` sits before `new-pair` per the settled ruling, so in the re-add-alone case the marker names it. By design; recorded for completeness.

## Focus-area verification results

**Arm fires on every base-absent/head-present path.** `ratchet_run` (replay.py:2058): `if head_text is not None and base_text is None`. `head_text` is `None` only on `FileNotFoundError` (replay.py:1903-1911) — an empty file yields `""`, which is `not None`, so **empty re-adds fire** (proven by `bl-empty.tsv` halves and the killed `ratchet-reintroduced-content-weakened` mutant). Unreadable/dir/out-of-tree-symlink baselines raise `ReadError` → exit 2 `baseline-unreadable` (infra precedence, before all verdicts — correct). The only earlier return is `--print-baseline` (replay.py:2019-2036), a developer-only drain tool CI never invokes.

**Findings order cannot be gamed into a weaker verdict.** There is no weaker verdict: all classes exit 1. Exit-2 conditions all precede verdict collection and are themselves failures. The arm's placement before the `elif new:` block (2058 < 2064) matches the settled ruling, and `row_rt_reintroduced_newpair` pins the co-firing `new-pair` detail lines.

**`--baseline`/`--base` cannot bypass.**
- CI invokes `python3 -I scripts/ci-pr-affected-replay.py ratchet --report "$full"` with no flags and no `${{ }}` in `run:` (ci.yml:444) — flag injection is local-only.
- `--baseline` is confined by `read_bytes` realpath guard (replay.py:1236-1240): absolute or `..`-escaping paths → exit 2, never a verdict. The same `rel` is read at the base via `git ls-tree`/`git show sha:path` (lint-ratchet.py:528-538) — repo-relative only.
- `--base` is `rev-parse --verify --end-of-options` with a leading-dash guard (replay.py:1873-1878); unresolvable → `base-unresolved` exit 2, never adoption. The helper is loaded **from the base commit** (`ratchet_load`, replay.py:1848), so a PR cannot weaken `baseline_at` and the baseline together (`row_rt_helper_pr_tree_ignored` covers a PR-tree helper reporting "baseline-reintroduced" — marker stays `grown`).
- Residual local semantics: `--base` to a pre-retirement commit that carries an identical baseline can pass present/present only if live ⊆ baseline exactly — the retained machinery doing its documented job, unreachable in CI. Consistent with the settled KEEP ruling.

**42 deleted accept rows — all genuinely orphaned.** Every deleted row keys `scripts/ci-pr-affected-audit.baseline.tsv` (verified: `awk` on the diff, 14 each under `ci-pr-affected-replay-{a,b,c}`, 2993 = 3035 − 42). The path becomes untracked in the same commit, so each pair is `path-untracked` → `stale-accept` the instant the file lands — orphaned, not a real gap riding the deletion out. No other path column appears in the deletions. Had any row survived, this PR's own ratchet would mark `stale-accept`.

**Widened edge cannot select on attacker-influenced paths.** `AFFECTED_PLUGINS_SOLEUR_TEST_CODEQL_TO_ISSUES_SWEEP_WIRING_TEST_SH_PATHS` (test-affected-paths.sh:519-523) is three literal repo paths — file-entry matching is exact equality, no globs, no directory prefixes. Naming convention matches sibling `CODEQL_*_TEST_SH_PATHS` arrays; self-inclusion of `scripts/lib/test-affected-paths.sh` is present (a narrowing edit selects the suite). Widening is fail-safe direction only.

**Guard-shaped additions have teeth.** `! grep -q '^grown' <<<"$ROUT"` present on `row_rt_reintroduced` (test:2473); it is what discriminates the `ratchet-adoption-refused` mutant (grown's guard widened to base-absent) — confirmed killed live, along with `ratchet-reintroduced-{tolerated,live-gated,content-weakened}`: **4 of 4 killed, 0 survivors** in the exported-copy run. `DECLARED_TOTAL=599` matches `^mutate ` (473) + `^ow_mutate ` (126); registered ranges 1-193/194-386/387-599 tile the space.

## Settled-ruling conformance (no contradictions found)

Token `baseline-reintroduced` (:2059, fits the `[a-z0-9-]+` marker class in ci.yml:446 and `MARKER_RE` at ratchet-observation-window-10865.sh:161) · present/present machinery kept · arm before new-pair block · absent-grown assertion present · single deletion commit (`ab487915f1`, only `D baseline.tsv` + coupled changes) · ci.yml step name byte-identical · `.gitattributes` line removed with the file. The observation probe already treats baseline-absent-at-tip as `grew=0` (followthroughs script :498, "absent at the tip is the end state (PR5 deletes it)") — consistent.

## Dissent notes

- The two P3s are quality nits, not gate weaknesses; neither blocks merge on security grounds.
- I confirmed the decision log's own dissent on the tail-remedy co-fire ("up to five verdict lines under one marker") and add the remedy-text variant above as its concrete consequence.

## Summary

PR #12127 retires the committed affected-index baseline and makes any re-add an unconditional exit-1 verdict. The `baseline-reintroduced` arm is presence-keyed (immune to accept rows, live-set contents, and findings-order gaming), fires on empty re-adds, sits exactly where the settled ruling put it, and is backed by four killed mutants including the `! grown` discriminating assertion — verified live with 4/4 kills and 715/715 green assertions on an exported copy. The 42 removed accept rows are all orphaned `baseline.tsv` keys, and the widened codeql-to-issues edge is three literal exact-match paths. No P1/P2; two P3s: a stale docstring lead sentence at replay.py:135-136 and a misleading restore/regenerate tail remedy that can co-print under a malformed re-add.

---
title: "Affected-audit accept rows must cover EVERY boundary line (the ratchet report shows a subset), and a full --timings-dir re-price can break committed-table invariants"
date: 2026-10-30
category: engineering
tags: [ci-pr-affected-replay, ratchet, accept-rows, shard-manifest, regenerate-shard-manifest, fast-tier-budget]
symptoms: [affected-index-ratchet new-pair on arm labels despite matching-anchor accept rows, stale-accept duplicate rows, test-all-fast-tier-budget red after an honest manifest regen]
module: CI
component: affected-index-audit
problem_type: test_failure
resolution_type: documentation
root_cause: incomplete_exemption_set + stale_committed_prices
severity: medium
issue: '#11562'
pr: '#11561'
---

# Two committed-table surfaces the --rows split broke — and the fixes

## 1. Anchor-keyed audit accept rows: the report's `ref` list is not the complete boundary set

Splitting `plugins/soleur/test/ci-pr-affected-replay.test.sh` into `-a/-b/-c` arm labels multiplied its audit pairs ×3 (each arm label audits the same file → `new-pair` ×9 on `.gitignore`, `README.md`, `ruff.toml`). The fix is anchor-keyed rows in `scripts/ci-pr-affected-audit.accept.tsv` — but a first pass using only the anchors printed under each `new-pair` in the ratchet report left `README.md` and `ruff.toml` still red: the report showed 3 README refs while the live boundary set is **12** (8 in the suite file + 4 in `scripts/ci-pr-affected-replay.py` — the suite's read closure feeds `texts`). A pair exempts only when EVERY boundary line has a row (`judge_rules`: `all((a,o) in want for a in lines)`).

Also: re-adding the same `suite<TAB>path<TAB>anchor<TAB>ordinal` rows with a different reason string produced `stale-accept: duplicate accept row` — the key is the first four columns; one reason per key.

**The complete source of truth:** `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs` — emits every `ref suite path file:line anchor/ordinal text` row actually counted. Build accept rows from that, not from the ratchet report's per-pair ref display.

## 2. A full `--timings-dir` re-price red-s the fast-tier budget on pre-existing drift

`test-all-fast-tier-budget` reads the **committed** `suite-durations.tsv`: `ALWAYS_ON` labels >10s each or >300s total fail. Committed prices on main were stale (e.g. `test-all-group-affected` 3,200ms vs a real ~352s CI median over 5 runs). A full `--timings-dir` regen honestly re-priced all incumbents → 8 always-on labels over cap → budget suite red — the drift pre-dated the PR but the regen made it the PR's red.

**Incumbent-preserving regen:** `python3 scripts/regenerate-shard-manifest.py --durations <seed>` where seed = committed durations minus dropped labels plus new-label estimate rows (`label<TAB>ms<TAB>measured`). Incumbent prices/legs stay within their committed epsilon; new labels pack by seeded weight; `separate_arm_groups` still spreads same-stem `-<letter>` siblings. The drift itself went to a deferral issue (#11648 — demotion per the #9763 doctrine), because an honest re-price is a separate S4 classification change.

## Prevention

- When a label rename/split touches a suite with `ci-pr-affected-audit.baseline.tsv` rows: baseline is shrink-only — delete the stale rows and add accept rows keyed on the new labels (per boundary line, all of them).
- Before `--write` on a regen, check what invariants read the generated file (`grep -l 'suite-durations' scripts/*.test.sh`) — a committed generated table is input to at least two guards (budget caps, keys-parity lint).
- `src=measured` on seeded estimates is known laundering (#11647 tracks the `est` tier).

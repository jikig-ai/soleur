# A standing tracker sinks below the `gh issue list` window — and three green-gap classes in a p90 ratchet

**Source:** PR #11842 (issue #11774, epic #11556 Lever E), one-shot pipeline 2026-11-02.

## The read-side decay of a standing tracker

`gh issue list --limit 100` returns **created-desc**; a weekly watch's standing tracker sinks below any fixed limit window in days at this repo's filing velocity (~216 open issues/week measured). A digest read built on "recent issues + exact-title match" silently renders its fallback forever — a quiet death that looks like a quiet week. Fix: **label-scoped read** (`gh issue list --label ci/<watch>` — a permanently-stable set, matching the `--label action-required` precedent), with the watch creating the label idempotently (`gh label create … || true`) and re-adding it on every `issue edit` so a stripped label self-heals. Add `author` to the `--json` fields and keep only bot-authored matches — the write side's bot-author gate has no automatic read-side mirror.

## Green-gap classes two seats converged on (a new ratchet's real defect space)

1. **A whole surface producing zero qualifying samples read GREEN** — the `unmeasured` finding fired per-check only when that surface had ≥1 sample; a dead surface produced zero findings and an exit-0 verdict. Fix: count runs-listed per surface; `listed>0 ∧ rows==0` → surface-level `unsampled` finding.
2. **A successful-but-empty/mis-shaped API payload evaded the failure counter** — `gh api` exiting 0 with a missing/renamed `check_runs` key yielded zero rows silently; only non-zero exits counted as fetch failures. Fix: a listed run emitting 0 sample rows counts as a failed fetch.
3. **Body-write-before-comment burns the sentinel** — rewriting the tracker body (which carries `drift=<sha>`) before posting the drift comment consumes the sentinel when the comment call fails; on a tracker with no prior sentinel comment the next run suppresses the repost permanently. Fix: post the comment BEFORE the body rewrite on the update path (duplicate-on-failure is the loud direction).

Meta-lesson: the structural-enumeration seat and the code-quality seat found the same dead-surface hole independently — for a ratchet/guard deliverable, "the window is narrower than the property" is the dominant defect class; allocate the enumeration seat early.

## Same-day bound-seed volatility

Bounds seeded from "measured p90 at implementation time" were stale within hours — merge-queue latencies moved 15–80% intra-day (queue congestion), and the instrument flagged its own baseline on `--dry-run`. Contract held: re-seed to the **latest** probe-verified measurement (ceil to minute) at commit time, and let the margin absorb future drift. A ratchet whose seed is a snapshot must be seeded by the instrument itself, not by a hand measurement (a hand pass under-sampled the ~55–80-check-run paginated payload — 30-item default page).

## Test-suite anchor traps the fix-round proved

- `assert body == *"test"*` is vacuous when the standing report table always contains every check name — anchor on the finding line's syntax (`- breach: \`x\` (\`y\`)`).
- A `p90` implementation is a `max` equivalent-mutant until a bucket has ≥11 samples (nearest-rank `ceil(0.9n)-1 == n-1` for all n≤10) — assert exact values on a ≥11-sample bucket.
- A fixture where the "wrong" branch also happens to satisfy the `min_by` fallback doesn't discriminate — make the foreign candidate closer to the anchor so the preference arms diverge.

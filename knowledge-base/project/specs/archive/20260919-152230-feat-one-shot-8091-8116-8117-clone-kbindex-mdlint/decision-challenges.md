# Decision challenges — feat-one-shot-8091-8116-8117-clone-kbindex-mdlint

Headless plan-review / Step 4.5 record per ADR-084. `ship` Phase 6 renders this under
`## Model Dissents (informational)` and files an `action-required` issue only when a
Taste or User-Challenge row is present.

**Mode: headless** (one-shot Task subagent).

---

## Plan-review panel (2026-09-14)

No Taste or User-Challenge findings. Option choices on the three issues were
technical forks (`hr-technical-fork-is-not-an-operator-question`) and were
auto-decided in the plan:

- #8091: ship-merge-only `git fetch --unshallow` after `gh pr checkout`, not
  substrate-wide `--filter=blob:none` (ADR-099 keeps `--depth=1` on the agent
  sandbox; unshallow is host-side `spawnSimple`).
- #8116: DIRTY-but-locally-clean sync via merge-tree, not "stop committing
  INDEX.md on feature branches" (ADR-210 keeps the committed artifact + local
  driver).
- #8117: `git config gc.auto 0` after `git init` in `build_sandbox`.

Mechanical plan-review applications (already in the plan body): unshallow
continue-on-complete-repository; Phase 7 fixture split so default `git()` rc=0
cannot convert a real-conflict DIRTY test into a sync; ephemeral clone has no
kb-index driver so hosted Phase 7 DIRTY still dirty-exits on a true INDEX.md
conflict.

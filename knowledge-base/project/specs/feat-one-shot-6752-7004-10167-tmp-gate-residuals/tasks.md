# Tasks — tmp-gate residuals (#6752, #7004, #10167)

Derived from `knowledge-base/project/plans/2026-10-13-fix-tmp-gate-residuals-plan.md`
(post inline review). One bundled PR. AC# maps to the plan's Acceptance Criteria.

Legend: `[ ]` todo · `[x]` done.

---

## Phase 1 — #10167: block-aware presence check + fixture suite

- [ ] 1.1 Write `plugins/soleur/skills/skill-security-scan/test/parse-override.test.sh`
      FIRST (RED): scratch-repo fixture (`SUITE_TMP` + owning `trap … EXIT`
      before any `source`), arms = block-mapping `findings_json` accept,
      flow-style accept, absent `findings_json` reject, declared-but-empty
      reject, nested-under-another-key reject, second artifact missing
      `timestamp` reject, `verdict: LOW-RISK` reject. Seed `rule_pack_sha256`
      from the real manifest's `sha256sum` at runtime. → AC1, AC2, AC3
- [ ] 1.2 Replace the `grep -qE "^${f}:[[:space:]]"` loop
      (`plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh:73-77`)
      with the single `awk` presence pass: `^f:` top-level key AND (non-empty
      same-line value OR a following indented line before the next top-level
      key). `^`-anchored; comments/blank lines neutral. → AC1, AC2
- [ ] 1.3 Run the new suite (GREEN), plus
      `bash scripts/skill-security-scan-step-body.test.sh` and
      `bun test plugins/soleur/test/skill-security-scan.test.ts`.

## Phase 2 — #6752: verify + close

- [ ] 2.1 Re-verify the three sites on the worktree:
      `grep -n 'mktemp\|trap\|rm -f' scripts/learning-retrieval-bench.sh`,
      same for `scripts/weekly-analytics.sh` and
      `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` —
      each stray alloc must be `rm -f`'d on all paths or under an owning trap;
      constraint-scaffold's `trap '_wt_cleanup' EXIT` is the single owner.
- [ ] 2.2 Confirm `python3 scripts/lint-trap-tempfile-ownership.py --census`
      unchanged (the three files are not class-b members).
- [ ] 2.3 `gh issue comment 6752` with the evidence (census Mandatory-rows cite
      + fresh verification output). PR body carries `Closes #6752`. → AC4

## Phase 3 — #7004: bounded producer adoption

- [ ] 3.1 `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`:
      opportunistic `source scripts/lib/scratch-root.sh` +
      `soleur_scratch_session_begin` before the first `mktemp` (:163), mirroring
      `scripts/test-all.sh:505-515` (missing lib degrades, never blocks).
      Splice `_soleur_scratch_cleanup` into the FINAL EXIT-trap assignment
      (:1714) — ADR-129, never a second trap. → AC5
- [ ] 3.2 `plugins/soleur/scripts/harness-discovery-smoke.ts`: import +
      `ensureScratchSession()` at entry (top-level statement before `main()`
      runs — same placement as `git-tripwire.ts:108`). → AC6
- [ ] 3.3 Verify `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
      passes standalone; then register it as a `sh` leaf in
      `tests/scripts/test-scratch-residue.sh` (`add_leaf sh-cloud-init-inngest …`).
      If standalone run is not green, keep 3.1's `begin` (no-op under runner)
      and register no leaf — record the reason. → AC5
- [ ] 3.4 Run `bash tests/scripts/test-scratch-residue.sh` (green incl. new
      leaf delta + counting arms) and
      `python3 scripts/lint-trap-tempfile-ownership.py --census` (unchanged). → AC7

## Phase 4 — bookkeeping + deferred-tail tracking

- [ ] 4.1 File the deferred-tail issue: "tmpfs-guard: adoption tail — Tier-3
      `env -i` sites, absolute `/tmp` literals, day-7 soak probe" (Refs #7004;
      cite the safety rationale: ~25+ judgement calls per the recorded
      decision-challenge). Verify label names via `gh label list` first;
      use `domain/engineering`, `type/chore`, `priority/p3-low`. → AC8
- [ ] 4.2 `gh issue comment 7004` linking the tracking issue + summarizing the
      landed adoption residual.
- [ ] 4.3 `gh issue edit 7004 --remove-label deferred-scope-out`. → AC8
- [ ] 4.4 Check `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv`
      for whether the new suite needs explicit rows; update if the registry
      requires them.
- [ ] 4.5 PR body: `Closes #6752`, `Closes #10167`, `Refs #7004`,
      `Refs #8786` — and NOT `Closes #7004` (close-condition is the #8786
      drain evidence). → AC8

## Verification (whole)

- [ ] V.1 `bash plugins/soleur/skills/skill-security-scan/test/parse-override.test.sh` → `OK:` line, rc 0
- [ ] V.2 `bash tests/scripts/test-scratch-residue.sh` green
- [ ] V.3 `git diff --quiet origin/main...HEAD -- scripts/learning-retrieval-bench.sh scripts/weekly-analytics.sh plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh .claude/hooks/lib/session-state.sh apps/web-platform/infra/workspaces-cutover.sh` → clean
- [ ] V.4 New suite discovered by test-all glob: `bash scripts/test-all.sh --print-suite-globs` lists it (or equivalent enumeration)
- [ ] V.5 Pre-existing failures are out of scope: #7210 tmpfs-guard socket-held-tree, #8335 five-suite pre-existing — do not chase.

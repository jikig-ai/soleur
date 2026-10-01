# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-17-fix-git-data-boot-signal-poll-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. All deepen-plan halt gates passed (4.6 User-Brand Impact, 4.7 Observability, 4.8
PAT-shaped, 4.11 Guard Contract); 4.5/4.9/4.10/4.55 evaluated and skipped with recorded
dispositions. `lint-guard-contract.py` and `lint-infra-no-human-steps.py` green.
NOTE: `lefthook` is not on PATH in this worktree, so commit hooks did not run.

### Decisions
- Route the poll through `doppler run -p soleur -c prd_terraform` rather than reconciling two
  credential stores; the step's own error text already names prd_terraform while binding GitHub
  secrets, and those secrets predate the git-data source.
- Keep the two terminal branches separate and fix the predicate, anchored on whether the FINAL
  read answered. Verdicts: received / silent / unreadable.
- Extract only the classifier's partition (`bs_read_classify`) into `scripts/lib/`, leaving
  `_bs_read_remedy` in place.
- Library goes in `scripts/lib/`, not `tests/scripts/lib/` — `lint-diagnosis-claims.sh` excludes
  `/tests?/` twice over, so conventional placement would move this change's operator prose
  outside the gate it exists to satisfy.
- Add a `BOOT_TRAIL_SINCE` run anchor as `dt > fromUnixTimestamp(<anchor - 120s>)`; `host_name`
  pins the host, not the host generation.
- Failure surfaces rc + classification + body byte-length + scrubbed stderr, NEVER the raw body
  — the repo is PUBLIC and a ClickHouse 403 body carries the query username.

### Operator decisions taken at the Step 1-2 boundary (this session)
- SCOPE: wire BOTH `git_data_host_create` and `git_data_host_replace`. Confirmed by operator.
- SIGNOFF: brand-survival stays `single-user incident`; `requires_cpo_signoff: true` accepted.

### Lead-verification corrections made by the pipeline runner (not the planner)
- The hand-back claimed a fix wired only into the birth job "cannot fire". MEASURED FALSE as
  stated: `git_data_host_create` RAN and FAILED in both cited runs (34822248580, 34836141887),
  with `git_data_host_replace` skipped. That is #8178's entire evidence base. The accurate,
  narrower claim is about the future (birth is once-ever; the live path is now `replace`). The
  plan's own prose was already correctly qualified; a clarifying paragraph was added so the
  short form cannot propagate.
- Deferred tracking issues owed (from planning): the seven workflows still binding the GitHub
  Better Stack secrets; a pre-existing 130-day-stale `gdpr-gate` rule corpus.

### Components Invoked
soleur:plan, soleur:deepen-plan; agents repo-research-analyst, learnings-researcher,
soleur:engineering:cto, spec-flow-analyzer, plan-review panel (code-simplicity-reviewer,
architecture-strategist, dhh-rails-reviewer, kieran-rails-reviewer); gdpr-gate.sh,
lint-guard-contract.py, lint-infra-no-human-steps.py; gh, doppler, git.

## Work Phase (resumed 2026-09-18)
- Rebased onto origin/main 4b087c388 (merge-tree measured clean at that SHA; main's #8252
  edit to apply-web-platform-infra.yml is in `inngest_host_replace`, not a git-data job).
- Phase 5 DONE: scripts/followthroughs/git-data-boot-poll-8178.sh + .test.sh (63/0; 24/24
  mutants killed; one live end-to-end run through the real `gh` → NOT YET on pre-fix runs).
  Registered in scripts/test-all.sh.
- Phase 6 was NOT fully done at resume: 6.2 (ADR-192 addendum) and 6.3 (AP-027) were absent
  from the diff. Both now written; ADR-149's amendment cites AP-027 and the probe.
- Plan corrections: directive needs `secrets=GH_TOKEN`; unreadable log exits 3 (the sweeper
  renders 2 as NOT YET); frontmatter `closes:` -> `ref:`.
- OWED AT SHIP, right after merge (a missing script makes the sweeper `fail` daily, so NOT
  before merge): add to #8178's body
  `<!-- soleur:followthrough script=scripts/followthroughs/git-data-boot-poll-8178.sh earliest=<merge+1d> secrets=GH_TOKEN -->`
  and the `follow-through` label. PR body uses `Ref #8178`, never `Closes`.
- Deferred filings owed (plan §Deferred Items 1-2) are handled at the Phase 4 filing gate.

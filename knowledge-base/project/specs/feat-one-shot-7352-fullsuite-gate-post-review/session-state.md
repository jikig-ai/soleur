# Session State

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-08-11-chore-move-full-suite-gate-post-review-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #7470 (stays draft — see OD2)

### Errors

Six defects in the planning subagent's own output, each caught by a gate rather than by the author:

1. ADR ordinal probe wrong (reported max `ADR-180`, actual `ADR-182`; `ADR-181` held by the sibling branch it was forbidden to read). Corrected to **183**; two reviewers caught it independently.
2. R4 classified as a coverage gap when it is already CI-gated (`plugins/soleur/test/terraform-target-parity.test.ts:2055`, in the `bun` shard, feeding the required `test` context). Falsified a row in its own regression table.
3. `FULLSUITE_SHA` had no persistence substrate — the Bash tool carries only CWD between calls, so the gate would have failed on 100% of PRs and re-run the battery on every infra diff, reinstating the cost the plan exists to remove. Its own mutation proof would have passed against the degenerate gate.
4. `## Observability` claimed "not applicable" incorrectly (the exemption covers `.md` *outside* `plugins/*/skills/`). Deepen-plan gate 4.7 halted; a real 5-field block was written.
5. Internal contradictions: Files-to-Edit instructed "name Phase 4 the merge gate" while AC10 forbade that exact string; AC6 required change on lines AC7 required verbatim.
6. Its own revision introduced five stale-live defects (assertion count, cut tripwire, cut ACs cited as live mitigations, an orphaned AC13-15 block reintroducing deleted SHA-pin phrasing). Caught by the Phase 4.45 self-audit pass.

### Decisions

- **The issue's central premise is wrong in a way that makes the change safer.** The local runner was never the merge gate — CI ruleset 14145388's required `test` context is, aggregating three `test-all.sh` shards. The one real gap is `apps/web-platform/infra/`, which no required context reaches.
- **Phase 2 runs `TEST_GROUP`-scoped `test-all.sh`, not a hand-derived command set.** Replaced a `vitest --changed` + `git grep -l` derivation and dissolved six findings at once: preserves the contention banners, the `EXIT CONTRACT`, and the rc discipline, and has no empty-set state — which the drafted design's own dogfood diff landed in.
- **The one surviving ceiling: ship Phase 4 stays `TEST_GROUP=all`.** Guarded by a single assertion whose mutation is *sharding*, not deleting.
- **Cut aggressively**: the SHA pin, the infra re-run trigger, 4 of 5 guard assertions, 8 of 17 ACs, the cap rule, and the falsifiability tripwire.
- **Threshold raised to `single-user incident`** on blast radius.

### Operator Decisions (2026-08-12) — post-subagent, authoritative

`plan-review` classified the session as headless and persisted the decision-challenges instead of
asking. That premise was wrong; the session is interactive. Both open items were put to the operator:

- **OD1 (UC1) — apply CPO's C1 conditional.** The four project-agnostic lines are relaxed *with* the
  conditional; the detection question is **in scope for `/work`**, not deferred. Plan AC11/AC12.
- **OD2 (UC2) — hold the merge for #7441.** Implementation/review/QA proceed; PR stays **draft**.
  Plan AC13 + Pre-merge hold H1-H4. `wg-verified-work-ships-without-asking` is overridden by this
  explicit operator sequencing instruction.
- **OD3 (UC3)** — milestone placement not asked; open and non-blocking.

### Components Invoked

`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` · agents: `repo-research-analyst`,
`learnings-researcher`, `cto`, `functional-discovery`, `dhh-rails-reviewer`, `kieran-rails-reviewer`,
`code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cpo`, plus a Phase 4.45
realism agent.

## Work Phase

- Status: implementation complete; verification in progress
- Commits: guard test + work/ship/plan SKILL.md, ADR-183, backtick fix, spec deviations

### Sibling landed mid-session

PR #7441 merged 2026-08-11T17:27:07Z. The Phase 0.5 FAIL-HARD rebase (this plan edits
`ship/SKILL.md`) pulled it in, which satisfies **OD2 H1 + H2**. Consequences:

- Every plan-quoted line number drifted ~+12; content anchors used throughout.
- `plugins/soleur/test/fanout-suite-scope.test.sh` is now on `main` and its Arm 4 pins two literals
  inside `work/SKILL.md` (`run only the suites targeting the files they were given`, and
  `SOLEUR_SUBAGENT=1`). Both verified preserved after the §9 rewrite.
- #7441 added `test-all.sh` exit 4 (refuse a full-gate run under `SOLEUR_SUBAGENT=1`), which is
  complementary: it reduces the cost of each run where this change reduces the number of runs.

### Verification status

| Gate | Result |
|---|---|
| Guard test | RED (1 pass / 4 fail) → GREEN (5 pass) |
| Mutation matrix | 6/6 RED, restore byte-identical, post-restore baseline green |
| `bun test plugins/soleur/` | 2445 pass, 9 skip, 1 environmental fail (#6842) |
| markdownlint | delta 0 vs `origin/main` (work=12, ship=16, plan=5 on BOTH) |
| enforcement-tag linter | OK — 31 skill tags resolved, incl. the preserved `work Phase 2 exit` anchor |
| ADR ordinal checker | pass |
| credential-path-guard | pass |
| Phase-2 touched-shard gate (dogfood) | `bun` shard rc=1 on #6842 only; `scripts` shard pending |

### Known-flaky, confirmed three ways — NOT this diff

`changelog-data.test.ts > returns html from GitHub Releases API` fails at ~5000 ms (bun's default
timeout) only under concurrent load; it fetches the live GitHub Releases API. Confirmed by isolated
re-run (3/3 pass), by the file being untouched on this branch, and by CI green on `main`. The same
log carries `SIBLING_RUN_DETECTED` and `LOCK_CONTENDED_PROCEEDING` (lock held 900 s) with two
sibling worktrees running. Already tracked as **#6842** — no new issue filed, net issue flow 0.

### Deliberately NOT run at Phase 2 exit

The full `TEST_GROUP=all` battery. Running it here would contradict the reordering this PR ships and
would verify a tree that review is about to change. It belongs at `/ship` Phase 4, which is also
where **OD2 H3** wants it — on the rebased, post-review tree. An early run was launched, then killed
(ownership resolved via `/proc/<pid>/cwd`; the three sibling sessions were left untouched).

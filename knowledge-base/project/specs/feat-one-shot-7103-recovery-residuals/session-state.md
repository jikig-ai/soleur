# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-01-fix-7103-recovery-residuals-r1-r5-plan.md`
- Status: complete
- Draft PR: #7146
- Scope check: PASSED — `git diff origin/main...HEAD --name-only` returned only
  `knowledge-base/project/plans/` + `knowledge-base/project/specs/`. No product code,
  workflow YAML, infra script, or CHANGELOG was touched by the planning subagent, so its
  "Decisions" are prescriptions rather than applied changes.

### Errors
- First plan write blocked by the IaC-routing PreToolUse hook (`systemctl` in plan prose).
  Resolved by adding the required `## Infrastructure (IaC)` section + `iac-routing-ack`
  marker — not by weakening the routing.
- A second write failed "file modified since read" after a linter touched the file;
  resolved by remove-and-recreate rather than reading a ~900-line file back into context.
- Verification sweep found one self-contradiction and corrected it in the plan:
  `run-registered-suites.sh --list | wc -l` returns 88 because the runner prints a
  `Derived N registered infra suite(s)…` header; Phase 0.2 now uses
  `| grep -c '\.test\.sh$'` expecting 87.

### Coordinator verification of plan claims (independent, post-return)
Three load-bearing claims were spot-checked before accepting the plan — the Session
Summary narrative was not trusted on its own:
1. **Repo is PUBLIC** — `gh repo view --json visibility` = `PUBLIC`. Confirms the
   `::add-mask::` requirement for R4 is real, not defensive.
2. **Suite count 87** — `run-registered-suites.sh --list | grep -c '\.test\.sh$'` = 87.
   Plan's prescribed command and expected value agree with measurement.
3. **`vector.service` runs `User=deploy`** — CONFIRMED. The unit is a heredoc inside
   `apps/web-platform/infra/soleur-host-bootstrap.sh`, not a standalone `.service` file
   (first grep missed it). `User=deploy` / `Group=deploy` verified verbatim. Its
   `ExecStart` also wraps vector in `doppler run --project soleur --config prd`, which
   independently corroborates R3: vector's own process dies with the credential whose
   failure it is supposed to report.

### Decisions
*(what the plan PRESCRIBES — nothing was applied during planning)*

- **R1 split into two halves; half (a) re-filed rather than implied.** Second invoker
  named as `apply-deploy-pipeline-fix.yml` › *Redeploy to load applied profile*. But the
  residual's remedy "give it `ZOT_REGISTRY_URL`" has no invoker-side site — both hooks
  pass identical environments and the URL resolves inside `ci-deploy.sh` from Doppler.
  Plan prescribes half (b) (loud failure on the credential-absent gate arm, the only arm
  lacking a degraded event) plus a 4-field `SOLEUR_DEPLOY_INVOCATION` marker as the
  discriminator, holding both hypotheses at UNKNOWN until it has been read. The residual's
  short-form log string does not exist at HEAD — the outage-fix PR replaced it — leaving
  "stale script" a live hypothesis the plan refuses to grade from source.
- **R2 picks option (b), gated on a security precondition absent from the residual's
  option set.** `infra-config-install.sh` validates drop-in content only for
  `/etc/default/*`; the three `*.service.d/*.conf` dests get none. With
  `vector.service` running `User=deploy`, a drop-in may set `User=root` + `ExecStart=` —
  inert today only because nothing root-restarts the unit. A drop-in shape gate therefore
  ships BEFORE the restart grant, for all four options.
- **R3 fixes the consumer, not the emitter, and repairs two defects in the existing
  control.** The canary already exists but runs inside `doppler run`; and
  `betterstack-query.sh` has no `--host` flag while `--grep` terms OR-combine, so a
  foreign host's canary could certify this host. Prescribes hoisting the emit out of the
  credential wrapper, a host-scoped raw-SQL read, and a four-outcome helper where
  `unknown` and `unshipping` can never return 0.
- **R4 accepts required-check gating deliberately.** The harness needs no tooling the
  required `test` job doesn't already run; the advisory alternative would put a regression
  guard in a runner nobody is blocked by — reproducing, in the same PR, the exact defect
  R5 exists to fix. Adds `::add-mask::` because the repo is public and the digest step
  `nonsensitive()`s a base64 of the live prd Doppler token.
- **R5(b) was already done** by the credential-channel PR (it re-anchored the liveness
  gate's assertions). Plan prescribes the missing half — a committed 7-arm mutation
  battery proving deletion goes red — not a second learning file.
- **Phase order follows the risk ranking** (R1 → R5(a) → R2 → R3 → R4 → R5(b)), with
  R2→R3 a hard dependent pair. One consequence recorded: R1's tests live inside the runner
  Phase 2 folds in, so Phase 1 is re-verified at the exit gate.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Research: `Explore` ×4 (infra/vector, CI test globbing, R5 suite gap, prior plans/ADRs)
- Review panel (escalated by the `single-user incident` threshold):
  `architecture-strategist`, `code-simplicity-reviewer`, `spec-flow-analyzer`,
  `security-sentinel`, `observability-coverage-reviewer`, `user-impact-reviewer`, plus an
  `Explore` verify-the-negative / attribution / count sweep
- `gh` (issue/PR/ruleset/repo-visibility reads), `git fetch origin main` + ADR-ordinal
  derivation, `git log -S`, `git commit`/`push`

---

## Work Phase — session 2 (2026-08-02), resumed after the 2026-08-01 Warp crash

**Verify these against the artifacts before trusting them.** Every claim below was measured in
this session; the entries are past-tense because they are done, not because they were intended.

### Recovery (pre-plan)
- **Divergence resolved.** Local was the superset: `git cherry` marked BOTH remote-only commits
  `-` (equivalent patch present), patch-IDs matched pairwise, and the remote→HEAD diff had ZERO
  deletions. Published with `--force-with-lease` pinned to the verified SHA. Local == remote.
- **Uncommitted work adjudicated.** The `SOLEUR_CRED_FILE` seam in `ci-deploy.sh` was REVERTED,
  not committed: `ci-deploy.test.sh`'s F16 header had already weighed that exact override and
  rejected it ("a production surface … the wrong trade"), and its (e) arm caught it. The marker
  tests now redirect the credential path by rewriting the literal in a COPY of the script — F16's
  own technique at file scope — so this PR's production diff for that change is zero.
  Second defect: the new block sat AFTER the strict-mode restore, so a legitimate `grep` no-match
  killed the suite before its summary (which is why its last assertion had never been observed).
  ci-deploy.test.sh is 212/212.
- **CI `lint-bot-statuses` root-caused to the PLAN, not the code.** `lint-infra-no-human-steps.py`
  flagged 3 lines; all three are NEGATED mentions ("REPLACES the operator-local apply", "a CI
  lever INSTEAD OF", "NOT an operator-local apply"). Wrapped inline with paired
  `lint-infra-ignore` markers (both markers on one line — the linter checks `end` before `start`,
  so the line is skipped with no open region; this is also the only form safe inside a table row).
  The 4 later steps in that job had never run behind the fail-fast; all 4 pass.

### Phases complete
- **Phase 1 (R1) — DONE.** 1.1-1.6 shipped earlier; 1.7 + 1.8 closed this session.
- **Phase 2 (R5(a)) — DONE.** 2.1-2.6. Mutation-proved; see the commit body for the transcript.

### AC corrections made rather than reported as passing
- **AC-R5-3 was VACUOUS.** Its literal never appeared on one line (the target comment wraps after
  "does NOT"), so it returned 0 against the UNMODIFIED file and would have certified Phase 2.4
  before a byte changed. Measured: literal 0, shape 5. Corrected to a scoped shape (an unscoped
  form matches a still-TRUE claim about `scripts/*.test.sh` globs).
- **AC-R5-1 is +5, not +4** (corrected in the prior session's commit; the five are enumerated).

### Live production finding (NOT in this plan's scope)
`soleur-web-2` is still failing to pull images. Pulled from Better Stack in-session: the
"two ci-deploy invocations ~73s apart with different credential environments" in the residual are
TWO HOSTS (host_name/_MACHINE_ID/_BOOT_ID all differ), joined by
`FANOUT: peer 10.0.1.11 accepted deploy (HTTP 202)`. web-1 went `ZOT_GATE: active` after the
credential landed; web-2 stayed dark and its `IMAGE_PULL_FAIL … auth_denied` recurs on the newest
tag (v0.247.6 @ 20:29:30Z). Consequences: **F6 ("deploy-peer is dormant at single-host") is
FALSIFIED**; the pull failure MIGRATED rather than stopped; and the misattribution was produced by
the very R3 defect this tracker records (`betterstack-query.sh` has no `--host` flag, `--grep`
terms OR-combine). This is issue B4, outside R1-R5 — evidence filed as a tracker comment, scope
NOT widened.

---

## Work Phase — session 3 (2026-08-02)

**Verify these against the artifacts before trusting them.** Everything below was measured this
session. Past tense means done, not intended.

### Phases complete
- **Phase 3 (R2) — DONE.** 3.1–3.11, in the mandated order (shape gate before grant).
- **Phase 4 (R3) — DONE.** 4.1–4.8.
- Phase 0 preconditions executed this session: 0.6 (FILE_MAP = **19**), 0.9, 0.10, 0.11, 0.12.
  Still unrun: **0.1, 0.3, 0.4, 0.5, 0.7, 0.8** — 0.4/0.5/0.7/0.8 gate Phase 5, so run them first.

### Findings that changed the work (not just executed it)
- **A mutation battery found a real gap rather than confirming the work.** 8 mutations, 7 killed
  immediately. The survivor: deleting the mtime-preservation `touch -r` in
  `infra-config-install.sh` left `infra-config-apply.test.sh` green at **106/106** — every install
  in that suite runs in SANDBOX mode (direct `mv`), while in prod the helper writes its own temp
  in the dest dir and discards whatever the caller preserved. The production path had zero
  coverage. Now asserted against the helper directly, both directions; mutation killed.
- **The reconciliation loop was unreachable when first written.** The suite was 70/70 green while
  every unit resolved to `unit_inactive` on any dev box or CI runner, so the whole staleness and
  grading path never executed. Fixed with stateful, argv-validating (`exit 64`) stubs through the
  `INFRA_CONFIG_SYSTEMCTL*` seams.
- **`touch -r` in the caller alone was wrong.** Traced to the real producer: in prod the write
  goes through the root helper, so the caller-side preservation is discarded before the rename.
  The fix had to land in `infra-config-install.sh`.

### Deliberate deviations from the plan (each with its reason)
- **3.8 `active != active`.** Plan called for a hard fail on any unit not active. Every case where
  the handler *acted* and the restart did not take is already covered by the three failure enums,
  which fire regardless of resulting state. Extending it to SKIPPED units would permanently red
  the gate on a host where the unit legitimately does not run (`inngest-heartbeat.service` is
  created by `inngest-bootstrap.sh`, so it is co-location dependent). Those now `::warning::` by
  name. "Is vector actually shipping?" is R3's question, answered at the sink.
- **3.2 sudoers formatting.** One line with two commands (the `INNGEST_QUIESCE` precedent in the
  same file), not the plan's line-continuation — so 3.10's argv lockstep extracts it without
  reassembling continuations. `visudo` parses it.
- **3.9 stale counts.** A grep sweep found **6** stale counts, not the 2 the plan named. Fixed the
  3 live ones (install.sh ×2 said 18, sudoers said 11, actual 19) **count-free** rather than
  re-pinned to 19 — `infra-config-install.test.sh` already records why a literal pin is a third
  source of truth that goes stale on every FILE_MAP addition. The 2 in `push-infra-config.sh` were
  LEFT ALONE: they sit inside dated nonce rationale describing what the host held at a past
  moment, so correcting them would falsify the record.

### Components / gates
- Filed **#7170** (AC12 soak) + cross-link comment on #7103 — **verified present** by re-reading
  the issue, not recorded on the strength of intending it.
- Filing gate: Closing 0 / Filing 1 / **Net +1**, justified inline (a post-apply soak cannot be
  inlined; a dedicated issue is required because the sweeper closes on PASS).
- `code-simplicity-reviewer` CONCUR gate NOT run — agent spawning is disabled this session. The
  cost-of-filing test was applied inline instead.

### Verified at this checkpoint
`run-registered-suites.sh` **87/87**. infra-config-install 44/44, infra-config-apply 106/106,
infra-config-gate 29/29, infra-config-handler-bootstrap 36/36, journald-config 79/79,
betterstack-assert-absence 44/44 (23 when this line was first written; the P2 --since fix and the 2026-08-03 review each added arms), web-zot-consumer-probe green. `terraform fmt -check` clean.
`visudo -cf` parses. All shellcheck findings on touched files are pre-existing or annotated.

### Exit gate (Phase 8) — measured on the final clean tree

- `scripts/test-all.sh` → **rc=0, `=== 248/248 suites passed ===`** (terminal marker, not an
  intermediate `Total:` line). Zero failures.
- Both nested runners were invoked BY test-all.sh and both `[ok]`:
  `run-registered-suites.sh` (268s, 87/87) and `.github/scripts/test/run-all.sh` (161s).
  Phase 2's R5(a) registration is doing its job — the epilogue NOTE confirms
  `apps/web-platform/infra/` IS covered via the nested runner.
- Contention epilogue clean: 4% `/tmp` used, 3959MB avail, delta 26 entries. **No banner fired** —
  the `LOW_TMP_HEADROOM` / `SIBLING_RUN_DETECTED` grep hits are the contention SUITE's own `[ok]`
  assertion lines, exactly the false positive the runner's guidance warns about.
- 8.2 (as measured on the pre-review tree) `shellcheck` on all **19** changed `.sh` files (the "20" counted `deploy-inngest-bootstrap.sudoers`,
  which shellcheck cannot lint); `actionlint` **1.7.7** — the version `ci.yml` pins; the "1.7.12"
  claim named a version this repo does not use — clean on the one edited
  workflow (the plan said "two" — only `apply-deploy-pipeline-fix.yml` was touched).
- 8.3 `AGENTS.md` (5290 B) and `AGENTS.rules.md` (37330 B) byte-identical to `origin/main`.
- 8.4 every citation in ADR-159 / tasks.md / session-state resolves.

**Plan arithmetic correction.** 8.1 says "baseline + 4"; the measured delta is **+5**. All five are
plan-mandated — the two nested runners (2.1), `betterstack-assert-absence` (4.8),
`digest-oracle-guard` (5.6), `cf-tunnel-liveness-gate-mutations` (6.3). The plan's own "+4"
omitted 4.8's suite from its count. The delta is correct; the plan's arithmetic was not.

**A shellcheck directive of mine was disabling checks for ~900 lines.** Written as
`# shellcheck disable=SC2016 -- <prose>`, which does not parse (SC1072/SC1073) and ABORTS analysis
of the rest of the file. It surfaced as a reported syntax error at line 984 that `bash -n`
disagreed with — the tell that the LINTER's parse was failing, not the script's. Fixed; the file
now reports only pre-existing advisories.

### Review phase (inline, DEGRADED — read this before trusting the coverage)

**Reviewed with 0 of ~10 agents.** Agent spawning is disabled for this session, so the
multi-agent panel did NOT run. This was the sanctioned Gate 2a inline fallback, not a full
review. What that costs: the panel's independent lenses (security-sentinel, test-design-reviewer,
architecture-strategist in particular) are exactly the ones that historically catch what a
self-review misses on this class of diff — and the author of the code is the reviewer here.
Treat the findings below as a floor, not a clearance.

**3 findings, all pr-introduced, all fixed inline (0 filed).**

1. **P1 — the PR body would have auto-closed #7103.** Caught by task 8.5's own check. The opening
   line read "Closes #7103's R1–R5"; GitHub's close-keyword parser is word-boundary based, so it
   would have closed the tracker on merge with B1–B7 and R1's half (a) still open — precisely the
   outcome 8.5 and the tracker's exit gate exist to prevent. The sentence that violated the rule
   was the sentence *explaining* the rule. Rewritten; re-verified 0 adjacencies in BOTH the PR
   body and the commit bodies that will be squashed.
2. **P2 — `betterstack-assert-absence.sh` reported a usage error as an OUTCOME.** `since_secs()`
   fed the flag straight to `$(( ))`; an arithmetic EXPANSION error is fatal at expansion time, so
   the `|| echo -1` never ran, `set -e` killed the script, and it exited **1** — which is
   `present` in its own table. The follow-through probe maps `present` to FAIL, so a typo'd window
   would have told the operator the credential channel had regressed. Measured: `--since
   '1;evil h'` exited 1 silently. Now shape-validated by regex (so `$(( ))` only sees digits) plus
   an integer assert before the SQL interpolation; 6 malformed shapes pinned.
3. **P3 — the drop-in gate's residual surface was undocumented.** `Environment=` is permitted and
   accepts `LD_PRELOAD` (verified adversarially). Acceptable here for a SPECIFIC reason now
   recorded in the file: both granted units run `User=deploy` and the handler already runs as
   deploy, so it is lateral rather than escalation — and `User=` is forbidden precisely so that
   stays true. Noted with the condition that would invalidate it (a future root unit in
   RESTART_MAP).

**Adversarial testing of the drop-in shape gate** (the security precondition) — 9 payloads:
continuation-smuggling `ExecStart`, comment-continuation swallowing, CRLF, UTF-8 BOM, trailing
comment on `[Service]`, leading-whitespace `ExecStart`, `[Unit]`, `LD_PRELOAD`, positive control.
Every escalation attempt rejected; the two accepts are correct-by-design and now documented.

### Resume point
**All implementation phases are DONE (0 through 8).** The only open task is **8.5** — use
`Ref #7103` in the PR body, never `Closes` — which belongs to `/ship`.

Remaining: **/compound -> /ship**. Review is done (inline, degraded — see above).

> **SUPERSEDED 2026-08-03.** The degraded review above was re-run with the full 12-agent panel,
> which is what the paragraph below asked for. It found ~60 findings, 15 P1, and three
> merge blockers the green branch could not see. See "Review Phase — session 4" at the end of
> this file. The line below stands as the record of what session 3 knew; it is no longer the
> current state.

`/ship` still owes: `gh pr ready`, the Phase 5.5 review-findings exit gate, and auto-merge. The
PR body is already written and safe (8.5 verified on both surfaces). If the panel can be run in a
later session, run `/review` again BEFORE shipping — this diff grants a root restart on a host
with no replacement path, and a 0-agent review is thin evidence for that blast radius. (/qa does not apply: the diff touches no
`apps/web-platform/app/(dashboard)/**`, `components/dashboard/**` or any `layout.tsx`.)

A PR body is drafted and ready for /ship, carrying 5.7's required-check gating decision verbatim,
the Net +1 issue-flow accounting, and a post-merge section with no operator steps.

Note for Phase 8 (SUPERSEDED by this PR's own R5(a) — kept for the record, corrected here):
`scripts/test-all.sh` now INVOKES `run-registered-suites.sh` as a nested suite when `want_infra`
holds and the diff touches that directory. What was true when written — that both runners
are required, and `betterstack-assert-absence.test.sh` was newly registered in test-all.sh, so the
baseline is **+1** there beyond the pre-existing delta.

PR 7146 still draft, MERGEABLE. Branch pushed through Phase 4.

---

## Review Phase — session 4 (2026-08-03): the 12-agent panel that session 3 asked for

**Everything below was measured in this session.** Session 3 recorded its review as
`0 of ~10 agents` and said plainly: *"Treat the findings below as a floor, not a clearance … If the
panel can be run in a later session, run `/review` again BEFORE shipping."* It was run. The floor
was low.

### Coverage

12 agents: security-sentinel, test-design-reviewer, architecture-strategist,
observability-coverage-reviewer, silent-failure-hunter, user-impact-reviewer,
data-integrity-guardian, code-quality-analyst, pattern-recognition-specialist,
git-history-analyzer, agent-native-reviewer, performance-oracle. All 12 returned.
`semgrep-sast` deliberately SKIPPED — bash-only diff, where OSS semgrep's tree-sitter parser
matches ~0 rules and reports a vacuous clean; `shellcheck` substituted (HEAD 249 findings vs
main 245, zero error-level, no net-new codes, all five new scripts clean).

### What the 0-agent review had missed

~60 distinct findings after dedup, 15 P1. Three were merge-blocking and none was visible to the
green branch:

1. **ADR-155 collided** with `ADR-155-cross-gate-exemption-markers` (#7161), plus 156 and 157
   landed on main mid-pipeline. `check-adr-ordinals.sh` reads only the local tree, so it was
   GREEN on the un-rebased branch and RED the moment the branch caught up — measured in exactly
   that order. Renumbered to **ADR-159**, 15 citations, scoped by file ownership.
2. **`model.likec4.json` was a hard merge conflict** (`mergeable: CONFLICTING`). REGENERATED from
   the merged `.c4` at every conflict, never hand-resolved: picking a side would have dropped
   main's ADR-156/157 `claude -> hooks` edge while the `.c4` still declared it.
3. **The squash merge would have retired #7103.** The repo's own `auto-close-scan.sh` flagged the
   commit body that RECORDED session 3's review — the same trap, re-introduced by the paragraph
   documenting it. Reworded; scanner now CLEAN on commits, body and title.

### The through-line, in one sentence

*The diagnostic is correct and the routing is wrong — the unknown-value path and the error path
both land on the same branch as success.* That is ADR-159's own thesis, found inside the
machinery written to enforce it. Instances, each independently corroborated by 3+ agents:

- The activation gate hard-failed on an **allow-list of three reason strings** and never keyed on
  `action`. Measured against the shipped adjudicator: `action=failed` with an unrecognised reason
  returned `rc=0` with EMPTY output. Now a deny-list; reverting takes the suite 40/40 → 24/16.
- `unit_prop` returned `""` on ANY failure, so a `systemctl show` that could not answer graded as
  `unit_inactive` → warning → green, certifying an apply that reconciled nothing.
- `test-all.sh` printed *"infra IS covered above"* in the three CI shards where `want_infra` is
  false. Strictly worse than the `main` text it replaced, which was universally true.
- The `no_credential_source` Sentry beacon was **inert in the failure it reports**
  (`grep -c SENTRY_INGEST_DOMAIN cloud-init.yml` → 0), and had zero tests anywhere in the repo.
- The anti-vacuity batteries **exempted themselves** from the floors they impose on siblings.

### Deliberate decisions taken during the fix pass

- **`inngest-heartbeat.service` removed from `RESTART_MAP` and both sudoers copies.** Verified
  `Type=oneshot`, no `RemainAfterExit` anywhere in `inngest-bootstrap.sh`, 60s timer around a
  sub-second `ExecStart` — so it graded `skipped/unit_inactive` on essentially every apply,
  making the gate's warning arm the STEADY STATE, and the grant activated nothing that
  `daemon-reload` + the next tick does not. Retires one standing root-restart capability on the
  host with no replacement path.
- **The Sentry claim was corrected, not "fixed".** Baking `SENTRY_*` into cloud-init would be true
  only for a future fresh host (`ignore_changes=[user_data]`) while reading as true today — the
  delivery-is-not-activation trap this ADR names. Code and comment now agree AT MERGE.
- **`RESTART_SETTLE_SECS` validated.** Unvalidated it was a deterministic prod freeze: measured
  with the value `abc`, 19 of 19 files on disk, frame reporting `files_total:0/"unhandled"`,
  webhook self-restart NEVER RAN.

### Measured on this tree (per-suite; each re-run after the final rebase)

`run-registered-suites.sh` **87/87** · `ci-deploy` **216/216** · `infra-config-apply` **110/110** ·
`infra-config-gate` **40/40** · `infra-config-install` **44/44** ·
`infra-config-handler-bootstrap` **36/36** · `journald-config` **79/79** ·
`betterstack-assert-absence` **44/44** · `digest-oracle-guard` **27/27** ·
`cf-tunnel-liveness-gate-mutations` **8/8** · `test-all-infra-coverage-notice` **20/20** (new).
`check-adr-ordinals` rc=0 · `lint-orphan-test-suites` none · `visudo -cf` parses ·
`terraform fmt -check` clean · `actionlint` 1.7.7 clean · shellcheck no error-level findings.

**`run_suite` registration delta: main 103 → HEAD 109 = +6**, derived from the two files rather
than asserted (a literal count is the cheapest thing to make green by dropping a registration —
the R5 defect itself). The six are named in the tasks.md 8.1 entry.

**The aggregate `scripts/test-all.sh` run is NOT recorded here as a number.** Two attempts were
killed under 4 and then 7 concurrent sibling `test-all.sh` runs (load 16.15/16 cores, `/tmp` 70%);
the runner's own `SIBLING_RUN_DETECTED` banner fired both times. A killed run is not a failure and
not a pass, and inventing a total for it is the precise defect this PR exists to remove. CI is the
authoritative aggregate.

### Errors made in this session

1. Set a `MIN_ASSERTS` floor to 27 against 26 actual — **caught by the floor itself**, which is the
   behaviour it was added for.
2. Wrote `out=$(...); rc=$?` under `set -e` in the very commit fixing that class; the suite aborted
   and showed me. Converted to `|| rc=$?`.
3. Guessed `BETTERSTACK_QUERY_BIN` for the stub seam when the real name is
   `BETTERSTACK_QUERY_SCRIPT` — a stub that cannot reject, caught before it could certify anything.
4. Ran a `git commit` from a shell whose CWD had been reset to the bare root, tripping the
   commit-to-main guard. Re-established CWD in its own call.

# Tasks — #7450 git-root fallback is not a trusted anchor

Derived from
[`knowledge-base/project/plans/2026-08-12-fix-git-root-fallback-untrusted-anchor-plan.md`](../../plans/2026-08-12-fix-git-root-fallback-untrusted-anchor-plan.md).

Phase order is dependency-directed. Phase 1 is a **halt gate**: a negative measurement stops
the plan rather than degrading it.

## Phase 0 — Preconditions (read-only)

- [x] 0.1 Re-read all 5 sites; confirm the git-root form is still present
      (`hr-always-read-a-file-before-editing-it`)
- [ ] 0.2 Re-run Pattern A / B / C sweeps; confirm counts (6 / 45 / 2)
- [x] 0.3 Re-read `apps/web-platform/server/safe-bash.ts`; confirm none of the 3 scripts is in
      `EXACT_LITERAL_SAFE_COMMANDS`, and confirm `SAFE_BASH_PATTERNS` has no `bash <path>` regex
- [x] 0.4 Read all three `.c4` files in full; re-confirm the no-C4-impact conclusion
- [x] 0.5 Confirm `plugins/soleur/skills/*/scripts/redact-*.sh` discovery yields the expected set
- [x] 0.6 Determine whether `redact-sentinel.test.sh` is path-gated in `scripts/test-all.sh`;
      if so, widen the predicate to the full gate-site set in this PR

## Phase 1 — MEASURE (halt gate; precedes the amendment text)

- [x] 1.1 Build a throwaway skill with a bare `${CLAUDE_PLUGIN_ROOT}` inside a fenced `bash`
      block that prints its own expansion
- [x] 1.2 **Arm A** — marketplace-style session, variable expected to resolve. Capture
      artifact + invocation + raw output verbatim
- [x] 1.3 **Arm B** — plain monorepo session, variable unset. The identity preflight halts on
      an unset variable regardless of loader substitution, so this arm covers a second unknown
      Arm A cannot reach
- [x] 1.4 Record the verdict per arm, and which sessions lose which skills under each
- [x] 1.5 **On negative: STOP and re-plan.** Do not proceed to Phase 5. (No flow reviewer
      examined this branch — see §Deepen-Plan Review Findings coverage gap)

## Phase 2 — RED: decoy positive control

- [x] 2.1 Synthetic contributor tree: `mktemp -d` + `git init`
- [x] 2.2 Plant the decoy `redact-sentinel.sh` (`exit 0`, mode 0755) at the payload-shaped path
- [x] 2.3 Assert the decoy is a live hazard — exits 0 on a synthesized-secret file
- [x] 2.4 Extract the anchor from the **committed** `incident/SKILL.md` (independent producer;
      do not hardcode)
- [x] 2.5 With `CLAUDE_PLUGIN_ROOT` unset and CWD in the tree, expand and assert the resolved
      path is NOT under the tree
- [x] 2.6 Run; **capture the RED output for the PR body** (`cq-write-failing-tests-before`)

## Phase 3 — RED: extend the anchor guard

- [x] 3.1 Extend `plugin-root-anchoring.test.ts` file axis to all `skills/**/SKILL.md`
- [x] 3.2 Derive the script axis: discovered `skills/*/scripts/redact-*.sh` + closed extras
      `{ token-efficiency-report.sh }`
- [ ] 3.3 Add the `scanned >= 5` anti-vacuity floor
- [x] 3.4 Update the docstring's out-of-scope block; keep naming the ~105 sites deferred to #7453
- [x] 3.5 Run; capture RED

## Phase 4 — GREEN: migrate, with guards

- [x] 4.1 `incident/SKILL.md` — bare payload-relative operand + identity preflight (keep `[[ -r ]]`)
- [x] 4.2 `legal-generate/SKILL.md` — same; byte-identical to 4.1
- [x] 4.3 `linear-fetch/SKILL.md` — operand + identity preflight + **the missing readability
      guard and exit-code dispatch**
- [x] 4.3b `one-shot/SKILL.md` + `brainstorm/SKILL.md` — absent-`persist_safe_summary` halt
      contract. Without it the 4.3 guard turns a refusal into a LEAK (callers fall back to
      `agent_context`, which carries signed `uploads.linear.app` bearer URLs)
- [ ] 4.4 `compound/SKILL.md` — operand + **NON-BLOCKING** skip guard (named marker, continue;
      never `exit 2` — it authorises nothing); **do not touch** `TE_REPORT_REPO_ROOT`
- [ ] 4.4b Each halt message gains a plain-language remediation line; the redaction gates also
      say "do NOT write this by hand"
- [x] 4.5 Correct the git-root-fallback prose in `incident` + `legal-generate`
- [x] 4.6 Correct the falsified rationale comment in `preflight/SKILL.md`
      (**comment only — operands stay**, DC-1)
- [x] 4.7 Retarget + strengthen Test 18 (coupling, identity preflight, corpus-wide negative)
- [x] 4.8 Verify no `${CLAUDE_PLUGIN_ROOT}/plugins/soleur` doubled segment anywhere
- [x] 4.9 Both suites green

## Phase 5 — ADRs

- [x] 5.1 Amend ADR-179 as `## Amendment — 2026-08-12 (#7450): …`; keep `status: accepted`
- [x] 5.2 Include: scope extension; no-`safe-bash`-change finding; fail-closed asymmetry;
      Phase 1 measurement; code-root vs data-root; Pattern C residual
- [ ] 5.3 Edit §R5 **in place** — record closure and correct its "all four are secret gates" wording
- [x] 5.4 Correct ADR-093 `## Amendments` — the `git-root = the operator's own checkout`
      premise; keep the #6223 export-invariant reasoning intact
- [x] 5.5 Confirm **no new ADR file** is added

## Phase 6 — Downstream comments (no code)

- [ ] 6.1 Comment on **#7453**: ratified anchor; **ordinal is ADR-179, not ADR-177**; this
      subset needed no `safe-bash.ts` change; the 2 Pattern C preflight sites with severity flag
- [ ] 6.2 Comment on **#6222**: remedy falsified; `${CLAUDE_PLUGIN_ROOT}` cannot anchor
      repo-root `scripts/` members; correct instruments are relocate-into-payload (ADR-179
      decision 3) or monorepo-sentinel gate (decisions 4-6); cite §R4's re-derived table; note
      the `domain-model-drift.sh` sites are already remediated
- [ ] 6.3 Verify both issues remain **OPEN**

## Phase 7 — Exit

- [x] 7.1 `bash scripts/test-all.sh` green
- [x] 7.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
- [ ] 7.3 Guard 1 mutation matrix M1-M6 executed; 6-row table in PR body
- [ ] 7.4 Guard 2 mutation matrix M7-M10 executed; 4-row table in PR body
- [ ] 7.5 PR body: `Closes #7450`; AC #3 disposition; DC-1/DC-2 rendered
- [ ] 7.6 `/soleur:review` (includes `user-impact-reviewer` at the single-user-incident threshold)
- [ ] 7.7 `/soleur:ship`


---

## Addendum — 2026-08-12 remediation pass (#7450 review panel + CTO ruling)

**Why the boxes above were 0/48 checked while the work was done.** The originating session
completed the phases and never marked the record; the review panel logged that as D5. The
ticks above are the items whose artifact was re-verified in this session or whose evidence
is in the commit graph. **Deliberately still unchecked**, because each is now false,
superseded, or genuinely not done — a tick is a claim, so these are annotated instead of
ticked:

| Item | Status |
| --- | --- |
| 0.2 "confirm counts (6 / 45 / 2)" | **The 6 was wrong for the command published beside it.** `git grep -lF ':-$(git rev-parse --show-toplevel)' -- plugins/soleur/` returned **5**, not 6 — the `worktree-manager.sh` site uses `--git-common-dir` and cannot match that needle. The 6 came from a shorter needle than the one printed. Pattern B published no command at all. Post-migration the same command returns **0**. |
| 3.3 "add the `scanned >= 5` anti-vacuity floor" | **Superseded.** A `>=` floor fails OPEN on additions (review-finding A10). Replaced by an identity SET pin, so both directions are a reviewable diff. |
| 4.4 "`compound/SKILL.md` — operand + NON-BLOCKING skip guard" | **DESCOPED**, and the descope was already shipped in `7840b2a42` (anchor swap only). ADR-179 §R5 asserted the guard as delivered; that claim is corrected in this pass (review-finding C6). |
| 4.4b halt-message remediation lines | **Partially done.** The three gates print a resolved-root line and an actionable remedy; the full C9/C10 pass (telemetry markers on every halt) is still open. |
| 5.3 "edit §R5 in place" | Superseded by the fuller amendment: §R5's enumeration was by SYNTAX rather than STAKES, which is why it missed trigger-cron and could not see the three payload scripts at all. Recorded as amendment items 6-7. |
| 6.1 / 6.2 / 6.3 downstream comments | **Not done.** |
| 7.3 / 7.4 "mutation matrix M1-M6 / M7-M10" | **Superseded, and deliberately NOT re-run.** M1-M10 all pass and all mutate the SUT; the panel's post-mortem showed the vacuities live on seven axes those ten never edit. Replaced by two new batteries — 8 mutations against Guard 1, 6 against Guard 2 — each with a GREEN control and each mutation asserted to have LANDED against a pristine backup rather than against HEAD. |
| 7.5 / 7.6 / 7.7 PR body, `/soleur:review`, `/soleur:ship` | **Not done.** |

### Work done in this pass that the plan never contained

The panel scoped three surfaces the plan did not, and the CTO ruling added a fourth that
the panel's own `SKILL.md`-scoped grep could not see:

- **B2** `trigger-cron/SKILL.md` — a prod-Doppler secret gate on `${CLAUDE_PLUGIN_ROOT:-…}`
  with no env-var precondition at all. Migrated + preflight + presence guard.
- **B3** the 20 `source` sites — inverted to inert markers under new ADR-179 decision 9,
  with a validating monorepo-only PostToolUse capture hook.
- **B4** `.claude/settings.json` — dead auto-approve entry removed; new decision 8 bans the
  form in operator config and G8 asserts it.
- **CTO C1** three payload SCRIPTS (`gdpr-gate.sh`, `net-issue-flow.sh`,
  `token-efficiency-report.sh`) sourcing incidents.sh from the git root.
- **Not in any finding:** all FOUR linear-fetch suites were unregistered — `test-all.sh`
  globs `skills/*/test/*.test.sh` and linear-fetch was the only skill putting `.test.sh`
  under `scripts/`. §G had recorded this for one file; it was four.

## Round-2 reconciliation (2026-08-13)

Thirteen boxes remain unchecked. Each is one of three kinds, and the kind is stated so an
unchecked box is never read as forgotten work.

**DONE — tick, evidence named**

| Box | Evidence |
| --- | --- |
| 4.4b | Every halt at all four gates carries state-discriminating remediation (empty-root vs wrong-root are different actions) and a `SOLEUR_*_HALT` marker. Pinned by Test 22, which also has a growth floor so a new halt cannot arrive unmarked. |
| 5.3 | §R5 corrected in place; its "all four are secret gates" wording is what correction C6 retracts, and ADR-093 now carries the same correction after this session reinstated it by accident. |
| 6.1 / 6.2 / 6.3 | Both comments posted and both issues verified OPEN (re-verified this session; #7453's title does still cite ADR-177, which DC-2 records as a citation correction, not a defect in this PR). |
| 7.3 / 7.4 | M1–M6 and M7–M10 executed. **Superseded as adequacy evidence** — see `mutation-matrices.md`: all ten mutate the SUT along five axes, and the vacuities lived on axes they never edit. Battery 3 (15/15, eight axes) is what carries the claim now, so the PR body renders Battery 3 rather than these. |
| 7.5 | PR body carries `Closes #7450`, the AC #3 disposition and DC-1/DC-2. |

**SUPERSEDED — deliberately not done, recorded where it will be found**

| Box | Disposition |
| --- | --- |
| 0.2 | The "(6 / 45 / 2)" counts are stale by construction: this PR changed the populations. Live counts are re-derived in the guards themselves (Test 24's population is discovered on disk, not asserted from a plan-time number) — which is the point of the rewrite. |
| 3.3 | `scanned >= 5` was **implemented and then removed**. A count floor fails OPEN on shrinkage; it was measured surviving a mutation that gutted the predicate. Replaced by required-membership. Re-adding this box would re-introduce finding A10. |
| 4.4 | `compound`'s non-blocking guard was descoped by `7840b2a42` and is correctly still unchecked. ADR-179 §R5 C6 retracts the claim that it shipped; ADR-093 briefly reinstated that claim this session and has been corrected. |

**IN FLIGHT**

| Box | State |
| --- | --- |
| 7.6 | `/soleur:review` run twice — a 10-agent panel and a 6-agent round-2 panel plus a CTO consult. `user-impact-reviewer` was NOT among the round-2 seats; the round-2 panel was scoped to the guard/record surface, and the threshold-driven seat ran in round 1. |
| 7.7 | `/soleur:ship` — next. |

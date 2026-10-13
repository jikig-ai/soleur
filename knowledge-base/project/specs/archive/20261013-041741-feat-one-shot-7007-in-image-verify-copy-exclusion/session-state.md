# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-28-perf-ci-in-image-verify-copy-exclusion-plan.md`
- Status: complete (v3 — plan-review + deepen applied)
- Paused at operator request after plan; resumed on "please continue".

## Work Phase
- Status: implementation complete; RED/GREEN/mutation + L2 rehearsal all executed.
- RED (naive body): failures exactly **{3, 5, 6}** as the plan predicted; assertion 5 RAN (not SKIP).
- GREEN: 8/8 at work-time. **The suite was substantially rewritten at review** (now 10 assertions)
  after multi-agent review proved the 8-assertion version could be fully defeated — see Review Phase.
- AC6: in-image `diff -rq` parity clean, `node_modules` + `infra/.terraform` absent,
  `infra/.terraform.lock.hcl` survived, all three `stat -c %U` lines `root`.
- AC7 (never run before): `npm ci --no-audit --no-fund` in the filtered `/build` exited 0,
  added 1357 packages, 827 top-level `node_modules` entries — confirms the excluded tree is
  genuinely discarded-and-rebuilt by the very next command.
- A/B measured in the pinned digest against a warm tree. **Lead with the deterministic
  quantity — it has zero variance and reproduced exactly on an independent re-run:
  2.6 GB / 99,263 archive members → 30 MB / 2,974.** Wall clock is a RANGE, not a point:
  ~18–28 s → ~0.25–0.5 s. Two earlier claims were withdrawn at review: "~57×" is not
  derivable from the recorded pairs (they give 63.5× and 55.4×; both estimators give 59.4×),
  and the runs were two sequential BEFORE-first blocks, not "interleaved" — a counterbalanced
  re-run found no resolvable ordering penalty, so the conclusion stands but the label was wrong.
  **Scope correction:** this is a LOCAL win only. Both CI jobs are checkout-only, so the
  exclusions save 0 bytes and 0 ms there; the CI-visible effect is the cp→tar substitution,
  measured as unresolved at ±24 ms (i.e. perf-neutral within noise). Commit scope retagged
  perf(scripts). Independent measurement also showed `npm ci` gets ~2.8 s FASTER (it deletes any
  pre-existing node_modules first — 96,279 inodes / 2,334 MB), so the PR understated itself.
  Plan-phase figures (22.96 s / 2.3 GB → 0.48 s / 35 MB) were a different tree; superseded.
- AC5 lint green; trap-tempfile-ownership 20/20 green; AC1 grep pair green.
- AC4 `bash scripts/test-all.sh scripts`: rc=0, **226/226 suites passed**. The new suite
  auto-registered and ran (`[ok] apps/web-platform/scripts/lib/in-image-copy-src.test.sh`,
  419ms), confirming the `scripts/lib/*.test.sh` glob picks it up — load-bearing, since it is
  the only detector a broken exclusion can ever trip. Run under a `SIBLING_RUN_DETECTED`
  banner (2 sibling test-all runs in other worktrees); result was green, so no
  contention-vs-real disambiguation was needed.
- SO-1 filed as issue **#7043** (labels + milestone reconciled via `gh issue view`).
- **L3 paid end-to-end: NOT RUN** — both helpers require `ANTHROPIC_API_KEY` and drive a real
  Haiku turn, and neither CI gate's trigger regex names the changed files.

### Follow-up net flow
Closing 1 (#7007) / filing 1 (#7043) / **net 0**. #7043 is a genuine posture question about a paid
gate that cannot be verified without the paid path — not inlineable.

### Errors
None. All deepen-plan halt gates (4.5–4.10) passed; KB citations, rule IDs, and GitHub labels verified to resolve.

### Decisions
- **The fix specified in issue #7007 was falsified and replaced.** `GLOBIGNORE` filters only the
  top-level `/src/*` glob expansion, so `/src/infra` survives the filter and `cp -r` recurses into
  it carrying `.terraform`. Independently re-verified by the parent pipeline on a synthetic fixture:
  `node_modules` excluded, but `dest/infra/.terraform/providers/big.bin` still copied; dotfiles
  (`.dotfile`) did survive, so that half of the issue's reasoning held. Replacement:
  `tar -C "$SRC" --exclude=./node_modules --exclude=.terraform -cf - . | tar -C "$DEST" --no-same-owner -xf -`,
  which also covers the not-yet-initialised second terraform root at `infra/sentry/`.
  Recorded as a User-Challenge in `decision-challenges.md` since it departs from a literally-specified fix.
- **Ship the copy as one file** (`apps/web-platform/scripts/lib/in-image-copy-src.sh`) called by both
  helpers, rather than two pasted blocks. `/src` is a mount of `apps/web-platform`, so
  `/src/scripts/lib/…` is reachable in-container. Deletes a marker-extraction/`sed`/`eval` test
  harness, a byte-identity drift pin, and an apostrophe hazard, and lets `set -o pipefail` live in a
  scope with zero blast radius on the canary's `curl | bash`.
- **Verification ladder without a paid turn:** hermetic suite auto-registered via the existing
  `apps/web-platform/scripts/lib/*.test.sh` glob (the only detector — the exclusions are no-ops on a
  cold CI checkout), plus an in-image rehearsal proving parity, root ownership, and `npm ci` success.
  The paid end-to-end path is explicitly NOT run; the PR body must say so rather than claim it.
- **Declined to expand the CI trigger regexes** — cost corrected from two paid Haiku turns to one,
  with the canary half structurally inert due to a second internal regex in `sdk-bump-sandbox-gate.sh`.
- **Two self-corrections applied:** the v1 `PIPESTATUS` guard was dead code under `set -e`, and the
  v2 tar-anchoring comment was empirically false (`--exclude` is `--no-anchored`; `./node_modules` is
  root-only only because of the `.` member root).

### Measured effect
See the A/B bullet under **Work Phase** above. Headline: **2.6 GB / 99,263 members → 30 MB / 2,974**
(deterministic), wall clock ~18–28 s → ~0.25–0.5 s, **local only** — CI is perf-neutral within noise.

### Open findings — resolved during /work
- Neither CI gate's trigger regex names the helper scripts, so a cold CI checkout is structurally
  incapable of observing a broken exclusion. **Closed:** the hermetic suite shipped and is confirmed
  auto-registered (it ran in the green 226/226 shard). It is the only detector, by design.
- `sdk-bump-sandbox-gate.sh` captured its verify command as `"$(… 2>/dev/null | tail -1 || true)"`,
  making a copy FATAL invisible. **Closed inline:** the redirect is deleted, so the FATAL reaches the
  job log. The residual `|| true` ack-fallback posture is deliberate, untouched, and filed as #7043
  rather than claimed as fail-loud.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Plan review: `code-simplicity-reviewer`, `kieran-rails-reviewer`, scoped strong-model consult (opus)
- Deepen: `learnings-researcher`, claim-verification pass (sonnet), `test-design-reviewer`, `architecture-strategist`
- Empirical probes: synthetic-fixture `GLOBIGNORE`/`tar` A/B, `docker run` against the pinned
  `node:22-slim` digest (tar version, parity diff, ownership, before/after wall clock), tar anchoring
  control, producer-failure `PIPESTATUS` discrimination

## Review Phase

Ten agents (change class `code`; shellcheck substituted for semgrep on a bash-only diff;
`user-impact-reviewer` not triggered — plan threshold is `none`). No agent found a P1 in the copy
mechanism itself; the exclusion semantics were independently confirmed against the real tree
(**tar member set 2978 == expected 2978, zero unintended exclusions**, on tar 1.34 and 1.35).

**Four P1s, all fixed inline. Every one was a guard that certified the wrong property:**

1. **Assertion 8 pinned the followers to each other and left the leader unpinned.** Both helper
   headers say "pin to the same base as `apps/web-platform/Dockerfile`"; the assertion compared
   helper-vs-helper and never read the Dockerfile. Renovate's `dockerfile` manager bumps that
   digest and **automerges** (`default:automergeDigest` + `platformAutomerge`), and the helpers sit
   outside every configured manager — so both would go stale together and the guard stays green,
   silently breaking ADR-079's capture-env == replay-env == deploy-image invariant. Now extracts
   from the Dockerfile plus each helper's `IMG=` pin, requires exactly one digest per helper (a
   decoy in a comment would otherwise unpin the real one), and `sort -u` must yield one.
2. **The whole optimisation could be reverted with the suite green.** `grep -qF` matched comments,
   and this PR's own file carries the invocation literal as usage text — so `cp -r` plus a decoy
   comment passed 8/8 while copying 2.3 GB again. The ban also missed `cp -vr` / `cp --recursive`.
   Now comment-blind, and bans any `cp`/`rsync` touching `/src`.
3. **Nothing asserted the assertions ran.** Deleting every assertion block yielded
   "0 passed, 0 failed", **exit 0**. Added a `MIN_ASSERTIONS` floor (a floor, not equality; SKIP
   counts so the root path degrades observably).
4. **The FATAL guard conflated tar's two exit statuses and was untested in production.** GNU tar
   uses 2 = error, **1 = warning** ("file changed as we read it"). The unreadable-member case is
   unreachable as root — which is how this ships — so the only reachable class was the warning,
   and it produced a false FATAL on a complete tree. `/src` is read-only to the *container*; the
   host tree stays live, so any editor save, `tsc --watch`, or even a file deletion during the
   ~0.44 s window would have reddened the gate on the operator's warm tree — the one machine this
   optimisation exists for. Now discriminates on status (2 → FATAL, 1 → WARN + proceed), pinned by
   a stubbed-`tar` assertion that is deterministic and does **not** skip as root.
   `--warning=no-file-changed` was measured and does NOT help: it suppresses the message, not the status.

**Also fixed inline:** `.next`/`out` excluded (already in `.dockerignore`; removes the dominant
race trigger and the largest local cost); symlink survivor pinning tar's non-dereferencing (a future
`-h` would pull targets from outside the ro mount); nested `.next`/`out`/`node_modules` over-reach
sentinels with membership assertions; `/src`-mount and `CALL_LITERAL` derived from the SUT path;
the four sibling in-container steps un-muted (`2>&1` → `>`) so an `apt`/`npm ci` failure has cause
text; T15 added to `sdk-bump-sandbox-gate.test.sh` (the `2>/dev/null` deletion had **zero** coverage
— every other arm's VERIFY_CMD is silent on stderr); ADR-079 addendum re-grounded structurally
rather than on a token census; perf claims rescoped and de-pointed.

**Mutation battery (post-fix): 16 RED + 1 documented GREEN**, each mutation verified landed against
a pristine backup, against a green sandbox baseline. The GREEN is `--no-same-owner`, which the
hermetic suite is structurally unable to pin (as non-root, tar cannot chown at all) — proven instead
by the in-image rehearsal, and now said so in both the script header and the suite header rather
than claimed as covered.

**One battery result was self-caught as fabricated:** an early mutation "survived", but inspection
showed the edit had landed on the *comment* documenting the flag rather than the code — the
documented replace-first-occurrence trap. Re-run with exactly-once anchors, it goes RED. Anchors now
assert single-occurrence so an ambiguous one fails loudly instead of producing a false verdict.

**Declined:** widening the CI trigger regex to the propagation gate. It is a sharper argument than
the plan's (the canary half is structurally inert, the propagation half is not), but it reverses a
trade recorded in `decision-challenges.md` UC-2 as an operator decision and costs a paid Haiku turn
on every future edit to these files. UC-2 carries the sharper framing so the operator decides on it.

## Compound Phase

Learning: `knowledge-base/project/learnings/2026-07-29-my-guard-tested-the-one-case-that-cannot-happen-in-production.md`
(15 session errors, each with a Prevention line).

**Routed to definition:** one bullet appended to `plugins/soleur/skills/review/SKILL.md`'s
defect-class catalogue — the two NOVEL shapes (discriminating case unreachable in the shipping
environment; "keep in sync" guard pinning followers instead of an automerge-mutated leader).
Eval-gate checked first: `gated:false`, so applied normally. Placement gate says review-scoped,
NOT AGENTS.md — the insight only fires inside a review, and the always-loaded payload is in WARN.

**Not promoted to constitution.** Two of the four P1 lessons are recurrences of classes already in
`review/SKILL.md`; constitution.md is at 295/300 bullets and the rule-budget linter reports
`[WARN] B_ALWAYS=22900 >= 20000` (~100 bytes of headroom). Adding an always-loaded rule for a
review-scoped insight is exactly what that WARN advises against. Budget shrink is already tracked
as **#6138** — not re-filed.

**Archival DEFERRED to post-ship (deliberate, not skipped).** Auto-consolidation would `git mv` the
whole `specs/feat-<branch>/` directory to `archive/`, but `/ship` Phase 2.5 reads
`specs/<branch>/decision-challenges.md` by exact path to render `## Model Dissents (informational)`
and open the `action-required` issue. Archiving first would silently strip UC-1/UC-2 from the PR
body — losing the operator visibility that artifact exists for. The plan file is not in scope
anyway (its filename lacks the branch slug). Run
`bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` after the PR merges.

**Rule-metrics aggregator failed**; its partial write was reverted so a later blanket
`git add -A knowledge-base/` could not stage a rejected aggregate. No unused-rules hint this run.

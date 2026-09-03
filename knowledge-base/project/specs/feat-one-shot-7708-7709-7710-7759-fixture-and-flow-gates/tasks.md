---
title: "Tasks — fixture-operand scanner and flow gates"
branch: feat-one-shot-7708-7709-7710-7759-fixture-and-flow-gates
plan: knowledge-base/project/plans/2026-09-03-fix-fixture-operand-and-flow-gates-plan.md
lane: cross-domain
closes: [7708, 7709, 7710, 7759]
---

# Tasks

Derived from the plan after review. Four pull requests, one per issue. **PR 1 must merge before PR 2
begins** — Phase 2.1 measures against the tree PR 1 cleans. PR 3 and PR 4 depend on nothing and may
run in parallel with the scanner work.

Each pull request carries exactly one closing keyword. The frontmatter `closes:` list above describes
the branch, not any single pull request — lifting it whole into PR 1 would auto-close three issues
whose work has not shipped.

## Phase 0 — Preconditions (all pull requests)

- [ ] 0.1 Confirm the four issues are still OPEN and unclosed by a merged pull request.
- [ ] 0.2 Re-measure the P1a baseline: `python3 plugins/soleur/test/lib/fixture-scan.py --rule operand --repo .`
      Record `SITES` and `FILES`. Planning measured `SITES=167`, `FILES=914`.
- [ ] 0.3 Confirm the baseline row sum equals the reported `SITES`.

## Phase 1 — PR 1: burn down the P1a baseline (#7709)

Body carries `Closes #7709` and nothing else.

- [ ] 1.1 Record the measured starting point in the pull request body, noting that 167 is current and
      that the issue body's 160 predates the 2026-08-27 detector-widening regeneration.
- [ ] 1.2 Order the 32 holders by descending count from the live baseline, not from the issue body
      (which is stale: it says 23 for `ship-unpushed-commits-gate.test.sh`, live is 19, and it omits
      `context-reviewed-gate.test.sh` at 12 and `pencil-collapse-guard.test.sh` at 10).
- [ ] 1.2a BEFORE remediating: `_guard_res` matches only literal `|| exit` / `|| return`, so a site
      guarded by a `… || _setup_fail "msg"` helper reads as unguarded (~140 such idioms across the
      holders). Where that idiom is the real guard, extend guard recognition instead of adding a second
      assertion — it retires several sites at once and is a smaller diff. This may reduce the 167
      before any site is edited.
- [ ] 1.3 Sequence the two largest holders first and review them separately.
- [ ] 1.4 Choose the remedy by AVAILABILITY first, then binding form. Measured: only 4 holders carry an
      inline `assert_fixture_dir`, 5 source or reference it, and 23 cannot reach it at all — so the
      control-flow remedies are the default for most sites, not the fallback. Order: (a) helper already
      available -> `assert_fixture_dir "$X"`; (b) a test file that can reasonably source the helper ->
      source it, never copy it (each inline copy widens the byte-equality drift arm, and there are
      already 4); (c) a plugin script under `plugins/soleur/` -> read ADR-178 on where shared bash
      primitives live before adding any dependency, and prefer `${X:?}` if it does not fit; (d)
      anything else -> `${X:?}` at the binding or `|| return 1` / `|| exit` on a capture.
      Three of the 23 are not tests at all and must not gain a test-helper dependency:
      `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`,
      `scripts/context-reviewed-gate-discoverability.sh`,
      `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`.
- [ ] 1.5 For each holder, run that file's own suite green before moving to the next. Do not sweep and
      run once at the end.
- [ ] 1.6 For each `.claude/hooks/*` and gate-test holder, capture a before-and-after transcript: the
      holder's own existing RED fixtures, plus a synthetic pass and a synthetic failure, comparing exit
      code and failure text on both sides. Exercise the fixture-construction path too.
- [ ] 1.7 If a transcript shows a shifted verdict boundary, escalate in order: switch to the additive
      remedy, then acknowledge the site with the observed shift as its recorded reason. Do not cycle
      remedies until the exercise goes quiet.
- [ ] 1.8 Regenerate with `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh --write-baseline`
      and commit each shrink in the same commit as the source edits that earned it.
- [ ] 1.9 Verify per commit that no commit touches the baseline without also touching a `.sh` file.
      Walk `git rev-list` and inspect each commit's own diff — not `git log -- pathA pathB`, which is a
      union filter and would pass on the asymmetric commit this check exists to catch.
- [ ] 1.10 Run the full test battery, not only the suites for edited files.
- [ ] 1.11 Confirm the scanner's reported `SITES` equals the acknowledged-row total (0 when none).

## Phase 2 — PR 2: add the P1b detector (#7708)

Body carries `Closes #7708` and nothing else. Begins only after PR 1 has merged.

- [x] 2.0 CARRIED FROM PR 1's POSTMERGE, declared here so it is not smuggled into a scanner PR:
      postmerge Phase 4 reported all 5 spot-checked files MISSING on a healthy merge. The worktree
      had not fetched the merge commit, and git's wording for an object it does NOT have
      (`exists on disk, but not in <sha>`) reads like a verdict about the file. Measured against a
      control on the same commit: a path genuinely absent from a real tree says
      `does not exist in <sha>` instead. The two messages are one word apart and mean opposite
      things. Fix in `plugins/soleur/skills/postmerge/SKILL.md`: fetch before the first `git show`,
      plus a table naming both messages. Per `wg-when-a-workflow-gap-causes-a-mistake-fix`.
- [ ] 2.1 The residue is already measured (plan Phase 2.1): `mv` 3 sites, `cp -r` 0, `rm -rf` 941 across
      316 files, redirection 1759 across 244. The last two are overwhelmingly false positives —
      939/941 and 1586/1759 are command-substitution bindings, and 650 / 1130 are literally
      `X=$(mktemp -d)`. **That parenthetical is FALSE and was corrected during PR 2 — see 2.1a.**
- [ ] 2.1a PREREQUISITE for the widening and root-anchored families: teach the machinery that a
      `$(mktemp -d)` binding is self-guarding — directly, through a same-file wrapper, and through a
      wrapper defined in a sourced helper. Re-measure after this; that residue is the real one.
      **MEASURED CORRECTION (PR 2).** The premise "always yields an absolute non-empty path" is
      false on BOTH counts, measured on uutils coreutils 0.8.0:
      `TMPDIR=reldir mktemp -d` -> `reldir/tmp.XXXX` (RELATIVE), `mktemp -d -p reldir` -> relative,
      and a failing `mktemp -d` exits 1 leaving the binding EMPTY. The absolute-path property is
      environmental, not lexical: it depends on `TMPDIR` at runtime, which a static scanner cannot
      see. Documented behaviour ("use `$TMPDIR` if set, else `/tmp`", no absolutisation) is
      implementation-agnostic; only uutils was available to measure on this host.
      Therefore self-guarding may be claimed ONLY as follows, and the distinction is load-bearing:
      (a) bare `$(mktemp -d)` / `$(mktemp -d -t PREFIX)` -> self-guards RELATIVITY. Measured safe
          for this corpus: zero relative `TMPDIR` literals and zero relative `-p`/`--tmpdir` args
          repo-wide, established with a positive control showing the pattern can match (8 real
          `-p` uses, all `$`-expansions or `/tmp`).
      (b) `mktemp -d -p "$X"` / `--tmpdir="$X"` -> does NOT self-guard: it inherits `$X`'s
          relativity, which is task 2.1b's derived-binding problem, not a separate one.
      (c) NOTHING about `mktemp` self-guards EMPTINESS. A failed `mktemp` binds empty, so the P1a
          rule must keep treating these as command-substitution bindings needing `|| exit`.
      Encoding the blanket claim would have silenced ~650/1130 and ~939/941 sites — the same
      "widening that silences" P1 the nine-agent review caught on PR 1, one PR later.
- [ ] 2.1b Handle derived bindings for the relativity claim: `_bind_res` treats `R2F="$TMP/r2floor"` as
      a literal and drops the site. Correct for P1a (empty), wrong for P1b (relative) — if `$TMP` is
      relative so is the derived path. Either resolve the parent variable or scope P1b explicitly to
      the recognized binding forms and document the exclusion.
- [ ] 2.2 Apply the repo's existing fix-inline-versus-file threshold — the cost-of-filing auto-flip at
      100 lines and 4 files — to the re-measured residue. If 2.1a proves large, ship the loud-failure
      family alone (3 sites) and file the other two with the measured numbers attached.
- [ ] 2.3 Add the rule function to `plugins/soleur/test/lib/fixture-scan.py` with its own verb tables.
- [ ] 2.4 Register the new `--rule` value in the rule-validation tuple in `main()` — a third editing
      site distinct from the rule function itself, currently `if rule not in ("operand", "cd")`.
- [ ] 2.5 Update the module docstring, which currently asserts in prose that there are two rules.
- [ ] 2.6 State the three measured behaviours as three families: widening (relative `git -C`, relative
      `rm -rf`, relative redirection target), root-anchored (empty `$X` in `"$X/f"`, which resolves to
      `/f`), and loud-failure (`mv` and `cp -r` into an empty destination, which exit non-zero).
- [ ] 2.7 For the `git -C` arm, claim only the residue P1a cannot see: literal-bound relative operands,
      which `_binding_of` skips because the nearest binding is a literal.
- [ ] 2.8 Extract the baseline compare, regenerate and floor logic into a shared helper used by both
      suites, rather than copying it. Only the fixture corpora differ.
- [ ] 2.9 Add the P1b test file with its own baseline path, modelled on the existing lettered sections.
- [ ] 2.10 Seed the P1b baseline against the post-burn-down tree.
- [ ] 2.11 Confirm `git diff` shows no change to `OPERAND_WRITE` or `scan_operand`, and that the P1a
      baseline is byte-identical to the state PR 1 left it in.
- [ ] 2.12 Execute every row of Guard 1's mutation matrix and record the observed result.
- [ ] 2.13 If grandfathering, file the burn-down issue with the measured count, per-family split and
      largest holders. Do NOT add a `Mandated-By:` line: the exemption corpus holds only
      `wg-block-pr-ready-on-undeferred-operator-steps`, and the gate's jq pass explicitly rejects a
      claim naming an untagged rule. The 1:1 close/file offset already keeps the gate green.

## Phase 3 — PR 3: the gdpr-gate freshness instrument (#7710)

Body carries `Closes #7710` and nothing else.

- [ ] 3.1 Verify by comparing `path:` VALUES against the body table, not counts — a count check passes
      at 8 == 8 even with a typo'd or duplicated path. Add frontmatter `lifted-files` entries for `references/layers/auth-sessions.md`,
      `references/layers/frontend.md` and `references/layers/testing-seeding.md`, each with its
      `upstream-path`, the `upstream-blob-sha` already in the body table, a `local-blob-sha` from
      `git hash-object --no-filters`, and a `status`. Precondition to any attestation.
- [ ] 3.2 Strengthen `vendor-pin-integrity.sh --verify-upstream` from blob-resolvability to
      path-content currency, reporting per-file `SAME` or `DRIFTED` plus a total.
- [ ] 3.3 Use the same API call shape as `cron-content-vendor-drift.ts`, and add a comment in each
      naming the other as its twin.
- [ ] 3.4 Demonstrate the strengthened check fails on a deliberately falsified pin, not only that it
      passes on the real one.
- [ ] 3.5 Confirm it passes on a re-vendor-shaped diff, where pins move to current upstream in the
      same change, so hardening this gate does not start failing the canonical §6 pipeline.
- [ ] 3.6 Re-run the comparison. On zero drift, bump `last-verified` with the per-file output in the
      commit message. On drift, withhold only the bump, ship the rest, and file the re-vendor
      separately per the Phase 3.3 branch in the plan.
- [ ] 3.7 Append the retrospective row to the `## Active Compliance Items` table in
      `knowledge-base/legal/compliance-posture.md` for the 2026-05-10 to 2026-09-03 window: that the §8
      chain did not run, why, and the resolution. Follow that section's documented row schema.
- [ ] 3.7a Correct the `## Vendored Code Provenance` row in the same file: `Lifted Files` reads 5,
      should read 8; `Last Verified` reads 2026-05-10 and moves with the NOTICE bump. Confirm all three
      artifacts — NOTICE frontmatter, NOTICE body table, provenance row — agree on count and date.
- [ ] 3.8 Add an unconditional stdout line to `gdpr-gate.sh` stating that the path scan ran and what it
      examined and matched. The line must NOT contain the substring `days stale`: `gdpr-gate.test.ts`
      asserts stdout does not match `/days stale/` on a fresh NOTICE, so a phrasing like "scan
      complete; rules N days stale" would red the suite for an unrelated reason. Stdout, not stderr.
- [ ] 3.9 Assert the new line in both the matched and unmatched cases, in BOTH
      `gdpr-gate-self-test.test.sh` AND `gdpr-gate.test.ts` — Guard 2's assembly names both as members,
      and asserting in only one leaves the other free to drift.
- [ ] 3.10 Confirm the gate still exits 0 on every path and the 30-day and 90-day thresholds are
      unchanged. Do not relevance-gate the staleness banners.
- [ ] 3.11 Execute Guard 2's mutation matrix and record the observed result.
- [ ] 3.12 Verify no commit message or pull request body describes any change as resolving #7255.

## Phase 4 — PR 4: the net-issue-flow FILED blind spot (#7759)

Body carries `Closes #7759` and nothing else.

- [ ] 4.1 Leave the existing FILED predicate unchanged.
- [ ] 4.2 Add the conservation predicate — post-pull-request issues citing a number in `CLOSING_NUMS`
      but not the pull request — conjoined with a machine-filing marker (`Mandated-By:` line or the
      `deferred-scope-out` label) to raise precision.
- [ ] 4.3 Emit the conservation set on a structurally separate output channel, consumed by its own
      loop that never touches `FILED`, `EXEMPT` or `NET`. The existing loop runs
      `FILED=$((FILED + 1))` once per row before reading any verdict, so a shared stream would raise
      `NET` per finding and block the pull request.
- [ ] 4.4 Keep a SINGLE jq pass — do not add a second invocation. The existing pass costs about a
      second over a ~2 MB payload, the gate runs in the several-second range, and it sits behind a hook
      timeout this gate already has a post-mortem about. Emit a structured result (sibling keys, or
      rows tagged by set) and route to different loops on the bash side. Add the new predicate as a
      sibling filter over the same array, not as a stage inside the FILED pipeline.
- [ ] 4.5 Name the set in the always-emitted block with its issue numbers enumerated.
- [ ] 4.6 Emit telemetry under a rule id distinct from the existing ones, and give any new failure
      branch its own `_fail_open` rule id.
- [ ] 4.7 Report without blocking in this cycle.
- [ ] 4.8 Add test cases, all as synthesized fixtures (never a live query against the real pull
      request, per `cq-test-fixtures-synthesized-only`): the measured PR #7702 shape; a second unattributed issue after an attributed
      first; an unrelated citation that must not be reported; a citation without a machine-filing
      marker that must not be reported.
- [ ] 4.9 Add the arithmetic-isolation case — `NET` numerically unchanged on the #7702 fixture before
      and after this change. Every other assertion here would pass while the count moved.
- [ ] 4.10 Raise `MIN_ASSERTIONS` to match the added cases.
- [ ] 4.11 Re-run `plugins/soleur/test/net-issue-flow.test.sh`, which the script's header requires on
      any change to the FILED query.
- [ ] 4.12 Execute Guard 3's mutation matrix, including row 6 (arithmetic isolation), and record the
      observed result.
- [ ] 4.13 File the promotion-to-blocking issue with a re-evaluation trigger stated in terms of
      measured fire rate.

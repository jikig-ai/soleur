# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-22-fix-inngest-config-refresh-verify-blob-reject-plan.md
- Plan artifact: complete (selector=branch)
- Status: complete

### Errors
- No subagent/Task capability on this harness inside the planner — all skill fan-out phases executed inline; technical rulings recorded as `pending - assumed:` rows in decision-challenges.md.
- Real `.sigstore.json` inside the private GHCR bundle not fetchable locally (no read:packages token; zot behind Cloudflare Access) — plan Phase 0 is the CI-dispatch reproduction capturing cosign stderr.
- Defect-3 root cause NOT conclusively proven — diagnosis-first plan with branched fix.

### Decisions
- All three prior suspects refuted by live measurement: baked trusted root key-identical to Sigstore live root; Fulcio cert SAN byte-matches pinned identity regexp; reconstructed v0.3 bundle verified `Verified OK` under verbatim `--network none` invocation.
- New mechanism: cosign v3.1.1 verify-blob gates `--trusted-root` on `checkNewBundle()` = `sgbundle.LoadJSONFromPath` — a bundle-load failure produces the same honest reject as a crypto failure (hypotheses H1–H4 ranked in plan).
- Diagnosability-first fix: kept `diagnose-inngest-verify.yml` dispatch probe; verify stderr `>/dev/null 2>&1` replaced by bounded capture + `detail=` classification token on VERIFY_FAIL rows; host delivery via inngest-host-replace immutable redeploy only.
- `brand_survival_threshold: single-user incident`, `requires_cpo_signoff: true` (edits cryptographic provenance gate on sole production scheduler).

### Components Invoked
- soleur:plan, soleur:deepen-plan (read in-process, run to completion)
- cloud-detect.sh → not-local:no-devin-env
- gh, doppler, docker (pinned cosign verify-blob reproduction), Rekor public API, Sigstore root-signing fetch, cosign v3.1.1 source fetches

## Collision Probes (post-planning re-probe)
- All args refs still OPEN: #10390 #9927 #8620 #7596 #10713 #10751.
- Plan frontmatter targets issue: 10390 (open epic).
- Open PRs linked to #10390: #10744 (verification-scaffold guardrails — no file overlap), #10742 (followthrough DateTime64 — no file overlap). Disjoint scope; continuing.
- Anchor probe: no open PR touches cloud-init-inngest.yml / cosign-trusted-root.json / inngest-config-drift.yml / diagnose-inngest-verify.yml.
- pr-overlap-preflight.sh --mode start: exit 2 twice (jq Argument list too long) — NOT checked; continuing per contract with disclosure.

## Rulings
- cto_spawns=1 (batched, 7 rows; all assumed defaults affirmed)

## Work Phase — complete
- Phase 0.1 DONE: `.github/workflows/diagnose-inngest-verify.yml` + paired shape test
  `plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh` (25/0). Commit d069de017a.
- Phase 0.2 BLOCKED-till-merge: `gh workflow run` 404s for workflows absent from the default
  branch; app-token GHCR pull denied ("installation not allowed to Read organization package").
  Dispatch post-merge per plan.
- Phase 2 DONE: cloud-init-inngest.yml verify stderr capture (`$STATE_DIR/verify.stderr`, 4KiB,
  0600, wraps `timeout`) + `detail=` classifier (flag-newbundle|tlog|identity|chain|timeout|
  docker|other) on `verify_fail signature "" "detail=$_cls"`; `_summ_row` regex gained `detail`
  in inngest-config-drift.yml. Tests: S10 + F16 rows in inngest-config-refresh.test.sh; suite
  132/0; sibling suites green (inngest-host 202/0, drift-compare 18/0, staleness 3/0, mirror 108/0).
  Commit 9cf7c540e7.
- Phase 5 DONE: ADR-135 defect-3 addendum, PIR (post-mortems/2026-10-22-…md), runbook detail=
  note, followthrough probe scripts/followthroughs/inngest-verify-clean-10390.sh (BETTERSTACK_QUERY_*
  already wired in sweeper). Commit d65c232da6. Pushed: HEAD=d65c232da6 on
  origin/feat-one-shot-10390-verify-blob-reject, draft PR #10864.
- Phase 1 root-cause fix: PENDING Phase-0 measured stderr (post-merge dispatch) — plan's
  branch table applies; under Verified-OK branch no code fix is owed (AC6 re-scoped by CTO).
- Floor bump 5→6: conditional (AC9) — only if a new bundle is promoted; not in this PR.

## Review Phase — IN PROGRESS (interrupted by context exhaustion)
- merge-tree vs origin/main: clean (rc=0). PANEL_SHA=d65c232da6eb4031f52adcd0121dd7954f0cdb76.
- Change class: code. design-risk: yes (new `detail=` token vocabulary consumed by a second
  surface) — design-validity pass running FIRST per review skill §step 4:
  - seat code-simplicity-reviewer: subagent 642c330d (background, still running)
  - seat architecture-strategist: subagent 1687d323 (background, still running)
- Resume: collect both seats, settle the mechanism question, then spawn the code-class panel
  MINUS lenses already run (arch-strategist done; code-simplicity reruns at Step 4 anyway).
  Panel = 8 agents (git-history-analyzer, pattern-recognition-specialist, architecture-strategist
  [dedup if design pass covered it], security-sentinel, performance-oracle, data-integrity-guardian,
  agent-native-reviewer, code-quality-analyst) + conditional: test-design-reviewer (test files
  touched) + structural-enumeration seat (guard-shaped: detail= classifier + shape test). Settled
  rulings to pass to every seat are the 7 rows in decision-challenges.md (all affirmed by CTO).
- Then: one-shot Step 5 (resolve findings incl. ADR-267 fix round) → 5.5 soleur:qa →
  6 soleur:compound → 7 soleur:ship → 8 DONE. Tally: seats=0 agent_rounds=2.

## Design-validity pass — COMPLETE, findings fixed (commit 2002c09aee)
- code-simplicity (642c330d): mechanism affirmed; fixed — last-failure-only verify.stderr
  semantics, vacuous S10 token pins → `_cls=<tok>` anchors, missing _summ_row pin (AC5),
  stdout file dance removed.
- architecture (1687d323): architecture affirmed; fixed — soak probe discriminator now
  signature-scoped (sig_undetailed), NOT-YET scoped to sig_rows, instrument-absent→3,
  digest input via env: + 64-hex gate, VF_STAMP keys reason:detail, F16 timeout arm,
  probe .test.sh added + registered in test-all.sh.
- inngest-config-refresh.test.sh 134/0, diagnose-inngest-verify-workflow.test.sh 26/0,
  probe suite 9/0. Remaining panel: 6 seats (git-history-analyzer, pattern-recognition,
  security-sentinel, performance-oracle, data-integrity-guardian, agent-native-reviewer,
  code-quality-analyst = 7 — dedup arch-strategist done, code-simplicity reruns at Step 4)
  + test-design-reviewer + structural-enumeration. Then Step 5 fix round → qa → compound → ship.

## Review Phase — panel complete, findings resolved

Panel: 10 seats (7 code-class + test-design + structural-enumeration + user-impact; arch-strategist deduped via design pass; code-simplicity reruns at review Step 4). All 7 settled CTO rulings held; zero DISSENT.

### Dedup ledger (raw findings → canonical defects)

| raw finding | canonical defect key | reporting seat(s) | fix commit |
|---|---|---|---|
| run_verify unguarded under bash -e (P1) | errexit-kills-failing-arm | pattern-recognition | this fix round |
| chain arm shadows identity (P2×2+P3×3) | classifier-ordering | user-impact, test-design, code-quality, data-integrity, structural | this fix round |
| MIN_ASSERTIONS under-raised/absent ×3 | vacuity-floors | test-design, pattern | this fix round |
| verdict matrix missing contract rows | probe-matrix-coverage | test-design, pattern, code-quality, data-integrity | this fix round |
| 4KiB bound pin vacuous | vacuous-bound | test-design, structural | this fix round |
| verify.stderr: no ts/digest binding; truncate-before-read; umask window | stderr-file-hardening | user-impact, data-integrity, security | this fix round |
| followthrough enrollment gap + premature task | enrollment-doc | agent-native | this fix round |
| probe header not signature-scoped; tick wording | contract-doc-drift | pattern, data-integrity, git-history | this fix round |
| S10 CWD-relative + comment-satisfiable pins; swallow-spelling gaps; call-site/membership pins | test-anchor-hardening | pattern, test-design, code-quality, structural, data-integrity | this fix round |
| diagnose workflow: arm-B comment, stale "swallows", unbounded cat, tar symlink, cid leak | diagnose-hardening | code-quality, git-history, security, structural | this fix round |
| VF_STAMP reason-only comment; probe rc=3 swallowed by command-subst | correctness-fixes | git-history, (found by new matrix row) | this fix round |
| runbook digest source; PATH portability; exec bit; mktemp template; counter self-test | misc-hardening | agent-native, test-design, pattern | this fix round |

Deferred (documented, not fixed): probe substring-predicate edges (detail2=/renamed marker fail toward FAIL = safe direction; old-binary-healthy vacuity bounded by operator-set earliest=); SEAM_REFUSED detail= double-semantics (cosmetic truncation); _summ_row free-text detail on non-signature rows (harmless); F16 boilerplate (house style is explicit); suite-durations rows for new suites (regen-owned); diagnose suite recursion arm (optional).

New real defect found by the added matrix row: run_one's `exit` inside command-substitution made transport rc=3 surface as NOT YET instead of CANNOT ESTABLISH — fixed with SCAN_RC propagation.

### Fix-round state
- Fix diff base: PANEL_SHA d65c232da6eb4031f52adcd0121dd7954f0cdb76
- Finding-seats for fix round: pattern-recognition-specialist, user-impact-reviewer, test-design-reviewer, security-sentinel, data-integrity-guardian, structural-enumeration, code-quality-analyst, agent-native-reviewer, git-history-analyzer
- Suites after fixes: refresh 160/0, diagnose 26/0, probe 14/0

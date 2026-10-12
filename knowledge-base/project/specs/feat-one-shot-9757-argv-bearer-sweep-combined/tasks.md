# Tasks: argv-bearer sweep, held-back sites, htpasswd, inspect-evidence

Plan: `knowledge-base/project/plans/2026-10-12-fix-argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence-plan.md`
Branch: `feat-one-shot-9757-argv-bearer-sweep-combined`. Draft PR: #10086. Trackers: #9757 (Ref), #10089 (Closes), #10091, #10092, #10093.
RED edits are local only; every pushed commit is green. No merge, no workflow dispatch: stop at PR ready and ask the operator for merge and apply-and-release notice approval.

## Phase 0: Baselines and measurements (read-only)

- 0.1 Run `python3 scripts/lint-shell-trace-credential-refusal.py --changed`; record baselined touched files (inspect-evidence, luks-monitor).
- 0.2 Green-baseline every edited suite (infra census, S-battery, community, registry-boot-guard, luks-monitor, web-git-data-probe, inngest, inspect, lint suite, registry-userdata-budget, web-host-provisioner-parity, git-lock-marker-telemetry vitest). Record pre-existing reds.
- 0.3 Measure `registry-userdata-budget.sh` stored size (expect ~21,500 B vs 21,600).
- 0.4 Read-only live shape count of the three heartbeat URL values against the shape guard (counts only; stop and decide on any failure).
- 0.5 Re-probe PR 10073 and PR 7390 (state, files).

## Phase 1: C, inspect-evidence xtrace refusal (#10089) [commit 1]

- 1.1 RED: must-refuse row (bash -x with the pair set, rc 78, value-free) and must-pass row (same argv without -x, stub aws) in `apps/cla-evidence/scripts/inspect.test.sh`.
- 1.2 Add the preamble after `set -euo pipefail` in `apps/cla-evidence/scripts/inspect-evidence.sh` (names `AWS_SECRET_ACCESS_KEY` and `R2_CLA_EVIDENCE_SECRET`).
- 1.3 Delete line 5 of `scripts/lint-shell-trace-credential-refusal.baseline.txt`; run the lint suite (check "first real row" mutation rows) and the repo-wide lint.

## Phase 2: A1, HMAC arms, census, leads (a)(b)(g) [commit 2]

- 2.0 Name and move the S4-stage hold-back rows with the S2-A rows in the same commit (`S4_HMAC_ALLOW`, census floor and wrapper control, `S4_HM_COPIES_WANT`, `S4_HM_HELD`, `hm_hmacflag`, `HM_PYARMS`, `heldpy` mutants); re-pin `EXPECTED_TESTS`.

- 2.1 RED: rewrite S2-A part 2 rows in `tests/scripts/test-argv-bearer-sweep.sh` to the end state (19 copies, zero `-hmac`, D1 comment row removed, mutation rows repointed).
- 2.2 Add the fixed-string whole-line allowance (two exact forms, with and without `|| SIG=""`) to `_probe_arms_code_of`, preceded by an exactly-one-canonical-per-arm row in `apps/web-platform/infra/cutover-inngest-workflow.test.sh`; add Guard 1 mutation and must-pass rows; keep the arms-seen floor.
- 2.3 Convert `registry-probe)` and `doublefire-probe)` HMAC lines in `scripts/cutover-inngest.sh` to the canonical form; delete hold-back comments.
- 2.4 Lead (a): `_bearer_ok "$tok"` before the `-H @-` feed; guard `$SIG` and the Cloudflare Access values before the local `--config -`.
- 2.5 Lead (b): shape-check then mask at the six unguarded `::add-mask::` sites.
- 2.6 Lead (g): bounded scrubbed first line instead of raw body at the four echoes.
- 2.7 Recording-curl rows for 2.4 to 2.6 in the S2-A harness.

## Phase 3: linkedin write-env [commit 2]

- 3.1 Copy the `_wenv_*` block verbatim from `x-setup.sh` into `plugins/soleur/skills/community/scripts/linkedin-setup.sh`; call it before the first write in `cmd_write_env`.
- 3.2 Update the population manifest rows in `community-argv.test.sh` (four validated writers, no deferred row); check `fixture-relative-assert.baseline.txt`.

## Phase 4: B, htpasswd [commit 3 for the workflow step; commit 6, LAST, for the registry template]

- 4.1 RED: Guard 3 rows (stub argv, rendered-block `bash -s` execution on ubuntu:24.04 + apache2-utils incl. failure arms, real-binary round trip in the new `apps/web-platform/infra/htpasswd-stdin.test.sh` (fail-closed docker), refusing stub-docker, recurrence floor 4 by site identity).
- 4.2 (commit 6) Convert `_htp_verify` and the two boot-step lines in `cloud-init-registry.yml`; replace the post-hoc `chmod 600` with `install -m 600 /dev/null /etc/zot/htpasswd` first; sweep the comments naming the argv form (line 18 trailing comment, ~610 prose, `zot-image.provenance.md`).
- 4.3 Convert the workflow step in `.github/workflows/apply-web-platform-infra.yml` (`docker run -i`).
- 4.4 Measure `user_data` size after; keep `REGISTRY_GZIP_BUDGET` unchanged; run `registry-boot-guard.test.sh`.

## Phase 5: A2, heartbeat URLs [commits 4 and 5]

- 5.1 RED: stdin-recording stub rows (per attempt, fail on missing `url = "` line), hostile/empty rows (a positive-pattern guard must fail them), derived population with residual allowlist (#10093), dash row for the inngest body, a new `web-git-data-probe.test.sh` harness (seam unset, PATH curl stub, reach override), and repoint every `luks-monitor.test.sh` argv-matching row incl. the vacuous negatives ~352 and ~622.
- 5.2 Convert `web-git-data-probe.sh` (add `-g` and leading `-q`; one substitution per attempt; stderr marker) and `luks-monitor.sh` (validate once before the loop; `log` helper marker; delete stale baseline row if confirmed) [commit 4].
- 5.3 Convert the `HEARTBEATSCRIPTEOF` body in `inngest-bootstrap.sh` (POSIX heredoc, negated-class `case` guard, `-q`, existing `logger -t "$LOG_TAG"` behind the hourly rate limiter) [commit 5; peel if PR 10073 unresolved].

## Phase 6: Docs and leads [commit 1 or 2]

- 6.1 Lead (d): canonical HMAC line in `ship/SKILL.md`, `postmerge/references/deploy-status-debugging.md`, runbooks `inngest-server.md`, `vector-redeliver.md`, `dsar-export-failed-job.md` (population by `git grep -n 'dgst .*-hmac'`).
- 6.2 Lead (f): verify the fatal-channel probe; code only on a gap.
- 6.3 Lead (h): add a `bash:3.2` run to the existing opt-in docker row in `community-argv.test.sh`.
- 6.4 ADR-280 addendum (2026-10-12, #9757 residue).
- 6.5 Tick every #9757 item with evidence; the Better Stack item cites PR #9811.

## Phase 7: D archive, gates, PR

- 7.0 Order check: B1/B2 is the final commit; ask the operator to rule on C1 and C6 (peel inngest-bootstrap, stage the registry template) before merge approval.
- 7.1 In a throwaway worktree off `origin/main`, run `archive-kb.sh` for slug `one-shot-9756-cla-evidence-sigv4-argv` and again for `cla-evidence-r2-sigv4-pair-off-curl-argv`; commit; cherry-pick onto the branch.
- 7.2 Rollback simulation in a scratch detached worktree: `git revert --no-commit` each apply-firing commit and run the gates.
- 7.3 Run each gate's own invocation (`--changed`, battery, c4 parity, markdownlint on plan and tasks).
- 7.4 PR body (first line: merging alone mutates production), coupling table, commit order, `Closes #10089`, `Ref #9757`, `Ref #9597`, `Ref #7797`, `Ref #9905`.
- 7.5 Review and QA; STOP; ask the operator for explicit approval to merge and for the apply and release notice.

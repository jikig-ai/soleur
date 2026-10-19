# Tasks - registry Phase 2 batch (#10119, #8408 close-out, #7530)

Plan: `knowledge-base/project/plans/2026-10-14-fix-registry-phase2-batch-htpasswd-stdin-clientip-alert-plan.md`

> **Re-scope (2026-10-15):** PR #10322 merged the #10119 registry-template conversion and its host replace, so every task below that edits `cloud-init-registry.yml`, the htpasswd/heartbeat suites, ADR-280 or the 10119 probe (Phase 5 and the Part A items) was dropped from this PR; this PR carries the #7530 alert, its probe, runbook and records, and the #8408 close-out. See the plan's Re-scope addendum.
Branch: `feat-one-shot-registry-phase2-batch-10119-8408-7530` | Draft PR: #10320 | Epic: #10205
Rules: every issue is `Ref #N` (never a closing keyword); the pipeline never merges this PR (Operator Holds); use `/usr/bin/grep -a`; use `$SECONDS` for timings; write any file containing the apply command's name with the Write tool.

## Phase 0 - Baselines (read-only, no commits)

- [ ] 0.1 Record `bash apps/web-platform/infra/registry-userdata-budget.sh` stored size (21,500 B) and headroom (100 B)
- [ ] 0.2 Record `apply-web-platform-infra.yml` size (473,632 B), `EXPECTED_TESTS`, S6 floors and `S6_ALLOW_CEIL=3`, `.claude/hooks/grep-q-pipe-guard.test.sh` `PRODUCER_JOIN` / `PJ_TRIPLES`, `bash plugins/soleur/test/c4-count-parity.test.sh` (13 passed)
- [ ] 0.3 Run green-on-main: `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh`, `zot-liveness-heartbeat.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `zot-image-fetch.test.sh`
- [ ] 0.4 Re-run the 7-day clientIP census and the 16-literal classification table (documentation addresses) against Better Stack (read-only)
- [ ] 0.5 Record the current registry `boot_id` (today `889b0dca-76b0-4648-90c2-03de21bf7ab1`)
- [ ] 0.6 `gh pr list --state open --search 'cloud-init-registry.yml in:path'` - no sibling PR on the file (owner comment on #10119)

## Phase 1 - RED first

- [ ] 1.1 Add the new S6 / registry-heartbeat rows, the rendered-boot-block rows and the alert suite; prove each reds on `main`

## Phase 2 - #7530 standing alert (commit 1; no host effect)

- [ ] 2.1 `betterstack-logs-alerts.tf`: `registry_clientip_not_rfc1918_sql` local, `logtail_exploration`, `logtail_exploration_alert` (`higher_than 0`, 300/900/0/1800, `treat_as_zero`, `paused = false`), live-probe counts and the sampling caveat in the comment
- [ ] 2.2 `apply-web-platform-infra.yml`: the two `-target=` lines
- [ ] 2.3 `apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh` (structural rows + the Guard 2 mutation rows on COPIES via `REGCIP_TF` / `REGCIP_WF`; dispatch floor; must-PASS re-wrapped SQL; verified zot digest pin); register in `.github/workflows/infra-validation.yml` (step and any `paths:` entry)
- [ ] 2.3b `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` count 13 to 14; add the row to `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` "Standing alarms over this source"; `git grep -c` of the source variable line in the .tf equals 14
- [ ] 2.4 Runbook `knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md` (CLO content list in the plan; never paste an address)
- [ ] 2.5 ADR-218 amendment (fourteenth Logs alert, signal class, #10321 pointer); ADR-211 note ("discharged 2026-10-14 by the standing alert: clientIP is detected and alerted, not masked"); ADR-184 note (rate-cap sampling and zot clientIP field order are a consumed contract)

## Phase 3 - Part E probes and enrollment (commit 2)

- [ ] 3.1 `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` + `.test.sh` (merge SHA via `gh pr view 10320`; qualifying dispatcher run = success, headSha equals or descends from the merge SHA, Dispatch and Poll steps `success`; template identity via `git show <headSha>:...cloud-init-registry.yml` holds no argv-form htpasswd; fresh `boot_id` vs the self-derived baseline; `htpasswd_*_matches=true`; informational posture lines; exit 1 only for a measured contradiction, missing baseline / unreadable window / equal boot ids / no new-boot row within 90 minutes are exit 3)
- [ ] 3.2 `scripts/followthroughs/registry-clientip-alert-7530.sh` + `.test.sh` (push-apply success for the merge SHA or a descendant, failed apply is exit 3; extract the SQL from the .tf; classification table, as-written count over the post-boot window, private-flagged control; counts only; never echo an address)
- [ ] 3.3 Register both readers in `scripts/lint-betterstack-emitter-read.sh` allowlist (+ its suite if floors move) and both suites in `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`; each probe header: credential posture, exit contract, `RETIREMENT:` line; xtrace refusal (exit 78)
- [ ] 3.4 `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 66 to 67 with the PLACEMENT / TRUTH / NO-SUBSTITUTE comment
- [ ] 3.5 `gh issue edit` #8408: remove the `registry-luks-live-8386.sh` directive and the `follow-through` label in ONE edit (CTO C2); add unfenced column-0 directives to #10119 and #7530 with comma-separated `secrets=` (copy probes to the main checkout first; `earliest=` = filing time)
- [ ] 3.6 Dry-run the real sweeper on the branch: `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-registry-phase2-batch-10119-8408-7530 -f dry_run=true`; read each tracker's `exit=` line

## Phase 4 - Docs (commit 3)

- [ ] 4.1 `2026-08-counsel-review-7440.md`: appended "fires on merge of PR #10320" pointer, frontmatter pointer key, `> Superseded` marker under trigger 2; cross-reference `2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`
- [ ] 4.2 `article-30-register.md` PA-8 (c) and (g): dated merge-conditioned brackets (CLO attests at ship Phase 5.5); update a legal-docs mirror if one exists
- [ ] 4.3 Comment the CTO ruling and future evidence bar on #7521 and #7456 (`Ref`, no closing keyword); note on #7079 recording the measured readiness-rider cost (+32 B) and that it was not included

## Phase 5 - #10119 registry template (commit 4, LAST, ONE commit with suites, battery rows and ADR-280 text)

- [ ] 5.1 `cloud-init-registry.yml`: `_htp_verify` stdin form (`printf '%s' "$2" | htpasswd -vi ...`)
- [ ] 5.2 Boot step: `install -m 600 /dev/null /etc/zot/htpasswd`; two separate `printf | htpasswd -Bin` pipelines (`>` then `>>`); guards stay above; remove the post-hoc `chmod 600`
- [ ] 5.3 Two heartbeat curls to `curl --disable --noproxy '*' -g -fsS -m 10 --config - < <(printf 'url = "%s"\n' '${..._url}')`
- [ ] 5.4 Byte discipline: expected stored 21,536 B (headroom 64 B); if headroom falls under 30 B drop the liveness then the disk heartbeat conversion; never the htpasswd conversion or `install -m 600`; the readiness-loop rider is NOT in this batch
- [ ] 5.5 Comments: ~610 prose, line-18 trailing comment, `zot-image.provenance.md`; re-measure bytes after each edit group; `REGISTRY_GZIP_BUDGET` never raised
- [ ] 5.6 `registry-boot-guard.test.sh` (127/6/1-through-the-pipe row; no `set -e`/`pipefail` before `_htp_verify`)
- [ ] 5.7 `htpasswd-stdin.test.sh`: rendered boot block from the offline templatefile render, run via `bash -s` in the digest-pinned ubuntu image; stub list from a census of the block's command words (at least `doppler`, `jq`, `findmnt`, `docker`, `sleep`, `chattr`, `curl`, `head`, plus the `/run/soleur/zot-image-id` fixture); failure arms; `>>` vs `>` row; stat in the first `htpasswd` stub under `umask 022`; extraction non-empty row; `DECLARED_ROWS` / `_arm_skip` counts
- [ ] 5.8 `zot-liveness-heartbeat.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `zot-image-fetch.test.sh`: curl stub reads `--config -` stdin with a bounded read (`read -t 1` / `timeout 1`)
- [ ] 5.9 `tests/scripts/test-argv-bearer-sweep.sh` S6: delete `S6_ALLOW` to zero, `S6_ALLOW_CEIL=0`, rewrite the ceiling row to assert zero entries, converted-site rows, new registry-heartbeat row, re-pin `EXPECTED_TESTS`
- [ ] 5.10 `.claude/hooks/grep-q-pipe-guard.test.sh` `PRODUCER_JOIN` / `PJ_TRIPLES` re-measured by derivation if new rows add a stub or producer
- [ ] 5.11 ADR-280 addendum (registry template converted, S6 allowlist zero, heartbeat inline-form residual)

## Phase 6 - Ratchets and verification (every new or edited `*.test.sh` and shell probe)

- [ ] 6.1 `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- [ ] 6.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`
- [ ] 6.3 `bash scripts/guard-vacuity-floor.test.sh`
- [ ] 6.4 `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`
- [ ] 6.5 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt <each new or edited .sh>` (baseline only shrinks; fix findings, never regenerate)
- [ ] 6.6 `bash scripts/lint-betterstack-emitter-read.test.sh`; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-shell-trace-credential-refusal.py`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash apps/web-platform/infra/registry-userdata-budget.sh` (headroom >= 30 B); `cloud-init-user-data-size.test.ts`
- [ ] 6.7 Full `bun` battery once (the `BASELINE_DECLARED_PROBES` ratchet surfaces only there); `terraform fmt -check` and offline validate for the alert; `npx markdownlint-cli2` on the plan, tasks and runbook

## Phase 7 - PR body and hand-over (the pipeline stops at a green, ready PR)

- [ ] 7.1 First line: "Merging this PR replaces the production registry host unattended (registry-host-replace-dispatch.yml push trigger); merge only when the replace can be watched."
- [ ] 7.2 `Ref` lines only: #10119, #8408, #7530, #7456, #7521, #7079, #10093, #10205 (no closing keyword in body or title)
- [ ] 7.3 Production-apply table, measured byte table, pre-merge `bash scripts/registry-delivery-change.sh` preview (this PR is the only render delta or name the others), recorded pre-merge `boot_id`
- [ ] 7.4 Hand-over section: pre-merge checks (incl. queued releases, other infra-path PRs, staged revert), recommended merge window, merge command, post-merge watch keyed on the merge SHA with a 4,800 s deadline, `unverified` read-first rule, later-release rerun note (P3 waits for the co-fired release), failed-first-boot stance, "rotation not required", the owner's #8408 close command
- [ ] 7.5 Mark ready; do NOT arm auto-merge; do NOT merge (Operator Holds)

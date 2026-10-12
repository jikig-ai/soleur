# S7c evidence: J0 measurement of derivation recall (tracker #9217, Ref only)

Written before any owner suite or the guard is edited (AC-1). Branch `feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall` at `ffe17b85c3` (the S7c branch merged with origin/main). Host: 16 cores, `gawk` 5.4.1 only, load average 14 to 45 during the probes (every wall time below carries its load). Raw logs (suite output, hit logs, per-run results, the mutant outputs) stay under `/var/tmp/s7c/`, outside the repository; this file carries verdict blocks only. The reach table is also written machine-readably to `reach-table.tsv` beside this file (columns: arm-set, suite, verb, producer-files, class, drain-state, flag, action, vocabulary-reason, note), which Phase 3 and 4 consume.

## 0.1 Re-run of the derivation on the merged tree

Commands, run from the repository root of the merged tree (`git status --porcelain` empty before the run):

```text
ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-derive.py
ulimit -v 6000000; bash .claude/hooks/grep-q-pipe-guard.test.sh
```

The J0 output is byte-identical to `j0-plan-time-output.txt` (`cmp` reports identical), so main moved nothing that changes the population. BASE reads 66 pairs and 120 producer triples. The guard on the same tree exits 0 and prints `PASS: grep-q-producer-join (66 derived pairs, 120 producer triples; 14 drains rows verified, 53 exempt rows with a vocabulary reason)`, its twelve `DEFERRED:` lines and 67 `JOINED:` lines (66 derived pairs plus the variable-named `ssh` row); the guard run took about 30 s under `ulimit -v 6000000`. The port therefore reproduces the guard, and the arm increments are attributable.

```text
J0 S7c: base is the port of the guard derivation (S7b state)
  BASE: 66 pairs, 120 producer triples (the guard prints 66 and 120 at 0aae3f8680)
  R1: +29 pairs, +42 triples over base; 27 test files; lost vs base: 0
  R2: +1 pairs, +3 triples over base; 1 test files; lost vs base: 0
  R3: +47 pairs, +70 triples over base; 42 test files; lost vs base: 0
  R4a: +18 pairs, +30 triples over base; 16 test files; lost vs base: 0
  R4b: +10 pairs, +12 triples over base; 10 test files; lost vs base: 0
  R4c: +18 pairs, +30 triples over base; 16 test files; lost vs base: 0
  R5a: +2 pairs, +2 triples over base; 1 test files; lost vs base: 0
  R5b: +6 pairs, +10 triples over base; 4 test files; lost vs base: 0
  R6: +0 pairs, +0 triples over base; 0 test files; lost vs base: 0
  R7: +7 pairs, +8 triples over base; 7 test files; lost vs base: 0
  R8: +0 pairs, +1 triples over base; 0 test files; lost vs base: 0
  U1 = R1+R2+R4b+R5a+R5b+R6+R7+R8: +57 pairs, +81 triples over base; 48 test files; lost vs base: 0
  U2 = U1+R3: +90 pairs, +142 triples over base; 66 test files; lost vs base: 0
  ALL: +100 pairs, +166 triples over base; 71 test files; lost vs base: 0
```

U2 is not a superset of R3 alone. Two pairs in R3's list (`cron-egress-firewall.test.sh timeout`, `cron-egress-self-heal.test.sh timeout`) are absent from U2. Measured by deriving R3 with each other arm in turn (`derive(files, (R3, X))`): the pair survives with R2, R4b, R5a/R5b, R6, R7 or R8 and is lost only when R1 is on, because R1 joins the continuation line `| timeout "$CV_CAP" docker exec -i ... \` of `cron-egress-resolve.sh:305` into its predecessor `CONTAINER_VIEW="$(printf '%s\n' "$HOSTS_SORTED" \`, whose left context holds an odd number of double quotes (it opens `"$(`), so the quote-parity test skips the bar: the documented bar-inside-`"$( ... )"` under-derivation, reached through R1's join (without R1 the bar sits at the start of its own line with an empty left context). 17 of U2's 90 new pairs need R1 and R3 together and are in no single arm's list (decision-challenges item 23).

## 0.2 Classification of the new pairs

Every new pair of U2 (90 new pairs, plus the 11 listed pairs that gain a producer) is classed in the reach table below; U1 is a subset of U2 (57 of the 90). The closed vocabulary was enough: no new word was needed (decision-challenges item 25). Class counts, by pair set and by suite tranche (BLOCKED and VARNAMED are 0 everywhere: no suite is red at base for a non-sandbox, non-host reason, and no new pair is a variable-named verb):

| pair set | pairs | EXEC | TEXT | UNVERIFIED | BLOCKED | NOTCMD | VARNAMED |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U1 new pairs (R1, R2, R4b, R5a, R5b, R6, R7, R8) | 57 | 28 | 18 | 7 | 0 | 4 | 0 |
| R3-only new pairs (U2 minus U1) | 33 | 13 | 7 | 2 | 0 | 11 | 0 |
| U2 new pairs (the final configuration) | 90 | 41 | 25 | 9 | 0 | 15 | 0 |
| new pairs in tranche-1 suites (the 51 suites behind U1) | 71 | 35 | 19 | 9 | 0 | 8 | 0 |
| new pairs in tranche-2 suites (the 18 further suites) | 19 | 6 | 6 | 0 | 0 | 7 | 0 |
| listed pairs that gain a producer in U2 (11) | 11 | 5 | 5 | 1 | 0 | 0 | 0 |

NOTCMD pairs (15 of the 90, none of them a stdin-reading command; all `exempt not-a-command`):

- `died` (4 suites: luks-monitor, workspaces-luks-freeze, workspaces-luks-rollback-refusal, workspaces-luks-staging): `died` is a shell function of `workspaces-luks-harness.sh`, and the producer site is a printf message that spells `died ran | died ran | ...` (prose); R4b reads it as a pipe.
- `lexer`, `fatal`, `bunfig.local.toml`: words of a case-pattern alternation (`"lexer depth"|"lexer budget"|...`, `panic:*|"fatal error"*|...`, `bunfig.toml | */bunfig.toml | bunfig.local.toml | ...`) that the case-pattern exclusion misses when the patterns are quoted or glob-shaped.
- `ready`: prose in `betterstack-query.sh:110` (`# missing | unauthenticated | ready | unknown`).
- `AGENTS.md`, `constitution.md`: file names inside a markdown table printed by `rule-audit.sh`.
- `_liquid_redact_secrets`: a real shell function of `content-publisher.sh` (it reads stdin, but it is not an external command and not a stub).
- `set` (2 suites) and `systemctl` (2 suites): the YAML list-item block scalar `- |` followed by `set -a` or `systemctl daemon-reload`. This is a defect of the measurement, not noise in the corpus: R1 joins a line that ends in a single bar with the next line, and the block-scalar exclusion only knows `key: |`. Re-measured with the exclusion widened to `(:|(^|[ \t])-)[ \t]*[|>][-+]?[ \t]*$` (a patched copy of `j0-derive.py`, output kept outside the repo): BASE still 66 and 120, R1 +29, R3 +47, U1 +57 pairs and 81 triples, U2 **+86 pairs, +136 triples, 65 test files** (was 90, 142, 66). The four pairs need no row once the derivation excludes `- |` (decision-challenges item 19). The plan's "about 7 still noise" for R3 is 11 of the 33 pairs only R3 reads.

## 0.3 Reach probe

Method. The S7b tooling was recovered from commit `6e320b391e` into this directory (`j0-stubs.py`, `j0-sites.py`, `j0-instrument.py`) and adapted, because the S7c `j0-derive.py` renamed the helpers the S7b tools imported. Changes: `j0-stubs.py` and `j0-sites.py` use the S7c names and read all arms (`j0-sites.py` prints every logical-line site that any arm reads as `... | VERB`, including a bar inside a command substitution); `j0-stubs.py` adds the `helperarg` and `loop` stub kinds; `j0-instrument.py` also writes a marker into `printf '#!/bin/bash\n...'`, `printf '#!%s\n...'` and loop-built stubs (a marker inside the loop body that records the stub's own name through `${0##*/}`). One hand patch: the `doppler` stub of `doppler-download-error-channel.test.sh` is written through a variable (`printf '%s\n' "$dop" > "$sb/bin/doppler"`), so a `sed -i '1a ...'` line was added after it in the three sandboxes. Result: 124 stub sites instrumented in 60 files (fn 11, heredoc 82, loop-built 6, printf format 25), all passing `bash -n`; 14 sites skipped by the tool (guard row text 2, a `tree_row` call and the `slow_lexer` definition 2, the `vt_run` name 1, a printf of the feeder suite 1, three `for bin in ...` availability checks and one symlink farm of real binaries 4, the real function `_liquid_redact_secrets` 1, a data file written by `lint-dual-lockfile.test.sh` 1, the `doppler` stub of `doppler-download-error-channel.test.sh` 1 (hand patch above), and the `ready` function of `web2-luks-live-6931.test.sh` 1 (its function marker is already in)).

The marker is `[ -p /dev/stdin ] && echo "<file>:<line>|<verb>|$*" >> "${S7B_REACH_LOG:-<fallback>}"` as the first statement of every stub definition a suite owns (a suite is run once for all its verbs). Markers lived only in three scratch sandboxes made by `bash scripts/soleur-sandbox.sh new s7c-reach-{a,b,c}` and in two scratch clones; nothing was committed and `git status` of the worktree shows only this directory. Each suite ran once under `timeout 300` and `ulimit -v 6000000` through `bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- bash -c 'ulimit -v 6000000; timeout -k 5 300 bash "$1" </dev/null' _ <suite>`, at most three at a time, one sandbox each. The population runs no bun or vitest (checked by grep: the `vitest` and `bun` words in `ci-deploy.test.sh`, `heartbeat-reconcile-issue-step.test.sh` and `lint-dual-lockfile.test.sh` are stubs or text), so `ulimit -v` was applied to every run. `scripts/test-all.sh` was not run.

What a hit means. The marker records a stub whose stdin is any pipe: a producer pipe, a process substitution, a here-string (bash 5 feeds small here-strings through a pipe) or a pipe the suite inherited and passed down to a script that calls the stub. So every hit was read against its producer line: a pair is EXEC only when a recorded argv has the producer's consuming shape (`--config -`, `-K -`, `--header @-`, `--data-binary @-`, `--password-stdin`, `secrets set`, `secret set`, `--input -`, `-xf -`, `-f -`, `-c -`, or, for filters such as jq, grep, awk, tr, perl, python3, logger, the same call shape as the producer line). Hits whose argv does not have that shape (a `secrets get`, a `grep -v pat FILE`, a `logger -t TAG MESSAGE`) are inherited-stdin noise and do not make EXEC. Caveat that stays: an argv can match a producer line and still come from a here-string or process substitution in the same script; the producer-site listing for each EXEC row was checked to be a `printf|echo|cat ... | VERB` or a pipeline, never a bare here-string, but the marker alone cannot prove it.

Classes. EXEC: a piped call with the producer's shape reached the stub. TEXT: the suite finished green (in the sandbox or a real clone) and no such call arrived. UNVERIFIED: the suite hit the 300 s cap, or is red for a host reason, and no matching call was seen. NOTCMD, VARNAMED, BLOCKED as in S7b.

Tranches. Tranche 1 = the 50 suites behind U1 that the sandbox can run (`cloud-init-inngest-bootstrap.test.sh`, the 51st, is in the real clone below). Tranche 2 = the 17 suites only the any-producer arm adds, all run; the 18th, `.claude/hooks/grep-q-pipe-guard.test.sh` (its only pair is `set`, NOTCMD), was not run because running the guard inside a sandbox proves nothing about a pair that is not a command. Tranche 2 is therefore complete: every one of the 33 R3-only pairs is classified from a run or, for the 11 NOTCMD ones, from the producer line.

Red runs. 14 suites were red in a sandbox (the copy has no `.git`, no tags and no `knowledge-base/`; `run-isolated` also maps the caller to uid 0). Each was re-run once in a real local clone of the worktree (`git clone`, history and 4,084 tags, `knowledge-base/` present) through `plugins/soleur/scripts/run-in-pid-namespace.sh` with the same bounds. Result: 9 went green in the clone (the sandbox red was environmental, never BLOCKED); 2 hit the 300 s cap in the clone (`git-data-cutover-access.test.sh`, `test-sentry-alert-live-fidelity.sh`; both logged matching hits first); 3 stayed red: `workspaces-luks-rollback-refusal.test.sh` refuses to run for a user in the disk group (host), `fixtures-validate-infra-templates.sh` fails closed because this host has no `cloud-init` (host; CI has it), and `infra-config-apply.test.sh` is red under the isolation helper because one row (`chmod 000` does not stop the uid 0 that `unshare -Ur` maps) cannot pass there; it went green (250 passed) in a single plain non-isolated run in the clone (a suite, not a mutant, writing only under its own `TEST_DESTDIR`). Nothing is BLOCKED: no suite is red at base for a reason outside this host.

`cloud-init-inngest-bootstrap.test.sh` was run only in a real clone with tags (never in a sandbox copy), with markers at its docker (def 2004) and timeout (def 2025) stubs added in the scratch clone; the file in the worktree is unchanged. Result: rc0, `Results: 240/240 passed`, 12 s at load 41, 5 piped `login 10.0.1.30:5000 -u zu --password-stdin` calls through both stubs. So the suite is green at base, `blocked-#9956` is untrue (decision-challenges items 6 and 20), and both pairs are EXEC and fenced (0.5).

Run table (rc 0 green, 124 or 137 the cap, other red; wall in seconds; load average before and after; the last column counts hit-log lines of the run, stdin-inheriting hits included):

| run | env | suite | rc | wall s | load before > after | log lines |
| --- | --- | --- | --- | --- | --- | --- |
| t1 | sandbox | apps/web-platform/infra/cron-egress-self-heal.test.sh | 1 | 14 | 13.71 > 14.28 | 0 |
| t1 | sandbox | apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | 0 | 49 | 13.71 > 15.76 | 77 |
| t1 | sandbox | apps/web-platform/infra/git-data-cutover-access.test.sh | 1 | 18 | 15.76 > 15.07 | 7 |
| t1 | sandbox | apps/web-platform/infra/git-data-rung2-rehearsal.test.sh | 0 | 3 | 15.07 > 15.07 | 1 |
| t1 | sandbox | apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh | 0 | 1 | 15.07 > 14.35 | 0 |
| t1 | sandbox | apps/web-platform/infra/workspaces-luks-freeze.test.sh | 0 | 49 | 14.35 > 17.08 | 0 |
| t1 | sandbox | apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | 2 | 0 | 17.08 > 17.08 | 0 |
| t1 | sandbox | apps/web-platform/scripts/postgrest-reload-schema.test.sh | 0 | 1 | 17.08 > 17.87 | 38 |
| t1 | sandbox | apps/web-platform/infra/git-data-liveness.test.sh | 0 | 111 | 14.28 > 17.87 | 122 |
| t1 | sandbox | apps/web-platform/infra/inngest-dedicated-host-classify.test.sh | 0 | 3 | 17.87 > 18.29 | 17 |
| t1 | sandbox | .claude/hooks/grep-rewrite.test.sh | 0 | 10 | 17.87 > 17.54 | 254 |
| t1 | sandbox | apps/web-platform/infra/web-probes-token-rotation.test.sh | 0 | 20 | 18.29 > 16.73 | 0 |
| t1 | sandbox | apps/web-platform/infra/workspaces-luks-host-token-refresh.test.sh | 0 | 2 | 16.73 > 16.73 | 88 |
| t1 | sandbox | apps/web-platform/infra/workspaces-luks-staging.test.sh | 0 | 10 | 16.73 > 17.24 | 0 |
| t1 | sandbox | apps/web-platform/test/infra/ghcr-blocked-alert.test.sh | 2 | 0 | 17.24 > 17.24 | 0 |
| t1 | sandbox | plugins/soleur/skills/community/test/community-argv.test.sh | 0 | 52 | 17.54 > 19.76 | 247 |
| t1 | sandbox | plugins/soleur/test/operator-9321-stages.test.sh | 2 | 0 | 19.76 > 19.76 | 0 |
| t1 | sandbox | plugins/soleur/test/operator-stage-approval-hook.test.sh | 0 | 12 | 19.76 > 18.97 | 0 |
| t1 | sandbox | .claude/hooks/guardrails.test.sh | 0 | 61 | 17.24 > 20.46 | 36 |
| t1 | sandbox | apps/web-platform/infra/ci-deploy.test.sh | 124 | 300 | 13.71 > 23.16 | 1035 |
| t1 | sandbox | apps/web-platform/infra/doppler-download-error-channel.test.sh | 0 | 4 | 23.16 > 22.67 | 0 |
| t1 | sandbox | apps/web-platform/infra/git-data-root-key.test.sh | 0 | 97 | 22.67 > 25.97 | 0 |
| t1 | sandbox | apps/web-platform/infra/luks-monitor.test.sh | 0 | 16 | 25.97 > 24.74 | 0 |
| t1 | sandbox | scripts/check-web-host-escrow-config.test.sh | 124 | 301 | 18.97 > 26.24 | 0 |
| t1 | sandbox | plugins/soleur/test/destructive-command-guard-hook.test.sh | 124 | 300 | 20.46 > 26.14 | 38 |
| t1 | sandbox | plugins/soleur/test/operator-agent-runnable.test.sh | 1 | 18 | 26.14 > 24.34 | 0 |
| t1 | sandbox | plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh | 0 | 3 | 24.34 > 23.67 | 15 |
| t1 | sandbox | scripts/web2-rebirth-recovery-check.test.sh | 0 | 49 | 26.24 > 23.67 | 579 |
| t1 | sandbox | tests/hooks/test_incidents.sh | 0 | 1 | 23.67 > 24.58 | 0 |
| t1 | sandbox | scripts/inngest-probe-heartbeat-feeder.test.sh | 0 | 33 | 23.67 > 31.33 | 101 |
| t1 | sandbox | apps/web-platform/infra/workspaces-boot-unlock.test.sh | 124 | 300 | 24.74 > 36.45 | 420 |
| t1 | sandbox | scripts/web2-rebirth.test.sh | 0 | 217 | 31.33 > 38.09 | 12717 |
| t1 | sandbox | tests/scripts/test-git-data-birth-readiness-gate.sh | 124 | 300 | 24.58 > 42.70 | 8 |
| t1 | sandbox | tests/scripts/test-sentry-alert-live-fidelity.sh | 1 | 0 | 42.70 > 42.70 | 0 |
| t1 | sandbox | tests/scripts/test-zot-log-channel-probe.sh | 1 | 22 | 42.70 > 41.24 | 442 |
| t1 | sandbox | apps/web-platform/infra/workspaces-luks-provision.test.sh | 137 | 305 | 36.45 > 44.81 | 1355 |
| t1 | sandbox | apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh | 0 | 50 | 44.81 > 44.45 | 4 |
| t1 | sandbox | .claude/hooks/browser-snapshot-credential-guard.test.sh | 1 | 0 | 44.45 > 44.45 | 0 |
| t1 | sandbox | .github/scripts/test/fixtures-validate-infra-templates.sh | 1 | 10 | 44.45 > 45.43 | 0 |
| t1 | sandbox | tests/scripts/test-argv-bearer-sweep.sh | 124 | 301 | 38.09 > 44.88 | 1150 |
| t1 | sandbox | plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh | 0 | 29 | 45.43 > 45.14 | 32 |
| t1 | sandbox | tests/scripts/test-git-data-boot-signal-poll.sh | 0 | 21 | 44.88 > 44.25 | 0 |
| t1 | sandbox | tests/scripts/test-supabase-advisor-scan.sh | 0 | 7 | 44.25 > 44.03 | 124 |
| t1 | sandbox | plugins/soleur/test/operator-script.test.sh | 0 | 277 | 45.14 > 31.78 | 6 |
| t1 | sandbox | scripts/check-cloudflare-token-drift.test.sh | 0 | 90 | 31.78 > 38.21 | 299 |
| t1 | sandbox | scripts/ship-incident-pir-gate-mutation.test.sh | 0 | 9 | 38.21 > 39.12 | 200 |
| t1 | sandbox | scripts/web-host-reboot.test.sh | 124 | 300 | 39.12 > 39.02 | 8636 |
| t1 | sandbox | tests/scripts/test-destroy-guard-counter-web-platform.sh | 0 | 41 | 39.02 > 37.28 | 0 |
| t1 | sandbox | tests/scripts/test-git-data-rung2-evidence-capture.sh | 1 | 92 | 37.28 > 36.93 | 70 |
| t1 | sandbox | tests/scripts/test-workspaces-luks-cutover-gate.sh | 0 | 5 | 36.93 > 36.52 | 0 |
| t2 | sandbox | apps/web-platform/infra/git-data-flag-precheck.test.sh | 0 | 15 | 41.24 > 41.31 | 6 |
| t2 | sandbox | apps/web-platform/infra/inngest-inventory.test.sh | 0 | 27 | 41.31 > 43.94 | 0 |
| t2 | sandbox | apps/web-platform/infra/webhook-doppler-token-reread.test.sh | 0 | 7 | 43.94 > 45.47 | 0 |
| t2 | sandbox | apps/web-platform/scripts/lib/in-image-copy-src.test.sh | 0 | 1 | 45.47 > 45.47 | 4 |
| t2 | sandbox | apps/web-platform/infra/cutover-inngest-workflow.test.sh | 1 | 80 | 41.24 > 44.88 | 0 |
| t2 | sandbox | apps/web-platform/infra/infra-config-apply.test.sh | 1 | 78 | 44.88 > 39.51 | 1 |
| t2 | sandbox | apps/web-platform/infra/inngest.test.sh | 0 | 36 | 39.51 > 34.91 | 0 |
| t2 | sandbox | .github/scripts/test/test-mint-inngest-bootstrap-tag.sh | 0 | 175 | 45.47 > 34.80 | 62 |
| t2 | sandbox | scripts/followthroughs/infra-config-activation-7220.test.sh | 0 | 6 | 34.80 > 35.54 | 1 |
| t2 | sandbox | scripts/lint-dual-lockfile.test.sh | 0 | 3 | 35.54 > 35.33 | 0 |
| t2 | sandbox | scripts/test-jaccard-duplicates.sh | 0 | 1 | 35.33 > 35.33 | 0 |
| t2 | sandbox | apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | 1 | 127 | 34.91 > 38.11 | 0 |
| t2 | sandbox | apps/web-platform/scripts/run-migrations-schema-probe.test.sh | 0 | 2 | 38.11 > 37.62 | 7 |
| t2 | sandbox | scripts/check-deploy-script-parity.test.sh | 0 | 3 | 37.62 > 37.62 | 2 |
| t2 | sandbox | scripts/followthroughs/web2-luks-live-6931.test.sh | 0 | 169 | 37.62 > 38.50 | 324 |
| t2 | sandbox | scripts/test-content-publisher.sh | 0 | 28 | 38.50 > 39.95 | 0 |
| t2 | sandbox | scripts/verify-agent-security-slice1.test.sh | 0 | 8 | 39.95 > 41.15 | 0 |
| bs | real clone+tags | apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | 0 | 12 | 41.25 > 43.03 | 10 |
| red | real clone+tags | apps/web-platform/infra/cron-egress-self-heal.test.sh | 0 | 33 | 37.49 > 38.47 | 0 |
| red | real clone+tags | apps/web-platform/infra/git-data-cutover-access.test.sh | 124 | 300 | 38.47 > 38.54 | 38 |
| red | real clone+tags | apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | 2 | 0 | 38.54 > 38.54 | 0 |
| red | real clone+tags | apps/web-platform/test/infra/ghcr-blocked-alert.test.sh | 0 | 45 | 38.54 > 36.76 | 0 |
| red | real clone+tags | plugins/soleur/test/operator-9321-stages.test.sh | 0 | 258 | 36.76 > 35.79 | 208 |
| red | real clone+tags | plugins/soleur/test/operator-agent-runnable.test.sh | 0 | 88 | 35.79 > 36.13 | 12 |
| red | real clone+tags | tests/scripts/test-sentry-alert-live-fidelity.sh | 124 | 300 | 36.13 > 21.10 | 4 |
| red | real clone+tags | tests/scripts/test-zot-log-channel-probe.sh | 0 | 17 | 21.10 > 22.58 | 442 |
| red | real clone+tags | .claude/hooks/browser-snapshot-credential-guard.test.sh | 0 | 1 | 22.58 > 22.58 | 1 |
| red | real clone+tags | .github/scripts/test/fixtures-validate-infra-templates.sh | 1 | 5 | 22.58 > 22.85 | 0 |
| red2 | real clone+tags | apps/web-platform/infra/cutover-inngest-workflow.test.sh | 0 | 36 | 22.85 > 25.06 | 0 |
| red2 | real clone+tags | apps/web-platform/infra/infra-config-apply.test.sh | 1 | 48 | 25.06 > 23.01 | 1 |
| red2 | real clone+tags | apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | 0 | 79 | 23.01 > 20.01 | 0 |
| red3 | real clone+tags | tests/scripts/test-git-data-rung2-evidence-capture.sh | 0 | 38 | 19.85 > 22.08 | 70 |
| red3 | real clone+tags | apps/web-platform/infra/cron-egress-self-heal.test.sh | 0 | 23 | 22.08 > 22.85 | 0 |
| red3 | real clone+tags | apps/web-platform/infra/cron-egress-firewall.test.sh | 0 | 47 | 22.85 > 26.99 | 0 |
| r3x | sandbox | apps/web-platform/infra/cron-egress-firewall.test.sh | 1 | 51 | 37.91 > 35.50 | 0 |
| r3x | sandbox | apps/web-platform/infra/cron-egress-self-heal.test.sh | 1 | 22 | 35.50 > 32.27 | 0 |

Reach table, one row per pair (arm-set is the arm or arms of `j0-derive.py` that read the pair; `joint` means R1 plus R3 together; the three trailing rows of `reach-table.tsv` are extra listed or R3-alone rows):

| arm-set | suite | verb | class | argv seen (first piped hit) |
| --- | --- | --- | --- | --- |
| R7 | browser-snapshot-credential-guard.test.sh | jq | EXEC | -r .tool_name // empty |
| joint(R1+R3) | grep-q-pipe-guard.test.sh | set | NOTCMD | - |
| R4b | grep-rewrite.test.sh | grep | TEXT | -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-d |
| R4b | grep-rewrite.test.sh | jq | TEXT | -j  |
| R7 | guardrails.test.sh | perl | EXEC | -0777 -pe s/((?<!<)<<(?!<)-?\s*["']?)(\w+)(["']?)(.*?)(\n[ \t]*\2\b)/$ |
| R1,R3 | fixtures-validate-infra-templates.sh | terraform | UNVERIFIED | - |
| joint(R1+R3) | test-mint-inngest-bootstrap-tag.sh | gh | EXEC | api --method POST repos/jikig-ai/soleur/git/tags --input - |
| R2 | ci-deploy.test.sh | docker | EXEC | login 10.0.1.30:5000 -u mock-ZOT_PULL_USER --password-stdin |
| joint(R1+R3) | ci-deploy.test.sh | doppler | UNVERIFIED | - |
| R3 | ci-deploy.test.sh | logger | EXEC | -t ci-deploy -p user.warning |
| joint(R1+R3) | ci-deploy.test.sh | python3 | UNVERIFIED | - |
| joint(R1+R3) | ci-deploy.test.sh | systemctl | NOTCMD | - |
| R3 | ci-deploy.test.sh | tr | EXEC | -c [:print:]   |
| R2 | cloud-init-inngest-bootstrap.test.sh | docker | EXEC | login 10.0.1.30:5000 -u zu --password-stdin |
| R2 | cloud-init-web-zot-seed.test.sh | docker | EXEC | login 10.0.1.30:5000 -u zot-pull --password-stdin |
| R7 | cron-egress-self-heal.test.sh | jq | TEXT | - |
| joint(R1+R3) | cutover-inngest-workflow.test.sh | doppler | TEXT | - |
| R1,R3 | doppler-download-error-channel.test.sh | doppler | TEXT | - |
| R1,R3 | git-data-cutover-access.test.sh | doppler | EXEC | secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd |
| joint(R1+R3) | git-data-flag-precheck.test.sh | doppler | EXEC | secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd |
| R1,R3 | git-data-liveness.test.sh | curl | EXEC | --disable --noproxy * -fsS -m 10 -o /dev/null --config - |
| R1,R3 | git-data-root-key.test.sh | doppler | TEXT | - |
| R1,R3 | git-data-rung2-rehearsal.test.sh | curl | EXEC | --disable --noproxy * --connect-timeout 5 -m 20 -sS -f -K - https://ap |
| R3 | infra-config-apply.test.sh | logger | TEXT | -t infra-config-apply SOLEUR_INFRA_CONFIG_HOOK_ORPHAN dangling_hook_co |
| R1,R3 | inngest-dedicated-host-classify.test.sh | curl | EXEC | --disable --noproxy * -s --max-time 30 -o /tmp/tmp.eX5Xm418kx/health-b |
| R4b | inngest-dedicated-host-classify.test.sh | jq | TEXT | -R -r def inngest_probe_row: type == "object" and .SYSLOG_IDENTIFIER = |
| R3 | inngest-inventory.test.sh | logger | TEXT | - |
| R3 | inngest.test.sh | logger | TEXT | - |
| joint(R1+R3) | inngest.test.sh | systemctl | NOTCMD | - |
| R4b | luks-monitor.test.sh | died | NOTCMD | - |
| R1,R3 | soleur-host-bootstrap-observability.test.sh | doppler | TEXT | - |
| R1,R3 | web-probes-token-rotation.test.sh | doppler | TEXT | - |
| R3 | webhook-doppler-token-reread.test.sh | logger | TEXT | - |
| R7 | workspaces-boot-unlock.test.sh | awk | UNVERIFIED | - |
| joint(R1+R3) | workspaces-boot-unlock.test.sh | docker | UNVERIFIED | - |
| R1,R3 | workspaces-boot-unlock.test.sh | doppler | UNVERIFIED | - |
| R4b | workspaces-luks-freeze.test.sh | died | NOTCMD | - |
| R1,R3 | workspaces-luks-host-token-refresh.test.sh | doppler | TEXT | - |
| R5b | workspaces-luks-host-token-refresh.test.sh | grep | TEXT | -v ^DOPPLER_TOKEN= /var/tmp/wl-token-refresh.ZbUrXPO2/h1.env |
| R5b | workspaces-luks-host-token-refresh.test.sh | sed | TEXT | -n s/^DOPPLER_TOKEN=//p /var/tmp/wl-token-refresh.ZbUrXPO2/h1.env |
| R3 | workspaces-luks-provision.test.sh | awk | EXEC | /^[[:space:]]*device:/{print $2; exit} |
| R5a | workspaces-luks-provision.test.sh | cryptsetup | EXEC | luksFormat --batch-mode --type luks2 --label soleur-formatting --uuid  |
| R5a | workspaces-luks-provision.test.sh | curl | EXEC | --disable --noproxy * --config - --aws-sigv4 aws:amz:auto:s3 -sS --max |
| R4b | workspaces-luks-rollback-refusal.test.sh | died | NOTCMD | - |
| R4b | workspaces-luks-staging.test.sh | died | NOTCMD | - |
| R3 | workspaces-luks-verify-workflow.test.sh | jq | TEXT | - |
| R7 | zot-disk-heartbeat-redaction.test.sh | jq | EXEC | -r if type=="object" and has("message") then .message else empty end |
| R3 | in-image-copy-src.test.sh | tar | EXEC | -C /tmp/tmp.qeEbLMWKMO/stubdst20 --no-same-owner -xf - |
| R1,R3 | postgrest-reload-schema.test.sh | curl | EXEC | --disable --noproxy * --silent --show-error --request POST --url https |
| R3 | run-migrations-schema-probe.test.sh | psql | EXEC | postgresql://fake@fake/fake --no-psqlrc --set ON_ERROR_STOP=1 -tAq -c  |
| R1,R3 | ghcr-blocked-alert.test.sh | doppler | TEXT | - |
| joint(R1+R3) | community-argv.test.sh | base64 | EXEC |  |
| R1,R3 | community-argv.test.sh | curl | EXEC | --disable --noproxy * -s -w \n%{http_code} --config - -X POST --data-u |
| R5b | community-argv.test.sh | od | EXEC | -An -v -tx1 |
| R5b | community-argv.test.sh | openssl | EXEC | dgst -sha1 -binary |
| joint(R1+R3) | community-argv.test.sh | tr | EXEC | -d  \n |
| R7 | destructive-command-guard-hook.test.sh | jq | EXEC | -r if type != "object" then "invalid" else |
| R3 | destructive-command-guard-hook.test.sh | lexer | NOTCMD | - |
| joint(R1+R3) | destructive-command-guard-hook.test.sh | perl | EXEC | /var/tmp/soleur-sbx.s7c-reach-c.F7hRVauf/plugins/soleur/hooks/lib/shel |
| R1,R3 | heartbeat-reconcile-issue-step.test.sh | curl | TEXT | - |
| R4b | operator-9321-stages.test.sh | gh | EXEC | secret set DOPPLER_TOKEN_INFRA_APP --env infra-privileged -R jikig-ai/ |
| R3 | operator-9321-stages.test.sh | jq | EXEC | -r --arg n release-app-mint (. // [])[] / select(.name == $n) / .slug |
| R4b | operator-agent-runnable.test.sh | gh | TEXT | - |
| R3 | operator-agent-runnable.test.sh | jq | EXEC | -r --arg n release-app-mint (. // [])[] / select(.name == $n) / .slug |
| R4b | operator-script.test.sh | gh | EXEC | secret set STUBBED_SECRET -R owner/repo |
| R3 | operator-script.test.sh | jq | TEXT | - |
| R4b | operator-stage-approval-hook.test.sh | gh | TEXT | - |
| R3 | operator-stage-approval-hook.test.sh | jq | TEXT | - |
| R5b | reusable-release-zot-mirror-retry.test.sh | sha256sum | EXEC | -c - |
| R1,R3 | check-cloudflare-token-drift.test.sh | curl | EXEC | --disable --noproxy * -s -o /dev/null -D /var/tmp/tmp.3p3x1ikDUy -w %{ |
| R1,R3 | check-cloudflare-token-drift.test.sh | doppler | TEXT | - |
| joint(R1+R3) | check-deploy-script-parity.test.sh | python3 | EXEC | - /var/tmp/soleur-sbx.s7c-reach-b.P5wdGXsZ/apps/web-platform/infra/var |
| R1,R3 | check-web-host-escrow-config.test.sh | doppler | UNVERIFIED | - |
| joint(R1+R3) | infra-config-activation-7220.test.sh | python3 | EXEC | -I -c import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or s |
| R3 | web2-luks-live-6931.test.sh | ready | NOTCMD |  |
| R1,R3 | inngest-probe-heartbeat-feeder.test.sh | curl | EXEC | --disable --noproxy * -fsS --max-time 20 --config - https://uptime.bet |
| R3 | lint-dual-lockfile.test.sh | bunfig.local.toml | NOTCMD | - |
| R7 | ship-incident-pir-gate-mutation.test.sh | awk | EXEC | BEGIN{f=0; n=0} /^[[:space:]]*```/{f=!f; print ""; next} |
| R3 | test-content-publisher.sh | _liquid_redact_secrets | NOTCMD | - |
| R3 | test-jaccard-duplicates.sh | AGENTS.md | NOTCMD | - |
| R3 | test-jaccard-duplicates.sh | constitution.md | NOTCMD | - |
| joint(R1+R3) | verify-agent-security-slice1.test.sh | bash | TEXT | - |
| R1,R3 | web-host-reboot.test.sh | curl | EXEC | --disable --noproxy * -sS --max-time 15 --config - -X GET -o /tmp/tmp. |
| R1,R3 | web2-rebirth-recovery-check.test.sh | curl | EXEC | --disable --noproxy * --config - --aws-sigv4 aws:amz:auto:s3 -sS --max |
| R1,R3 | web2-rebirth.test.sh | curl | EXEC | --disable --noproxy * -sS --max-time 15 --config - -X GET -o /tmp/tmp. |
| R4b | test_incidents.sh | jq | TEXT | - |
| R1,R3 | test-argv-bearer-sweep.sh | curl | EXEC | --disable --noproxy * -sS -w \nHTTP_STATUS:%{http_code} --config - -H  |
| R1,R3 | test-argv-bearer-sweep.sh | doppler | UNVERIFIED | - |
| R3 | test-argv-bearer-sweep.sh | fatal | NOTCMD | - |
| R1,R3 | test-argv-bearer-sweep.sh | jq | EXEC | -r .data / length // 0 |
| R3 | test-argv-bearer-sweep.sh | python3 | EXEC | -I -c import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or s |
| joint(R1+R3) | test-argv-bearer-sweep.sh | set | NOTCMD | - |
| R1,R3 | test-destroy-guard-counter-web-platform.sh | doppler | TEXT | - |
| R1,R3 | test-git-data-birth-readiness-gate.sh | curl | UNVERIFIED | - |
| R3,R8 | test-git-data-birth-readiness-gate.sh | grep | UNVERIFIED | -oE templatefile\( |
| R1,R3 | test-git-data-boot-signal-poll.sh | doppler | TEXT | - |
| R1,R3 | test-git-data-rung2-evidence-capture.sh | curl | TEXT | - |
| R1 | test-sentry-alert-live-fidelity.sh | curl | EXEC | --disable --noproxy * --proto =https -g -fsS --max-time 15 --header @- |
| R1 | test-supabase-advisor-scan.sh | curl | EXEC | --disable --noproxy * --silent --show-error --max-time 30 --header @-  |
| R5b | test-workspaces-luks-cutover-gate.sh | cryptsetup | TEXT | - |
| joint(R1+R3) | test-zot-log-channel-probe.sh | awk | EXEC | -F\t -v host=soleur-registry -v envpfx=SOLEUR_ZOT_LOG shipper=zot-log- |
| R3 (alone; not in U2) | cron-egress-firewall.test.sh | timeout | TEXT | - |
| R3 (alone; not in U2) | cron-egress-self-heal.test.sh | timeout | TEXT | - |
| (listed pair, S7b) | cloud-init-inngest-bootstrap.test.sh | timeout | EXEC | - |

## 0.4 Drain state of every EXEC pair

Each stub definition was read by hand. Drain states: `all-arms-keyed` (every definition drains inside the arm that carries the consuming flag, before its first exit or return), `all-arms` or `all-arms-unconditional` (an unconditional drain before any exit), `some-arms` (a drain exists but an earlier exit or only one definition lacks it), `never`, `delegates` (execs the real binary, which reads stdin). The finder window is the opener line plus 4 code lines; a drain that is real but sits further down is an `exempt arm-drain` row (attested), one inside the window is a `drains` row. A deliberate-fault stub is one whose non-zero first-statement exit is the fixture's point: under pipefail the stub is the last stage, so its status is the rightmost non-zero one whatever the producer did (decision-challenges item 21).

| suite | verb | drain state | flag | action | reason |
| --- | --- | --- | --- | --- | --- |
| browser-snapshot-credential-guard.test.sh | jq | never: def 156 `exit 127` first statement (jq absent shim; the row asserts the degraded deny) | * | exempt | deliberate-fault |
| guardrails.test.sh | perl | never: def 1034 `exit 127` first statement (perl absent stub, the fixture is "without perl the fallback still gates") | * | exempt | deliberate-fault |
| test-mint-inngest-bootstrap-tag.sh | gh | all-arms-keyed: def 112 `body=$(cat)` at opener+29, after the arg parse; the earlier exits (FORBID 99, unmodelled flag 64, DELETE) are rows where no p | --input - | exempt | arm-drain |
| ci-deploy.test.sh | docker | listed row `drains / 2 / --password-stdin`: defs 388/9809 as measured at S7b | --password-stdin | exempt | arm-drain |
| ci-deploy.test.sh | logger | never: def 69 mock appends argv to MOCK_LOGGER_CAPTURE_FILE, exit 1 on a fail-match, else exit 0; no stdin read | * | edit-stub | - |
| ci-deploy.test.sh | tr | listed row `exempt deliberate-fault`: FCTR stub (8424) exits 3 as its first statement; the new producers (ci-deploy.sh:623 `tr -dc [:print:]/`, 1662 ` | - | exempt | deliberate-fault |
| cloud-init-inngest-bootstrap.test.sh | docker | never: def 2004 logs argv, pull arm exits rc, default exit 0, no login arm (read, hits tag 2004) | --password-stdin | fenced | blocked-#9956 |
| cloud-init-web-zot-seed.test.sh | docker | all-arms-keyed: def 361 `login)` arm `pw=$(cat)` at opener+8; def 903 has no login arm (pull/cp only) and no hit reached it | --password-stdin | exempt | arm-drain |
| git-data-cutover-access.test.sh | doppler | never: def 2450 `secrets set` arm logs to FZ_LOG and exits STUB_FLAGWRITE_RC without reading; defs 337/1476/2132 are get-only or exit 1/64 (no set arm | secrets set | edit-stub | - |
| git-data-flag-precheck.test.sh | doppler | some-arms: `secrets set` arm reads `read -r value` only after the arg loop, the missing-token exit 1 and the SHIM_SET_ERR auth/network exits 1/3 (undr | secrets set | edit-stub | - |
| git-data-liveness.test.sh | curl | all-arms-keyed: def 180 drains in the `--config` arm at opener+4 (inside the window), def 859 `cat >/dev/null` is the first statement | --config - | drains | - |
| git-data-rung2-rehearsal.test.sh | curl | all-arms: def 2481 `cat >> $STUB_DIR/stdin` is the 2nd statement (opener+3), unconditional | -K - | drains | - |
| inngest-dedicated-host-classify.test.sh | curl | never: def 510 reads fixture files and prints the code, no stdin read in any arm | --config - | edit-stub | - |
| workspaces-luks-provision.test.sh | awk | delegates: def 1190 exits 1 for a `canon=` awk (fault arm) else execs the real awk, which reads stdin | - | exempt | pass-through |
| workspaces-luks-provision.test.sh | cryptsetup | all-arms-keyed: def 129 drains `key=$(cat)` as the first statement of the luksFormat and luksOpen arms; other verbs never receive a pipe | --key-file - | exempt | arm-drain |
| workspaces-luks-provision.test.sh | curl | all-arms-keyed: def 326 drains `cfg=$(cat)` in the `--config -` test on opener+3, inside the window with the token on the same line | --config - | drains | - |
| zot-disk-heartbeat-redaction.test.sh | jq | never: def 560 `exit 127` first statement (jq absent stub, NOJQ farm) | * | exempt | deliberate-fault |
| in-image-copy-src.test.sh | tar | all-arms-keyed: def 187 `-xf)` arm `cat >/dev/null` at opener+5 inside the argv loop, before any exit; `-cf)` arm prints and exits (producer side) | -xf - | exempt | arm-drain |
| postgrest-reload-schema.test.sh | curl | all-arms-unconditional: def 41 drains `cat > $CURL_STDIN_FILE` at opener+13 before any exit (outside the finder window) | --header @- | exempt | arm-drain |
| run-migrations-schema-probe.test.sh | psql | all-arms-keyed: defs 89 and 230 `if [[ -z $sql ]]; then cat >/dev/null; exit 0; fi` after the arg parse, before any other exit | -f - | exempt | arm-drain |
| community-argv.test.sh | base64 | delegates: recorder shim execs the real base64 | - | exempt | pass-through |
| community-argv.test.sh | curl | all-arms-keyed: def 147 drains `cat > $d/stdin.$n` / `body.$n` inside the argv loop (`--config -`, `--data-binary @-`) before any exit (SHIM_MUTATE ro | --config - | exempt | arm-drain |
| community-argv.test.sh | od | delegates: recorder shim (1178 loop) logs argv then `exec`s the real od, which reads stdin | -An -v -tx1 | exempt | pass-through |
| community-argv.test.sh | openssl | delegates: recorder shim execs the real openssl | dgst -sha1 -binary | exempt | pass-through |
| community-argv.test.sh | tr | delegates: recorder shim execs the real tr | -d \n | exempt | pass-through |
| destructive-command-guard-hook.test.sh | jq | delegates: shims `-nc) exit 3` fault arm else `exec` real jq (reads stdin); the producer shape `-j .tool_input.command` reaches the exec arm | -j | exempt | pass-through |
| destructive-command-guard-hook.test.sh | perl | never: def 292 `exit 255` first statement (bad perl farm) | * | exempt | deliberate-fault |
| operator-9321-stages.test.sh | gh | all-arms-keyed: stub-world def (lib/operator-stub-world.sh:155) `secret set` arm `cat >/dev/null` at opener+8, first statement of the arm | secret set | exempt | arm-drain |
| operator-9321-stages.test.sh | jq | delegates (listed pair): stub-world shim logs then execs the real jq; new producer bootstrap.sh `jq -e select(...)` reaches it | - | exempt | pass-through |
| operator-agent-runnable.test.sh | jq | delegates: stub-world shim (lib/operator-stub-world.sh:276) logs then execs the real jq; the `for bin in ... jq ...` loop at 114 is a tool-availabilit | - | exempt | pass-through |
| operator-script.test.sh | gh | all-arms-keyed: def 147 `secret set` arm `cat >> $GH_STDIN_LOG` at opener+8; the stub-world def (lib/operator-stub-world.sh:155) drains `cat >/dev/nul | secret set | exempt | arm-drain |
| reusable-release-zot-mirror-retry.test.sh | sha256sum | never: loop-built `exit 0` stub (loop over sha256sum sudo tar sleep at 101) | -c - | edit-stub | - |
| check-cloudflare-token-drift.test.sh | curl | all-arms-keyed: def 237 drains `_stdin_cfg=$(cat)` in the `--config -` arm at opener+10, before any decision or exit | --config - | exempt | arm-drain |
| check-deploy-script-parity.test.sh | python3 | some-arms: def 234 `[[ $1 == -I ]] && exit 1` (fails ONLY the HMAC call), else execs the real python3 | -I -c | exempt | deliberate-fault |
| infra-config-activation-7220.test.sh | python3 | never: `printf '#!/usr/bin/env bash\nexit 1\n'` at 305 (failing python3, "uncomputable signature refused") | -I -c | exempt | deliberate-fault |
| inngest-probe-heartbeat-feeder.test.sh | curl | all-arms-unconditional: def 131 `stdin="$(cat)"` at opener+5 before any exit (one line outside the window) | --config - | exempt | arm-drain |
| ship-incident-pir-gate-mutation.test.sh | awk | never: def 394 `exit 2` first statement (broken strip stage, M10/N10 rows) | * | exempt | deliberate-fault |
| web-host-reboot.test.sh | curl | all-arms-keyed: def 44 `[[ have_cfg == 1 ]] && cat > stdin.last` at opener+11 after the arg loop, before any exit | --config - | exempt | arm-drain |
| web2-rebirth-recovery-check.test.sh | curl | all-arms-keyed: def 34 `[[ cfg -eq 0 ]] // { printf ... $(cat) }` at opener+9, before `exit 7` | --config - | exempt | arm-drain |
| web2-rebirth.test.sh | curl | all-arms-keyed: def 18 drains in the `--config -` case at opener+11 before the first exit | --config - | exempt | arm-drain |
| test-argv-bearer-sweep.sh | curl | some-arms: 6 shims; 1523/3279 drain `cat > $D/$n.stdin` on `--config -` after the arg parse; 126/2484/3713 exit 99 on an unmodelled flag before any re | --config - | exempt | arm-drain |
| test-argv-bearer-sweep.sh | jq | delegates (listed pair): shim records argv then execs the real jq on every path; new producers board-status-sync.yml and rule-audit.yml reach the same | - | exempt | pass-through |
| test-argv-bearer-sweep.sh | python3 | never: defs 2973/2974/2975/3235 exit 1 / print a non-digest / fail only `-I` (fault stubs for the HMAC rows) | -I -c | exempt | deliberate-fault |
| test-sentry-alert-live-fidelity.sh | curl | all-arms: defs 460 (`cat >> stdin.log` at opener+4) and 515 (`cat >/dev/null` at opener+4) drain unconditionally inside the finder window | --header @- | drains | - |
| test-supabase-advisor-scan.sh | curl | never: def 59 loops argv for --data/-d and prints fixture bodies, no stdin read in any arm (exit 0 / exit 99) | --header @- | edit-stub | - |
| test-zot-log-channel-probe.sh | awk | some-arms: def 681 `exit 1` first statement (deterministic non-zero), def 685 `echo not-a-summary` then exits 0 unread (race-capable: the producer pip | * | edit-stub | - |
| cloud-init-inngest-bootstrap.test.sh | timeout | passthrough: def 2025 `shift; exec "$@"` hands stdin to the docker stub (def 2004), which never drains | --password-stdin | fenced | blocked-#9956 |

## 0.5 Suites that need a stub edit

EXEC and not draining in every arm (`edit-stub` rows): **7 suites, 4 of them under `apps/web-platform/infra/`** and 3 outside it. Phase 2 and 3 order the commits non-infra first and infra second; there is no gate on the number.

| suite | verb | consuming flag | drain state | infra |
| --- | --- | --- | --- | --- |
| apps/web-platform/infra/ci-deploy.test.sh | logger | `*` | never: def 69 mock appends argv to MOCK_LOGGER_CAPTURE_FILE, exit 1 on a fail-match, else exit 0; no stdin read | yes |
| apps/web-platform/infra/git-data-cutover-access.test.sh | doppler | `secrets set` | never: def 2450 `secrets set` arm logs to FZ_LOG and exits STUB_FLAGWRITE_RC without reading; defs 337/1476/2132 are get-only or exit 1/64 (no set arm reached) | yes |
| apps/web-platform/infra/git-data-flag-precheck.test.sh | doppler | `secrets set` | some-arms: `secrets set` arm reads `read -r value` only after the arg loop, the missing-token exit 1 and the SHIM_SET_ERR auth/network exits 1/3 (undrained) | yes |
| apps/web-platform/infra/inngest-dedicated-host-classify.test.sh | curl | `--config -` | never: def 510 reads fixture files and prints the code, no stdin read in any arm | yes |
| plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh | sha256sum | `-c -` | never: loop-built `exit 0` stub (loop over sha256sum sudo tar sleep at 101) | no |
| tests/scripts/test-supabase-advisor-scan.sh | curl | `--header @-` | never: def 59 loops argv for --data/-d and prints fixture bodies, no stdin read in any arm (exit 0 / exit 99) | no |
| tests/scripts/test-zot-log-channel-probe.sh | awk | `*` | some-arms: def 681 `exit 1` first statement (deterministic non-zero), def 685 `echo not-a-summary` then exits 0 unread (race-capable: the producer pipeline in zot-log-cha | no |

Not counted, and listed so Phase 3 can choose: 8 further suites whose only non-draining EXEC stubs are `deliberate-fault` absence or fault stubs (browser-snapshot-credential-guard.test.sh, guardrails.test.sh, zot-disk-heartbeat-redaction.test.sh, destructive-command-guard-hook.test.sh, check-deploy-script-parity.test.sh, infra-config-activation-7220.test.sh, ship-incident-pir-gate-mutation.test.sh, test-argv-bearer-sweep.sh; 1 of them under infra). Editing those too would make the list 15 suites (5 infra).

Per-arm EXEC counts (an arm whose pairs are all non-EXEC still buys the recall property for future pipes and ships by default; this is the data the ship-time cut of R3 is argued from, decision-challenges items 1, 4 and 23):

| arm | new pairs (J0) | EXEC | TEXT | UNVERIFIED | NOTCMD |
| --- | --- | --- | --- | --- | --- |
| R1 | 29 | 14 | 10 | 5 | 0 |
| R2 | 1 | 1 | 0 | 0 | 0 |
| R3 | 47 | 18 | 17 | 5 | 7 |
| R4b | 10 | 2 | 4 | 0 | 4 |
| R5a | 2 | 2 | 0 | 0 | 0 |
| R5b | 6 | 3 | 3 | 0 | 0 |
| R7 | 7 | 5 | 1 | 1 | 0 |
| R8 | 0 | 0 | 0 | 0 | 0 |
| joint (R1 join + R3 bar scan; in no single arm's list) | 17 | 8 | 2 | 3 | 4 |
| R6 | 0 | 0 | 0 | 0 | 0 |

Fenced, not edited, NOT fixed: `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` pairs `docker` (R2 adds the producer `cloud-init-inngest.yml`, `printf | timeout 60 docker login ... --password-stdin`) and `timeout` (the pass-through stub in front of it). Both **EXEC**, drain state **never** (docker stub def 2004 logs argv, answers `pull`, exits 0; no login arm), consuming flag `--password-stdin`; the suite is green in a real clone with tags. The file is not edited whatever the class (the brief); the two rows need a reason that is true at merge (item 20).

## 0.6 Late findings on #10074, re-measured at the merged head

All runs use the merged tree: the finder and detector are taken verbatim (`awk '/^PJ_DEFS_AWK=/...'`, read-only) from the guard at `ffe17b85c3` into a scratch harness with `PJ_DRAIN_WINDOW=4`; the verdict mutants run on a scratch clone (`/var/tmp/s7c/clone-06`, `git status` clean before and after), one mutant at a time, each asserting that the edit landed (`git diff --quiet` is 1) and that the control exits 0, under `ulimit -v 6000000`, `timeout 240`, with the load beside each wall time. No mutant executes an owner suite.

| Finding | Command and fixtures | Result at the merged head | Verdict |
| --- | --- | --- | --- |
| Window crosses to another verb's stub | `pj_defs FIX curl '*'` over `crossverb` (`curl() { :; }` then `gh() { cat >/dev/null; }`), `crossbrace` (`curl() {` `:` `}` then a top-level `cat >/dev/null`), `crossheredoc` (`cat > "$d/curl" <<'EOF'`, `:`, `EOF`, then `cat >/dev/null`); control `curl() { cat >/dev/null; }` | `crossverb` ok, `crossbrace` ok, `crossheredoc` ok (want `no` for all three); the control reads ok. With `exit 0` as the heredoc body `crossheredoc` reads `no` only because the exit sets the dead flag, not because the window stops | OPEN (all three) |
| Six unneutered verdicts | the table below | each fault with its verdict intact exits 1 and names its FAIL; each fault with its verdict neutered exits 0 | OPEN (all six) |
| Fail-open drain spellings | `pj_detects STRING` (rc 0 = read as a drain) over `[[ -t 0 ]] && cat >/dev/null`, `test -t 0 && cat >/dev/null`, `if [ -t 0 ]; then cat >/dev/null; fi`, `cat >/dev/null </dev/null` | rc 1 (rejected), rc 0, rc 0, rc 0 | `[[ -t 0 ]]` FIXED; the other three OPEN |
| Fail-closed false rejects | `pj_detects` over `x=$(cat 2>/dev/null)`, `cat -`, `[ -t 0 ] && true \|\| cat`, `cat >/dev/null; sleep 0 &`, `body=$(cat) && grep x <<<"$body"`; `pj_defs` over a stub `echo "a #b"; cat >/dev/null` | all rc 1 (rejected) and the `#`-in-a-string stub reads `no`; `body=$(cat); grep x <<<"$body"` (a `;`, not `&&`) is accepted | OPEN (all reproduce; the here-string case needs `&&` or `\|\|` before the here-string) |
| Annotation: pipe before / after the string | `PJ_AWK` extracted from the guard, run over `a.test.sh` (stubs `curl`, `jq`, `tr`, names `prod.sh`) and `prod.sh` (`set -o pipefail`; `printf "%s" "$B" \| curl -s "$U" \|\| echo "::error::fail"`; `echo "::error::fail $X"; printf "%s" "$B" \| jq .`; `echo "::error::fail $(cat f \| head -1)"; printf "%s" "$B" \| tr a b`) | derives `a.test.sh curl prod.sh` only: the pipe BEFORE the annotation is read, the pipe after the closing quote (jq) and the one after a command-substitution annotation (tr) are dropped with the line tail. J0's R8 arm (merged-tree re-run): 0 new pairs, 1 new triple | pipe before FIXED; pipe after OPEN (arm R8) |
| `pj_sourced` has no fixture | `grep -n pj_sourced .claude/hooks/grep-q-pipe-guard.test.sh` | the definition (line 1340) and one use (1437, the row loop); no fixture drives it | OPEN |
| `1\|141` reachability | `head -c 1048576 /dev/zero \| ./stub.sh` (stub `exit 0`) under `set -o pipefail`, bash and dash, SIGPIPE default and `trap "" PIPE` | default: rc 141 in both shells; ignored: rc 1 in both | measured reachable; no row (item 17) |
| mawk unmeasured | `command -v mawk busybox original-awk nawk` | none present; only `/usr/bin/gawk` (`awk` is gawk 5.4.1) | CI is the only mawk reading; stated, not claimed |

Verdict-mutant table (guard `ffe17b85c3` on the scratch clone; F = a fault with its verdict intact, N = the verdict neutered):

| case | what the edit does | guard exit | wall s | load | first FAIL line |
| --- | --- | --- | --- | --- | --- |
| C0 | unmutated control | 0 | 29 | 38.78 | - |
| F1 | fault: drains row count 1 -> 2 (count mismatch), verdict intact | 1 | 30 | 38.28 | FAIL: apps/web-platform/infra/git-data-root-key.test.sh stubs 'curl' in 1 definitions, the row pins 2 - a defi |
| F1+N1 | F1 + the count `pj_fail` replaced by `:` | 0 | 26 | 37.74 | - |
| F2 | fault: row token `*` -> `-zzz-` (no drain keyed on it), verdict intact | 1 | 23 | 36.52 | FAIL: apps/web-platform/infra/git-data-root-key.test.sh:944 defines the 'curl' stub with no stdin drain keyed  |
| F2+N2 | F2 + the `no`-line `pj_fail` replaced by `:` | 0 | 24 | 34.58 | - |
| F2+N6 | F2 + the `no`-line loop test `[[ "$_l" == no\ * ]] || continue` replaced by `continue` (the loop made a no-op) | 0 | 23 | 33.49 | - |
| F3 | fault: row count `1` -> `x` (malformed row), verdict intact | 1 | 22 | 33.08 | FAIL: malformed drains row for apps/web-platform/infra/git-data-root-key.test.sh curl: want '<suite> / <v> / d |
| F3+N3 | F3 + the malformed-row `pj_fail` replaced by `:` | 0 | 24 | 30.10 | - |
| F4 | fault: `PJ_TRIPLES=120` -> `121`, verdict intact | 1 | 29 | 29.87 | FAIL: the derivation found 120 (test file, verb, producer file) triples and PJ_TRIPLES pins 121 - a producer o |
| F4+N4 | F4 + the triple-pin `pj_fail` replaced by `:` | 0 | 30 | 33.42 | - |
| F5 | fault: the `git-data-root-key.test.sh | curl` row deleted (unlisted pair), verdict intact | 1 | 30 | 37.69 | FAIL: unlisted pair: apps/web-platform/infra/git-data-root-key.test.sh stubs 'curl' and names a non-test file  |
| F5+N5 | F5 + the `pj_j="$(... | pj_judge ...)"` assignment blanked to `pj_j=""` | 0 | 26 | 38.99 | - |

Reading: a verdict that a fault turns red but a neutering leaves green is unprotected; all six (N1, N2, N6, N3, N4, N5) are. The plan's M4, M26, M41 and M43 rows are the ones that must read RED after Guard 3 lands.

## Observations that change the work

- The `- |` YAML list scalar defect (item 19): four of U2's 90 pairs are an artefact of R1 plus R3; fix the exclusion in the port and the awk before writing arms, and U2 becomes 86 pairs, 136 triples, 65 files.
- The #9956 premise is false on this host too: the bootstrap suite is green at base in a real clone (item 20).
- 8 of the 50 sandbox runs of tranche 1 (and 2 of the real-clone re-runs) hit the 300 s cap at load 25 to 45: a probe of this size wants a quiet host; ten pairs stay UNVERIFIED for that reason (item 22).
- The hit marker fires for any pipe, so raw hit counts overstate reach: `workspaces-boot-unlock.test.sh` logged 420 doppler hits and none was `secrets set`; `workspaces-luks-host-token-refresh.test.sh` logged 51 doppler, grep and sed hits and none had the producer's shape. Only argv-matched hits count.
- Two EXEC findings are not printf/echo/cat producers: `ci-deploy.test.sh logger` (`... 2>&1 | logger -t TAG -p user.warning`, a script's output) and `inngest-dedicated-host-classify.test.sh curl` (a workflow producer); they exist only because R3 and R1 look at a bar, which is the recall the slice is for.
- A `printf ''` producer (empty write) cannot raise EPIPE; the HMAC `python3 -I -c` sites in `cutover-inngest.sh` and the workflows mostly use it, which is why those python3 stubs are `deliberate-fault` and need no drain even apart from the fault.
- Phase 3 candidates in the edit list are mostly shims with an early `exit 0` or an early failure arm; `git-data-flag-precheck.test.sh` reads with `read -r value` after its early exits, and the finder accepts only `cat` or `dd` as a drain, so its fix is a `cat` drain at the top of the `secrets set` arm, not a hoisted `read`.

## Phase 1 red-first run (2026-10-12, before any derivation change)

Tree: the S7c branch at the Phase 1 commit, the guard with the new fixtures, controls and the `wire_pjj` pin and with NO arm and NO verdict function yet. Command: `ulimit -v 6000000; bash .claude/hooks/grep-q-pipe-guard.test.sh` from the worktree (empty `git status --porcelain` apart from the edit under test); exit 1, 15.8 s wall at load 12. The join block printed no `unlisted pair`, `stale join row` or `triples` FAIL (the new fixture text derives no pair of its own for this file), so the red lines below are the probe's, and only the probe's.

| new check | first result | what it read |
| --- | --- | --- |
| `derivation-fixtures` (one table, 41 cases, 26 must-derive and 18 must-not expectations) | RED, 19 must-derive failures, 0 must-not failures | red: `stub-semicolon`, `stub-unquoted-semicolon` (R7); `pipe-split`, `pipe-split-tab`, `backslash-split` (R1); `wrapper-timeout`, `wrapper-timeout-k`, `wrapper-env`, `wrapper-assign`, `wrapper-nice`, `wrapper-stdbuf`, `wrapper-command-p` (R2); `annot-pipe-after`, `annot-cmdsub` (R8); `library-sourced` (R4); `helper-arg2` (R5a); `loop-built` curl and jq (R5b); `tf-producer` (R6). Green at once, as intended: the 18 must-not cases (`quoted-trailing-bar`, `yaml-block-scalar`, `continuation-or-true`, `command-v`, `wrapper-bare`, `annot-pipe-inside`, `annot-escaped-quote`, `library-unsourced-no-pipefail`, `library-sourcer-no-pipefail`, `loop-nonverb` x2, `tf-no-pipefail`, `stub-other-verb`, and the five base ones) and 7 must-derive controls (`base-printf`, `second-site` x2, `crlf`, `helper-arg1`, `annot-pipe-before`, and `stub-space-semicolon`, which already derives at the merged head: the base strip `"?[ \t]?$` removes the quote and the space of `> "$d/jq" ;`, so only the two spellings with the semicolon directly after the name are the R7 defect) |
| `producer-join-window` (crossverb, crossbrace, crossheredoc, logwrite, oneline) | RED | the three must-end fixtures read `ok` (want `no`): the window crosses another verb's opener, a closing brace and a heredoc terminator; the two must-pass fixtures read `ok` as wanted |
| new spellings in `PJ_DRAIN_OK` / `PJ_DRAIN_BAD` (`producer-drain-nonreading`) | RED (detector side only) | accepted `x=$(cat 2>/dev/null)` and `cat -` not detected; non-reading `test -t 0 && cat >/dev/null`, `if [ -t 0 ]; then cat >/dev/null; fi` and `cat >/dev/null </dev/null` detected as drains. The dynamic control agrees with the intended reading on all five (the hazard runs: the three non-reading spellings fail the pipeline, the two accepted ones succeed), which is why `producer-hazard-control`, `producer-drain-accepted` and the dynamic half of `producer-drain-nonreading` stay green |
| `producer-join-verdicts` (row checks and the triple pin) | RED | `pj_check_rows` and `pj_check_triples` do not exist yet, so every fixture reads `command not found` and no verdict prints: all nine fixtures red. The neutered-verdict readings (the six one-fault-one-neuter mutants of 0.6) are re-run once the functions exist |
| `wire_pjj` (the column-0 `pj_j` assignment, counted into `producer-join-wiring`) | GREEN | the assignment exists at column 0 today, so the pin reads 1; its negative reading is the blanked assignment (F5+N5 of 0.6), run after the verdict functions land |
| `SWEEP_PROBE_CHECKS` | 47 to 50 | the three new checks; the number is the header recipe's count, not a hand edit |

## Phase 2 per-arm parity (the awk derivation against the J0 port, 2026-10-12)

Method. Before each arm's rows exist, the guard's own derivation (`PJ_AWK` through `pj_derive`, extracted by the markers `PJ-DERIVE-BEGIN`/`END` into a scratch driver) is run on the tree, its sorted unique `test file, verb, producer file` triples are compared with `j0-derive.py`'s triples for the same arm set (a scratch driver imports `derive()` from the port), and the two lists are `diff`ed. Pairs are the first two columns. The guard itself is then run once with the arm in and its rows absent: its `unlisted pair` count equals the pair delta, and its triple count the triple delta (the red lines the arm is expected to leave until Phase 4). Arm toggles were also run one off at a time on a scratch copy of the guard against the matching port arm set, so each arm is attributable in the awk and not only in the sum. Port changes made to carry the plan's rules (all in `j0-derive.py`): the block-scalar exclusion for the list item `- |` (item 19), the R2 wrapper table now the plan's seven (`timeout env command nice stdbuf exec builtin`) with per-wrapper flag arity and `command -v` excluded, the word before a wrapper kept as a site, and a `VAR=x` assignment before the verb read.

### R7, the stub name (commit `8f2702024d`)

awk against port `{R7}`: empty diff on 128 triples. Delta over base: +7 pairs, +8 triples (jq 4, awk 2, perl 1), exactly the J0 reading. Guard with the arm in and no rows: 7 `unlisted pair`, triples 128 against the pin 120; `stub-semicolon` and `stub-unquoted-semicolon` read green.

### R1 + R2 + R8 (one commit)

awk against port `{R7, R1, R2, R8}`: empty diff on 206 triples. One-arm-off checks: R8 off against port `{R7,R1,R2}`, R1 off against `{R7,R2,R8}`, R2 off against `{R7,R1,R8}`: each an empty diff (205, 155 and 172 triples). Deltas over base, each arm alone in the port: R1 +29 pairs, +42 triples (27 test files; J0: 29 and 42); R8 +0 pairs, +1 triple (J0: 0 and 1); **R2 +7 pairs, +22 triples (J0: +1 and +3)**; the sum R7+R1+R2+R8 over base is +47 pairs, +86 triples with 0 lost.

The R2 difference is explained and kept (decision-challenges item 26): J0's port read a `VAR=x` assignment before the verb only through its any-producer scan, so the plan's own R2 text ("or `VAR=x`") was under-measured. The six pairs it adds are `ci-deploy.test.sh` doppler and python3, `cutover-inngest-workflow.test.sh` doppler, `verify-agent-security-slice1.test.sh` bash, `test-argv-bearer-sweep.sh` doppler and python3 (producers: `printf '' | HMAC_KEY=... python3 -I -c ...` in the cutover scripts, a doppler call behind an assignment); the J0 `docker` pair is the other one. The python3 pairs are the empty-write producers of the 0.5 observation (an empty `printf ''` cannot raise EPIPE) and their stubs are the `deliberate-fault` ones. The guard with the three arms in and no rows: 47 `unlisted pair` (the pair delta over base), triples 206 against the pin 120 (+86); `pipe-split`, `pipe-split-tab`, `backslash-split`, the eight wrapper cases, `annot-pipe-after` and `annot-cmdsub` read green, the 18 must-not cases stay green.

### R4, the library rule (pipefail from a file that sources the library)

awk against port `{R7, R1, R2, R8, R4b}`: empty diff on 219 triples; R4 off (a scratch copy with the sourcer test removed) equals the previous configuration (206 triples, empty diff). Delta of the arm alone in the port: +10 pairs, +12 triples, 10 test files (J0: 10 and 12); over the three arms in the awk +10 pairs, +13 triples (one more producer for a pair the earlier arms already derive). Guard with the arm in and no rows: 57 `unlisted pair` (47 + 10), triples 219 against 120; `library-sourced` reads green and `library-unsourced-no-pipefail` and `library-sourcer-no-pipefail` stay green (the owning test file's `pipefail` is not read: a subprocess does not inherit the option).

### R5a, R5b and R6 (helper arguments, loop-built stubs, the extension list)

awk against port `{R7, R1, R2, R8, R4b, R5a, R5b, R6}`: empty diff on 231 triples; each arm off in turn (a scratch copy with that arm disabled) against the port without it: empty diffs (229, 221 and 231 triples). Deltas of each arm alone in the port, equal to J0's: R5a +2 pairs, +2 triples (1 test file); R5b +6 pairs, +10 triples (4 test files); R6 +0 pairs, +0 triples (the `.tf` family has no suite with a stub and a text pipe today). Over the previous configuration (R7, R1, R2, R8, R4) the three arms add +8 pairs, +12 triples; the sum of all arms so far over base is +65 pairs, +111 triples, 55 test files, 0 lost. Guard with the arms in and no rows: 65 `unlisted pair`, triples 231 against 120; `helper-arg2`, `loop-built` (curl and jq) and `tf-producer` read green, so `derivation-fixtures` is green as a whole; `loop-nonverb`, `tf-no-pipefail` and `helper-arg1` stay green.

Two port changes made so the port carries the plan's rules and not a wider one (the awk is authoritative where they differ): (a) R5a and R5b read the stub helpers by the fixed name list (`make_stub write_stub stub_cmd mkstub stub`) at the start of a statement, with every bare lowercase argument as a verb; the port's first draft read any function of the test file whose body writes a path ending in a positional parameter, which also finds a user-named helper called in a loop (`wstub` in `workspaces-boot-unlock.test.sh` gives one more pair, `docker`, that only R2 and R5b together reach: not derived, listed under NOT fixed as a stub built through a helper the finder cannot read); (b) R6 is the extension list `.tf .tftpl .template .service .tmpl` only (the first draft also read `.tpl` and extensionless shebang files, 0 pairs, both cut). The first awk draft read the helper word anywhere on a line and read the prose of assertion messages (`stub WRITES the raw tree ...`) as helper calls (five false pairs); anchoring at the start of a statement removed them, which is why the arm has its own anchored regex and the base first-argument rule keeps its unanchored form.

### Guard 2, the extent of a stub and the drain spellings

Changes: the finder `PJ_DEFS_AWK` bounds a stub's extent at the earliest of the window, the next opener of ANY verb that is a function, a stub-helper call or a heredoc writer (a one-line `printf ... >> "$d/args"` logging write is not a bound), the heredoc terminator named on the opener line, the closing brace at the opener's indent (or the opener line itself for a one-line stub, decided by the brace balance of the text after the first `{`), and the next opener of the verb itself; its helper-call opener now finds the verb in any argument (the same reading as R5a). The detector gains `cat 2>FILE` and `cat -` as drains (`x=$(cat 2>/dev/null)`, `cat -`); the non-drain pattern gains `test -t 0 && ...`, `[ -t 0 ]; then` (and the `test` form) and an input redirect after `cat`. The 14 `drains` rows are unchanged and still verified (no finder FAIL), so no existing stub read differently.

Second readings (first readings are in the Phase 1 section): `producer-join-window` GREEN (crossverb, crossbrace, crossheredoc read `no`; logwrite and oneline read `ok`); `producer-drain-nonreading` GREEN on the detector side as well (the two accepted spellings are detected, the three non-reading ones are not), and the dynamic control still agrees on all five under both dispositions and both interpreters. The guard prints no finder or detector FAIL; its remaining red is the 65 `unlisted pair` lines, the triple pin (231 against 120) and `producer-join-verdicts` (the verdict functions land in the next commit).

### Guard 3, the verdict controls and the merge pins (commit `b0b8921316`)

Changes: the three row checks (malformed row, definition count, no drain) are `pj_check_rows <pairs>` (rows on stdin; prints its FAIL lines and returns 3 with `UNRESOLVED` for a row that finds no definition) and the triple pin is `pj_check_triples <found> <pin>`; `pj_fail` is gone. Each of the three verdict sinks (`pj_j` from the judge, `pj_rc` from the row checks, `pj_tc` from the triple pin) is one column-0 assignment and one column-0 merge `[[ -z "$x" ]] || { PJ_FAIL=1; printf ... }`, and all six statements plus the column-0 fold are counted into `producer-join-wiring`. The check `producer-join-verdicts` feeds the two functions nine fixtures that must each make a verdict print and one clean one that must print nothing (a compliant stub, a count that is off by one, a stub with no drain, a malformed row, two faulty rows in one run with both verdicts required, a row whose suite has no stub, a triple count that is off by one and one that is equal).

First reading (Phase 1): RED, the functions did not exist. Final reading: GREEN (the guard prints no `producer-join-*` line). Neutered-verdict readings on a scratch shared clone of the committed tree, one mutant at a time, each asserting the edit landed and that the unmutated control prints no probe line (control: exit 1 only for the 65 `unlisted pair` lines the arms leave until Phase 4, no `producer-*` line), under `ulimit -v 6000000`, `timeout 240`, host load 20 to 49 (wall 21 to 48 s). A row counts as RED only when the guard exits non-zero and prints the named substring:

| row | mutation | guard | named substring |
| --- | --- | --- | --- |
| M37 | the definition-count verdict `echo` replaced by `:` | exit 1 | `producer-join-verdicts: ... no 'stubs 'curl' in 1 definitions, the row pins 2'` |
| M38 | the no-drain verdict `echo` replaced by `:` | exit 1 | `producer-join-verdicts: ... no 'defines the 'curl' stub with no stdin drain'` |
| M39 | the malformed-row verdict `echo` replaced by `:` | exit 1 | `producer-join-verdicts: ... no 'malformed drains row'` |
| M40 | the triple-pin verdict `echo` replaced by `:` | exit 1 | `producer-join-verdicts: ... no 'triples and PJ_TRIPLES pins 6'` |
| M41 | the `pj_j` merge assignment blanked to `pj_j=""` | exit 1 | `producer-join-wiring: the pj_judge merge 1 and its assignment 0` |
| M42 | the `no`-line loop test replaced by `continue` | exit 1 | `producer-join-verdicts: ... no 'defines the 'curl' stub with no stdin drain'` |
| M43 | the row loop stops after its first row (second member) | exit 1 | `producer-join-verdicts: ... no 'with no stdin drain'` (the second row's verdict) |
| M44 | the row-check driver is handed zero rows | exit 1 | `producer-join-verdicts: ... no 'stubs 'curl' in 1 definitions, the row pins 2'` |
| M45 | `pj_unread` widened to accept rc 3 (S7b row) | exit 1 | `producer-hazard-control: ... [pj_unread grades a status it must not]` |
| M45b | the row-check merge neutered to `:` | exit 1 | `producer-join-wiring: ... the row-check merge 0` |
| M45c | the triple-pin assignment blanked | exit 1 | `producer-join-wiring: ... the triple-pin merge 1 and its assignment 0` |

All eleven read RED; the S7b reading of the six unneutered verdicts (all exit 0 in 0.6) is now closed.

### R3, the any-producer scan (last arm)

awk against port `{R7, R1, R2, R3, R8, R4b, R5a, R5b, R6}` (the final configuration): empty diff on 261 triples, no allowed delta. Delta of the arm alone in the port: +47 pairs, +70 triples, 42 test files (J0: 47, 70, 42); over the previous configuration (everything but R3) in the awk +21 pairs, +30 triples, 18 test files (the other 26 of R3's alone-pairs are already reached by R1, R2 or R5, and seventeen need R1 and R3 together: decision-challenges item 23). **Final configuration over base: +86 pairs, +141 triples, 66 test files, 0 lost.** J0's figure after the item-19 fix was 86 pairs, 136 triples, 65 test files: the pair counts are equal but the sets differ by two pairs, both explained: (+) `scripts/followthroughs/inngest-soak-6178.test.sh python3` is the `VAR=x python3` form that the port's first draft did not read (R2, item 26); (-) `apps/web-platform/infra/workspaces-boot-unlock.test.sh docker` needs a user-named helper (`wstub`) called in a loop, which the fixed helper list does not read (item 27, NOT fixed). The extra five triples are the `VAR=x` producers of already-derived pairs. Guard with every arm in and no rows: 86 `unlisted pair`, triples 261 against 120 (+141), and no other FAIL line: `derivation-fixtures` (51 cases, 31 must-derive and 24 must-not expectations), `producer-join-window`, `producer-join-verdicts`, the spelling rows and the wiring pins all green.

R3 fixtures first reading: the ten R3 cases were added with the arm (the table of Phase 1 had none for it: the arm was written last by design); each of the five that carry a named mutation row reads RED when the arm is narrowed (scratch shared clone, one mutant at a time, `ulimit -v 6000000`, control prints no probe line): M8 (any-bar scan dropped) reds `other-producer`, `other-producer-second-bar`, `other-producer-and-amp`, `other-producer-wrapped`; M9 (quote parity dropped) reds `quoted-bar` and `quoted-bar-single`; M10 (parity dropped from the join) reds `quoted-trailing-bar`; M11 (join over a block-scalar indicator) reds `yaml-block-scalar` and `yaml-list-block-scalar`; M12 (case-alternation exclusion dropped) reds `case-alternation`. Each reading carries `landed=True`, exit 1 and the case name in the `derivation-fixtures` line.

### Cost of the arms, and what took it back

The derivation CPU (`user` seconds of the extracted awk run, interleaved five times per version on the loaded host, minimum shown) rose with the arms: S7b base 5.7; after R7 5.6; after R1+R2+R8 7.2; after R4 7.3; after R5+R6 9.6; after R3 10.1. Four changes took it back without changing a derived triple (the awk output is byte-identical to the port's before and after): the site scan is entered only for a line that holds a bar, a backslash or the pipefail token (or continues a joined line), the first character of the code is read once and decides which statement-start rule can apply, the extension and `for` tests are single anchored or dotted tests, and the trailing-character test of a join is one `substr`. Result 8.0 for the derivation. Whole guard, same host, interleaved, `ulimit -v 6000000`: the S7b guard 23.7 s user (29.1 and 30.3 s real), the S7c guard at the R3 commit 31.0 and 31.3 s user (42 s real), the S7c guard after the cost commit 23.6 and 23.7 s user (29.6 and 33.9 s real), all at load 40 to 46. The cost commit also builds the unique-basename `.sh` list once (`PJ_UNIQ_SH`): `pj_sourced` read the whole 18,666-line listing on every call and the row checks plus the new controls call it about twenty times; its output is identical to the old function's on all 790 test suites (compared one by one) and the fixture runner forks less. A quiet-host figure (item 10's 12 s) could not be taken: the load average was 12 to 49 for the whole session, so the wall figures above are context only and the CPU comparison with the S7b guard is the reading.

## Phases 3 to 5: stub edits, rows and header (2026-10-12)

### Phase 3 re-verification and the edit list

The seven suites of 0.5 were re-read against their producer lines before any edit (a hit of the reach marker fires for a process substitution too). **Six are edited and one is reclassified.** `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh curl` is NOT edited: the suite executes only the `probe` and `nolive` steps of the health workflow, and its curl stub is reached through the bearer-curl library, which feeds `--config -` by a process substitution (a comment in the library says "never a pipe"). The piped site (`printf Authorization | curl --header @-`) lives in the pool probe step, which the suite never runs. The 13 hits of the reach probe were the process substitution; the pair is `exempt text-only` and the reach table's EXEC for it was wrong. Per the plan's own rule (naming is not running) nothing was edited.

Edits (three kinds only: a drain as the stub's first act keyed on what real reads, a wire assert, no new knob beyond the `${KNOB:-default}` of the assert itself):

| suite | verb | edit | wire assert | pair run base to head |
| --- | --- | --- | --- | --- |
| plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh | sha256sum | the verb leaves the four-name `for` loop and gets its own heredoc stub; `case " $* " in *" -c - "*) [ -t 0 ] \|\| timeout 2 cat > "${0%/*}/sha256sum.stdin"` | after T3, the captured bytes equal `${MOCK_SHA256_LINE:-<CRANE_SHA256 read from the extracted block>  /tmp/crane.tgz}` | rc 0 both; 24/24 to 25/25 (the added assertion) |
| tests/scripts/test-supabase-advisor-scan.sh | curl | `case " $* " in *" --header @- "*) [ -t 0 ] \|\| timeout 2 cat > "${0%/*}/header.stdin"` ahead of the argv loop | after the clean scan, the capture equals `${STUB_HEADER_LINE:-Authorization: Bearer <synthetic PAT>}` | rc 0 both; 24 to 25 ok |
| tests/scripts/test-zot-log-channel-probe.sh | awk | both printf-written fake awks read first (`[ -t 0 ] \|\| timeout 2 cat`); the first keeps `$0.stdin` | the capture holds `${S6_AWK_STDIN_LINES:-<log rows + control rows>}` lines | rc 0 both; 115 to 116 passed |
| apps/web-platform/infra/ci-deploy.test.sh | logger | the mock reads first when no message operand follows the options (`-t TAG` or `-t TAG -p PRIO`, the two piped forms of the script), optional `MOCK_LOGGER_STDIN_FILE` | new `assert_layer3_logger_stdin`: the Layer 3 failure line reaches the mock, `${MOCK_LAYER3_LINE:-canary-bundle-claim-check: simulated bad JWT}` | rc 0 both; 609/609 to 610/610 (477 s and 432 s at load 22 to 24) |
| apps/web-platform/infra/git-data-flag-precheck.test.sh | doppler | the `secrets set` arm takes `value="$(timeout 2 cat)"` as its first act (the `read -r value` after the early exits is gone) | the existing W1 write read-back (the stored value is `true`) | rc 0 both; 101 passed 0 failed both |
| apps/web-platform/infra/git-data-cutover-access.test.sh | doppler | the finalizer stub's `secrets set` arm drains to `$FZ_LOG.stdin` before it logs or exits | FZ1 compares the capture with `${FZ_FLAG_OFF_VALUE:-false}` | rc 0 both; 615 passed 0 failed both (231 s and 229 s) |

Every stub runs under a PATH that carries `timeout` (`/usr/bin`), so none needed the plain `cat` of the env -i PATH farm. `git diff` of each edited suite shows only these lines; no reach marker is in any of them. `shellcheck -S warning` finding counts are unchanged from base on all six suites and on the guard (0, 0, 1, 19, 0, 0 and 0, base equal to head). Pair runs: base is a real checkout of `8873e3a0b5`, head is this worktree, same host, one suite at a time, `ulimit -v 6000000`, `timeout` 600 or 1800; the pass counts differ only by the one added assertion, no suite changed result.

Wire assert, mutation-proved (delete the drain, expect the named assertion red; a same-directory copy of the suite, one mutation, the unmutated suite green first, `landed` asserted by a count of one):

| suite | mutation | result |
| --- | --- | --- |
| reusable-release-zot-mirror-retry | the sha256sum drain replaced by `:` | rc 1, `T3 sha256sum stub received the checksum line ... got '', want 'c14340...  /tmp/crane.tgz'`, 24/25 |
| test-supabase-advisor-scan | the curl drain replaced by `:` | rc 1, `FAIL curl stub stdin` |
| test-zot-log-channel-probe | the first awk's drain removed | rc 1, `FAIL: S6 the fake awk received the rows the grading pass pipes into it` |
| git-data-flag-precheck | the `value=` drain line deleted | rc 1, W1, W7 and W8 red |
| git-data-cutover-access | the finalizer drain deleted | rc 1, `FZ1 the flag-off value did not reach the doppler stub on stdin` |
| ci-deploy | the logger drain line deleted | rc 1 on a copy of the suite cut at the end of the Layer 3 case (the whole suite takes about 8 minutes): `FAIL: layered canary: the logger mock received the Layer 3 failure output on stdin`; the first mutant read rc 1 with no message because the failed `cat` of the missing capture aborted under `set -e`, so the assert reads the capture with `|| true` |

### Phase 4 rows

`PRODUCER_JOIN` now has 153 rows (152 derived pairs plus the variable-named `ssh` row): **21 `drains`** (the 14 of S7b, plus sha256sum, the supabase curl, the probe awk with 2 definitions, the flag-precheck doppler shim, and three pairs whose stubs already drained inside the finder window: `git-data-rung2-rehearsal` curl, `workspaces-luks-provision` curl, `test-sentry-alert-live-fidelity` curl with 2 definitions) and **132 `exempt`**: arm-drain 23, text-only 54, not-a-command 16, pass-through 14, unverified 11, deliberate-fault 10, blocked-#9217 2, helper-built-stub 1, variable-named-verb 1. No new vocabulary word.

Rows the finder would not accept as `drains` and why (each is `exempt arm-drain` with the reason in the row): `ci-deploy logger` (five definitions; four are in-process function shadows of small extracted functions that no pipe feeds, the mock of `create_mock_logger` drains), `git-data-liveness curl` (def 859 is a one-line printf stub `cat >/dev/null` that the finder cannot credit, because the detector reads the newline escape before `cat` as part of a word), `git-data-cutover-access doppler` (four definitions, only the finalizer stub receives a piped set). `inngest-soak-6178.test.sh python3` (the one pair of the final configuration that J0 did not list) is `deliberate-fault`: the stubs exit 1 or print a non-digest and the producer is `printf ''`, which cannot raise EPIPE.

The two `blocked-#9956` rows of `cloud-init-inngest-bootstrap.test.sh` (docker, timeout) now read `blocked-#9217`: the suite is green at base (240/240, section 0.3), both pairs are reached by a piped `docker login --password-stdin` and never drain, the file is fenced for this slice, and the fix stays on the series tracker (decision-challenges item 33). #9956 is not cited as red at base anywhere.

A row's reason must not name a file the derivation reads as a producer: the first draft named `workspaces-cutover.sh` in a row, which made the guard an owner of that file and derived a pair of its own (`with`, a prose word piped from that file); the rows now carry counts and extension-free words, and the guard derives 152 pairs and 261 triples, the same as before the rows existed. The `unlisted pair` message names the non-test file(s) that derive the pair (`pj_raw`, one awk for all unlisted pairs), driven by a fixture of the existing `producer-join-judge` check. `PJ_TRIPLES` 120 to 261, read from the green run; `SWEEP_PROBE_CHECKS` stays 50 (header recipe re-run: 50). Guard: rc 0, 16.7 s wall (22.4 s user) at load about 20; `JOINED:` lines 153, `DEFERRED:` lines 12; the unlisted-pair message read once for a deleted row: `... (scripts/followthroughs/zot-log-channel-7440.sh, scripts/lint-followthrough-varq-ban.sh) — add a PRODUCER_JOIN row ...`.

### Phase 5 header

The comment block above `PJ_DRAIN_WINDOW`, the guard's opening paragraph about the producer side and the comment above `PJ_AWK` were rewritten to the S7c state: what each arm sees, the STATED LIMITS (extensionless producers, a bar inside `"$( )"`, a verb behind a group beyond its first word, a stub two or more hops away, a variable-named verb, user-named loop helpers, the tab-as-one-character brace bound, a helper defined inside a heredoc stub, the rare drain spellings that fail closed) and a STILL OPEN paragraph (Items D, E, F, G, I and H, the wave A3 carriers, the #9639 and #9638 triage; listed, not planned; no claim that the series is finished). Comments only: the guard's code and its pins are unchanged by that commit.

## Phase 6 evidence: the guard on the merged tree, the mutation and harness rows, the lints (2026-10-12)

Host: 16 cores shared with other sessions; load average is stated beside every figure. Scratch clones under `/var/tmp/s7c/p6/` (`branch`, `merged`, `mut`, `h7`), never this worktree; every guard run is `ulimit -v 6000000` (shell only; no gate, bun or vitest run carries it).

### AC-3, AC-4, AC-10: the guard from a clean checkout

| tree | exit | `DEFERRED:` | `JOINED:` (rows) | `PASS: grep-q-producer-join` | wall, load before |
| --- | --- | --- | --- | --- | --- |
| the branch at `28e0b0ed53` (before main moved) | 0 | 12 | 153 (153 rows) | 152 derived pairs, 262 producer triples; 21 drains rows, 132 exempt rows | 31.3 s at load 41.9 (the first run of the session, host saturated) |
| the branch merged with `origin/main` `f5a1495387` (merge commit `23d0b0a680`, its own commit; main moved one commit, `#10109`, which touches `cron-egress-resolve.sh`, `cron-egress-firewall.test.sh`, the egress gateway bootstrap and one `.env`; no pair or triple moved) | 0 | 12 | 153 | same line | 18.5 s at load 34.9 |
| final head `0e3a0d0a84` (merge plus the fixture commit of this section) | 0 | 12 | 153 | same line | 9.9, 9.0, 10.8 s at load 6.4 to 8.3 (three runs) |

Merge commit `23d0b0a680` is a plain merge of `origin/main` into the branch (a separate commit, no edit); the merged tree's guard output was identical to the branch's before it was committed.

**AC-4, derivation parity.** `bash drv.sh` (the guard's own `PJ-DERIVE-BEGIN`..`END` block, `git ls-files` listing, `LC_ALL=C sort -u`) against `j0-derive.py` imported with the final arm set `{R1, R2, R3, R4b, R5a, R5b, R6, R7, R8}`: 262 triples each, `diff` empty on triples and on the 152 pairs, on the branch tree (`28e0b0ed53`), on the merged tree and at the final head (after the port received the comment rule). No delta to enumerate. The plain command `python3 -I .../j0-derive.py` on the merged tree now prints BASE 67 pairs and 126 triples (not the plan's 66 and 120) and U2 `+85 pairs, +136 triples`: 67 + 85 = 152 and 126 + 136 = 262. The BASE moved because this branch's own `sha256sum` stub edit (the verb leaves a four-name `for` loop and gets a heredoc stub) makes the pair `reusable-release-zot-mirror-retry.test.sh | sha256sum` visible to the S7b rules; the S7b guard text run on this tree reads the same 126 triples and one unlisted pair (that one). Not a port drift.

**AC-10.** `SWEEP_PROBE_CHECKS=50`; `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\('` returns 50 (S7b: 47; three checks added, `derivation-fixtures`, `producer-join-window`, `producer-join-verdicts`). `PJ_TRIPLES=262`. The literal grep of AC-10, `grep -c 'awk "\$PJ_AWK"'`, no longer matches the source (the call is `awk -v exts=... "$PJ_AWK"` in `pj_derive`); the equivalent `grep -vE '^[[:space:]]*#' ... | grep -c '"\$PJ_AWK"'` returns 1, and `pj_derive` has one call outside the fixture runner (`pj_join_pairs`, once, at the real run). No per-pair scan or per-file process was added. Static check H3: column-0 `FAIL=0` 1, `exit "$FAIL"` 1, `sweep_main .` 1, `sweep_fold` 2 (the definition and the one call), none inside a fixture or message.

**Wall time, plain and under a Check 10-shaped read-only bwrap** (`BWRAP_ARGS` of preflight Check 10 with `--tmpfs /home /root /run /tmp /var/tmp`, the repo bound read-only after them, `env -i`, `timeout 15s`, command `bash .claude/hooks/grep-q-pipe-guard.test.sh`; no `ulimit` inside it, as Check 10 has none). The load is high and shared; none of these is a quiet-host reading.

| run | wall | load average at the end of the run |
| --- | --- | --- |
| S7b guard (`0aae3f8680`), plain, interleaved | 10.8, 10.9, 14.3 s; later 10.4, 10.9 s | 9.3 to 10.3 |
| S7c head, plain, interleaved with the above | 10.2, 10.7, 14.1 s; later 9.7, 10.4 s | 9.1 to 9.6 |
| S7c head, plain, quieter window | 9.9, 9.0, 10.8 s | 6.6, 6.4, 8.3 |
| S7c head, bwrap with the 15 s cap | 8.3, 7.6, 7.7 s (first three, load 8.4 to 9.5); 7.8, 7.8, 9.9 s (load 6.6 to 10.1); every run exit 0 | as listed |

The head is within noise of the S7b guard at the same load, and under the Check 10 cap in all six capped runs. The plan's 12 s quiet-host trigger (decision-challenges item 10) is not reached (the largest plain figure at load under 10 is 10.9 s); the quiet-host figure itself still cannot be taken on this host.

### AC-7: mutation rows (M1 to M46, harness rows H1 to H7)

Method: `mutate.py` (scratch, not committed) drives each row in the clone `mut` under `ulimit -v 6000000`, one row at a time: `git reset --hard HEAD; git clean`, the UNMUTATED control run (must exit 0), the edits (each `sub` must land exactly the declared number of times, each `del` on exactly the declared number of lines, the tree must differ from `HEAD`), the guard run, graded RED only when the exit status is non-zero (or the named status, 3 for the two UNRESOLVED rows) AND every named substring is printed AND no forbidden substring is. A row that exits non-zero without its substring is WRONG-REASON and is not counted. No row executes an owner suite (every row is a read-only edit of the guard or of a file the guard reads), so none went through `run-isolated`.

**Final run, head `0e3a0d0a84`: 55 rows run, control exit 0 and mutation landed on every one; 54 RED, 1 survivor (M6 as written, an equivalent mutant, below), 0 wrong-reason, 0 unverified.** M4, M26, M41 and M43 read RED.

First run, head `23d0b0a680` (before the fixture commit, 54 rows; every control exit 0, every mutation landed): M6, M6b and M30 SURVIVED, M3 and M35 WRONG-REASON, the other 49 RED. What each was and what changed:

| row | first reading | cause | action |
| --- | --- | --- | --- |
| M3 | exit 1, but the named fixture `backslash-split` did not fire; red only through real-tree `unlisted pair` lines | the fixture's bar sits on the continuation line after a quoted word, which the any-producer arm (R3) reads without the backslash join, so the fixture does not pin R1's join | fixture `backslash-split-bar-first` added (`printf x \| \` then `curl -K -`: the bar ends line one, only the join sees the verb); M3 now reads `[backslash-split-bar-first must derive curl]` |
| M6 | survived | dropping `-k` from the timeout arity is an equivalent mutant: the numeric duration skip that follows reads `-k`'s operand anyway, so `timeout -k 2 5 curl` derives with or without the arity | recorded as equivalent, not counted passed; the real arity is pinned by M6b below |
| M6b (re-aimed M6: no timeout arity at all) | survived | no fixture used `-s SIG` | fixture `wrapper-timeout-s` added; M6b reads `[wrapper-timeout-s must derive curl]` |
| M30 | survived | the one-line stub fixture `curl() { cat >/dev/null; }` is a one-line file, so the extent is the file whatever the bound does | must-end fixture `crossoneline` added to `producer-join-window` (`curl() { :; }` then a top-level `cat >/dev/null`, want `no`); M30 reads `extent [no |no |no |ok |]` |
| M19 | red only by the luks-monitor recall row | the matrix names a `stub-in-sourced` fixture that did not exist | fixture added (a suite sources a file that defines the stub); M19 reads both |
| M35 | exit 1 not 3, no `UNRESOLVED` | the real rows partly find stubs through the other openers, so the exit is the definition-count FAIL plus the finder controls | re-aimed to the finder control it actually trips: `producer-join-finder-positive: a keyed first-statement drain read as [none]` |
| H2 (comment line between two joined lines) | the pair did not derive | `feed()` appended the comment text and ended the join; valid shell allows a comment between the stages of a pipe | `feed()` skips a comment line while the hold came from a trailing bar (a backslash hold is unchanged); a tree scan finds no such site, so no pair moved (AC-4 diff still empty); fixture `comment-between-stages` and new row M46 |

Table (final run, `res-final2.tsv`):

| row | mutation | control rc | landed | guard rc | grade | named substring read |
| --- | --- | --- | --- | --- | --- | --- |
| M1a | own dispatch: the real run derives from an empty file set | 0 | yes | 3 | RED | `UNRESOLVED: the producer-side join derived zero pairs` |
| M1b | own dispatch: the fixture runner derives from an empty file set | 0 | yes | 1 | RED | `[the fixture run derived nothing]` |
| M2 | drop the logical-line join over a trailing pipe | 0 | yes | 1 | RED | `[pipe-split must derive curl]` |
| M3 | drop the logical-line join over a trailing backslash | 0 | yes | 1 | RED | `[backslash-split-bar-first must derive curl]` |
| M4 | second member: the site scan stops after the first site of a file | 0 | yes | 1 | RED | `[second-site must derive jq]` |
| M5 | drop the wrapper table | 0 | yes | 1 | RED | `[wrapper-timeout must derive curl]` |
| M6 | per-wrapper arity: timeout -k read without its argument (the plan row as written) | 0 | yes | 0 | SURVIVED (equivalent mutant) | `[wrapper-timeout-k must derive curl]` |
| M6b | per-wrapper arity: timeout flags read with no arity at all (re-aimed M6) | 0 | yes | 1 | RED | `[wrapper-timeout-s must derive curl]` |
| M7 | treat command -v as a wrapper of the verb | 0 | yes | 1 | RED | `[command-v must NOT derive curl]` |
| M8 | drop the any-bar scan | 0 | yes | 1 | RED | `[other-producer must derive curl]` |
| M9 | quote parity removed from the any-bar scan | 0 | yes | 1 | RED | `[quoted-bar-single must NOT derive curl]` |
| M10 | join a trailing bar that sits inside a quote | 0 | yes | 1 | RED | `[quoted-trailing-bar must NOT derive curl]` |
| M11 | join over a YAML block-scalar indicator | 0 | yes | 1 | RED | `[yaml-block-scalar must NOT derive curl]` |
| M12 | drop the case-alternation exclusion | 0 | yes | 1 | RED | `[case-alternation must NOT derive curl]` |
| M13 | drop the sourcer rule (reverse source map) | 0 | yes | 1 | RED | `[library-sourced must derive curl]` |
| M14 | pipefail taken from the owning test file | 0 | yes | 1 | RED | `[library-unsourced-no-pipefail must NOT derive curl]` |
| M15 | helper stub: read only the first argument | 0 | yes | 1 | RED | `[helper-arg2 must derive curl]` |
| M16 | drop the loop arm | 0 | yes | 1 | RED | `[loop-built must derive curl]` |
| M17 | drop .tf from the shared extension list | 0 | yes | 1 | RED | `[tf-producer must derive curl]` |
| M18 | restore the stub-name strip | 0 | yes | 1 | RED | `[stub-unquoted-semicolon must derive jq]` |
| M19 | drop the one-hop sourced-stub arm | 0 | yes | 1 | RED | `[stub-in-sourced must derive curl]` |
| M20 | annotation strip reverts to end of line | 0 | yes | 1 | RED | `[annot-pipe-after must derive jq]` |
| M21 | annotation strip stops at the first quote and ignores the backslash | 0 | yes | 1 | RED | `[annot-escaped-quote must NOT derive curl]` |
| M22 | no annotation strip | 0 | yes | 1 | RED | `[annot-pipe-inside must NOT derive curl]` |
| M23 | the observed rule reads only the first physical line of a logical line | 0 | yes | 1 | RED | `[continuation-or-true must NOT derive curl]` |
| M24 | a new producer of an already-listed pair (a file added and named by the suite) | 0 | yes | 1 | RED | `FAIL: the derivation found 263 (test file, verb, producer file) triples and PJ_TRIPLES pins 262` |
| M25a | delete one row and keep its pair | 0 | yes | 1 | RED | `FAIL: unlisted pair: .claude/hooks/grep-rewrite.test.sh stubs 'jq'` |
| M25b | keep a row whose pair no longer derives | 0 | yes | 1 | RED | `FAIL: stale join row: ghost.test.sh \| curl` |
| M26 | REORDER (window): no bound at another verb's opener | 0 | yes | 1 | RED | `extent [ok \|no \|no \|no \|] (want` |
| M27 | remove the heredoc-terminator bound | 0 | yes | 1 | RED | `extent [no \|no \|ok \|no \|] (want` |
| M28 | remove the closing-brace bound | 0 | yes | 1 | RED | `extent [no \|ok \|no \|no \|] (want` |
| M29 | widen the bound to every file write | 0 | yes | 1 | RED | `must still read as drains [no \|ok \|] (want` |
| M30 | the closing-brace bound ignores a one-line stub (the plan row as written) | 0 | yes | 1 | RED | `extent [no \|no \|no \|ok \|] (want` |
| M31 | second member: a second definition of the verb with no drain after a compliant first | 0 | yes | 1 | RED | `with no stdin drain` |
| M32 | drop the test -t 0 alternative from the non-drain pattern | 0 | yes | 1 | RED | `non-reading spelling detected as a drain: test -t 0 && cat >/dev/null` |
| M33 | drop the if ...; then alternative | 0 | yes | 1 | RED | `non-reading spelling detected as a drain: if [ -t 0 ]; then cat >/dev/null; fi` |
| M34 | drop the input-redirect alternative | 0 | yes | 1 | RED | `non-reading spelling detected as a drain: cat >/dev/null </dev/null` |
| M35 | own dispatch: the stub opener is renamed so the finder sees zero | 0 | yes | 1 | RED | `producer-join-finder-positive: a keyed first-statement drain read as [none]` |
| M36 | remove the cat 2> and cat - alternatives | 0 | yes | 1 | RED | `accepted spelling not detected: cat -` |
| M37 | the definition-count verdict is neutered | 0 | yes | 1 | RED | `no 'stubs 'curl' in 1 definitions, the row pins 2'` |
| M38 | the no-drain verdict is neutered | 0 | yes | 1 | RED | `no 'defines the 'curl' stub with no stdin drain'` |
| M39 | the malformed-row verdict is neutered | 0 | yes | 1 | RED | `no 'malformed drains row'` |
| M40 | the triple-pin verdict is neutered | 0 | yes | 1 | RED | `no 'triples and PJ_TRIPLES pins 6'` |
| M41 | the pj_j merge assignment is blanked, with a real row deleted | 0 | yes | 1 | RED | `the pj_judge merge 1 and its assignment 0` |
| M42 | the no-line loop of the row check is made a no-op | 0 | yes | 1 | RED | `no 'defines the 'curl' stub with no stdin drain'` |
| M43 | second member: the row check stops after its first row | 0 | yes | 1 | RED | `no 'with no stdin drain'` |
| M44 | own dispatch: the row-check driver is handed zero rows | 0 | yes | 1 | RED | `no 'stubs 'curl' in 1 definitions, the row pins 2'` |
| M45 | pj_unread widened to accept rc 3 | 0 | yes | 1 | RED | `[pj_unread grades a status it must not]` |
| M45b | the row-check merge is neutered | 0 | yes | 1 | RED | `the row-check merge 0` |
| M45c | the triple-pin assignment is blanked | 0 | yes | 1 | RED | `the triple-pin merge 1 and its assignment 0` |
| M46 | a comment line between the stages of a pipe: the skip removed | 0 | yes | 1 | RED | `[comment-between-stages must derive curl]` |
| H1 | delete the derivation-fixture runner tail | 0 | yes | 1 | RED | `probe-count: this probe carries 49 checks, pinned at 50` |
| H4 | the extent logic accepts only a function opener | 0 | yes | 3 | RED | `UNRESOLVED: the drains row for` |
| H6 | delete the verdict-control tail | 0 | yes | 1 | RED | `probe-count: this probe carries 49 checks, pinned at 50` |
| H7c | the fold: a deliberately wrong row turns the suite red and prints no PASS line | 0 | yes | 1 | RED | `stubs 'docker' in 2 definitions, the row pins 3` |

Plan rows whose expectation text differs from what the guard prints: M44's plan text says `row checks derived nothing`; the guard has no such line (the zero-row driver reads RED through the verdict control, `producer-join-verdicts`), so the row is graded on that substring. M1's two halves (real run and fixture runner) are M1a and M1b. M25 is two rows (M25a a deleted row, M25b a ghost row). M45b and M45c are the two merge pins S7c added (decision-challenges item 29). M46 is the new row for the comment rule.

**Harness rows.**

| row | what | result |
| --- | --- | --- |
| H1 | delete the fixture runner's `|| sweep_probe_fail+=` tail | RED: `probe-count: this probe carries 49 checks, pinned at 50` |
| H2 | must-PASS fixtures that are not the canonical, through the guard's own `pj_derive` (`h2.sh`): a tab-indented continuation after a backslash and after a pipe; `env -i VAR=1 curl`; a comment line between joined lines (both forms); a suite naming `fprod.sh` is not an owner of `prod.sh` while one naming `prod.sh` is; a CRLF producer and a CRLF continuation | first run 8 of 9 pass, the comment case failed (above); final run 9 of 9 pass |
| H3 | the remediation's own text: no column-0 `FAIL=0`, `exit "$FAIL"`, `sweep_fold` or `|| sweep_probe_fail+=(` text inside a fixture or message; header recipe re-run | counts above (1, 1, 1 call plus the definition); the recipe returns 50 = `SWEEP_PROBE_CHECKS` |
| H4 | the extent logic accepts only a function opener | RED, exit 3: `UNRESOLVED: the drains row for .claude/hooks/grep-rewrite.test.sh jq found 0 stub definitions` |
| H5 | each accepted spelling through the dynamic control, both dispositions, both interpreters (AC-8 below) | 82 graded runs, 0 disagreements |
| H6 | delete the verdict control's tail | RED: `probe-count: ... 49 checks, pinned at 50` |
| H7 | must-PASS: (a) a clean fixture table and clean fixtures print nothing from each verdict function; (b) extra blanks around the separators and a tab-separated `drains` row are accepted by `pj_judge` and `pj_check_rows`, and a wrong count still prints (a copy of the guard with a probe block ahead of the real run, scratch clone `h7`: `H7-RESULT: clean`); (c) the fold: a deliberately wrong real row (`ci-deploy.test.sh | docker | drains | 3`) | (a) and (b) clean; (c) RED, exit 1, `stubs 'docker' in 2 definitions, the row pins 3`, and no `PASS: grep-q-producer-join` line |

### AC-8: the dynamic control (`ac8.sh`, independent of the guard's own run; the spelling arrays and the detector are the guard's)

A `#!/bin/sh` stub that reads nothing, run by dash and by bash, and a bash stub: SIGPIPE ignored rc 1, default disposition rc 141, in every case (the two measured reachable; CI reads 1 for both where SIGPIPE is inherited ignored). Every accepted spelling, including `x=$(cat 2>/dev/null)` and `cat -`, `[ ! -t 0 ] && cat` and `[ -t 0 ] || cat`, exits 0 under both dispositions and every interpreter its tag allows (sh-tagged under dash and bash, bash-tagged under bash) and is detected as a drain. Every non-reading spelling, including `test -t 0 && cat`, `if [ -t 0 ]; then cat; fi`, `cat >/dev/null </dev/null`, `[ -t 0 ] && cat`, `[[ -t 0 ]] && cat`, `true || cat`, a backgrounded `cat` and a pipe-fed `cat`, fails with rc 1 or 141 under both dispositions and is not detected as a drain. 82 graded runs, 0 disagreements between the run and the detector (output `ac8-final.out`).

### AC-9: lints

| lint | command | result |
| --- | --- | --- |
| shell capture exit | `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` | rc 0, `1571 script(s) scanned, 0 new findings, 224 baselined` |
| vacuity floor | `bash scripts/guard-vacuity-floor.test.sh` | rc 0, 23 passed, 0 failed |
| orphan suites | `bash scripts/lint-orphan-test-suites.sh` | rc 0, `675 covered, 0 orphaned` |
| shellcheck `-S warning` findings, `origin/main` against head | the guard 0 to 0; `reusable-release-zot-mirror-retry.test.sh` 0 to 0; `test-supabase-advisor-scan.sh` 0 to 0; `test-zot-log-channel-probe.sh` 1 to 1; `ci-deploy.test.sh` 19 to 19; `git-data-flag-precheck.test.sh` 0 to 0; `git-data-cutover-access.test.sh` 0 to 0 | unchanged on all seven |
| guard contract | `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-12-chore-grep-q-wave-b-s7c-derivation-recall-plan.md` | rc 0, 1 plan, 3 guard entries |
| no human steps | `python3 scripts/lint-infra-no-human-steps.py <the plan>`; also `--changed` | rc 0 both (1 and 5 files scanned) |
| fixture relative assert | `bash plugins/soleur/test/fixture-relative-assert.test.sh` | first lane run RED (see below); rc 0 after the one-comment reword, 62 passed |
| kb consumers | `bash scripts/test-affected-kb-consumers.test.sh`, once, nothing written to the repo while it ran | rc 0, 23 passed of 23, 154 s at load about 10; the gate named no new reference, so the baseline file was not touched in this section |
| pre-push ratchet lane | `bash scripts/pre-push-ratchet-lane.sh` on the merged tree (head `0e3a0d0a84`) | rc 0, `RATCHET_LANE verdict=PASS members=19 red=0 seconds=949 merge=ok base=f5a1495387` (its kb-consumers member ran too, 351 s at load about 10, PASS) |

**A real find from the lane.** The first lane run (head `23d0b0a680`) was RED on `fixture-relative-assert`: the guard's S7c edit carried the text `> "$d/jq"; chmod` in an awk comment (the R7 note), which the scanner reads as a redirect to a relative operand (`root=never-bound`), one new site over the baseline of 2067. Fixed by rewording the comment (commit `0e3a0d0a84`) rather than baselining one more row; the lane member and the standalone suite are green. The lane's other RED in that run was `ci-deploy.test` hitting the lane's own 300 s member cap (the suite takes about 8 minutes on this host, evidence Phase 3 and the AC-6 pair run); it printed PASS lines up to the cap and no FAIL. In the second lane run (head `0e3a0d0a84`, lower load) the same member passed in 295 s, five seconds under the cap: the member is flaky against its own cap at this host's load, not red. Not changed here (the lane script is outside this slice).

## Fix round A (2026-10-12; guard code; review panel at `0a8d2bd5e5`)

Commits (all on the branch, nothing else touched but this spec directory's `j0-derive.py`, `decision-challenges.md` (items 43 to 58) and this section): `6c4e15708c` P1-1 rename, `af5f801136` P1-2 order-independent producer list, `7a03a1b4cb` P1-3 row counts and call pin, `730bcc298a` collision lint and the softened comment, `cd2ab0ff7e` bounds (P2-A), `5758facb6f` pins, floors, fixtures, `fenced`, same-line loop arm, header (P2-B to I), `030ac54a5e` the port, `9b525e63e7` the pj_judge join (a perf regression of the round's own bash 3.2 lookup, found and fixed in the round).

### Instruments

* **mawk and busybox awk without a package install or network.** `docker create` + `docker cp` of `/usr/bin/mawk` out of `node:22-slim` (mawk 1.3.4 20200120, the Debian dialect) and of `ubuntu:24.04` (mawk 1.3.4 20240123, the Ubuntu 24.04 default), and of `/bin/busybox` out of `busybox:latest` (BusyBox v1.38.0); each put first on `PATH` as `awk` (busybox through a one-line `exec busybox awk "$@"` wrapper) and the WHOLE guard run: `( ulimit -v 6000000; PATH=<shim dir>:$PATH bash .claude/hooks/grep-q-pipe-guard.test.sh )`. The host has gawk only, and a container has no git, so the guard cannot run inside one; the derivation program itself was also run inside containers with the worktree read-only: `docker run --rm --network none -v "$PWD":/w:ro -v <dir with prog.awk, exts.txt, listing.txt, files.txt>:/s:ro node:22-slim sh -c 'cd /w && LC_ALL=C awk -v exts="$(cat /s/exts.txt)" -f /s/prog.awk /s/listing.txt $(cat /s/files.txt)'` (prog.awk is `PJ_AWK` written out by the guard's own `PJ-DERIVE` block) and the same with `bash:3.2` (busybox awk): 263 sorted triples each, `diff` empty against gawk's.
* **Mutation harness.** Five sandboxes (`bash scripts/soleur-sandbox.sh new fixa…`, `git init`, `git add -A`; the guard sees 1846 files, 152 then 153 pairs exactly like the worktree), one mutant at a time per sandbox; per mutant: the pristine guard copied in, the substitution applied by a script that refuses to run if the pattern is absent, `diff -q` against the pristine copy asserting the mutation landed, the guard run under `( ulimit -v 6000000; ... )`, the output searched for the named FAIL text, the pristine guard copied back. A control (the unmutated copy) runs first in every batch. No mutant sends a signal or removes a file (the dynamic control's own pipes excepted), so no `run-isolated` was needed.
* **Triple dumps.** `drv.sh` sources the guard's `PJ-DERIVE` block and prints `pj_join_pairs | LC_ALL=C sort -u` (the header recipe); `j0-derive.py` is run from the repo root through a scratch driver with the shipped arm set `{R1, R2, R3, R4b, R5a, R5b, R6, R7, R8}`.

### P1

| item | before | after |
| --- | --- | --- |
| P1-1 `base` local in `anybar` | mawk 1.3.4 20200120 at `0a8d2bd5e5`: `awk: line 56: syntax error at or near base` (and lines 57, 59), `UNRESOLVED: the producer-side join derived zero pairs`, rc 3 | renamed `bs0` (3 tokens); derivation parses and gives 263 (then 262) triples under gawk, mawk 20200120, mawk 20240123 and busybox 1.38 |
| P1-2 order-dependent producer list | after P1-1, mawk: `producer-join-judge: ... [no 'names a non-test file that pipes text into it (fxlib.sh, fxprod.sh)' for a fixture that must print it]`, rc 1 (a leading comma: mawk creates `m[k]` first) | `if (k in m) m[k] = m[k] ", " $3; else m[k] = $3`: rc 0 under mawk; at `9b525e63e7` this became one awk join (item 58) |
| P1-3 no floor on the row checker | `printf junk | pj_check_rows` or `${PRODUCER_JOIN[@]:0:1}` stayed green and still printed `21 drains rows verified` | the checker ends with `ROWS-CHECKED <rows> <drains>` when asked (`counts`), `pj_check_counts` compares both with `${#PRODUCER_JOIN[@]}` and the separate loop's drains count, the call is pinned to the exact form (comment-stripped, column 0, whole table, `counts`), the strip and the merge each have a pin; the PASS line prints `21 of 21 drains rows verified by the checker, ... 154 of 154 rows read` |
| lint for the P1-1 class | none | `pj_collide` (pure awk, over `PJ_AWK` and `PJ_DEFS_AWK`) with a positive control (`anybar:base`), a must-pass control, a two-collision control; check `awk-param-collision` |

Mutations (final head unless a commit is named; every row landed, `diff -q` differs; control GREEN, rc 0):

| mutation | result |
| --- | --- |
| P1-1 lint at `730bcc298a`: reintroduce the local `base` (3 spots), gawk | RED rc 1: `awk-param-collision: ... [anybar:base] (want none: mawk stops on it)`; before the lint this exact edit was GREEN under gawk |
| lint neutered (`if (0 && pp[i] in isfn)`) | RED rc 1: `awk-param-collision: ... [none] ... the known collision read as [NOTHING]` |
| P1-3 call fed `junk` | RED rc 1: `FAIL: the definition checker looked at 1 of the table's 154 rows and 0 of its 21 drains rows` |
| P1-3 call fed `${PRODUCER_JOIN[@]:0:1}` | RED rc 1: `looked at 29 of the table's 154 rows and 0 of its 21 drains rows` (word splitting of the unquoted expansion; first form of the call) |
| call without `counts` | RED rc 1: `producer-join-wiring: ... which must feed the whole table and ask for the counts 0` |
| strip of the count line replaced by `pj_rc=""` | RED rc 1: `producer-join-wiring: ... the strip of the count line 0` |
| `pj_check_counts` neutered (`|| :`) | RED rc 1: `producer-join-negative-controls` (and the four `producer-join-verdicts` fixtures) |
| checker stops counting rows / drains rows | RED rc 1: `looked at 0 of the table's 154 rows` / `... and 0 of its 21 drains rows` |
| count line swaps its two numbers | RED rc 1: `looked at 21 of the table's 154 rows and 154 of its 21 drains rows` and `producer-join-verdicts: ... [pj_check_rows reported 'ROWS-CHECKED 2 3' ...]` |
| count line always printed | RED rc 1: `producer-join-verdicts: ... [clean rows printed: ROWS-CHECKED 1 1] ... [pj_check_rows printed a count line without being asked for one]` |
| drop the `|| true` after the `read` of the count line together with `counts` | RED rc 1 but SILENT (`set -e` ends the guard at the `read`, no FAIL text): this is why the `|| true` stays; it cannot be pinned alone (with `counts` present the `read` succeeds) |

### P2

**A. bounds** (`cd2ab0ff7e`). The derived triples are identical before and after (sorted `diff` empty; gawk, mawk 20200120, busybox): the 200-character cap on `unwrap` (both call sites), `JOINBYTES = 8192` beside `JOINCAP`, the loop list compacted at 32 entries (the 15-line life of a loop bounds the live entries at 15). The stale comment now reads 4.4 to 5.5 s of user CPU at origin/main and 6.1 to 7.9 s at head under load (performance seat). Cost of the loop list, measured on a synthetic test file of 30000 consecutive `for` lines through `pj_derive`: 44.0 s before, 3.6 s after (the bound changes no output, so it is not pinnable by a fixture; `loop-many` pins that compaction keeps a live loop correct). Mutations: `unwrap` cap removed RED `derivation-fixtures: 60 cases ...; failed: [wrapcap-over must NOT derive curl]`; byte cap removed RED `[joinbytes-over must derive curl]`; byte cap raised to 100000 the same; `lcompact` copying the wrong pattern, dropping every entry, or zeroing the life: RED `[loop-many must derive curl]` (three mutants).

**G. hygiene** (`cd2ab0ff7e`, `5758facb6f`, `9b525e63e7`). Unused locals removed (`q` in `anybar`, `w` in `site`, `lv[nlp]`, the scalar `tl` that shadowed the global array of test files, now `rst`): triples unchanged. `local -A` gone: bash 3.2 (`docker run --rm --network none ... bash:3.2`) prints the same three FAIL lines for a three-pair fixture. `LC_ALL=C` on the four remaining awk calls (pj_defs, pj_detects, the PJ_UNIQ_SH build, pj_sourced). The pj_defs and pj_sourced header comments are rewritten to the S7c behaviour.

**B. pins and floors** (`5758facb6f`):

| mutation | result |
| --- | --- |
| delete a derivation case (floor 79 after the additions of this round) | RED rc 1 (printf+exit): `FAIL: PJ_CASES holds 76 derivation cases, the floor is 77` (run at the intermediate floor) |
| delete an accepted spelling / a non-reading spelling | RED rc 1: `PJ_DRAIN_OK holds 8 ..., the floor is 9` / `PJ_DRAIN_BAD holds 24 ..., the floor is 25` |
| `pj_jc`, `pj_rcc`, `pj_tcc`, `pj_ccc` made to record no failure (one mutant each) | RED rc 1, each: `producer-join-negative-controls: a fixture driver recorded no failure ...` (the positive fixtures stay green: that is the vacuity the control exists for) |
| definition-count check silent when found is greater than pinned (`>=`) | RED rc 1: `producer-join-verdicts: ... [no 'stubs 'curl' in 2 definitions, the row pins 1' ...]`; the `<=` mutant is caught by the existing `pins 2` fixture |
| triple pin silent when found is greater than pinned (`>=`) | RED rc 1: `producer-join-verdicts: ... [no 'found 6 (test file, verb, producer file) triples and PJ_TRIPLES pins 5' ...]`; the `<=` mutant is caught first by the negative control of `pj_tcc` |
| a drains row flipped to `exempt arm-drain` | RED rc 1: `FAIL: the table holds 20 drains rows, the floor is 21` |
| the drains-row floor statement deleted / a table floor statement deleted | RED rc 1: `producer-join-wiring: ... the drains-row floor 0` / `the three table floors 2 (want 3)` |

**C. extent bounds** (`5758facb6f`; fixtures `crosshelp`, `crosshd`, `crossown`, `innerbrace`, `returnfirst`, `exitsemi`, `exitbare`, `sameexit`, `samereturn` on top of the five that existed). Each removed alone: `ANYHELP` (`producer-join-window` RED, `crosshelp` reads `ok`), `ANYHD` (RED, `crosshd`), the `own ||` term of `bnd` (RED, `crossown` reads `ok ok`), the indent compare of the brace bound (RED, `innerbrace` reads `no`), `return` in the disarming regex (RED), the `;` in its class (RED), the `$` alternative (RED). Seven mutants, seven REDs, all `producer-join-window: ...`.

**D. fixture claims** (`5758facb6f`). Cases 55 to 79: `ext-<e>` (must derive) and `ext-<e>-no-pipefail` (must not) for `bash yml yaml tftpl template service tmpl`, `ext-unlisted` (`.txt`), `helper-other-verb` and `helper-mid-statement` (R5a must-nots), the two bound pairs, `loop-many`, `loop-sameline` and its must-not; the comment now lists the pair of cases per arm and is true. Dropping each extension from `PJ_EXTS` in turn: RED, each naming `[ext-<e> must derive curl]` (seven mutants). R5a anchor dropped RED `[helper-mid-statement must NOT derive curl]`; every helper call stubbing `curl` RED `[helper-other-verb must NOT derive curl]` (the first attempt mutated the loop copy of the line and was GREEN-for-the-wrong-reason; it was redone on the R5a copy). `pj_sourced` fixture (`producer-join-sourced`, check 52): self-source not excluded RED, statement-start anchor dropped RED, unique list ignored RED, quote tolerance dropped RED rc 3 (the real luks-monitor row then finds 0 definitions, before the fixture runs); the comment-skip rule of `pj_sourced` is dead (equivalent mutant, removed: old and new agree on all 1560 tracked `.sh`, 236 non-empty).

**E. non-reading spellings** (`5758facb6f`). Independent proof first (`hz.sh`: the guard's `pj_hazard` shape, a stub reading nothing run against a 1 MiB producer under `set -o pipefail`; SIGPIPE ignored then default; dash then bash): `echo cat >/dev/null`, `command -v cat >/dev/null`, `type cat`, `which cat`, `dd of=/dev/null count=1`, `dd of=/dev/null bs=1 count=1`, `[ -t 1 ] && cat >/dev/null`, `cat >/dev/null <&-`, `cat >/dev/null & wait`, `exit 0; cat >/dev/null`: rc 1 and 141 under both interpreters; `return 0; cat >/dev/null`: rc 1 and 141 under dash, rc 0 and 0 under bash (a top-level `return` is an error there and the script goes on), so that one is tagged `sh`; the control `cat >/dev/null`: rc 0 and 0. The guard's own dynamic loop runs every one of the 25 spellings (and the nine accepted ones) under both dispositions. Mutations (each alternative of the new non-drain pattern removed alone): echo/printf/type/which/command-v alternative (and each of `echo`, `type`, `which`, `command -v` alone), the `dd ... count=` alternative, `-t` restricted to descriptor 0, `<&-`, the `& wait` alternative, the line-initial `exit|return N;` alternative: ten mutants, ten REDs, each `producer-drain-nonreading: ... detector disagreements: [non-reading spelling detected as a drain: <the spelling>]`.

**F. vocabulary** (`5758facb6f`). `fenced` is the ninth word (decision 43); the two cloud-init-inngest-bootstrap rows read `fenced ...`; `blocked-#9217` is no longer used. Fixtures: `fenced x` accepted, `fencedx x` and `fence x` rejected, `blocked-#9217 x` still accepted; the vocabulary is pinned at nine words. Mutations: `fenced` dropped from `PJ_VOCAB` RED (`exempt row without a vocabulary reason` for both rows and the fixture); a tenth word RED `the closed vocabulary holds 10 words (want 9)`.

**Same-line loop stub** (`5758facb6f`, decision 51). 13 lines of awk; one new triple (`zot-image-fetch.test.sh cryptsetup`, producer a cloud-init file), so 153 pairs, 263 triples and one new row (`exempt deliberate-fault`, 154 rows); the port got the same rule and its sorted triples equal the awk's (263 each). Mutations: arm removed RED `[loop-sameline must derive curl]`, the row deleted RED `unlisted pair: apps/web-platform/infra/zot-image-fetch.test.sh`, `PJ_TRIPLES` left at 262 RED `PJ_TRIPLES pins 262`, the loop variable ignored RED `[loop-sameline-nonverb must NOT derive curl]`.

**pj_judge join** (`9b525e63e7`, decision 58). Four mutants (join key, separator, triples never read, ordering): four REDs naming the `names a non-test file ... (fxlib.sh, fxprod.sh)` and the empty-table fixtures.

### Final numbers (head `9b525e63e7`)

153 derived pairs, 263 producer triples (`PJ_TRIPLES=263`), 154 rows (21 drains, 133 exempt), `SWEEP_PROBE_CHECKS=52` (two checks added: `awk-param-collision`, `producer-join-sourced`), derivation cases 79 (floor 79), accepted spellings 9 (floor 9), non-reading spellings 25 (floor 25), drains-row floor 21, vocabulary nine words. 152 pairs and 262 triples became 153 and 263 by exactly one deliberate change (the same-line loop arm, decision 51); before that edit every step of the round printed 152 and 262 (bounds, floors, fixtures). Derivation equals the port: `diff` of the sorted triples empty at 263.

Guard wall time: 11.0 s real, 16.5 s user at load about 11 (gawk, final head), 9.8 s under mawk 20200120, 9.5 s under mawk 20240123, 30.8 s under the busybox wrapper (a shell wrapper per awk call). The review head ran 11 to 31 s real on the same host at load 30 to 34; the intermediate head with the per-pair string lookup ran 45 to 67 s.

Lints on the final head: `lint-shell-capture-exit.py --baseline` 0 new findings (1571 scripts); `guard-vacuity-floor.test.sh` 23 passed; `lint-orphan-test-suites.sh` none orphaned; `fixture-relative-assert.test.sh` 62 passed, 0 failed (it was RED at the intermediate head: four relative-redirect sites in the guard, decision 54, fixed in the guard, the baseline not regenerated); `shellcheck -S warning` on the guard 0 findings at origin/main, 0 at the review head, 0 at this head (it was 14 at the intermediate head: three fixture lines appended with the array form `+=(` to a string variable, so their failures would have been recorded in element 1 and never read: a vacuous fixture, fixed and proven by the two count-line mutants above); `bash scripts/test-affected-kb-consumers.test.sh` once, nothing written to the repo while it ran: 23 passed, 0 failed (the baseline file was not touched).

Surprises: (1) the mawk and the busybox shim made the whole-guard check cheap (one `docker cp` each), and the review's "CI is the only mawk reading" was avoidable; (2) shellcheck caught a vacuous fixture that no mutation had been aimed at; (3) a bash 3.2-safe replacement of an associative array can be 30 times slower than the array (glob match over a 30 KB string, 153 lookups, twice): measure it; (4) `set -e` turned a missing count line into a silent rc 1.

## Fix round B (2026-10-12; suites and documents; review panel at `0a8d2bd5e5`, after round A at `e8e91ca13b`)

Append-only: nothing above is edited; this section supersedes the lines it names. Suite commits: `a76bb550b5`, `f8a77fd949`, `6b7e083e82`.

### Suites (three P3 edits; each proven by deleting it back out in a sandbox from `bash scripts/soleur-sandbox.sh new fixb`, `run-isolated`, `ulimit -v 6000000`)

| Suite | Edit | Deleted back out, the named assertion |
| --- | --- | --- |
| `tests/scripts/test-zot-log-channel-probe.sh` (S6 wire assert) | `_awk_want` takes `S6_AWK_STDIN_LINES` only when it matches `^[0-9]+$`, otherwise the computed default (the value was interpolated into a condition `assert()` runs through `eval`) | Drain removed from the fake awk: `FAIL: S6 the fake awk received the rows the grading pass pipes into it` (113 passed, 3 failed against 114 and 2). Injection control: with `S6_AWK_STDIN_LINES='$(touch MARKER)'` quoted in single quotes, the pre-edit text creates the marker file, the edited text does not and still passes the assert |
| `tests/scripts/test-supabase-advisor-scan.sh` | `STUB_HEADER_LINE` renamed `ADVSCAN_WANT_HEADER_LINE` (the only occurrence; it was read by the assert alone, in the namespace the file's comment says `reset_stub` exports and the stub reads bare) | Drain removed from the curl stub: `FAIL curl stub stdin`, `1 check(s) FAILED`, rc 1 |
| `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` (T3) | `rm -f "$STUB_DIR/sha256sum.stdin"` before T3 | Drain removed: `FAIL: T3 sha256sum stub received the checksum line ... got ''` (24/25). Stale-file control: with the stub's drain skipped in T3 only, the pre-edit text passes (25/25, the assert read T1/T2's file) and the edited text is red (24/25) |

Pair runs (HEAD before this round, then the edited file, same sandbox, same host; the zot probe suite reads 2 failures in BOTH because the sandbox copy has no `.git` index for its C12 linter and mode checks, the same two at base): zot probe `114 passed, 2 failed` and `114 passed, 2 failed`; supabase advisor scan `all checks passed` (25 ok lines) both; mirror retry `25/25 passed, 0 failed` both. No assertion was added or removed, so the counts are equal.

### Corrections to section 0.1, Phase 4, and the 0.4 and 0.5 tables

* **Section 0.1 and AC-4: the BASE delta 66 / 120 to 67 / 126 has two causes, not one.** The branch's own `sha256sum` stub edit adds one pair and five triples (`reusable-release-zot-mirror-retry.test.sh | sha256sum`, five producer files, all five present in the guard's triple dump at this head), and main's `fc2c938d86` (#10038) adds one triple, `tests/scripts/test-argv-bearer-sweep.sh | jq | scripts/probe-github-app-mint.sh` (the guard on main's merge base `fea9d482ae` pins `PJ_TRIPLES=121`; the guard at `0aae3f8680`, `ffe17b85c3` and current origin/main also pins 120, a figure this section does not explain). 120 + 1 + 5 = 126. AC-4 attributes the whole delta to the stub edit; that sentence is superseded by this one. The reconciliation of the totals is decision-challenges item 59.
* **Phase 4 sentence "#9956 is not cited as red at base anywhere" is over-broad.** The archived S7b plan (`knowledge-base/project/plans/archive/20261012-033826-2026-10-11-chore-grep-q-wave-b-s7b-producer-join-plan.md`, lines 43 and 360) cites #9956 as red on main and ties the cloud-init row to it; its live subject is the tier-census defect (G4c) closed by #10053. What holds: no live artifact of this branch cites it as red at base for the cloud-init suite after Phase 4.
* **Lines that still read `blocked-#9956` are historical and superseded by decision-challenges item 43:** the section 0.4 and 0.5 table rows for `cloud-init-inngest-bootstrap.test.sh` (docker, about line 287; timeout, about line 327) and `reach-table.tsv` rows 15 and 105. They record the plan-time classification and are not edited. The `action` column of `reach-table.tsv` is likewise plan-time (a TSV has no comment line to say so): the rows of the guard are the current state.
* **The late finding "the annotation skip has no real instances" is false.** J0's R8 is `+0 pairs, +1 triple`, and the triple is real: `tests/scripts/test-git-data-birth-readiness-gate.sh | grep | .github/workflows/git-data-rung2-rehearsal.yml`, from `printf '%s' "$probe_out" | grep -c .` inside `$(...)` in the `echo "::error::..."` lines 478 and 784 of that workflow.
* **Item 24 against section 0.1:** `69 / 51` and `66 / 48` are the same measurement counted with and without three listed pairs that only gain a producer (decision-challenges item 60).

## Post-merge and fix round C (2026-10-12; guard, documents and one learning; review panel of seven seats at `8b43c9df5d`)

Append-only: nothing above is edited; this section supersedes the figures and statements it names. Fix-round commits: guard `39cb00fc81` (fenced rule, JOINBYTES, floors, controls, collision lint, dash-less hosts, header), documents `c51f9c31fc`, guard `8508116948`, and the commits that follow this section (their subjects are in the report; `git log 8b43c9df5d..HEAD` is the list).

### The merge with main, and which figure belongs to which head

* `8b43c9df5d` merged `origin/main` into the branch. Main's change deleted `web-host-reboot.yml` and `web2-luks-rebirth.yml` and retired their suites (`scripts/web-host-reboot.test.sh`, `scripts/web2-rebirth.test.sh`, `scripts/web2-rebirth-recovery-check.test.sh`). Four rows were dropped from `PRODUCER_JOIN` (web-host-reboot curl; web2-rebirth-recovery-check cryptsetup and curl; web2-rebirth curl), all exempt, and `PJ_TRIPLES` went from 263 to 258 (five triples: web-host-reboot curl over two producers, the recovery-check pair over two verbs, web2-rebirth curl).
* **Every earlier "final" figure in this directory is the `e737ea0814` state**: 153 pairs, 263 triples, 154 rows, 133 exempt rows, `PJ_TRIPLES=263`, `BASE 67 / 126`, `120 + 1 + 5 = 126`, `U2 +86 / +137` over 66 test files, `+85 over 67`. At the merge head and at the fix-round-C head the guard prints 149 pairs, 258 triples, 150 rows, 129 exempt rows, and `j0-derive.py` prints `BASE 66 pairs, 125 triples` and `U2 +83 pairs, +133 triples over 63 test files` (149 = 66 + 83, 258 = 125 + 133 = 120 + 138). The BASE moved from 126 to 125 because the one retired pair that the base rules could see (recovery-check cryptsetup) is gone; the evidence's "a figure this section does not explain" for the guard on current main (120) is main's own retirement of a web2 cryptsetup row.
* `reach-table.tsv` rows 84 to 86 and the evidence tables for the three retired suites (the t1 timing rows, the EXEC listing and the arm-drain table, about lines 106, 110, 125, 252 to 254 and 318 to 320 above) are HISTORICAL: those suites no longer exist and no guard row corresponds to them. They are not edited.

### Review result (seven seats, report-only, at `8b43c9df5d`; fix diff `0a8d2bd5e5..e737ea0814` plus the merge)

| Seat | P2 | P3 | Disposition |
| --- | --- | --- | --- |
| security | 1 (`JOINBYTES` stops joining, so a trailing-bar consumer on the next line is not derived) | 5 | Fixed (decision 64); P3 comments fixed, the collision lint widened (67), the `fenced` residual closed by 62; the hand-read zot row now says so |
| architecture | 1 (`fenced` weaker than `blocked-#N`) | 6 | Fixed (62); the stale header limit and the unstated limits fixed (68); R1 x R3 fixtures added; the granularity gap stays the plan's NOT-fixed item (72) |
| git-history | 3 (annotation claims disagree across header, learning and `j0-derive.py`; loop-on-one-line limit; no post-merge figures) | 4 | All fixed (68, this section, the learning's further correction, `j0-derive.py`); item 59's arithmetic and item 8 corrected as items 69 and 70 |
| pattern | 0 | 7 | Wording, floor-message and boundary items fixed (62, 65, 68, NODRAIN left boundary); naming, stray `;`, helper-list copies and `def NNN` citations not fixed (71, 72) |
| test-design | 7 (no `n` counter; floors on the table not on what ran; row existence; wanted-text controls with empty output; collision dispatch; `ignore` versus `default`; four legs) | many | All seven fixed (65 to 67) with a named FAIL each (below); the P3 survivors fixed or recorded (66, 72 to 74) |
| code-quality | 1 (the same loop-on-one-line limit) | 11 | Fixed; the dead inner `\|\| true` dropped and the outer one pinned by a wire regex; `wire_flr` replaced by one regex per floor NAME and value; the drains-floor text widened; tasks.md 0.3 corrected |
| performance | 1 (the `sh\|return 0; cat >/dev/null` spelling is non-reading only under dash) | 2 | Fixed (63): reproduced rc 1 at `8b43c9df5d`, rc 0 now; the two residual cost items stated in the header |

### Instruments

Four sandboxes from `bash scripts/soleur-sandbox.sh new fixc1` to `fixc4` (git-initialised, control first: the unmutated guard rc 0 in each), the guard under `( ulimit -v 6000000; ... )`. A mutation is one text replacement of the guard file written into a sandbox; **landed** is `filecmp` of the file that ran against the pristine copy (differs), **KILLED** is rc not 0 AND the row's own FAIL text in the output (the harness `mut.py` and registries `reg1.py` to `reg5.py` are in the scratch directory `/var/tmp/s7c/review/c/`, outside the repository). Awk binaries copied out of images and put first on `PATH` as `awk` in a sandbox: mawk 1.3.4 20200120 (`node:22-slim`), mawk 1.3.4 20240123 (`ubuntu:24.04`), BusyBox v1.38.0 (`busybox:latest`), versions asserted (`awk -W version`) before the run; gawk 5.4.1 is the host's. The dash-less run is `env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp` (`command -v dash` is empty there, `/bin/sh` is bash on this host; dash lives in `~/.local/bin`).

### Mutations of this round (final guard; every mutant KILLED with its own text except the equivalent compaction mutant; the unmutated control is rc 0)

| Item | Mutation (one at a time) | Result: the named FAIL |
| --- | --- | --- |
| 1 | the `return 0; cat` spelling put back into `PJ_DRAIN_BAD` | `producer-shell-parity: ... [shbash/ignore return 0; cat >/dev/null][shbash/default ...]` (and, on a dash-less host, `producer-drain-nonreading`) |
| 1 | the shell-parity comparison made trivially true | `producer-hazard-control: [a bash named sh did not tell a top-level return ...]` |
| 4 | `JOINBYTES` 4096 / 8191 / 16384; 8193 | `derivation-fixtures ... [joinbytes-edge-in must derive curl]`; `[joinbytes-edge-out must NOT derive curl]` |
| 4 | the old stop at the cap put back | `[joinbytes-trailing-bar must derive curl]`, `-quote`, `-squote`, `joinbytes-over-tail` |
| 4 | `squeeze` without the double-quote fix / without the single-quote fix / without the pending bar | `[joinbytes-trailing-bar-quote must derive curl]` / `[joinbytes-trailing-bar-squote must derive curl]` / `[joinbytes-trailing-bar must derive curl]` |
| 4 | the end-of-line window without its fallback for 64 trailing blanks | `[join-blanks-bar must derive curl][join-blanks-backslash must NOT derive curl]` |
| 10 | `UNWRAPCAP` 199 / 150 / 201; `JOINCAP` 49 / 6 / 51 | `[wrapcap-edge-in must derive curl]` / `[wrapcap-edge-out must NOT derive curl]`; `[joincap-in must NOT derive curl]` / `[joincap-out must derive curl]` |
| 10 | loop compaction at 40 instead of 32 | SURVIVED (equivalent: only finished entries are dropped; stated in the header, decision 66) |
| 5 | `#[0-9]+` loosened to `*`; the fenced check removed; `blocked-#N` accepted again; a tenth vocabulary word; a fenced row flipped to `unverified`; a fenced row without a number; the zot row's first word changed | `producer-join-judge: ... [no 'must name its tracker issue' ...]`; `[no 'without a vocabulary reason' ...]`; `the closed vocabulary reads [... fenced blocked ]`; `the table holds 1 fenced rows`; `a fenced exempt row must name its tracker issue: ...`; `exempt row without a vocabulary reason: ...zot-image-fetch... cryptsetup` |
| 6a | loop over the first case only; first expectation only; the `n` verdict neutered; the `y` verdict neutered | `the derivation loop read 1 of the table's 102 cases`; `floor cases-y: ... evaluated is 57, the floor is 62`; `derivation-fixtures control: ... [nothing] for a must-NOT-derive ...` and the mirror for `y` |
| 6b | all rows of one driver family deleted (five families), and all at once | `floor judge-fixtures ... is 2, the floor is 22`; `floor rows-fixtures ... 2 ... 11`; `triple-fixtures 2 ... 5`; `count-fixtures 2 ... 9`; `rowcount-fixtures 1 ... 4` |
| 6c | `pj_jc` / `pj_rcc` weakened from "contains the wanted text" to "printed something" | `producer-join-negative-controls: ... [[pj_rcc][pj_tcc][pj_ccc][pj_cntfx]] of [...]` (the weakened driver missing from the list) |
| 6d | `PJ_DEFS_AWK` left out of the lint loop; the call removed; the collision reintroduced in `PJ_AWK` (`bs0` -> `base`); an indented `function zz(t,   indent)` added to `PJ_DEFS_AWK` | `awk-param-collision: ... read from 1 programs (want 2)`; `read from 0 programs`; `[anybar:base]`; `[zz:indent]` |
| 12 | the lint restricted to column-0 headers | `awk-param-collision: ... an indented header ... read as [NOTHING]` |
| 6e | the `ignore` argument never matching; `SIGPIPE` always ignored | `producer-hazard-control: [an unread stub did not give rc 1 under an ignored SIGPIPE and rc 141 under the default disposition: 141 and 141]` / `... 1 and 1` |
| 6f | each of the four legs neutered; each leg's loop cut to its first spelling | `producer-hazard-control: [the dynamic reader leg passed a stub that never reads]` and the three siblings; `floor leg-dyn-ok ... is 2, the floor is 18`, `leg-dyn-bad 2 ... 52`, `leg-det-ok 10 ... 12`, `leg-det-bad 1 ... 26` |
| 11 | the left word boundary of `(echo\|printf\|type\|which\|command -v)` removed; `printf` removed from it; `-[vV]` -> `-v` | `detector disagreements: [accepted spelling not detected: mytype cat >/dev/null][... reprintf ...][... my_echo ...]`; `[non-reading spelling detected as a drain: printf cat >/dev/null]`; `[... command -V cat >/dev/null]` |
| 7 | `pj_floor cases` literal 102 -> 1; every literal -> 1; one floor turned into another; the function neutered | `producer-join-wiring: ... the floors not at column 0 with their listed literal exactly once [...]`; `producer-floor-control: pj_floor exited 0 below its floor (want 1) printing []` |
| 7 | `PJ_FLOOR_DRAINS` 21 -> 1 | `producer-join-wiring: ... the drains-row floor 1 and its value 0` |
| 9 | the outer `\|\| true` of the count-line `read` removed | `producer-join-wiring: ... the read of the count line 0` |
| 9 | a drains row flipped to exempt / made stale / made malformed | `the checker verified 20 drains rows, the floor is 21 — a drains row was flipped to exempt, deleted, gone stale ... or malformed`; plus `stale join row` / `malformed drains row` |
| 8 | `pj_check_counts` compared with `>=` | `producer-join-verdicts: [no 'looked at 306 of the table' for counts that must print it: ][no 'looked at 153 of the table' ...][no 'looked at 154 ...']` |
| 8 | the row counter incremented twice | `the definition checker looked at 300 of the table's 150 rows` and the ROWS-CHECKED fixtures red |
| 13 | the any-producer scan skipped on joined lines; the workflow shell token removed; `"?bash` allowed; the quote-parity test removed; the owner scan made to ignore trailing comments | `[r1r3-any-producer-split must derive curl]` (and four stale rows); `[yml-shell-bash must derive curl][yml-shell-bash-args-overread ...]`; `[yml-shell-quoted-known-miss must NOT derive curl]`; `[r1r3-dq-cmdsub-split-known-miss ...]` with the prose-word pairs; `[owner-trailing-comment-overread must derive curl]` |
| 14 | `json` added to `PJ_EXTS` | `[ext-unlisted-json must NOT derive curl]` |
| 3 | the annotation strip to the end of the line; the annotation strip removed | `[annot-pipe-after must derive jq][annot-cmdsub must derive tr][annot-cmdsub-quoted must derive grep]` (and `PJ_TRIPLES pins 258` against 257); `[annot-cmdsub-hidden must NOT derive head]` (and unlisted pairs) |
| 12 | the same-line loop arm without the stub-helper form | `[loop-sameline-helper must derive curl][... jq]` |
| 2 | `PJ_TRIPLES` 259 | `the derivation found 258 ... triples and PJ_TRIPLES pins 259` |
| (one) | a mutant written with a quote inside the single-quoted awk program | rc 2 (bash syntax error): an invalid mutant, redone as `"?bash` above |

### Stress inputs for the JOINBYTES change (derivation awk alone, 61 lines of 1 MB each ending in ` \` or ` |`, then `printf x | curl -K -`; wall seconds at load 3 to 10; base is the awk of `8b43c9df5d`)

| Shape | Base | Final |
| --- | --- | --- |
| no spaces, ` \` | 0.5 | 0.3 |
| `ab ` repeated (spaces), ` \` | 0.6 | 0.3 (the first form of the change, which copied the whole line to strip its blanks, took 2.6 to 2.9; the end of the line is now stripped from a 64-character window) |
| 87,000 bars per line, ` \` | no end in 250 s | 29 (the last eleven lines are still scanned bar by bar: `anybar`'s quadratic term, stated in the header) |
| no bars, trailing ` \|` | 0.7 | 0.5 |
| 100 bars per line, ` \` | 3.3 | 0.3 |
| 100 bars per line, trailing ` \|` | 3.0 | 0.4 |
| a 9000-character line ending in a bar, its consumer `curl -K -` on the next line | derives nothing | derives `curl` |

The derived triples are unchanged by the change: the sorted triples of the awk before and after are `cmp`-identical (258), under gawk and under mawk 20200120. Other measurements for the header: 64000 bars on a 256 KB line 19 s gawk, 9 s mawk 20200120; 30000 consecutive `for vN in zz; do` lines 5 s gawk, 30 s mawk (the same lines with ONE variable name: 0.9 s gawk, 0.3 s mawk); the corpus 3.4 s gawk, 1.2 s mawk (load 10); longest physical line of the corpus 5903 bytes.

### Final numbers, derived on the tree this section is committed on

* Guard PASS line: `149 derived pairs, 258 producer triples; 21 of 21 drains rows verified by the checker, 129 exempt rows with a vocabulary reason, 150 of 150 rows read`; 150 `JOINED` lines, 12 `DEFERRED` lines; the table holds 2 `fenced` rows. `PJ_TRIPLES=258` (header recipe: `pj_join_pairs | LC_ALL=C sort -u | wc -l` = 258; pairs by `cut -f1,2 | sort -u` = 149).
* `PJ_CASES` 102 cases (62 must-derive and 47 must-not-derive expectations), `PJ_DRAIN_OK` 9, `PJ_DRAIN_BAD` 26 (19 of them sh-tagged with 6 accepted ones: 25 sh-tagged spellings), `PJ_DET_EDGE` 3. The 15 `pj_floor` floors: cases 102, cases-run 102, cases-y 62, cases-n 47, drain-ok 9, drain-bad 26, judge-fixtures 22, rows-fixtures 11, triple-fixtures 5, count-fixtures 9, rowcount-fixtures 4, leg-dyn-ok 18, leg-dyn-bad 52, leg-det-ok 12, leg-det-bad 26; and `PJ_FLOOR_DRAINS=21`. `SWEEP_PROBE_CHECKS=54` (the header recipe counts 54; it was 52 before `producer-shell-parity` and `producer-floor-control`).
* `j0-derive.py` (shipped arms): `BASE 66 pairs, 125 triples`, `U2 +83 pairs, +133 triples over 63 test files`; the U2 sorted triples equal the awk's 258 (`cmp` empty; 149 pairs). The BASE arm set alone gives 125, so the comparison is not trivially empty.
* Header limit figures re-measured on the final tree: ignoring the quote-parity test 258 -> 281 (+23 triples; 12 new pairs, ten prose words and two real, `grep` and `markdown-lint.sh`; nine triples on existing pairs: five `jq`, one `sed`, one `sha256sum`, two `tr`); relaxing the case-pattern exclusion 258 -> 262 (+4 triples, 3 new pairs: `false`, `t`, `write`). The 31 stub definitions of the 21 drains rows (sum of the definitions column) were the ones read for "no drains row relies on a credited non-reader".
* The whole guard, rc 0 with nine PASS lines and no FAIL line, under gawk 5.4.1, mawk 1.3.4 20200120, mawk 1.3.4 20240123, BusyBox v1.38.0 awk, and gawk under `env -i PATH=/usr/local/bin:/usr/bin:/bin` with dash absent. At `8b43c9df5d` the last command gave rc 1 with `producer-drain-nonreading: ... [sh/ignore return 0; cat >/dev/null][sh/default return 0; cat >/dev/null]` (the finding). The new bash constructs (`printf -v` with an indirect name, `[[ =~ $var ]]`, indirect expansion) were also run under real bash 3.2.57 (`bash:3.2`) as fragments; the whole guard under bash 3.2 was not re-run this round (the first fix round's run stands).
* Guard wall time with `taskset -c 0-7`: 9.0 to 10.0 s at load 5.5 to 7 against 5.6 to 6.8 s for `8b43c9df5d` (about 3 s more: 23 more derivation cases, the shell-parity runs, the four legs' counters); at load 13 to 20 the two are within noise (14 to 15 s). The Check-10 cap of 15 s is load-bound, as the performance seat measured; this round uses about 3 s of its quiet-host margin.
* Lints: `shellcheck -S warning -x` on the guard 0 findings; `lint-shell-capture-exit.py --baseline` 0 new findings; `guard-vacuity-floor.test.sh` 23 passed, 0 failed; `lint-orphan-test-suites.sh` none orphaned; `plugins/soleur/test/fixture-relative-assert.test.sh` 62 passed (the same count as at base: no new relative redirect; the file is not under `scripts/`).

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

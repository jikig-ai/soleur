# S7b evidence: J0 measurement of the producer-side join (tracker #9217, Ref only)

Written before any owner suite or the guard was edited (AC-1). Commands: `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7b-producer-join/j0-derive.py`. Base commit of the measurement: `bee2e15b9a` (main at `31ada28352`).

## 0.1 Re-run of the derivation

The re-run output is byte-identical to `j0-plan-time-output.txt` (header block and pair list both diff clean), so main moved nothing that changes the population.

```text
funnel A (verb-free, the property): 60 pairs, 48 test files, 58 non-test files behind them
  by verb: jq 10, cryptsetup 10, curl 9, doppler 7, docker 4, nft 4, timeout 3, gh 3, grep 2, rc 2,
           bc_hmac_sha256_hex 1, tr 1, sha256sum 1, hmac_sha1_b64 1, openssl 1, parse_directive 1
funnel B (the series hand-written registry): 38 pairs, 34 test files (a cross-check, not the population)
```

One row is added that Funnel A cannot derive: `workspaces-luks-verify-workflow.test.sh` with `ssh` (a variable-named stand-in, the stated miss). Rows in total: 61 = 60 derived + 1 recall row. The stale-row check must therefore let a `variable-named-verb` row stand without deriving.

## 0.2 to 0.4 Classification

Method. The reach probe put one marker (`[ -p /dev/stdin ]` then a log write) at the top of each stub definition in a scratch copy under a sandbox from `scripts/soleur-sandbox.sh new`, ran each owner suite once under `timeout 300` and `ulimit -v 6000000` through `run-isolated`, and read the hit log. A hit means a call reached the stub with a pipe or a process substitution on stdin; the probe cannot tell the two apart, so each EXEC row was then read by hand against its producer site. Base-red suites were re-run at the base commit and listed UNVERIFIED (never edited). The markers lived only in the scratch copy and were never committed. Four read-only passes then read every stub definition and its producer site and wrote the table below.

Reproduction tooling, committed beside this file: `j0-stubs.py` (where each verb is stubbed), `j0-sites.py` (the producer pipe sites per pair) and `j0-instrument.py` (the marker insertion, sandbox copy only).

Classes: EXEC (a piped call reaches the stub), TEXT (the suite names the producer but no piped call reaches the stub), UNVERIFIED (suite red or timed out in the isolated run, or a helper-built stub), BLOCKED (red at main, #9956), NOTCMD (the verb is a shell function or a variable, not a stdin-reading command), VARNAMED (verb named through a variable).

| class | pairs |
| --- | --- |
| EXEC | 23 |
| TEXT | 21 |
| UNVERIFIED | 8 |
| BLOCKED | 2 |
| NOTCMD | 6 |
| VARNAMED | 1 |
| total | 61 |

Rows: 18 `drains`, 43 `exempt`.

Exempt vocabulary. The plan fixed six reasons (`not-a-command`, `text-only`, `unverified`, `blocked-#N`, `helper-built-stub`, `variable-named-verb`). Measurement found two shapes none of them names truthfully, so the vocabulary gains two words, recorded in `decision-challenges.md`: `pass-through` (a shim or wrapper that logs and then execs the real binary or the wrapped command, which reads; a leading drain would steal the bytes from it) and `deliberate-fault` (a stub that fails on purpose with a status the stub itself decides).

### Full table

| suite | verb | class | defs | drain state | edit |
| --- | --- | --- | --- | --- | --- |
| .claude/hooks/grep-rewrite.test.sh | jq | EXEC | 2 | never | Y |
| infra/ci-deploy.test.sh | curl | TEXT | 5 | some: 10678,10727 drain via timeout 2 cat (after argv log); 1100,8946,10849 never | N |
| infra/ci-deploy.test.sh | docker | EXEC | 2 | some: 388 drains inside login arm (721 _ltok=$(cat), keyed on --password-stdin, before an… | Y |
| infra/ci-deploy.test.sh | openssl | TEXT | 1 | delegates: 10743 wrapper runs command openssl "$@" (real openssl reads stdin) | N |
| infra/ci-deploy.test.sh | rc | NOTCMD | 0 | - | N |
| infra/ci-deploy.test.sh | tr | EXEC | 1 | never: 8171 FCTR stub is exit 3 as first statement, deliberate fault injection | N |
| infra/cloud-init-inngest-bootstrap.test.sh | docker | BLOCKED | 1 | never: 2004 logs argv, pull arm exit rc, default exit 0, no login arm | N |
| infra/cloud-init-inngest-bootstrap.test.sh | timeout | BLOCKED | 1 | passthrough: 2025 is shift; exec "$@" (stdin goes to the docker stub, which never drains) | N |
| infra/cloud-init-web-zot-seed.test.sh | curl | TEXT | 3 | never: 408 (/v2/ arm exit, arg loop, exit 0), 806 (arg loop, fixture body), 918 (log, exi… | N |
| infra/cloud-init-web-zot-seed.test.sh | timeout | EXEC | 2 | never: 396 (printf >> CALLS; shift; exec "$@"), 926 (printf >> C4_LOG; shift; exec "$@");… | N |
| infra/cron-egress-firewall.test.sh | docker | UNVERIFIED | 2 | never: 1768 (ps/network/exec/exit 0), rbmk docker 'exit 0' (1702, helper-built) | N |
| infra/cron-egress-firewall.test.sh | nft | UNVERIFIED | 2 | some: ga_setup heredoc 1738 never (no -f arm, exit 99); rbmk nft (1703) drains first stat… | N |
| infra/cron-egress-ghcr-probe.test.sh | nft | TEXT | 1 | never: 145 logs argv, exits rc, no -f arm | N |
| infra/cron-egress-nftables.test.sh | nft | EXEC | 1 | -f arm drains (body=$(cat) first statement of the arm, before CEN_STUB_NOLOG branch and e… | Y |
| infra/cron-egress-self-heal.test.sh | nft | UNVERIFIED | 1 | never: 139 dispatches on last arg, nft -f - ends in - so unhandled exit 99 | N |
| infra/cutover-inngest-workflow.test.sh | curl | TEXT | 6 | some: 1077 drains (cat > FLV_CURL_STDIN, 2nd statement after argv write); 841 exit 99 sen… | N |
| infra/fresh-boot-ready.test.sh | curl | TEXT | 1 | --config - arm drains (cat >> $FBR_CAP.stdin) but is the 2nd statement after echo log | N |
| infra/git-data-bootstrap-store-verify.test.sh | cryptsetup | TEXT | 1 | never (stub:431 answers only isLuks; every other argv exit 64 undrained) | N |
| infra/git-data-luks-reopen.test.sh | cryptsetup | EXEC | 1 | all-arms (luksOpen arm: first stmt `cat > $FX/key_seen`; isLuks/status/luksFormat/* arms … | N |
| infra/git-data-root-key.test.sh | curl | EXEC | 1 | all-arms (`cat >/dev/null` is the first statement, unconditional) | N |
| infra/infra-config-apply.test.sh | sha256sum | UNVERIFIED | 4 (1991,2056,… | never (`exit 7`) | N |
| infra/inngest-boot-emitter.test.sh | curl | EXEC | 2 | all-arms keyed (112: drain `_in=$(cat)` in the `-K -` case before any exit; 394: `cat > $… | N |
| infra/inngest-dedicated-host-classify.test.sh | jq | EXEC | 1 | all-arms keyed (loop: `-R` -> `cat >/dev/null; exit 3`; otherwise `exec` real jq, which r… | N |
| infra/inngest.test.sh | curl | TEXT | 2 | never (843: `exit 7`; 1175: s8_curl unquoted heredoc, loops argv, exits without reading) | N |
| infra/luks-monitor.test.sh | cryptsetup | EXEC | 2 (harness 40… | all-arms (both drain right after the record, before any verdict arm, keyed `--key-file -`… | N |
| infra/luks-monitor.test.sh | curl | TEXT | 2 reachable (… | never (739 records and exits; 794 emulates -o/-w, no stdin read) | N |
| infra/registry-luks-escrow.test.sh | cryptsetup | EXEC | 1 | some (luksOpen arm drains via `cat > $KEYSEEN` but only AFTER `[ "$*" = ... ] // exit 64`… | Y |
| infra/resend-inbound-bootstrap.test.sh | doppler | TEXT | 1 | never (logs argv, `exit 0`; unquoted heredoc) | N |
| infra/scripts/sigpipe-triage-feasibility.test.sh | grep | EXEC | 2 | all-arms keyed (`-q` with no file operand: `input=$(cat)` drain; else exec real grep; 127… | N |
| infra/web-ghcr-deny.test.sh | docker | TEXT | 1 | never (pull/image/version/info arms never read stdin) | N |
| infra/web-ghcr-deny.test.sh | timeout | TEXT | 1 | never (`shift; exit 124` or `exec "$@"`) | N |
| infra/workspaces-boot-unlock.test.sh | cryptsetup | EXEC | 1 (+ loop-bui… | all-arms (luksOpen arm: first stmt `cat > $FX/key_seen`; other arms never piped) | N |
| infra/workspaces-luks-freeze.test.sh | cryptsetup | TEXT | 2 (harness 40… | all-arms (harness drains right after rec/printf, keyed `--key-file -`) | N |
| infra/workspaces-luks-rollback-refusal.test.sh | cryptsetup | UNVERIFIED | 2 harness + 1… | all-arms in harness; never in the G5d recorder (asserted `! grep ^cryptsetup`) | N |
| infra/workspaces-luks-rollback-refusal.test.sh | rc | NOTCMD | 0 | - | N |
| infra/workspaces-luks-staging.test.sh | cryptsetup | TEXT | 2 (harness 40… | all-arms (as freeze) | N |
| infra/workspaces-luks-verify-workflow.test.sh | jq | UNVERIFIED | 1 | some (FIXTURE_JQ_BREAK=1 arm exit 3 undrained; else `exec` real jq) | N |
| infra/workspaces-luks-verify-workflow.test.sh | ssh | VARNAMED | 1 (sshstub he… | some (arms `tar xzf` and luks-monitor.sh drain; the latter skipped by FIXTURE_NO_DRAIN=1 … | N |
| infra/zot-disk-heartbeat-redaction.test.sh | cryptsetup | TEXT | 1 (+ cp of th… | never (`status` arm only; any other argv exit 64 undrained) | N |
| plugins/soleur/skills/community/test/community-argv.test.sh | hmac_sha1_b64 | NOTCMD | 1 | - | N |
| plugins/soleur/skills/community/test/community-argv.test.sh | jq | EXEC | 1 | pass-through | N |
| plugins/soleur/test/flag-detach-shared.test.sh | doppler | UNVERIFIED | 1 | never (set arm logs and exits 0 without reading) | N |
| plugins/soleur/test/flag-org-scoping-pr2.test.sh | doppler | UNVERIFIED | 1 | never | N |
| plugins/soleur/test/operator-9321-stages.test.sh | jq | NOTCMD | 1 | pass-through | N |
| plugins/soleur/test/operator-ack-guard.test.sh | doppler | EXEC | 1 | never | Y |
| plugins/soleur/test/operator-digest-provision.test.sh | gh | EXEC | 1 | some (reads in the secret-set arm via cat > gh.stdin, after the argv log line) | Y |
| plugins/soleur/test/operator-script.test.sh | doppler | TEXT | 1 | all-arms for set (stub-world doppler set arm: cat > file) | N |
| plugins/soleur/test/operator-stage-approval-hook.test.sh | doppler | TEXT | 1 | same stub-world | N |
| plugins/soleur/test/operator-stage-approval-hook.test.sh | jq | TEXT | 1 | pass-through | N |
| plugins/soleur/test/ship-followthrough-directive.test.sh | parse_directive | NOTCMD | 1 | - | N |
| scripts/ci-demand-census.test.sh | jq | TEXT | 1 | some (shim L1160: JQ_FAIL_MATCH arm exits 5 undrained; else exec real jq) | N |
| scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh | jq | EXEC | 1 | never (L64: printf '#!/bin/sh\nexit 127\n'; first statement is exit 127) | Y |
| scripts/followthroughs/zot-soak-6122.test.sh | curl | TEXT | 1 | never (heredoc L53-L119, no stdin read in any arm) | N |
| scripts/lint-workflow-local-action-checkout.test.sh | bc_hmac_sha256_hex | NOTCMD | 0 | n/a (no stub; shell function in scripts/lib/bearer-curl.sh) | N |
| scripts/marketplace-drift-check.test.sh | jq | TEXT | 1 | some (L183: has("version") arg arm exit 5 undrained; else exec real jq) | N |
| scripts/rotate-supabase-db-credential.test.sh | doppler | EXEC | 1 | all-arms for the piped arm (L45: `secrets set` arm does `val="$(cat)"` first; other arms … | N |
| scripts/sweep-followthroughs.test.sh | gh | EXEC | 5 | some: L434 yes (`issue comment` arm: cat > file), L704 yes (cat >/dev/null), L816 yes (ca… | Y |
| scripts/watch-registration-narrowing-9564.test.sh | gh | EXEC | 1 | all-arms for the piped arm (L84: `issue comment` arm drains in both branches: cat >/dev/n… | N |
| scripts/web2-rebirth-recovery-check.test.sh | cryptsetup | EXEC | 1 | all-arms for the piped arm (L64: `open` arm does `cat > $LOG/cs-stdin` first; luksUUID/* … | N |
| tests/scripts/test-argv-bearer-sweep.sh | jq | EXEC | 1 | all-arms by delegation (L342 shim: records argv then `exec real jq "$@"` on every path, n… | N |
| tests/scripts/test-git-data-birth-readiness-gate.sh | grep | EXEC | 1 | some (L1318 A18 stub: arg == templatefile shape pattern -> `exit 2` undrained; any other … | N |

## 0.5 Count of suites that need an edit

**8 suites need a stub edit, 3 of them under `apps/web-platform/infra/` and 5 outside it** (EXEC and not draining as the first statement of every definition). There is no gate on the number; Phase 2 commits non-infra first and infra second.

| suite | verb | defs | flag token | what the edit is |
| --- | --- | --- | --- | --- |
| .claude/hooks/grep-rewrite.test.sh | jq | 2 | `*` | two one-line printf writes (exit 1; echo then exit 0), neither reads; producer: printf OUT / jq -e . (status observed); 285x4 hits |
| infra/ci-deploy.test.sh | docker | 2 | `--password-stdin` | positional pin: hoist token capture to first statement in 388 (arm needs the token value) and add a drain to 9809 |
| infra/cron-egress-nftables.test.sh | nft | 1 | `-f` | positional pin: hoist the -f drain above st=/printf |
| infra/registry-luks-escrow.test.sh | cryptsetup | 1 | `--key-file -` | fix: add a keyed drain (`case " $* " in *" --key-file - "*) cat > "$KEYSEEN" ;; esac`) before the argv guard / case; consumer sits behind `timeout 12… |
| plugins/soleur/test/operator-ack-guard.test.sh | doppler | 1 | `secrets set` | stub: log line, secrets get arm, exit 0; never reads; 380x69 hits |
| plugins/soleur/test/operator-digest-provision.test.sh | gh | 1 | `secret set` | reads correctly but not as first statement; edit = move the keyed read above the log line |
| scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh | jq | 1 | `*` | producer .sh:60/63/64/93 `printf '%s' "$X" / jq` under set -uo pipefail; reached 1x via L60. Exit 127 is the rightmost non-zero member so pipefail st… |
| scripts/sweep-followthroughs.test.sh | gh | 5 | `--body-file -` | producers sweep-followthroughs.sh:469,672,828,907 `printf '%s' "$msg" / gh issue comment ... --body-file -` under set -euo pipefail. Hits 434x1335 70… |

Pairs whose stub already drains correctly inside the consuming arm, but not as its first statement, are `drains` rows with edit N above only where the guard accepts the arm form; whether the positional pin accepts them as written is what the first red run in Phase 1 measures, and any that it rejects are hoisted in the same commit as the others.

## Draft PRODUCER_JOIN rows

```text
.claude/hooks/grep-rewrite.test.sh | jq | drains | 2 | *
apps/web-platform/infra/ci-deploy.test.sh | curl | exempt | text-only derived sites cloud-init-inngest.yml:336,426 are grep-pinned only; ci-deploy.sh:378 feeds --config - via < <(printf) not a pipe
apps/web-platform/infra/ci-deploy.test.sh | docker | drains | 2 | --password-stdin
apps/web-platform/infra/ci-deploy.test.sh | openssl | exempt | text-only derived sites scripts/cutover-inngest.sh:1372,1546 not executed here; fan_out no longer calls openssl
apps/web-platform/infra/ci-deploy.test.sh | rc | exempt | not-a-command rc is a variable written by printf > $d/rc, no stub exists
apps/web-platform/infra/ci-deploy.test.sh | tr | exempt | deliberate-fault stub exits 3 on purpose; pipeline status is the second tr, decided by the stub, not by a write race
apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | docker | exempt | blocked-#9956 suite red at origin/main
apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | timeout | exempt | blocked-#9956 suite red at origin/main
apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | curl | exempt | text-only derived sites cloud-init-inngest.yml:336,426 not executed; hits 806x11 are < <(printf) in scripts/fresh-host-boot-trail.sh:94,263
apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | timeout | exempt | pass-through wrapper logs then execs the wrapped command, which reads
apps/web-platform/infra/cron-egress-firewall.test.sh | docker | exempt | text-only derived sites are apply-web-platform-infra.yml docker login lines, grep-pinned; resolve.sh:305 docker exec -i not reached (container absent in RB run)
apps/web-platform/infra/cron-egress-firewall.test.sh | nft | exempt | helper-built-stub the RB resolver run pipes echo|nft -f - into rbmk-built stub (compliant, first stmt drains); the heredoc 1738 only serves ASSERT_SCRIPT (no pipe)
apps/web-platform/infra/cron-egress-ghcr-probe.test.sh | nft | exempt | text-only suite extracts only the GHCR probe fn and constants; resolve.sh:492 apply is not run
apps/web-platform/infra/cron-egress-nftables.test.sh | nft | drains | 1 | -f
apps/web-platform/infra/cron-egress-self-heal.test.sh | nft | exempt | text-only suite extracts enforcement_probe/enforcement_extra and the self-heal block only; resolve.sh:492 not extracted
apps/web-platform/infra/cutover-inngest-workflow.test.sh | curl | exempt | text-only the hits are process substitutions; the one executed pipe (cutover-inngest.sh:557) is invisible to the join and its stub drains
apps/web-platform/infra/fresh-boot-ready.test.sh | curl | exempt | text-only the derived site is only text-pinned; the executed pipe (soleur-host-bootstrap.sh:1062) runs without pipefail
apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh | cryptsetup | exempt | text-only luksOpen pipe site git-data-bootstrap.sh:102 is outside the extracted store-verify unit; stub answers isLuks only
apps/web-platform/infra/git-data-luks-reopen.test.sh | cryptsetup | drains | 1 | --key-file -
apps/web-platform/infra/git-data-root-key.test.sh | curl | drains | 1 | -H @-
apps/web-platform/infra/infra-config-apply.test.sh | sha256sum | exempt | text-only sha256sum is the pipe producer with a file operand at infra-config-apply.sh:489,512; no stdin is piped into it
apps/web-platform/infra/inngest-boot-emitter.test.sh | curl | drains | 2 | -K -
apps/web-platform/infra/inngest-dedicated-host-classify.test.sh | jq | drains | 1 | -R
apps/web-platform/infra/inngest.test.sh | curl | exempt | text-only the probe body under test never pipes into curl; both stubs ignore stdin
apps/web-platform/infra/luks-monitor.test.sh | cryptsetup | drains | 2 | --key-file -
apps/web-platform/infra/luks-monitor.test.sh | curl | exempt | text-only no producer pipes into curl in luks-monitor.sh or workspaces-luks-emit.sh
apps/web-platform/infra/registry-luks-escrow.test.sh | cryptsetup | drains | 1 | --key-file -
apps/web-platform/infra/resend-inbound-bootstrap.test.sh | doppler | exempt | text-only step 4 pipe (resend-inbound-bootstrap.sh:252) is unreachable: the curl shim returns an empty domain list so step 1 exits first
apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh | grep | drains | 2 | -q
apps/web-platform/infra/web-ghcr-deny.test.sh | docker | exempt | text-only the shim only sees `timeout 120 sudo docker pull` with no piped stdin
apps/web-platform/infra/web-ghcr-deny.test.sh | timeout | exempt | text-only no pipe feeds the timeout shim here (cloud-init-registry.yml:2085 is not run)
apps/web-platform/infra/workspaces-boot-unlock.test.sh | cryptsetup | drains | 1 | --key-file -
apps/web-platform/infra/workspaces-luks-freeze.test.sh | cryptsetup | exempt | text-only no piped call observed; the sourced harness stubs drain
apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | cryptsetup | exempt | unverified suite exits 2 in the isolated run (finds no block device); the sourced harness stubs drain
apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | rc | exempt | not-a-command rc is the f6() stub-exit-code parameter (F6_RC), not a command
apps/web-platform/infra/workspaces-luks-staging.test.sh | cryptsetup | exempt | text-only no piped call observed; the sourced harness stubs drain
apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | jq | exempt | text-only the stub is on PATH only for the web2_marker g3 sandbox, whose judge reads file operands, never a pipe
apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | ssh | exempt | variable-named-verb workflow calls ${WEB_HOST_SSH}, bound to the sshstub stand-in; arms drain for luks-monitor.sh and tar xzf
apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh | cryptsetup | exempt | text-only the heartbeat only runs `cryptsetup status`; luksOpen pipes (cloud-init-registry.yml:1968,2085,2446) are outside the rendered heartbeat
plugins/soleur/skills/community/test/community-argv.test.sh | hmac_sha1_b64 | exempt | not-a-command shell function in scripts/lib/hmac-sha1-b64.sh
plugins/soleur/skills/community/test/community-argv.test.sh | jq | exempt | pass-through shim: logs argv then execs the real jq, which reads (its one exit-5 arm is the unpiped createSession program)
plugins/soleur/test/flag-detach-shared.test.sh | doppler | exempt | unverified suite fails at base under the isolated run (rc1 at 21s); stub set arm never reads
plugins/soleur/test/flag-org-scoping-pr2.test.sh | doppler | exempt | unverified suite fails at base under the isolated run (rc1 at 15s); stub set arm never reads
plugins/soleur/test/operator-9321-stages.test.sh | jq | exempt | pass-through shim in lib/operator-stub-world.sh: logs then execs the real jq
plugins/soleur/test/operator-ack-guard.test.sh | doppler | drains | 1 | secrets set
plugins/soleur/test/operator-digest-provision.test.sh | gh | drains | 1 | secret set
plugins/soleur/test/operator-script.test.sh | doppler | exempt | text-only no piped call observed (rc0 158s); the shared stub-world doppler set arm reads
plugins/soleur/test/operator-stage-approval-hook.test.sh | doppler | exempt | text-only no piped call observed (rc0 12s)
plugins/soleur/test/operator-stage-approval-hook.test.sh | jq | exempt | text-only no piped call observed (rc0 12s); stub-world jq is a pass-through exec
plugins/soleur/test/ship-followthrough-directive.test.sh | parse_directive | exempt | not-a-command shell function in scripts/sweep-followthroughs.sh
scripts/ci-demand-census.test.sh | jq | exempt | text-only no piped jq in scripts/ci-demand-census.sh (every jq reads a file operand); the ci.yml sites in sites.txt are fixture names, not exercised
scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh | jq | drains | 1 | *
scripts/followthroughs/zot-soak-6122.test.sh | curl | exempt | text-only no '| curl' producer: soak feeds --config - via `< <(printf ...)` process substitution (zot-soak-6122.sh:274-276) whose writer status is never observed
scripts/lint-workflow-local-action-checkout.test.sh | bc_hmac_sha256_hex | exempt | not-a-command shell function sourced from scripts/lib/bearer-curl.sh, the suite only lints track.sh text
scripts/marketplace-drift-check.test.sh | jq | exempt | text-only the checked step (scheduled-marketplace-drift.yml check) reads jq stdin by here-string `<<<` only, no '| jq'
scripts/rotate-supabase-db-credential.test.sh | doppler | drains | 1 | *
scripts/sweep-followthroughs.test.sh | gh | drains | 5 | --body-file -
scripts/watch-registration-narrowing-9564.test.sh | gh | drains | 1 | --body-file -
scripts/web2-rebirth-recovery-check.test.sh | cryptsetup | drains | 1 | --key-file=-
tests/scripts/test-argv-bearer-sweep.sh | jq | exempt | pass-through shim records argv then execs the real jq on every path
tests/scripts/test-git-data-birth-readiness-gate.sh | grep | exempt | pass-through shim execs the real grep; its exit-2 fault arm is reached only through a here-string since #9210, so no pipe reaches it
```

## Observations that change the work

- Most `curl` hits (every one for ci-deploy and cloud-init-web-zot-seed, and four of the six in cutover-inngest-workflow) come from process substitution (`curl ... < <(printf ...)`), not a pipeline, so no pipeline status is observed there. Those pairs are TEXT rows.
- The one executed pipe in cutover-inngest-workflow is `printf | ( ... curl -H @- )` (cutover-inngest.sh:557). The join reads the word after the pipe, which is `(`, so it cannot see it. Stated limit; the serving stub already drains.
- `sites.txt` style lists are tree-wide, not per suite. Each pair was judged against what its suite actually executes; several derived producers are only text-pinned by their suite.
- Suites that were red or timed out in the isolated run at the base commit are UNVERIFIED rather than edited: flag-detach-shared and flag-org-scoping-pr2 (fail before reaching the stub), operator-9321-stages, infra-config-apply, workspaces-luks-verify-workflow, workspaces-luks-rollback-refusal (exits 2: it finds no block device and refuses to run), and the cron-egress firewall and self-heal suites. `cloud-init-inngest-bootstrap.test.sh` is BLOCKED by #9956 and is not edited.
- `test-git-data-birth-readiness-gate.sh` passed on its long run (259 assertions, 264 s) after two 300 s timeouts; `test-argv-bearer-sweep.sh` was red once on tracked-file census checks and green on a rerun (651 assertions). Neither red is about a stub.
- `sweep-followthroughs.test.sh` has four T18 failures in the isolated run (the sourced script runs `gh repo view` at source time with no network); the other assertions pass and the hits are valid, so the pair stays EXEC. Its fifth stub definition (line 99) is a loud safety net no case reaches.
- Two stubs are shims that exec the real tool (`jq` in test-argv-bearer-sweep.sh and the stub-world `jq`, `grep` in the birth-readiness suite). A leading drain would consume the bytes the real tool must read, so they are `pass-through` rows, not `drains` rows.
- Shell hazard of the probe itself: a command text containing a literal `secrets set` is refused by a pre-tool hook; any scripted pass over the doppler stubs must not spell it in a command line.

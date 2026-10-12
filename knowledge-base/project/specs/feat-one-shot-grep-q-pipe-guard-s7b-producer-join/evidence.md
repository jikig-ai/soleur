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
| plugins/soleur/test/…-ack-guard.test.sh | doppler | 1 | `secrets set` | stub: log line, secrets get arm, exit 0; never reads; 380x69 hits |
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


## Phase 1 to 6 results (appended; Ref #9217)

### Red first (Phase 1)

First run of the guard with the derivation and an empty `PRODUCER_JOIN` table, from a clean checkout under `ulimit -v 6000000`: rc 1 with 60 lines `FAIL: unlisted pair: <suite> stubs '<verb>' and names a non-test file that pipes text into it`, one per derived pair (the first is `.claude/hooks/grep-rewrite.test.sh` with `jq`). Output kept in the session scratchpad as `guard-red1.out`. With the 61 rows filled in the guard passes: `PASS: grep-q-producer-join (60 derived pairs; 13 drains rows verified, 48 exempt rows with a vocabulary reason)`, plus one `JOINED:` line per row and one recall row.

### AC-4: the bash derivation against J0

The bash/awk derivation `pj_join_pairs` yields the same 60 (test file, verb) pairs as `j0-derive.py` (`j0-plan-time-output.txt`). Where the Python measurement and the awk derivation could differ, the awk derivation is authoritative; they did not differ on this tree.

### AC-6: pair runs at base and head (same machine)

Base is `31ada28352b0`. Head is the branch tip. "Serial" means one run at a time with nothing else of mine running; the host carried other sessions (load average 10 to 40), so the parallel-era runs include load flakes on both sides.

| Suite | Base | Head | Reading |
|---|---|---|---|
| apps/web-platform/infra/ci-deploy.test.sh | serial base2, base3: 565 pass, 2 fail (rc 1) | serial head3, head4: 565 pass, 2 fail (rc 1) | Identical. The two failures are the `inngest-server` start-writer inventory (`git grep` rc 128, the isolated sandbox has no `.git`) and the assertion-count floor that follows from it; both fail at base. Earlier runs under load differed (base 564/3, head 564/3, head2 563/4: the extra two are timing assertions) and are load flakes, not a head effect. |
| apps/web-platform/infra/cron-egress-nftables.test.sh | rc 0 | rc 0 (head2) | The first head run was rc 1 with 16 failures: the stub's `PATH` has no `timeout`, so the new `timeout 2 cat` drain was not found. The stub now drains with `cat` alone; head2 is rc 0. |
| apps/web-platform/infra/registry-luks-escrow.test.sh | rc 0, 52 pass | rc 0, 52 pass | Identical. |
| plugins/soleur/test/operator-ack-guard.test.sh | rc 0 | rc 0 | Identical. |
| plugins/soleur/test/operator-digest-provision.test.sh | rc 0 | rc 0 | Identical. |
| scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh | rc 0, 34 pass | rc 0, 34 pass | Identical. |
| scripts/sweep-followthroughs.test.sh | rc 1, 277 pass, 8 fail | rc 1, 277 pass, 8 fail | Identical failing set (the `gh repo view` call at source time has no network in the isolated run). |
| .claude/hooks/grep-rewrite.test.sh | rc 0, 71 pass | rc 0, 71 pass | Identical. |
| scripts/rotate-supabase-db-credential.test.sh | rc 0, 17 cases, 0 failures | rc 0, 17 cases, 0 failures | Identical (this stub was edited after the battery, see below). |

`git diff --stat` for each edited suite shows only the three kinds of edit (a keyed drain as the stub's first statement, the capture moved there, a wire assert); a search of the added lines for a reach-probe marker finds none. `cloud-init-inngest-bootstrap.test.sh` is untouched (red at base, #9956).

### AC-7: mutation and harness battery

Every row ran one at a time in a scratch worktree under `ulimit -v 6000000`, against the committed guard at the commit named below. The guard's own mutants only read; none of the rows executes an owner suite. Grades are from the harness (`results.json`), re-read by hand for M2 and M12.

| Row | Mutation | Expected | Result | Grade |
|---|---|---|---|---|
| M1 | new producer into gh plus a new suite that stubs gh and names it | RED expected | rc 1 | RED-AS-EXPECTED |
| M2 | second member: another suite that stubs an already-listed verb and names an already-listed producer | RED expected | rc 1 | RED-AS-EXPECTED |
| M3 | delete one row and leave its pair | RED expected | rc 1 | RED-AS-EXPECTED |
| M4 | keep a row whose stub was renamed in its suite | RED expected | rc 1 | RED-AS-EXPECTED |
| M5 | own dispatch: the listing returns nothing | RED expected | rc 3 | RED-AS-EXPECTED |
| M6 | narrow the stub detector: drop the stub-helper-call arm | RED expected | rc 1 | RED-AS-EXPECTED |
| M7 | narrow the stub detector: drop the function-definition arm | RED expected | rc 1 | RED-AS-EXPECTED |
| M8 | narrow the stub detector: drop the sourced-file hop | RED expected | rc 1 | RED-AS-EXPECTED |
| M9 | narrow the text-pipe pattern: drop echo producers | RED expected | rc 1 | RED-AS-EXPECTED |
| M10 | drop the status of the one site behind a single-site pair | RED expected | rc 1 | RED-AS-EXPECTED |
| M11 | delete the drain from one compliant stub | RED expected | rc 1 | RED-AS-EXPECTED |
| M12 | REORDER: the drain moved below the first dispatch | RED expected | rc 1 | RED-AS-EXPECTED |
| M13 | second member: a second definition with no drain after a compliant one | RED expected | rc 1 | RED-AS-EXPECTED |
| M14 | the drain left only in a comment | RED expected | rc 1 | RED-AS-EXPECTED |
| M15 | remove the flag token and keep an unconditional cat | RED expected | rc 1 | RED-AS-EXPECTED |
| M16 | own dispatch: the definition opener renamed so the finder sees zero | RED expected | rc 3 | RED-AS-EXPECTED |
| M17 | an exempt row whose reason is outside the vocabulary | RED expected | rc 1 | RED-AS-EXPECTED |
| M17b | an exempt row with an empty reason | RED expected | rc 1 | RED-AS-EXPECTED |
| M18 | make the control stub drain | RED expected | rc 1 | RED-AS-EXPECTED |
| M19 | shrink the payload to a few bytes (the timing-dependent shape; there is no sentinel in this design) | RED expected | rc 1 | RED-AS-EXPECTED |
| M20 | add a non-reading spelling to the accepted array | RED expected | rc 1 | RED-AS-EXPECTED |
| M21 | own dispatch: empty the accepted array | RED expected | rc 1 | RED-AS-EXPECTED |
| H1 | delete the recall check tail | RED expected | rc 1 | RED-AS-EXPECTED |
| H3 | opener finder accepts only a function opener | RED expected | rc 3 | RED-AS-EXPECTED |
| H5 | delete the dynamic control tail | RED expected | rc 1 | RED-AS-EXPECTED |
| H2a | a suite naming a listed producer only in a comment derives no pair | PASS expected | rc 0 | PASS-AS-EXPECTED |
| H2b | a row with extra whitespace around the separators parses | PASS expected | rc 0 | PASS-AS-EXPECTED |
| H2c | a suite naming xs7b-h2c.sh does not become an owner of s7b-h2c.sh | PASS expected | rc 0 | PASS-AS-EXPECTED |
| H4 | the flag spelled with [[ ]] instead of case still counts as a keyed drain | PASS expected | rc 0 | PASS-AS-EXPECTED |
| H6 | a [[ ]] spelling tagged sh fails the dynamic run (a bash-tagged spelling is not exercised under sh) | RED expected | rc 1 | RED-AS-EXPECTED |

M2 (a second new producer for a stub already in a listed pair) and M12 (the drain moved below the first dispatch arm) both read RED. H1 and H5 go RED through the probe-count pin, which is the intended net for a deleted check; their own check lines are what the count protects. M19 differs from the S7a design because this guard has no sentinel: the control writes 1 MiB and needs none.

H3 was UNVERIFIED in the first battery run (its harness anchored a string that occurs twice in the guard) and was repaired and re-run, so it is graded above.

#### What the battery found, and the fix

1. M11 and M14 (delete the drain, or leave it only in a comment, in the wildcard-keyed `curl` stub of git-data-root-key) first read WRONG, rc 0. The definition finder counted the opener line `cat > "$STUB/curl" <<'SH'` itself as a drain, because a `*` flag token is "seen" from the first line. The finder now strips the opener's own heredoc writer before testing for a drain. Both rows then read RED.
2. H6 (a bash-only spelling tagged `sh`) first read WRONG on this host, where `/bin/sh` is bash. The dynamic run now runs `sh`-tagged spellings under `dash` when the host has it (CI's `/bin/sh` is dash), else under `/bin/sh`. H6 then reads RED.
3. Fix 1 exposed one real stub: the `doppler` stub in `scripts/rotate-supabase-db-credential.test.sh` read stdin only inside its `secrets set` arm. It now drains first, keyed on the set subcommand, and the row pins that token instead of `*` (pair run above).
4. Two cheap scans in the derivation are now gated on a substring (an extension for the token scan, a producer word for the pipe scan). The derivation and the 61 `JOINED:` lines are byte-identical before and after.

The full battery was re-run after each guard change; the table is the run at the final guard commit.

### AC-8: the dynamic control

Control stub (`:`, never reads) fails the pipeline in all four cases (SIGPIPE ignored and default, `sh` stub and bash stub): a producer writing 1 MiB takes SIGPIPE (141) or EPIPE (rc 1). Each accepted spelling (7) passes under the interpreter it is tagged for, in both dispositions; each non-reading spelling (5) fails in both; the detector shared with the positional pin agrees on every spelling. `producer-drain-zero` requires the run count to equal 2 x (accepted + non-reading) with both lists non-empty, so zero spellings is never a pass (M21 reads RED).

### AC-9: lints

| Lint | Result |
|---|---|
| `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` | 0 new findings, 224 baselined |
| `bash scripts/guard-vacuity-floor.test.sh` | 23 passed, 0 failed |
| `bash scripts/lint-orphan-test-suites.sh` | 663 covered, 0 orphaned |
| `python3 scripts/lint-guard-contract.py` on the plan | 1 plan with a Guard Contract, 3 guard entries, rc 0 |
| `bash scripts/test-affected-kb-consumers.test.sh` (once, before the push) | First run: 21 passed, 2 failed (cases 2 and b1). The guard's table names three suites whose bodies, one hop away, name knowledge-base files (`followthrough-convention.md`, `inngest-server.md`, and a spec `bootstrap.sh`); the guard reads none of them. The gate's own regeneration (`--write-baseline`) added exactly those three rows to `scripts/test-affected-kb-consumers.baseline.txt`, as it already holds six rows for this guard. Re-run after: 23 passed, 0 failed. After merging main (see the merge section below) the same regeneration added one more row, for `ADR-136-preapply-entrypoint-enumeration-gate.md`, named one hop away by `test-preapply-entrypoint-gate.sh`; 23 passed, 0 failed again. |
| `shellcheck -S warning`, base vs head, guard and each edited suite | unchanged (ci-deploy 19 and 19, operator-ack-guard 1 and 1, rotate-supabase 2 and 2, the rest 0 and 0) |

### AC-10: probe count and wall time

`SWEEP_PROBE_CHECKS` is 45: the S7a count was 36 (recomputed from `origin/main` with the header recipe), and this change adds 9 checks. The header recipe, run on the branch, prints 45.

The derivation reads files with one `git ls-files` listing plus one `git ls-files -z` pass and one awk run (one token set per test file); there is no per-pair scan of the corpus. Cost, measured on a host carrying other sessions' load:

| Measure | Base guard | Head guard | Load average at the time |
|---|---|---|---|
| wall, plain, 2 runs | 3.6 and 3.7 s | 10.4 and 10.0 s | 12 |
| wall, plain, 3 runs | | 20.6, 19.6, 20.9 s | 37 to 40 |
| wall, Check 10-shaped read-only bwrap, 3 runs | | 19.2, 20.3, 18.8 s | 38 to 40 |
| CPU (user+sys), interleaved | 14.6 and 14.3 s | 23.1 and 23.2 s | 33 |

Reading: the join adds about 6 s wall when the host is quiet-ish and about 9 CPU seconds, almost all in the one derivation awk (it reads about 42 MB over 1,699 tracked files). Under the host's heavy load the 15 s preflight cap is not met by wall time, and the base guard's own time doubles with it. This is recorded as context, not a gate, as AC-10 says; the larger-than-planned cost (the plan expected about 1.4 s extra) is listed in the NOT-fixed list as a follow-on (a per-file map step, or starting the derivation before the sweep so the two overlap).

### Merge with main (21 commits after the base)

The pre-push ratchet lane runs the guard on the branch merged with current main, and went RED there: main's apply workflow now carries three `::error::` echo strings that show the operator a `printf ... | curl` command, which the derivation reads as a text producer. Eleven suites that stub `curl` and name that workflow therefore derived a pair the branch had not seen (guard output: 11 `FAIL: unlisted pair` lines, all verb `curl`). The guard did what it is for. Main is merged into the branch; each of the 11 is an `exempt` row with the `text-only` reason (a quoted echo is not an executed pipe; the workflow has no other `| curl` producer line). The derived set is now 71 pairs (60 plus 11), 13 `drains` rows verified, 59 `exempt` rows. The battery (all 30 rows) was re-run at the merged tip `e67d50275e` with the same grades as the table above: M1 to M21, M17b, H1, H3, H5 and H6 RED as expected, H2a, H2b, H2c and H4 PASS as expected.

### Ratchet lane on the merged tip

`bash scripts/pre-push-ratchet-lane.sh` on the branch merged with main: 21 of 22 members PASS, including the guard, the kb-consumer ratchet and every edited suite that is a member. The one non-pass is `ci-deploy.test` with verdict TIMEOUT at the lane's 300 s cap (no failing assertion in its log). The same suite run directly on the merged tip, alone: `609/609 passed, 0 failed`, rc 0, 248 s. At base it took 233 to 269 s in the pair runs, so the suite sits near the lane's cap on a host carrying other sessions' load (load average 11 to 20 during these runs); the edit adds one `case` line to a stub and no measurable time.


## Review round 1 (appended; Ref #9217)

Nine report-only seats reviewed PR #9985 at `d8b85f8fe7` (git history, pattern, architecture, security, code quality, performance, test design with mutation, structural enumeration, simplicity). Risk tier none (plan scope-out), class code, no design-risk pass. No P1; the P2 findings were fixed inline, the rest is recorded below and in `decision-challenges.md` items 15 and 16.

Corrections to the record above (a dated record is corrected by appending; the one in-place edit is wording only, a path in the AC-6 classification table abbreviated and one phrase in `decision-challenges.md` item 9 reworded so that `scripts/lint-infra-no-human-steps.py` passes on this branch): the vocabulary gained three words, not two (`pass-through`, `deliberate-fault`, `arm-drain`); nine suites are edited, not eight; the J0 counts of 18 `drains` and 43 `exempt` rows at `:36` are the plan-time classification, and the guard that merged carries 13 and 49 after the annotation change below; the reproduction scripts `j0-stubs.py`, `j0-sites.py` and `j0-instrument.py` named at `:22` are removed (recoverable from commit `6e320b391e`; `j0-derive.py` and its output stay); `#7797` and `#9482` in the plan are issues named in the brief, not trackers of this series (`#7797` is an unrelated credential-printing issue, `#9482` a merge-queue decision record); `cloud-init-inngest-bootstrap.test.sh` is exempt as `blocked-#9956` on the strength of the #9217 comment `issuecomment-6103531873` (2026-10-10), which lists it among the main reds tracked by #9956; #9956's own body names only the privileged-tier census row.

### What the review found that the author battery had not

- The drain detector accepted `cat < FILE`, a cat on the right of a pipe, a cat behind `true ||`, a non-negated tty test and a backgrounded cat; none was in the non-reading list. It now excludes them, and the five spellings are in the list the dynamic control runs.
- The pin window crossed into the next definition, ignored a bare `exit` ahead of the drain, and matched the flag token inside a trailing comment. It is now bounded at the next definition of the verb, disarmed by a bare exit or return, and reads the code part of the line.
- The operator-ack-guard doppler stub called `timeout`, which the suite's sandbox `PATH` does not carry: the drain never ran there. Fixed (plain `cat` fallback).
- The table verdicts and the verdict sink had no negative control: neutering a `PJ_FAIL=1` assignment printed FAIL and exited 0. The verdicts moved into `pj_judge` (driven with one-row fixtures), and the sink (`pj_fail`, the judge merge, the column-0 fold) is pinned by text.
- A new producer of an already-listed pair needed no row. `PJ_TRIPLES` now pins the (test file, verb, producer file) count (113).
- Annotation echoes (`::error::` and friends) were read as pipes: ten `text-only` rows existed only for that. The scan skips them (pairs 71 to 61, rows 72 to 62); one row's reason named the wrong producer and is corrected; seventeen reasons that had been cut mid-word are restored.

### Rows added to the battery (all at the fixed guard, `e949471417`)

| Row | Mutation | rc | Grade |
|---|---|---|---|
| N1 | the detector accepts cat < FILE again | rc 1 | RED-AS-EXPECTED |
| N2 | NODRAIN loses its pipe and background alternatives | rc 1 | RED-AS-EXPECTED |
| N3 | the window is no longer bounded at the next definition | rc 1 | RED-AS-EXPECTED |
| N4 | a bare exit ahead of the drain no longer disarms it | rc 1 | RED-AS-EXPECTED |
| N5 | NODRAIN loses its heredoc alternative: the opener-line heredoc writer counts as a drain again | rc 1 | RED-AS-EXPECTED |
| N6 | a trailing comment counts as code again | rc 1 | RED-AS-EXPECTED |
| N7 | pj_fail prints FAIL and no longer sets the flag | rc 1 | RED-AS-EXPECTED |
| N8 | the judge merge prints its FAIL lines and no longer sets the flag, with a real unlisted pair present | rc 1 | RED-AS-EXPECTED |
| N9 | the column-0 fold into FAIL is neutered, with a real unlisted pair present | rc 1 | RED-AS-EXPECTED |
| N10 | the unlisted-pair verdict is neutered | rc 1 | RED-AS-EXPECTED |
| N11 | the vocabulary verdict is neutered | rc 1 | RED-AS-EXPECTED |
| N12 | the producer-triple pin is off by one | rc 1 | RED-AS-EXPECTED |
| N13 | a new producer of an already-listed exempt pair (ci-deploy | curl) | rc 1 | RED-AS-EXPECTED |
| N14 | a variable-named-verb row whose suite no longer exists | rc 1 | RED-AS-EXPECTED |
| N15 | a bare exit ahead of a real stub drain (A1) | rc 1 | RED-AS-EXPECTED |
| N16 | the flag token only in a trailing comment of a real stub (A2) | rc 1 | RED-AS-EXPECTED |
| N17 | a real stub reads only on a terminal (A3) | rc 1 | RED-AS-EXPECTED |
| N18 | a real stub redirects its drain from /dev/null (A4) | rc 1 | RED-AS-EXPECTED |
| N19 | a real stub loses its drain and the next stub writer falls into its window (A6) | rc 1 | RED-AS-EXPECTED |

The whole battery was re-run at that commit: 49 rows, 45 RED as expected, 4 PASS as expected (M1 to M21 and M17b, H1, H3, H5, H6 and N1 to N19 red; H2a, H2b, H2c, H4 green). Four earlier rows changed meaning and were re-aimed rather than left to pass for a new reason: M16 (an opener renamed so the pair no longer derives is now reported as a stale row, which is the correct reading), N3 (the first bounded-window fixture was masked by the exit rule), N5 (the opener-line strip proved redundant once the non-drain pattern excludes heredoc writers, so the strip is deleted and the row mutates that pattern) and N15 (the mutation was not the shape the finding described).

### Not fixed in this PR

- Derivation recall: a pipe split over lines by a trailing backslash or pipe (the reviewers measured about 24 further pairs, 15 of whose stubs have no drain within 60 lines), a verb behind `timeout`/`env`/`command`, a producer other than printf/echo/cat, a library pipe with no pipefail token of its own (16 pairs when forced on), helper-with-argument and loop-built stubs (five suites seen by no pair), and producers in `.tf` or extensionless files. Each pair needs a reach classification before it can be a row, which is a slice of its own; the limits are listed in the guard header and the slice is named on the tracker.
- `arm-drain`, `pass-through`, `text-only` and `blocked-#N` reasons remain attestations checked for their first word.
- Guard wall time: the derivation still reads about 42 MB. A grep prefilter (about 1.3 to 2 s) and a background start overlapping the sweep (about 2.4 to 4 s) were measured by the performance seat to be byte-identical in output, and are not applied: the first couples a bash regex to the awk predicates, the second adds a background job to a guard that pins its own control flow by text. The single-awk `pj_sourced` and the `read`-based row split (about 600 fewer forks) are applied. This host carries other sessions' load (load average 35 to 65 during the re-measurement), so an end-to-end figure is not resolvable here.
- No ADR for the guard architecture yet; awk operands shaped like `name=...` and symlinked tracked files need commit rights and exist nowhere in the tree.

### Verification pass over the round-1 fixes (one fresh seat, two attempts)

The first verifier stopped answering after about two hours (its transcript stopped moving; it was not resumable); a second, smaller brief returned with no P1 or P2 and five P3 items. Three were fixed inline: the double-bracket non-negated tty test reads as a non-drain (a spelling added to the non-reading list), the annotation filter strips the text after the annotation token instead of skipping the line (so a pipe before it on the same line is still derived; a pipe inside the annotation text is a stated limit), and the status grade is one helper (`pj_unread`) with a negative control plus an exit-3 stub driven to prove the status surfaces. Left as they are, with the reason: false rejects of unusual drains (`cat -`, `dd if=/dev/stdin`, a one-line `printf '...\ncat...'` stub) fail closed with the hint that names the accepted form; the unbounded `cat` in the operator-ack-guard fallback applies only on a host with no `timeout` and an inherited open stdin.

Rows added: N20 (the double-bracket tty alternative removed, red through the non-reading list), N21 (the grade widened to accept rc 3, red through the hazard control) and N22 (a pipe before an annotation skipped with it; the correct guard reads 114 triples with the fixture present, the mutant reads 113, so the row pins `PJ_TRIPLES` at 114 and is red; the unmutated guard with the same fixture and pin passes). The whole battery was re-run at the final guard commit `792c6e9674`: 52 rows, 48 RED as expected, 4 PASS as expected. The guard reads 61 pairs and 113 producer triples, 13 `drains` rows and 49 `exempt` rows; `SWEEP_PROBE_CHECKS` is 47.

### Exit gate (`scripts/test-all.sh --affected`) on the final tree

Run on a stable tree (nothing committed during the run), under the memory limit used for the batteries. 3 suites reported failing and 2 web-app legs were killed, all of them bun/vitest processes that crashed on the address-space limit (rc 133 and 134, "memory allocation failed"): `tests/scripts/scratch-residue`, `apps/web-platform/test/vitest-related`, `apps/web-platform/test/destroy-ask-mutation`, plus the two web-platform legs. Re-run directly without the limit: `scratch-residue` 136/136, `vitest-related` 36 passed 0 failed, `destroy-ask-mutation` 99 of 101 mutants killed with the 2 documented equivalents, 113/113 checks. The infra registered-suite runner (including `ci-deploy.test.sh`) passed in that run. A first affected run earlier in the session was void (commits landed while it ran) and is not quoted. CI on the draft head: lint and analysis checks pass; `test` reads red by design on a draft (`draft: full battery owed at ready`); `deploy-script-tests` failed once on a timing assertion of `ci-deploy.test.sh` (`#9860 D10e3`, a different timing row failed in a local run) and passed on re-run.

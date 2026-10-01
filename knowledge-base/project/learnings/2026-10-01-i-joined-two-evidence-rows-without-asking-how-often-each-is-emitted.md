# Learning: I joined two evidence rows on a key without asking how often each is emitted

## Problem

PR #9352 (#6931, guest-side fresh-boot LUKS for web-2) earned a soak marker by joining a daily
`luks-monitor` probe row to a `SOLEUR_FRESH_BOOT_READY` readiness row on `boot_id` equality. The probe row is
emitted once per BOOT. The readiness row is emitted by a cloud-init `runcmd` line, which runs once per
INSTANCE. After any reboot the two `boot_id`s differ forever, so the daily job returned `boot_id_mismatch`,
deleted the marker and went red, and the planned reboot proof ("a new row with a new `boot_id`") could not be
produced by any code. Seven of thirteen independent review seats (observability, architecture, pattern,
quality, code-simplicity, user-impact, structural) found it at the same SHA. It had survived the plan, deepen-plan,
plan-review, a CTO consult, the implementation and ~700 green assertions, because every test fixture
synthesized BOTH rows with the same `boot_id`, so the fixture agreed with the join.

## Solution

Join at the grain the data actually has: an INSTANCE-level join (the probe row is not older than the green
readiness row) to EARN the marker, and the probe row alone to KEEP it (the readiness row ages out of the
lookback on a host that never reboots). `boot_id` stays in both rows as a diagnostic only. Docs, ADR-263 and the
reason-to-action table were rewritten from the code, and the Phase-7 reboot proof (#9372) became "the next
probe row has a new `boot_id`, `device_type=crypto_LUKS`, mount source the mapper".

## Key Insight

A join key is a claim about two cadences. Before writing `a.key == b.key`, state in one line how often each
side is emitted (per instance, per boot, per day, per deploy) and what resets it; if the cadences differ the
key cannot be equality. A fixture that builds both sides from one literal proves the join works when the
cadences are equal and nothing else — write one fixture where the key changes on the side that is emitted more
often (a reboot) before calling the join covered.

## Session Errors

1. **Joined two rows of different cadence on equality (the headline defect).** Recovery: instance-level join
   plus keep-on-probe. **Prevention:** plan Sharp Edge (added): any plan that joins two emitted rows names each
   row's emission cadence and carries a fixture where the shared key differs.
2. **File-selected suite selection missed three suites that render `cloud-init.yml`** (`cloud-init-web-zot-seed`,
   `cloud-init-inngest-bootstrap`, `web-ghcr-deny`): adding a template variable broke their fixed vars maps, and
   only the code-quality seat found it. Recovery: key added to each map. **Prevention:** when a diff adds a
   `templatefile` variable, grep every suite that renders that template for its vars map (the existing
   work-skill rule on file-selected suites already names this blind spot; this is another instance of it).
3. **Pre-commit `web-platform-typecheck` hook died with a 2 GB Node heap OOM** on a loaded 31 GB machine, and the
   commit tool call was then interrupted with the outcome unknown. Recovery: checked `git log`/index lock
   first, then committed with hooks skipped on the user's instruction ("skip the precommit battery test and
   rely on CI"). **Prevention:** after any interrupted git write, read `git log -1` and the index lock before
   retrying; tracked as a recurring-gate issue (see triage).
4. **`gh issue edit` run from a scratchpad cwd** printed "Stopping at filesystem boundary" but the pipe
   through `tail` made RC=0 look like success. Recovery: re-ran from the worktree with `-R`, then verified by
   reading the body back. **Prevention:** run `gh` from inside the worktree with `-R`, and verify by reading
   back, never by the exit of a piped command.
5. **Filing hook refused a `--body-file $VAR` plus a heredoc in the same command.** Recovery: wrote the body
   with the Write tool to a literal absolute path, then ran `gh issue create` alone. **Prevention:** write the
   body file in its own step and pass a literal path.
6. **`pgrep -f` blocked by the guard hook** (self-matching). Recovery: `pgrep -x`/`pgrep <name>`.
   **Prevention:** none needed, the hook already enforces it.
7. **Earlier in the branch (forwarded from the pre-compaction summary):** `${ROOT:?}` aborted in production
   where ROOT is empty; a harness row recorded dropped cases so a deleted case did not red; a mutation row
   count was off by one; `luks-monitor-install` G1 forbade a `systemctl start` kick; the ForceNew premise for
   `hcloud_volume.format` was measured wrong (it is not ForceNew) and had to be corrected across `server.tf`,
   ADR-263 and the plan; `lint-workflow-step-env-refs`, guard-vacuity-floor ledger growth (49 vs 47) and
   `lint-trap-tempfile-ownership` each tripped a repo ratchet; the plan's `discoverability_test` command was
   invalid. **Prevention:** each was fixed in the same change with a mutation row; the premise error is the
   reason the plan now carries a "Work-phase measurements and corrections" section.
8. **A stop hook repeatedly flagged closing text that named an action.** Recovery: either do the action or end
   with a `<stop>BLOCKED: …</stop>` line. **Prevention:** none needed, the hook already enforces it.

## Tags

category: logic-errors
module: web-platform-infra, luks, observability

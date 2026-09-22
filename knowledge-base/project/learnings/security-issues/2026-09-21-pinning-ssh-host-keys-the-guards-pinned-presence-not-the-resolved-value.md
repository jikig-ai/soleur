---
title: "Pinning SSH host keys: the guards pinned option presence, not the value ssh resolves"
date: 2026-09-21
category: security-issues
module: ssh-host-key-pinning
tags: [ssh, host-key, tofu, known_hosts, terraform, github-actions, workflow_run, review]
issues: [7226, 5914, 8125]
pr: 8511
---

# Learning: pinning SSH host keys — the guards pinned presence, not the resolved value

## Problem

PR #8511 replaced trust-on-first-use (`StrictHostKeyChecking` accept-new with a throwaway or
`/dev/null` known_hosts) on every SSH path to web-1 and the git-data host: the CF-tunnel CI
bridge, 19 Terraform `connection {}` blocks, the git-data cutover's two hops, and the app's
git-data transport/provision/erasure helpers. A web-1 ECDSA-P256 pin is committed; the git-data
ED25519 key is minted by Terraform, installed by cloud-init with a boot proof, published to
Doppler `prd`, rotated on every replace, and loaded into the app by a follow-on redeploy.

The implementation passed its own suites and a self-run mutation matrix, and a 10-seat review
still found 62 findings (6 P1). Almost all reduce to four causes.

## Root causes and what fixed them

1. **Guards asserted presence, not effect.** ssh keeps the FIRST value it sees for an option, so
   a runtime-built `StrictHostKeyChecking=no` prepended ahead of the pinned block passed every
   `toContain` test while ssh ran unpinned. A text denylist (Guard 1) misses spellings by
   construction (`1>`, `|&`, `tee`/`dd`/`sponge`, `KnownHostsCommand`, concatenation), and a
   per-block "has a `host_key` line" check accepted `host_key = null` / `""` (both mean unset).
   Fix: assert the value ssh RESOLVES (`ssh -G` over the captured argv), keep the text guard as
   a cheap tripwire with per-arm rows and a realistic file floor, and require `host_key` to be in
   an allow-set. The bridge also gained `-F /dev/null` so runner ssh_config cannot add trust.
2. **A late relocation was not propagated.** The redeploy moved from jobs inside the apply
   workflow (which would have held the fleet apply lock for ~80 min) into its own `workflow_run`
   workflow. Docs, ADR, runbook, ledger and comments kept naming the never-built jobs, and the new
   workflow shipped with no failure email and a WORKFLOW-level concurrency group — so every
   ordinary merge-apply follower run entered the group and could cancel a pending redeploy.
   Fix: job-level concurrency, a `failure()` notify step, and a repo-wide sweep by SUBJECT.
3. **`LogLevel=ERROR` hid the diagnostic the plan depended on.** OpenSSH 9.6 logs "Unable to
   negotiate … no matching host key type found" and "channel N: open failed" at INFO, so the
   plan's `host_key_mismatch reason=alg` verdict was unobservable. Measured in a container,
   removed everywhere, and a test pins its absence.
4. **Recovery states were not enumerated.** After the SECOND rotation, a replace that fails
   between the key rotating and the new server existing leaves the pin secret (depends_on the
   server) at the OLD value; a re-dispatched birth plans a pin `update`, which the birth gate
   refused — a dead end. Fix: accept a pin `update` exactly when the server is a `create`.

## Key insight

For a trust-establishing change, every guard must be checked against the property "what does the
client actually trust at runtime", not "is the right text present". Text and presence guards are
cheap tripwires; the load-bearing check is the resolved configuration (`ssh -G`, a real
`sshd -T`, a real terraform plan) plus an enumeration of every path to the protected host.

## Session Errors

1. **Plan prescribed `LogLevel=ERROR` on every pinned path.** Recovery: a work-phase agent
   measured OpenSSH 9.6 in a container; removed and pinned by a test. **Prevention:** before
   adopting any log-level/quiet flag on a path whose failure text is classified, run the failing
   case under that flag and confirm the classified line still prints.
2. **Plan put the redeploy jobs inside the apply workflow**, inside its workflow-level lock.
   Recovery: moved to a `workflow_run` workflow. **Prevention:** for any job added to an existing
   workflow, read the workflow's top-level `concurrency:` and ask what the new job holds.
3. **The relocation was not swept**: `git_data_redeploy_*` survived in 8+ files. Recovery: sweep
   by subject. **Prevention:** existing rule — sweep by the claim's subject repo-wide, not by the
   diff's file list.
4. **New workflow without failure alerting and with workflow-level concurrency.** Recovery:
   `failure()` notify-ops-email + job-level concurrency. **Prevention:** a new workflow that is the
   only actuator of a state change needs an alert on failure and a concurrency group scoped so
   skipped runs never enter it.
5. **Four repo ratchets tripped by new files** (capture-exit lint, fixture-relative-assert,
   guard-vacuity-floor, xtrace refusal), found at review. Recovery: fixed inline. **Prevention:**
   existing work-skill guidance — run the shape-selected ratchets before review, not only the
   file-selected suites.
6. **Guards pinned presence, not effect** (Guard 1 spellings, Guard 2 null/"", app option tests).
   Recovery: `ssh -G` resolved-value tests, allow-set, per-arm rows. **Prevention:** this learning.
7. **Birth-gate dead end after the second rotation.** Recovery: accept pin `update` when the
   server is a `create`. **Prevention:** enumerate post-partial-failure states for every gate that
   blocks a recovery path.
8. **A fix agent reported 52 mutants; the suite ran 47.** Recovery: measured via a probe copy
   with the floor raised. **Prevention:** existing rule — never set a floor from an agent-reported
   count; read the runner's own number.
9. **Fix-agent comments spelled out the banned TOFU literal**, reddening Guard 1 twice.
   Recovery: reworded. **Prevention:** fix-agent briefs for a text-guarded PR must say "never
   write the banned literal, even in a comment".
10. **ADR-237 and the runbook stated AC15 as done before the run existed.** Recovery: reworded
    and later cited the green run. **Prevention:** existing rule — present-tense claims about
    post-merge or pending verification must be conditional until the evidence exists.
11. **Plan addendum claimed a mid-line CR is rejected**; both sites strip every CR. Recovery:
    corrected. **Prevention:** run the claim's fixture before writing it into a deviation record.
12. **Local terraform against `apps/web-platform/infra` failed three ways**: local 1.9.8 vs a
    backend needing `use_lockfile` (≥1.10); `--name-transformer tf-var` renames the R2
    `AWS_*` credentials so the S3 backend sees none; a nested `doppler run` inherited an
    unusable token. Recovery: verified TF 1.10.5 download, export the two `AWS_*` values
    directly, single `tf-var` run, targeted saved plan diffed before apply. **Prevention:** route
    to the `admin-ip-refresh` skill (its emitted commands hit all three).
13. **A two-dot diff in the lead's own verification** pulled a main-only file into a lint run
    (false red). Recovery: re-ran on the three-dot set. **Prevention:** existing rule.
14. **A `verdict=` grep over a run log matched GitHub's echo of the step's own source.**
    Recovery: read the context line. **Prevention:** anchor run-log greps on emitted lines, not
    on tokens that also appear in `run:` bodies.
15. **The local touched-shard gate queued behind three sibling runs**; the operator chose CI as
    the gate. Recovery: stopped the run, pushed. **Prevention:** none — contention is expected.
16. **`ADR-068` matched the one-shot Linear-ID regex** `[A-Z]{2,}-[0-9]+`. Recovery: treated as
    a false positive. **Prevention:** route to one-shot Step 0a — ADR ordinals are not Linear ids.
17. **Merge conflict with main** (`INDEX.md` untracked by ADR-235, CODEOWNERS, C4 emitter count).
    Recovery: resolved by hand, regenerated the C4 JSON. **Prevention:** none beyond the review
    skill's pre-panel `merge-tree` check, which caught it.

## Related

- ADR-237 (`knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`)
- Runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- Follow-ups #8518; #5914 (transitional fallback deletion)

## Tags

category: security-issues
module: ssh-host-key-pinning

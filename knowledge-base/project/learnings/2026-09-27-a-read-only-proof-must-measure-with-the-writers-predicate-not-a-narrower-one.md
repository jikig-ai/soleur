---
title: A read-only proof must measure with the writer's predicate, not a narrower one
date: 2026-09-27
category: security-issues
module: apps/web-platform/infra/git-data-cutover.sh
tags: [git-data, luks, cutover, proof, gdpr, art-17, mutation-testing, runbook]
issues: [8211, 5914, 9066]
---

# Learning: a read-only proof must measure with the writer's predicate, not a narrower one

## Problem

#8211 PR2 inverted the cutover proof: `already_cut_over` (the store served from
`/dev/mapper/git-data`) went from a refusal (exit 5) to the pass condition. The first
implementation passed the plan's mutation battery and still proved less than the property
its verdict names. An 11-seat review plus CTO/CLO rulings found five root causes:

1. **Config validated late.** `OLD_ROOT`, `REPO_SUBDIR`, `STORE_VERIFIED`, `LUKS_MAPPER`
   and `TRANSPORT_WRAPPER` were interpolated into remote commands before anything checked
   them.
2. **The proof was narrower than the property.**
   - The store-empty count skipped entries that the bootstrap's `_repo_count` counts.
   - `findmnt` resolved the containing mount rather than `--mountpoint`.
   - The source, UUID, marker and freeze facts were read in separate ssh sessions, so each
     read could observe a different state.
3. **The RB/P3 extractors were narrower than the files they checked.** A runbook row whose
   `reason=` word had no emitter anywhere in the repo stayed green.
4. **Runbook evidence gaps.** The GDPR Art. 17 discharge record ("no repository held;
   nothing to erase") did not require `plaintext_volume=present`. It also did not account
   for `.<user_id>.init.lock` files. `git-data-remove.sh` and `git-data-provision.sh`
   create those and never unlink them, and **no count sees them** (#9066).
5. **Stale docs.** Several documents said "exactly as strict as the wrappers"; the true
   statement is "never stricter".

## Solution

- **One ssh session for all store facts.** Read the freeze sentinel first, then source,
  UUID and marker, then the count, all with `findmnt -n -o SOURCE|UUID --mountpoint`.
  The count uses `_repo_count`'s exclusion list verbatim (`.*.init.lock`, `lost+found`)
  and the wrappers' `stat -c %m` containing-mount check. The suite's P4 pins that parity.
- **`refuse_if_config_unsafe` (`probe=config`)** runs before anything is printed or
  dialed. `LC_ALL=C` is exported.
- **The RB reverse check** runs over every verdict-map row. Each `verdict=` and `reason=`
  word must have an emitter, found by `git grep` excluding md, tests and knowledge-base.
  Each map probe/verdict pair must have been observed. Every check has one isolating
  mutant. Floors are exact (`-ne`): 91 mutants, 453 assertions.
- **The CLO-ruled discharge record** has evidence (a) to (d); (d) classifies lock-file
  risk per id. No user id appears on a public surface. Unreadable evidence produces a
  NOT DISCHARGED record and opens a `clo-attestation` issue.

## Key Insight

When a read-only proof certifies the same fact that a writer script enforces, it must
measure with the **writer's** predicate: the same exclusion list, the same mount
resolution, and the same session atomicity. The suite must pin that parity. Otherwise
the proof passes a stricter-looking check that sees less. Two consequences:

- The objects a count deliberately excludes still need their own accounting. Here the
  excluded lock files carry personal identifiers, so "nothing to erase" was false in a
  way no count could show.
- A mutation battery proves that the suite detects edits to the code it has. It cannot
  prove that the code measures the whole property. Only reading the writer side by side
  shows that.

## Session Errors

1. **A Python batch edit aborted on its own occurrence-count assertion** (`rm -rf
   /mnt/git-data;` found once, not twice). Recovery: reapplied the edits with explicit
   per-occurrence replacements. **Prevention:** keep the count assertion in multi-site
   batch edits; it worked as designed and wrote nothing.
2. **An unquoted heredoc for the findmnt shim needed its tail escaped** (`\$`, `\\\\n`).
   Recovery: rendered the shim and inspected it. **Prevention:** keep one-variable
   interpolation out of large shims. Prepend a separate `FIX_UUID=...` line and keep the
   body `<<'EOF'`-quoted.
3. **The g2v-h4 sed mutant had the wrong backslash count.** Recovery: `printf .%s\\n.`
   (one backslash in the rendered shim). **Prevention:** assert every mutant on the
   rendered bytes; the exact diff-line landing check does this.
4. **The rb-1 mutant stopped landing after a runbook row move.** Recovery: re-aimed the
   anchor at `**Tampering signal**`. **Prevention:** already covered, because the harness
   fails loud when a mutant does not land. Anchor doc mutants on the row label, not the
   cell text.
5. **The S11 row stayed on the old `findmnt -no SOURCE` form** after the predicate
   change. Recovery: updated it. **Prevention:** when changing a remote command's form,
   grep the suite for the old form across every row class (canned, executed, runtime).
6. **`gh issue create` for #9066 was blocked twice by the net-issue-flow filing gate.**
   Recovery: a `Mandated-By: hr-gdpr-gate-on-regulated-data-surfaces` line plus an
   authority rationale. **Prevention:** for a CLO-mandated GDPR tracker, use the
   `Mandated-By:` exemption first. The Fix-Size/User-Impact route is for scope-outs, not
   for mandated filings.
7. **ADR-237 hit markdownlint MD012.** Recovery: removed the blank line.
   **Prevention:** run markdownlint on each appended ADR note before committing; lint
   already catches this.
8. **The docker runtime arm (anonymous `/mnt/git-data` volume) did not run locally**
   because the machine was contended (user constraint). Recovery: CI is the gate.
   **Prevention:** watch the runtime job by name on the head SHA before merge.

9. **The runbook's dispatch step selected a `web-platform-release` run with `gh run list --commit <merge-sha>` and named no arm.** CI's `workflow-run-deploy-invariants` G8 caught it: each merge produces both a push run and a deploy run, so the unnamed selection reads the wrong one about half the time. Recovery: the step now uses `deploy-arm.sh find --wait` + `served`. **Prevention:** when prose tells someone to wait for a deploy, cite `plugins/soleur/scripts/deploy-arm.sh`, never a bare `gh run list`. Before pushing a runbook edit, run `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`: it scans `knowledge-base/`, so no file-selected suite set picks it up.

## Tags

category: security-issues
module: git-data-cutover

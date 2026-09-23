---
title: "My sweep was keyed on a literal, and the claim had another spelling"
date: 2026-09-22
category: workflow-patterns
issue: 8535
pr: 8568
tags: [correction-sweep, stale-claims, emitted-text, review, ratchets]
---

# My sweep was keyed on a literal, and the claim had another spelling

## Problem

#8535 enumerated its own work by running `grep -niE 'plaintext|unencrypted'` over the repo
and listing the seven files that matched. The registry store volume has been LUKS since the
2026-08-10 recut, so every present-tense "the volume is plaintext" sentence was false.

The issue's file list was complete for that grep and incomplete for the claim. A 3-agent
review panel found the same proposition living under a different spelling in files the grep
never touched:

- `.github/workflows/scheduled-zot-restart-loop.yml` wrote "an **UNFIRED** LUKS recut makes a
  replace fatal (#7287)" into every auto-filed restart-loop issue. Emitted operator-facing
  text, the same class as the `::error::` line the PR did fix — invisible to the grep because
  the sentence never says "plaintext".
- `model.c4` (and 12 copies in the generated `model.likec4.json`) said the launch gate and
  escrow re-test were "CODE-DECLARED until a registry replace delivers them".
- ADR-096's amendment kept "Status: CODE-DECLARED"; the disk-full post-mortem's row still
  said "the recut has not yet applied".

## Solution

Index a correction sweep by the **proposition**, not by the literal that happened to surface
it. Write the falsified claims as sentences first:

- "the registry volume is currently plaintext"
- "the LUKS recut has not run"
- "a host replace darks the registry"
- "the launch gate / escrow re-test is pending delivery"

Then grep each one's paraphrases — `unfired`, `CODE-DECLARED`, `not yet applied`, `BLOCKED ON
A PROVISIONING EVENT` — and classify every hit as dated history, a conditional/refuse arm, or
a live false claim. The highest-value hits are in files the diff does not touch, because
opening a file to fix one occurrence buys nothing for a proposition living elsewhere.

Two corollaries this PR also paid for:

- **Posture belongs in one place.** Five files ended up asserting "it is LUKS now", which is
  a sentence that goes stale at the next state change and re-creates this sweep. The fix was
  to state the mechanism ("a host replace keeps the volume, so it cannot recut") everywhere
  and keep current posture in the encryption-posture ledger row, with the NFR register row
  copying it and the runbook pointing at it.
- **An allowlist beats a denylist in operator guidance.** A new pre-dispatch check listed the
  two escrow failure values I had in mind (`fail_passphrase`, `fail_header`), so
  `fail_key_absent` — plus `indeterminate`, `stale`, `none`, and "no recent heartbeat" —
  passed it, and the replace it authorises boots a host that cannot reopen the store. Written
  as "proceed only if `store_luks=yes` AND `store_escrow=ok`", it cannot go stale when a new
  escrow state is added.

## Key Insight

A residual-zero count over a literal is evidence about a string. It is never evidence about a
claim, and the spelling that escapes it is disproportionately the one in emitted text — where
an operator reads it during an incident.

## Session Errors

1. **`gh issue create` denied twice** — once for a missing `--milestone`, then for a
   `--body-file` the gate could not read because the heredoc writing it was in the same Bash
   call the deny rejected. Recovery: write the body with the Write tool first, then file.
   **Prevention:** already covered by work/SKILL.md's "never heredoc an issue-body into the
   SAME Bash command as a hook-gated `gh issue create`" — this was a lapse, not a gap.

2. **Session-start `cleanup-merged` reaped nothing** — the session's plugin copy predates
   #8493, so merged `[gone]` branches were skipped for "no merge evidence". Recovery: ran the
   `origin/main` copy of `worktree-manager.sh` via `git archive`, which reaped 10.
   **Prevention:** operator runs `claude plugin marketplace update soleur-marketplace` then
   `claude plugin update soleur@soleur-marketplace`.

3. **The plan file failed markdownlint** (hard tabs inside a `3\t3` numstat quote, MD032) and
   **`tasks.md` failed MD022/MD032** — both authored by the planning subagent, both surfacing
   only when I linted them. **Prevention:** route a bullet to the plan skill — run
   markdownlint on the plan and tasks artifacts before the Session Summary.

4. **The touched-shard gate was unreachable** — two sibling worktrees held the runner, so a
   shard would have queued on the advisory lock. Substituted the suites that reference the
   changed files. **Prevention:** none needed; this is the documented substitute path.

5. **The first substitute set missed a ratchet.** `lint-shell-trace-credential-refusal` reds
   in CI via `--changed`, which bypasses the baseline for any touched file — so editing a
   baselined script owes the xtrace refusal in the same PR. My consumer-derived set found it
   only because I added the repo lints by hand. **Prevention:** when the shard is refused,
   derive substitutes from `*.baseline.txt` membership as well as from file references.

6. **The sweep missed a P1 that review caught** — the subject of this learning.

7. **`git fetch origin main:main` refused** — `main` is checked out in another worktree.
   One-off; used `origin/main` directly.

## Prevention

- For any correction sweep, list the propositions before the files, and grep paraphrases per
  proposition.
- Check emitted text specifically: `::error::`, `printf` into an issue body, dispatch input
  descriptions, PASS/ABORT echoes. These are read by an operator mid-incident and are the
  least likely to match a doc-shaped grep.
- Put current state in one machine-readable place and have prose point at it.

---
module: legal-corpus
date: 2026-09-07
problem_type: logic_error
component: documentation
symptoms:
  - "A corrected lead sentence left its dependent clauses asserting the old, narrower scope"
  - "The correction created a NEW contradiction inside the document being corrected"
  - "A guard shipped as blocking was disarmable by a document edit"
root_cause: incomplete_propagation
severity: high
tags: [legal-corpus, propagation, guards, mutation-testing, review, scope]
issues: [7874, 7786, 6474, 7787]
pr: 7881
synced_to: [review]
---

# I widened the sentence and left its clauses behind — five times in one PR

## Problem

PR #7881 closed four issues. All four were diagnosed correctly and fixed on the first
pass. Then five review agents plus a CLO attestation produced ~33 findings, and **almost
every one was in the VERIFICATION or the CORRECTIONS, not in the diagnosis.**

One class dominates, and it recurred **five times**:

> Correct a lead sentence, and the bullets, table cells, balancing tests and warranty
> cells beneath it keep describing the old, narrower scope.

That is not a cosmetic miss. It manufactures a NEW contradiction *inside the document
being corrected* — which is the exact defect the PR existed to close.

| # | Site | What the lead said | What the dependent clause still said |
|---|---|---|---|
| 1 | `privacy-policy.md` §5.14 | "two emitters reach this source" | bullets still said "shipped from the Hetzner **inngest VM**", "scoped to the **inngest plane's** failure surface" |
| 2 | `gdpr-policy.md` §3.7 | widened to disclose off-host shipping | the Art. 6(1)(f) balancing test still read `journald + host_metrics … as of 2026-05-21` and had never been run against the higher-sensitivity stream it now covered |
| 3 | `gdpr-policy.md` limb (a) | *my own* amendment | "routine operation produces **no off-host record at all**" — false: `host_metrics` scrapes every 300 s unconditionally |
| 4 | all six published files | non-JSON carve-out disclosed | it landed in **1 document of 3**, so this PR's own `gdpr-policy` admitted a wider exposure than its siblings disclosed |
| 5 | DPA template Schedule 2 | I edited the row's Duration cell | the **Sensitive data** cell one column over still warranted "None (pseudonymised)" — a warranty in a customer-signed instrument |

**The tell:** I was re-reading corrected sentences for **accuracy**. The failure mode is
**scope**. Every one of those five sentences was individually true when read on its own.

## Root cause

A correction changes what a passage is *about*. Reviewing it for truth answers "is this
sentence right?" and never asks "is this sentence still about the same set?" The
dependent clauses were written against the narrower set, stay grammatical, stay
plausible, and are the last thing anyone re-reads.

Sibling shape, same root: **index by CLAIM, not by FILE.** I edited
`recover-userid-from-pino-stdout.md`'s trigger list and left two claims *about the
register* stale in that same file — after having flagged that exact failure earlier in
the same session.

## Solution

For every corrected sentence, before moving on:

1. `grep` the dependent constructs beneath it — bullets, table cells, balancing tests,
   warranty cells, frontmatter fields — and re-read each **for scope, not accuracy**.
2. `grep` the SIBLING documents for the same claim. A carve-out that lands in one of
   three published files is worse than one that lands in none: it proves the author knew.
3. Ask per clause: *what set was this written against, and is that still the set?*

## The guards I shipped were worse than the prose

**A blocking guard, wrong in both directions.** A bare `30 MB` in the corpus-truth
probe's `FORBIDDEN` list would have red-lined **every open PR** on a future
attachment-limit disclosure (`1 MB` and `24 MB` already live in the corpus) AND missed
`30MB` / `30 megabytes` / `max-size=10m`. Replaced with a co-occurrence pattern — the
figure adjacent to the mechanism it was misattributed to. Then the window `[^.]{0,120}`
spanned table pipes, so `| 30 MB | attachment upload, per container |` matched across
cells; narrowed to `[^.\n|]`.

**And disarmable by a document edit, with no code change.** The correction-note exemption
used `re.S` with a lazy `.*?`, so one span ran to the next `)*` anywhere in the file.
Reproduced against the real corpus: a fake audit note wrapping a region hid two live
`FORBIDDEN` claims at `CORPUS-OK`, rc=0.

The discriminator came from **measuring, not capping**: of the 20 legitimate correction
notes in the corpus, **zero** span a paragraph break. A length cap does not discriminate
— the longest legitimate note is 880 chars, *longer than the exploit*.

```python
# A note that crosses a blank line is a failure AND is left unstripped,
# so the claims inside it are still checked.
PARAGRAPH_BREAK = re.compile(r"\n[ \t]*\n")
```

**A comment asserting a property of a regex is a comment that has not been tested.** My
"measured shapes actually present in the corpus" list named five; shape 3 — the bold form
this PR adds to all six documents — did not match, because `[^)*]*` cannot cross the `)`
in `(#7786 / #6474)`. Fixed by making the list an executable startup assertion, so the
next shape added is checked by construction.

**The dispatcher axis no SUT mutation can reach.** Everything in a suite is observed
*through* `pass()`/`fail()`, so those helpers going silent is invisible from inside.
Rewriting `fail()` to keep `TOTAL` and drop `FAIL` reported `PASS=22 FAIL=0 TOTAL=58`,
exit 0, against a deliberately broken scanner. `MIN_CASES` cannot see it (TOTAL still
moves); `PASS -eq TOTAL` cannot see the sibling mutation that short-circuits the oracle
(both counters then move together). Needs **both**: a positive control driving each helper
once and asserting both counters moved, plus a conservation check at the epilogue.

## Two findings that were not about documents

**The trigger I repaired reproduced its own defect.** `compliance-posture.md` records that
trigger 2 missed a change because it anchored on the `daemon.json` block while the change
was made at the `docker run` invocation. My re-scope anchored on **one of three**
`--log-driver journald` sites — and the one it watched (`cloud-init.yml`) runs only at
host birth, while the per-deploy path that starts the live container on every merge is
`ci-deploy.sh`. `vector.toml` already recorded that both files start the container.

**A safety defect introduced into a recovery runbook.** The `ssh -vvv` I sanctioned as the
terminal verification **feeds fail2ban's `maxretry`**, under `bantime.increment = true`
with no `bantime.maxtime` cap — so retrying it re-arms the ban the operator just cleared,
at a longer bantime, plausibly after the noVNC tab is closed. An L4 banner probe answers
the same question without authenticating:

```bash
timeout 5 bash -c 'cat </dev/tcp/<ip>/22' | head -1
# timeout      -> firewall drop (admin-ip-drift)
# reset        -> fail2ban (ssh-fail2ban-unban)
# SSH-2.0-...  -> channel open
```

My "there is no no-SSH read path" claim was false in **both** runbooks — and in
`admin-ip-drift.md` the no-SSH read (`hcloud firewall describe`) was **already inside the
fence I had sanctioned.** The narrow claim that survives is the true one: confirming
end-to-end *key auth* requires an SSH attempt.

## Prevention

- Re-read corrected sentences for **scope**, not accuracy; grep the dependents and the
  siblings.
- For any guard: name the input that makes it green while the thing it protects is broken,
  AND the legitimate input that makes it red. Both directions, or it is not calibrated.
- Prefer a **measured** discriminator over an intuited threshold. "Zero of 20 notes span a
  paragraph break" beat a length cap that the exploit was already under.
- A prose invariant is a comment that has not been tested. Make the list executable.
- When repairing a trigger that failed to fire, enumerate **every** site it must watch —
  the repair inherits the original's blind spot by default.

## Session Errors

1. **Ended the turn after review on a forward-looking status line** ("Next: /qa →
   /compound → /ship"); the operator had to ask "why did you stop". — Recovery: resumed
   the pipeline. — **Prevention:** a phase-complete marker is a CHECKPOINT; the next tool
   call in the SAME response must be the successor skill.
2. **`rc=$?` after a pipe reported `tail`'s status, not the script's — twice.** —
   Recovery: re-ran capturing rc directly. — **Prevention:** capture into a variable on
   its own line before any expansion.
3. **`gh pr diff --name-only` returned `stream error: CANCEL`** on three large PRs, making
   the collision gate's scope discriminator silently vacuous. — Recovery: substituted
   premise-validation against `main`. — **Prevention:** never read an errored probe as
   clean; name the substitute measurement.
4. **Ran `lint-infra-no-human-steps.py` over `docs/legal/**`,** which is outside its
   `SCAN_DIRS` and its lefthook glob, producing a self-inflicted "FAIL: 6". — Recovery:
   checked the linter's own scope. — **Prevention:** read a linter's scope before running
   it over explicit paths; explicit paths override discovery.
5. **markdownlint baseline taken in a temp dir without `.markdownlint.json`** → a
   different rule set, so the comparison was apples-to-oranges. — **Prevention:** copy the
   config into the baseline sandbox.
6. **Em-dash vs `--` anchor mismatch** caused two failed edit applications. —
   **Prevention:** dash-agnostic matching for corpus prose.
7. **`MIN_CLAIM_LEN` over-applied to `FORBIDDEN`,** refusing the corpus on the legitimate
   6-character `30 MB` on first run. — **Prevention:** the asymmetry IS the point —
   REQUIRED is fail-open on a short entry, FORBIDDEN is fail-closed. Scope the floor.
8. **An edit script wrote per-file after all replacements,** so a mid-group assertion left
   earlier groups applied and later ones not. — **Prevention:** assert every anchor across
   every file BEFORE writing any.
9. **My correction note contained the literal `30 MB` and tripped my own probe.** —
   **Prevention:** none needed; the guard caught its author within an hour of being wired.
10. **A loose grep matched plan/spec paths** and reported 17 phantom findings. —
    **Prevention:** anchor greps on the path prefix, not a bare basename.
11. **ANSI colour codes defeated a `Tests N passed` grep,** making a real result look
    absent. — **Prevention:** strip ANSI before matching.
12. **`grep -c` on a one-line JSON file counts lines, not occurrences.** —
    **Prevention:** `grep -o … | wc -l`.
13. **A worktree waiter's `pgrep` matched its own command line** → a false "settled". —
    **Prevention:** never `pgrep` a pattern your own command contains.
14. **Three background tasks OOM-killed** under four sibling `test-all.sh` runs; the
    commit did not land and had to be re-made. — **Prevention:** check `free -m` and the
    sibling count before spawning.
15. **`git stash list` blocked by the guardrails hook** (a correct block; my error). —
    **Prevention:** `git rev-parse --verify --quiet refs/stash`.
16. **An edit assertion caught a 3-space vs 2-space anchor drift** before writing. —
    **Prevention:** none; the assertion did its job and is the reason nothing was
    corrupted.
17. **Forwarded from planning:** a deepen-plan Phase 4.7 halt on an over-trimmed
    Observability block; two markdownlint commit failures; five claims in planning drafts
    measured false by reviewers. — **Prevention:** already recorded in the plan's own
    retractions.

## Related

- `2026-09-04-three-review-rounds-each-found-defects-in-the-last-rounds-fixes.md`
- `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`
- `2026-08-12-every-blocking-finding-was-the-defect-class-the-pr-existed-to-close.md`

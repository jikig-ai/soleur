---
title: "Every field my alarm trusted came from the region it did not trust"
date: 2026-09-08
category: security-issues
tags: [redaction, untrusted-input, greedy-parse, log-injection, guard-vacuity, public-egress, adr-166]
issues: [7500, 7444, 7272, 7959, 7960]
pr: 7954
---

# Every field my alarm trusted came from the region it did not trust

## Problem

Issue #7500 asked a narrow architecture question: should `zot_last_err` route through `redact()`? The
answer was yes, at two layers. The work that followed produced **39 recorded errors**, and they
collapse into far fewer classes than that number suggests. The dominant one cost four P1s.

## The dominant class: a trusted field parsed out of the untrusted region

`SOLEUR_ZOT_DISK` rows end with `zot_last_err=<free text from zot's log>`. That field is
attacker-influenceable — anything that can land an HTTP request on the registry chooses part of
it, because `user-agent` is on the redaction allowlist and is preserved verbatim.

This repo already has the discipline. `scripts/lib/zot-telemetry-parse.sh` carries
`zot_trusted_region()`, whose header says outright that it is *"a security guard (a crafted
`zot_last_err` log tail must not spoof `boot_id=`/`exit_code=137`)"*, and it cuts at the **first**
occurrence.

Four consumers parsed the other way round — a leading greedy `.*`, which binds to the **last**
occurrence, and the untrusted tail is emitted last:

| consumer | forged | consequence |
|---|---|---|
| `err_src` (the tier label) | ` zot_last_err_src=panic ` in a tail | routine chatter published to a **public** issue as "a matched diagnostic line" |
| `last_err` sentinel | ` zot_last_err=REDACTION_FAILED ` | false "the fail-safe fired", and the real tail suppressed |
| follow-through `boot_id` | ` boot_id=FORGED ` | **closes the tracker**, asserting a control is live on a host never replaced |
| `NIC_ALARM_VERDICT` (unanchored `grep -oE` + `head -1`) | ` NIC_ALARM_VERDICT=GREEN ` | silences the alarm class built for #6400 — a dead pull path that read green for 14 days |

Measured, on the real expressions: greedy returns `panic`, bounded returns `fallback`; unanchored
returns the forged `GREEN`, anchored returns the true `FIRE`.

**The sharpest part is that I introduced the first one while fixing ADR-166.** The tier label
exists so an alarm never presents a routine sample as a measured cause. Reading that label out of
the untrusted region made the label itself the forgery vector — the defect, delivered by its own
remedy.

**Prevention:** when a row has one free-text field, every OTHER field is trusted and must be read
from the trusted region. Cut the tail at its **first** occurrence before extracting anything; a
leading greedy `.*` binds to the last. Anchor consumer greps at line start (`sed -n 's/^KEY=…'`),
never `grep -oE 'KEY=…' | head -1` — emit ORDER is not a control, and any field emitted after the
attacker's text is unprotected by it.

## The second class: a guard that could not fail

Seven, of which the worst is one character of operator:

```bash
assert_struct() { … if [[ "$n" -ge "$min" ]]; then pass …
assert_struct "no published field bypasses emit_field" "$CHECKER" '<pattern>' 0
```

`n -ge 0` is true for every n. It was the **only** guard on the chokepoint that keeps credentials
out of a public issue, and its own comment said *"the absence is asserted rather than trusted."*
It was trusted. Inserting a real bypass raised the count to 1 and it still printed
`ok … (matches=1 >= 0)`.

**The shape is invisible on the page** — the output reads like a pass, because it is one.

Siblings from the same session: a floor reading `PASS+FAIL`, both written only by `assert()`, so
one line rewriting that helper to always pass satisfied it at rc=0 across 102 assertions; a
non-vacuity control that shadow-copied the producer's tier regexes, so producer drift left it
green with the needle no longer in the sample; a row cited by an ADR *and* the Art. 30 register as
proof of the allowlist which was tier-4 shaped, so the tier **gate** withheld it and it passed
against a program with no redaction in it.

**Prevention:** a `>=` helper given a floor of 0 is a tautology — absence needs its own helper
asserting `-eq 0`. Any counter a floor reads must not be written solely by the helper it
backstops; add a positive control that drives the helper both ways and requires both counters to
move. Derive a control's model of the SUT **from** the SUT, never by copying its patterns.

## The third class: the fix shipped the defect it was fixing

Six. The worst was a **P0 I introduced while fixing the injection**:

```yaml
run: |
  verdict="$(… | sed -n 's/^ZOT_ALARM_VERDICT=\\([A-Z_]*\\)$/\\1/p' | head -1)"
```

`run: |` is a YAML **literal** block — no escape processing, so sed receives those bytes verbatim.
A doubled backslash-paren is a *literal* backslash-paren in BRE, not a capture group. Both verdicts
extracted **empty on every run**, turning all four filing conditions false: the alarm would have
filed nothing, on any verdict. That is the #7242 "dark on exactly the verdicts it exists to raise"
defect, which this very file's header documents at length.

Also in this class: a blanket scrub that collapsed newlines, so the assembled block flattened and
every field parsed empty; a residual refusal that rejected *correctly*-redacted rows (after the jq
walk a redacted value is `["REDACTED"]`, so the byte after the colon is `[`, not `R`) and broke 3
log-shipper assertions; and a delivery baseline passed as an env var that the sweeper's `env -i`
strips, leaving the FAIL branch I had just added as dead code.

**Prevention:** verify a fix in the environment it *ships into*, executing the line as the runtime
will receive it — for a workflow, parse the YAML and run the extracted command, don't read it.

## The fourth class: a control failing open on a missing dependency

`redact()` reached its jq allowlist only if `jq -e` succeeded; otherwise it fell to the non-JSON
**denylist** branch and returned **0**. So without jq the allowlist silently became a denylist and
an unanticipated credential header (`X-Registry-Auth`) shipped in the clear, with no
`REDACTION_FAILED` and no tier change. jq absence is a measured-real state on this host — the
cloud-init carries a `dpkg -s jq` re-ensure *because it happened*.

**Prevention:** when a function's security property depends on a tool, `command -v` it and **fail
closed**. A fallback to a weaker branch that still returns success is a silent downgrade of the
property the function exists to provide.

## What the panel measured that no single instrument found

Six agents, disjoint yields. `shellcheck` found the highest-severity *assertion* defect (a
captured-but-never-asserted verdict, `SC2034`). The structural-enumeration seat produced the route
map the four adversarial seats each sampled one instance of. `test-design-reviewer`, in an isolated
worktree, found eight survivors no behavioural suite could. `code-quality-analyst` caught the P0 —
in my **uncommitted** tree, because it re-read rather than trusting the diff it had been given.

No instrument found more than three. A review that runs only one ships the rest.

## Session Errors

**39 recorded** — 4 forwarded from the plan phase plus 35 from implementation and review
(the last of which is a hook deny). Grouped by the class each belongs to; the class sections
above carry the full mechanism, so the preventions here are stated once per class.

### A — a trusted field parsed out of the untrusted region (4; all mine, all P1)

1. `err_src` read with a greedy `.*` — a crafted tail relabels routine chatter as "a matched
   diagnostic line", breaking ADR-166 via the very label built to enforce it.
2. `REDACTION_FAILED` matched against that same untrusted tail — a forged fail-safe claim, with
   the real tail suppressed behind it.
3. The follow-through's `boot_id` — a forged value **closes the tracker** while Phase B has
   never been applied to any host.
4. `NIC_ALARM_VERDICT` extracted with an unanchored `grep -oE … | head -1` — alarm suppression.
   Pre-existing, and my own comment falsely claimed newline-collapsing prevented it.

**Prevention:** as §"The dominant class" — cut the row at the first space-prefixed `zot_last_err=` and read
every other field from the trusted region; anchor consumer greps at line start.

### B — a guard that could not fail (7)

5. `G2-2b` asserted `n -ge 0` — a tautology, and the **only** guard on the emit chokepoint.
6. The boot-guard floor read `PASS+FAIL`, both written solely by `assert()` — one line disarms
   all 102 assertions at rc=0.
7. The heartbeat non-vacuity control shadow-copied the producer's tier regexes, so producer
   drift leaves it green with the needle gone.
8. `G1-2`'s fixture was tier-4 shaped, so the tier **gate** withheld it — it passed against a
   program containing no redaction.
9. "exactly ONE degrade branch" implemented as `-ge 1` over an unstripped file — satisfiable by
   a comment.
10. `G2-4` asserted uniqueness but never that the sink copy was in the comparison set.
11. `proxy-authorization` satisfied by `authorization` as a substring.

**Prevention:** as §"The second class" — `-eq 0` for absence, a positive control driving the
helper both ways, and a control's model of the SUT derived from the SUT.

### C — a fix that shipped the defect it was fixing (6)

12. **P0** — the anchored-verdict fix used doubled backslashes inside a YAML literal block, so
    both verdicts extracted **empty** and the alarm would file nothing on any verdict.
13. A blanket scrub collapsed newlines — every field then parsed empty.
14. A residual refusal rejected *correctly*-redacted rows (`["REDACTED"]` starts with `[`) —
    log-shipper 171/3.
15. `SOLEUR_FT_BASELINE_BOOT` is stripped by the sweeper's `env -i`, leaving the FAIL branch I
    had just added dead.
16. The follow-through fell through to PASS on *equal* boot ids — i.e. on not-delivered.
17. A drift check grepped a bare string my own explanatory comment contained (counted 3, not 2)
    — `cq-assert-anchor-not-bare-token`, committed while writing the guard against it.

**Prevention:** as §"The third class" — execute the line as the runtime will receive it; and for
an anchor, `^\s*<code>`, which a comment cannot produce.

### D — a record asserting something the system does not do (8)

18. The workflow scrub was justified by a threat the code refutes (the alarm has **zero** `>&2`
    writes); the step was deleted.
19. AP-025 cited backwards.
20. "disjoint egresses" — false.
21. "permanently" — an overclaim about a control that is inert until host replace.
22. ADR-211 shipped `status: accepted` where plan and `tasks.md` both required `adopting`.
23. The plan's Observability block keyed monitoring on an enum the code emits **zero** times.
24. The Art. 30 register carried framing the ADR had explicitly withdrawn.
25. The CLO attestation certified a completeness that two rows falsified.

**Prevention:** for every causal or universal sentence the diff ADDS, name the falsifying command
and run it; when a review corrects a claim, propagate it to every record that states it.

### E — a control failing open on a missing dependency (1)

26. `redact()` returned **0** without jq — the allowlist silently became a denylist and an
    unanticipated credential header shipped in the clear, with no `REDACTION_FAILED` and no tier
    change.

**Prevention:** as §"The fourth class" — `command -v` the dependency and fail closed.

### F — mechanical, and instruments read as results (8)

27. A heredoc terminator at column 0 ended the cloud-init YAML block.
28. A wrapped string put `"` at column 0 — same failure.
29. A braced shell expansion needed the `$${…}` templatefile escape.
30. An unterminated single quote in generated bash swallowed the `CRED_UNIQ` assignment.
31. A call-site counter undercounted loop-driven `assert()` calls and produced a false FATAL.
32. Two fixtures carried invented expectations — `oom5m=2` routed to a different OOM arm than
    the assertion named, and `NIC_ALARM_VERDICT` was asserted `UNEVALUATED` where the measured
    value is `SILENT`. Both went RED for the wrong reason.
33. A summary `grep -c` matched the floor **comment** (`88 passed`) rather than a verdict line.
34. My RED-scan grepped `^(FAIL|ERROR)` while the runner emits `RED` — I reported "none" from a
    pattern that could not match.

**Prevention:** inside a YAML literal block nothing may start at column 0, and every template
edit is rendered and validated. For 32–34, the class is asserting instead of measuring my own
instrument: give each instrument a known-positive before its negative counts as evidence, and
read a RED before believing it — a RED for the wrong reason proves nothing.

### G — hook deny (1)

35. `gdpr-gate-staleness` — corpus 121 days stale (`POSTURE_FAIL`). Pre-existing, tracked at
    #7255/#7857; not caused by this work and not fixed here.

**Prevention:** none owed by this session — the disposition is file-tracked against the existing
issues rather than a new filing (net-issue-flow).

### Forwarded from the plan phase (4)

36. A `redact()` probe fixtured on `Cookie` — a **denylist** member — so a denylist success read
    as an allowlist success. Re-measured with `X-Secret`, the header ships in the clear at rc=0.
37. An ADR premise inherited from a sibling agent and never checked: `redact()`, `CRED_HDRS` and
    `HDR_KEEP` appear in **zero** ADRs. Reversed from "amend ADR-184" to minting ADR-211.
38. The two-control justification was falsified by its own scoping — `boot_id=$NEWEST_BOOT`
    makes the claimed 3-hour historical window unreachable by construction.
39. The headline measurement was understated ~5x (actual 100 / 36 / 13 against a claimed
    "~20 / twenty / ~7") — the same defect class the plan opens by criticising in the issue.

**Prevention:** a redaction probe must use a fixture absent from *every* list the code consults;
for each inherited causal claim, name the falsifying command and run it; check whether an
existing scope predicate already makes a claimed time window unreachable; and count with a
command, never from recall, before a number enters prose.

## Key Insight

Thirty-nine errors, seven classes. The two that produced every P1 share a shape: **a value was
treated as trusted at the point of use, having been read from somewhere untrusted** — and **a check
was treated as protection, having been written in a form that cannot fail.** Both read correctly on
the page. Both are invisible to a green suite. Both were introduced by fixes for the very defects
they embody.

## Addendum — the ship of this PR reproduced three of the classes above

Errors 40-43 happened while shipping the very change this file documents. They are recorded here
rather than in a new file because the point is not the individual slips — it is that each one had
a written prevention in the sections above, and the prevention did not fire.

**40. I started a second `git commit` in one worktree while the first was still running** — the
defect §"The third class" documents from #7828, committed hours after writing it up.

I inferred the first commit had **died** from two signals, and both are worthless. Its log had not
advanced in ~2 minutes — but the hook it sat on runs a full test battery, so a static tail is the
*expected* reading. And `.git/index.lock` was absent — the real trap: **lefthook runs pre-commit
hooks BEFORE git acquires the index lock**, so for essentially the whole runtime of a commit in
this repo, a perfectly healthy `git commit` holds no lock. I read the absence of a lock as the
absence of a process. `ps` answered it in one command, after two writers had already sat on one
index and the second one's log had stalled at the same hook as the first — contention I nearly
diagnosed as a second death.

**Prevention:** liveness is a question about a PROCESS — ask the process table. Never infer death
from a quiet log or a missing `index.lock`; in this repo the lock is absent for nearly the entire
life of a healthy commit. Wait on a terminal signal the work actually emits (an rc file,
`MERGE_HEAD` clearing), never on a proxy for "still alive".

**41. Killing the duplicate did not stop the work it had started.** Its lefthook had already
spawned a full battery; terminating the parent left that battery running, **reparented to
systemd**. For several minutes the host carried two of my batteries plus three siblings' — the
contention that makes a RED at this gate untrustworthy. It surfaced only because I counted
`test-all.sh` processes and found one more than I could account for.

**Prevention:** after killing a build or commit, re-count the work it owned — a process whose
parent dies is orphaned, not terminated. Discriminate yours from a sibling's by `/proc/<pid>/cwd`,
never by the command line, which is byte-identical across worktrees; then signal the orphan's
process group after confirming it differs from the run you must keep.

**42. A gate whose comment claims more coverage than its code has.**
`scripts/check-adr-ordinals.sh` documents "Required-heading completeness: each file has
`## Status` / `## Context` / `## Decision` / `## Consequences`". Its implementation loops
`for required in ADR-042 ADR-041` — two hardcoded legacy files. **No new ADR is heading-checked.**
ADR-211, this PR's primary deliverable, shipped without a `## Status` heading while the script
reported `ADR ordinal + content checks passed`. The ordinal half is real and did useful work here;
only the heading half is vacuous, and the header comment is what hides it — a reader who greps for
"Status" finds the string and stops.

**Prevention:** when a gate passes on an artifact you have reason to doubt, read its
IMPLEMENTATION, not its header comment — the two are independent claims and only one executes.
For authors: a required-content check written against a fixed file list must say so, because "each
file" reads as universal quantification and will be cited as coverage.

**43. I put the session's durable artifacts in `/tmp`, and a reboot took them.** The machine
suspended overnight; `/tmp` is a tmpfs, so the scratchpad was wiped — losing a prepared commit
message, a staged patch script, and an earlier draft of this addendum. §"The third class" already
carries the rule, verbatim: *"Put long-lived logs in the worktree — `/tmp` is swept between turns
and leaves the writer holding a deleted inode."* I wrote that sentence in this file and then wrote
every artifact to `/tmp` anyway. Nothing was unrecoverable, but the next `git commit -F` ran
against a path that no longer existed.

**Prevention:** anything that must outlive a turn goes under the worktree's git-dir
(`$(git rev-parse --git-dir)/…`) — on-disk, untracked, and per-worktree. Reserve `/tmp` for output
you are about to read in the same turn.

### What these four have in common

Three of them are the SAME failure as the session's second class, relocated: **a check that cannot
observe what it claims to observe, reported as an observation.** `index.lock` does not mean "a
commit is running". A host-wide `ps` grep does not mean "our battery". A gate's comment does not
mean "the gate checks this". In each case the instrument returned a confident answer about
something it was not measuring, and in each case one direct measurement settled it.

The fourth (43) is different and worse: the prevention was not merely known, it was **written in
this file, by me, hours earlier**. That is the real finding of this addendum. A learning that is
written but not wired into the tooling — a path helper, a lint, a default — is a document that
makes you feel prepared for exactly the failure you are about to repeat. Where these route to
definitions, they should route as mechanism, not as more prose.

### The addendum's own postscript: `sort -u` made two credential guards vacuous

Adding the value-class assertion the user-impact review asked for, I drove it red to check it
worked — and it passed on a mutant that diverged the two copies. Chasing that produced the sharpest
instance of the session's second class, in code that predates this PR.

`sort -u` under this host's default `en_US.UTF-8` collation treats strings differing **only in
punctuation** as equal and drops one. Measured directly: two lines differing by a single `,` inside
a bracket expression collapse to one line unquoted, and stay two under `LC_ALL=C`.

Three guards in `registry-boot-guard.test.sh` are built on `grep | sed | sort -u | wc -l == 1` to
assert that the two `redact()` copies are byte-identical — the new value-class one, and the
**pre-existing `CRED_HDRS` and `HDR_KEEP` pair**, which are what stop the credential denylist and
the header allowlist from silently diverging between the producer's two copies.

Every difference those guards exist to catch is punctuation: a regex metacharacter, a hyphen in a
header name, a quote. So the collation was discarding precisely the differences under test.
Measured with a positive control on the fix itself — divergence applied to ONE copy
(`x-api-key` → `x_api_key`), locale pin reverted: **rc=0, zero failures.** With `LC_ALL=C`: rc=1,
and the correct assertion is the one that fires. Two mutants now discriminate, each failing the
assertion that owns it.

**Prevention:** any byte-identity guard implemented through `sort`, `uniq`, `comm` or `join` must
pin `LC_ALL=C`. Locale collation is not a formatting detail there — it decides which differences
the guard can perceive, and the default is to ignore exactly the punctuation that regex and
identifier drift consists of.

The general lesson is the one this whole file keeps arriving at from different directions: **a
guard's coverage is a property of how it compares, not of what it names.** These three named the
right subject, ran on every commit, and could not see the difference they were written for. The
only reason it surfaced is that a new assertion was driven red rather than trusted green.

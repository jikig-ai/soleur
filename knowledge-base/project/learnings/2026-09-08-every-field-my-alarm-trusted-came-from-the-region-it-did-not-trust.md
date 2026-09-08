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

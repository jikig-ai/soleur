---
date: 2026-07-29
category: test-failures
module: apps/web-platform/infra
issue: 6982
pr: 7015
tags: [guard-building-pr, tautology, self-derived-oracle, mutation-testing, quantifier-domain, adr-151, adr-149, cost-of-filing, cto-routing]
---

# Every guard I fixed this session was narrower than the claim it carried, and one of my fixes was a net regression

## Problem

A resumed session worked a post-review queue — four A-items and seventeen B-items — on the
pre-birth hardening for `soleur-git-data`, the host that will hold every connected user's
source code and **has never existed**. A six-agent review then ran over the delta.

The review's most serious findings were not in the code the branch was hardening. They were in
**the guards the branch added**, produced during that same session, and three of them made the
tree *less* safe than before the "fix".

Every one reduces to a single sentence: **the guard's quantifier domain was narrower than the
property its name claimed** — and in the worst case the domain was derived from the very
artifact under test, which makes the assertion a tautology.

## The root cause, in one shape

A guard asserts `∀ x ∈ S : P(x)`. Correctness needs three things to be true at once:

1. `S` is the set the property is *about*;
2. `S` is derived from something **other than the artifact being checked**;
3. the fixture instantiates more than one member of `S`.

Violating (2) is the subtle one, and it is the one that produces a **regression** rather than
merely a weak test — because it converts a real assertion into `S == S`, which is true of every
tree including a broken one.

## Solution

### 1. A set-equality guard whose expected set comes from the artifact under test is a tautology

B1 (`git-data-runcmd-rehearsal.test.sh`) asserts that every `indent(6, …)`-delivered payload is
byte-identical to its repo source. It originally floored on `checked >= 9`. I "improved" it to a
delivered-vs-expected **set** comparison — and derived the expected roster by regexing
`cloud-init-git-data.yml`, the same file that produces the delivered set.

Deleting a payload shrank **both** sides. Measured, after removing the `git-data-gc.timer`
delivery block:

    B1 OK: delivered set == expected set (8 payloads), all byte-identical

Four escapes were green under the rewrite and would have been caught by the count floor it
replaced:

| escape | consequence |
|---|---|
| drop the `git-data-gc.timer` delivery | the maintenance timer never installs |
| drop the Art. 17 erasure wrapper delivery | the remove key's forced command points at a nonexistent file — **GDPR erasure is dark** |
| relocate a payload, keep the basename | identity was `os.path.basename`, so `/tmp/junk/git-data-gc.timer` passed; systemd never sees it |
| second `authorized_keys` entry at an allowlisted path | the allowlist branch `continue`d *before* the dupe check; cloud-init applies in order, so an unrestricted key beats three `command=`-restricted ones |

The corrected shape, all four now RED:

- **roster authority = the PRODUCER** (`git-data.tf`'s `file()` bindings). A payload bound but
  never delivered fails.
- **destination contract owned by the test.** Deriving paths from the template re-created the
  tautology one level down — relocation moved both sides. The nine destinations are an explicit
  map in the test, so a deliberate move is a review event.
- **full-path identity**, never basename.
- the inline allowlist is exempt from *byte comparison* but **not** from the duplicate check.
- an **absolute** floor, not a self-derived one.

### 2. A cadence change justified by an unmeasured mechanism inverted the thing it optimised

B12 changed `git-data-gc.timer` weekly → daily, on the reasoning that
`--unpack-unreachable=2.weeks.ago` loosens objects which "sit until the next run", so a shorter
interval shortens loose-object residency — the resource A1 had just identified as binding
(655,360 inodes; inodes exhaust at ~55–60% of *bytes*).

Measured primitives say the mechanism runs backwards:

- loosened objects **inherit the source pack's mtime** (a pack aged 10 days yields loose objects
  dated 10 days ago);
- `repack -A -d` does **not** refresh existing loose mtimes;
- a pack older than the grace is **dropped, never loosened**.

So a loose object lives until `pack_mtime + 14d` — **wall-clock, independent of the interval**.
A shorter interval only makes the loosening start *earlier*.

    daily:  last repack 1d ago -> loosened=42, reclaimed day +14  => 14 DAYS LOOSE
    weekly: last repack 7d ago -> loosened=42, reclaimed day  +8  =>  8 DAYS LOOSE

Daily raised time-averaged loose-inode population **~1.75×**, i.e. B12 was working directly
against A1. Reverted. Daily also buys nothing on the push path once `receive.unpackLimit=1`
makes pushes arrive packed.

**The generalizable form:** a change whose *justification* is a causal mechanism must measure
the mechanism, not the intuition. "Shorter interval ⇒ shorter residency" is only true if
residency is a function of the interval.

### 3. A self-invalidating hash must cover every input, not the one you were thinking about

A3 added `git_data_rung2_rehearsal_gate`, whose value is that rung-2 boot evidence
**self-invalidates** when the thing that boots changes. It hashed `cloud-init-git-data.yml`
alone — **1 of the 10 files** composing `user_data` — so editing `git-data-gc.sh`, either gc
unit, the bootstrap, or any forced-command wrapper left the evidence valid for a payload that
had changed. The property the gate exists for did not hold.

Fixed with a hash-of-hashes over the template plus every `file()`-bound payload, derived from
the `.tf` so a newly injected payload is covered the day it is bound, with a floor of 10 inputs
so a shrunken extraction cannot silently narrow the binding.

### 4. A grep/sed oracle over an unstripped file can harvest its answer from a comment

The AC30 boot-payload parity check derived the producer's key set with
`sed -n '/boot_complete info/,/|| true/p'` — two unanchored bare-token addresses over an
unstripped shell file, where `|| true` already occurs in prose two lines above the emit.

Measured: planting a comment listing all six keys **while deleting `luks_mounted` and
`hooks_path` from the real emit** reported **44/44 GREEN**.

The aggravating detail is specific to this PR: ADR-152 strips comments **at render time**, so
the text that made the gate green *does not exist on the host*. The boot signal whose arrival is
supposed to mean the LUKS device mounted would stop saying so, with three consumers reading a
payload the suite swore was complete.

The same class hit `extract_strip` in the new parity suite (`grep … | head -1` over an
unstripped `.tf` can pick a comment mentioning the assignment). Both now strip comments first
and anchor on the call.

This is `cq-assert-anchor-not-bare-token` recurring **twice in one PR**, in a repo whose house
style is dense inline rationale — so the comments are load-bearing prose *and* an attack surface
on every grep-based oracle.

### 5. A new guard does not inherit its sibling's invocation pin

`terraform-target-parity.test.ts` pins gate 1's *invocation* (not just its `source` line),
with a comment recording three measured mutations. A3 added a second interlock and inherited
none of it. Measured against a green 98/0 baseline:

    delete the rung-2 invocation (if false; then)  -> 96 pass, 2 fail
    add `if: ${{ false }}` to its step             -> 97 pass, 1 fail

Both were GREEN before. Either disarms the only thing currently holding the birth. Now pinned
identically — invocation regex, step triad (no `if:`, no `continue-on-error`, a non-zero exit),
and ordering before `terraform plan`.

## Key Insight

**When a PR's deliverable is a guard, its bugs fail OPEN.** A defect in guarded code makes
something break; a defect in the guard certifies broken-as-fine. That asymmetry means a
guard-building change deserves *more* adversarial review than the code it guards, and the
author's own mutation battery is the weakest instrument available — it mutates the things the
author was already thinking about. Every escape here was found by asking a different question:

> What SET does this claim quantify over, where does that set come from, and how many members
> does the fixture instantiate?

Three of the five had green batteries throughout.

**Corollary on "improving" a weak guard.** A count floor is crude, but it is *independent* of
the artifact. Replacing it with a richer-looking set comparison derived from that artifact is a
strict downgrade. Before replacing a coarse assertion, check that the replacement's domain does
not come from the thing under test — otherwise the sophistication is decoration over `S == S`.

## Also measured, and worth keeping

**dash's `.` is a POSIX special builtin, so a failed source kills the shell.** This is the
mechanism behind two separate findings:

    dash -c '. /nonexistent || echo FALLBACK; echo SURVIVED'   # prints NOTHING, rc=2
    bash -c '. /nonexistent || echo FALLBACK; echo SURVIVED'   # prints both, rc=0

Both `git-data-gc*.service` units opened with `set -a; . /etc/default/git-data-doppler`, so the
failure reporter's documented "still fires from the BAKED DSN" fallback was **unreachable in
exactly the case it was written for** — the env file is mode 0600, written in `runcmd` after
stages that can abort. Fixed with `EnvironmentFile=-`.

The sibling: **a lost shebang degrades silently, it does not raise ENOEXEC.** `execvp` is
POSIX-mandated to retry `/bin/sh`, so `git`'s hook execution and `authorized_keys`
`command="…"` both fall back to dash. Four of nine payloads degrade quietly if the render-time
strip ever ate line 1 — which is why the strip's `#!` carve-out is load-bearing, and why an
earlier ADR-152 table that put the pre-receive hook in the "loud" column understated it.

**`receive.unpackLimit` semantics, confirmed against git 2.53.0:** unset inherits
`transfer.unpackLimit` (default 100); "equals or exceeds" stores a pack. Measured with a
42-object push: unset → 42 loose / 0 packs; `=1` → 0 loose / 1 pack. `1` is correct, not
off-by-one.

## Prevention

- **For any `∀ x ∈ S` guard, state where `S` comes from.** If the answer is "the artifact I am
  checking", stop. Derive it from the producer, or own it explicitly in the test.
- **Before replacing a coarse floor with a richer assertion, prove the replacement is not
  weaker.** Run the mutation the old form caught and confirm the new form still catches it.
- **Ask the reviewer to find the vacuity your battery missed** — never to re-run your mutations.
  The battery measures the mutations you imagined.
- **Any hash meant to self-invalidate must enumerate its inputs**, and the enumeration needs its
  own floor.
- **A new guard inherits none of its sibling's pins.** When adding one beside an existing gate,
  diff the sibling's test coverage and copy it.
- **Mutation runs need a green baseline in the same harness.** A sandbox copied out of the repo
  commonly breaks path resolution; a red baseline voids every result.

## Session Errors

1. **Rebase conflict in the generated `model.likec4.json`** — Recovery: regenerated via
   `scripts/regenerate-c4-model.sh` rather than hand-merging. Prevention: generated artifacts
   should be regenerated, never resolved by hand.
2. **Rebase conflict: two competing anti-vacuity floors** (main's `passes+fails >= 76` vs the
   branch's `passes >= 93`) — Recovery: kept main's more robust form (a failing assertion still
   counts as *ran*) and raised it to the branch's count. Prevention: when both sides add the
   same guard, keep the stronger mechanism and re-derive the number.
3. **`user_data` went 260 B over a hard ForceNew cap mid-session** — Recovery: routed to the
   `cto` agent as an architecture fork; ruling was ADR-152's render-time comment strip.
   Prevention: a cap this tight needs a structural answer, not prose-shaving; the
   architectural-fork gate correctly routed it away from the operator.
4. **My A1/A2 comments overran the cap twice** — Recovery: trimmed, then superseded by ADR-152.
   Prevention: check the budget in the same call as the edit on capped files.
5. **CWD drift produced `No such file or directory`** — Recovery: chained `cd <abs> && …`.
   Prevention: already a documented rule; it still recurred after an earlier `cd` into a
   subdirectory persisted.
6. **A stale rendered file produced four phantom payload MISMATCHes** — Recovery: re-rendered;
   all nine were byte-identical. Prevention: re-render before diffing against a render; a stale
   artifact reading as a finding is the same class as the stale-`_site/` false-pass.
7. **Edit-tool anchor off by one character** (`.test.sh` vs `.test.ts`) — Recovery: switched to
   an asserted python replace. Prevention: prefer `assert s.count(old)==1` over eyeballed
   anchors.
8. **B3's first fix diverged from systemd semantics** — a lookahead refusing to join a
   `Directive=` line, when systemd continues on *any* trailing backslash. Recovery: reverted for
   the union approach the review also offered. Prevention: when a fix changes how a third party's
   syntax is modelled, check the third party's actual rule first.
9. **A2's absolute `ExecStart=/usr/local/bin/doppler` would have reddened CI** —
   `systemd-analyze verify` resolves the binary on the *linting* machine. Recovery: kept
   `/bin/sh` as the lintable ExecStart with the absolute path inside. Prevention: run the gate
   that lints the artifact you just changed.
10. **A backtick in `git commit -m` was command-substituted away**, leaving
    "ACCOUNTING.  counted COMMANDS" — a sentence with a hole, which reads as complete.
    Recovery: amended via `--file`. Prevention: already a documented rule; use `--file` or a
    quoted heredoc unconditionally.
11. **A bare `/terraform plan/` ordering assertion matched the job HEADER COMMENT**, inverting
    the comparison — one screen below an existing test whose comment warns about exactly that.
    Recovery: used the anchored `terraform plan -no-color` form. Prevention:
    `cq-assert-anchor-not-bare-token`, which this session violated twice.
12. **A sandbox mutation run had a red baseline** (`0 pass 1 fail` from missing repo structure),
    voiding the measurement. Recovery: re-ran in place against a verified backup with a green
    baseline. Prevention: always establish the unmutated baseline in the same harness first.
13. **A stub's glob never matched** (`seq -w 1 6` yields `r1`…`r6`, so a `*/r01.git` case was
    dead), so the "hang" it modelled never happened. Recovery: rebuilt the fixture and re-ran.
    Prevention: assert the fixture exercised the path — a test whose scenario never fires is
    indistinguishable from one that passed.
14. **B1's rewrite was a net regression** — see Solution §1. Prevention: derive the expected
    set from the producer, never from the artifact under test, and re-run the mutation the
    replaced assertion caught before believing the new one is stronger.
15. **B12's daily cadence was backwards** — see Solution §2. Prevention: measure the causal
    mechanism a change is justified by; "shorter interval ⇒ shorter residency" holds only if
    residency is a function of the interval.
16. **A3's hash bound 1 of 10 inputs** — see Solution §3. Prevention: enumerate a
    self-invalidating hash's inputs from a producer and floor the enumeration.
17. **The AC30 oracle harvested its answer from a comment** — see Solution §4. Prevention:
    strip comments before any grep/sed oracle and anchor on the call, not a bare token.
18. **A3's invocation was unpinned and deletable at 98/0 green** — see Solution §5.
    Prevention: when adding a guard beside an existing one, diff the sibling's test coverage
    and copy its invocation pin — sourcing a library only defines, it never runs.
19. **ADR-152 carried two figures reproducible from no commit** (42,277 / ~69,182 against a
    measured 42,149 / 68,963) — Recovery: corrected to measured values with the command
    published beside them. Prevention: publish the command next to the number; a figure measured
    against an uncommitted tree is not reproducible by anyone.
20. **ADR-152's shebang table misclassified the pre-receive hook as loud** — Recovery: the
    reviewer executed it; corrected to four-of-nine silent. Prevention: a table enumerating
    "which losses are loud" must be executed, not reasoned.
21. **`RESUME.md` carried stale byte figures under a heading reading "verified this session"** —
    Recovery: refreshed. Prevention: a handoff's "verified" heading is a claim with a timestamp;
    re-derive before trusting it (this session's own instructions said so, about this file).
22. **Forwarded from `session-state.md`:** `iac-plan-write-guard` blocked two writes on
    `systemctl` prose (legitimately quoted template content, resolved with the documented
    opt-out), and deepen-plan gate 4.8 halted on a Better Stack ingest token adjudicated a false
    positive. Both one-off; recorded rather than silently dismissed.

## Related

- ADR-152 — the render-time rationale strip (this session's architecture ruling)
- ADR-149 — the git-data birth route and its readiness interlock
- [[2026-07-28-the-property-my-pr-existed-to-buy-was-pinned-by-nothing]] — the immediately
  preceding instance of a guard-building PR whose central property was pinned by nothing
- [[2026-07-22-a-drift-guard-pr-fails-open-in-the-guard-not-the-guarded-code]] — the same
  fail-open asymmetry, stated one week earlier
- [[2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once]] — the quantifier
  question, in its original form

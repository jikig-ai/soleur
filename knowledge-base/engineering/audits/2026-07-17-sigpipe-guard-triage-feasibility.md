# Can the `producer | grep -q P` guard class be triaged? — measured 2026-07-17

**Verdict: no, not by window analysis — and the class is smaller than any prior count suggested.**
**Disposition: track both subsets. Convert nothing in this PR.**

Regenerate everything below with:

```bash
bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh
```

This note exists because a prior attempt to track this class was rejected for citing a count nobody
had measured. It is therefore held to its own standard: **every number here carries the command that
produced it, and no number is restated from the prior record.** Where a prior figure is referenced it
is named as a hypothesis under test, never as a finding.

---

## 0. The finding that nearly didn't happen: the instrument was broken

Before any count, the question is whether the host can observe the defect at all.

`grep -q` exits on first match; the producer's next `write()` takes SIGPIPE (141); `pipefail`
promotes 141 to the pipeline status. **A `grep` that drains its input instead of exiting early
cannot produce that outcome — so every reading through it is 0/N.** A measurement taken there
reports that no site is reachable. That is a *false all-clear*, and it is strictly more dangerous
than the over-count this exercise was commissioned to correct, because nobody re-audits a green.

On the authoring host, measured:

```bash
/bin/grep --version                       # => grep (GNU grep) 3.12
type grep                                 # => grep is a function
bash slowprod.sh | /bin/grep -q MATCH     # => PIPESTATUS=141 0   0.016s  (early-exit: defect observable)
bash slowprod.sh | grep -q MATCH          # => PIPESTATUS=0   0   5.256s  (drained: defect invisible)
unset -f grep; bash slowprod.sh | grep -q MATCH   # => PIPESTATUS=141 0   0.015s
```

The resolved binary **was** GNU grep 3.12. It still drained, because a shell **function** shadowed
it. `unset -f grep` restored early-exit.

**This falsifies the obvious guard.** An identity check — assert `grep --version` reports GNU —
passes on this exact host while the measurement is silently poisoned. Identity does not imply
behaviour. The probe therefore asks the only question that discriminates:

> when a match arrives early, does this grep exit and let the producer die?

It refuses to emit a verdict when the answer is no, and names the cause. The attestation
(`sigpipe-triage-feasibility.test.sh`) pins both negative arms, including a shim that reports itself
as `grep (GNU grep) 3.12` and drains anyway — the shape an identity check cannot see.

**Consequence for any future reader: no verdict may be taken from a host whose grep does not
early-exit.** Run it where CI's grep runs, or `env -i PATH=/usr/bin:/bin bash <probe>`.

---

## 1. Corpus: 44% of the apparent class is the repo talking about itself

```bash
# raw hits (the number a naive audit would report)
git grep -cE '<shape>' -- 'apps/web-platform/infra/' | awk -F: '{s+=$NF} END {print s}'
# real sites (comments, double-quoted strings, and heredoc bodies stripped; `||` neutralised)
bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh   # "real sites" line
```

| measure | count |
|---|---|
| raw `git grep` hits | **280** across 42 files |
| **real sites** | **158** across 29 files |
| prose about the shape, not the shape | **122 (44%)** |

Two normalisations account for the gap, and both were found by inspection of the matched lines
rather than by reasoning:

- **Comments, strings, heredocs.** This repo documents the shape it forbids. The guard files explain
  the defect in comments; the harnesses print it in failure messages. A raw grep counts all of it.
- **`||` is not a pipe.** `cmd_a || grep -q P FILE` contains the byte `|`, but nothing feeds grep's
  stdin — no producer, no SIGPIPE, structurally incapable. A `\|` regex cannot see the difference.
  Several production files carry this shape; it accounts for a real share of the apparent count.
- **The instrument is in-corpus and must exclude itself.** The probe lives under
  `apps/web-platform/infra/scripts/` and its preflight contains a genuine `| grep -q` — that
  pipeline *is* the instrument. Measured: committing it moved the reported production set from
  34 sites/8 files to 36/9 and reclassified an audit tool as production infrastructure. It excludes
  itself and its attestation by path, and prints the exclusion beside the counts.

A count taken without both is a syntax count sold as a relevance count — the precise defect this
lineage is about. It is easy to commit *while* correcting it: the first draft of this probe did.

## 2. The partition that decides the disposition

Nobody had split this corpus. It is two populations, not one:

| population | sites | files |
|---|---|---|
| test-harness internals (`*.test.sh`) | **124** | 21 |
| **production** | **34** | **8** |

```bash
for f in $(git grep -lE '<shape>' -- 'apps/web-platform/infra/'); do
  case "$f" in *.test.sh) t=$((t+$(count_sites "$f")));; *) p=$((p+$(count_sites "$f")));; esac
done   # implemented in the probe; see its "partition" section
```

In test-harness code the defect is test debt: it false-FAILs a test (noise) or false-PASSes one (a
test that gates nothing). In production it changes what infra *does*.

**Symptom mix (production, pipefail-bearing).** The prior framing modelled one symptom — an inverted
`if` — and missed the dominant one:

| symptom | sites |
|---|---|
| **aborts** (`set -e` present: the script dies mid-run) | **19** |
| inverts (no `set -e`) | 2 |

`set -e` is the rc consumer for a bare pipeline, so most of this class does not silently invert — it
halts the script. That is a different failure with a different blast radius, and it had no bucket in
any prior framing.

**Coverage caveat, stated rather than buried:** 13 production sites sit in files that do not set
`pipefail` locally. That is **not** a clean bill — a sourced helper inherits its caller's `pipefail`.
Resolving it needs a call-graph this probe does not build, so "not locally set" is reported as a
bound, never as "safe".

## 3. B — the number the disposition was supposed to turn on

**B = bounded ÷ var-fed = 4/14 = 28%.**

| var-fed production sites | count |
|---|---|
| **bounded** (assignment resolves to a bound) | 4 |
| unbounded | 0 |
| **UNDECIDED** (assignment unresolvable) | **10** |

The threshold fixed *before* measuring was B ≥ 0.8 for triage to be considered available. **28% is
not close.** Window analysis cannot triage this class.

The 10 undecided are undecided for a structural reason, not a lazy one. The dominant shape is:

```bash
local e="${1:-}"                  # a function parameter
printf '%s' "$e" | grep -qiE ...  # its bound is a property of every CALLER, not of this line
```

Bounding those requires whole-program data-flow. **Calling them "bounded" because they feed a var is
exactly the inference that produced the discredited prior figure** — it asserts the consequent and
leaves the antecedent (*are the vars actually bounded?*) unestablished. They are reported as
undecided instead.

### The one genuine discriminator, and why it is not a byte threshold

The 4 bounded sites are bounded **by construction**, and the argument is worth stating precisely
because a superficially similar claim was correctly retracted before.

A prior byte-threshold claim ("producers under N bytes are unreachable") was retracted as false
precision: an 8 KB producer read 0/200 unperturbed yet was still killed under `strace`. That
retraction was right. Frequency arguments run backwards ("we didn't see it, so it can't happen") are
not proof of impossibility.

This is a different argument. Measured on the authoring host:

| producer | inversions |
|---|---|
| single `printf` of 400 B | **0/300** |
| single `printf` of 200 KB (match first) | **300/300** |
| multi-write loop | **300/300** |

A **single** `write()` of less than the pipe capacity (64 KiB on Linux) cannot block. It completes
into the buffer and the producer exits before `grep` can close the pipe, so no SIGPIPE is
deliverable. A **multi**-write producer is killable at any size, because any write issued after
grep's exit fails regardless of buffer room — which is exactly why the 8 KB case died under `strace`
and why the byte threshold deserved its retraction.

So the discriminator is not size. It is *single non-blocking write*; size only enters as the
condition under which that write cannot block. The probe counts a site bounded only on an explicit
truncation (`head -c N` / `tail -c N`, `N < 65536`) — e.g. `ci-deploy.sh`'s `tail="$(tail -c 400 …)"`.
Shape alone never qualifies.

**The conclusion is invariant across this refinement**: with the classifier resolving nothing, B was
0%; with the construction rule, 28%. Both are far below the 0.8 bar. Nothing downstream turns on
which is right — stated here so the precision is not mistaken for load-bearing.

## 4. Disposition

Applied mechanically from the rule fixed before the numbers were known.

| subset | measured | disposition |
|---|---|---|
| production | 34 sites / 8 files | **TRACK** — security-rung auto-forfeit |
| test-harness | 124 sites / 21 files | **TRACK** — never converted here |

Size alone said *convert* (34 ≤ 50, 8 ≤ 12). **The security-rung auto-forfeit overrides it:** 6 of
the 8 production files guard a security seam (RLS, egress/exfil, sandbox). Where a guard protects
one of those, a wrong conversion does not fail loudly — it yields a green gate that gates nothing,
which is the same failure this class already causes. A conversion needs per-site review that this
measurement has just demonstrated it cannot supply.

```bash
bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh   # "security-gating production files" line
```

**On what this note deliberately does not contain.** This repository is public
(`gh repo view --json visibility` → `PUBLIC`). A ranked per-site index of which security gates are
currently vacuous — fixing none of them — is a targeting artifact whose value to an attacker rises
with the quality of the measurement. This note therefore publishes counts, classes, and commands
only. Site-level detail for security-gating rungs belongs in the tracking issue.

That constraint costs nothing here, and the reason is the finding itself: **triage is unavailable, so
there is no ranked index to withhold.** The probe cannot say which rungs are live-vacuous. Nobody
can, by this method.

## 5. What would actually resolve this

Not a bigger ledger. The two options that remain, stated with what each costs:

1. **Convert the class blind** — `| grep -q<flags> P` → `| grep -<flags> P >/dev/null`, which removes
   the early exit and therefore the window, at every site, with no per-site judgment. Measured
   semantics-preserving. Two reviewers argued for it; it reverses the operator's stated direction and
   is recorded as UC-3 in this branch's `decision-challenges.md`, not decided here. Note the naive
   `sed` is unsafe (`-qE` + `-F` yields conflicting flags) and dropping `-q` makes grep read to EOF —
   harmless on a bounded producer, a hang on an unbounded one.
2. **Whole-program data-flow** on the 10 undecided var sources. This is the only thing that would
   make a per-site ledger honest, and it is a real project, not a by-product of a fix.

**The close-condition for the tracking issues is mechanical and fails today** (verified at file time):

```bash
bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh --pathspec <scope>
# closes when the reported production/test-harness site count for <scope> reaches 0
```

---

*Probe: `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` (registered in
`infra-validation.yml`; registration asserted cross-file by `scan-workflow.test.sh`).*
*Attestation: `sigpipe-triage-feasibility.test.sh`.*
*All counts regenerated 2026-07-17 on GNU grep 3.12 with the shell function unset.*

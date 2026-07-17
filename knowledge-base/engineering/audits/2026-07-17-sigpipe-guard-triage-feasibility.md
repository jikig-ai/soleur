# Can the `producer | grep -q P` guard class be triaged? — measured 2026-07-17

**Verdict: no, not by window analysis.**
**Disposition: one proven-live site fixed here; track the rest.**

The single demonstrated live defect this measurement found — `cat-deploy-state.sh` reporting journald
as volatile on a host where it is persistent — is **fixed in this PR**. Everything else is either
fail-closed or undecided, and is tracked.

Regenerate every number below with:

```bash
bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh
```

This note exists because a prior attempt to track this class was rejected for citing a count nobody
had measured. It is therefore held to its own standard: **every number carries the command that
produced it, and no prior figure is restated as a finding.** Several numbers in earlier drafts of
this very note failed that standard; they are corrected below in place, not quietly replaced.

---

## 0. The finding that nearly didn't happen: the instrument was broken

Before any count, the question is whether the host can observe the defect at all.

`grep -q` exits on first match; the producer's next `write()` takes SIGPIPE (141); `pipefail` promotes
141 to the pipeline status. A `grep` that drains its input instead of exiting early cannot produce
that outcome.

> **An earlier revision of this section claimed that a draining grep makes "every reading here 0/N"
> and this note a false all-clear. That was itself an unmeasured claim** — in the note whose subject
> is unmeasured claims — and it is false. Neutralise the gate, run the whole probe under a draining
> grep, and diff: identical but for the printed grep path. No measurement in this probe consumes
> grep's early-exit; every counting grep is `-c`/`-l`/`-v`/`-n`, or `-q` against a **file** argument.
>
> The gate still earns its place, for a reason that is true: it is an **environmental canary** for the
> rest of the repo. The #6572 rungs in `scan-workflow.test.sh` *do* depend on grep early-exiting and
> would pass **vacuously** under a draining grep. This probe runs in the same CI job, so it is the
> cheapest place to assert a property those tests silently assume.

On the authoring host, measured:

```bash
/bin/grep --version                                # => grep (GNU grep) 3.12
type grep                                          # => grep is a function
bash slowprod.sh | /bin/grep -q MATCH              # => PIPESTATUS=141 0   0.016s  (early-exit: observable)
bash slowprod.sh | grep -q MATCH                   # => PIPESTATUS=0   0   5.256s  (drained: invisible)
unset -f grep; bash slowprod.sh | grep -q MATCH    # => PIPESTATUS=141 0   0.015s
```

The resolved binary **was** GNU grep 3.12. It still drained, because a shell **function** shadowed it.
`unset -f grep` restored early-exit.

**This falsifies the obvious guard.** An identity check — assert `grep --version` reports GNU — passes
on this exact host while the measurement is silently poisoned. Identity does not imply behaviour. So
the probe asks the only question that discriminates:

> when a match arrives early, does this grep exit and let the producer die?

It refuses to emit a verdict when the answer is no, and names the cause. The attestation pins both
negative arms, including a shim that reports itself as `grep (GNU grep) 3.12` and drains anyway — the
shape an identity check cannot see. Not hypothetical twice over: an independent reviewer sent to audit
this PR was caught by the same wrapper and measured 0/N before noticing.

**No verdict may be taken from a host whose grep does not early-exit.** Run it where CI's grep runs,
or `env -i PATH=/usr/bin:/bin bash <probe>`.

### The false all-clear was real — through a door the gate did not watch

While the preflight guarded a failure this probe could not have, a reachable one sat open:

```bash
cd apps/web-platform/infra && bash ./scripts/sigpipe-triage-feasibility.sh
#   => production=0/0 test-harness=0 B=0% arm=convert       exit 0
```

`git grep` resolves its pathspec relative to CWD, so from any subdirectory the probe matched nothing —
and an empty corpus is not a harmless zero. It satisfies `0 ≤ 50 sites` and `0 ≤ 12 files`, and the
security forfeit cannot fire with no files to match, so **the arm flips from TRACK to CONVERT**: the
probe confidently recommends converting a class it never looked at. The fail-safe posture inverts.

Fixed: the probe pins itself to the repo root and **refuses an empty corpus**. A zero for this
pathspec means the instrument missed, never that the defect is absent — which is the whole lesson of
this note, applied to itself.

---

## 1. Corpus: a third of the apparent class is not the shape at all

| measure | count |
|---|---|
| raw `git grep` hits | **280** across 42 files |
| **real sites** | **189** across 30 files |
| prose / non-pipe `\|\|` forms, not the shape | **91 (33%)** |

Four normalisations account for the gap. Each was found by *inspecting the matched lines*, not by
reasoning — and each was, at some point in this PR's own history, missing:

- **Comments, strings, heredocs (in plain shell).** This repo documents the shape it forbids. The
  guard files explain the defect in comments; the harnesses print it in failure messages. A raw grep
  counts all of it as findings.
- **`||` is not a pipe.** `cmd_a || grep -q P FILE` contains the byte `|`, but nothing feeds grep's
  stdin — no producer, no SIGPIPE, structurally incapable. A `\|` regex cannot see the difference.
- **The instrument is in-corpus and must exclude itself.** The probe lives under
  `apps/web-platform/infra/scripts/` and its preflight contains a genuine `| grep -q` — that pipeline
  *is* the instrument. Committing it inflated the reported production set and reclassified an audit
  tool as production infrastructure. It excludes itself and its attestation by path, and prints the
  exclusion beside the counts.
- **But heredocs are PAYLOAD in `.yml`/`.tf`, not prose.** In cloud-init `runcmd` / `write_files` and
  Terraform `remote-exec inline`, the heredoc body is the code that runs on the host. An earlier
  revision stripped heredocs everywhere and scored `cloud-init-registry.yml` (6 raw), `server.tf` (2)
  and `soleur-host-bootstrap.sh` (1) at **zero** — discarding live code as commentary. That is this
  lineage's defect with the **sign flipped**: an unmeasured zero rather than an unmeasured many, and
  the more dangerous direction, because nobody re-audits a zero.

A count taken without these is a syntax count sold as a relevance count — the precise defect this
lineage is about, and easy to commit *while* correcting it. This probe did, twice.

## 2. The partition, and the symptom that was reported backwards

| population | sites | files |
|---|---|---|
| test-harness internals (`*.test.sh`) | **148** | 21 |
| **production** | **41** | **9** |

In test-harness code the defect is test debt: it false-FAILs a test (noise) or false-PASSes one (a
test that gates nothing). In production it changes what infra *does*.

**Symptom mix (production, pipefail-bearing):**

| symptom | sites |
|---|---|
| **inverts** (site is a condition => errexit suppressed) | **24** |
| aborts (bare pipeline under `set -e`) | **2** — an upper bound, see below |

> **An earlier revision of this note claimed the reverse** — "19 aborts / 2 inverts" — and was wrong.
> It tested `set -e` once per FILE and attributed that verdict to every site in the file. But POSIX
> shells **suppress errexit for any command run as a condition**: the controlling pipeline of
> `if`/`elif`/`while`/`until`, an operand of `&&`/`||`, anything under `!`. Essentially every site in
> this corpus is a condition — that is what a guard *is*. Measured:
>
> ```bash
> set -euo pipefail; if ! prod | grep -q M; then echo TAKEN; fi; echo SURVIVED
> #   => TAKEN + SURVIVED, rc=0          (inverts; errexit suppressed)
> set -euo pipefail; prod | grep -q M; echo SURVIVED
> #   => rc=141, SURVIVED never printed  (aborts)
> ```
>
> The correction moves the class toward the *worse* failure. An abort announces itself. An inversion
> is a guard confidently returning the wrong answer while the script sails on.

The 2 "aborts" are an **upper bound, not a count**: both are pipelines in *function bodies*, and a
bare pipeline inside a function is still guarded when every caller invokes that function as a
condition. Resolving that needs a call graph this probe does not build, so it over-reports.

**Coverage caveat, stated rather than buried:** 13 production sites sit in files that do not set
`pipefail` locally. That is **not** a clean bill — a sourced helper inherits its caller's `pipefail`.
Conversely, a file invoked as `bash /usr/local/bin/foo.sh` gets a fresh shell and does **not** inherit
it. Neither is resolved here; "not locally set" is reported as a bound, never as "safe".

## 3. B — the number the disposition was supposed to turn on

**B = bounded / var-fed = 4/15 = 26%.**

| var-fed production sites | count |
|---|---|
| **bounded** (assignment resolves to a bound) | 4 |
| unbounded | 1 |
| **UNDECIDED** (assignment unresolvable) | **10** |

The threshold fixed *before* measuring was B >= 0.8 for triage to be considered available. **26% is
not close.**

> **An earlier revision reported `unbounded = 0`** for a corpus full of `docker`/`nft`/`journalctl`
> producers. That was not a finding — it was a broken instrument. FOUR separate anchoring bugs in one
> classifier (assignment position, RHS position, the `$(` gap, the `printf '%s\n'` format) each made a
> site *vanish* rather than misreport, which is why none of them announced itself. **An instrument that
> silently drops what it cannot parse reports a smaller, cleaner, wronger world** — and a zero is the
> most confident-looking unsupported verdict there is. Window analysis cannot triage this class.

The 10 undecided are undecided structurally, not lazily. The dominant shape is:

```bash
local e="${1:-}"                  # a function parameter
printf '%s' "$e" | grep -qiE ...  # its bound is a property of every CALLER, not of this line
```

Bounding those requires whole-program data-flow. **Calling them "bounded" because they feed a var is
exactly the inference that produced the discredited prior figure** — it asserts the consequent and
leaves the antecedent (*are the vars actually bounded?*) unestablished. They are reported undecided.

### The one genuine discriminator, and why it is not a byte threshold

The 4 bounded sites are bounded **by construction**. The argument needs stating precisely, because a
superficially similar claim was correctly retracted before.

A prior byte-threshold claim ("producers under N bytes are unreachable") was retracted as false
precision: an 8 KB producer read 0/200 unperturbed yet was still killed under `strace`. That
retraction was right — a frequency argument run backwards ("we didn't see it, so it can't happen") is
not proof of impossibility.

This is a different argument, and the producer must be **pinned** or it does not reproduce:

| producer | killed |
|---|---|
| `printf 'MATCH\n%s' "$(head -c 3498 ...)" \| grep -q MATCH` — single write, under capacity | **0/100** |
| `printf 'MATCH\n%s' "$(head -c 200000 ...)" \| grep -q MATCH` — single write, over capacity | **100/100** |
| `{ echo MATCH; for i in $(seq 1 5000); do echo pad; done; } \| grep -q MATCH` — multi-write | **300/300** |

A **single** `write()` below **glibc's stdio buffer (`st_blksize` = 4096)** cannot block: it completes
into the pipe buffer and the producer exits before `grep` can close the pipe, so no SIGPIPE is
deliverable.

> **An earlier revision put this boundary at the 64 KiB pipe capacity, and that was wrong** — the same
> error as the retracted byte threshold, wearing a construction argument as a disguise. Above 4096 the
> producer issues MULTIPLE writes (`head -c 60000` → 15 write() calls), so it is killable. Measured at
> the old rule's own boundary: `head -c 65535` is killed **3/100** here, and 158/200 on a busier host —
> load-dependent, and non-zero either way, which is all it takes to falsify "no SIGPIPE is
> deliverable". The two points that "justified" 65536 (400 B and 200 KB) both sit *outside* the
> failure band. Boundary corrected to ≤ 4096. B is unchanged, because the 4 bounded sites are
> `tail -c 400`: the rule was wrong, the answer was not. A
**multi**-write producer is killable at *any* size, because any write issued after grep's exit fails
regardless of buffer room — which is exactly why the 8 KB case died under `strace`, and why the byte
threshold deserved its retraction.

So the discriminator is not size. It is a *single non-blocking write*; size only enters as the
condition under which that write cannot block. The probe counts a site bounded only on an explicit
truncation (`head -c N` / `tail -c N`, `N ≤ 4096`). Shape alone never qualifies.

> **A reviewer could not reproduce the 200 KB row** and reported it as fabricated — correctly, given
> what they ran: a 200 KB blob containing **no newline** measures 0/300, because grep cannot match a
> line that has not terminated and so drains to EOF regardless of size. Same command, different
> producer, opposite result. The original text said "a 200 KB producer" without pinning the match
> position. **An unreproducible number *with* its command is worse than one without** — it looks
> audited. That is the prose-predicate-does-not-pin-a-count defect, committed inside the note that
> exists to correct it.

**The conclusion is invariant** across every refinement above: with the classifier resolving nothing,
B was 0%; with the construction rule, 26%. Both are far below the 0.8 bar. Nothing downstream turns on
which is right — stated so the precision is not mistaken for load-bearing.

## 4. Disposition

| subset | measured | disposition |
|---|---|---|
| production | 41 sites / 9 files | **TRACK** (one live site fixed here) |
| test-harness | 148 sites / 21 files | **TRACK** — never converted here |

Size alone said *convert* (41 <= 50, 9 <= 12). The security-rung auto-forfeit overrides it: all 9
production files touch a security seam by content (cosign/x509/credential, nftables/egress, RLS,
sandbox). The detector flags **9 of 9**, so it does not discriminate here — it is deliberately
over-inclusive, and its errors are fail-safe, because over-flagging forfeits to TRACK.

**But the forfeit's original rationale was backwards, and saying so is the point of this section.**
The plan justified it as "a wrong conversion yields a green gate that gates nothing." Tracing all nine
shows the opposite: `grep -q` early-exits **only on match**, and at every security site a match means
*the control is present/healthy*. So an inversion can only misfire in the healthy branch — a duplicate
nftables jump, a spurious self-heal, a false `ASSERT-FAILED`, a probe reporting RLS *not* enforced.
Each is noisy or fail-closed. **There is no fail-open path among them.** This class is *least*
dangerous exactly where the plan assumed it was most.

The honest reason not to convert blind is therefore narrower: the measured live exposure is one site
(now fixed), every security-seam inversion is fail-closed, and the remaining sites are undecided by a
method this note has just shown cannot decide them. That is a weaker claim than the one originally
written, and it is the one the data supports.

**On disclosure, honestly.** The plan required withholding per-site detail for security rungs because
this repo is public (`gh repo view --json visibility` => `PUBLIC`) and a ranked index of vacuous
security gates would be a targeting artifact. **That control was theatre and has been dropped rather
than performed**, for three reasons in order of weight:

1. **The exposure is fail-closed** (above). There is little to target.
2. **The list is one `git grep` away** for anyone with a clone, and the probe that regenerates it
   ships in this PR and prints the file list into public CI logs on every infra PR. A note withholding
   what the same PR publishes is a control that exists to be described, not to work.
3. **There is no ranked index to withhold anyway** — triage is unavailable, so nothing here can say
   which rungs are live-vacuous.

## 5. What would actually resolve this

Not a bigger ledger. Two options remain:

1. **Convert the class blind** — `| grep -q<flags> P` -> `| grep -<flags> P >/dev/null`, removing the
   early exit and therefore the window, at every site, with no per-site judgment. Measured
   semantics-preserving. Recorded as UC-3 in this branch's `decision-challenges.md`; it reverses
   operator-stated direction, so it is surfaced with data rather than decided here. The naive `sed` is
   unsafe (`-qE` + `-F` yields conflicting flags), and dropping `-q` makes grep read to EOF — harmless
   on a bounded producer, a hang on an unbounded one.
2. **Whole-program data-flow** on the 10 undecided var sources — the only thing that would make a
   per-site ledger honest, and a real project rather than a by-product of a fix.

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

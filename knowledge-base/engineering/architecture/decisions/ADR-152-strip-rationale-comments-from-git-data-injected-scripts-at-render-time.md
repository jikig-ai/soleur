# ADR-152 — Strip rationale comments from rendered `user_data` at render time

- **Scope:** git-data's injected scripts (2026-07-29) and the registry's cloud-init template
  (2026-08-04, #7278). The technique is shared; the EXPRESSION is deliberately not — see the
  amendment. Filename kept at its original slug so cross-references do not churn.

- **Status:** Accepted
- **Date:** 2026-07-29
- **Issue:** #6982
- **Related:** ADR-147 (boot-stage diagnostics live in baked host scripts — why zero-cost
  baking does not transfer here), ADR-149 (git-data birth route; dark-host
  indistinguishability), ADR-080 (bake-and-extract, unavailable to git-data), ADR-068
  (multi-host workspaces / git-data store)

## Context

Hetzner's `user_data` limit is a hard **32,768 B** gate on `hcloud_server.git_data`. The
resource carries no `lifecycle.ignore_changes = [user_data]`, so it is **ForceNew**: exceeding
the cap does not degrade anything, it fails the birth apply outright.

The payload is `cloud-init-git-data.yml` plus nine `file()`-injected scripts and units
(`git-data-bootstrap.sh`, `git-data-gc.sh`, `git-data-provision.sh`,
`git-data-transport-wrapper.sh`, `git-data-remove.sh`,
`git-data-pre-receive-placeholder.sh`, `git-data-gc.service`,
`git-data-gc-failure.service`, `git-data-gc.timer`).

#6982 landed two user-facing fixes that ship inside that payload — `receive.unpackLimit=1`
plus inode telemetry (a silent ENOSPC-on-inodes path), and `EnvironmentFile=-` on both gc
units (the failure reporter died on the failure it exists to report). With both applied the
payload measured **33,028 B — 260 B over the cap**, with B7, B11 and B12 still queued and also
inside `user_data`.

Two facts made this an architecture decision rather than a wording exercise:

1. **Comments are 61% of the raw payload** — **42,149 of 68,963** raw bytes across the ten
   files at `ba9423922` (the commit before the strip); `cloud-init-git-data.yml` alone carries
   15,772 comment bytes of 27,582, and `git-data-bootstrap.sh` 9,410 of 15,610. Reproduce with:

   ```sh
   d=$(mktemp -d); git archive ba9423922 | tar -x -C "$d"
   cd "$d/apps/web-platform/infra" && python3 -c '
   import os
   fs=["cloud-init-git-data.yml","git-data-bootstrap.sh","git-data-pre-receive-placeholder.sh",
       "git-data-provision.sh","git-data-transport-wrapper.sh","git-data-remove.sh",
       "git-data-gc.sh","git-data-gc.service","git-data-gc-failure.service","git-data-gc.timer"]
   t=c=0
   for f in fs:
       for l in open(f):
           t+=len(l.encode())
           if l.lstrip().startswith("#"): c+=len(l.encode())
   print(c,t,round(100*c/t,1))'
   ```

   An earlier revision of this ADR said "42,277 of ~69,182". Those were measured mid-session
   against an uncommitted tree and are not reproducible from any commit in the branch; the
   figures above are, which is why the command ships next to them.
2. **Prose trimming returns badly after gzip.** Two rounds of comment-trimming during the
   session moved `stored` from 33,220 B to 33,096 B and then to 33,028 B — roughly 60-125 B
   of *stored* return per round, against edits of several hundred raw bytes each. (These were
   intermediate working-tree states, not commits, so they are recorded as what was observed
   rather than as something re-runnable.) At that rate, fitting the remaining fixes by hand
   meant cutting on the order of 3,000 raw bytes of rationale — and that rationale is exactly
   what explains why each fail-closed invariant exists, on a host where ADR-149 records that
   "a green `terraform apply` and a dark host are indistinguishable."

## Decision

**Strip whole-line `#` comments from the nine injected payloads at render time**, in
`git-data.tf`, via a shared local:

```hcl
git_data_rationale_strip = "/(?m)^[ \t]*#([^!\n][^\n]*)?\n/"
```

`cloud-init-git-data.yml` itself is **not** stripped. The repo keeps its full rationale;
`user_data` stops paying for it.

    before: 33,028 B stored (over cap by 260 B)
    after:  19,588 B stored (13,180 B headroom) at the moment of the strip
    now:    20,456 B stored (12,312 B headroom) with B7/B11/B12 and the review
            fixes added back on top

The expression is **anchored at line start** and **preserves `#!` by construction**.

The class is `[^!\n]`, not `[^!=\n]`. The first draft excluded `=` as well, which was an
accident rather than a carve-out: it left exactly one unstrippable class (a comment whose
first character after `#` is `=`, with no space, e.g. `#===== banner`) for no stated reason.
Zero such lines exist in the nine, so narrowing it costs nothing and stops the expression
from quietly disagreeing with its own documented intent.

### Why the anchoring and the `#!` carve-out are load-bearing

A `#`-anywhere rule (`s/#.*//`) breaks four of the six scripts on `${var#...}` parameter
expansion — measured, `bash -n`. Only the anchored form is safe.

Preserving the shebang is not cosmetic, and the reason is a silent-failure path rather than a
loud one. Losing line 1 does **not** fail uniformly:

| payload | invoked by | effect of a lost `#!` |
|---|---|---|
| `git-data-gc.sh` | systemd / doppler, directly | **ENOEXEC**, unit dies (loud) |
| `git-data-pre-receive-placeholder.sh` | git execs hooks via `execvp` | **silently falls back to `sh`** — see below |
| `git-data-provision.sh`, `git-data-remove.sh`, `git-data-transport-wrapper.sh` | `authorized_keys` `command="…"` | **silently falls back to `sh`, which is dash on 24.04** |

That is the same defect class as the `EnvironmentFile=-` fix in this very PR: dash and bash
diverging silently on a fail-closed host. **FOUR of the nine** would degrade without erroring,
not three — an earlier revision of this table put the pre-receive hook in the loud column.
Review executed it: a hook with no shebang, mode 755, against git 2.53 **ran via the `sh`
fallback and the push SUCCEEDED** (POSIX mandates `execvp` retry `/bin/sh` on `ENOEXEC`).
The consequence there happens to be benign — dash does not know `set -o pipefail`, so it exits
non-zero and the hook's fail-closed contract survives — but the classification was wrong, in a
table whose entire purpose is enumerating which losses are loud. Correcting it makes the `#!`
carve-out MORE load-bearing, not less.

## Consequences

### Guards, because none of this is self-enforcing

`apps/web-platform/infra/git-data-render-strip-parity.test.sh`
(registered in `.github/workflows/infra-validation.yml` — nothing auto-discovers `infra/`):

1. **Strip-expression parity.** `git-data-userdata-budget.sh` carries an independently
   hand-mirrored copy of the templatefile map, and it is the render harness for
   `git-data-emit.test.sh` and `git-data-runcmd-rehearsal.test.sh`. A `replace()` added to one
   and not the other means **CI renders a different payload than production, silently**, on
   the gate whose entire job is to be the thing you trust. Nothing compared them before. The
   arm is mutation-proven: drifting either file reddens it.
2. **Downstream-parser invariants.** `plugins/soleur/test/cloud-init-user-data-size.test.ts`
   locates the templatefile map by counting **brace depth** and parses entries with a
   **line-based** regex. So the strip expression must contain **no brace**, and all nine map
   entries must stay on **one physical line** each. `terraform fmt` realigns `=` but does not
   wrap, so this holds — but it is now a stated invariant rather than an accident.
3. **Rendered-payload integrity.** Every rendered shell payload must still begin with `#!` and
   pass `bash -n`, with a floor of 6 so "found nothing to check" cannot read as "everything
   passed", plus verify-the-verifier arms proving the strip is not a no-op and does not touch
   mid-line or trailing `#`.

   > **Scoped 2026-08-20 (#7613):** that last clause is a property of **the render's** strip
   > expression, and it is true of it. It was read as a property of the whole pipeline, which
   > it is not — the *test suite* runs a SECOND, independent strip when it derives its
   > `.code.sh` corpora. Until #7613 that one was whole-line-only and left trailing `#`
   > standing; #7613 extends it to blank ` # ` tails as well. Either way the clause above is a
   > property of the RENDER's expression, not of the pipeline. See the amendment at the end.

`git-data-runcmd-rehearsal.test.sh`'s B1 byte-identity check now compares against the
**stripped** source, reading the expression out of `git-data.tf` rather than restating it — a
hand-copied fourth spelling would drift, and a stripper that silently disagreed with
production would make B1 compare the wrong bytes while still reporting byte-identity. It fails
closed if the expression is absent, is not a `/…/` literal, or matches nothing on a
known-commented probe.

### Costs accepted

- **On-host debugging loses rationale.** The scripts on the booted host carry code without the
  comments that explain it. Mitigated by the payloads being byte-derivable from the repo at
  any commit, and by B1 asserting exactly that correspondence.
- **A new transformation sits between repo and host.** Bounded by the guards above; the
  transformation is a single anchored regex with no state.

### Hazard classes checked and found empty

Verified across the nine files before adopting the dumb stripper: zero heredocs, zero
comment-after-line-continuation, zero comments inside multi-line strings, zero comment-only
`then`/`do`/`{}` blocks, and zero comment-anchored assertions anywhere in the repo against
these files. Guard 3 exists to keep it that way.

The `%{`/`${` template-escaping trap does not apply: `templatefile` does not re-scan an
interpolated value, and `cloud-init-git-data.yml` has zero `%{` directives (enforced by
`git-data-luks.test.sh` A26). The 37 `$${…}` escapes live in the template, which is not
stripped.

## Alternatives considered

### Comment-freeze, per the `server.tf` precedent — REJECTED

`server.tf:200-205` records the repo's existing answer to this pressure: *"cloud-init.yml is
effectively comment-frozen; .tf files cost nothing."*

That was **containment adopted under duress** — the web host had ~300 B of headroom and no
cheaper lever, because it already had ADR-080 bake-and-extract. git-data cannot use ADR-080
(on record in `git-data.tf`). Comment-freeze stops future growth and recovers **nothing** of
what is already spent. To actually recover bytes under it you must relocate ~26 KB of
line-adjacent rationale into the `.tf` — divorcing each comment from the line it explains (the
`EnvironmentFile=-`/dash reasoning is only intelligible sitting directly above the directive),
across nine safety-critical files, repeated by every future author.

Stripping makes comments **free, permanently**. It removes the tax that forced comment-freeze
rather than institutionalizing a documentation tax on the most safety-critical files in the
repo.

### Hand-trim ~3,000 raw bytes of comments — REJECTED

Preserves the mechanism but degrades the rationale, and buys only one round: the next feature
hits the cap immediately. Measured return was 68 B stored per ~450 raw bytes trimmed.

### Move scripts off `user_data` to a boot-time fetch — REJECTED

Adds a network dependency to a deliberately fail-closed boot. Strictly worse for a host whose
entire design property is that a failed boot is loud rather than dark.

### Descope B7/B11/B12 to a follow-up — REJECTED

`user_data` is ForceNew and the host is **not yet born** (#6982 and #7025 both open), so these
bytes are free now and cost a destroy-before-create replacement of the store holding every
user's source after birth. Deferring also leaves a known silent-failure path live: B7 is the
timer arm, the sole defence against unbounded growth, which can fail to arm while the host
reports healthy.

## Scope

This ADR covers the render-time transformation only. The birth dispatch and the rung-2 boot
rehearsal remain out of scope for #6982 and are carried by #7025; the DO-NOT-DISPATCH banner
stays up, and #6982 additionally re-arms the birth interlock mechanically
(`git_data_rung2_rehearsal_gate`) so that hold is no longer prose alone.

## Amendment (2026-08-04, #7278) — extended to the registry host, with a DIFFERENT expression

`hcloud_server.registry` was measured at **34,628 B** against the same 32,768 B cap — over it,
and therefore unprovisionable, before anyone tried to add to it. Because ADR-096 makes the
registry host cloud-init-only, a provisioning event is its only channel for host-side change,
so the cap breach silently disabled EVERY path that creates this host —
`registry-host-replace`, `registry-luks-recut` AND `registry-region-migrate`
(apply-web-platform-infra.yml) — independently of their own gates. The region-migrate omission
is the one that matters most in practice: that is the lever an operator reaches for when the
REGION is the problem, i.e. exactly when they are least likely to suspect a byte cap. This ADR's technique is what brought it
back under (34,628 → 9,072 B).

**The expression is deliberately not shared, and must not be.** The rule above
(`/(?m)^[ \t]*#([^!\n][^\n]*)?\n/`) preserves `#!` and nothing else. That is correct for the
artifacts this ADR was written about — the nine INJECTED SCRIPTS — and it is wrong for a
cloud-init template, because it deletes `#cloud-config`. Deleting it does not fail: the apply
succeeds, the host boots, and cloud-init never recognises the payload, so none of it runs.
That is the dark-host indistinguishability ADR-149 names, reached through the mechanism this
ADR introduced.

The registry uses `/(?m)^[ \t]*#([ \t][^\n]*)?\n/` (`local.registry_rationale_strip` in
`zot-registry.tf`): a `#` line is rationale only when followed by a **space/tab**, or when
**bare**. This preserves `#cloud-config` and `#!` by construction rather than by enumeration.

**The generalizable rule, for the next host:**

| What is being stripped | Safe expression | Why |
|---|---|---|
| Injected scripts (both hosts) | preserve `#!` only | scripts have no `#`-directive but a shebang |
| The cloud-init template itself (registry) | preserve `#!` **and** any `#`-directive without a separator | `#cloud-config` is load-bearing and is a comment by syntax |
| A **test suite's** `.code.sh` corpus, derived from an already-stripped render (#7613) | preserve `#!`, `${var#pat}`, `$#` and a URL fragment — strip only ` # ` tails. **Python `re`, so `[ \t]+#([ \t].*)?$`, NOT `[[:space:]]`** | the input is shell that has ALREADY been through the render strip, so what survives is mid-line and trailing `#`, which is exactly what the other two expressions are not built to touch |

Do not port an expression between these two cases. Verify the divergence the same way #7278
did: assert the first line survives, assert every shebang survives, and assert the strip is
not a no-op — a strip that matched nothing satisfies both preservation checks while leaving
the payload over the cap.

**One copy per expression — and know what that does NOT buy.** git-data's is hand-mirrored into
`git-data-userdata-budget.sh` and kept equal by `git-data-render-strip-parity.test.sh`. The
registry's is instead **extracted** from `zot-registry.tf` by
`plugins/soleur/test/cloud-init-user-data-size.test.ts`. Prefer extraction for a future host: a
model that strips differently than production measures a payload production never boots, and
measures it green.

But extraction removes only EXPRESSION divergence. It does not replace git-data's
`git-data-userdata-budget.sh`, which exists for a reason extraction cannot satisfy — it renders
through terraform's OWN `base64gzip` from an empty scratch dir with no `terraform init`, i.e. a
byte-exact measurement. The TS model is explicitly not that (node zlib vs Go zlib; it asserts a
BUDGET, never equality), so the registry has no byte-exact CI measurement today. At 9,072 B
against 32,768 that is acceptable on margin; it is a gap, not a solved problem.

> **CLOSED 2026-08-06 (#7299).** `apps/web-platform/infra/registry-userdata-budget.sh` is now
> that byte-exact measurement for the registry, and it runs in CI. Read the paragraph above as
> history. Note how the gap closed, because it is the cautionary half: the script shipped in
> #7283 measuring the render WITHOUT the strip, reported a phantom 3,636 B breach, and #7299 was
> filed against that reading as an outage. Its first fix then reproduced the defect named in the
> paragraph below — it asserted the expression was DECLARED and not that it was APPLIED, which
> review caught before merge. Current measurement: 9,408 B stored, 23,360 B of headroom.

Extraction also does not prove the strip is APPLIED. Reading the expression out of the `.tf`
says nothing about whether `user_data` wraps `templatefile()` in it — measured: unwiring the
`replace()` and leaving the local orphaned kept the whole suite green while the render returned
to 34,628 B, and so did keeping `replace()` with an inline boot-bricking literal. git-data hit
the identical class (`git-data-render-strip-parity.test.sh`: "nothing checked that the budget
harness actually APPLIES it"). Assert on the RENDER EXPRESSION, not on a string in a file.

**Coverage gap this closed, and the one it did not.** `cloud-init-user-data-size.test.ts`
guarded the web and git-data hosts and had no registry arm at all, which is why a 1,860 B breach
sat undetected. Any host whose `user_data` is rendered against the cap needs an arm there at
birth, not after a breach.

**The sweep is OUTSTANDING, not done.** After #7278 two further hosts still render
`base64gzip(templatefile(...))` with no arm in that suite: `hcloud_server.inngest`
(`inngest-host.tf`) and the grok-dogfood host (`grok-dogfood.tf`). Both are under cap today and
neither is this PR's scope — but they are on the same unguarded trajectory the registry was on,
and this paragraph is the record that the gap is known rather than closed.

## Amendment (2026-08-11, #7264) — git-data's own cloud-init template is now stripped too

This ADR's original scope stripped the **nine injected payloads** and explicitly left
git-data's `cloud-init-git-data.yml` alone; the 2026-08-04 amendment then extended the
technique to the registry host with a deliberately **different** expression, and recorded the
generalizable rule as a two-row table for "the next host". git-data is that next host, and it
now occupies **both** rows of its own table.

**What changed.** `modules/git-data-userdata/main.tf` declares a second local,
`git_data_template_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"` — byte-identical to
the registry's `registry_rationale_strip` — and the render is wrapped
`replace(templatefile(…), local.git_data_template_rationale_strip, "")`, mirroring
`zot-registry.tf`. The payload expression is **unchanged**.

**Measured** (terraform's own `base64gzip`, via `git-data-userdata-budget.sh`):

| | raw | stripped | stored | headroom |
|---|---|---|---|---|
| before | 67,479 B | — | **30,376 B** | 2,392 B |
| after | 67,479 B | 36,805 B | **12,588 B** | **20,180 B** |

Recovery is **17,788 stored bytes**, and headroom goes from 7% of the cap to 62%.

**Why two expressions and not one.** This amendment does not relax the rule above it — it
applies it. The payload form preserves `#!` and nothing else, which is correct for scripts
that have a shebang and no `#`-directive, and *wrong* for a cloud-init body, where
`#cloud-config` is a directive that is a comment by syntax. That was verified rather than
assumed: applying the payload expression to the git-data render produces a document whose
first line is `package_update`, and `cloud-init schema -c` rejects it with *"Expected first
line to be one of: #!, ## template: jinja, #cloud-boothook, #cloud-config, …"*. A collapse of
the two expressions is therefore a dark-host defect, and it is one line away at all times —
so `git-data-render-strip-parity.test.sh` now asserts they are **distinct**, in addition to
mirroring each independently.

### The verification triad, and the gate that was blind to it

This ADR prescribes three arms — first line survives, every shebang survives, the strip is not
a no-op. All three now run for git-data, in `git-data-template-strip.test.sh` (registered in
`infra-validation.yml`), alongside two that the triad does not cover:

- **Per-entry byte diff.** Top-level keys and `runcmd`/`write_files` entry *counts* are
  invariant under corruption *inside* a `write_files` content string or the `LUKSEOF` heredoc
  body, so a shape comparison passes over a deleted data line. The arm asserts each entry
  differs from its unstripped twin **only** by lines the expression matches.
- **Interpolation reachability.** The strip runs over the *rendered* output, so it sees
  interpolated values. Nine interpolation sites sit at the start of a line
  (`${indent(6, git_data_bootstrap)}` and its siblings) and six of those payloads begin with
  `#!/usr/bin/env bash`; they survive only because `!` is not `[ \t]`. That was true by
  accident and is now asserted.

**A gate was validating the wrong document.** `.github/scripts/validate-infra-templates.sh`
renders the **bare** `templatefile()` and runs `cloud-init schema -c` on it. Once a call site
wraps the render in `replace(...)`, that gate validates a document no host is ever given — and
worse, the *one shape that cannot fail*, because the unstripped body still carries its header.
The script now resolves the call site's strip local and applies it before validating. This
affected the registry host too — from **#7280** (`d0295964f`), the commit that actually
shipped the registry's `replace()` wrap, not #7278 where this amendment was written.
Mutation-proven in both directions.

**Still outstanding**, unchanged from the amendment above: `hcloud_server.inngest` and the
grok-dogfood host still render `base64gzip(templatefile(...))` with no arm in
`cloud-init-user-data-size.test.ts`. Under cap today; on the same unguarded trajectory.


---

## Amendment — 2026-08-20 (#7613): a THIRD strip exists, in the test suite, and it is not this one

### What was inconsistent

The Decision above says the render's strip "does not touch mid-line or trailing `#`". That is
true, and it is a property of the RENDER. It was read one scope too wide.

`git-data-runcmd-rehearsal.test.sh` derives two `.code.sh` corpora from the already-stripped
render, using its own independent expression — `^\s*#`, whole-line-only. So the pipeline has
**two** strips in series, and the second one is the only thing standing between a trailing
comment and the R3 family's predicates. Nothing in this ADR said so, and a reader checking
"can a predicate be satisfied by a comment?" against this file alone would have concluded no.

### The rule-table row, and why the expression differs

The new row above is not a third dialect for its own sake. Its INPUT is different: it receives
shell that has already been through the render strip, so whole-line comments are gone by
construction and what remains is precisely the mid-line and trailing `#` the other two
expressions are not built to touch. `[ \t]+#([ \t].*)?$` — written for Python `re`, which has no POSIX classes, so
`[[:space:]]` there is the literal set `{[,:,s,p,a,c,e,]}` and strips nothing — requires whitespace
before the `#` and either end-of-line or whitespace after it, which is what preserves
`${var#pat}`, `$#`, `#!` and `#` inside a URL fragment.

**Do not reuse `_b2_strip` for this.** The suite already contains `sed -e 's/[[:space:]]*#.*$//'`
under that name, and #7613's issue body proposed it as the ready-made fix. Measured against a
synthesized fixture, its zero-width prefix (`*`, not `+`) destroys all four:

| input | `_b2_strip` | the new expression |
|---|---|---|
| `base=${path#/prefix/}` | `base=${path` | `base=${path#/prefix/}` |
| `argc=$#` | `argc=$` | `argc=$#` |
| `url="…/#anchor"` | `url="…/` | `url="…/#anchor"` |
| `#!/bin/sh` | *(empty)* | `#!/bin/sh` |

### What the change is worth, stated honestly

**It is a measured no-op today, and ships as prophylaxis.** Re-measured against a fresh render
on 2026-08-20, independently of the plan that proposed it:

- `luks-stage`: 55 lines → 55, **0** lines containing `#` after the current whole-line strip.
- `runcmd-all`: 170 lines → 170, **1** such line —
  `STAGE=volume_mount # (#6982) name the stage for the top-armed on_err fatal`.
- `volume_mount` is matched by **zero** predicates in the suite, so the one survivor is on a
  line nothing reads.
- **0** at-risk tokens (`${var#pat}`, `$#`, `#`-in-string) in either artifact.

So it changes one line in one artifact and no arm's verdict. It is retained because the
property it buys — a predicate cannot be satisfied by the commentary that explains it — is one
the suite asserts elsewhere and should not depend on the render's strip continuing to be
exhaustive. The suite's own comment says this in the same words, rather than implying the
change fixed something live.

**Known false positive, and it is a LATENT BREAK rather than a bound.** The expression strips
`msg="value # not a comment"` to `msg="value`. There are zero such lines in either artifact
today — measured — but an earlier revision of this paragraph claimed "the suite asserts that
count", and it does not: no assertion anywhere measures surviving trailing comments or at-risk
tokens in the real corpora. Those numbers live only in prose. Worse, this particular shape is
undetectable by the guard that does exist, because `_b2_strip` corrupts it identically, so a
parity check stays green. Asserting an assertion is the same defect class this ADR's amendment
is about, so it is stated as what it is: if such a line is ever introduced upstream, nothing
here will catch it.

**And the rule-table row above states a guarantee the expression lacks.** It says the expression
preserves "`#` inside strings". It preserves a URL fragment (`#` with no preceding whitespace)
and does NOT preserve a ` # ` sequence inside a quoted string. The table is the normative artifact
this ADR tells the next host to port from, so the row names the narrower, true property.

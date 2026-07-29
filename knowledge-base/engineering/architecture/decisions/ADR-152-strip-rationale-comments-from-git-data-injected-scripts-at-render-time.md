# ADR-152 — Strip rationale comments from the git-data injected scripts at render time

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

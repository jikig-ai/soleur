# RESUME — #7277 D10 gate PASS condition

Updated 2026-08-05 (third session). **All five blockers are closed.** Every command below was run;
nothing is recalled.

---

## State

| | |
|---|---|
| Branch | `feat-one-shot-7277-d10-gate-pass-condition` |
| PR | **#7290** — OPEN, **DRAFT** until the exit gate is green |
| Suites | `test-registry-pull-path-health.sh` **59/0**, `test-registry-restore-from-ghcr.sh` **43/0** |
| Mutation battery | committed + registered; **40+ caught, 0 unexplained survivors**, 3 documented-unreachable with reachability proofs |
| `terraform-target-parity` | **103/0** (was 2 RED for the life of the branch) |
| Net issue flow | 0 — closes #7277, files #7295 |

---

## What the blockers turned out to be

**B1 — A5 deleted.** Routed to the `soleur:engineering:cto` agent as an architectural fork rather
than picked inline. Ruling: DELETE, on three independent grounds — A5's only distinctive abort arm
fires on an htpasswd divergence *the recut itself repairs*; the authorisation-vs-availability call
is undecidable on the CF-tunnel transport (#7242 / ADR-166); and that transport is fail-closed and
cannot carry the asymmetry. **R2 is reversed and recorded as a reversal** (plan review row R16),
not edited away. A5's asymmetry was SOUND and is recorded as sound in three places, because a
future reader will re-derive it, find it valid, and be tempted to re-add the predicate.

**B2 — rehearsal split** into `registry_pull_path_gate`, which `registry_luks_recut` now `needs:`.
Buys a failure-semantics property (a timeout there destroys nothing); buys **no** mutex release,
and says so — worst case is now the sum across three jobs, **135 min**, not the 90 the restore
job's header claimed after the split.

**B3 — resolved BY the split**, not by the hoist it proposed. The hoist is recorded as rejected
with its reason (widens the plan→apply gap against a lock-less R2 backend).

**B4 — the claim was right; its evidence was not.** The cited `crane ls NAME_UNKNOWN` was
uncredentialed and hit the tags API, so it could not separate absent from not-visible. Re-measured
with a positive control: the producing workflow has **never been dispatched** and the Terraform
pointer secret does not exist. So the entry stays `conditional` and `FLOOR` stays **4** — the
opposite of the promotion the blocker anticipated. Corrected in **three** sites; the blocker named
two.

**B5 — closed structurally.** The manifest is uploaded AFTER the verdict, so the artifact the
restore consumes IS the inventory the rehearsal proved. `manifest_sha256=` on both verdict lines,
and the ordering is pinned by a test.

---

## What was found that was on nobody's list

This is the part worth carrying forward.

**The mutation battery was ad-hoc.** "15/15 and 13/13 caught" lived in a session transcript, so it
protected nothing the next day. Committed and registered, its first run found **15 of 44 mutations
surviving** — guards both suites certified and neither tested, including the `GITHUB_ACTIONS` seam
guard, which is the only thing preventing `REGISTRY_GATE_RESTORE_CMD=/bin/true` from manufacturing
`verdict=AUTHORIZED`. Every other row in the suite ran without `GITHUB_ACTIONS` set, so nothing
ever reached it.

They share one shape: **deleting the guard still exits non-zero**, via some later check. A row
asserting only `rc != 0` cannot see the guard at all. What differs is WHICH code and WHICH message
— and here the exit code is operational policy, since 3 is retryable and 4 is not.

**Three live defects, not test gaps:**

- `last_err` bounded the last 400 **bytes** while `classify()` documented the last **line**, and
  `classify()` substring-matches, so its first case arm won over the whole capture. On a
  *conditional* pin that turned a credential rejection into a silent declared skip. Nothing but the
  battery could find it: every real crane message is under 400 bytes, so the two implementations
  are indistinguishable on every existing fixture.
- **Value-taking flags with no value spin forever** (both scripts). Demonstrated, not reasoned. In
  a runner that is a hang to the job timeout — a *cancellation*, so no `::error::` and no diagnosis.
- **The exit-5 operator remedy was wrong-directional.** It said "rotate `ZOT_PUSH_*` in Doppler".
  `/etc/zot/htpasswd` is baked ONCE at boot, so a rotation makes a transient rejection *permanent*.
  Found at CPO re-sign-off, verified against `cloud-init-registry.yml` §2g. Replaced with
  measure-then-re-bake.

**A pre-existing RED.** `terraform-target-parity` had been 2/103 failing for the life of the branch
— the step-order SAFETY property for the job that destroys the sole pull path — because a step
rename left its needle stale. That is the concrete cost of the VOID exit-gate run, not a
hypothetical one.

---

## Sign-offs

- **CTO** (`soleur:engineering:cto`) — B1 ruling (delete A5) + B2 ruling (split). Recorded in
  ADR-169 and plan row R16/R17.
- **CPO** (`soleur:product:cpo`) — **re-obtained**, because the original rationale read "signable
  specifically because of A5's abort/degrade boundary" and A5 is gone. Verdict: SIGNED OFF WITH
  AMENDED CONDITIONS. Conditions 2/3/5/6/7 unchanged, 1 and 4 amended, **8 and 9 added as blocking**
  (the exit-5 remedy, and the bridge failure as a post-destroy arm).

---

## Gates

```
bash tests/scripts/test-registry-pull-path-health.sh          # 59/0
bash tests/scripts/test-registry-restore-from-ghcr.sh         # 43/0
bash tests/scripts/test-registry-gate-mutation-battery.sh     # 0 unexplained survivors
cd plugins/soleur && bun test test/terraform-target-parity.test.ts   # 103/0
bash apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh   # 53/0
bash tests/scripts/test-registry-luks-recut-gate.sh           # 37/0
actionlint .github/workflows/apply-web-platform-infra.yml
grep -c "no valid PASS condition" scripts/registry-pull-path-health.sh   # 0
bash scripts/test-all.sh   # launch on a CLEAN tree; do not edit under it
```

Scope guards re-verified: ADR-096 `unowned constraint` = **2**, Status **Adopting**, ADR-169 still
next-free against freshly-fetched `origin/main` (highest is 168). No recut dispatched, no
`terraform apply`.

### Process trap that cost three shells in session two

`pgrep -f`, the bracket trick, and matching on `/proc/<pid>/cmdline` **all self-match**, because
the pattern sits in the matcher's own command line. Write commit messages with the Write tool, then
`git commit --file`; never compose a heredoc in the same Bash call as something that can kill the
shell. Long runs need `setsid nohup` and an **rc file** — a background task's completion
notification reports the trailing command, not the one you care about.

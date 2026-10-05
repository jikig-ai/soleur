# The guard I wrote to close #7378 reopened it, one field to the left

**Date:** 2026-08-10 · **PR:** #7379 · **Issue:** #7378

## Problem

`registry-luks-recut` destroys production's only container registry store. Its D10 gate has a
predicate A2 — a rehearsed restore — that ADR-169 makes the gate's PASS condition. A2 failed on
every run, so the dispatch was structurally unfireable during the incident it exists to recover
from. Cause: `crane validate --remote` walks an OCI index's children and gunzips every layer, so a
buildx attestation child (one `application/vnd.in-toto+json` layer, plain JSON, never compressed)
failed with `gzip: invalid header`.

The fix verifies the index per child: platform children keep `crane validate`, attestation children
are verified by blob presence.

## The bug the fix shipped with

The attestation test read:

```bash
children="$(jq -r '(.manifests//[])[] | [.digest, (.annotations["..."] // ""), (.platform.architecture // "")] | @tsv' ...)"
while IFS=$'\t' read -r c_digest c_type c_arch; do
  if [[ "$c_type" == "attestation-manifest" || "$c_arch" == "unknown" ]]; then
```

**Tab is an IFS-*whitespace* character, so bash `read` collapses runs of it and drops empty middle
fields.** `@tsv` emits an empty field for an absent key. So an attestation child carrying only
`platform.architecture: unknown` and no annotation renders as `digest<TAB><TAB>unknown` and parses:

```
digest=[sha256:b22]  type=[unknown]  arch=[]
```

Neither disjunct fires. The child goes to `crane validate`, gunzips the in-toto layer, and exits 4
with a message asserting *"This is no longer the buildx-attestation false positive."*

The `|| c_arch == "unknown"` disjunct — documented in the code as *"the shape-stable one"* — was
**unreachable in exactly the case it was written for**. It could only be reached when the annotation
was also present, i.e. precisely when it was redundant.

Fix: sentinel every `@tsv` field with `"-"`, so no field is ever empty and no collapse is possible.

## Key insight

**A guard that can only fire when it is redundant is indistinguishable, in every green test run,
from a guard that works.** The fixture set the OR to true on both sides, so dropping *either*
disjunct left the suite at 51/0. Nothing in the suite could tell a load-bearing signal from a dead
one, because no fixture ever separated them.

Generalisable rule: **when a predicate is a disjunction, at least one fixture must satisfy each
disjunct ALONE.** A fixture that sets every signal at once proves only that the set is non-empty.

The same shape recurred four more times in this PR: `n_children > 0` (could not see partial
enumeration), `ref_repo` (never called by any test), `verify_die`'s NETWORK/DENIED arms (no failing
`manifest:` fixture existed anywhere), and the whole 106-line new test block (deleting it left the
suite green at 43/0 — there was no assertion floor).

## What actually caught it

Not the suite, not `tsc`, not shellcheck, not CI. A 10-agent review panel, and specifically the
agents that were told to **find the vacuity my own battery missed rather than re-run its
mutations**. My RED→GREEN transition (44/7 → 51/0) proved the *mechanism* and pinned almost none of
the *guards*.

Two agents independently ran mutation batteries against the delivered suite and found 6 and 10
surviving mutants respectively. Overlap was partial — the union was larger than either.

## Prevention

- **Sentinel `@tsv` fields** whenever any key can be absent and the row is read with `IFS=$'\t' read`.
  Or use a non-whitespace delimiter. Never rely on positional fields from `@tsv` with optional keys.
- **One fixture per disjunct**, always. Litmus: *name the mutation that satisfies this assertion
  while violating the property.*
- **An assertion-count floor** (`MIN_ASSERTIONS`, a floor never an equality) so deleting the block
  is loud.
- **Extend the mutation battery in the same PR as the guards.** It dispatched 45 against a floor of
  45 — zero headroom — while certifying pre-PR code only.

## Session Errors

1. **The IFS tab-collapse bug above.** Recovery: `-` sentinel per field. **Prevention:** the rule above.
2. **A vacuous positive control, self-caught mid-flight.** The index positive control passed against
   the pre-fix engine because `ok_fixtures` still supplied a whole-index `validate:` fixture.
   Recovery: delete that fixture in `att_index_fixtures` so the pre-fix path hits the stub's
   no-fixture arm. **Prevention:** for any "this case is RED before the fix" claim, verify the RED is
   caused by the thing under test, not by a fixture that happens to be present.
3. **Read the sink index by TAG.** `crane manifest <tag>` does not verify returned bytes
   (go-containerregistry: *"Do nothing for tags; I give up"*), so this dropped the index's only
   byte-integrity check and added a TOCTOU. **Prevention:** when replacing a call, enumerate what the
   OLD call verified that the new one does not.
4. **`|| true` on a streaming jq.** `.manifests[]` emits elements 1..k-1 then exits 5 on a fault at
   k; the truncated list passed every downstream guard. **Prevention:** capture rc; never `|| true`
   on a filter whose partial output is usable.
5. **Two over-claiming operator messages.** `verify_die` asserted "the manifest resolves" at the two
   sites where the manifest read failed; the LAYERFORMAT text asserted the attestation false positive
   was impossible, which would rebuild the original 6-day trap with a confident label.
   **Prevention:** a message must not name a cause the code did not measure — this file's own header
   says so twice, and it was violated anyway.
6. **Exit 6 for a NAMED condition**, contradicting the exit-6 runbook row this same PR wrote.
7. **Four documentation claims asserted without measuring:** both Hetzner probes listed as cold when
   both ran in the gate job; "a registry the recut never touches" (it reads GHCR every entry); "no
   new exposure surface" (this is the first path that fetches attestation blob bytes); and an AC
   asserting set equality that a documented deviation made unsatisfiable. **Prevention:** for every
   claim a diff ADDS, name the command that would falsify it and run it.
8. **I argued a scope-out on "verifiability" that was actually scheduling.** The CONCUR gate pointed
   out the battery already uses the restore suite as its oracle, so the rows were a transcription of
   evidence I already held. **Prevention:** when deferring, state what evidence is missing; if the
   answer is "none, it just takes time", that is not a criterion.
9. **I classified the signature blob gap as `pre-existing-unrelated`.** Pre-existing was true;
   unrelated was not — verification 3 is a numbered step of the same predicate, in the same file,
   50 lines below the change. **Prevention:** "unrelated" is about topology, not chronology.
10. **I edited a file while `test-all` was running**, invalidating a 275/275 run and producing two
    FAIL lines that were my own mixed tree. This trap is already documented in `work/SKILL.md`.
    **Prevention:** confirm clean, launch, then do not edit; if an edit cannot wait, kill the run.
11. **A python edit script aborted on its first anchor miss**, so none of seven plan edits applied,
    and the failure looked like partial success. **Prevention:** make multi-edit scripts report per-anchor
    hit/miss and continue, rather than raising on the first.
12. **A guessed assertion floor (79 vs actual 70).** **Prevention:** derive floors from a green run.
13. **Command reaps (exit 144/143)** under 5 concurrent test runs. Environmental; detached `setsid`
    launches with rc files were the working pattern.
14. **A `git push` reported "correct access rights" and had actually succeeded.** **Prevention:**
    verify push state against `origin/<branch>`, not the command's message.

## Tags

category: test-failures
module: registry-restore-engine

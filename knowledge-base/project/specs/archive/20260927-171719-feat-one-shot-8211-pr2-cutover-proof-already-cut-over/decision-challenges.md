# Decision challenges — feat-one-shot-8211-pr2-cutover-proof-already-cut-over

Taste and User-Challenge decisions from planning, per ADR-084, recorded so they are auditable
outside this session. `ship` renders this file into the PR body.

---

## DC-1 — The proof does not add a separate LUKS2 check

**Date:** 2026-09-27
**Classification:** Taste. The brief asked for evidence that "the store is actually served from the
verified LUKS mapper", and this cut interprets that wording.
**Decision:** a pass needs two things:

- the store's mount source equals `/dev/mapper/git-data`;
- `/etc/git-data/store-verified` is bound to the mounted filesystem's UUID.

There is no separate dm-crypt or LUKS2 probe, whether through `dmsetup info -o uuid` or
`cryptsetup status`.

**Why:**

- The bootstrap opens that mapper only after `cryptsetup isLuks` accepts the device, and writes
  the marker only after its boot proofs pass (`git-data-bootstrap.sh`, the luksOpen block and
  step 5a). So a bound marker already implies a LUKS-backed mapper.
- A separate check would add only one case: root remapping the device after boot. A compromised
  root can also forge the check's own answer.
- Step 5 discharges erasures on emptiness, not on encryption. The CLO requires that the proof make
  no encryption-at-rest claim, which is #8634's determination.
- DHH and code-simplicity converged on the cut at plan review. The correctness findings on the
  check's argv and ARG rows dissolved with it.

**Reopen if:** the operator wants the proof itself to attest dm-crypt, independently of the
bootstrap. The check was costed at one remote element, one shim, one census rule, 7 test rows and
2 mutants.

## DC-2 — The freeze-sentinel probe is kept

**Date:** 2026-09-27
**Classification:** Taste. DHH raised it as a User-Challenge.
**Decision:** the proof refuses `cutover_frozen` when `/mnt/git-data/.cutover-freeze` exists.

**Why:** #8211 asks for it explicitly: "the read-only proof should probe that the sentinel is
ABSENT before any real run". A sentinel left behind by a crashed run would make every provision,
remove and push refuse, and every account deletion would log an Art. 17 failure.

**Against:** the sentinel has no writer today, so this is scaffolding for the follow-on. Its
runbook row routes to an incident with a reviewed hotfix remover.

**Reopen if:** the #8211 follow-on drops the freeze model entirely.

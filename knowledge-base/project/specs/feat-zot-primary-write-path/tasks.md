# Tasks — container-registry write-path topology

Derived from `knowledge-base/project/plans/2026-08-04-fix-container-registry-write-path-topology-plan.md`.

**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (CPO sign-off
required before `/work`).

**Headline:** the plan *declines* the proposed zot-primary topology change on measured
evidence, records that decision as ADR-167, corrects four false statements in the architecture
record, and ships one narrow retry. Do not treat this as a topology migration.

---

## Phase 1 — Record the decision (docs only, no code)

- [ ] **1.1** Create `knowledge-base/engineering/architecture/decisions/ADR-167-container-registry-write-path-stays-dual-push.md` (status `accepted`). *(Draft already written in this worktree — review, do not regenerate.)*
  - [ ] 1.1.1 Re-derive the ADR ordinal against freshly-fetched `origin/main` before PR-ready; `/ship`'s collision gate re-checks it again at merge. If it moves, sweep **every** artifact naming the old ordinal: `grep -rn 'ADR-167' knowledge-base/project/{plans,specs}/ knowledge-base/engineering/`.
- [ ] **1.2** Amend ADR-096's 2026-07-30 amendment in place (no new ordinal). Scope *"nothing can read it back"* to **hosts**; note CI's read is what the amendment's own `crane copy GHCR→zot` backfill remedy depends on. **Do not change its conclusion** — the mirror stays release-blocking.
- [ ] **1.3** Add one scoping sentence to ADR-088 arm-b: the finding constrains *host-side zero-touch* credentials and does not bear on CI's in-job `GITHUB_TOKEN` read. **Do not reopen the finding. Do not propose a personal credential.**
- [ ] **1.4** Correct `knowledge-base/engineering/architecture/diagrams/model.c4`:
  - [ ] 1.4.1 L268 (`ghcr`) — replace *"It receives every image and can serve none"* with a host-scoped statement; name CI's backfill read and the ADR-135 config-bundle host read.
  - [ ] 1.4.2 L272 (`zotRegistry`) — scope *"re-fills ONLY from a fresh CI dual-push — NOT from GHCR"* to the **host pull path**; name the CI `crane copy` backfill.
  - [ ] 1.4.3 L272 (`zotRegistry`) — replace stale host spec: `cx33 / 4 vCPU / 8 GB` → cx23; drop the `7168m` constant and describe the **derivation** (`server_type.memory × 1024 − reserve`, `zot-registry.tf:83`) so it cannot go stale again on a resize.
  - [ ] 1.4.4 L507/513/514/515 — `ADR-136` → `ADR-135` (config-refresh channel). **Leave L470 alone** — its ADR-136 citation is correct.
  - [ ] 1.4.5 **Do not** touch L260/264/362/474/475 (the Web Push cluster). Correct ordinal unestablished; out of scope. See plan §C4 views "Deliberately NOT fixed".
  - [ ] 1.4.6 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `apps/web-platform/test/c4-render.test.ts`.

## Phase 2 — DESCOPED on review evidence (no workflow change ships)

~~Conditional retry on the GHCR push.~~ **Cut.** Three verified findings:

1. The GHCR push is `uses: docker/build-push-action@…` (`reusable-release.yml:743`) — a `uses:`
   step. The `retry()` it was told to reuse is a bash function in a `run:` block (`:962-971`).
   You cannot wrap one in the other, and a `uses:` step's stderr is not readable from a sibling
   step, so the signature gate has nothing to match.
2. A cause-classifying retry is *more* ADR-166-exposed than a blanket one, and
   `scripts/lint-diagnosis-claims.sh` is a **blocking** lint over `.github/workflows/`.
3. GHCR blocked one attempt transiently; the zot leg blocked five releases the same day.
   Re-running the job is the existing remedy and it worked.

- [ ] **2.1** Nothing to do. Confirm `git diff --name-only origin/main...HEAD -- '.github/workflows/'` is empty (AC10).

## Phase 3 — Verification

- [ ] **3.1** c4 syntax + render tests (from 1.4.6).
- [ ] **3.2** Full-suite exit gate: `bash test-all.sh`.
- [ ] **3.3** Walk AC1–AC13, skipping the deleted AC7/AC8. Use the **rewritten** AC4/AC5/AC12
      commands — the originals were defective (AC4 would have deleted true facts about web-1 and
      soleur-grok-dogfood; AC5 passed before any edit; AC12 false-passed on a line shift).
- [ ] **3.4** `actionlint` / `bash -c` — **not applicable**, no workflow edited.

## Phase 4 — Ship

- [ ] **4.1** PR body uses `Ref #7247` / `Ref #7248` — **never** `Closes` (AC11). Neither issue is resolved here.
- [ ] **4.2** PR body must state the headline plainly: *this plan declines the proposed topology change and explains why*, so a reader does not skim it as an approval.
- [ ] **4.3** `/soleur:review` → `/soleur:compound` → `/soleur:ship`.

---

## Before `/work` — two gates the plan flags

- [ ] **G1** CPO sign-off (threshold = `single-user incident`, `requires_cpo_signoff: true`).
- [ ] **G2** **Recommended:** run `/soleur:plan-review` (or `/soleur:deepen-plan`). At this
      threshold the skill normally escalates to a 5-agent adversarial panel; this plan was
      written without one because agent spawning was disabled for the session. Every central
      claim is a first-party measurement with its command inlined, so it is re-checkable — but
      it has not been independently challenged.

## Explicitly not in scope

- Diagnosing **why** zot restarts → #7247. The plan measured the rate (~4.44/min) and excluded
  OOM and disk-full; it names no further cause (ADR-166).
- Fixing the read-path-only health verdict → #7248. Not a dependency of this work.
- The registry volume's LUKS posture (#6929).
- The Web Push ADR-136 citation cluster (ordinal unestablished — verify separately).

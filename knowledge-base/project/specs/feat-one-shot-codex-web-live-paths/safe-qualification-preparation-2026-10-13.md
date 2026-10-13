---
title: Reviewed offline candidate export and schema preparation
date: 2026-10-13
pr: 9051
source_sha: 186359b94c553f52dc31ef7c0f05c602fb1f3cd8
status: offline-source-prepared-operational-controller-and-approval-pending
---

# Preparation evidence

This source includes main through `446afcb727394e3abf721e6aaa3edcb72616ec3a`.
The complete offline wrapper passes with inherited `PYTHONOPTIMIZE=1`. Preview
binds **5,061** production/plugin inputs, all **188** forward migration bodies,
the preparation components and eleven scenario artifacts (ten committed SQL
files plus the derived ledger census). Migration bodies and the production
admission guard remain unchanged.

| Source-bound preparation input | SHA-256 |
|---|---|
| Runtime/plugin manifest | `82d963b1d70626b40380b313a852a7447164e8ac89a2bfaf1c1e6ed788e38097` |
| Forward-schema manifest | `baeb4ee9428e8187d98743d6fe84dd84a20c98162a5440f140df9891edc9f172` |
| Preparation components | `d509e56c61d7f03df7a78f956e455dcca0520c80a5fed85132c00fbda482ee99` |
| Source/schema/auth/components pairing | `0e968f982370fdc733dff5ab26c42231b534ffeae4125efec389f9cbc8c5b330` |
| Rehearsal recipe | `01ed99a5658814842048311fdb8c9d5b8ac15e2a36ffe4159f1a1413324dd54a` |

The [candidate assembler](../../../../scripts/codex-qualification/candidate.py)
exported the real committed source into fresh local scratch and verified
**6,781** source leaves, including **1,718** exact vendored plugin inputs,
file modes and symlinks. The export manifest is
`04a7f9e6b72f9a23788125d250da710c601416518ff0b9fc227982842b54e964`;
its prospective build recipe is
`4ad0e4f8150f40075ec8652350df4ad5b9528f53b0c80463e79da5c4b8d8f70d`.
This is file preparation, with Docker/build/startup/SQL/provider/credential-read
counts all zero. No build/recovery marker was consumed or reset.

## Independent source review

The [focused ledger](qualification-boundary-review-2026-10-12.md) owns all seven
findings and binding CTO direction. A fresh independent verifier closed all
seven and measured 37 targeted checks, including deterministic old/current
cleanup and stdin-publication schedules. Schema guardian found no unresolved
concrete finding in the prepared SQL source and verified the canonical ledger
fix. SQL evidence remains source and fake-command output, never database execution.

The fresh verifier separately examined the candidate exporter at this source:
no concrete preparation finding; ten isolated candidate fixtures, forced expiry
refusal, 46 host-pin lint fixtures, syntax and ShellCheck passed. The live host
guard passed 45 enumerated files with zero violations, retaining its existing
25-versus-24 census note and three deprecation waivers. The dated non-caller
entry requires zero real Management API calls. Registration census passed
679 covered / zero orphaned. Earlier fixture ratchets passed 62/62 and 71/71;
these are source-specific checks, not full PR/SAST/runtime clearance. Host Node
leaf checks do not attest production parity; Bun enumeration warned of the
installed/pinned mismatch without executing Bun suites.

## Draft CI

[CI 38357777571](https://github.com/jikig-ai/soleur/actions/runs/38357777571)
settled 69 pass / 11 skip / no pending or cancelled checks. Only required `test`
is red; its executed log reports draft-skipped Web and both scripts legs and
`draft: full battery owed at ready`. The token-name lint correction is green.
This is the recorded source's draft CI, not a full-suite or runtime verdict.
Final evidence-only head CI and description checks remain separate.

## Scoped advisory GDPR gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

The five mandatory checks covered lawful-basis annotation, retention metadata,
user-FK erasure/caller wiring, vendor transfer and special-category column names.
This preparation delta adds no production PII schema/FK, provider SDK or vendor
route. The owner-only synthetic snapshot helper stays inside an owned synthetic
database; complete rows must never become customer/account evidence or published
row dumps. No new Critical or Important finding arose in that narrow source
scope. Broader privacy findings and mode-specific CLO restrictions remain open.

## Operational completion remains pending

The saved build recipe remains unreviewed for builder/daemon admission,
dependency networking and resource bounds. There is no operational execute
entrypoint. Actual role image/config profiles, TLS/namespace startup and route/
trust observations, retained storage/workspace byte manifests, schema-service
quiescence and bounded race/session cleanup orchestration remain incomplete.
An empty runner-blocker list does not discharge these controls. Neither a
runnable full rehearsal nor an approval-ready action is claimed.

Only a newly reviewed exact current-source/full-production action can be
presented for fresh explicit approval. Authorization remains consumed and the
withdrawn recovery command unavailable/unexecuted. The ensuing evidence-only
commit requires fresh source pairing and exact-head CI/description guards;
the receipts above remain attributable to their recorded source.

Keep draft, auto-merge off, Codex default-off and customer content blocked.
Hosted App Server auth remains BLOCKED in both modes; the alternative API route
is PENDING. Project sharing, retention/inheritance and regions remain unknown.
SAST VOID; Ref #10082 OPEN; full panel incomplete; Ref #9791 OPEN/unverified;
no latest-source C.9 rerun or root-cause clearance. Credential/provider/browser-
auth, account/shared-write, deployment and flag/cohort restrictions persist.
Recovery → authenticated screenshots → eligible routine → permitted Web/CLO
matrices → full review/promotion remains open.

## Session errors and corrections

- Sandbox denied locks, sockets, network and `/var/tmp` scaffolds; exact retries
  passed. A failed enumerator generated secondary orphan diagnostics, not real
  orphan evidence. **Prevention:** check producer exit before its derived census.
- Guessed paths/interpreter and patch anchors were wrong; correct targets were
  discovered/read and rerun. **Prevention:** use `rg --files`, the shebang and
  actual target text before execution/editing.
- Image inspection changed fixture request counts; exact sequences replaced
  them. Dirty-source preview correctly refused until commit. **Prevention:**
  assert request identity/order and bind only committed source.
- Token-name lint, literal audit metadata and ANSI-log refusals were corrected
  through their existing mechanisms. **Prevention:** verify zero calls, record
  literal intent and sanitize bounded log output.
- Moving main caused hash/instruction/archival conflicts; legal changes and
  relocated evidence were preserved, hashes/links repaired and old checks kept
  historical. **Prevention:** refresh source pairing after every main sync.
- Seven boundary/oracle defects were fixed and independently verified in the
  ledger. **Prevention:** test dispatch transitions, inherited resources and
  oracle synchronization with meaningful guard-removal controls.

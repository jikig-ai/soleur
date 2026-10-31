---
title: "CLO determination — Art. 4(12) assessment of the sibling-readable CLI session state in the shared HOME (#10455)"
type: clo-attestation
date: 2026-10-31
issue: 10455
related_issues: "10445, 11689"
attestation-authority: clo
status: "DRAFT v1 — internal CLO attestation (Soleur-as-tenant-zero v1), NOT external counsel advice. PROVISIONAL. The operator retains an optional veto."
disposition: "REACHABILITY-ONLY, PROVISIONAL. Art. 4(12) first limb (a confidentiality-measure gap) is conceded; the second limb (unauthorised access to personal data) is not established. Reachability alone does not start the Art. 33 clock. Art. 33: No. Art. 34: No. Evidentiary limbs: inconclusive."
signed_off_at: 2026-10-31
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-10-31 — the measurement in PR #11689 (test apps/web-platform/test/sandbox-wrapped-command-runtime.test.ts, G2). Antecedent: the 2026-10-09 arm-F ruling, which recorded no row because no personal-data fact had been measured."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the facts established to date. Re-opens with a FRESH 72h from awareness of any evidence that a sibling tenant actually read one of the files below. If the affected workspace is one where Jikigai is processor, Art. 33(2) notice to the controller is owed without the risk threshold."
open_limbs: "inconclusive: (E1) a counts-only, metadata-only census of the production HOME for history.jsonl, debug, todos and tasks, not run and requiring the operator's authorisation; (E2) whether any sibling read occurred, for which no instrument exists; (E3) the content of the `name` field and of the peer key file, unmeasured."
tier_classification: "Tier 1 — an internal determination record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
related_records: "`knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md` and `knowledge-base/legal/audits/2026-10-09-clo-ruling-arm-f-elevation-disposition.md` (the standing rule: reachability alone does not start the Art. 33 clock)."
---

# CLO determination — #10455 sibling-readable CLI session state in the shared HOME, Art. 4(12)

> **DRAFT v1. Internal CLO attestation, not external counsel advice.** It records the CLO
> agent's position on 2026-10-31 for the Art. 33(5) file. It is append-only after merge.

## Verdict — reachability only. PROVISIONAL

1. **Measured (a test with the real vendored CLI and synthesized tenants, shared HOME, production sandbox posture).**
   A sibling tenant's sandbox can read, in the shared HOME: the session metadata files
   (`~/.claude/sessions/<pid>.json`: working directory, which contains the other tenant's workspace
   identifier; session identifier; process identifier; status; name; messaging socket path), a
   peer-protocol key file, shell snapshot files, and the account state file. The other tenant's
   prompt text, tool output and a credential were not readable in that test.
2. **The workspace identifier is personal data, pseudonymous** (Art. 4(1), Recital 26), never
   anonymous. For a solo workspace the identifier equals the user identifier (see the doc comments
   on `provisionWorkspace` and `purgeWorkspaceLogoObjects` in `apps/web-platform/server/workspace.ts`,
   and migration 053). The session identifier, working directory, process identifier, name and
   status are linked metadata.
3. **Art. 4(12), first limb — a breach of security: conceded.** The confidentiality measure for
   per-tenant CLI state was not tenant-scoped.
4. **Art. 4(12), second limb — unauthorised access to personal data: NOT ESTABLISHED.** Nothing shows
   that a sibling read these files, and no instrument could show it. Reachability alone does not
   start the Art. 33 clock (the standing rule of the 7797 and 11294 determinations).
5. **Art. 33: No. Art. 34: No,** on present evidence. Any evidence of an actual sibling read starts
   a fresh 72 hours. Where the affected workspace is one in which Jikigai is processor, Art. 33(2)
   notice to the controller is owed without the risk threshold.

## Unmeasured classes — no claim is made about them

`history.jsonl`, `debug/`, `todos/` and `tasks/` are the classes most likely to carry prompt text.
The CLI in SDK print mode did not produce them in the test, so they are **unmeasured, not safe**,
and the production HOME was **not inspected**. No statement to users, and no claim that no content
is readable, may be made until a read-only, counts-only, metadata-only census of the production HOME
has run: no content opened, no values reproduced, no real identifiers quoted. The CLO authorises the
method. The operator, as controller, must authorise production access in the operator's own message.
The CTO executes it with no SSH fallback. This does not gate merging PR #11689. A census that finds
readable prompt text is a new finding with a fresh awareness anchor.

## Wording constraints (PR bodies, ADR addenda, issue comments)

May say: measured in a test with the real CLI and synthesized tenants; the listed classes are
readable by name; prompt, tool output and an exported credential were not readable in that test;
the production HOME was not inspected; the classes above are unmeasured; the engineering owner
documented the residual; no Art. 4(12) event is established, provisionally; no instrument shows
whether any read occurred; the peer key is not demonstrated usable.

Must not say: "no personal data exposed", "tenant isolation", "not a breach", "fixed", "secure",
"anonymous", "key unusable", or anything in the past tense about a change that has not merged. Do
not quote real identifiers, process identifiers or key bytes.

## If the finding flips

A demonstrated sibling read; a census that finds prompt text in the production HOME; a demonstrated
use of the peer key from inside a sandbox; or a CLI change that adds a readable file holding any of
the above. Each re-opens this record with a fresh awareness anchor and goes to external counsel.

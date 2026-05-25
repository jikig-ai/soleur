# Learning: Plan-Time Paraphrase-Without-Verification — File Extension and "Reuse Existing Salt" Class

**Date:** 2026-05-22
**Skill:** soleur:plan (primary), soleur:brainstorm (propagation source)
**Category:** plan-quality / paraphrase-without-verification
**Tags:** plan-review, multi-agent-fan-out, file-extension-drift, salt-source-verification, single-user-incident
**Related issue:** #4319 (DSAR Art. 15(4) author-only redaction)

## Problem

The plan-skill session for #4319 produced a v1 plan that passed brainstorm
+ spec + my own self-review with **two paste-class bugs** at the P0
severity that only surfaced when the 5-agent parallel reviewer fan-out
(DHH + Kieran + Code-Simplicity + GDPR-gate + SpecFlow) ran:

**P0-1 (Kieran):** Plan v1 referenced `.jsonl` file extension across the
manifest path field (`redactions[].path: "messages.jsonl"`), AC1 fixture
assertions (`messages.jsonl in the export bundle`), and disclosure copy
("messages.jsonl"). The actual code at `apps/web-platform/server/dsar-export.ts:1174`
writes `tables/${t.table}.json` — single JSON object per table
(`{table, article, row_count, rows}`), NOT line-delimited JSON. A
shipped manifest would have pointed at non-existent files.

**P0-2 (GDPR-gate Crit-5):** Plan v1 Reconciliation row #5 said
"salt = per-export-job random bytes (already minted at dsar-export.ts
for bundle hashing — reuse)." The only `createHash` near manifest time
at `dsar-export.ts:1270-1281` is `bundleHash`, a **content-derived
SHA-256 of the bundle stream**, not a random secret salt. A
content-derived hash as a pseudonym salt is non-cryptographic
(predictable from the bundle content) and lifecycle-wrong (computed
AFTER manifest write, so unavailable at predicate-apply time).

Both bugs survived: original brainstorm → spec → plan v1 → my own
re-read of plan v1. Only the parallel reviewer fan-out caught them.

Six additional findings of similar shape ranged from P0 to P2:
- Missed `messages.user_id` NULLABILITY semantics (mig 046:79-101) →
  predicate would have falsely redacted subject's legacy rows.
- Missed Art. 15 completeness gap (subject's messages in foreign-owned
  conversations) — distinct from Art. 15(4) under-redaction; scope-out
  to #4358.
- Missed `dsar_export_audit_pii` WORM horizon vs. pino 30d retention —
  scope-out to #4359.
- Missed PA-2 §(g) as the Article 30 register insertion site — assumed
  a standalone DSAR-export PA that does not exist.
- Missed `action_class` as Art. 9 leak vector on redacted rows.
- Orphan-attachment denylist-vs-allowlist semantic.
- Pseudonym hex8 collision space.

## Recovery

5-agent parallel fan-out (DHH plan review + Kieran plan review +
Code-Simplicity plan review + security-sentinel running GDPR-gate +
spec-flow-analyzer running data-flow edge-case enumeration) at the end
of plan write surfaced all 12 findings. Operator accepted "apply all
P0 + simplifications, reject DHH consolidate-docs/drop-hash/drop-bump
proposals" path. Plan was rewritten with:
- `.json` everywhere (correct producer extension).
- Explicit `pseudonymSalt = crypto.randomBytes(32)` at function entry.
- Two deferred follow-up issues filed (#4358 completeness, #4359 WORM).
- Legacy-NULL fail-closed default with Phase 0.3 audit override.
- `action_class` added to null-list.
- Allowlist semantic for attachments.
- Hex8 → hex12 pseudonym widening.
- PA-2 §(g) target for Art. 30 register.

## Key Insight

At brand-survival threshold = `single-user incident`, the plan-skill's
4-step "Final Review & Submission" checklist is necessary but
insufficient. Two specific failure classes pass brainstorm + first-draft
plan + self-review and need explicit grep gates at plan-write time:

**Class A — File-format-extension assumption.** When a plan asserts a
file path, manifest field value, or fixture-read-by-extension, the
producer code's actual emission shape must be grepped. Bundle libraries,
archive writers, and serializers use formats that drift from the
plan author's mental model:
- `archive.append(buffer, { name: "x.json" })` ≠ `x.jsonl`
- `fs.writeFile(path, JSON.stringify(arr) + "\n")` ≠ `.json` (it's
  conventionally `.jsonl` when each line is one record)
- The plan author often assumes JSONL because it's the common DSAR
  shape, when the codebase chose differently for streaming reasons.

The fix: grep `archive\.append\|fs\.writeFile\|writeStream` in the
producer file at plan-write time and cite the literal `name:` / path
in the plan's Reconciliation table.

**Class B — "Reuse the existing X" claim.** When a plan says
"reuse the existing salt / secret / random nonce / cached token /
already-minted identifier," the cited symbol's lifecycle AND
cryptographic property must be verified. Common drift patterns:
- "Reuse the bundle-hashing salt" → `bundleHash` is a content-derived
  SHA-256 of the file stream, NOT a secret salt (this case).
- "Reuse the JWT signing key" → the symbol exists but is an HMAC key
  not an RSA private key.
- "Reuse the existing rate-limit window" → the symbol exists but is
  a per-user counter, not a per-IP counter.

The fix: grep `randomBytes|randomUUID|crypto\.subtle\.generateKey|salt\s*=`
in the named file to verify the cited symbol is the cryptographic
primitive the plan claims, AND grep for its assignment line to verify
lifecycle (function entry vs. mid-function vs. post-output).

**Both classes share a meta-property:** they pass plan-review agents
that read ONLY the plan text (DHH + Kieran for `.jsonl`/`.json` —
the agents can't tell which is correct without code-side grep). They
require an agent that READS the producer code (Kieran did, which is
why P0-1 surfaced; GDPR-gate did, which is why P0-2 surfaced). The
plan-skill's existing Sharp Edges include several entries about
"paraphrase-without-verification" but none specifically calls out
file-extension and "reuse existing salt" as load-bearing classes.

## Prevention (Workflow Change)

Add a Sharp Edge to `plugins/soleur/skills/plan/SKILL.md` enumerating
the two failure classes with the specific greps that catch each. See
route-to-definition below.

Alternative considered: extend the existing "paraphrase-without-
verification" Sharp Edge for issue-body claims (`2026-04-22-ts-sql-
normalizer-parity`) to also cover plan-author-own claims. Rejected:
the existing Sharp Edge is about ISSUE-BODY paraphrase; the new class
is about PLAN-AUTHOR paraphrase (which has different failure dynamics
— the plan author is one's own self-review blind spot, not a third
party's prose). They warrant separate Sharp Edges.

## Session Errors

12 plan-quality errors enumerated in Phase 0.5 above, all caught at
5-agent review BEFORE code shipped. **Prevention:** the plan SKILL.md
Sharp Edge added in this learning's route-to-definition forces the two
specific greps (producer-code emission shape; salt/secret cryptographic-
primitive verification) at plan-write time, catching the two highest-
severity classes at the cheapest point. The other 10 errors are covered
by existing Sharp Edges (premise validation, paraphrase verification,
field-list-closed sweep) — they survived this session because I did
not invoke them at plan-draft time. The 5-agent review fan-out is the
backstop; the plan-time greps are the cheaper primary gate.

## Cross-References

- Plan: `knowledge-base/project/plans/2026-05-22-feat-dsar-author-redaction-art-15-4-plan.md`
- Spec: `knowledge-base/project/specs/feat-dsar-author-redaction-4319/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-dsar-author-redaction-brainstorm.md`
- Deferred follow-ups: #4358, #4359
- Related learnings:
  - `best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — paraphrase-without-verification for issue-body claims (this is the plan-author analog).
  - `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md` — third-party API contract verification.
  - `2026-05-15-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md` — runtime shape verification.

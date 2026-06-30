---
title: Counsel-Review CLO-Attestation — epic #5274 Phase 2 PR A (worktree_write_lease)
date: 2026-06-30
attestor: CLO-agent (Soleur-as-tenant-zero v1 internal sign-off)
pr_branch: feat-5274-phase2-git-data-lease-fencing
brand_survival_threshold: single-user incident
disposition: DISCHARGED (one non-blocking prose-correction condition)
re_evaluation_triggers:
  - first arms-length (non-Soleur) user
  - EEA-out data residency change
  - regulated-industry tenant onboarding
output_status: DRAFT — internal v1 attestation; external counsel re-review reserved for the triggers above
---

# Scope

Migration 116 (`public.worktree_write_lease`) adds a per-(workspace_id, worktree_id)
write-lease coordination row for the multi-host `/workspaces` layer (ADR-068 §2).
Legal-surface change: a DSAR **exclusion** entry + the 4-doc lockstep changelog
(`privacy-policy`, `gdpr-policy`, `data-protection-disclosure` + compliance-posture),
NO new disclosure section, NO `article-30-register.md` amendment, SHA repins for 3 docs.

# Implementation cross-check (prose claim → code body)

| Prose / DSAR-entry claim | Source of truth | Verdict |
|---|---|---|
| Table `public.worktree_write_lease`, migration 116 | 116_worktree_write_lease.sql | MATCH |
| Columns: workspace_id (FK), worktree_id, host_id, lease_generation, acquired_at, heartbeat_at ("two timestamps") | DDL `create table` block | MATCH (column-exact) |
| host_id = host-stable server identity, NEVER `auth.uid()` | migration comment "Infra identity… NEVER auth.uid()" | MATCH |
| Art.17 erasure via `ON DELETE CASCADE` from `public.workspaces` | `references public.workspaces(id) on delete cascade` | MATCH |
| "no anonymise RPC needed" | grep: only acquire/touch/release RPCs exist; no anonymise_* | MATCH |
| "proven by the AC5 cascade integration test" | worktree-write-lease.integration.test.ts:291-303 asserts 0 rows post workspace-delete | MATCH |
| DSAR **EXCLUSION** (not allowlist) | DSAR_TABLE_EXCLUSIONS entry | MATCH |
| no new sub-processor / recipient / third-country transfer | no external egress in migration; same Supabase Postgres | MATCH |
| SHA repin (3 docs) | sha256sum of each doc == repinned value in legal-doc-shas.ts | MATCH (all 3) |
| 3-doc byte-identical 5274 prose | hash afac1f156e87, 1054 bytes ×3 | MATCH |
| TC_VERSION not required | T&C untouched; only non-T&C SHAs repinned | MATCH |

# Legal determinations

(a) **DSAR exclusion is correct at the VALUE level.** The row carries NO user-id
column at all (no actor_id, no auth.uid()) — a weaker personal-data nexus than the
already-DISCHARGED `routine_runs` exclusion. Only `workspace_id` is user-transitive,
and it is a pseudonymous tenant-boundary key already exported via the `workspaces`
table. Remaining columns are pure machine coordination (one overwritten-in-place row
per worktree, not a growing timeline). No meaningful Art.15 profile data. EXCLUSION SOUND.
"No re-evaluation trigger" is defensible (no user-id to promote); holistic re-review is
still covered by the frontmatter triggers above.

(b) **"No new Article 30 processing activity" is defensible.** No new purpose and no new
data category: storing a `workspace_id` FK in an additional coordination table is part of
existing service-operation processing already accounted for under the workspaces RoPA
entry. Contrast `routine_runs`, which minted PA-29 precisely because it held `actor_id`
(real personal data). This table holds none, so no PA and no amendment. Thinnest point of
the package, but sound.

(c) **Lawful basis (legitimate interest, Art.6(1)(f)) adequate** — conservative, in fact:
with no personal-data attribute beyond an already-covered FK, a separate Art.6 basis is
arguably not even required. LI mirrors the parent workspaces processing. No LIA mandated
(no new personal-data purpose). ADEQUATE.

(d) **No-new-disclosure-section treatment is honest.** With no personal-data processing to
disclose, a dedicated section would add nothing for the data subject; the changelog entry
documenting the decision + rationale is the correct transparency artifact. HONEST.

# Drift found (one) — non-blocking prose-correction condition

The prose (3 docs + DSAR allowlist entry + compliance-posture) calls the row **"ephemeral
with zero audit lineage."** The migration's OWN comment contradicts "ephemeral": release
now TOMBSTONES rather than deletes — "a row now persists for the life of the workspace
rather than per-release; this is a retention change." The row is durable for the workspace
lifetime (overwritten in place), not ephemeral.

Materiality: NIL to every legal determination. Art.17 still satisfied by cascade (AC5
proves it on the tombstoned row), classification still no-personal-data, exclusion still
sound. "Zero audit lineage" remains true (no history rows, no actor identity). The defect
is solely the adjective "ephemeral," which overstates transience and invites future audit
confusion (exact prose-vs-code drift class, cf. PR #4353/#4558).

CONDITION (non-blocking — does not hold the ship gate): in a follow-through edit, replace
"ephemeral" across all 5 loci with e.g. "non-personal operational coordination state
(retained for the workspace lifetime, overwritten in place, cascade-erased on workspace
deletion)", then repin the 3 doc SHAs and re-sync the Eleventy mirrors in the same commit.

# Disposition

**DISCHARGED.** Legal prose matches the implementation; classification (no personal data,
DSAR exclusion, no new Art.30 PA, Art.17 via cascade, Art.6(1)(f) basis) is sound. One
non-material wording correction ("ephemeral") is recorded as a tracked follow-through, not
a blocker. Output remains DRAFT pending external counsel re-review at the frontmatter
re-evaluation triggers.

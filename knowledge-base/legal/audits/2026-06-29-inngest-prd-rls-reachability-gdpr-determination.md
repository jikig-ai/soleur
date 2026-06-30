# GDPR determination — RLS-disabled reachability on `soleur-inngest-prd` (`pigsfuxruiopinouvjwy`)

**Date:** 2026-06-29 · **Authority:** Soleur v1 CLO-attestation (founder-grade internal sign-off, not formal external legal advice — external counsel re-review reserved for first arms-length user / EEA-out / regulated-industry triggers) · **Status:** SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1, 2026-06-29) · **Evidence:** `knowledge-base/project/specs/feat-one-shot-inngest-prd-rls-enable/gate-g-escalate-evidence.md`

## Verdict — NOT a notifiable personal-data breach; recorded as an Art. 33(5) breach-documentation / near-miss entry (cross-referenced from the Art. 30 register). DISCHARGED.

The 2026-06-17 → ~2026-06-27 residual window does **not** constitute a personal-data breach under Art. 4(12) and triggers **no Art. 33** (supervisory authority) and **no Art. 34** (data-subject) notification obligation. Recorded as a "reachability-only, remediated, no notifiable breach" Art. 33(5) breach-documentation / near-miss entry (Art. 30 register cross-reference), with the log-coverage limitation disclosed.

## Reasoning

1. **Art. 4(12) is a risk assessment, not a categorical test.** A misconfiguration making data reachable *in principle* is a vulnerability; whether it rises to a breach turns on the facts, not on a presumption that absent positive-access evidence is automatically no-breach (EDPB Guidelines 9/2022 treat unconfirmed access with unavailable logs cautiously, not as a free pass). Here (i) an exploitable surface is established, but the access-log dimension is unavailable for part of the window — so the determination does **not** rest on "no facts of access ⇒ no breach"; it rests on the Art. 33(1) likelihood analysis below (the never-published key driving exploitation likelihood to near-zero).
2. **The never-published key removes the exploitation precondition and drives likelihood to near-zero.** The anon/service_role keys for this project were never shipped in a client bundle and never committed (clean current tree + full git-history pickaxe); the client-shipped `NEXT_PUBLIC_SUPABASE_*` address the *web-platform* project, not this one. Unauthenticated PostgREST exploitation required this project's anon key, which had no public ingress vector for the entire window.
3. **Retained-log evidence is corroborating, not dispositive.** `edge_logs`/`auth_logs` show zero REST/GraphQL/auth traffic over the retained slice, and Inngest reaches the DB only via the session pooler as `postgres`. The access-log dimension is treated **INCONCLUSIVE** for the unretained 06-17 → ~06-27 portion (retention ~1–2 days < 12-day window) and is NOT certified clean; the determination rests primarily on the absent exploitation precondition.
4. **Art. 33(1) threshold met even arguendo.** Treating the reachability as a constructive breach, the likelihood of any unauthorised access is very low (no public key, zero retained traffic, REST surface unused by the legitimate data path) — comfortably "unlikely to result in a risk to the rights and freedoms of natural persons," so notification would not be required on that footing either.
5. **Severity acknowledged.** The tables *can* embed personal data (event payloads, step I/O, tenant identifiers, `event_user`, `worker_ip`); had access occurred, severity would be non-trivial. The **likelihood** prong, not severity, is dispositive here.

## Conditions / residual actions

- **REQUIRED — remediation enforced, not just declared.** Verified live on `pigsfuxruiopinouvjwy`: RLS enabled on all 14 tables, anon/authenticated grants revoked, default privileges revoked; advisor 14→0; anon read → `permission denied` (42501); owner access intact (3603 events). ✔
- **RECOMMENDED — key rotation as defense-in-depth.** Not compelled (key never published); rotating anon + service_role would foreclose the residual theoretical tail. Held as optional; not gating.
- **REQUIRED — monitoring note.** Recorded that edge-log retention (~1–2 days) < exposure window → access-log dimension inconclusive-by-design, not clean. (Captured in the evidence file + the Art. 33(5) near-miss record below.)
- **FOLLOW-UP — retention-policy gap.** Evaluate extending edge/auth-log retention (or shipping to durable storage) on production projects so a future reachability event can be certified against full-window logs. Tracked as a non-blocking issue.
- **PROCESS — confirm advisor clears** on the next Supabase security-advisor run. (Verified: `rls_disabled_in_public` 14 → 0.)

## Art. 33(5) breach-documentation / near-miss record (canonical) — cross-referenced from the Art. 30 register

```
GDPR Art. 33(5) breach-documentation / near-miss record (Art. 30 register cross-ref) — RLS-disabled reachability, soleur-inngest-prd (pigsfuxruiopinouvjwy, eu-west-1)

Event: Supabase security-advisor (dated 2026-06-22) flagged rls_disabled_in_public on 14 public tables that can
embed personal data (event payloads, step I/O, tenant identifiers incl. event_user/worker_ip). RLS was disabled
and anon/authenticated held DML; the PostgREST public schema was reachable in principle by any holder of this
project's anon key + URL. Exposure window: project creation 2026-06-17 → remediation 2026-06-29 (~12 days).
Determination: REACHABILITY-ONLY, NO NOTIFIABLE BREACH. The exploitation precondition (this project's anon key)
was never published in any client bundle or commit (clean current tree + full git-history pickaxe); the
client-shipped Supabase keys address the separate web-platform project. Retained edge/auth logs show zero
REST/GraphQL/auth traffic; the legitimate Inngest path reaches the DB via the session pooler as postgres, not via
REST. No positive evidence of unauthorised access. No Art. 4(12) breach arose; Art. 33 (72h) and Art. 34
obligations were not triggered, and the "unlikely to result in a risk" threshold of Art. 33(1) would be met even
on a constructive-breach reading.
Remediation: RLS enabled and anon/authenticated DML revoked on all 14 tables; default privileges (grantor
postgres) revoked to stop recurrence. Key rotation: declined (key never published; held as optional defense-in-depth).
Coverage limitation: edge-log retention (~1-2 days) is shorter than the ~12-day exposure window, so the access-log
dimension is INCONCLUSIVE (not certified clean) for 2026-06-17 → ~2026-06-27; the determination rests primarily on
the never-published key. Retention-extension follow-up tracked separately.
Determined by: Soleur v1 CLO-attestation authority, 2026-06-29.
```

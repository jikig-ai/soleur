# Legitimate Interest Assessment: Flag Flip Audit Processing

**Date:** 2026-05-25
**Author:** Jean Deruelle
**Lawful basis:** Art. 6(1)(f) GDPR — legitimate interest
**Related:** Migration 071 (`flag_flip_audit` table), ADR-043, umbrella #4456 PR-2

## 1. Purpose

Record every skill-driven feature-flag mutation (create, on, off, archive) in a WORM ledger for:
- **Art. 32(1)(d) effectiveness-of-TOMs:** evidence that security controls (flag gates) were correctly managed
- **SOC2 CC8.1 change management:** audit trail proving who changed what, when, and why
- **Incident response:** forensic reconstruction of flag state at any point in time

## 2. Three-Part Test

### 2.1 Legitimate Interest (Art. 6(1)(f) first limb)

The controller has a legitimate interest in maintaining an immutable record of access-control configuration changes. Feature flags gate tenant-boundary features (`team-workspace-invite`, `byok-delegations`); misconfiguration is a cross-tenant exposure vector. The audit trail:
- Enables rapid root-cause analysis during incidents
- Satisfies SOC2 CC8.1 evidence requirements without manual logging
- Provides Art. 32(1)(d) effectiveness proof for supervisory authorities

### 2.2 Necessity (Art. 6(1)(f) second limb)

- **Conversation history is volatile:** clearable, per-session, not searchable — unsuitable as an evidence standard
- **Git history records intent (commit) not execution (runtime flip):** skill scripts may be re-run, rolled back, or partially applied
- **Structured WORM is the minimum evidence standard** that satisfies both SOC2 auditors and DPA supervisory authorities

No less intrusive measure provides equivalent forensic fidelity.

### 2.3 Balancing Test (Art. 6(1)(f) third limb)

| Factor | Assessment |
|---|---|
| **Data subject** | Operator (controller employee), not end-user |
| **Data category** | Operator email address (corporate, not personal) |
| **Sensitivity** | Non-sensitive (work email performing job function) |
| **Reasonable expectation** | Operators expect their administrative actions to be logged |
| **Impact on data subject** | Minimal — no profiling, no automated decision-making |
| **Safeguards** | WORM immutability, RLS with zero policies (service-role only), 7-year retention aligned to SOC2 evidence window |
| **Opt-out mechanism** | Not applicable — operator is performing a controller function |

**Conclusion:** The legitimate interest clearly outweighs any minimal impact on the operator data subject. Processing is proportionate and necessary.

## 3. Data Minimization

- **Actor field:** operator email only (no user PII, no IP, no session token)
- **No FK to users table:** `actor` is a CHECK-constrained text field, not a UUID reference
- **transient: true on Flagsmith calls:** identity evaluation is not persisted server-side
- **Retention:** 7 years (SOC2 CC8.1 evidence window), then row-state-bypass DELETE permitted

## 4. Technical Controls

- WORM enforcement: two Postgres triggers (no_update, no_delete on unexpired rows)
- Access control: SECURITY DEFINER writer RPC, service_role only
- Integrity: `search_path = public, pg_temp` pinned on all functions
- Input validation: `actor` CHECK regex ensures well-formed lowercase email

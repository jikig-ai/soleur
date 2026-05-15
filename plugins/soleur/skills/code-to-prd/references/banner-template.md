<!-- BANNER:DUE-DILIGENCE — non-removable per code-to-prd FR7 -->
> **Due-diligence disclaimer.** This PRD is auto-generated from source code by `code-to-prd` (#2726). It is a best-effort regex-driven snapshot, not an exhaustive specification. Routes, state shapes, and external dependencies are extracted from filesystem walk + grep — no AST analysis is performed in v1. Verify any load-bearing claim against the source tree before relying on it for an acquisition, valuation, or audit decision.

<!-- BANNER:PII-CONFIDENTIALITY — non-removable per code-to-prd FR7 -->
> **Confidentiality / PII notice.** This PRD may reference business logic, environment-variable names, and route topology. Secret values, JWTs, API keys, and the 14 redaction classes enumerated in `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` are scrubbed at write-time by a 3-layer fail-closed pipeline (path filter → sentinel → gitleaks). Redacted tokens render as `<8-prefix>***<8-suffix>`. Treat this document as containing the business posture of the codebase — share it with the same care you would the codebase itself.

### How to Read This PRD

- **Redaction-token format.** When a token would have appeared in the source, the PRD shows `<8-prefix>***<8-suffix>` instead. The token format is the redaction signature, not a leak.
- **Redacted ≠ leaked.** A redaction marker means the scanner *found and removed* a secret. Nothing sensitive landed in this document.
- **If you see a token shape (`sk_…`, `ghp_…`, `eyJ…`, etc.) in plaintext:** the source file contained that secret. Rotate the credential, move it to `.env`, and regenerate the PRD.
- **Coverage Caveats** at the end of this PRD enumerates what was excluded, which frameworks were not scanned, and the GDPR Art. 9 special-category gap. Read it before sharing.

---
title: "Counsel review audit — #4952 (PR #4954 autonomous command execution disclosure: AUP §5.7 + T&C §3a.7/§10.4 + TC_VERSION 2.3.0)"
type: counsel-review
date: 2026-06-04
issue: 4952
pr: 4954
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-06-04
signed_off_by: "Soleur CLO agent (Jikigai SARL — v1 internal counsel-review attestation authority; operator retains optional veto)"
disposition: DISCHARGED
re_evaluation_triggers: "First arms-length (non-Soleur) Workspace Owner enabling/inheriting autonomous command execution; first EEA-out operator running autonomous mode; first regulated-industry tenant (healthcare/finance/legal); OR any narrowing of the BLOCKED_BASH_PATTERNS blocklist OR widening of the read-only auto-approve allowlist that changes the illustrative blocklist verbs disclosed in AUP §5.7 (which would require re-pinning the disclosure prose AND the AUTONOMOUS_DISCLOSURE_COPY LOCKED COPY in lockstep); OR conversion of autonomous command execution into a third-party-effecting send (which would move it under §3a.1-3a.6 / Art. 22 and require an Art. 22(3) human-review affordance)"
---

# Counsel review audit — #4952 (autonomous command execution disclosure)

Load-bearing evidence for the ship-time Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #4954 (`feat-one-shot-aup-tos-autonomous-cmd-disclosure`, `brand_survival_threshold: single-user incident`). The legal artifacts below carry ADDITIVE disclosures for the Web Platform agent's autonomous (auto-run) shell-command surface shipped by PR #4949 (default-ON autonomy + first-run owner consent soft-gate). Each disclosure was cross-checked claim-by-claim against the IMPLEMENTING TypeScript — not trusted on prose alone — per the prose-against-code drift class recorded at PR #4353/#4558. Per the Soleur-as-tenant-zero v1 posture, the CLO agent performs this review and returns a per-artifact verdict; the operator (non-lawyer founder) retains an optional veto, and external counsel re-review is reserved for the frontmatter re-evaluation triggers.

The PR is held until this disposition is **DISCHARGED**.

## Implementation files cross-checked

- `apps/web-platform/server/permission-callback.ts` — `BLOCKED_BASH_PATTERNS` (authoritative blocklist regex) + `isBashCommandBlocked` + the `bashAutonomous` toggle / `verifyAutonomousAck` defense-in-depth consent re-check / `resolveAckPosture` live-in-session ack getter / `autonomous_disclosure` gate-kind HOLD model.
- `apps/web-platform/components/chat/autonomous-disclosure-banner.tsx` — `AUTONOMOUS_DISCLOSURE_COPY` (the in-product LOCKED COPY) + the default-ON ("Got it") vs existing-workspace ("Keep autonomous on" / "Ask me each time") soft-gate branch.
- `knowledge-base/legal/article-30-register.md` — PA-2 §(b) Purposes + §(g) TOMs (Art. 32) — the interactive Concierge runtime home; PA-21 / PA-22 (Inngest `agent.spawn.requested` TodayCard leader-prompt runtime) to confirm the NOT-PA-21/22 disambiguation.
- `knowledge-base/legal/tc-version-bump-policy.md` — Tier-1 material rubric + semver-for-legal-docs MINOR definition.

## Prose ↔ implementation fidelity (drift table — CONFIRMED CLEAN)

| Prose claim (AUP §5.7 / T&C §3a.7 / §10.4 / AUTONOMOUS_DISCLOSURE_COPY) | Code evidence | Verdict |
|---|---|---|
| Blocklist illustrative verbs: `curl`, `wget`, `nc`/`ncat`, `eval`, `sudo`, inline interpreter `-e`/`-c`, `base64 -d`, `/dev/tcp` (AUP §5.7, "for example") | `BLOCKED_BASH_PATTERNS = /\b(?:curl\|wget\|ncat\|nc\|eval\|sudo)\b\|(?:sh\|bash\|node\|python\|python3\|ruby\|perl\|deno\|bun)\s+-(?:e\|c)\b\|deno\s+eval\b\|base64\s+-d\|\/dev\/tcp/i` | MATCH. Every disclosed verb is in the regex. AUP frames the list as "for example" (illustrative) — consistent with the "illustrative and not exhaustive" admission and with the code (regex also blocks `deno eval`; over-coverage of the regex vs prose is harmless). |
| "auto-approves only a narrow read-only allowlist; commands neither blocked nor on that allowlist run automatically under autonomous mode" | `isBashCommandSafe` / `SAFE_BASH_PATTERNS` (re-exported from `./safe-bash`) gate the read-only auto-approve; `bashAutonomous` true auto-approves every NON-BLOCKED command, with `isBashCommandBlocked` AUTHORITATIVE (toggle bypasses ONLY the review-gate, NEVER the blocklist) | MATCH. The three-way partition (blocked / read-only-allowlisted / neither-→-auto-run-under-autonomy) is faithful. |
| "first-run owner consent soft-gate … the command is held … Owner's acknowledgement is recorded per workspace and releases the held command" (T&C §3a.7 Consent model) | `gateKind: "autonomous_disclosure"` HOLD path; `verifyAutonomousAck` re-checks the per-workspace ack was persisted before `allow()`; banner default-ON "Got it" writes ack + releases | MATCH. Hold-not-auto-approve on first non-blocked command with no recorded ack is exactly the disclosed model. |
| "Owner may keep the workspace in autonomous (trusted) mode or return it to ask-each-time at any time" | Banner existing-workspace branch: "Keep autonomous on" (sets `bash_autonomous=true` + ack) vs "Ask me each time" (leaves false + ack); `bashAutonomous` per-workspace toggle | MATCH. |
| Mitigations: "work is git-backed (the connected repository is the recovery surface) and every command is visible in the chat as it runs" | `AUTONOMOUS_DISCLOSURE_COPY`: "Your work is backed up in git, and you can watch every command run in the chat." | MATCH — substantively identical to the in-product LOCKED COPY (no second source of truth). |
| "no blocklist is perfect. A command that looks safe could still change or delete files in this workspace" | `AUTONOMOUS_DISCLOSURE_COPY` verbatim: "but no blocklist is perfect. A command that looks safe could still change or delete files in this workspace." | MATCH — the contract prose (AUP §5.7 / T&C §3a.7 / §10.4) is the contractual counterpart of the banner; no divergence. |
| "Only connect repos and accounts you trust" (responsibility) | `AUTONOMOUS_DISCLOSURE_COPY`: "Only connect repos and accounts you trust." | MATCH — AUP §5.7 "Your responsibilities" and T&C §3a.7/§10.4 mirror this. |

No drift found. The contract prose does not over-claim any safety guarantee the code does not provide; the banner's "hides your secrets" claim (secret redaction) is a SUPERSET disclosure the contract does not lean on for any warranty, so its omission from the contract is conservative, not a divergence.

## Resolution of the five attested questions

### 1. Tier-1 bump classification — CONFIRMED (MINOR → 2.3.0)

New T&C §10.4 introduces **disclaimer-of-warranty text not previously present** ("TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, WE DO NOT WARRANT THAT AUTONOMOUS COMMAND EXECUTION CANNOT RUN A COMMAND THAT CHANGES OR DELETES FILES …"). Per `tc-version-bump-policy.md` Tier-1 rubric ("New disclaimer-of-warranty or limitation-of-liability text not previously present, or material narrowing of the user's rights") this is **Tier-1 Material → BUMP REQUIRED**. Under the semver-for-legal-docs scheme a material change consistent with the user's prior expectations is a **MINOR** bump: `2.2.1 → 2.3.0`. The bump forces `/accept-terms` re-acceptance — the correct UX for a residual-risk admission. `TC_VERSION = "2.3.0"` confirmed in `tc-version.ts`; seed-script parity confirmed (`seed-dev-users.sh` + `seed-qa-user.sh` → 2.3.0). **VERDICT: PASS.**

### 2. Lawful basis / Art. 22 — CONFIRMED (no collision with §3a.6)

T&C §3a.6 ("Right to human review (GDPR Article 22(3))") governs automated **decisions producing legal/significant effects** and offers the human-review affordance. §3a.7's closing "GDPR Article 22" paragraph correctly frames autonomous command execution as "a development-workflow action on your own connected systems, not automated decision-making that produces legal or similarly significant effects on a third party," and explicitly routes third-party effects back to §3a.1-3a.6 with the §3a.6 Art. 22(3) right preserved. The own-workspace-vs-third-party-send distinction is clean: §3a.7's opening paragraph distinguishes "third-party 'sends' governed by Sections 3a.1 through 3a.6" (external effects under the scope-grant model) from "commands that the agent runs on your own connected workspace." No §3a.6 right is narrowed, removed, or contradicted. **VERDICT: PASS.**

### 3. Art. 30 disposition — CONFIRMED (PA-2 anchor correct; no TOM narrowed; PA-21/22 mis-cite fixed)

- **PA-2 is the correct anchor.** PA-2 §(b) Purposes registers "Provide conversational-AI interactions with Soleur domain-specific agents; persist user prompts, assistant responses, and **tool-call metadata** …" — the interactive Concierge runtime (cc-dispatcher / permission-callback conversation surface). Autonomous command execution is a tool-call on the operator's own connected workspace WITHIN that already-registered runtime — no new processing purpose, personal-data category, recipient, or sub-processor. No Art. 30 amendment required. CONFIRMED.
- **PA-21/22 mis-cite fix landed.** Verified directly: PA-21 ("Autonomous-acknowledgment runtime, Inngest `agent.spawn.requested`, PR-A #4124") and PA-22 ("Autonomous AI leader-prompt runtime, Anthropic SDK, PR-B #4379") are the distinct **Inngest TodayCard leader-prompt** surface, NOT the interactive Concierge chat runtime. Both the compliance-posture HTML comment and the Completed-Work table row now read "NOT PA 21/22 (those are the separate Inngest agent.spawn TodayCard leader-prompt runtime)." The earlier draft's mis-citation is corrected. CONFIRMED.
- **Removing per-command approval narrows no registered PA-2 §(g) TOM.** PA-2's Art. 32 §(g) measures protect THIRD-PARTY data subjects' conversation data: RLS scoping (`messages`/`conversations`), per-user JWT mint (`getFreshTenantClient`), write-boundary sentinel (`assertWriteScope`), data-minimisation (`messages.usage` cost-only), attachment-storage isolation, and Art. 15(4) DSAR redaction. **None of these gates shell-command approval.** The per-command human-approval step that default-ON autonomy removes is a workspace-safety control on the **operator's own systems** (the operator is both actor and controller-of-record at the single-user threshold), not a registered TOM protecting another data subject. Its removal therefore narrows no registered limb and triggers no PA-2 amendment. **VERDICT: PASS.**

### 4. In-product vs contract consistency — CONFIRMED

AUP §5.7, T&C §3a.7, and T&C §10.4 are substantively consistent with `AUTONOMOUS_DISCLOSURE_COPY` (see drift table above). The LOCKED COPY banner states the residual-risk admission in summary form; the three contract sections are its contractual counterpart and cross-reference it explicitly. No divergence-liability gap (the contract neither over-promises beyond the banner nor under-discloses the banner's risk admission). The 3-way Eleventy lockstep is byte-equivalent: AUP §5.7, T&C §3a.7, and T&C §10.4 section bodies are IDENTICAL between `docs/legal/` canonical and `plugins/soleur/docs/pages/legal/` mirror (diff-verified). **VERDICT: PASS.**

### 5. EU mandatory rights — CONFIRMED (carve-outs preserved)

T&C §10.4's warranty disclaimer closes with: "This Section does not limit or exclude any liability that cannot be limited or excluded under mandatory applicable law (see Section 11.3), and the EU consumer-rights reservation in Section 10.3 applies." Both referenced carve-outs exist and are non-excludable: §10.3 ("EU Consumer Rights") preserves mandatory statutory warranty rights for EU/EEA consumers; §11.3 ("EU/EEA Limitations") preserves non-excludable liability. The "TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW" qualifier on the disclaimer itself is the standard mandatory-law floor. The disclaimer does not purport to waive any non-excludable EU consumer right. **VERDICT: PASS.**

## Per-artifact verdicts

| Artifact | File(s) | Verdict |
|---|---|---|
| AUP §5.7 + §2 scope clause | `docs/legal/acceptable-use-policy.md` + `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` | ☑ PASS — residual-risk admission accurate against `BLOCKED_BASH_PATTERNS`; mitigations stated as mitigations not guarantees; responsibilities mirror banner; §2 scope clause cross-references §5.7 and T&C §3a.7. |
| T&C §3a.7 (consent model + residual risk + Art. 22 distinction) | `docs/legal/terms-and-conditions.md` + mirror | ☑ PASS — consent soft-gate model faithful to the HOLD/ack/release code; own-workspace-vs-third-party-send Art. 22 distinction does not collide with §3a.6. |
| T&C §10.4 (disclaimer-of-warranty) | `docs/legal/terms-and-conditions.md` + mirror | ☑ PASS — Tier-1 material (drives the MINOR bump); §10.3 / §11.3 non-excludable carve-outs preserved. |
| T&C §9 prohibited-use bullet | `docs/legal/terms-and-conditions.md` + mirror | ☑ PASS — prohibits circumventing the command-safety layer and connecting unauthorized repos/accounts; consistent with §3a.7 responsibilities. |
| SHA repins + TC_VERSION + bump metadata | `apps/web-platform/lib/legal/{legal-doc-shas.ts,tc-version.ts}` | ☑ PASS — `TC_DOCUMENT_SHA` = `19d9fc6e…0cc738` and `LEGAL_DOC_SHAS["acceptable-use-policy"]` = `d6824e40…21ba` both match freshly-computed `sha256sum` of the final bytes; `TC_VERSION 2.3.0`; `TC_BUMP_METADATA` updated (June 4, 2026 / "§Autonomous command execution residual-risk disclosure"). |
| Eleventy 3-way lockstep | `plugins/soleur/docs/pages/legal/{acceptable-use-policy,terms-and-conditions}.md` | ☑ PASS — §5.7 / §3a.7 / §10.4 section bodies byte-identical to canonical; Last-Updated date + hero line updated to June 4, 2026. |
| Article 30 disposition | `knowledge-base/legal/compliance-posture.md` (no register edit) | ☑ PASS — no PA amendment required; PA-2 anchor correct; PA-21/22 mis-cite corrected; no §(g) TOM narrowed. |

## Overall disposition

**DISCHARGED.** All five attested questions PASS; every per-artifact verdict is ☑; the disclosure prose is clean against the implementing `BLOCKED_BASH_PATTERNS`, the `bashAutonomous`/ack HOLD model, and the `AUTONOMOUS_DISCLOSURE_COPY` LOCKED COPY; SHAs and TC_VERSION are correctly pinned; no Article 30 amendment is owed. This is the v1 internal CLO-agent attestation under the Soleur-as-tenant-zero posture; the operator retains an optional veto, and external counsel re-review is reserved for the frontmatter re-evaluation triggers.

---
title: "Counsel review audit — #9601 / PR #9599 (Art. 32 TOM entry: Anthropic API key withheld from sandboxed Bash in hosted agent sessions, ADR-272)"
type: counsel-review
date: 2026-10-06
issue: 9601
pr: 9599
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-06
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "BLOCKED as drafted; DISCHARGED on verbatim application of W1 (replacement bullet below). Every checkable claim in the drafted bullet is true. It is blocked for omission, not falsehood: it does not say the measurement was taken on a development host and not in the production image, it does not say the control fails open silently, it does not say the status is 'adopting', and 'hosted agent sessions' reads wider than the interactive paths the control covers. A regulator reading the Art. 32 list would take it as an in-production, all-sessions control."
blocking_findings:
  - "B1 — Scope omissions. (a) Measured on a dev host, not the production container image (ADR-272 Consequences; phase-0 §1.3); the in-image canary is blocked on #9614. (b) A renamed, re-shaped or ignored `credentials` block fails open with no error (phase-0 §1.5), so no runtime signal exists; detection is CI-only. (c) ADR status is 'adopting', not 'accepted'. (d) Inngest-spawned platform agents (operator key, `sandbox.enabled:false`) and `pdf-chapter-router` are outside the measure; 'hosted agent sessions' is unqualified."
applied_in_review:
  - "W1 — Replacement bullet text (below), to be applied by the lead. Adds B1(a)-(d), names other LLM-provider keys as covered by the connected-service-token residual, drops 'owner's' (the credential is whatever `buildAgentEnv` injects for the session; BYOK delegation was not measured and is not asserted), and keeps the no-public-claim sentence with an as-of date."
conditions:
  - "C1 — Re-measure on the production image when #9614 lands; only then may the entry drop 'development host' and 'adopting' (ADR-272 becomes 'accepted')."
  - "C2 — Any SDK bump re-runs `sandbox-credential-deny-argv.test.ts` and `sandbox-credential-deny-runtime.test.ts` (the only detectors). If the SDK stops honouring `sandbox.credentials`, this entry becomes false and must be amended the same day."
  - "C3 — Public-surface lockstep: none required today. Before any public security claim about credential isolation is written (#9603), the claim is limited to what this entry states, and canonical + Eleventy mirror + `legal-doc-shas.ts` move together."
re_evaluation_triggers: "First measurement on the production image (#9614) OR credential broker lands (#9543, residual moves) OR SDK bump that changes `sandbox.credentials` behaviour OR any observed read of a service token / GH_TOKEN by an agent command (Art. 33 triage) OR first arms-length user OR EEA-out data subject OR regulated-industry user."
---

# Counsel review audit — #9601 (ADR-272 Art. 32 TOM entry)

Internal v1 counsel-review attestation for PR #9599 (`single-user incident`), which adds one bullet to `knowledge-base/legal/article-30-register.md` under *Cross-Cutting Technical & Organisational Measures (Art. 32)*. Draft material; external counsel is reserved for the frontmatter triggers.

**Method.** Each claim checked against ADR-272, `phase-0-measurements.md`, `server/agent-auth-env-vars.ts` (`AGENT_AUTH_ENV_VARS`), `server/agent-runner-sandbox-config.ts` (`buildAgentSandboxConfig`, `credentials` block), `server/agent-env.ts` (`buildAgentEnv`, auth-variable switch), `server/soleur-go-runner.ts` (`CREDENTIALS_PROMPT_DIRECTIVE`), and the public documents `docs/legal/{gdpr-policy,privacy-policy,data-protection-disclosure}.md` plus the `plugins/soleur/docs/pages/legal/` mirrors. Code is cited by name, not line.

## Per-claim verdicts

| Claim in the drafted bullet | Checked against | Verdict |
|---|---|---|
| Anthropic key unset for sandboxed `Bash` | `buildAgentSandboxConfig` returns `credentials.envVars` deny entries from `AGENT_AUTH_ENV_VARS`; phase-0 §1.1 control arm PRESENT, treatment ABSENT | TRUE (dev host) |
| Mechanism = SDK `sandbox.credentials` deny entries | same config block; ADR Decision 1 | TRUE |
| Measured 2026-10-06 on SDK 0.3.284 | phase-0 header; ADR Measurements | TRUE, but incomplete: omits dev host, decoy values, no production image |
| "hosted agent sessions" | Deny rides the shared builder: legacy runner and Concierge dispatcher (pinned by tests). Inngest `cron-*`/`oneshot-*`/`event-ship-merge` agents use the operator key with `sandbox.enabled:false`; `pdf-chapter-router` has no Bash | OVERBROAD. Qualify as interactive sessions; name the exclusion (B1d) |
| Agent process keeps the key for its own calls | ADR Decision 1; CLI authenticated in every treatment arm | TRUE |
| "owner's" key | `buildAgentEnv` injects whatever `AgentCredential` the session resolved; BYOK-delegation was not measured | UNVERIFIED wording; replaced with "the session's Anthropic credential" |
| Connected-service tokens, `GH_TOKEN`, git installation token readable | phase-0 table (PRESENT in both arms); ADR Decision 3, Residuals | TRUE |
| Credential file readable by server user | phase-0 §1.1 credentials-file residual (both arms) | TRUE |
| Hooks and in-process tools run outside the sandbox | ADR Residuals | TRUE |
| "No public document makes a claim about this measure" | grep of the three canonical documents and mirrors for sandbox / environment / credential-isolation language: no hit. The only nearby sentences are CRM-scoped (GDPR Policy DPIA status "within-tenant prompt-injection ... human-approval gate on every agent write", scoped to the `beta_contacts` store) and the Flagsmith "BYOK keys do NOT egress" limb | TRUE as of 2026-10-06; add the date |
| (implied) protection of other credentials / production image / tenant data | Not claimed in the draft; also not disclaimed for the image or for provider keys | Add explicit disclaimers |
| Omitted: fails open silently, no runtime tripwire | phase-0 §1.5; ADR Status | MUST ADD (affects the TOM's reliability, which is the Art. 32(1) "effectiveness" question) |
| Omitted: status adopting | ADR Status | MUST ADD |

## Public-disclosure cross-check

No public sentence overstates, contradicts or goes stale because of this bullet. Privacy Policy, GDPR Policy and the DPD describe BYOK storage (AES-256-GCM, lease, audit rows) and processors; none states that an agent's shell cannot read credentials, and none states the converse. The Art. 30 register is not a published surface. The GDPR Policy DPIA sentence is CRM-scoped and unaffected. Keeping the public documents silent is the correct posture until #9603; writing a "your key is isolated from agent commands" sentence now would overclaim (dev-host measurement, silent fail-open, residuals). Gates over `docs/legal/**` are not triggered by this PR (register only).

## Art. 30 / 32 / 33 consequences of the residuals

- **Art. 30(1)(g) / Art. 32.** The register describes TOMs "where possible"; a TOM entry that names its own gaps is the compliant form, and the draft already does. The residuals (service tokens and `GH_TOKEN` readable by a prompt-injected agent) mean Art. 32(1) "appropriate to the risk" rests on: closed egress (`allowedDomains: []`, except the entitled-token GitHub allowlist), per-session short-lived installation token, human-approval gates on writes, and the dated credential-broker follow-up (#9543). Note the egress closure is conditional, and where the GitHub allowlist applies a token could in principle be sent to a GitHub-hosted sink; the bullet must not imply egress is always closed (it does not). Recommend, non-blocking, that #9543 carry an owner and a date, since an open-ended residual is the weakest part of an Art. 32 record.
- **Art. 33.** The existence of a readable-token residual is not a personal-data breach and starts no clock. A breach is an actual breach of security leading to unauthorised disclosure or access. If a session is observed to have read or exfiltrated a connected-service token or the installation token, that is a confidentiality event; the Art. 33 clock runs 72 hours from awareness, assessed per `knowledge-base/legal/breach-register.md`, and the `incident` skill applies. The material point: the operator's reliance on this TOM must not lead to a "the key was withheld" closing argument for a token that was not withheld. The register bullet's explicit residual list is what prevents that.
- **Art. 28 / controller-processor.** No change. Service tokens belong to the connected third parties; their exposure would also trigger the processor-side notification duties of those vendors, not new Soleur Art. 30 entries.

## Replacement bullet (W1, apply verbatim in place of the drafted bullet)

```markdown
- **Anthropic API key withheld from sandboxed Bash in interactive agent sessions (ADR-272, #9601; status: adopting):** in interactive hosted agent sessions (the legacy runner and the Concierge dispatcher), `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` are unset for commands run through the sandboxed `Bash` tool (SDK `sandbox.credentials` deny entries); the agent process itself keeps the session's Anthropic credential for its own API calls. **Measured, and how far:** on 2026-10-06, SDK 0.3.284, on a development host with decoy values and a scripted API stand-in (no real credential), the API key was present in sandboxed Bash without the entries and absent with them, including from the process environment, readable `/proc/<pid>/environ` files and `ps`; the OAuth token was already withheld by the CLI before these entries. **Not measured:** the production container image (its seccomp and AppArmor profiles differ; the in-image canary is pending, #9614). **Reliability limit:** the SDK accepts a malformed or ignored `credentials` block silently, so there is no runtime signal if the control stops applying; detection is by CI tests only. **Not covered, recorded rather than implied:** connected-service tokens (including any other LLM-provider keys connected as services), `GH_TOKEN` and the git installation token remain readable by sandboxed commands, and so by a prompt-injected agent, until the credential broker (#9543); any credential file readable by the server user is readable from sandboxed commands; hooks and in-process tools run outside the sandbox with the full environment; platform-authored Inngest agent jobs (operator key, sandbox disabled) are outside this measure. This entry makes no statement about tenant data or any other credential. As of 2026-10-06 no public legal document makes a claim about this measure; public security claims are held until it is measured in production (#9603).
```

## Disposition

BLOCKED as drafted; DISCHARGED when W1 is applied verbatim (no re-review needed if verbatim). Conditions C1-C3 stay open and are tracked by #9614, #9543 and #9603.

## Disposition record

DISCHARGED 2026-10-06: the W1 replacement bullet above was applied verbatim to `knowledge-base/legal/article-30-register.md` in the same PR (#9599). Conditions C1-C3 remain open as listed.

---
title: "Counsel review audit — #9776 (autonomous-mode disclosure copy: force-push over the default branch and infrastructure teardown; AUP §5.7 + T&C §3a.7/§10.4; TC_VERSION 2.5.1 -> 2.6.0; ack reset)"
type: counsel-review
date: 2026-10-08
issue: 9776
pr: 9792
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-10-08
signed_off_by: "CLO agent"
disposition: "DISCHARGED on verbatim application of the CLO ruling of 2026-10-08, with conditions C1-C4"
conditions:
  - "C1 — ack reset migration: moves autonomous_disclosure_ack_at into autonomous_disclosure_ack_superseded_at where bash_autonomous is true, with no write to the toggle column."
  - "C2 — deploy order: the release pipeline applies migrations before it swaps the build, so a window exists in which an old-build owner can re-acknowledge the OLD copy. Accepted with a mitigation, not eliminated: before the merge goes live the PR body states the window, and after the new build is serving the supersede UPDATE is re-run with a cutoff (COALESCE keeps the first superseded timestamp) under the owner explicit go-ahead for a production write. A versioned acknowledgement (copy version recorded with the ack) is the durable fix and is recommended on #9776."
  - "C3 — the banner, the enable-confirm dialog, AUP §5.7 and T&C §3a.7/§10.4 carry the same exposure statement; TC_VERSION 2.6.0; SHAs repinned; canonical and Eleventy mirror byte-equal."
  - "C4 — #9776 ships a same-PR copy revision and a legal-text follow-up for the '(and at the date of this version it does not)' parenthetical."
supersedes_in_part: knowledge-base/legal/audits/2026-06-counsel-review-4952.md
re_evaluation_triggers: "Merge of the #9776 ask-gate (copy and contract narrowing review; a narrowing needs no re-ack); any new unblocked destructive command family; any change to BLOCKED_BASH_PATTERNS or the read-only allowlist; first arms-length Workspace Owner; first EEA-out operator; first regulated-industry tenant; any conversion of autonomous execution into a third-party-effecting send (Art. 22(3))"
---

# Counsel review audit — #9776 (autonomous-mode disclosure copy)

Load-bearing evidence for the ship-time Counsel-Review CLO-Attestation Gate on the PR that closes the CPO3-R2 required change for #9776. It supersedes in part `2026-06-counsel-review-4952.md`: that audit found the disclosure prose "CONFIRMED CLEAN" while the code did not block a force-push over the default branch or infrastructure teardown, and while the in-product copy told the owner their work was "backed up in git" and that Soleur "always blocks clearly dangerous commands" and "hides your secrets". Those three claims are removed. The June audit's body is not amended; it carries superseded markers that point here.

Under the Soleur-as-tenant-zero v1 posture the CLO agent performs this review; the operator retains an optional veto. Per-artifact verdicts below are written in the conditional: each fires on the merge of the PR that carries this change.

## Code cross-checked (by name)

- `apps/web-platform/server/permission-callback.ts` — `BLOCKED_BASH_PATTERNS` and `isBashCommandBlocked` (authoritative blocklist); the autonomous branch (`deps.bashAutonomous`), `resolveAckPosture` (live in-session ack cell, falling back to the frozen `autonomousAckAt`), the `autonomous_disclosure` hold, and the `verifyAutonomousAck` defense-in-depth re-read that runs only inside the hold branch.
- `apps/web-platform/server/set-autonomous-ack.ts`, `server/resolve-autonomous-ack.ts` and migration 099 — `set_workspace_autonomous_ack` (owner-only, `COALESCE`, never overwritten) and `get_workspace_autonomous_ack` (member read, NULL fail-closed to HOLD). The ack is a bare `autonomous_disclosure_ack_at timestamptz`; it records no copy text and no version.
- `apps/web-platform/server/agent-runner-sandbox-config.ts` — `ENTITLED_EGRESS_DOMAINS` (`github.com`, `api.github.com`, `registry.npmjs.org`, the GitHub Actions log-signed-URL hosts) and the `network.allowedDomains` build (`allowGithubEgress ? [...ENTITLED_EGRESS_DOMAINS] : []`, `allowManagedDomainsOnly: true`). Egress is closed except those hosts, so the copy says Soleur can RUN the command without asking, not that it will succeed.
- `apps/web-platform/server/agent-env.ts` — the `GIT_ASKPASS` helper and the GitHub App installation token (never a PAT): hosted sessions can authenticate a `git push` from inside the sandbox.

## Drift table (prose against code)

| Claim | Code evidence | Verdict |
|---|---|---|
| Blocklist verbs `curl`, `wget`, `sudo`, `nc`/`ncat`, `eval`, inline `-e`/`-c`, `base64 -d`, `/dev/tcp` | `BLOCKED_BASH_PATTERNS` regex | MATCH |
| A force-push over (or deletion of) the default branch is not blocked and can run without asking | `git push --force origin main`, `git push -f`, `git push origin +main`, `git push origin :main` and `git push --delete origin main` do not match `BLOCKED_BASH_PATTERNS` | MATCH — disclosed |
| `terraform destroy` / `tofu destroy` / `terraform apply -destroy` are not blocked | `terraform destroy`, `tofu destroy -auto-approve`, `terraform apply -destroy` and `gh repo delete x --yes` do not match the regex | MATCH — disclosed, with the caveat that success depends on reach (sandbox egress is closed except `ENTITLED_EGRESS_DOMAINS`) |
| Pushing is possible from the hosted sandbox | `GIT_ASKPASS` + installation token in `agent-env.ts`; `github.com` is in `ENTITLED_EGRESS_DOMAINS` | MATCH |
| "hides your secrets" (old banner) | Redaction is not a protection against a command the model chooses to run | FALSE as a protection claim — removed |
| "backed up in git" / "recovery surface" (old banner, AUP §5.7, T&C §3a.7/§10.4) | The remote default branch is itself exposed to force-push and deletion | FALSE for this case — removed and replaced with a not-a-backup statement |
| "always blocks clearly dangerous commands" (old banner) | Force-push and `terraform destroy` are dangerous and not blocked | FALSE — removed |
| "Until a stricter check ships" | The #9776 ask-gate has not shipped at the date of this version | TRUE at date, time-bound (C4 follow-up) |

## Questions 1-6

1. **Tier 1 MINOR (2.5.1 -> 2.6.0) — PASS.** AUP §5.7 and T&C §3a.7/§10.4 add a disclaimer that the command-safety layer will not stop, or ask first about, a destructive remote or infrastructure command, and withdraw a mitigation claim. That is new disclaimer text and a narrowing of the user's expectations under `tc-version-bump-policy.md` Tier 1; it is consistent with the prior direction of the document, so MINOR. The bump forces `/accept-terms` re-acceptance.
2. **Ack validity — reset required.** The prior ack evidences consent to copy that affirmatively said the work was backed up in git. It is therefore not informed consent to this risk, and the ack is reset. A change that only narrows the exposure statement later (for example when the ask-gate ships) needs no re-ack.
3. **Art. 13 — improves.** The owner now sees the exposure before consent; `tc_acceptances` records version and SHA for the re-acceptance.
4. **Art. 22 — unchanged.** Force-push and teardown act on the owner's own connected systems, not on a third party; §3a.6 is untouched.
5. **Art. 30 / Art. 32 — no change.** No new purpose, data category, recipient or sub-processor; PA-2 is unchanged. No Privacy Policy, GDPR Policy, DPD or register edit.
6. **EU mandatory rights — retained.** The §10.3 and §11.3 carve-outs are left untouched.

## Per-artifact verdicts

| Artifact | Verdict |
|---|---|
| Banner `autonomous-disclosure-banner.tsx` + test (LOCKED re-locked 2026-10-08, #9776) | Would PASS on the merge of the PR that carries this change: copy verbatim from the ruling; the removed claims asserted absent. |
| Enable-confirm dialog `bash-autonomous-toggle.tsx` + test | Would PASS on the merge of the PR that carries this change: copy verbatim; `/no blocklist is perfect/i` still matches. |
| AUP §5.7 (canonical + Eleventy mirror) | Would PASS on the merge of the PR that carries this change: bold exposure sentence appended to paragraph 2; paragraph 3 recovery claim replaced. |
| T&C §3a.7 and §10.4 (canonical + Eleventy mirror) | Would PASS on the merge of the PR that carries this change: residual-risk admission, mitigations and §10.4 disclaimer updated; §10.3 and §11.3 untouched. |
| Migration 159 + test + verify sentinel | Would PASS on the merge of the PR that carries this change, subject to C2: one UPDATE scoped to `bash_autonomous AND autonomous_disclosure_ack_at IS NOT NULL`; the toggle column is not written. |
| SHA / version / seed repins | Would PASS on the merge of the PR that carries this change: `TC_VERSION` 2.6.0, `TC_DOCUMENT_SHA` and `LEGAL_DOC_SHAS["acceptable-use-policy"]` repinned on final bytes, `seed-dev-users.sh` and `seed-qa-user.sh` at 2.6.0, `TC_BUMP_METADATA` updated. |

## Overall disposition

**DISCHARGED** on verbatim application of the 2026-10-08 CLO ruling with conditions C1-C4. This is the v1 internal CLO-agent attestation under the Soleur-as-tenant-zero posture; the operator retains an optional veto, and external counsel re-review is reserved for the frontmatter re-evaluation triggers.

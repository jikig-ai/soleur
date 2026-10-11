# CLO ruling on #9776 (hosted autonomous ask lane) - binding

Date 2026-10-10. Agent-attested under the Soleur-as-tenant-zero v1 posture; the operator keeps an optional veto. Draft material, not legal advice; external counsel is reserved for the re-evaluation triggers in section 6. Reads: `cto-ruling.md` (RULING 1, Copy and legal, Rollout), `knowledge-base/legal/audits/2026-10-counsel-review-9776.md`, `tc-version-bump-policy.md`, `tc-version.ts` (TC_VERSION 2.6.0), `legal-doc-shas.ts`, the banner and toggle components, AUP 5.7, T&C 3a.7 and 10.4, and the temporal-qualifier learning of 2026-05-25. This ruling creates no legal-doc edit and no product-code edit.

## 0. Verdict in one table

| Item | Ruling |
|---|---|
| Banner copy | Replace with the text in section 1. The CTO's suggested assurance is acceptable in substance but NOT as drafted: "may not recognise every way" is too soft against known, deliberate gaps. |
| Toggle confirm | Replace with the text in section 2. Its opening sentence ("will run any non-blocked command without asking") also becomes false and must change. |
| AUP 5.7 / T&C 3a.7 / 10.4 | Rule (a): leave all three, and both mirrors, untouched in this PR. Dated deadline: 2027-01-08, or earlier on the triggers in section 3. AUP-only edit is rejected (section 3.3). |
| Existing acks | Remain valid. No re-ack, no migration (section 4). |
| Art. 30 / privacy docs | No change (section 5). |
| Ship gate | DISCHARGED only on conditions C1-C9 (section 6). |

## 1. Banner `AUTONOMOUS_DISCLOSURE_COPY` - verbatim

```
Soleur runs commands automatically. It blocks a short list of risky commands (curl, wget, sudo, …), but no blocklist is perfect. It also pauses to ask before common forms of a force-push over, or deletion of, your repository's default branch (which can erase its history on GitHub), and before terraform destroy. It does not recognise every way of writing those commands, or every other way to delete a repository or tear down infrastructure, so such a command can still run without asking. Other commands that look safe could still change or delete files in this workspace. You can watch each step in the chat. Only connect repos and accounts you trust.
```

Why this and not the CTO's draft:

- The CTO sentence ends "but it may not recognise every way of writing those commands." The gaps are not hypothetical: the CTO ruling names `gh api -X DELETE .../git/refs/heads/<default>`, `gh repo delete`, `git update-ref`, terragrunt/pulumi destroy, variable-built names and aliases as deliberately uncovered. "May not" invites the reading that the gap is a remote edge case. "Does not recognise every way" is the true statement, and the second clause names the nearest equivalents of the same harm so the owner is not left believing the class is covered.
- The 2026-10 audit removed three overclaims ("backed up in git", "always blocks clearly dangerous commands", "hides your secrets"). Each was a protection claim larger than the code. The new sentence is a protection claim too, so it is bounded three ways: "common forms" (scope), "pauses to ask" (a behaviour, not "blocks", "prevents", "protects" or "safe"), and the explicit residual sentence.
- I keep the harm clause "(which can erase its history on GitHub)" and the closing "can still run without asking". Dropping the consequence would turn a narrowing into a silent change of what the owner understands the residual to be. Consent stays informed because the residual exposure is still named.
- Kept as locked: "no blocklist is perfect" (toggle test `/no blocklist is perfect/i`), the "Other commands that look safe could still change or delete files in this workspace." sentence, "You can watch each step in the chat.", "Only connect repos and accounts you trust."
- Removed: "Until a stricter check ships, it can force-push over your repository's default branch (erasing its history on GitHub) or run infrastructure teardown (terraform destroy) without asking."
- Representation ruling: the assurance is acceptable as a hedged, present-tense, best-effort description of a shipped behaviour, on three conditions: (i) it is true on the live `canUseTool` path in the same build (CTO AC-14 real-factory test); (ii) it is never stronger than the verbs above; (iii) it ships and reverts as one unit with the lane (C1). It is not a warranty: T&C 10.4 still disclaims, in capitals, any warranty that the layer will stop or ask first.
- Test impact: the LOCKED test must assert ABSENCE of `Until a stricter check ships`, `backed up in git`, `always blocks`, `hides your secrets`, and PRESENCE of `no blocklist is perfect`, `does not recognise every way` and `pauses to ask`. It must not assert absence of the tokens `terraform destroy` or `without asking`, which the new text legitimately contains.

## 2. Toggle enable-confirm paragraph (`bash-autonomous-toggle.tsx`) - verbatim

```
The Concierge will run non-blocked commands without asking, except that it pauses to ask before common forms of a force-push over, or deletion of, your repository's default branch (which can erase its history on GitHub), and before terraform destroy. The blocklist (curl, wget, sudo, …) still applies, but no blocklist is perfect. The pauses do not recognise every way of writing those commands, or every other way to delete a repository or tear down infrastructure, so such a command can still run without asking. Other commands that look safe could still change or delete files in this workspace. You can watch each step in the chat. Only turn this on for repos and accounts you trust.
```

Same facts as the banner. The old opening "will run any non-blocked command without asking" is no longer true once the lane ships, so it is rewritten rather than left as an under-claim contradicting the next sentence. In JSX keep `&apos;` for the apostrophe as today.

## 3. AUP 5.7 / T&C 3a.7 / T&C 10.4

### 3.1 What stays accurate

- "does not guarantee that it will stop, or ask you first about ..." stays TRUE. A parser with named residuals is not a guarantee, and fail-toward-ask is not completeness.
- T&C 10.4's capitalised disclaimer ("WE DO NOT WARRANT ... THAT THE COMMAND-SAFETY LAYER WILL STOP, OR ASK YOU BEFORE RUNNING ...") carries NO date qualifier, stays true, and never needs revising for this lane. It also does not conflict with the banner: a hedged "pauses to ask" and a no-warranty clause coexist.
- Only the parenthetical "(and at the date of this version it does not)" in AUP 5.7 and T&C 3a.7 goes stale, and "Soleur may run such a command automatically" is then true only of unrecognised forms.

### 3.2 Ruling: option (a) - do not touch the legal text in this PR

Applying `tc-version-bump-policy.md` literally to the only edit that would fix it (delete the parenthetical in T&C 3a.7):

- Tier 3 is out: it removes an admission, which changes meaning; it is not a typo, whitespace or link fix.
- Tier 1 does not fit on its terms: no new disclaimer text is added and no user right is narrowed. But the policy says "if unsure whether cosmetic or clarifying, treat it as clarifying". The edit is therefore Tier 2 (PATCH, 2.6.1): `TC_VERSION` bump, `TC_DOCUMENT_SHA` repin, mirror sync, `TC_BUMP_METADATA`, CLO sign-off, and `/accept-terms` re-acceptance for every user plus mid-session WebSocket close.
- Classification of the change itself: a correction that narrows the DISCLOSED exposure (loosens an over-disclosure). It is user-favourable, so there is no consumer reason to force fresh consent for it. That is the proportionality argument against Tier 2 cost. I do not use it to re-tier the edit as cosmetic, because the policy forbids doing so.
- Forcing every user through re-acceptance in order to delete a conservative parenthetical, one build after the previous forced re-acceptance (2.6.0, 2026-10-08), is consent-fatigue harm that the avoidable-effect principle in `tc-version.ts` says to avoid.

### 3.3 AUP-only edit: rejected

- Mechanics (answering the question asked): `docs/legal/acceptable-use-policy.md` is pinned in `LEGAL_DOC_SHAS`, not `TC_DOCUMENT_SHA`. An AUP-only edit needs the unconditional SHA refresh and the paired mirror edit (AUP is enrolled in `BODY_EQUIVALENCE_DOCS`, so any one-sided edit reds that check), and it does NOT bump `TC_VERSION` and does NOT force a Terms re-acceptance, because no middleware reads an AUP version. The policy's non-T&C section still requires a tier classification: Tier 2 for register and ledger purposes, with no version constant moved. It is not a "Tier-3-no-bump" change; it is a Tier 2 change whose tier carries no bump because the document class has none.
- Why still rejected: T&C 3a.7 describes itself as "the contractual counterpart ... of Acceptable Use Policy Section 5.7", and AUP 5.7 says the same of the T&C. Editing only one produces an AUP that says "pauses to ask" next to Terms that say "at the date of this version it does not". That is a self-created cross-document contradiction on the exact sentence the 2026-10 audit made consistent (its C3). It also does not remove the stale text from the instrument that actually binds (the Terms prevail, T&C 16.1). It spends the CI cost (SHA, mirror, `--print-vocab`) for negative value.
- Canonical vs mirror difference for T&C (verified by diff): benign and accepted. Differences are frontmatter vs Eleventy hero/wrapper, and relative `.md` links vs `/legal/<doc>/` links. The 3a.7, 10.4 and section 9 text is byte-identical on both surfaces. The AUP differs only by frontmatter and the hero wrapper. The 3.2 conclusion does not depend on this.

### 3.4 Stale-but-true risk and deadline

- Risk assessment: LOW. The stale text understates protection, so it over-warns and cannot mislead to the user's detriment (no UCPD misleading action; UCTD Art. 3 detriment is absent). GDPR Art. 13 is not engaged: the clauses are not processing notices. The residual exposure is (i) UCTD Art. 5 / French consumer-code ambiguity construed against the drafter (works against Jikigai only if Jikigai tried to rely on the over-disclosure, which it does not), and (ii) a public inconsistency between the in-product banner and the Terms. Per the 2026-05-25 learning, the sentence stays true because "at the date of this version" is anchored to the document's own `Last Updated: October 8, 2026` line. That anchor holds only while that line is unchanged and visible.
- Deadline (a trigger, not an intention). Revise the parenthetical in AUP 5.7 and T&C 3a.7 at the EARLIEST of: (1) the next `TC_VERSION` bump for any reason (must be bundled into that same PR); (2) publication of #9603's hosted-coverage claim (public page and Terms must not contradict); (3) the first arms-length workspace owner, or any other re-evaluation trigger in section 6; (4) 2027-01-08, being 90 days after the 2026-10-08 version. A tracking issue for this is mandatory before merge (C6); no open issue exists today.
- Verbatim text for that future bump, to replace the bold sentence's parenthetical and the sentence after it in BOTH AUP 5.7 and T&C 3a.7 (do not apply now):

```
**The command-safety layer does not guarantee that it will stop, or ask you first about, a force-push over (or deletion of) the default branch of the connected repository, or an infrastructure teardown command such as `terraform destroy`, `tofu destroy` or `terraform apply -destroy`.** Soleur's command-safety layer is designed to pause and ask you first about common forms of those commands, but it does not recognise every way of writing them and does not check other ways to delete a repository or a branch or to tear down infrastructure. Soleur may run such a command automatically, and the result may not be recoverable.
```

  In that same PR: refresh the `Last Updated` note, tier-classify (Tier 2, PATCH, so 2.6.1 or later), update `TC_BUMP_METADATA.substantiveChange` (it currently says the layer can run these "without asking"), and bundle any other pending legal text.

## 4. Existing acknowledgements: still valid

Confirmed, with the added-assurance analysis you asked for.

- An ack evidences consent to a RISK. The risk under the new copy is a strict subset of the risk the acked copy disclosed: every force/delete/destroy spelling was exposed before; now only unrecognised spellings are, and the new text still names that residual. Nobody who acked under the 2026-10-08 copy accepted more than they now carry. Q2 of the prior audit (a narrowing needs no re-ack) applies.
- The added assurance is a representation, not only a narrowing. It does not defeat existing acks because no existing ack was induced by it: reliance on a statement made after the ack cannot vitiate earlier consent. For future ackers it is a representation, and it is bounded by section 1 and condition C1.
- Triggers that WOULD require a versioned ack (CTO RULING 2 design, not built now): any copy WIDENING (a newly unasked command class, or a withdrawal of this assurance that is not a pure revert to the 2026-10-08 text). A revert to the 2026-10-08 copy leaves acks valid because it restores the exact text they acked.
- Not covered: the CTO's C2 follow-through (re-run of the supersede UPDATE for acks written on the old build during the migrate-before-swap window) is still an open operator item. Acks written to the PRE-#9792 copy are not valid under this ruling or the last one; this PR neither fixes nor worsens that.
- Approving a destroy card is not an ack, not consent to the autonomous disclosure, and grants nothing durable (CTO design). The card's text must say what was matched and nothing more (C4).

## 5. GDPR / compliance (Art. 30, privacy docs)

NONE required.

- The telemetry (`ruleId`, `family`, `autonomous`, `isOwner`, `acked`, `authoritative`, `repo` owner/name; Sentry without `repo`) is security and operational logging inside the existing Sentry (PA register entry for error monitoring) and Better Stack WARN-and-above stream (Privacy Policy 5.14, 90-day retention). No new purpose, data category, recipient, sub-processor, retention period or transfer. Lawful basis is unchanged: Art. 6(1)(f) with Art. 32 security of processing.
- `repo` as `owner/name` is already emitted by the sibling `autonomous-disclosure-hold` log lines (`repo: ${ctx.repoOwner}/${ctx.repoName}`), so this adds an event, not a field class. A user-owned repo owner can be a natural person's handle; that is personal data already in that stream.
- Conditions that keep this true (C5): the line goes through the shared pino logger so `userId` is hashed (`userIdHash`); no raw `userId`, email, branch or refspec name and NO command text or redacted preview in pino, Sentry tags, `extra`, or breadcrumbs. The redacted preview exists only in the card and the existing offline-notify path (unchanged, same exposure as today's review gates; do not widen it). Reminder of #8532: an error path that echoes a command argument into Sentry is the failure class here.
- Privacy Policy, GDPR Policy, DPD, article-30-register: no edit. The three-document sharp edge does not trigger because no processing activity is added.

## 6. Conditions for the ship-time CLO attestation (C1-C9) and audit file

Audit file to create in the PR: `knowledge-base/legal/audits/2026-10-counsel-review-9776-ask-gate.md` (type `counsel-review`, issue 9776, `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`, `supersedes_in_part` frontmatter pointing at `2026-10-counsel-review-9776.md` for the "Until a stricter check ships" row only, and a `> **Superseded 2026-10-10 (#9776 ask-gate): ...**` marker under that sentence in the 2026-10 audit's drift table, conditioned on the merge of this PR, not past tense). Per-artifact verdicts are written in the conditional ("fires on the merge of PR #N").

- C1. One unit. Banner copy, toggle copy, lane, tests ship in one build and one commit/revert unit; no feature flag. A revert restores the 2026-10-08 copy together with removing the lane. Copy is applied byte-for-byte from sections 1 and 2.
- C2. The statement is true on the live path: CTO AC-14 (real `canUseTool` factory, `autoAllowBashIfSandboxed` present) and AC-1/AC-4 (un-acked owner is gated, a prior `git push` or `terraform` grant does not launder). The attestation re-reads the lane by function/constant name, never by line number.
- C3. Vocabulary guard: the banner, toggle and card never contain "blocks", "prevents", "protects", "safe to approve", "guaranteed" or "always" in reference to the lane. A test asserts it.
- C4. Card text: states the matched family and "paused for your approval"; does not claim other commands are safe; options exactly Approve/Reject.
- C5. Telemetry hygiene per section 5, asserted by a test that greps emitted payloads for the command string.
- C6. Tracking issue filed before merge for the section 3.4 parenthetical revision (label legal, milestone with the 2027-01-08 date), linked in the PR body and in the audit.
- C7. Legal artifacts untouched and asserted: `docs/legal/**`, `plugins/soleur/docs/pages/legal/**`, `TC_VERSION`, `TC_DOCUMENT_SHA`, `LEGAL_DOC_SHAS` have an empty diff. The PR body states "no TC_VERSION bump; no re-acceptance".
- C8. ADR and C4 text (CTO Phase 5) must not say the hosted gate is complete; they carry the residual list. The CTO's ADR addendum (hook stays off in hosted) is the source.
- C9. Post-merge, one-line recorded observation (dev hosted, throwaway repo): card appears for `git push --force origin <default>` and `terraform destroy`, and the telemetry arrives. Without it the banner assurance stays ship-blocked in prod verification, and the owner is told so.

Re-evaluation triggers for the audit frontmatter: first arms-length Workspace Owner; first EEA-out operator; first regulated-industry tenant; any change widening or narrowing the lane's recognised set (including adding `gh repo delete`, `gh api` ref deletion, terragrunt/pulumi); a measured miss in the near-miss telemetry on a destructive spelling; any new unblocked destructive command family; any change to `BLOCKED_BASH_PATTERNS` or the read-only allowlist; any enablement of the plugin hook in hosted (D8 change); the next `TC_VERSION` bump; publication of #9603; 2027-01-08; any conversion of autonomous execution into a third-party-effecting send (Art. 22(3)).

Disposition if C1-C9 hold: DISCHARGED. If C1 or C2 fails: BLOCKED (the assurance would be an overclaim).

## 7. #9603 (security/control page), one line

It MAY say hosted autonomous sessions pause to ask before common forms of a force-push over or deletion of the default branch and before `terraform destroy`/`tofu destroy` (once C9 is observed and the Terms parenthetical deadline in 3.4 is met), and it MUST NOT claim that destructive commands are blocked, prevented, protected or fully covered, that other destructive commands (`gh repo delete`, `gh api` ref deletion, `git update-ref`, terragrunt/pulumi, recursive `rm`, force-push to non-default branches) are checked, that the plugin hook runs in hosted sessions, or that approval grants any lasting permission.

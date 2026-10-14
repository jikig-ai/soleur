---
title: "Counsel review audit — #7947 / PR #7975 (Art. 30 PA-8 §(g) and PA-31 §(g), amended for the browser-snapshot credential guard)"
type: counsel-review
date: 2026-09-09
issue: 7947
pr: 7975
status: SIGNED-OFF (CLO-agent-reviewed, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-09
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED — no conditions. Two artifacts in scope (article-30-register.md PA-8 §(g) + PA-31 §(g); compliance-posture.md). Every implementation-detail claim in both brackets was verified against the shipped body, not against the plan or the PR description. The recorded prior defect — the register asserting per-shell-segment judgment while the splitter did not handle a bare `&` — is FIXED and FIXTURED: the splitter at `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` handles `&&`, `||`, `;` and bare `&` (protecting `>&` first), and `.claude/hooks/browser-snapshot-credential-guard.test.sh` carries a deny row per separator. The residual is stated at the correct strength: P7 achieved on the `agent-browser` Bash path ONLY, NOT achieved on the Playwright-MCP runtime path, tracked at #7980 (verified OPEN, `priority/p1-high`). No Art. 33 and no Art. 34 duty arises."
blocking_findings: []
required_before_merge_DISCHARGED: []
optional_precision_notes:
  - "O1 (optional, non-blocking) — the `@playwright/mcp` `--secrets` README characterisation (\"a convenience and not a security feature\") carries no version or date anchor, and the bracket's pinning sentence names only `agent-browser` 0.22.3 and `playwright-core` 1.58.2, neither of which is that package (`@playwright/mcp` is pinned at 0.0.75 in `apps/web-platform/package.json`). Non-blocking because the sentence DISCLAIMS a third-party control rather than claiming a Jikigai one: any error runs toward understating protection, which is the safe direction under Art. 5(2)."
  - "O2 (optional, non-blocking) — PA-8 §(g) reads the deny is registered in the shipped plugin manifest \"rather than in repo-local `.claude/`\". The SCRIPT indeed ships only at `plugins/soleur/hooks/`; the same shipped script is ALSO registered repo-locally at `.claude/settings.json` for dogfooding. The load-bearing half (it reaches a customer) is true and the additional registration adds reach rather than removing it, so the cell is defensible as written."
attests:
  - knowledge-base/legal/article-30-register.md (PA-8 §(g) and PA-31 §(g) appended brackets ONLY)
  - knowledge-base/legal/compliance-posture.md (the #7947 Completed-Compliance-Work row and the `last_updated` bump ONLY)
art_33_triggered: false
art_34_triggered: false
art_33_limb_applied: "Art. 33(1) is not engaged. Art. 33 is conditioned on a personal data breach within Art. 4(12) — a breach of security leading to accidental or unlawful destruction, loss, alteration, unauthorised disclosure of, or unauthorised access to personal data. This PR introduces NO new processing (no new purpose, data category, recipient, sub-processor or retention) and no such event occurred in this work: it is preventive hardening of an Art. 32(1)(b) confidentiality control, recorded under Art. 30(1)(g) with Art. 32(1)(d) as the accountability hook. Art. 34 is not reached, being conditional on an Art. 33 breach plus high risk. No clock started; nothing fell due. The historical 2026-05-19 event the bracket cites as corroboration was adjudicated on its own record (no third-party recipient; token minted 10:42:20Z, revoked 10:45:03Z; no Art. 33 / Art. 34 notification warranted) and this amendment does NOT reopen it — it cites it as evidence that the mechanism is a realized class, not as a new finding. Consistent with the house position at `2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md`: a credential exposure is not automatically an Art. 4(12) personal-data breach, and no breach-register row is owed where `art_33_triggered` is false."
carve_outs:
  - "NOT ATTESTED — the engineering design. The three-control split, the deny-not-rewrite disposition (ADR-162), the name-predicate ceiling and the `SNAPSHOT_RULE_DIRS` population are settled decisions at ADR-213, reviewed here only for whether the register describes them truthfully."
  - "NOT ATTESTED — the redactor's coverage as a security control. It is attested as recorded: defence-in-depth on one enumerated sink with its bypasses stated, NOT a control that makes snapshotting a credential page safe."
  - "NOT ATTESTED — the published corpus. No `docs/legal/` or `plugins/soleur/docs/pages/legal/` byte changed in this PR (verified: zero diff on both trees), so the mirror-drift, scope-block, SHA-pin and heading-parity gates are not engaged. The under-inclusive AUP §2 scope found while verifying (it names only `agent-browser`) is filed at #7981 and is NOT fixed here."
  - "NOT ATTESTED — #7980's remediation. The Playwright-MCP `.mcp.json` stdio proxy is deferred; this review attests only that the gap is recorded at the correct strength."
  - "NOT PROMOTED — external counsel review. This is the v1 internal sign-off under the Soleur-as-tenant-zero posture."
re_evaluation_triggers:
  - "Any of PA-31 §(g)'s four pinned triggers fires (t1 a member granted `mcp__playwright__browser_snapshot`; t2 a member's `CRON_BASH_ALLOWLISTS` entry admits `agent-browser`; t3 `cron-ux-audit`'s navigate origin pin widened beyond `NEXT_PUBLIC_APP_URL`; t4 a member granted a browser tool under a credential other than the bot account) — on any of these the PA-8 residual becomes live on PA-31 and that cell must be re-APPENDED, never edited."
  - "#7980 lands, or is closed without landing — P7's per-surface statement in PA-8 §(g) changes either way."
  - "`agent-browser` moves off 0.22.3 or the Playwright MCP surface changes — both measured facts (screenshot unsafe for a readonly `type=text` credential panel; no surface serializes `type=`) are dated observations of pinned versions and bind on no other version."
  - "First arms-length (non-Jikigai-affiliate) data subject affected by a browser-automation capture — v1 attestation rests on the affected subject being the operator on their own machine."
  - "Any data subject outside the EEA/UK, or in a regulated industry."
related:
  - knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md
  - knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md
  - plugins/soleur/hooks/browser-snapshot-credential-guard.sh
  - plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py
  - scripts/lint-credential-path-literals.py
  - knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md
  - knowledge-base/legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md
---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**

# Counsel review — #7947 / PR #7975

## Scope

Four insertions, three deletions, two files. The gate fired because the diff
touches `knowledge-base/legal/` at a `single-user incident` brand-survival
threshold. Diff size is not the measure of whether a review record is warranted:
this change AMENDS the Article 30 register in two cells and names a live,
unclosed residual on an open `priority/p1-high` issue. Both facts must be
traceable by a later reader who did not see this PR.

## §1 — Verification method

Every implementation-detail claim in both brackets was checked against the
shipped body. The known drift class here is legal prose hallucinated against the
code (PR #4353 / #4558), and this PR has already produced one instance of it —
recorded below at §2 as the prior defect. Nothing was accepted on the strength of
the PR description.

## §2 — The prior defect, re-verified rather than assumed fixed

An earlier draft of PA-8 §(g) asserted the interceptor judged the command **per
shell segment**. That was FALSE when written: the splitter handled `&&`, `||`
and `;` but not a bare `&`, so a command of the form
`… snapshot | redactor & … snapshot` stayed one segment, the segment contained
the redactor anchor, and the second unrouted invocation rode through.

Re-verified on this branch against the current script, not against the
description of the fix:

- The splitter protects `>&` (so `2>&1` survives), then splits on `&&`, `||`,
  `;` **and bare `&`**, restoring the protected `>&` afterwards. The comment at
  that site names the bypass and names the register as the artifact whose claim
  was false — the correct disclosure posture.
- The suite carries a deny row per separator: `&&` (M3), bare `&`, `;` and `||`.
  The `;` and `||` rows were added specifically because two of four separators
  had no coverage, which is what made truncating the splitter a survivable
  mutation.
- The allow-predicate is not substring presence: it requires the redactor
  anchor **downstream of a pipe**, and separately denies `tee` and a file
  redirect of the snapshot, each of which satisfies a naive substring check
  while writing the unredacted tree to the exact sink the deny text names.

The register's current claim — "judged per shell segment so a chained command
with one piped and one unpiped invocation is caught" — is now TRUE of the
shipped script.

## §3 — Does the register describe the measure that exists, or a stronger one?

Claim-by-claim, all confirmed against the body:

| Register claim | Verified against |
|---|---|
| Redactor rewrites credential-shaped node values to `<redacted>` and suppresses the duplicated nested `StaticText` child | `redact-a11y-snapshot.py` — `REDACTED`, `VALUE_CARRYING_CHILD_ROLES = {"StaticText"}`, `TEXT_INPUT_ROLES`, `CREDENTIAL_NAME_RE` |
| Its module header enumerates its own bypasses (localised/renamed name; credential outside a text-input role; value split across segmented inputs; the whole Playwright-MCP path) | module docstring §"STATED BYPASSES" — all four present, plus an unnamed non-text-input node |
| Deny registered in the **shipped** plugin manifest | `plugins/soleur/hooks/hooks.json` — new `PreToolUse` / `Bash` entry on `${CLAUDE_PLUGIN_ROOT}` (see O2) |
| Deny not rewrite, per ADR-162 | hook header; emits `permissionDecision: "deny"`, never `updatedInput` |
| Second rule family in `lint-credential-path-literals.py`, population `plugins/soleur/{skills,agents}/` only, excluding `knowledge-base/**` | `SNAPSHOT_RULE_DIRS = ("plugins/soleur/skills/", "plugins/soleur/agents/")`; `scan_snapshot_rule` returns early off-population; `SCAN_DIRS` (the older family) remains the wider pair |
| Backs `credential-path-guard` and is therefore blocking from its first run | `scripts/required-checks.txt` line 206 — the context is already required from #6882, so the new family inherits blocking status on arrival |
| Screenshot is safe for `type=password` and renders a readonly `type=text` panel in clear | `phase-0-measurement.md` measurement table; reproduced in the hook's own deny text as a MEASURED CAVEAT |
| No predicate can be structural — neither surface serializes `type=` | `phase-0-measurement.md`; restated in the redactor's "WHY THIS IS NAME-BASED AND NOT STRUCTURAL" |
| The class already fired on this Activity's mint path | `2026-05-19-sentry-token-scope-probe-divergence.md` — `mcp__playwright__browser_snapshot` after the `Create Token` click returned a `textbox "Generated token"` whose value rendered verbatim |

No claim was found describing a stronger measure than the one that ships. The
brackets consistently characterise the redactor as defence-in-depth on one sink
rather than as making a credential page safe to snapshot, which matches both the
module header and the deny text.

PA-31 §(g)'s three arithmetic claims reproduce exactly:
`grep -ci 'agent-browser' _cron-claude-eval-substrate.ts` → **0**;
`grep -c 'browser_snapshot'` on the same file → **0**; and `cron-ux-audit`'s five
granted Playwright tools are literally `browser_navigate`,
`browser_take_screenshot`, `browser_resize`, `browser_close`, `browser_wait_for`.
The `auth: bot` authenticated-session claim is carried by
`plugins/soleur/skills/ux-audit/SKILL.md` §3 step 1 (`bot-signin.ts`, storage
state reused across routes).

## §4 — Is the residual stated honestly?

Yes, and at the correct strength on both cells.

PA-8 §(g) states P7 is achieved on the `agent-browser` Bash path **only** and is
**NOT** achieved on the Playwright-MCP runtime path; it names why
`@playwright/mcp --secrets` does not close the gap (it masks values named in
advance and cannot reach a value the agent never supplied — which is the whole
mechanism); and it names the deferral at #7980, verified OPEN and
`priority/p1-high`. The cell claims no coverage the implementation does not have.

PA-31 §(g) does the harder thing: it records a **non-reach** so a later reader
cannot infer coverage, and it credits the containment to pre-existing measure (1)
rather than to anything shipped here — "the `PreToolUse` interceptor shipped at
#7947 gates a call no member of this fleet may make, and this cell claims no new
measure from it." It then records the one live residual it does have
(`cron-ux-audit` holding `browser_take_screenshot` over `auth: bot` routes inside
an authenticated session, against measure (8)'s standing statement that no PII
scrub exists on Anthropic-bound content on this path), explicitly as a residual
and not a control, with four mechanically checkable re-evaluation triggers.

Both amendments are **purely additive**: the register diff carries zero deletions
(`--word-diff` shows no removal tokens), honouring the cell's own
"re-appended, never edited" contract. `scripts/lint-legal-registers.sh` passes
(11 assertions, 0 failed).

## §5 — Art. 33 / Art. 34

Confirmed, not contradicted. See `art_33_limb_applied` in the frontmatter for the
limb reasoning. In short: Art. 33(1) is conditioned on an Art. 4(12) personal
data breach; this PR introduces no new processing and no such event occurred in
this work, so nothing is notifiable and no clock started. Art. 34 is not reached.
The operative articles are Art. 32(1)(b) (confidentiality of the credential that
opens a path to this Activity's own record set, including the Sentry
`message` / breadcrumb / tag / `user.*` values the ingest-time key-name scrub does
not remove) and Art. 32(1)(d) (a control that cannot block is not an effective
measure — the #6882 precedent), recorded under Art. 30(1)(g) with Art. 5(2)
accountability for the residual.

The bracket's elevation of the credential's characterisation — from an
infrastructure secret to a control over this Activity's record set — does not
reopen the 2026-05-19 disposition. That event was operator-local, the token lived
163 seconds, no third-party recipient occurred, and the record already states no
Art. 33 / Art. 34 notification was warranted.

## §6 — Scope discipline

Verified: neither bracket, nor the compliance-posture row, contains any
incident-specific credential detail — no value, no length, no fragment. The
records cite the mechanism and the node shape only, which is what #7947's own
scope note restricts them to.

## §7 — Disposition

**DISCHARGED. No conditions.** Two optional precision notes (O1, O2) are recorded
in the frontmatter; neither blocks merge and neither corrects a false statement
about the implementation.

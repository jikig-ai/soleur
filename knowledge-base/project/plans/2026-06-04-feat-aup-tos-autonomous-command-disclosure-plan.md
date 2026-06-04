---
title: "AUP + ToS disclosure of autonomous command execution + residual-risk admission"
type: feat
issue: 4952
ref: 4949
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
domain: legal (CLO)
created: 2026-06-04
deepened: 2026-06-04
---

# 📚 feat: AUP + ToS disclosure of autonomous command execution + residual-risk admission

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Files to Edit, Acceptance Criteria, Risks, Sharp Edges, Research Insights (new)

### Key Improvements

1. **Seed-script TC_VERSION parity is a load-bearing gap (NEW Files-to-Edit).**
   `check-tc-document-sha.sh` Step 2.5 (lines 276-318) asserts
   `apps/web-platform/scripts/seed-dev-users.sh:94` AND
   `apps/web-platform/scripts/seed-qa-user.sh:18` hardcode the **same** `TC_VERSION`
   as `lib/legal/tc-version.ts`. Both currently pin `"2.2.1"`. Bumping canonical to
   `2.3.0` WITHOUT updating both seed scripts **fails the guard** (`TC_VERSION drift`).
   Added both seed scripts to Files to Edit + a new AC + a Sharp Edge.
2. **Corrected the local-vs-CI guard-pass mechanism.** The plan v1 said the guard
   "accepts the SHA change because TC_VERSION was bumped" — that is the **CI-only**
   bypass (`check-tc-document-sha.sh:240-248`, requires `GITHUB_BASE_REF` set + an
   `origin/$BASE...HEAD` diff showing a `TC_VERSION` line change). **Locally**
   (`test-all.sh` strips `GITHUB_BASE_REF`), the guard passes via the **matched-SHA
   short-circuit** (`:236-238`, `if canonical_sha == literal_sha then continue`) —
   because Phase 4 repins the SHA to the final bytes, the bypass is never consulted
   locally. Both paths are now stated precisely.
3. **Precedent diff added (Phase 4.4).** The 3-way-lockstep legal-doc edit has strong
   sibling precedent (#4508, #4625/#4637, #4916) — recorded in Research Insights.

### New Considerations Discovered

- The `discoverability_test`/observability skip is correct, but the **enforcement
  observability** is the CI guard itself (`check-tc-document-sha.sh` is the load-bearing
  drift detector — it fails loudly on SHA, body-equivalence, AND seed-script drift).
- The sensitive-path regex (preflight Check 6 / deepen 4.6) DOES match
  `apps/web-platform/lib/legal/` — but the `single-user incident` threshold (not `none`)
  means no scope-out bullet is required; the gate passes.

Closes #4952. Ref #4949.

## Overview

PR #4949 shipped Concierge **autonomous command execution default-ON** on the Web
Platform: the agent runs non-blocked shell commands automatically, gated only by a
**first-run owner consent soft-gate** (a one-time disclosure banner whose ack is
persisted per workspace). Before recruiting the first arms-length **external beta**
user (product Phase 4 — currently 0 external users), the **Acceptable Use Policy** and
**Terms & Conditions** must disclose this autonomous-execution surface and admit its
**residual risk** to a high (CLO) bar:

1. **The blocklist is NOT exhaustive** — `BLOCKED_BASH_PATTERNS` rejects a fixed set of
   clearly-dangerous verbs (`curl`, `wget`, `ncat`, `nc`, `eval`, `sudo`,
   interpreter `-e`/`-c`, `base64 -d`, `/dev/tcp`), and `SAFE_BASH_PATTERNS` auto-approves
   a narrow read-only allowlist — but **no blocklist is perfect**.
2. **A non-blocked-but-harmful command can auto-run** — a command that *looks* safe (and
   is not on the blocklist) can still change or delete files in the connected workspace
   without a per-instance approval, once the owner has acknowledged the soft-gate (or set
   the workspace to autonomous/trusted).
3. **Mitigations** — work is **git-backed** (the connected repo is the recovery surface),
   and **every command is visible in chat** (the operator can watch each command run).
   The disclosure must present these honestly as *mitigations of a residual risk*, not as
   a guarantee of safety.

This is **CLO-domain legal-doc work**, not an engineering change to PR #4949. The
disclosure language already exists verbatim in the product UI as the **LOCKED COPY** in
`apps/web-platform/components/chat/autonomous-disclosure-banner.tsx`
(`AUTONOMOUS_DISCLOSURE_COPY`); the legal docs must mirror its three claims and cross-link
to it, so the in-product disclosure and the contractual disclosure are mutually
consistent (a divergence between the two is itself a brand/compliance liability).

**This is a Tier-1 MATERIAL T&C change** (new disclaimer-of-warranty / residual-risk text
not previously present — see Research Reconciliation): it **requires a `TC_VERSION` bump**
(`2.2.1` → `2.3.0`), an `article-30-register.md` review, and **CLO sign-off**. The change
forces re-acceptance of the Terms for existing users via the `/accept-terms` middleware —
which is *correct* here: the autonomous-execution residual-risk admission is exactly the
kind of disclosure a user should be re-prompted to accept.

The change is **docs + version-guard literals only** — no schema, no migration, no route
handler, no UI component. The only `apps/web-platform/**` files touched are the two
hand-edited SHA/version literal files (`legal-doc-shas.ts` for the AUP, `tc-version.ts`
for the T&C) and **no** TypeScript logic.

## Research Reconciliation — Spec vs. Codebase

| Premise (issue body / assumption) | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| "Update SHA guards in `legal-doc-shas.ts`" for **both** docs | The AUP SHA lives in `LEGAL_DOC_SHAS["acceptable-use-policy"]` in `lib/legal/legal-doc-shas.ts`. The **T&C SHA does NOT** — it lives separately in `TC_DOCUMENT_SHA` in `lib/legal/tc-version.ts`, and `legal-doc-shas.ts` has **no** `terms-and-conditions` key. | Plan edits **two different literal files**: `legal-doc-shas.ts` (AUP) and `tc-version.ts` (T&C SHA + `TC_VERSION` + `TC_BUMP_METADATA`). |
| Issue calls the gate a "denylist" | Two distinct mechanisms: `BLOCKED_BASH_PATTERNS` (denylist, `permission-callback.ts:84`) AND `SAFE_BASH_PATTERNS` (auto-approve **allowlist**, `safe-bash.ts:90`). Autonomous mode bypasses the review-gate for non-blocked, non-allowlisted commands; `isBashCommandBlocked` stays authoritative even under autonomy. | Disclosure prose describes the actual two-layer model ("clearly-dangerous commands are always blocked; a narrow read-only set is auto-approved; other commands run automatically under autonomy") — does not parrot "denylist" as if it were a complete safety boundary. |
| Disclosure is new copy to author | The residual-risk admission **already exists verbatim** as `AUTONOMOUS_DISCLOSURE_COPY` (LOCKED COPY) in `autonomous-disclosure-banner.tsx:21-27`, shipped by PR #4949. | Legal-doc prose is drafted to be **substantively consistent** with the LOCKED COPY and cross-references it; the plan does NOT edit the LOCKED COPY (it is plan-locked in #4949) and does NOT introduce a second source of truth that could drift. |
| "Keep cross-document consistency tests green" | `legal-doc-consistency.test.ts` asserts: (a) heading-sequence parity between `docs/legal/<doc>.md` and the Eleventy mirror `plugins/soleur/docs/pages/legal/<doc>.md`; (b) identical `**Last Updated:**` date in mirror **body** AND mirror **hero `<p>`**; (c) sentinel-string parity for specific load-bearing fragments. `legal-doc-shas-guard.test.ts` exercises `check-tc-document-sha.sh` (SHA-pin + T&C body-equivalence). | Every canonical edit is mirrored into `plugins/soleur/docs/pages/legal/<doc>.md` **in the same PR** (3-way lockstep), including both date sites. New section headings land identically in both files. |
| T&C change "is a CLO task, not a blocker for internal merge" | Confirmed: tenant-zero/dogfood is unaffected; external beta is the gating event. The middleware re-acceptance on a `TC_VERSION` bump is the intended behavior. | Plan bumps `TC_VERSION` (forces re-acceptance) and documents the consent-fatigue trade-off as acceptable for a residual-risk admission. |

**Premise Validation:** Issue #4952 is `OPEN` with no closing PR. PR #4949 is `MERGED`
(2026-06-04T21:09:35Z). Both target files exist; both current SHAs (`d979595e…` AUP,
`e87c8b45…` T&C) match their pinned literals exactly, so the edits will deterministically
trip both guards and the refresh procedure is known. `BLOCKED_BASH_PATTERNS`,
`SAFE_BASH_PATTERNS`, the soft-gate hold/ack flow, and `AUTONOMOUS_DISCLOSURE_COPY` were
all read in source. Article 30 register's highest existing PA is **26** → next free is
**27** (no collision). No external premises remain unvalidated.

## User-Brand Impact

**If this lands broken, the user experiences:** an external beta user reads an AUP/ToS
that is silent on (or contradicts) the in-product autonomous-execution disclosure banner,
then a non-blocked command auto-deletes/auto-modifies files in their connected repo —
with no contractual disclosure that this was a disclosed-and-accepted residual risk.
A broken edit can also surface as a **failed `/accept-terms` flow** (TC_VERSION/SHA
mismatch crashing the gate) that locks every existing user out of the Web Platform.

**If this leaks, the user's data / workflow / money is exposed via:** N/A for new exposure
— this PR creates no new processing activity and collects no new personal data; it is a
**disclosure** of an existing risk created by #4949. The residual-risk vector being
*disclosed* is: a non-blocked-but-harmful auto-run command mutating the connected
workspace (mitigated by git-backed recovery + chat visibility).

**Brand-survival threshold:** **single-user incident.** A single external beta user whose
repo is damaged by an undisclosed autonomous command — when the product positions itself
as a trustworthy autonomous agent — is a brand-survival event. The disclosure is the
contractual half of the mitigation the product UI already ships.

> CPO sign-off required at plan time before `/work` begins. CLO sign-off is required at
> ship time per the Tier-1 bump-policy (legal-doc material change). Confirm CPO has
> reviewed this plan (or invoke the CPO domain leader) before implementation.

## Files to Edit

**Canonical legal docs (the disclosure):**

- `docs/legal/acceptable-use-policy.md`
  - Add a new subsection **§5.7 "Autonomous command execution (Web Platform)"** under
    §5 (User Responsibilities), immediately after §5.6, disclosing the autonomous-execution
    surface, the residual-risk admission (blocklist not exhaustive; non-blocked-but-harmful
    command can auto-run), the git-backed + visible-in-chat mitigations, and the user's
    responsibility to connect only repos/accounts they trust. Cross-reference T&C §3a.7
    (new) and the in-product `AUTONOMOUS_DISCLOSURE_COPY` banner.
  - Append a clause to **§2 (Scope)** noting autonomous command execution is in scope (the
    existing bullet "Execution of shell commands … through agents" predates autonomy and
    does not mention auto-run).
  - Update the top **`**Last Updated:**`** prose line (prepend a new dated entry per the
    existing pattern: `June 4, 2026 -- added Section 5.7 "Autonomous command execution …" (PR #4949 / #4952); …`).
  - Update YAML frontmatter `last-updated: 2026-06-04`.
- `docs/legal/terms-and-conditions.md`
  - Add a new subsection **§3a.7 "Autonomous command execution (Web Platform)"** under §3a
    (Agent Command Authority), disclosing the same surface from the contractual angle:
    the consent model (first-run owner soft-gate ack persisted per workspace; the
    autonomous/trusted toggle), the explicit **residual-risk admission**, and that the
    user bears responsibility for non-blocked commands that auto-run. Cross-reference
    AUP §5.7 and T&C §10 (Disclaimer of Warranties).
  - Add a clause to **§10.2** (No Guarantee of Availability or Accuracy) OR a new **§10.4
    "Autonomous command execution — residual risk"** under §10 admitting the blocklist is
    not exhaustive and Soleur does not warrant that autonomous execution cannot run a
    harmful command (mitigations named: git-backed recovery, chat visibility, user repo/
    account trust). **Decision (deepen-plan to finalize):** a dedicated §10.4 is preferred
    over editing §10.2 — it keeps the residual-risk admission discoverable by section
    number and avoids re-flowing the existing AS-IS warranty disclaimer. **This §10.4 is
    the "new disclaimer-of-warranty text not previously present" that makes the change
    Tier-1 material** (see bump-policy §Tier 1).
  - Add a clause to **§9 (Acceptable Use)** mirroring the AUP cross-reference (the existing
    §9 bullet already cross-refs §3a for the human-in-the-loop boundary; add a sibling
    bullet for autonomous command execution → §3a.7 / AUP §5.7).
  - Update the top **`**Last Updated:**`** prose line and YAML frontmatter date.

**Eleventy mirrors (3-way lockstep — same PR, body-equivalent):**

- `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`
  - Mirror the new §5.7 + §2 clause **identically** (heading text + body) so
    `legal-doc-consistency.test.ts` heading-sequence parity passes.
  - Update **both** date sites: the hero `<p>…Last Updated <DATE></p>` AND the body
    `**Last Updated:** <DATE>` line — both must equal the canonical date (the body prose
    "previously …" history line may be trimmed in the mirror per the existing pattern, but
    the *date token* must match).
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
  - Mirror §3a.7 + §10.4 + §9 clause identically (heading sequence + body), so both the
    consistency test AND `check-tc-document-sha.sh`'s **T&C body-equivalence** step pass
    (the body-SHA comparison normalizes the mirror's collapse/normalize_plugin pipeline
    against the canonical — a sentinel paragraph in one but not the other fails it).
  - Update both date sites.

**Version-guard / SHA literals (hand-edited — same PR):**

- `apps/web-platform/lib/legal/legal-doc-shas.ts`
  - Refresh `LEGAL_DOC_SHAS["acceptable-use-policy"]` ←
    `sha256sum docs/legal/acceptable-use-policy.md` (computed AFTER the canonical AUP edit
    is final). (No `terms-and-conditions` key exists here — do NOT add one.)
- `apps/web-platform/lib/legal/tc-version.ts`
  - Refresh `TC_DOCUMENT_SHA` ← `sha256sum docs/legal/terms-and-conditions.md` (computed
    AFTER the canonical T&C edit is final).
  - **Bump `TC_VERSION`** `"2.2.1"` → `"2.3.0"` (Tier-1 material; minor bump because a new
    section/processing-disclosure is added, not a breaking restructure — confirm against
    `knowledge-base/legal/tc-version-bump-policy.md` §semver-for-legal-docs at /work).
  - Update `TC_BUMP_METADATA`: `lastUpdated: "June 4, 2026"`,
    `substantiveChange: "§Autonomous command execution residual-risk disclosure"`
    (matches the new top-level/subsection introduced by the bump; consumed by the
    `/accept-terms` re-acceptance banner + `accept-terms-copy-regression.test.tsx`).

**Seed-script TC_VERSION parity (REQUIRED with the bump — Step 2.5 guard):**

- `apps/web-platform/scripts/seed-dev-users.sh`
  - Update the hardcoded `TC_VERSION="2.2.1"` literal (line 94) → `"2.3.0"`.
- `apps/web-platform/scripts/seed-qa-user.sh`
  - Update the hardcoded `TC_VERSION="2.2.1"` literal (line 18) → `"2.3.0"`.
  - **Why required:** `check-tc-document-sha.sh` Step 2.5 (`:276-318`) asserts both seed
    scripts hardcode the **same** `TC_VERSION` as `tc-version.ts`. Drift fails the guard
    (`<seed>: TC_VERSION drift`). Without this, QA/dev re-seeded users hit the
    `/accept-terms` redirect loop on next sign-in (silent failure surfacing days later).

**Compliance / register artifacts (same PR):**

- `knowledge-base/legal/article-30-register.md`
  - **Review** whether the disclosure introduces or alters an Art. 30(1) limb. The
    autonomous-execution runtime processing is **already** registered (PA 21 "Autonomous-
    acknowledgment runtime", PA 22 "Autonomous AI leader-prompt runtime"). This PR is a
    *disclosure* of existing processing, not a new processing activity → **most likely no
    new PA**. Decision rule: if `/work`'s gdpr-gate (Phase 2.7) determines the disclosure
    surfaces a previously-unregistered processing limb, add **PA 27** (next free number;
    do NOT reuse ≤26). Otherwise record "no Art. 30 amendment — disclosure of existing
    PA 21/22 runtime" in the PR body. **Default: no new PA; confirm at gdpr-gate.**
- `knowledge-base/legal/compliance-posture.md`
  - Add a **Completed Compliance Work** entry (HTML comment + line) recording the
    AUP §5.7 / T&C §3a.7 + §10.4 autonomous-execution disclosure for external-beta
    readiness, `TC_VERSION 2.2.1 → 2.3.0`, and the Art. 30 disposition. (Touched anyway by
    the legal-doc cross-document discipline; not necessarily gate-forced for this file set
    — confirm the cross-document gate's enumerated-surface list at /work.)

## Files to Create

None. (All artifacts already exist; this is an edit-only change.)

## Implementation Phases

> **Phase order is load-bearing:** canonical docs first → mirrors → recompute SHAs LAST
> (SHA literals depend on the final canonical bytes). Bumping `TC_VERSION` is independent
> of the SHA and can land with the literal edit, but the SHA MUST be the final byte state.

### Phase 0 — Preconditions (verify, do not code)

1. `cd` into the worktree (bare-root git commands exit 128 — see learning
   `2026-05-29-legal-doc-triple-lockstep…` Session Errors).
2. Re-confirm current SHAs still match pinned literals
   (`sha256sum docs/legal/{acceptable-use-policy,terms-and-conditions}.md` vs
   `legal-doc-shas.ts` / `tc-version.ts`) — if drift exists, an unrelated edit landed and
   the plan's "edit trips the guard deterministically" assumption must be re-checked.
3. Read `knowledge-base/legal/tc-version-bump-policy.md` §Tier 1 + §semver-for-legal-docs
   to lock the `2.2.1 → 2.3.0` decision.
4. Read `AUTONOMOUS_DISCLOSURE_COPY` (`autonomous-disclosure-banner.tsx:21-27`) and
   `BLOCKED_BASH_PATTERNS` (`permission-callback.ts:84`) so the drafted prose is
   substantively consistent with the shipped denylist verbs and banner claims.

### Phase 1 — Draft the AUP disclosure (canonical)

1. Author **AUP §5.7** "Autonomous command execution (Web Platform)" + the §2 scope
   clause, to the high CLO bar (see Drafting Bar below).
2. Update the AUP `**Last Updated:**` prose line + YAML `last-updated`.

### Phase 2 — Draft the T&C disclosure (canonical)

1. Author **T&C §3a.7** + **§10.4** + the §9 cross-ref bullet.
2. Update the T&C `**Last Updated:**` prose line + YAML date.

### Phase 3 — Mirror both docs (Eleventy)

1. Apply §5.7 + §2 clause to `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`
   identically (heading + body); update hero `<p>` date + body `**Last Updated:**` date.
2. Apply §3a.7 + §10.4 + §9 clause to
   `plugins/soleur/docs/pages/legal/terms-and-conditions.md` identically; update both date
   sites.

### Phase 4 — Refresh version guards (LAST, after canonical bytes are final)

1. `sha256sum docs/legal/acceptable-use-policy.md` → `LEGAL_DOC_SHAS["acceptable-use-policy"]`.
2. `sha256sum docs/legal/terms-and-conditions.md` → `TC_DOCUMENT_SHA`.
3. Bump `TC_VERSION` `2.2.1 → 2.3.0`; update `TC_BUMP_METADATA` (3 fields).

### Phase 5 — Compliance register

1. Run the gdpr-gate determination (Phase 2.7) on the disclosure; record Art. 30
   disposition (default: no new PA; if needed, **PA 27**).
2. Add the `compliance-posture.md` Completed Compliance Work entry.

### Phase 6 — Verify (full-suite exit gate — load-bearing)

Run **`scripts/test-all.sh`** (NOT just touched-file tests — the SHA literal lives in
`lib/legal/` and the mirror in `plugins/soleur/`; neither is a "touched file" when editing
`docs/legal/*.md`, so only the full suite catches drift). Specifically green:
`legal-doc-consistency.test.ts`, `legal-doc-shas-guard.test.ts`, `tc-version.test.ts`,
`accept-terms-copy-regression.test.tsx`. See Acceptance Criteria for exact assertions.

## Drafting Bar (CLO — high-bar disclosure requirements)

The disclosure prose MUST, in plain-language but contract-grade form:

1. **Name the surface:** Soleur's Web Platform agent runs shell commands **automatically**
   (without per-instance approval) once the workspace owner has acknowledged the first-run
   disclosure soft-gate or set the workspace to autonomous/trusted.
2. **Admit the residual risk explicitly** — do not soften to a guarantee:
   - The blocklist (`curl`, `wget`, `ncat`, `nc`, `eval`, `sudo`, interpreter `-e`/`-c`,
     `base64 -d`, `/dev/tcp`) is **illustrative, not exhaustive** ("no blocklist is
     perfect" — mirror the LOCKED COPY's admission).
   - A command that is **not blocked and not on the read-only auto-approve allowlist** can
     auto-run, and a non-blocked command **could still change or delete files in the
     connected workspace**.
3. **Name the mitigations honestly as mitigations, not safety guarantees:** work is
   **git-backed** (the connected repo is the recovery surface); **every command is visible
   in chat** (the operator can watch each run); the owner controls the autonomous toggle
   and can revert to ask-each-time.
4. **State the user's responsibility:** connect only repos and accounts you trust; review
   command activity; the residual risk of an auto-run non-blocked command is the user's.
5. **Cross-reference** the in-product `AUTONOMOUS_DISCLOSURE_COPY` banner and the
   companion section in the other doc (AUP §5.7 ↔ T&C §3a.7 ↔ T&C §10.4), so the three
   disclosure surfaces are mutually consistent.
6. **GDPR Art. 22 note:** autonomous command execution is a development-workflow action on
   the user's own connected systems, not automated decision-making producing legal effects
   on a third party; the existing §3a.6 / §9 Art. 22 framing already covers third-party
   effects via the action-bus — §3a.7 should explicitly distinguish "commands on your own
   connected workspace" from "sends to third parties" (governed by §3a.1–§3a.6).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AUP §5.7 exists** in `docs/legal/acceptable-use-policy.md` with the residual-risk
      admission (blocklist not exhaustive) AND both mitigations (git-backed, visible-in-chat)
      AND the trust-only-what-you-connect responsibility. Verify:
      `grep -c "Autonomous command execution" docs/legal/acceptable-use-policy.md` ≥ 1 AND
      the section names "git" and "chat" mitigations.
- [ ] **T&C §3a.7 AND §10.4 exist** in `docs/legal/terms-and-conditions.md` with the
      residual-risk warranty admission. Verify section headings present via
      `grep -nE "^### 3a\.7|^### 10\.4" docs/legal/terms-and-conditions.md` returns 2 lines.
- [ ] **Heading-sequence parity:** `legal-doc-consistency.test.ts` `%s: section-heading
      sequence matches between source and mirror` passes for BOTH
      `acceptable-use-policy` and `terms-and-conditions` (new headings land identically in
      canonical + mirror).
- [ ] **Date lockstep:** the `Last Updated date is identical between source and mirror`
      test passes — the new date (`June 4, 2026`) appears identically in canonical body,
      mirror body `**Last Updated:**`, AND mirror hero `<p>` for both docs.
- [ ] **AUP SHA pinned:** `LEGAL_DOC_SHAS["acceptable-use-policy"]` equals
      `sha256sum docs/legal/acceptable-use-policy.md`; `legal-doc-shas-guard.test.ts`
      `stale SHA literal on a non-T&C doc is detected` baseline passes (the unmodified-tree
      `exits 0` case).
- [ ] **T&C SHA pinned + TC_VERSION bumped together:** `TC_DOCUMENT_SHA` equals
      `sha256sum docs/legal/terms-and-conditions.md` AND `TC_VERSION === "2.3.0"`.
      **Local pass mechanism:** `check-tc-document-sha.sh` Step 3 (`:236-238`)
      short-circuits when `canonical_sha == literal_sha` — because the SHA is repinned to
      the final bytes, the guard passes locally via the matched-SHA path (the
      `GITHUB_BASE_REF` bypass at `:240-248` is NOT consulted locally, since `test-all.sh`
      runs with `GITHUB_BASE_REF` empty). **CI bypass (informational):** if a future PR
      edits the T&C and leaves the SHA stale, CI accepts it only when the same PR diff
      (`origin/$BASE...HEAD`) shows a `TC_VERSION` line change — which this PR does.
- [ ] **Seed-script TC_VERSION parity:** `seed-dev-users.sh:94` AND `seed-qa-user.sh:18`
      both read `TC_VERSION="2.3.0"`, matching `tc-version.ts` (`check-tc-document-sha.sh`
      Step 2.5 asserts this; drift fails the guard). Verify:
      `grep -hoE '^TC_VERSION="[^"]+"' apps/web-platform/scripts/seed-{dev-users,qa-user}.sh`
      returns `TC_VERSION="2.3.0"` twice.
- [ ] **T&C body-equivalence:** the guard's `mirror prose drift on T&C` path is green —
      the §3a.7/§10.4/§9 prose is present in BOTH canonical and mirror so the body-SHA
      comparison matches.
- [ ] **Re-acceptance metadata current:** `accept-terms-copy-regression.test.tsx` passes
      with the updated `TC_BUMP_METADATA` (`lastUpdated`/`substantiveChange`).
- [ ] **`scripts/test-all.sh` exits 0** (full-suite exit gate — run before marking ready,
      not at ship; legal-doc drift is only caught here, per learning).
- [ ] **gdpr-gate (Phase 2.7) run** and Art. 30 disposition recorded in PR body
      (default: "no new PA — disclosure of existing PA 21/22 autonomous-execution runtime";
      or PA 27 if the gate finds an unregistered limb).
- [ ] **CPO sign-off** recorded (single-user-incident threshold) and **CLO sign-off**
      recorded (Tier-1 material T&C change) before merge.
- [ ] PR body uses `Closes #4952` and `Ref #4949`. PR title pattern:
      `legal(tc): TC_VERSION → 2.3.0 — disclose autonomous command execution + residual risk`.

### Post-merge (operator)

- [ ] **None automatable beyond CI.** The `TC_VERSION` bump auto-forces `/accept-terms`
      re-acceptance for existing users via middleware on next request — no operator action.
      The docs-site mirror deploys via the existing Eleventy build pipeline. No migration,
      no `terraform apply`, no Doppler write. (Automation-feasibility gate: every step is
      either CI-verified or middleware-automatic; nothing punts to the operator.)

## Domain Review

**Domains relevant:** Legal (CLO — primary), Product (CPO — single-user-incident threshold).

### Legal (CLO)

**Status:** reviewed (plan-time; CLO sign-off pending at ship per Tier-1 bump-policy)
**Assessment:** This is a Tier-1 material T&C change adding new disclaimer-of-warranty /
residual-risk text (T&C §10.4) — `TC_VERSION` bump required (`2.2.1 → 2.3.0`), forcing
re-acceptance. The disclosure must be substantively consistent with the shipped
`AUTONOMOUS_DISCLOSURE_COPY` LOCKED COPY (#4949) to avoid an in-product-vs-contract
divergence liability. Art. 22 distinction (own-workspace commands vs third-party sends)
must be explicit so §3a.7 does not collide with the existing §3a.6 / §9 Art. 22 framing.
Art. 30 register: disclosure of existing PA 21/22 runtime, most likely no new PA —
confirm at gdpr-gate. CLO sign-off is the ship-time gate.

### Product/UX Gate

**Tier:** none (no UI surface)
**Decision:** auto-accepted (pipeline) — this plan implements legal-doc + version-literal
edits only. `## Files to Edit` / `## Files to Create` contain **no** path under
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`; the mechanical
UI-surface override does NOT fire. The autonomous-disclosure **banner** is already shipped
by #4949 (LOCKED COPY, plan-locked) — this PR does not touch it.
**Agents invoked:** none (no UI surface; CPO sign-off requirement noted under
User-Brand Impact for the single-user-incident threshold).
**Pencil available:** N/A (no UI surface).

#### Findings

CPO sign-off is required at plan time (single-user-incident threshold) for the *approach*
— disclosure parity with the in-product banner, TC_VERSION bump forcing re-acceptance.
No wireframes (no new UI). `user-impact-reviewer` runs at review-time per the conditional
agent block.

## Infrastructure (IaC)

Skipped — no new infrastructure surface. No server, service, cron, secret, DNS, cert,
firewall rule, or vendor account is introduced. The only `apps/web-platform/**` files are
two hand-edited TS literal files (no runtime logic). Phase 2.8 trigger set: no match.

## Observability

Skipped — pure-docs + version-literal change. `## Files to Edit` includes
`apps/web-platform/lib/legal/{legal-doc-shas,tc-version}.ts`, but these are **const-only
literal files** with no runtime code path, no new failure mode, and no new emit site. The
*enforcement* observability already exists: `check-tc-document-sha.sh` (CI gate) +
`legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` fail loudly on drift.
No new liveness signal, error-reporting destination, or failure mode is introduced by a
disclosure-text edit. (Per Phase 2.9 skip rule: no new code/infra surface — the literal
files carry no logic.)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (70 open) queried against every
planned file path (`docs/legal/acceptable-use-policy.md`,
`docs/legal/terms-and-conditions.md`, `legal-doc-shas.ts`, `tc-version.ts`,
`plugins/soleur/docs/pages/legal`) and against AUP/ToS/legal/autonomous-titled issues —
zero matches. No fold-in, acknowledge, or defer needed.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **Date drift between canonical, mirror body, and mirror hero** (3 sites per doc, 6 total). | `legal-doc-consistency.test.ts` asserts all three per doc; Phase 3 updates all date sites explicitly; full-suite exit gate catches any miss before ready. |
| **SHA computed before final canonical bytes** → stale literal. | Phase 4 is LAST; SHAs computed only after canonical edits are final and mirrors applied. |
| **T&C SHA edited without TC_VERSION bump** → guard fails the build. | TC_VERSION bump is mandatory (Tier-1 material) and lands in the same literal edit; guard's T&C branch accepts a SHA change when the version also changed. |
| **Mirror heading sequence diverges** (new section in canonical not mirror, or vice-versa). | Phase 3 mirrors headings identically; consistency test's heading-sequence assertion is the gate. |
| **T&C body-equivalence sensitive to mirror collapse/normalize pipeline** — a sentinel paragraph present in one but not the other fails the body-SHA step. | Mirror the §3a.7/§10.4/§9 prose verbatim into the mirror content `<section>`; the guard's body-equivalence test (`legal-doc-shas-guard.test.ts`) confirms parity. |
| **Disclosure prose drifts from the shipped LOCKED COPY** (`AUTONOMOUS_DISCLOSURE_COPY`). | Drafting Bar item 5 cross-references the banner; the legal prose is drafted to be substantively consistent (same three claims) without re-stating the LOCKED COPY as a second source of truth. |
| **Over/under-classifying the TC bump** (PATCH vs MINOR vs MAJOR). | Phase 0 reads §semver-for-legal-docs; new disclaimer text = material = bump required; MINOR (`2.3.0`) for a new section/disclosure (not a breaking restructure). Over-bumping is recoverable (consent fatigue) — when unsure, bump. |
| **Spurious Art. 30 PA added** (disclosure ≠ new processing). | Default to "no new PA — disclosure of existing PA 21/22 runtime"; only add PA 27 if gdpr-gate finds an unregistered limb. |
| **`TC_VERSION` bumped but seed scripts not updated** → `check-tc-document-sha.sh` Step 2.5 fails (`TC_VERSION drift`). | Update `seed-dev-users.sh:94` + `seed-qa-user.sh:18` to `2.3.0` in the same PR (now an explicit Files-to-Edit item + AC). |

### Research Insights

**Precedent diff (Phase 4.4 — pattern-bound, strong sibling precedent):** The 3-way-lockstep
legal-doc disclosure edit is NOT novel. Recent sibling PRs followed the identical mechanic
(canonical `docs/legal/*.md` + Eleventy mirror `plugins/soleur/docs/pages/legal/*.md` + SHA/
version literal, all in one PR):

- `84146d17` **#4508** — BYOK delegations PR-B: UI surfaces + legal docs (added AUP §5.6, T&C §3a cross-refs, mirrors, SHAs).
- `6dfb014c` **#4625/#4637** — DPD §2.3(w) lawful-basis correction (canonical + mirror + SHA repin).
- `8e8f50ca` **#4916** — workspace logo (added Art. 30 PA 26, legal-doc touches).

The canonical mechanic matches the lockstep documented in
`knowledge-base/project/learnings/2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md`.
**No novel pattern** — the deepen risk is orphan-guard misses (caught: seed-script Step 2.5),
not a new design.

**Verify-the-negative pass (cited claims confirmed against source):**

- `BLOCKED_BASH_PATTERNS` verbs (`permission-callback.ts:84-85`): `curl|wget|ncat|nc|eval|sudo`
  + interpreter `-e`/`-c` (`sh|bash|node|python|python3|ruby|perl|deno|bun`) + `deno eval` +
  `base64 -d` + `/dev/tcp`. The plan's enumerated verb list matches the source regex verbatim. ✔ confirms
- `AUTONOMOUS_DISCLOSURE_COPY` (`autonomous-disclosure-banner.tsx:21-27`) carries the three
  load-bearing claims the legal prose mirrors: "no blocklist is perfect", "could still change
  or delete files", "backed up in git … watch every command run in the chat", "only connect
  repos and accounts you trust". ✔ confirms (prose drafted to be substantively consistent)
- `check-tc-document-sha.sh` matched-SHA short-circuit (`:236-238`) + CI bypass (`:240-248`,
  `GITHUB_BASE_REF`-gated) + Step 2.5 seed parity (`:276-318`). ✔ confirms (corrected AC + added seed Files-to-Edit)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is complete; threshold = single-user incident.)
- **`TC_DOCUMENT_SHA` is in `tc-version.ts`, NOT `legal-doc-shas.ts`.** The issue body says
  "update SHA guards in `legal-doc-shas.ts`" but that file has no `terms-and-conditions`
  key — the T&C SHA lives in `tc-version.ts`. Editing only `legal-doc-shas.ts` for the T&C
  is a no-op that leaves `check-tc-document-sha.sh` red.
- **Editing `docs/legal/*.md` is a 3-way lockstep** (canonical + Eleventy mirror + SHA
  literal), and the SHA literal + mirror are NOT "touched files" when you edit the
  canonical — only `scripts/test-all.sh` catches the drift. Run it before Phase ready, not
  at ship. (Learning `2026-05-29-legal-doc-triple-lockstep…`.)
- **Compute the SHA on the FINAL bytes** — `sha256sum` includes frontmatter, whitespace,
  and the trailing newline. Re-running an editor that strips/adds a trailing newline after
  the SHA was pinned re-breaks the guard.
- **Mirror has TWO date sites** (hero `<p>` + body `**Last Updated:**`); the consistency
  test asserts both equal the canonical date. Updating only one fails the test.
- **Bumping `TC_VERSION` requires THREE literal sites, not one.** `tc-version.ts` is the
  canonical source, but `seed-dev-users.sh:94` and `seed-qa-user.sh:18` hardcode the same
  version and `check-tc-document-sha.sh` Step 2.5 fails on drift. All three move to `2.3.0`
  in the same PR. (This guard is an orphan suite — only `scripts/test-all.sh` exercises it;
  editing `tc-version.ts` alone leaves the seed scripts as a "non-touched file" miss.)

## Test Scenarios

1. **Edit canonical AUP → mirror → repin SHA → run suite:** `legal-doc-shas-guard` baseline
   `exits 0`, consistency heading + date tests green.
2. **Edit canonical T&C without TC_VERSION bump:** `check-tc-document-sha.sh` MUST fail
   (`TC_DOCUMENT_SHA literal is stale`) — confirms the bump is load-bearing. Then bump
   `TC_VERSION` → guard accepts.
3. **Inject a sentinel paragraph into the T&C mirror only:** guard MUST fail
   (`terms-and-conditions body drift`) — confirms mirror/canonical body-equivalence is
   enforced. (This is the negative control; production edits keep them in lockstep.)
4. **`accept-terms-copy-regression.test.tsx`** green with updated `TC_BUMP_METADATA`.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Disclose in AUP only (skip T&C). | Rejected. The residual-risk admission is a warranty/liability matter (T&C §10 domain); AUP governs permitted-use/responsibility. Both are needed for a high-bar disclosure; the issue explicitly names both. |
| Edit T&C §10.2 inline instead of new §10.4. | Deferred to deepen-plan. Leaning new §10.4 for discoverability + to avoid re-flowing the AS-IS clause; either way it is new disclaimer text → Tier-1 material. |
| Skip `TC_VERSION` bump to avoid re-acceptance friction. | Rejected. New disclaimer text is Tier-1 material per bump-policy; *and* re-prompting users to accept a residual-risk admission is the correct UX, not friction to avoid. |
| Re-author the residual-risk copy independently of the banner. | Rejected. Creates a second source of truth that can drift from `AUTONOMOUS_DISCLOSURE_COPY`; instead the legal prose cross-references and stays substantively consistent. |
| Add a new Art. 30 PA for autonomous execution. | Default-rejected. Autonomous-execution runtime is already PA 21/22; this is a *disclosure*, not new processing. Confirm at gdpr-gate; add PA 27 only if an unregistered limb is found. |

## Deferrals

None. All disclosure surfaces (AUP + T&C + both mirrors + both SHA/version literals +
compliance register) land in one PR. No capability is deferred to a later phase.

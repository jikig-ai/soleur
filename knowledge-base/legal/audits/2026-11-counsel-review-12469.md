---
title: "Counsel review audit — #12469 (cc server-side GitHub read tools for entitled sessions): Art. 30 PA-2 amendment (Art. 6(1)(f) assessment and Art. 14 position), DPIA screening addendum, ADR-278 amendment"
type: counsel-review
date: 2026-11-09
issue: 12469
pr: 12465
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-11-09
signed_off_by: "CLO agent function run via subagent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED for the merge of PR #12465, conditioned on C1 to C3 below. Not external counsel. The Art. 14 position is settled (Art. 14(5)(b)) and its weakest points are recorded, not hidden; the one open item is a monitored condition tracked in #12487, not an undecided position."
non_blocking:
  - "N1 — The Art. 30 amendment is one very long cell. It reads, but a future edit should split it into the register's usual limb rows. Left as drafted: re-flowing it in this PR would hide the real diff."
  - "N2 — ADR-278 amendment: the Consequence paragraph names the residual and points to the DPIA addendum. No legal wording to change."
open_follow_ups: ["C1 — widen Privacy Policy Section 8.1 carve-out (canonical, Eleventy mirror, SHA pin) to name issue, pull-request and comment authors and the hosted agent's reads, before a second workspace has the tools registered (#12487)", "C2 — decide a per-login suppression route for an upheld Art. 21 objection (not built) (#12487)", "C3 — re-read production (`web_egress=true` count and repository visibility) immediately before merge; the one-workspace figure is carried from the 2026-11-09 ruling and was not re-run by this review"]
re_evaluation_triggers: "A second workspace has the tools registered (Agent web access on with a verified public repository) OR first arms-length user OR widening to private repositories (#12471) OR any write tool or workflow-log tool (#12467, #12468) OR an Art. 21 objection or Art. 15 request from a repository author OR a change to what the tools return (a field naming a person other than the login) OR an EEA-out data subject OR a regulated-industry repository"
---

# Counsel review audit — #12469 (cc GitHub read tools, entitled sessions)

v1 internal counsel-review attestation under the ship Phase 5.5 gate, for a PR whose plan declares `brand_survival_threshold: single-user incident`. Authority: CLO agent function (Soleur-as-tenant-zero v1); operator veto retained; external counsel reserved for the frontmatter triggers. Output is draft material, not legal advice. Issue #12487 asked the CLO to attest the Art. 6(1)(f) assessment and settle the Art. 14 position; this file does both.

**Method.** Every implementation claim in the artifacts was checked against the code by function name, not line: `buildGithubReadTools` and the narrowing functions in `server/github-read-tools.ts` (fields returned: login only, no display name, email or avatar; no diff or patch field), `server/ci-tools.ts` and the read-CI tool in `server/github-tools.ts` (run name, branch, SHA, URL; no author field), `server/github-read-sanitize.ts` (`prepareStrings`: format-character strip on every string, `redactGithubSourcedText` on `title` and `body` keys only, per-field caps), and the registrar in `server/cc-github-read.ts` (visibility read with `redirect: "manual"`; `false` registers, `true` is `repo-private`, anything else is `visibility-unknown`). The published surfaces were read for the Art. 14 question: Privacy Policy Sections 4.4, 4.7 (Agent web access bullet), 8.1 (the "Operator-assisted sessions and granted repository access" carve-out) and GDPR Policy Section 3.14. The one-workspace production figure was taken from the 2026-11-09 ruling row in `decision-challenges.md` and was not re-run (C3).

## Artifact 1 — article-30-register.md, 2026-11-09 amendment (PA-2 web-egress sub-purpose)

| Claim | Checked against | Verdict |
|---|---|---|
| Six tools, read-only, run in the dispatch process with the installation token; token never enters the sandbox | tool list in `github-tools.ts`, ADR-278 amendment | TRUE |
| Registers only for a verified public repository; error, timeout or missing field fails closed as `visibility-unknown` | registrar in `cc-github-read.ts` | TRUE |
| Data categories: "GitHub login, display text and whatever they chose to publish" | narrowing functions | **IMPRECISE — corrected in place.** The tools return the login only (no display name, email or avatar); CI status has no author field. Text now says so |
| Necessity: "the owner could otherwise paste the same text into the conversation" | reasoning | **WEAK — rewritten.** Pasting is the same processing by the same model, so it is no less intrusive for the author and is not a necessity argument. Replaced by the real alternatives considered and rejected (in-sandbox token = the channel ADR-278 Decision 5 closes) and the point that an entitled session with open egress could already fetch the same public pages, so the tools add reliability and framing, not reach |
| Balancing: authors "can expect it to be read by the repository owner and tooling acting for them" | reasoning | **ONE-SIDED — rewritten.** Reading by a person or search engine is expected; transmission to an AI provider in the US next to an open egress path is a weaker expectation. The balancing now lists what weighs against (expectation gap, incidental Art. 9 and third-party data the redaction does not catch, prompt-injected exfiltration) and why each is bounded |
| "nothing is stored beyond the conversation" | PA-2 envelope | **IMPRECISE — corrected.** Tool output that enters the conversation is PA-2 conversation content and goes to Anthropic with the model call; (f) now says so |
| Art. 21: the agent "stops receiving that text only by the owner removing it or turning the toggle off" | reasoning | **FALSE AS AN Art. 21 ANSWER — rewritten.** That is the owner's option, not Jikigai's. Jikigai has no per-login suppression (none built). Honest route stated: manual, no completeness guarantee, stop reading, delete local copies, cannot compel Anthropic earlier than its terms, author can edit or delete the GitHub text. Mirrors the published Section 8.1 carve-out |
| `redactGithubSourcedText` is data minimisation, not a confidentiality or exfiltration control | `prepareStrings`, docstring of the sanitiser | TRUE (title and body only; logins, labels, branch and run names are only stripped and capped) |
| Residuals: visibility not rechecked per call; toggle-off leaves tools registered until the conversation ends | registrar and per-call revalidation (identity and stored installation only) | TRUE, correctly stated |
| "Not a control: no scope-grant gate" | CLO ruling row | TRUE |
| Controller role not stated | Privacy Policy (Jikigai controller for the Web Platform), PA-2, PA-17 | **GAP — added.** Jikigai treated as controller; the owner's own controllership is not decided and is not used to move the Art. 14 duty |

**Verdict: accurate after correction.** The Art. 6(1)(f) assessment is attested as rewritten.

## Artifact 2 — Art. 6(1)(f) legitimate-interest assessment (inside the amendment)

| Part | Finding |
|---|---|
| Purpose | Legitimate, specific, real. Two interest-holders (Jikigai delivering the capability the owner switched on; the owner working on their own repository). Art. 6(1)(f) admits a third party's interest |
| Necessity | Met. The reading is the capability, so no narrower processing delivers it; reach is minimised (metadata and capped text, no diffs, no logs, no writes, public repositories only, repository closed over server-side). Less intrusive alternatives are named and rejected on reasons |
| Balancing | Passes on a one-workspace footing. Impact on authors is low (public by their own act; login-only identifier; no author index; no use beyond the owner's request; read-only). Counter-weights are stated and bounded. It would need re-doing for a second workspace, a private repository or any write path (re-evaluation triggers) |
| Art. 21 | A route exists (`legal@jikigai.com`), but the remedy is manual and bounded; the limits are written into the amendment. No per-login suppression exists (C2) |
| Residual not closed | Incidental Art. 9 and third-party data in free text: the redaction does not claim to catch it; Art. 9(2)(e) is not stretched to cover data about a person published by someone else |

**Verdict: ATTESTED.**

## Artifact 3 — Art. 14 position (third-party authors of the text the tools read)

**Ruling.** Art. 14 applies: the login and the text are not obtained from the author. Jikigai gives no individual notice and relies on **Art. 14(5)(b), disproportionate effort**, because (a) the tools return no contact route, so notice would require obtaining more personal data than the processing uses; (b) the authors are numerous, not enumerated and not indexed by Jikigai; (c) the reading is transient, read-only and at the owner's direction; (d) the text is public by the author's own act. The appropriate measures Art. 14(5)(b) asks for are the publication of the register entry, the DPIA addendum and this audit in the public Soleur repository, and the published rights route (Privacy Policy Section 8.1 carve-out, which states the Art. 14(5)(b) reliance and the Art. 21 route; Section 4.4 for the Soleur repository).

**Why not the other options.** Notice by the existing Privacy Policy alone: not enough, because Section 8.1 is headed for operator-assisted sessions and names files and commits, not issue, pull-request and comment authors. Art. 14(5)(a) (already informed): no. Leaving it open: not defensible once the record says a basis exists.

**Weakest points, recorded.** (1) Art. 14(5)(b) is framed around archiving, research and statistics and this purpose is commercial (GDPR Policy Section 3.14 already names the same weakness). (2) For authors on any repository other than `jikig-ai/soleur` the published information is thin (the carve-out wording). (3) The `jikig-ai/soleur` population is already recorded as engaged and undischarged under PA-31 and PA-32 (#7120); this change adds no author to it and neither discharges nor worsens it. For the single live workspace (Jikigai-owned, `jikig-ai/soleur`) the categories read here are the ones Privacy Policy Section 4.4 already names for that repository.

**Why DISCHARGED despite (2).** The only live workspace is Jikigai-owned, so the added population is empty today; the processing is public text, read-only and transient; and the condition is concrete. The honest limit: the toggle is owner self-service, so nothing in code stops a second owner enabling before C1 lands. That window is accepted as a monitored v1 residual (C3 re-read, onboarding checkpoint), not a gate. If the lead prefers zero window, the alternative is the one-sentence carve-out widening inside this PR (canonical, mirror, SHA pin) and a re-attestation; this review does not require it.

**Verdict: SETTLED, with conditions C1 and C2.**

## Artifact 4 — DPIA screening addendum (section 4 of the 2026-10-05 audit)

| Claim | Checked against | Verdict |
|---|---|---|
| Trigger t5 fires; t2 does not (deny census and `denyRead` unchanged, token stays in the dispatch process) | ADR-278 amendment, trigger list in sections 1 to 3 | TRUE |
| Full DPIA still not required | EDPB criteria: innovative technology applies; no scoring, no vulnerable subjects, no large-scale processing on the live footing (one workspace) | Accepted as a one-workspace conclusion. **Sharpened in place:** the addendum now says it is re-screened when a second workspace has the tools registered |
| Residual (a) accepted with a named widening, narrowed by the public-repository gate | registrar | TRUE |
| Redaction is data minimisation only; framing covers comments and CI text | sanitiser; framing applied by the read builder to all six tools | TRUE |
| "Art. 14 and the lawful basis ... open, tracked in #12487" | this audit | **UPDATED in place** to the settled position, the three weakest points, condition C1 and a pointer here |
| Present-tense wording | append-only rule: a record written inside the PR whose merge fires its trigger must be conditioned on that merge | **CORRECTED:** the addendum now says it fires on the merge of PR #12465 and describes no earlier state |

**Verdict: accurate after correction.**

## Artifact 5 — ADR-278 amendment (2026-11-09)

Read for legal accuracy only (the architecture belongs to the CTO). The amendment states the Decision 5 consequence, the public-repository registration gate with its fail-closed reason, both residuals, the absence of a new credential path and the pointer to the DPIA addendum. It makes no Art. 14 or lawful-basis claim of its own. **Verdict: no legal change required.**

## Not edited, by ruling

Privacy Policy and Data Protection Disclosure remain unedited (earlier ruling, on the one-workspace footing). C1 is the condition that ends that footing. No file under `docs/legal/` is touched, so the mirror-drift, SHA-pin and heading-parity gates are not engaged by this PR.

## Conditions

1. **C1** — before a workspace other than the Jikigai-owned one has the tools registered, widen Privacy Policy Section 8.1 carve-out to name issue, pull-request and comment authors and the hosted agent's reads (canonical, Eleventy mirror, SHA pin re-pin). Tracked in #12487 (re-scoped to this).
2. **C2** — decide and build, or consciously decline with reasons, a per-login suppression route for an upheld Art. 21 objection. Tracked in #12487.
3. **C3** — immediately before merge, re-read production for the count of workspaces with `web_egress=true` and each one's repository visibility. If a second workspace is already enabled, C1 becomes a merge precondition, not a follow-up.

## Decision record

**Decision:** discharge the counsel-review gate for PR #12465 on the corrected text. The assessment is attested, the Art. 14 position is Art. 14(5)(b) with named weaknesses, and two follow-ups plus one pre-merge re-read are recorded as conditions.

**Rationale:** the processing reads public text, read-only and transiently, for a repository owner who switched it on, in a single Jikigai-owned workspace; the legal risk is concentrated in the publication measure for a future population, which has a concrete, tracked condition. Blocking the merge would not reduce harm to any current data subject.

## External counsel re-review triggers

Any of the `re_evaluation_triggers` in the frontmatter re-opens this review and, where the trigger is a first arms-length user, an EEA-out data subject or a regulated-industry repository, sends it to external counsel.

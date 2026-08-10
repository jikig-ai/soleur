# feat: three write-time gates for legal-corpus edits

---
issue: 7387
branch: feat-one-shot-7387-legal-corpus-write-time-gates
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
created: 2026-08-10
---

> **Lane note.** No `spec.md` exists for this branch, so `lane:` could not be carried forward.
> Defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Build three mechanically-checkable gates over the legal document corpus (`docs/legal/*.md` and
its Eleventy mirror `plugins/soleur/docs/pages/legal/*.md`), register them into runners that
actually execute, and mutation-prove each one.

1. **`legal-scope-block-placement`** — for **added** scope blocks asserting plugin-local scope,
   assert (a) the enclosing section makes no Web-Platform / Controller / Cloud-Execution claim,
   and (b) the block is flush-left, not list-indented.
2. **`legal-mirror-drift-baseline`** — for each canonical↔mirror pair, assert normalised drift at
   HEAD **equals** drift at the merge base (equality, not zero).
3. **`obligation-checklist`** — a runner that takes a typed binding-items file, runs one
   **positive** check per item, and fails on any miss.

The unifying idea: the review skill's defect-class catalogue has ~80 entries, nearly all of which
are review findings that became institutional knowledge and never became a gate. These three are
the subset with the highest recurrence against `docs/legal/` and the lowest judgment requirement.

**Closes #7387.**

---

## Premise Validation

Run before any research was dispatched, per plan Phase 0.6. Five premises checked; **three were
stale or wrong**, and one of those materially changes the plan's framing.

| # | Premise (from #7387) | Verified? | Finding |
|---|---|---|---|
| 1 | Context files exist at the cited paths | ❌ **stale** | All three cited context files are absent from `origin/main` **and** from `origin/feat-one-shot-7347-…` (remote tip `8b871eb4b`). They live only on the **local** ref `feat-one-shot-7347-dpd-operator-assisted-scope` (tip `2dd397542`), which is 10 commits ahead of its remote. Read via `git show 2dd397542:<path>` — verified reachable from this worktree. |
| 2 | PR #7372 is the merged motivating change | ❌ **stale** | PR #7372 is **OPEN** (`WIP:`), `mergedAt: null`. Its legal-corpus edits are **not on main**. |
| 3 | Pre-existing drift is 56 / 58 / 63 / 18 / 2 lines | ✅ **holds, and is larger** | Measured with the real normalisers: DPD 56, privacy 58, gdpr 63, AUP 18, disclaimer 2 — **exactly as claimed** — plus three the issue omits: corporate-cla 12, individual-cla 7, cookie-policy 4. T&C is 0 (already body-equivalence-enforced). **Total 220 lines across 8 pairs.** |
| 4 | The three gates would have caught 6–7 of the 10 P1s | ❌ **wrong** | They would have caught **4** (P1-4, P1-5 via gate 1; P1-6, P1-9 via gate 3). See R1 as corrected by R13 — the first draft said 3, having mis-filed P1-6 (a pure grep) as a judgment finding and omitted P1-8 entirely. |
| 5 | The obligation rule shipped in `work/SKILL.md` on 2026-08-09 | ⚠️ **not on main** | The `Verify that every BINDING item LANDED` HARD GATE exists only on the unmerged 7347 branch (`work/SKILL.md:190`). Main has no such rule. |

**Disposition:** none of these blocks the work. #7387 is genuinely open, the gates are genuinely
absent, and the corpus is genuinely ungated. Premises 1/2/5 mean this plan must not cite the
context files in any file-existence AC, and premise 4 is corrected in the framing below rather
than inherited.

---

## Research Reconciliation — Spec vs. Codebase

### R1 — The issue's finding-attribution is wrong, in the gates' disfavour *(material)*

`review-findings.md` (read at `2dd397542`) records what each finding actually was:

| Claim in #7387 | Reality | Evidence |
|---|---|---|
| "would have caught 6–7 of the 10 P1s" | **4 of 10** — P1-4, P1-5 (gate 1); P1-6, P1-9 (gate 3) | The other 7 are judgment findings: a conjunction-gated carve-out, a collapsed three-limb test, an unexecuted instrument published as standing practice, a quasi-identifier reproduced after being flagged, a false closed exception list, an intra-section contradiction, and a missing balancing test. None is a grep. |
| Gate 1 → "Nine findings" | 2 P1s + one P2 spanning 7 sites | Counting 7 sites of one P2 as 7 findings while counting P1-4/P1-5 as 2 is a unit mismatch. |
| "both list-splitting defects" | **three** | `review-findings.md`: "three list-splitting insertions (6 sites incl. mirrors) — Disclosure §3.1, §10.1, gdpr-policy §7.1". |
| Gate 2 caught the §8.1 ordering defect | Gate 2 catches **zero of the 10 P1s** | `review-findings.md` §"What held": *"Mirror sync is exact: normalised drift sets are character-for-character identical at `origin/main` and at HEAD for all five pairs."* The ordering defect was introduced **later**, during CLO-ruled remediation — commit `50f589c2d`, *"a mirror-position regression I introduced"*. |

**Plan response.** Keep all three gates; correct the justification. Gate 2 is a **post-review
regression catcher**, not a P1 catcher — and that is still the strongest argument for it, because
it is the only one of the three that sees a defect on the *published* surface that no existing
gate can see (`legal-doc-consistency` compares heading sequence; the SHA guard compares canonical
hashes; neither sees a mirror-side reordering). The honest headline: **4 of 10 P1s, ~9–11 P2/P3
sites, and one class of regression that is currently invisible** — and gate 3 *detects* none of
its share: it executes a checklist a human authored (R13). That is worth building. The
inflated claim is not needed and must not be repeated in the PR body.

### R2 — `**Scope.**` and `**What this covers.**` do not exist on main *(load-bearing)*

Measured across both corpora on `origin/main`: **0 occurrences** of either marker; 0 occurrences of
`plugin-local`, `operator-assisted`, or `on the User's own machine`. Both markers are coined
entirely by the 7347 branch (36 × `**Scope.**`, 14 × `**What this covers.**`).

**Plan response — this reverses the naive reading of "derive the marker list from the corpus".**
A literal marker allowlist derived from `origin/main` would contain neither marker and would
therefore **reject the very change the gate exists to police**. The gate must derive a *semantic
discriminator* from the tree under test (HEAD), not a literal marker list from main:

- **locality assertion** — `plugin-local|(running|operates|runs|executes)\s+(on|locally|entirely)|(your|the User's)\s+own\s+(machine|filesystem|API key|credentials)|locally-installed|local CLI environment`
- **AND a negative delimiter** — `must not be read as covering it|It does not describe`

The negative delimiter is what separates signal from noise. Every genuine scope block on 7347 has it.
Blocks like `**Technical measure.**`, `**Lawful basis.**`, `**Profiling.**` have neither half.
`**Plugin (Local Execution).**` has the locality half only — it is a *responsibility* block, and
correctly not a scope block.

> **⚠ Corrected at plan-review — the delimiter's evidence on `main` is a sample of ONE, not two.**
> An earlier draft claimed two pre-existing main-branch instances. Measured: the only matches are
> `docs/legal/privacy-policy.md:269` **and its own mirror** `plugins/…/privacy-policy.md:268` — one
> block, two surfaces. `data-protection-disclosure.md:61`
> (`**Therefore, Soleur is neither a Controller nor a Processor…**`) carries the locality half and
> **no** negative delimiter; it does not match.
>
> **Consequence:** the two literal phrases are over-fitted to a single sentence plus an unmerged
> branch. A future block reading *"does not apply to"*, *"should not be construed as covering"*, or
> *"is not a statement about"* would pass silently — which is exactly this plan's declared
> fail-open harm. **Phase 2.3 must therefore broaden the delimiter to a pattern family** and
> re-measure false positives on main:
> `(must not|should not|is not to) be (read|construed|understood) as (covering|describing|applying)|does not (describe|cover|apply to)`
> Report the new main-branch hit count in the PR body. If broadening produces false positives, the
> fallback is to **invert the arm**: a block with a locality assertion sitting in a claim-bearing
> section fails *unless* it carries a delimiter — which fails safe instead of failing open.

### R3 — A blanket "no indented bold" rule false-fires on main

Measured: `^[ \t]+\*\*` matches **6 lines on main**, all in `data-protection-disclosure.md`
(`:106`, `:108`, `:110` + mirror `:115`, `:117`, `:119`). All six are **legitimate** lazy-continuation
paragraphs of the `- **(o)**` list item (`**Per-tenant scope grants…**`, `**Audit viewer…**`,
`**Legal basis:**`). 2-space indent + blank-line separation is valid CommonMark.

**Plan response.** Rule (b) is scoped to **scope blocks only** — blocks matching the R2
discriminator. Verified: that scoping yields **0 hits on main** and **6 true positives on 7347**
(3 canonical + 3 mirror).

> **⚠ The sentence that stood here is WITHDRAWN (CLO Amendment 5 / R3).** It read: *"A
> section-scoping statement is never list-item-scoped, so for this class 'indented' is
> unconditionally wrong."* The premise is true but the **class is misdefined** — the class is
> *section-referent blocks*, not *scope blocks*. A limb-referent rider is legitimately indented, and
> DPD §2.3's newly-opened `(a)`–`(ad)` list is exactly where one belongs. See the corrected arm (b):
> attachment must match declared referent.

### R4 — The normalisers cannot be sourced; they must be extracted

`apps/web-platform/scripts/check-tc-document-sha.sh` carries `set -euo pipefail`, `shopt -s nullglob`,
a doc-enumeration loop, and an `exit 1` at top level. **Sourcing it runs the entire guard.**

**Plan response.** Extract `normalize_canonical` / `normalize_plugin` / `collapse` verbatim into
`scripts/lib/legal-normalise.sh`; `source` it from both the existing guard and the new gate 2.
Repo-root `scripts/lib/` is the correct home — the corpus lives at `docs/legal/` and
`plugins/soleur/docs/pages/legal/`, **neither of which is under `apps/web-platform/`**.

**Extraction proven behaviour-preserving in-session**: the T&C body SHA computed through the
extracted functions is `bae24228864531665b28c5c6c08bbc35447368734ef1659fc86593ce47181fda` on both
canonical and mirror — identical, matching, and the in-place guard still exits 0.

`check-tc-document-sha.sh` backs the **required** status check `tc-document-sha-guard` (pinned in
`infra/github/ruleset-ci-required.tf` per ADR-032). The job name is untouched; only the script body
changes, so no terraform apply is needed.

### R5 — Registration: `scripts/` is auto-enforced; the other two runners are not

| Runner | Registration | Auto-caught if forgotten? |
|---|---|---|
| `scripts/*.test.sh` | explicit `run_suite` in `scripts/test-all.sh` | ✅ **YES** — `scripts/lint-orphan-test-suites.sh` fails the build, anchored on the `run_suite` **call shape** |
| `.github/scripts/test/test-*.sh` | auto-glob in `run-all.sh` | ⚠️ glob is automatic, but `MIN_SUITES=10` must be raised, and the job is **bash-only** (no terraform/apt/python per #6454) and checks out at **depth 1** |
| `apps/web-platform/infra/*.test.sh` | named step in `infra-validation.yml`, derived by `run-registered-suites.sh` | ✅ via `test-infra-suite-registration.sh` |

**Plan response — this decides the architecture.** Put all three gates and their suites in
repo-root `scripts/`. The orphan lint makes the issue's central failure mode — *"registration is
the part that is silently skipped"* — **structurally impossible**: a `.test.sh` with no `run_suite`
line reds the build automatically.

Decisive supporting fact: **`test-scripts` checks out with `fetch-depth: 0`** (`ci.yml:716`), and
`test-all.sh` already computes `git diff --name-only origin/main...HEAD` (`:243`) with an explicit
shallow-clone degradation note (`:288`). So the `scripts` shard can host **both** the fixture suites
and the live diff-based gate runs, and it rolls up into the required `test` context.

### R6 — Checklist row 21's anchor bug, and how gate 1 repairs gate 3

The CLO **overturned its own checklist row**: row 21 counted `^\*\*Scope\.\*\*` and was read as
counting *blocks*, but the `^` anchor excluded list-indented blocks — so *"exactly 8"* measured a
subset while reading as a total (commit `50f589c2d`, adjudication A).

**Plan response.** Two consequences, and they interlock:
- Gate 3 must treat an anchor's **coverage** as data, not as an assumption: every count row
  declares `anchor_covers` and is mutation-tested against a known-indented instance.
- **Gate 1(b) is what makes `^`-anchored counts sound in the first place.** Once no scope block may
  be list-indented, `^\*\*Scope\.\*\*` and "the number of scope blocks" are the same population.
  Gate 1 is therefore a precondition for gate 3's count rows, not merely a sibling. Ship gate 1
  first.

### R7 — Literal-match brittleness in the claim markers

| Marker | Occurrences | Brittleness |
|---|---|---|
| `Web Platform` | 555 ✅ | misses `web-platform` (48), `WEB PLATFORM` (6), `web platform` (2) — **9.2% of 611 total mentions**. Use case-insensitive `web[ -]platform`. `Web-Platform` title-case-hyphenated: 0, not a real variant. |
| `app.soleur.ai` | **140** *(corrected)* | An earlier draft said 202. Re-measured with `grep -roF` across both corpora: **140**. Seeding a declared list from the wrong number would have failed the calibration check on its first run. `.` must be escaped. |
| `acts as Controller` | **2** | extremely brittle — 2 lines out of 186 `controller`-family tokens |
| `Cloud Execution` | 2 | no lowercase/hyphenated variants exist |
| `server-side monitoring` | 2 | no variants |

**Plan response.** Markers live in a **declared, tested list at the top of the gate script** with
the measured count beside each, and a calibration assertion that the live corpus still yields
those counts (a marker whose count drops to 0 has been reworded and the gate has gone vacuous).
Use `grep -iE 'web[ -]platform'` for the dominant marker.

### R8 — Section resolution hazards *(all four confirmed against the corpus)*

1. **Nearest heading ≠ last-seen `###`.** Must be `max(last_h2_line, last_h3_line)` — a `##` with no
   subsections leaves a stale `###` from the *previous* section as the last-seen H3.
   **⚠ The earlier draft's cited example was wrong and is withdrawn.** It claimed `gdpr-policy.md:350`
   sits under `## 6.` [L331] vs `### 5.4` [L325]; measured on this tree, `## 6.` is at **320**,
   `### 5.4` at **314**, and line 350 falls under `### 7.1 Local Security` [343] — so
   `max(last_h2, last_h3)` = 343 and that site is not an instance. Line 350 is not even a bold-lead
   marker (it is a bullet). **The hazard class is real; this evidence was not.**
   **Phase 0.5 must re-derive the hazard sites and record them as *content anchors*
   (`### 5.4 Supervisory Authority`, `## 6. International Data Transfers`), never line numbers**
   — `cq-cite-content-anchor-not-line-number`. The stale-coordinate failure this bullet just
   demonstrated is the rule's own justification.
2. **A marker before the first heading.** Real, but **only on the 7347 branch**, and the earlier
   draft cited it against `main` where it does not exist. Verified: on `2dd397542`,
   `docs/legal/data-protection-disclosure.md:22` is `**Scope.** This section describes…` and the
   first heading is `## 1. Definitions` at **L28**. On `main`, line 22 is plain prose and the first
   bold-lead marker is at L50 — so a fixture built on "main's line 22" would test a line the gate
   never examines and pass vacuously. My prototype hit `sed: invalid usage of line address 0` on the
   7347 instance. The gate must handle a null/preamble section, and **AC7's fixture must be
   synthesized**, not a corpus coordinate.
3. **Non-integer section IDs** exist at both levels: `## 3a.`, `## 3b.`, `## 8b.`, `### 2.1b`,
   `### 8.1b`, `### 8.1c`, `### 14.1b`, `### 3a.1`. No `\d+\.\d+` assumption.
4. **Two docs have zero `###`** (`corporate-cla.md`, `individual-cla.md`).

### R9 — Regex cap drops 9 markers

`^[ \t]*\*\*[A-Z][^*]{0,60}\.\*\*` silently drops 9 real markers (longest is 120 chars). Use the
**uncapped** `^[ \t]*\*\*[A-Z][^*]+\.\*\*`. Note a second family exists — colon-terminated
`**Label:**` (`**Legal basis:**`, `**Retention:**`, …) — which is *out of scope* for this gate and
must not be swept in.

---

## Gate 1 — respecified on REFERENT after CLO review *(the plan's largest correction)*

> **The original arm (a) was wrong and would have caused the harm it exists to prevent.** It is
> withdrawn. What follows is the corrected specification.

**What went wrong in the first draft.** I prototyped against `FETCH_HEAD` (`8b871eb4b`, the 7347
**remote** tip) and the gate reproduced the review's 9 findings exactly, which read as validation.
It was not. The remote tip is **12 commits behind** the CLO-ruled-final tree (`2dd397542`). I had
validated the gate against the *pre-remediation* state that motivated the fix — never against the
*post-remediation* state the gate must not disturb.

**Measured on the ruled-final tree**, arm (a) as originally drafted fires on **8** sites, of which
**6 are text the CLO expressly ruled correct**:

| Referent | Enclosing section has a marker | Count | Disposition |
|---|---|---|---|
| `This section` | yes | **2** — gdpr `### 2.1 Soleur's Role` (L33), DPD preamble | genuine, still owed |
| `The paragraph above` | yes | **6** — AUP §5.1 (L238), §6.1 (L319); gdpr §6 (L439), §9 (L523); privacy §6 (L438), §10 (L544) | **ruled to survive — false positives** |

The CLO's remedy for the seven over-reach sites was **never relocation or deletion**. It was to
*narrow the referent in place*: `This section` → `The paragraph above`. Review findings: *"§4.1 is
the one site that got the shape right — it scopes 'the paragraph above'… That is the form every
other site needed."* A gate that reds those six would drive an editor to delete or move text
against a standing ruling.

**The legal test is not proximity to cloud words. It is whether the scope statement's declared
referent is larger than the text that is actually plugin-local.**

### Corrected specification

**Classification (arm 0).** A block is a scope block iff it carries a **locality assertion** AND a
**referent token** (`This section` / `The section` / `The paragraph above` / `The two paragraphs above`).
**The negative delimiter is NOT part of the classifier** — making it one creates an escape hatch
where deleting `must not be read as covering it` blinds the gate while the false affirmative stays
published, i.e. the gate rewards removing a disclaimer.

**Arm (a) — referent/section agreement.** Fire only when the referent is **section-scoped**
(`This section` / `The section`) **and** the enclosing section carries a marker. Paragraph-scoped
referents are excluded entirely — they are the ruling's prescribed remedy form.
*Verified: 2 hits on the ruled-final tree, both genuine; **0** false positives.*

**Arm (b) — attachment matches referent.** Not "flush-left, always". Section referent → flush-left;
paragraph referent → adjacent to that paragraph; **limb referent → indented under that limb**. The
absolute rule was wrong: R3's six indented continuations under `- **(o)**` (including
`**Legal basis:**`) are legitimate per-limb qualifications, and DPD §2.3's newly-opened `(a)`–`(ad)`
list is precisely where a limb-level rider belongs. Forcing such a rider flush-left would silently
re-scope it to the whole enumeration — the same defect running the other way. What made the three
P2 list-splitting sites wrong was that they said **"This section"** while GFM attached them to one
bullet: **referent and attachment disagreed.** Fire when referent is `This section` **and** the line
is indented.

**Arm (c) — delimiter as a requirement, not a classifier.** A classified scope block that lacks a
negative delimiter fails. This is what arm 0's exclusion of the delimiter makes possible, and it
closes the laundering path.

### Two further laundering paths the design must not reward

- **Section laundering.** `acts as Controller` is 2 lines out of 186 controller-family tokens.
  Rewording DPD §4.2's opener to *"Where Jikigai determines the purposes and means…"* would turn
  **P1-4 — the flagship defect** — green with the false block intact. The marker list is a
  heuristic over prose; treat a marker-list edit in the same diff as a scope block as a review flag,
  not a pass.
- **Relocation** to a marker-free but substantively cloud-scoped section.

Neither is fully mechanically preventable. Both are reasons the gate must never be represented as
adjudicating scope correctness (Amendment 11).

**Gate 1(b)** — 6 indented scope blocks on 7347 (3 canonical + 3 mirror), **0 on main**.

**Discriminator calibrated on main.** Running the R2 discriminator (locality **AND** negative
delimiter) over both corpora on `origin/main` yields **exactly 2** scope blocks —
`privacy-policy.md:269` and `data-protection-disclosure.md:61` — and **0 of them are indented**.
That is the AC5 number: the flush-left rule has zero false positives against the 6 legitimate
indented continuations, because none of those 6 is a scope block. The discriminator is neither
vacuous (it finds the 2 real ones) nor greedy (it rejects `**Technical measure.**`,
`**Lawful basis.**`, `**Plugin (Local Execution).**`).

**Preamble case.** No bold-lead block precedes the first heading in any doc on main, so AC7's
"no enclosing section" case has **no natural fixture** and must be synthesized
(`cq-test-fixtures-synthesized-only`). The real instance is `data-protection-disclosure.md:22` on
the 7347 branch, where the first heading is `## 1.` at L26.

**Consequence to state plainly:** once gate 1 merges it will **red PR #7372** until those sites are
fixed. That is the intended effect (#7349 is next in the same corpus), but it is a real sequencing
interaction and belongs in the PR body, not as a surprise.

---

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) a **fail-open** gate — a future legal-corpus
PR publishes a scope statement asserting "this section describes plugin-local processing" inside a
section that governs cloud processing, and a user reading `soleur.ai/legal/…` believes their data
stays on their machine when it does not; or (b) a **false-firing** gate that reds every PR in the
repo, since these ride required contexts.

**If this leaks, the user's data/workflow is exposed via:** no new data path. The gates read
already-public repo content in CI. No secrets, no user data, no network egress.

**Brand-survival threshold:** `single-user incident`

Rationale: the corpus these gates protect is *published legal text a user relies on*. A false
scope statement is a single-user-incident-class harm the moment one user acts on it — that is the
precise harm P1-4 and P1-5 were. The gate is one step removed from the harm, but its entire
justification is preventing that class, so grading it lower would exempt this surface from the
user-impact reviewer. Graded at the harm it exists to prevent.

Per threshold: `user-impact-reviewer` is invoked at review time; plan-review runs the escalated
panel (+`architecture-strategist` +`spec-flow-analyzer`).

---

## Architecture Decision (ADR/C4)

**No ADR required.** This adds CI gates on an already-provisioned surface. It introduces no
ownership/tenancy boundary, no new substrate, no resolver/dispatch/trust boundary, and reverses no
existing ADR. Extracting a shared normaliser lib is a refactor with one behaviour-preserving
consumer, not an architectural decision. A competent engineer reading the existing ADRs + C4 would
not be misled about the system after this ships.

**C4 completeness check (all three model files read, per the mandate — not a keyword grep).**
Enumerated for this change:
- **External human actors:** none. No new correspondent, reviewer, or recipient.
- **External systems / vendors:** none. No inbound webhook, no outbound API, no third-party store.
  The gates are bash + git + coreutils inside an existing GitHub Actions job.
- **Containers / data stores touched:** none. No new persistent store; reads tracked repo files.
- **Actor↔surface access relationships changed:** none.

`model.c4` models infrastructure hosts, vendors, and runtime edges (`hooks`, `tunnel`, `zotRegistry`,
`betterstack`, …); CI lint gates are not modelled as elements at any level, and adding one would be
inconsistent with how every sibling gate (`adr-ordinals`, `rule-body-lint`,
`service-role-allowlist-gate`, `tc-document-sha-guard`) is represented — i.e. not at all. **No `.c4`
edit is in scope**, and no element description is falsified by this change.

---

## Observability

```yaml
liveness_signal:
  what: the three suites appear BY NAME in the CI run log of their registering job
  cadence: every PR (required contexts `test` + `tc-document-sha-guard`)
  alert_target: PR status check (merge-blocking)
  configured_in: scripts/test-all.sh (run_suite lines) + .github/workflows/ci.yml
error_reporting:
  destination: GitHub Actions annotations (`::error::`) + non-zero exit
  fail_loud: true — exit 2 on internal error (broken glob, unresolvable base), never a silent 0
failure_modes:
  - mode: gate script silently scans zero files (broken glob / wrong CWD)
    detection: min-cardinality floor in each gate; exit 2 below floor
    alert_route: CI job failure with the measured count in the message
  - mode: suite registered but never executed
    detection: scripts/lint-orphan-test-suites.sh (already runs at ci.yml:177)
    alert_route: CI job failure naming the unregistered file
  - mode: marker list goes vacuous (corpus reworded, grep matches nothing)
    detection: calibration assertion — declared per-marker counts re-measured on the live corpus
    alert_route: CI job failure naming the marker whose count collapsed
  - mode: gate 2 cannot resolve the merge base (shallow clone)
    detection: explicit base-resolution check; exit 2, never fall through to a vacuous pass
    alert_route: CI job failure (mirrors the merge_group empty-base hard-fail at
                 legal-doc-cross-document-gate.yml:97-100)
logs:
  where: GitHub Actions run logs
  retention: 90 days (repo default)
discoverability_test:
  command: gh run view --log --job "test-scripts" | grep -E 'lint-legal-scope-block-placement|legal-mirror-drift-baseline|obligation-checklist'
  expected_output: all three suite labels present, each followed by its PASS line
```

No SSH anywhere. Nothing to soak; no follow-through enrollment required (no time-gated close
criterion).

---

## Encryption Posture

**Skipped** — introduces no persistent data store and no new cross-component connection. Pure CI
lint over tracked repo files.

---

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/lib/legal-normalise.sh` | The **single** normaliser. `normalize_canonical` / `normalize_plugin` / `collapse` extracted verbatim from `check-tc-document-sha.sh`. Guarded against double-source. |
| `scripts/lint-legal-scope-block-placement.sh` | Gate 1. `--base <ref>` (default `origin/main`), added-lines-only. Exit 0/1/2. |
| `scripts/lint-legal-scope-block-placement.test.sh` | Gate 1 fixtures + mutation battery. |
| `scripts/lint-legal-mirror-drift-baseline.sh` | Gate 2. Sources the shared lib. Exit 0/1/2. |
| `scripts/lint-legal-mirror-drift-baseline.test.sh` | Gate 2 fixtures + mutation battery. |
| `scripts/obligation-checklist.sh` | Gate 3 runner. Sources a bash checklist file; provides the `obligation` / `deletion` / `preserve` verbs. Usage contract lives in a ~15-line script header, **not** a separate schema doc. |
| `scripts/obligation-checklist.test.sh` | Gate 3 fixtures + mutation battery, incl. pre-edit-must-fail validation. Ships the worked example **as an executed fixture**, so it cannot go stale. |
| `knowledge-base/project/specs/feat-one-shot-7387-legal-corpus-write-time-gates/tasks.md` | Task breakdown. |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/scripts/check-tc-document-sha.sh` | Replace the three inline function bodies with `source scripts/lib/legal-normalise.sh`. **Behaviour-preserving**; job name untouched. `^EXPECTED_COUNT=9` must stay at line-start (AC14b) — a vitest guard parses this file's text. |
| `scripts/test-all.sh` | `run_suite` lines: live + unit for each gate, **plus** a live line for `check-tc-document-sha.sh` (see below). |
| `scripts/lint-orphan-test-suites.sh` | Add the three **live** gate scripts to `REQUIRED_RUNNERS`. Without this, the plan's registration thesis is false for exactly the half that gates the corpus. |

**Deliberately NOT edited — `.github/workflows/ci.yml`.** An earlier draft added gate-1 and gate-2
steps to the `tc-document-sha-guard` job. **Cut at plan-review**, on three converging findings:

1. **It buys nothing.** The `run_suite` lines already land the gates in `test-scripts`
   (`ci.yml:668`) → the `test:` aggregator (`ci.yml:792-793`, `needs: [test-webplat, test-bun, test-scripts]`)
   → the **required** `test` context. Both gates already ride a merge-blocking context with
   `fetch-depth: 0`, with **zero** workflow and zero terraform change.
2. **It costs the name.** `tc-document-sha-guard`'s script header and the ruleset comment both
   describe it as SHA-pinning. A future operator debugging a red `tc-document-sha-guard` would read
   three artifacts all pointing at SHA literals. Risk 2 proposed to mitigate this with prose against
   a name — which is not an enforcement mechanism.
3. **It was factually wrong, and the error was load-bearing.** The draft asserted the job "already
   carries `GITHUB_BASE_REF` + `MERGE_GROUP_BASE_SHA`". Those are **step-scoped** (`ci.yml:302-308`),
   not job-scoped — there is no job-level `env:`. New steps would have inherited nothing, and gate 2's
   hard-fail-on-empty-base would have redded a required context on **every** PR the moment it merged.

Dropping it removes duplicate execution, a divergence surface (the two invocations resolved their
base differently), Risk 2 entirely, and the ADR-032 amendment question — which is what makes this
plan's "no ADR required" claim *true* rather than assumed.

**Also NOT edited:** `infra/github/ruleset-ci-required.tf` and
`scripts/ci-required-ruleset-canonical-required-status-checks.json`. No new required check is minted.

**`check-tc-document-sha.sh` gets a `run_suite` line it never had.** Verified: its only invocation
anywhere is `ci.yml:309`. After Phase 1 the shared lib has two consumers and `bash scripts/test-all.sh scripts`
would exercise only one — so a future edit to the normaliser (Risk 3: silently re-bases every drift
measurement) would be caught in a different job and never locally. Registering it makes the
extraction's parity test live in the same runner as the lib's own suite.

---

## Implementation Phases

Phase order is load-bearing: the contract-changing extraction precedes its consumers, and gate 1
precedes gate 3's count rows (R6).

### Phase 0 — Preconditions (no code)

0.1 Re-verify the drift baseline (220 lines / 8 pairs) — it moves whenever the corpus moves.
0.2 Re-verify marker counts from R7 against the live corpus; any drift updates the declared list.
0.3 Confirm `bash scripts/lint-orphan-test-suites.sh` exits 0 **before** the change (baseline).
0.4 Confirm `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0 (refactor baseline).

### Phase 1 — Shared normaliser extraction *(contract change, ships first)*

1.1 Create `scripts/lib/legal-normalise.sh` with the three functions **byte-identical** to source.
    Verified in-session: they reference only `$1` and close over nothing, so extraction is clean.
1.2 Refactor `check-tc-document-sha.sh` to source it; delete the inline copies.
    **Resolve the source path from `BASH_SOURCE`, not CWD** — use
    `source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/legal-normalise.sh"`.
    A bare `source scripts/lib/legal-normalise.sh` happens to work today because the script is
    already repo-root-CWD-dependent (`CANONICAL_DIR=docs/legal`), but that makes a *silent* CWD
    dependency into a *fatal* one, and this script backs a required check.
1.3 **Prove behaviour preservation:** T&C body SHA identical before/after
    (`bae24228864531665b28c5c6c08bbc35447368734ef1659fc86593ce47181fda`), and the guard still exits 0.
1.4 Add `scripts/lib/legal-normalise.test.sh` (auto-globbed — `test-all.sh` covers `scripts/lib/*.test.sh`).

### Phase 2 — Gate 1: scope-block placement

2.1 **RED first.** Write `scripts/lint-legal-scope-block-placement.test.sh` with failing fixtures.
2.2 Implement added-lines extraction (`git diff --unified=0 "$BASE"...HEAD`), tracking new-file
    line numbers through `@@` hunk headers — the mechanic prototyped in-session.
2.3 Implement the R2 discriminator (locality **AND** negative delimiter), the uncapped R9 regex,
    and `max(last_h2, last_h3)` section resolution handling all four R8 hazards.
2.4 Implement arm (a) claim scan with the R7 case-insensitive marker list + calibration assertion.
2.5 Implement arm (b) flush-left assertion, scoped to scope blocks only.
2.6 Mutation battery: neuter each arm independently; both must red the suite.

### Phase 3 — Gate 2: mirror drift vs baseline

3.1 RED first.
3.2 Implement: for each of the 9 pairs, compute normalised drift at HEAD and at the merge base via
    `git show "$base:$path"`; assert **equality of the ORDERED DIFF**, not of a line count.

**Equality of what, exactly — this is load-bearing, and the first two drafts both got it wrong.**

| Comparison | Content change | Reordering | Lockstep shift | Verdict |
|---|---|---|---|---|
| line **count** | only if count moves | ❌ no | ✅ immune | rejected |
| **sorted** drift set | yes | ❌ no — sorting destroys the signal | ✅ | rejected |
| **full** diff output SHA | yes | ✅ | ❌ **FALSE-FIRES** | **rejected (draft 2)** |
| **`^[<>]`-stripped ordered sequence** | yes | ✅ | ✅ immune | **chosen** |

**Why the full-diff SHA was wrong.** `diff` output carries **absolute position headers**
(`3c3`, `196c197`, `2a3`). Adding an identical paragraph to *both* surfaces — the single most
common correct legal-edit journey — shifts every subsequent header and changes the SHA, redding a
perfectly lockstep edit. Proven in-session on an isolated fixture: two surfaces differing by one
line, then two identical lines prepended to both →

```
before:  3c3   < DIFFER-CANON / > DIFFER-MIRROR
after:   5c5   < DIFFER-CANON / > DIFFER-MIRROR      # same drift, shifted
FULL diff SHA      : 572522643313 -> 9405ccd61acd   CHANGED  => false fire
STRIPPED ^[<>] SHA : eb9f239ec0c0 -> eb9f239ec0c0   SAME     => correct
```

**The primitive:** the **ordered sequence of `^[<>]` lines** (side-tag + content), with `NcN` /
`NaN` / `NdN` position headers and `---` separators stripped. Ordered, so a reorder still changes
it (AC10, the `50f589c2d` §8.1 shape). Position-free, so a lockstep edit does not. This is what
*"normalised drift **sets** are character-for-character identical"* actually meant.

**And the assertion is a RATCHET, not equality.** Strict equality is symmetric: it forbids
*reducing* drift exactly as much as increasing it — so **#7349's own remediation PR would be
red-ed by this gate**, which is the work gate 2 was scoped around. The plan asserted both halves of
that contradiction (Risk 9 said "#7349 will ratchet 220 down"; Non-Goals said "asserts equality").
Corrected assertion, per pair:

- **content:** `driftset(HEAD) ⊆ driftset(base)` — may shrink or stay equal, never grow.
- **order:** the surviving subsequence must preserve base order.

The repo already implements this primitive twice — `scripts/lint-trap-tempfile-ownership.highwater`
and `scripts/lint-diagnosis-claims.sh` (*"the baseline ratchets DOWN only"*). Reuse the idiom.

Per-pair diagnostics measured at HEAD == merge base (all 9 EQUAL) are recorded in Premise
Validation as **diagnostics, not literals to hardcode** — the gate recomputes both sides every run
(Risk 9).
3.3 Base resolution mirrors the proven precedent (`GITHUB_BASE_REF` → `origin/$ref`;
    `MERGE_GROUP_BASE_SHA` on merge_group; **hard-fail on an empty base**, never a vacuous pass).
3.4 Mutation battery, incl. the **ordering** case: same content, different position, equal line
    count — the `50f589c2d` regression shape, which a naive count-only check would miss.

### Phase 4 — Gate 3: obligation-checklist runner

4.1 Define the schema (see below). RED first.
4.2 Implement per-kind execution, `[C][M]` surface expansion into two executions, the advisory
    (non-gating) tier, and `kind: procedure` as an explicit unrunnable-row escape hatch.
4.3 Implement **pre-edit validation**: re-run every `kind: obligation` row against the merge-base
    tree and require it to FAIL. Exempt `preserve` and `procedure`; `deletion` rows match their
    declared `pre_count` instead.
4.4 Mutation battery, incl. the R6 anchor-coverage case.

### Phase 5 — Registration *(same commit as the code it registers)*

5.1 Six `run_suite` lines in `scripts/test-all.sh`.
5.2 Two live steps in the `tc-document-sha-guard` job in `ci.yml`.
5.3 Run `bash scripts/lint-orphan-test-suites.sh` → must exit 0.
5.4 `actionlint` on the edited workflow.
5.5 **Confirm each new suite appears BY NAME in the CI run log** — the AC that #3366 is about.

### Phase 6 — Full-suite exit gate

`bash scripts/test-all.sh scripts` green; `check-tc-document-sha.sh` green; corpus-clean assertions.

---

## Gate 3 — Input format: a sourced shell DSL, **not** YAML

**A YAML schema is unimplementable here, and this was caught at plan-review.** There is no `yq` on
the `test-scripts` job, none on PATH locally, and the repo carries an explicit precedent against
adding one (`scripts/compound-promote.sh:59` — *"Avoids the yq dep."*). A YAML input would force a
hand-rolled bash parser over values that are backslash-escaped regex containing `$C` interpolation
and literal `**` — the three things such a parser gets wrong. The plan's earlier YAML draft also
contradicted its own AC25 tooling list.

The deeper point: the terminal value of every row is **a shell command**. A structured format whose
only job is to hand strings back to the shell they came from is a parser you must write, test, and
maintain for no gain. The checklist is therefore a **sourced bash file** — one function call per
row, with the runner providing the verbs:

```bash
# checklist-<work-stream>.sh — sourced by scripts/obligation-checklist.sh
# Verbs: obligation | deletion | preserve   (id, label, anchor, expect, doc)
# $C and $M are provided by the runner; `surfaces` is a runner-level loop, not a field.

obligation 8  "gdpr §2.2 heading landed"  '^- \*\*Operator-assisted sessions and repository access granted to Jikigai\.\*\*' 1 gdpr-policy.md
obligation 8  "gdpr §2.2 basis pointer"   'The lawful basis for both'                                                        1 gdpr-policy.md

# Deletions carry the PRE count and a survivor assertion. `expect=0` is REFUSED by the runner.
deletion   21 "DPD §4.2 Scope removed"    '^\*\*Scope\.\*\* This section describes'  8 data-protection-disclosure.md \
           --was 9 --anchor-covers 'flush-left only' --survivor-lines-outside 171,203

preserve   11 "original clause survives"  'the original limb text'                                                           1 gdpr-policy.md
```

**Runner-enforced invariants** (each is an AC):
- `obligation` rows must **FAIL** when re-run against the merge-base tree, else the row is vacuous.
- `deletion` **refuses `expect=0`** outright — a shape rejection, not a pass. Deletions assert an
  exact post-count plus a survivor check.
- Every row runs **twice**, once per surface (`$C` then `$M`). A canonical-only pass is a failure.
- `--anchor-covers` is mandatory on `deletion`, and mutation-tested against the population it claims.
- Repo-wide greps exclude the ruling document itself — it quotes every drafted string verbatim.

**Two corrections to the earlier draft, both surfaced by review against the real 37-row table:**

1. **Survivor checks are line-number assertions, not substring sets.** The earlier
   `must_contain: ["§2.1","§2.2","§5.2"]` could never pass — the `**Scope.**` lines do not contain
   the string `§2.1`. The CLO's row 21 operates on `grep -n … | cut -d: -f1`, i.e. **line numbers**.
   Hence `--survivor-lines-outside`.
2. **The two deletion rows have *different* survivor shapes.** Row 21 is a line-set exclusion;
   row 30 is *"the lowest remaining line number must be greater than the `## 3.` heading's line
   number"* — an inequality against a heading. The verb must support both, or it fits one of the
   two rows that exist.

**Dropped from the earlier draft as single-instance over-fitting:** `kind: procedure` (2 rows that
are not greps at all — they belong in the prose table, not a grep runner), the `gates: false`
advisory tier (1 row, one time), `block:` provenance (recorded, never read), and `source` hashing
(guards a failure the greps already catch on an immutable draft-of-record).

---

## Acceptance Criteria

### Pre-merge (PR)

**Gate 1**
- [ ] **AC1** Fires on an added plugin-local scope block inside a section carrying a Web-Platform /
      Controller / Cloud-Execution claim; exit 1 and the message cites `file:line` + the matched marker.
- [ ] **AC2** Fires on a list-indented added scope block; passes the same block flush-left.
- [ ] **AC3** Passes on the current corpus: `bash scripts/lint-legal-scope-block-placement.sh --base origin/main` exits 0 on a branch with no legal-doc edits.
- [ ] **AC4** Scoped to added lines only: reverting the corpus edits returns exit 0 with the same base.
- [ ] **AC5** Zero false positives on main's 6 legitimate indented continuations
      (`data-protection-disclosure.md:106,108,110` + mirror `:115,117,119`).
- [ ] **AC6** Marker calibration is a **floor, not an equality**: every declared marker must match
      **≥ 1** line in the live corpus; zero exits 2 (the gate has gone vacuous).
      *Equality (`== N`) was rejected at plan-review as a scheduled false positive: `acts as Controller`
      and `Cloud Execution` each occur exactly **2** times, so any legitimate edit to those lines
      would red a merge-blocking gate — and those are precisely the PRs this gate rides (#7349 edits
      this corpus next). A floor detects vacuity without blocking the corpus work.*
- [ ] **AC7** Handles a scope block with **no enclosing heading**
      (`data-protection-disclosure.md:22` shape) without erroring.
- [ ] **AC8** Replaying the real 7347 diff yields exactly the 9 canonical section-claim sites and
      3 canonical indentation sites enumerated in "Design validated in-session", and `acceptable-use-policy.md:268` passes.
- [ ] **AC8b** Hunk-header parsing covers **all four** shapes. Measured on the real 7347 legal diff:
      `@@ -N,N +N,N @@` ×29, `@@ -N +N @@` ×7, `@@ -N +N,N @@` ×1, `@@ -N,N +N @@` ×1 — the
      single-line forms omit the comma and a parser assuming `+c,d` mis-numbers every line in them.
      Unit-tested against all four literal shapes.

**Gate 2**
- [ ] **AC9** Fires when one surface is edited without the other.
- [ ] **AC10** Fires when the same content lands in a different **position** on the two surfaces at
      equal line count (the `50f589c2d` shape).
- [ ] **AC11** Passes at equal-to-baseline drift: exit 0 on a branch that does not touch the corpus.
      **No drift figure appears in the gate or in this AC** — both sides are recomputed every run
      (Risk 9). The earlier draft hardcoded "220 lines across 8 pairs", contradicting its own Risk 9;
      that number is a diagnostic recorded in Premise Validation, not an assertion.
- [ ] **AC12** Hard-fails (exit 2) on an unresolvable/empty merge base — never a vacuous 0.
- [ ] **AC13** Exactly one normaliser exists:
      `grep -rnE '^normalize_canonical\(\)' scripts/ apps/ | wc -l` returns **1**, and that one hit is
      `scripts/lib/legal-normalise.sh`.
      *(Anchored on the definition syntax and scoped to code dirs by explicit path — NOT
      `--include='*.sh' .`. Measured in-session: that form returns **2**, because it matches this plan
      file's own AC text. `grep` is a shell **function shim** in this environment
      (`.claude/hooks/grep-rewrite.sh`), so `--include` does not filter as GNU grep would. Two defects
      in one line: self-reference and an unreliable filter — `cq-assert-anchor-not-bare-token`.)*
- [ ] **AC14** `check-tc-document-sha.sh` still exits 0, and the T&C body SHA is unchanged at
      `bae24228864531665b28c5c6c08bbc35447368734ef1659fc86593ce47181fda`.
- [ ] **AC14b** The refactor preserves `^EXPECTED_COUNT=9` at line-start in
      `check-tc-document-sha.sh`. `apps/web-platform/test/legal-doc-shas-guard.test.ts` parses the
      script's **text** with `/^EXPECTED_COUNT=(\d+)\b/m` and asserts it equals
      `|LEGAL_DOC_SHAS| + 1` — a text-coupled guard that a reflow would break invisibly to `tsc`.
      Verify with `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-shas-guard.test.ts`
      (grep the log for `FAIL`/`× ` — a background runner has reported exit 0 with a real failure).
- [ ] **AC14c** All 9 canonical docs still have a mirror and vice versa (measured today: 9/9
      symmetric). Gate 2 exits **2**, not 0, on an unpaired doc — an unpaired doc has no baseline to
      compare against and must never read as "no drift".

**Gate 3**
- [ ] **AC15** Fires on a binding item whose positive check misses; reports the row `id` next to hit/miss.
- [ ] **AC16** Rejects a `kind: deletion` row expressed as `expect: 0` (shape rejection, not a pass).
- [ ] **AC17** Rejects an `obligation` row that PASSES on the merge-base tree (vacuous-row detection).
- [ ] **AC18** A `surfaces: [C, M]` row runs twice; a canonical-only edit fails.
- [ ] **AC19** `gates: false` rows report advisory and do not affect exit code.
- [ ] **AC20** A count row whose `anchor_covers` excludes indented instances is detected when an
      indented instance exists (R6 / row-21 shape).

**Mutation-proving**
- [ ] **AC21** Each of the 6 gate arms neutered independently → the registering suite reds. Mutations
      land in a `mktemp` sandbox, never in tracked files, and each is proven to have landed
      (`cmp -s` against pristine) before its SURVIVED/KILLED verdict is trusted.

**Registration**
- [ ] **AC22** `bash scripts/lint-orphan-test-suites.sh` exits 0 (auto-enforces all six `run_suite` lines).
- [ ] **AC23** All three suites appear **by name** in the CI run log:
      `gh run view --log --job "test-scripts" | grep -c -E 'lint-legal-scope-block-placement|legal-mirror-drift-baseline|obligation-checklist'` ≥ 3.
- [ ] **AC24** The gate-1 and gate-2 live steps appear by name in the `tc-document-sha-guard` run log.
- [ ] **AC25** Runner tooling verified: every external command the suites shell out to
      (`git`, `grep`, `awk`, `sed`, `diff`, `sha256sum`, `mktemp`) is present in the job body with no
      new install step.
- [ ] **AC26** `bash scripts/test-all.sh scripts` green end-to-end.
- [ ] **AC27** `actionlint` clean on `.github/workflows/ci.yml`.

**Hygiene**
- [ ] **AC28** Every `knowledge-base/` path cited in this plan resolves:
      `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'` → empty.
      *(The three #7372 context files are deliberately cited as `git show 2dd397542:<path>`, not as
      working-tree paths — they do not exist on main. See Premise Validation.)*
- [ ] **AC29** PR body states the corrected attribution — **4 of 10 P1s** (P1-4, P1-5 via gate 1;
      P1-6, P1-9 via gate 3), not the issue's 6–7 claim and not this plan's own first-draft 3 — plus
      the caveat that **gate 3 detects nothing**: it executes a checklist a human authored, so its
      share is a property of whether a row was written, not of the gate (R13).
      *(Not machine-checkable — this is a PR-body copy instruction, tracked on the PR checklist.)*

### Post-merge (operator)

None. Every step above is automated in CI. No terraform apply, no vendor dashboard, no SSH.

---

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal

**Status:** reviewed (plan-time assessment; CLO agent to be spawned at plan-review)
**Assessment:** The gates operate *over* the legal corpus but change no published legal text — no
document byte moves in this PR. The legal-relevant risk is second-order and runs in both directions:
a fail-open gate licenses a future false publication, and a false-firing gate blocks legitimate
legal remediation (notably #7349, which is queued against this same corpus). Gate 1's discriminator
was derived from the corpus rather than from memory precisely because a hardcoded marker list would
have rejected the motivating change (R2). **The CLO is the authority on whether a scope block is
correctly placed; this gate only enforces the two mechanical preconditions the CLO already ruled on.**
It must not be represented as adjudicating scope correctness.

### Engineering

**Status:** reviewed
**Assessment:** The chosen registration path makes the issue's headline failure mode structurally
impossible (R5). The two real engineering risks are (a) riding existing required contexts, which
widens what `tc-document-sha-guard` and `test` mean without a terraform change, and (b) refactoring
a required-check script — mitigated by a byte-identical extraction with a proven-identical output
SHA. Phase ordering is load-bearing twice over (Phase 1 before its consumers; gate 1 before gate 3's
count rows).

### Product/UX Gate

**Skipped — Product NONE.** Mechanical UI-surface override checked against `## Files to Create`
and `## Files to Edit`: zero paths match `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any UI-surface glob. All paths are `scripts/`, `.github/workflows/`, and one
`apps/web-platform/scripts/` shell file. No user-facing surface.

---

## GDPR / Compliance Gate

**Assessed, not triggered.** The canonical regulated-surface regex (schemas, migrations, auth flows,
API routes, `.sql`) matches none of the touched paths. The four expansion triggers:

- (a) LLM/external-API processing of operator data — **no**; bash + git, no network egress.
- (b) `single-user incident` threshold declared — **yes**, this one fires.
- (c) new cron/workflow reading `learnings/` or `specs/` — **no**; gate 3 reads a checklist file
  passed as an argument, in-process, in CI. No new cron; no cross-controller data movement.
- (d) new artifact distribution surface — **no**.

Trigger (b) alone routes this to `user-impact-reviewer` at review time (already scheduled by the
threshold) rather than to a full gdpr-gate pass, since no personal data is processed by anything
this PR adds. **Flagged for plan-review to confirm** — the conservative reading of (b) is that
gdpr-gate runs regardless, and it is cheap.

---

## Open Code-Review Overlap

Queried 64 open `code-review` issues against every path in `## Files to Create` / `## Files to Edit`
(`scripts/test-all.sh`, `apps/web-platform/scripts/check-tc-document-sha.sh`, `.github/workflows/ci.yml`,
`docs/legal/`, `scripts/lint-orphan-test-suites.sh`, `.github/scripts/test/run-all.sh`).

**None.** No open scope-out names any file this plan touches.

---

## Risks & Sharp Edges

1. **Gate 1 will red PR #7372 on merge.** 9 canonical section-claim sites + 3 indentation sites are
   live on that branch. Intended, but state it in the PR body — a sibling PR going red without
   warning reads as a false positive and invites the gate being disabled.

2. **Riding existing required contexts widens their meaning.** A gate-1 failure surfaces as
   `tc-document-sha-guard` red. The trade is deliberate: minting a new required context needs a
   paired terraform apply on `infra/github/ruleset-ci-required.tf`, which is out of scope. Document
   it in both the job comment and the script header, or the next person debugging a red
   `tc-document-sha-guard` will look only at SHA pinning.

3. **Refactoring a required-check script.** Mitigated by byte-identical extraction + the proven
   T&C SHA (AC14). Do not "tidy" the functions while moving them — a normalisation change silently
   re-bases every drift measurement, including gate 2's baseline.

4. **`--base` default must be `origin/main`, never `origin/<branch>`.** Once the branch is pushed,
   `origin/<branch>...HEAD` returns zero files and the gate never fires — the exact silent-pass
   shape this work exists to eliminate.

5. **`set -e` inside functions leaks to caller scope.** Use `|| true` on greps expected to miss.
   A `grep -c` returning 0 matches exits 1 and will abort a `set -e` script mid-scan, producing a
   partial scan that exits 0.

6. **Do not build the added-line set with `grep -v` before `grep -n`.** Line-number order is
   load-bearing: re-indexing against a filtered stream mis-cites every offender. Extract line
   numbers from the `@@` hunk headers, as prototyped.

7. **Gate 3's repo-wide greps match the ruling document itself**, which quotes every drafted string
   verbatim. Exclude the source file, or every obligation row passes on the strength of its own
   provenance record.

8. **`MIN_SUITES=10` in `.github/scripts/test/run-all.sh`** must be raised if any suite is added
   there. This plan puts suites in `scripts/` instead, so the floor is untouched — but if that
   choice is revisited at review, the floor moves with it.

9. **The drift baseline moves whenever the corpus moves.** #7349 will ratchet 220 down. Gate 2
   asserts *equality with the merge base*, computed per-run — never a hardcoded number. No literal
   drift count may appear in the gate.

10. **Anchor coverage is a claim, not a given (R6).** The CLO's own row 21 counted a subset while
    reading as a total. Every count row declares `anchor_covers` and is mutation-tested against the
    population it claims to cover.

11. **`grep` is a shell function shim in the agent environment** (`.claude/hooks/grep-rewrite.sh`
    redefines it to neutralise a ugrep shim). Measured consequence: `--include='*.sh'` does **not**
    filter as GNU grep would — `grep -rn 'normalize_canonical()' --include='*.sh' .` returned a `.md`
    file. Any AC or gate assertion must scope by **explicit directory arguments**, not `--include`,
    and must anchor on definition syntax. This bit AC13 in this very plan; it will bite the gate
    scripts too if they rely on `--include`. CI runs real GNU grep, so the two environments disagree
    — which is worse than either being wrong consistently.

12. **The functions extract cleanly** — verified: `normalize_canonical` / `normalize_plugin` /
    `collapse` reference only `$1`, closing over no top-level variable. If that ever changes, the
    extraction stops being behaviour-preserving silently.

---

## Non-Goals

- **Resyncing the 220 lines of pre-existing drift.** Tracked on #7349. Gate 2 asserts equality
  precisely so this stays out of scope; a zero-assertion would be unshippable and disabled within a day.
- **Adjudicating whether a scope block is legally correct.** Gate 1 enforces two mechanical
  preconditions. Scope correctness is a CLO decision.
- **Minting new required status checks.** Deliberate; see Risk 2.
- **Generalising the gates beyond `docs/legal/` + its mirror.** Gate 3's runner is corpus-agnostic
  by construction, but only the legal corpus is wired in this PR.
- **Fixing PR #7372's 12 sites.** That is #7372's work; this PR builds the detector.

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Put suites in `.github/scripts/test/` (auto-glob, required) | Auto-glob is attractive, but the job checks out at **depth 1** and is contractually **bash-only**; gate 2 needs merge-base history. Splitting suites across two runners doubles the registration surface — the thing most likely to be skipped. |
| Hardcode the marker list from the issue text | R2 — `**Scope.**` and `**What this covers.**` don't exist on main, so a main-derived list rejects the motivating change and a memory-derived list is exactly what the issue forbids. |
| Assert mirror drift == 0 | Unshippable: 220 lines of legitimate pre-existing drift. Would be disabled within a day. |
| Write a second normaliser for gate 2 | Explicitly forbidden by the issue, and correctly — a second normaliser is a second thing to drift. Extraction + sourcing gives one implementation, two consumers. |
| Markdown table as gate 3's input | The CLO's own table already escapes embedded pipes and carries conjunctions/comparators/exemptions in prose. Not tabular data. |
| Extend `check-tc-document-sha.sh` with gate 2 inline | Bloats a load-bearing required guard and couples two independent failure modes into one exit code. Sibling script + shared lib keeps the diagnostics separable. |

---

## Plan Review Revisions (R1–R24)

Five-agent escalated panel (`single-user incident` threshold) + CLO. **The CLO returned
NOT SAFE TO IMPLEMENT AS WRITTEN with 13 binding amendments; gate 1 was respecified.** Every
finding below was independently verified against the repo before acceptance. Revisions are folded
into the sections above; this log records what changed and why.

### Blocking — gate 1 was inverted (CLO A1–A5)

- **R1 — Arm (a) respecified on REFERENT, not marker proximity.** As drafted it fired on **6 sites
  the CLO expressly ruled correct**. Root cause: I prototyped against the 7347 **remote** tip
  (`8b871eb4b`), which is **12 commits behind** the ruled-final tree (`2dd397542`) — validating the
  gate against the pre-remediation state that motivated the fix, never against the post-remediation
  state it must not disturb. Corrected: fire only on `This section` referents; exclude
  `The paragraph above` (the ruling's prescribed remedy form). **Verified: 2 hits, 0 false positives.**
- **R2 — Negative delimiter removed from the classifier (A2).** As a classifier it was an escape
  hatch: deleting `must not be read as covering it` blinded the gate while the false affirmative
  stayed published. Now classified on locality + referent; the delimiter is asserted separately.
- **R3 — Flush-left absolute withdrawn (A5).** Restated as *attachment must match declared referent*.
  Limb-referent riders are legitimately indented — DPD §2.3's newly-opened `(a)`–`(ad)` list is
  exactly where one belongs, and forcing it flush-left re-scopes it to the whole enumeration.
- **R4 — AC8 rewritten (A3).** It made the false-positive set the acceptance criterion.
- **R5 — Risk 1 re-derived (A4).** "Will red PR #7372" was normalised as intended; under the old
  spec the only way to green it was to edit against a standing ruling.

### Blocking — gate 2 was unbuildable as specified

- **R6 — Drift primitive defined (spec-flow P0-3).** Full-diff SHA carries absolute position headers
  and false-fires on lockstep edits. Now the `^[<>]`-stripped ordered sequence. Proven in-session.
- **R7 — Equality → subset ratchet (CLO A6 + spec-flow P0-2).** Equality is symmetric and would red
  **#7349's own remediation PR**. Now `driftset(HEAD) ⊆ driftset(base)` with order preserved.
- **R8 — Base is the merge-base SHA, not a tip ref (spec-flow P1-3).** `origin/$GITHUB_BASE_REF` is
  a tip; an un-rebased branch false-fires when main advances. Resolve
  `git merge-base HEAD "$base_ref"` first. Precedent: `scripts/lint-rule-bodies.py`.
- **R9 — Pair lifecycle enumerated (Kieran P1-2, spec-flow P2-1/2/3/4).** Four cases: both present →
  ratchet; absent at base → assert drift 0 (no day-one grandfathering); one-sided delete → fail;
  unpaired → exit 2. Enumerate the **union** of base and HEAD globs. Renames excluded from gate 1's
  added-line set (a rename presents as add-only and would fire on every pre-existing block).

### Blocking — the registration thesis was half-true

- **R10 — `REQUIRED_RUNNERS` extended (Kieran P1-3, spec-flow P1-5, arch).** `lint-orphan-test-suites.sh`
  globs `scripts/*.test.sh` only, so it enforced the **unit** lines and nothing enforced the **live**
  lines — the half that actually gates the corpus. AC22's "auto-enforces all six" was false.
- **R11 — `.github/workflows/ci.yml` edit dropped** (simplicity CUT 4 + arch P1-1 + Kieran P0-2).
  Buys nothing (the gates already ride required `test`), costs the name, and rested on a false claim
  that the job carries job-level `env:` (it is **step**-scoped, `ci.yml:302-308`). Removes duplicate
  execution, the base-divergence surface, Risk 2, and the ADR-032 amendment question.
- **R12 — `check-tc-document-sha.sh` registered** (arch P1-3). Its only invocation was `ci.yml:309`;
  after Phase 1 the shared lib would have had an unexercised consumer.

### Substantive corrections

- **R13 — Attribution is 4 of 10, not 3** (CLO A10). P1-6 is a pure grep (checklist row 35), P1-8 was
  missing, and a P2 had been substituted for a P1 *inside the table correcting a mis-attribution*.
  Added: **gate 3 detects nothing** — it executes a checklist a human authors; its value is making an
  authored obligation un-droppable, not finding obligations.
- **R14 — The drift is not "legitimate"** (CLO A7). It is asymmetric and directional: the **published
  page under-discloses relative to the record** — omitting collected-data categories, a named
  third-country recipient (Anthropic, US), lawful bases, a retention period, and an Art. 14 posture.
  "Legitimate" struck; the gate-2 header must name what is frozen.
- **R15 — #7349 needs a date** (CLO A8, stands independently of this PR). A knowingly-retained
  published-notice under-disclosure behind an undated P2 is not a managed risk; actual knowledge
  bears on Art. 83(2)(b)/(c). Raise to P1 with a dated target, cite it in the gate-2 header, and
  record the specific omissions on #7349 + `compliance-posture.md`.
- **R16 — `anchor_covers` becomes a measured identity** (CLO A9). A free-text field is an unvalidated
  assertion by the same author in the same artifact — row 21's defect relocated. Now: compute the
  anchored count **and** an over-broad superset count; a silent inequality exits 1 **on the live
  corpus every run**, not only under mutation.
- **R17 — R6's "gate 1 is a precondition for gate 3" deleted** (arch P1-4 + CLO). Both gates go live
  in the same merge commit, so there is no window; and under R3 indented blocks remain legitimate, so
  the structural argument fails outright. Leaving it in was an active hazard — it gave a future author
  a documented reason to omit `anchor_covers`. The measured superset (R16) is the sole soundness
  mechanism.
- **R18 — Gate 3 input is a sourced shell DSL, not YAML** (simplicity CUT 2 + arch P0-2). **No `yq`
  anywhere**; `scripts/compound-promote.sh:59` records "Avoids the yq dep." The draft contradicted its
  own AC25 and stacked three escape layers. Also: `survivors.must_contain` could never pass (the
  `**Scope.**` lines do not contain `§2.1` — the CLO's check is on **line numbers**), and it encoded
  neither of the two real deletion rows faithfully.
- **R19 — Gate 3 lifecycle defined** (spec-flow P1-10). The pre-edit-must-fail rule inverts after the
  PR that lands the obligation: the row then passes on the merge base and reds every later PR. Scope
  discovery to the branch's spec dir and archive on merge.
- **R20 — Discriminator delimiter broadened** (Kieran P1-4). Its main-branch evidence was a sample of
  **one** (`privacy-policy.md:269` + its own mirror); `data-protection-disclosure.md:61` does not match.
- **R21 — Stale figures corrected** (Kieran). `app.soleur.ai` is **140**, not 202; R8's
  `gdpr-policy.md:350` hazard example was wrong (that site is under `### 7.1`, and line 350 is a
  bullet); AC7's `data-protection-disclosure.md:22` is a **7347-branch** coordinate, plain prose on
  main. Hazard sites are re-derived in Phase 0 and recorded as **content anchors**.
- **R22 — Broken AC commands fixed** (Kieran P0-1/P0-3, self-found). `gh run view --job` takes a
  **numeric job ID**, not a name (404s on a name); `grep -c -E 'a|b|c'` counts *lines*, not distinct
  suites — three lines naming one suite satisfied "≥ 3". Now resolve the job ID, then
  `grep -oE … | sort -u | wc -l`. Hunk-header contract pinned for all four shapes incl. the
  count-omitted single-line form `@@ -2,0 +3 @@`, `+c,0` skip, path keyed off `+++ b/` (renames),
  and `+++ /dev/null` skip. AC28 made fail-closed (it exited 0 while printing BROKEN).

### Deferred / recorded, not applied

- **R23 — Escape hatch for gate 1** (spec-flow P1-1). **⚠ The pragma shape below is SUPERSEDED by
  D1** — the waiver is an out-of-band, CODEOWNERS-owned ack ledger, not an in-document comment.
  Kept for the reasoning, which still holds. Real gap: no waiver, and the natural remedies
  (delete the block, or reword the legal section to drop a marker) are both worse than the defect.
  R1's referent respecification removes the *known* false positives, which lowers urgency — but the
  hatch is still required before Phase 2 code, because it changes the parser (it must read a
  preceding pragma). Shape, following `lint-rule-bodies.py` + `lint-orphan-test-suites.sh`:
  `<!-- legal-scope-block: ok #NNNN <ruling-path> <reason> -->`, with a 1-line lookback, mandatory
  issue **and** ruling citation, and a reasonless pragma being itself exit 1. **Keeps the CLO as the
  authority** rather than a lint.
- **R24 — Gate 3's producer** (spec-flow P0-1, simplicity CUT 1). No actor, no path, no CI trigger,
  no instance file — and AC23 would go green off the *unit-suite label* with zero real rows consumed.
  Simplicity recommends deferring gate 3 to its own issue entirely. **This changes the operator's
  stated scope, so it is recorded as a User-Challenge in
  `knowledge-base/project/specs/feat-one-shot-7387-legal-corpus-write-time-gates/decision-challenges.md`
  rather than applied unilaterally.** If gate 3 ships here it needs: a declared home
  (`knowledge-base/project/specs/<branch>/obligation-checklist.sh`, matching the ~20 existing
  `migration-checklist.md` siblings), a named producer skill, a glob-driven CI step, an
  absence-detection predicate, and an AC requiring ≥1 **real committed** checklist executed.

### Runtime-representation amendments (CLO A11–A13) — all binding

- **R25 — Non-adjudication disclaimer moves into runtime output, including the PASS line.** A gate
  that prints nothing on success teaches "green means the legal text is fine." Gate 1's pass message
  must name what it did **not** check and cite the CLO as the authority.
- **R26 — Gate 3's pass output must read necessary-not-sufficient.** A green `obligation-checklist`
  satisfies one of three conjuncts of CLO discharge; the runner must name the other two (mirror +
  `LEGAL_DOC_SHAS` repin after the final prose byte; the CLO attestation audit) and state that the
  CLO, not the runner, is the attestation authority.
- **R27 — Ruling-hash mismatch exits 1**, not warns, and routes to the CLO: a reworded drafted string
  means the ruling moved and the rows are no longer its contract.

### Environment / correctness notes folded in

- **R28 — `LC_ALL=C` pinned in the shared normaliser** and CRLF handled (spec-flow P2-5/P2-6). Both
  change the drift hash; both must be settled **before** Phase 1.1, since AC14's byte-identical proof
  (`bae24228…`) has to be re-run against them rather than discovered mid-phase. No root `.gitattributes`
  exists.
- **R29 — Bot-PR synthetic-check derivation recorded** (arch P2-2, spec-flow P0-4). `required-checks.txt`
  fabricates green for `test` and `tc-document-sha-guard` on bot PRs. Derived per ADR-139 (which
  mandates re-derivation, never inheritance): `ALLOWED_PATHS` is `weakness-digest.md` +
  `rule-metrics.json`, which does **not** intersect `docs/legal/` or the mirror — so the gates are
  **sound by unreachability**. Recorded as a finding and repeated in each gate's script header.
- **R30 — Min-cardinality floor split by gate class** (spec-flow P1-6). A floor on *added lines* would
  exit 2 on nearly every PR. Gate 1's floor is on corpus files readable; gates 2/3 keep a
  corpus-enumeration floor derived from the glob, not the literal `9`.
- **R31 — AC3 replaced** (spec-flow P1-7). With no legal-doc edits the added-line set is empty, so it
  asserted nothing. Replaced with a whole-corpus-as-added run reporting exactly the known main-branch
  scope blocks.

---

## Deepen-Plan Research Insights

Deepened 2026-08-10, after the five-agent panel + CLO review. All mandatory halts pass
(4.6 User-Brand Impact · 4.7 Observability · 4.8 PAT-shaped variable). 4.9 UI-wireframe and
4.10 Encryption-posture do not trigger: the only UI-glob mention in the plan is the Domain Review's
*negative* assertion, and no path matches `.tf` / `supabase/migrations/*.sql` / `cloud-init*.yml` /
`docker-compose*.yml`. Citation sweeps clean: 3 cited AGENTS rule IDs all **active**, none retired;
all 5 cited issue/PR numbers resolve with the states the plan claims.

### D1 — The waiver must NOT live in the legal document *(supersedes this section's first draft)*

My first deepen pass measured that the normaliser does not strip HTML comments, concluded the
`<!-- legal-scope-block: ok … -->` pragma must go on **both** surfaces, and called that a happy
result. **That conclusion was wrong**, and the precedent research shows why: it treated a
mirror-drift problem as the whole problem. There are **three** hashes over these files, and an
inline pragma hits all three.

**Measured, all six verified in-session:**

1. **The SHA pin is over the RAW file, with no normalisation at all** —
   `check-tc-document-sha.sh:234`: `canonical_sha=$(sha256sum "$canonical_path" …)`. Proof: adding
   one comment line to `privacy-policy.md` moves the raw SHA `cc4fee452bbf0197` →
   `66e2029408b880db`, forcing a `LEGAL_DOC_SHAS` re-pin. There is no normalisation layer to teach.
2. **For T&C the pin is legal evidence.** `TC_DOCUMENT_SHA` is written as `p_doc_sha` into the WORM
   consent ledger (`app/api/accept-terms/route.ts:96`). A waiver comment would be indistinguishable,
   in the consent record, from a substantive terms edit.
3. **The CLA is worse.** `cla-evidence.yml:126` hashes `git show <base>:docs/legal/individual-cla.md`
   into R2 Object-Lock evidence. A comment mutates signed-CLA evidence hashes.
4. **Authority cannot be bound to a person by an inline pragma.** The requirement is that the *CLO*,
   not the engineer, authorises. CODEOWNERS owns **files, not line ranges** — a pragma inside
   `privacy-policy.md` inherits that file's ownership, so the engineer editing the clause authors
   their own waiver. That defeats the primary requirement outright. The working precedent is
   `.github/CODEOWNERS:56` → `/.claude/rule-weakening-acks.txt @deruelle`.
5. **The repo has already rejected in-artifact override markers, in writing.**
   `.claude/hooks/ship-net-issue-flow-gate.sh`: reading the marker from committed files *"would let
   the gate find its own override marker inside committed evidence/spec files and silently
   self-override — invisible to the acceptance criteria."*
6. **A pragma has no content binding.** It waives the line it sits above, *whatever that line later
   becomes* — the CLO ratifies clause X and clause Y is swapped underneath with no gate signal.

**Corrected design: an out-of-band, hash-bound, CODEOWNERS-owned ack ledger** at
`.claude/legal-scope-block-acks.txt`, leaving `docs/legal/*.md` byte-identical so all three hashes,
the mirror drift, and the consent/CLA evidence records are untouched. Fields:

```
<doc-path>#<anchor>|<sha256-of-normalised-block>|<date>|#NNNN|<ruling-doc-path>|<expires_on>|<reason>
```

Mechanics lifted from established idioms rather than invented:
- **Content binding + replay protection** — `lint-rule-bodies.py`. The key is
  `sha256(normalised block)`, and the ack must be **newly added in this diff**
  (`new_acks(rid) = head_acks - base_acks`, base read via `git show <merge-base>:<ackfile>`), so
  reverting to a previously-acked form cannot pass on a stale historical ack. These are the only
  two properties that make an approval bind to *specific words*.
- **Fail-closed parse** — a line short of the field count or with an empty reason is *dropped*, so a
  malformed waiver cannot satisfy the gate; the block still fires.
- **Anchored issue regex** `^#[0-9]+$` — `lint-encryption-posture.py`'s `TRACKING_ISSUE_RE`, not the
  unanchored `#[0-9]+` of `lint-orphan-test-suites.sh`.
- **`expires_on` with offline date arithmetic** + an `--today` override for hermetic tests. An
  expired waiver becomes a **red build**, not silent permanence — the right default for a legal
  exception.
- **Fail CLOSED if the cited `<ruling-doc-path>` does not resolve** — a waiver may not cite a ruling
  that does not exist.
- **WORM header** (`NEVER edit or remove an existing line`) + the CODEOWNERS entry pointing at the
  CLO. That entry is the line that satisfies the authority requirement; everything else is
  bookkeeping around it.

**What survives from the first draft:** the measurement that HTML comments are **5 of the 220 drift
lines** and asymmetric across four pairs (AUP 3v2, DPD 1v0, gdpr 14v12, privacy 14v13) — a small,
previously uncharacterised slice of what R14 says the freeze hides. And the finding that stripping
comments in the normaliser is **not** a free cleanup: it moves the T&C body SHA
`bae2422886453166` → `d937ff6cef13df09` and the whole baseline 220 → 215.

| doc | drift | drift w/o comments | canonical `^<!--` | mirror `^<!--` |
|---|---|---|---|---|
| acceptable-use-policy | 18 | 17 | 3 | 2 |
| data-protection-disclosure | 56 | 55 | 1 | **0** |
| gdpr-policy | 63 | 61 | 14 | 12 |
| privacy-policy | 58 | 57 | 14 | 13 |
| terms-and-conditions | 0 | 0 | 2 | 2 |
| **total** | **220** | **215** | | |

**One trap the ledger does not remove.** Body-equivalence is currently armed for
`terms-and-conditions` **only** (`BODY_EQUIVALENCE_DOCS`), so a comment in `privacy-policy.md` does
*not* trip drift today and would start tripping it the moment the remaining eight docs are activated
— which is exactly #7349's deferred remediation. Gate 2 closes that gap for all nine pairs, which is
an additional argument for it.

### D2 — Precedent diff (Phase 4.4): both novel mechanisms have in-repo idioms

The plan prescribes two pattern-bound behaviors with sibling precedent, so per Phase 4.4 they must
be diffed rather than invented:

- **The ratchet (R7) — two precedents, and I initially named the wrong pair.**
  - *Scalar high-water, committed file:* `scripts/lint-diagnosis-claims.sh` (*"Do NOT raise the
    baseline to make this pass. The baseline ratchets DOWN only"*; missing baseline → **exit 2**;
    plus a `MIN_FILES` anti-vacuity floor — *"A clean result from a walk that found nothing is not a
    clean result"*) and `scripts/lint-trap-tempfile-ownership.highwater`. Both compare a **count**.
  - *Per-item set, committed file:* `scripts/lint-shell-capture-exit.baseline.txt` +
    `.py`. Its `fingerprint()` is the shape to copy — `f"{rel}\t{code}\t{' '.join(text.split())}"`,
    **deliberately not line-numbered**, with the reasoning stated in-file: *"Line numbers churn on
    every edit above a finding, which would make the baseline produce spurious 'new' findings for
    untouched code."* That is an independent derivation of R6's position-header strip.
  - **The actual merge-base precedent is `scripts/lint-rule-bodies.py`** — which I did not name in
    the first draft. It builds its base-side map with `_git_show(root, base_commit, rel)`, resolves
    the base via `rev-parse --verify --quiet "<ref>^{commit}"`, and **fails closed** on an
    unresolvable base (`::error::… (fail-closed). Pass \`git merge-base origin/main HEAD\`` → exit 2).
    Copy it, including its CI recipe: `fetch-depth: 0` + `git fetch --no-tags --quiet origin main` +
    `BASE="$(git merge-base origin/main HEAD)"`, and register the local self-test with `--base HEAD`
    so the no-op path is asserted green.

  **Three things that precedent gives us free, and one trap:**
  1. **No artifact to launder.** Gate 2's baseline is recomputed, so the "do not regenerate the
     baseline" guard all three committed-file gates need does not apply. Say so in the script header
     — a reviewer who knows the other gates will go looking for the missing guard.
  2. **The union-of-scopes anti-hack.** `lint-rule-bodies.py` parses both sides with the **union** of
     base-side and head-side section names, so a PR that narrows the scope while degrading an item
     inside the removed scope cannot hide it. This is exactly R9's "union of base+HEAD globs" —
     independently derived, now with a precedent to copy.
  3. **Fail-closed is a choice, and the repo is split.** `lint-infra-no-human-steps.py` and
     `lint-credential-path-literals.py` fail **closed**; `lint-trap-tempfile-ownership.py` and
     `.claude/hooks/ship-runbook-ssh-gate.sh` fail **open**. Gate 2 is blocking → closed.
  4. **⚠ The trap — SE-1, recorded in `lint-rule-bodies.py` itself.** When the base predates a rename
     of the scanned corpus, `git show <base>:<path>` resolves to nothing, **the base map is empty,
     and the change-detection arm goes blind for the entire branch** — not just the renaming commit.
     For a ⊆-ratchet an empty base is the *unsafe* direction (everything reads as new → red, which is
     loud), but a **head-side rename reads as a shrink and silently hides real drift**. This is the
     same hazard R9 flags for renames; their mitigation was a committed manifest as a
     git-history-free second oracle for the deletion direction. Phase 3.7 must decide explicitly
     whether gate 2 needs that second oracle or whether `EXPECTED_COUNT` already serves as one.
- **The waiver (R23) — resolved in D1 as an ack ledger.** Four in-repo idioms exist: an inline
  pragma with mandatory reason
  (`lint-trap-tempfile-ownership.py`), a hash-bound ack file with replay protection
  (`lint-rule-bodies.py` + `.claude/rule-weakening-acks.txt`), an in-file allowlist
  (`check-adr-ordinals.sh`), and a reason-plus-issue exclusion array that fails closed
  (`lint-orphan-test-suites.sh`). **The selection criterion is authority, not ergonomics:** the CLO,
  not the engineer, must authorise a legal-scope exception. That rules out **every in-document
  form**, because CODEOWNERS owns files rather than line ranges — see D1. The surviving idiom is
  the hash-bound ack ledger (`lint-rule-bodies.py`) hybridised with `expires_on`
  (`lint-encryption-posture.py`), owned by the CLO in CODEOWNERS.

### D3 — Residual risk the plan should not pretend it closed

Gate 1 cannot detect the two laundering paths named in its own spec (delete the delimiter; reword
the section's markers). D1's dual-surface waiver and R16's measured superset close the *mechanical*
holes, but the semantic ones stay open by construction. This is the strongest argument for R25's
requirement that the **pass** message name what was not checked — the gate's honest claim is
"no section-referent scope block was added into a marker-bearing section", never "the legal text is
correct."

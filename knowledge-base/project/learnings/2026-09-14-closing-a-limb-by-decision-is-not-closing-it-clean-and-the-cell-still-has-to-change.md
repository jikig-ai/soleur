---
module: legal-corpus
date: 2026-09-14
problem_type: logic_error
component: documentation
symptoms:
  - "A register correction said 'the cell now reads' while the cell still read the old text"
  - "Dropping 'provisional' flipped an 'inconclusive?' cell to 'No' on a limb that was never measured"
  - "Three prose claims in a determination addendum were stronger than the record they summarised"
  - "A qualified verdict label extended a runbook's 'three ways, and only three' enum"
root_cause: missing_workflow_step
resolution_type: documentation_update
severity: high
tags: [legal-corpus, art-33, determination, breach-register, in-cell-correction, review, clo, operator-veto, instruments]
issues: [7945, 7797, 7791, 7349]
pr: 8153
synced_to: [clo]
---

# Closing a limb by decision is not closing it clean — and the cell still has to change

## Problem

`/soleur:go #7945` routed to the `clo` agent via the legal-threshold row. The issue
asked to escalate the Art. 33 confidentiality/read limb of the #7797 personal-token
determination to Sentry support — the last untried instrument after the token last-used
field turned out not to exist and the org audit log answered only the write limb.

The CLO prepared the escalation (channel, verbatim request, disclosure check, both
"Done when" branches pre-decided) and recommended sending. The operator was asked to
authorise the external contact and **declined**: close the read limb now as
INCONCLUSIVE, vendor support deliberately not attempted.

That produces a third outcome the determination's own re-evaluation triggers had no
branch for (BREACH → fresh 72h; CLEAN → drop "provisional"). The CLO wrote it as
`INCONCLUSIVE-BY-DECISION`, dropped `provisional` → FINAL, embedded the un-sent draft,
and recorded a re-opener. The 4-seat review panel then returned **1 P1 / 6 P2 / 9 P3**,
all in the record's *verification and corrections*, none in the legal call itself.

## What was wrong, by structural cause

Eleven of sixteen findings reduce to two causes.

### 1. Corrections narrated, not applied (the #7791 class, again)

- The breach-register `## Corrections — 2026-09-14` block said *"The cell now reads:
  **No — closed by decision.**"* while the 2026-09-03 row physically still read
  `PROVISIONAL` / `No — provisional` / `**Yes** … has not been run`. The register's own
  2026-09-04 (#7791) block records exactly this defect — corrections "recorded as
  supersessions … but never applied to the cell they correct" — and its remedy: apply
  **in-cell**, keep the blockquote as the record. The determination compounded it by
  justifying the drop with "the register's column *reads that field*" — a free-text cell
  derives from nothing.
- The determination's `§Re-evaluation triggers` list still ended at "CLEAN → drops
  provisional" with no marker beneath it; the addendum said "this is where a reader of
  that section is sent" and nothing sent them. Append-only forbids editing the list; it
  does not forbid a `> **Superseded 2026-09-14 (#7945): …**` blockquote under it.
- The PIR addendum claimed to supersede `### Still open` — the ADR-031 paragraph the
  2026-09-11 addendum had already superseded, and which the same addendum called
  "unchanged" one paragraph later. The sentences actually being superseded lived in
  `### Finding 3`. Two addenda claimed one section; the right one carried no marker.
- Both frontmatters' `art_33_deadline` still said "a BREACH finding on the open limb…"
  beside `open_limbs: none`.

### 2. Prose stronger than the record

- *"Every capability the admin scope set conferred that could have done lasting harm …
  writes to the org audit log."* The corpus already records a write class it does not:
  `2026-05-19-sentry-token-scope-probe-divergence.md` — "The Organization Audit Log does
  NOT record Personal Token mint or revoke operations." `event:admin` issue writes are
  not an org-audit event class either. The write limb is CLEAN *on the event classes the
  instrument records* (`detector.*`, `monitor.add`, `uptime_monitor.edit`, `rule.*`).
- *"No evidence it left that environment"* — the determination's own limb 2 says the
  channel was the operator's session **and the Anthropic agent context** (a DPA-covered
  processor). The draft to a vendor read as "no third party saw it".
- *"Our only uses were operator-workstation calls"* — asserted from script inventory.
  The other in-window reader was `fresh-host-boot-trail.sh` (a GitHub Actions job).
  Measured: 14 in-window `apply-web-platform-infra` runs, all `push`, `web_host_create`
  / `web_host_replace` **skipped** in every one; the only non-skipped host job was after
  revocation. True — and now recorded with its command.
- *"The 2026-05-17 tie-breaker convention"* — cited without a path. It exists
  (`runbooks/sentry-support-ticket-drafts.md` step 0, reply `Date:` header anchors the
  gate); cite the path, not the memory.

### 3. Two smaller ones

- **INCONCLUSIVE and FINAL are separate axes.** "Provisional" = an instrument is still
  to be run; "inconclusive?" = was it measured. The register's 2026-06-29 row already
  pairs a FINAL disposition with "**Yes** — INCONCLUSIVE and expressly not certified
  clean". Dropping the first must not flip the second. The cell now reads *"**Yes — read
  limb INCONCLUSIVE-BY-DECISION 2026-09-14** (closed; no instrument will be run; not a
  CLEAN, not exhaustion)."*
- **A qualified label extends a closed enum.** The runbook's Step 4 is "three ways, and
  only three" (BREACH / CLEAN / INCONCLUSIVE) and the determination invokes that section
  by name. Resolved with an append-only runbook addendum admitting
  `INCONCLUSIVE-<QUALIFIER>` as sub-states of the INCONCLUSIVE branch (the branch is
  unchanged; the qualifier records how the CLO closed the residual-window decision the
  runbook already routes to it) — not by minting a fourth branch.

## Solution

All sixteen fixed inline in `794c2cafc` on PR #8153; nothing filed. The legal call
(FINAL, not CLEAN, not exhaustion, re-opener with a fresh 72h from awareness of any
later evidence of use, vendor escalation first on re-open) survived review unchanged.
The operator's veto now has a first-person trace outside agent prose:
<https://github.com/jikig-ai/soleur/issues/7945#issuecomment-5661536361>.

## Key insight

A determination closed **by decision** is thinner ground than one closed by measurement
or by exhaustion, and the record has to say so in the same field a downstream reader
scans — not three paragraphs down. The two failure shapes that make a thin record read
as a clean one are (a) a correction that describes the cell instead of changing it, and
(b) a summary sentence that generalises past what the instrument actually covered. Both
are caught by one question per sentence: *what command would falsify this, and did I run
it?*

Related: the same class one week earlier —
[2026-09-04-four-of-six-p1s-were-in-the-corrections-not-the-thing-corrected](2026-09-04-four-of-six-p1s-were-in-the-corrections-not-the-thing-corrected.md)
and
[2026-09-07-i-widened-the-sentence-and-left-its-clauses-behind](2026-09-07-i-widened-the-sentence-and-left-its-clauses-behind.md).

## Prevention

- **CLO agent (routed):** when amending a register row or determination frontmatter,
  apply the correction in-cell and append a supersede marker under every superseded
  sentence in every sibling file; "the cell now reads" in a blockquote is a claim about
  the file it sits in — grep the cell.
- **Reviewer:** for a legal-corpus diff, list the sentences the frontmatter change
  falsifies (`git grep -n 'provisional\|only vendor support\|has not been run'`) and
  require each survivor to be marked or amended; then, for each summary sentence the
  diff ADDS about an instrument's coverage, name the instrument's documented blind spots
  (`git grep -n 'does NOT record'`) before accepting a universal.
- **Instrument check:** a `grep -c <LITERAL>` returning 0 is a result only if the
  literal has been shown to live in that file. `OUT_OF_SCOPE_ROW` is a variable in
  `scripts/lint-legal-registers.sh` naming a register *path*; the count on the register
  measured nothing, and the lint's exit code was the gate all along.

## Session Errors

1. **`gh run view --json jobs --jq --arg id …` → `accepts at most 1 arg(s), received 4`.**
   `gh --jq` takes one expression and does not forward `--arg`. Recovery: `sed "s/^/$id /"`.
   **Prevention:** already documented in `review/SKILL.md` (`gh --jq` does not forward
   jq flags); verify a flag on the exact subcommand with `--help` before composing.
2. **`grep -c OUT_OF_SCOPE_ROW knowledge-base/legal/breach-register.md` → 0 read as
   "untouched".** The literal lives in `scripts/lint-legal-registers.sh`; the CLO's first
   report and the original PR body inherited the same framing. Recovery: checked
   `origin/main` and the script; the register lint (rc=0) is the gate.
   **Prevention:** run every instrument against a known-positive before reading a zero.
3. **Two review seats reported the `Date:`-header tie-breaker convention absent.** Their
   `grep 'Date: *header'` cannot match the runbook's `` `Date:` header `` (a backtick sits
   between). Recovery: cross-reconciliation with the third seat + `/usr/bin/grep -a -i
   'tie-break'` found it at `runbooks/sentry-support-ticket-drafts.md` step 0.
   **Prevention:** when two seats agree a thing is absent and one says present, re-grep
   with a looser pattern yourself before crediting the majority — agreement on a
   negative from the same regex is one measurement.
4. **Session start: `CLAUDE_PLUGIN_ROOT` unset → `SOLEUR_SESSION_START_SKIPPED
   reason=plugin-root-unverified`.** Recovery: ran `cleanup-merged` from the repo-local
   plugin path; it reported one orphan it cannot remove (`feat-one-shot-supabase-bind-loopback`,
   EACCES), pre-existing. **Prevention:** #7442 class; the marker did its job — the skip
   was visible, not silent.
5. **MCP `plugin:github:github` failed to connect (`Authorization header is badly
   formatted`); the Playwright MCP disconnected mid-session.** Recovery: `gh` CLI for all
   GitHub reads/writes; no browser work was needed on this PR. **Prevention:** none
   needed for this PR; a UI-touching PR would need the Playwright MCP re-registered
   (`soleur:pencil-setup`-style) before QA.
6. **Unkept-promise stop hook fired once** on a closing line that named a future action
   while two background agents were still running. Recovery: explicit `<stop>BLOCKED:
   …</stop>` markers on every subsequent wait. **Prevention:** when the turn ends waiting
   on a subagent, say so with the marker rather than with a promise.
7. **CLO's first `markdown-lint` pass rc=1** (MD038 nested code spans in the new PIR
   lines). Recovery: self-corrected before reporting. **Prevention:** one-off.
8. **CLO's addendum narrated the register-cell corrections in a blockquote without
   applying them in-cell** — the #7791 class, reproduced in a CLO-authored record, caught
   as the review P1. Recovery: applied in-cell, kept the blockquote as the record,
   routed a bullet to the `clo` agent (see Prevention above).
   **Prevention:** the routed bullet; and the reviewer sweep in Prevention.

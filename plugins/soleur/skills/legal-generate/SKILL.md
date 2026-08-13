---
name: legal-generate
description: "This skill should be used when generating draft legal documents for a project or company. It gathers company context interactively, invokes the legal-document-generator agent, and writes markdown output."
---

# Legal Document Generator

Generate draft legal documents from company context. Supports 8 document types across US, EU/GDPR, and UK jurisdictions. All output is marked as a draft requiring professional legal review.

## Supported Document Types

- Terms & Conditions
- Privacy Policy
- Cookie Policy
- GDPR Policy
- Acceptable Use Policy
- Data Processing Agreement
- Data Protection Disclosure
- Disclaimer / Limitation of Liability

## Phase 0: Context Gathering

Use the **AskUserQuestion tool** to gather company context. Ask for:

1. **Company name** (required)
2. **Product/service description** (required) -- what the product does, who it serves
3. **Data practices** -- what user data is collected, how it is processed, stored, shared
4. **Jurisdiction** -- which legal frameworks apply (US, EU/GDPR, UK, or multiple)
5. **Contact information** -- email and/or physical address for legal notices

If the user provides arguments after the skill name (e.g., `/legal-generate privacy-policy`), use that as the document type selection and skip Phase 1.

## Phase 1: Document Selection

Use the **AskUserQuestion tool** to select a document type from the 8 supported types listed above.

## Phase 2: Generation

Invoke the `legal-document-generator` agent via the **Task tool** with the company context and selected document type:

```
Task legal-document-generator: "Generate a [document type] for [company name].
Company: [name]
Product: [description]
Data practices: [practices]
Jurisdiction: [jurisdiction]
Contact: [contact info]"
```

**Gates measure agreement, not truth (#7349).** All five gates compare the two surfaces against
each other. None asks whether the agreed text is correct, so two byte-identical copies of a false
sentence pass every one of them. Three defects shipped past a full green run in #7349 that way: a
controllership statement drift-reduction copied onto the published page, a duplicated clause left
behind by a half-applied replacement, and "eleven processing activities" in a document whose
register carries thirty-five. Read the prose; do not read the drift number and stop.

**`BODY_EQUIVALENCE_DOCS` is a one-way ratchet.** `terms-and-conditions`, `acceptable-use-policy`
and `disclaimer` are enrolled; each was verified at ZERO normalised drift immediately before
enrolment, because enrolling a drifted document turns a required check red on arrival. Once
enrolled, any edit landing on one surface only reds that check — which is the point. `--print-vocab`
and a mutation check (inject a line, confirm the guard fails, remove it) are the two ways to prove
an enrolment is live rather than decorative.

**Two measurement traps that cost real rounds in #7349.** `collapse()` normalises `[0-9]+ AI
agents` but NOT a bare `[0-9]+ agents`, so count divergence between the record and the published
page can be invisible to the drift gate. And a grep for `Article ` will not match the corpus's
plural `Articles 15 through 22` — use `Articles? 1[5-9]`.

## Phase 2.5: Redaction Gate (BLOCKING — runs BEFORE inline presentation)

A generated legal draft can echo a secret or PII that was passed in as company context (a contact email, an API identifier pasted into a data-practices answer). **Presenting the draft inline in Phase 3 is a transcript write boundary** — the same fail-closed rule the incident skill enforces (`incident/SKILL.md` Phase 6): the sentinel must precede inline-emit, not just file-commit. So the redaction gate runs here, before the operator ever sees the draft.

1. Write the generated draft to a `mktemp` file (do NOT emit it inline yet).

Register the cleanup trap **in the same block that allocates the draft**, before anything
can halt. This PR adds an earlier fail-closed exit, so it increases how often the draft is
abandoned mid-flight — and the abandoned file is the UN-REDACTED text, which is precisely
what this gate exists to stop escaping. Leaving it in `mktemp` is a leak with a longer
lifetime than the session (#7450 review-finding C14).

The allocation, the trap and the gate MUST share **one** fence — each fenced block is a
separate Bash call, so a trap registered in its own block fires when *that* block exits,
deleting the draft immediately and leaving `$DRAFT` empty for everything after it. The split
form shipped once and all three of its guarantees were false. The combined fence is in step 2
below.

2. Run the shared hardened engine against it. Resolve the path from the **deployed plugin root**
   (`${CLAUDE_PLUGIN_ROOT}`, the platform-trusted copy — ADR-179's canonical bare anchor, with no
   fallback arm) — NOT a bare `../incident/...` relative path, which depends on the current working
   directory and, from the wrong CWD, exits `127` *outside* the shim (bypassing the shim's fail-closed
   exit-2 normalization). On the Concierge server the deployed-root anchor is load-bearing: a bare
   CWD-relative path would resolve the connected repo's **untrusted** copy of the sentinel (ADR-093).
   The default arm was **removed, not re-pointed**: `review/SKILL.md` instructs `gh pr checkout`, after
   which the git worktree is the *reviewed party's* tree, so that arm resolved this gate's own scanner
   from a file a hostile PR controls (#7450). The **bare anchor is the load-bearing control** — the
   loader substitutes it with the installed root at delivery, so no ambient environment value reaches
   this site (measured: `specs/feat-one-shot-7450-git-root-anchor-untrusted/phase-1-measurement.md`
   Arm 4). The identity preflight below is **defence-in-depth** for surfaces where substitution does
   not govern: it is a *shape* check and cannot tell an install from a checkout carrying the same
   manifest, which is why ADR-179 §(a) measured a shape check passing while an attacker-chosen payload
   executed. The stronger root-outside-the-worktree form was evaluated and rejected — see
   `specs/feat-one-shot-7450-git-root-anchor-untrusted/b1-disposition.md`. Each halt emits a
   `SOLEUR_*` marker on stdout so refusals reach telemetry:

   ```bash
   DRAFT="$(mktemp)" || { echo "SOLEUR_LEGAL_GENERATE_HALT reason=draft-alloc-failed"
                          echo "legal-generate: cannot allocate a draft file — stopping before any draft text exists." >&2
                          exit 2; }
   trap 'rm -f "$DRAFT"' EXIT INT TERM HUP

   # Write the generated draft into "$DRAFT" here — in THIS fence, before the gate below.
   # Use a QUOTED heredoc delimiter (`<<'DRAFT_EOF'`): company-context answers can contain
   # `$(…)`, backticks and `$VAR`, and an unquoted delimiter would EXECUTE the substitutions
   # on the operator's machine and expand `$VAR` to empty — mutating the text the sentinel is
   # about to scan, so a secret's shape can be destroyed by the shell instead of the redactor.
   #   cat > "$DRAFT" <<'DRAFT_EOF'
   #   <the generated draft, verbatim>
   #   DRAFT_EOF

   [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
     && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
     || { echo "SOLEUR_LEGAL_GENERATE_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]"
          echo "legal-generate: cannot verify the Soleur plugin installation — stopping before any draft is written." >&2
          echo "  Resolved plugin root: [${CLAUDE_PLUGIN_ROOT}]" >&2
          echo "  If that is EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session — re-running here resolves the same empty root." >&2
          echo "  If it names a path: that path is not a Soleur install (a repo checkout is not an install). Run 'claude plugin update soleur', then RESTART Claude Code — plugin changes apply only on restart. If you installed with --scope project or --scope local, pass the same scope. Reinstall only if that does not clear it." >&2
          echo "  Do NOT hand-edit and publish this draft — the redaction scanner is what makes it safe to share." >&2
          exit 2; }
   SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"
   [[ -r "$SENTINEL" ]] || { echo "SOLEUR_LEGAL_GENERATE_HALT reason=sentinel-unreadable sentinel=[$SENTINEL]"
          echo "legal-generate: the redaction sentinel is missing from an otherwise valid Soleur install — stopping." >&2
          echo "  Expected at: [$SENTINEL]" >&2
          echo "  The install is partial or out of date. Run 'claude plugin update soleur', then RESTART Claude Code — plugin changes apply only on restart. If you installed with --scope project or --scope local, pass the same scope. Reinstall only if that does not clear it." >&2
          echo "  Do NOT hand-edit and publish this draft — the redaction scanner is what makes it safe to share." >&2
          exit 2; }
   # EMPTINESS IS A FAILURE, NOT A CLEAN SCAN — the sentinel exits 0 on zero bytes, so an
   # unwritten draft passes the gate vacuously and Phase 3 presents the un-redacted text
   # inline. Sibling of `linear-fetch`'s `[ -n "$PERSIST_SAFE" ]`.
   [ -s "$DRAFT" ] || { echo "SOLEUR_LEGAL_GENERATE_HALT reason=draft-empty draft=[$DRAFT]"
          echo "legal-generate: the draft file is empty — nothing was scanned, so nothing is safe to share." >&2
          echo "  Write the draft into \"\$DRAFT\" in the SAME fence as this gate, then re-run." >&2
          echo "  An empty file is a failure, not a clean scan: the sentinel exits 0 on zero bytes." >&2
          exit 2; }
   bash "$SENTINEL" "$DRAFT"
   ```

   The engine is owned by the `incident` skill and shared cross-skill by relative reference (see ADR-095).

3. Dispatch on the exit code (fail-closed):
   - **exit 0 (clean)** — proceed to Phase 3 and present the draft.
   - **exit 1 (redaction needed)** — print the finding lines (each is meta-redacted; never the full token), revise/redact the offending context, regenerate, and re-run the gate until it exits 0. Do NOT present or write an un-cleared draft.
   - **exit 2 (cannot-evaluate)** — halt. The engine could not run (skill bug, `python3` absent, unreadable tmpfile). Do NOT present or write; surface the error.

No un-scanned draft ever crosses the transcript or lands on disk.

## Phase 3: Output

<decision_gate>

Present the generated document to the user. Use the **AskUserQuestion tool** with options:

- **Accept** -- Write to disk
- **Edit** -- Provide feedback to revise (return to Phase 2 with feedback)
- **Reject** -- Discard and exit

</decision_gate>

On acceptance, write the markdown file to the user-specified path or default `docs/legal/<type>.md` (e.g., `docs/legal/privacy-policy.md`).

Report: "Draft written to `<path>`. This document requires professional legal review before use."

## Important Guidelines

- All generated documents include mandatory DRAFT disclaimers -- do not remove them
- Gather context interactively every time -- do not assume context from previous sessions
- One document type per invocation -- to generate multiple types, run the skill multiple times
- Output format is markdown only -- Eleventy .njk wrapping is out of scope for this skill
- **But the mirror is NOT out of scope for the corpus.** `docs/legal/<doc>.md` is the canonical
  record; `plugins/soleur/docs/pages/legal/<doc>.md` is the surface users actually read at
  soleur.ai/legal/. Writing canonical only leaves the published site unchanged AND trips
  [lint-legal-mirror-drift-baseline.sh](../../../../scripts/lint-legal-mirror-drift-baseline.sh), which exits 2 on a document that exists on
  exactly one surface. After generating, create the mirror in the same commit.
- Five CI gates ride `docs/legal/**` (#7387). Reproduce locally before pushing:
  `bash scripts/lint-legal-scope-block-placement.sh --base origin/main` (added scope blocks:
  referent agreement, attachment, discharge -- run `--print-vocab` for the accepted phrasings)
  and `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` (canonical<->mirror
  drift ratchet). The other three are `check-tc-document-sha.sh` (re-pin `legal-doc-shas.ts`
  after any canonical edit), `legal-doc-consistency.test.ts`, and the `EXPECTED_COUNT` sentinel.
- If the user asks for a document type not in the supported list, suggest the closest match or explain that the type is not supported

# CLO register markers (ruling L2, 2026-11-10)

Verbatim marker text ruled by the CLO agent on 2026-11-10 for the internal legal records that change 1 makes false on merge. Paste each block exactly; the placement line above each block is the CLO's. After pasting, run `bash scripts/lint-legal-registers.sh` and markdownlint on the edited files. The "Design record: ADR-319, Amendment 2026-11-10 (#12197)" text depends on the ADR-319 heading in plan Phase 1.8; if that heading's date or issue changes, change this text to match.

## M1: `knowledge-base/legal/article-30-register.md`, PA-40 Status cell

In-cell, after the existing `...human review owed.]**` that closes the 2026-11-09 marker, one space, before the closing cell pipe.

```text
**[Superseded 2026-11-10 (#12197, PR #12567; fires on the merge of the pull request that carries it), as to "the web screen that writes the tables exists behind the `approval-queue` flag" and "(the configured-founder gate is evaluated before the flag)": from that merge, `isLegalSurfaceEnabled` gates the card pages, the Inbox row and the decide and reauth routes on the configured founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`) alone and does not read the `approval-queue` flag. Design record: ADR-319, Amendment 2026-11-10 (#12197). A v1 CLO-agent position, human review owed.]**
```

## M2: `knowledge-base/legal/article-30-register.md`, PA-40 Addendum 2026-11-09 (prose)

New blockquote after the `> **Superseded 2026-11-09 (review round 4; ...` blockquote and before `> **Cross-reference, no amendment (PA-2, PA-8, PA-38):**`, blank line on each side.

```text
> **Superseded 2026-11-10 (#12197, PR #12567; fires on the merge of the pull request that carries it), as to *"behind the same configured-founder-and-flag gate as the card"* (Addendum 2026-11-09, limb (d), reader paths, point 2), and to *"once migration 184 is applied and the `approval-queue` feature flag is switched on"* and *"behind the `approval-queue` flag"* (Scope note, including its Amendment 2026-11-05):** from that merge, `isLegalSurfaceEnabled` gates the card pages, the Inbox row and the decide and reauth routes on the configured founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`) alone and does not read the `approval-queue` flag. Design record: ADR-319, Amendment 2026-11-10 (#12197). A v1 CLO-agent position, human review owed.
```

## M3: `knowledge-base/legal/compliance-posture.md`, founder legal-acceptance row (last cell)

In-cell, after the round-4 marker's final sentence (`...see the PA-40 Addendum 2026-11-09 and its round-4 marker.`), one space, before the closing cell pipe. Leave `last_updated` unchanged. This is a different row from the approval-queue cell append in plan Phase 4.2.

```text
**[Superseded 2026-11-10 (#12197, PR #12567; fires on the merge of the pull request that carries it), as to "adds the web screen behind the `approval-queue` flag", "so the card does not go beyond the flag" and "compared to `LEGAL_ACCEPTANCE_FOUNDER_ID` before the flag is read":]** from that merge, `isLegalSurfaceEnabled` gates the card pages, the Inbox row and the decide and reauth routes on the configured founder id alone and does not read the `approval-queue` flag. Design record: ADR-319, Amendment 2026-11-10 (#12197). A v1 CLO-agent position, human review owed.
```

## M4a: `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-attestation.md`

Append at the end of the file:

```text
## Addendum 2026-11-10 (#12197, PR #12567; fires on the merge of the pull request that carries it)

> Drafted, not counsel-reviewed. The sign-off block in section 6 stays blank, because it is for counsel.

- **[Superseded 2026-11-10, as to section 1, property 10 ("The card is shown only behind the `approval-queue` flag; with the flag off the page still renders existing rows but creates nothing and cannot record a Yes."):]** from that merge, `isLegalSurfaceEnabled` gates the card pages, the Inbox row and the decide and reauth routes on the configured founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`) alone and does not read the `approval-queue` flag; the flag's state does not stop the configured founder recording a Yes. This record does not attest property 10 as written.
```

Frontmatter key after `addendum_2026_11_09_round4`:

```text
addendum_2026_11_10: "2026-11-10 addendum at the end (#12197, PR #12567; fires on its merge): property 10 marked; the founder surface is gated by the configured founder id alone and does not read the approval-queue flag; sign-off block still blank"
```

## M4b: `knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md`

Append at the end of the file:

```text
## Addendum 2026-11-10 (#12197, PR #12567; fires on the merge of the pull request that carries it)

**[Superseded 2026-11-10, as to the safeguard "Behind the `approval-queue` flag; with the flag off the page still shows existing rows but creates nothing and cannot record a Yes." and, in the Stage paragraph and the paragraph after it, "adds the web screen behind the `approval-queue` flag", "stays behind the flag" and "ships behind the flag":]** from that merge, `isLegalSurfaceEnabled` gates the card pages, the Inbox row and the decide and reauth routes on the configured founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`) alone and does not read the `approval-queue` flag; the flag's state does not stop the configured founder recording a decision. Addendum 2026-11-09, point 3, already records that the flag is not what limits the record to one data subject, so the balancing outcome is unchanged; the status stays `draft-requires-counsel-review`. A v1 CLO-agent position, human review owed.
```

New element in the existing `addenda:` frontmatter array:

```text
"2026-11-10 addendum (#12197, PR #12567, fires on its merge): the flag safeguard is marked; the founder surface is gated by the configured founder id alone; balancing outcome unchanged"
```

## M4c: `knowledge-base/legal/audits/2026-11-counsel-review-12011.md`

Append at the end of the file (earlier dated rows describe the code at their own merge and are not marked):

```text
## Addendum 2026-11-10 (#12197, PR #12567; fires on the merge of the pull request that carries it)

> Drafted by the CLO agent as a v1 internal position standing in for counsel; human review owed. Nothing above is edited. The dispositions above are not re-attested and not withdrawn.

- **[Superseded 2026-11-10, as to "(`isLegalSurfaceEnabled` compares it before it reads the flag)" in the first bullet of the Addendum 2026-11-09, review round 4:]** from that merge, `isLegalSurfaceEnabled` gates the founder card, the decide and reauth routes and the Inbox row on the configured founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`) alone and does not read the `approval-queue` flag.
```

New element in the existing `addenda:` frontmatter array:

```text
"2026-11-10 addendum (#12197, PR #12567, fires on its merge): the founder surface is gated by the configured founder id alone and does not read the approval-queue flag; no disposition re-attested or withdrawn"
```

## Not marked (CLO ruling)

The DSAR and notice note (its flag lines describe the flag state, not the gate); `public-security-claim-ledger.md`; the 2026-11-07 ruling; the 2026-11-05 gdpr-gate work-exit record (a dated record of PR-C); `founder-acceptance-record.md` (no flag text); `docs/legal/*` and mirrors (unchanged).

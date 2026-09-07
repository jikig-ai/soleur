---
title: "Draft reply — Convergence Corporate CLA request"
date: 2026-09-04
type: correspondence-draft
custodian: clo
status: awaiting-operator-send
counterparty: Convergence (Islamabad, Pakistan)
inbound: support@convergence.pk → legal@jikigai.com
related: [3210]
---

# Draft reply to Convergence

**Status: DRAFT — not sent.** Operator sends from `legal@jikigai.com`. Two blanks to fill before sending: the turnaround commitment in paragraph 4, and whether to name the harness review point (see "Operator notes" below).

Basis for the content: CLO rulings D1 (both instruments), D2 (PR not blocked), D3 (role mailbox insufficient, and the exact field list with its no-extra-PII boundary).

---

**Subject:** Re: Corporate CLA — Convergence

Hello,

Thank you for getting in touch, and for offering to put this on a proper footing before contributing — that is genuinely appreciated and not the norm.

Yes, we would be glad to execute a Corporate Contributor License Agreement with Convergence. The agreement is published here:

<https://soleur.ai/pages/legal/corporate-cla.html>

**What we need from you.** Section 5 of that agreement asks for three things:

1. Convergence's full legal name and registered address, together with your registration identifiers (we have noted NTN 0829197-7 and PSEB Z-25-0716/02 from your site — please confirm or correct these).
2. The **name and title of the authorised signatory** — an individual with authority to bind the company. We are not able to countersign against a shared mailbox such as support@: the agreement's Section 4(a) is a representation made by a natural person, and both French contract law and our own record-keeping obligations require the signature to identify its author. Please also give us an individual email address for that person. We will keep `support@convergence.pk` on file as the notification channel for Section 5 changes to your representative list.
3. The list of **GitHub usernames** authorised to contribute on Convergence's behalf.

Please do not send us any further personal information — no phone numbers, home addresses, identity documents or employee numbers. We do not need them and will not retain them.

**Your pull request is not blocked while we do this.** Please go ahead and open it from `feat-opencode-harness` whenever it is ready. Two things will happen:

- Our CLA bot will comment on the pull request asking the individual author to sign the **Individual** CLA by posting one line as a comment. Please have them do that — it takes a few seconds and it is what turns the automated check green.
- The Corporate CLA runs in parallel, on our side, and is not a merge gate. **Chasing it is our job, not your engineer's.**

To be explicit about why we ask for both: the Corporate CLA secures Convergence's rights as your employee's employer, and the Individual CLA secures the author's own — including moral rights, which under French law cannot be transferred by an employer on an employee's behalf. They cover different things, so we need both. This is the same approach the Apache Software Foundation takes.

We will come back to you within [**N business days** — operator to set] of receiving the details above with a countersigned copy for your records.

One note on the contribution itself, so it is not a surprise at review time: adding a third agent harness widens a type union that several parts of the codebase consume, so the review will look at those call sites as well as at the new harness code. Happy to talk through the shape before you invest heavily in it.

Thanks again — we are glad to have you contributing.

Best regards,
Jean Deruelle
Jikigai — <legal@jikigai.com>

---

## Operator notes (do not send)

- **Do not countersign against `support@convergence.pk`.** CLO D3: a role mailbox has no capacity and no title; it also makes the record inaccurate under Art. 5(1)(d) and any Art. 15/17 request unanswerable, so it is worse for data protection, not better.
- **Set the turnaround number.** An SLA you actually meet beats a faster one you do not.
- **Do not add anyone to the `allowlist:` in `.github/workflows/cla.yml`.** It would write a permanent "maintainer bypass" record into a 10-year write-once archive for a contributor who *does* have a grant, and a malformed edit blocks every PR in the repo (#7597).
- **Record the countersigned agreement** in `knowledge-base/legal/ccla-register.md` (to be created) with the doc hash: `git rev-parse HEAD` and `git show <sha>:docs/legal/corporate-cla.md | sha256sum`.
- **The harness paragraph is optional.** It is a courtesy warning about review burden, not a condition. Whether Soleur accepts a third harness at all is a separate strategic decision that has not been made — do not let the CCLA correspondence imply it has.
- **Outbound transfer:** sending correspondence naming their signatory to Pakistan is a Chapter V transfer to a non-adequate third country. Covered for one-off correspondence, but the published corpus does not yet disclose it — see the brainstorm's Chapter V section and FR9.

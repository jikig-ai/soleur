# Questionnaires — the questions the founder sent out, and what came back

Some decisions cannot be made inside this company. Whether a prepaid contract is expensed or spread,
whether a clause survives termination, whether an insurer treats a change as material — the answer is
held by an accountant, a lawyer, an auditor, an insurer, a bank or a landlord, and no amount of
reading in here produces it. This directory holds the documents that went out to those people, one
file per ask, so that the question, its deadline and its answer stay together instead of living in a
mail thread nobody else can see.

Each file is written by `soleur:questionnaire-generate` and is meant to be read by someone outside the
company. Treat every byte of it as sent.

## File naming

```text
knowledge-base/project/questionnaires/YYYY-MM-DD-<recipient-role>-<topic>.md
```

The date is the day the questions were sent. The role is a role and never a person's name — an entry
naming an individual turns a public git history into a personal-data record. The topic is a short slug
for the decision, not for the document.

That last point is not hypothetical and it is the reason the role rule is absolute: this repository is
public, so every file in this directory is readable by anyone, in every version it has ever had. The
discipline that governs the Context paragraph governs the rest of the file too — a name, an amount or
a counterparty written here cannot be taken back by a later commit.

Anything in this directory that does not match `^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$` is not a
questionnaire. This file is the reason the pattern is mechanical rather than advisory: a reader
sweeping the directory for open asks would otherwise pick up the README and report it as an
unanswered question.

## Frontmatter contract

Four fields, all four required:

| Field | Meaning |
|---|---|
| `recipient_role` | The role the document was addressed to, lowercase, never a person |
| `needed_by` | The date the founder said the answers were needed, `YYYY-MM-DD` |
| `blocked_decision` | The one decision that cannot be made until the answers arrive |
| `status` | `sent` while an answer is outstanding, `answered` once a reply has been recorded |

`needed_by` is the founder's own stated date. Nothing derives it, nothing rounds it, and no default
replaces it — a deadline the founder did not name is a deadline nobody is waiting on.

## The two sections that close the loop

A questionnaire that is only sent is a question that gets lost. Two sections carry the return leg:

- `## Answers` — where the reply is recorded, and the one place an outside person's words enter this
  repository. The recipient may answer inside the file, on the blank quote line under each question.
  More often the reply arrives as an email.

  **Record the substance; never paste the message.** An inbound reply carries the sender's name,
  their signature block, a direct line, a firm address and a confidentiality footer, and this
  repository is PUBLIC with permanent history — so a verbatim paste publishes a third party's
  contact details, which they gave to answer a question and not to be indexed. It is also
  inconsistent with the rest of this design: the frontmatter records a recipient ROLE and never an
  identity, and the sibling rejected-concepts record removed `requester` from its schema outright
  for exactly this reason. A rule that strips the identity from the question and restores it from
  the answer protects nothing.

  So: transcribe each answer under its question, drop the greeting, the sign-off, the signature
  block and any contact detail, and keep the professional's role as the attribution ("the
  accountant", not a name). Where a verbatim sentence matters — a figure, a statutory citation, a
  commitment the founder may need to rely on — quote that sentence and say it is a quotation.
  `status` becomes `answered` either way.
- `## Blocked on` — a back-pointer to the artifact that caused the ask: a repo-relative path, or an
  issue reference. This is what lets the next session pick the thread up without anyone remembering
  it. Read from the other direction, it answers "why is this plan still open".

## Overdue asks are noticed without anyone watching

`scripts/followthroughs/questionnaire-unanswered-8289.sh` reads this directory on the follow-through
sweep. It reports an action when a file is still `status: sent` and its own `needed_by` has passed. It
notifies and nothing else — chasing an accountant is a judgement call, not something a script gets to
decide. It measures the deadline the founder stated, so it cannot nag about an expectation the founder
never set.

The probe runs on the sweeper and never inside the skill that writes these files: a reporter that is
also the subject reports on itself.

## Worked examples stay answered

A sample questionnaire committed here for reference is left at `status: answered`. A committed sample
left at `sent` eventually passes its own `needed_by` and then reports an overdue answer every single
day, forever, about a reply that was never coming — a permanent false alarm that trains the reader to
ignore the real one.

## What never goes into `## Context`

The Context paragraph is built from three things the founder said out loud: the decision, the
recipient's role, and the deadline. It is assembled from that list rather than drafted and then
cleaned up, because the cleaning-up version is the one that leaks. Monthly spend, break-even counts,
user names and numbers, competitor names, unshipped plans, file paths, issue numbers and internal tool
names are all absent by construction — none of them is a secret a scanner would catch, and every one
of them is something the founder did not choose to tell an outsider.

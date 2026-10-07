---
recipient_role: email infrastructure vendor
needed_by: 2026-10-16
blocked_decision: whether Resend Inboxes can be used for inbound email that must stay in the European Union, for individual users and for automated agents
status: answered
---

# Questions for my email infrastructure vendor

I am the founder of Jikigai. What follows is a list of questions and nothing else. It is not a
position, not a brief, and not advice from me to you. I am asking because the answers sit with you
and not with me.

## Context

I am deciding whether Resend Inboxes can be used for inbound email that must stay in the European Union, for individual users and for automated agents. I am writing to you as the email infrastructure vendor that offered me the Inboxes beta. I need your written answers by 2026-10-16.

## How to answer

Write your answer on the blank quote line under each question. A partial answer is worth more to me
than a blank one, and "I do not know" is a real answer I can act on. Where a question rests on
something you need from me first, say what you need rather than assuming it.

I need this back by 2026-10-16.

## Questions

### Can all Inboxes data be stored and processed only in the European Union?

_Why I am asking: EU-only storage, deletion of single messages and published retention are the three conditions for me to adopt Inboxes, and this is also my feedback on the beta._

By data I mean message bodies, headers, attachments, metadata, logs and backups.

>

### In which region or regions is inbound mail received and processed before it is stored, and does any copy, replica or failover leave the European Union?

>

### If any processing happens outside the European Union, which transfer mechanism covers Inboxes, and will you commit in the data processing agreement to EU-only storage and processing for my account?

>

### How long is Inboxes data kept by default, and can I set the retention period per inbox or per message?

>

### Can I delete a single message, a whole inbox, and an account through the API, and how long until the data is gone from backups and logs?

>

### Can you honour an erasure request from a person whose mail sits in an inbox within one month, and what is the process?

>

### Which sub-processors handle Inboxes data, and how much notice do you give before the list changes?

>

### Will you sign a data processing agreement that covers Inboxes now, and who is the contact for it?

>

### What are the pricing and the rate limits for Inboxes, is it available only in the beta, and when is general availability?

>

### How much notice do you give before a breaking change to the Inboxes API or webhooks during the beta?

>

## Anything I have not asked

Is there a question I should have put on this list? Write it here with your answer.

>

## Answers

Received 2026-10-05, from the vendor's founder and chief executive, the same day it was sent. Transcribed by
question; quoted only where the exact wording is a commitment or a figure.

**Overall: Inboxes does not meet the first condition (EU-only storage).** The vendor states it would rather
say so now than have me wait for the deadline, and advises not to build on Inboxes for this requirement.

1. **EU-only storage and processing: no.** All stored data (bodies, headers, attachments, metadata, logs,
   backups) is in the United States.
2. **Regions:** inbound mail is accepted in a receiving region tied to the domain (the Ireland region, eu-west-1,
   is available), but storage, indexing and backups are in the US, so copies leave the EU.
3. **Transfer mechanism:** Standard Contractual Clauses plus the EU-U.S. Data Privacy Framework. Quote: "We can't
   commit in the DPA to EU-only storage or processing."
4. **Retention:** inbox threads are kept until deleted. Quote: the formal retention policy for Inboxes "is being
   finalized before GA." No per-inbox or per-message retention setting today.
5. **Deletion:** a thread (moves to trash) and an inbox can be deleted through the API; the account can be deleted
   from team settings. Backups are kept for 7 days; data is deleted within 90 days of account termination.
6. **Erasure requests:** for mail users send into inboxes, I am the controller and delete the thread or inbox through
   the API; where I cannot complete a request without the vendor, they assist under Section 7 of the DPA. Requests
   about my own account data go to their support team and are completed within the one-month GDPR window.
7. **Sub-processors:** published on the vendor's legal page; at least 14 days' written notice before adding or
   replacing one.
8. **DPA:** already in force for my account and covers all of the vendor's services, Inboxes included.
9. **Pricing and limits:** not final. Direction: a few inboxes included per plan, a small monthly charge per extra
   inbox, sent and received mail counting toward the plan quota; rate limits as the rest of the API. Public launch
   is weeks away.
10. **Breaking changes in the beta:** announced by email and in the changelog; the docs flag which response shapes may
    change. No fixed notice period can be promised during the beta.

The vendor will say if EU residency ever becomes available.

## Blocked on

The decision on whether to adopt Resend Inboxes, tracked in issue #9459.

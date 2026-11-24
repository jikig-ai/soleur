# Inbound fit call

Use this when someone has already asked whether Soleur fits them, or has asked for a hosted founding-cohort seat. They may attach an operating document. This is a sales and product-fit conversation. It is not a cold problem interview.

## Not this script

A problem interview does not pitch and does not describe Soleur. That script lives in `knowledge-base/project/specs/archive/20261012-213508-feat-product-strategy/interview-guide.md`. Use it only when you have not yet heard how they spend their week. Do not merge the two scripts in one call. If they already sent a department map, asking them to react to a domain list measures the document, not independent pain.

## Two scores

Keep these apart. A person can be useful as a design partner and a poor customer.

| Score | Question it answers | Pass looks like |
| --- | --- | --- |
| Paying ICP | Will this person pay for Solo after they have seen the product? | One operator, a real product or revenue, AI already used outside code, a cost they can name, a budget anchored on that cost |
| Design partner | Will a hosted seat teach us something the roadmap does not already know? | They have already felt cross-department contradictions, a drifting approval rule, or reports that hide silence |

Do not average the two into one "fit" number.

## ICP screen

Record each line as pass or fail. From `knowledge-base/marketing/brand-guide.md`: solo founder, either a technical builder or a non-technical founder who wants business leverage.

The problem-interview screen is stricter. Fail paying ICP when any of these is true:

- The team is larger than three people
- They do not use AI for anything except code completion
- They are not building a product. Freelancing, consulting, an agency, or a job search fails this line

A polished operating document is a claim. It is not a pass. Ask what happened last week before you discuss the document.

## What you may quote on price

The live pricing page wins over this file. `knowledge-base/product/pricing-strategy.md` records the structure as Solo $49/month, Startup $149/month, Scale $499/month, and Enterprise custom. Solo is the one-operator plan. Startup and Scale buy concurrency for a team. They are not a prestige tier above Solo.

The public founding cohort is ten teams, onboarded by hand (`plugins/soleur/docs/pages/getting-started.njk`). Recruitment copy offers two weeks at no cost (`knowledge-base/marketing/recruitment-messaging-templates.md`). There is no paid plan named "founder tier". If they ask for the highest founder level, ask which thing they mean: a hosted cohort seat, or a paid plan. Do not invent a SKU, and do not describe the free two weeks as the premium offer.

## Thirty minutes

Read the questions as written. Skip a later question when an earlier answer already settled it.

1. What are you running today? Is there a product with users or revenue, or an operation you keep for yourself?
2. Walk me through last week, apart from maintaining the document. What actually got sent, submitted, or decided?
3. In the last month, where did two parts of the operation contradict each other? What caught it?
4. What is this costing you now, in money, in hours, or in something that did not happen?
5. If something took the part you are worst at, how would you know it had done it wrong?
6. You named that cost. How much of it would have to come off your plate before you would pay, and what would the budget be?
7. The hosted cohort is ten teams, onboarded by hand. The paid plan for one operator is Solo, at the price on the pricing page. Which are you asking for?
8. What would have to be true in the next 30 days for you to start?

When they already run the same shape of company in a document, question 3 is the fit test. Soleur has to do something the document cannot enforce: one shared record, one approval rule, and a report that leads with what did not happen. If they cannot name a contradiction the document missed, they do not yet have a reason to switch.

## After the call

Write the CRM record in the CRO chat (`/dashboard/chat/new` with `leader=cro` and `mode=crm-lead`). The board at `/dashboard/crm` is read-only. The write is the authenticated owner's, and the review gate is the save confirmation. Do not insert the row any other way.

Store only the existing fields: name, company, role, source, stage, nextAction, nextActionDate, lastContact, amount, currency, amountBasis, expectedCloseDate. A note takes `body` and a non-empty `lens` subset of `sales` and `product`.

- Do not set `qualified` unless the operator says the contact is qualified. `contacted` means a real exchange already happened. Stage history is append-only.
- Do not store an amount without a currency. `amountBasis` is `hypothetical_acv`, `committed`, or `unknown`.
- Do not ask the CRO chat to solicit a mailbox address. The contact table has no mailbox column. An address the operator already holds may sit in the note, because that is the only place the record can stay reachable.
- Do not ask for health, religion, biometrics, or other special-category data.
- Do not commit the person's name, address, or document to git. The CRM store is the record. Git history cannot honor erasure.

## Scorecard

Fill this after the call. No names in a file that will be committed.

| Line | Result |
| --- | --- |
| Building a product, team of three or fewer | |
| Uses AI outside code | |
| Named a real cost | |
| Named a budget anchored on that cost | |
| Named a contradiction the current setup missed | |
| Asked for a cohort seat, a paid plan, or both | |
| Paying ICP | pass / fail |
| Design partner | pass / fail |
| Stage to set | new / contacted / qualified |
| Next action and date | |

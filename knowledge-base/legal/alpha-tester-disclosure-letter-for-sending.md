# What happened on 6 August 2026, and what we are asking of you

> **Please read this first.** This letter has **not been reviewed by a lawyer**. We offer it in good faith, as an honest account of what happened and what you can ask of us. We invite you to **take your own legal advice** before you reply or decide anything, and you are free to ask us for changes or for more information.

**From:** Jikigai SARL, 25 rue de Ponthieu, 75008 Paris, France (RCS Paris 927 585 729)
**To:** `[Customer legal name]`, operator of the repository `[repository]` (GitHub account: `[GitHub account]`)
**Date:** `[date of sending]`
**Contact:** <legal@jikigai.com>

## 1. Why we are writing

On 6 August 2026 we ran software on your repository at your request, without the written data-processing agreement that the GDPR (Article 28(3)) requires to be in place before that kind of work begins. We are writing to tell you plainly what happened, what we hold, and what you can ask of us. **This letter asks you to sign nothing and agree to nothing.** Our separate processing annex, enclosed, governs future runs only and does not apply to the 6 August session.

## 2. What happened

At your request, as part of a guided onboarding, our founder ran Soleur agents against the content of your repository. This was done on the founder's own machine, under an Anthropic credential held by Jikigai (not yours). Content that the agents read was sent to Anthropic, our AI provider, for processing. No written agreement between you and Jikigai covering that processing existed at the time. In that session Jikigai acted as your **processor**, and the agreement should have come first. It did not.

## 3. Which of your repository content was involved

From the session record, reconstructed using counts and shapes only, without re-reading any of your content:

- The work was repository-structure exploration, test-suite inventory, domain-routing tests and discussion of schema and migrations. File reads resolved to 34 Markdown files.
- No query results, no database dump or CSV, SQL or spreadsheet file, no `INSERT` statements and no seed data were referenced.
- A directory listing of a fixtures folder showed four filenames. Two denote filed financial statements, one denotes sample French business-register (RNE) data on company officers (who are natural persons), and one is an advisor-related fixture. The record shows the listing only and **no evidence that the contents were read, but it cannot positively exclude a partial read.**

We therefore **do not say that no personal data was involved.** What we can say is that no records from a venture database appear to have been read into the session, and that the material was mostly schema, configuration, tests and documentation, with a possible exposure to company-officer data in a fixtures sample.

## 4. Where that content went, and how long it can stay

- **Anthropic.** Content went to Anthropic under our account. We understand Anthropic's default retention is 30 days, which for the 6 August session ran out in early September 2026; that content flagged by Anthropic's safety classifiers can be kept for up to two years, and classifier scores up to seven years. We cannot compel earlier deletion, and we have no zero-retention amendment. These figures are our working understanding and **we have not checked them against Anthropic's current published terms.** We have also **not confirmed** whether the account used on 6 August was on Anthropic's Commercial Terms, or what transfer mechanism applied to the transfer to Anthropic in the United States.
- **Our machine.** The tool keeps transcripts and related files on the machine it runs on (conversation transcripts, stored tool outputs, edit history, prompt history, plans and debug logs). We have **not verified** whether the files from the 6 August session still exist, whether they have been deleted, or whether any backup or snapshot of that machine existed. `[TO COMPLETE BEFORE SENDING, if this has been established: whether the 6 August local files still exist or have been deleted, by what method (say "unlinked", not "securely erased"), and whether any backup or snapshot existed. If not established, leave the sentence above as it stands and delete this bracket.]`
- **Encryption on that machine.** A note made at the time recorded that the machine's disk was not encrypted. A later observation found disk encryption (LUKS) on the founder's current workstation, which contradicts that note. We have **not established** which is right for the machine used on 6 August. `[TO COMPLETE BEFORE SENDING, if established: the position for the 6 August machine. If not established, delete this bracket.]`

## 5. A second purpose we also had, which you did not ask for

During that session we also watched how our own software performed on a real external codebase, for our own product-improvement purposes. In addition, since you gave our founder collaborator access to your private repository, we have used that access to read the repository's `knowledge-base/` tree to measure the growth of that knowledge base as a Jikigai product metric. **For these purposes Jikigai acted as a controller in its own right, not as your processor.** You did not ask for either, and we should have told you at the time.

`[TO COMPLETE BEFORE SENDING: state the status of this observation, either "That observation stopped on (date)" or "That observation will stop before you receive this letter". Do not send this letter until one of the two is true.]`

We have assessed that purpose under legitimate interest and recorded the assessment; we can give you a copy. A supervisory authority could take a different view, including that the two purposes were so entangled that Jikigai was a controller for the whole run, and we do not exclude that reading.

## 6. Our view on whether this is a personal-data breach, which we do not ask you to share

Our assessment is that the 6 August session is **not** a "personal-data breach" under Article 4(12) GDPR, because the disclosure to us was requested by you and no security control failed. We regard the opposing argument, that using your data for our own purpose can amount to unauthorised processing, as **not frivolous**. We consider the defect to be one of lawfulness and documentation (Articles 28 and 5(1)(b)) and not a security failure.

**Under Article 33(1) the judgment whether to notify a supervisory authority is yours, as controller, not ours, and we are the party at fault.** You are not asked to adopt our view. If it would help you reach your own, we will give you any fact you ask for.

## 7. What you can ask of us

You may, by writing to <legal@jikigai.com> — without any need to give a reason:

1. ask us to **delete** everything we hold from the 6 August session, and to confirm in writing what was deleted, by what method, and what we cannot reach (Anthropic's retention periods);
2. ask us to **stop** any observation of your repository outside a run you have requested;
3. ask for an **audit** of how we handled your content, or for the documents we rely on (our determination, our register entry and our assessment);
4. ask for the **facts** you need for any decision of your own, including any notification, and we will supply them without delay; and
5. **decline** to use us for any further run, with no consequence for your place in the alpha programme.

You also have the right to complain to the CNIL, the French supervisory authority.

## 8. What we have changed

We will not run Soleur on your repository content again under a Jikigai machine or credential until a written processing annex is in force between us. The enclosed annex sets out what we process, the limits on our use, who can access your content, where it can persist, how long Anthropic keeps it, and what happens if something goes wrong. It prohibits any use of your content for our own purposes. It applies only from countersignature and **not** to the 6 August session.

We are sorry that this reached you after the fact rather than before.

`[Signature — name and title of signatory, Jikigai SARL]`

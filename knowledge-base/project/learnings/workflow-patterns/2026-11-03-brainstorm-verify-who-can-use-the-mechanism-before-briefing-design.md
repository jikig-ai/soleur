# Learning: verify who can actually use a proposed mechanism before it goes into a design brief

## Problem

In the #12011 brainstorm (founder approval cards) I carried two mechanism assumptions from a leader ruling straight into the next prompt without checking the user population:

1. The CTO ruled that legal acceptances need a `web-session` answer. I then offered the operator "the link goes to the web app". The operator asked: "Other Soleur users may want to use the CLI only and not the webapp." CLI-only users have no web account, so the ruled channel did not exist for them.
2. The wireframe brief said "fresh re-login before Yes". At wireframe review the operator asked for a password or code popup instead. A grep of the auth stack then showed there is **no password login at all**: sign-in is email one-time code plus OAuth (Google, Apple, GitHub, Azure), so a password prompt would also have been wrong for most founders.

Both were refutable in one grep (`signInWithOtp`, the OAuth buttons component, the plugin's lack of any web credential) before the design agent spent about 17 minutes drawing the wrong flow.

## Solution

Asked the CTO for a ruling on CLI-only users (split: operator-first, customers later via GitHub environment reviewer, record in the customer's repo) and a second ruling on the step-up mechanism (email code default, password only if the account has one, OAuth redirect as last fallback, separate single-use challenge row because `mintFounderJwt` can mint a founder session server-side). Wireframes were revised once.

## Key Insight

A leader's mechanism ruling is correct for the population the leader had in mind. Before threading a mechanism into a user-facing design brief or an operator question, name who must be able to use it and run the one grep that proves they can: for auth steps, the sign-in methods the app actually supports; for web-app links, whether the user population has a web account at all. The probe is cheap; a wrong wireframe round is not.

## Session Errors

1. **Mechanism assumed web account for all users** — Recovery: CTO and CLO rulings on CLI-only users, split into operator-first increment. **Prevention:** before offering an operator question or design brief that depends on a user-facing mechanism, grep which sign-in methods and surfaces the target users have.
2. **"Fresh re-login" and password step-up specified without checking the auth stack** — Recovery: CTO ruling after grep (email code default). **Prevention:** same check; add the user population to every design-agent prompt.
3. **A CTO subagent completed with an empty result** — Recovery: SendMessage asking it to resend. **Prevention:** after any background agent notification, confirm a result body exists before treating the question as answered.
4. **`gh issue edit` used a scratchpad path that did not exist** — Recovery: `mkdir -p` then retry. **Prevention:** `mkdir -p` the scratchpad directory before writing into it.
5. **Design commit blocked by the secret-scan hook (`fileToken` key left in the saved `.pen`)** — Recovery: strip the key and recommit. **Prevention:** none beyond the existing hook; it did its job.

## Tags

category: workflow-patterns
module: brainstorm

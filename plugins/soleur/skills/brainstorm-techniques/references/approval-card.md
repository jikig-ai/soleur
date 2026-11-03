# Approval card — how the command line asks a founder to approve something

Canonical wording and rules for the plain-words card a CLI session shows when a step needs the founder's own answer. The
record formats stay in [standing-delegation.md](./standing-delegation.md); this file owns only how the question is put and
what the session does with each answer. Design source: `knowledge-base/product/design/approvals/founder-approval-cards.pen`,
frame 18. Spec: `knowledge-base/project/specs/feat-founder-approval-cards/spec.md` (FR1, FR2, FR6).

## 1. The shape of the card

1. **What will happen, in business terms, first.** One to three sentences saying what the work achieves and what changes for
   the founder's customers or money. Never a generic phrase such as "this piece of work".
2. **What the answer covers.** The scope items exactly as they will be recorded, one per line, and the end date.
3. **The three choices, typed in words.** `yes`, `no` or `changes`. Show them after the consequence, never before it.
4. **No default.** Pressing Enter on its own does nothing and the card is shown again. A single letter such as `y` is refused
   with "Please type the whole word: yes, no or changes." so a reflex keystroke cannot answer for the founder.
5. **`changes` records nothing.** Ask "What would you like changed?", print the answer in the session, keep the hold standing
   and do not write any approval.

## 2. Which message applies

The card never guesses. It picks exactly one row, top to bottom; the first row that matches wins.

| Where the session is | The step | What the card does |
|---|---|---|
| A person is typing in a terminal | Reversible and delegable (a merge, a ready mark, a revert change) | Shows the card of section 1 and records `--method tty-ack` |
| Headless or cloud, nobody can answer | Any | Asks nothing. The hold stands, and the existing standing-delegation issue is filed or reused by the `go` entry point (section 4) |
| A person is typing in a terminal | Legal, irreversible or money-moving, and the founder has a web account | Prints the browser-hold message (section 3) and carries on with work that does not depend on the answer |
| Any session | Legal, irreversible or money-moving, and no approver is set up | Prints the no-approver message (section 3) and does nothing |

Legal, irreversible and money-moving steps are never answered at `tty-ack` strength. A typed answer in a terminal is
evidence that someone at the keyboard answered; it is not evidence of who that was, because an agent shares the keyboard.

## 3. The two fixed messages

Browser hold:

```text
This needs your answer in the Soleur app: <link>. Nothing was done. I will carry on with anything that does not depend on it.
```

No approver set up:

```text
This needs approval from you in a browser and no approver is set up. Nothing was done.
```

The delegation question itself uses the epic-start wording of [standing-delegation.md](./standing-delegation.md), followed by
one line: `Type yes, no or changes. Pressing Enter on its own does nothing.`

## 4. Headless sessions and pending cards

A session with nobody to answer never asks. `go` already files, or reuses, one open issue per epic carrying the machine
marker `Standing-delegation epic: #<N>`; that issue is the queued card, and the next session with a person at the keyboard
asks the epic-start question once. This file adds no second queue.

## 5. The `method` vocabulary

`tty-ack` is the only value a delegation comment may carry (as a `**Method:**` line, written by
`delegation-verify.sh render --method tty-ack`). It is a label for how the answer was given. It never makes any check lighter:
the verifier returns the same verdict with and without it. `web-session` is a value only the web app's own record can hold; a
comment that claims it is refused.

## 6. Wording rules for every card and message

Plain sentences. No file paths, issue numbers, command lines or jargon in the question the founder reads. Never describe an
answer as proven, independently checked, lawyer-approved or officially certified; say only what happened ("Typed in
this terminal on your computer. It was not re-checked against your account."). The exact list of words the web copy must
avoid lives in the copy test, not here, so this file can describe the rule without breaking it.

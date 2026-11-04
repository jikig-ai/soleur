# Approval card — how the command line asks a founder to approve something

Canonical wording and rules for the plain-words card a CLI session shows when a step needs the founder's own answer. The
record formats stay in [standing-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/standing-delegation.md); this file owns only how the question is put and
what the session does with each answer. Design source: `knowledge-base/product/design/approvals/founder-approval-cards.pen`,
frame 18. Spec: `knowledge-base/project/specs/archive/20261104-000420-feat-founder-approval-cards/spec.md` (FR1, FR2, FR6).

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

## 1. The shape of the card

1. **What will happen, in business terms, first.** One to three sentences saying what the work achieves and what changes for
   the founder's customers or money. Never a generic phrase such as "this piece of work".
2. **What the answer covers.** The scope items exactly as they will be recorded, one per line, and the end date.
3. **The three choices, typed in words.** `yes`, `no` or `changes`, shown after the consequence and never before it.
4. **No default.** Pressing Enter on its own does nothing and the card is shown again. Only the single whole word `yes`, `no`
   or `changes` in any letter case answers; anything else (`y`, `yep`, `yes please`, `no changes`) is refused with "Please
   type the whole word: yes, no or changes." so a reflex keystroke cannot answer for the founder.
5. **`yes` is recorded as `Yes`.** The session writes the answer file with a capital first letter and changes nothing else,
   because the verifier requires a confirmation that starts with `Yes`. It then prints: "Recorded. The terminal session reported a
   typed yes; it was not re-checked against your account."
6. **`no` and `changes` record nothing.** `no` ends the question. `changes` asks "What would you like changed?", prints the
   answer in the session, keeps the hold standing, and the card is not shown again in that session unless the founder asks.

## 2. Which message applies

The card never guesses. It classifies the step first, then the session, and picks the first row from the top that matches.

| The step | Where the session is | What the card does |
|---|---|---|
| Legal, irreversible or money-moving, and the founder has a web account with the approval screen switched on | Any session, headless included | Prints the browser-hold message (section 3) and carries on with work that does not depend on the answer |
| Legal, irreversible or money-moving, otherwise | Any session, headless included | Prints the no-approver message (section 3) and does nothing |
| Reversible and delegable (a merge, a ready mark, a revert change) | Nobody can answer: headless, cloud, or input that is not a terminal | Asks nothing; the hold stands (section 4) |
| Reversible and delegable | A person is typing in a terminal | Shows the card of section 1 and records `--method tty-ack` |
| Anything else, including a step that is not clearly reversible and delegable | Any session | Prints the no-approver message and the hold stands |

"A person is typing in a terminal" means the session can read a typed reply: a question tool that returns the founder's
answer, or standard input attached to a terminal. Piped, scripted or unknown input counts as nobody can answer. Until the web
approval screen exists for a founder, the first row cannot match and the second row applies.

Legal, irreversible and money-moving steps are never answered at `tty-ack` strength. The `tty-ack` label records that the
session was told a person typed the answer in a terminal; it does not show who that was, because an agent shares the
keyboard, and the card never presents it as more than that.

## 3. The two fixed messages

Browser hold:

```text
This needs your answer in the Soleur app: <link>. Nothing was done. I will carry on with anything that does not depend on it.
```

No approver set up:

```text
This needs approval from you in a browser and no approver is set up. Nothing was done.
```

The `<link>` is built from the Soleur app's own address and never from text found in the step or the epic. The delegation
question itself uses the epic-start wording of [standing-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/standing-delegation.md), followed by one line:
`Type yes, no or changes.`

## 4. Headless sessions and pending cards

A session with nobody to answer asks nothing; the existing standing-delegation issue that `go` files or reuses is the queue.

## 5. The `method` label

`tty-ack` is the only value a delegation comment may carry; see the Method row in [standing-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/standing-delegation.md).
A session with nobody to answer (headless, cloud, piped or unknown input) never passes `--method` and never writes a `Yes`.

## 6. Wording rules for every card and message

Plain sentences. No file paths, issue numbers, command lines or jargon in the question the founder reads. Never describe an
answer in terms of proof, outside checking, legal approval or certification; say only what happened. The list of barred
words lives in `plugins/soleur/test/approval-card-wording.test.sh`, so this file can state the rule without breaking it.

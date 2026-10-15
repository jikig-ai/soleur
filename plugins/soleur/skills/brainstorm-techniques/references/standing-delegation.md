# Standing Delegation and Production Envelope — the single format source

Canonical home of the record formats behind hard rule `hr-menu-option-ack-not-prod-write-auth`'s second path. The verifier
(`plugins/soleur/scripts/delegation-verify.sh`), the Technical-Ruling Gate, the ask hook, the hold evaluator
(`plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`) and the CTO agent cite this file and restate none of it. A test
extracts the templates below, fills them with fixture values and requires the verifier to answer `valid`, so this document
and the code cannot drift apart silently.

"The operator" is whoever runs the skill: the founder in this repository, a Soleur end user elsewhere. These users are not
technical. After ONE plain-language confirmation at the start of an epic, every technical or production-safety decision is
the CTO's, executed inside a recorded envelope with automated checks. A session with no recorded delegation behaves exactly
as before: ask once, naming the action, at each operator-class step.

## 1. The delegation record (v1)

An issue comment on the epic. Line 1 is exactly `<!-- soleur-delegation v1 -->`. Required parts, each checked by the
verifier (the reason token is what the verifier prints when the part is wrong):

| Part | Rule | Reason token |
|---|---|---|
| Marker | line 1, byte for byte | `no-marker` |
| Author | a real user (not an App or bot) whose login is the repository owner OR who holds the `admin` permission | `bot-author`, `not-admin-author` |
| Never edited | `updated_at` equals `created_at`; an edit is a revocation, the operator re-records instead | `edited` |
| Quote | under the line `Operator instruction, verbatim`, a blockquote (lines starting `>`) of at least 40 characters, not counting the two `Question shown:` / `Operator answer:` labels: the EXACT question shown plus the operator's answer, so a bare "Yes" is never the whole quote | `no-quote`, `quote-too-short` |
| Confirmation | a `**Confirmation:**` line carrying the operator's answer text (option label or free-text reply) exactly as the calling skill received it | `no-confirmation` |
| Scope | numbered items, each an act class; an item that names an exact command embeds it in backticks | `no-scope-item` |
| Excluded | the `**Excluded (still operator-only):**` list names every anchor keyword in section 5 | `excluded-incomplete` |
| Expiry | an ISO date no later than the comment's creation date plus 30 days, not in the past; the epic closing also ends it | `expiry-missing`, `expiry-too-long`, `expired`, `epic-closed` |
| Revoke | "delete or edit this comment" | (informational) |

### Delegation record template

```text
<!-- soleur-delegation v1 -->
## Standing delegation - epic #{EPIC} (recorded {DATE})

**Operator instruction, verbatim ({DATE}):**
> Question shown: {QUESTION}
> Operator answer: {ANSWER}

**Confirmation:** {ANSWER}

**Scope (act classes the CTO agent may run without a further per-command prompt):**
1. {ACT_CLASS_1}
2. {ACT_CLASS_2}

**Excluded (still operator-only):** user-data loss or sole-copy destruction, money, legal-risk, brand, scope changes, force-push to main, bypassing required checks or rulesets, editing this delegation, credential rotation that can lock users out, anything on third-party or tenant systems, and any act whose rollback is not named.

**Expiry:** {EXPIRY} (or when the epic closes, whichever comes first). **Revoke:** delete or edit this comment.
```

The calling skill never hand-writes this. It runs `delegation-verify.sh render --epic <N> --question-file <f>
--answer-file <f> --scope-file <f> --expiry <ISO date>`, posts the output with `gh issue comment <N> --body-file`, and
reads the comment straight back through `delegation-verify.sh verify`. A record that does not verify is deleted and the
epic stays on today's behaviour.

## 2. The Production Envelope

A section in a file the CTO commits (a plan, a spec, a runbook). One section per production act. The heading is
`## Production Envelope`, optionally followed by a hyphen and a title; a file with several sections is addressed
`path#<title substring>`; more than one section and no anchor is `parse-ambiguous`. The section runs to the next level-two
heading (fences are respected). Every part below is required (reason `envelope-incomplete`); `Rollback:` must be named,
never `none`, `n/a` or `unknown` (`rollback-unnamed`):

- `Delegation:` the comment URL; it must equal the URL passed to the verifier (`envelope-delegation-mismatch`).
- `Scope item:` the number of the delegation's Scope item this act falls under (`no-scope-item`).
- `Command:` followed by ONE fenced block, one command per line. The executed command is a byte-identical FULL line of
  this block; a prefix, a substring, trailing whitespace or a CRLF difference does not match (`command-not-in-envelope`).
- `Blast radius:` who or what the act can touch.
- `Preconditions:` with one or more `Gate:` lines (section 3).
- `Verification:` commands run against telemetry afterwards, never an eyeball check.
- `Abort:` when to stop before the act, and `Rollback:` how to undo it, named and tested.
- `Stop conditions:` what makes the CTO halt after the act began.

The envelope file must be tracked and unmodified at HEAD (`envelope-not-committed`): the verified text is the committed
text.

### Production Envelope template

````text
## Production Envelope - {TITLE}

Delegation: {URL}
Scope item: {N}

Command:

```text
{COMMAND}
```

Blast radius: {BLAST_RADIUS}
Preconditions:
- Gate: {GATE}
Verification:
- {VERIFICATION_COMMAND}
Abort: {ABORT}
Rollback: {ROLLBACK}
Stop conditions: {STOP_CONDITIONS}
````

## 3. `Gate:` v1 grammar

One predicate per line, closed set. An unknown kind, an unreadable probe, a missing or invalid delegation or a timeout
means the hold STANDS. Adding a kind is a CTO ruling plus a test row.

```text
Gate: pr-merged <N>
Gate: no-inflight-run <workflow-file>
Gate: run-green <workflow-file> <sha>
Gate: command <repo-relative script and args> => <literal expected output>
```

`pr-merged` needs state MERGED on `main` and the merge commit reachable from HEAD. `no-inflight-run` needs the queued,
in_progress and waiting lists all empty, and is true only at that instant (it is evaluated again right before arming).
`command` runs a repo-relative script (no `..`, no symlink escape, tracked at HEAD and byte-identical to `origin/main`,
30 s cap, no `ssh`) and compares its output with the literal after the FIRST `=>`.

## 4. What this does NOT bypass

- Acts that `prod-write-defer-gate.sh` recognises (terraform apply, git push to main, secret-store writes, operator-ack
  scripts) still defer to the harness approval prompt. A delegation covers acts such as `gh pr merge`, `gh workflow run`
  and revert changes; hook-gated forms stay per-command.
- The delegation is posted through the same `gh` identity as the agent. The `Confirmation:` line, the 40-character
  quote, the 30-day cap and edit-as-revocation are tamper-evidence and an audit trail, NOT prevention.
- Byte-identical execution depends on the CTO running the line the verifier printed (`verified-command:`), checked right
  before the act and audited at ship.
- A closed text denylist backs the Excluded list: `git push`, `--admin`, writes to rulesets or branch protection,
  secret-store set or delete, `terraform`/`tofu` apply, destroy or import, `rm -r`, `gh repo delete` and `gh secret` are
  `non-delegable-command` whatever the envelope says.

## 5. The Excluded list

Not delegable, ever: user-data loss or sole-copy destruction, money, legal exposure, brand, scope, force-push to main,
bypassing required checks or rulesets, editing the delegation, credential rotation that can lock users out, anything on
third-party or tenant systems, and any act whose rollback is not named. The verifier requires each anchor keyword below
as a case-insensitive substring of the record's Excluded list:

### Excluded anchor keywords

```text
user-data loss
money
legal-risk
brand
scope
force-push
bypassing required checks
editing this delegation
credential rotation
third-party
```

## 6. Plain-language wording (the only strings an operator sees)

A test checks every block in this section for jargon (patch, hash, rebase, diff, draft, branch, pull request, issue
numbers and similar). Keep them in plain sentences.

### Epic-start confirmation

Asked by the CALLING skill as a real question (the CTO agent is headless and never asks): the outcome in business terms in
at most three sentences, then the acts, then the promise.

```text
I will carry this piece of work through to the end on my own. To do that I need to merge and release changes to your live product, and undo them if something goes wrong. I will only come back to you for money, what is in or out of scope, how it looks or reads, legal exposure, anything that could lose your customers' data, or anything I am not allowed to do for you. You can tell me to stop at any time. Is that OK?
```

Yes writes the record (section 1). No keeps today's behaviour: ask once, naming the action, at each operator-class step.

### Stall sentences

One plain sentence in the session for every stall, in addition to any issue filed.

```text
Your standing approval was changed after you gave it, so I have paused and done nothing. Please confirm it again and I will carry on.
Your standing approval has run out, so I have paused and done nothing. Please confirm it again and I will carry on.
This piece of work is finished, so the standing approval has ended.
Your standing approval is gone, so I have paused and done nothing until you confirm it again.
I could not check that it is safe to go ahead, so I am waiting and have not done anything.
This step needs you, because it is on the list of things I am never allowed to do for you. I have not done it.
Another open change already covers this work, so I am holding mine back and will not touch theirs.
```

### Execution log sentences

One plain sentence on the epic after EVERY delegated act.

```text
Merged <title> under your standing approval; it is live and healthy.
Rolled back <title> because <plain reason>.
You asked me to stop, so I removed the standing approval and will not act further without it.
```

## 7. Stall, re-confirm, resume

When the verifier answers `edited`, `expired` or `epic-closed`, or the comment is gone, the agent says one stall sentence,
the CTO returns the epic-start wording for the calling skill to ask again, and a Yes re-records through `render` and
resumes from the first unticked checklist item. A conversational "stop" makes the agent delete the delegation comment
(deleting reduces authority and is allowed; editing it is excluded). The verifier is re-run immediately before every act,
so a stop between verification and execution cannot be raced past by more than that instant.

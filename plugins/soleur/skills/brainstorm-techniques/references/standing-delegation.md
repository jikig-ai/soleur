# Standing Delegation and Production Envelope — the single format source

Canonical home of the record formats behind hard rule `hr-menu-option-ack-not-prod-write-auth`'s second path. The verifier
(`${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh`), the Technical-Ruling Gate, the hold evaluator
(`${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh`) and the CTO agent cite this file and do not restate the
formats. If `CLAUDE_PLUGIN_ROOT` is unset, resolve it as ship's Cloud Mode paragraph does. A test extracts the templates
below, fills them with fixture values and requires the verifier to answer `valid`, and it requires every reason token the
verifier can print to have a plain sentence in section 7, so this document and the code cannot drift apart silently.

"The operator" is whoever runs the skill: the founder in this repository, a Soleur end user elsewhere. These users are not
technical. After ONE plain-language confirmation at the start of an epic, every technical or production-safety decision is
the CTO's, executed inside a recorded envelope with automated checks. A session with no recorded delegation behaves exactly
as before: ask once, naming the action, at each operator-class step.

A delegation is recorded consent plus a drift guard, not two independent keys: the same `gh` identity writes the record and
the CTO's envelope. What the checks prove is that the recorded scope names the act, that the line which runs is a
byte-identical line the CTO committed, and that nothing was edited since.

## 1. The delegation record (v1)

An issue comment on the epic. Line 1 is exactly `<!-- soleur-delegation v1 -->`. Required parts, each checked by the
verifier (the reason token is what the verifier prints when the part is wrong; section 7 gives each token its plain
sentence):

| Part | Rule | Reason token |
|---|---|---|
| Marker | line 1, byte for byte | `no-marker` |
| Author | a real user, not an App or bot (`type` is `User` and `performed_via_github_app` is null), whose login is the repository owner OR who holds the `admin` permission | `bot-author`, `not-admin-author` |
| Never edited | `updated_at` equals `created_at`; an edit is a revocation, the operator re-records instead | `edited` |
| Quote | under the line `Operator instruction, verbatim`, a blockquote (lines starting `>`) of at least 40 bytes, not counting the two `Question shown:` / `Operator answer:` labels: the EXACT question shown plus the operator's answer, so a bare "Yes" is never the whole quote | `no-quote`, `quote-too-short` |
| Confirmation | exactly one `**Confirmation:**` line whose text starts with the word `Yes` (the option label or the free-text reply, as the calling skill received it); a No, a maybe or any other answer is never a delegation | `no-confirmation` |
| Scope | numbered items, each an act class; an item that names an exact command embeds it in backticks and names the command's target in words (section 2, scope binding) | `no-scope-item` |
| Excluded | exactly one `**Excluded (still operator-only):**` paragraph, equal to the fixed sentence in section 5 after whitespace is normalised | `excluded-incomplete` |
| Expiry | exactly one `**Expiry:**` line with an ISO date no later than the comment's creation date plus 30 days, not in the past; the epic closing also ends it | `expiry-missing`, `expiry-too-long`, `expired`, `epic-closed` |
| Revoke | "delete or edit this comment" | (informational) |

Time rules. A plain `verify` enforces the expiry and an open epic against the current time. The ship gate audits an act
that has ALREADY run with `verify --audit --at <YYYY-MM-DDTHH:MM:SSZ>`, where the time is when the act ran: the delegation
must have been in force then (created at or before that time, not past the end of its expiry day), and the only check
skipped is `epic-closed`, because an epic closes on its last item. `--audit` without `--at` (or `--at` without `--audit`) is
a usage error, an act dated before the delegation existed is `before-delegation`, and one dated after the expiry is
`expired`. The CTO never runs `--audit`.

What a `valid` verdict prints, after the first line: `verified-created-at: <ISO time the delegation comment was created>`
and `verified-expiry: <YYYY-MM-DD>` (the window the ship gate binds receipts to), then, when an envelope was checked,
`verified-envelope-sha256: <hex>`, then one `verified-command:` and `verified-sha256:` pair per asked command. An invalid
verdict prints none of them.

Hidden text is not text. The verifier drops every HTML comment (`<!-- ... -->`, also across lines) from the delegation
comment (after its marker line) and from the envelope file before it reads anything, so a Scope item or an envelope
section that a reader of the rendered page cannot see is not a Scope item or a section. A Scope item that contains a
negation (the whole words `not`, `never`, `except`, `excluding`, `without` or `don't`) never covers any command.

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

Only the CALLING skill writes this record, after it asked the operator the epic-start question of section 6 as a real
question and received a `Yes` answer. The CTO agent never runs `render` and never posts a delegation, whatever the
verifier says about an earlier one. The calling skill never hand-writes the record either. It writes the question it showed
(with the Scope items and the expiry date filled in), the operator's answer and the Scope items to files, runs
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh" render --epic <N> --question-file <f> --answer-file <f>
--scope-file <f> --expiry <ISO date>`, posts the output with `gh issue comment <N> --body-file`, and reads the comment
straight back through `delegation-verify.sh verify`. `render` refuses an answer that does not start with `Yes`, an answer
longer than 600 characters (the answer is published word for word on the issue) and an answer or question that looks like a
password or key. A record that does not verify is deleted and the epic stays on today's behaviour.

Find the delegation of an epic with this exact discovery command. It lists the candidates oldest first, so verify them from
the last line upward. The NEWEST marker comment written by an administrator decides: a comment the verifier rejects as
`not-admin-author` or `bot-author` is skipped, but the first one it does not reject so decides, and if that one is invalid,
edited, expired or its epic closed, the delegation is invalid. Never fall back to an older marker comment: editing or
deleting the newest one is how an operator takes the approval back.

```text
gh api repos/{owner}/{repo}/issues/<epic>/comments --paginate --jq '.[] | select(.body|startswith("<!-- soleur-delegation v1 -->")) | .html_url'
```

## 2. The Production Envelope

A section in a file the CTO commits (a plan, a spec, a runbook). One section per production act. The heading is
`## Production Envelope`, optionally followed by a hyphen and a title; a file with several sections is addressed
`path#<title substring>` (matched against the title, case-insensitively); more than one section and no anchor is
`parse-ambiguous`. The section runs to the next level-two heading (fences are respected: a fence closes only on the same
character, at least as long, with no text after it). Every part below is required (reason `envelope-incomplete`); the
`Rollback:` must be a real way to undo the act in at least three words, and a placeholder or an admission is refused
(`none`, `n/a`, `unknown`, `tbd`, `todo`, `nothing`, `impossible`, `irreversible`, `cannot`, `can't`, `no rollback`,
`not reversible`, `not possible`, `not undoable`) (`rollback-unnamed`):

- `Delegation:` the comment URL; it must equal the URL passed to the verifier (`envelope-delegation-mismatch`).
- `Epic:` `#<N>`, the issue the delegation comment sits on; a different number is `epic-mismatch`, a missing or malformed
  line is `envelope-incomplete`.
- `Scope item:` the number of the delegation's Scope item this act falls under (`no-scope-item`).
- `Command:` followed by one or more fenced blocks, one command per line. EVERY line of every block must be on the closed
  grammar below (`command-not-delegable`), covered by the cited Scope item (`scope-mismatch`) and not on the denylist of
  section 4 (`non-delegable-command`), whether or not it is asked for. The executed command is a byte-identical FULL line of
  these blocks; a prefix, a substring, trailing whitespace or a CRLF difference does not match (`command-not-in-envelope`).
  A fence that is never closed is `envelope-incomplete`.
- `Blast radius:` who or what the act can touch.
- `Preconditions:` with one or more `Gate:` lines (section 3).
- `Verification:` commands run against telemetry afterwards, never an eyeball check.
- `Abort:` when to stop before the act, and `Rollback:` how to undo it, named and tested.
- `Stop conditions:` what makes the CTO halt after the act began.

The text of `Verification:`, `Abort:`, `Rollback:` and `Stop conditions:` is run by the CTO, so it is checked too: every
line of those parts (fenced lines, backticked spans and plain lines) is tested against the denylist of section 4
(`non-delegable-command`). In a `Rollback:` every fenced line and every backticked span must be a command on the grammar
below, and the rest of the line must be plain words without shell characters (`;`, `&`, `|`, `<`, `>`, `$`, backticks,
`\`, `{`, `}`, `*`); otherwise `command-not-delegable`. A revert is therefore written in words or as a
`gh pr create --fill` of a revert branch.

### The command grammar

The only delegable command lines, with N = `[0-9]+`. Any character outside `[A-Za-z0-9 ._=:/@+,-]` rejects the line, and
a line is exactly one command: no quotes, no `;`, `&`, `|`, `$`, backticks or redirects.

```text
gh pr merge <N> [--squash|--merge|--rebase] [--auto]
gh pr ready <N>
gh workflow run <file>.yml|<file>.yaml [-f <k>=<v>]...
gh pr create --fill [--head <branch>] [--base <branch>]
```

`k` is `[A-Za-z0-9_.-]+`, `v` is `[A-Za-z0-9._/:@+,-]+`, `branch` is `[A-Za-z0-9._/-]+`. A revert is a `gh pr create --fill`
of a revert branch. Everything else stays with the operator: the grammar is the whole list, not a sample.

### Scope binding

The cited Scope item's own words must name the command's target as a whole token: for merge and ready, the pull request
number (written `#N`, `PR N`, or right after `pr merge` or `pr ready`) AND the word merge (or ready); for a workflow run,
the workflow file name; for create, the word create or revert. Otherwise `scope-mismatch`. The item therefore says in words
what the operator approved, and a command filed under the wrong item is refused.

### Where the envelope is read from

The verifier never reads the working tree. The path must be relative to the current repository (no leading `/`, no `..`,
none of `*`, `?`, `[`; otherwise `envelope-outside-repo` or `envelope-missing`), and the text is read from the committed
`HEAD` blob (the path is a literal file name: git pathspec magic such as `:(top)` or `:/` is just a name that is not in
`HEAD`): not in `HEAD` is `envelope-not-committed`, a symlink, an executable or a directory is
`envelope-not-regular-file`; a control character or a trailing `/` in the path is `envelope-missing`. So the verified text is the committed text, an uncommitted edit changes nothing, and a
verified envelope prints `verified-envelope-sha256: <sha256 of that blob>` for the receipt of section 8. `HEAD` is the
checked-out commit, not a reviewed or pushed one.

### Production Envelope template

````text
## Production Envelope - {TITLE}

Delegation: {URL}
Epic: #{EPIC}
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
means the hold STANDS (the evaluator exits 1 for an invalid delegation and 2 for anything it cannot evaluate). Adding a kind is a CTO ruling plus a test row.

```text
Gate: pr-merged <N>
Gate: no-inflight-run <workflow-file>
```

`command` and `run-green` are deferred. The first real consumer re-adds them, and only by CTO ruling.

`pr-merged` needs state MERGED on the repository's default branch and the merge commit reachable from HEAD.
`no-inflight-run` needs no run of that workflow in any of the statuses queued, in_progress, waiting, requested or pending,
and is true only at that instant (it is evaluated again right before arming).

## 4. What this does NOT bypass

- Acts that `prod-write-defer-gate.sh` recognises (terraform apply, git push to main, secret-store writes, operator-ack
  scripts) still defer to the harness approval prompt. A delegation covers only the four command lines of the grammar in
  section 2; hook-gated forms stay per-command.
- The delegation is posted through the same `gh` identity as the agent. The `Confirmation:` line, the 40-byte quote, the
  30-day cap and edit-as-revocation are tamper-evidence and an audit trail, NOT prevention. Anything that can run `gh` as the
  operator can also write a record; the controls below limit what a record can authorize, not who can write it.
- Byte-identical execution depends on the CTO running the line the verifier printed (`verified-command:`), checked right
  before the act. Section 8 records what was run, so a run can be compared with its envelope afterwards.
- A text denylist is a second layer behind the grammar, for the Excluded list: `git push` (also written with quotes, so
  `g''it push` is read as `git push`), `--admin`, `git reset --hard`, `git branch -D`, writes through `gh api -X` with
  DELETE, PATCH or PUT, writes to rulesets or branch protection, `gh release delete` and every other `gh ... delete`,
  `gh repo delete`, `gh secret` and `gh variable`, secret-store set, delete or upload, `terraform`/`tofu` apply, destroy,
  import or state, `rm -r` in any flag spelling, `find -delete`, `kubectl`, `supabase`, `psql`, `hcloud`, `ssh`, `curl -X`
  are `non-delegable-command` whatever the envelope says. The grammar alone already refuses all of them; the denylist
  gives them the more specific answer and keeps a future widening of the grammar from admitting them.
- The verifier has no seam inside the script, but it trusts the `gh` and `jq` on the caller's PATH and the caller's
  GitHub credentials, as any script does. It also refuses to run with neither `timeout` nor `gtimeout`, rather than run a
  network call unbounded.

## 5. The Excluded list

Not delegable, ever: user-data loss or sole-copy destruction, money, legal exposure, brand, scope, force-push to main,
bypassing required checks or rulesets, editing the delegation, credential rotation that can lock users out, anything on
third-party or tenant systems, and any act whose rollback is not named. The record carries exactly one sentence for it, and
the verifier compares the record's paragraph with that sentence after whitespace is normalised; a shorter, longer, negated
or reworded paragraph is `excluded-incomplete`.

### The fixed Excluded sentence

```text
**Excluded (still operator-only):** user-data loss or sole-copy destruction, money, legal-risk, brand, scope changes, force-push to main, bypassing required checks or rulesets, editing this delegation, credential rotation that can lock users out, anything on third-party or tenant systems, and any act whose rollback is not named.
```

## 6. Plain-language wording (the only strings an operator sees)

A test checks every text block in this section for jargon (patch, hash, rebase, diff, draft, branch, pull request, issue
numbers and similar). Keep them in plain sentences.

### Epic-start confirmation

Asked by the CALLING skill as a real question (the CTO agent is headless and never asks), never answered on the operator's
behalf and never reused from an earlier answer. The two options are labelled `Yes ...` and `No ...`; only a `Yes` answer is
recorded. The question shows, in this order: the outcome in business terms (`{OUTCOME}`, required, at most three sentences
and never a generic phrase such as "this piece of work"), the promise, the Scope items exactly as they will be recorded
(`{SCOPE_ITEMS}`, one per line, in plain words) and the expiry date (`{EXPIRY}`, the date that will be recorded, at most 30
days out). The calling skill quotes the text it actually showed into the record, not a paraphrase.

```text
{OUTCOME}

I will carry this piece of work through to the end on my own. You are giving me a standing approval for up to 30 days that covers every merge and every dispatch listed, posted publicly on the epic. It ends on {EXPIRY}, or sooner if the work is finished. Here is everything I may do without asking you again:

{SCOPE_ITEMS}

I will only come back to you for money, what is in or out of scope, how it looks or reads, legal exposure, anything that could lose your customers' data, or anything I am not allowed to do for you. You can tell me to stop at any time. Is that OK?
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

One plain sentence in the session after EVERY delegated act, and the same sentence in the receipt comment of section 8. The
run summary lists every delegated act.

```text
Merged <title> under your standing approval; it is live and healthy.
Rolled back <title> because <plain reason>.
You asked me to stop, so I removed the standing approval, switched off the automatic merges I had set up and cancelled the runs I had started. Still running or still waiting: <what could not be stopped, or nothing>.
```

## 7. Stall, re-confirm, resume

When the verifier answers `edited`, `expired` or `epic-closed`, or the comment is gone, the agent says one stall sentence,
the CTO returns the epic-start wording for the calling skill to ask again, and the calling skill asks a REAL operator
question: a new record is written only after a fresh `Yes` to that question, through `render`. The CTO never re-records, and
an earlier answer is never reused. The work then resumes from the first unticked checklist item. The verifier is re-run
immediately before every act, so a stop between verification and execution cannot be raced past by more than that instant.

### Stopping

A conversational "stop" (or "take back the approval") makes the agent do all of the following, in this order; stopping
reduces authority, so none of it needs a delegation. Deleting the comment is allowed, editing it is excluded.

1. Delete EVERY delegation marker comment on the epic (`gh api -X DELETE repos/{owner}/{repo}/issues/comments/<id>`, one
   per comment from the discovery command of section 1, not only the newest), so that nothing older can take over.
2. List every merge it armed with `gh pr merge --auto` (the open changes whose auto-merge is set) and disarm each with
   `gh pr merge <N> --disable-auto`.
3. Cancel every workflow run it dispatched that is still queued or running (`gh run cancel <run-id>`).
4. Say, in the stop sentence of section 6, which of these could not be stopped (a merge that already happened, a run that
   already finished). Deleting the comment alone does not stop a merge that is already armed or a run that has started.

### Reason tokens

Every reason token the verifier can print, and the two the hold evaluator and the ship gate print when the verifier gave no
usable answer (`no-answer`, `verifier-error`), has one plain sentence here. The agent says that sentence, never the token.

| Reason | What the operator is told |
|---|---|
| `bad-url` | I was given a link to the standing approval that is not a link to a comment on this project, so I have paused and done nothing. |
| `wrong-repo` | The standing approval I was pointed at belongs to a different project, so I have paused and done nothing. |
| `comment-unreadable` | I cannot find your standing approval any more, it may have been deleted, so I have paused and done nothing until you confirm it again. |
| `api-error` | I could not reach GitHub to check your standing approval, so I am waiting and have not done anything. |
| `tool-missing` | A tool I need to check your standing approval safely is not installed on this computer, so I have not done anything. |
| `usage` | I asked for the check in the wrong way, which is my mistake, so I have not done anything and will try again. |
| `no-marker` | The note I found is not a standing approval that I recognise, so I have not done anything. |
| `wrong-issue` | The standing approval is attached to a different piece of work than the one I was told about, so I have paused and done nothing. |
| `epic-is-pr` | The standing approval was left on a proposed change instead of on the piece of work itself, so I have paused and done nothing. |
| `bot-author` | The standing approval was not written by a person, so I have not used it and have done nothing. |
| `not-admin-author` | The standing approval was not written by someone who runs this project, so I have not used it and have done nothing. |
| `edited` | Your standing approval was changed after you gave it, or I cannot tell that it was not, so I have paused and done nothing. Please confirm it again and I will carry on. |
| `no-quote` | Your standing approval does not show your own words, so I have not used it. Please confirm it again. |
| `quote-too-short` | Your standing approval shows too little of what you actually said to prove what you agreed, so I have not used it. Please confirm it again. |
| `no-confirmation` | Your standing approval does not show a clear Yes from you, so I have not used it. Please confirm it again. |
| `no-scope-item` | Your standing approval does not list what I may do, or does not list the step I am about to take, so I have not done it. |
| `excluded-incomplete` | Your standing approval does not carry the exact list of things I may never do for you, so I have not used it. Please confirm it again. |
| `expiry-missing` | Your standing approval has no valid end date, so I have not used it. Please confirm it again. |
| `expiry-too-long` | Your standing approval runs for more than 30 days, which is not allowed, so I have not used it. Please confirm it again. |
| `expired` | Your standing approval has run out, so I have paused and done nothing. Please confirm it again and I will carry on. |
| `before-delegation` | The step is dated before your standing approval was given, so it cannot count as covered by it. |
| `epic-closed` | This piece of work is finished, so the standing approval has ended. |
| `envelope-missing` | I cannot find the written plan for this step, so I have not done it. |
| `envelope-not-committed` | The written plan for this step is not saved in the project history yet, so I have not done it. |
| `envelope-outside-repo` | The written plan for this step is not inside this project, so I have not done it. |
| `envelope-not-regular-file` | The written plan for this step is a shortcut or a folder instead of a normal file, so I have not done it. |
| `parse-ambiguous` | The written plan holds several steps and I cannot tell which one to use, so I have not done any of them. |
| `envelope-delegation-mismatch` | The written plan for this step points at a different standing approval than yours, so I have not done it. |
| `envelope-incomplete` | The written plan for this step is missing a required part, so I have not done it. |
| `epic-mismatch` | The written plan for this step belongs to a different piece of work than your standing approval, so I have not done it. |
| `rollback-unnamed` | The written plan for this step does not say how to undo it, so I have not done it. |
| `non-delegable-command` | This step is on the list of things I am never allowed to do for you, so I have not done it. |
| `command-not-delegable` | This step is not one of the few kinds of step a standing approval can cover, so I have not done it and I need you. |
| `scope-mismatch` | This step is not what the item in your standing approval says it covers, so I have not done it. |
| `command-not-in-envelope` | The step I was about to take is not word for word what the written plan says, so I have not done it. |
| `no-answer` | I did not get an answer when I checked your standing approval, so I am waiting and have not done anything. |
| `verifier-error` | The check of your standing approval gave an answer I could not understand, so I am waiting and have not done anything. |

## 8. The execution receipt

After every delegated act the CTO posts one comment on the epic. Its first line is exactly this, with each value filled in.
A value has no spaces, except that `envelope` may hold a space inside its optional `#title`:

```text
<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<verified-envelope-sha256> result=ok|rolled-back run=<url|none> -->
```

followed by one plain sentence from the execution log sentences of section 6. `delegation` is the delegation comment URL,
`envelope` is the path with an optional `#title`, exactly the string passed to `--envelope`; the receipt parser compares it
exactly with the row's envelope, never as a prefix. `sha256=<verified-envelope-sha256>` is the value of the verifier's
`verified-envelope-sha256:` line, copied unchanged, `result` is `ok` or `rolled-back`, and `run` is the URL of the workflow run the
act started, or `none`. The calling skill prints the same sentence in the session and lists the delegated acts in its run
summary.

The Technical-Ruling Gate requires, for every delegation row that carries `ran <ISO time>`, a receipt on the epic whose
four values equal the row's delegation URL, the row's envelope path, the verifier's `verified-envelope-sha256` for that
envelope and a result of `ok` or `rolled-back`, and whose author is an `OWNER`, `MEMBER` or `COLLABORATOR`. A missing
receipt is `receipt-missing`, a mismatch `receipt-mismatch`, a receipt that cannot be read `receipt-unreadable`; each stops
the ship. This checks that a receipt exists, is attributable and matches. It is not proof of what ran; a hook-written
receipt is the stronger follow-up (#10361).

The `sha256` covers the WHOLE envelope file at `HEAD`, not only the section. Any later commit that edits that file changes
the hash, and a receipt posted before the edit then no longer matches the file as it stands. So keep each envelope in a
file of its own, do not edit it after the first act, and re-verify immediately before every act (an act keeps its receipt
only if the receipt rows were checked while the verified text was still the file's current text).

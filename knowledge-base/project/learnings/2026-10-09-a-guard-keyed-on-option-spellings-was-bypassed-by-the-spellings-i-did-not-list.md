# Learning: a guard keyed on option spellings is bypassed by the spellings you did not list

## Problem

Slice S3 of the argv-credential sweep (tracker #9597, PR #9811) added a sourced library, `scripts/lib/bearer-curl.sh`, that puts a
credential on curl's stdin config instead of its argument list. To stop a caller undoing that, the library checks the arguments the
caller passes after `--` (`_bc_tail_ok`). Three review rounds each found the guard narrower than the property it named:

- **First version:** matched whole tokens against a deny list (`-H`, `--header`, `-d @-`). The attached forms (`-Hx`, `-d@-`),
  clustered short flags (`-sSH x`), `=`-joined long options (`--header=x`) and several option families all passed.
- **Second version:** parsed clusters and attached values, but matched long options by exact name. The runner's curl 8.5 accepts any
  unambiguous prefix (`--verb` ran verbose; `--locat` was only rejected as *ambiguous*), so the verbose and redirect refusals were
  bypassable on the very curl that runs in CI. Several stdin-body spellings (`-F 'a=<-'`, `-F 'a=@-;type=…'`, `--expand-data @-`,
  `/dev/./stdin`), a literal `--` (which turns the library's own `--config -` into URLs and silently drops the credential header) and
  a value-taking option left without its value also passed.
- **The tests:** the table of forbidden arguments said "every deny-list alternative", but mutants deleting `--proxy-insecure`,
  `x-gitlab-token`, `/proc/*` or a value-taking letter stayed green, and two rows were vacuous (see Session Errors).

## Solution

- Match long options by **prefix** of the full name (and by family stem), because the tool accepts abbreviations; walk short-option
  clusters letter by letter and treat the rest of the token as the attached value; consume the next token as the value of a
  value-taking option so a value that looks like an option is not judged as one; refuse a literal `--` and a dangling value.
- Judge a request body by what it **reads** (`@-`, `<-`, `name=-`, device spellings, with `;type=` modifiers dropped), not by a
  list of option names.
- One test row per alternative, then **delete each alternative from a scratch copy of the library and require a red row**. A
  stem-only family needs a row only the stem can satisfy (`--proxy-anyauth`, `--proxytunnel`), otherwise the exact-name entry
  hides a deleted stem.
- Where a mutant survives because two rules cover the same input (the explicit `--` arm and the "`--` is a prefix of every name"
  accident), say so in the commit rather than deleting the explicit one.

## Key Insight

A guard that bans spellings establishes nothing about the property: curl, like most CLIs, has several grammars for one option
(separate, attached, clustered, `=`-joined, abbreviated, aliased), and the guard's author tests the grammar they were thinking
about. State the property in one sentence ("nothing after `--` can put a credential on argv or consume the config channel"), then
enumerate the tool's *grammars* before the tool's options, and run the guard on the **runner's** version of the tool, not the dev
host's (curl 8.22 rejects abbreviations that 8.5 accepts). Replay every real call site through the guard first, so a stricter
rule cannot refuse a legitimate argument list.

The same session produced three smaller instances of the class "a check certified something narrower than its name":

- a lint matched head-ref *names* (`head_sha`, `head_ref`) where the property is "the checkout is not the default branch", so
  `refs/pull/N/merge` and step outputs passed; the fail-closed form is an allowlist of the default ref. On `pull_request_review*`
  even the implicit and `github.sha` refs are the PR's merge ref.
- a sparse-cone check used a string prefix (`startswith("scripts")`), then `scripts/ci` passed; judge path segments.
- a blast-radius sentence counted files that *name* the library (12) where the reader needs files *affected* (22) and call steps
  (26): state which set a number measures.

## Session Errors

**The trailing-newline test row built its value with `V="$(printf 'tok\n')"`** — command substitution strips trailing newlines, so
the row passed on a library with no trim at all. The SIGPIPE row exported a 200 KB environment string, over Linux's 128 KiB
per-string limit, so `bash -c` failed to exec and the library never ran. Recovery: build the value with `$'…\n'`; use a 100 KB
value and a curl that exits before reading its config, with a positive control that the run reached curl's own error, plus a mutant
row proving the row can fail. Prevention: every new assertion about library behaviour needs a control that the library actually ran,
and a mutation that turns it red.

**An unmeasured causal claim in the ADR and header ("curl itself trims a header value")** was written to justify a decision and was
false (curl 8.22 sends the trailing blank verbatim). Recovery: measured it, rewrote the reason. Prevention: the existing rule
"falsify each causal sentence the diff adds with a command" — the seats that ran the command found it, the author did not.

**I edited the sweep battery while a background gate run was reading it**, voiding that run's battery and shellcheck results.
Recovery: reran both. Prevention: no repository writes while a background run is in flight (already in the review skill's sharp edges).

**A ratchet run during an unresolved merge** reported `orphan=1` and `rulee=2` from the conflicted state. Recovery: resolved the
baseline conflict, committed the merge, reran. Prevention: run ratchets only after the merge commit exists (S2 lesson 9).

**`cd` into a skill's references directory persisted in the Bash tool**, so the next calls ran from the wrong directory. Recovery:
`cd` back and use absolute paths. Prevention: use `git -C`/absolute paths, or a subshell, for one-off reads.

**My own probes were wrong twice** — a call-site extractor that failed on unbalanced quotes, and mutated suite copies in scratch
whose repo root resolved to the scratch directory (85 assertions instead of 86, misread as a mutation effect). Recovery: lenient
parse; pin `ROOT`/`SUT` in the copy. Prevention: run every instrument against a known-positive and a known-negative first.

**The session restart swept the scratchpad**, losing the panel reports and stopping the verification seat. Recovery: respawned the
seat with its report under `/var/tmp`. Prevention: keep reports and briefs outside `/tmp` (already documented).

**One sweep-battery row (`evaluate: a probe that uses a curl flag the shim does not model`) failed once in four runs** with an
extra `bash-error`, and passed on the next three. Not diagnosed; the row is in an older stage this slice did not touch. Prevention:
none yet — if it recurs, capture the row's stderr before rerunning.

**`rm -f $D/*` was blocked by the safety check** and `tar` over `git ls-files` (no `-z`) choked on a unicode path. Recovery: dropped
the removal (fresh directory), used `-z`/`--null`. Prevention: `"${D:?}"/*` or a literal path; always `-z` with `git ls-files`.

## Tags

category: security-issues
module: scripts/lib/bearer-curl.sh, scripts/lint-workflow-local-action-checkout.py

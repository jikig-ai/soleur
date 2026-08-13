# Upstream defect evidence — `anthropics/claude-code`

Tracker: #7490 part 3. Every reading below was taken on CLI `2.1.228` and is reproduced from
`measurements.md` in this directory. Nothing here is inferred; each section states the command that
produced it.

**Scrub.** These bodies are posted to a third party's PUBLIC repository and are this change's named
leak vector. Every section is scrubbed against all four exposure categories from the plan's
`## User-Brand Impact`: absolute home paths in either spelling, the names and layout of unrelated
local repositories, install timestamps, and machine identifiers. The scrub is asserted against this
file, and re-asserted against each body **as posted** (fetched back with `gh api`), because the
posted body is the artefact that leaks and the local copy is not proof about it.

The canonical check lives in `scripts/upstream-report-scrub.sh` rather than being quoted here. That
is not tidiness: an earlier draft of this file inlined the grep, and the pattern literals inside the
command matched *themselves*, so the file failed its own scrub for its description of the scrub. A
check that cannot be written down next to what it checks belongs in a script.

```console
$ bash scripts/upstream-report-scrub.sh knowledge-base/project/specs/<branch>/upstream-reports.md
SCRUB OK: 0 exposures in 1 file
```

---

## Section-to-posting mapping

Four evidence sections, **two** postings. The plan anticipated three; section 4 was withdrawn on
measurement, which is recorded here rather than quietly dropped.

| # | Section | Destination | Status |
|---|---|---|---|
| 1 | Metadata does not follow delivered content, plus the two-field non-exclusive identity recording and the compound-version half | comment on **76882** | to post |
| 2 | The 120 s default clone timeout is insufficient for a repo of this size | comment on **77927** | to post, combined with §3 |
| 3 | SSH-first transport; the HTTPS fallback is reached only after the SSH attempt terminates | comment on **77927** | to post, combined with §2 |
| 4 | A failed refresh moves the checkout to `.bak` and a later invocation deletes both | **not filed** | withdrawn — see §4 |

§2 and §3 are one root-cause argument split for readability, so they post as a single comment.

No DOCS issue is opened for `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`: upstream **58859** already tracks
it. The transport evidence folds into §3 instead.

---

## §1 — Recorded identity does not follow delivered content (→ 76882)

Two independent fields carry identity, their population rules are undocumented and **not mutually
exclusive**, and only one of them is read by the update comparator.

A scratch install with no prior CLI state recorded:

```
version       = 43c7d3d79542-31fddb37
gitCommitSha  = 43c7d3d79542e0909b3825ec17a3d58e193524de
```

A second install, later the same day, at a different delivered commit:

```
version       = 0d6443960662-31fddb37
gitCommitSha  = 0d644396066262b32884a2faec10e317857bea5e
```

**The `version` string is a compound, and only its leading half varies with content.** The
12-character half equals the delivered commit both times, confirmed against
`git ls-remote https://github.com/jikig-ai/soleur.git HEAD`. The 8-character half is
**byte-identical across two different delivered commits**, so it does not identify the content it
appears to identify. What it does encode is not established here, and is not guessed.

Separately, a pre-existing install on the same machine carried `version: 0.0.0-dev` **and** a valid
40-character `gitCommitSha` simultaneously — so the two fields are not alternatives, and a consumer
cannot infer from the presence of one that the other is absent or stale.

**Why this matters for 76882.** `claude plugin update` compares version STRINGS. An entry whose
recorded `version` is constant compares equal on every run and the update short-circuits, reporting
success while delivering nothing, with no error and no visible symptom — even though a correct
`gitCommitSha` sits beside it in the same record showing the install is stale.

**Reproduction of the projection property** — `claude plugin list --json` is not an independent
authority, so reading the CLI does not escape the metadata:

```console
# mutate installed_plugins.json to a sentinel version and installPath
$ claude plugin list --json   # output changes verbatim, then reverts when the file is restored
```

---

## §2 — The 120 s default clone timeout is insufficient for a repo of this size (→ 77927)

Measured **329 s** to clone the monorepo against the CLI's 120,000 ms default — approximately
2.7x over. This is **deterministic, not flaky**: the payload is ~181 MiB and the operation cannot
complete inside the default on this repository at all.

The failure is not silent, and the message names the right knob
(`Set CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS to increase it`), so this is a defaults report rather than a
diagnosis one. What makes it worth filing is that the affected operation is a first-time
`marketplace add`, i.e. the very first thing a new user does.

Falsifiability instrument used throughout, so a timeout can be forced rather than waited for:

```console
$ CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=1 claude plugin marketplace add <owner/repo>
✘ Failed to add marketplace: ... Git clone timed out after 0s ...
rc=1, 3 s
```

A raised timeout proves nothing on its own — success at the default and success at a raised value
are indistinguishable — which is why every claim here rests on a value that forces failure.

**Also measured: the timeout is configurable from a settings file, which is not documented.** With
no such variable in the process environment, a user-scope `settings.json` containing
`{"env": {"CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS": "1"}}` produced the timeout above (rc=1, 4 s), while
the same scratch state with `{}` completed normally (rc=0, 10 s). So the `env` block **does** reach
the plugin git path.

**Explicitly NOT claimed:** whether that same block reaches the BACKGROUND auto-update refresh,
which runs without the user's shell. That is the case that would actually matter for an unattended
install, and it could not be triggered deterministically here — `claude plugin list` does not drive
a refresh. It is stated as unverified rather than inferred from the foreground result.

---

## §3 — SSH-first transport, with HTTPS reached only after the SSH attempt terminates (→ 77927)

The CLI constructs an **SSH** remote from an `owner/repo` argument:

```
Cloning via SSH: git@github.com:<owner>/<repo>
```

and, when that attempt terminates, logs:

```
SSH clone failed, retrying with HTTPS
```

Measured both ways. On a machine whose git config rewrites `git@github.com:` to `https://github.com/`,
the SSH form never reaches the network. With that rewrite neutralised and SSH forced to fail fast
(`BatchMode=yes`), the fallback engaged and the clone completed in 7 s.

**The hypothesis this ordering produces, offered as a mechanism proposal and labelled as such:**
because the HTTPS fallback is reached only *after* the SSH attempt terminates, an environment where
SSH **stalls** rather than fails fast consumes the clone budget before HTTPS is ever tried. That is
the shape 77927 reports.

**This is not verified here, but 77927 already reports the symptom it predicts.** That issue's own
title reads *"git clone stalls in non-interactive SSH, killed at ~60s timeout"* — a stall in
non-interactive SSH is exactly the case where this ordering consumes the budget before HTTPS is
tried. So the two halves fit: they observed the stall without the transport ordering, and this
report supplies the ordering without the stall.

The distinction still matters and is kept: the probes here forced SSH to fail FAST
(`BatchMode=yes`), so the stall itself was **not reproduced on this machine**. What is offered is
the mechanism plus the fail-fast measurement, as a proposal to check against their reproduction —
not a diagnosis of their bug.

Setting `CLAUDE_CODE_PLUGIN_PREFER_HTTPS` skips the SSH attempt rather than surviving it. That
variable is undocumented; upstream 58859 already tracks its documentation.

---

## §4 — WITHDRAWN: the failed-refresh `.bak` destruction (not filed)

The tracker proposed filing a new issue for: *a failed marketplace refresh moves the checkout to
`.bak`, then a later invocation deletes both — fail-open and destructive.*

**It is not filed, because it did not reproduce on 2.1.228.** Three independent forced-failure
instruments, each against a scratch checkout carrying a sentinel file that survives an in-place
reconcile but cannot survive a re-clone:

| Instrument | Checkout | Sentinel | `.bak` |
|---|---|---|---|
| `add --sparse` with the clone aborted before it starts | intact | intact | none |
| `marketplace update` with the remote pointed at a nonexistent repository | intact | intact | none |
| `add --sparse` with the clone failing mid-flight | intact | intact | none |

Both arms of `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` — set and unset — behaved identically
in every instrument, because the branch it governs never executed.

The strings **are** present in the 2.1.228 bundle: a `will re-clone` path, a
`sparse-checkout reconcile requires re-clone` path, a `.bak` rename, and a later removal of both a
checkout and its `.bak`. But a string is not a behaviour, and the removal of both sits in what reads
as a cleanup/removal path where deleting both is the correct thing to do.

**Opening an issue on a third party's repository asserting a destructive failure that this session
could not reproduce would be an unverified inference stated as fact.** It is recorded here instead.
If it is reproduced later — on the version the original observation came from, or with an instrument
that reaches the rename before the clone fails — this section is the evidence to file with.

**What was measured and IS reportable from this area** is narrower and is already covered by §2:
applying `--sparse` to an *existing* checkout forces a full re-clone rather than reconciling in
place (sentinel gone, `.git` inode changed, sparse-checkout file created). On a repository whose
clone takes 329 s against a 120 s default, that turns a documented mitigation into an operation that
cannot complete.

---

## Posting log

Posted 2026-08-13 with the operator's explicit approval, from the operator's GitHub account. Each
body was fetched back with `gh api` and re-scrubbed **as upstream stores it** — the posted body is
the artefact that leaks, and the local copy is not evidence about it.

| Section(s) | Destination | URL | Scrub re-check |
|---|---|---|---|
| §1 | 76882 | [comment 5273479508](https://github.com/anthropics/claude-code/issues/76882#issuecomment-5273479508) | PASS — 0 exposures, 2345 bytes as stored |
| §2 + §3 | 77927 | [comment 5273482066](https://github.com/anthropics/claude-code/issues/77927#issuecomment-5273482066) | PASS — 0 exposures, 3406 bytes as stored |
| §4 | not filed | — | n/a (withdrawn on measurement, see §4) |

Both routes landed, so the follow-through's posting check is satisfied. §4 stays unfiled by
decision rather than by omission; if it is ever reproduced, §4 is the evidence to file with.

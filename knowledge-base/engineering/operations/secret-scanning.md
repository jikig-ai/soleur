---
title: Secret-scanning floor — operator runbook
status: active
audience: operators, on-call, contributors
related:
  - https://github.com/jikig-ai/soleur/issues/3121
  - https://github.com/jikig-ai/soleur/issues/3874
  - https://github.com/jikig-ai/soleur/issues/3877
  - knowledge-base/engineering/operations/golden-tests.md
last_updated: 2026-05-16
---

# Secret-scanning floor

This document is the operator runbook for the secret-scanning floor introduced
in [#3121](https://github.com/jikig-ai/soleur/issues/3121). It covers:

- The rule pack and its allowlist semantics.
- The `# gitleaks:allow` waiver discipline.
- The decision tree when an alert fires (rotate vs. history-rewrite).
- Per-token rotation playbooks.
- The notification flow (Discord, GDPR).
- The forensics workflow (why we don't upload `--report-path` JSON).
- Rule-pack maintenance (adding a new token shape).

## Architecture

Two enforcement layers, one source of truth.

| Layer | Where | When | Bypassable | Purpose |
|---|---|---|---|---|
| **Lefthook `gitleaks-staged`** | local pre-commit | every `git commit` | yes (`--no-verify`, hook removal) | fast feedback before a leak hits the local index |
| **Lefthook `lint-fixture-content`** | local pre-commit | every `git commit` | yes | catches semi-sensitive shapes (real emails, prod-shape UUIDs, Supabase project refs) gitleaks misses |
| **CI `secret-scan` workflow** | GitHub Actions | PR + merge_group + push:main + weekly cron | no (CODEOWNERS-protected) | load-bearing enforcer; the rule's `[hook-enforced: ...]` tag points here |

Each trigger scans a **different set of commits** — see
[Ref scope per event](#ref-scope-per-event-which-commits-each-trigger-actually-scans)
below. That distinction is load-bearing: it is what determines whether a finding
on an in-flight branch can redden `main`'s gate.

The local hook is a **fast-feedback courtesy**, not a safety floor. The CI
workflow is what stops a secret from reaching `main`. Operators MUST NOT
disable the CI job to "unblock" a PR; if a finding is a false positive, add
a per-rule `[[rules.allowlists]]` block in `.gitleaks.toml` or a `# gitleaks:allow`
waiver in the source file.

## Ref scope per event: which commits each trigger actually scans

`gitleaks git` scans a **commit range**, not the working tree. Fixing a file in a
later commit does not clear a finding introduced by an earlier one — which is why
a red gate is sometimes unfixable by editing the file it names.

| Event | Range scanned | Invocation |
|---|---|---|
| `pull_request` | the PR diff, `base..head` | `--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"` |
| `pull_request` — **full tree** | the checked-out worktree | `gitleaks dir .` |
| `merge_group` | the merge-queue candidate diff, `base..head` | `--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"` |
| `merge_group` — **full tree** | the checked-out worktree | `gitleaks dir .` |
| `push` (main) — **blocking** | **main's ancestry only** | `--log-opts="--no-merges HEAD"` |
| `push` (main) — **full tree** | the checked-out worktree | `gitleaks dir .` |
| `push` (main) — **advisory** | **every fetched ref, merge commits included** | `-v --log-opts="-m --all"`, `\|\| echo ::warning` — never fails the job |
| `schedule` (weekly) | **every fetched ref, merge commits included** | `--log-opts="-m --all"`, plus `-v` |
| `schedule` (weekly) — **full tree** | the checked-out worktree | `gitleaks dir .` |

The `gitleaks dir` rows are the remedy for merge-commit-exclusive content on the
PR side (see the next section). They scan the **tree**, not a commit range, so
they catch anything still present in the checkout regardless of which commit
introduced it — and, unlike a range scan, a fix at the tip genuinely clears them.

`-m` is carried by the two **non-blocking** range scans — the weekly cron and the
push:main advisory sweep — and by no blocking one. That split is deliberate; see
"Why no BLOCKING range scan gets `-m`" below.

`push:main` runs **three** invocations on purpose (blocking ancestry, full tree, advisory sweep). Blocking *verdict* scope and scan
*breadth* are independent axes: the first decides whether `main`'s required check
goes red (main's ancestry only — the #6706 fix), the second keeps full all-refs
visibility as a `::warning` so a finding on a pushed branch that never opened a PR
still surfaces within minutes. The advisory step ends in `|| echo`, so it cannot
fail and cannot redden `main` no matter what it finds.

**Why `push:main` is explicitly scoped ([#6706](https://github.com/jikig-ai/soleur/issues/6706)).**
Bare `gitleaks git` defaults to walking every ref the checkout fetched, and
`actions/checkout` runs with `fetch-depth: 0` — which fetches *all* remote
branches. So before this was scoped, a finding on an unmerged in-flight branch
turned `main`'s required check red for a commit that had never merged, and the
output named no branch.

Reproduce the difference on any checkout that has an off-main ref present (exact
totals grow with `main`, so compare the two runs against each other, not against
a remembered number):

```bash
gitleaks git --redact --no-banner --exit-code 1                            # walks ALL refs
gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges HEAD"  # main only
```

The bare form scans strictly more commits — the ones reachable only from unmerged
remote-tracking branches — and it is exactly those extra commits that could redden
`main`. Compare the two runs against each other rather than against a remembered
number: the totals track `main`'s growth and go stale within days.

**Triaging a red weekly cron.** The cron keeps all-refs breadth on purpose — it
is the retroactive net that re-scans history against the *current* rule pack. `-v`
makes that breadth diagnosable, printing per finding:

```
RuleID:      <rule>
File:        <path>
Line:        <n>
Commit:      <full sha>
Fingerprint: <sha>:<file>:<rule>:<line>
```

Resolve the owning branch from the SHA:

```bash
git branch -r --contains <Commit>
```

If the answer is an unmerged feature branch, the finding is **not** on `main` — fix
it on that branch (or delete the branch); do not treat it as a `main` incident.

**Do this resolution step BEFORE the `## When an alert fires` decision tree below.**
That tree routes the `push:main / weekly cron` column straight to *ROTATE NOW /
assume exfil*, which is correct only once you know the finding is actually in
`main`'s ancestry. The all-refs surfaces (the advisory sweep and the cron) can both
report a commit that never merged. Resolve the owning ref first, then enter the
tree. (A secret pushed to any branch of a public repo still warrants rotation — but
"rotate" and "treat as a `main` incident" are different responses.)

**Un-PR'd branches: reduced, not removed.** A branch pushed to `origin` with no PR
opened is invisible to the `pull_request` job, and since #6706 it no longer
contributes to `main`'s **blocking** verdict. It is still swept on every push to
`main` by the advisory step above, which emits a `::warning` naming the commit —
so the practical detection window is minutes, not the weekly cron. What is
genuinely given up is *enforcement*: nothing blocks on such a finding, and if the
branch is deleted before anyone reads the warning it goes unnoticed. That is the
deliberate trade: `main`'s required check answers "is `main` clean?", and a branch
that never merged cannot make it red.

Note this is a detection question, not a `main`-integrity one — on a public repo a
secret pushed to any branch is already exposed at push time, so rotation is the
remedy regardless of which gate reports it.

**Blind spot: merge-commit-exclusive content.** `gitleaks git` drives `git log -p`
without `-m`/`--cc`, so a merge commit contributes **no** patch content to any
scan. Measured on `cbd6c948d`:

```bash
# patch portion only — everything from the first `diff --git` onward
git log -p -1 cbd6c948d          | sed -n '/^diff --git/,$p' | wc -c   # -> 0
git log -p -1 cbd6c948d^         | sed -n '/^diff --git/,$p' | wc -c   # -> 10901
```

(Note the total output for the merge is 302 bytes, not 0 — that is the commit
header alone, with zero diff beneath it. Measure the patch portion, or the
result looks like a contradiction.) Content introduced *only* by a merge commit's own tree — the
plausible shape being a hand-resolved conflict — was therefore invisible to **every**
job, including the weekly cron. `--no-merges` removes nothing that was ever
scanned. This is pre-existing and not a consequence of the #6706 scoping; it
matters because `main` genuinely carries merge commits (`allow_merge_commit` is
enabled).

**CLOSED by [#6721](https://github.com/jikig-ai/soleur/issues/6721).** The weekly
cron now walks `--log-opts="-m --all"`, and every job gained a `gitleaks dir .`
full-tree step. Measured on a purpose-built fixture (a genuine 2-parent merge
whose secret is in neither parent), pinned by
`plugins/soleur/test/gitleaks-merge-commit.test.sh`:

| walk | rc | detects merge-exclusive secret? |
|---|---|---|
| `--no-merges HEAD` (the old shape) | 0 | no |
| bare `HEAD` | 0 | no |
| `-m` | 1 | **yes** |
| `-m --first-parent` | 1 | yes |
| `--cc` | 0 | **no — see the trap below** |
| `gitleaks dir .` | 1 | yes (content still on the tree) |

**TRAP: `--cc` is NOT an equivalent of `-m`.** It looks like one, and it is a
silent no-op. On the same fixture it emits 195 bytes of patch content that
visibly contain the secret, and gitleaks detects **nothing** (rc=0) — its diff
parser does not consume combined-diff `@@@` format. Byte volume is not
detection. Shipping `--cc` as a cheaper `-m` would install a fresh gate that
cannot fail, which is the exact defect class this section documents. The test
asserts both halves (bytes > 0 **and** rc == 0) so the trap cannot be re-read as
"`--cc` simply sees nothing".

**Why only the cron gets `-m`.** `-m` is the wrong remedy for the PR and
merge_group jobs, because GitHub sets `BASE_SHA` to
`pull_request.base.sha` — main's **tip** at PR-event time, not the merge-base. A
routine "merge main into my branch" therefore puts main's own commits inside
`BASE..HEAD`. Without `-m` the merge commit contributes no patch and they stay
invisible; with `-m` the merge is diffed against each parent, and the
merge-vs-feature diff replays everything main brought in. Measured on a clean
main-sync fixture with no conflict anywhere:

| arm | log-opts | rc |
|---|---|---|
| shipped | `--no-merges BASE..HEAD` | 0 — main's secret not attributed to the PR |
| candidate | `-m BASE..HEAD` | 1 — main's secret counts against the PR |

So `-m` on the PR range would make every branch that syncs main inherit main's
findings as its own. The PR side gets `gitleaks dir` instead: an understood
failure mode (it scans the tree, so it misses content that was removed before
the tip) rather than a false-positive generator. Pinned by T7 of the same suite,
including preconditions — an earlier attempt at this measurement returned rc=0
on both arms because the fixture never reached the state under test, and a
silent rc=0/rc=0 reads exactly like "no coupling".

## Rule pack

`.gitleaks.toml` extends the upstream default pack and adds 13 project-specific
rules covering token shapes that appear in our `prd` Doppler config. See the
file for the full list; key categories:

- **Soleur BYOK** — `sk-soleur-` prefix.
- **Doppler** — `dp.{pt,st,sa,ct}.` prefix (personal / service / service-account / CLI tokens).
- **Supabase** — service-role JWT (HS256), anon JWT, access token (`sbp_`).
- **Stripe** — webhook secret (`whsec_`). Default pack covers API keys (`sk_live_`, etc.).
- **Anthropic / Resend / Sentry / Cloudflare / Discord webhook**.
- **Database URL** with embedded password.
- **VAPID** web-push private key.

### Allowlist semantics — read this carefully

gitleaks v8.24.2 supports **per-rule** `[[rules.allowlists]]` blocks. v8.25+
adds a top-level `[[allowlists]]` with `targetRules = [...]` syntax — we are
NOT on v8.25+, so the per-rule form is the only option.

**Default-pack rules do NOT inherit our project allowlists.** This is
intentional. Examples:

- An AWS access key under `__goldens__/foo.snap` would still trigger the
  default pack's `aws-access-token` rule. AWS keys never belong in fixtures
  even synthesized — if you need one for a contract test, paste it through
  the official sandbox docs and document the source.
- Our 12 custom rules each carry the same `paths` allowlist:
  - `__goldens__/.*` — golden snapshots from the A2 surface (#3121, #3143, #3144).
  - `(__snapshots__|__goldens__)/.*\.snap$` — anchored snapshot files.
  - `apps/web-platform/test/__synthesized__/.*` — fixtures with semi-sensitive
    shapes that need to look real (e.g., a JWT shape for a parser test).
  - `reports/mutation/.*` — Stryker output (also gitignored; defensive belt-and-suspenders).
- Two custom rules carry an **additional** carve-out for
  `knowledge-base/project/learnings/.*\.md$`, because learning files routinely
  document credential-shape symptoms in recovery runbooks:
  - The `private-key` rule — motivated by literal `BEGIN/END PRIVATE KEY`
    blocks in symptom reproductions (e.g.,
    `2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md`, added via
    [#3268](https://github.com/jikig-ai/soleur/issues/3268) /
    [#3281](https://github.com/jikig-ai/soleur/issues/3281)).
  - The `database-url-with-password` rule — motivated by asterisk-redacted
    Postgres connection strings pasted from operator `doppler run` output
    (e.g., `2026-05-16-supabase-mcp-oauth-fallback-to-doppler-database-url.md`,
    motivated by issue [#3874](https://github.com/jikig-ai/soleur/issues/3874),
    landed in PR [#3875](https://github.com/jikig-ai/soleur/pull/3875)).
- Default-pack rules (AWS, Stripe, etc.) and the other 12 custom rules
  (Doppler, Supabase JWT, Anthropic, Resend, Cloudflare, Sentry, Discord
  webhook, VAPID, JWT, generic-API-key, Soleur BYOK, Stripe webhook secret)
  remain LIVE on the learnings tree — only literal `BEGIN/END PRIVATE KEY`
  blocks and `postgres(ql)?://user:password@host` URLs are silenced.

`apps/web-platform/test/fixtures/qa-auth.ts` is **NOT** allowlisted. It is a
real auth-test fixture that interacts with a live Supabase test project; if
it ever needs a synthesized token, the file should move under
`apps/web-platform/test/__synthesized__/`.

**Path carve-out: `^plugins/soleur/skills/review/SKILL\.md$`**
([#6723](https://github.com/jikig-ai/soleur/issues/6723)), on
`database-url-with-password` only.

That file documents the DSN allowlist bypass in prose, using a
credential-shaped example. Widening the rule to span to the last `@` (the #6723
fix) turned its own example into a finding — on commit `48b8bc4a5`, which is
already on `main`. A line-level `# gitleaks:allow` **cannot** clear it: history
scans read the old blob, and the old blob carries no waiver. The only
alternatives were rewriting history or a path predicate, since path predicates
match identically across every commit.

The `^` and `$` are load-bearing. gitleaks matches `paths` entries as a
**search** against the scan-root-relative path, so unanchored, any parent
directory launders a real DSN — measured: `evil/plugins/soleur/skills/review/SKILL.md`
carrying a real credential was silenced without the anchors and is detected with
them.

Scope cost: exactly one file, blinded to exactly one rule. That file is skill
prose and never a credential carrier, and every other rule still applies to it,
alongside lint-fixture-content, GitHub push protection, and CODEOWNERS on
`.gitleaks.toml`. Pinned by T10 in `plugins/soleur/test/gitleaks-rules.test.sh`,
which asserts both the entry count and that the carve-out stays anchored.

The alternative — a finding-scoped `.gitleaksignore` entry — is a live open
question rather than a settled rejection; see the PR's decision-challenges
record. It was inherited from #6706's rejection ("the fingerprint embeds the
commit SHA, so survival is merge-strategy-dependent"), a premise that does not
hold here because `48b8bc4a5` is already an ancestor of `main` and its SHA is
frozen. It remains unmeasured, and the anchored path entry is what ships.

### Placeholder-regex allowlist — `database-url-with-password`

Orthogonal to the path carve-out above, the `database-url-with-password` rule
carries a per-rule `regexes = [...]` placeholder allowlist that silences
documentation-shape connection strings regardless of path. The current
allowlist covers:

- Literal placeholder user-and-password shapes — `postgres://USER:PASSWORD@host`,
  `postgres://user:password@host`, `postgres://postgres:secret@host`.
- Angle-bracket placeholders — `postgres://<user>:<password>@host`.
- Asterisk-redacted password shapes — `postgres://user:***@host` (one or more
  literal asterisks) — added via
  [#3877](https://github.com/jikig-ai/soleur/issues/3877) to recognize the
  canonical Doppler/`psql`/pooler-output redaction convention.

**CLOSED — a real password containing `@` used to be silenced.**
[#6723](https://github.com/jikig-ai/soleur/issues/6723). The rule's password class
was `[^@/\s]+`, which stops at the FIRST `@`, while every real URL parser takes
userinfo to the LAST one. Because the allowlist entry was an unanchored *search*
against the rule's match, a credential like
`<scheme>://user:password@<realsecret>@<host>` contained the substring
`<scheme>://user:password@` and allowlisted itself.

Two changes were needed, and shipping either alone would have left the gate
broken:

1. **The password class spans to the last `@`** — `[^/\s]+`. `/` stays excluded
   so a realistic DSN still terminates at its `/dbname` path.
2. **The allowlist entry is fully anchored** — `^...$`. Allowlist `regexes` match
   the Secret, and with no `secretGroup` the Secret is the whole rule match, so
   an unanchored entry means "the match CONTAINS a placeholder" when the only
   safe reading is "the match IS a placeholder".

**The obvious fix would have made things worse.** #6723's body proposed keeping
an `<[^>]+>` bracket branch. Once the password class permits `@` and `:`, that
branch lets an entire real credential masquerade as a placeholder:
`<scheme>://user:<admin:R3alPassw0rd@prod.db.internal>@x.com`. Measured: three
such shapes are detected under the *old* config and would have been **silenced**
by the proposed one — the same defect class that got #6706's widening reverted,
re-entering through a different branch. The shipped form hardens both branches to
`<[^>@:]+>`, which keeps every legitimate placeholder quiet (`<user>:<pw>`,
`USER:PASSWORD`, `user:***`, `user:password`) while closing that door.

This is also why the placeholder alternation is **deliberately not widened** with
short tokens. #6706 proposed adding `pass`/`passwd`/`pw` and the change was
reverted on measurement: those prefixes are far likelier to head a real password.

If you need to document a DSN shape in a comment, use the angle-bracket form
`<scheme>://<user>:<pw>@host` — that is what `apps/web-platform/infra/vector.toml`
does. **Elide the scheme in prose examples.** The rule is keyword-gated on the
literal `postgres://`, so writing it out makes the comment itself a finding; that
is not hypothetical, it happened twice in this very PR, in the comments
explaining these examples, and only the working-tree diff caught it.

`plugins/soleur/test/gitleaks-rules.test.sh` T6–T10 pin this rule's behaviour:
T6 that documentation shapes stay quiet, T7 that real credentials still fire (one
varied dimension per row), T7b the multi-`@` bypass, T7c the bracket-userinfo
regression net that keeps the rejected candidate from re-entering, T8 that the
allowlist stays a single entry, T9 that both anchors survive and no bare
`<[^>]+>` branch returns, T10 that the `paths` list keeps its exact arity and the
review carve-out stays anchored. T7 is also T6's positive control: T6 alone passes
vacuously if the scanner is degraded. Extend them together if you touch the rule.

The placeholder regex covers ONLY the canonical shapes. Prose-style redactions
that extend beyond placeholder form (e.g., a Supabase pooler URL like
`postgres.<projectref>:***@`, where the user portion is dotted-with-projectref)
still rely on the path carve-out for the learnings tree.

### Rename-laundering — empirical behavior (gitleaks v8.24.2)

The CI smoke matrix's `rename-laundering` case proved **empirically** that
gitleaks v8.24.2 **allows** a rename from a non-allowlisted path into an
allowlisted path. The path-based allowlist is evaluated against the
**destination** path of the staged change; the diff content (which carries
the same secret) is not re-evaluated against the source path.

This means a `git mv apps/web-platform/server/with-secret.ts
apps/web-platform/test/__synthesized__/now-allowed.ts` followed by
`git add` slips a real secret past the gate.

Mitigations in place:

1. **`rename-guard` CI job** (added 2026-05-15, [#3160](https://github.com/jikig-ai/soleur/issues/3160))
   — fails the PR check on any `git mv` whose destination matches a regex
   in `.gitleaks.toml`'s allowlist surface. Override paths:
   - Apply the `secret-scan-allow-rename` label to the PR, OR
   - Include `Rename-Allowed-By: <name>` as a trailer on any commit in
     the PR (mirrors the `Co-Authored-By` convention; case-sensitive).

   Logic lives in `apps/web-platform/scripts/rename-guard.sh`; the smoke
   matrix exercises it via three cases (`rename-guard-fires`,
   `rename-guard-label-override`, `rename-guard-trailer-override`).
2. **GitHub push protection** independently scans every committed line for
   well-known token shapes (Doppler, AWS, Stripe, etc.) and blocks the push
   regardless of allowlist scope. We confirmed this empirically when
   GitHub blocked our own smoke-test fixture commit until we split the
   token into prefix + body composed at runtime.
3. **CODEOWNERS** requires 2nd-reviewer for any change touching
   `.gitleaks.toml`, the workflow, the linter, or `AGENTS.md` — humans
   review the diff before merge.
4. **Reviewer awareness** — `git mv` into `__goldens__/` / `__synthesized__/`
   warrants extra scrutiny even when the gate is overridden.

The smoke matrix `rename-laundering` case stays as a **canary** on gitleaks
bumps — if a green run flips to blocked on a future bump, the upstream
behavior shifted and our smoke expectations need updating in the same PR.

**Operator note on label-based override.** Applying the
`secret-scan-allow-rename` label triggers a fresh `labeled` workflow event
that re-runs the gate with the new label list. This is why the workflow's
`pull_request:` trigger lists `types: [opened, synchronize, reopened,
labeled, unlabeled]` — without that, manually applying the label after a
failing run would NOT re-fetch labels (workflow re-runs replay the original
event payload per actions/runner #3149).

### Allowlist-diff gate (#3323)

Any PR that modifies `paths = [...]` under `[allowlist]` or
`[[rules.allowlists]]` in `.gitleaks.toml` triggers the `allowlist-diff`
CI job. The job:

1. Extracts the path-regex set at PR base and head via
   `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` (regex-only
   walker — no `@iarna/toml` dep).
2. Computes added / removed paths via `comm -13` / `comm -23`.
3. Posts (or updates) a sticky PR comment listing both sets. The comment
   is keyed on a leading marker line (`<!-- allowlist-diff-comment -->`)
   so re-runs `PATCH` the existing comment instead of stacking.
4. Blocks merge for **additions** until the PR carries either:
   - The `secret-scan-allowlist-ack` label, OR
   - An `Allowlist-Widened-By: <name>` trailer on any commit in the PR.

**Removals are auto-allowed** — a net-tightening edit shouldn't require
ceremony. Only widening fires the gate.

Same operator note as rename-guard: applying the
`secret-scan-allowlist-ack` label after a failing run requires the
`labeled` event variant on the workflow trigger (already wired) so the
gate re-runs naturally. Manual workflow re-runs do NOT re-fetch labels.

Logic lives in `apps/web-platform/scripts/allowlist-diff.sh`; the smoke
matrix's `allowlist-diff-fires` case proves the script exits 1 on
un-acknowledged widening.

### `# gitleaks:allow` waivers

Both gitleaks and the companion `lint-fixture-content.mjs` linter honor
line-level waivers. The vocabulary is:

```
# gitleaks:allow # issue:#NNN <one-line reason>
// gitleaks:allow # issue:#NNN <one-line reason>
```

The `# issue:#NNN <reason>` trailer is **mandatory** — the linter rejects
waivers without it. The intent is forensic: every waiver in the codebase
points to a tracked decision, so a future reviewer can ask "why is this
allowed?" and get an answer in <30 seconds.

When opening a PR that adds a waiver, link the issue in the PR body. When
closing the issue, audit any waivers that reference it and remove them if
the underlying constraint is gone.

**Why the trailer is enforced in CI, not just by `lint-fixture-content`:**
Native gitleaks `# gitleaks:allow` is honored on **any line in any file**
with no trailer enforcement. `lint-fixture-content.mjs` is glob-scoped to
fixture/golden/snapshot directories AND, as of 2026-05-15
([#3322](https://github.com/jikig-ai/soleur/issues/3322)),
`knowledge-base/project/learnings/**/*.md` so future learning-file waivers
also carry the `issue:#NNN <reason>` trailer. A developer could still
waive a real `whsec_` or `sk-ant-` token in a server-path file with bare
`# gitleaks:allow` outside those globs and gitleaks would honor it — that
gap is what the `waiver-discipline` job closes.

The `waiver-discipline` CI job closes this gap: it greps every PR-added
line containing `gitleaks:allow` (across the whole tree) and rejects any
without an `issue:#[0-9]+\s+\S{3,}` trailer. Failure blocks merge;
CODEOWNERS guards the job definition itself so the gate cannot be removed
without a 2nd-reviewer.

## When an alert fires

```
                 secret-scan finding
                          │
                          ▼
              ┌───────────────────────┐
              │ Where did it appear?  │
              └───────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   pre-commit         PR diff           push:main /
   (local hook)       (CI gate)         weekly cron
        │                 │                 │
        ▼                 ▼                 ▼
   ┌─────────┐    ┌──────────────┐    ┌──────────────────┐
   │ Edit /  │    │ Push fix to  │    │ ROTATE NOW       │
   │ unstage │    │ same PR;     │    │ Do NOT rewrite   │
   │ before  │    │ never merge  │    │ history.         │
   │ commit. │    │ until green. │    │ Assume exfil.    │
   └─────────┘    └──────────────┘    └──────────────────┘
```

### Why "rotate, don't `filter-repo`" on `push:main`

Once `push:main` fires, the secret is on GitHub's CDN, replicated across
the issue/code search index, and potentially mirrored into every fork that
has fetched in the last few minutes. `git filter-repo` rewrites your local
copy and the canonical remote, but cannot scrub the CDN cache, the search
index, or any fork. Rotation is the only durable remediation.

History-rewrite is appropriate ONLY when:

1. The secret was committed in the **current PR** branch and has never been
   pushed to `main`. Push the rewritten branch (force-push to your own
   feature branch is fine) and proceed.
2. AND the secret was never visible in CI logs of a public-repo run (check
   the workflow logs even if the secret was redacted — `echo $TOKEN` in a
   `set -x` step bypasses redaction).

If both conditions hold, you may rewrite. Otherwise: rotate, document, move on.

## Per-token rotation playbook

Order: by blast radius — worst-case first.

### `BYOK_ENCRYPTION_KEY` — WORST CASE

The byok-encryption-key encrypts user-supplied provider keys at rest in
Supabase. Rotating it without re-encrypting stored ciphertexts will brick
every BYOK user's workspace.

1. Generate the new key. Do NOT swap immediately.
2. Stand up a dual-key migration: `BYOK_ENCRYPTION_KEY_NEXT` env var; the
   server-side decrypt path tries CURRENT, falls back to NEXT.
3. Run a backfill that re-encrypts every row under NEXT.
4. Promote NEXT → CURRENT; remove the fallback path.
5. Audit logs to confirm no further decrypt failures.

If the key was leaked publicly, also notify affected users (every BYOK
user is "affected" — assume their stored keys are compromised) and force
a re-enrollment on next login.

### `SUPABASE_SERVICE_ROLE_KEY`

1. Supabase dashboard → Project Settings → API → "Reset service_role key".
2. Update Doppler `prd` immediately: `doppler secrets set SUPABASE_SERVICE_ROLE_KEY="..." -p soleur -c prd`.
3. Coordinate with deploy: the running container holds the old key in env
   until the next restart. Either redeploy immediately or accept a window
   where server-side calls 401 until the next deploy.
4. Audit logs for unexpected requests in the gap.

### `SUPABASE_ACCESS_TOKEN` (CLI / `sbp_`)

1. https://supabase.com/dashboard/account/tokens → revoke compromised token.
2. Generate new token; update Doppler `prd_terraform` (used by Terraform
   provider) AND any local `~/.zshrc` exports.
3. Re-run any in-flight `terraform apply` that may have authenticated with
   the old token.

### `ANTHROPIC_API_KEY`

1. https://console.anthropic.com → API Keys → revoke + regenerate.
2. Update Doppler `prd` AND `dev` (separate keys per env if possible).
3. No re-deploy needed — server reads at request time.

### `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET`

1. Stripe dashboard → API keys → roll. (Restricted-key rotation is fine
   in flight; live secret-key rotation requires coordination.)
2. Webhook secret is a separate rotation: Developers → Webhooks → endpoint
   → "Roll secret". Update env var. The previous secret stays valid for
   24 hours by default — you have a window, use it.
3. Redeploy webhook handler to pick up new env var.

### `GITHUB_APP_PRIVATE_KEY`

1. https://github.com/settings/apps/<app> → Private keys → generate new.
2. Update Doppler `prd`.
3. **All installations re-authenticate.** The old private key is still
   accepted by GitHub for ~ 5 minutes; after that, every active
   installation token expires and must be re-minted with the new key.
4. Confirm the GitHub App callback service successfully mints a new
   installation token before declaring rotation complete.

### Other tokens (lower blast radius)

| Token | Where to rotate | Notes |
|---|---|---|
| `RESEND_API_KEY` | https://resend.com/api-keys | No re-deploy; reads at request time |
| `CF_API_TOKEN_PURGE` | https://dash.cloudflare.com/profile/api-tokens | Scoped to cache-purge; rotate + update Doppler |
| `SENTRY_*` (DSN, auth-token) | https://sentry.io → Settings → Auth Tokens / Project DSNs | DSN is public-by-design; auth-token rotation needs CI re-deploy |
| `GOOGLE_CLIENT_SECRET` | https://console.cloud.google.com → APIs & Services → Credentials | OAuth flow re-auth; no token invalidation |
| `GITHUB_CLIENT_SECRET` | https://github.com/settings/applications/<id> | Same as above |
| `BUTTONDOWN_API_KEY` | https://buttondown.email/settings/programming | Newsletter integration only |
| `VAPID_PRIVATE_KEY` | regenerate keypair, redeploy server, push subscriptions re-register | Web-push subscribers need to re-subscribe |
| `DISCORD_OPS_WEBHOOK_URL` | Discord channel → Edit Webhook → Regenerate URL | Internal-only |
| `DATABASE_URL` password | Supabase dashboard → Database → Connection pooler → reset password | Coordinate with deploy |

## Notification flow

When a secret is rotated due to a leak:

1. **Immediately** post to `#security-incidents` Discord via
   `DISCORD_OPS_WEBHOOK_URL`. Template:
   > Secret rotated: `<name>`. Source: <PR-link / commit-SHA / workflow-run>.
   > Blast radius: <one line>. Status: <rotated / re-deployed / monitoring>.
2. If the leaked secret could have allowed read access to **customer data**
   (Supabase service-role, BYOK encryption key, database URL with password):
   - Open a private incident in the security tracker.
   - Determine GDPR Article 33 obligation (notify supervisory authority
     within 72 hours if there is a "risk to the rights and freedoms of
     natural persons").
   - Determine GDPR Article 34 obligation (notify affected data subjects
     directly if "high risk").
   - Coordinate with CLO before any external statement.
3. Internal-only secrets (Discord webhook, Resend key for transactional
   email): Discord notification is sufficient; no external disclosure.

## Forensics workflow

The CI workflow does **NOT** upload `--report-path` JSON as an artifact.
Rationale: gitleaks v8.18+ redacts the `Secret` field in the JSON output,
but on a public repo the safer default is "logs only" — any future change
that disables `--redact` would leak via the artifact. The forensics path is:

1. Read the redacted finding from the workflow log: `<rule-id>` + `<file>:<line>`.
2. Locally re-run the scan against the offending commit:

   ```bash
   git fetch origin pull/<PR>/head:pr-<PR>
   git checkout pr-<PR>
   gitleaks git --redact=false --no-banner --log-opts="-1 <commit-SHA> --"
   ```

3. The local scan shows the unredacted secret. Do this in a private terminal
   on a trusted workstation; do NOT paste the unredacted secret anywhere.
4. Identify which `prd` token shape matched, then follow the rotation
   playbook above.
5. After rotation, re-run the workflow on the PR to confirm the finding
   does not re-fire (it should still fire — the secret is in git history;
   the point is to confirm the scan is detecting the same line).

## Author-Side Pitfalls

Pitfalls discovered while authoring the rule pack and CI workflow during
PR1 of #3121. Read before adding a new custom rule or smoke-test fixture.

### A line waiver cannot clear a history finding

`# gitleaks:allow` is evaluated against the blob being scanned. A range scan
reads the blob **as it was in the commit that introduced it**, and that blob does
not contain the waiver you just added. So for anything already committed — and
especially anything already on `main` — a line waiver is inert. The real options
are a path predicate in `.gitleaks.toml` (path matching is commit-independent), a
`.gitleaksignore` fingerprint, or a history rewrite. Fixing the file at the tip
clears only the `gitleaks dir` full-tree steps, never the range scans.

The corollary catches authors constantly: **fixing the file the red gate names
does not turn the gate green.** See "Ref scope per event" for why.

### `--cc` looks like `-m` and detects nothing

If you are tempted to "simplify" a `-m` walk to `--cc`, don't. `--cc` emits patch
bytes that visibly contain the secret and gitleaks detects **none** of it — its
diff parser does not consume combined-diff `@@@` format. It is a gate that cannot
fail, which is worse than no gate because it reads as coverage. Measured and
pinned in `plugins/soleur/test/gitleaks-merge-commit.test.sh` T2, which also
asserts that no step ships `--cc` as a `log-opts` value. The workflow itself
only documents the trap in a comment — the assertion lives in the test.

### The comment explaining a rule is itself scanned

Writing a credential-shaped example into a comment — in `.gitleaks.toml`, in a
test file, in a workflow — makes that comment a finding, because the scanner has
no notion of "this is documentation". Elide the part the rule is keyword-gated on
(`<scheme>://` rather than the literal `postgres://`), or assemble the example at
runtime the way the test suites do.

This is not a hypothetical: it happened twice while fixing #6723, in the very
comments that explained the bypass, and neither the 29/29 test suite nor review
caught it. Only a working-tree finding comparison did — baseline config vs
shipped config against the same tree. Run that comparison whenever you change a
rule:

```bash
git show origin/main:.gitleaks.toml > /tmp/baseline.toml
gitleaks dir . --config /tmp/baseline.toml --report-format json --report-path /tmp/base.json --exit-code 0
gitleaks dir . --config .gitleaks.toml   --report-format json --report-path /tmp/ship.json --exit-code 0
# anything only in ship.json is a finding YOUR change introduced
```

### Always use non-capturing groups in custom rule regexes

Gitleaks auto-picks the **first capturing group** as `secretGroup` when
the rule does not set `secretGroup` explicitly. A token-shape alternation
like `(pt|st|sa|ct)` becomes the secret body, and the rule extracts only
that fragment instead of the full token — detection silently degrades.

```
# Wrong — first group captured by gitleaks as secretGroup
regex = '''dp\.(pt|st|sa|ct)\.[A-Za-z0-9_\-]{40,}'''

# Right — non-capturing group; gitleaks captures the whole match
regex = '''dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_\-]{40,}'''
```

**Rule:** every custom regex in `.gitleaks.toml` must use `(?:...)` for
grouping unless an explicit `secretGroup = N` is set with intent. The
smoke-fixture for the rule should include the full token shape so that a
silent capture-group regression is caught at CI time, not in production.

### Doppler-shape literals in workflow files trip GitHub push protection

GitHub server-side push protection scans every committed line for the
contiguous Doppler shape (and Slack, Stripe, AWS PATs, GitHub PATs, etc.)
regardless of file path or surrounding context. A YAML env literal like:

```yaml
env:
  FAKE_DOPPLER: "dp.pt.SMOKETEST..."
```

is rejected at push time with `GH013: Push cannot contain secrets`, even
though the value is a fixture and the file is `.github/workflows/*.yml`.

**Workaround:** split the shape across two env vars and concatenate at
runtime in the step:

```yaml
env:
  FAKE_DOPPLER_PREFIX: "dp.pt."
  FAKE_DOPPLER_BODY: "SMOKETEST..."
run: |
  echo "${FAKE_DOPPLER_PREFIX}${FAKE_DOPPLER_BODY}" > /tmp/fixture
```

Same trick applies to any vendor whose token shape GitHub push-protection
recognizes when a fake fixture token is genuinely needed for a smoke test.
Generating the fixture from random bytes inside a `run:` step is also
acceptable; the split-env pattern is preferred when you need fixture
stability across runs.

### Override default-pack rules by id, don't add parallel rules

Per-rule allowlists do **not** apply across rules. A custom rule named
`doppler-api-token-custom` with a `paths` allowlist will not silence the
default pack's `doppler-api-token` rule on the same file. To extend the
default pack with allowlists, declare a custom rule with the **same id**
as the default-pack rule — gitleaks treats the local definition as an
override, not an addition.

### Smoke-test fakes should map to allowlistable rules

`jwt` (default rule, v8.24.2) cannot be allowlisted per-path. If a smoke
matrix needs a fake JWT-shaped fixture, either upgrade gitleaks to a
version that supports per-path allowlist for `jwt`, or pick a different
fake-token shape whose rule you can allowlist. We chose Doppler shapes
for the smoke matrix because our custom rules carry the path allowlist.

## Rule-pack maintenance

When a new token shape lands in Doppler that the current pack misses:

1. Open a PR adding a `[[rules]]` block to `.gitleaks.toml`. Include:
   - `id` — kebab-case, prefix with vendor (e.g., `vendor-product-key`).
   - `description` — one line.
   - `regex` — anchored on a fixed prefix (`whsec_`, `sk-ant-`, etc.) to
     reduce false positives. Use `entropy = 4.5` or higher when shape alone
     would over-match.
   - `keywords` — array of literal substrings; gitleaks pre-filters lines
     by these before running the regex (cheap perf optimization).
   - Per-rule `[[rules.allowlists]]` block with the standard four paths.
2. Add a smoke-test case to `secret-scan.yml` matrix: stage a synthetic
   token in `__goldens__/` (expect pass) and at a server path (expect fail).
3. The weekly cron will re-scan history on Monday with the new rule pack;
   any pre-existing leak surfaces there.
4. **When widening a rule's `paths` allowlist toward a path already
   covered by another rule's allowlist** (e.g., adding
   `knowledge-base/project/learnings/.*\.md$` to a second rule when
   `private-key` already carves it out), the `allowlist-diff` CI gate
   will NOT fire — the parser dedups paths across the union of all
   rules' allowlists. Add the `Allowlist-Widened-By: <name>` commit
   trailer manually as belt-and-suspenders. Diagnostic: run
   `gitleaks git --no-banner --exit-code 1 --redact -v` (with `-v`) to
   surface per-finding file/line/rule on stdout; `--redact` alone hides
   the metadata you need. See #3874 / #2026-05-16 learning.

## Upgrading gitleaks

`.gitleaks.toml` and `secret-scan.yml` are pinned to v8.24.2 with a
hardcoded SHA256.

To upgrade:

1. Read the gitleaks CHANGELOG between current and target. Pay special
   attention to schema changes — v8.25 introduced top-level `[[allowlists]]`
   with `targetRules = [...]`. Migrating to v8.25+ would let us collapse 13
   per-rule allowlist blocks into one. Worth doing on the next bump.
2. Fetch the new SHA256 from the release's `checksums.txt`:
   ```bash
   curl -sL https://github.com/gitleaks/gitleaks/releases/download/v<NEW>/gitleaks_<NEW>_checksums.txt \
     | grep linux_x64.tar.gz
   ```
3. Update `GITLEAKS_VERSION` and `GITLEAKS_SHA256` in `.github/workflows/secret-scan.yml`.
4. Verify the smoke-test matrix still passes on the bump PR.
5. Update the version pin reference in this runbook's frontmatter.

## See also

- [`golden-tests.md`](./golden-tests.md) — the partner runbook for the
  `__goldens__/` convention introduced in PR2 of #3121.
- [`AGENTS.md` rule `cq-test-fixtures-synthesized-only`](../../../AGENTS.md) —
  the workflow rule that documents the no-real-data invariant.

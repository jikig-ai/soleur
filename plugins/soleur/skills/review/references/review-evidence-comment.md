# Review-Evidence comment and the agent-review merge gate

Loaded by `soleur:review` step 3 (after `emit-review-trailer.sh` succeeds) and linked from the arm steps of
`soleur:ship`, `soleur:merge-pr`, `soleur:drain-prs`, `soleur:product-roadmap` and ship's
[merge-queue-dequeue.md](../../ship/references/merge-queue-dequeue.md) re-arm. This is the one copy of the gate text; the skills link here.

## The gate

Soleur's operators are non-technical and cannot review code, so the merge gate is **agent review plus green CI,
never a human approval** (CTO ruling 2026-10-22; `rf-never-skip-qa-review-before-merging` already defines
review-gated as "`soleur:review` ran and its findings are fixed"). This does not extend to production-mutating,
destructive or irreversible commands: those still need the explicit per-command go-ahead that
`hr-menu-option-ack-not-prod-write-auth` requires, whatever the review said.

Domain surfaces additionally need a binding ruling from the owning agent before the merge, obtained through the
ruling route in [technical-ruling-delegation.md](../../brainstorm-techniques/references/technical-ruling-delegation.md),
and recorded in the comment's `domain-ruling` field:

- legal text, the Art. 30 register, privacy, terms or DPA: `soleur:legal:clo`;
- `infra/`, terraform, migrations, production writes, destructive operations or `.github/workflows`:
  `soleur:engineering:cto`, plus the review panel's infra and data seats;
- auth, secrets and URL or input-validation code: `soleur:engineering:review:security-sentinel` is in the panel;
- the `single-user incident` and `aggregate pattern` tiers add `soleur:engineering:review:user-impact-reviewer`.

drain-prs' exempt arm reads the line below, its one copy of the domain-surface paths (CTO amendment A-amend,
2026-11-12): any changed path it matches takes the PR off the exempt arm. It adds manifests, lockfiles, build and
CI-execution surfaces and agent-instruction files to the list above. It is a floor, not the whole gate: code it
cannot name, such as an auth helper under another name, still routes to `soleur:review` on the agent's read, and
in doubt the checked arm wins. Whoever edits the surface list above updates this line in the same change, and
it stays at column 0, where drain-prs' `sed` and `arm-check-sites.test.sh` read it:

```text
DOMAIN_SURFACE_RE='(^|/)infra/|\.tf$|\.tfvars$|\.hcl$|(^|/)migrations/|\.sql$|^\.github/|(^|/)legal/|(^|/)o?auth[^/]*(/|\.)|(^|/)secrets?(/|\.|-)|doppler|(^|/)package(-lock)?\.json$|(^|/)bun\.lockb?$|\.lock$|(^|/)Dockerfile|(^|/)\.env|cloud-init|(^|/)middleware\.ts$|(^|/)\.claude/|(^|/)AGENTS[^/]*\.md$|(^|/)CLAUDE\.md$|^plugins/[^/]+/(hooks|agents|commands|scripts)/|^plugins/[^/]+/skills/.*\.(md|sh|m?js|ts|py|json)$|(^|/)\.claude-plugin/|^scripts/|(^|/)\.git(modules|attributes)$|(^|/)bunfig\.toml$|\.config\.[cm]?[jt]s$'
```

## The comment

A commit trailer is invisible to a reader of `gh pr merge`, so post one PR comment after the trailer. A comment is
not a push, so it is also safe on a PR already in the merge queue. State what actually ran, never more, and fill
every placeholder from the review you ran, deriving each value with a command in the same call that posts it (`git rev-parse --short HEAD` for the head; a sha typed from memory shipped wrong on #12307) (do not post the template as written):

```bash
gh pr comment <number> --body "Review-Evidence: head=<short sha reviewed>; soleur:review ran; coverage=<full|degraded|partial-by-ruling>; tier=<resolved tier>; seats=<agents that returned>; missing=<names or none>; domain-ruling=<none|CLO|CTO>; unresolved-P1-P2=<n>; merge gate = agent review + green CI; no human approval required for non-production-mutating changes"
```

This is a self-attestation by the reviewing agent, not tamper-proof: anyone with comment access can post the same
text and it survives later pushes. A `coverage` other than `full`, a nonzero `unresolved-P1-P2`, or a fix commit
after the head it names is not a pass; the arm check below enforces all three.

Under a merge queue, the head the comment covers must be the head that enters the queue: a fix commit pushed after
the comment and left unreviewed rides the queue, and this repo's queue builds one entry at a time
(`max_entries_to_build = 1`), so pulling the PR out and re-entering puts it at the back. Re-review the new commits
and post a fresh comment before arming or re-arming `gh pr merge --squash --auto`; when auto-merge is already armed,
run `gh pr merge <number> --disable-auto` before pushing a fix. **Why:** #12518 — four CI-guard fix commits entered
the queue past the evidence head, and their P3 findings had to be fixed forward in #12633.

## Arm check

Ship's arm and CI-fix re-arm, merge-pr's merge gate, drain-prs §4's checked arm, product-roadmap's locked arm,
merge-queue-dequeue.md's step 3 re-arm and sync-pr-behind.sh's dequeue message run this one check; it is the only
copy. drain-prs' exempt arm (first-party bot author, bot-written or clean-sync commits, no `DOMAIN_SURFACE_RE`
path) is the one recorded exemption; it pins the head its read call wrote (drain-prs §4). Never assign `H`, `EV`
or `EXEMPT_HEAD` by hand: only the statement, or the exempt read call, sets them. It takes the
latest `Review-Evidence:` comment, requires its first line to say `coverage=full` and `unresolved-P1-P2=0` (each
field exactly once), requires its `head=` to be an ancestor of the PR head, and requires that no non-merge commit
sits on the branch's first-parent line between the two. The first statement is the check and exits 1 on refusal;
the second is the arm:

```bash
EV=$(gh pr view PR_NUMBER --json comments --jq '[.comments[].body|select(test("^\\s*review-evidence:";"i"))]|last // ""|split("\n")[0]|select(test("; coverage=full[; ]") and test("; unresolved-P1-P2=0([; ]|$)") and ([scan("coverage=")]|length==1) and ([scan("unresolved-P1-P2=")]|length==1))|capture("^Review-Evidence: head=(?<h>[0-9a-f]{7,40})[; ]").h') \
  && H=$(gh pr view PR_NUMBER --json headRefOid --jq .headRefOid) \
  && git merge-base --is-ancestor "$EV" "$H" \
  && R=$(git rev-list --first-parent --no-merges "$EV..$H") && [ -z "$R" ] \
  || { echo "ARM_CHECK refused: no passing evidence covers the PR head"; exit 1; }
gh pr merge PR_NUMBER --squash --auto --match-head-commit "${H:?run the arm check in this call}"
```

Where a skill wraps the merge in the merge-main lock, run the first statement and then the lock block in place of
the second, all in one Bash call: the `exit 1` stops the call before the lock block, and the lock block's
`${H:?…}` aborts if it runs without the check. On refusal, run `soleur:review`, which posts fresh evidence, then
run the check again; never arm around it.
`git rev-list --first-parent --no-merges "$EV..$H"` names the unreviewed commits.

- A main-sync merge (`git merge origin/main`, or GitHub's update-branch) passes: `--first-parent` keeps main's
  commits, which arrive through the merge's second parent, out of the range. Without it every synced PR refuses.
- No qualifying comment leaves `EV` empty and `merge-base` errors, so the check fails closed. So do a rebase or
  force-push that drops the reviewed commit and a PR head missing from the local object store (`git fetch` first).
- Only the latest comment counts: a re-review that finds P1s, or one that ran degraded, refuses until a later
  `coverage=full` comment with `unresolved-P1-P2=0` replaces it. An older passing comment never re-qualifies.
- `--match-head-commit "$H"` (gh: "Commit SHA that the pull request head must match to allow merge") ties the arm
  to the head the check read. It is not a substitute for `--disable-auto` before a later push (merge-queue
  paragraph above).
- Not covered: a merge of any branch, not only main, passes, because `--no-merges` drops the merge commit and
  `--first-parent` drops what its second parent brought; so does code changed while resolving a conflict inside a
  merge commit. Review both before arming.
- The check proves which commits the evidence covers, not who wrote it (see the self-attestation note above).
- It depends on the comment's wording: `head=` first, then `; coverage=full` and `; unresolved-P1-P2=0`. Whoever
  edits the template above updates this check in the same change, or every arm refuses.

**Why:** #12619 merged at 7d20e7c1a6, a P1 review-fix commit pushed after its only evidence comment
(`head=0127b5dc45`); the old check only counted `Review-Evidence:` comments. Dry run of this check (without the
merge): #12619 refuses naming 7d20e7c1a6, and #12518 arms (evidence 1af1ec063d is its head). On #12518's
main-sync merge 829f5c6777, `4778bd5058..829f5c6777` lists one main commit without `--first-parent` and none with
it. CTO ruling, 2026-11-11.

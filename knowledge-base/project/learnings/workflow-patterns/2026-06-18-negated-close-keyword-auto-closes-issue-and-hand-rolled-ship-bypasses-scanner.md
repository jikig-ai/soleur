# "does NOT close #N" auto-closes the issue — GitHub's parser is negation-blind, and it reads the COMMIT MESSAGE (not just the PR body), so the title/body-only scanner misses it

## Problem

The SAME issue (#5463, the report-only→blocking flip tracker, which must stay open until
the flip ships) was prematurely auto-closed **twice in one day** by a negated close-keyword:

1. **PR #5519** carried a PR **body** line intended to PREVENT a closure — *"this PR does
   NOT close #5463"* — and GitHub auto-closed #5463 on merge anyway.
2. **PR #5564** (a no-op live-verify trigger) then did it AGAIN — this time the keyword was
   in the **commit message** (*"Does not close #5463 (flip-to-blocking stays tracked
   separately)"*), not the PR body. The PR body was clean and the `/ship` Auto-Close
   Pre-Creation Scan returned **no matches** — yet on squash-merge GitHub still closed #5463,
   because the squash commit is built from the **branch commit messages**, which the parser
   reads on merge to main.

## Root cause

GitHub's issue-auto-close parser is **markdown-blind AND negation-blind**: it matches
`close[sd]?|fix(e[sd])?|resolve[sd]? #N` anywhere it scans, including inside the phrase
"does NOT close #5463". It does not understand "not", checkboxes, code fences, or
blockquotes. The literal substring `close #5463` was enough.

Two distinct surfaces feed the parser, and the second was the blind spot:
- **PR body** (the #5519 path) — covered by the scanner.
- **Commit messages** (the #5564 path) — on a **squash merge** (this repo's default), the
  squash commit message is assembled from the branch commit messages, and GitHub runs the
  auto-close parser over that commit on push to main. So a keyword in a commit body fires
  even when the PR body is spotless.

This is the same class as the `#3407` trap (PR #3185 closed twice — title `(Closes #N after
fire)`, then body checkbox `- [ ] Post-merge: close #N`). Counting #5519 and #5564, #5463
makes the **fourth and fifth** firings of this class.

The compounding failure was a **scanner blind spot**: the `/ship` Auto-Close Keyword
Pre-Creation Scan and the CI `pr-auto-close-scanner.yml` both scanned only **title + body**,
never the commit messages. In #5564 the scan ran and returned clean (the body was clean),
giving false confidence while the trap sat in the commit message. (In #5519 the additional
failure was hand-rolling `/ship` Phase 6 so the scan never ran at all — still true, but even
running it would not have caught a commit-message trap until this fix.)

## Solution

1. **Recover:** `gh issue reopen 5463` with a comment. (In #5564 the premature close was
   moot in hindsight — the genuine flip #5576 landed hours later and legitimately closed
   #5463 — but for the ~3h window #5463 was CLOSED while the flip was undone.)
2. **Prevent (authoring):** never put a close-keyword + `#N` in a PR body **OR a commit
   message** unless you intend to auto-close N — even negated. To DISCLAIM a closure, drop
   the keyword entirely: "this PR is a **prerequisite for** #5463 (it does not resolve it)"
   or "tracked separately in #5463". Reserve `Closes #N` for genuine work targets.
3. **Prevent (mechanical) — landed in this PR:** the scanner now also scans commit
   messages. `/ship` Phase 6 writes `git log origin/main..HEAD --format=%B` to a temp file
   and scans it alongside title+body; the CI `pr-auto-close-scanner.yml` fetches the PR's
   commit messages (`gh api .../pulls/N/commits`) and scans them too. Test `TS9` in
   `auto-close-scanner.test.sh` pins the negated-form catch. This closes the blind spot
   that let #5564 through a clean body scan.
4. **Prevent (process):** still do NOT hand-roll `/ship` Phase 6 — run `soleur:ship` so the
   (now commit-aware) scan + the Phase 6.4 unpushed-commits gate + title guard all run.

## Key insight

A close-keyword next to `#N` is a loaded gun regardless of surrounding prose **or which
text you put it in** — GitHub fires on the substring, not the sentence, and it reads the
**commit message** the squash merge produces, not only the PR body. A scanner that checks
only the body gives false confidence: the body can be spotless while the commit body holds
the trap. Scan every surface that reaches the merge commit, and write the disclaimer
without the keyword.

## Session Errors

- **PR #5519 auto-closed #5463 via the negated PR-body prose "does NOT close #5463".** —
  Recovery: `gh issue reopen 5463`. — Prevention: keyword-free disclaimers + run `soleur:ship`.
- **PR #5564 auto-closed #5463 AGAIN via a negated COMMIT MESSAGE "Does not close #5463",
  while the body scan returned clean.** — Recovery: the real flip #5576 later closed #5463
  legitimately. — Prevention: the scanner now scans commit messages (this PR); never write a
  close-keyword in a commit body even negated.

## Tags
category: workflow-patterns
module: ship

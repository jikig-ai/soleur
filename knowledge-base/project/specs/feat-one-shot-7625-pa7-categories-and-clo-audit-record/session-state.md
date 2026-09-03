# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-03-legal-pa7-c-categories-and-clo-audit-record-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Closes: 7625

### Errors
- Planning subagent issued a premature Session Summary while a background sweep was still
  running; that sweep returned six stale cross-references, all fixed in 5fe43616c. The final
  summary supersedes the premature one.
- A duplicate orphaned `### AC pre-flight` section carrying pre-revision numbers was listed in
  a mid-session inventory and not acted on until the sweep caught it.
- Nine factual errors in the planner's own research, all caught by review and corrected in
  place: `SignerRow` misused for the record shape (it omits `repoId`); the receipt comment
  named as the notice mechanism (the real one is the pre-signature
  `custom-notsigned-prcomment`); `:242` cited as a PA-7 block (it is PA-12); `:658` cited as
  PA-35 (it is PA-33, and that had propagated into two CLO rulings); a frontmatter contract
  attributed to `2026-08-counsel-review-7440.md` that it does not carry; a fabricated `--help`
  flag and listing verb; nine amendment labels where there are ten; a grep count described
  from a filtered view.
- The CLO advisory's Ruling 3 asserted CLA §0 cross-references the DPD. It does not. Caught by
  two reviewers, corrected by the CLO in addendum A1 — it was landing in the one cell whose
  original defect was naming no mechanism.
- A Bash hook blocked a heredoc containing a literal credential-set command in prose; reworded.
- MCP servers `playwright` and `plugin:github:github` failed to connect. Neither was needed.

### Decisions
- CLO advisory obtained at plan time and made binding, then re-consulted after review, so
  `/work` implements a decided Art. 9 question rather than making a subjective legal
  determination mid-implementation. The artefact `/ship` Phase 5.5 requires already exists.
- The PR is split. The transparency consequence of the capture predicate needs a
  `docs/legal/**` edit — five legal gates plus a mirror/SHA re-pin — so it became PR B with
  its own issue, to be minted in Phase 2. PR B's scope grew twice at review:
  `privacy-policy.md` §5.11 (a bot-only enumeration that is false, since `deruelle` is a
  natural person) and §8.1 (the section conferring a rights route, carved out for three other
  accountless populations and not this one).
- Scope grew where evidence demanded and shrank where it did not. Grew: four record shapes, a
  wider data-subject population, a new `(h) DSAR` cell, a CORPUS DIVERGENCE block, four Active
  Items rows instead of one. Shrank: the archive measurement left this PR entirely (bought no
  property, and put a live production-credential read inside a docs-only PR), ACs went 30 -> 19,
  and the drift sentinel was left to the issue that already owns it.
- Two blockers caught that would have stopped `/work` cold: the register carries ten
  pre-existing markdownlint errors and lefthook lints staged Markdown, so staging it blocks the
  commit; and `MD056` is disabled repo-wide, making the plan's own 2-column assertion the only
  table guard for this file.
- `AC17` was kept over two reviewers' objections. Both called the `vector.toml` assertion an
  invented risk; it encodes a constraint the work was handed, and dropping requested scope is
  not a simplification a reviewer is authorised to make.

### Components Invoked
`soleur:plan` - `soleur:plan-review` - `soleur:deepen-plan` - `soleur:legal:clo` (x2: advisory,
then addendum on four review-found gaps) - `Explore` -
`soleur:engineering:research:learnings-researcher` -
`soleur:engineering:review:code-simplicity-reviewer` -
`soleur:engineering:review:architecture-strategist` -
`soleur:engineering:review:kieran-rails-reviewer` -
`soleur:engineering:review:dhh-rails-reviewer` - `soleur:product:spec-flow-analyzer` -
`soleur:product:cpo` - `soleur:engineering:cto` - `general-purpose` x2 (verify-the-negative
sweep: 27 confirmed / 1 contradicted; post-edit self-audit sweep: 6 drifts)

### Gate re-probe (one-shot Step 0a.5, post-plan)
- Plan frontmatter `closes: 7625` — same ref cleared pre-worktree; no new work target introduced.
- Collision candidates #7622 / #7664 dismissed on evidence: `comment_body` absent from the
  register, and PA-7 §(e) records "§(c) field omissions remain tracked at #7625 and are
  untouched by this correction." #4718 had zero path intersection.

## Work Phase (2026-09-03)

- Status: complete. Five phases executed in dependency order (0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 6).
- Closes: 7625. Filed: 7812, 7813, 7814, 7815, 7816, 7817, 7818. Net issue flow +6 (planned +9).

### Deliverables
- `knowledge-base/legal/audits/2026-09-counsel-review-7625.md` — the binding advisory,
  spliced mechanically and proven byte-identical, plus the A7-A11 second addendum.
- `knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md` — the
  missing retrospective record; all nine findings, all ten AC anchors.
- `knowledge-base/legal/article-30-register.md` — PA-7: four cells amended, `(h)` added.
- `knowledge-base/legal/compliance-posture.md` — four Active Items rows on three numbers.

### Decisions taken during work (each departs from the plan as written)
1. **CONCUR gate run as admission control before filing, not after.** Net was +9 for one
   closed issue. The gate found the plan's stated blocker for inlining seven filings was
   false, that the plan undercounted the AUP 4.7 sites (four, not two), and that the PA-32
   precedent it cited splits on obligation rather than remediation.
2. **Legal scope routed to the CLO, not settled by the reviewer.** It ruled FILE anyway on a
   ground neither party had: the 4.7 clause at PA-17 implements a prior counsel recommendation
   (2026-05 review, finding B2), so striking it reverses that recommendation and leaves
   "None by design." unsupported — a fresh Art. 9 determination, not a sentence edit.
3. **Four posture rows, three issue numbers** (Rows 2 and 4 share #7814); **Row 3 IS the PR B
   issue** (#7812), one number serving three referents.
4. **AC5 amended, not satisfied.** It was unsatisfiable by a correct implementation: it forbade
   the old limb-(iii) string anywhere in PA-7, while this register's amendment convention
   REQUIRES the block to quote the text it supersedes. Rescoped to live cell text; reads 0 on
   HEAD and 1 on main, so it is non-vacuous.
5. **AC9 strengthened and mutation-proven.** The original was label-scoped, not PA-scoped: it
   would pass a full semantic rewrite of PA-31's cell. A mutated PA-31 row PASSES the old form
   and FAILS the replacement. AC9-STRONG asserts whole-register changed lines == PA-7 changed
   lines: 9 and 9.

### Errors made and corrected in-session
- A mutation test reported PASS/PASS because `git diff main...HEAD` reads the COMMITTED tree
  and the mutation was in the working tree — the mutation never landed, so both arms measured
  the baseline. Redone with a diff that sees the change; the two-number comparison is what
  surfaced it.
- `git diff main` was measured against a STALE local `main` ref (2 behind origin/main), listing
  six files from sibling branches as mine. Re-based on `origin/main` and rebased the branch.
- Two self-introduced bare-address lint errors in the new cells; fixed, so both files measure
  lint-neutral against base (register 10=10, posture 5=5).
- A literal shell pipe inside a posture row's Notes made it an eight-field row that GFM would
  have rendered with a dropped cell. Caught by AC19's field-count check; escaped.

### Verification
Targeted suites, because the `scripts` shard exited **rc=4 = REFUSED** (a sibling full-gate run
in another worktree, #7553) — nothing ran; that is neither a pass nor a failure of this diff.
`legal-doc-consistency` 35 passed · `lint-credential-path-literals` exit 0 ·
`lint-infra-no-human-steps --changed` exit 0 · `check-pa-22.sh` exit 0 · `gdpr-gate` +
`gdpr-gate-repo-scan` 54 pass / 0 fail · legal cross-document gate short-circuits
(`surface_hit=false`; my diff touches no DSAR source surface) · markdownlint clean on both new
audit files and the plan · KB index regenerated and idempotent.

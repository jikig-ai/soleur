# Decision challenges — plan-review (headless; surfaced, not auto-applied)

Plan: `knowledge-base/project/plans/archive/20261002-082739-2026-10-02-fix-drift-autoclose-skip-hcloud-server-replacement-plan.md`.
The plan follows the operator's stated direction in each case below; the reviewer view is recorded for `ship` to render.

## 1. Cut entity normalization, R2 and the truncation-title check (User-Challenge)

- Operator direction: match the HTML-escaped form, match `-/+ resource "hcloud_server"`, treat the `Plan output (truncated)` title as truncation, with fixtures for "replacement only in escaped form" and "truncated body".
- Reviewers (simplicity, DHH): the issue-body producer is raw today (verified), R2 is redundant with the R1 header, the title exists only in the email path, and the terminator check already fails closed on any escaped/truncated body. Cutting removes about a third of the planned surface.
- Plan response: kept (operator-requested scope; never silently dropped). If the operator agrees, deletion is mechanical: remove `normalize`, R2, `has_truncation_marker`, their fixtures and mutation rows 2 and 4.

## 2. Judge the newest plan-bearing artifact instead of the union of body and all comments (Taste)

- Operator direction: skip any issue whose body shows a replacement; close only when readable and clean.
- Reviewers (DHH, CTO): union semantics strand an issue forever once any scan showed a server replacement, even after the host was replaced; "latest plan-bearing artifact" is the current observation and is the same code size.
- Plan response: union kept (literal brief, fail-closed). The cost is a stale-open issue that the operator closes by hand. Alternative to adopt later: classify only the last comment containing `<summary>Plan output`, else the body.

## 3. Producer-side label instead of consumer-side parsing (Taste, deferred direction)

- CTO: have `scheduled-terraform-drift.yml` label an issue `drift-host-replacement` when its raw plan shows an `hcloud_server` action; the closer then skips labelled issues and needs no parsing, truncation or escape logic.
- Plan response: not adopted — the brief scopes the fix to the closer and says the filer is not the target; recorded as the cheaper long-term form (the filer holds the raw pre-redaction plan).

## Rulings (lead, 2026-10-02; no operator question asked)

1. Kept: entity normalization, R2 and the truncation-title check stay, as the operator specified. Mutation rows 2 and 4 stay.
2. **Adopted: judge the newest plan-bearing artifact, not the union.** The union strands an issue open forever once any scan showed a server replacement, even after the host was replaced, which defeats closing. Classify the last artifact (comment, else body) containing `<summary>Plan output`; if that artifact is incomplete or shows a replacement, skip. This SUPERSEDES the plan's union wording wherever the plan says "union" or "any plan-bearing artifact"; the work phase implements the newest-artifact rule and updates the plan text to match.
3. Not adopted: producer-side label stays a recorded long-term alternative; no issue filed (net-issue-flow).

## Review dispositions (9-seat panel on 390a7df88b; fixed inline in the review commit)

Structural cause: the classifier trusted and parsed text it could not validate (author, grammar, size).
- Fixed: comment/body AUTHOR is now checked (only github-actions / app/github-actions / github-actions[bot]; loop mode blanks other authors' text), with a stub-gh scenario and a mutant (m14).
- Fixed: R1 now covers module prefixes, keys holding `/` or spaces, `(deposed object ...)`; R2 covers `-`, `+`, `-/+`, `+/-` markers (`~` in-place still closes); locale pinned to C; grep errors fail closed.
- Fixed: quadratic runtime (whitespace tests via regex, one jq call, newest-first scan, normalize only when `&` present); a 60 x 50 KB scale case with a 30 s bound.
- Fixed (suite): battery rows 3/4 were vacuous (one-line functions swallowed `classify`); rows now use markers and reject non-verdict output. The `gh issue list` query is asserted exactly; comment order, forged-author, strict close-failure, `Plan:`-only, escaped `Note:`-only, human-mentions-plan cases added; the table comparison is self-tested and mutated (H5).
- Documented: slug vocabulary and operator action in the script header; failed close/view is a warning with rc 0 (deliberately softer than the old `set -e` step).
- Not changed (recorded): (a) other closers of infra-drift issues outside this step (follow-through sweeper, other workflows) are out of scope; the wiring sentinel only covers this workflow. (b) A clean scan after a real host replace writes no new artifact, so the stale replacement plan stays newest and the issue is closed by hand; closing on a clean scan is a producer-side change (the architecture seat's marker proposal) and is the better long-term form. (c) Two plan blocks in one artifact are not modelled (the filer writes one per artifact). (d) `-L 200` truncation now warns.

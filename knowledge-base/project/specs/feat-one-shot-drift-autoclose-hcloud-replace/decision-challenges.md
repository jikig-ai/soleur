# Decision challenges — plan-review (headless; surfaced, not auto-applied)

Plan: `knowledge-base/project/plans/2026-10-02-fix-drift-autoclose-skip-hcloud-server-replacement-plan.md`.
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

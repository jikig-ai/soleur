# Upstream defect evidence — `anthropics/claude-code` (residual after 76882 closed)

Tracker: #7490 part 3, residual. The two postings recorded in the archived record
(`knowledge-base/project/specs/archive/20260813-114111-feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md`)
both landed on 2026-08-13. Upstream then closed **76882** on 2026-08-17 as `documentation` — the
collaborator's reply addressed the `marketplace update` vs `plugin update` confusion and the bare-name
failure, and did not address the version-comparator no-op that §1 of that record carried. So the
comparator residual had no open upstream home until it was searched for again on 2026-09-18.

**Search before drafting (2026-09-18).** `gh api search/issues` on `repo:anthropics/claude-code is:issue`
with the phrasings `plugin version compare`, `plugin update commit sha`, `plugin update does not update`.
Result: **93108** (OPEN, `bug` + `has repro`, filed 2026-09-09) is the version-comparator no-op, stated
from an independent reproduction (`langsmith-skills`, `version` constant since 2026-03-10, four months
stale while `autoUpdate: true`). Two further commenters have added instances (`cloudflare@cloudflare`
on 2026-09-10; a Windows local-marketplace matrix on 2026-09-14). **Decision: no new issue.** A fourth
issue on the same comparator would be a duplicate; the correct move is one comment on 93108 carrying
what the existing thread does not yet have.

Two adjacent issues were read and are NOT the destination: **83947** (bare `plugin update <name>`
fails unless fully qualified — the docs-side finding this repo's part (a) acts on; nothing to add) and
**86700** (`plugin install` on an already-installed plugin does not upgrade — a different verb).

**Scrub.** This body is posted to a third party's PUBLIC repository. It is scrubbed with
`scripts/upstream-report-scrub.sh` against this file before posting, and re-scrubbed against the body
**as posted** (`gh api <comment-url> --jq .body | bash scripts/upstream-report-scrub.sh -`), because the
posted body is the artefact that leaks and the local copy is not proof about it. A clean exit covers the
enumerated shapes only; the body also had a human read for a hostname or username in a novel position.

---

## Section-to-posting mapping

| # | Section | Destination | Status |
|---|---|---|---|
| 1 | What the thread lacks: the two identity fields side by side, the controlled two-arm reading, and the projection property of `plugin list --json` | comment on **93108** | _pending_ — operator-gated |

---

## §1 — the comment for 93108

**The postable bytes live in their own file:** `upstream-reports/93108-comment.md`, de-quoted and
containing nothing but the comment. This file is the RECORD and is not postable — its header carries
the tracker number, the branch-naming and spec-archive conventions, the scrub tooling and this
posting log, none of which matches an enumerated scrub shape and all of which would ship if the send
used this file. The send is therefore `--body-file upstream-reports/93108-comment.md`, with no
slice-selection step left to a human, and the scrub runs against that file (AC18).

Three things were removed from the draft after a human read that the regex scrub cannot perform:
a 12-character commit string that resolves in no public repository (replaced with a description of
its shape); a skills-count comparison that is a product-quality statement about this operator's own
delivery and adds nothing to the comparator argument; and the plugin's own name in the quoted CLI
output, since the prior comment in the same evidence chain deliberately described the repo generically.
The mechanism claim about the two third-party plugins named in the upstream thread is attributed to
those reports rather than asserted as this session's own reading.

## Posting log

| Section | Destination | URL | Scrub re-check |
|---|---|---|---|
| §1 (`upstream-reports/93108-comment.md`) | 93108 | _pending_ | _pending_ |

The posting is operator-gated: composing the body is in scope for this change; sending it to a third
party's public repository is not, until the operator has read the body above and said so. When it is
sent, replace both `_pending_` cells (URL, then `PASS — 0 exposures, <N> bytes as stored` from the
re-scrub) in the same edit.

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

## §1 — Comment for 93108 (composed body)

> One reading that may sharpen the mechanism section of this report: the stale install is
> **detectable from the CLI's own record**, and the CLI does not look at the field that would detect it.
>
> **Two identity fields, one comparator.** On 2.1.228, an `installed_plugins.json` entry carried
> `version: 0.0.0-dev` (the manifest's constant) **and** a valid 40-character `gitCommitSha`
> simultaneously. `plugin update` compared `version` only — `✔ soleur is already at the latest version
> (0.0.0-dev)`, exit 0, nothing delivered — while the installed content was three months behind the
> marketplace clone on the same disk (64 skills against 96 at source) and the `gitCommitSha` beside the
> constant named the commit the install had actually come from. The datum that would prove the install
> stale is already in the record; it is just not the one the comparator reads.
>
> **Controlled reading of what the `version` key changes.** Two arms, identical except for the plugin
> manifest's `version` key; marketplace entry keyless in both; clean `HOME` per arm; same CLI.
>
> | Arm | `plugin.json` `version` | `gitCommitSha` recorded | `version` recorded |
> |---|---|---|---|
> | with-version | `"0.0.0-dev"` | yes | `0.0.0-dev` |
> | keyless | absent | yes | `bfc681c7d8c7` (a commit string) |
>
> So the key does not suppress `gitCommitSha`; it decides what lands in `version`. Keyless manifests
> get a commit-derived string there, which is why they update, and versioned manifests get a constant,
> which is why they do not. That agrees with the langsmith-skills and cloudflare cases above: both have
> a constant `version`, both have current commits in the clone, neither refreshes.
>
> **`plugin list --json` cannot detect it either.** Its output is a projection of
> `installed_plugins.json`: editing that file's `version` and `installPath` to sentinels changed the
> `plugin list --json` output verbatim, and restoring the file reverted it. There is no independent read
> of installed content to compare against, so a consumer cannot script around the comparator from the
> CLI surface.
>
> **Smallest fix consistent with the record:** when a `gitCommitSha` is present for a `github`/`git`
> source, compare it against the resolved source commit and update on difference regardless of
> `version`. That uses a field the CLI already writes, and it makes `autoUpdate: true` mean what it says
> for unversioned plugins. The `--force` fallback proposed above would also close the workaround gap.
>
> Earlier evidence from the same measurements, posted before 76882 closed:
> https://github.com/anthropics/claude-code/issues/76882#issuecomment-5273479508

---

## Posting log

| Section | Destination | URL | Scrub re-check |
|---|---|---|---|
| §1 | 93108 | _pending_ | _pending_ |

The posting is operator-gated: composing the body is in scope for this change; sending it to a third
party's public repository is not, until the operator has read the body above and said so. When it is
sent, replace both `_pending_` cells (URL, then `PASS — 0 exposures, <N> bytes as stored` from the
re-scrub) in the same edit.

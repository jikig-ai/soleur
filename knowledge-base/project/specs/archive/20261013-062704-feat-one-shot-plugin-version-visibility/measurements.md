# Phase 0 measurements — plugin version visibility

Run 2026-10-11, Claude Code 2.1.296, Linux. Harness style follows
`feat-one-shot-7471-plugin-delivery-path/measurements.md` §1.9: clean `HOME` per run, local
git marketplace, fixture plugin `fixp` (script kept outside the repo; reproducible from the table).

## M1 — does `claude plugin update` compare version strings (both source shapes)?

Fixture: two commits of a plugin; commit 2 changes `content.md`. Arm A keeps `plugin.json`
`version` constant (`1.0.0`); arm B bumps it to `1.0.1`. Marketplace entry is keyless in every run.

| Arm | Source shape | `plugin update` result | Cached content after update |
|---|---|---|---|
| A (constant version) | relative path | "already at the latest version (1.0.0)" | content-one (stale) |
| A (constant version) | `git-subdir` (`file://` url) | "already at the latest version (1.0.0)" | content-one (stale) |
| B (bumped version) | relative path | "updated from 1.0.0 to 1.0.1" | content-two |
| B (bumped version) | `git-subdir` | "updated from 1.0.0 to 1.0.1" | content-two |

Reading: re-confirms #7471 (a constant version no-ops while reporting success) and shows a
changed version string is what makes the update apply, on both source shapes. **M1 passes.**

## M2 — recorded version and cache dir shape

Real install on this machine (`~/.claude/plugins/installed_plugins.json`): `soleur@soleur`,
`version: "b78d30e919ff"`, `installPath` ends in `.../soleur/soleur/b78d30e919ff`, `gitCommitSha`
is the full 40-char sha whose first 12 characters equal the directory name. So for a keyless
`git-subdir` install the cache dir basename is the 12-hex commit prefix (D2 regex
`^[0-9a-f]{12}(-[0-9a-f]{8})?$` accepts it; the optional suffix is not observed here and is only
tolerated). For a versioned install (fixture, arm B) the dir is the version (`1.0.1`).

## M3 — keyless marketplace entry + versioned plugin.json

The arm B runs above are exactly this shape (entry keyless, manifest versioned) and record the
manifest version (`1.0.1`) as the install version on both source shapes. `claude plugin validate`
was not run. **M3 passes for resolution; validation unmeasured.**

## M4 — hook `systemMessage` rendering

Not measured here: running a nested interactive Claude session from this pipeline is not
reproducible headlessly. Fallback built into D4: the hook emits a top-level `systemMessage`;
if a future check shows it is not rendered, switch to a one-line `additionalContext`.
Follow-up to verify by hand: start a session with the plugin and check the banner line appears.

## M5 — network cost

- `git ls-remote --tags https://github.com/jikig-ai/soleur.git 'refs/tags/v*'`: 0.6 s, ~118 KB,
  2005 lines (all tag families), highest strict `vX.Y.Z` tag at measurement time `v3.335.9`.
- GitHub compare API: HTTP 200 with a **617 KB** body without `per_page`; the resolver sends
  `?per_page=1`. The first `"status"` in the body is the top-level one (per-file entries carry
  their own later), so it is parsed first-match-only.
- A 12-char SHA is accepted as the base ref. This machine's own install
  (`b78d30e919ff`, a docs-branch commit) compares `diverged` against `v3.335.9`, which the
  resolver reports as `relation=unknown`, never "up to date".

## M6 — stale-window baseline (Slice B)

`gh pr list --state merged --author app/soleur-infra`, created to merged, minutes:
n=6 (all inngest-bootstrap pin bumps, the only bot-PR population that exists today):
41, 43, 77, 80, 88, 112 → p50 77, p90/p95/max 112. The plan asks for the last 30; only 6 exist,
so the p95 is a max over a small sample, not a distribution. It meets the <= 120 min ceiling.

## Go / no-go for Slice B

M1 pass, M3 pass (resolution), M6 p95 112 <= 120 (n=6), operator confirmed DC-1
("Slice A + gated stamp"). **Go, as a dark-launched follow-up PR** — governance reversals
(ADR amendments, rule-body edit with its hash-bound ack, removal of key-absent tests) belong in
the same change as the stamp (plan Slice B condition 7), so Slice B is not mixed into the
Slice A PR. Condition 3 (staged live stamp) and 4 (>= 7 days and >= 3 releases soak) are
post-merge and keep the flag off until met.

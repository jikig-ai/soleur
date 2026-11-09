# Receipts — S4 go/no-go evidence re-run (4th), window pinned 2026-11-09

Window: last 300 first-parent commits of `origin/main` at BASE `af764001eebe535b44af468c9f3904f2809f8220` (window pinned by BASE SHA at 10:32:53Z; see provenance note below).
Out dir: `/var/tmp/s4-rerun-9729-r4` (not committed; JSONL manifests are the resumability signal).
This run exercises the ejections corroboration + classifier-coverage changes merged earlier today (2026-11-09).

Files: commands.txt, go-no-go.md (verdict receipt), replay-summary.txt, replay-commits.tsv,
histograms.txt, ejections-window.json, index-audit.out / index-audit-bare-noaccept.out / index-audit.err,
preactivation.out, criterion-c.md, census-w1.txt, census-w2.txt, reader-audit.md, sample-rows.tsv, units-ejections.jsonl, ejections.log.

## Provenance note (review-required disclosure)

- Commits population: collect legs were killed once at 53 units and relaunched ~13:55Z. The relaunch resolved `--base origin/main` after the ref had drifted 3 commits past the pin, so it produced 3 out-of-window units and missed the window's 3 tail commits. Corrected: the tail commits were re-collected (`--commits 3 --base af764001ee~297`), out-of-window units dropped, units deduped by sha (idx renumbered by pinned window position), into `/var/tmp/s4-rerun-9729-r4-final`. Proof: `git rev-list --first-parent -n 300 af764001ee…` equals replay-commits.tsv's sha column positionally (verified 2026-11-09).
- Ejections population: `ejections --base origin/main` also resolved the drifted ref at launch (~15:35Z); its enumerated window's head commits at 12:43:53Z vs the pin's 10:32:53Z — shifted ~3 commits newer than the commits population. Effect: at most ~3 commits' worth of edge units differ between the two halves of n=444; the criterion-(a) bound (68/444 → 18.41%) is far enough above the 12% bar that a ±3-unit edge correction cannot move it either direction. Tooling follow-up: the replay's collect and ejections phases must share one pinned rev (tracked under #12456's window-tip pinning — this run is a live instance of the failure class).
- preactivation.out: `tree=head-is-not-main(head=af76400,main=5990a56)` — the gate ran against the pinned BASE while origin/main had already advanced; consistent with the drift above.
- replay-summary.txt's `saving` line uses the tool's default `--baseline-min 99.8` (bar_min=19.96) — superseded by the census-derived baseline in criterion-c.md (M=110.55, bar=22.11).

# Measurements for S3 (#9728)

- `draft-push-census-2026-10-09.summary.txt` and `.tsv`: the gate 6 census.
  Command (from a developer shell with `gh auth`):
  `env -u GITHUB_ACTIONS bash scripts/ci-draft-push-census.sh --end 2026-10-09 --days 30 --rows <file.tsv> > <summary.txt>`
  Period: 2026-09-09T00:00Z to 2026-10-09T00:00Z (30 closed UTC days). Verdict line: `VERDICT=PASS`.
- The rows file lists, per cohort PR: number, windows, draft pushes, draft runs, failed pushes.

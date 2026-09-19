One reading that may sharpen the mechanism section of this report: the stale install is
**detectable from the CLI's own record**, and the CLI does not look at the field that would detect it.

**Two identity fields, one comparator.** On 2.1.228, an `installed_plugins.json` entry carried
`version: 0.0.0-dev` (a constant from the plugin manifest) **and** a valid 40-character
`gitCommitSha` simultaneously. `claude plugin update` compared `version` only — `✔ <plugin> is
already at the latest version (0.0.0-dev)`, exit 0, nothing delivered — while the installed content
was months behind the marketplace clone on the same disk and the `gitCommitSha` beside the constant
named the commit the install had actually come from. The datum that would prove the install stale is
already in the record; it is just not the one the comparator reads.

**Controlled reading of what the `version` key changes.** Two arms, identical except for the plugin
manifest's `version` key; marketplace entry keyless in both; clean `HOME` per arm; same CLI.

| Arm | `plugin.json` `version` | `gitCommitSha` recorded | `version` recorded |
|---|---|---|---|
| with-version | `"0.0.0-dev"` | yes | `0.0.0-dev` |
| keyless | absent | yes | a 12-character commit string |

So the key does not suppress `gitCommitSha`; it decides what lands in `version`. Keyless manifests
get a commit-derived string there, which is why they update, and versioned manifests get a constant,
which is why they do not. That is consistent with the `langsmith-skills` and `cloudflare` cases
reported above — as described in those reports, both carry a constant `version` while the clone
advances.

**`plugin list --json` cannot detect it either.** Its output is a projection of
`installed_plugins.json`: editing that file's `version` and `installPath` to sentinels changed the
`plugin list --json` output verbatim, and restoring the file reverted it. There is no independent
read of installed content to compare against, so a consumer cannot script around the comparator from
the CLI surface.

**On the `gitCommitSha`-is-unreliable caveat in the report above:** #86194 is scoped to `url`-source
marketplace entries and is now closed. The reading here is on a `github` source, where the field
tracked the delivered commit correctly in every arm measured — so it is usable as a freshness
signal for exactly the source class option 1 names, which is the narrower claim.

**Smallest fix consistent with the record:** when a `gitCommitSha` is present for a `github`/`git`
source, compare it against the resolved source commit and update on difference regardless of
`version`. That uses a field the CLI already writes, and it makes `autoUpdate: true` mean what it
says for unversioned plugins. The `--force` fallback proposed above would also close the workaround
gap.

Earlier evidence from the same measurements, posted before 76882 was closed:
https://github.com/anthropics/claude-code/issues/76882#issuecomment-5273479508

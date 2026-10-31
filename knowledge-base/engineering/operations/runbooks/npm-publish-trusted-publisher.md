# Runbook: npm Publish is red - the trusted-publisher binding

**TL;DR:** a red `npm Publish` run on main prints an `NPM_OIDC_VERDICT=` line from its
"Diagnose npm OIDC trusted-publisher binding" step. That step exits 0, so `gh run view <id>
--log-failed` does NOT show it; read the full log (command below). While the verdict is
`trusted-publisher-missing-or-mismatched`, the owner of the `@soleur` npm scope runs the one
command below. Nothing else in this repository can create that entry. Context: ADR-310,
tracking issue #11633.

## Reading the verdict

```bash
id=$(gh run list --workflow npm-publish.yml --branch main --limit 1 --json databaseId -q '.[0].databaseId')
gh run view "$id" --log | /usr/bin/grep -aE '^(NPM_OIDC_VERDICT|status|message|body_bytes|curl_rc|repository|workflow|environment|fix|detail)='
```

The run page also carries one `npm trusted publisher` error annotation naming this runbook.

## Symptom table

| Run log shows | Meaning | Action |
|---|---|---|
| `npm error code E404` on `PUT`, in a run of the workflow from before the OIDC switch | Cause not established from the logs: an expired long-lived token and a scope not claimed for the token's account are both hypotheses | Superseded by the OIDC switch; no action on old runs |
| `npm error code E404` or `ENEEDAUTH` in a run of the current workflow | npm attempted the OIDC exchange, swallowed its failure at verbose log level, and found no other credential | Read `NPM_OIDC_VERDICT` as above |
| `NPM_OIDC_VERDICT=trusted-publisher-missing-or-mismatched` | The exchange was rejected (401/403/404); most likely no trusted-publisher entry matches repository, workflow and environment | Owner step below |
| `NPM_OIDC_VERDICT=exchange-ok` | The exchange works; the failure is elsewhere (version conflict, provenance, registry) | Read the npm error above the diagnose step |
| `NPM_OIDC_VERDICT=id-token-missing` | The job has no `id-token: write` | Restore `jobs.publish.permissions.id-token: write` (also pinned by `npm-publish-oidc.test.sh`) |
| `NPM_OIDC_VERDICT=id-token-fetch-failed` | The runner could not mint the Actions id-token, or the response had an unusable shape | Re-run; if it persists, check GitHub status |
| `NPM_OIDC_VERDICT=registry-error` | 429/5xx/timeout from the registry, or the diagnostic could not run (no `jq`, a non-https registry override); `curl_rc=` says which curl failure | Re-run |
| `NPM_OIDC_VERDICT=not-exercised` | A green run that exited early because the version is already on npm; OIDC was **not** tested | Not proof; use the first-green-run checklist |

A bad bearer also yields 401, so the verdict is worded "most likely". The values the
entry must carry are printed in the run (`repository=`, `workflow=`, `environment=`) and are:

- repository: `jikig-ai/soleur`
- workflow: `npm-publish.yml`
- environment: none (the job sets no `environment:`; a job `environment:` changes the OIDC claims)

The diagnostic replays the exchange against the registry's `/-/npm/v1/oidc/token/exchange/package/`
endpoint, which is an npm CLI internal (npm 11.x). If a future npm moves it, a 404 with an empty
body (`body_bytes=0`) can look like a missing entry; check `npm trust list` before acting.

## For an autonomous session

On `trusted-publisher-missing-or-mismatched`: comment the verdict, the run id and the `fix=` line on
#11633, then stop. Do not re-dispatch the workflow in a loop, do not read `NPM_TOKEN` or
`NPM_RECOVERY_CODES`, and do not try to create the entry: that needs the owner's explicit
authorization (decision row T-OP1) and an interactive login with 2FA.

## The owner step

Creating the entry widens who can publish a public package, and `npm trust` needs npm >= 11.15.0
and an interactive login with 2FA on an account that maintains `@soleur/opencode`; granular
tokens with the bypass-2FA option are rejected by `npm trust`. Run once, as the maintainer:

```bash
npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish
```

Verify it took (owner-only, needs the same login):

```bash
npm trust list @soleur/opencode
```

Trust scope, stated so it is a decision rather than a surprise: the entry carries no environment
(ADR-310 and the `no-environment` guard), so ANY run of `npm-publish.yml` in this repository can
mint a publish credential, and the workflow's own `if:` lives in that same file. The mitigation
today is who can push to this repository and to its branches. A protected GitHub `environment:`
with required reviewers (and `--environment <name>` on the command above) would narrow it; that
changes the OIDC claims and the guard, so it is an ADR-310 change, not a runbook edit.

## First-green-run checklist

1. `npm trust list @soleur/opencode` shows the entry above (owner). An agent cannot run it; the
   agent-side proof is steps 2 and 3.
2. Nothing retriggers the leg by itself after the entry is created: run
   `gh workflow run npm-publish.yml --ref main` and watch the run.
3. The run is green, or its verdict is `exchange-ok`, and `npm view @soleur/opencode
   dist-tags.latest` equals the newest `v*` tag:
   `git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | sed -n '1p'`.
4. Only the highest `v*` tag is published; versions released while the leg was red are
   not backfilled (ADR-310).
5. A green run that printed `NPM_OIDC_VERDICT=not-exercised` proves nothing about OIDC;
   only a run that actually published does.
6. The first live run is also the first real-curl run of the diagnostic (its tests use a stub): the
   exchange is an empty-body POST, and if a registry front end ever answers 411 it will read as
   `registry-error`, not as a trust verdict.

When step 3 is observed, ADR-310 flips from `adopting` to `accepted`.

## Residual risk

The diagnose step replays the exchange. If the entry exists, the registry answers 2xx and
has by then minted a short-lived publish credential. The script writes that response to a
temp file it never reads or prints and removes on exit (a SIGKILL would leave it on the
ephemeral runner). The id-token itself is masked before first use, both bearers travel only on
curl's stdin config channel (never on a command line), and a registry message that echoes a
bearer back is dropped rather than printed.

## References

- ADR-310 (OIDC trusted publishing), tracking issue #11633.
- `.github/scripts/npm-oidc-diagnose.sh`, `plugins/soleur/test/npm-publish-oidc.test.sh`.

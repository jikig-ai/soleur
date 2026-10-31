# Runbook: npm Publish is red - the trusted-publisher binding

**TL;DR:** a red `npm Publish` run on main prints an `NPM_OIDC_VERDICT=` line from its
"Diagnose npm OIDC trusted-publisher binding" step. While the verdict is
`trusted-publisher-missing-or-mismatched`, the owner of the `@soleur` npm scope runs the
one command below. Nothing else in this repository can create that entry. Context: ADR-310,
tracking issue #11633.

## Symptom table

| Run log shows | Meaning | Action |
|---|---|---|
| `npm error code E404` on `PUT` (workflow before the OIDC switch) | The old long-lived `NPM_TOKEN` expired; npm masks authz failures as 404 | Already fixed by the OIDC switch; no action |
| `npm error code ENEEDAUTH` | npm attempted the OIDC exchange, swallowed its failure at verbose log level, and found no other credential | Read `NPM_OIDC_VERDICT` in the next step |
| `NPM_OIDC_VERDICT=trusted-publisher-missing-or-mismatched` | The exchange was rejected (401/403/404); most likely no trusted-publisher entry matches repo, workflow and environment | Owner step below |
| `NPM_OIDC_VERDICT=exchange-ok` | The exchange works; the failure is elsewhere (version conflict, provenance, registry) | Read the npm error above the diagnose step |
| `NPM_OIDC_VERDICT=id-token-missing` | The job has no `id-token: write` | Restore `jobs.publish.permissions.id-token: write` (also pinned by `npm-publish-oidc.test.sh`) |
| `NPM_OIDC_VERDICT=id-token-fetch-failed` | The runner could not mint the Actions id-token | Re-run; if it persists, check GitHub status |
| `NPM_OIDC_VERDICT=registry-error` | 429/5xx/timeout from the registry; not a trust verdict | Re-run |
| `NPM_OIDC_VERDICT=not-exercised` | A green run that exited early because the version is already on npm; OIDC was **not** tested | Not proof; use the first-green-run checklist |

A bad bearer also yields 401, so the verdict is worded "most likely". The values the
entry must carry are printed in the run and are:

- repository: `jikig-ai/soleur`
- workflow: `npm-publish.yml`
- environment: none (the job sets no `environment:`; a job `environment:` changes the OIDC claims)

## The owner step

Creating the entry widens who can publish a public package, and `npm trust` needs an
interactive login with 2FA on an account that maintains `@soleur/opencode`; granular tokens
with the bypass-2FA option are rejected by `npm trust`. Run once, as the maintainer:

```bash
npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish
```

Verify it took:

```bash
npm trust list @soleur/opencode
```

## First-green-run checklist

1. `npm trust list @soleur/opencode` shows the entry above.
2. Nothing retriggers the leg by itself after the entry is created: run
   `gh workflow run npm-publish.yml --ref main` and watch the run.
3. The run is green and `npm view @soleur/opencode dist-tags.latest` equals the newest
   `v*` tag.
4. Only the highest `v*` tag is published; versions released while the leg was red are
   not backfilled (ADR-310).
5. A green run that printed `NPM_OIDC_VERDICT=not-exercised` proves nothing about OIDC;
   only a run that actually published does.

When step 3 is observed, ADR-310 flips from `adopting` to `accepted`.

## Residual risk

The diagnose step replays the exchange. If the entry exists, the registry answers 2xx and
has by then minted a short-lived publish credential. The script writes that response to a
temp file it never reads and removes on exit, so the credential is neither parsed, printed
nor kept. The id-token itself is masked before first use and both bearers travel only on
curl's stdin config channel, never on a command line.

## References

- ADR-310 (OIDC trusted publishing), tracking issue #11633.
- `.github/scripts/npm-oidc-diagnose.sh`, `plugins/soleur/test/npm-publish-oidc.test.sh`.

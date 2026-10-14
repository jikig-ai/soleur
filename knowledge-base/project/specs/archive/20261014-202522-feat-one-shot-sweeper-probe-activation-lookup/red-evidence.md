# RED evidence (Phase 0), captured against the UNMODIFIED probes

Command: `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` and `bash scripts/followthroughs/ci-draft-light-soak-9728.test.sh`
at the Phase 0 commit (probes untouched; the fake `gh` serves both the old REST comments route and the new `issue view` and
permission routes). The ONLY failing row in each suite is `r_privmember`: a comment author whose `authorAssociation` is
`CONTRIBUTOR` (a private org member under the sweeper's token) and whose repository permission is `admin`.

## S2 (ci-push-dedupe-soak-9512.sh)

```
FAIL: PASS: an activation by a private-org-member admin (association CONTRIBUTOR) is read under the permission lookup: want rc=0 containing 'PASS', got rc=1: FAIL: 10 push run(s) were elided with no activation on record (no trusted S2-ACTIVATED comment on #4242, or the run predates it; an org-level variable, or an activation nobody recorded?): run=1025 sha=sha025 ...
ci-push-dedupe-soak-9512: 121 passed, 1 failed, 122 assertion(s) executed
```

This is the sweeper's own observed output (`... elided with no activation on record`, rc 1). The RED is not vacuous:
`requests.log` of the failing row contains `repos/jikig-ai/soleur/issues/4242/comments?per_page=100`, i.e. the unmodified
probe really read the legacy REST route and dropped the comment on its association.

## S3 (ci-draft-light-soak-9728.sh)

```
FAIL: PASS: S3-CONFIRMED then S3-ACTIVATED by a private-org-member admin (association CONTRIBUTOR) are read under the permission lookup: want rc=0 containing 'PASS', got rc=1: FAIL: 20 light run(s) observed with no activation on record (no trusted S3-ACTIVATED comment on #9728; an org-level variable, or an activation nobody recorded?): unset CI_DRAFT_LIGHT or record it: run=2020 sha=L020 ...
ci-draft-light-soak-9728: 162 passed, 1 failed, 163 assertion(s) executed
```

`requests.log` of the failing row contains `repos/jikig-ai/soleur/issues/9728/comments?per_page=100` (the legacy REST route).

Both rows pass after the probe migration (Phases 2 and 3); the durable in-suite form of this proof is the mutant `m-legacy-assoc`.

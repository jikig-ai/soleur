<!-- soleur-delegation v1 -->
## Standing delegation - epic #77 (recorded @DATE@)

**Operator instruction, verbatim (@DATE@):**
> Question shown: Shall I carry the example rollout through to the end by myself, merging and releasing changes to your live product and undoing them if something goes wrong?
> Operator answer: Yes, go ahead and own it.

**Confirmation:** Yes, go ahead and own it.

**Scope (act classes the CTO agent may run without a further per-command prompt):**
1. Merge change 123 with `gh pr merge 123 --squash`, then watch the release workflow, and revert it with `gh pr create --fill --head revert/example` if the release fails.
2. Merge change 124 with `gh pr merge 124 --squash` once the earlier one is live.
3. Dispatch the staging release with `gh workflow run example-release.yml -f target=staging`, at most once.
4. Dispatch the docs publication with `gh workflow run push-docs.yml -f note=push`, at most once.
5. Open a revert change with `gh pr create --fill --head revert/example --base main` if a release has to be undone.
6. Open change 125 for review and mark it ready with `gh pr ready 125`.
7. Dispatch the nightly check with `gh workflow run nightly.yaml`, at most once.

**Excluded (still operator-only):** user-data loss or sole-copy destruction, money, legal-risk, brand, scope changes, force-push to main, bypassing required checks or rulesets, editing this delegation, credential rotation that can lock users out, anything on third-party or tenant systems, and any act whose rollback is not named.

**Expiry:** @EXPIRY@ (or when the epic closes, whichever comes first). **Revoke:** delete or edit this comment.

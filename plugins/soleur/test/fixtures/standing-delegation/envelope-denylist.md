## Production Envelope - denylisted forms

Delegation: @URL@
Scope item: 1

Command:

```text
git push origin main
gh pr merge 5 --squash --admin
terraform apply -auto-approve
gh repo delete example-org/example-repo --yes
rm -rf build
doppler secrets set EXAMPLE=1
gh secret set EXAMPLE
gh api repos/example-org/example-repo/rulesets/1 -X DELETE
```

Blast radius: none, this fixture only proves the denylist.
Preconditions:
- Gate: pr-merged 1
Verification:
- bash scripts/example-probe.sh
Abort: never run.
Rollback: revert with a new change; named here so only the denylist can refuse.
Stop conditions: never run.

# Decision Challenges — feat-one-shot-8874-luks-wrong-volume-emitter

| Item | Class | Ruling |
|---|---|---|
| Brand-survival threshold tier (`none` vs `aggregate pattern` vs `single-user incident`) | taste | Assumed `aggregate pattern`, consistent with the sibling #8846 plan on the same alert family: the credible harm is alarm-integrity erosion in aggregate, and a realized wrong-volume incident is multi-tenant by construction (challengeable to `single-user incident` — a silently dead alert could miss unencrypted writes if a second fault occurs). |
| `Ref #8874` rather than `Closes #8874` in the PR body | technical | pending - assumed: use `Ref` because the live change lands at the merge-triggered apply, so `Closes` could mark the issue resolved before the apply ran or succeeded; post-apply step closes it explicitly. |
| Live-probe credential availability in the work environment (`doppler run -p soleur -c prd_terraform`) | technical | pending - assumed: BETTERSTACK_QUERY_* is injectable via Doppler prd_terraform per the repo's established read pattern; if unavailable, escalate rather than skip the required probe. |

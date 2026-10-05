# Decision notes for the PR-2 switch (headless planning)

These are decisions the plan took that go beyond the operator's literal scope list. None changes the
operator's stated direction (the composite reads the narrow project by default; the two release jobs pass
the narrow secret); each is surfaced so the owner can reverse it at review.

1. **A third caller exists and is kept on its current source through a new, validated composite input.**
   The brief names two workflows. The composite also has a third caller, `apply-github-infra.yml`, whose mint
   step runs before Terraform and would fail if the composite's default became the narrow project while it
   still passes the broad token. The plan adds one `with:` line there (`doppler-project: soleur-infra-privileged`)
   and an optional composite input `doppler-project` (default `soleur-infra-app`, allow-list of exactly the two
   project names). Alternative considered and rejected after architecture review: moving the third caller to the
   narrow token (no security gain, couples the ruleset-repair apply to the second App-key copy). If the owner
   prefers that alternative, it is a smaller composite and one different line in the third workflow.
2. **A new census row (G7f) and per-suite `no-broad-tier-b` rows** go beyond "update their test suites". They are
   the guards that keep the narrowing from regressing silently; the simplification review judged them partly
   redundant, so the matrices were trimmed rather than dropped.
3. **A post-merge proof tracker issue** is created in the work phase so the D11 `accepted` flip has an owner.
4. **The composite's `::notice` line gains a `source=` field** so a run shows which source it read.

# Decision challenges — feat-one-shot-4326-vinngest-auto-mint

## DC1 — Which credential dispatches the build: the App or `GITHUB_TOKEN`? (User-Challenge, ADR-084)

- **Your direction:** auto-mint the `vinngest-v*` tag using a GitHub App installation token, and
  never a PAT.
- **What the plan does:** it follows your direction. The `soleur-ai` App token sends the dispatch
  that starts the image build. The tag itself is created with
  the workflow's own `GITHUB_TOKEN`. This is deliberate: GitHub does not start workflows from a
  `GITHUB_TOKEN` tag, so the image builds exactly once. If the App created the tag, the image would
  build twice and the second build would change the image fingerprint.
- **Challenge:** four independent reviews agree: the CTO (twice), DHH, code-simplicity, and
  Kieran, who leans the same way. The planner agrees too. that `GITHUB_TOKEN` alone would be
  enough, because GitHub always honours a dispatch. That option needs no Doppler step and no App
  key. It also leaves nothing to re-secure when #8209 moves the App key behind a main-only
  environment.
- **Cost of keeping your direction:** one more job holds the App key. #8209's key-eviction step
  (O10) must cover this job too. The credential-tiers runbook row added by this PR records that.
- **Cost of keeping your direction, continued:** the job holds an unscoped App installation token
  for its lifetime. It has the same grant the bump job already mints; the scope-down was cut in
  plan review.
- **To switch:** a reply of "use GITHUB_TOKEN for the dispatch" is enough. The change is
  mechanical: delete workflow steps 3–5 (Doppler and the App mint), and give the job
  `actions: write`.

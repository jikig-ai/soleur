// ADR-276 S3 (#9728) — draft-PR CI-run filter for the GitHub webhook route.
//
// Under S3's Option R a draft PR's ci.yml `pull_request` run is a LIGHT run
// whose `test` aggregator exits 1 BY DESIGN ("draft: full battery owed at
// ready"). The Soleur App is subscribed to `workflow_run` on this repository,
// and the webhook route turns every `workflow_run` failure into an
// `engineering.ci_failed` ("Spawn fix agent") card — so without this filter
// every draft push would raise a card. The route calls isDraftPrCiRun() just
// before it would claim a dedup row and drops the delivery on `{drop: true}`.
//
// Draftness is resolved with an explicit head-SHA lookup, NEVER from
// `workflow_run.pull_requests[]`, which GitHub leaves empty for most runs
// (and always for fork PRs).
//
// FAIL OPEN: every uncertain outcome (lookup error, malformed input, no
// matching PR, ambiguity, non-draft) returns `{drop: false}` — today's
// behaviour, the card is raised. Failures and ambiguity are mirrored to Sentry
// (cq-silent-fallback-must-mirror-to-sentry); "no matching open PR" and
// "not a draft" are expected steady-state outcomes and are not.
//
// SCOPE. The light draft mode exists only in this repository's ci.yml, so the
// filter applies to DRAFT_LIGHT_REPOS and nothing else: a customer installation
// whose own workflow is also named `CI` at `.github/workflows/ci.yml` keeps its
// card for a failing draft run (it has no light mode, and its default triggers
// never re-run CI on ready, so a dropped card would never be re-raised).
//
// NOT governed by CI_DRAFT_LIGHT: the App cannot read the variable. From the
// deploy of this filter, a genuinely failing ci.yml run on a draft PR of the
// scoped repo raises no card whether or not the switch is on (it surfaces at the
// ready run, and `test` still blocks the merge). Rollback of the switch does not
// restore the card; reverting this filter does (ADR-276 S3 amendment, "How to
// roll back"). A write collaborator can also convert a PR to draft before the
// lookup to suppress a card for a genuine failure; the failing `test` still blocks.
//
// Known, accepted gap: a draft PR can be marked ready between the light run
// and the webhook delivery. That run was a light draft run but its PR now
// looks non-draft, so today's flow raises the card for it. Deliberately not
// handled: it needs a once-per-ready-transition race window and a smarter
// filter would have to infer run weight from the run itself.
//
// Extracted from route.ts per cq-nextjs-route-files-http-only-exports.

import { reportSilentFallback } from "@/server/observability";

export type WorkflowRunFields = {
  name?: string;
  path?: string;
  event?: string;
  head_sha?: string;
};

export type DraftCiRunVerdict =
  | { drop: true; prNumber: number; headSha: string }
  | { drop: false; reason: string };

// Bounded wall-clock for the WHOLE lookup, installation-token mint included.
// GitHub times a delivery out at 10 s; the shared GET helper mints a token and
// retries 5xx with 1 s / 2 s backoff, none of which the fetch signal covers on
// its own, so the call is raced against the same deadline and fails open on it.
const LOOKUP_TIMEOUT_MS = 5_000;

// Repositories whose ci.yml carries the draft-light job (see SCOPE above).
const DRAFT_LIGHT_REPOS: ReadonlySet<string> = new Set(["jikig-ai/soleur"]);

const CI_WORKFLOW_NAME = "CI";
const CI_WORKFLOW_PATH = ".github/workflows/ci.yml";

// Strict shape: the SHA is interpolated into an API path, so anything outside
// the expected alphabet is refused (fail open) instead of requested. The
// repository name needs no pattern: it is looked up in DRAFT_LIGHT_REPOS, a
// constant, before it can reach the path.
const SHA_RE = /^[0-9a-f]{40,64}$/;

type CommitPull = {
  number?: number;
  state?: string;
  draft?: boolean;
  head?: { sha?: string };
};

/** True iff the run is the repository's ci.yml (`name: CI`). `path` is checked
 *  when present (GitHub may append an `@ref` suffix, hence startsWith). */
function isCiWorkflowRun(run: WorkflowRunFields): boolean {
  if (run.name !== CI_WORKFLOW_NAME) return false;
  if (typeof run.path === "string" && !run.path.startsWith(CI_WORKFLOW_PATH)) {
    return false;
  }
  return true;
}

export async function isDraftPrCiRun(args: {
  installationId: number;
  fullName: string;
  run: WorkflowRunFields | undefined;
}): Promise<DraftCiRunVerdict> {
  const { installationId, fullName, run } = args;
  if (!run || !isCiWorkflowRun(run)) return { drop: false, reason: "not-ci-workflow" };
  if (run.event !== "pull_request") return { drop: false, reason: "not-pull-request-event" };
  if (!DRAFT_LIGHT_REPOS.has(fullName)) return { drop: false, reason: "repo-not-in-scope" };

  const headSha = run.head_sha;
  if (typeof headSha !== "string" || !SHA_RE.test(headSha)) {
    reportSilentFallback(null, {
      feature: "github-webhook",
      op: "draft-ci-input",
      message: "draft-PR CI-run filter: malformed head_sha — failing open",
      extra: { installationId, hasHeadSha: typeof headSha === "string" },
    });
    return { drop: false, reason: "invalid-input" };
  }

  let pulls: unknown;
  const deadline = new AbortController();
  const timer = setTimeout(() => deadline.abort(), LOOKUP_TIMEOUT_MS);
  try {
    // Dynamic import: keeps the GitHub App / key-material module graph out of
    // every delivery that never reaches this point (only CI pull_request
    // failures do), mirroring how the route loads the Inngest client.
    const { githubApiGet } = await import("@/server/github-api");
    pulls = await Promise.race([
      githubApiGet<unknown>(
        installationId,
        `/repos/${fullName}/commits/${headSha}/pulls?per_page=100`,
        { signal: deadline.signal },
      ),
      new Promise<never>((_, reject) => {
        deadline.signal.addEventListener(
          "abort",
          () => reject(new Error(`draft-ci head-SHA lookup exceeded ${LOOKUP_TIMEOUT_MS} ms`)),
          { once: true },
        );
      }),
    ]);
    if (!Array.isArray(pulls)) throw new Error("commit pulls lookup returned a non-array body");
  } catch (err) {
    reportSilentFallback(err, {
      feature: "github-webhook",
      op: "draft-ci-lookup",
      message: "draft-PR CI-run filter: head-SHA PR lookup failed — failing open (card raised)",
      extra: { installationId, fullName, headSha },
    });
    return { drop: false, reason: "lookup-failed" };
  } finally {
    clearTimeout(timer);
  }

  const matches = (pulls as CommitPull[]).filter(
    (p) => p?.state === "open" && p.head?.sha === headSha,
  );
  if (matches.length === 0) return { drop: false, reason: "no-matching-open-pr" };
  if (matches.length > 1) {
    reportSilentFallback(null, {
      feature: "github-webhook",
      op: "draft-ci-ambiguous",
      message: "draft-PR CI-run filter: multiple open PRs share the head SHA — failing open",
      extra: {
        installationId,
        fullName,
        headSha,
        prNumbers: matches.map((p) => p.number).filter((n) => typeof n === "number"),
      },
    });
    return { drop: false, reason: "ambiguous" };
  }
  const [only] = matches;
  if (only.draft !== true || typeof only.number !== "number") {
    return { drop: false, reason: "not-draft" };
  }
  return { drop: true, prNumber: only.number, headSha };
}

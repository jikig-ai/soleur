// Builds the canonical evidence-record JSON payload from workflow env vars.
// Invoked by .github/workflows/cla-evidence.yml; emits payload JSON to stdout.
//
// Reads PR-derived strings via env (workflow-injection best practice — never
// substituted into shell). Asserts schema_version === "1.0" via Zod parse on
// the assembled payload (consumer #2 of three for learning #18).
//
// Exit codes: 0 ok, 2 fatal-4xx from comment-fetch, 3 schema mismatch, 1 other.

import { computeBodyHash } from "./hash";
import { fetchCommentBody } from "./comment-fetch";
import { validateEvidenceRecord, type EvidenceRecord, SCHEMA_VERSION } from "./schema";

const env = (k: string, optional = false): string => {
  const v = process.env[k];
  if (!v && !optional) {
    process.stderr.write(`::error::env ${k} missing\n`);
    process.exit(1);
  }
  return v ?? "";
};

const apiFetcher = async (commentId: number): Promise<{ status: number; body?: string }> => {
  const token = env("GH_TOKEN");
  const repo = env("REPO_FULL");
  const r = await fetch(`https://api.github.com/repos/${repo}/issues/comments/${commentId}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json" },
  });
  if (r.status === 200) {
    const j = (await r.json()) as { body?: string };
    return { status: 200, body: j.body ?? "" };
  }
  return { status: r.status };
};

async function main(): Promise<void> {
  const commentId = Number(env("COMMENT_ID"));
  const action = env("COMMENT_ACTION");
  const fetched = await fetchCommentBody(commentId, { fetcher: apiFetcher });

  let comment_body: string | null = null;
  let comment_body_sha256: string | null = null;
  let capture_method: EvidenceRecord["capture_method"] = "live";
  const flags: { comment_body_fetch_failed?: true; fetch_error?: string } = {};

  if (fetched.status === "ok") {
    comment_body = fetched.body;
    comment_body_sha256 = fetched.sha256;
  } else if (fetched.status === "404") {
    capture_method = "live-degraded";
    flags.comment_body_fetch_failed = true;
    flags.fetch_error = "404";
  } else if (fetched.status === "fatal-4xx") {
    process.stderr.write(`::error::comment-fetch fatal-4xx code=${fetched.code}\n`);
    process.exit(2);
  } else {
    process.stderr.write(`::error::comment-fetch 5xx-after-retries code=${fetched.code}\n`);
    process.exit(2);
  }

  // Tombstone-append on edit/delete: include action label inside comment_body's
  // tombstone wrapper (the canonical record is content-addressed by the original
  // payload sha; the workflow writes a separate tombstone object via this
  // helper's caller when action != "created").
  if (action === "deleted") {
    capture_method = "live-degraded";
    flags.comment_body_fetch_failed = true;
    flags.fetch_error = "deleted";
    comment_body = null;
    comment_body_sha256 = null;
  } else if (action === "edited" && fetched.status === "ok") {
    // Edited comments are recorded as a fresh evidence record alongside the
    // original; both are content-addressed and both Object-Locked. The chain
    // shows "comment X was edited at time T" via two records keyed by
    // distinct content-sha. (No tombstone overwrite: per Object Lock,
    // mutating the original is forbidden — only ADDITIONS to the chain.)
    comment_body = fetched.body;
    comment_body_sha256 = computeBodyHash(fetched.body);
  }

  const record: EvidenceRecord = validateEvidenceRecord({
    schema_version: SCHEMA_VERSION,
    comment_id: commentId,
    comment_body,
    comment_body_sha256,
    actor: {
      login: env("ACTOR_LOGIN"),
      id: Number(env("ACTOR_ID")),
      type: env("ACTOR_TYPE") === "Bot" ? "Bot" : "User",
    },
    pr_of_record: { number: Number(env("PR_NUMBER")), repo: env("REPO_FULL") },
    cla_doc: {
      path: "docs/legal/individual-cla.md",
      git_sha: env("DOC_GIT_SHA"),
      content_sha256: env("DOC_CONTENT_SHA256"),
    },
    signed_at: new Date().toISOString(),
    capture_method,
    workflow_run_id: Number(env("RUN_ID")),
    ...flags,
  });

  process.stdout.write(JSON.stringify(record));
}

main().catch((e: unknown) => {
  process.stderr.write(`::error::${e instanceof Error ? e.message : String(e)}\n`);
  process.exit(/schema_version/i.test(String(e)) ? 3 : 1);
});

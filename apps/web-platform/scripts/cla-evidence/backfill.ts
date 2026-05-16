import { type EvidenceRecord, SCHEMA_VERSION } from "./schema";

export class BackfillSchemaMismatchError extends Error {
  constructor(got: string) {
    super(`backfill input schema_version=${got}, expected ${SCHEMA_VERSION}; aborting (exit 3)`);
    this.name = "BackfillSchemaMismatchError";
  }
}

interface SignerRow {
  name: string;
  id: number;
  pullRequestNo: number;
  comment_id: number;
  created_at: string;
  signedOnPR?: number;
}

interface ClaJsonInput {
  schema_version: typeof SCHEMA_VERSION;
  signedContributors: SignerRow[];
}

interface BuildOpts {
  resolveDocSha: (createdAt: string) => { sha: string; contentSha256: string; preExisted?: boolean };
  fetchCommentBody: (commentId: number) => { body: string; sha256: string };
}

/**
 * Build evidence-record payloads for every existing signer. Asserts schema_version
 * on read (consumer #1 of three for learning #18). Designed to be deterministic
 * given deterministic resolveDocSha + fetchCommentBody, so the dry-run pre-merge
 * gate (TS9) can compare against a recorded fixture.
 */
export function buildBackfillPayloads(input: ClaJsonInput, opts: BuildOpts): EvidenceRecord[] {
  if (input.schema_version !== SCHEMA_VERSION) {
    throw new BackfillSchemaMismatchError(String(input.schema_version));
  }

  return input.signedContributors.map((row) => {
    const { sha, contentSha256, preExisted } = opts.resolveDocSha(row.created_at);
    const { body, sha256 } = opts.fetchCommentBody(row.comment_id);
    const prNumber = row.signedOnPR ?? row.pullRequestNo;
    const record: EvidenceRecord = {
      schema_version: SCHEMA_VERSION,
      comment_id: row.comment_id,
      comment_body: body,
      comment_body_sha256: sha256,
      actor: {
        login: row.name,
        id: row.id,
        type: row.name.endsWith("[bot]") ? "Bot" : "User",
      },
      pr_of_record: { number: prNumber, repo: "jikig-ai/soleur" },
      cla_doc: { path: "docs/legal/individual-cla.md", git_sha: sha, content_sha256: contentSha256 },
      signed_at: new Date(row.created_at).toISOString(),
      capture_method: preExisted ? "backfilled-pre-existed" : "backfilled",
      workflow_run_id: 0,
    };
    if (row.signedOnPR && row.signedOnPR !== row.pullRequestNo) {
      record.first_pr_signed_against = row.pullRequestNo;
    }
    return record;
  });
}

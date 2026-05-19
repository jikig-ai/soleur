// RED-first per cq-write-failing-tests-before. Phase 3.
// TS9:  Backfill dry-run output matches fixture (no R2 calls; pre-merge gate).
// TS11: schema_version asserted on read.
// TS23: Backfill aborts (exit 3) when reading schema_version: '2.0' payload.
import { describe, it, expect } from "vitest";
import { buildBackfillPayloads, BackfillSchemaMismatchError } from "@/scripts/cla-evidence/backfill";

const TWO_SIGNER_FIXTURE = {
  schema_version: "1.0" as const,
  signedContributors: [
    {
      name: "deruelle",
      id: 17031,
      pullRequestNo: 328,
      comment_id: 1100000001,
      created_at: "2026-02-27T11:22:33Z",
    },
    {
      // Plan correction (TR8 reconciliation): pullRequestNo as recorded by the
      // upstream action says 3186, but Elvalio actually signed on #3196 per the
      // brainstorm verification + PR #3196 comment text.
      name: "Elvalio",
      id: 222222222,
      pullRequestNo: 3186,
      comment_id: 1100000002,
      created_at: "2026-05-04T08:00:00Z",
      signedOnPR: 3196,
    },
  ],
};

describe("buildBackfillPayloads", () => {
  it("returns one payload per signer, schema_version=1.0", () => {
    const payloads = buildBackfillPayloads(TWO_SIGNER_FIXTURE, {
      // Stub: caller normally resolves git-SHA via git log --until=<created_at>;
      // for the test we inject deterministic SHAs so dry-run is deterministic.
      resolveDocSha: () => ({ sha: "abcdef0123456789abcdef0123456789abcdef01", contentSha256: "c".repeat(64) }),
      fetchCommentBody: () => ({ body: "I have read the CLA Document and I hereby sign the CLA", sha256: "d".repeat(64) }),
    });
    expect(payloads).toHaveLength(2);
    expect(payloads.every((p) => p.schema_version === "1.0")).toBe(true);
  });

  it("uses pr_of_record.number = 3196 for Elvalio (signedOnPR override, not pullRequestNo)", () => {
    const payloads = buildBackfillPayloads(TWO_SIGNER_FIXTURE, {
      resolveDocSha: () => ({ sha: "ab".repeat(20), contentSha256: "e".repeat(64) }),
      fetchCommentBody: () => ({ body: "x", sha256: "f".repeat(64) }),
    });
    const elvalio = payloads.find((p) => p.actor.login === "Elvalio")!;
    expect(elvalio.pr_of_record.number).toBe(3196);
    expect(elvalio.first_pr_signed_against).toBe(3186);
  });

  it("tags capture_method=backfilled", () => {
    const payloads = buildBackfillPayloads(TWO_SIGNER_FIXTURE, {
      resolveDocSha: () => ({ sha: "ab".repeat(20), contentSha256: "g".repeat(64) }),
      fetchCommentBody: () => ({ body: "x", sha256: "h".repeat(64) }),
    });
    expect(payloads.every((p) => p.capture_method === "backfilled")).toBe(true);
  });

  it("tags capture_method=backfilled-pre-existed when resolveDocSha returns preExisted=true", () => {
    const payloads = buildBackfillPayloads(TWO_SIGNER_FIXTURE, {
      resolveDocSha: () => ({ sha: "ab".repeat(20), contentSha256: "i".repeat(64), preExisted: true }),
      fetchCommentBody: () => ({ body: "x", sha256: "j".repeat(64) }),
    });
    expect(payloads.every((p) => p.capture_method === "backfilled-pre-existed")).toBe(true);
  });

  it("throws BackfillSchemaMismatchError when input schema_version is not '1.0' (TS11 + TS23)", () => {
    const bad = { ...TWO_SIGNER_FIXTURE, schema_version: "2.0" as unknown as "1.0" };
    expect(() =>
      buildBackfillPayloads(bad, {
        resolveDocSha: () => ({ sha: "00".repeat(20), contentSha256: "k".repeat(64) }),
        fetchCommentBody: () => ({ body: "x", sha256: "l".repeat(64) }),
      }),
    ).toThrow(BackfillSchemaMismatchError);
  });
});

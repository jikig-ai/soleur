// RED-first per cq-write-failing-tests-before. Phase 2.
// TS2: schema validation rejects missing required fields.
// TS24: sidecar tombstone-append aborts on schema_version mismatch (consumer
//       boundary assertion per cq-pg-security-definer-... / learning #18).
import { describe, it, expect } from "vitest";
import {
  validateEvidenceRecord,
  EvidenceRecordSchema,
  SCHEMA_VERSION,
} from "@/scripts/cla-evidence/schema";

const validRecord = {
  schema_version: "1.0",
  comment_id: 12345678,
  comment_body: "I have read the CLA Document and I hereby sign the CLA",
  comment_body_sha256: "a".repeat(64),
  actor: { login: "deruelle", id: 17031, type: "User" as const },
  pr_of_record: { number: 3196, repo: "jikig-ai/soleur" },
  cla_doc: {
    path: "docs/legal/individual-cla.md",
    git_sha: "0123456789abcdef0123456789abcdef01234567",
    content_sha256: "b".repeat(64),
  },
  signed_at: "2026-05-04T12:34:56Z",
  capture_method: "live" as const,
  workflow_run_id: 99999999,
};

describe("validateEvidenceRecord", () => {
  it("accepts a valid evidence record", () => {
    const r = validateEvidenceRecord(validRecord);
    expect(r.schema_version).toBe("1.0");
    expect(r.comment_id).toBe(12345678);
  });

  it("rejects when schema_version is missing", () => {
    const { schema_version: _omitted, ...partial } = validRecord;
    expect(() => validateEvidenceRecord(partial)).toThrow();
  });

  it("rejects when comment_body is missing on capture_method='live'", () => {
    const { comment_body: _o, ...partial } = validRecord;
    expect(() => validateEvidenceRecord(partial)).toThrow();
  });

  it("rejects when comment_body_sha256 is not 64 hex chars", () => {
    expect(() =>
      validateEvidenceRecord({ ...validRecord, comment_body_sha256: "tooShort" }),
    ).toThrow();
  });

  it("rejects when actor.id is missing", () => {
    expect(() =>
      validateEvidenceRecord({ ...validRecord, actor: { login: "x", type: "User" } as unknown }),
    ).toThrow();
  });

  it("rejects when capture_method is unknown", () => {
    expect(() =>
      validateEvidenceRecord({ ...validRecord, capture_method: "bogus" as unknown }),
    ).toThrow();
  });

  it("accepts capture_method='live-degraded' with comment_body_fetch_failed and null comment_body", () => {
    const degraded = {
      ...validRecord,
      capture_method: "live-degraded" as const,
      comment_body: null,
      comment_body_sha256: null,
      comment_body_fetch_failed: true,
      fetch_error: "404",
    };
    const r = validateEvidenceRecord(degraded);
    expect(r.capture_method).toBe("live-degraded");
  });
});

describe("schema_version consumer-boundary assertion (TS23 + TS24)", () => {
  it("rejects when schema_version !== '1.0'", () => {
    expect(() =>
      validateEvidenceRecord({ ...validRecord, schema_version: "2.0" }),
    ).toThrow(/schema_version/);
  });

  it("exposes SCHEMA_VERSION = '1.0' constant", () => {
    expect(SCHEMA_VERSION).toBe("1.0");
  });

  it("is the same constant the Zod schema validates against", () => {
    // Forward-compat guard: if SCHEMA_VERSION constant ever drifts from the
    // Zod literal, this test fails — preventing the silent-pass class of bugs
    // that learning #18 enumerates.
    const parsed = EvidenceRecordSchema.safeParse({ ...validRecord, schema_version: SCHEMA_VERSION });
    expect(parsed.success).toBe(true);
  });
});

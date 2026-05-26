import { z } from "zod";

/**
 * Pinned schema version. Per learning #18 (`schema_version` constants are
 * cosmetic unless the consumer asserts at parse time), three consumers assert
 * this constant on read: sidecar workflow (tombstone-append), backfill script,
 * inspect-evidence.sh. Bump only with a coordinated migration.
 */
export const SCHEMA_VERSION = "1.0" as const;

const Sha256Hex = z.string().regex(/^[0-9a-f]{64}$/, "must be 64 lowercase hex chars");

const ActorSchema = z.object({
  login: z.string().min(1),
  id: z.number().int().nonnegative(),
  type: z.enum(["User", "Bot"]),
});

const PrOfRecordSchema = z.object({
  number: z.number().int().positive(),
  repo: z.string().min(1),
});

const ClaDocSchema = z.object({
  path: z.string().min(1),
  git_sha: z.string().regex(/^[0-9a-f]{7,40}$/),
  content_sha256: Sha256Hex,
});

/**
 * Evidence record. capture_method drives which fields may be null:
 *   - "live"             : full record, comment_body + sha required
 *   - "live-degraded"    : comment-fetch 404; comment_body null + flag set
 *   - "backfilled"       : retroactive write for existing signers
 *   - "backfilled-pre-existed": doc may pre-date individual-cla.md introduction
 */
export const EvidenceRecordSchema = z
  .object({
    schema_version: z.literal(SCHEMA_VERSION),
    comment_id: z.number().int().nonnegative(),
    comment_body: z.string().nullable(),
    comment_body_sha256: Sha256Hex.nullable(),
    actor: ActorSchema,
    pr_of_record: PrOfRecordSchema,
    cla_doc: ClaDocSchema,
    signed_at: z.string().datetime({ offset: true }),
    capture_method: z.enum(["live", "live-degraded", "backfilled", "backfilled-pre-existed"]),
    workflow_run_id: z.number().int().nonnegative(),
    comment_body_fetch_failed: z.boolean().optional(),
    fetch_error: z.string().optional(),
    first_pr_signed_against: z.number().int().positive().optional(),
  })
  .refine(
    (r) => r.capture_method !== "live" || (r.comment_body !== null && r.comment_body_sha256 !== null),
    { message: "capture_method='live' requires non-null comment_body and comment_body_sha256" },
  );

export type EvidenceRecord = z.infer<typeof EvidenceRecordSchema>;

/**
 * Typed schema-mismatch error. Callers in shell context map this to exit 3
 * (paralleling the cited learning's convention). Parallels
 * `BackfillSchemaMismatchError` so both paths surface the same boundary
 * via `instanceof` rather than message-regex sniffing.
 */
export class SchemaVersionMismatchError extends Error {
  readonly exitCode = 3;
  constructor(messages: string) {
    super(`evidence record invalid (schema_version=${SCHEMA_VERSION}): ${messages}`);
    this.name = "SchemaVersionMismatchError";
  }
}

/**
 * Consumer-boundary assertion. Throws SchemaVersionMismatchError on schema
 * mismatch. The thrower's caller distinguishes via `instanceof`; the
 * exit-3 contract is honoured uniformly across backfill / sidecar / inspect.
 */
export function validateEvidenceRecord(payload: unknown): EvidenceRecord {
  const parsed = EvidenceRecordSchema.safeParse(payload);
  if (!parsed.success) {
    const messages = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new SchemaVersionMismatchError(messages);
  }
  return parsed.data;
}

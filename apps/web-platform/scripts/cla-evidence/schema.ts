import { z } from "zod";

/**
 * Pinned schema version. Per learning #18 (`schema_version` constants are
 * cosmetic unless the consumer asserts at parse time), three consumers assert
 * this constant on read: sidecar workflow (tombstone-append), backfill script,
 * inspect-evidence.sh. Bump only with a coordinated migration.
 */
export const SCHEMA_VERSION = "1.0" as const;

export const Sha256Hex = z.string().regex(/^[0-9a-f]{64}$/, "must be 64 lowercase hex chars");

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
  constructor(messages: string, subject = "evidence record") {
    super(`${subject} invalid (schema_version=${SCHEMA_VERSION}): ${messages}`);
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

// ---------------------------------------------------------------------------
// Corporate CLA coverage map (the "roster").
//
// Folded into this module rather than a sibling `roster-schema.ts`: that would
// re-declare a 64-hex regex and a parallel error class, which is duplication
// wearing a convention's clothes. `Sha256Hex` and `SchemaVersionMismatchError`
// are reused as-is.
//
// WHAT THIS FILE MAY NOT CARRY. Per the CLO ruling of 2026-09-04 (B1-c), the
// roster is tracked in a PUBLIC repository, so identity fields are removed from
// the schema permanently — not gated pending a decision. `.strict()` is what
// makes that a closed set by construction: a fifth key name like
// `signatory_email` walks straight through any four-name denylist, and cannot
// walk through this.
// ---------------------------------------------------------------------------

const RosterRepresentativeSchema = z
  .object({
    /** GitHub numeric account id. The upstream ledger keys on id, not login. */
    id: z.number().int().positive(),
    login: z.string().min(1),
    /** The legally operative date from the instrument — NOT a commit timestamp. */
    authorized_from: z.string().datetime({ offset: true }),
    /**
     * Withdrawal-of-designation marker. NOT erasure, and it must never be
     * described as one: the surface is a public git repository and the earlier
     * association survives in history and in every clone. Deliberately not
     * called a "tombstone" — that word already denotes something
     * erasure-shaped here (`tombstones/<sha>.deleted.json` on the R2 path).
     */
    removed_at: z.string().datetime({ offset: true }).nullable(),
  })
  .strict();

const RosterOrganizationSchema = z
  .object({
    /**
     * Null where the organisation's legal name IS a natural person's name — a
     * sole trader, or anyone trading under their own name (CLO amendment
     * B1-c-2). Such a counterparty is published under `record_ref` alone.
     */
    legal_name: z.string().min(1).nullable(),
    record_ref: z.string().regex(/^CCLA-[0-9]{4,}$/, "must look like CCLA-0001"),
    signed_at: z.string().datetime({ offset: true }),
    cla_doc: ClaDocSchema.strict(),
    /** SHA-256 of the executed instrument as received. The instrument is off-repo. */
    executed_instrument_sha256: Sha256Hex,
    representatives: z.array(RosterRepresentativeSchema),
    // NO FREE-TEXT FIELD, deliberately. An operator `notes` string was drafted
    // here and removed: it is unbounded text about a third party on a surface
    // that is world-readable and from which nothing can be erased, and no limb
    // of the Art. 6(1)(f) balancing test at gdpr-policy.md 3.4 covers it — that
    // test enumerates the join fields and stops. Refusing to store it beats
    // disclosing it. The roster-schema suite asserts this absence, so
    // reintroducing a free-text key reds rather than lands quietly.
  })
  .strict();

export const RosterSchema = z
  .object({
    schema_version: z.literal(SCHEMA_VERSION),
    organizations: z.array(RosterOrganizationSchema),
  })
  .strict();

export type Roster = z.infer<typeof RosterSchema>;

/**
 * Consumer-boundary assertion for the roster. Same exit-3 contract as
 * `validateEvidenceRecord`, via the same error type.
 */
export function validateRosterRecord(payload: unknown): Roster {
  const parsed = RosterSchema.safeParse(payload);
  if (!parsed.success) {
    const messages = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new SchemaVersionMismatchError(messages, "roster record");
  }
  return parsed.data;
}

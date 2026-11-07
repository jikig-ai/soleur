/**
 * PHASE 0 STUB (fail-open on purpose, replaced in Phase 2): the labeler returns no label.
 */

import type { RequesterLabelFn } from "./card-visibility";

/** A PostgREST-shaped result. */
export interface RequesterQueryResult<T> {
  data: T | null;
  error: unknown;
}

/** The slice of the service client the labeler reads through. */
export interface RequesterQueryClient {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        in(column: string, values: string[]): {
          abortSignal(signal: AbortSignal): PromiseLike<RequesterQueryResult<Array<{ user_id: string; role: string }>>>;
        };
      };
    };
  };
  auth: {
    admin: {
      getUserById(id: string): PromiseLike<RequesterQueryResult<{ user: { email?: string | null } | null }>>;
    };
  };
}

export interface RequesterLabelerOptions {
  signal?: () => AbortSignal;
}

export function createRequesterLabeler(_getClient?: () => RequesterQueryClient, _opts?: RequesterLabelerOptions): RequesterLabelFn {
  return async () => undefined;
}

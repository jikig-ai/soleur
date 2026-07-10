// Client write helpers for the Workstream board (ADR-109). POST/PATCH the
// session-gated write endpoints and throw a TYPED WorkstreamWriteClientError
// carrying the HTTP status + stable code so the board can branch on it (403 →
// read-only disable + honest hint, 429 → distinct "slow down" state) rather than
// treating every failure as a generic immediately-re-tripping retry.

import type { WorkstreamIssue, WorkstreamStatus } from "@/lib/workstream";

export interface WorkstreamWriteClientError extends Error {
  status: number;
  code: string;
}

export interface CreateIssueBody {
  title: string;
  body?: string;
  status?: WorkstreamStatus;
}

export interface PatchIssueBody {
  title?: string;
  status?: WorkstreamStatus;
  state_reason?: "completed" | "not_planned";
  reopen?: boolean;
}

async function toError(res: Response): Promise<WorkstreamWriteClientError> {
  let code = "workstream_write_error";
  try {
    const body = (await res.json()) as { error?: string };
    if (typeof body?.error === "string") code = body.error;
  } catch {
    /* non-JSON body — keep the generic code */
  }
  const err = new Error(code) as WorkstreamWriteClientError;
  err.status = res.status;
  err.code = code;
  return err;
}

export async function createIssueRequest(
  input: CreateIssueBody,
): Promise<WorkstreamIssue> {
  const res = await fetch("/api/workstream/issues", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) throw await toError(res);
  const json = (await res.json()) as { issue: WorkstreamIssue };
  return json.issue;
}

export async function patchIssueRequest(
  issueNumber: number | string,
  body: PatchIssueBody,
): Promise<WorkstreamIssue> {
  const res = await fetch(
    `/api/workstream/issues/${encodeURIComponent(String(issueNumber))}`,
    {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  if (!res.ok) throw await toError(res);
  const json = (await res.json()) as { issue: WorkstreamIssue };
  return json.issue;
}

/** True for the read-only-install 403 — the caller disables write affordances
 *  with an honest hint (no 403 retry loop). */
export function isReadOnly(err: unknown): boolean {
  return (
    (err as WorkstreamWriteClientError | null)?.status === 403 ||
    (err as WorkstreamWriteClientError | null)?.code === "forbidden_readonly"
  );
}

/** True for the 429 secondary-rate-limit — a distinct "slow down" state, not a
 *  generic retry that immediately re-trips. */
export function isRateLimited(err: unknown): boolean {
  return (
    (err as WorkstreamWriteClientError | null)?.status === 429 ||
    (err as WorkstreamWriteClientError | null)?.code === "rate_limited"
  );
}

// #8211 quiet-window — the HTTP face of the kill-switch, shared by the routes that start work on a
// host (POST /api/repo/setup clones a working tree; POST /api/repo/create creates the repo that setup
// then clones). One helper so the refusal is identical everywhere: 503, Retry-After, a stable `code`
// the connect-repo page maps to calm copy, and a static message (no ids, no internals).
//
// Place the call AFTER auth and BEFORE any write, lock flip, resolution or clone: a refusal must leave
// repo_status, the filesystem and the user's GitHub account untouched.

import { NextResponse } from "next/server";
import { QUIET_WINDOW_CODE } from "@/lib/repo-connect-codes";
import { newAgentSessionsRefused, QUIET_WINDOW_MESSAGE } from "@/server/quiet-window";
import { hashUserIdValue } from "@/server/userid-pseudonymize";
import logger from "@/server/logger";

/** A 503 response while the kill-switch is on, otherwise null (proceed). Fail-open on a throwing read. */
export async function quietWindowRefusal(
  surface: string,
  userId: string,
): Promise<NextResponse | null> {
  if (!(await newAgentSessionsRefused({ userId }))) return null;
  logger.info(
    { feature: "quiet-window", op: "refuse-http", surface, userIdHash: hashUserIdValue(userId) },
    "quiet-window: refused a request that would start work on a host (new-sessions-paused)",
  );
  return NextResponse.json(
    { error: QUIET_WINDOW_MESSAGE, code: QUIET_WINDOW_CODE },
    { status: 503, headers: { "Retry-After": "300" } },
  );
}

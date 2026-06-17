// PR-B (#4379) AC9 + AC14 — POST /api/dashboard/today/[id]/undo
//
// Reverses every element in `action_sends.reversal_handles` in order.
// Returns a per-element ledger so the operator sees exactly what was
// reverted, what was already absent (idempotent success), and what
// failed (merged-PR terminal, 401 install revoked, 4xx, 5xx).
//
// Per-kind reversal verbs (AC9):
//   pr_review_comment / pr_comment / issue_comment →
//     DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}
//     (pr_review_comment ALSO supports
//      DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id} — but the
//      issues/comments endpoint reverses both shapes per GitHub docs.)
//   issue_label →
//     DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{label_name}
//   branch →
//     DELETE /repos/{owner}/{repo}/git/refs/heads/{branch_ref}
//   pr → guard `pull.merged` first; if merged → 410 terminal; else
//        PATCH …/pulls/{n} state="closed" + DELETE branch.
//
// State semantics (AC9 + M4):
//   - undone_at = now() is set ONLY when EVERY element has status
//     "reverted" or "already_absent" (idempotent absent counts as
//     success).
//   - On partial failure, `undone_at` stays NULL, `reversal_handles` is
//     REWRITTEN with only the still-failing elements (the dashboard's
//     next Undo click retries just the still-failing subset), and
//     `artifact_url` is preserved.
//   - Returns 200 with `{ allSucceeded: true, elements: [...] }` on
//     full success; 207 with the per-element ledger on partial failure;
//     409 with "Already undone" if `reversal_handles IS NULL` at entry.
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports +
// dynamic.

import { NextResponse } from "next/server";

import { createClient } from "@/lib/supabase/server";
import { getServiceClient } from "@/lib/supabase/service";
import { createGitHubAppClient } from "@/server/github/app-client";
import { resolveInstallationId } from "@/server/resolve-installation-id";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

type ReversalKind =
  | "pr_review_comment"
  | "pr_comment"
  | "issue_label"
  | "issue_comment"
  | "branch"
  | "pr";

interface ReversalHandle {
  kind: ReversalKind;
  owner: string;
  repo: string;
  commentId?: number;
  prNumber?: number;
  issueNumber?: number;
  labelName?: string;
  branchRef?: string;
}

type ElementStatus =
  | "reverted"
  | "already_absent"
  | "failed_410_merged"
  | "failed_4xx"
  | "failed_5xx";

interface ElementLedgerEntry {
  index: number;
  kind: ReversalKind;
  status: ElementStatus;
  error?: string;
}

interface ActionSendRow {
  id: string;
  user_id: string;
  message_id: string;
  reversal_handles: ReversalHandle[] | null;
  artifact_url: string | null;
  undone_at: string | null;
}

interface OctokitLike {
  request: (
    route: string,
    params: Record<string, unknown>,
  ) => Promise<{ data: unknown }>;
}

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/undo", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;

  // Tenant-side ownership check.
  const { data: msgRow, error: msgErr } = await supabase
    .from("messages")
    .select("id")
    .eq("id", messageId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (msgErr) {
    reportSilentFallback(msgErr, {
      feature: "dashboard-undo",
      op: "messages-owner-check",
      message: "messages select failed during undo",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!msgRow) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  const service = getServiceClient();
  const { data: rawSend, error: sendErr } = await service
    .from("action_sends")
    .select("id,user_id,message_id,reversal_handles,artifact_url,undone_at")
    .eq("message_id", messageId)
    .maybeSingle();
  if (sendErr) {
    reportSilentFallback(sendErr, {
      feature: "dashboard-undo",
      op: "action-sends-read",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!rawSend) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  const send = rawSend as ActionSendRow;
  if (send.user_id !== user.id) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }
  if (!send.reversal_handles || send.reversal_handles.length === 0) {
    return NextResponse.json(
      { error: "already_undone", copy: "Already undone." },
      { status: 409 },
    );
  }

  // Resolve installation id for the GitHub App client. ADR-044 PR-2: read via the
  // membership-checked RPC keyed on the caller's active workspace (was a direct
  // `users.github_installation_id` read, which goes NULL for a newly-connected
  // user after the write relocated to `workspaces`). null = no install OR a
  // transient read error (Sentry-mirrored inside the resolver) → 403, preserving
  // the prior unauthorized contract.
  const installationId = await resolveInstallationId(user.id);
  if (!installationId) {
    return NextResponse.json(
      { error: "github_installation_unauthorized" },
      { status: 403 },
    );
  }

  const octokit = (await createGitHubAppClient(
    installationId,
    user.id,
  )) as OctokitLike;

  const ledger: ElementLedgerEntry[] = [];
  const stillFailing: ReversalHandle[] = [];

  for (let i = 0; i < send.reversal_handles.length; i++) {
    const handle = send.reversal_handles[i];
    const outcome = await reverseHandle(octokit, handle);
    ledger.push({
      index: i,
      kind: handle.kind,
      status: outcome.status,
      error: outcome.error,
    });
    if (
      outcome.status !== "reverted" &&
      outcome.status !== "already_absent"
    ) {
      stillFailing.push(handle);
    }
  }

  const allSucceeded = stillFailing.length === 0;

  // Persist: full success → undone_at + clear reversal_handles. Partial →
  // rewrite reversal_handles with only the still-failing subset.
  //
  // Both UPDATEs scope `.is("undone_at", null)` so a second concurrent
  // Undo (double-click / two-tab race) lands as 0-rows-affected if the
  // first writer already finished. The state-matrix already gives
  // undone_at precedence; this predicate keeps the row consistent if the
  // second writer's stillFailing set is shorter than the first's.
  //
  // Full success also clears failure_reason — the per-spawn failure
  // (e.g., leader_response_truncated mid-loop with partial artifact)
  // has been operator-acknowledged via the Undo flow; without the clear,
  // the state-matrix's row-1/row-2 precedence would render "Failed"
  // forever on a row that the operator successfully undid.
  if (allSucceeded) {
    const { error: updErr } = await service
      .from("action_sends")
      .update({
        undone_at: new Date().toISOString(),
        reversal_handles: null,
        failure_reason: null,
      })
      .eq("id", send.id)
      .is("undone_at", null);
    if (updErr) {
      reportSilentFallback(updErr, {
        feature: "dashboard-undo",
        op: "action-sends-undone-write",
        extra: { userId: user.id, messageId },
      });
      return NextResponse.json({ error: "internal_error" }, { status: 500 });
    }
    return NextResponse.json({ allSucceeded: true, elements: ledger });
  }

  const { error: rewriteErr } = await service
    .from("action_sends")
    .update({ reversal_handles: stillFailing })
    .eq("id", send.id)
    .is("undone_at", null);
  if (rewriteErr) {
    reportSilentFallback(rewriteErr, {
      feature: "dashboard-undo",
      op: "action-sends-partial-rewrite",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  return NextResponse.json(
    { allSucceeded: false, elements: ledger },
    { status: 207 },
  );
}

interface ReverseOutcome {
  status: ElementStatus;
  error?: string;
}

async function reverseHandle(
  octokit: OctokitLike,
  handle: ReversalHandle,
): Promise<ReverseOutcome> {
  try {
    switch (handle.kind) {
      case "pr_comment":
      case "issue_comment":
      case "pr_review_comment": {
        if (!handle.commentId) {
          return { status: "failed_4xx", error: "missing commentId" };
        }
        // pr_review_comment uses the /pulls/comments endpoint; the
        // /issues/comments endpoint won't find a code-line review.
        const route =
          handle.kind === "pr_review_comment"
            ? "DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}"
            : "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}";
        await octokit.request(route, {
          owner: handle.owner,
          repo: handle.repo,
          comment_id: handle.commentId,
        });
        return { status: "reverted" };
      }
      case "issue_label": {
        if (!handle.issueNumber || !handle.labelName) {
          return { status: "failed_4xx", error: "missing issueNumber/labelName" };
        }
        await octokit.request(
          "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}",
          {
            owner: handle.owner,
            repo: handle.repo,
            issue_number: handle.issueNumber,
            name: handle.labelName,
          },
        );
        return { status: "reverted" };
      }
      case "branch": {
        if (!handle.branchRef) {
          return { status: "failed_4xx", error: "missing branchRef" };
        }
        await octokit.request("DELETE /repos/{owner}/{repo}/git/refs/{ref}", {
          owner: handle.owner,
          repo: handle.repo,
          ref: `heads/${handle.branchRef}`,
        });
        return { status: "reverted" };
      }
      case "pr": {
        if (!handle.prNumber) {
          return { status: "failed_4xx", error: "missing prNumber" };
        }
        // Guard merged PRs (AC9) — once merged on GitHub there is no
        // automatic undo path; surface as 410 terminal.
        const { data } = (await octokit.request(
          "GET /repos/{owner}/{repo}/pulls/{pull_number}",
          {
            owner: handle.owner,
            repo: handle.repo,
            pull_number: handle.prNumber,
          },
        )) as { data: { merged?: boolean } };
        if (data?.merged === true) {
          return {
            status: "failed_410_merged",
            error: "PR was already merged; cannot undo automatically",
          };
        }
        await octokit.request(
          "PATCH /repos/{owner}/{repo}/pulls/{pull_number}",
          {
            owner: handle.owner,
            repo: handle.repo,
            pull_number: handle.prNumber,
            state: "closed",
          },
        );
        if (handle.branchRef) {
          try {
            await octokit.request(
              "DELETE /repos/{owner}/{repo}/git/refs/{ref}",
              {
                owner: handle.owner,
                repo: handle.repo,
                ref: `heads/${handle.branchRef}`,
              },
            );
          } catch {
            // The PR is closed; the branch may already be gone or
            // protected. Reaching here is non-fatal for the PR undo —
            // operator can clean up manually.
          }
        }
        return { status: "reverted" };
      }
    }
  } catch (err) {
    const status = (err as { status?: number } | null)?.status;
    const message = err instanceof Error ? err.message : String(err);
    if (status === 404) {
      // Already deleted on GitHub side — idempotent absent.
      return { status: "already_absent" };
    }
    if (status && status >= 400 && status < 500) {
      return { status: "failed_4xx", error: message };
    }
    return { status: "failed_5xx", error: message };
  }
}

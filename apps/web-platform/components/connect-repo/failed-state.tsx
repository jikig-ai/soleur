"use client";

import { XCircleIcon } from "@/components/icons";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import {
  REPO_CONNECT_BLOCKED_CODE,
  WORKSPACE_SWITCH_REQUIRED_CODE,
} from "@/lib/repo-connect-codes";
import type { GitErrorCode } from "@/server/git-auth";

interface FailedStateProps {
  onRetry: () => void;
  errorMessage?: string | null;
  errorCode?: GitErrorCode | string | null;
  // feat-repo-connect-block-offer-join: present ONLY for the switch state
  // (workspace_switch_required) and ONLY ever the caller's OWN solo id. The
  // decline state never receives it (no cross-user disclosure).
  existingWorkspaceId?: string | null;
}

type ErrorCopy = {
  headline: string;
  body: string;
  steps: string[];
  primaryCta: {
    label: string;
    action: "retry" | "reinstall" | "choose" | "switch";
  };
};

// feat-repo-connect-block-offer-join — connect-time block error codes returned
// by POST /api/repo/setup (NOT GitErrorCode clone failures). The page maps the
// 409 `code` into errorCode so these copy entries render. The literals are the
// single-source-of-truth in @/lib/repo-connect-codes (shared with the guard
// producer); re-exported here for existing ERROR_COPY-key consumers.
export { REPO_CONNECT_BLOCKED_CODE, WORKSPACE_SWITCH_REQUIRED_CODE };

// Sentinel for create-flow failures (string-keyed, not in GitErrorCode enum).
// Surfaces the "connect an existing repo instead" escape hatch when repo
// creation fails for an operator-side reason (template missing, App lost
// admin:write, etc.) — without it, the user sees a generic toast and bounces.
export const CREATE_FAILED_ERROR_CODE = "CREATE_FAILED" as const;

// Partial because CLONE_UNKNOWN intentionally falls through to the
// generic copy (same shape as legacy plain-stderr rows).
const ERROR_COPY: Record<string, ErrorCopy> = {
  // STATE 1 — switch: the caller's OWN (ready) workspace already owns this repo,
  // reached while connecting from a different active workspace.
  [WORKSPACE_SWITCH_REQUIRED_CODE]: {
    headline: "You already have a workspace for this project",
    body: "This repository is already connected to one of your workspaces. Switch to it to keep working — there's no need to connect it again.",
    steps: [
      "Click Switch to that workspace to jump straight to it.",
      "Or pick a different repository to connect here.",
    ],
    primaryCta: { label: "Switch to that workspace", action: "switch" },
  },
  // STATE 2 — generic, non-disclosing decline. MUST NOT reveal that another
  // workspace/user owns the repo (info-disclosure): no "taken", no "already
  // connected by someone", no workspace/user reference. The forward CTA is true
  // for everyone (collaborator-gate is the deferred path).
  [REPO_CONNECT_BLOCKED_CODE]: {
    headline: "This repository can't be connected",
    body: "We can't connect this repository to your workspace right now.",
    steps: [
      "If you should have access, ask the repository's workspace owner to invite you.",
      "Or pick a different repository to connect.",
    ],
    primaryCta: { label: "Pick a different repository", action: "choose" },
  },
  [CREATE_FAILED_ERROR_CODE]: {
    headline: "Couldn't create your project",
    body: "GitHub couldn't create the new repository. This is usually a temporary issue on our side — you can try again, or connect an existing repo from your GitHub account instead.",
    steps: [
      "Click Try Again — most issues resolve on a second attempt.",
      "Or connect an existing repository from your GitHub account.",
      "If neither works, contact support with the time of the error.",
    ],
    primaryCta: { label: "Connect existing repo instead", action: "choose" },
  },
  REPO_ACCESS_REVOKED: {
    headline: "Soleur no longer has access",
    body: "The Soleur GitHub App no longer has access to this repository. Reinstall the app and try again.",
    steps: [
      "Reinstall the Soleur GitHub App on the repository's owner.",
      "Make sure the app has access to this repository.",
      "Return here and click Try Again.",
    ],
    primaryCta: { label: "Reinstall GitHub App", action: "reinstall" },
  },
  REPO_NOT_FOUND: {
    headline: "Repository not found",
    body: "We could not find this repository. It may have been deleted, renamed, or made private without granting Soleur access.",
    steps: [
      "Choose a different repository to connect.",
      "If this repo still exists, make sure the Soleur GitHub App has access to it.",
    ],
    primaryCta: { label: "Choose a different repository", action: "choose" },
  },
  AUTH_FAILED: {
    headline: "Authentication failed",
    body: "We could not authenticate with GitHub for this repository. Reinstalling the Soleur GitHub App usually resolves this.",
    steps: [
      "Reinstall the Soleur GitHub App.",
      "Return here and click Try Again.",
    ],
    primaryCta: { label: "Reinstall GitHub App", action: "reinstall" },
  },
  CLONE_TIMEOUT: {
    headline: "Repository clone timed out",
    body: "The clone took longer than expected. Large repositories sometimes need a second attempt.",
    steps: [
      "Click Try Again — transient timeouts usually resolve on retry.",
      "If it persists, contact support with the time of the error.",
    ],
    primaryCta: { label: "Try Again", action: "retry" },
  },
  CLONE_NETWORK_ERROR: {
    headline: "Network error during clone",
    body: "We could not reach GitHub to fetch your repository. This is usually a transient issue.",
    steps: [
      "Check GitHub's status page for ongoing incidents.",
      "Click Try Again.",
    ],
    primaryCta: { label: "Try Again", action: "retry" },
  },
};

export function FailedState({
  onRetry,
  errorMessage,
  errorCode,
  existingWorkspaceId,
}: FailedStateProps) {
  const copy =
    errorCode && errorCode in ERROR_COPY ? ERROR_COPY[errorCode] : undefined;

  // Switch into the caller's OWN existing workspace for this repo. Mirrors the
  // canonical two-phase commit in org-switcher-container.tsx (#4917): the RPC
  // (set_current_workspace_id) is WRITE 1, then refreshSession re-mints the
  // current_workspace_id JWT claim (ADR-044 Decision.3), then a HARD navigation
  // to /dashboard converges server components onto the durable truth. Redirecting
  // WITHOUT the refresh would land on the stale prior-claim workspace.
  const handleSwitch = async () => {
    if (!existingWorkspaceId) {
      onRetry();
      return;
    }
    const supabase = createClient();
    const { error } = await supabase.rpc("set_current_workspace_id", {
      p_workspace_id: existingWorkspaceId,
    });
    if (error) {
      // Membership revoked / workspace deleted between the connect read and this
      // click — nothing committed. Fall back to the generic decline + refresh
      // (GAP-3): onRetry returns the user to repo choice. Transient/expected —
      // console-only, mirrors org-switcher's failed_pre_rpc path.
      console.error(
        "[repo-connect-switch] set_current_workspace_id failed:",
        error,
      );
      onRetry();
      return;
    }
    try {
      await supabase.auth.refreshSession();
    } catch (err) {
      // The durable pointer is already committed; converge forward — the server
      // re-reads user_session_state on the hard navigation regardless. But the
      // post-commit refresh failing is the same brand-critical DB/JWT divergence
      // org-switcher-container.tsx mirrors (op:refresh-session-post-rpc) so an
      // aggregate pattern stays visible (cq-silent-fallback-must-mirror-to-sentry).
      reportSilentFallback(err, {
        feature: "repo-connect-switch",
        op: "refresh-session-post-rpc",
        message:
          "refreshSession failed after set_current_workspace_id committed — converging forward via hard nav",
      });
    }
    window.location.assign("/dashboard");
  };

  const handlePrimary = () => {
    if (!copy || copy.primaryCta.action === "retry") {
      onRetry();
      return;
    }
    if (copy.primaryCta.action === "reinstall") {
      window.location.href = "/api/repo/install";
      return;
    }
    if (copy.primaryCta.action === "switch") {
      void handleSwitch();
      return;
    }
    // "choose" — the parent page owns repo selection; onRetry takes the
    // user back to the choose step.
    onRetry();
  };

  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-red-500/10">
        <XCircleIcon className="h-8 w-8 text-red-400" />
      </div>

      <div className="space-y-3">
        <h1 className="text-4xl font-semibold">
          {copy?.headline ?? "Project Setup Failed"}
        </h1>
        <p className="text-base text-soleur-text-secondary">
          {copy?.body ??
            "Something went wrong while setting up your project. This is usually a temporary issue."}
        </p>
      </div>

      {errorMessage && (
        <Card className="text-left">
          <details>
            <summary className="cursor-pointer text-sm font-medium text-soleur-text-primary">
              Error details (for support)
            </summary>
            <p className="mt-2 text-sm text-soleur-text-secondary font-mono break-all">
              {errorMessage}
            </p>
          </details>
        </Card>
      )}

      <Card className="text-left">
        <h3 className="mb-3 text-sm font-medium text-soleur-text-primary">What you can do</h3>
        <ol className="space-y-3">
          {(copy?.steps ?? [
            "Try again — most issues resolve on a second attempt.",
            "Check GitHub's status page for ongoing incidents.",
            "If the problem persists, contact support with the time of the error.",
          ]).map((step, i) => (
            <li key={i} className="flex items-start gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-soleur-border-default text-xs font-medium text-soleur-text-secondary">
                {i + 1}
              </span>
              <span className="text-sm text-soleur-text-secondary">{step}</span>
            </li>
          ))}
        </ol>
      </Card>

      <div className="flex items-center justify-center gap-3">
        <GoldButton onClick={handlePrimary}>
          {copy?.primaryCta.label ?? "Try Again"}
        </GoldButton>
        <OutlinedButton
          onClick={() => window.open("https://www.githubstatus.com", "_blank")}
        >
          GitHub Status Page
        </OutlinedButton>
      </div>
    </div>
  );
}

"use client";

// Phase 8 UI: list of the user's DSAR export jobs.
//
// Plan rev-2 FR6 + AC4 + AC24 + AC31.
//
// - Renders status + ETA inline; disables the "Download my data"
//   button when an active job exists (AC31).
// - `expired` rows show a "re-request" CTA per AC24.
// - Reissue is a POST to /api/account/export/[jobId] per S9 inline
//   (no separate route file).
//
// The reauth flow is delegated to /dashboard/settings/privacy/reauth
// (Phase 7): the parent dialog collects a password (or triggers OAuth
// redirect), this component receives an `eventId` and uses it to POST
// /api/account/export.

import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { DsarExportDialog } from "./dsar-export-dialog";

// `jobs` is the snapshot at server-render time. We don't keep client-
// side mutable state for it — router.refresh() re-renders the server
// component when an active job's status changes.

export type JobStatus =
  | "pending"
  | "running"
  | "completed"
  | "delivered"
  | "expired"
  | "failed";

export interface DsarExportJobRow {
  id: string;
  status: JobStatus;
  requested_at: string;
  signed_url_expires_at: string | null;
  failure_reason: string | null;
  bundle_size_bytes: number | null;
}

interface DsarExportJobListProps {
  initialJobs: DsarExportJobRow[];
}

function isActive(status: JobStatus): boolean {
  return status === "pending" || status === "running" || status === "completed";
}

function statusLabel(status: JobStatus): string {
  switch (status) {
    case "pending":
      return "Queued";
    case "running":
      return "Preparing your bundle…";
    case "completed":
      return "Ready to download";
    case "delivered":
      return "Downloaded";
    case "expired":
      return "Expired";
    case "failed":
      return "Failed";
  }
}

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString();
}

function formatBytes(bytes: number | null): string {
  if (bytes === null) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

export function DsarExportJobList({ initialJobs }: DsarExportJobListProps) {
  const router = useRouter();
  const jobs = initialJobs;
  const [error, setError] = useState<string | null>(null);
  const hasActiveJob = jobs.some((j) => isActive(j.status));

  // Poll every 10s while an active job is running. Once all jobs are
  // terminal, polling stops. AC31's "disable button + show status
  // inline" requires keeping the list fresh. The refresh re-fetches
  // the server component (RLS-scoped) — no separate /list endpoint
  // required (code-simplicity-reviewer P1 on PR #3634: the prior
  // fetch hit /api/account/export?list=1 which returns 405 because
  // no GET handler exists at that path).
  useEffect(() => {
    if (!hasActiveJob) return;
    const handle = setInterval(() => {
      router.refresh();
    }, 10_000);
    return () => clearInterval(handle);
  }, [hasActiveJob, router]);

  // The parent owns isOpen so the "Re-request" CTA on an `expired`
  // row can open the same dialog programmatically (AC24 fix per
  // user-impact-reviewer P1 on PR #3634: previously the Re-request
  // button POST'd to /api/account/export/[jobId] which returns 409
  // for status != 'completed' — every expired-row re-request errored).
  const [dialogOpen, setDialogOpen] = useState(false);

  const handlePasswordConfirm = useCallback(
    async (password: string) => {
      // Step 1: re-auth via the password endpoint.
      const reauthRes = await fetch(
        "/dashboard/settings/privacy/reauth",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ mode: "password", password }),
        },
      );
      if (!reauthRes.ok) {
        const body = await reauthRes.json().catch(() => ({}));
        throw new Error(body.error ?? "Re-authentication failed");
      }
      const { event_id } = (await reauthRes.json()) as { event_id: string };

      // Step 2: enqueue.
      const enqueueRes = await fetch("/api/account/export", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-reauth-event": event_id,
        },
        body: JSON.stringify({}),
      });
      if (!enqueueRes.ok) {
        const body = await enqueueRes.json().catch(() => ({}));
        throw new Error(body.error ?? "Failed to start the export");
      }
      router.refresh();
    },
    [router],
  );

  // Note: OAuth re-auth path is not wired client-side in v1. The
  // server route accepts mode=oauth_completed but the redirect +
  // return-handler is a deferred follow-up. Until then, the dialog
  // exposes only the password field and we don't render an SSO CTA —
  // OAuth-only users use the email channel via legal@jikigai.com
  // (documented in privacy-policy §8.1).

  return (
    <div className="space-y-6">
      <DsarExportDialog
        isOpen={dialogOpen}
        onOpen={() => setDialogOpen(true)}
        onClose={() => setDialogOpen(false)}
        onConfirmPassword={handlePasswordConfirm}
        hasActiveJob={hasActiveJob}
      />

      {error && (
        <p
          role="alert"
          className="rounded-md border border-red-800/50 bg-red-950/30 px-3 py-2 text-sm text-red-300"
        >
          {error}
        </p>
      )}

      <section>
        <h3 className="mb-3 text-sm font-semibold text-soleur-text-primary">
          Your export history
        </h3>

        {jobs.length === 0 ? (
          <p className="text-sm text-soleur-text-secondary">
            You haven&apos;t requested any data exports yet.
          </p>
        ) : (
          <ul className="space-y-3">
            {jobs.map((job) => (
              <li
                key={job.id}
                className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/50 p-4"
              >
                <div className="flex flex-wrap items-baseline justify-between gap-3">
                  <div>
                    <p
                      data-testid={`job-status-${job.id}`}
                      className="text-sm font-medium text-soleur-text-primary"
                    >
                      {statusLabel(job.status)}
                    </p>
                    <p className="text-xs text-soleur-text-secondary">
                      Requested {formatDate(job.requested_at)}
                      {job.bundle_size_bytes !== null && (
                        <> · {formatBytes(job.bundle_size_bytes)}</>
                      )}
                    </p>
                    {job.status === "failed" && job.failure_reason && (
                      <p className="mt-1 text-xs text-red-400">
                        Reason: {job.failure_reason}
                      </p>
                    )}
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    {job.status === "completed" && (
                      <a
                        href={`/api/account/export/${job.id}/download`}
                        className="rounded-lg bg-soleur-button-primary px-3 py-1.5 text-sm font-medium text-soleur-text-primary"
                      >
                        Download
                      </a>
                    )}
                    {job.status === "expired" && (
                      <button
                        type="button"
                        onClick={() => setDialogOpen(true)}
                        disabled={hasActiveJob}
                        className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-1.5 text-sm text-soleur-text-secondary hover:bg-soleur-bg-surface-2 disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        Re-request
                      </button>
                    )}
                    {(job.status === "completed" ||
                      job.status === "delivered") &&
                      job.signed_url_expires_at && (
                        <span className="text-xs text-soleur-text-muted">
                          Expires {formatDate(job.signed_url_expires_at)}
                        </span>
                      )}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

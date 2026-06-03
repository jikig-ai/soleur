// Phase 8 — Settings / Privacy.
//
// Plan rev-2 FR1 + FR6 + AC4 + AC8 + AC24 + AC31.
//
// Server component: fetches the user's DSAR jobs via RLS-scoped read
// (policy dsar_export_jobs_owner_select restricts to auth.uid() =
// user_id, so this is owner-only by construction). Renders the
// confirmation dialog + job list.

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  DsarExportJobList,
  type DsarExportJobRow,
  type JobStatus,
} from "@/components/settings/dsar-export-job-list";
import { BashAutonomousToggle } from "@/components/settings/bash-autonomous-toggle";
import { resolveBashAutonomous } from "@/server/resolve-bash-autonomous";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

export const dynamic = "force-dynamic";

export default async function PrivacyPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: jobsData } = await supabase
    .from("dsar_export_jobs")
    .select(
      "id, status, requested_at, signed_url_expires_at, failure_reason, bundle_size_bytes",
    )
    .eq("user_id", user.id)
    .order("requested_at", { ascending: false })
    .limit(20);

  // Issue B part 2 — Concierge autonomous-mode toggle (owner-only). Read the
  // current value (member-checked, fail-closed false) and resolve owner status
  // of the active workspace so non-owners don't see a control they can't use.
  const autonomous = await resolveBashAutonomous(user.id);
  const activeWorkspaceId = await resolveCurrentWorkspaceId(user.id, supabase);
  // Cookie (RLS-scoped) client — workspace_members has a members_select_peers
  // policy, so the caller can read its own membership row without the
  // RLS-bypassing service-role client (review PR #4868). Scoped to user.id.
  const { data: membership } = await supabase
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", activeWorkspaceId)
    .eq("user_id", user.id)
    .maybeSingle();
  const isWorkspaceOwner = membership?.role === "owner";

  const jobs: DsarExportJobRow[] = (jobsData ?? []).map((row) => ({
    id: row.id as string,
    status: row.status as JobStatus,
    requested_at: row.requested_at as string,
    signed_url_expires_at: (row.signed_url_expires_at as string | null) ?? null,
    failure_reason: (row.failure_reason as string | null) ?? null,
    bundle_size_bytes: (row.bundle_size_bytes as number | null) ?? null,
  }));

  return (
    <div className="mx-auto max-w-3xl space-y-10 px-6 py-10">
      <header>
        <h1 className="text-2xl font-semibold text-soleur-text-primary">
          Privacy
        </h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Manage data we hold about you under GDPR Articles 15 (right of
          access), 17 (right to erasure), and 20 (data portability). You can
          also email{" "}
          <a
            href="mailto:legal@jikigai.com"
            className="underline hover:text-soleur-text-primary"
          >
            legal@jikigai.com
          </a>{" "}
          to make a request manually — both paths fulfil the same right.
        </p>
      </header>

      <section>
        <h2 className="mb-3 text-lg font-semibold text-soleur-text-primary">
          Download my data
        </h2>
        <p className="mb-4 text-sm text-soleur-text-secondary">
          Request a copy of your data as a ZIP archive. The bundle is
          delivered via a one-time download link, valid for 7 days, bound to
          your current session and network.
        </p>
        <DsarExportJobList initialJobs={jobs} />
      </section>

      {isWorkspaceOwner && (
        <section>
          <h2 className="mb-3 text-lg font-semibold text-soleur-text-primary">
            Concierge command approval
          </h2>
          <p className="mb-4 text-sm text-soleur-text-secondary">
            By default the Concierge asks you to approve each command it runs.
            Autonomous mode lets it run non-blocked commands without asking.
          </p>
          <BashAutonomousToggle
            initialAutonomous={autonomous}
            isOwner={isWorkspaceOwner}
          />
        </section>
      )}
    </div>
  );
}

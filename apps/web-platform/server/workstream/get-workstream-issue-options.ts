// Picker options for the Workstream edit-fields drawer (labels / assignees /
// milestones of the active workspace's connected repo). Reads through the SAME
// server-side workspace resolution the write accessor uses (resolveContext →
// ADR-044) — owner/repo/installation NEVER come from request input.
//
// DEGRADE-SAFE (load-bearing): a failure here must NEVER throw the whole board.
// Any error (no repo, lost grant, GitHub 5xx) collapses to empty arrays +
// reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry), so an editor
// opens with empty menus rather than a broken drawer. The labels list is
// filtered to NON-status labels only — the labels editor never owns the column.

import { STATUS_LABELS } from "@/lib/workstream";
import { resolveContext } from "@/server/workstream/mutate-workstream-issue";
import { reportSilentFallback } from "@/server/observability";

export interface WorkstreamIssueOptions {
  /** Non-status repo labels the labels editor can apply. */
  labels: Array<{ name: string; color: string }>;
  /** Assignable logins for the assignees editor. */
  assignees: Array<{ login: string }>;
  /** Open + closed milestones for the milestone selector. */
  milestones: Array<{ number: number; title: string }>;
}

const EMPTY: WorkstreamIssueOptions = {
  labels: [],
  assignees: [],
  milestones: [],
};

/** Walk all pages of a paginated list call (per_page:100) up to a defensive cap.
 *  A repo's label/assignee/milestone counts are naturally far below the cap, so
 *  this fetches the FULL set — a single per_page:100 page would hide out-of-page
 *  labels from the picker (review F1). */
async function fetchAllPages<T>(
  fetchPage: (page: number) => Promise<{ data: T[] }>,
): Promise<T[]> {
  const out: T[] = [];
  for (let page = 1; page <= 20; page++) {
    const { data } = await fetchPage(page);
    out.push(...data);
    if (data.length < 100) break;
  }
  return out;
}

export async function getWorkstreamIssueOptions(
  userId: string,
): Promise<WorkstreamIssueOptions> {
  try {
    const { owner, repo, octokit } = await resolveContext(userId);
    const [labelsData, assigneesData, milestonesData] = await Promise.all([
      fetchAllPages((page) =>
        octokit.rest.issues.listLabelsForRepo({
          owner,
          repo,
          per_page: 100,
          page,
        }),
      ),
      fetchAllPages((page) =>
        octokit.rest.issues.listAssignees({ owner, repo, per_page: 100, page }),
      ),
      fetchAllPages((page) =>
        octokit.rest.issues.listMilestones({
          owner,
          repo,
          state: "all",
          per_page: 100,
          page,
        }),
      ),
    ]);
    const statusSet = new Set<string>(STATUS_LABELS);
    const labels = labelsData
      .filter((l) => !statusSet.has(l.name))
      .map((l) => ({ name: l.name, color: l.color ?? "" }));
    const assignees = assigneesData.map((a) => ({ login: a.login }));
    const milestones = milestonesData.map((m) => ({
      number: m.number,
      title: m.title,
    }));
    return { labels, assignees, milestones };
  } catch (err) {
    reportSilentFallback(err, {
      feature: "workstream",
      op: "issue-options-degrade",
      extra: { userId },
    });
    return EMPTY;
  }
}

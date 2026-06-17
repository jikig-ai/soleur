import { reportSilentFallback } from "@/server/observability";

// ADR-044 Amendment 2026-06-17b — non-push webhook founder attribution.
//
// Resolves the SINGLE solo-workspace founder that owns a GitHub-App
// installation, replacing the former
// `service.from("users").select("id").eq("github_installation_id", …)`
// reverse-lookup in the webhook route. That `users` read was load-bearing on
// the mig-052 partial-UNIQUE; PR-2b drops that column AND its index, so the
// reverse-lookup against the NON-UNIQUE `workspaces.github_installation_id`
// is structurally invalid (one install → N workspaces: solo + team; two users
// + same fork). A `.maybeSingle()` would silently route a 1:N install to one
// founder — the exact cross-tenant misattribution hazard the UNIQUE prevented.
//
// Resolution rule (CTO binding ruling, Option C): a SOLO workspace is one whose
// membership self-row satisfies `m.user_id = w.id` (the solo invariant:
// `workspaces.id == owner users.id`, ADR-038 N2). A team workspace's id is a
// fresh uuid, never == a member's user_id, so the self-join deliberately
// excludes team workspaces sharing the install. `founderId := w.id` is value-
// compatible with the old `users` read (== owner `users.id`), so `isGranted`
// and the installation-token path need no other change.
//
// Match-count is fail-closed: 0 → none, 1 → found, >1 → ambiguous (do NOT pick
// one — the caller drops the event + pages), db-error → db-error. The `>1` case
// is genuinely reachable now that the column is NON-UNIQUE; it is the load-
// bearing new defense and MUST be distinguishable from `0`.
//
// Injected service-role client (NO `.service-role-allowlist` entry — mirrors
// `resolve-installation-id-for-workspace.ts`): the credential read is keyed on
// a SERVER-DERIVED installation id (from the signature-verified webhook body),
// never request-supplied, and supabase-js has no membership self-join sugar so
// the join is expressed via the `workspace_members!inner` embed.

interface ServiceClient {
  from: (table: string) => unknown;
}

// supabase-js inner-join embed shape. The `!inner` filter on
// `workspace_members` makes the embed a JOIN (rows without a matching member
// are dropped), and the `.eq` filters on the embedded columns express the
// solo self-join predicate (`m.user_id = w.id AND m.role = 'owner'`).
type FounderJoinChain = {
  select: (cols: string) => FounderJoinChain;
  eq: (col: string, val: string | number) => FounderJoinChain;
  then: <T>(
    onfulfilled: (value: {
      data: Array<{ id: string }> | null;
      error: unknown;
    }) => T,
  ) => Promise<T>;
};

export type SoloFounderResolution =
  | { kind: "found"; founderId: string }
  | { kind: "none" }
  | { kind: "ambiguous"; count: number }
  | { kind: "db-error" };

/**
 * Resolve the single solo-workspace founder for a GitHub-App installation via
 * the membership self-join (CTO ruling). Returns a discriminated union so the
 * webhook route can branch 0/1/>1/error distinctly — the `>1` (ambiguous) case
 * is fail-closed, never collapsed into `none`.
 */
export async function resolveSoloFounderForInstallation(
  installationId: number,
  service: ServiceClient,
): Promise<SoloFounderResolution> {
  const chain = service.from("workspaces") as FounderJoinChain;
  // Solo self-join: workspaces w JOIN workspace_members m
  //   ON m.workspace_id = w.id AND m.user_id = w.id AND m.role = 'owner'
  //   WHERE w.github_installation_id = :installationId
  // Expressed in supabase-js: the `!inner` embed JOINs workspace_members and
  // drops workspaces with no matching owner self-row; `m.workspace_id = w.id`
  // is the embed's implicit FK join, and `workspace_members.user_id = w.id`
  // (the solo invariant) is filtered by `.eq("id", …)`-equivalence below.
  const { data, error } = await chain
    .select("id, workspace_members!inner(user_id, role)")
    .eq("github_installation_id", installationId)
    .eq("workspace_members.role", "owner");

  if (error) {
    reportSilentFallback(error, {
      feature: "github-webhook",
      op: "founder-resolve",
      extra: { installationId },
      message:
        "Solo-founder resolution failed — workspaces self-join read error",
    });
    return { kind: "db-error" };
  }

  // The embed cannot express the cross-column predicate
  // `workspace_members.user_id = workspaces.id` server-side, so apply the solo
  // invariant in TS: keep only rows whose owner member-row is the self-row
  // (`m.user_id == w.id`). Team workspaces (fresh uuid id != member user_id)
  // are dropped here even though they share the install.
  const soloRows = (data ?? []).filter((row) => {
    const members = (row as unknown as {
      workspace_members?: Array<{ user_id?: string; role?: string }>;
    }).workspace_members;
    return (members ?? []).some(
      (m) => m.role === "owner" && m.user_id === row.id,
    );
  });

  if (soloRows.length === 0) return { kind: "none" };
  if (soloRows.length > 1) return { kind: "ambiguous", count: soloRows.length };
  return { kind: "found", founderId: soloRows[0].id };
}

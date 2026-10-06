// #7122 — shared test support: apply the request parameters GitHub's
// `GET /repos/{owner}/{repo}/issues` honours, so a fake issue store answers the
// QUESTION ASKED instead of returning its whole content for any call.
//
// The handler-level and publication suites model GitHub with in-memory stores. A
// store that ignores `per_page`, `direction`, `state` and `labels` cannot see a
// regression in any of them (the upsert changing to `direction: "asc"` or a tiny
// `per_page` would stop finding today's digest once enough older digests exist and
// would silently file a duplicate every run, the #5751 class). Every fake that
// answers this route goes through `applyIssueListParams`.
//
// Semantics mirrored from GitHub: `state` defaults to `open` (`all` matches both);
// `labels` is a comma-separated AND filter; `sort` is `created` (only mode the
// handler uses, anything else throws so a new mode cannot be silently ignored);
// `direction` defaults to `desc`; `per_page` defaults to 30 and caps at 100; only
// page 1 is returned (the handler never paginates).

export type ListableIssue = {
  number?: number;
  state?: string;
  /** Label names. A row without the field is treated as carrying `defaultLabel`. */
  labels?: string[];
  /** ISO instant. Rows without one are ordered by `number` (higher = newer). */
  created_at?: string;
};

export function applyIssueListParams<T extends ListableIssue>(
  rows: readonly T[],
  params: Record<string, unknown>,
  defaultLabel = "scheduled-community-monitor",
): T[] {
  const sort = params.sort ?? "created";
  if (sort !== "created") throw new Error(`fake issue list: unsupported sort ${String(sort)}`);

  const state = String(params.state ?? "open");
  const wanted =
    typeof params.labels === "string" && params.labels !== ""
      ? params.labels.split(",").map((l) => l.trim())
      : [];
  const key = (r: T): number => {
    const t = r.created_at ? Date.parse(r.created_at) : Number.NaN;
    return Number.isNaN(t) ? (r.number ?? 0) : t;
  };

  const direction = params.direction === "asc" ? "asc" : "desc";
  const perPage = Math.min(100, Math.max(1, Number(params.per_page ?? 30)));

  return rows
    .filter((r) => state === "all" || (r.state ?? "open") === state)
    .filter((r) => {
      const have = r.labels ?? [defaultLabel];
      return wanted.every((w) => have.includes(w));
    })
    .sort((a, b) => (direction === "asc" ? key(a) - key(b) : key(b) - key(a)))
    .slice(0, perPage);
}

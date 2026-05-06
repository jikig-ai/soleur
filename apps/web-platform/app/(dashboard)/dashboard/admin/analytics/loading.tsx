export default function AnalyticsLoading() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-soleur-text-primary">Analytics</h1>
      <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 overflow-hidden">
        <table className="w-full">
          <thead>
            <tr className="border-b border-soleur-border-default">
              {["User", "Domains", "Sessions", "Multi-Domain", "KB Growth", "TTFV", "Error Rate", "Status"].map(
                (header) => (
                  <th
                    key={header}
                    className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider"
                  >
                    {header}
                  </th>
                ),
              )}
            </tr>
          </thead>
          <tbody>
            {Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="border-b border-soleur-border-default/50">
                {Array.from({ length: 8 }).map((_, j) => (
                  <td key={j} className="px-4 py-3">
                    <div className="h-4 rounded bg-soleur-bg-surface-2 animate-pulse" />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default function AnalyticsLoading() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-white">Analytics</h1>
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 overflow-hidden">
        <table className="w-full">
          <thead>
            <tr className="border-b border-neutral-800">
              {["User", "Domains", "Sessions", "Multi-Domain", "KB Growth", "TTFV", "Error Rate", "Status"].map(
                (header) => (
                  <th
                    key={header}
                    className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider"
                  >
                    {header}
                  </th>
                ),
              )}
            </tr>
          </thead>
          <tbody>
            {Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="border-b border-neutral-800/50">
                {Array.from({ length: 8 }).map((_, j) => (
                  <td key={j} className="px-4 py-3">
                    <div className="h-4 rounded bg-neutral-800 animate-pulse" />
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

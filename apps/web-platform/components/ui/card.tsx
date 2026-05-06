export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6 ${className ?? ""}`}>
      {children}
    </div>
  );
}

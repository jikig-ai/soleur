export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border border-neutral-800 bg-neutral-900/50 p-6 ${className ?? ""}`}>
      {children}
    </div>
  );
}

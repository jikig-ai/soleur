export function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-xs font-medium uppercase tracking-widest text-amber-500/70">
      {children}
    </span>
  );
}

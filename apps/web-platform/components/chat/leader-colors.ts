import type { DomainLeaderId } from "@/server/domain-leaders";

/** Tailwind border-left color classes for each domain leader. */
export const LEADER_COLORS: Record<DomainLeaderId, string> = {
  cmo: "border-l-pink-500",
  cto: "border-l-blue-500",
  cfo: "border-l-emerald-500",
  cpo: "border-l-violet-500",
  cro: "border-l-orange-500",
  coo: "border-l-amber-500",
  clo: "border-l-slate-400",
  cco: "border-l-cyan-500",
  system: "border-l-neutral-600",
};

/** Tailwind background color classes for leader avatar badges. */
export const LEADER_BG_COLORS: Record<DomainLeaderId, string> = {
  cmo: "bg-pink-500",
  cto: "bg-blue-500",
  cfo: "bg-emerald-500",
  cpo: "bg-violet-500",
  cro: "bg-orange-500",
  coo: "bg-amber-500",
  clo: "bg-slate-400",
  cco: "bg-cyan-500",
  system: "bg-neutral-600",
};

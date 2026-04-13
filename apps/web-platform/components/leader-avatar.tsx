import { memo, useState, useEffect } from "react";
import {
  Megaphone,
  Cog,
  TrendingUp,
  Boxes,
  Target,
  Wrench,
  Scale,
  Headphones,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";

const ICON_MAP: Record<string, LucideIcon> = {
  Megaphone,
  Cog,
  TrendingUp,
  Boxes,
  Target,
  Wrench,
  Scale,
  Headphones,
};

const SIZE_CLASSES = {
  sm: { container: "h-5 w-5", icon: 12 },
  md: { container: "h-7 w-7", icon: 16 },
  lg: { container: "h-8 w-8", icon: 18 },
} as const;

interface LeaderAvatarProps {
  leaderId: DomainLeaderId | null | undefined;
  size: "sm" | "md" | "lg";
  className?: string;
  /** Optional custom icon KB path. When provided, renders as an img instead of lucide icon. */
  customIconPath?: string | null;
}

export const LeaderAvatar = memo(function LeaderAvatar({
  leaderId,
  size,
  className,
  customIconPath,
}: LeaderAvatarProps) {
  const [imgError, setImgError] = useState(false);

  // Reset error state when the icon path changes (new upload or reset)
  useEffect(() => {
    setImgError(false);
  }, [customIconPath]);

  const leader = leaderId
    ? DOMAIN_LEADERS.find((l) => l.id === leaderId)
    : null;
  const sizeConfig = SIZE_CLASSES[size];
  const isSystem = !leaderId || leaderId === "system" || !leader;

  if (isSystem) {
    return (
      <span
        className={`flex ${sizeConfig.container} shrink-0 items-center justify-center overflow-hidden rounded-md ${className ?? ""}`}
        aria-label="Soleur avatar"
      >
        <img
          src="/icons/soleur-logo-mark.png"
          alt=""
          width={sizeConfig.icon + 4}
          height={sizeConfig.icon + 4}
          className="h-full w-full object-cover"
        />
      </span>
    );
  }

  const bgColor = LEADER_BG_COLORS[leaderId!];
  const IconComponent = ICON_MAP[leader.defaultIcon];
  const showCustomIcon = customIconPath && !imgError;

  return (
    <span
      className={`flex ${sizeConfig.container} shrink-0 items-center justify-center rounded-md ${bgColor} overflow-hidden ${className ?? ""}`}
      aria-label={`${leader.name} avatar`}
    >
      {showCustomIcon ? (
        <img
          src={`/api/kb/content/${customIconPath}`}
          alt={`${leader.name} custom icon`}
          width={sizeConfig.icon + 4}
          height={sizeConfig.icon + 4}
          className="h-full w-full object-cover"
          onError={() => setImgError(true)}
        />
      ) : (
        IconComponent && (
          <IconComponent size={sizeConfig.icon} className="text-white" />
        )
      )}
    </span>
  );
});

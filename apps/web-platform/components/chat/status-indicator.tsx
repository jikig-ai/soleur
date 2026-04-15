"use client";

export type ChatStatus = "connecting" | "connected" | "reconnecting" | "disconnected";

export function StatusIndicator({
  status,
  disconnectReason,
}: {
  status: ChatStatus;
  disconnectReason?: string;
}) {
  const config = {
    connecting: { color: "bg-yellow-500", label: "Connecting" },
    connected: { color: "bg-green-500", label: "Connected" },
    reconnecting: { color: "bg-yellow-500", label: "Reconnecting" },
    disconnected: { color: "bg-red-500", label: "Disconnected" },
  };

  const { color, label } = config[status];

  return (
    <div className="flex items-center gap-2">
      <span className={`h-2 w-2 rounded-full ${color}`} />
      <span className="text-xs text-neutral-500">
        {status === "disconnected" && disconnectReason ? disconnectReason : label}
      </span>
    </div>
  );
}

"use client";

import { useParams } from "next/navigation";
import { ChatSurface } from "@/components/chat/chat-surface";

export default function ChatPage() {
  const params = useParams<{ conversationId: string }>();
  return <ChatSurface variant="full" conversationId={params.conversationId} />;
}

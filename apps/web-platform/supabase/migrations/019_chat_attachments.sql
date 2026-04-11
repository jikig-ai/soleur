-- Chat attachments: Storage bucket + message_attachments table
-- Supports image (PNG, JPEG, GIF, WebP) and PDF uploads via presigned URLs

-- 1. Create private Storage bucket for chat attachments
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-attachments', 'chat-attachments', false)
ON CONFLICT (id) DO NOTHING;

-- 2. Storage RLS: authenticated users can read objects in their own conversations
CREATE POLICY "Users can read own attachment objects"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- No INSERT/UPDATE/DELETE via anon key — uploads happen via service role presigned URLs

-- 3. Create message_attachments table
CREATE TABLE public.message_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  filename text NOT NULL,
  content_type text NOT NULL,
  size_bytes integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;

-- RLS: SELECT only for users who own the conversation (via messages -> conversations join)
CREATE POLICY "Users can read own message attachments"
  ON public.message_attachments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversations c ON c.id = m.conversation_id
      WHERE m.id = message_attachments.message_id
        AND c.user_id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policies for anon/authenticated — all writes via service role

-- 4. Index on message_id for join performance
CREATE INDEX idx_message_attachments_message_id
  ON public.message_attachments(message_id);

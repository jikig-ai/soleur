-- Enable Supabase Realtime to include all column values in change payloads.
-- Required for the Command Center's real-time status badge updates.
ALTER TABLE public.conversations REPLICA IDENTITY FULL;

BEGIN;
ALTER TABLE public.messages ALTER COLUMN sender_id TYPE TEXT USING sender_id::TEXT;
ALTER TABLE public.messages ALTER COLUMN receiver_id TYPE TEXT USING receiver_id::TEXT;
COMMIT;

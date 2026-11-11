-- Lock message writes to the membership- and role-checked RPCs.
-- The original permissive table policies allowed clients to bypass channel
-- posting restrictions and message edit/delete validation through PostgREST.

drop policy if exists "Members can send messages as themselves" on public.messages;
drop policy if exists "Authors can edit their own messages" on public.messages;
drop policy if exists "Authors can delete their own messages" on public.messages;

-- Authenticated clients retain SELECT access through "Members can read messages".
-- send_chat_message, edit_chat_message, delete_chat_message and
-- forward_chat_message remain the only supported client write paths.

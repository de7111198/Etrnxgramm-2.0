-- Secure message sending and realtime delivery preparation.

create or replace function public.send_chat_message(
  target_chat uuid,
  message_text text,
  reply_message uuid default null
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_body text := btrim(message_text);
  inserted_message public.messages;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if clean_body is null or char_length(clean_body) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  if char_length(clean_body) > 10000 then
    raise exception 'Message is too long';
  end if;

  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = current_user_id
  ) then
    raise exception 'You are not a member of this chat';
  end if;

  if reply_message is not null and not exists (
    select 1 from public.messages
    where id = reply_message and chat_id = target_chat
  ) then
    raise exception 'Reply target must belong to this chat';
  end if;

  insert into public.messages (chat_id, sender_id, body, reply_to)
  values (target_chat, current_user_id, clean_body, reply_message)
  returning * into inserted_message;

  update public.chats set updated_at = now() where id = target_chat;

  return inserted_message;
end;
$$;

revoke all on function public.send_chat_message(uuid, text, uuid) from public;
grant execute on function public.send_chat_message(uuid, text, uuid) to authenticated;

-- Add messages to Supabase Realtime publication when it exists and the table
-- has not already been added. Safe to apply more than once.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'messages'
     ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$$;

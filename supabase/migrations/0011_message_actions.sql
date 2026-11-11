-- Secure message editing, deletion and forwarding.
create or replace function public.edit_chat_message(
  target_message uuid,
  replacement_text text
)
returns public.messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  clean_body text := btrim(replacement_text);
  updated_message public.messages;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if clean_body is null or char_length(clean_body) = 0 then
    raise exception 'Message cannot be empty';
  end if;
  if char_length(clean_body) > 10000 then
    raise exception 'Message is too long';
  end if;
  update public.messages
  set body = clean_body, edited_at = now()
  where id = target_message and sender_id = caller
    and public.is_chat_member(chat_id)
  returning * into updated_message;
  if not found then
    raise exception 'Message not found or cannot be edited';
  end if;
  return updated_message;
end;
$$;

create or replace function public.delete_chat_message(target_message uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then raise exception 'Authentication required'; end if;
  delete from public.messages
  where id = target_message and sender_id = caller
    and public.is_chat_member(chat_id);
  if not found then
    raise exception 'Message not found or cannot be deleted';
  end if;
end;
$$;

create or replace function public.forward_chat_message(
  source_message uuid,
  destination_chat uuid
)
returns public.messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  source_row public.messages;
  destination_kind public.chat_kind;
  destination_role public.chat_member_role;
  forwarded public.messages;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select * into source_row from public.messages
  where id = source_message and public.is_chat_member(chat_id);
  if not found then raise exception 'Source message not found'; end if;

  select c.kind, m.role into destination_kind, destination_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = destination_chat and m.user_id = caller;
  if destination_kind is null then
    raise exception 'You are not a member of the destination chat';
  end if;
  if destination_kind = 'channel' and destination_role not in ('owner', 'admin') then
    raise exception 'Only channel administrators can publish messages';
  end if;

  insert into public.messages(chat_id, sender_id, body, forwarded_from)
  values (destination_chat, caller, source_row.body, source_row.id)
  returning * into forwarded;
  update public.chats set updated_at = now() where id = destination_chat;
  return forwarded;
end;
$$;

revoke all on function public.edit_chat_message(uuid, text) from public;
revoke all on function public.delete_chat_message(uuid) from public;
revoke all on function public.forward_chat_message(uuid, uuid) from public;
grant execute on function public.edit_chat_message(uuid, text) to authenticated;
grant execute on function public.delete_chat_message(uuid) to authenticated;
grant execute on function public.forward_chat_message(uuid, uuid) to authenticated;

-- Channel creation and server-enforced channel posting permissions.
-- Channel owners/admins can publish; members can read and react.

create or replace function public.create_channel_chat(
  channel_title text,
  member_ids uuid[] default array[]::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  new_chat uuid;
  requested_count integer;
  valid_count integer;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  if channel_title is null or char_length(trim(channel_title)) not between 1 and 80 then
    raise exception 'Channel title must be between 1 and 80 characters';
  end if;
  if member_ids is null then
    member_ids := array[]::uuid[];
  end if;

  select count(distinct requested.user_id) into requested_count
  from unnest(member_ids) as requested(user_id);
  select count(*) into valid_count
  from public.profiles p where p.id = any(member_ids);
  if valid_count <> requested_count then
    raise exception 'One or more selected users do not exist';
  end if;

  insert into public.chats(kind, title, created_by)
  values ('channel', trim(channel_title), caller)
  returning id into new_chat;

  insert into public.chat_members(chat_id, user_id, role)
  values (new_chat, caller, 'owner');

  insert into public.chat_members(chat_id, user_id, role)
  select new_chat, requested.user_id, 'member'
  from (
    select distinct requested.user_id
    from unnest(member_ids) as requested(user_id)
  ) requested
  where requested.user_id <> caller;

  return new_chat;
end;
$$;

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
  current_role public.chat_member_role;
  current_kind public.chat_kind;
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

  select c.kind, m.role into current_kind, current_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = target_chat and m.user_id = current_user_id;

  if current_kind is null then
    raise exception 'You are not a member of this chat';
  end if;
  if current_kind = 'channel' and current_role not in ('owner', 'admin') then
    raise exception 'Only channel administrators can publish messages';
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

revoke all on function public.create_channel_chat(text, uuid[]) from public;
grant execute on function public.create_channel_chat(text, uuid[]) to authenticated;
revoke all on function public.send_chat_message(uuid, text, uuid) from public;
grant execute on function public.send_chat_message(uuid, text, uuid) to authenticated;

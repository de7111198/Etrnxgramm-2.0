-- Etrnxgram chat hardening and ownership transfer.
-- Apply after 0002_chat_operations.sql.

create or replace function public.create_group_chat(chat_title text, member_ids uuid[])
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
  if chat_title is null or char_length(trim(chat_title)) not between 1 and 80 then
    raise exception 'Group title must be between 1 and 80 characters';
  end if;
  if member_ids is null then
    member_ids := array[]::uuid[];
  end if;

  select count(distinct requested.user_id) into requested_count
  from unnest(member_ids) as requested(user_id);
  if requested_count > 199 then
    raise exception 'A group can contain at most 200 members';
  end if;

  select count(*) into valid_count
  from public.profiles p
  where p.id = any(member_ids);
  if valid_count <> requested_count then
    raise exception 'One or more selected users do not exist';
  end if;

  insert into public.chats(kind, title, created_by)
  values ('group', trim(chat_title), caller)
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

create or replace function public.add_chat_member(target_chat uuid, new_member uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  current_kind public.chat_kind;
  member_count integer;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;

  select kind into current_kind
  from public.chats
  where id = target_chat
  for update;

  if current_kind is null then
    raise exception 'Chat not found';
  end if;
  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = caller
      and role in ('owner', 'admin')
  ) then
    raise exception 'Only chat admins can add members';
  end if;
  if current_kind = 'direct' then
    raise exception 'Direct chats cannot have additional members';
  end if;
  if not exists (select 1 from public.profiles where id = new_member) then
    raise exception 'User not found';
  end if;
  if exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = new_member
  ) then
    return;
  end if;

  select count(*) into member_count
  from public.chat_members
  where chat_id = target_chat;
  if member_count >= 200 then
    raise exception 'A group can contain at most 200 members';
  end if;

  insert into public.chat_members(chat_id, user_id, role)
  values (target_chat, new_member, 'member');
end;
$$;

create or replace function public.transfer_chat_ownership(
  target_chat uuid,
  new_owner uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  current_kind public.chat_kind;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  if new_owner is null or new_owner = caller then
    raise exception 'Choose another group member';
  end if;

  select kind into current_kind
  from public.chats
  where id = target_chat
  for update;

  if current_kind is null or current_kind = 'direct' then
    raise exception 'Group or channel not found';
  end if;
  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = caller and role = 'owner'
  ) then
    raise exception 'Only the current owner can transfer ownership';
  end if;
  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = new_owner
  ) then
    raise exception 'New owner must already be a member';
  end if;

  update public.chat_members
  set role = 'admin'
  where chat_id = target_chat and user_id = caller;

  update public.chat_members
  set role = 'owner'
  where chat_id = target_chat and user_id = new_owner;
end;
$$;

revoke all on function public.create_group_chat(text, uuid[]) from public;
revoke all on function public.add_chat_member(uuid, uuid) from public;
revoke all on function public.transfer_chat_ownership(uuid, uuid) from public;
grant execute on function public.create_group_chat(text, uuid[]) to authenticated;
grant execute on function public.add_chat_member(uuid, uuid) to authenticated;
grant execute on function public.transfer_chat_ownership(uuid, uuid) to authenticated;

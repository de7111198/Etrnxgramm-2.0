-- Transactional chat creation and membership operations.
-- These SECURITY DEFINER functions are the only client-facing write path
-- for chat creation and adding members; each checks the authenticated caller.

create or replace function public.create_direct_chat(target_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  new_chat uuid;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  if target_user is null or target_user = caller then
    raise exception 'Choose another registered user';
  end if;
  if not exists (select 1 from public.profiles where id = target_user) then
    raise exception 'User not found';
  end if;

  -- Reuse an existing one-to-one conversation, if present.
  select c.id into new_chat
  from public.chats c
  where c.kind = 'direct'
    and exists (select 1 from public.chat_members a where a.chat_id = c.id and a.user_id = caller)
    and exists (select 1 from public.chat_members b where b.chat_id = c.id and b.user_id = target_user)
    and (select count(*) from public.chat_members m where m.chat_id = c.id) = 2
  limit 1;

  if new_chat is not null then
    return new_chat;
  end if;

  insert into public.chats(kind, created_by) values ('direct', caller)
  returning id into new_chat;
  insert into public.chat_members(chat_id, user_id, role)
  values (new_chat, caller, 'owner'), (new_chat, target_user, 'member');
  return new_chat;
end;
$$;

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
  requested_count := (select count(distinct x) from unnest(member_ids) as x);
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
  select new_chat, x, 'member'
  from (select distinct unnest(member_ids) as x) requested
  where x <> caller;

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
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  select kind into current_kind from public.chats where id = target_chat;
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
  if not exists (select 1 from public.profiles where id = new_member) then
    raise exception 'User not found';
  end if;
  if current_kind = 'direct' then
    raise exception 'Direct chats cannot have additional members';
  end if;
  insert into public.chat_members(chat_id, user_id, role)
  values (target_chat, new_member, 'member')
  on conflict (chat_id, user_id) do nothing;
end;
$$;

create or replace function public.leave_chat(target_chat uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  current_kind public.chat_kind;
  caller_role public.chat_member_role;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  select c.kind, m.role into current_kind, caller_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = target_chat and m.user_id = caller;
  if current_kind is null then
    raise exception 'Chat membership not found';
  end if;
  if current_kind <> 'direct' and caller_role = 'owner'
     and (select count(*) from public.chat_members where chat_id = target_chat) > 1 then
    raise exception 'Transfer ownership before leaving this group';
  end if;
  delete from public.chat_members where chat_id = target_chat and user_id = caller;
  if not exists (select 1 from public.chat_members where chat_id = target_chat) then
    delete from public.chats where id = target_chat;
  end if;
end;
$$;

revoke all on function public.create_direct_chat(uuid) from public;
revoke all on function public.create_group_chat(text, uuid[]) from public;
revoke all on function public.add_chat_member(uuid, uuid) from public;
revoke all on function public.leave_chat(uuid) from public;
grant execute on function public.create_direct_chat(uuid) to authenticated;
grant execute on function public.create_group_chat(text, uuid[]) to authenticated;
grant execute on function public.add_chat_member(uuid, uuid) to authenticated;
grant execute on function public.leave_chat(uuid) to authenticated;

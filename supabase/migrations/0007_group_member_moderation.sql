-- Group member moderation with server-enforced role checks.
create or replace function public.set_chat_member_role(
  target_chat uuid,
  target_user uuid,
  new_role public.chat_member_role
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
  if caller is null then raise exception 'Authentication required'; end if;
  if new_role not in ('member', 'admin') then
    raise exception 'Only member or admin roles can be assigned';
  end if;
  select kind into current_kind from public.chats
    where id = target_chat for update;
  if current_kind is null or current_kind = 'direct' then
    raise exception 'Group or channel not found';
  end if;
  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = caller and role = 'owner'
  ) then
    raise exception 'Only the owner can change administrator roles';
  end if;
  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = target_user
  ) then raise exception 'Member not found'; end if;
  if target_user = caller then raise exception 'Owner cannot change their own role'; end if;
  update public.chat_members set role = new_role
    where chat_id = target_chat and user_id = target_user;
end;
$$;

create or replace function public.remove_chat_member(
  target_chat uuid,
  target_user uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  current_kind public.chat_kind;
  caller_role public.chat_member_role;
  target_role public.chat_member_role;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if target_user = caller then raise exception 'Use leave_chat to leave the group'; end if;
  select kind into current_kind from public.chats
    where id = target_chat for update;
  if current_kind is null or current_kind = 'direct' then
    raise exception 'Group or channel not found';
  end if;
  select role into caller_role from public.chat_members
    where chat_id = target_chat and user_id = caller;
  select role into target_role from public.chat_members
    where chat_id = target_chat and user_id = target_user;
  if caller_role is null or target_role is null then
    raise exception 'Member not found';
  end if;
  if caller_role = 'owner' then
    if target_role = 'owner' then raise exception 'Cannot remove the owner'; end if;
  elsif caller_role = 'admin' then
    if target_role <> 'member' then
      raise exception 'Admins can remove regular members only';
    end if;
  else
    raise exception 'Only owners and admins can remove members';
  end if;
  delete from public.chat_members
    where chat_id = target_chat and user_id = target_user;
end;
$$;

revoke all on function public.set_chat_member_role(uuid, uuid, public.chat_member_role) from public;
revoke all on function public.remove_chat_member(uuid, uuid) from public;
grant execute on function public.set_chat_member_role(uuid, uuid, public.chat_member_role) to authenticated;
grant execute on function public.remove_chat_member(uuid, uuid) to authenticated;

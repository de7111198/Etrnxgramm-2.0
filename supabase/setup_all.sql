-- Etrnxgram one-time database setup
-- Run this script ONCE in the Supabase SQL Editor for a brand-new project.
-- Do not rerun after a successful execution: some constraints/policies are not idempotent.

-- ==================== 0001_initial_schema.sql ====================
-- Etrnxgram initial Supabase schema
-- Apply with the Supabase CLI or SQL editor after creating a project.
-- Privileged gift administration and marketplace settlement must run server-side.

create extension if not exists pgcrypto;

create type public.chat_kind as enum ('direct', 'group', 'channel');
create type public.chat_member_role as enum ('member', 'admin', 'owner');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Etrnx User' check (char_length(display_name) between 1 and 64),
  about text not null default '' check (char_length(about) <= 160),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.usernames (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  username text not null unique check (username ~ '^[A-Za-z][A-Za-z0-9_]{3,31}$'),
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index usernames_one_primary_per_user
  on public.usernames(user_id) where is_primary;

create table public.chats (
  id uuid primary key default gen_random_uuid(),
  kind public.chat_kind not null,
  title text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'direct' and title is null) or (kind <> 'direct' and title is not null))
);

create table public.chat_members (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.chat_member_role not null default 'member',
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  primary key (chat_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  body text not null check (char_length(body) between 1 and 10000),
  reply_to uuid references public.messages(id) on delete set null,
  forwarded_from uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);
create index messages_chat_created_idx on public.messages(chat_id, created_at desc);

create table public.gift_collections (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.gift_models (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.gift_collections(id) on delete restrict,
  name text not null,
  artwork_url text,
  rarity text not null default 'regular',
  edition_limit integer check (edition_limit is null or edition_limit > 0),
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.gifts (
  id uuid primary key default gen_random_uuid(),
  model_id uuid not null references public.gift_models(id) on delete restrict,
  owner_id uuid not null references public.profiles(id),
  serial_number bigint,
  background_key text,
  symbol_key text,
  acquired_at timestamptz not null default now(),
  is_listed boolean not null default false,
  unique (model_id, serial_number)
);

create table public.gift_transfers (
  id uuid primary key default gen_random_uuid(),
  gift_id uuid not null references public.gifts(id) on delete restrict,
  from_user_id uuid references public.profiles(id),
  to_user_id uuid not null references public.profiles(id),
  transfer_kind text not null check (transfer_kind in ('grant', 'transfer', 'marketplace', 'revoke')),
  created_at timestamptz not null default now()
);

create table public.gift_listings (
  id uuid primary key default gen_random_uuid(),
  gift_id uuid not null unique references public.gifts(id) on delete restrict,
  seller_id uuid not null references public.profiles(id),
  status text not null default 'active' check (status in ('active', 'sold', 'cancelled')),
  created_at timestamptz not null default now()
);

-- Membership checks use SECURITY DEFINER to avoid recursive RLS on chat_members.
create or replace function public.is_chat_member(target_chat uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = auth.uid()
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), 'Etrnx User'));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.usernames enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.gift_collections enable row level security;
alter table public.gift_models enable row level security;
alter table public.gifts enable row level security;
alter table public.gift_transfers enable row level security;
alter table public.gift_listings enable row level security;

create policy "Authenticated users can view profiles"
  on public.profiles for select to authenticated using (true);
create policy "Users update their own profile"
  on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "Authenticated users can view usernames"
  on public.usernames for select to authenticated using (true);
create policy "Users add their own usernames"
  on public.usernames for insert to authenticated with check (user_id = auth.uid());
create policy "Users remove their own usernames"
  on public.usernames for delete to authenticated using (user_id = auth.uid());
create policy "Users change their own username primary flag"
  on public.usernames for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "Members can view their chats"
  on public.chats for select to authenticated using (public.is_chat_member(id));
create policy "Members can view chat membership"
  on public.chat_members for select to authenticated using (public.is_chat_member(chat_id));

create policy "Members can read messages"
  on public.messages for select to authenticated using (public.is_chat_member(chat_id));
create policy "Members can send messages as themselves"
  on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Authors can edit their own messages"
  on public.messages for update to authenticated
  using (sender_id = auth.uid() and public.is_chat_member(chat_id))
  with check (sender_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Authors can delete their own messages"
  on public.messages for delete to authenticated
  using (sender_id = auth.uid() and public.is_chat_member(chat_id));

create policy "Users can view published gift collections"
  on public.gift_collections for select to authenticated using (is_published);
create policy "Users can view published gift models"
  on public.gift_models for select to authenticated using (
    is_published and exists (
      select 1 from public.gift_collections c
      where c.id = collection_id and c.is_published
    )
  );
create policy "Users can view their own gifts"
  on public.gifts for select to authenticated using (owner_id = auth.uid());
create policy "Users can view transfers involving them"
  on public.gift_transfers for select to authenticated
  using (from_user_id = auth.uid() or to_user_id = auth.uid());
create policy "Users can view active gift listings"
  on public.gift_listings for select to authenticated
  using (status = 'active' or seller_id = auth.uid());

-- Deliberately no client-side write policies for gifts, transfers, listings,
-- chat creation or membership changes. Those operations require trusted,
-- server-side authorization and transactional functions.


-- ==================== 0002_chat_operations.sql ====================
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


-- ==================== 0003_chat_hardening.sql ====================
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


-- ==================== 0004_remove_group_member_cap.sql ====================
-- Remove the fixed member-count cap from groups and channels.
-- Membership remains restricted to authenticated owners/admins.

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

  insert into public.chat_members(chat_id, user_id, role)
  values (target_chat, new_member, 'member')
  on conflict (chat_id, user_id) do nothing;
end;
$$;

revoke all on function public.create_group_chat(text, uuid[]) from public;
revoke all on function public.add_chat_member(uuid, uuid) from public;
grant execute on function public.create_group_chat(text, uuid[]) to authenticated;
grant execute on function public.add_chat_member(uuid, uuid) to authenticated;


-- ==================== 0005_profile_sync.sql ====================
-- Profile synchronization helpers.
-- Username changes are performed transactionally so each account always has
-- at most one primary username and usernames remain globally unique.

create or replace function public.set_primary_username(username_value text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  normalized text := lower(trim(username_value));
  existing_owner uuid;
  existing_id uuid;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  if normalized !~ '^[a-z][a-z0-9_]{3,31}$' then
    raise exception 'Username must be 4-32 characters: letters, numbers or underscore';
  end if;

  select user_id, id into existing_owner, existing_id
  from public.usernames
  where lower(username) = normalized
  for update;

  if existing_owner is not null and existing_owner <> caller then
    raise exception 'This username is already taken';
  end if;

  if existing_id is null then
    insert into public.usernames(user_id, username, is_primary)
    values (caller, normalized, false)
    returning id into existing_id;
  end if;

  update public.usernames
  set is_primary = false
  where user_id = caller and is_primary;

  update public.usernames
  set is_primary = true
  where id = existing_id and user_id = caller;
end;
$$;

revoke all on function public.set_primary_username(text) from public;
grant execute on function public.set_primary_username(text) to authenticated;

create or replace function public.touch_profile_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_profile_updated_at();


-- ==================== 0006_secure_message_sending.sql ====================
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


-- ==================== 0007_group_member_moderation.sql ====================
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


-- ==================== 0008_message_reactions.sql ====================
-- Secure per-user message reactions.
-- Clients can read reactions in chats they belong to; all writes go through
-- the membership-checked toggle RPC below.

create table public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (emoji in ('👍', '❤️', '😂', '😮', '😢', '🔥', '🎉')),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create index message_reactions_chat_message_idx
  on public.message_reactions(chat_id, message_id);

alter table public.message_reactions enable row level security;

create policy "Chat members can view message reactions"
  on public.message_reactions for select to authenticated
  using (public.is_chat_member(chat_id));

create or replace function public.toggle_message_reaction(
  target_message uuid,
  reaction_emoji text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_chat uuid;
  removed_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if reaction_emoji not in ('👍', '❤️', '😂', '😮', '😢', '🔥', '🎉') then
    raise exception 'Unsupported reaction';
  end if;

  select chat_id into target_chat
  from public.messages
  where id = target_message
  for update;

  if target_chat is null then
    raise exception 'Message not found';
  end if;

  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = current_user_id
  ) then
    raise exception 'You are not a member of this chat';
  end if;

  delete from public.message_reactions
  where message_id = target_message
    and user_id = current_user_id
    and emoji = reaction_emoji
  returning id into removed_id;

  if removed_id is not null then
    return false;
  end if;

  insert into public.message_reactions (message_id, chat_id, user_id, emoji)
  values (target_message, target_chat, current_user_id, reaction_emoji)
  on conflict (message_id, user_id, emoji) do nothing;

  return true;
end;
$$;

revoke all on function public.toggle_message_reaction(uuid, text) from public;
grant execute on function public.toggle_message_reaction(uuid, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'message_reactions'
     ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end;
$$;


-- ==================== 0009_channels.sql ====================
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


-- ==================== 0010_platform_owner_gift_admin.sql ====================
-- Platform owner registry and privileged gift administration.
-- No account is automatically made owner. Seed platform_owners manually
-- from the Supabase SQL editor using the maintainer's verified auth user UUID.

create table public.platform_owners (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.platform_owners enable row level security;

create or replace function public.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_owners
    where user_id = auth.uid()
  );
$$;

create or replace function public.owner_create_gift_collection(
  collection_name text,
  collection_description text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null or not public.is_platform_owner() then
    raise exception 'Platform owner permission required';
  end if;
  if collection_name is null or char_length(trim(collection_name)) not between 1 and 80 then
    raise exception 'Collection name must be between 1 and 80 characters';
  end if;
  insert into public.gift_collections(name, description, is_published)
  values (trim(collection_name), left(coalesce(collection_description, ''), 500), true)
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.owner_create_gift_model(
  target_collection uuid,
  model_name text,
  image_url text default null,
  model_rarity text default 'regular',
  max_edition integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null or not public.is_platform_owner() then
    raise exception 'Platform owner permission required';
  end if;
  if model_name is null or char_length(trim(model_name)) not between 1 and 80 then
    raise exception 'Gift name must be between 1 and 80 characters';
  end if;
  if model_rarity not in ('regular', 'limited', 'rare', 'epic', 'legendary') then
    raise exception 'Unsupported gift rarity';
  end if;
  if max_edition is not null and max_edition < 1 then
    raise exception 'Edition limit must be positive';
  end if;
  if not exists (
    select 1 from public.gift_collections
    where id = target_collection and is_published
  ) then
    raise exception 'Published collection not found';
  end if;
  insert into public.gift_models(
    collection_id, name, artwork_url, rarity, edition_limit, is_published
  ) values (
    target_collection, trim(model_name), nullif(trim(image_url), ''),
    model_rarity, max_edition, true
  ) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.owner_grant_gift(
  target_user uuid,
  target_model uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_gift uuid;
  next_serial bigint;
  edition_cap integer;
begin
  if auth.uid() is null or not public.is_platform_owner() then
    raise exception 'Platform owner permission required';
  end if;
  if not exists (select 1 from public.profiles where id = target_user) then
    raise exception 'Recipient not found';
  end if;

  select edition_limit into edition_cap
  from public.gift_models
  where id = target_model and is_published
  for update;
  if not found then
    raise exception 'Published gift model not found';
  end if;

  select coalesce(max(serial_number), 0) + 1 into next_serial
  from public.gifts where model_id = target_model;

  if edition_cap is not null and next_serial > edition_cap then
    raise exception 'This limited edition is sold out';
  end if;

  insert into public.gifts(model_id, owner_id, serial_number)
  values (target_model, target_user, next_serial)
  returning id into new_gift;

  insert into public.gift_transfers(
    gift_id, from_user_id, to_user_id, transfer_kind
  ) values (new_gift, auth.uid(), target_user, 'grant');

  return new_gift;
end;
$$;

revoke all on function public.is_platform_owner() from public;
revoke all on function public.owner_create_gift_collection(text, text) from public;
revoke all on function public.owner_create_gift_model(uuid, text, text, text, integer) from public;
revoke all on function public.owner_grant_gift(uuid, uuid) from public;
grant execute on function public.is_platform_owner() to authenticated;
grant execute on function public.owner_create_gift_collection(text, text) to authenticated;
grant execute on function public.owner_create_gift_model(uuid, text, text, text, integer) to authenticated;
grant execute on function public.owner_grant_gift(uuid, uuid) to authenticated;


-- ==================== 0011_message_actions.sql ====================
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


-- ==================== 0012_pinned_messages.sql ====================
-- Pinned messages with role-checked mutations.
create table public.chat_pins (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by uuid not null references public.profiles(id),
  pinned_at timestamptz not null default now(),
  unique (chat_id, message_id)
);
create index chat_pins_chat_pinned_idx on public.chat_pins(chat_id, pinned_at desc);
alter table public.chat_pins enable row level security;

create policy "Chat members can view pinned messages"
  on public.chat_pins for select to authenticated
  using (public.is_chat_member(chat_id));

create or replace function public.pin_chat_message(target_message uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  target_chat uuid;
  target_kind public.chat_kind;
  caller_role public.chat_member_role;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select chat_id into target_chat
  from public.messages where id = target_message;
  if target_chat is null then raise exception 'Message not found'; end if;

  select c.kind, m.role into target_kind, caller_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = target_chat and m.user_id = caller;
  if target_kind is null then raise exception 'You are not a member of this chat'; end if;
  if target_kind <> 'direct' and caller_role not in ('owner', 'admin') then
    raise exception 'Only chat administrators can pin messages';
  end if;

  insert into public.chat_pins(chat_id, message_id, pinned_by)
  values (target_chat, target_message, caller)
  on conflict (chat_id, message_id) do nothing;
end;
$$;

create or replace function public.unpin_chat_message(
  target_chat uuid,
  target_message uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  target_kind public.chat_kind;
  caller_role public.chat_member_role;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select c.kind, m.role into target_kind, caller_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = target_chat and m.user_id = caller;
  if target_kind is null then raise exception 'You are not a member of this chat'; end if;
  if target_kind <> 'direct' and caller_role not in ('owner', 'admin') then
    raise exception 'Only chat administrators can unpin messages';
  end if;
  delete from public.chat_pins
  where chat_id = target_chat and message_id = target_message;
end;
$$;

revoke all on function public.pin_chat_message(uuid) from public;
revoke all on function public.unpin_chat_message(uuid, uuid) from public;
grant execute on function public.pin_chat_message(uuid) to authenticated;
grant execute on function public.unpin_chat_message(uuid, uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'chat_pins'
     ) then
    alter publication supabase_realtime add table public.chat_pins;
  end if;
end;
$$;


-- ==================== 0013_chat_settings.sql ====================
-- Per-user chat settings: archive state, mute deadline and pin ordering.
create table public.chat_user_settings (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  archived_at timestamptz,
  muted_until timestamptz,
  pinned_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
alter table public.chat_user_settings enable row level security;

create policy "Users read their own chat settings"
  on public.chat_user_settings for select to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Users create their own chat settings"
  on public.chat_user_settings for insert to authenticated
  with check (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Users update their own chat settings"
  on public.chat_user_settings for update to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id))
  with check (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Users delete their own chat settings"
  on public.chat_user_settings for delete to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));


-- ==================== 0014_lock_down_message_writes.sql ====================
-- Lock message writes to the membership- and role-checked RPCs.
-- The original permissive table policies allowed clients to bypass channel
-- posting restrictions and message edit/delete validation through PostgREST.

drop policy if exists "Members can send messages as themselves" on public.messages;
drop policy if exists "Authors can edit their own messages" on public.messages;
drop policy if exists "Authors can delete their own messages" on public.messages;

-- Authenticated clients retain SELECT access through "Members can read messages".
-- send_chat_message, edit_chat_message, delete_chat_message and
-- forward_chat_message remain the only supported client write paths.


-- ==================== 0015_case_insensitive_usernames.sql ====================
-- Username matching is case-insensitive throughout the app.
-- Prevent visually identical handles such as Alice and alice from coexisting.

create unique index if not exists usernames_username_lower_unique
  on public.usernames (lower(username));


-- ==================== 0016_profile_cover.sql ====================
-- Persistent profile cover image URL.
alter table public.profiles
  add column if not exists cover_url text;

alter table public.profiles
  add constraint profiles_avatar_url_length
  check (avatar_url is null or char_length(avatar_url) <= 2048);

alter table public.profiles
  add constraint profiles_cover_url_length
  check (cover_url is null or char_length(cover_url) <= 2048);


-- ==================== 0017_profile_media_storage.sql ====================
-- Public profile images with writes restricted to the owning account.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-media',
  'profile-media',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Profile images are publicly readable"
on storage.objects for select
to public
using (bucket_id = 'profile-media');

create policy "Users upload their own profile images"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users update their own profile images"
on storage.objects for update
to authenticated
using (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users delete their own profile images"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

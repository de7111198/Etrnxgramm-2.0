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

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

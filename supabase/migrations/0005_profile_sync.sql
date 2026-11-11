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

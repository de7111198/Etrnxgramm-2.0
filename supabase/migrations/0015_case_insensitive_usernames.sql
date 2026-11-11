-- Username matching is case-insensitive throughout the app.
-- Prevent visually identical handles such as Alice and alice from coexisting.

create unique index if not exists usernames_username_lower_unique
  on public.usernames (lower(username));

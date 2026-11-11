# Etrnxgram

Etrnxgram is a Flutter messenger project targeting Android and Windows, with Android, Windows and unsigned iOS builds configured in CI.

## Current project status

- Flutter app with Chats, Groups, Channels, Gifts, Contacts and Profile tabs; Contacts supports user search by display name or primary username and opens direct conversations.
- Channels have server-enforced read-only subscriber access: only owners and admins can publish.
- Gifts includes a published-model catalog and a personal collection view; gift grants, transfers and purchases remain server-side work.
- Email one-time-code login UI and Supabase session gate are implemented. They activate only when the Supabase project URL and public anon/publishable key are supplied at build time.
- Profile name, about text and primary username now load from and save to Supabase when configured. Cover art and avatar presentation are still local UI only.
- Profile editing UI is currently local to the device; it is not synchronized to a server yet.
- GitHub Actions checks Dart analysis, runs widget tests and builds Android and Windows release artifacts.
- GitHub Actions also attempts an unsigned iOS release build on macOS runners.
- Supabase schema and secure chat operations are included in `supabase/migrations/`. The client now has chat creation, direct conversations, group member lists, invitations by username, role management and ownership transfer; these features require the Supabase project and migrations to be activated.
- **The backend is not connected yet.** Login, real-time messaging, multi-device sync and live gift data are not available until a Supabase project is configured and migrations are applied. The catalog and collection screens are client UI backed by the planned schema.

## Build artifacts

Open the repository's **Actions** tab, select the latest successful **Flutter CI** run, and download:
- `etrnxgram-android-apk` for the Android APK.
- `etrnxgram-windows` for the Windows release files.
- `etrnxgram-ios-app-unsigned` for the unsigned iOS app bundle, if the macOS build job succeeds. This is not installable on an iPhone until it is signed with an Apple development/distribution identity.

The CI workflow generates platform folders during the build, so they do not need to be committed to the repository.

## Backend foundation (Supabase)

Migrations are in `supabase/migrations/`:

- `0001_initial_schema.sql` defines profiles, multiple usernames, chats, membership, messages, gift collections/models, owned gifts, transfers and listings. Row Level Security is enabled.
- `0002_chat_operations.sql` adds authenticated database functions for creating direct/group chats, adding group members as an owner/admin, and leaving chats. These functions check the caller's identity and permissions.
- `0003_chat_hardening.sql` adds owner-controlled group/channel ownership transfer and serializes membership changes.
- `0004_remove_group_member_cap.sql` removes the fixed group member-count cap while keeping membership changes restricted to owners/admins.
- `0005_profile_sync.sql` adds a transactional primary-username operation and profile update timestamp trigger.
- `0006_secure_message_sending.sql` adds authenticated message sending with membership and reply checks, and enables message Realtime.
- `0007_group_member_moderation.sql` adds owner-controlled admin promotion/demotion and secure member removal; admins can remove regular members only.
- `0008_message_reactions.sql` adds per-user message reactions, membership-protected reads, a secure toggle RPC and Realtime updates.
- `0009_channels.sql` adds channel creation and enforces owner/admin-only publishing on the server.
- `0010_platform_owner_gift_admin.sql` adds an explicitly seeded platform-owner registry and secure gift collection/model creation and gift-grant RPCs.
- `0011_message_actions.sql` adds server-checked message editing, deletion and forwarding.
- `0012_pinned_messages.sql` adds membership-protected pinned-message reads and role-checked pin/unpin operations, with a live pinned-message banner in chat threads.
- `0013_chat_settings.sql` adds per-user archive, mute and pin settings with row-level security.

The owner gift panel is available only after the maintainer manually inserts their verified Supabase Auth user UUID into `public.platform_owners` using the Supabase SQL Editor. There is no first-user auto-owner or hidden default administrator. User-to-user gift transfers and marketplace settlement still require additional trusted server-side operations and audit logging.

To activate a backend later:

1. Create a Supabase project owned by the project maintainer.
2. Apply all SQL migrations in numerical order using the Supabase SQL Editor or Supabase CLI.
3. Configure email OTP delivery and allowed redirect URLs in Supabase Auth.
4. Add GitHub Actions repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY` (the public anon/publishable key). The workflow passes them to Android, Windows and iOS builds as compile-time values. Never add a service-role key, database password or email-provider secret to the Flutter app, GitHub Actions build variables, or public repository.
5. Manually seed `public.platform_owners` with the maintainer's verified Auth user UUID from the Supabase SQL Editor to enable the owner panel. Do not add a client-side owner claim flow.
6. Connect and test the Flutter client and server-side operations before enabling real messaging, gift administration or marketplace actions.

The migrations alone do not create a running backend. Email OTP also requires email delivery and redirect settings to be configured in Supabase Auth. Without the two GitHub secrets, the app deliberately shows a server-not-configured screen instead of pretending that login works.

## Development

The app uses Flutter. The CI workflow runs `flutter pub get`, `flutter analyze`, widget tests, an Android release build, a Windows release build and an unsigned iOS build on macOS runners.

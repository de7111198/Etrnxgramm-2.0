# Etrnxgram

Etrnxgram is a Flutter messenger project targeting Android and Windows, with an iOS build planned.

## Current project status

- Flutter app shell with Chats, Gifts, Contacts and Profile tabs.
- Profile editing UI is currently local to the device; it is not synchronized to a server yet.
- GitHub Actions checks Dart analysis and builds Android and Windows release artifacts.
- A first Supabase database migration is included in `supabase/migrations/`.
- **The backend is not connected yet.** Login, real-time messaging, multi-device sync, gifts and marketplace actions are not live features at this stage.

## Build artifacts

Open the repository's **Actions** tab, select the latest successful **Flutter CI** run, and download:
- `etrnxgram-android-apk` for the Android APK.
- `etrnxgram-windows` for the Windows release files.

The CI workflow generates platform folders during the build, so they do not need to be committed to the repository.

## Backend foundation (Supabase)

The initial schema is in:

`supabase/migrations/0001_initial_schema.sql`

It defines profiles, multiple usernames, chats, membership, messages, gift collections/models, owned gifts, transfers and listings. Row Level Security is enabled. Sensitive operations such as creating chats, changing membership, granting/transferring gifts and settling marketplace transactions intentionally have no client-side write policies; they must be implemented as trusted server-side operations with authorization and audit logging.

To activate a backend later:

1. Create a Supabase project owned by the project maintainer.
2. Apply the SQL migration using the Supabase SQL Editor or Supabase CLI.
3. Configure email OTP delivery and allowed redirect URLs in Supabase Auth.
4. Add the project's public URL and publishable/anon key to the app's build configuration. Never put a service-role key, database password or email-provider secret in the Flutter app or public repository.
5. Implement and test the server-side operations before enabling chat creation, gift administration or marketplace actions.

The migration alone does not create a running backend or make the app connect to Supabase.

## Development

The app uses Flutter. The CI workflow runs `flutter pub get`, `flutter analyze`, an Android release build and a Windows release build on pushes to `main` and pull requests.

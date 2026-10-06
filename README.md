# Vistar Logitek — LR Management

Digital Lorry Receipt generation, dispatch, billing and reporting system built per the SRS for Vistar Logitek Pvt Ltd.

**Stack:** Flutter (web · Windows · Android · iOS) · Riverpod · go_router · Plus Jakarta Sans

## Quick start

```bash
flutter pub get
flutter run -d chrome     # or windows / android
```

**Demo logins** (one-click sign-in available on the login screen):

| Role | Username | Password |
|---|---|---|
| Admin | `admin` | `admin` |
| Operator | `anita` | `anita` |
| Accounts | `ravi` | `ravi` |

## Project structure

```
lib/
  core/            theme, router, constants, utils
  shared/          models, reusable widgets
  features/
    auth/          login, profile, change/forgot password
    dashboard/     stats, role-flow, top customers
    lr/            list, create, edit, detail, print (4 copies)
    masters/       consignors, consignees, vehicles, drivers, transporters, routes
    ewb/           12-digit validator + expiry tracking
    warehouse/     booked / in-transit / delivered
    reports/       daily / monthly / accounts tabs + CSV / Tally export
    accounts/      pending freight + margin + Tally export
    admin/         users, numbering, audit, settings
    shell/         sidebar + topbar layout
```

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for Cloudflare Pages setup (GitHub Actions auto-deploy + direct CLI).

## Usage analytics (event tracker)

`lib/core/telemetry/telemetry.dart`, using the in-house `vistar_event_tracker`
SDK (vendored in `packages/`, see its `VENDORED.md`). Read in the Platform
Console under Analytics > Event tracker; register the app there (Settings >
Event tracker) as `lr_app` to get its write key.

**Off unless the build gets both `ET_APP_ID` and `ET_WRITE_KEY`.** Without
them nothing is initialised and the app behaves exactly as before.

- **Live web app.** Built by Cloudflare Pages' Git integration (project
  `vistar-transport-management-system`), whose build command is
  `bash cloudflare-build.sh` (see [DEPLOYMENT.md](DEPLOYMENT.md)). To switch
  analytics on, add two **build** variables under Settings > Build > Variables
  and secrets: `ET_APP_ID` = `lr_app` and `ET_WRITE_KEY` (encrypted), then
  retry the latest production deployment. The script passes them to
  `flutter build web` only when both are set and logs
  `Usage analytics on, as lr_app` (or `off`). If the dashboard's build command
  has been replaced by an inline command, append
  `--dart-define=ET_APP_ID=$ET_APP_ID --dart-define=ET_WRITE_KEY=$ET_WRITE_KEY`
  to its `flutter build web` instead. The GitHub workflow publishes nothing;
  it passes the repository variable `ET_APP_ID` and secret `ET_WRITE_KEY` to
  its check build when both are set.
- **APK / other builds.** Add
  `--dart-define=ET_APP_ID=lr_app --dart-define=ET_WRITE_KEY=wk_...`.

Events go to the host of `API_BASE_URL` (a UAT build, with
`API_BASE_URL=https://uat-api.vistarlogitek.com/api/v1/lr-management`, reports
to UAT); `ET_BASE_URL` overrides it.

Sent: screen views by route pattern (`/lrs/:id/edit`: ids, LR numbers and
vehicle numbers replaced), sign-in / sign-out (the user as `lr:<user id>` with
role and organisation codes only), named actions from successful API writes
(`lr_created`, `lr_status_changed`, `lr_sent_for_payment`, `invoice_created`,
`tracking_started`, `vehicle_created`, ... see `_actions`), failed API calls
(5xx / no connection: endpoint pattern, method, status) and uncaught client
errors (error type only). Never sent: request or response bodies, error
messages, names, usernames, emails, phone numbers, LR or vehicle numbers,
consignor / consignee names, amounts. Nothing is awaited by a screen, a save,
a sign-in or a sign-out; start-up waits at most 2 s; the event queue is capped
at 200 in shared preferences.

## Verification

```bash
flutter analyze     # static analysis (clean)
flutter test        # widget tests (passing)
flutter build web --release
```

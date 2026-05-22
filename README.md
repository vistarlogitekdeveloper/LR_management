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

## Verification

```bash
flutter analyze     # static analysis (clean)
flutter test        # widget tests (passing)
flutter build web --release
```

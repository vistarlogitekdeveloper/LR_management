# VTMS on Google Play: listing pack

Developer account: personal (decided 2026-11-18). App id: `com.vistarlogitek.vtms`.

## Store listing

**App name** (max 30 characters): `VTMS – Vistar Transport`

**Short description** (max 80 characters):
> Create LRs, track consignments and upload proof of delivery for Vistar Logitek.

**Full description** (max 4,000 characters):
> VTMS is the transport management app of Vistar Logitek. It is for Vistar staff and authorised partners.
>
> With VTMS you can:
> • Create and edit lorry receipts (LRs) with consignor, consignee, vehicle and freight details
> • Track every consignment from booking to delivery
> • Take proof of delivery (POD) photos with the camera, or attach a document
> • Pick pickup and delivery points on a map
> • Export LRs as PDF or Excel
>
> You need an account to sign in. Accounts are created by your company administrator. VTMS has no ads.

**Category:** Business. **Tags:** Logistics, Transportation.
**Contact email:** a company inbox (shown publicly). **Website:** https://vistarlogitek.com

## Graphics

| Asset | Size | Source |
|---|---|---|
| App icon | 512×512 PNG, 32-bit, max 1 MB | `icon/app_icon.png`, scaled |
| Feature graphic | 1024×500 PNG/JPG, no alpha | to make: logo + "VTMS" on the brand colour |
| Phone screenshots | 2–8, 16:9 or 9:16, min 320 px side | from the app on a phone or emulator: login, LR list, LR form, POD, map |

## App content answers

- **Privacy policy URL:** `https://lr-management.pages.dev/privacy-policy.html` (file: `web/privacy-policy.html`, live once this PR is merged to main).
- **App access:** "All functionality is behind a login. Use username `<reviewer login>` / password `<given in this field>`. The account is a demo with sample data." *You create this account. Type its password into Play Console yourself.*
- **Ads:** No ads.
- **Content rating (IARC):** Category "Utility, productivity, communication or other". Answer No to violence, sexual content, language, controlled substances and gambling. Users don't interact publicly and the app doesn't share location. Expected result: rated for everyone (3+).
- **Target audience:** 18 and over only. Not designed for children.
- **News app:** No. **Government app:** No. **Financial features:** none. **Health:** No.
- **Account deletion:** Play requires a deletion route. Give the privacy policy's "Deleting your account" section URL. It explains how to ask by email.

## Data safety form

Encrypted in transit: **Yes**. Users can request deletion: **Yes** (by email). Data is never sold. Nothing is collected for advertising.

| Data type (Play's name) | Collected | Shared | Purpose | Optional? |
|---|---|---|---|---|
| Personal info → Name, Email address, Phone number, User IDs | Yes | No | App functionality, Account management | Required |
| Photos and videos → Photos | Yes | No | App functionality (proof of delivery) | Optional (only when a POD is added) |
| Files and docs | Yes | No | App functionality (POD documents) | Optional |
| App activity → App interactions | Yes | No | Analytics | Required |
| App info and performance → Crash logs, Diagnostics | Yes | No | Analytics | Required |
| Location | **No** | – | Points are chosen on a map; the app has no location permission | – |

"Shared" means sent to a *third party*. Data sent to Vistar's own servers, or to Google Maps tiles for display, is not "sharing" under Play's definition.

## Personal account: testing before production

New personal accounts must run a **closed test with at least 12 testers opted in for 14 days in a row** before they can apply for production.

1. Testing → Closed testing → create a track. Add testers as an email list: 12+ Gmail/Google accounts of employees. Upload the .aab and roll it out.
2. Share the opt-in link. Each tester opens it, taps "Become a tester", installs from Play and **keeps it installed for 14 days**.
3. After 14 days: Dashboard → "Apply for production". Answer the questions about the test.
4. After approval, promote the release to Production. Review usually takes 1–7 days.

**Internal testing** (up to 100 testers, almost no review) works from day one. It's a free way to get the app to staff through Play while the closed test runs.

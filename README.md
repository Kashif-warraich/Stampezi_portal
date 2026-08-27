# Stampezi portal

The print-shop portal: customers send files from their phone by scanning a shop's QR code,
and each shop's Windows service polls for them and prints. Rails 8 + PostgreSQL, with
Cloudflare R2 for the files themselves.

The desktop half lives in `../Stampezi_desktop`. The HTTP API is a contract, not a
preference — the deployed `Stampezi.Service` parses these exact paths, camelCase keys and
ISO 8601 timestamps, so nothing here gets renamed.

## Running it

```
bundle install
bin/rails db:prepare          # create, migrate, seed
bin/rails server -p 3300
```

Ruby 4.0.3 (`.ruby-version`), Rails 8.1, PostgreSQL.

Every credential is an environment variable, listed in `.env` (gitignored): `DATABASE_URL`,
`SECRET_KEY_BASE`, `R2_*`, `ADMIN_TOKEN`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`. Production sets
the same names for real — on Render, from `render.yaml` — so the two differ by values only.
`ADMIN_PASSWORD` deliberately has no default: a known admin password in production is a way
in.

Sign in at `/admin/login` with the seeded account. **Change the password before deploying.**

```
bin/rails test                # models + API contract + admin pages
```

## The admin back office

`/admin` is plain Rails — controllers in `app/controllers/admin/`, ERB views, `layout
"admin"`, and session auth through this app's own `User` model with a 12-hour TTL. No
Devise, and no admin framework: ActiveAdmin was tried and removed, which is why there is no
Ransack, no `dartsass-rails` and no Sprockets to fight Propshaft. (The
`ransackable_attributes` methods still on the models are leftovers of that and are unused.)

| Page | What you can do |
|---|---|
| Dashboard | licence counts by status, files waiting, recent uploads, newest releases |
| Live | which shops are still checking in, worst first - the page to open when someone says a shop has stopped printing |
| Shops | full CRUD, name search, status filter chips; creating one issues its licence in the same transaction |
| Shop page | **Extend** by N months, set the expiry date directly, activate/deactivate, **Reset machine binding** (30-day cooldown), **Download QR** as a print-resolution PNG, last 25 uploads |
| Releases | upload a build, publish, rename, delete, choose which shops it rolls out to, and watch Pending fall to zero as Running climbs |
| Users | full CRUD — add, rename, change password, delete |

A shop's licence number is never editable: it is printed on QR codes and configured into
desktop services, so renaming a shop is allowed and re-issuing a number is not.

### Live

Every agent writes `licenses.last_check_at` on its licence check, once a minute by default,
so silence is the whole signal - there is no heartbeat table and nothing extra for a shop to
send. `/admin/live` buckets shops into **live** (seen in the last 5 minutes), **quiet**
(under an hour), **not checking in** (over an hour) and **never seen**, sorts the worst to
the top so one silent shop cannot be pushed off the bottom by a hundred healthy ones, and
refreshes itself every minute with a `<meta http-equiv="refresh">` - the admin loads no
JavaScript and this needs none.

The thresholds are fixed in `License::LIVE_WITHIN` and `LATE_WITHIN` rather than derived
from each shop's `LicenseCheckIntervalMinutes`, because that interval lives in the shop's
own `setup.ini` and the portal never sees it.

What the page deliberately does not claim is *why* a shop is silent. A stopped service, a
switched-off PC and a dead router are the same event from here, and a shop whose licence has
fully expired stops checking in on purpose.

### Releases and rollout

The **Upload** page does the whole publish in the browser: it computes the SHA-256 with
WebCrypto, reserves a slot with `POST /api/agent-releases`, `PUT`s the 230 MB installer
straight to R2 over XHR (for the progress bar), then confirms with `…/publish`. The bytes
never touch the Rails process, which is on a web dyno with neither the time nor the memory
for them. `Stampezi_desktop/tools/publish-release.ps1` drives the same two endpoints from
the build machine.

Publishing arms nothing. A release's page lists every shop with a checkbox, and saving that
form is what sets `shops.target_agent_version` — tick two shops on Monday, the rest on
Wednesday. Unticking a shop freezes it where it is rather than rolling it back, because a
rollback has to be an explicit choice.

The list shows two counts per release. **Running** is what the shops themselves last
reported on their licence check, so it climbs on its own as they take the build. **Pending**
is what has been asked for and has not arrived yet: rolling out to five shops reads 5 and
counts down to 0. Pending 0 with Running 5 is a finished rollout; both reading 0 means
nobody has been rolled out to yet, which is correct rather than broken.

On a release's own page each shop shows where it stands - **frozen** (no target, so it keeps
what is installed), **updating -> x.y.z**, or **up to date**. The target version is printed
only while it differs from what the shop reports; once they match, repeating it in the next
column tells the operator nothing. It is still stored, though: `shops.target_agent_version`
is a standing instruction, not a queue item, and it is what makes a shop reinstalled from an
old `setup.exe` update itself back to where it belongs - as well as what stops the release it
depends on being deleted or pruned out of R2.

R2 keeps the newest three published builds (`AgentRelease::KEEP_OBJECTS`) and never prunes
a version some shop is still pointed at, which would strand that shop with an update it can
never download. Deleting or renaming a release is refused for the same reason while a shop
targets it; a rename moves the R2 object server-side so the row and the bytes keep
describing each other.

## How the pieces fit

| Path | Who calls it |
|---|---|
| `/upload?l=<licence>` | a customer's phone, from the shop's QR code |
| `/admin/*` | the operator, in a browser |
| `/api/license/check` | each shop's desktop service, on a timer — also carries update instructions |
| `/api/pending-files?license=` | the desktop service, polling |
| `/api/files/:id/download-url` | the desktop service, claiming one file |
| `/api/files/:id/release` | the desktop service, handing a claim back after a failed download |
| `/api/upload-session`, `/api/upload-complete` | the upload page's JavaScript |
| `/api/shops`, `/api/license/extend`, `/api/license/reset-binding` | scripts, via `ADMIN_TOKEN` |
| `/api/agent-releases`, `/api/agent-releases/:id/publish` | the release upload page and `publish-release.ps1`, via `ADMIN_TOKEN` |

Files never pass through this app. The phone `PUT`s straight to R2 with a presigned URL,
and the shop `GET`s it back the same way; Rails only signs URLs and records state. R2 is
S3-compatible, so this is `aws-sdk-s3` against a different endpoint — and presigning needs
real keys, which is why `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` exist rather than a
bucket binding.

**The licence number is the shop's identity** — 10 digits, printed on the QR code and
configured into the desktop service. It is also the credential on the public API endpoints,
which is a known limitation, not a design goal.

**A file is delivered exactly once.** `download-url` claims it with a single conditional
`UPDATE`, so of two racing requests exactly one gets the URL. `release` is the way back:
without it, a download that died after the claim would keep the file out of every future
poll and lose the customer's job.

**R2 is a passing medium, not storage.** A customer's file is deleted from the bucket once
it can no longer reach a desktop - `PENDING_WINDOW` with nothing touching the row, which is
exactly when `pending-files` stops offering it and `release` stops resurrecting it. The
sweep rides on the poll every shop makes every few seconds, because this plan has no
scheduler; it is capped per request, marks rows with `purged_at` so a key is never offered
twice, and never raises, since housekeeping must not be able to stop a delivery. A claim
bumps `updated_at`, so a download still in flight keeps its own object alive. Deleting a
shop deletes its objects first, before the rows that are the only record of them.

One gap worth knowing: a shop whose licence has fully lapsed stops polling, so its files
stop being swept. An R2 lifecycle rule on the `shops/` prefix is the backstop if that ever
matters - `agent/` must stay out of its scope.

**A licence binds to one machine**, claimed the same way on first check-in — the `WHERE
machine_fingerprint IS NULL` guard makes a second machine racing the first lose rather than
rebind. Clearing it is an admin action with a 30-day cooldown, which is what stops one
licence quietly running on many PCs.

**Expiry is enforced server-side.** `active` / `grace` (5 days) / `expired`, computed in
`License`; `check_status` reports `valid` instead of `active` because the deployed .NET
client matches that exact string, and a test locks that down. Deactivating a shop reads as
expired to the desktop whatever the expiry date, and the file endpoints then 403 — so an
unpatched desktop cannot ignore it.

Uploads are limited to `UploadRules::ALLOWED_EXTENSIONS` and 50 MB. The browser checks both
so the customer finds out early, but the presigned `PUT` goes straight to R2, so
`upload-complete` is where an oversized file is actually rejected and deleted.

## Deploying to Render

Create the service from `render.yaml`, then set the values Render cannot generate:
`ADMIN_PASSWORD` and the four `R2_*` keys.

Migrations and seeding belong in a `preDeployCommand`, which the free plan does not offer,
so they ride along at the end of `buildCommand` instead — chained with `&&` throughout, so
a failed migration fails the deploy rather than shipping an app against the wrong schema.
`db:seed` is a no-op once the admin exists.

`DATABASE_URL` comes from the managed Postgres and overrides everything in
`config/database.yml`, so the same code path runs locally and in production.

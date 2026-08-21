# Stampezi portal

The print-shop portal: customers send files from their phone by scanning a shop's QR code,
and each shop's Windows service polls for them and prints. Rails 8 + PostgreSQL, with
Cloudflare R2 for the files themselves.

Replaces the Next.js portal in `../Stampezi_portal_Next.js`. The HTTP API is unchanged - the
deployed `Stampezi.Service` desktop client talks to the same paths with the same JSON.

## Running it

```
bundle install
bin/rails db:prepare          # create, migrate, seed
bin/rails server -p 3300
```

Every credential is an environment variable, listed in `.env` (gitignored): `DATABASE_URL`,
`SECRET_KEY_BASE`, `R2_*`, `ADMIN_TOKEN`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`. Production sets
the same names for real - on Render, from `render.yaml` - so the two differ by values only.

Sign in at `/admin/login` with the seeded account (`ADMIN_EMAIL` / `ADMIN_PASSWORD`,
defaults `admin@stampezi.it` / `change-me`). **Change the password before deploying.**

## The admin back office

`/admin` is [ActiveAdmin](https://activeadmin.info), one file per model in `app/admin/`:

| Resource | What you can do |
|---|---|
| `Dashboard` | licence counts by status, files waiting, recent uploads |
| `Shops` | full CRUD; creating one issues its licence in the same transaction |
| `Admin users` | full CRUD - add, rename, change password, delete |
| `Licences` | read-only; expiry moves through the Extend action so it is always logged |
| `Uploads` | read-only; editing rows would desynchronise them from R2 |

It was installed with `--skip-users`, so there is **no Devise**: ActiveAdmin authenticates
through this app's own `User` model and session (`config.authentication_method =
:require_admin`, `current_user_method = :current_user`).

Per-shop actions live on the shop page: **Extend** by N months, **Reset machine binding**
(30-day cooldown), and **Download QR** as a print-resolution PNG.

Two things that will bite if you add a model or a filter:

- Ransack needs an explicit `ransackable_attributes` allowlist on every model, or the index
  page raises. It is a security boundary - it is what stops `password_digest` being
  searchable from a query string.
- ActiveAdmin ships Sass sources only. `dartsass-rails` compiles them (`bin/rails
  dartsass:build`, and automatically during `assets:precompile`). Do not add `sassc-rails`:
  it drags in Sprockets, which fights Rails 8's Propshaft.

```
bin/rails test                # models + API contract
```

## How the pieces fit

| Path | Who calls it |
|---|---|
| `/upload?l=<licence>` | a customer's phone, from the shop's QR code |
| `/admin/*` | the operator, in a browser |
| `/api/license/check` | each shop's desktop service, on a timer |
| `/api/pending-files?license=` | the desktop service, polling |
| `/api/files/:id/download-url` | the desktop service, claiming one file |
| `/api/upload-session`, `/api/upload-complete` | the upload page's JavaScript |
| `/api/shops`, `/api/license/extend`, `/api/license/reset-binding` | scripts, via `ADMIN_TOKEN` |

Files never pass through this app. The phone `PUT`s straight to R2 with a presigned URL,
and the shop `GET`s it back the same way; Rails only signs URLs and records state.

**The licence number is the shop's identity** - 10 digits, printed on the QR code and
configured into the desktop service. It never changes, which is why renaming a shop is
allowed and re-issuing a number is not.

**A file is delivered exactly once.** `download-url` claims it with a single conditional
`UPDATE`, so of two racing requests exactly one gets the URL. **A licence binds to one
machine**, claimed the same way on first check-in; clearing it is an admin action with a
30-day cooldown.

## Deploying to Render

Create the service from `render.yaml`, then set the values Render cannot generate:
`ADMIN_PASSWORD` and the four `R2_*` keys. Migrations and seeding run in
`preDeployCommand`, so a deploy to an empty database is a single step.

`DATABASE_URL` comes from the managed Postgres and overrides everything in
`config/database.yml` - the same code path runs locally and in production.

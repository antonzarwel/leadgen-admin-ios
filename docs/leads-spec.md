# Lead Gen Admin: unified leads (discovery + implementation spec)

**Status:** discovery only. No code or database changes were made.  
**As of:** 24 Nov 2026, America/Sao_Paulo. Counts are from Supabase project `nfoawkvgnbdckcllopus` (saunify-booking) unless noted.  
**Ask:** store and show leads from every directory and trade site in the Lead Gen Admin app (web + native iPhone). Each lead is a card: which companies it was sent or offered to, who accepted, plus site, date, service, location, budget/description, price, status, billed/free, and contact (admin only).

---

## 1. Current apps (what already exists)

The work is split across two GitHub repos, both already checked out:

| Repo | Path on this box | Role |
|---|---|---|
| `antonzarwel/leadgen-admin` | `/workspace/repos/leadgen-admin` (main = `769696d`, 18 Nov 2026) | Next.js web admin + client portal + APIs, including `/api/m/*` for the iPhone app. Deployed at `leadgen-admin-alpha.vercel.app`. |
| `antonzarwel/leadgen-admin-ios` | `/workspace/leadgen-admin-ios` (main = `c118558`) | Native SwiftUI iPhone app (iOS 17+, bundle `com.antonzarwel.leadgenadmin`). No web view. Read-only JSON from `/api/m/*`. |

There is already a Leads experience in both. It is built only on `public.lg_leads`. It does **not** join `td_lead_market` / `td_lead_offers`, so a trade lead is either missing from the useful card shape, or it appears as several disconnected rows (the unassigned master plus one clone per routed/accepted buyer).

### 1.1 Schema the admin already uses

`lg_leads` (14,976 rows, 25 Jan 2022 – 24 Nov 2026) is the system of record for exclusive/rental site leads and also the landing table for trade quote forms.

Columns (do not guess new names; these are the live ones):

`id` uuid pk, `client_id` → `lg_clients`, `domain`, `source`, `external_id`, `submitted_at`, `name`, `phone`, `email`, `message`, `raw_data` jsonb, `created_at`, `lead_status`, `notes`, `follow_up_date`, `status_*_at` timestamps, `won_value_sek`, `bad_lead` + reason/audit, `lead_quality_score`, `notes_won`, `phone_normalized`, `email_normalized`, `is_duplicate`, `dupe_of`, `dedup_reason`, `invoice_draft_id`, `won_completion`, `is_test`.

Allowed `source` values: `typeform`, `jotform`, `telavox`, `custom_form`, `directory-form`, `phone` (phone is wired in the app but has **0** rows).

Related: `lg_sites` (59 WordPress/rental sites), `lg_clients` (164; 159 active, 5 archived), `lg_client_domains`, `lg_form_mappings` (87 Typeform/Jotform mappings), `lg_webhook_log` (0 rows).

There is **no** existing `lg_leads` view, and no `lg_lead_recipients` table or view.

### 1.2 Web admin

- Page: `/leads` (`app/leads/page.tsx`). Table + side panel. Filters: client, site, source, date, CRM status, tests, duplicates, bad leads.
- List API: `GET /api/leads` reads `lg_leads` directly (page/per_page, max 100).
- Mutations: `PATCH /api/admin/leads/[id]` (CRM fields), `POST /api/admin/leads/[id]/flag` (junk), `POST /api/admin/leads` (manual phone lead).
- **Do not use** `PATCH /api/leads/[id]`. That route is a leftover Notion client. CRM writes go through `/api/admin/leads/[id]`. The Notion route also contains a hardcoded fallback API key in source; remove the fallback in the same cleanup and rotate the key if it was ever committed. Do not put secrets in the app or in this spec.

The web page treats every `lg_leads` row as a card. For trade leads that means the master (often `client_id` null) and the per-buyer copies all show up as separate leads. There is no recipient list, no offer status, no price, no billed/free except indirectly via CRM / `raw_data.free_lead`.

### 1.3 iOS app (already has a Leads tab)

Tabs: **Today**, **Leads**, **Clients**, **Money**, **Sites**. Face ID lock, Keychain token, on-device cache, pull-to-refresh, tab-change and refresh haptics, swipe-to-call.

Leads tab today:

- `GET /api/m/leads?days=90` (server allows 1–365, default 90). Duplicates and `bad_lead` are excluded. Test leads are included and flagged.
- Search: name, phone, email, or site.
- Filters: kind (All / Forms / Calls / Missed), period (client default 30 days on an already-fetched 90-day payload), client, show-tests. `LeadFilter.domain` exists but is not a first-class control in the filter menu (used when arriving from a site).
- Day-sectioned list, lead detail (contact, message, map when a place can be parsed, client and site links), swipe actions, copy with haptic.

`Lead` has no recipients, price, billed/free, service, location, or marketplace status. The app is **admin-only** (password → bearer). There is no client-restricted iOS build yet.

### 1.4 Client portal

`/client/leads` + `GET /api/client/leads` already scopes to `session.client_id`, hides duplicates and junk, and lets the client edit CRM status. A trade buyer who received a clone row can see that copy (including contact, because the clone is only written after route/accept). They cannot see the full market, other companies, or unaccepted offers. Exclusive clients see every lead assigned to them.

---

## 2. Source inventory

Two lead *models* exist today. The unified UI has to show both, without mixing them up.

**A. Exclusive / rental leads** — one client owns the site; every lead is delivered automatically (email + portal). No accept/decline. Recipients are implied (`lg_leads.client_id`, `lg_sites.notify_email`, `cc_emails`).  
**B. Trade marketplace leads** — a homeowner request can be offered to several firms; contact is revealed only after a firm accepts (max 3 slots). Recipients live in `td_lead_offers` (and sometimes `td_lead_routes`).

### 2.1 Exclusive WordPress sites (`lg_sites`, 59 domains)

These are the rental/lead sites (trädfällning, VVS, elektriker, hoppborg, etc.). They are **not** named `byggare-*.se`. No domain matching `byggare-*.se` exists in `lg_sites` or `lg_leads`. Treat “byggare-*.se lead sites” as this 59-site portfolio unless Anton names a different set.

Ingest path today: WordPress custom form → `scripts/leadgen-rebuild/lead-submit.php` (Hostinger, shared across the sites) inserts `source=custom_form` into `lg_leads` and emails Anton + the client. Historical sources were Typeform and Jotform (webhooks + a re-import cron). Calls come from Telavox.

| Source | Rows | First (UTC) | Last (UTC) | Tests / dupes / bad | Recipients / acceptance |
|---|---:|---|---|---|---|
| `typeform` | 8,992 | 2022-01-25 | 2026-07-12 | 0 / 224 / 20 | Assigned `client_id` (or `orphaned`). No accept flow. **`raw_data` is null on every row.** Names 446, messages 446, phones 8,253, emails 8,980. |
| `jotform` | 3,443 | 2022-08-20 | 2026-04-23 | 0 / 82 / 12 | Same. **`raw_data` is null on every row.** Contact fields are mostly filled. |
| `telavox` | 1,490 | 2025-11-24 | 2026-11-24 | 1 / 446 / 1 | Assigned to the Telavox client. `raw_data`: `missed`, `duration_s`, `queue_*`, `answered_by`, sometimes caller city/address. No email. |
| `custom_form` | 976 | 2026-03-17 | 2026-11-24 | 1 / 69 / 33 | Assigned `client_id` (8 rows have none). `raw_data` usually has `service`, `city`, `test`, sometimes `photos`. 103 rows marked `backfilled_from`; 11 also have Gmail backfill ids. |
| `phone` | 0 | — | — | — | Manual portal entry exists but unused. |

**Notifications:** all 59 `lg_sites` have `notify_email`; 41 have `cc_emails`. The admin also has `lib/lead-notify.ts` (Gmail). There is **no send log table** (`lg_webhook_log` is empty). “Sent to company X at time T” for exclusive leads cannot be reconstructed from a first-class event; only the lead row and the inbox exist.

### 2.2 Veravi (Jan-Erik)

Exclusive client `veravi`. **789** `lg_leads` rows. Sites in the lead rows include `arborististockholm.se`, `tradfallningtaby.se`, and the Danderyd, Lidingö, Huddinge and Värmdö trädfällning domains (some stored as punycode). Form mappings exist for both Typeform and Jotform. These are **not** marketplace leads; they must not be merged with `arboristtorget.se`.

### 2.3 Husbesiktning sites (former MB Projekt, now unrented)

Eight `lg_sites` rows, all `client_id=orphaned` (MB Projekt paid ~14k SEK/month, then went bankrupt). Leads are still coming in on the custom forms.

Domains with rows in `lg_leads` (approximate, by `domain` on the row):

| Site | Rows (domain match) | Range |
|---|---:|---|
| husbesiktninghbg.se | 274 | 2022-03-28 – 2026-10-25 |
| besiktningsmänskåne.se | 184 | 2022-05-20 – 2026-11-20 |
| husbesiktningmalmö.se | 93 | 2022-05-20 – 2026-11-23 |
| göteborghusbesiktning.se | 75 | 2023-02-13 – 2026-11-18 |
| uppsalahusbesiktning.se | 70 | 2022-06-01 – 2026-11-08 |
| husbesiktningvästerås.se | 64 | 2022-05-21 – 2026-10-16 |
| stockholmhusbesiktning.se | 23 | 2022-10-14 – 2026-11-02 |
| husbesiktningeskilstuna.se | 1 | 2026-10-13 |

Family total with a husbesiktning/besiktningsmän domain: **736 typeform + 48 custom_form**. Additional orphaned Typeform/Jotform rows have `domain` null; form titles include Husbesiktning Vallentuna, Lidingö, Besiktningsföretaget, and similar. Överlåtelsebesiktningar.se is in `lg_sites` but did not show up as a `lg_leads.domain`. Historical recipients were MB Projekt (mail also went to Anton). There is no current paying client, and no accept flow.

### 2.4 Trade directories (`trade-directory`, same Supabase project)

One Next.js codebase, eight verticals. Quote form `POST /api/offert` always inserts a **master** `lg_leads` row with `source=directory-form`, `client_id` null, `external_id = dir_<uuid>` (40 chars). Then, if the market (or the older router) is on, it writes marketplace / route rows and may clone `lg_leads` for a buyer (`external_id = <master>_<client_id>`, `raw_data.routed_from`, `offer_id`, `free_lead`).

| Vertical | Domain | Buyers (`td_buyers`) | Master `directory-form` leads in `lg_leads` | `td_lead_market` | `td_lead_offers` | Notes |
|---|---|---:|---:|---:|---:|---|
| varmepump | varmepumpinstallator.se | 33 (29 active) | 22 unassigned + several clones | 5 | 52 | Live market. |
| tak | jamfortaklaggare.se | 32 | 7 unassigned + clones (many tests) | 5 | 16 | Live; several test market rows. |
| badrum | badrumsforetag.se | 24 | 3 unassigned + 1 clone | 1 | 18 | Live. |
| bastubygge | bastubyggare.se | 5 | 11 unassigned + 1 clone | 9 (7 closed, 2 open) | 95 | Live; 69 queued offers sit on one open lead (Magnus / Bastuexperten batch). |
| arborist | arboristtorget.se | 30 (29 active) | 3 unassigned | 2 | **0** | Market rows exist but **no offers were written**. Gap. |
| dranering | draneringsforetag.se | 16 | 2 unassigned (both flagged bad) | 0 | 0 | Buyers exist; no market run. |
| kranbil | hyrkranbil.se | **0** | 3 unassigned | 0 | 0 | Leads exist; no buyers, so nobody to offer to. |
| bryggbyggare | bryggbyggare.se | 3 active | **0** | 0 | 0 | Site is new (claim outreach mid-Nov 2026). Ready for offers, no homeowner leads yet. |

`directory-form` totals: **75** rows, 18 Oct 2026 – 24 Nov 2026. Of those, **51** are 40-character unassigned masters (28 flagged `bad_lead`). **24** are longer per-buyer clones. **22** masters match `td_lead_market.master_external_id`. Most bad/spam masters never entered the market.

Marketplace tables:

- `td_lead_market` (22 rows, 15 Oct – 24 Nov 2026). pk `master_external_id`. Columns include `vertical`, `kommun`, `kommun_slug`, `jobb`, `is_test`, `max_slots`, `status` (`open` / `full` / `closed`), `code`, schedule timestamps, `followup`, `note`, offer subject/text.  
- `td_lead_offers` (181 rows). One row per company the lead was (or will be) offered to. Statuses seen: `queued`, `offered`, `won`, `expired`, `released`, `cancelled`. Schema also allows `sending`, `late`, `failed`. Key fields: `company_slug/id/name`, `email`, `client_id`, `tier`, `price_shown`, `billable`, `free_n`, `offered_at`, `accepted_at`, `delivered_at`, `expired_at`, `released_at`, `contacted_at`, `credit_status`, `resend_id`, `consent`. **This is the acceptance record.**  
- `td_lead_routes` (19 rows, 18 Oct – 23 Nov 2026). Older/parallel “push to buyer” path: `master_external_id`, `client_id`, `lead_external_id`, `kommun`, `email_status` (`sent` 17, `pending` 1, `skipped` 1), `void_reason`, `free_n`, `offer_id`. 13 sent and not voided, 4 sent but later voided.  
- `td_buyers` (143). Buyer accounts, kommuner, plan, `price_accepted`.

`raw_data` on directory leads is rich: `kommun`, `lan`, `jobb` / `jobb_label`, `vertical`, calculator fields (`kalkyl_*`, `boyta`, `takyta`, `material`, `nar`, `hustyp`, …), `routed_from`, `offer_id`, `free_lead`, `market`.

Product rule already in force (do not break it): builders do not see homeowner contact until they accept; at most three can accept; price is only charged if they take the lead (and after any free trial).

Historical typeform rows also exist on Veravi’s exclusive arborist site and an orphaned `arboristskåne.se` — those are exclusive-site leads, not `arboristtorget.se` marketplace leads.

### 2.5 Sauna directories (bastur.se, saunakortet.dk, saunaorte.de)

Live in **saunify-prod** (`dugzxwpvodewpmcbwpku`), not in the lead-gen database.

| Table | Rows | What it is |
|---|---:|---|
| `bastur_claims` | 132 | Operators claiming a listing. Not a homeowner inquiry. |
| `bastur_edits` / `bastur_photos` / `bastur_submissions` | 236 / 278 / 2 | Listing changes and 2 operator-submitted saunas. |
| `bastur_page_stats` | 5,560 | Pageviews and outbound clicks. No personal data. |
| `public.leads` | 1,846 | Saunify **venue outreach CRM** (company, outreach emails, `bastur_slug`). Not directory customer inquiries. |

Visitor contact on these sites is outbound (phone/website click). There is no quote-form write into `lg_leads`. Do not import `bastur_claims` or saunify-prod `leads` into the Lead Gen leads view.

### 2.6 Other / not lead-gen customer inquiries

Bastuexperten tables on the same project (`orders`, `be_quiz_subscribers`, `be_callback_requests`, `be_lead_notes`) are a different business. Skip them.

---

## 3. Gaps

1. **Trade marketplace is not a first-class card.** Offers, accepts, price, billed/free and the company list live in `td_lead_*`. The admin and iOS apps only list `lg_leads` rows, so one homeowner request becomes many cards, or an unassigned master with no recipients.
2. **No recipient event log for exclusive sites.** We know who *should* have received the lead (`client_id`, `notify_email`) but not whether the mail was sent, opened, or bounced.
3. **Typeform/Jotform `raw_data` is empty.** Service, city, budget are often missing as structured fields. Typeform in particular is thin on `name` and `message`. Some of that may only exist in the original notification email.
4. **Pre-2022 and HubSpot leads are email-only.** Gmail harvest (`/workspace/leadgen-revenue/email-leads`) shows Typeform notifications from April 2020 and HubSpot form notifications from mid-2020 through early 2024. `lg_leads` starts 25 Jan 2022 and has **no** `hubspot` source. Those years are not in the database.
5. **Domain often null** on older Typeform/Jotform rows (thousands of rows, especially `client_id=orphaned` or assigned only at client level). Site filters will under-count unless backfilled from form mappings / mail.
6. **Marketplace coverage holes:** arborist market rows with zero offers; dranering buyers but no market; hyrkranbil leads with zero buyers; bryggbyggare buyers with zero leads. Unrouted masters (no market, or all bad) still need a card so Anton can see them.
7. **Sauna directories have no stored customer leads.** Only claims and click stats.
8. **Husbesiktning has no current recipient.** Cards should show “unrented / no client” rather than inventing a buyer.
9. **iOS payload is last 90 days only** and caps at 365. Full history is ~15k rows; the phone app must stay windowed and paginated, not load everything.
10. **Legacy Notion lead PATCH** is a trap and a secret-hygiene issue (see 1.2).

---

## 4. Implementation spec

### 4.1 Data: a view, not a second leads table

Keep `lg_leads` as the write target for new exclusive and directory submissions. **Do not** copy every row into a new `lg_leads` table.

Add two Postgres views in project `nfoawkvgnbdckcllopus` (names can vary; keep this shape):

#### `lg_lead_cards`

One row per homeowner request.

Include:

- Exclusive/call/form rows: `lg_leads` where `source <> 'directory-form'`.
- Directory masters only: `lg_leads` where `source = 'directory-form'` and `client_id is null` (the 40-character `dir_*` id).  
  **Exclude** per-buyer clones (`raw_data ? 'routed_from'` or `client_id is not null` on a directory-form row). Those clones stay in `lg_leads` for billing and the client portal, but they are not their own cards.

Suggested columns:

- `card_id` — `lg_leads.id` of the master/exclusive row (stable UUID).
- `kind` — `exclusive` \| `marketplace` \| `unrouted` (directory master with no market / no routes).
- `source`, `domain`, `site_name`, `vertical` (from `raw_data.vertical` or domain map).
- `submitted_at`, `is_test`, `is_duplicate`, `bad_lead`.
- `client_id` / `client_name` — only for exclusive leads. Null on marketplace masters.
- CRM: `lead_status`, `won_completion`, `won_value_sek`, `follow_up_date`, `notes` (exclusive / clone CRM stays on the owner’s row; for a marketplace card, CRM on the master is admin-side).
- Display fields: `name`, `phone`, `email`, `message` (contact is stripped in non-admin APIs; see 4.5).
- `service` — `raw_data.service` or `raw_data.jobb_label` / `jobb`.
- `location` — `raw_data.city` / `kommun` / `lan` / Telavox caller city.
- `description` — `message` plus a short teaser of calculator fields (size, timing, budget) without dumping the whole jsonb.
- `market_status` — `td_lead_market.status` or `none`.
- `slots` — `{ max, won, offered, queued }`.
- `price_sek` — marketplace list price shown to buyers, or exclusive `lg_clients.billing_rate` when `per_lead`.
- `offered_count`, `accepted_count`, `billable_count`, `free_count`.
- `master_external_id` — for joins.

Default list filters should hide `is_duplicate` and `bad_lead` (same as today), with admin toggles to show them.

#### `lg_lead_recipients`

One row per company the card was sent, offered, routed, or delivered to.

Union of:

1. **Marketplace offers** from `td_lead_offers`, keyed by `master_external_id`. Map status to a UI status:

   | DB status | UI status |
   |---|---|
   | `queued`, `sending` | `queued` |
   | `offered` | `offered` (treat as sent; we do not have a reliable “viewed” flag today) |
   | `won` | `accepted` |
   | `late` | `late` |
   | `expired`, `released` | `expired` / `released` |
   | `cancelled` | `declined` or `cancelled` (cancelled is usually “market closed / slot gone”, not an explicit no) |
   | `failed` | `failed` |

   Include `company_name`, `company_slug`, `client_id`, `email` (admin only), `price_shown`, `billable`, `free_n`, `tier`, and timestamps (`offered_at`, `accepted_at`, `delivered_at`, `expired_at`, `released_at`, `contacted_at`, `send_after`).

2. **Routes without an offer** from `td_lead_routes` (left join where `offer_id` is null or the offer row is missing). UI status from `email_status` / `void_reason`: `sent`, `pending`, `skipped`, `voided`.

3. **Exclusive synthetic recipient** — for `kind = exclusive` and a non-null `client_id` (and not `orphaned` / `personal` unless we want those labelled). One row: company = `lg_clients.name`, status `delivered` (automatic), `price_shown` = billing rate when per-lead, `billable` = existing `isQualifiedBillableLead` rules, `free` = `raw_data.free_lead`. Timestamp = `submitted_at` (we do not have a real send time). If `client_id` is `orphaned` or null, omit the recipient and set the card to `unassigned`.

Optional follow-up (not required for v1): a write table `lg_lead_events` (`card_id`, `recipient_id`, `event`, `at`, `meta`) so future Resend/Gmail sends can record `sent` / `bounced` / `viewed`. Do not invent historical opens.

### 4.2 API

Keep admin cookie auth for `/api/leads*` and `/api/admin/*`, and bearer auth for `/api/m/*`. Client session for `/api/client/*`.

**List (admin + iOS)**

- Extend `GET /api/m/leads` and `GET /api/leads` to read `lg_lead_cards` (not raw clones).
- Query params: `days` or `date_from`/`date_to`, `site`/`domain`, `vertical`, `source`, `status` (market or CRM; document both), `client`, `q` (search name/phone/email/site/kommun — admin only for contact), `tests`, `include_bad`, `include_duplicates`, `page` / `cursor`, `per_page`.
- iOS must use **cursor pagination**. Default window 90 days, max 365 per request. Do not return 15k rows.
- Each list item: card fields above, plus a compact `recipients_summary`: `{ accepted: [{ name, at, price_sek, billable, free }], offered, queued, declined }` and counts. No contact in the list payload if we can avoid it; detail can include it for admin.
- Sort: `submitted_at` desc.

**Detail**

- `GET /api/m/leads/[id]` and `GET /api/leads/[id]` (new; do not reuse the Notion PATCH path).
- Full card + `recipients[]` timeline (sorted by `send_after` / `offered_at` / `accepted_at`) + teaser fields from `raw_data` + CRM + billed/free explanation.
- Admin only: `name`, `phone`, `email`, full `message`, recipient emails.

**Writes** stay on existing admin CRM/flag endpoints, always against the underlying `lg_leads.id` (the card id). Do not let a CRM patch rewrite marketplace offer rows.

### 4.3 Web Leads page

Keep `/leads` as the admin page. Change the row model to `lg_lead_cards`.

- Card/row: date, site, service, location, source icon, market or CRM status, recipient chips (“3 offered · 1 accepted · 2 queued”), price, billed/free mark, test/junk flags.
- Filters: site (include trade domains, even though they are not in `lg_sites` — add a small site directory or union distinct lead domains + `lg_sites`), vertical, status, date, search.
- Detail drawer: description, calculator teaser, **recipient timeline** (company, status, price, billed/free, timestamps). Admin contact block.
- Marketplace cards should not be editable as if they belonged to one client. Exclusive cards keep today’s CRM editor.
- Unrouted / unrented cards are first-class (husbesiktning, hyrkranbil with no buyers, bad masters if include_bad is on).

Add the 8 trade domains to the site filter even though they are missing from `lg_sites`. (Optional later: register them in `lg_sites` as `status=directory`, no exclusive client.)

### 4.4 Native iOS Leads tab (world-class polish)

Stay in `leadgen-admin-ios`. Do not wrap the web page.

**List**

- Keep day sections, search, pull-to-refresh, swipe-to-call (only when the admin is allowed to see the phone), cached last response.
- New card treatment: site + location as the subtitle; a recipient bar (e.g. “Komfortvärme accepted · 2 offered”); price and billed/free; status pill (`Open`, `Filled`, `Unrouted`, `Exclusive`, CRM status for exclusive).
- Filters (all visible): site, status (open / filled / unrouted / exclusive / accepted / junk), date range (7 / 30 / 90 / 365), vertical or source, search. Persist the last filter in `SceneStorage` or equivalent.
- Haptics: keep selection + successful refresh; add a light impact when a filter chip is chosen and a success haptic when pull-to-refresh finishes with new leads.
- Pagination: when the user scrolls near the end of the window, fetch the next cursor. Changing days should refetch, with a skeleton that matches the card layout (already has `SkeletonRows`).
- Empty states: distinguish “no leads in this filter” from “marketplace lead still queued”.

**Detail**

- Hero: service, site, location, when.
- Recipient timeline (vertical): queued → offered → accepted / expired / released / cancelled, each with company name, price, billed or free (and free-trial number), and relative time. Accepted rows get a checkmark and a slightly stronger haptic when the screen appears only if something was accepted in the last day (do not buzz on every historic accept).
- Admin contact section (name, phone, email, message) behind the existing copy actions.
- Exclusive leads: one “Delivered to {client}” row, plus today’s CRM fields (read-only in v1 is acceptable; write can stay on the web if we want a smaller first ship).
- Map card stays when a kommun/city exists.

**Today tab:** count unique cards, not clones. Accepted-today can be a small badge on the Leads tab.

### 4.5 Client-restricted view

Portal (`/client/leads` + `/api/client/leads`) — and any future client app — must use the same card model with a hard scope.

- **Exclusive clients:** cards where `lg_leads.client_id = session.client_id` (current behaviour). Full contact is visible. Recipients list is only themselves (or omit it).
- **Trade buyers:** cards where they have a `td_lead_offers` or `td_lead_routes` or a clone row.  
  - If status is not `accepted`/`won`/`delivered`: show teaser only (kommun, job type, timing, price, slots left). **Never** name, phone, email, or free-text message that contains contact.  
  - If accepted: show contact and the fact that they accepted, not the other companies’ contact, and not a full competing-offer roster beyond “N other firms were also offered” if we want to be conservative.  
  - Price, billed/free, and free-trial index are visible for their own offer.
- Never list another client’s exclusive leads. Never list husbesiktning/orphaned inventory to a random buyer.
- Admin preview (`/api/admin/preview-client`) must obey the same stripping.

### 4.6 Backfill plan

v1 of the views needs **no data copy** for anything already in `lg_leads` / `td_lead_*`. Ship the views, point the APIs at them, and the last 14 months of custom forms plus all trade leads appear immediately, with recipients for market leads.

Then, only with Anton’s approval, in this order:

1. **Register trade domains** in the site filter / optionally `lg_sites`, so Sites and Leads agree.
2. **Fix live marketplace holes** (product, not just UI): arborist offers not written; decide what to do with unrouted hyrkranbil and dranering leads. Out of scope for the view itself, but the UI should make these visible.
3. **Backfill `domain` (and service/city when possible)** on Typeform/Jotform rows from `lg_form_mappings`, `raw` leftovers, and the email harvest. Write to `lg_leads.domain` / `raw_data` only after a dry-run count.
4. **Email-only history (the real gap):**  
   - Source: antonzarwel@gmail.com lead notifications (Typeform from Apr 2020, HubSpot mid-2020–2024, Jotform from mid-2022, “Nytt lead” custom forms from Mar 2026). Work already started in `/workspace/leadgen-revenue/email-leads` (2,130 deduped messages in the comparison months alone; harvest of the peak months is still incomplete).  
   - Insert missing leads as `source=typeform|jotform|hubspot|custom_form` with `raw_data` flags `backfilled_from=gmail`, message id, and no double-insert when an `external_id` or close fingerprint already exists.  
   - Exclude Bastuexperten / Saunify forms.  
   - Do not mark them billed. `client_id` from mapping or `orphaned`.
5. **Exclusive recipient history:** after (4), synthetic “delivered to {client}” is enough. Do not pretend we have accept/decline. Optional: parse the notification’s To: line (Anton + client) into `lg_lead_events` as `sent`.
6. **Do not** import saunify-prod `leads`, `bastur_claims`, or Bastuexperten orders.
7. **Sauna directory visitor inquiries** stay a product decision: either add a quote form that writes `lg_leads`, or keep showing “no stored leads, only clicks”.

### 4.7 Suggested ship order

1. SQL views + admin list/detail API + web page recipient timeline (read-only).  
2. iOS models, card list, filters, detail timeline, pagination, haptics.  
3. Client portal scoping and contact stripping for trade offers.  
4. Domain/email backfill behind an approval card.  
5. Optional `lg_lead_events` for new sends.

### 4.8 Privacy and safety

- Never log or display secrets (Supabase service role, Resend, Notion, admin password, Gmail tokens).
- Contact is admin-only except for the client who owns an exclusive lead or has accepted a marketplace lead.
- The iPhone app is an admin surface; treat lost-device risk seriously (already: Keychain, Face ID, app-switcher cover). Do not add a “share lead” action that includes contact.
- Do not change billing rules in this project (`free_lead`, `bad_lead`, `is_duplicate`, `isQualifiedBillableLead` stay as they are).

---

## 5. Repos and follow-up

- Spec path: `/workspace/leadgen-admin-leads-spec.md`
- Web/API work: `antonzarwel/leadgen-admin`
- iOS work: `antonzarwel/leadgen-admin-ios`
- Trade ingest (already writing `lg_leads` + `td_lead_*`): `trade-directory` (`/workspace/trade-directory`)
- WordPress ingest: `claudeclaw/scripts/leadgen-rebuild/lead-submit.php`
- Email harvest notes: `/workspace/leadgen-revenue/email-leads`

This document does not approve implementation, outreach, or any email import. Implementation should start only after Anton (or the parent agent with his approval) says to build it.

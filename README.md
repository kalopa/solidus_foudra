# Foudra MRP integration with Solidus

Connects a [Solidus](https://solidus.io) shop to [Foudra MRP](https://foudra.com).
The shop sells; Foudra makes, stocks and ships.

| Direction | What | How |
|---|---|---|
| Solidus → Foudra | A completed order becomes a Foudra **sales order** on the shop's channel, with its **customer** (found by the shop's user id or email, or created). Cancelling the order cancels it in Foudra. | `order_finalized` / `order_canceled` on `Spree::Bus` → ActiveJob |
| Foudra → Solidus | **Stock**: each variant's count on hand is Foudra's *available* quantity for its part. | `stock.changed`, `sales_order.created`/`.cancelled` webhooks, nightly pass |
| Foudra → Solidus | **Products and prices**: each part listed on the channel is a product; its price is the listing's; unlisted means discontinued. | `listing.changed` webhook, nightly pass, `rake solidus_foudra:import` |
| Foudra → Solidus | **Shipping**: a Foudra shipment that has left ships the Solidus units, with its tracking number, so Solidus emails the customer as usual. | `shipment.shipped` / `shipment.updated` webhooks, nightly pass |

## Who owns what

Foudra's rule: **Foudra owns the physical facts, never money.** So:

- **Foudra owns** stock, what is listed for sale, and shipping. The shop shows
  Foudra's available stock, never its own idea of it, and ships what Foudra
  says left. Don't ship in the Solidus admin: Foudra wouldn't know.
- **Solidus owns** the storefront, the checkout, payments, tax, promotions and
  customers' accounts. Prices on a Foudra sales order are information (what the
  customer was charged per unit, before order-level promotions), never booked.
- **Prices** flow from Foudra's listing to the shop because that is where they
  are kept, but the shop still charges.
- **Content** (name, description, image) is Foudra's when a product is created,
  and the shop's afterwards, unless `sync_content = true`.
- **Nothing is deleted.** Unlisting a part in Foudra discontinues the product;
  cancelling an order in Solidus cancels what hasn't shipped in Foudra.

## Installing

```ruby
# Gemfile
gem "solidus_foudra"
```

```sh
bundle install
bin/rails generate solidus_foudra:install   # initializer, migrations, route
```

The generator:

- writes `config/initializers/solidus_foudra.rb`;
- adds `mount SolidusFoudra::Engine, at: "/foudra"` to `config/routes.rb`, so
  the webhook is `POST https://<your shop>/foudra/webhooks`;
- copies two migrations: `solidus_foudra_webhook_events` (de-duplication) and
  `spree_variants.foudra_part_number`, `spree_orders.foudra_customer_id`,
  `spree_orders.foudra_sales_order_id`.

Jobs run on your ActiveJob adapter (Sidekiq, Resque, …). Run the nightly pass
from cron (or a Kubernetes CronJob): `bin/rails solidus_foudra:sync`, or
schedule `SolidusFoudra::FullSyncJob` with your job scheduler.

## Configuration

```ruby
SolidusFoudra.configure do |config|
  config.base_url = "https://acme.foudra.com"          # the company's own subdomain
  config.api_key = ENV["FOUDRA_API_KEY"]               # never commit it
  config.webhook_secret = ENV["FOUDRA_WEBHOOK_SECRET"] # never commit it
  config.channel = "SHOP"                              # the Foudra channel that is this shop
  config.stock_location = nil                          # a stock location's name or id; nil = the default
  config.part_number_column = :foudra_part_number      # the spree_variants column with the part number
  config.sync_content = false                          # true: Foudra's name/description/image always win
  config.send_orders_since = nil                       # nightly re-send of missed orders; set to go-live time
  config.wanted_after_days = 0                         # sales order wanted date = order date + this
  config.queue = :default                              # ActiveJob queue
  config.markdown_renderer = nil                       # optional ->(markdown) { html }
end
```

Nothing is sent or synced until `base_url`, `api_key` and `channel` are set.
The key and secret come from the environment or `Rails.application.credentials`
(`foudra.api_key`, `foudra.webhook_secret`).

**The part number** joins a variant to a Foudra part. It is Foudra's canonical
dashed number (`902-40169-00`), kept in `part_number_column`, and need not be
the SKU. A variant without one is the shop's own business: its lines are left
off Foudra's sales orders and its stock isn't touched.

### Kalopa's shop

```ruby
SolidusFoudra.configure do |config|
  config.base_url = "https://kalopa.foudra.com"
  config.api_key = Rails.application.credentials.dig(:foudra, :api_key)
  config.webhook_secret = Rails.application.credentials.dig(:foudra, :webhook_secret)
  config.channel = "SHOP"                    # whatever code the shop's channel has in Foudra
  config.part_number_column = :stock_code    # KRT-XL's stock_code is 902-40169-00
  config.send_orders_since = Time.zone.parse("<go-live time>")
end
```

- Its prices are Irish gross (`admin_vat_country_iso = "IE"`) with
  `Kalopa::FlatGrossVatPriceGenerator` deriving the other countries' prices:
  the listing price in Foudra must be the gross EUR price. The gem sets the
  default price and asks Solidus to rebuild the VAT prices from it.
- The unit prices it sends to Foudra are the line items' prices, VAT included.
- **Switch off kalsync's Solidus routines** (`solidus_orders_to_foudra`,
  `foudra_stock_to_solidus`) when this goes live. Both would otherwise raise
  the same orders as demand a second time and fight over stock counts. Set
  `send_orders_since` to after kalsync's last run so the nightly pass doesn't
  re-send orders kalsync already raised.
- Rack::Attack: make sure `/foudra/webhooks` isn't throttled.

## What Foudra must have

1. **A channel** for the shop (Foudra → Sales channels), its code in `config.channel`.
2. **An API key** (Foudra → API keys) with the **write** scope, made by a user
   who is at least a **planner** (customers and sales orders need it).
3. **A webhook** (Foudra → Webhooks, admins):
   - URL: `https://<your shop>/foudra/webhooks`
   - Events: `stock.changed`, `sales_order.created`, `sales_order.cancelled`,
     `shipment.shipped`, `shipment.updated`, `listing.changed`.
   - Copy the signing secret shown once into `webhook_secret`.
   - **Send test** should answer 204 (a `ping`; nothing is done with it).
4. **Listings**: each part the shop sells, listed on the channel with a price
   (the part's Listings page, or `PUT /api/channels/{code}/listings/{part}`).

Check it all with `bin/rails solidus_foudra:status`.

## How it works

### Orders in

`order_finalized` queues `SendOrderJob`, which:

1. waits (retries) until the order is committed as complete;
2. builds a line per line item whose variant has a part number, naming the
   part by `part_number` (Foudra resolves it; an unknown one refuses the order
   with 422, logged);
3. finds the customer: a signed-in shopper by their Spree user id, which
   Foudra keeps as the customer's ref on the channel
   (`GET /api/customers?channel=&channel_ref=`), then anyone by the order's
   email (`GET /api/customers?email=`, adding the user id to a customer found
   that way); else creates one with the bill-to name, phone, addresses and the
   user id as its channel ref. An existing customer's details are never changed;
4. `POST /api/sales-orders` with `channel`, `channel_order_ref` = the order
   number (Foudra makes one order per pair, so a repeat is harmless),
   `customer_reference` = the order number, ship-to from the ship address,
   the order date as ordered and wanted date, the currency and unit prices;
5. remembers the Foudra customer and sales order ids on `spree_orders`.

`order_canceled` queues `CancelOrderJob`: `POST /api/sales-orders/{id}/cancel`.
Foudra cancels what hasn't shipped; an order that has all shipped is left
(409, logged).

Every write carries an `Idempotency-Key` (`solidus_foudra:order:<number>`,
`solidus_foudra:cancel:<number>`, `solidus_foudra:customer:<digest of the body>`:
Foudra refuses one key with two different bodies, so a customer's key changes
with their details).

### Webhooks

`POST /foudra/webhooks` checks `X-Foudra-Signature` (`t=<unix>,v1=<hex
HMAC-SHA256 of "<t>.<body>">`, keyed with the signing secret, over the raw
body; constant-time compare; `t` within 5 minutes), records the event id
(a repeat is answered 204 and dropped), queues a job with **only the ids** the
event names, and answers 204. The job re-fetches everything from the API: an
event is a nudge, never data.

| Event | Does |
|---|---|
| `stock.changed` | Re-fetch the part, set the stock |
| `sales_order.created`, `.cancelled` | Re-fetch each line's part, set the stock (committed stock moved) |
| `listing.changed` (on our channel) | Re-fetch that part's listing (`?part_id=`) and the part, create/update/discontinue the product |
| `shipment.shipped`, `.updated` | Re-fetch the shipment and its sales order, ship the Solidus units or correct the tracking |
| `ping`, anything else | Nothing |

### Stock

Available = Foudra's on hand less what open orders commit, rounded down, never
below zero, set as the count on hand at the configured stock location
(`StockItem#set_count_on_hand`, which also fills backorders). Variants that
don't track inventory are left alone.

### Products

For each listing on the channel:

- **Listed, no variant with its number**: a new product (master only), SKU =
  the part number, name, description (Foudra's Markdown rendered to HTML), the
  part's own first image (never its category's), price = the listing's,
  available now. Not created without a price in the shop's currency, nor when
  a deleted variant had that number, nor when another variant has that SKU.
- **Listed, a variant has its number**: adopted. Price set (in the shop's
  currency, the default price and its VAT prices; in another currency, a price
  in that currency), discontinuation cleared; name, description and image only
  with `sync_content`.
- **Unlisted, or the part archived** (`part_is_active` false): the product is
  discontinued, unless another of its variants is still listed (Solidus
  discontinues products, not variants: logged).
- The shop's SKU is written back as the listing's `channel_part_number`, so
  Foudra shows the listing as pushed.

### Shipping

A shipped Foudra shipment on this channel ships, in the Solidus order whose
number is its `channel_order_ref`, as many not-yet-shipped units of each line's
part as Foudra shipped, through `Spree::OrderShipping#ship`: one carton per
Solidus shipment, `external_number` = the Foudra shipment's number, `tracking`
= its tracking number. Solidus then sends its shipped email. A repeat finds the
carton by `external_number` and only corrects the tracking (no second email).
Units Solidus still has as backordered wait for the stock update first.

### The nightly pass

`rake solidus_foudra:sync` (or `FullSyncJob`): products, stock (every part, 100
a page), shipments of sent orders not yet shipped here (last 60 days), orders
since `send_orders_since` that never reached Foudra, and pruning de-duplication
rows older than 30 days. Each step is independent.

### Failures

Foudra being busy or down (429, 5xx, network) is retried three times in the
request, then by ActiveJob with growing pauses for about two and a half hours.
A refusal (401/402/403, 422, an unknown part number) is logged and dropped:
retrying won't fix it. Logs never contain the API key or a customer's email or
address.

## Rake tasks

| Task | Does |
|---|---|
| `solidus_foudra:status` | Shows the configuration (not the secrets) and checks the channel and listings |
| `solidus_foudra:import` | First import: products for every listing, then stock |
| `solidus_foudra:sync` | The nightly pass |

## Needs from Foudra

Delivered by Foudra on 2026-11-23 and used: `listing.changed`, `part_number`
on sales order lines, `GET /api/parts?part_number=`, one listing by
`?part_id=` (with `part_is_active`), and customers' ids in channels.
Foudra's [shops contract](https://foudra.com/developers/shops) describes them.

Still open:

- **Available stock per channel.** `available` on a part counts every one of
  Foudra's locations; a figure counting only the locations that stock the shop
  waits on an owner decision in Foudra's plan.
- **No event when committed stock changes on an edited order line**
  (`PUT /api/sales-orders/{id}/lines/{line}`): the shop's figure catches up at
  the nightly pass. `sales_order.created` and `.cancelled` are used as nudges.

## Development

```sh
source ~/.rvm/scripts/rvm && rvm use 3.2.3
bundle config set --local path vendor/bundle
bundle install
bin/rake extension:test_app     # builds spec/dummy (SQLite)
bundle exec rspec
bundle exec rubocop
```

## Licence

Copyright (c) 2026, Kalopa Robotics Limited.

Licensed under the [Apache License, Version 2.0](LICENSE). You may not use this
gem except in compliance with the License. Unless required by applicable law or
agreed to in writing, software distributed under the License is distributed on
an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
or implied. See the License for the specific language governing permissions and
limitations under the License.

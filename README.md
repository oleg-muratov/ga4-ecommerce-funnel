# GA4 e-commerce funnel: Google Merchandise Store

Funnel and channel analysis of the public Google Analytics 4 export of the Google Merchandise Store
(November 1, 2020 – January 31, 2021), built in BigQuery SQL and Python. Work in progress.

## What the data can and cannot show

The data are Google's public, obfuscated sample of the store's GA4 export: 4,295,584 events over 92 days,
grouped here into 360,129 visits. Before measuring the funnel, the export was checked for what it can be
trusted for. Each point below gives the problem, its size, and what the analysis does about it.
The queries and their results are in `sql/04_quality_checks.sql` and `sql/02_sessions_checks.sql`.

1. **It is a scrambled sample, not the store's real data.** Google replaces some values with placeholders
   (`<Other>`, `(data deleted)`) and does not guarantee internal consistency. On December 1, 10% of visits
   have a traffic source that cannot be identified. Results describe this sample, not the store's business.

2. **Some funnel steps were not tracked every day.** Product views, checkout, shipping, payment and purchase
   are recorded on all 92 days. Add-to-cart is missing on 18 days (November 2–15 and 21–24) and only partly
   recorded on November 16–20; product selection is recorded only from November 23; product-list views appear
   on 33 scattered days. The funnel therefore starts at the product view, and any rate involving add-to-cart
   uses November 25 – January 31 only (68 days).

3. **The store is recorded as its own traffic source.** Of the 1,428,080 events that carry a traffic source,
   756,057 (52.9%) name the store's own domain, a tracking set-up problem known as self-referral. These are
   treated as missing: a visit's channel is its first recorded source that is not the store itself. Visits
   with no other source count as Direct, so Direct (51% of visits on December 1) is overstated.

4. **Visits are rebuilt from events.** GA4 session IDs repeat across visitors, so a visit is a visitor ID plus
   a session ID, and visits that cross midnight (UTC) are joined across the daily tables. Every event falls
   in exactly one visit, and no visit spans two devices or two countries. 5,272 visits (1.5%) have no
   session-start event: about 1.2% on most days, with spikes on November 24–26, December 10–11 and
   January 27–28 that mark days with tracking problems. Counting session-start events would understate visits.

5. **Purchase events overcount purchases.** Of 5,692 purchase events, 906 (15.9%) have no transaction ID, and
   320 reuse an ID already recorded. In the most-repeated IDs, every repeat comes from the same visitor: the
   same purchase was recorded two to four times. The funnel therefore counts visits with a purchase, not
   purchase events, and revenue is not analysed.

6. **Some steps are recorded several times within one visit.** On December 1, checkout was recorded about
   3.2 times per visit that reached it, and shipping details about 1.7 times. Event counts suggest a large
   drop-off between the two steps; per visit there is none (229 visits reached both). All funnel rates are
   therefore measured per visit.

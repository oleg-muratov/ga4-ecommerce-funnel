-- 04_quality_checks.sql
-- Day 3: what the data can and cannot be trusted for.
-- Source: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*  (Nov 1, 2020 – Jan 31, 2021; 92 days)

-- A. Coverage: on how many days is each funnel event recorded?
--    Dry run: This query will process 94.33 MB when run.
--    Result: view_item, begin_checkout, add_shipping_info, add_payment_info, purchase: all 92 days.
--            add_to_cart: 74 days (missing Nov 2-15 and Nov 21-24; Nov 16-20 only partly recorded).
--            select_item: 70 days (from Nov 23, then every day). view_item_list: 33 scattered days.
--            -> the funnel starts at view_item; rates using add_to_cart only from Nov 25 to Jan 31 (68 days).
--            "Days present" = at least one event that day, so partly recorded days still count.
SELECT
  event_name,
  MIN(event_date) AS earliest_date,
  MAX(event_date) AS latest_date,
  COUNT(DISTINCT event_date) AS n_dates
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name IN (
  'view_item_list', 'select_item', 'view_item', 'add_to_cart',
  'begin_checkout', 'add_shipping_info', 'add_payment_info', 'purchase'
)
GROUP BY event_name;


-- B. Purchases vs transaction IDs: does every purchase event carry its own ID?

-- B1. Purchase events, missing IDs and distinct IDs (all 92 days).
--    Dry run: 1.22 GB (event_params is read for every event; the WHERE does not reduce bytes).
--    Result: 5,692 purchase events; 906 (15.9%) have no transaction_id; the other 4,786 carry only
--            4,466 distinct IDs -> 320 purchase events (6.7% of those with an ID) reuse an ID.

WITH purchases AS (
  SELECT
    e.user_pseudo_id,
    e.event_name,
    e.event_timestamp,
    (SELECT ep.value.string_value
   FROM UNNEST(e.event_params) AS ep
   WHERE ep.key = 'transaction_id') AS transaction_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
  WHERE e.event_name = 'purchase'
)

  SELECT COUNT(*) as n_purchases, COUNTIF(transaction_id IS NULL) AS missing_ids, COUNT(DISTINCT transaction_id) AS distinct_ids
  FROM purchases
;

-- B2. Which IDs repeat, and is each repeated ID one person or several?
--    Dry run: 1.22 GB.
--    Result: no placeholder value; repeats are spread over many IDs, mostly 2 per ID, at most 4.
--            In the 20 most-repeated IDs every ID belongs to a single user -> the same purchase was recorded
--            more than once (e.g. a reloaded confirmation page), not scrambled IDs shared between visitors.
--            -> purchase events overcount purchases, and revenue summed over events would double-count;
--               the funnel counts visits with a purchase, and revenue is left out.

WITH purchases AS (
  SELECT
    e.user_pseudo_id,
    e.event_name,
    e.event_timestamp,
    (SELECT ep.value.string_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'transaction_id') AS transaction_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
  WHERE e.event_name = 'purchase'
)

SELECT transaction_id, COUNT(*) AS n_purchases, COUNT(DISTINCT user_pseudo_id) AS n_users
FROM purchases
WHERE transaction_id IS NOT NULL
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY n_purchases DESC
LIMIT 20;

-- C. Self-referrals: how often is the store's own domain recorded as the traffic source? (all 92 days)
--    Dry run: not recorded; about 1.1 GB (event_params for every event, as in B, without B's three smaller columns).
--    Result: 1,428,080 events carry a source (33% of all 4,295,584 events); 756,057 of them name the store's own
--            domain (shop.googlemerchandisestore.com / googlemerchandisestore.com) -> 52.9% self-referral
--            (Dec 1 alone: 54%). The full-period share matches one day's, so it is not a one-day glitch; it points to the
--            tracking set-up (week-by-week stability not checked).
--            -> self-referrals are treated as missing attribution; visits with no other source count as Direct,
--               which is why Direct is about half of all visits.

WITH event_sources AS (
  SELECT
    (SELECT ep.value.string_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'source') AS source
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
)

SELECT
  COUNTIF(source IS NOT NULL) AS n_events_with_source,
  COUNTIF(source LIKE '%googlemerchandisestore.com') AS self_referral_events,
  SAFE_DIVIDE(COUNTIF(source LIKE '%googlemerchandisestore.com'),
              COUNTIF(source IS NOT NULL)) AS self_ref_share
FROM event_sources;

-- D. Visits without a session_start event, by visit date (all 92 days).
--    Uses the events and visits steps of 02_sessions.sql plus one flag, has_session_start.
--    Dry run: 1.5 GB, the same as 02_sessions.sql (it reads the same columns of the same tables).
--    Result: 360,129 visits; 5,272 (1.5%) have no session_start (02 check 1 found at least 5,159; the other 113
--            are hidden there by visits that record two session_start events).
--            Most days: about 1.2% (median 43 visits a day), a steady trickle.
--            Spikes on consecutive days: Nov 24-26 (253, 312, 119), Dec 10-11 (235, 131), Jan 27-28 (328, 160);
--            smaller on Jan 13 (93) and Jan 30-31 (93, 83). Nov 1 is normal (31).
--            Nov 24-26 coincides with other tracking changes (A: add_to_cart back from Nov 25, select_item from
--            Nov 23). Dec 10-11 and Jan 27-28 are unexplained.
--            -> these visits have real events and are kept; session_start counts understate visits by about 1.5%,
--               and the spike dates mark days with tracking problems.

WITH events AS (
  SELECT
    e.user_pseudo_id,
    e.event_name,
    e.event_timestamp,
    (SELECT ep.value.int_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'ga_session_id') AS session_id,
    (SELECT ep.value.string_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'source') AS source,
    (SELECT ep.value.string_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'medium') AS medium,
    e.device.category AS device_category,
    e.geo.country AS country
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
),

visits AS (
  SELECT
    user_pseudo_id,
    session_id,
    TIMESTAMP_MICROS(MIN(event_timestamp)) AS visit_start,
    ANY_VALUE(device_category) AS device_category,
    COUNT(*) AS n_events,
    COUNT(DISTINCT device_category) AS n_devices,
    ANY_VALUE(country) AS country,
    COUNT(DISTINCT country) AS n_countries,
    ARRAY_AGG(
      CASE
        WHEN source IS NULL
          OR source LIKE '%googlemerchandisestore.com'
          OR source = '' THEN NULL
        ELSE CONCAT(source, ' / ', medium)
      END
      IGNORE NULLS ORDER BY event_timestamp LIMIT 1
    )[SAFE_OFFSET(0)] AS source_medium,
    LOGICAL_OR(event_name = 'view_item') AS has_view_item,
    LOGICAL_OR(event_name = 'add_to_cart') AS has_add_to_cart,
    LOGICAL_OR(event_name = 'begin_checkout') AS has_begin_checkout,
    LOGICAL_OR(event_name = 'add_shipping_info') AS has_add_shipping_info,
    LOGICAL_OR(event_name = 'add_payment_info') AS has_add_payment_info,
    LOGICAL_OR(event_name = 'purchase') AS has_purchase,
    LOGICAL_OR(event_name = 'session_start') AS has_session_start
  FROM events
  GROUP BY user_pseudo_id, session_id
)

SELECT
  COUNT(*) AS n_visits,
  DATE(visit_start) AS visit_start_date,
  COUNTIF(NOT has_session_start) AS n_visits_without_session_start
FROM visits
GROUP BY visit_start_date
ORDER BY visit_start_date;
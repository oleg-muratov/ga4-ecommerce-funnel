-- 01_events_overview.sql
-- Day 1: how the GA4 export is structured.
-- Source: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*  (Nov 1, 2020 – Jan 31, 2021)
-- Each query: one-line purpose, dry-run size, and what the result showed.

-- 1. Event names and how often each occurs (most frequent first).
--    Dry run: 53.36 MB
--    Result: 17 events; sums to 4,295,584; view_item_list 71 vs select_item 31,007.

SELECT event_name, COUNT(*) AS n_events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
GROUP BY event_name
ORDER BY n_events DESC;

-- 2. Funnel events per day; then the same for one week via _TABLE_SUFFIX (compare dry-run sizes).
--    Dry run: 94.33 MB (all 92 days); 9.77 MB with AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
--    Result: add_to_cart missing Nov 2-24 (partial Nov 16-20); select_item tracked from Nov 23;
--            view_item_list ~never; begin_checkout about 2-3x add_shipping_info from mid-Nov;
--            peak Dec 8-11; Cyber Monday (Nov 30) > Black Friday; trough Dec 24-Jan 3.

SELECT
  event_date,
  event_name,
  COUNT(*) AS n_events,
  CASE event_name
    WHEN 'view_item_list'    THEN 1
    WHEN 'select_item'       THEN 2
    WHEN 'view_item'         THEN 3
    WHEN 'add_to_cart'       THEN 4
    WHEN 'begin_checkout'    THEN 5
    WHEN 'add_shipping_info' THEN 6
    WHEN 'add_payment_info'  THEN 7
    WHEN 'purchase'          THEN 8
  END AS funnel_step
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE event_name IN (
  'view_item_list', 'select_item', 'view_item', 'add_to_cart',
  'begin_checkout', 'add_shipping_info', 'add_payment_info', 'purchase'
)
-- AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
GROUP BY event_date, event_name
ORDER BY event_date, funnel_step;

-- 3. What is inside event_params: keys, counts, and which value field is filled.
--    Dry run: 23.15 MB
--    Result: 33 keys on Dec 1; ga_session_id and page_location on all 71,804 events (= the day's total, query 4);
--            source/medium only on ~25k; transaction_id 97 vs 107 purchase events (query 2) -> ~10 purchases
--            without a transaction ID. Slots: ga_session_id int, page_location string; value/tax split int+double;
--            gclid/gclsrc/dclid/all_data always empty; page_referrer empty on 32,624 of 51,881.

SELECT
  ep.key,
  COUNT(*) AS n_events,
  COUNTIF(ep.value.string_value IS NOT NULL) AS n_string,
  COUNTIF(ep.value.int_value    IS NOT NULL) AS n_int,
  COUNTIF(ep.value.double_value IS NOT NULL) AS n_double,
  COUNTIF(ep.value.float_value  IS NOT NULL) AS n_float,
  COUNTIF(ep.value.string_value IS NULL
      AND ep.value.int_value    IS NULL
      AND ep.value.double_value IS NULL
      AND ep.value.float_value  IS NULL) AS n_empty
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e,
     UNNEST(e.event_params) AS ep
WHERE _TABLE_SUFFIX = '20201201'
GROUP BY ep.key
ORDER BY n_events DESC;

-- 4. ga_session_id and page_location for each event (one row per event).
--    Dry run: 26.69 MB
--    Result: without LIMIT, 71,804 rows = one per event (nothing multiplied); session_id and page_location
--            filled on every event. In the first ~90% of visitors (console CSV export was cut off at 65,405 rows):
--            113 session IDs shared by 2+ visitors -> a session = user_pseudo_id + session_id; 84 sessions have
--            no session_start (likely began the previous day); 94 of 4,525 sessions include a purchase.
--            Session IDs are scrambled (not start times). Several events share one timestamp.
--            Full day (02_sessions_checks.sql): 88 visits without session_start; 100 of 5,000 visits
--            include a purchase.

SELECT
  e.event_date,
  e.event_timestamp,
  e.event_name,
  e.user_pseudo_id,
  (SELECT ep.value.int_value
   FROM UNNEST(e.event_params) AS ep
   WHERE ep.key = 'ga_session_id') AS session_id,
  (SELECT ep.value.string_value
   FROM UNNEST(e.event_params) AS ep
   WHERE ep.key = 'page_location') AS page_location
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
WHERE _TABLE_SUFFIX = '20201201'
ORDER BY e.user_pseudo_id, e.event_timestamp
LIMIT 20;  -- remove LIMIT for the row-count check (expect 71,804)

-- 5. Does event_params carry source / medium? (decides the session channel)

-- 5a. Which event types carry a `source` parameter (Dec 1).
--     Dry run: (not recorded)
--     Result: 24,731 events, matching query 3. session_start and first_visit carry NONE; source rides on
--             browsing events: user_engagement 10,595, page_view 9,314, scroll 3,766, view_promotion 655,
--             view_item 187, begin_checkout 152, select_item 37, click 8, add_to_cart 7,
--             view_search_results 5, purchase 5.

SELECT
  e.event_name,
  COUNT(*) AS n_events_with_source
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e,
     UNNEST(e.event_params) AS ep
WHERE _TABLE_SUFFIX = '20201201'
  AND ep.key = 'source'
GROUP BY e.event_name
ORDER BY n_events_with_source DESC;

-- 5b. All events by type on Dec 1 (the denominators for 5a).
--     Dry run: (not recorded)
--     Result: 71,804 events (= query 4 row count). Share carrying a source: user_engagement 56%, scroll 44%,
--             page_view 43%, view_promotion 21%, begin_checkout 21%, purchase 5%, view_item 3%,
--             add_to_cart 0.4%, session_start 0% (4,912), first_visit 0% (3,303).
--             -> a session's channel must be gathered from its browsing events, not read off session_start.

SELECT
  event_name,
  COUNT(*) AS n_events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX = '20201201'
GROUP BY event_name
ORDER BY n_events DESC;

-- 5c. Source + medium combinations (Dec 1).
--     Dry run: (not recorded)
--     Result: 31 combinations, 25,016 events (= medium count, query 3). The store's own domain as referrer
--             (shop.googlemerchandisestore.com / googlemerchandisestore.com, referral) = 13,538 (54%): self-referral,
--             a tracking misconfiguration, not a real channel. Real channels: google/organic 4,306 (17%),
--             (direct)/(none) 2,408 (10%), google/cpc 433 (2%), email 17, affiliate 17, external referrals small.
--             Scrambled: <Other> and (data deleted) = 3,787 (15%). 285 events: medium 'organic' with no source.

WITH event_sources AS (
  SELECT
    (SELECT ep.value.string_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'source') AS source,
    (SELECT ep.value.string_value
     FROM UNNEST(e.event_params) AS ep
     WHERE ep.key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
  WHERE _TABLE_SUFFIX = '20201201'
)

SELECT source, medium, COUNT(*) AS n_events
FROM event_sources
WHERE source IS NOT NULL OR medium IS NOT NULL
GROUP BY source, medium
ORDER BY n_events DESC;

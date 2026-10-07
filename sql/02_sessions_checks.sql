-- 02_sessions_checks.sql
-- Checks on the visits table built in 02_sessions.sql.
-- To run a check: take 02_sessions.sql and replace its final SELECT with the check
-- (the events and visits steps stay the same). Results are for Dec 1, 2020 unless noted.

-- 1. Reconciliation: does grouping events into visits lose or duplicate any?
--    Result (Dec 1): 5,000 visits; 71,804 events (= the day's total); 0 visits with 2+ devices;
--            visit_start from 00:00:00.73 to 23:59:57.67 UTC -> the daily tables are cut at UTC midnight.
--            5,000 visits vs 4,912 session_start events -> 88 visits began the day before.
--    Result (all 92 days; dry run 1.5 GB): 360,129 visits; 4,295,584 events (= the full export); 0 visits with
--            2+ devices; 0 with 2+ countries; visit_start from 2020-11-01 00:00:04 to 2021-01-31 23:59:51 UTC.
--            360,129 visits vs 354,970 session_start events -> at least 5,159 visits (1.4%) have no
--            session_start even after visits crossing midnight are joined (audit, 04_quality_checks.sql).

SELECT
  COUNT(*) AS n_visits,
  SUM(n_events) AS total_events,
  COUNTIF(n_devices > 1) AS multi_device_visits,
  MIN(visit_start) AS earliest_visit_start,
  MAX(visit_start) AS latest_visit_start
FROM visits;

-- 2. Visits whose events carry more than one country.
--    Result (Dec 1): 0 -> one country per visit (ANY_VALUE) is safe. All 92 days: 0 (run with check 1).

SELECT COUNTIF(n_countries > 1) AS multi_country_visits
FROM visits;

-- 3. Visits per channel pair (source / medium); a visit with no genuine source -> (direct) / (none).
--    Result (Dec 1): 27 pairs, summing to 5,000; one Direct row; no googlemerchandisestore.com row.
--            Direct 2,573 (51%); google / organic 1,253; <Other> / <Other> 418; <Other> / referral 367;
--            google / cpc 121; (data deleted) 104; <Other> / organic 70; analytics.google.com / referral 39.

SELECT
  COALESCE(source_medium, '(direct) / (none)') AS channel_pair,
  COUNT(*) AS n_visits
FROM visits
GROUP BY channel_pair
ORDER BY n_visits DESC;

-- 4. Visits per channel group (the same CASE as medium_group in 02_sessions.sql).
--    Result (Dec 1): Direct 2,573; Organic Search 1,328; Unknown 522; Referral 446; Paid search 121;
--            Email 6; Affiliate 4. Sum 5,000; matches the pairs in check 3.

SELECT
  CASE
    WHEN source_medium IS NULL OR source_medium LIKE '%(direct) / (none)%' THEN 'Direct'
    WHEN source_medium LIKE '%organic' THEN 'Organic Search'
    WHEN source_medium LIKE '%cpc' THEN 'Paid search'
    WHEN source_medium LIKE '%referral' THEN 'Referral'
    WHEN source_medium LIKE '%email' THEN 'Email'
    WHEN source_medium LIKE '%affiliate' THEN 'Affiliate'
    ELSE 'Unknown'
  END AS medium_group,
  COUNT(*) AS n_visits
FROM visits
GROUP BY medium_group;

-- 5. Visits reaching each funnel step.
--    Result (Dec 1): view_item 1,265; add_to_cart 460; begin_checkout 229; add_shipping_info 229;
--            add_payment_info 145; purchase 100; all visits 5,000. Each is below that step's event count
--            (01_events_overview.sql, query 2: 6,976; 1,653; 732; 379; 270; 107).
--            begin_checkout fires about 3.2 times per checkout visit, add_shipping_info about 1.7
--            -> Day 1's 2-3x event gap is repeat firing, not more visitors starting checkout.
--            107 purchase events in 100 visits -> 7 extra purchase events (compare transaction_id,
--            01_events_overview.sql, query 3).

SELECT
  COUNTIF(has_view_item) AS n_view_item,
  COUNTIF(has_add_to_cart) AS n_add_to_cart,
  COUNTIF(has_begin_checkout) AS n_begin_checkout,
  COUNTIF(has_add_shipping_info) AS n_add_shipping_info,
  COUNTIF(has_add_payment_info) AS n_add_payment_info,
  COUNTIF(has_purchase) AS n_purchase,
  COUNT(*) AS n_visits
FROM visits;

-- 6. Nesting: later funnel steps without begin_checkout.
--    Result (Dec 1): 0 and 0. The 229 add_shipping_info visits are the same 229 begin_checkout visits,
--            and all 100 purchase visits began checkout.

SELECT
  COUNTIF(has_add_shipping_info AND NOT has_begin_checkout) AS shipping_without_checkout,
  COUNTIF(has_purchase AND NOT has_begin_checkout) AS purchase_without_checkout
FROM visits;

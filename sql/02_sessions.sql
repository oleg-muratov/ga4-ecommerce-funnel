-- 02_sessions.sql
-- One row per visit, built from the GA4 event export.
-- Source: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*  (Nov 1, 2020 – Jan 31, 2021)
--
-- A visit = user_pseudo_id + session_id (session IDs are shared across visitors, so both are needed).
-- Columns:
--   visit_start                  time of the visit's first event (UTC)
--   device_category, country     one value per visit; n_devices and n_countries confirm there is only one
--   n_events                     number of events in the visit
--   source_medium                first source / medium in the visit that is not missing, blank or the store's
--                                own domain (self-referral); NULL if there is none
--   has_view_item … has_purchase TRUE if the visit has at least one event of that step
--   medium_group                 channel grouped by medium: NULL or (direct) / (none) -> Direct;
--                                <Other> / <Other> and (data deleted) -> Unknown
--   visit_start_date             UTC date of visit_start (the daily tables are cut at UTC midnight)
--
-- Checks on this table: 02_sessions_checks.sql (each check replaces the final SELECT below).
-- Look: add LIMIT 20 at the end. Dec 1: all columns filled, all dates Dec 1; blank source_medium -> Direct;
--       the longest visit (98 events) has all six funnel flags TRUE.

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
  -- WHERE _TABLE_SUFFIX = '20201201'  -- one day while checking; remove for all 92 days
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
    LOGICAL_OR(event_name = 'purchase') AS has_purchase
  FROM events
  GROUP BY user_pseudo_id, session_id
)

SELECT
  *,
  CASE
    WHEN source_medium IS NULL OR source_medium LIKE '%(direct) / (none)%' THEN 'Direct'
    WHEN source_medium LIKE '%organic' THEN 'Organic Search'
    WHEN source_medium LIKE '%cpc' THEN 'Paid search'
    WHEN source_medium LIKE '%referral' THEN 'Referral'
    WHEN source_medium LIKE '%email' THEN 'Email'
    WHEN source_medium LIKE '%affiliate' THEN 'Affiliate'
    ELSE 'Unknown'
  END AS medium_group,
  DATE(visit_start) AS visit_start_date
FROM visits;

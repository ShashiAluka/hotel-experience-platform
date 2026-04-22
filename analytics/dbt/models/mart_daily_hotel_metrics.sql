-- models/marts/mart_daily_hotel_metrics.sql
-- Business-level daily metrics per hotel: occupancy, revenue, booking volume

{{ config(
    materialized='table',
    tags=['daily', 'hotel-metrics']
) }}

WITH confirmed_stays AS (
    SELECT
        hotel_id,
        check_in_date,
        check_out_date,
        total_amount,
        nights,
        reservation_id
    FROM {{ ref('stg_reservations') }}
    WHERE status IN ('CONFIRMED', 'CHECKED_IN', 'CHECKED_OUT')
),

date_spine AS (
    SELECT date_add('day', seq, DATE '2024-01-01') AS stay_date
    FROM (SELECT sequence(0, 730) AS s) CROSS JOIN UNNEST(s) AS t(seq)
),

-- Explode each reservation into individual night rows
nightly_stays AS (
    SELECT
        hotel_id,
        stay_date,
        total_amount / NULLIF(nights, 0) AS nightly_rate,
        reservation_id
    FROM confirmed_stays
    CROSS JOIN date_spine
    WHERE stay_date >= check_in_date
      AND stay_date <  check_out_date
),

daily_metrics AS (
    SELECT
        hotel_id,
        stay_date                       AS metric_date,
        COUNT(reservation_id)           AS occupied_rooms,
        SUM(nightly_rate)               AS daily_revenue,
        AVG(nightly_rate)               AS avg_nightly_rate
    FROM nightly_stays
    GROUP BY hotel_id, stay_date
),

-- Total hotel capacity (static seed, replace with actual capacity table)
hotel_capacity AS (
    SELECT hotel_id, capacity
    FROM (VALUES
        ('HYT-CHI-001', 180),
        ('HYT-NYC-002', 320),
        ('HYT-LAX-003', 240),
        ('HYT-MIA-004', 150)
    ) AS t(hotel_id, capacity)
)

SELECT
    dm.hotel_id,
    dm.metric_date,
    dm.occupied_rooms,
    hc.capacity                                             AS total_rooms,
    ROUND(dm.occupied_rooms * 100.0 / NULLIF(hc.capacity, 0), 2) AS occupancy_pct,
    ROUND(dm.daily_revenue, 2)                              AS daily_revenue,
    ROUND(dm.avg_nightly_rate, 2)                           AS avg_nightly_rate,
    -- RevPAR: Revenue Per Available Room
    ROUND(dm.daily_revenue / NULLIF(hc.capacity, 0), 2)    AS revpar,
    CURRENT_TIMESTAMP                                       AS dbt_updated_at
FROM daily_metrics dm
LEFT JOIN hotel_capacity hc USING (hotel_id)
ORDER BY dm.hotel_id, dm.metric_date DESC

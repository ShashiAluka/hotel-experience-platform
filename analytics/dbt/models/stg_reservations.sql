-- models/staging/stg_reservations.sql
-- Staging model: clean and type-cast raw reservation events from S3/Athena

{{ config(materialized='view') }}

SELECT
    JSON_EXTRACT_SCALAR(detail, '$.reservationId') AS reservation_id,
    JSON_EXTRACT_SCALAR(detail, '$.guestId')       AS guest_id,
    JSON_EXTRACT_SCALAR(detail, '$.hotelId')       AS hotel_id,
    JSON_EXTRACT_SCALAR(detail, '$.status')        AS status,
    CAST(JSON_EXTRACT_SCALAR(detail, '$.totalAmount') AS DECIMAL(10,2)) AS total_amount,
    DATE(JSON_EXTRACT_SCALAR(detail, '$.checkInDate'))  AS check_in_date,
    DATE(JSON_EXTRACT_SCALAR(detail, '$.checkOutDate')) AS check_out_date,
    DATE_DIFF(
        'day',
        DATE(JSON_EXTRACT_SCALAR(detail, '$.checkInDate')),
        DATE(JSON_EXTRACT_SCALAR(detail, '$.checkOutDate'))
    ) AS nights,
    CAST(JSON_EXTRACT_SCALAR(detail, '$.timestamp') AS TIMESTAMP) AS event_timestamp,
    "detail-type" AS event_type,
    year, month, day  -- Athena partition columns
FROM {{ source('raw', 'reservation_events') }}
WHERE JSON_EXTRACT_SCALAR(detail, '$.reservationId') IS NOT NULL

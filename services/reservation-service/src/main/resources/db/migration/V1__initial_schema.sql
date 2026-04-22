-- V1__initial_schema.sql
-- HXP Reservation Service — initial database schema

CREATE TABLE IF NOT EXISTS reservations (
    id                  VARCHAR(36)    PRIMARY KEY,
    guest_id            VARCHAR(36)    NOT NULL,
    hotel_id            VARCHAR(50)    NOT NULL,
    room_number         VARCHAR(10)    NOT NULL,
    room_type           VARCHAR(20)    NOT NULL CHECK (room_type IN ('STANDARD','DELUXE','SUITE','PRESIDENTIAL')),
    check_in_date       DATE           NOT NULL,
    check_out_date      DATE           NOT NULL,
    status              VARCHAR(20)    NOT NULL DEFAULT 'PENDING'
                                       CHECK (status IN ('PENDING','CONFIRMED','CHECKED_IN','CHECKED_OUT','CANCELLED','NO_SHOW')),
    total_amount        NUMERIC(10,2)  NOT NULL,
    currency            CHAR(3)        NOT NULL DEFAULT 'USD',
    special_requests    VARCHAR(1000),
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    confirmed_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    cancellation_reason VARCHAR(500),
    CONSTRAINT chk_dates CHECK (check_out_date > check_in_date),
    CONSTRAINT chk_amount CHECK (total_amount >= 0)
);

CREATE INDEX idx_reservations_guest_id    ON reservations(guest_id);
CREATE INDEX idx_reservations_hotel_dates ON reservations(hotel_id, check_in_date, check_out_date);
CREATE INDEX idx_reservations_status      ON reservations(status);
CREATE INDEX idx_reservations_created_at  ON reservations(created_at DESC);

-- Trigger: auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER reservations_updated_at
  BEFORE UPDATE ON reservations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

package com.hxp.reservation.model;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "reservations", indexes = {
    @Index(name = "idx_guest_id",    columnList = "guest_id"),
    @Index(name = "idx_hotel_dates", columnList = "hotel_id, check_in_date, check_out_date"),
    @Index(name = "idx_status",      columnList = "status")
})
@Getter @Setter @Builder @NoArgsConstructor @AllArgsConstructor
public class Reservation {

  @Id
  @Column(name = "id", updatable = false, nullable = false)
  private String id;

  @Column(name = "guest_id", nullable = false)
  private String guestId;

  @Column(name = "hotel_id", nullable = false)
  private String hotelId;

  @Column(name = "room_number", nullable = false, length = 10)
  private String roomNumber;

  @Enumerated(EnumType.STRING)
  @Column(name = "room_type", nullable = false, length = 20)
  private RoomType roomType;

  @Column(name = "check_in_date", nullable = false)
  private LocalDate checkInDate;

  @Column(name = "check_out_date", nullable = false)
  private LocalDate checkOutDate;

  @Enumerated(EnumType.STRING)
  @Column(name = "status", nullable = false, length = 20)
  private ReservationStatus status;

  @Column(name = "total_amount", nullable = false, precision = 10, scale = 2)
  private BigDecimal totalAmount;

  @Column(name = "currency", length = 3)
  private String currency = "USD";

  @Column(name = "special_requests", length = 1000)
  private String specialRequests;

  @Column(name = "created_at", nullable = false, updatable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  @Column(name = "confirmed_at")
  private LocalDateTime confirmedAt;

  @Column(name = "cancelled_at")
  private LocalDateTime cancelledAt;

  @Column(name = "cancellation_reason", length = 500)
  private String cancellationReason;

  @PrePersist
  void prePersist() {
    if (id == null) id = UUID.randomUUID().toString();
    createdAt = updatedAt = LocalDateTime.now();
    if (status == null) status = ReservationStatus.PENDING;
  }

  @PreUpdate
  void preUpdate() { updatedAt = LocalDateTime.now(); }

  public enum ReservationStatus { PENDING, CONFIRMED, CHECKED_IN, CHECKED_OUT, CANCELLED, NO_SHOW }
  public enum RoomType { STANDARD, DELUXE, SUITE, PRESIDENTIAL }
}

package com.hxp.reservation.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.hxp.reservation.controller.ReservationController.CreateReservationRequest;
import com.hxp.reservation.model.Reservation;
import com.hxp.reservation.model.Reservation.ReservationStatus;
import com.hxp.reservation.repository.ReservationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.eventbridge.EventBridgeClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;
import java.time.LocalDateTime;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class ReservationService {

  private final ReservationRepository reservationRepository;
  private final EventBridgeClient eventBridgeClient;
  private final ObjectMapper objectMapper;

  @Value("${hxp.eventbridge.bus-name}")
  private String eventBusName;

  @Transactional
  public Reservation create(CreateReservationRequest req) {
    Reservation reservation = Reservation.builder()
        .guestId(req.guestId())
        .hotelId(req.hotelId())
        .roomNumber(req.roomNumber())
        .roomType(req.roomType())
        .checkInDate(req.checkInDate())
        .checkOutDate(req.checkOutDate())
        .totalAmount(req.totalAmount())
        .specialRequests(req.specialRequests())
        .status(ReservationStatus.PENDING)
        .currency("USD")
        .build();

    Reservation saved = reservationRepository.save(reservation);
    publishEvent("reservation.created", saved);
    log.info("Reservation created id={} guestId={}", saved.getId(), saved.getGuestId());
    return saved;
  }

  @Transactional
  public Reservation confirm(String id) {
    Reservation r = findByIdOrThrow(id);
    assertStatus(r, ReservationStatus.PENDING);
    r.setStatus(ReservationStatus.CONFIRMED);
    r.setConfirmedAt(LocalDateTime.now());
    Reservation saved = reservationRepository.save(r);
    publishEvent("reservation.confirmed", saved);
    return saved;
  }

  @Transactional
  public Reservation cancel(String id, String reason) {
    Reservation r = findByIdOrThrow(id);
    if (r.getStatus() == ReservationStatus.CHECKED_IN || r.getStatus() == ReservationStatus.CHECKED_OUT) {
      throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Cannot cancel a checked-in reservation");
    }
    r.setStatus(ReservationStatus.CANCELLED);
    r.setCancelledAt(LocalDateTime.now());
    r.setCancellationReason(reason);
    Reservation saved = reservationRepository.save(r);
    publishEvent("reservation.cancelled", saved);
    return saved;
  }

  @Transactional
  public Reservation checkIn(String id) {
    Reservation r = findByIdOrThrow(id);
    assertStatus(r, ReservationStatus.CONFIRMED);
    r.setStatus(ReservationStatus.CHECKED_IN);
    Reservation saved = reservationRepository.save(r);
    publishEvent("reservation.checkedIn", saved);
    return saved;
  }

  @Transactional
  public Reservation checkOut(String id) {
    Reservation r = findByIdOrThrow(id);
    assertStatus(r, ReservationStatus.CHECKED_IN);
    r.setStatus(ReservationStatus.CHECKED_OUT);
    Reservation saved = reservationRepository.save(r);
    publishEvent("reservation.checkedOut", saved);
    return saved;
  }

  public Reservation findByIdOrThrow(String id) {
    return reservationRepository.findById(id)
        .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Reservation not found: " + id));
  }

  public Page<Reservation> search(String guestId, String hotelId, ReservationStatus status, Pageable pageable) {
    return reservationRepository.search(guestId, hotelId, status, pageable);
  }

  private void assertStatus(Reservation r, ReservationStatus expected) {
    if (r.getStatus() != expected) {
      throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
          String.format("Expected status %s but was %s", expected, r.getStatus()));
    }
  }

  private void publishEvent(String detailType, Reservation reservation) {
    try {
      String detail = objectMapper.writeValueAsString(Map.of(
          "reservationId", reservation.getId(),
          "guestId",       reservation.getGuestId(),
          "hotelId",       reservation.getHotelId(),
          "status",        reservation.getStatus().name(),
          "checkInDate",   reservation.getCheckInDate().toString(),
          "checkOutDate",  reservation.getCheckOutDate().toString(),
          "totalAmount",   reservation.getTotalAmount().toString(),
          "timestamp",     LocalDateTime.now().toString()
      ));

      PutEventsRequest request = PutEventsRequest.builder()
          .entries(PutEventsRequestEntry.builder()
              .source("hxp.reservation-service")
              .detailType(detailType)
              .detail(detail)
              .eventBusName(eventBusName)
              .build())
          .build();

      eventBridgeClient.putEvents(request);
      log.info("Published event detailType={} reservationId={}", detailType, reservation.getId());
    } catch (Exception e) {
      log.error("Failed to publish EventBridge event detailType={} reservationId={}",
          detailType, reservation.getId(), e);
    }
  }
}

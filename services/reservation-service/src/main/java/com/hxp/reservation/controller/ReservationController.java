package com.hxp.reservation.controller;

import com.hxp.reservation.model.Reservation;
import com.hxp.reservation.service.ReservationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/reservations")
@RequiredArgsConstructor
@Slf4j
public class ReservationController {

  private final ReservationService reservationService;

  @PostMapping
  public ResponseEntity<Reservation> create(@Valid @RequestBody CreateReservationRequest req) {
    log.info("Creating reservation for guestId={} hotelId={}", req.guestId(), req.hotelId());
    return ResponseEntity.status(HttpStatus.CREATED).body(reservationService.create(req));
  }

  @GetMapping("/{id}")
  public ResponseEntity<Reservation> getById(@PathVariable String id) {
    return ResponseEntity.ok(reservationService.findByIdOrThrow(id));
  }

  @GetMapping
  public ResponseEntity<Page<Reservation>> list(
      @RequestParam(required = false) String guestId,
      @RequestParam(required = false) String hotelId,
      @RequestParam(required = false) Reservation.ReservationStatus status,
      @PageableDefault(size = 20, sort = "createdAt") Pageable pageable) {
    return ResponseEntity.ok(reservationService.search(guestId, hotelId, status, pageable));
  }

  @PatchMapping("/{id}/confirm")
  public ResponseEntity<Reservation> confirm(@PathVariable String id) {
    log.info("Confirming reservation id={}", id);
    return ResponseEntity.ok(reservationService.confirm(id));
  }

  @PatchMapping("/{id}/cancel")
  public ResponseEntity<Reservation> cancel(
      @PathVariable String id,
      @RequestBody Map<String, String> body) {
    log.info("Cancelling reservation id={}", id);
    return ResponseEntity.ok(reservationService.cancel(id, body.getOrDefault("reason", "")));
  }

  @PatchMapping("/{id}/check-in")
  public ResponseEntity<Reservation> checkIn(@PathVariable String id) {
    return ResponseEntity.ok(reservationService.checkIn(id));
  }

  @PatchMapping("/{id}/check-out")
  public ResponseEntity<Reservation> checkOut(@PathVariable String id) {
    return ResponseEntity.ok(reservationService.checkOut(id));
  }

  public record CreateReservationRequest(
      String guestId,
      String hotelId,
      String roomNumber,
      Reservation.RoomType roomType,
      java.time.LocalDate checkInDate,
      java.time.LocalDate checkOutDate,
      java.math.BigDecimal totalAmount,
      String specialRequests) {}
}

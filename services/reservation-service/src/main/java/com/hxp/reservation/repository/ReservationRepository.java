package com.hxp.reservation.repository;

import com.hxp.reservation.model.Reservation;
import com.hxp.reservation.model.Reservation.ReservationStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface ReservationRepository extends JpaRepository<Reservation, String> {

  @Query("""
      SELECT r FROM Reservation r
      WHERE (:guestId IS NULL OR r.guestId = :guestId)
        AND (:hotelId  IS NULL OR r.hotelId  = :hotelId)
        AND (:status   IS NULL OR r.status   = :status)
      ORDER BY r.createdAt DESC
      """)
  Page<Reservation> search(
      @Param("guestId") String guestId,
      @Param("hotelId")  String hotelId,
      @Param("status")   ReservationStatus status,
      Pageable pageable);

  long countByStatus(ReservationStatus status);

  @Query("SELECT COUNT(r) FROM Reservation r WHERE r.status = 'CONFIRMED' AND CAST(r.confirmedAt AS date) = CURRENT_DATE")
  long countConfirmedToday();
}

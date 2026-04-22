package com.hxp.reservation;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.hxp.reservation.controller.ReservationController.CreateReservationRequest;
import com.hxp.reservation.model.Reservation;
import com.hxp.reservation.model.Reservation.ReservationStatus;
import com.hxp.reservation.model.Reservation.RoomType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import software.amazon.awssdk.services.eventbridge.EventBridgeClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsResponse;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@Testcontainers
@ActiveProfiles("local")
class ReservationIntegrationTest {

  @Container
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
      .withDatabaseName("hxp_test")
      .withUsername("hxp")
      .withPassword("test");

  @Autowired MockMvc mockMvc;
  @Autowired ObjectMapper objectMapper;
  @MockBean  EventBridgeClient eventBridgeClient;

  @BeforeEach
  void setup() {
    when(eventBridgeClient.putEvents(any(PutEventsRequest.class)))
        .thenReturn(PutEventsResponse.builder().failedEntryCount(0).build());

    // Set datasource URL from Testcontainers
    System.setProperty("spring.datasource.url",      postgres.getJdbcUrl());
    System.setProperty("spring.datasource.username", postgres.getUsername());
    System.setProperty("spring.datasource.password", postgres.getPassword());
  }

  @Test
  void createReservation_returns201_withValidPayload() throws Exception {
    var req = new CreateReservationRequest(
        "guest-001", "HYT-CHI-001", "301", RoomType.DELUXE,
        LocalDate.now().plusDays(10), LocalDate.now().plusDays(13),
        new BigDecimal("780.00"), "High floor please");

    mockMvc.perform(post("/api/v1/reservations")
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(req)))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.id").isNotEmpty())
        .andExpect(jsonPath("$.status").value("PENDING"))
        .andExpect(jsonPath("$.guestId").value("guest-001"))
        .andExpect(jsonPath("$.totalAmount").value(780.00));
  }

  @Test
  void confirmReservation_transitions_pendingToConfirmed() throws Exception {
    // Create first
    var req = new CreateReservationRequest(
        "guest-002", "HYT-NYC-002", "201", RoomType.STANDARD,
        LocalDate.now().plusDays(5), LocalDate.now().plusDays(7),
        new BigDecimal("340.00"), null);

    var createResult = mockMvc.perform(post("/api/v1/reservations")
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(req)))
        .andExpect(status().isCreated())
        .andReturn();

    var created = objectMapper.readValue(createResult.getResponse().getContentAsString(), Reservation.class);

    // Confirm
    mockMvc.perform(patch("/api/v1/reservations/" + created.getId() + "/confirm"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.status").value("CONFIRMED"))
        .andExpect(jsonPath("$.confirmedAt").isNotEmpty());
  }

  @Test
  void getReservation_returns404_forUnknownId() throws Exception {
    mockMvc.perform(get("/api/v1/reservations/non-existent-id"))
        .andExpect(status().isNotFound());
  }

  @Test
  void cancelConfirmedReservation_succeeds() throws Exception {
    var req = new CreateReservationRequest(
        "guest-003", "HYT-LAX-003", "401", RoomType.SUITE,
        LocalDate.now().plusDays(20), LocalDate.now().plusDays(23),
        new BigDecimal("1200.00"), null);

    var createResult = mockMvc.perform(post("/api/v1/reservations")
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(req)))
        .andReturn();
    var created = objectMapper.readValue(createResult.getResponse().getContentAsString(), Reservation.class);

    // Confirm then cancel
    mockMvc.perform(patch("/api/v1/reservations/" + created.getId() + "/confirm"));
    mockMvc.perform(patch("/api/v1/reservations/" + created.getId() + "/cancel")
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"reason\": \"Change of plans\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.status").value("CANCELLED"))
        .andExpect(jsonPath("$.cancellationReason").value("Change of plans"));
  }
}

import { SQSEvent, SQSRecord } from 'aws-lambda';
import { SESv2Client, SendEmailCommand } from '@aws-sdk/client-sesv2';

const ses = new SESv2Client({});
const FROM_ADDRESS = process.env.FROM_EMAIL_ADDRESS!;

interface ReservationEvent {
  reservationId: string;
  guestId: string;
  hotelId: string;
  status: string;
  checkInDate: string;
  checkOutDate: string;
  totalAmount: string;
  timestamp: string;
  // Enriched by upstream (EventBridge pipe or step function)
  guestEmail?: string;
  guestFirstName?: string;
}

const templates: Record<string, (e: ReservationEvent) => { subject: string; html: string }> = {
  'reservation.confirmed': (e) => ({
    subject: `Booking Confirmed — Reservation #${e.reservationId.slice(0, 8).toUpperCase()}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: #1a1a2e; color: white; padding: 24px; text-align: center;">
          <h1 style="margin:0; font-size: 24px;">Hotel Experience Platform</h1>
        </div>
        <div style="padding: 32px; background: #ffffff;">
          <h2 style="color: #1a1a2e;">Your booking is confirmed! 🎉</h2>
          <p>Hi ${e.guestFirstName || 'Guest'},</p>
          <p>We're pleased to confirm your reservation.</p>
          <table style="width:100%; border-collapse: collapse; margin: 24px 0;">
            <tr style="background: #f8f9fa;">
              <td style="padding:12px; font-weight:bold;">Confirmation #</td>
              <td style="padding:12px;">${e.reservationId.slice(0, 8).toUpperCase()}</td>
            </tr>
            <tr>
              <td style="padding:12px; font-weight:bold;">Hotel</td>
              <td style="padding:12px;">${e.hotelId}</td>
            </tr>
            <tr style="background: #f8f9fa;">
              <td style="padding:12px; font-weight:bold;">Check-in</td>
              <td style="padding:12px;">${e.checkInDate}</td>
            </tr>
            <tr>
              <td style="padding:12px; font-weight:bold;">Check-out</td>
              <td style="padding:12px;">${e.checkOutDate}</td>
            </tr>
            <tr style="background: #f8f9fa;">
              <td style="padding:12px; font-weight:bold;">Total</td>
              <td style="padding:12px;">$${e.totalAmount}</td>
            </tr>
          </table>
          <p style="color: #666;">We look forward to welcoming you!</p>
        </div>
        <div style="background: #f8f9fa; padding: 16px; text-align:center; color: #666; font-size: 12px;">
          Hotel Experience Platform · This is an automated message
        </div>
      </div>`,
  }),
  'reservation.cancelled': (e) => ({
    subject: `Booking Cancellation — #${e.reservationId.slice(0, 8).toUpperCase()}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px;">
        <h2>Your reservation has been cancelled</h2>
        <p>Hi ${e.guestFirstName || 'Guest'}, your reservation #${e.reservationId.slice(0, 8).toUpperCase()} 
           for ${e.checkInDate} – ${e.checkOutDate} has been cancelled.</p>
        <p>If this was unexpected, please contact our support team.</p>
      </div>`,
  }),
  'reservation.checkedIn': (e) => ({
    subject: `Welcome! You've checked in — #${e.reservationId.slice(0, 8).toUpperCase()}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px;">
        <h2>Welcome, ${e.guestFirstName || 'Guest'}! 🏨</h2>
        <p>You've successfully checked in. Enjoy your stay!</p>
        <p>Check-out date: <strong>${e.checkOutDate}</strong></p>
      </div>`,
  }),
};

async function processRecord(record: SQSRecord): Promise<void> {
  const body = JSON.parse(record.body);
  // EventBridge events arrive wrapped
  const detailType: string = body['detail-type'] || body.detailType;
  const event: ReservationEvent = body.detail || body;

  console.log(JSON.stringify({ msg: 'Processing notification', detailType, reservationId: event.reservationId }));

  const template = templates[detailType];
  if (!template) {
    console.log(`No template for detailType=${detailType}, skipping`);
    return;
  }

  const guestEmail = event.guestEmail;
  if (!guestEmail) {
    console.warn(`No guestEmail on event reservationId=${event.reservationId}, skipping email`);
    return;
  }

  const { subject, html } = template(event);

  await ses.send(new SendEmailCommand({
    FromEmailAddress: FROM_ADDRESS,
    Destination: { ToAddresses: [guestEmail] },
    Content: {
      Simple: {
        Subject: { Data: subject, Charset: 'UTF-8' },
        Body: { Html: { Data: html, Charset: 'UTF-8' } },
      },
    },
  }));

  console.log(JSON.stringify({ msg: 'Email sent', to: guestEmail, subject, reservationId: event.reservationId }));
}

export const handler = async (event: SQSEvent): Promise<{ batchItemFailures: { itemIdentifier: string }[] }> => {
  const failures: { itemIdentifier: string }[] = [];

  await Promise.allSettled(
    event.Records.map(async (record) => {
      try {
        await processRecord(record);
      } catch (err) {
        console.error(JSON.stringify({ msg: 'Failed to process record', messageId: record.messageId, error: String(err) }));
        failures.push({ itemIdentifier: record.messageId });
      }
    })
  );

  return { batchItemFailures: failures };
};

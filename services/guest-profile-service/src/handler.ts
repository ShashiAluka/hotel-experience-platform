import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  QueryCommand,
  DeleteCommand,
} from '@aws-sdk/lib-dynamodb';
import { v4 as uuidv4 } from 'uuid';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.GUEST_PROFILES_TABLE!;

interface GuestProfile {
  guestId: string;
  email: string;
  firstName: string;
  lastName: string;
  phone?: string;
  dateOfBirth?: string;
  loyaltyTier: 'BRONZE' | 'SILVER' | 'GOLD' | 'PLATINUM';
  loyaltyPoints: number;
  totalNights: number;
  preferences?: {
    roomType?: string;
    floor?: 'LOW' | 'MID' | 'HIGH';
    pillowType?: 'SOFT' | 'FIRM';
    dietaryRestrictions?: string[];
    amenities?: string[];
  };
  createdAt: string;
  updatedAt: string;
}

const response = (statusCode: number, body: unknown): APIGatewayProxyResult => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  },
  body: JSON.stringify(body),
});

const now = () => new Date().toISOString();

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const { httpMethod, pathParameters, queryStringParameters, body } = event;
  const guestId = pathParameters?.guestId;

  try {
    // POST /guests — create
    if (httpMethod === 'POST' && !guestId) {
      const data = JSON.parse(body || '{}');
      if (!data.email || !data.firstName || !data.lastName) {
        return response(400, { error: 'email, firstName, lastName are required' });
      }
      // Check email uniqueness
      const existing = await ddb.send(new QueryCommand({
        TableName: TABLE,
        IndexName: 'EmailIndex',
        KeyConditionExpression: 'email = :email',
        ExpressionAttributeValues: { ':email': data.email },
        Limit: 1,
      }));
      if (existing.Items?.length) return response(409, { error: 'Email already registered' });

      const guest: GuestProfile = {
        guestId: uuidv4(),
        email: data.email,
        firstName: data.firstName,
        lastName: data.lastName,
        phone: data.phone,
        dateOfBirth: data.dateOfBirth,
        loyaltyTier: 'BRONZE',
        loyaltyPoints: 0,
        totalNights: 0,
        preferences: data.preferences,
        createdAt: now(),
        updatedAt: now(),
      };
      await ddb.send(new PutCommand({ TableName: TABLE, Item: guest }));
      return response(201, guest);
    }

    // GET /guests/{guestId}
    if (httpMethod === 'GET' && guestId) {
      const result = await ddb.send(new GetCommand({ TableName: TABLE, Key: { guestId } }));
      if (!result.Item) return response(404, { error: 'Guest not found' });
      return response(200, result.Item);
    }

    // GET /guests?email=...
    if (httpMethod === 'GET' && queryStringParameters?.email) {
      const result = await ddb.send(new QueryCommand({
        TableName: TABLE,
        IndexName: 'EmailIndex',
        KeyConditionExpression: 'email = :email',
        ExpressionAttributeValues: { ':email': queryStringParameters.email },
        Limit: 1,
      }));
      if (!result.Items?.length) return response(404, { error: 'Guest not found' });
      return response(200, result.Items[0]);
    }

    // PATCH /guests/{guestId}
    if (httpMethod === 'PATCH' && guestId) {
      const data = JSON.parse(body || '{}');
      const allowedFields = ['firstName', 'lastName', 'phone', 'preferences'];
      const updates = Object.entries(data).filter(([k]) => allowedFields.includes(k));
      if (!updates.length) return response(400, { error: 'No updatable fields provided' });

      const expressions = updates.map(([k], i) => `#f${i} = :v${i}`).join(', ');
      const names = Object.fromEntries(updates.map(([k], i) => [`#f${i}`, k]));
      const values = Object.fromEntries(updates.map(([k, v], i) => [`:v${i}`, v]));
      values[':updatedAt'] = now();

      const result = await ddb.send(new UpdateCommand({
        TableName: TABLE,
        Key: { guestId },
        UpdateExpression: `SET ${expressions}, updatedAt = :updatedAt`,
        ExpressionAttributeNames: names,
        ExpressionAttributeValues: values,
        ConditionExpression: 'attribute_exists(guestId)',
        ReturnValues: 'ALL_NEW',
      }));
      return response(200, result.Attributes);
    }

    // POST /guests/{guestId}/loyalty — add points
    if (httpMethod === 'POST' && guestId && event.path?.endsWith('/loyalty')) {
      const { points, nights } = JSON.parse(body || '{}');
      const result = await ddb.send(new UpdateCommand({
        TableName: TABLE,
        Key: { guestId },
        UpdateExpression: 'ADD loyaltyPoints :p, totalNights :n SET updatedAt = :u',
        ExpressionAttributeValues: { ':p': points || 0, ':n': nights || 0, ':u': now() },
        ConditionExpression: 'attribute_exists(guestId)',
        ReturnValues: 'ALL_NEW',
      }));
      // Recalculate tier
      const total = (result.Attributes?.loyaltyPoints as number) ?? 0;
      const tier = total >= 50000 ? 'PLATINUM' : total >= 25000 ? 'GOLD' : total >= 10000 ? 'SILVER' : 'BRONZE';
      await ddb.send(new UpdateCommand({
        TableName: TABLE,
        Key: { guestId },
        UpdateExpression: 'SET loyaltyTier = :t',
        ExpressionAttributeValues: { ':t': tier },
      }));
      return response(200, { ...result.Attributes, loyaltyTier: tier });
    }

    // DELETE /guests/{guestId}
    if (httpMethod === 'DELETE' && guestId) {
      await ddb.send(new DeleteCommand({ TableName: TABLE, Key: { guestId } }));
      return response(204, {});
    }

    return response(405, { error: 'Method not allowed' });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Internal error';
    console.error('Unhandled error:', err);
    if (msg.includes('conditional')) return response(404, { error: 'Guest not found' });
    return response(500, { error: msg });
  }
};

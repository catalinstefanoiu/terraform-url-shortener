// Lambda handler for the URL shortener API (API Gateway HTTP API, payload format 2.0).
//   POST /links   body {"url": "https://..."}  -> 201 {"code": "...", "short_url": "..."}
//   GET  /{code}                               -> 302 redirect to the long URL

import { randomInt } from "node:crypto";
import {
  ConditionalCheckFailedException,
  DynamoDBClient,
  GetItemCommand,
  PutItemCommand,
} from "@aws-sdk/client-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";

// Created once per Lambda instance (outside the handler) and reused by every request it serves.
const db = new DynamoDBClient({});

// Table name comes from the TABLE_NAME environment variable, set by Terraform (lambda.tf).
const TABLE_NAME = process.env.TABLE_NAME ?? "";

const ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"; // 62 characters
const CODE_LENGTH = 6; // 62^6 ≈ 56 billion possible codes
const MAX_ATTEMPTS = 3; // retries when a generated code is already taken

// Entry point called by Lambda: routes each request to the right function.
export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  // Log the route and the request ID; it shows up in CloudWatch Logs.
  console.log(JSON.stringify({ route: event.routeKey, requestId: event.requestContext?.requestId }));

  if (event.routeKey === "POST /links") return createLink(event); // create a short link
  if (event.routeKey === "GET /{code}") return redirect(event.pathParameters?.code); // open a short link
  return json(404, { error: "Not found" });
}

// POST /links: stores the long URL under a new random code and returns the short link.
async function createLink(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  // The long URL the user wants to shorten, e.g. "https://developer.hashicorp.com/terraform".
  const url = parseUrl(event.body, event.isBase64Encoded);
  if (!url) return json(400, { error: 'Send JSON like {"url": "https://example.com"}' });

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const code = generateCode(); // e.g. "k3x9Qa"
    try {
      await db.send(
        new PutItemCommand({
          TableName: TABLE_NAME,
          Item: {
            code: { S: code },
            url: { S: url },
            created_at: { S: new Date().toISOString() },
          },
          // Write only if this code is still free: never overwrite someone else's link.
          ConditionExpression: "attribute_not_exists(code)",
        }),
      );
      console.log(JSON.stringify({ msg: "created", code }));

      // The short link: the API's own address + the new code.
      return json(201, { code, short_url: `https://${event.requestContext.domainName}/${code}` });
    } catch (err) {
      // Code already taken: go back to the top of the loop and try a new one.
      if (err instanceof ConditionalCheckFailedException) continue;
      // Anything else is a real failure: rethrow so Lambda counts it as an error.
      throw err;
    }
  }
  throw new Error(`No free code after ${MAX_ATTEMPTS} attempts`);
}

// GET /{code}: looks up the code and redirects the browser to the long URL.
async function redirect(code: string | undefined): Promise<APIGatewayProxyResultV2> {
  if (!code) return json(404, { error: "Not found" });

  const result = await db.send(
    new GetItemCommand({ TableName: TABLE_NAME, Key: { code: { S: code } } }),
  );
  const url = result.Item?.url?.S; // undefined when the code does not exist
  if (!url) return json(404, { error: "Not found" });

  // 302 = temporary redirect: browsers do not cache it, so every click reaches Lambda.
  return { statusCode: 302, headers: { location: url } };
}

// Returns a clean http(s) URL from the request body, or null if the body is not valid.
function parseUrl(body: string | undefined, isBase64Encoded: boolean): string | null {
  if (!body) return null;
  try {
    // API Gateway may send the body base64-encoded; decode it back to plain text.
    const text = isBase64Encoded ? Buffer.from(body, "base64").toString("utf8") : body;
    // Take only the "url" field from the JSON object.
    const { url } = JSON.parse(text) as { url?: unknown };
    if (typeof url !== "string" || url.length > 2048) return null;
    const parsed = new URL(url); // throws if the text is not a valid URL
    // Only http and https: blocks schemes like "javascript:".
    return parsed.protocol === "https:" || parsed.protocol === "http:" ? parsed.toString() : null;
  } catch {
    return null;
  }
}

// Builds a random code from ALPHABET using a cryptographically secure generator.
function generateCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}

// Builds a JSON response for API Gateway.
function json(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  };
}

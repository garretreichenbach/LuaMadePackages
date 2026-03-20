"use strict";

const crypto = require("crypto");

/**
 * Verifies the API key supplied in the Authorization header.
 *
 * The expected value is stored as a SHA-256 hex digest in the
 * API_KEY_HASH environment variable so that the plaintext key is
 * never held in configuration.
 *
 * Header format:  Authorization: Bearer <api-key>
 *
 * @param {import("@azure/functions").HttpRequest} request
 * @returns {boolean}
 */
function isAuthorized(request) {
  const apiKeyHash = process.env.API_KEY_HASH;
  if (!apiKeyHash) {
    // If no hash is configured, authenticated endpoints are disabled.
    return false;
  }

  const authHeader = request.headers.get("authorization") || "";
  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    return false;
  }

  const provided = parts[1];
  const providedHash = crypto.createHash("sha256").update(provided).digest("hex");
  return crypto.timingSafeEqual(
    Buffer.from(providedHash, "hex"),
    Buffer.from(apiKeyHash, "hex")
  );
}

/**
 * Returns a 401 JSON response.
 * @returns {{ status: number, body: string, headers: Record<string,string> }}
 */
function unauthorizedResponse() {
  return {
    status: 401,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ error: "Unauthorized – valid Bearer token required." }),
  };
}

module.exports = { isAuthorized, unauthorizedResponse };

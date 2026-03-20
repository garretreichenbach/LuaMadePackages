"use strict";

const { describe, it, expect, beforeEach } = require("@jest/globals");
const crypto = require("crypto");

// ---------------------------------------------------------------------------
// auth utility tests – no real Azure connection required.
// ---------------------------------------------------------------------------

const { isAuthorized, unauthorizedResponse } = require("../src/utils/auth");

function makeRequest(authHeaderValue) {
  return {
    headers: {
      get: (name) => (name.toLowerCase() === "authorization" ? authHeaderValue : null),
    },
  };
}

const PLAINTEXT_KEY = "super-secret-key-for-testing";
const KEY_HASH = crypto.createHash("sha256").update(PLAINTEXT_KEY).digest("hex");

describe("isAuthorized", () => {
  beforeEach(() => {
    process.env.API_KEY_HASH = KEY_HASH;
  });

  it("returns true for the correct Bearer token", () => {
    const req = makeRequest(`Bearer ${PLAINTEXT_KEY}`);
    expect(isAuthorized(req)).toBe(true);
  });

  it("returns false for an incorrect Bearer token", () => {
    const req = makeRequest("Bearer wrong-key");
    expect(isAuthorized(req)).toBe(false);
  });

  it("returns false when the Authorization header is missing", () => {
    const req = makeRequest(null);
    expect(isAuthorized(req)).toBe(false);
  });

  it("returns false when the scheme is not Bearer", () => {
    const req = makeRequest(`Basic ${PLAINTEXT_KEY}`);
    expect(isAuthorized(req)).toBe(false);
  });

  it("returns false when API_KEY_HASH is not configured", () => {
    delete process.env.API_KEY_HASH;
    const req = makeRequest(`Bearer ${PLAINTEXT_KEY}`);
    expect(isAuthorized(req)).toBe(false);
  });
});

describe("unauthorizedResponse", () => {
  it("returns a 401 status with a JSON error body", () => {
    const res = unauthorizedResponse();
    expect(res.status).toBe(401);
    expect(res.headers["Content-Type"]).toBe("application/json");
    const body = JSON.parse(res.body);
    expect(body.error).toBeTruthy();
  });
});

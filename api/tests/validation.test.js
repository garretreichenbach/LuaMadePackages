"use strict";

const { describe, it, expect } = require("@jest/globals");
const {
  isValidPackageName,
  isValidVersion,
  validateManifest,
  errorResponse,
  jsonResponse,
} = require("../src/utils/validation");

describe("isValidPackageName", () => {
  it("accepts valid lowercase names", () => {
    expect(isValidPackageName("my-package")).toBe(true);
    expect(isValidPackageName("lua_utils")).toBe(true);
    expect(isValidPackageName("helloworld")).toBe(true);
    expect(isValidPackageName("a")).toBe(true);
  });

  it("rejects names with uppercase letters", () => {
    expect(isValidPackageName("MyPackage")).toBe(false);
  });

  it("rejects names starting with a hyphen", () => {
    expect(isValidPackageName("-bad")).toBe(false);
  });

  it("rejects names with spaces or special characters", () => {
    expect(isValidPackageName("bad name")).toBe(false);
    expect(isValidPackageName("bad@name")).toBe(false);
    expect(isValidPackageName("bad/name")).toBe(false);
  });

  it("rejects empty string", () => {
    expect(isValidPackageName("")).toBe(false);
  });

  it("rejects names longer than 64 characters", () => {
    expect(isValidPackageName("a".repeat(65))).toBe(false);
  });

  it("accepts names exactly 64 characters long", () => {
    // 1 leading char + 63 more = 64 total
    expect(isValidPackageName("a" + "b".repeat(63))).toBe(true);
  });
});

describe("isValidVersion", () => {
  it("accepts valid semver versions", () => {
    expect(isValidVersion("1.0.0")).toBe(true);
    expect(isValidVersion("0.0.1")).toBe(true);
    expect(isValidVersion("10.20.30")).toBe(true);
  });

  it("rejects versions without three parts", () => {
    expect(isValidVersion("1.0")).toBe(false);
    expect(isValidVersion("1")).toBe(false);
    expect(isValidVersion("1.2.3.4")).toBe(false);
  });

  it("rejects versions with non-numeric parts", () => {
    expect(isValidVersion("1.0.a")).toBe(false);
    expect(isValidVersion("1.x.0")).toBe(false);
  });

  it("rejects empty string", () => {
    expect(isValidVersion("")).toBe(false);
  });
});

describe("validateManifest", () => {
  const validManifest = {
    name: "test-package",
    version: "1.0.0",
    description: "A test package",
    author: "Test Author",
  };

  it("returns no errors for a valid manifest", () => {
    expect(validateManifest(validManifest)).toEqual([]);
  });

  it("returns an error for an invalid name", () => {
    const errors = validateManifest({ ...validManifest, name: "Bad Name!" });
    expect(errors.some((e) => e.includes("name"))).toBe(true);
  });

  it("returns an error for an invalid version", () => {
    const errors = validateManifest({ ...validManifest, version: "not-semver" });
    expect(errors.some((e) => e.includes("version"))).toBe(true);
  });

  it("returns an error for a missing description", () => {
    const errors = validateManifest({ ...validManifest, description: "" });
    expect(errors.some((e) => e.includes("description"))).toBe(true);
  });

  it("returns an error for a missing author", () => {
    const errors = validateManifest({ ...validManifest, author: "" });
    expect(errors.some((e) => e.includes("author"))).toBe(true);
  });

  it("accumulates multiple errors", () => {
    const errors = validateManifest({ name: "Bad!", version: "x", description: "", author: "" });
    expect(errors.length).toBeGreaterThan(1);
  });
});

describe("errorResponse", () => {
  it("returns the correct status and JSON body", () => {
    const res = errorResponse(404, "Not found");
    expect(res.status).toBe(404);
    expect(res.headers["Content-Type"]).toBe("application/json");
    const body = JSON.parse(res.body);
    expect(body.error).toBe("Not found");
  });
});

describe("jsonResponse", () => {
  it("returns the correct status and JSON body", () => {
    const data = { packages: [], total: 0 };
    const res = jsonResponse(200, data);
    expect(res.status).toBe(200);
    expect(res.headers["Content-Type"]).toBe("application/json");
    const body = JSON.parse(res.body);
    expect(body).toEqual(data);
  });
});

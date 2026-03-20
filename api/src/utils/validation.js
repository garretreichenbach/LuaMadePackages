"use strict";

/**
 * Validates a package name: lowercase alphanumeric, hyphens and underscores only.
 * @param {string} name
 * @returns {boolean}
 */
function isValidPackageName(name) {
  return typeof name === "string" && /^[a-z0-9][a-z0-9_-]{0,63}$/.test(name);
}

/**
 * Validates a semver-style version string (major.minor.patch).
 * @param {string} version
 * @returns {boolean}
 */
function isValidVersion(version) {
  return typeof version === "string" && /^\d+\.\d+\.\d+$/.test(version);
}

/**
 * Validates a package manifest object.
 * Returns an array of validation error messages (empty when valid).
 * @param {Record<string,unknown>} manifest
 * @returns {string[]}
 */
function validateManifest(manifest) {
  const errors = [];

  if (!isValidPackageName(manifest.name)) {
    errors.push(
      "\"name\" must be 1-64 lowercase alphanumeric characters, hyphens, or underscores and must start with a letter or digit."
    );
  }

  if (!isValidVersion(manifest.version)) {
    errors.push("\"version\" must follow semver (MAJOR.MINOR.PATCH, e.g. 1.0.0).");
  }

  if (typeof manifest.description !== "string" || manifest.description.trim() === "") {
    errors.push("\"description\" must be a non-empty string.");
  }

  if (typeof manifest.author !== "string" || manifest.author.trim() === "") {
    errors.push("\"author\" must be a non-empty string.");
  }

  return errors;
}

/**
 * Returns a standard JSON error response object.
 * @param {number} status  HTTP status code
 * @param {string} message Error message
 * @returns {{ status: number, headers: Record<string,string>, body: string }}
 */
function errorResponse(status, message) {
  return {
    status,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ error: message }),
  };
}

/**
 * Returns a standard JSON success response object.
 * @param {number} status  HTTP status code
 * @param {unknown} data   Response payload
 * @returns {{ status: number, headers: Record<string,string>, body: string }}
 */
function jsonResponse(status, data) {
  return {
    status,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  };
}

module.exports = {
  isValidPackageName,
  isValidVersion,
  validateManifest,
  errorResponse,
  jsonResponse,
};

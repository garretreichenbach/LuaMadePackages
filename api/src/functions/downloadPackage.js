"use strict";

/**
 * Azure Function: downloadPackage
 * GET /api/packages/{name}/{version}/download
 *
 * Returns the raw tarball for a specific package version.
 * Redirects the client to the Azure Blob Storage URL.
 */

const { app } = require("@azure/functions");
const { downloadBlob, metadataBlobName } = require("../utils/storage");
const { isValidPackageName, isValidVersion, errorResponse } = require("../utils/validation");

app.http("downloadPackage", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "packages/{name}/{version}/download",
  handler: async (request) => {
    const { name, version } = request.params;

    if (!isValidPackageName(name)) {
      return errorResponse(400, "Invalid package name.");
    }
    if (!isValidVersion(version)) {
      return errorResponse(400, "Invalid version. Must follow semver (MAJOR.MINOR.PATCH).");
    }

    try {
      const raw = await downloadBlob(metadataBlobName(name));
      if (!raw) {
        return errorResponse(404, `Package "${name}" not found.`);
      }

      const metadata = JSON.parse(raw.toString("utf8"));
      const versionInfo = metadata.versions && metadata.versions[version];
      if (!versionInfo) {
        return errorResponse(404, `Version "${version}" of package "${name}" not found.`);
      }

      // Redirect to the blob's public URL.
      return {
        status: 302,
        headers: { Location: versionInfo.downloadUrl },
        body: "",
      };
    } catch (err) {
      return errorResponse(500, `Failed to resolve download URL: ${err.message}`);
    }
  },
});

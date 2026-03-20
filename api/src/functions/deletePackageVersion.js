"use strict";

/**
 * Azure Function: deletePackageVersion
 * DELETE /api/packages/{name}/{version}
 *
 * Removes a specific version of a package.
 * If the deleted version was the latest, the latest pointer is updated to
 * the most recently published remaining version.
 *
 * Requires a valid Bearer API key in the Authorization header.
 */

const { app } = require("@azure/functions");
const { downloadBlob, uploadBlob, deleteBlob, metadataBlobName, packageBlobName } = require("../utils/storage");
const { isAuthorized, unauthorizedResponse } = require("../utils/auth");
const { isValidPackageName, isValidVersion, jsonResponse, errorResponse } = require("../utils/validation");

app.http("deletePackageVersion", {
  methods: ["DELETE"],
  authLevel: "anonymous",
  route: "packages/{name}/{version}",
  handler: async (request) => {
    if (!isAuthorized(request)) {
      return unauthorizedResponse();
    }

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
      if (!metadata.versions || !metadata.versions[version]) {
        return errorResponse(404, `Version "${version}" of package "${name}" not found.`);
      }

      // Delete the tarball from storage.
      await deleteBlob(packageBlobName(name, version));

      // Remove version entry from metadata.
      delete metadata.versions[version];

      const remainingVersions = Object.keys(metadata.versions);
      if (remainingVersions.length === 0) {
        // No versions left – delete the metadata blob entirely.
        await deleteBlob(metadataBlobName(name));
        return jsonResponse(200, {
          message: `Package "${name}" deleted (no versions remaining).`,
        });
      }

      // Update latestVersion if needed.
      if (metadata.latestVersion === version) {
        // Pick the version with the most recent publishedAt timestamp.
        const latest = remainingVersions.reduce((best, v) => {
          const bestDate = new Date(metadata.versions[best].publishedAt);
          const vDate = new Date(metadata.versions[v].publishedAt);
          return vDate > bestDate ? v : best;
        });
        metadata.latestVersion = latest;
      }

      metadata.updatedAt = new Date().toISOString();
      await uploadBlob(
        metadataBlobName(name),
        Buffer.from(JSON.stringify(metadata, null, 2), "utf8"),
        "application/json"
      );

      return jsonResponse(200, {
        message: `Version "${version}" of package "${name}" deleted.`,
        package: metadata,
      });
    } catch (err) {
      return errorResponse(500, `Failed to delete package version: ${err.message}`);
    }
  },
});

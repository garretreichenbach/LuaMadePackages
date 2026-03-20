"use strict";

/**
 * Azure Function: listPackages
 * GET /api/packages
 *
 * Returns a list of all published packages with their latest metadata.
 * Supports an optional ?search=<query> query parameter.
 */

const { app } = require("@azure/functions");
const { listBlobs, downloadBlob, metadataBlobName } = require("../utils/storage");
const { jsonResponse, errorResponse } = require("../utils/validation");

app.http("listPackages", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "packages",
  handler: async (request) => {
    try {
      const search = (request.query.get("search") || "").toLowerCase().trim();

      // Collect unique package names from metadata blobs.
      const allBlobs = await listBlobs();
      const packageNames = new Set();
      for (const name of allBlobs) {
        if (name.endsWith("/metadata.json")) {
          packageNames.add(name.split("/")[0]);
        }
      }

      // Load each package's metadata and optionally filter by search term.
      const packages = [];
      for (const pkgName of packageNames) {
        const raw = await downloadBlob(metadataBlobName(pkgName));
        if (!raw) continue;
        const metadata = JSON.parse(raw.toString("utf8"));
        if (
          !search ||
          metadata.name.includes(search) ||
          (metadata.description || "").toLowerCase().includes(search) ||
          (metadata.tags || []).some((t) => t.toLowerCase().includes(search))
        ) {
          packages.push(metadata);
        }
      }

      packages.sort((a, b) => a.name.localeCompare(b.name));
      return jsonResponse(200, { packages, total: packages.length });
    } catch (err) {
      return errorResponse(500, `Failed to list packages: ${err.message}`);
    }
  },
});

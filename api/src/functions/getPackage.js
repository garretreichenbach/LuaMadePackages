"use strict";

/**
 * Azure Function: getPackage
 * GET /api/packages/{name}
 *
 * Returns the full metadata for a package including all available versions.
 */

const { app } = require("@azure/functions");
const { downloadBlob, metadataBlobName } = require("../utils/storage");
const { isValidPackageName, jsonResponse, errorResponse } = require("../utils/validation");

app.http("getPackage", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "packages/{name}",
  handler: async (request) => {
    const name = request.params.name;

    if (!isValidPackageName(name)) {
      return errorResponse(400, "Invalid package name.");
    }

    try {
      const raw = await downloadBlob(metadataBlobName(name));
      if (!raw) {
        return errorResponse(404, `Package "${name}" not found.`);
      }

      const metadata = JSON.parse(raw.toString("utf8"));
      return jsonResponse(200, metadata);
    } catch (err) {
      return errorResponse(500, `Failed to retrieve package: ${err.message}`);
    }
  },
});

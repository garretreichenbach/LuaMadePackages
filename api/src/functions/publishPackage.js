"use strict";

/**
 * Azure Function: publishPackage
 * POST /api/packages
 *
 * Publishes a new package version.  Expects a multipart/form-data body with:
 *   - manifest  (JSON text)  – package manifest (name, version, description, author, …)
 *   - package   (binary)     – the package tarball (.tar.gz)
 *
 * Requires a valid Bearer API key in the Authorization header.
 */

const { app } = require("@azure/functions");
const busboy = require("busboy");
const { uploadBlob, downloadBlob, metadataBlobName, packageBlobName } = require("../utils/storage");
const { isAuthorized, unauthorizedResponse } = require("../utils/auth");
const { validateManifest, isValidPackageName, isValidVersion, jsonResponse, errorResponse } = require("../utils/validation");

app.http("publishPackage", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "packages",
  handler: async (request) => {
    if (!isAuthorized(request)) {
      return unauthorizedResponse();
    }

    const contentType = request.headers.get("content-type") || "";
    if (!contentType.includes("multipart/form-data")) {
      return errorResponse(400, "Content-Type must be multipart/form-data.");
    }

    let manifest = null;
    let packageBuffer = null;

    try {
      await new Promise((resolve, reject) => {
        const bb = busboy({ headers: { "content-type": contentType } });

        bb.on("field", (name, value) => {
          if (name === "manifest") {
            try {
              manifest = JSON.parse(value);
            } catch {
              reject(new Error("\"manifest\" field must be valid JSON."));
            }
          }
        });

        bb.on("file", (fieldName, stream) => {
          if (fieldName === "package") {
            const chunks = [];
            stream.on("data", (chunk) => chunks.push(chunk));
            stream.on("end", () => {
              packageBuffer = Buffer.concat(chunks);
            });
          } else {
            // Drain unrecognised file streams to avoid hanging.
            stream.resume();
          }
        });

        bb.on("finish", resolve);
        bb.on("error", reject);

        request.arrayBuffer().then((ab) => {
          bb.write(Buffer.from(ab));
          bb.end();
        });
      });
    } catch (err) {
      return errorResponse(400, `Failed to parse request body: ${err.message}`);
    }

    if (!manifest) {
      return errorResponse(400, "Missing required field: manifest.");
    }
    if (!packageBuffer || packageBuffer.length === 0) {
      return errorResponse(400, "Missing required file: package.");
    }

    const errors = validateManifest(manifest);
    if (errors.length > 0) {
      return errorResponse(400, errors.join(" | "));
    }

    const { name, version } = manifest;

    // Load or initialise package metadata.
    let metadata;
    const existingRaw = await downloadBlob(metadataBlobName(name));
    if (existingRaw) {
      metadata = JSON.parse(existingRaw.toString("utf8"));
      if (metadata.versions && metadata.versions[version]) {
        return errorResponse(
          409,
          `Version "${version}" of package "${name}" already exists. Bump the version number to publish an update.`
        );
      }
    } else {
      metadata = {
        name,
        description: manifest.description,
        author: manifest.author,
        license: manifest.license || "MIT",
        tags: manifest.tags || [],
        versions: {},
        latestVersion: null,
        publishedAt: new Date().toISOString(),
      };
    }

    // Upload the tarball.
    const blobUrl = await uploadBlob(
      packageBlobName(name, version),
      packageBuffer,
      "application/gzip"
    );

    // Record the version in the metadata.
    metadata.versions[version] = {
      version,
      publishedAt: new Date().toISOString(),
      downloadUrl: blobUrl,
      size: packageBuffer.length,
      dependencies: manifest.dependencies || {},
      luamadeVersion: manifest.luamadeVersion || null,
    };
    metadata.latestVersion = version;
    metadata.updatedAt = new Date().toISOString();

    // Persist updated metadata.
    await uploadBlob(
      metadataBlobName(name),
      Buffer.from(JSON.stringify(metadata, null, 2), "utf8"),
      "application/json"
    );

    return jsonResponse(201, {
      message: `Package "${name}@${version}" published successfully.`,
      package: metadata,
    });
  },
});

"use strict";

const { BlobServiceClient } = require("@azure/storage-blob");

const PACKAGES_CONTAINER = process.env.PACKAGES_CONTAINER || "packages";

/**
 * Returns a BlobServiceClient constructed from the environment.
 * Supports both a full connection string and account-key credentials.
 */
function getBlobServiceClient() {
  const connectionString = process.env.AZURE_STORAGE_CONNECTION_STRING;
  if (!connectionString) {
    throw new Error("AZURE_STORAGE_CONNECTION_STRING environment variable is not set.");
  }
  return BlobServiceClient.fromConnectionString(connectionString);
}

/**
 * Ensures the packages container exists, creating it if absent.
 * @returns {import("@azure/storage-blob").ContainerClient}
 */
async function getContainerClient() {
  const client = getBlobServiceClient();
  const container = client.getContainerClient(PACKAGES_CONTAINER);
  await container.createIfNotExists({ access: "blob" });
  return container;
}

/**
 * Constructs the blob name used to store a package version's tarball.
 * Convention: <name>/<version>/package.tar.gz
 * @param {string} name
 * @param {string} version
 * @returns {string}
 */
function packageBlobName(name, version) {
  return `${name}/${version}/package.tar.gz`;
}

/**
 * Constructs the blob name for a package's metadata JSON.
 * Convention: <name>/metadata.json
 * @param {string} name
 * @returns {string}
 */
function metadataBlobName(name) {
  return `${name}/metadata.json`;
}

/**
 * Uploads a buffer as a blob.
 * @param {string} blobName
 * @param {Buffer} data
 * @param {string} contentType
 */
async function uploadBlob(blobName, data, contentType = "application/octet-stream") {
  const container = await getContainerClient();
  const blockBlob = container.getBlockBlobClient(blobName);
  await blockBlob.upload(data, data.length, {
    blobHTTPHeaders: { blobContentType: contentType },
  });
  return blockBlob.url;
}

/**
 * Downloads a blob as a Buffer.
 * Returns null when the blob does not exist.
 * @param {string} blobName
 * @returns {Promise<Buffer|null>}
 */
async function downloadBlob(blobName) {
  const container = await getContainerClient();
  const blockBlob = container.getBlockBlobClient(blobName);
  const exists = await blockBlob.exists();
  if (!exists) return null;
  const response = await blockBlob.downloadToBuffer();
  return response;
}

/**
 * Deletes a blob if it exists.
 * @param {string} blobName
 */
async function deleteBlob(blobName) {
  const container = await getContainerClient();
  const blockBlob = container.getBlockBlobClient(blobName);
  await blockBlob.deleteIfExists();
}

/**
 * Lists all blob names that match an optional prefix.
 * @param {string} [prefix]
 * @returns {Promise<string[]>}
 */
async function listBlobs(prefix = "") {
  const container = await getContainerClient();
  const names = [];
  for await (const blob of container.listBlobsFlat({ prefix })) {
    names.push(blob.name);
  }
  return names;
}

module.exports = {
  getContainerClient,
  packageBlobName,
  metadataBlobName,
  uploadBlob,
  downloadBlob,
  deleteBlob,
  listBlobs,
};

"use strict";

const { describe, it, expect, beforeEach } = require("@jest/globals");

// ---------------------------------------------------------------------------
// Inline mock for the @azure/storage-blob module so no real Azure connection
// is needed during unit tests.
// ---------------------------------------------------------------------------

// Stored blobs: Map<blobName, Buffer>
let mockBlobStore = new Map();

jest.mock("@azure/storage-blob", () => {
  const fakeBlockBlobClient = (name) => ({
    exists: async () => mockBlobStore.has(name),
    upload: async (data) => {
      mockBlobStore.set(name, Buffer.from(data));
      return { url: `https://fake.blob.core.windows.net/packages/${name}` };
    },
    downloadToBuffer: async () => {
      if (!mockBlobStore.has(name)) throw new Error("Blob not found");
      return mockBlobStore.get(name);
    },
    deleteIfExists: async () => {
      mockBlobStore.delete(name);
    },
    url: `https://fake.blob.core.windows.net/packages/${name}`,
  });

  const fakeContainerClient = {
    createIfNotExists: async () => {},
    getBlockBlobClient: (name) => fakeBlockBlobClient(name),
    listBlobsFlat: function* ({ prefix = "" } = {}) {
      for (const [name] of mockBlobStore) {
        if (name.startsWith(prefix)) yield { name };
      }
    },
  };

  return {
    BlobServiceClient: {
      fromConnectionString: () => ({
        getContainerClient: () => fakeContainerClient,
      }),
    },
  };
});

// Set required env vars before importing storage utils.
process.env.AZURE_STORAGE_CONNECTION_STRING = "DefaultEndpointsProtocol=https;AccountName=fake;AccountKey=ZmFrZWtleQ==;EndpointSuffix=core.windows.net";
process.env.PACKAGES_CONTAINER = "packages";

const storage = require("../src/utils/storage");

describe("storage utilities", () => {
  beforeEach(() => {
    mockBlobStore.clear();
  });

  it("uploadBlob stores data and returns a URL", async () => {
    const url = await storage.uploadBlob("test/1.0.0/package.tar.gz", Buffer.from("data"), "application/gzip");
    expect(typeof url).toBe("string");
    expect(url).toContain("test/1.0.0/package.tar.gz");
  });

  it("downloadBlob retrieves stored data", async () => {
    const data = Buffer.from("hello lua");
    await storage.uploadBlob("pkg/metadata.json", data, "application/json");
    const result = await storage.downloadBlob("pkg/metadata.json");
    expect(result).toEqual(data);
  });

  it("downloadBlob returns null for a missing blob", async () => {
    const result = await storage.downloadBlob("nonexistent/metadata.json");
    expect(result).toBeNull();
  });

  it("deleteBlob removes a stored blob", async () => {
    await storage.uploadBlob("todel/metadata.json", Buffer.from("x"), "application/json");
    await storage.deleteBlob("todel/metadata.json");
    const result = await storage.downloadBlob("todel/metadata.json");
    expect(result).toBeNull();
  });

  it("listBlobs returns all blob names", async () => {
    await storage.uploadBlob("alpha/metadata.json", Buffer.from("a"), "application/json");
    await storage.uploadBlob("beta/metadata.json", Buffer.from("b"), "application/json");
    const names = await storage.listBlobs();
    expect(names).toContain("alpha/metadata.json");
    expect(names).toContain("beta/metadata.json");
  });

  it("listBlobs filters by prefix", async () => {
    await storage.uploadBlob("alpha/metadata.json", Buffer.from("a"), "application/json");
    await storage.uploadBlob("beta/metadata.json", Buffer.from("b"), "application/json");
    const names = await storage.listBlobs("alpha/");
    expect(names).toContain("alpha/metadata.json");
    expect(names).not.toContain("beta/metadata.json");
  });

  it("packageBlobName returns the correct path", () => {
    expect(storage.packageBlobName("mypkg", "1.2.3")).toBe("mypkg/1.2.3/package.tar.gz");
  });

  it("metadataBlobName returns the correct path", () => {
    expect(storage.metadataBlobName("mypkg")).toBe("mypkg/metadata.json");
  });
});

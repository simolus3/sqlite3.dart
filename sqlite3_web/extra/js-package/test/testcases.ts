import { test as baseTest, describe, onTestFinished, expect } from "vitest";

import type * as sqlite from "../lib/index";
import type { WebSqlite, ConnectOptions, Database } from "../lib/index";

// @ts-expect-error
import workerUrl from "../assets/worker_testing.js?url";
// @ts-expect-error
import wasmCiphersUrl from "../assets/sqlite3mc.wasm?url";

export function sqliteTestCases(module: typeof sqlite) {
  const test = baseTest.extend<{ sqlite: WebSqlite }>({
    sqlite: async ({}, use) => {
      await use(
        module.openWebSqlite({
          workers: module.defaultWorkerConnector(workerUrl),
          wasmUri: wasmCiphersUrl,
          async handleCustomRequest(request) {
            expect(request).toStrictEqual("customRequestFromServer");
            return "client-side response";
          },
        }),
      );
    },
  });

  const databaseTest = test.extend<{
    database: {
      name: string;
      connect: (options?: ConnectOptions) => Promise<Database>;
    };
  }>({
    database: async ({ sqlite }, use) => {
      const name = `db-${crypto.randomUUID()}`;

      await use({
        name,
        connect: async (options) => {
          const db = await sqlite.connect(
            name,
            module.DatabaseImplementation.inMemoryShared,
            options,
          );
          onTestFinished(() => db.close());
          return db;
        },
      });
    },
  });

  test("feature detection", async ({ sqlite }) => {
    const results = await sqlite.runFeatureDetection();

    console.log(`${results}`);
  });

  test("close", async ({ sqlite }) => {
    const db = await sqlite.connect(
      `db-${crypto.randomUUID()}`,
      module.DatabaseImplementation.inMemoryShared,
    );
    await db.execute("SELECT 1");
    sqlite.close();

    await db.closed;
    await expect(db.execute("SELECT 1")).rejects.toThrow();
  });

  describe("database", () => {
    databaseTest("smoke test", async ({ database }) => {
      const db = await database.connect();
      const { result } = await db.select("SELECT 1");

      expect(result).toStrictEqual({
        columnNames: ["1"],
        tableNames: null,
        rows: [[1]],
        types: new Uint8Array([1]).buffer,
      });
    });

    databaseTest("execute", async ({ database }) => {
      const db = await database.connect();
      const { result } = await db.execute("CREATE TABLE foo (bar);");

      expect(result).toStrictEqual(null);
    });

    databaseTest("locks and aborts", async ({ database }) => {
      const db = await database.connect();

      const [token, releaseToken] = await new Promise<[number, () => void]>(
        (resolve) => {
          db.requestLock(async (token) => {
            return new Promise<void>((returnToken) => {
              resolve([token, returnToken]);
            });
          });
        },
      );

      await db.execute("SELECT 1", { token });
      await expect(
        db.select("SELECT 2", { abort: AbortSignal.abort() }),
      ).rejects.toThrow();
      await expect(
        db.select("SELECT 3", { abort: AbortSignal.timeout(50) }),
      ).rejects.toThrow();

      const completesEventually = db.select("SELECT 3");
      releaseToken();
      await completesEventually;
    });

    databaseTest("vfs access", async ({ database }) => {
      const db = await database.connect({ onlyOpenVfs: true });
      const fs = db.fileSystem;

      expect(await fs.exists("database")).toBeFalsy();
      await db.execute("pragma user_version = 2");
      expect(await fs.exists("database")).toBeTruthy();

      const bytes = await fs.readFile("database");
      expect(bytes).toHaveLength(8192); // default page size
    });

    databaseTest("additional connection", async ({ database }) => {
      const firstInstance = await database.connect();
      await firstInstance.execute("CREATE TABLE foo (BAR INTEGER);");
      await firstInstance.execute("INSERT INTO foo DEFAULT VALUES");

      const endpoint = await firstInstance.additionalConnection();
      const second = await module.connectToPort(endpoint);
      expect(
        (await second.select("SELECT * FROM foo")).result.rows,
      ).toHaveLength(1);
      await second.execute("DELETE FROM foo");

      expect(
        (await firstInstance.select("SELECT * FROM foo")).result.rows,
      ).toHaveLength(0);
    });

    databaseTest("custom request", async ({ database }) => {
      const instance = await database.connect();
      const response = await instance.customRequest("foo");
      expect(response).toStrictEqual("client-side response");
    });

    databaseTest("bind types", async ({ database }) => {
      const instance = await database.connect();
      const { result } = await instance.select("SELECT typeof(?), typeof(?)", {
        parameters: [3, 3],
        types: new Uint8Array([1, 3]).buffer,
      });

      expect(result.rows).toStrictEqual([["integer", "real"]]);
    });

    databaseTest("result types", async ({ database }) => {
      const instance = await database.connect();
      const { result } = await instance.select("SELECT 3, 3.0");

      expect(result.rows).toStrictEqual([[3, 3]]);
      expect(result.types).toStrictEqual(new Uint8Array([1, 3]).buffer);
    });

    baseTest("encryption", async () => {
      const sqlite = module.openWebSqlite({
        workers: module.defaultWorkerConnector(workerUrl),
        wasmUri: wasmCiphersUrl,
        handleCustomRequest: undefined,
      });
      const db = await sqlite.connect(
        `db-${crypto.randomUUID()}`,
        module.DatabaseImplementation.inMemoryShared,
        { enableEncryptedVfs: true },
      );

      const getCipher = await db.select("pragma cipher");
      expect(getCipher.result.rows).toStrictEqual([["chacha20"]]);

      await db.execute("pragma key = 'foo'");
      await db.execute("pragma user_version = 2");
    });
  });
}

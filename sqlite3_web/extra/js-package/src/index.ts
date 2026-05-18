import { Database, WebSqlite } from "./api";
import { WebEndpoint } from "./channel";
import { ClientInitializationOptions, DatabaseClient } from "./client";
import { unsupportedWorkerConnector } from "./worker_connector";

export * from "./api";
export {
  type WorkerConnector,
  type WorkerHandle,
  defaultWorkerConnector,
} from "./worker_connector";
export { type ClientInitializationOptions } from "./client";
export { type WebEndpoint } from "./channel";

/**
 * Prepares a {@link WebSqlite} instance.
 *
 * @param options Provides URIs for workers and WebAssembly modules to load.
 */
export function openWebSqlite(options: ClientInitializationOptions): WebSqlite {
  return new DatabaseClient(options);
}

/**
 * Establishes a connection to a database that has already been opened.
 *
 * @param port An endpoint obtained from {@link Database.additionalConnection}.
 */
export async function connectToPort(port: WebEndpoint): Promise<Database> {
  const client = new DatabaseClient({
    workers: unsupportedWorkerConnector,
    wasmUri: "",
  });

  return await client.connectToExisting(port);
}

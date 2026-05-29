import { Database, WebSqlite } from "./api.js";
import { WebEndpoint } from "./channel.js";
import { ClientInitializationOptions, DatabaseClient } from "./client.js";
import { unsupportedWorkerConnector } from "./worker_connector.js";

export * from "./api.js";
export {
  type WorkerConnector,
  type WorkerHandle,
  defaultWorkerConnector,
} from "./worker_connector.js";
export { type ClientInitializationOptions } from "./client.js";
export { type WebEndpoint } from "./channel.js";

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

  return await client._internal_connectToExisting(port);
}

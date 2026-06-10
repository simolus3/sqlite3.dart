import {
  ConnectOptions,
  ConnectToRecommendedResult,
  Database,
  DatabaseExecuteOptions,
  DatabaseImplementation,
  DatabaseResult,
  ExistingDatabase,
  FeatureDetectionResult,
  FileSystem,
  FileType,
  MissingBrowserFeature,
  ResultSet,
  StorageMode,
  WebSqlite,
} from "./api.js";
import {
  createChannel,
  ProtocolChannel,
  ProtocolChannelOptions,
  WebEndpoint,
} from "./channel.js";
import {
  indexedDb,
  inMemory,
  opfs,
  throughDedicatedWorker,
  throughSharedWorker,
} from "./constants.js";
import {
  Request,
  Response,
  Message,
  SimpleSuccessResponse,
  ConnectRequest,
  DedicatedCompatibilityCheck,
  SharedCompatibilityCheck,
  extractTransferrable,
  OpenRequest,
  typeSimpleSuccessResponse,
  RequestExclusiveLock,
  typeRequestExclusiveLock,
  typeConnectRequest,
  typeCustomRequest,
  typeReleaseLock,
  ReleaseLock,
  OpenAdditionalConnection,
  EndpointResponse,
  typeEndpointResponse,
  typeOpenAdditionalConnection,
  CustomRequest,
  RunQuery,
  RowsResponse,
  typeRowsResponse,
  typeRunQuery,
  FileSystemAccess,
  typeFileSystemAccess,
  FileSystemExistsQuery,
  typeFileSystemExistsQuery,
  CloseDatabase,
  typeCloseDatabase,
  typeOpenRequest,
  typeDedicatedCompatibilityCheck,
  typeSharedCompatibilityCheck,
} from "./generated_protocol.js";
import { CompatibilityResult, typeCodesForValues } from "./types.js";
import { wrapFeatureDetectionResult } from "./utils.js";
import { WorkerConnector, WorkerHandle } from "./worker_connector.js";

class WorkerConnection extends ProtocolChannel {
  override async _internal_serveRequest(request: Request): Promise<Response> {
    if (request.t == typeCustomRequest) {
    }

    throw new Error("Method not implemented.");
  }

  override _internal_handleNotification(): void {
    // Ignore notifications, the JS package doesn't support update/commit/rollback hooks currently.
  }

  async _internal_requestDatabase(
    request: Omit<OpenRequest, "i">,
  ): Promise<RemoteDatabase> {
    const response = await this._internal_sendRequest<
      OpenRequest,
      SimpleSuccessResponse
    >(request, typeSimpleSuccessResponse);

    return new RemoteDatabase(this, response.r as number);
  }
}

export interface ClientInitializationOptions {
  /**
   * How to open web workers. Use {@link defaultWorkerConnector} as a sensible default.
   */
  workers: WorkerConnector;
  /**
   * The URI of the `sqlite3.wasm` or `sqlite3mc.wasm` module to load.
   */
  wasmUri: string;
  handleCustomRequest?: ((request: unknown) => Promise<unknown>) | undefined;
}

export class DatabaseClient implements WebSqlite {
  readonly #workerInitializationLock = `web-sqlite-init-${crypto.randomUUID()}`;
  readonly #missingFeatures = new Set<MissingBrowserFeature>();
  readonly #options: ClientInitializationOptions;

  #startedWorkers = false;
  #connectionToDedicated?: WorkerConnection;
  #connectionToShared?: WorkerConnection;
  #connectionToDedicatedInShared?: WorkerConnection;

  constructor(options: ClientInitializationOptions) {
    this.#options = options;
  }

  async #startWorkers() {
    await navigator.locks.request(this.#workerInitializationLock, async () => {
      if (this.#startedWorkers) {
        return;
      }
      this.#startedWorkers = true;
      await this.#startDedicated();
      await this.#startShared();
    });
  }

  #wrapAsConnection(channel: ProtocolChannelOptions) {
    return new WorkerConnection(channel);
  }

  async #startDedicated() {
    let dedicated: WorkerHandle | null = null;
    try {
      dedicated = this.#options.workers.spawnDedicatedWorker();
    } catch {
      // Add missing feature and move on.
    }

    if (dedicated == null) {
      this.#missingFeatures.add("dedicatedWorkers");
      return;
    }

    const [endpoint, channel] = await createChannel({
      _internal_errors: dedicated.targetForErrorEvents,
    });
    const request = {
      t: typeConnectRequest,
      i: 0,
      d: null,
      r: endpoint,
    } satisfies Message;
    dedicated.postMessage(request, extractTransferrable(request));
    this.#connectionToDedicated = this.#wrapAsConnection(channel);
  }

  async #startShared() {
    let shared: WorkerHandle | null = null;
    try {
      shared = this.#options.workers.spawnSharedWorker();
    } catch {
      // Add missing feature and move on.
    }

    if (shared == null) {
      this.#missingFeatures.add("sharedWorkers");
      return;
    }

    const [endpoint, channel] = await createChannel({
      _internal_errors: shared.targetForErrorEvents,
    });
    const request = {
      t: typeConnectRequest,
      i: 0,
      d: null,
      r: endpoint,
    } satisfies Message;
    shared.postMessage(request, extractTransferrable(request));
    this.#connectionToShared = this.#wrapAsConnection(channel);
  }

  async #connectToDedicatedInShared() {
    return navigator.locks.request(this.#workerInitializationLock, async () => {
      if (this.#connectionToDedicatedInShared != null) {
        return this.#connectionToDedicatedInShared;
      }

      const [endpoint, channel] = await createChannel();
      this.#connectionToShared!._internal_sendRequest<
        ConnectRequest,
        SimpleSuccessResponse
      >(
        { t: typeConnectRequest, d: null, r: endpoint },
        typeSimpleSuccessResponse,
      );

      return (this.#connectionToDedicatedInShared =
        this.#wrapAsConnection(channel));
    });
  }

  async deleteDatabase(name: string, storage: StorageMode): Promise<void> {
    switch (storage) {
      case opfs:
        const pathSegments = ["drift_db", ...name.split("/")];

        try {
          let parent: FileSystemDirectoryHandle =
            await navigator.storage.getDirectory();
          let handle: FileSystemDirectoryHandle = parent;

          for (const segment of pathSegments) {
            if (segment.length == 0) continue;

            parent = handle;
            handle = await handle.getDirectoryHandle(name);
          }

          await parent.removeEntry(handle.name, { recursive: true });
        } catch (e) {
          if (
            e instanceof DOMException &&
            (e.name == "NotFoundError" || e.name == "TypeMismatchError")
          ) {
            // Directory doesn't exist, ignore.
            return;
          } else {
            throw e;
          }
        }

        break;
      case indexedDb: {
        const request = indexedDB.deleteDatabase(name);
        await new Promise<void>((resolve, reject) => {
          request.onsuccess = () => resolve();
          request.onerror = () => reject(request.error!);
          request.onblocked = () =>
            reject(new Error("deleting idb database blocked"));
        });
        break;
      }

      case inMemory:
        break; // Nothing to do here
    }
  }

  async runFeatureDetection(options?: {
    databaseName?: string;
  }): Promise<FeatureDetectionResult> {
    const dbName = options?.databaseName ?? null;
    await this.#startWorkers();

    const existing: ExistingDatabase[] = [];
    const available: DatabaseImplementation[] = [];

    function handleCompatibilityResult(result: CompatibilityResult) {
      for (let i = 0; i < result.a.length; i++) {
        const storage = result.a[i * 2] as StorageMode;
        const name = result.a[i * 2 + 1]!;
        existing.push({ name, storage });
      }
    }

    const dedicatedCompatibilityCheck = async (
      connection: WorkerConnection,
    ) => {
      let response: SimpleSuccessResponse;

      try {
        response = await connection._internal_sendRequest<
          DedicatedCompatibilityCheck,
          SimpleSuccessResponse
        >(
          { t: typeDedicatedCompatibilityCheck, d: dbName },
          typeSimpleSuccessResponse,
          AbortSignal.timeout(workerInitializationTimeout),
        );
      } catch {
        return;
      }

      const result = response.r as CompatibilityResult;
      handleCompatibilityResult(result);
      const canUseOpfs = result.c;
      const canUseIndexedDb = result.d;
      const opfsSupportsReadWriteUnsafe = result.g;

      if (!canUseOpfs) {
        this.#missingFeatures.add("fileSystemAccess");
      }
      if (!canUseIndexedDb) {
        this.#missingFeatures.add("indexedDb");
      }
      if (!opfsSupportsReadWriteUnsafe) {
        this.#missingFeatures.add("createSyncAccessHandleReadWriteUnsafe");
      }

      if (canUseOpfs) {
        available.push(DatabaseImplementation.opfsWithExternalLocksWorkaround);
        if (opfsSupportsReadWriteUnsafe) {
          available.push(DatabaseImplementation.opfsWithExternalLocks);
        }
      }
    };

    const sharedCompatibilityCheck = async (connection: WorkerConnection) => {
      let response: SimpleSuccessResponse;

      try {
        response = await connection._internal_sendRequest<
          SharedCompatibilityCheck,
          SimpleSuccessResponse
        >(
          { t: typeSharedCompatibilityCheck, d: dbName },
          typeSimpleSuccessResponse,
          AbortSignal.timeout(workerInitializationTimeout),
        );
      } catch {
        return;
      }

      const result = response.r as CompatibilityResult;
      handleCompatibilityResult(result);
      const canUseOpfs = result.c;
      const canUseIndexedDb = result.d;
      const sharedCanSpawnDedicated = result.b;

      if (canUseIndexedDb) {
        available.push(DatabaseImplementation.indexedDbShared);
      } else {
        this.#missingFeatures.add(indexedDb);
      }

      if (canUseOpfs) {
        available.push(DatabaseImplementation.opfsShared);
      } else if (sharedCanSpawnDedicated) {
        // Only report OPFS as unavailable if we can spawn dedicated workers.
        // If we can't, it's known that we can't use OPFS.
        this.#missingFeatures.add("fileSystemAccess");
      }

      available.push(DatabaseImplementation.inMemoryShared);
      if (!sharedCanSpawnDedicated) {
        this.#missingFeatures.add("dedicatedWorkersInSharedWorkers");
      }
    };

    if (this.#connectionToDedicated) {
      await dedicatedCompatibilityCheck(this.#connectionToDedicated);
    }
    if (this.#connectionToShared) {
      await sharedCompatibilityCheck(this.#connectionToShared);
    }

    return wrapFeatureDetectionResult({
      missingFeatures: [...this.#missingFeatures],
      existingDatabases: existing,
      availableImplementations: available,
    });
  }

  async connect(
    name: string,
    implementation: DatabaseImplementation,
    options?: ConnectOptions,
  ): Promise<Database> {
    await this.#startWorkers();
    let connection: WorkerConnection;
    switch (implementation.access) {
      case throughSharedWorker:
        if (implementation.storage == opfs) {
          // Shared workers don't support OPFS, but we can spawn a dedicated
          // worker inside of the shared worker and connect through that one.
          connection = await this.#connectToDedicatedInShared();
        } else {
          connection = this.#connectionToShared!;
        }

        break;
      case throughDedicatedWorker:
        connection = this.#connectionToDedicated!;
    }

    let internalFileSystemImpl: "s" | "l" | "x" | "y" | "i" | "m";
    switch (implementation.storage) {
      case opfs:
        if (implementation === DatabaseImplementation.opfsShared) {
          internalFileSystemImpl = "s";
        } else if (
          implementation === DatabaseImplementation.opfsWithExternalLocks
        ) {
          internalFileSystemImpl = "x";
        } else if (
          implementation ===
          DatabaseImplementation.opfsWithExternalLocksWorkaround
        ) {
          internalFileSystemImpl = "y";
        } else {
          throw new Error("Unknown OPFS file system impl");
        }
        break;
      case indexedDb:
        internalFileSystemImpl = "i";
        break;
      case inMemory:
        internalFileSystemImpl = "m";
        break;
    }

    return connection._internal_requestDatabase({
      t: typeOpenRequest,
      u: this.#options.wasmUri,
      d: name,
      s: internalFileSystemImpl,
      o: options?.onlyOpenVfs ?? false,
      a: {
        useMultipleCiphersVfs: options?.enableEncryptedVfs ?? false,
      },
    });
  }

  async connectToRecommended(
    name: string,
    options?: ConnectOptions,
  ): Promise<ConnectToRecommendedResult> {
    const probed = await this.runFeatureDetection({ databaseName: name });

    // If we haev an existing database in storage, we want to keep using it
    // even if we can use additional / better storage options after a browser
    // or package update.
    let availableImplementations = [...probed.availableImplementations];
    checkExisting: for (const {
      storage,
      name: existingName,
    } of probed.existingDatabases) {
      if (name === existingName) {
        availableImplementations = availableImplementations.filter(
          (e) => e.storage == storage,
        );
        break checkExisting;
      }
    }

    if (availableImplementations.length == 0) {
      throw new Error("No database implementations available");
    }

    // Sort by descending preference
    availableImplementations.sort((a, b) => b.preference - a.preference);
    const implementation = availableImplementations[0]!;
    const database = await this.connect(name, implementation, options);
    return {
      database,
      features: probed,
      implementation,
    };
  }

  async _internal_connectToExisting({ port, lockName }: WebEndpoint) {
    // We always have zero as a database id for these pre-existing connections, as the worker will identify it through
    // the unique send port.
    return new RemoteDatabase(
      this.#wrapAsConnection({
        _internal_port: port,
        _internal_lockName: lockName,
      }),
      0,
    );
  }

  close(): void {
    this.#connectionToShared?._internal_close();
    this.#connectionToDedicatedInShared?._internal_close();
    this.#connectionToDedicated?._internal_close();
  }
}

class RemoteDatabase implements Database {
  closed: Promise<void>;
  isClosed: boolean = false;
  #markClosed!: () => void;

  constructor(
    readonly _internal_connection: WorkerConnection,
    readonly _internal_databaseId: number,
  ) {
    this.closed = new Promise((resolve) => {
      this.#markClosed = () => {
        this.isClosed = true;
        resolve();
      };
    });

    this._internal_connection._internal_closed.finally(this.#markClosed);
  }

  public get fileSystem(): FileSystem {
    return new RemoteFileSystem(this);
  }

  async close(): Promise<void> {
    if (!this.isClosed) {
      this._internal_connection._internal_sendRequest<
        CloseDatabase,
        SimpleSuccessResponse
      >(
        { t: typeCloseDatabase, d: this._internal_databaseId },
        typeSimpleSuccessResponse,
      );
      this.#markClosed();
    }

    await this.closed;
  }

  async #databaseQuery<RS extends ResultSet | void>(
    includeResultSet: boolean,
    sql: string,
    options?: DatabaseExecuteOptions,
  ) {
    const parameters = options?.parameters ?? [];
    const rows = await this._internal_connection._internal_sendRequest<
      RunQuery,
      RowsResponse
    >(
      {
        t: typeRunQuery,
        s: sql,
        p: parameters,
        v: typeCodesForValues(parameters),
        z: options?.token ?? null,
        r: includeResultSet,
        c: options?.checkInTransaction ?? false,
        d: this._internal_databaseId,
      },
      typeRowsResponse,
      options?.abort,
    );

    const columnNames = rows.c;
    const tableNames = rows.n;

    return {
      result: (columnNames == null
        ? null
        : ({
            columnNames,
            tableNames: tableNames!,
            rows: rows.r as (string | null | Uint8Array | number)[][],
          } satisfies ResultSet)) as unknown as RS,
      autocommit: rows.x,
      lastInsertRowId: rows.y,
    };
  }

  async execute(
    sql: string,
    options?: DatabaseExecuteOptions,
  ): Promise<DatabaseResult<void>> {
    return this.#databaseQuery(false, sql, options);
  }

  select(
    sql: string,
    options?: DatabaseExecuteOptions,
  ): Promise<DatabaseResult<ResultSet>> {
    return this.#databaseQuery(true, sql, options);
  }

  async requestLock<T>(
    body: (token: number) => Promise<T>,
    options?: { abort?: AbortSignal | undefined },
  ): Promise<T> {
    const response = await this._internal_connection._internal_sendRequest<
      RequestExclusiveLock,
      SimpleSuccessResponse
    >(
      {
        t: typeRequestExclusiveLock,
        d: this._internal_databaseId,
      },
      typeSimpleSuccessResponse,
      options?.abort,
    );
    const lockId = response.r as number;

    try {
      return await body(lockId);
    } finally {
      await this._internal_connection._internal_sendRequest<
        ReleaseLock,
        SimpleSuccessResponse
      >(
        {
          t: typeReleaseLock,
          d: this._internal_databaseId,
          z: lockId,
        },
        typeSimpleSuccessResponse,
      );
    }
  }

  async customRequest(
    request: unknown,
    options: { token?: number | undefined; abort?: AbortSignal },
  ): Promise<unknown> {
    const { r } = await this._internal_connection._internal_sendRequest<
      CustomRequest,
      SimpleSuccessResponse
    >(
      {
        t: typeCustomRequest,
        d: this._internal_databaseId,
        r: request,
        z: options?.token ?? null,
      },
      typeSimpleSuccessResponse,
      options?.abort,
    );
    return r;
  }

  async additionalConnection(): Promise<WebEndpoint> {
    const response = await this._internal_connection._internal_sendRequest<
      OpenAdditionalConnection,
      EndpointResponse
    >(
      {
        t: typeOpenAdditionalConnection,
        d: this._internal_databaseId,
      },
      typeEndpointResponse,
    );
    return response.r;
  }
}

class RemoteFileSystem implements FileSystem {
  readonly #db: RemoteDatabase;

  constructor(db: RemoteDatabase) {
    this.#db = db;
  }

  get #connection() {
    return this.#db._internal_connection;
  }

  async exists(file: FileType): Promise<boolean> {
    const { r } = await this.#connection._internal_sendRequest<
      FileSystemExistsQuery,
      SimpleSuccessResponse
    >(
      {
        t: typeFileSystemExistsQuery,
        d: this.#db._internal_databaseId,
        f: fileTypeIndex(file),
      },
      typeSimpleSuccessResponse,
    );

    return r as boolean;
  }

  async readFile(file: FileType): Promise<Uint8Array> {
    const { r } = await this.#connection._internal_sendRequest<
      FileSystemAccess,
      SimpleSuccessResponse
    >(
      {
        t: typeFileSystemAccess,
        d: this.#db._internal_databaseId,
        f: fileTypeIndex(file),
        b: null,
      },
      typeSimpleSuccessResponse,
    );

    const buffer = r as ArrayBuffer;
    return new Uint8Array(buffer);
  }

  async writeFile(type: FileType, content: Uint8Array): Promise<void> {
    // We need to copy since we're about to transfer contents over.
    const copy = new Uint8Array(content);
    await this.#connection._internal_sendRequest<
      FileSystemAccess,
      SimpleSuccessResponse
    >(
      {
        t: typeFileSystemAccess,
        d: this.#db._internal_databaseId,
        f: fileTypeIndex(type),
        b: copy.buffer,
      },
      typeSimpleSuccessResponse,
    );
  }
}

function fileTypeIndex(type: FileType): number {
  return type == "database" ? 0 : 1;
}

const workerInitializationTimeout = 1_000;

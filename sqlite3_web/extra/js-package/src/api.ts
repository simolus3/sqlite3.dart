import { WebEndpoint } from "./channel.js";
import {
  indexedDb,
  inMemory,
  opfs,
  throughDedicatedWorker,
  throughSharedWorker,
} from "./constants.js";

/**
 * Available locations to store database content in browsers.
 */
export type StorageMode = "opfs" | "indexedDb" | "inMemory";

/**
 * Describes how a database can be accessed.
 */
export type AccessMode = "throughSharedWorker" | "throughDedicatedWorker";

/**
 * A supported mechanism to manage SQLite files on the web.
 *
 * Due to the large variety of browsers and the web standards they support, a number of implementations are available.
 * This library can automatically pick one after feature detection, but it's also possible to open databases with a
 * selected implementation.
 */
export class DatabaseImplementation {
  readonly #name: string;

  private constructor(
    name: string,
    readonly preference: number,
    readonly storage: StorageMode,
    readonly access: AccessMode,
  ) {
    this.#name = name;
  }

  toString() {
    return this.#name;
  }

  /**
   * Host an in-memory database in a shared worker.
   *
   * This isn't all that useful as it provides no persistence, but it's convenient for testing.
   */
  static readonly inMemoryShared = new DatabaseImplementation(
    "inMemoryShared",
    5,
    inMemory,
    throughSharedWorker,
  );

  /**
   * Opens a SQLite database stored in IndexedDB in a shared worker.
   */
  static readonly indexedDbShared = new DatabaseImplementation(
    "indexedDbShared",
    15,
    indexedDb,
    throughSharedWorker,
  );

  /**
   * Opens a synchronous database stored in OPFS.
   *
   * The database is opened with the non-standard `readwrite-unsafe` option, and the navigator locks API is used to
   * ensure two tabs don't access the same database concurrently.
   */
  static readonly opfsWithExternalLocks = new DatabaseImplementation(
    "opfsWithExternalLocks",
    22,
    opfs,
    throughDedicatedWorker,
  );

  /**
   * Opens a synchronous database stored in OPFS.
   *
   * This is similar to {@link opfsWithExternalLocks}, but also supports browsers without `readwrite-unsafe`.
   * It works by opening file handles on most database accesses, which is substantially slower.
   */
  static readonly opfsWithExternalLocksWorkaround = new DatabaseImplementation(
    "opfsWithExternalLocksWorkaround",
    21,
    opfs,
    throughDedicatedWorker,
  );

  /**
   * Open a synchronous database stored in OPFS.
   *
   * This works by letting a shared worker spawn a dedicated worker. This is supposed to work according to web
   * standards, but currently only implemented in Firefox.
   */
  static readonly opfsShared = new DatabaseImplementation(
    "opfsShared",
    25,
    opfs,
    throughSharedWorker,
  );
}

/**
 * Files persisted for SQLite databases (the main database file and a rollback
 * journal).
 */
export type FileType = "database" | "journal";

/**
 * A feature this package has probed for that is not supported in the current browser.
 *
 * This may be used to understand why a specific database implementation is unavailable.
 */
export type MissingBrowserFeature =
  | "sharedWorkers"
  | "dedicatedWorkers"
  | "dedicatedWorkersInSharedWorkers"
  | "fileSystemAccess"
  | "createSyncAccessHandleReadWriteUnsafe"
  | "indexedDb";

/**
 * The result of {@link WebSqlite.runFeatureDetection}, describing which browser features and databases are currently
 * available.
 */
export interface FeatureDetectionResult {
  /**
   * A list of features that were probed and found to be unsupported in the current browser.
   */
  missingFeatures: MissingBrowserFeature[];
  /**
   * All existing databases that have been found.
   *
   * Databases are only found reliably then a database name is passed to {@link WebSqlite.runFeatureDetection},
   * databases with another name might not be included here.
   */
  existingDatabases: ExistingDatabase[];
  /**
   * All available database implementations that can be used in the current browser.
   */
  availableImplementations: DatabaseImplementation[];
}

/**
 * A virtual file system used by a worker to persist database files.
 */
export interface FileSystem {
  /** Checks whether a given file exists. */
  exists(file: FileType): Promise<boolean>;
  /** Reads the entire database file. */
  readFile(file: FileType): Promise<Uint8Array>;
  /** Replaces a file, creating it if it doesn't exist. */
  writeFile(type: FileType, content: Uint8Array): Promise<void>;
}

/**
 * A data change notification from SQLite.
 */
export interface SqliteUpdate {
  kind: "insert" | "update" | "delete";
  tableName: string;
  rowId: number;
}

/**
 * A SQLite database instance opened on a web worker.
 */
export interface Database {
  /**
   * Provides access to the underlying virtual file system storing this database.
   */
  readonly fileSystem: FileSystem;

  /**
   * A future that resolves when the database is closed.
   *
   * Typically, databases are closed because {@link close} is called. For databases
   * opened with TODO however, it's possible that the original worker hosting the
   * database gets closed without this {@link Database} instance being closed explicitly.
   * In those cases, monitoring {@link closed} is useful to react to databases closing.
   */
  readonly closed: Promise<void>;

  /** Whether this database is currently closed. */
  readonly isClosed: boolean;

  /**
   * Closes this database and instructs the worker to release associated
   * resources.
   *
   * No methods may be called after a call to {@link close}.
   */
  close(): Promise<void>;

  /**
   * Executes an SQL statement, ignoring result rows.
   *
   * @param sql The SQL text to prepare and execute.
   * @param options Prepared statement parameters and additional options.
   */
  execute(
    sql: string,
    options?: DatabaseExecuteOptions,
  ): Promise<DatabaseResult<void>>;

  /**
   * Executes an SQL statement, returning result rows.
   *
   * @param sql The SQL text to prepare and execute.
   * @param options Prepared statement parameters and additional options.
   */
  select(
    sql: string,
    options?: DatabaseExecuteOptions,
  ): Promise<DatabaseResult<ResultSet>>;

  /**
   * Requests exclusive access to the database.
   *
   * @param body A callback to invoke with a lock token that can be passed in {@link DatabaseExecuteOptions}.
   * @param options An optional abort signal.
   */
  requestLock<T>(
    body: (token: number) => Promise<T>,
    options?: { abort?: AbortSignal | undefined },
  ): Promise<T>;

  /**
   * Sends a custom request to the worker hosting this database.
   *
   * This is an advanced feature and requires using this package with a custom worker instead of the default.
   */
  customRequest(
    request: unknown,
    options?: { token?: number | undefined; abort?: AbortSignal },
  ): Promise<unknown>;

  /**
   * Creates a {@link WebEndpoint} that can be used by another JavaScript context to connect to this database.
   *
   * After obtaining this value and sending it through message ports (remember to include {@link WebEndpoint.port} as
   * a transfer object), `connectToPort` can be used to open it as a database.
   */
  additionalConnection(): Promise<WebEndpoint>;
}

/**
 * Options for {@link Database.select} and {@link Database.execute}.
 */
export interface DatabaseExecuteOptions {
  /**
   * Prepared statement parameters to bind to the statement.
   */
  parameters?: (string | null | number | BigInt | Uint8Array)[] | undefined;

  /**
   * Whether to check the `autocommit` state of the database before running the statement.
   *
   * If you expect the database to be in a transaction, enable this option to make statements fail if `autocommit` is
   * enabled (that is, the database is in fact not in a transaction).
   */
  checkInTransaction?: boolean | undefined;
  /**
   * A lock token obtained from {@link Database.requestLock}.
   *
   * By default, each statement acquires its own temporary lock on the database. If you need to run multiple statements
   * with a guarantee that no other tab can access the database concurrently (e.g. for transactions), request a lock and
   * pass its token to queries.
   */
  token?: number | undefined;
  /**
   * An optional abort signal to abort queries, e.g. if no lock could be obtained in time.
   */
  abort?: AbortSignal | undefined;
}

/**
 * A list of rows returned by a SQLite statement.
 */
export interface ResultSet {
  /**
   * Names of result columns for each row.
   */
  columnNames: string[];
  /**
   * Table names for columns, if a result column directly selects from a table.
   */
  tableNames: (string | null)[];

  /**
   * All values for the statement.
   *
   * Each element in the outer array represents a row of the result set. Each inner array has exactly as many elements
   * as {@link columnNames}.
   */
  rows: (string | null | Uint8Array | number)[][];
}

/**
 * Wraps a {@link ResultSet} with additional information about the running statement.
 */
export interface DatabaseResult<T> {
  result: T;
  /**
   * Whether the database is in `autocommit` mode _after_ running the statement.
   */
  autocommit: boolean;
  /**
   * @see https://sqlite.org/c3ref/last_insert_rowid.html
   */
  lastInsertRowId: number;
}

/**
 * The result of {@link WebSqlite.connectToRecommended}, providing access to the database and information on why a
 * particular database implementation was chosen.
 */
export interface ConnectToRecommendedResult {
  /**
   * The asynchronous, worker-managed database connection.
   */
  database: Database;
  /**
   * Information about which features are supported on the current browser.
   */
  features: FeatureDetectionResult;
  /**
   * The database implementation used for {@link database}.
   */
  implementation: DatabaseImplementation;
}

/**
 * Provides asynchronous access to databases hosted in web workers.
 *
 * To obtain an instance of this, use `openWebSqlite`.
 */
export interface WebSqlite {
  /**
   * Deletes a database from the given storage, if it exists.
   *
   * This method should not be called while the database is open.
   */
  deleteDatabase(name: string, storage: StorageMode): Promise<void>;

  /**
   * Tries to find features related to storing and accessing datbaases.
   *
   * @param options Provide the name of the database you want to open, which allows probing whether it already exists.
   */
  runFeatureDetection(options?: {
    databaseName?: string;
  }): Promise<FeatureDetectionResult>;

  /**
   * Opens and connects to a SQLite database in a worker.
   *
   * Typically, one would use {@link connectToRecommended} instead.
   *
   * @param name The name of the database to open.
   * @param implementation The database implementation to use, see {@link DatabaseImplementation} for available options.
   * @param options Additional options, e.g. whether encryption should be enabled.
   */
  connect(
    name: string,
    implementation: DatabaseImplementation,
    options?: ConnectOptions,
  ): Promise<Database>;

  /**
   * Opens and connects to a SQLite database in a worker.
   *
   * @param name The name of the database to open.
   * @param options Additional options, e.g. whether encryption should be enabled.
   */
  connectToRecommended(
    name: string,
    options?: ConnectOptions,
  ): Promise<ConnectToRecommendedResult>;

  /**
   * Closes this instance and associated dedicated workers.
   */
  close(): void;
}

/**
 * Additional options for {@link WebSqlite.connect}.
 */
export interface ConnectOptions {
  /**
   * Whether to only open the file system implementation for the database.
   *
   * This is useful for cases where you just want to obtain a copy of the database file without opening a connection to
   * it.
   *
   * When this flag is enabled, this package will still open a connection on the first statement sent to the database (
   * if any).
   */
  onlyOpenVfs?: boolean | undefined;
  /**
   * Whether to enable an encrypted variant of the file system that would be opened by default.
   *
   * This is required to open encrypted databases, see this package's README for details.
   */
  enableEncryptedVfs?: boolean | undefined;

  /**
   * The maximum amount of prepared statements a worker should cache. It defaults to 0, which disables caching prepared
   * statements.
   */
  preparedStatementCacheSize?: number | undefined;
}

/**
 * An existing database available in the current browsing context.
 */
export interface ExistingDatabase {
  /**
   * The name (or path) of the database.
   */
  name: string;
  /**
   * Which filesystem API is used to store the database.
   */
  storage: StorageMode;
}

/**
 * An exception thrown when a operation fails on the remote worker.
 *
 * Because the worker is implemented in Dart, and Dart objects can't be sent
 * across send ports, {@link exception} is typically serialized and a string.
 */
export class RemoteError extends Error {
  constructor(message: string, cause?: DOMException | SqliteException) {
    super(message, { cause });
  }
}

export interface SqliteException {
  /**
   * SQLite extended result code.
   *
   * @see https://sqlite.org/rescode.html
   */
  extendedResultCode: number;

  /** An error message indicating what went wrong. */
  message: string;

  /** An optional explanation providing more detail on what went wrong. */
  explanation: string | undefined;

  /**
   * The SQL statement triggering this exception.
   *
   * This may be null when no prior statement is known.
   */
  causingStatement: string | undefined;

  /**
   * If this exception has a {@link causingStatement}, this contains the parameters
   * passed to that statement.
   */
  parametersToStatement: unknown[] | undefined;

  /**
   * An information description of what `package:sqlite3` in Dart was doing when
   * the exception occured, e.g. "preparing a statement".
   */
  operation: string | undefined;

  /**
   * If the error is related to a syntax error in SQL, contains the byte
   * offset of the token associated with wthe error.
   */
  offset: number | undefined;
}

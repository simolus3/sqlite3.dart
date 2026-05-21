/**
 * An interface responsible for opening web workers.
 *
 * This is mostly patchable for instrumentation purposes, a {@link defaultWorkerConnector} is a reasonable default for
 * almost all cases.
 */
export interface WorkerConnector {
  /** Spawns a dedicated database worker, or returns null if
   * dedicated workers are not supported. */
  spawnDedicatedWorker(): WorkerHandle | null;

  /** Spawns a shared database worker, or returns null if shared workers are
   * not supported.
   */
  spawnSharedWorker(): WorkerHandle | null;
}

/**
 * A {@link WorkerConnector} implemented by opening `Worker`s and `SharedWorkers` with regular web APIs.
 */
export function defaultWorkerConnector(uri: string | URL): WorkerConnector {
  return {
    spawnDedicatedWorker() {
      if (!("Worker" in globalThis)) return null;

      const worker = new Worker(uri, { name: "sqlite3_worker" });
      return {
        targetForErrorEvents: worker,
        postMessage(msg, transfer) {
          return worker.postMessage(msg, transfer);
        },
      };
    },
    spawnSharedWorker() {
      if (!("SharedWorker" in globalThis)) return null;

      const worker = new SharedWorker(uri);
      worker.port.start();
      return {
        targetForErrorEvents: worker,
        postMessage(msg, transfer) {
          return worker.port.postMessage(msg, transfer);
        },
      };
    },
  };
}

export const unsupportedWorkerConnector: WorkerConnector = {
  spawnDedicatedWorker() {
    return null;
  },
  spawnSharedWorker() {
    return null;
  },
} as const;

/** Handle to a shared or dedicated web worker. */
export interface WorkerHandle {
  /**
   * The web {@link EventTarget} representing the worker.
   *
   * This package will listen for errors on this target. Errors are assumed to
   * be fatal and unhandled errors from the worker will lead to the
   * connection closing.
   */
  targetForErrorEvents: EventTarget;

  /**
   * Posts a JavaScript value as a message to this worker (or, for shared workers,
   * the respective port).
   */
  postMessage(msg: unknown, transfer: Transferable[]): void;
}

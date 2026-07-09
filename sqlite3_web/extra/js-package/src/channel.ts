import {
  AbortRequest,
  extractTransferrable,
  Message,
  Request,
  Response,
  Notification,
  dispatchMessage,
  typeAbortRequest,
} from "./generated_protocol.js";
import {
  interpretResponseAsError,
  ReleaseLock,
  requestNavigatorLock,
  serializeError,
} from "./utils.js";

const disconnectMessage = "_disconnect";

export interface WebEndpoint {
  port: MessagePort;
  lockName: string | null;
}

export function randomLockName() {
  return `sqlite3-web-${crypto.randomUUID()}`;
}

export async function createChannel(
  options: Partial<ProtocolChannelOptions> = {},
): Promise<[WebEndpoint, ProtocolChannelOptions]> {
  const { port1, port2 } = new MessageChannel();
  // Request a random lock. We include its name in WebEndpoint. Since tabs return locks
  // when they're closed, that allows clients to reliably detect dead remotes.
  const lockName = randomLockName();
  const lock = await requestNavigatorLock(lockName);

  return [
    { port: port2, lockName },
    {
      ...options,
      _internal_port: port1,
      _internal_lockName: lockName,
      _internal_lock: lock,
    },
  ];
}

export interface ProtocolChannelOptions {
  _internal_port: MessagePort;
  _internal_lockName: string | null;
  _internal_lock?: ReleaseLock;
  _internal_errors?: EventTarget;
}

export abstract class ProtocolChannel {
  #port: MessagePort;
  #eventListener: (event: MessageEvent) => void;
  #heldLock?: ReleaseLock;

  #nextRequestId = 0;
  #outstandingRequests = new Map<
    number,
    { ok: (e: Response) => void; e: (e: unknown) => void }
  >();
  #closed = false;
  #closedPromise: Promise<void>;
  #markClosed!: () => void;

  constructor({
    _internal_port: port,
    _internal_lockName: lockName,
    _internal_lock: lock,
    _internal_errors: errors,
  }: ProtocolChannelOptions) {
    this.#port = port;
    this.#closedPromise = new Promise((resolve) => {
      this.#markClosed = () => {
        this.#closed = true;
        resolve();
      };
    });

    if (lock == null && lockName != null) {
      // Once this side is able to acquire the lock, the connection is closed.
      navigator.locks.request(lockName, () => {
        this.#markRemoteClosed();
      });
    }

    errors?.addEventListener(
      "error",
      (event) => {
        this.#markRemoteClosed((event as ErrorEvent).error);
      },
      { once: true },
    );

    this.#port.start();

    this.#eventListener = (event) => {
      if (event.data === disconnectMessage) {
        this.#markRemoteClosed();
      } else {
        this.#handleMessage(event.data);
      }
    };
    this.#port.addEventListener("message", this.#eventListener);
  }

  public get _internal_closed(): Promise<void> {
    return this.#closedPromise;
  }

  #handleMessage(message: Message) {
    const self = this;

    dispatchMessage(message, {
      _internal_whenAbortRequest() {
        // We don't currently support aborting requests handled on this side.
      },
      _internal_whenNotification(notification) {
        self._internal_handleNotification(notification);
      },
      _internal_whenResponse: function (message: Response) {
        const entry = self.#outstandingRequests.get(message.i);
        self.#outstandingRequests.delete(message.i);
        entry?.ok(message);
      },
      async _internal_whenRequest(message: Request) {
        let response: Response;
        try {
          response = await self._internal_serveRequest(message);
        } catch (e) {
          response = serializeError(message.i, "Error in JS client", e);
        }

        self.#port.postMessage(response, extractTransferrable(response));
      },
    });
  }

  #markRemoteClosed(cause?: unknown) {
    this.#closeLocally(cause);
  }

  #closeLocally(cause?: unknown) {
    this.#markClosed();
    this.#outstandingRequests.forEach((value) => {
      value.e(new Error(`Channel closed before receiving response: ${cause}`));
    });

    this.#port.postMessage(disconnectMessage);
    this.#port.removeEventListener("message", this.#eventListener);
    this.#port.close();

    this.#heldLock?.();
  }

  _internal_close() {
    return this.#closeLocally();
  }

  abstract _internal_serveRequest(
    request: Request,
  ): Promise<Response> | Response;

  abstract _internal_handleNotification(notification: Notification): void;

  _internal_sendNotification(notification: Notification) {
    this.#port.postMessage(notification, extractTransferrable(notification));
  }

  async _internal_sendRequest<Req extends Request, Res extends Response>(
    request: Omit<Req, "i">,
    expectedType: Res["t"],
    abort?: AbortSignal,
  ): Promise<Res> {
    abort?.throwIfAborted();

    if (this.#closed) {
      throw new Error("Channel closed");
    }

    let hasResponse = false;
    const response = await new Promise<Response>((ok, e) => {
      const id = this.#nextRequestId++;
      this.#outstandingRequests.set(id, { ok, e });

      (request as Req).i = id;
      this.#port.postMessage(request, extractTransferrable(request as Req));

      if (abort) {
        abort.addEventListener("abort", () => {
          if (!hasResponse && !this.#closed) {
            this.#port.postMessage({
              t: typeAbortRequest,
              i: id,
            } satisfies AbortRequest);
          }
        });
      }
    });
    hasResponse = true;

    if (response.t === expectedType) {
      return response as Res;
    } else {
      throw interpretResponseAsError(response);
    }
  }
}

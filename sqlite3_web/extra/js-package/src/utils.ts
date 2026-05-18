import { ErrorResponse, Response } from "./generated_protocol";
import { FeatureDetectionResult, RemoteError, SqliteException } from "./api";

export type ReleaseLock = () => void;

export function requestNavigatorLock(
  name: string,
  abort?: AbortSignal,
): Promise<ReleaseLock> {
  return new Promise((resolve, reject) => {
    navigator.locks
      .request(name, abort ? { signal: abort } : {}, (_lock) => {
        return new Promise<void>((complete) => {
          resolve(complete);
        });
      })
      .catch(reject);
  });
}

export function interpretResponseAsError(response: Response) {
  if (response.t === "errorResponse") {
    return new RemoteError(response.e, deserializeException(response));
  } else {
    return new RemoteError("Internal: Did not respond with expected type");
  }
}

const typeSqliteException = 0;
const typeAbortException = 1;

export function serializeError(
  requestId: number,
  message: string,
  error: unknown,
): ErrorResponse {
  let serializedExceptionType: number | null = null;
  let serializedException: any = null;

  if (error instanceof DOMException && error.name == "AbortError") {
    serializedExceptionType = typeAbortException;
  }

  return {
    t: "errorResponse",
    e: message,
    i: requestId,
    s: serializedExceptionType,
    r: serializedException,
  };
}

function deserializeException(
  e: ErrorResponse,
): DOMException | SqliteException | undefined {
  switch (e.s) {
    case typeSqliteException:
      const [
        message,
        explanation,
        extendedResultCode,
        operation,
        causingStatement,
        paramData,
        _paramTypes,
        offset,
      ] = e.r as unknown[];

      return {
        extendedResultCode: extendedResultCode as number,
        message: message as string,
        explanation: explanation as string | undefined,
        operation: operation as string | undefined,
        causingStatement: causingStatement as string | undefined,
        parametersToStatement: paramData as unknown[] | undefined,
        offset: offset as number | undefined,
      } satisfies SqliteException;
    case typeAbortException:
      return new DOMException("Aborted on worker", "AbortError");
    default:
      return;
  }
}

export function wrapFeatureDetectionResult(
  inner: FeatureDetectionResult,
): FeatureDetectionResult & Object {
  return {
    ...inner,
    toString(): string {
      return `Existing: ${JSON.stringify(this.existingDatabases)}, available: ${this.availableImplementations}, missing: ${this.missingFeatures}.`;
    },
  };
}

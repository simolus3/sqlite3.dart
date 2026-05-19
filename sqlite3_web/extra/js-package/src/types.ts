const typeCodeInteger = 1;
const typeCodeBigInt = 2;
const typeCodeFloat = 3;
const typeCodeText = 4;
const typeCodeBlob = 5;
const typeCodeNull = 6;
const typeCodeBoolean = 7;

export function typeCodeForValue(value: unknown): number {
  switch (typeof value) {
    case "string":
      return typeCodeText;
    case "number":
      return Number.isSafeInteger(value) ? typeCodeInteger : typeCodeFloat;
    case "bigint":
      return typeCodeBigInt;
    case "boolean":
      return typeCodeBoolean;
    case "undefined":
      return typeCodeNull;
    // @ts-expect-error (allow fallthrough)
    case "object":
      if (value == null) {
        return typeCodeNull;
      } else if (value instanceof Uint8Array) {
        return typeCodeBlob;
      }
    case "function":
    case "symbol":
      throw new Error("Unsupported value for database");
  }
}

export function typeCodesForValues(values: unknown[]): ArrayBuffer {
  return new Uint8Array(values.map(typeCodeForValue)).buffer;
}

export interface CompatibilityResult {
  a: string[]; // (storageMode, name) pairs of existing databases
  b: boolean; // sharedCanSpawnDedicated
  c: boolean; // canUseOpfs
  d: boolean; // canUseIndexedDb
  e: boolean; // supportsSharedArrayBuffers
  f: boolean; // dedicatedWorkersCanNest
  g: boolean; // opfsSupportsReadWriteUnsafe
}

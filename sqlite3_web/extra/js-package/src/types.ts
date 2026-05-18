const typeCode = {
  unknown: 0,
  integer: 1,
  bigInt: 2,
  float: 3,
  text: 4,
  blob: 5,
  null: 6,
  boolean: 7,
} as const;

export function typeCodeForValue(value: unknown): number {
  switch (typeof value) {
    case "string":
      return typeCode.text;
    case "number":
      return Number.isSafeInteger(value) ? typeCode.integer : typeCode.float;
    case "bigint":
      return typeCode.bigInt;
    case "boolean":
      return typeCode.boolean;
    case "undefined":
      return typeCode.null;
    // @ts-expect-error (allow fallthrough)
    case "object":
      if (value == null) {
        return typeCode.null;
      } else if (value instanceof Uint8Array) {
        return typeCode.blob;
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

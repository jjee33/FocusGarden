/**
 * A thin promise wrapper over IndexedDB.
 *
 * Deliberately small and dependency-free. The only thing it adds over the raw
 * API is promises and typed helpers; anything cleverer would be a second
 * abstraction to reason about on top of one that already has well-defined
 * transaction semantics.
 *
 * WHAT IS NOT PORTED, AND WHY. The desktop's `atomic_file` writes to a temp file,
 * reads it back to verify it parses, copies the real file to a timestamped
 * backup, then removes and renames - because a desktop process can be killed
 * between any two of those steps and leave truncated JSON where a garden used to
 * be. IndexedDB gives that guarantee directly: a transaction either commits whole
 * or not at all. Reimplementing the dance here would be adding ceremony around a
 * promise the platform already makes.
 */

export const DB_NAME = "focus-garden";
export const DB_VERSION = 1;

/** One record holding the whole save container, keyed "current". */
export const SAVE_STORE = "save";
export const SAVE_KEY = "current";

/**
 * One record per session, keyed by id.
 *
 * The desktop shards sessions by year so that finishing a pomodoro does not
 * rewrite a decade of history. IndexedDB writes records individually, so the
 * sharding buys nothing here and is dropped - it survives only in the transfer
 * format, where the whole history genuinely is one array.
 */
export const SESSION_STORE = "sessions";

/** Small scalars that must be readable before the save itself is parsed. */
export const META_STORE = "meta";

export type IdbFactoryLike = IDBFactory;

function request<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error("IndexedDB request failed"));
  });
}

/**
 * How long to wait for IndexedDB before giving up on it.
 *
 * `open()` is specified to fire success, error or blocked - and in practice it
 * can fire NONE of them and simply hang. A connection left half-closed by a
 * crashed tab, a delete that never finished, storage pressure, private mode on
 * some browsers: the request just never settles.
 *
 * Without a deadline that hang propagates all the way up: the shell waits for
 * storage before it renders anything, so the whole app sits on the loading
 * screen forever with no message and no way out. Timing out drops to the
 * ephemeral mode that already exists for "storage refused us" - the app works,
 * nothing is written to disk, and the person is told. A degraded app beats a
 * frozen one, and this is the difference between the two.
 *
 * GENEROUS ON PURPOSE. This deadline was 4 seconds, and 4 seconds was a false
 * positive: IndexedDB's events are ordinary main-thread tasks, so on a slow
 * phone still parsing the bundle and drawing the first plants, a perfectly
 * healthy success event can arrive late - and the person was told "nothing is
 * being saved" by an app that could save fine. Wrongly declaring storage dead
 * is worse than a long wait, so the deadline only needs to beat "forever".
 */
const OPEN_TIMEOUT_MS = 15_000;

export function openDatabase(factory: IdbFactoryLike = indexedDB): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    let settled = false;
    // Bare timers, not window.*: this module is exercised by tests that run in a
    // node environment where `window` does not exist, and a storage layer that
    // only works in a browser cannot be tested outside one.
    const finish = (fn: () => void): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn();
    };
    const timer = setTimeout(() => {
      finish(() => reject(new Error(
        "IndexedDB did not respond. Your garden will work but cannot be saved on "
        + "this device until the browser's storage recovers.",
      )));
    }, OPEN_TIMEOUT_MS);

    const open = factory.open(DB_NAME, DB_VERSION);
    open.onupgradeneeded = () => {
      const db = open.result;
      if (!db.objectStoreNames.contains(SAVE_STORE)) db.createObjectStore(SAVE_STORE);
      if (!db.objectStoreNames.contains(META_STORE)) db.createObjectStore(META_STORE);
      if (!db.objectStoreNames.contains(SESSION_STORE)) {
        const sessions = db.createObjectStore(SESSION_STORE, { keyPath: "id" });
        // Sessions are read by day for the heatmap and by plant for growth, so
        // both get an index rather than a full scan.
        sessions.createIndex("date_key", "date_key", { unique: false });
        sessions.createIndex("plant_uid", "plant_uid", { unique: false });
      }
    };
    open.onsuccess = () => {
      if (settled) {
        // A success arriving after the deadline is a connection nobody will
        // ever use. Left open it would hold the upgrade lock for the rest of
        // the tab's life - the very half-closed state this timeout guards
        // against.
        open.result.close();
        return;
      }
      finish(() => { resolve(open.result); });
    };
    open.onerror = () => {
      finish(() => { reject(open.error ?? new Error("Could not open IndexedDB")); });
    };
    open.onblocked = () => {
      finish(() => { reject(new Error("IndexedDB upgrade blocked by another tab")); });
    };
  });
}

/**
 * Runs `work` inside one transaction and resolves when it COMMITS, not when the
 * last request succeeds. Those are different moments, and resolving on the
 * earlier one is how a caller ends up believing a write landed that later aborted.
 */
export async function transact<T>(
  db: IDBDatabase,
  stores: string[],
  mode: IDBTransactionMode,
  work: (tx: IDBTransaction) => Promise<T> | T,
): Promise<T> {
  const tx = db.transaction(stores, mode);
  const done = new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error("IndexedDB transaction failed"));
    tx.onabort = () => reject(tx.error ?? new Error("IndexedDB transaction aborted"));
  });
  const result = await work(tx);
  await done;
  return result;
}

export function get<T>(tx: IDBTransaction, store: string, key: IDBValidKey): Promise<T | undefined> {
  return request<T | undefined>(tx.objectStore(store).get(key) as IDBRequest<T | undefined>);
}

export function put(
  tx: IDBTransaction, store: string, value: unknown, key?: IDBValidKey,
): Promise<IDBValidKey> {
  const objectStore = tx.objectStore(store);
  return request(key === undefined ? objectStore.put(value) : objectStore.put(value, key));
}

export function getAll<T>(tx: IDBTransaction, store: string): Promise<T[]> {
  return request<T[]>(tx.objectStore(store).getAll() as IDBRequest<T[]>);
}

export function clear(tx: IDBTransaction, store: string): Promise<undefined> {
  return request(tx.objectStore(store).clear());
}

export function remove(tx: IDBTransaction, store: string, key: IDBValidKey): Promise<undefined> {
  return request(tx.objectStore(store).delete(key));
}

/** Wipes every store. Used by import, which replaces rather than merges. */
export async function clearAll(db: IDBDatabase): Promise<void> {
  await transact(db, [SAVE_STORE, SESSION_STORE, META_STORE], "readwrite", async (tx) => {
    await Promise.all([
      clear(tx, SAVE_STORE),
      clear(tx, SESSION_STORE),
      clear(tx, META_STORE),
    ]);
  });
}

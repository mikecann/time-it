// This module has no database side effects and is also exercised by the protocol tests.
export type Category = { clientId: string; name: string; color: string; archived: boolean; revision: number; deviceId: string; updatedAt: number };
export type Entry = { clientId: string; categoryId: string; note: string; startedAt: number; endedAt?: number; deleted: boolean; revision: number; deviceId: string; updatedAt: number };
export type SyncPayload = { categories: Category[]; entries: Entry[]; categoryCursor?: string; entryCursor?: string; includeCategories: boolean; includeEntries: boolean };

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Expected an object");
  return value as Record<string, unknown>;
}
function text(value: unknown, max: number, allowEmpty = false): string {
  if (typeof value !== "string" || value.length > max || (!allowEmpty && !value.trim())) throw new Error("Invalid text");
  return value;
}
function number(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 8640000000000000) throw new Error("Invalid timestamp");
  return value;
}
function bool(value: unknown): boolean {
  if (typeof value !== "boolean") throw new Error("Invalid flag");
  return value;
}
function metadata(value: Record<string, unknown>) {
  const revision = number(value.revision);
  if (!Number.isSafeInteger(revision) || revision < 1) throw new Error("Invalid revision");
  return { clientId: text(value.clientId, 100), deviceId: text(value.deviceId, 100), revision, updatedAt: number(value.updatedAt) };
}
export function parsePayload(input: unknown): SyncPayload {
  const value = object(input);
  if (!Array.isArray(value.categories) || value.categories.length > 100 || !Array.isArray(value.entries) || value.entries.length > 100) throw new Error("Batches are limited to 100 records per table");
  const categories = value.categories.map((raw): Category => {
    const record = object(raw);
    const category = { ...metadata(record), name: text(record.name, 100).trim(), color: text(record.color, 7), archived: bool(record.archived) };
    if (!/^#[0-9a-fA-F]{6}$/.test(category.color)) throw new Error("Invalid colour");
    if (category.clientId === "convex" && (category.name !== "Convex" || category.archived)) throw new Error("Convex must remain the default category");
    return category;
  });
  const entries = value.entries.map((raw): Entry => {
    const record = object(raw);
    const entry: Entry = { ...metadata(record), categoryId: text(record.categoryId, 100), note: text(record.note, 2000, true), startedAt: number(record.startedAt), deleted: bool(record.deleted) };
    if (record.endedAt != null) {
      entry.endedAt = number(record.endedAt);
      if (entry.endedAt < entry.startedAt) throw new Error("End precedes start");
    }
    return entry;
  });
  const cursor = (value: unknown) => value == null ? undefined : text(value, 10000);
  return { categories, entries, categoryCursor: cursor(value.categoryCursor), entryCursor: cursor(value.entryCursor), includeCategories: bool(value.includeCategories), includeEntries: bool(value.includeEntries) };
}
export function wins(incoming: { revision: number; deviceId: string }, existing: { revision: number; deviceId: string }): boolean {
  return incoming.revision > existing.revision || (incoming.revision === existing.revision && incoming.deviceId > existing.deviceId);
}
// A fixed-length comparison avoids short-circuiting on the first differing byte.
export function authorized(header: string | null, secret: string | undefined): boolean {
  if (!secret || secret.length < 32) return false;
  const expected = `Bearer ${secret}`;
  const supplied = header ?? "";
  let mismatch = supplied.length ^ expected.length;
  for (let i = 0; i < expected.length; i++) mismatch |= expected.charCodeAt(i) ^ (supplied.charCodeAt(i) || 0);
  return mismatch === 0;
}

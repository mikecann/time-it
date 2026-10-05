import assert from "node:assert/strict";
import { test } from "node:test";
import { authorized, parsePayload, wins } from "../convex/protocol.ts";

const category = { clientId: "convex", name: "Convex", color: "#E8AE58", archived: false, revision: 1, deviceId: "device", updatedAt: 1000 };
const entry = { clientId: "entry", categoryId: "convex", note: "", startedAt: 1000, endedAt: 2000, deleted: false, revision: 2, deviceId: "device", updatedAt: 2000 };
const payload = { categories: [category], entries: [entry], includeCategories: false, includeEntries: false };
test("valid native payload, including nullable cursors, is normalized", () => {
  assert.equal(parsePayload({ ...payload, entryCursor: null }).entries[0].endedAt, 2000);
});
test("retries cannot overwrite a later stop or resurrect a deleted record", () => {
  assert.equal(wins({ revision: 1, deviceId: "device" }, entry), false);
  assert.equal(wins(entry, entry), false);
  assert.equal(wins({ revision: 3, deviceId: "device" }, entry), true);
});
test("equal revision conflicts resolve consistently across devices", () => {
  assert.equal(wins({ revision: 2, deviceId: "z" }, { revision: 2, deviceId: "a" }), true);
  assert.equal(wins({ revision: 2, deviceId: "a" }, { revision: 2, deviceId: "z" }), false);
});
test("unknown, missing, or short credentials never authorize a request", () => {
  const secret = "a".repeat(64);
  assert.equal(authorized(null, secret), false);
  assert.equal(authorized("Bearer " + secret, undefined), false);
  assert.equal(authorized("Bearer short", "short"), false);
  assert.equal(authorized("Bearer " + secret.slice(1), secret), false);
  assert.equal(authorized("Bearer " + secret, secret), true);
});
test("bounds, flags, duration, and default category are validated", () => {
  assert.throws(() => parsePayload({ ...payload, entries: Array(101).fill(entry) }));
  assert.throws(() => parsePayload({ ...payload, entries: [{ ...entry, endedAt: 999 }] }));
  assert.throws(() => parsePayload({ ...payload, categories: [{ ...category, archived: true }] }));
  assert.throws(() => parsePayload({ ...payload, entries: [{ ...entry, revision: 1.5 }] }));
  assert.throws(() => parsePayload({ ...payload, entries: [{ ...entry, startedAt: Infinity }] }));
  assert.throws(() => parsePayload({ ...payload, entries: [{ ...entry, deleted: "false" }] }));
  assert.throws(() => parsePayload({ ...payload, categories: [{ ...category, color: "orange" }] }));
});

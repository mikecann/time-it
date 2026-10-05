import { defineSchema, defineTable } from "convex/server";
import { categoryValidator, entryValidator } from "./validators";

// Approved by Mike on 5 October 2026. Stable client IDs make offline retries idempotent.
export default defineSchema({
  categories: defineTable(categoryValidator).index("by_clientId", ["clientId"]),
  entries: defineTable(entryValidator).index("by_clientId", ["clientId"]),
});

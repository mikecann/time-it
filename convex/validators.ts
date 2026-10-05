import { v } from "convex/values";

const metadata = { clientId: v.string(), deviceId: v.string(), revision: v.number(), updatedAt: v.number() };
export const categoryValidator = v.object({ ...metadata, name: v.string(), color: v.string(), archived: v.boolean() });
export const entryValidator = v.object({ ...metadata, categoryId: v.string(), note: v.string(), startedAt: v.number(), endedAt: v.optional(v.number()), deleted: v.boolean() });

import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";
import { paginationOptsValidator } from "convex/server";
import { wins } from "./protocol";

const metadata = { clientId: v.string(), deviceId: v.string(), revision: v.number(), updatedAt: v.number() };
export const categoryValidator = v.object({ ...metadata, name: v.string(), color: v.string(), archived: v.boolean() });
export const entryValidator = v.object({ ...metadata, categoryId: v.string(), note: v.string(), startedAt: v.number(), endedAt: v.optional(v.number()), deleted: v.boolean() });

export const upload = internalMutation({
  args: { categories: v.array(categoryValidator), entries: v.array(entryValidator) },
  handler: async (ctx, args) => {
    const acknowledgedCategories = [];
    const acknowledgedEntries = [];
    for (const category of args.categories) {
      const existing = await ctx.db.query("categories").withIndex("by_clientId", q => q.eq("clientId", category.clientId)).unique();
      if (!existing) await ctx.db.insert("categories", category);
      else if (wins(category, existing)) await ctx.db.replace(existing._id, category);
      const winner = existing && !wins(category, existing) ? existing : category;
      acknowledgedCategories.push({ clientId: winner.clientId, name: winner.name, color: winner.color, archived: winner.archived, revision: winner.revision, deviceId: winner.deviceId, updatedAt: winner.updatedAt });
    }
    for (const entry of args.entries) {
      const category = await ctx.db.query("categories").withIndex("by_clientId", q => q.eq("clientId", entry.categoryId)).unique();
      if (!category) throw new Error("Unknown category. Sync categories before their entries.");
      const existing = await ctx.db.query("entries").withIndex("by_clientId", q => q.eq("clientId", entry.clientId)).unique();
      if (!existing) await ctx.db.insert("entries", entry);
      else if (wins(entry, existing)) await ctx.db.replace(existing._id, entry);
      const winner = existing && !wins(entry, existing) ? existing : entry;
      acknowledgedEntries.push({ clientId: winner.clientId, categoryId: winner.categoryId, note: winner.note, startedAt: winner.startedAt, ...(winner.endedAt === undefined ? {} : { endedAt: winner.endedAt }), deleted: winner.deleted, revision: winner.revision, deviceId: winner.deviceId, updatedAt: winner.updatedAt });
    }
    return { acknowledgedCategories, acknowledgedEntries };
  }
});

// Each paginated query reads one table. This avoids Convex's restriction on multiple paginations per query.
export const categoriesPage = internalQuery({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db.query("categories").paginate(args.paginationOpts);
    return { ...result, page: result.page.map(({ _id, _creationTime, ...record }) => record) };
  }
});
export const entriesPage = internalQuery({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db.query("entries").paginate(args.paginationOpts);
    return { ...result, page: result.page.map(({ _id, _creationTime, ...record }) => record) };
  }
});

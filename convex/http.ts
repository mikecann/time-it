import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { authorized, parsePayload } from "./protocol";

const http = httpRouter();
http.route({
  path: "/sync",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const reply = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
    if (!authorized(request.headers.get("Authorization"), process.env.TIME_IT_SYNC_KEY)) return reply({ error: "Unauthorized" }, 401);
    // Enforce a byte limit before parsing, including requests without Content-Length.
    const reader = request.body?.getReader();
    if (!reader) return reply({ error: "Missing body" }, 400);
    const chunks: Uint8Array[] = [];
    let length = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 1024 * 1024) { await reader.cancel(); return reply({ error: "Body too large" }, 413); }
      chunks.push(value);
    }
    let payload;
    try {
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      payload = parsePayload(JSON.parse(new TextDecoder().decode(bytes)));
    } catch { return reply({ error: "Invalid sync request" }, 400); }
    const acknowledged = await ctx.runMutation(internal.sync.upload, { categories: payload.categories, entries: payload.entries });
    const categories = payload.includeCategories ? await ctx.runQuery(internal.sync.categoriesPage, { paginationOpts: { cursor: payload.categoryCursor ?? null, numItems: 200 } }) : null;
    const entries = payload.includeEntries ? await ctx.runQuery(internal.sync.entriesPage, { paginationOpts: { cursor: payload.entryCursor ?? null, numItems: 200 } }) : null;
    return reply({ ...acknowledged, categories: categories?.page ?? [], entries: entries?.page ?? [], categoryCursor: categories?.continueCursor ?? null, entryCursor: entries?.continueCursor ?? null, categoriesDone: categories?.isDone ?? true, entriesDone: entries?.isDone ?? true });
  })
});
export default http;

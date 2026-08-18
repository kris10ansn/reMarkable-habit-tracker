import { sql } from "drizzle-orm";
import {
    check,
    index,
    integer,
    primaryKey,
    sqliteTable,
    text,
} from "drizzle-orm/sqlite-core";

// SQLite tables mirroring the backend's normalized shape: a roster plus a
// (habitId, date)-keyed entry log. Both carry `editedAt` (the client-stamped last-write-wins merge
// key — the one timestamp the sync wire format exchanges) and `deletedAt` (null when alive,
// timestamp on tombstone). The backend's audit `UpdatedAt` is server-owned and never crosses the
// wire, so there is deliberately no local mirror of it. The `enum` column mode makes Drizzle infer
// domain types (Polarity/Outcome) directly, so reads need no mappers or casts.
export const habits = sqliteTable("habits", {
    id: text().primaryKey(),
    name: text().notNull(),
    polarity: text({ enum: ["Positive", "Negative"] }).notNull(),
    position: integer().notNull(),
    isPrivate: integer({ mode: "boolean" }).notNull().default(false),
    createdAt: integer().notNull(),
    editedAt: integer().notNull(),
    deletedAt: integer(),
});

export const entries = sqliteTable(
    "entries",
    {
        habitId: text().notNull(),
        date: text().notNull(),
        outcome: text({ enum: ["Success", "Failure"] }).notNull(),
        editedAt: integer().notNull(),
        deletedAt: integer(),
    },
    (table) => [
        primaryKey({ columns: [table.habitId, table.date] }),
        index("idx_entries_date").on(table.date),
    ],
);

export const settings = sqliteTable(
    "settings",
    {
        id: integer().notNull().default(0).primaryKey(),

        syncServerUrl: text().notNull().default(""),

        // When the last sync succeeded, epoch ms. Null until the first one, which is what makes
        // that sync a full one (every month we hold) rather than only the months edited since.
        lastSyncedAt: integer(),

        updatedAt: integer()
            .notNull()
            .$defaultFn(() => Date.now()),
    },
    (table) => [check("settings_singleton", sql`${table.id} = 0`)],
);

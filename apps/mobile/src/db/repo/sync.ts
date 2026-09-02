import { and, gt, gte, lt, lte, notInArray } from "drizzle-orm";

import type { SyncRequest, SyncResponse } from "@/api/gen";
import { monthKeyBounds } from "@/domain/dates";
import type { Habit } from "@/domain/types";

import type { Database } from "../client";
import { entries, habits } from "../schema";

// The database half of sync: gather what this device holds, then overwrite it with the
// authoritative result. The merge itself is the backend's — mobile never resolves a conflict, it
// submits state and accepts what comes back (see apps/backend/CLAUDE.md).
//
// Rows are the wire types verbatim (src/api/contract.ts asserts it), so nothing here maps or casts;
// what this module actually owns is *which* rows go, and how the response lands atomically.

// A lightweight status check, not a content diff: stop at the first row edited after the last
// successful sync. This intentionally uses the same edit-time cursor as incremental sync.
export async function hasUnsyncedChanges(
    db: Database,
    lastSyncedAt: number,
): Promise<boolean> {
    const [editedHabit] = await db
        .select({ id: habits.id })
        .from(habits)
        .where(gt(habits.editedAt, lastSyncedAt))
        .limit(1);
    if (editedHabit) return true;

    const [editedEntry] = await db
        .select({ habitId: entries.habitId })
        .from(entries)
        .where(gt(entries.editedAt, lastSyncedAt))
        .limit(1);

    return editedEntry !== undefined;
}

/**
 * Months to submit. The response is authoritative only for the months the request names, so this
 * decides what sync can reconcile at all.
 *
 * Before the first successful sync there is no `lastSyncedAt` and every month we hold goes, so a
 * fresh install pushes its whole history once. After that it is the months edited since — plus
 * `currentMonthKey` unconditionally, because that is the one the user is looking at and the only
 * way to *pull* someone else's edit for a month this device didn't touch.
 */
export async function monthsToSync(
    db: Database,
    currentMonthKey: string,
    lastSyncedAt: number | null,
): Promise<string[]> {
    const rows = await db
        .select({ date: entries.date })
        .from(entries)
        .where(
            lastSyncedAt === null
                ? undefined
                : gt(entries.editedAt, lastSyncedAt),
        );

    const months = new Set(rows.map((row) => row.date.slice(0, 7)));
    months.add(currentMonthKey);

    return [...months].sort();
}

/**
 * Everything the backend needs to merge: the full roster including tombstones, and every row of the
 * named months including tombstones. Tombstones must travel — a row that merely vanished locally
 * would be resurrected by the next sync, which is the whole reason deletes are soft.
 */
export async function gatherRequest(
    db: Database,
    monthKeys: string[],
): Promise<SyncRequest> {
    const roster = await db.select().from(habits);

    const months = await Promise.all(
        monthKeys.map(async (month) => {
            const { start, endExclusive } = monthKeyBounds(month);
            const rows = await db
                .select()
                .from(entries)
                .where(
                    and(
                        gte(entries.date, start),
                        lt(entries.date, endExclusive),
                    ),
                );

            return { month, entries: rows };
        }),
    );

    return { habits: roster, months };
}

/**
 * Replace local state with the server's, atomically.
 *
 * `syncStartedAt` is what makes this safe to run against a live app: a row edited while the request
 * was in flight was never submitted, so the response cannot be authoritative about it. Those rows
 * are left exactly as they are and the server's version of them is skipped — without that, a tap
 * landing mid-sync would be silently reverted by its own sync.
 *
 * Everything else is overwritten: the response carries the authoritative ALIVE state, so a habit or
 * entry missing from it has been deleted and its local tombstone has served its purpose.
 */
export async function applySynced(
    db: Database,
    response: SyncResponse,
    monthKeys: string[],
    syncStartedAt: number,
): Promise<void> {
    await db.transaction(async (tx) => {
        await applyRoster(tx, response.habits, syncStartedAt);

        for (const month of monthKeys) {
            const authoritative =
                response.months.find(
                    (responseMonth) => responseMonth.month === month,
                )?.entries ?? [];
            await applyMonth(tx, month, authoritative, syncStartedAt);
        }
    });
}

type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];

async function applyRoster(
    tx: Transaction,
    authoritative: Habit[],
    syncStartedAt: number,
): Promise<void> {
    // Rows the user touched mid-flight stay put, and the server's copy of them is not applied.
    const inFlight = await tx
        .select({ id: habits.id })
        .from(habits)
        .where(gt(habits.editedAt, syncStartedAt));
    const inFlightIds = new Set(inFlight.map((row) => row.id));

    const settled = authoritative.filter((habit) => !inFlightIds.has(habit.id));

    // Absent from the response means deleted. Tombstones we pushed are included in that.
    const survivingIds = [...inFlightIds, ...settled.map((habit) => habit.id)];
    await tx
        .delete(habits)
        .where(
            survivingIds.length === 0
                ? undefined
                : notInArray(habits.id, survivingIds),
        );

    for (const habit of settled) {
        await tx.insert(habits).values(habit).onConflictDoUpdate({
            target: habits.id,
            set: habit,
        });
    }
}

async function applyMonth(
    tx: Transaction,
    monthKey: string,
    authoritative: SyncResponse["months"][number]["entries"],
    syncStartedAt: number,
): Promise<void> {
    const { start, endExclusive } = monthKeyBounds(monthKey);
    const inMonth = and(
        gte(entries.date, start),
        lt(entries.date, endExclusive),
    );

    // Drop everything we submitted for this month — alive rows and tombstones alike — and rebuild
    // it from the response. Rows edited mid-flight are excluded from the sweep and kept.
    await tx
        .delete(entries)
        .where(and(inMonth, lte(entries.editedAt, syncStartedAt)));

    const kept = await tx
        .select({ habitId: entries.habitId, date: entries.date })
        .from(entries)
        .where(inMonth);
    const keptKeys = new Set(kept.map((row) => `${row.habitId}|${row.date}`));

    const toInsert = authoritative.filter(
        (entry) => !keptKeys.has(`${entry.habitId}|${entry.date}`),
    );

    if (toInsert.length > 0) {
        await tx.insert(entries).values(toInsert);
    }
}

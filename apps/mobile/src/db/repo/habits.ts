import { asc, eq, isNull } from "drizzle-orm";
import * as Crypto from "expo-crypto";

import { moveByIndex } from "@/domain/roster";
import type { Habit, Polarity } from "@/domain/types";

import type { Database } from "../client";
import { habits } from "../schema";

export function getHabits(db: Database): Promise<Habit[]> {
    return db
        .select()
        .from(habits)
        .where(isNull(habits.deletedAt))
        .orderBy(asc(habits.position));
}

// Append a habit at the end of the roster. The id is minted here rather than by the server: two
// devices can both create offline, so ids must be collision-free without coordination (the backend
// stores a sync id verbatim and never re-mints — see apps/backend/CLAUDE.md).
export async function createHabit(
    db: Database,
    name: string,
    polarity: Polarity,
    now: number = Date.now(),
): Promise<Habit> {
    const roster = await getHabits(db);
    const habit: Habit = {
        id: Crypto.randomUUID(),
        name,
        polarity,
        position: roster.length,
        isPrivate: false,
        createdAt: now,
        editedAt: now,
        deletedAt: null,
    };

    await db.insert(habits).values(habit);
    return habit;
}

// Deleting is a tombstone, never a row removal: a habit that simply vanished here would come back
// on the next sync, because absence carries no date for the merge to compare.
export async function deleteHabit(
    db: Database,
    id: string,
    now: number = Date.now(),
): Promise<void> {
    await db
        .update(habits)
        .set({ deletedAt: now, editedAt: now })
        .where(eq(habits.id, id));
}

export async function updateHabit(
    db: Database,
    id: string,
    patch: { name?: string; polarity?: Polarity },
    now: number = Date.now(),
): Promise<void> {
    if (patch.name === undefined && patch.polarity === undefined) return;
    await db
        .update(habits)
        .set({ ...patch, editedAt: now })
        .where(eq(habits.id, id));
}

// Move a habit to `toIndex` and renumber positions densely, bumping `editedAt` only on the rows
// whose position actually changed (position is LWW per habit for sync).
export async function reorderHabit(
    db: Database,
    habitId: string,
    toIndex: number,
    now: number = Date.now(),
): Promise<void> {
    const roster = await getHabits(db);
    const reordered = moveByIndex(roster, habitId, toIndex);
    if (reordered === roster) return; // habit absent or already at toIndex — nothing to renumber

    await db.transaction(async (tx) => {
        for (let position = 0; position < reordered.length; position += 1) {
            if (reordered[position].position === position) continue;
            await tx
                .update(habits)
                .set({ position, editedAt: now })
                .where(eq(habits.id, reordered[position].id));
        }
    });
}

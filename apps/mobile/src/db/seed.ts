import * as Crypto from "expo-crypto";

import { shiftDay, todayKey } from "@/domain/dates";
import type { Outcome, Polarity } from "@/domain/types";

import type { Database } from "./client";
import { entries, habits } from "./schema";

// First-run roster, with demo entries so the app opens populated. `marks` is keyed by day-offset
// back from the seed date (0 = today), covering every display state — a streak, a miss, a
// negative habit's clean run, and a slip. Seeded once into an empty database; thereafter these are
// ordinary user rows.
interface SeedHabit {
    name: string;
    polarity: Polarity;
    marks: Record<number, Outcome>;
}

const SEED_HABITS: SeedHabit[] = [
    {
        name: "Read 20 pages",
        polarity: "Positive",
        marks: {
            0: "Success",
            1: "Success",
            2: "Success",
            3: "Success",
            6: "Failure",
        },
    },
    {
        name: "Exercise",
        polarity: "Positive",
        marks: { 1: "Success", 3: "Success", 4: "Success" },
    },
    {
        name: "Meditate",
        polarity: "Positive",
        marks: { 0: "Success", 1: "Failure", 2: "Success" },
    },
    {
        name: "Drink water",
        polarity: "Positive",
        marks: { 0: "Success", 1: "Success", 2: "Success" },
    },
    { name: "Doomscroll", polarity: "Negative", marks: { 2: "Failure" } },
    { name: "Late-night snacks", polarity: "Negative", marks: {} },
];

// Seed the defaults only into a fresh database (run after migrations, see _layout).
export async function seedIfEmpty(db: Database): Promise<void> {
    const [existing] = await db.select({ id: habits.id }).from(habits).limit(1);
    if (existing) return;

    const now = Date.now();
    const today = todayKey();
    // Backdate creation so the clean negative demo habit ("Late-night snacks", no slips) shows a
    // streak off its createdAt anchor — the case the anchor exists for (see repo.getStreaks).
    const createdAt = now - 30 * 86_400_000;

    await db.transaction(async (tx) => {
        for (let position = 0; position < SEED_HABITS.length; position += 1) {
            const seed = SEED_HABITS[position];
            const id = Crypto.randomUUID();

            await tx.insert(habits).values({
                id,
                name: seed.name,
                polarity: seed.polarity,
                position,
                isPrivate: false,
                createdAt,
                editedAt: now,
                deletedAt: null,
            });

            const rows = Object.entries(seed.marks).map(
                ([offset, outcome]) => ({
                    habitId: id,
                    date: shiftDay(today, -Number(offset)),
                    outcome,
                    editedAt: now,
                    deletedAt: null,
                }),
            );
            if (rows.length > 0) await tx.insert(entries).values(rows);
        }
    });
}

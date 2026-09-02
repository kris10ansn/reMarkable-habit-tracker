import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";

import { useDatabase } from "@/db/client";
import * as repo from "@/db/repo";
import { nextAction, type MarkAction } from "@/domain/marks";
import type { Entry, Polarity } from "@/domain/types";

import { entriesKey, streaksKey, unsyncedChangesKey } from "./keys";

export function useMonthEntries(monthKey: string) {
    const db = useDatabase();
    return useQuery({
        queryKey: entriesKey(monthKey),
        queryFn: () => repo.getMonthEntries(db, monthKey),
    });
}

// A resolved tap: the storage action is decided once (from the live cache, see useToggleEntry) and
// carried through both the optimistic write and the DB write, so the two can never diverge.
interface ToggleVariables {
    habitId: string;
    date: string;
    action: MarkAction;
}

// Toggle a habit's mark for a day. Callers pass the habit + polarity, not an outcome snapshot.
export type ToggleFn = (
    habitId: string,
    date: string,
    polarity: Polarity,
) => void;

const applyAction = (
    entries: Entry[],
    habitId: string,
    date: string,
    action: MarkAction,
): Entry[] => {
    const rest = entries.filter(
        (entry) => !(entry.habitId === habitId && entry.date === date),
    );
    if (action.type === "clear") return rest;
    return [
        ...rest,
        {
            habitId,
            date,
            outcome: action.outcome,
            editedAt: Date.now(),
            deletedAt: null,
        },
    ];
};

// Toggling writes to the viewed month's cache optimistically, then invalidates that month and the
// streaks (which a mark can extend or break). The returned `toggle` derives the next action from
// the *live cache* at tap time — not a render-time outcome snapshot — so a rapid double-tap
// advances the cycle (unmarked→success→failure→clear) instead of computing the same step twice
// from a stale value. A shared mutation scope serialises the writes so SQLite lands in tap order.
export function useToggleEntry(monthKey: string): ToggleFn {
    const db = useDatabase();
    const queryClient = useQueryClient();
    const key = entriesKey(monthKey);

    const mutation = useMutation({
        scope: { id: "toggle-entry" },
        mutationFn: ({ habitId, date, action }: ToggleVariables) =>
            action.type === "set"
                ? repo.setOutcome(db, habitId, date, action.outcome)
                : repo.clearEntry(db, habitId, date),
        onMutate: async ({ habitId, date, action }) => {
            await queryClient.cancelQueries({ queryKey: key });
            const previous = queryClient.getQueryData<Entry[]>(key);
            queryClient.setQueryData<Entry[]>(key, (old = []) =>
                applyAction(old, habitId, date, action),
            );
            return { previous };
        },
        onError: (_error, _variables, context) => {
            if (context) queryClient.setQueryData(key, context.previous);
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: key });
            queryClient.invalidateQueries({ queryKey: unsyncedChangesKey });
            queryClient.invalidateQueries({ queryKey: streaksKey });
        },
    });

    return useCallback<ToggleFn>(
        (habitId, date, polarity) => {
            const entries =
                queryClient.getQueryData<Entry[]>(entriesKey(monthKey)) ?? [];
            const current = entries.find(
                (entry) => entry.habitId === habitId && entry.date === date,
            )?.outcome;
            mutation.mutate({
                habitId,
                date,
                action: nextAction(polarity, current),
            });
        },
        [queryClient, monthKey, mutation],
    );
}

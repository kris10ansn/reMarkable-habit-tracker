import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { useDatabase } from "@/db/client";
import * as repo from "@/db/repo";
import { moveByIndex } from "@/domain/roster";
import type { Habit, Polarity } from "@/domain/types";

import { habitsKey, streaksKey, unsyncedChangesKey } from "./keys";

export function useHabits() {
    const db = useDatabase();
    return useQuery({ queryKey: habitsKey, queryFn: () => repo.getHabits(db) });
}

export function useCreateHabit() {
    const db = useDatabase();
    const queryClient = useQueryClient();

    return useMutation({
        mutationFn: (variables: { name: string; polarity: Polarity }) =>
            repo.createHabit(db, variables.name, variables.polarity),
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: habitsKey });
            queryClient.invalidateQueries({ queryKey: unsyncedChangesKey });
            queryClient.invalidateQueries({ queryKey: streaksKey });
        },
    });
}

export function useDeleteHabit() {
    const db = useDatabase();
    const queryClient = useQueryClient();

    return useMutation({
        mutationFn: (id: string) => repo.deleteHabit(db, id),
        onMutate: async (id) => {
            await queryClient.cancelQueries({ queryKey: habitsKey });
            const previous = queryClient.getQueryData<Habit[]>(habitsKey);
            queryClient.setQueryData<Habit[]>(habitsKey, (old = []) =>
                old.filter((habit) => habit.id !== id),
            );
            return { previous };
        },
        onError: (_error, _id, context) => {
            if (context) queryClient.setQueryData(habitsKey, context.previous);
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: habitsKey });
            queryClient.invalidateQueries({ queryKey: unsyncedChangesKey });
            queryClient.invalidateQueries({ queryKey: streaksKey });
        },
    });
}

export function useUpdateHabit() {
    const db = useDatabase();
    const queryClient = useQueryClient();

    return useMutation({
        mutationFn: (variables: {
            id: string;
            patch: { name?: string; polarity?: Polarity };
        }) => repo.updateHabit(db, variables.id, variables.patch),
        onMutate: async ({ id, patch }) => {
            await queryClient.cancelQueries({ queryKey: habitsKey });
            const previous = queryClient.getQueryData<Habit[]>(habitsKey);
            queryClient.setQueryData<Habit[]>(habitsKey, (old = []) =>
                old.map((habit) =>
                    habit.id === id ? { ...habit, ...patch } : habit,
                ),
            );
            return { previous };
        },
        onError: (_error, _variables, context) => {
            if (context) queryClient.setQueryData(habitsKey, context.previous);
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: habitsKey });
            queryClient.invalidateQueries({ queryKey: unsyncedChangesKey });
            queryClient.invalidateQueries({ queryKey: streaksKey });
        },
    });
}

export function useReorderHabit() {
    const db = useDatabase();
    const queryClient = useQueryClient();

    return useMutation({
        mutationFn: (variables: { habitId: string; toIndex: number }) =>
            repo.reorderHabit(db, variables.habitId, variables.toIndex),
        onMutate: async ({ habitId, toIndex }) => {
            await queryClient.cancelQueries({ queryKey: habitsKey });
            const previous = queryClient.getQueryData<Habit[]>(habitsKey);
            queryClient.setQueryData<Habit[]>(habitsKey, (old = []) =>
                moveByIndex(old, habitId, toIndex),
            );
            return { previous };
        },
        onError: (_error, _variables, context) => {
            if (context) queryClient.setQueryData(habitsKey, context.previous);
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: habitsKey });
            queryClient.invalidateQueries({ queryKey: unsyncedChangesKey });
        },
    });
}

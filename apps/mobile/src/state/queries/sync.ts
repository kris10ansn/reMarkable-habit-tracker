import { useMutation, useQueryClient } from "@tanstack/react-query";

import { ApiError, NetworkError } from "@/api/client";
import { postApiSync } from "@/api/gen";
import { useDatabase } from "@/db/client";
import * as repo from "@/db/repo";
import { updateSettings } from "@/db/repo/settings";
import { monthKey } from "@/domain/dates";

import { isUnauthorized } from "@/state/queries/auth";
import { useSettings } from "@/state/queries/settings";
import {
    authSessionKey,
    entriesKey,
    habitsKey,
    settingsKey,
    streaksKey,
} from "./keys";

/**
 * One sync round-trip: gather local state, POST it, overwrite local with the authoritative result.
 *
 * The three steps are deliberately not interleaved. `syncStartedAt` is stamped before the gather
 * and carried through to the apply, so anything the user edits while the request is in flight is
 * recognisable as "never submitted" and survives (see repo/sync.ts).
 *
 * Merge is the backend's job — nothing here resolves a conflict, and this is the only place mobile
 * talks to the network at all.
 */
export function useSync() {
    const db = useDatabase();
    const queryClient = useQueryClient();

    const settings = useSettings();

    return useMutation({
        mutationFn: async (variables: { currentMonthKey?: string }) => {
            const baseURL = settings.data?.syncServerUrl.trim() ?? "";

            if (!baseURL) {
                throw new Error(
                    "No Server URL set — the app is standalone. Set one on the Sync tab first.",
                );
            }

            const now = new Date();
            const currentMonthKey =
                variables.currentMonthKey ??
                monthKey(now.getFullYear(), now.getMonth());

            const syncStartedAt = Date.now();
            const monthKeys = await repo.monthsToSync(
                db,
                currentMonthKey,
                settings.data?.lastSyncedAt ?? null,
            );

            const request = await repo.gatherRequest(db, monthKeys);
            const response = await postApiSync(request, { baseURL });

            await repo.applySynced(db, response, monthKeys, syncStartedAt);
            await updateSettings(db, { lastSyncedAt: syncStartedAt });

            return { monthKeys, syncedAt: syncStartedAt };
        },

        onSuccess: ({ monthKeys }) => {
            // A sync rewrites the roster and every synced month, so nothing cached survives it.
            queryClient.invalidateQueries({ queryKey: habitsKey });
            queryClient.invalidateQueries({ queryKey: streaksKey });
            queryClient.invalidateQueries({ queryKey: settingsKey });
            monthKeys.forEach((month) =>
                queryClient.invalidateQueries({ queryKey: entriesKey(month) }),
            );
        },

        onError: (error) => {
            // A dead/revoked token never wipes or blocks local data — `client.ts` has already
            // discarded it from SecureStore; this just lets the Sync tab's account card catch up
            // to "signed out" so the owner knows to reconnect. Habits and entries are untouched.
            if (isUnauthorized(error)) {
                queryClient.invalidateQueries({ queryKey: authSessionKey });
            }
        },
    });
}

/** What the Sync tab shows for a failure. The card renders it; it decides nothing. */
export function syncErrorReason(error: unknown): string {
    if (error instanceof NetworkError) {
        return "Couldn't reach the server — check the URL and your connection.";
    }

    if (error instanceof ApiError) {
        if (error.status === 401) {
            return "Signed out — reconnect in Settings.";
        }

        // The backend refuses a whole sync whose edit-times run too far ahead of its own clock,
        // because edit-time is the merge key and a bad one would out-rank every later edit.
        if (error.status === 400 && isClockSkew(error.body)) {
            return "This device's clock is too far ahead of the server. Fix the date and try again.";
        }

        return `Server returned ${error.status}.`;
    }

    return error instanceof Error ? error.message : "Something went wrong.";
}

// ASP.NET replies with ProblemDetails; the skew refusal is the only 400 the sync endpoint returns.
function isClockSkew(body: unknown): boolean {
    return (
        typeof body === "object" &&
        body !== null &&
        "title" in body &&
        typeof body.title === "string" &&
        body.title.toLowerCase().includes("clock")
    );
}

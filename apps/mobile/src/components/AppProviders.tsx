import { useDatabase } from "@/db/client";
import { migrations } from "@/db/migrations";
import { colors } from "@/theme/colors";

import { invalidateSessionOnUnauthorized } from "@/state/queries";
import {
    MutationCache,
    QueryCache,
    QueryClient,
    QueryClientProvider,
} from "@tanstack/react-query";
import { useMigrations } from "drizzle-orm/expo-sqlite/migrator";
import { SQLiteProvider, type SQLiteDatabase } from "expo-sqlite";
import { type ReactNode } from "react";
import { ActivityIndicator, Text, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { KeyboardProvider } from "react-native-keyboard-controller";

// A function declaration, not an arrow: it is referenced by the caches below, which are built
// before `queryClient` exists. Hoisting makes that legal, and it only ever reads `queryClient` at
// call time, long after construction.
function handleAuthError(error: unknown) {
    invalidateSessionOnUnauthorized(queryClient, error);
}

// Local SQLite is the source of truth, so data only changes through our own mutations (which
// invalidate) — queries never need to refetch on their own. Visited months linger for 30 min.
//
// The cache-level `onError`s are the single place a rejected bearer token is reacted to: see
// invalidateSessionOnUnauthorized. Wiring it here rather than per-hook is what stops a new query
// from silently leaving the UI claiming "signed in" against a token the transport already dropped.
const queryClient = new QueryClient({
    defaultOptions: {
        queries: { staleTime: Infinity, gcTime: 1000 * 60 * 30, retry: false },
    },
    queryCache: new QueryCache({ onError: handleAuthError }),
    mutationCache: new MutationCache({ onError: handleAuthError }),
});

const enableWal = async (db: SQLiteDatabase) => {
    await db.execAsync("PRAGMA journal_mode = WAL;");
};

const BootScreen = ({ children }: { children?: string }) => (
    <View className="flex-1 items-center justify-center bg-surface px-8">
        {children ? (
            <Text className="text-center text-ink-2">{children}</Text>
        ) : (
            <ActivityIndicator color={colors.accent} />
        )}
    </View>
);

// Applies Drizzle migrations before any screen queries the database.
function DatabaseGate({ children }: { children: ReactNode }) {
    const db = useDatabase();
    const { success, error } = useMigrations(db, migrations);

    if (error) {
        return <BootScreen>{`Database error: ${error.message}`}</BootScreen>;
    }

    if (!success) {
        return <BootScreen />;
    }

    return <>{children}</>;
}

// Composes the app-wide providers and gates rendering on a migrated database.
export function AppProviders({ children }: { children: ReactNode }) {
    return (
        <GestureHandlerRootView>
            <KeyboardProvider>
                <SQLiteProvider databaseName="habits.db" onInit={enableWal}>
                    <QueryClientProvider client={queryClient}>
                        <DatabaseGate>{children}</DatabaseGate>
                    </QueryClientProvider>
                </SQLiteProvider>
            </KeyboardProvider>
        </GestureHandlerRootView>
    );
}

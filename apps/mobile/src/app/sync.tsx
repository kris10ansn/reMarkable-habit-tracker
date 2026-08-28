import { SyncStatusCard } from "@/components/sync/SyncStatusCard";
import { AppScreen } from "@/components/ui/AppScreen";
import { Card } from "@/components/ui/Card";
import {
    TextInputField,
    TextInputHint,
    TextInputLabel,
} from "@/components/ui/TextField";
import { relativeTime } from "@/lib/relativeTime";
import { useUpdateEffect } from "@/lib/useUpdateEffect";
import {
    syncErrorReason,
    useSettings,
    useSync,
    useUpdateSettings,
} from "@/state/queries";
import { useState } from "react";
import { Text, View } from "react-native";

import { AccountSection } from "@/components/account/AccountSection";

import type { SyncState } from "@/components/sync/SyncStatusCard";

// Sync: point the app at a backend, or stay standalone with an empty Server URL.
export default function SyncScreen() {
    const settings = useSettings();
    const updateSettings = useUpdateSettings();
    const sync = useSync();

    const [syncServerUrl, setSyncServerUrl] = useState(
        settings.data?.syncServerUrl ?? "",
    );

    useUpdateEffect(() => {
        if (settings.data != undefined) {
            setSyncServerUrl(settings.data.syncServerUrl);
        }
    }, [settings.data]);

    const updateSyncSettingsUrl = () => {
        // A different backend has different history, so a stale lastSyncedAt would make the next
        // sync a silently-partial incremental one instead of the full one it needs to be.
        const changedServer =
            syncServerUrl !== (settings.data?.syncServerUrl ?? "");

        updateSettings.mutate({
            syncServerUrl,
            ...(changedServer ? { lastSyncedAt: null } : {}),
        });
    };

    const lastSyncedAt = settings.data?.lastSyncedAt ?? null;

    const state = syncState({
        savedServerUrl: settings.data?.syncServerUrl ?? "",
        lastSyncedAt,
        isSyncing: sync.isPending,
        failed: sync.isError,
    });

    return (
        <AppScreen
            eyebrow="Backend"
            title="Sync"
            subtitle="Keep every device in step"
        >
            <SyncStatusCard
                state={state}
                lastSynced={relativeTime(lastSyncedAt)}
                errorReason={
                    sync.isError ? syncErrorReason(sync.error) : undefined
                }
                onSyncNow={() => sync.mutate({})}
            />

            <Card className="flex-col">
                <TextInputLabel>Server URL</TextInputLabel>

                <View className="flex-row gap-4">
                    <View className="flex-1 flex-col">
                        <TextInputField
                            value={syncServerUrl}
                            onChangeText={setSyncServerUrl}
                            placeholder="https://example.com"
                            editable={!settings.isFetching}
                            inputMode="url"
                            autoCapitalize="none"
                            onBlur={updateSyncSettingsUrl}
                        />
                        <TextInputHint>
                            Syncs habits across your devices.
                        </TextInputHint>
                    </View>
                </View>
            </Card>

            <Text className="mb-2 ml-1 mt-1 text-xs font-semibold uppercase tracking-wide text-ink-3">
                Account
            </Text>
            <AccountSection />
        </AppScreen>
    );
}

// An empty Server URL is the standalone case and outranks everything — there is nothing to be out
// of date with. Otherwise a failure outranks a success, since the last error is what the user needs
// to act on, and "never synced" reads as not-synced rather than as up-to-date.
function syncState(status: {
    savedServerUrl: string;
    lastSyncedAt: number | null;
    isSyncing: boolean;
    failed: boolean;
}): SyncState {
    if (!status.savedServerUrl) return "standalone";
    if (status.isSyncing) return "syncing";
    if (status.failed) return "error";
    if (status.lastSyncedAt === null) return "not-synced";

    return "connected";
}

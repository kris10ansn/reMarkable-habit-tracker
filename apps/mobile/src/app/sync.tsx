import { SyncStatusCard } from "@/components/sync/SyncStatusCard";
import { AppScreen } from "@/components/ui/AppScreen";
import { Card } from "@/components/ui/Card";
import {
    TextInputField,
    TextInputHint,
    TextInputLabel,
} from "@/components/ui/TextField";
import { useUpdateEffect } from "@/lib/useUpdateEffect";
import {
    syncErrorReason,
    useSettings,
    useSync,
    useUpdateSettings,
} from "@/state/queries";
import { useState } from "react";
import { View } from "react-native";

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

    const savedServerUrl = settings.data?.syncServerUrl ?? "";
    const lastSyncedAt = settings.data?.lastSyncedAt ?? null;

    const syncNow = () =>
        sync.mutate({ syncServerUrl: savedServerUrl, lastSyncedAt });

    const state = syncState({
        savedServerUrl,
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
                onSyncNow={syncNow}
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

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

function relativeTime(
    instant: number | null,
    now: number = Date.now(),
): string {
    if (instant === null) return "never";

    const elapsed = now - instant;
    if (elapsed < MINUTE) return "just now";
    if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)} min ago`;
    if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)} h ago`;

    return `${Math.floor(elapsed / DAY)} d ago`;
}

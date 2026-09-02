import { ActivityIndicator, Pressable, Text, View } from "react-native";

import { Card } from "@/components/ui/Card";
import { Icon, type MaterialIconName } from "@/components/ui/Icon";
import { colors } from "@/theme/colors";
import { twMerge } from "tailwind-merge";

export type SyncState =
    | "connected"
    | "dirty"
    | "standalone"
    | "syncing"
    | "error"
    | "not-synced";

export type SyncStatusCardProps = {
    state: SyncState;
    lastSynced?: string;
    syncDetail?: string;
    errorReason?: string;
    onSyncNow?: () => void;
};

export type StateView = {
    icon: MaterialIconName;
    medallionClass: string;
    iconClass: string;
    dotClass: string;
    label: string;
    detail: (props: SyncStatusCardProps) => string;
    action: { label: string; enabled: boolean; busy?: boolean };
};

const stateViews: Record<SyncState, StateView> = {
    connected: {
        icon: "cloud-done",
        medallionClass: "bg-done-soft",
        iconClass: "text-done",
        dotClass: "bg-done",
        label: "No unsynced changes",
        detail: ({ lastSynced }) => `Last synced ${lastSynced}`,
        action: { label: "Sync now", enabled: true },
    },
    dirty: {
        icon: "cloud-sync",
        medallionClass: "bg-yellow-50",
        iconClass: "text-yellow-500",
        dotClass: "bg-yellow-500",
        label: "Changes not synced",
        detail: ({ lastSynced }) => `Last synced ${lastSynced}`,
        action: { label: "Sync now", enabled: true },
    },
    standalone: {
        icon: "cloud-off",
        medallionClass: "bg-ink-3/10",
        iconClass: "text-ink-3",
        dotClass: "bg-ink-3",
        label: "Standalone",
        detail: () => "Running fully on this device",
        action: { label: "Sync now", enabled: false },
    },
    syncing: {
        icon: "cloud-sync",
        medallionClass: "bg-accent-soft",
        iconClass: "text-accent",
        dotClass: "bg-accent",
        label: "Syncing…",
        detail: ({ syncDetail }) => syncDetail ?? "Sending changes",
        action: { label: "Syncing…", enabled: false, busy: true },
    },
    error: {
        icon: "cloud-off",
        medallionClass: "bg-slip-soft",
        iconClass: "text-slip",
        dotClass: "bg-slip",
        label: "Couldn't sync",
        detail: ({ errorReason }) => errorReason ?? "Check your connection",
        action: { label: "Try again", enabled: true },
    },
    ["not-synced"]: {
        icon: "cloud-sync",
        medallionClass: "bg-yellow-50",
        iconClass: "text-yellow-500",
        dotClass: "bg-yellow-500",
        label: "Not synced yet",
        detail: ({ lastSynced }) => `Last synced ${lastSynced}`,
        action: { label: "Sync now", enabled: true, busy: false },
    },
};

export function SyncStatusCard(props: SyncStatusCardProps) {
    const view = stateViews[props.state];

    return (
        <Card className="mb-3 flex-row items-center gap-3.5 p-4">
            <View
                className={twMerge(
                    "h-10 w-10 items-center justify-center rounded-full",
                    view.medallionClass,
                )}
            >
                <Icon name={view.icon} size={21} className={view.iconClass} />
            </View>

            <View className="min-w-0 flex-1">
                <View className="flex-row items-center gap-1.5">
                    <View
                        className={twMerge(
                            "h-[7px] w-[7px] rounded-full",
                            view.dotClass,
                        )}
                    />
                    <Text
                        numberOfLines={1}
                        className="shrink text-[15px] font-semibold text-ink"
                    >
                        {view.label}
                    </Text>
                </View>
                <Text numberOfLines={1} className="text-[12px] text-ink-3">
                    {view.detail(props)}
                </Text>
            </View>

            <SyncActionPill {...view.action} onPress={props.onSyncNow} />
        </Card>
    );
}

function SyncActionPill({
    label,
    enabled,
    busy,
    onPress,
}: StateView["action"] & { onPress?: () => void }) {
    return (
        <Pressable
            onPress={onPress}
            disabled={!enabled}
            className={twMerge(
                "flex-shrink-0 flex-row items-center gap-1.5 rounded-full px-4 py-2.5",
                enabled
                    ? "bg-accent active:opacity-80"
                    : "border border-line bg-surface-2",
            )}
        >
            {busy ? (
                <View className="h-[15px] w-[15px] items-center justify-center">
                    <ActivityIndicator
                        size="small"
                        color={colors.ink3}
                        className="scale-75"
                    />
                </View>
            ) : (
                <Icon
                    name="sync"
                    size={15}
                    className={enabled ? "text-white" : "text-ink-3"}
                />
            )}
            <Text
                className={twMerge(
                    "text-[13px] font-semibold",
                    enabled ? "text-white" : "text-ink-3",
                )}
            >
                {label}
            </Text>
        </Pressable>
    );
}

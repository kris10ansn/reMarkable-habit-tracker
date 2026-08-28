import { useRouter } from "expo-router";
import { Alert, Text, View } from "react-native";

import type { SessionDto } from "@/api/gen";
import { AppScreen } from "@/components/ui/AppScreen";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { IconButton } from "@/components/ui/IconButton";
import { Loading } from "@/components/ui/Loading";
import { Pill } from "@/components/ui/Pill";
import { relativeTime } from "@/lib/relativeTime";
import {
    authErrorReason,
    useAuthSession,
    useRevokeSession,
    useSessions,
} from "@/state/queries";

// Pushed from the Sync tab's Account card. Not a tab itself — see _layout.tsx, where it's
// registered with `href: null` so it's reachable via router.push without showing in the tab bar.
export default function DevicesScreen() {
    const router = useRouter();
    const session = useAuthSession();
    const sessions = useSessions();

    return (
        <AppScreen
            eyebrow="Account"
            title="Linked devices"
            subtitle="Every device signed into your account"
            onBack={() => router.back()}
        >
            {!session.data ? (
                <Card>
                    <Text className="text-[13px] text-ink-2">
                        You’re signed out. Sign in again on the Sync tab to see
                        linked devices.
                    </Text>
                </Card>
            ) : (
                <>
                    <Button
                        label="Link a device"
                        onPress={() => router.push("/link-device")}
                        className="mb-3"
                    />

                    {sessions.isPending ? (
                        <Loading />
                    ) : sessions.isError ? (
                        <Card>
                            <Text className="text-[13px] text-slip">
                                {authErrorReason(sessions.error)}
                            </Text>
                        </Card>
                    ) : (
                        (sessions.data ?? []).map((row) => (
                            <DeviceRow key={row.id} session={row} />
                        ))
                    )}
                </>
            )}
        </AppScreen>
    );
}

function DeviceRow({ session }: { session: SessionDto }) {
    const revoke = useRevokeSession();

    const confirmRevoke = () =>
        Alert.alert(
            session.isCurrentDevice
                ? "Sign out this device?"
                : `Revoke “${session.deviceName}”?`,
            session.isCurrentDevice
                ? "This is the device you’re using right now — you’ll be signed out here too."
                : "That device will need to sign in again to sync.",
            [
                { text: "Cancel", style: "cancel" },
                {
                    text: session.isCurrentDevice ? "Sign out" : "Revoke",
                    style: "destructive",
                    onPress: () =>
                        revoke.mutate({
                            id: session.id,
                            isCurrentDevice: session.isCurrentDevice,
                        }),
                },
            ],
        );

    return (
        <Card className="mb-2.5 flex-row items-center gap-3">
            <View className="min-w-0 flex-1">
                <View className="flex-row items-center gap-1.5">
                    <Text
                        numberOfLines={1}
                        className="shrink text-[15px] font-semibold text-ink"
                    >
                        {session.deviceName}
                    </Text>
                    {session.isCurrentDevice ? (
                        <Pill label="This device" />
                    ) : null}
                </View>
                <Text className="mt-0.5 text-[12px] text-ink-3">
                    Linked {relativeTime(session.createdAt)} · last used{" "}
                    {relativeTime(session.lastUsedAt)}
                </Text>
            </View>

            <IconButton
                icon="link-off"
                onPress={confirmRevoke}
                disabled={revoke.isPending}
            />
        </Card>
    );
}

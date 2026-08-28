import { useRouter } from "expo-router";
import { Pressable, Text, View } from "react-native";
import { twMerge } from "tailwind-merge";

import type { AuthSession } from "@/auth/session";
import { Card } from "@/components/ui/Card";
import { Icon, type MaterialIconName } from "@/components/ui/Icon";
import { Pill } from "@/components/ui/Pill";
import { authErrorReason, useLogout } from "@/state/queries";

interface Props {
    session: AuthSession;
}

// The signed-in view of the Sync tab's Account card: who's signed in, plus the two actions that
// touch the account (linked devices, log out). Signing out here only clears the local token — see
// useLogout — never local habit data.
export function AccountSummary({ session }: Props) {
    const router = useRouter();
    const logout = useLogout();

    return (
        <Card className="flex-col gap-3.5">
            <View className="flex-row items-center gap-3">
                <View className="h-10 w-10 items-center justify-center rounded-full bg-accent-soft">
                    <Icon name="person" size={20} className="text-accent" />
                </View>
                <View className="min-w-0 flex-1">
                    <Text
                        numberOfLines={1}
                        className="text-[15px] font-semibold text-ink"
                    >
                        {session.user.email}
                    </Text>
                    <Text className="text-[12px] text-ink-3">
                        Signed in on this device
                    </Text>
                </View>
                {session.user.isAdmin ? <Pill label="Admin" /> : null}
            </View>

            <View className="flex-row gap-2.5">
                <AccountActionButton
                    icon="devices"
                    label="Linked devices"
                    onPress={() => router.push("/devices")}
                />
                <AccountActionButton
                    icon="logout"
                    label={logout.isPending ? "Logging out…" : "Log out"}
                    tone="danger"
                    disabled={logout.isPending}
                    onPress={() => logout.mutate()}
                />
            </View>

            {logout.isError ? (
                <Text className="text-[13px] text-slip">
                    {authErrorReason(logout.error)}
                </Text>
            ) : null}
        </Card>
    );
}

function AccountActionButton({
    icon,
    label,
    onPress,
    disabled,
    tone = "neutral",
}: {
    icon: MaterialIconName;
    label: string;
    onPress: () => void;
    disabled?: boolean;
    tone?: "neutral" | "danger";
}) {
    return (
        <Pressable
            onPress={onPress}
            disabled={disabled}
            className={twMerge(
                "flex-1 flex-row items-center justify-center gap-1.5 rounded-field border border-line bg-surface-2 px-3 py-3 active:opacity-70",
                disabled && "opacity-50",
            )}
        >
            <Icon
                name={icon}
                size={16}
                className={tone === "danger" ? "text-slip" : "text-ink-2"}
            />
            <Text
                className={twMerge(
                    "text-[13px] font-semibold",
                    tone === "danger" ? "text-slip" : "text-ink-2",
                )}
            >
                {label}
            </Text>
        </Pressable>
    );
}

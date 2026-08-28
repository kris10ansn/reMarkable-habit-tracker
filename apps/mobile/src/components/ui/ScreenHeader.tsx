import { Pressable, Text, View } from "react-native";

import { Icon } from "@/components/ui/Icon";

interface Props {
    eyebrow?: string;
    title: string;
    subtitle?: string;
    // Set on screens reached by pushing a route rather than a tab (e.g. the linked-devices and
    // link-a-device screens) — tabs never pass this, so their header is unchanged.
    onBack?: () => void;
}

// The in-app page header (the native nav header is hidden). Shared by every tab
// so titles line up across screens.
export function ScreenHeader({ eyebrow, title, subtitle, onBack }: Props) {
    return (
        <View className="flex-row items-start gap-1 px-4 pb-3 pt-1">
            {onBack ? (
                <Pressable
                    onPress={onBack}
                    hitSlop={8}
                    className="mt-1 h-8 w-8 items-center justify-center rounded-full active:opacity-70"
                >
                    <Icon name="arrow-back" size={20} className="text-ink-2" />
                </Pressable>
            ) : null}
            <View className="flex-1">
                {eyebrow ? (
                    <Text className="text-xs font-semibold uppercase tracking-wide text-accent">
                        {eyebrow}
                    </Text>
                ) : null}
                <Text className="mt-0.5 text-3xl font-bold tracking-tight text-ink">
                    {title}
                </Text>
                {subtitle ? (
                    <Text className="mt-0.5 text-[13px] text-ink-2">
                        {subtitle}
                    </Text>
                ) : null}
            </View>
        </View>
    );
}

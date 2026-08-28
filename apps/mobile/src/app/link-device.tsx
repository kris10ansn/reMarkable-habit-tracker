import { useRouter } from "expo-router";
import { useState } from "react";
import { Text, View } from "react-native";

import { AppScreen } from "@/components/ui/AppScreen";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { Loading } from "@/components/ui/Loading";
import { TextInputField, TextInputLabel } from "@/components/ui/TextField";
import {
    pairingErrorReason,
    usePairingApprove,
    usePairingLookup,
} from "@/state/queries";

const CODE_LENGTH = 6;

// Pushed from the linked-devices screen. Not a tab — see _layout.tsx (`href: null`). The tablet
// (or another client doing the TV-style pairing flow, per AUTH_PLAN.md) displays a 6-character
// code; typing it here looks up who's asking (GET /api/pairing/{code}) before Approve is offered,
// so the owner never approves a device they can't identify.
export default function LinkDeviceScreen() {
    const router = useRouter();
    const [code, setCode] = useState("");
    const [approvedDeviceName, setApprovedDeviceName] = useState<string | null>(
        null,
    );

    const normalized = code.trim().toUpperCase();
    const ready = normalized.length === CODE_LENGTH;

    const lookup = usePairingLookup(code);
    const approve = usePairingApprove();

    const onChangeCode = (text: string) => {
        setCode(text);
        setApprovedDeviceName(null);
    };

    const onApprove = () => {
        const deviceName = lookup.data?.deviceName ?? "the device";
        approve.mutate(normalized, {
            onSuccess: () => setApprovedDeviceName(deviceName),
        });
    };

    return (
        <AppScreen
            eyebrow="Account"
            title="Link a device"
            subtitle="Enter the 6-character code shown on the other device"
            onBack={() => router.back()}
        >
            <Card className="flex-col gap-3.5">
                <View>
                    <TextInputLabel>Pairing code</TextInputLabel>
                    <TextInputField
                        value={code}
                        onChangeText={onChangeCode}
                        placeholder="ABCDEF"
                        autoCapitalize="characters"
                        autoCorrect={false}
                        maxLength={CODE_LENGTH}
                        className="text-center text-[20px] tracking-[4px]"
                    />
                    <Text className="ml-1 mt-2 text-xs leading-5 text-ink-2">
                        Case doesn’t matter — the server normalizes it.
                    </Text>
                </View>

                {ready && lookup.isPending ? <Loading /> : null}

                {ready && lookup.isError ? (
                    <Text className="text-[13px] text-slip">
                        {pairingErrorReason(lookup.error)}
                    </Text>
                ) : null}

                {ready && lookup.data ? (
                    approvedDeviceName ? (
                        <Text className="text-[13px] font-semibold text-done">
                            Approved “{approvedDeviceName}”. It can finish
                            connecting now.
                        </Text>
                    ) : (
                        <>
                            <Text className="text-[15px] text-ink">
                                Requesting device:{" "}
                                <Text className="font-semibold">
                                    {lookup.data.deviceName}
                                </Text>
                            </Text>

                            {approve.isError ? (
                                <Text className="text-[13px] text-slip">
                                    {pairingErrorReason(approve.error)}
                                </Text>
                            ) : null}

                            <Button
                                label={
                                    approve.isPending ? "Approving…" : "Approve"
                                }
                                onPress={onApprove}
                                disabled={approve.isPending}
                            />
                        </>
                    )
                ) : null}
            </Card>
        </AppScreen>
    );
}

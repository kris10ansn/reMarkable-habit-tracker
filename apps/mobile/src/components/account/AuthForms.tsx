import { useState } from "react";
import { Pressable, Text, View } from "react-native";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { TextInputField, TextInputLabel } from "@/components/ui/TextField";
import { authErrorReason, useLogin, useSignup } from "@/state/queries";
import { twMerge } from "tailwind-merge";

// The password rule the backend enforces (min length, no composition rules) — mirrored here only
// so the button disables with a clear reason, never re-implemented or tightened.
const MIN_PASSWORD_LENGTH = 10;

type Mode = "signup" | "login";

// One card, two modes. A toggle rather than two screens: there's nowhere useful to navigate to,
// and switching modes should keep whatever the user already typed for email/password.
export function AuthForms() {
    const [mode, setMode] = useState<Mode>("signup");
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [inviteCode, setInviteCode] = useState("");

    const signup = useSignup();
    const login = useLogin();
    const pending = mode === "signup" ? signup : login;

    const passwordTooShort =
        password.length > 0 && password.length < MIN_PASSWORD_LENGTH;
    const canSubmit =
        email.trim().length > 0 &&
        password.length >= MIN_PASSWORD_LENGTH &&
        !pending.isPending;

    const submit = () => {
        if (!canSubmit) return;

        if (mode === "signup") {
            signup.mutate({
                email: email.trim(),
                password,
                inviteCode: inviteCode.trim() || undefined,
            });
        } else {
            login.mutate({ email: email.trim(), password });
        }
    };

    return (
        <Card className="flex-col gap-3.5">
            <View className="flex-row self-start overflow-hidden rounded-full border border-line">
                <ModeTab
                    label="Sign up"
                    active={mode === "signup"}
                    onPress={() => setMode("signup")}
                />
                <ModeTab
                    label="Log in"
                    active={mode === "login"}
                    onPress={() => setMode("login")}
                />
            </View>

            <View>
                <TextInputLabel>Email</TextInputLabel>
                <TextInputField
                    value={email}
                    onChangeText={setEmail}
                    placeholder="you@example.com"
                    autoCapitalize="none"
                    autoCorrect={false}
                    inputMode="email"
                    autoComplete="email"
                    textContentType="emailAddress"
                />
            </View>

            <View>
                <TextInputLabel>Password</TextInputLabel>
                <TextInputField
                    value={password}
                    onChangeText={setPassword}
                    placeholder="At least 10 characters"
                    secureTextEntry
                    autoComplete={
                        mode === "signup" ? "new-password" : "current-password"
                    }
                    textContentType={
                        mode === "signup" ? "newPassword" : "password"
                    }
                />
                {passwordTooShort ? (
                    <Text className="ml-1 mt-2 text-xs leading-5 text-slip">
                        Needs to be at least {MIN_PASSWORD_LENGTH} characters.
                    </Text>
                ) : null}
            </View>

            {mode === "signup" ? (
                <View>
                    <TextInputLabel>Invite code (optional)</TextInputLabel>
                    <TextInputField
                        value={inviteCode}
                        onChangeText={setInviteCode}
                        placeholder="Only needed after the first account"
                        autoCapitalize="characters"
                        autoCorrect={false}
                        autoComplete="off"
                        importantForAutofill="no"
                    />
                    <Text className="ml-1 mt-2 text-xs leading-5 text-ink-2">
                        The very first account on a fresh server needs no code.
                    </Text>
                </View>
            ) : null}

            {pending.isError ? (
                <Text className="text-[13px] text-slip">
                    {authErrorReason(pending.error)}
                </Text>
            ) : null}

            <Button
                label={submitLabel(mode, pending.isPending)}
                onPress={submit}
                disabled={!canSubmit}
            />
        </Card>
    );
}

function submitLabel(mode: Mode, pending: boolean): string {
    if (mode === "signup") return pending ? "Signing up…" : "Sign up";
    return pending ? "Logging in…" : "Log in";
}

function ModeTab({
    label,
    active,
    onPress,
}: {
    label: string;
    active: boolean;
    onPress: () => void;
}) {
    return (
        <Pressable onPress={onPress} className="active:opacity-70">
            <Text
                className={twMerge(
                    "px-4 py-1.5 text-[13px] font-semibold",
                    active ? "bg-accent text-white" : "text-ink-2",
                )}
            >
                {label}
            </Text>
        </Pressable>
    );
}

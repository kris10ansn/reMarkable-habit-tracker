import { Text } from "react-native";

import { AccountSummary } from "@/components/account/AccountSummary";
import { AuthForms } from "@/components/account/AuthForms";
import { Card } from "@/components/ui/Card";
import { useAuthSession, useSettings } from "@/state/queries";

// The Sync tab's Account block: signup/login when signed out, or the current account + linked-
// devices/log-out actions when signed in. An empty Server URL is standalone — decision 10 in
// AUTH_PLAN.md — so there is nothing to sign into yet and the forms don't render at all.
export function AccountSection() {
    const settings = useSettings();
    const session = useAuthSession();

    const baseURL = settings.data?.syncServerUrl.trim() ?? "";

    if (!baseURL) {
        return (
            <Card>
                <Text className="text-[13px] text-ink-2">
                    Set a Server URL above to create or sign into an account.
                </Text>
            </Card>
        );
    }

    // Avoid a signed-out flash while the SecureStore read resolves on first mount.
    if (session.isPending) {
        return null;
    }

    return session.data ? (
        <AccountSummary session={session.data} />
    ) : (
        <AuthForms />
    );
}

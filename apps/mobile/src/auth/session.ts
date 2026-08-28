import * as SecureStore from "expo-secure-store";

import type { UserDto } from "@/api/gen";

// The only module allowed to touch SecureStore — everything else goes through
// getAuthSession/setAuthSession/clearAuthSession. Holds the bearer token plus the small user
// record returned alongside it at signup/login, so the account UI (email, admin badge) doesn't
// need a network round trip on every app start. Deliberately never mirrored into SQLite/Drizzle:
// the token is the one piece of state that must vanish independently of local habit data, and
// keeping the two stores structurally separate is what makes that guarantee cheap to keep (see
// AUTH_PLAN.md decision 10 — auth failure never touches local data).
const SESSION_KEY = "auth-session";

export type AuthSession = {
    token: string;
    user: UserDto;
};

export async function getAuthSession(): Promise<AuthSession | null> {
    const raw = await SecureStore.getItemAsync(SESSION_KEY);
    if (!raw) return null;

    try {
        return JSON.parse(raw) as AuthSession;
    } catch {
        // Corrupt/unreadable value — treat it as signed out rather than throwing at app start.
        return null;
    }
}

export async function setAuthSession(session: AuthSession): Promise<void> {
    await SecureStore.setItemAsync(SESSION_KEY, JSON.stringify(session));
}

export async function clearAuthSession(): Promise<void> {
    await SecureStore.deleteItemAsync(SESSION_KEY);
}

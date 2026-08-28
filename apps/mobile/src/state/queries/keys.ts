// Query keys for the whole seam, in one place because they are the cross-entity coupling: habit
// and entry mutations both invalidate the streaks prefix. `streaksKey` is package-internal — it is
// always used with a signature suffix (see streaks.ts), so nothing outside targets it directly.
export const habitsKey = ["habits"] as const;
export const entriesKey = (monthKey: string) => ["entries", monthKey] as const;
export const streaksKey = ["streaks"] as const;
export const settingsKey = ["settings"] as const;

// This device's own signed-in session (SecureStore-backed, see src/auth/session.ts) and the
// backend's view of every device signed into the account (GET /api/sessions) — two different
// things that happen to share a name in casual speech, so the key names spell out the difference.
export const authSessionKey = ["auth", "session"] as const;
export const linkedSessionsKey = ["auth", "linked-sessions"] as const;
export const pairingCodeKey = (code: string) =>
    ["auth", "pairing", code] as const;

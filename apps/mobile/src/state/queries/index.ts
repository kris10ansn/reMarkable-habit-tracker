// The screens' entire data seam: TanStack Query wraps the SQLite repo, owning caching (the
// per-month cache is the retention policy — unvisited months are evicted by gcTime), loading/error
// state, and optimistic mutations. `useSync` (below) is where the backend round-trip slots in.
// Split per entity; this index is the public surface (streaksKey stays internal).
export {
    authErrorReason,
    isUnauthorized,
    pairingErrorReason,
    useAuthSession,
    useLogin,
    useLogout,
    usePairingApprove,
    usePairingLookup,
    useRevokeSession,
    useSessions,
    useSignup,
    type LoginInput,
    type SignupInput,
} from "./auth";
export { useMonthEntries, useToggleEntry, type ToggleFn } from "./entries";
export {
    useCreateHabit,
    useDeleteHabit,
    useHabits,
    useReorderHabit,
    useUpdateHabit,
} from "./habits";
export { entriesKey, habitsKey } from "./keys";
export { useSettings, useUpdateSettings } from "./settings";
export { useStreaks } from "./streaks";
export { syncErrorReason, useSync } from "./sync";

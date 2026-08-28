import {
    useMutation,
    useQuery,
    useQueryClient,
    type QueryClient,
} from "@tanstack/react-query";

import { ApiError, NetworkError } from "@/api/client";
import {
    deleteApiSessionsId,
    getApiPairingCode,
    getApiSessions,
    postApiAuthLogin,
    postApiAuthLogout,
    postApiAuthSignup,
    postApiPairingApprove,
} from "@/api/gen";
import { getDeviceName } from "@/auth/deviceName";
import {
    clearAuthSession,
    getAuthSession,
    setAuthSession,
} from "@/auth/session";

import { useSettings } from "@/state/queries/settings";
import { authSessionKey, linkedSessionsKey, pairingCodeKey } from "./keys";

const NO_SERVER_URL_MESSAGE =
    "No Server URL set — set one on the Sync tab first.";

// The Server URL setting doubles as the backend account's address: there is nothing to sign up or
// log into without one. Every mutation below reads it fresh rather than taking it as an argument,
// same as useSync does, so it can never go stale against an in-flight edit on the Sync tab.
function useBaseUrl(): string {
    const settings = useSettings();
    return settings.data?.syncServerUrl.trim() ?? "";
}

/**
 * This device's own signed-in session — the SecureStore read, wrapped as a query so every screen
 * that cares (the Sync tab's account card, the devices list, pairing) re-renders together whenever
 * it changes. `null` and standalone (no Server URL) look the same to callers: signed out.
 */
export function useAuthSession() {
    return useQuery({
        queryKey: authSessionKey,
        queryFn: getAuthSession,
        staleTime: Infinity,
    });
}

export type SignupInput = {
    email: string;
    password: string;
    inviteCode?: string;
};

export function useSignup() {
    const queryClient = useQueryClient();
    const baseURL = useBaseUrl();

    return useMutation({
        mutationFn: async (input: SignupInput) => {
            if (!baseURL) throw new Error(NO_SERVER_URL_MESSAGE);

            const response = await postApiAuthSignup(
                {
                    email: input.email,
                    password: input.password,
                    deviceName: getDeviceName(),
                    inviteCode: input.inviteCode?.trim() || null,
                },
                { baseURL },
            );

            await setAuthSession({
                token: response.token,
                user: response.user,
            });
            return response;
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: authSessionKey });
        },
    });
}

export type LoginInput = { email: string; password: string };

export function useLogin() {
    const queryClient = useQueryClient();
    const baseURL = useBaseUrl();

    return useMutation({
        mutationFn: async (input: LoginInput) => {
            if (!baseURL) throw new Error(NO_SERVER_URL_MESSAGE);

            const response = await postApiAuthLogin(
                {
                    email: input.email,
                    password: input.password,
                    deviceName: getDeviceName(),
                },
                { baseURL },
            );

            await setAuthSession({
                token: response.token,
                user: response.user,
            });
            return response;
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: authSessionKey });
        },
    });
}

export function useLogout() {
    const queryClient = useQueryClient();
    const baseURL = useBaseUrl();

    return useMutation({
        mutationFn: async () => {
            // Best-effort server-side revocation — but signing out locally has to succeed even
            // offline, since the user asked to leave this device, not to reach the network.
            if (baseURL) {
                try {
                    await postApiAuthLogout({ baseURL });
                } catch {
                    // The token dies locally regardless; see the clearAuthSession() call below.
                }
            }

            await clearAuthSession();
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: authSessionKey });
            queryClient.invalidateQueries({ queryKey: linkedSessionsKey });
        },
    });
}

/** True when `error` is the backend rejecting a bearer token. */
function isUnauthorized(error: unknown): boolean {
    return error instanceof ApiError && error.status === 401;
}

/**
 * The single reaction to the backend rejecting a bearer token. By the time this runs, `client.ts`
 * has already discarded the dead token from SecureStore (see its 401 handling), so all that's left
 * is letting `useAuthSession()` re-read the now-missing session and the UI settle on signed-out —
 * nothing else is touched, least of all SQLite.
 *
 * Wired once onto the QueryClient's query and mutation caches in `AppProviders`, so no individual
 * query or mutation has to remember it — forgetting it used to mean the UI kept claiming "signed
 * in" against a token the transport had already thrown away. It also fires for the 401 a
 * wrong-password login returns, which is a harmless no-op: that request carried no token, so there
 * is no session to re-read.
 */
export function invalidateSessionOnUnauthorized(
    queryClient: QueryClient,
    error: unknown,
): void {
    if (isUnauthorized(error)) {
        queryClient.invalidateQueries({ queryKey: authSessionKey });
    }
}

/** The linked-devices list (GET /api/sessions) — every device holding a session for this account. */
export function useSessions() {
    const authSession = useAuthSession();
    const baseURL = useBaseUrl();

    return useQuery({
        queryKey: linkedSessionsKey,
        queryFn: () => getApiSessions({ baseURL }),
        enabled: Boolean(authSession.data) && Boolean(baseURL),
    });
}

export function useRevokeSession() {
    const queryClient = useQueryClient();
    const baseURL = useBaseUrl();

    return useMutation({
        mutationFn: async (input: { id: string; isCurrentDevice: boolean }) => {
            await deleteApiSessionsId(input.id, { baseURL });

            // Revoking this device's own session kills the token server-side either way, so drop
            // it locally too rather than leaving the app holding a token whose next use is just a
            // 401 — this is the "revoking the current device = signing out" case from the plan.
            if (input.isCurrentDevice) {
                await clearAuthSession();
            }

            return input;
        },
        onSuccess: ({ isCurrentDevice }) => {
            queryClient.invalidateQueries({ queryKey: linkedSessionsKey });
            if (isCurrentDevice) {
                queryClient.invalidateQueries({ queryKey: authSessionKey });
            }
        },
    });
}

/**
 * Looks up a tablet's pairing code (GET /api/pairing/{code}) to show its requesting device name
 * before Approve is offered. Only runs once a full 6-character code has been typed — the backend's
 * alphabet excludes 0/O/1/I but normalizes case, so casing is not checked client-side.
 */
export function usePairingLookup(code: string) {
    const baseURL = useBaseUrl();
    const normalized = code.trim().toUpperCase();

    return useQuery({
        queryKey: pairingCodeKey(normalized),
        queryFn: () => getApiPairingCode(normalized, { baseURL }),
        enabled: normalized.length === 6 && Boolean(baseURL),
        retry: false,
    });
}

export function usePairingApprove() {
    const baseURL = useBaseUrl();

    return useMutation({
        mutationFn: (code: string) => {
            if (!baseURL) throw new Error(NO_SERVER_URL_MESSAGE);

            return postApiPairingApprove(
                { code: code.trim().toUpperCase() },
                { baseURL },
            );
        },
    });
}

/** What an account-flow error reads as next to a form or action button. Mirrors `syncErrorReason`
 * in sync.ts — the same "the card renders it, it decides nothing" split. */
export function authErrorReason(error: unknown): string {
    if (error instanceof NetworkError) {
        return "Couldn't reach the server — check the URL and your connection.";
    }

    if (error instanceof ApiError) {
        if (error.status === 401) return "Incorrect email or password.";
        if (error.status === 409) return "That email is already registered.";
        if (error.status === 400)
            return "That invite code isn't valid, or one is required.";
        return `Server returned ${error.status}.`;
    }

    return error instanceof Error ? error.message : "Something went wrong.";
}

/** Distinct messages for the two documented pairing failures (404 unknown/expired, 409 already
 * approved) — the Link a Device screen needs to tell them apart, not just say "failed". */
export function pairingErrorReason(error: unknown): string {
    if (error instanceof NetworkError) {
        return "Couldn't reach the server — check the URL and your connection.";
    }

    if (error instanceof ApiError) {
        if (error.status === 404) return "That code is unknown or has expired.";
        if (error.status === 409)
            return "That device has already been approved.";
        return `Server returned ${error.status}.`;
    }

    return error instanceof Error ? error.message : "Something went wrong.";
}

// The HTTP transport under the generated backend client (`src/api/gen/`). kubb generates one
// function per backend operation and has each of them delegate the actual request to the default
// export here (see `client.importPath` in kubb.config.ts) — so this file is the single place that
// decides how mobile talks to the backend, and the only hand-written part of the seam.
//
// Deliberately stateless: there is no module-level base URL to fall stale. Mobile's Server URL is a
// user-editable setting (empty = standalone, see the Sync tab), so every call passes the URL it
// wants — `sync(request, { baseURL: settings.syncServerUrl })`. A caller with no server configured
// is not supposed to reach here at all.
//
// Also the single place that attaches the bearer token (see `src/auth/session.ts`) — every
// generated operation gets it for free, with no per-call wiring — and the single place that reacts
// to the server rejecting it: a 401 on a request that carried a token means that token is dead
// (revoked, or the session no longer exists), so it's discarded here. `/api/auth/signup` and
// `/api/auth/login` are the backend's anonymous endpoints (see AUTH_PLAN.md's endpoint table) and
// never get the header, so a 401 from either — wrong credentials — can never be confused with a
// dead token and never wipes a session that was working fine. Clearing storage is as far as this
// goes: it never touches SQLite, and it doesn't decide what the UI shows — callers read the
// resulting signed-out state through `useAuthSession()` (see `src/state/queries/auth.ts`).

import { clearAuthSession, getAuthSession } from "@/auth/session";

/** Per-request options. The generated operations fill in `method`/`url`/`data`; callers add `baseURL`. */
export type RequestConfig<TData = unknown> = {
    baseURL?: string;
    url?: string;
    method?: "GET" | "PUT" | "PATCH" | "POST" | "DELETE" | "OPTIONS" | "HEAD";
    // `unknown` rather than a record type, to match what kubb's generated operations pass for an
    // endpoint with query parameters. None of the backend's endpoints have any today.
    params?: unknown;
    data?: TData;
    signal?: AbortSignal;
    headers?: Record<string, string>;
};

/** What the transport hands back to a generated operation, which then unwraps `data`. */
export type ResponseConfig<TData = unknown> = {
    data: TData;
    status: number;
    statusText: string;
    headers: Headers;
};

/** The error payload type a generated operation declares for a failed call. */
export type ResponseErrorConfig<TError = unknown> = TError;

// The backend's own anonymous endpoints (see the endpoint table in AUTH_PLAN.md). Every other
// operation is either genuinely protected or harmlessly tolerant of a bearer header it doesn't
// need, so this is the only path-based special case the transport makes.
const ANONYMOUS_PATHS = new Set(["/api/auth/signup", "/api/auth/login"]);

/**
 * The transport signature. Generated operations accept a `client` override of this shape.
 *
 * `_TError` is unused here but structural: every generated operation calls the transport with
 * three type arguments (`request<Response, ResponseErrorConfig<Error>, Request>(…)`), so the slot
 * has to exist even though errors surface as a thrown `ApiError` rather than a return type.
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars -- see above: positional type slot
export type Client = <TResponseData, _TError = unknown, TRequestData = unknown>(
    config: RequestConfig<TRequestData>,
) => Promise<ResponseConfig<TResponseData>>;

/**
 * A non-2xx response. `body` is whatever the backend sent — for a rejected sync that is the
 * ASP.NET `ProblemDetails` shape, e.g. the 400 the backend returns when the client clock runs
 * further ahead than its skew tolerance allows.
 */
export class ApiError extends Error {
    readonly status: number;
    readonly statusText: string;
    readonly body: unknown;

    constructor(status: number, statusText: string, body: unknown) {
        super(`Backend responded ${status} ${statusText}`.trim());
        this.name = "ApiError";
        this.status = status;
        this.statusText = statusText;
        this.body = body;
    }
}

/** The request never left the device (offline, DNS failure, unreachable host, timeout). */
export class NetworkError extends Error {
    constructor(url: string, cause: unknown) {
        super(`Could not reach the backend at ${url}`);
        this.name = "NetworkError";
        this.cause = cause;
    }
}

function buildUrl(config: RequestConfig<unknown>): string {
    if (!config.baseURL) {
        throw new Error(
            "No backend base URL: pass `baseURL` from the Server URL setting. An empty Server URL means standalone — do not call the backend at all.",
        );
    }

    const base = config.baseURL.replace(/\/+$/, "");
    const path = (config.url ?? "").replace(/^\/*/, "/");
    const url = `${base}${path}`;

    const query = new URLSearchParams();
    const params = (config.params ?? {}) as Record<string, unknown>;
    for (const [key, value] of Object.entries(params)) {
        if (value !== undefined && value !== null) {
            query.append(key, String(value));
        }
    }

    const search = query.toString();
    return search ? `${url}?${search}` : url;
}

// `response.json()` on an empty or non-JSON body throws; a failed request should still surface its
// status rather than a parse error, so fall back to the raw text.
async function readBody(response: Response): Promise<unknown> {
    if (
        response.status === 204 ||
        response.status === 205 ||
        response.status === 304
    ) {
        return undefined;
    }

    const text = await response.text();
    if (!text) {
        return undefined;
    }

    try {
        return JSON.parse(text);
    } catch {
        return text;
    }
}

const client: Client = async <
    TResponseData,
    // eslint-disable-next-line @typescript-eslint/no-unused-vars -- positional slot, see `Client`
    _TError = unknown,
    TRequestData = unknown,
>(
    config: RequestConfig<TRequestData>,
): Promise<ResponseConfig<TResponseData>> => {
    const url = buildUrl(config);

    const isAnonymous = ANONYMOUS_PATHS.has(config.url ?? "");
    const session = isAnonymous ? null : await getAuthSession();

    const headers: Record<string, string> = {
        Accept: "application/json",
        ...(config.data === undefined
            ? {}
            : { "Content-Type": "application/json" }),
        ...(session ? { Authorization: `Bearer ${session.token}` } : {}),
        ...config.headers,
    };

    // ASP.NET advertises `application/*+json` alongside `application/json` on every action, and the
    // generated operations pass that spelling straight through as a request header. A wildcard is
    // not a valid Content-Type to send, so collapse it to the concrete type the backend parses.
    if (headers["Content-Type"]?.includes("*")) {
        headers["Content-Type"] = "application/json";
    }

    let response: Response;
    try {
        response = await fetch(url, {
            method: config.method ?? "GET",
            signal: config.signal,
            headers,
            body:
                config.data === undefined
                    ? undefined
                    : JSON.stringify(config.data),
        });
    } catch (cause) {
        throw new NetworkError(url, cause);
    }

    const body = await readBody(response);

    if (!response.ok) {
        if (response.status === 401 && session) {
            // The token we sent was rejected — dead or revoked server-side. Discard it so the next
            // request doesn't resend a token the server has already told us to forget. Local habit
            // data is untouched; UI state catches up via `useAuthSession()`.
            await clearAuthSession();
        }

        throw new ApiError(response.status, response.statusText, body);
    }

    return {
        data: body as TResponseData,
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
    };
};

export default client;

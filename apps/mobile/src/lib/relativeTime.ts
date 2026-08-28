const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

// Coarse "how long ago" for timestamps sourced from the backend (epoch ms) — last synced, session
// created/last-used. `null` reads as "never" rather than a blank, since every caller so far uses
// that to mean "hasn't happened yet".
export function relativeTime(
    instant: number | null,
    now: number = Date.now(),
): string {
    if (instant === null) return "never";

    const elapsed = now - instant;
    if (elapsed < MINUTE) return "just now";
    if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)} min ago`;
    if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)} h ago`;

    return `${Math.floor(elapsed / DAY)} d ago`;
}

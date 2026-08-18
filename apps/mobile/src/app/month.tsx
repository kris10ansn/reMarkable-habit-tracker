import { useMemo, useState } from "react";
import { RefreshControl } from "react-native";

import { MonthGrid } from "@/components/month/MonthGrid";
import { MonthNav } from "@/components/month/MonthNav";
import { AppScreen } from "@/components/ui/AppScreen";
import { Loading } from "@/components/ui/Loading";
import { SlideTransition } from "@/components/ui/SlideTransition";
import { addMonth, monthView, todayKey } from "@/domain/dates";
import {
    useHabits,
    useMonthEntries,
    useStreaks,
    useSync,
    useToggleEntry,
} from "@/state/queries";

// Month: the whole grid at review scale — days down, habits across. Navigable to any month;
// past and the current month are editable, future days are view-only.
export default function MonthScreen() {
    const today = todayKey();
    const [cursor, setCursor] = useState(() => {
        const now = new Date();
        return { year: now.getFullYear(), month: now.getMonth() };
    });
    // Sign of the last navigation: +1 next, -1 prev — drives which side the grid slides in from.
    const [direction, setDirection] = useState(1);
    // Stable per cursor so the memoized MonthGrid/rows aren't rebuilt on unrelated re-renders.
    const view = useMemo(
        () => monthView(cursor.year, cursor.month),
        [cursor.year, cursor.month],
    );

    const navigate = (delta: number) => {
        setDirection(delta);
        setCursor((prev) => addMonth(prev.year, prev.month, delta));
    };

    const habitsQuery = useHabits();
    const habits = habitsQuery.data ?? [];
    const entriesQuery = useMonthEntries(view.monthKey);
    const streaksQuery = useStreaks(habits);
    const toggle = useToggleEntry(view.monthKey);

    const sync = useSync();

    return (
        <AppScreen
            eyebrow="Overview"
            title="Month"
            subtitle="Your habits across the month"
            refreshControl={
                <RefreshControl
                    refreshing={habitsQuery.isPending || sync.isPending}
                    onRefresh={() =>
                        sync.mutate({ currentMonthKey: view.monthKey })
                    }
                />
            }
        >
            <MonthNav
                label={view.monthLabel}
                direction={direction}
                onPrev={() => navigate(-1)}
                onNext={() => navigate(1)}
            />
            {habitsQuery.isPending ? (
                <Loading />
            ) : (
                <SlideTransition
                    transitionKey={view.monthKey}
                    direction={direction}
                >
                    <MonthGrid
                        habits={habits}
                        view={view}
                        today={today}
                        entries={entriesQuery.data ?? []}
                        streaks={streaksQuery.data ?? {}}
                        onToggle={toggle}
                    />
                </SlideTransition>
            )}
        </AppScreen>
    );
}

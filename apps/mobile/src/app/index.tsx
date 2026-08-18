import { useMemo } from "react";

import { DaySummary } from "@/components/today/DaySummary";
import { HabitListItem } from "@/components/today/HabitListItem";
import { AppScreen } from "@/components/ui/AppScreen";
import { Loading } from "@/components/ui/Loading";
import {
    currentMonthView,
    monthDayLabel,
    todayKey,
    weekdayLabel,
} from "@/domain/dates";
import { entryIndex, outcomeAt } from "@/domain/entries";
import { isSuccess } from "@/domain/marks";
import {
    useHabits,
    useMonthEntries,
    useStreaks,
    useSync,
    useToggleEntry,
} from "@/state/queries";
import { RefreshControl } from "react-native";

// Today: the primary daily surface — log each habit at a glance. Always pinned to the real
// current month, whatever the Month tab is viewing.
export default function TodayScreen() {
    const now = new Date();
    const view = currentMonthView(now);
    const today = todayKey(now);

    const habitsQuery = useHabits();
    const habits = habitsQuery.data ?? [];
    const entriesQuery = useMonthEntries(view.monthKey);
    const streaksQuery = useStreaks(habits);

    const toggle = useToggleEntry(view.monthKey);
    const index = useMemo(
        () => entryIndex(entriesQuery.data ?? []),
        [entriesQuery.data],
    );
    const outcomeOf = (habitId: string) => outcomeAt(index, habitId, today);

    const logged = habits.filter((habit) =>
        isSuccess(habit.polarity, outcomeOf(habit.id)),
    ).length;
    const slips = habits.filter(
        (habit) =>
            habit.polarity === "Negative" && outcomeOf(habit.id) === "Failure",
    ).length;

    const sync = useSync();

    return (
        <AppScreen
            eyebrow={`${weekdayLabel(now)} · Today`}
            title={monthDayLabel(now)}
            subtitle={`${logged} of ${habits.length} habits logged`}
            refreshControl={
                <RefreshControl
                    refreshing={habitsQuery.isPending || sync.isPending}
                    onRefresh={() => sync.mutate({})}
                />
            }
        >
            {habitsQuery.isPending ? (
                <Loading />
            ) : (
                <>
                    <DaySummary
                        logged={logged}
                        total={habits.length}
                        slips={slips}
                    />
                    {habits.map((habit) => (
                        <HabitListItem
                            key={habit.id}
                            habit={habit}
                            outcome={outcomeOf(habit.id)}
                            streak={streaksQuery.data?.[habit.id]}
                            onToggle={() =>
                                toggle(habit.id, today, habit.polarity)
                            }
                        />
                    ))}
                </>
            )}
        </AppScreen>
    );
}

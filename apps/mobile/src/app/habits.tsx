import { AddHabitRow } from "@/components/habits/AddHabitRow";
import { EditHabitRow } from "@/components/habits/EditHabitRow";
import { AppScreen } from "@/components/ui/AppScreen";
import { Card } from "@/components/ui/Card";
import { CommunityIcon } from "@/components/ui/Icon";
import { Loading } from "@/components/ui/Loading";
import { SortableList, SortableListHandle } from "@/components/ui/SortableList";
import { Habit } from "@/domain/types";
import { useHabits, useReorderHabit, useSync } from "@/state/queries";
import { RefreshControl } from "react-native";

export default function HabitsScreen() {
    const habitsQuery = useHabits();
    const reorder = useReorderHabit();
    const sync = useSync();

    return (
        <AppScreen
            eyebrow="Manage"
            title="Habits"
            subtitle="Rename, reorder, set polarity, or add"
            avoidKeyboard
            refreshControl={
                <RefreshControl
                    refreshing={sync.isPending}
                    onRefresh={() => sync.mutate({})}
                />
            }
        >
            {habitsQuery.isPending ? (
                <Loading />
            ) : (
                <>
                    <SortableList
                        items={habitsQuery.data ?? []}
                        keyOf={(habit) => habit.id}
                        onReorder={(habitId, toIndex) =>
                            reorder.mutate({ habitId, toIndex })
                        }
                        renderRow={HabitRow}
                        rowClassName="pb-2.5"
                    />

                    <AddHabitRow />
                </>
            )}
        </AppScreen>
    );
}

const HabitRow = (habit: Habit) => (
    <Card className="flex-row items-center gap-3">
        <SortableListHandle className="-m-3 p-3">
            <CommunityIcon name="drag" />
        </SortableListHandle>

        <EditHabitRow habit={habit} />
    </Card>
);

import { useDatabase } from "@/db/client";
import { getSettings, SettingsPatch, updateSettings } from "@/db/repo/settings";
import type { settings } from "@/db/schema";
import { settingsKey } from "@/state/queries/keys";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

type Settings = typeof settings.$inferSelect;

export const useSettings = () => {
    const db = useDatabase();

    return useQuery({
        queryKey: settingsKey,
        queryFn: () => getSettings(db),
        staleTime: Infinity,
    });
};

export function useUpdateSettings() {
    const qc = useQueryClient();
    const db = useDatabase();

    return useMutation({
        mutationFn: (patch: SettingsPatch) => updateSettings(db, patch),
        onMutate: async (patch: SettingsPatch) => {
            await qc.cancelQueries({ queryKey: settingsKey });
            const prev = qc.getQueryData<Settings>(settingsKey);

            qc.setQueryData<Settings>(settingsKey, (old) =>
                old ? { ...old, ...patch } : old,
            );

            return { prev };
        },
        onError: (_err, _patch, ctx) => {
            if (ctx?.prev) qc.setQueryData(settingsKey, ctx.prev);
        },
        onSuccess: (row) => qc.setQueryData(settingsKey, row),
    });
}

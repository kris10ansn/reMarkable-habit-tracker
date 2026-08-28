import * as Device from "expo-device";

// The label this device sends at signup/login — shown back to the account owner in the linked-
// devices list, and to whoever approves a tablet pairing. `Device.modelName` is the closest thing
// to a stable, human-recognizable name on both platforms without extra entitlements: unlike
// `Device.deviceName`, which returns a generic "iPhone" on iOS 16+ unless the app adds a
// capability for it. Falling back to something honest beats a placeholder like "Unknown".
export function getDeviceName(): string {
    return Device.modelName ?? "Mobile device";
}

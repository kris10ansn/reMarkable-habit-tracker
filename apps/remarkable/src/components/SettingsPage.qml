import QtQuick 2.15
import ".." as App

Item {
    id: settingsPage

    property bool suspendImageEnabled: false
    property bool showPrivateHabits: false
    property string serverUrl: ""
    property string syncStatusText: ""

    // Tablet pairing (Connect flow). pairingConnected reflects whether SettingsStore is holding a
    // token; pairingStatus is PairingStore's own transient phase: "" (idle) | "requesting" |
    // "waiting" (code on screen, polling) | "expired" | "error".
    property bool pairingConnected: false
    property string pairingStatus: ""
    property string pairingCode: ""
    property string pairingErrorMessage: ""

    signal applyRequested(bool value)
    signal showPrivateHabitsApplied(bool value)
    signal serverUrlApplied(string url)
    signal syncNowRequested
    signal connectRequested
    signal disconnectRequested
    signal backRequested

    property bool staged: false
    property bool stagedShowPrivate: false
    property string stagedUrl: ""
    readonly property bool suspendImageDirty: staged !== suspendImageEnabled
    readonly property bool showPrivateDirty: stagedShowPrivate !== showPrivateHabits
    readonly property bool urlDirty: stagedUrl.trim() !== serverUrl
    readonly property bool dirty: suspendImageDirty || showPrivateDirty || urlDirty

    // A server address that is both set and committed. Both network actions gate on it: a staged
    // edit is not a server yet, so acting on the old address would talk to the wrong host.
    readonly property bool serverUrlReady: serverUrl.trim() !== "" && !urlDirty
    readonly property bool pairingRequestInFlight: pairingStatus === "requesting" || pairingStatus === "waiting"

    function _resync() {
        settingsPage.staged = settingsPage.suspendImageEnabled;
        settingsPage.stagedShowPrivate = settingsPage.showPrivateHabits;
        settingsPage.stagedUrl = settingsPage.serverUrl;
    }

    function _pairingHintText() {
        if (settingsPage.pairingStatus === "requesting") return "Requesting a code…";
        if (settingsPage.pairingStatus === "expired") return "That code expired.";
        if (settingsPage.pairingStatus === "error") return settingsPage.pairingErrorMessage;

        return "";
    }

    Component.onCompleted: settingsPage._resync()
    onVisibleChanged: if (visible)
        settingsPage._resync()
    // A committed change lands back here (the store properties follow), so re-sync the staged
    // values — Done becomes idle and dirty clears.
    onSuspendImageEnabledChanged: settingsPage._resync()
    onShowPrivateHabitsChanged: settingsPage._resync()
    onServerUrlChanged: settingsPage._resync()

    // Lowest sibling: taps on empty space fall through to here and drop input focus,
    // which dismisses the virtual keyboard. Buttons and the TextInput sit on top and
    // consume their own taps, so they're unaffected.
    MouseArea {
        anchors.fill: parent
        onPressed: urlInput.focus = false
    }

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: App.Theme.margin
        spacing: App.Theme.rowSpacing

        Text {
            text: "Settings"
            font.pixelSize: App.Theme.titleFont
            font.bold: true
            color: App.Theme.fg
        }

        Row {
            spacing: App.Theme.buttonGap

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Write to suspend image"
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
            }

            SegmentedToggle {
                anchors.verticalCenter: parent.verticalCenter
                value: settingsPage.staged
                onToggled: settingsPage.staged = value
            }
        }

        Row {
            spacing: App.Theme.buttonGap

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Show private habits"
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
            }

            SegmentedToggle {
                anchors.verticalCenter: parent.verticalCenter
                value: settingsPage.stagedShowPrivate
                onToggled: settingsPage.stagedShowPrivate = value
            }
        }

        Text {
            text: "Sync server"
            font.pixelSize: App.Theme.labelFont
            color: App.Theme.fg
        }

        Rectangle {
            width: Math.min(parent.width, 900)
            height: App.Theme.boxSize
            color: App.Theme.bg
            border.color: App.Theme.fg
            border.width: App.Theme.borderWidth

            TextInput {
                id: urlInput
                anchors.fill: parent
                anchors.margins: App.Theme.inputPadding
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                text: settingsPage.stagedUrl
                onTextChanged: settingsPage.stagedUrl = text
            }

            Text {
                anchors.fill: urlInput
                text: "http://address:5137 — blank runs offline"
                color: App.Theme.fg
                opacity: App.Theme.fadedOpacity
                font.pixelSize: urlInput.font.pixelSize
                verticalAlignment: Text.AlignVCenter
                visible: urlInput.text.length === 0 && !urlInput.activeFocus
            }
        }

        Row {
            spacing: App.Theme.buttonGap

            AppButton {
                width: App.Theme.quitButtonWidth
                height: App.Theme.quitButtonHeight
                text: "Sync now"
                disabled: !settingsPage.serverUrlReady
                onClicked: settingsPage.syncNowRequested()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: settingsPage.syncStatusText
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
                opacity: App.Theme.fadedOpacity
                visible: text.length > 0
            }
        }

        Text {
            text: "Tablet pairing"
            font.pixelSize: App.Theme.labelFont
            color: App.Theme.fg
        }

        Row {
            spacing: App.Theme.buttonGap
            visible: !settingsPage.pairingConnected

            AppButton {
                width: App.Theme.quitButtonWidth
                height: App.Theme.quitButtonHeight
                text: settingsPage.pairingStatus === "expired" ? "New code" : "Connect"
                disabled: !settingsPage.serverUrlReady || settingsPage.pairingRequestInFlight
                onClicked: settingsPage.connectRequested()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: settingsPage._pairingHintText()
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
                opacity: App.Theme.fadedOpacity
                visible: text.length > 0
            }
        }

        // The code itself: shown large, since it's read off this e-ink screen and typed into the
        // phone. The unambiguous-alphabet choice (no 0/O/1/I) is the server's; this just displays
        // it plainly.
        Text {
            visible: settingsPage.pairingStatus === "waiting"
            text: settingsPage.pairingCode
            font.pixelSize: App.Theme.scrollFont
            font.bold: true
            color: App.Theme.fg
        }

        Text {
            visible: settingsPage.pairingStatus === "waiting"
            text: "Enter this code on your phone to connect this reMarkable."
            font.pixelSize: App.Theme.labelFont
            color: App.Theme.fg
        }

        Row {
            spacing: App.Theme.buttonGap
            visible: settingsPage.pairingConnected

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Connected"
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
            }

            AppButton {
                width: App.Theme.quitButtonWidth
                height: App.Theme.quitButtonHeight
                text: "Disconnect"
                onClicked: settingsPage.disconnectRequested()
            }
        }

        // Disconnecting here drops only this device's local copy of the token — the server-side
        // session survives until it's revoked from the phone's linked-devices list.
        Text {
            visible: settingsPage.pairingConnected
            width: Math.min(parent.width, 900)
            text: "Disconnecting here signs out only this device. Revoke it for good from your phone's linked devices."
            font.pixelSize: App.Theme.dayLabelFont
            color: App.Theme.fg
            opacity: App.Theme.fadedOpacity
            wrapMode: Text.WordWrap
        }
    }

    AppButton {
        id: backButton
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: App.Theme.margin
        width: App.Theme.quitButtonWidth
        height: App.Theme.quitButtonHeight
        text: "Back"
        onClicked: settingsPage.dirty ? unsavedDialog.visible = true : settingsPage.backRequested()
    }

    AppButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: App.Theme.margin
        width: App.Theme.quitButtonWidth
        height: App.Theme.quitButtonHeight
        text: "Done"
        disabled: !settingsPage.dirty
        onClicked: settingsPage._commit()
    }

    function _commit() {
        if (settingsPage.suspendImageDirty) {
            settingsPage.applyRequested(settingsPage.staged);
        }
        if (settingsPage.showPrivateDirty) {
            settingsPage.showPrivateHabitsApplied(settingsPage.stagedShowPrivate);
        }
        if (settingsPage.urlDirty) {
            settingsPage.serverUrlApplied(settingsPage.stagedUrl.trim());
        }

        settingsPage.backRequested();
    }

    ConfirmDialog {
        id: unsavedDialog
        visible: false
        message: "Discard unsaved settings changes?"
        confirmText: "Discard"
        onConfirmed: {
            unsavedDialog.visible = false;
            settingsPage.backRequested();
        }
        onCancelled: unsavedDialog.visible = false
    }
}

import QtQuick 2.15
import QtTest 1.2
import "../src/js/ServerUrl.js" as ServerUrl

// Shared by SyncStore and PairingStore — see tst_syncstore.qml for the store-level coverage of
// the same behaviour through _serverUrl()/_endpoint(). These are the pure-function cases.
TestCase {
    name: "ServerUrl"

    function test_withDefaultSchemeAddsHttpToABareHost() {
        compare(ServerUrl.withDefaultScheme("192.168.1.50:5000"), "http://192.168.1.50:5000");
    }

    function test_withDefaultSchemeLeavesAnExplicitSchemeAlone() {
        compare(ServerUrl.withDefaultScheme("https://habits.example.test"), "https://habits.example.test");
        compare(ServerUrl.withDefaultScheme("HTTP://Habits.Example.Test"), "HTTP://Habits.Example.Test");
    }

    function test_withDefaultSchemeTrimsAndStaysEmptyWhenUnset() {
        compare(ServerUrl.withDefaultScheme("   "), "");
        compare(ServerUrl.withDefaultScheme("  http://example.test  "), "http://example.test");
        compare(ServerUrl.withDefaultScheme(undefined), "");
    }

    function test_endpointStripsTrailingSlashes() {
        compare(ServerUrl.endpoint("http://example.test", "/api/sync"), "http://example.test/api/sync");
        compare(ServerUrl.endpoint("http://example.test/", "/api/sync"), "http://example.test/api/sync");
        compare(ServerUrl.endpoint("http://example.test///", "/api/pairing/code"), "http://example.test/api/pairing/code");
    }
}

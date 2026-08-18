import QtQuick 2.15
import QtTest 1.2
import "../src/js/Ids.js" as Ids

TestCase {
    name: "Ids"

    // A client-minted id is also the backend's Guid primary key, so the RFC-4122 v4 shape is a
    // contract, not cosmetics — version nibble 4, variant nibble 8/9/a/b.
    function test_newIdIsAV4Uuid() {
        const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

        for (let i = 0; i < 200; i++) {
            const id = Ids.newId();
            verify(uuid.test(id), `not a v4 uuid: ${id}`);
        }
    }

    function test_newIdDoesNotRepeat() {
        const seen = {};
        for (let i = 0; i < 1000; i++) {
            const id = Ids.newId();
            verify(!seen[id], `duplicate id: ${id}`);
            seen[id] = true;
        }
    }
}

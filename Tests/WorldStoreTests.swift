import CoreLocation
import XCTest
@testable import PocketWorld

final class WorldStoreTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketWorldTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    @MainActor
    func testSeedsAreExplicitStableAndNearDemoAnchor() throws {
        let firstURL = temporaryURL()
        let secondURL = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: secondURL.deletingLastPathComponent())
        }
        let first = WorldStore(storageURL: firstURL)
        let second = WorldStore(storageURL: secondURL)
        XCTAssertEqual(first.treasures, second.treasures)
        XCTAssertEqual(Set(first.treasures.map(\.id)).count, first.treasures.count)
        XCTAssertTrue(first.treasures.count >= 4)
        let origin = CLLocation(latitude: WorldStore.demoCoordinate.latitude, longitude: WorldStore.demoCoordinate.longitude)
        for treasure in first.treasures {
            XCTAssertTrue(treasure.isDemo)
            XCTAssertTrue(treasure.author.contains("示例"))
            XCTAssertTrue(first.distanceLabel(for: treasure).contains("示范"))
            let location = CLLocation(latitude: treasure.latitude, longitude: treasure.longitude)
            XCTAssertLessThan(origin.distance(from: location), 250)
        }
    }

    @MainActor
    func testCreateTrimsAndRejectsBlankInput() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let count = store.treasures.count
        XCTAssertNil(store.create(title: " \n", body: "正文", kind: .letter, coordinate: WorldStore.demoCoordinate, place: "示范"))
        XCTAssertNil(store.create(title: "标题", body: "\t ", kind: .letter, coordinate: WorldStore.demoCoordinate, place: "示范"))
        XCTAssertEqual(store.treasures.count, count)
        let own = try XCTUnwrap(store.create(title: "  我的信 \n", body: " 好好吃饭 \n", kind: .letter, coordinate: WorldStore.demoCoordinate, place: " 示范点 "))
        XCTAssertEqual(own.title, "我的信")
        XCTAssertEqual(own.body, "好好吃饭")
        XCTAssertEqual(own.place, "示范点")
        XCTAssertFalse(own.isDemo)
        XCTAssertEqual(store.ownTreasures, [own])
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testAllInteractionsSurviveNewStoreInstance() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let treasure = try XCTUnwrap(store.create(title: "一颗星", body: "明天也会有好天气。", kind: .wish, coordinate: WorldStore.demoCoordinate, place: "示范点"))
        store.open(treasure)
        store.open(treasure)
        store.toggleSaved(treasure)
        store.reply(to: treasure, text: " 谢谢今天 \n")
        store.selectPet(.otter)

        let restored = WorldStore(storageURL: url)
        XCTAssertNil(restored.errorMessage)
        XCTAssertEqual(restored.ownTreasures, [treasure])
        XCTAssertEqual(restored.savedTreasures, [treasure])
        XCTAssertEqual(restored.openedIDs, [treasure.id])
        XCTAssertEqual(restored.pet, .otter)
        XCTAssertEqual(restored.replies[treasure.id.uuidString], ["谢谢今天"])
    }

    @MainActor
    func testOpenIsIdempotentAndCollectionTogglesWithoutDuplicates() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let treasure = try XCTUnwrap(store.treasures.first)
        for _ in 0..<5 { store.open(treasure) }
        XCTAssertEqual(store.openedIDs.count, 1)
        store.toggleSaved(treasure)
        XCTAssertEqual(store.savedTreasures.count, 1)
        store.toggleSaved(treasure)
        XCTAssertTrue(store.savedTreasures.isEmpty)
        store.toggleSaved(treasure)
        XCTAssertEqual(WorldStore(storageURL: url).savedIDs, [treasure.id])
        store.reply(to: treasure, text: " \n")
        XCTAssertTrue(store.replies.isEmpty)
    }

    @MainActor
    func testFailedWriteDoesNotCommitAnyInteraction() throws {
        let url = temporaryURL()
        let parent = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(storageURL: url)
        let treasure = try XCTUnwrap(store.treasures.first)
        let original = store.treasures
        // A file occupying the parent-directory path reliably blocks persistence.
        try FileManager.default.removeItem(at: parent)
        try Data("blocked".utf8).write(to: parent)

        store.open(treasure)
        store.toggleSaved(treasure)
        store.reply(to: treasure, text: "这一句不能丢")
        store.selectPet(.otter)
        XCTAssertNil(store.create(title: "新故事", body: "尚未保存", kind: .memory, coordinate: WorldStore.demoCoordinate, place: "示范点"))
        XCTAssertEqual(store.treasures, original)
        XCTAssertTrue(store.openedIDs.isEmpty)
        XCTAssertTrue(store.savedIDs.isEmpty)
        XCTAssertTrue(store.replies.isEmpty)
        XCTAssertEqual(store.pet, .bunny)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testCorruptFileIsPreservedAndCannotBeOverwritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("not valid JSON".utf8)
        try original.write(to: url)
        let store = WorldStore(storageURL: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.create(title: "新故事", body: "正文", kind: .letter, coordinate: WorldStore.demoCoordinate, place: "示范点"))
        store.open(try XCTUnwrap(store.treasures.first))
        XCTAssertTrue(store.openedIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testFutureVersionIsPreservedAndCannotBeOverwritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = WorldStore(storageURL: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["version"] = 999
        let original = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try original.write(to: url)
        let store = WorldStore(storageURL: url)
        store.selectPet(.otter)
        XCTAssertEqual(store.pet, .bunny)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}

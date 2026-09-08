import CoreLocation
import XCTest
@testable import PocketWorld

final class WorldStoreEditingTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketWorldEditingTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    @MainActor
    private func makeOwn(_ store: WorldStore, title: String = "我的奇遇") throws -> Treasure {
        try XCTUnwrap(store.create(
            title: title, body: "记下这一刻", kind: .letter,
            coordinate: WorldStore.demoCoordinate, place: "草坪"
        ))
    }

    @MainActor
    private func makeDraft(title: String = "还没有写完") -> TreasureDraft {
        TreasureDraft(
            title: title, body: "", kind: .memory,
            latitude: WorldStore.demoCoordinate.latitude,
            longitude: WorldStore.demoCoordinate.longitude, place: "草坪"
        )
    }

    @MainActor
    func testV1MigrationPreservesAllUserDataWithoutInventingOpeningDates() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = WorldStore(storageURL: url)
        let own = try makeOwn(original)
        original.open(own)
        original.toggleSaved(own)
        original.reply(to: own, text: "属于我的回应")
        original.selectPet(.otter)
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        fixture["version"] = 1
        fixture.removeValue(forKey: "openedDates")
        fixture.removeValue(forKey: "deletedDates")
        fixture.removeValue(forKey: "draft")
        let v1Data = try JSONSerialization.data(withJSONObject: fixture, options: .sortedKeys)
        try v1Data.write(to: url)

        let migrated = WorldStore(storageURL: url)
        XCTAssertNil(migrated.errorMessage)
        XCTAssertEqual(migrated.treasures, original.treasures)
        XCTAssertEqual(migrated.savedIDs, original.savedIDs)
        XCTAssertEqual(migrated.openedIDs, original.openedIDs)
        XCTAssertEqual(migrated.replies, original.replies)
        XCTAssertEqual(migrated.pet, .otter)
        XCTAssertEqual(migrated.openedTreasures, [own])
        XCTAssertTrue(migrated.openedDates.isEmpty)
        XCTAssertTrue(migrated.deletedDates.isEmpty)
        XCTAssertNil(migrated.draft)
        XCTAssertEqual(try Data(contentsOf: url), v1Data, "Reading a v1 record does not rewrite it")
        migrated.open(own)
        XCTAssertNil(migrated.openedDates[own.id], "Reopening must not invent a first-open date")

        XCTAssertTrue(migrated.saveDraft(makeDraft()))
        let upgraded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(upgraded["version"] as? Int, 2)
        let restored = WorldStore(storageURL: url)
        XCTAssertEqual(restored.treasures, original.treasures)
        XCTAssertEqual(restored.savedIDs, original.savedIDs)
        XCTAssertEqual(restored.openedIDs, original.openedIDs)
        XCTAssertEqual(restored.replies, original.replies)
        XCTAssertEqual(restored.pet, .otter)
        XCTAssertNil(restored.openedDates[own.id])
        XCTAssertEqual(restored.draft, makeDraft())
    }

    @MainActor
    func testUpdateUsesCurrentStoredIdentityAndPreservesRelatedData() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let own = try makeOwn(store)
        store.open(own)
        store.toggleSaved(own)
        store.reply(to: own, text: "先前的回应")
        let firstOpen = try XCTUnwrap(store.openedDates[own.id])
        var stale = own
        stale.latitude = 0
        stale.longitude = 0
        stale.author = "伪造作者"
        stale.createdAt = .distantPast
        let updated = try XCTUnwrap(store.update(
            stale, title: " 新标题 ", body: " 新正文\n", kind: .wish, place: " 新地点 "
        ))
        XCTAssertEqual(updated.id, own.id)
        XCTAssertEqual(updated.latitude, own.latitude)
        XCTAssertEqual(updated.longitude, own.longitude)
        XCTAssertEqual(updated.author, own.author)
        XCTAssertEqual(updated.createdAt, own.createdAt)
        XCTAssertEqual(updated.title, "新标题")
        XCTAssertEqual(updated.body, "新正文")
        XCTAssertEqual(updated.kind, .wish)
        XCTAssertEqual(updated.place, "新地点")
        XCTAssertEqual(store.treasure(id: own.id), updated)
        let restored = WorldStore(storageURL: url)
        XCTAssertEqual(restored.ownTreasures, [updated])
        XCTAssertEqual(restored.savedTreasures, [updated])
        XCTAssertEqual(restored.openedTreasures, [updated])
        XCTAssertEqual(restored.openedDates[own.id], firstOpen)
        XCTAssertEqual(restored.replies[own.id.uuidString], ["先前的回应"])
    }

    @MainActor
    func testCannotEditTrashOrRestoreDemoByForgingTheInput() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let demo = try XCTUnwrap(store.treasures.first)
        var forged = demo
        forged.isDemo = false
        forged.author = "我"
        XCTAssertNil(store.update(forged, title: "不应修改", body: "内容", kind: .wish, place: "地点"))
        XCTAssertFalse(store.moveToTrash(forged))
        XCTAssertFalse(store.restoreFromTrash(forged))
        XCTAssertEqual(store.treasure(id: demo.id), demo)
        forged.id = UUID()
        XCTAssertNil(store.update(forged, title: "不应修改", body: "内容", kind: .wish, place: "地点"))
        XCTAssertFalse(store.moveToTrash(forged))
        XCTAssertFalse(store.restoreFromTrash(forged))
        XCTAssertTrue(store.trashedTreasures.isEmpty)
    }

    @MainActor
    func testTrashHidesAllActiveQueriesAndRestoresEveryRelationship() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let own = try makeOwn(store)
        store.open(own)
        store.toggleSaved(own)
        store.reply(to: own, text: "仍在这里")
        let firstOpen = store.openedDates[own.id]
        XCTAssertTrue(store.moveToTrash(own))
        let trashed = WorldStore(storageURL: url)
        XCTAssertNil(trashed.treasure(id: own.id))
        XCTAssertFalse(trashed.activeTreasures.contains(own))
        XCTAssertTrue(trashed.ownTreasures.isEmpty)
        XCTAssertTrue(trashed.savedTreasures.isEmpty)
        XCTAssertTrue(trashed.openedTreasures.isEmpty)
        XCTAssertEqual(trashed.trashedTreasures, [own])
        XCTAssertTrue(trashed.treasures.contains(own), "Soft deletion keeps the original content")
        XCTAssertEqual(trashed.savedIDs, [own.id])
        XCTAssertEqual(trashed.openedIDs, [own.id])
        XCTAssertEqual(trashed.replies[own.id.uuidString], ["仍在这里"])
        XCTAssertNil(trashed.update(own, title: "不能改", body: "正文", kind: .letter, place: "地点"))
        trashed.toggleSaved(own)
        trashed.reply(to: own, text: "不能追加")
        trashed.open(own)
        XCTAssertEqual(trashed.savedIDs, [own.id])
        XCTAssertEqual(trashed.replies[own.id.uuidString], ["仍在这里"])
        XCTAssertTrue(trashed.restoreFromTrash(own))
        let restored = WorldStore(storageURL: url)
        XCTAssertEqual(restored.ownTreasures, [own])
        XCTAssertEqual(restored.savedTreasures, [own])
        XCTAssertEqual(restored.openedTreasures, [own])
        XCTAssertEqual(restored.openedDates[own.id], firstOpen)
        XCTAssertEqual(restored.replies[own.id.uuidString], ["仍在这里"])
        XCTAssertTrue(restored.trashedTreasures.isEmpty)
    }

    @MainActor
    func testOpeningDatesAreFirstOpenOnlyAndHistoryIsStableAcrossReload() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let first = try XCTUnwrap(store.treasures.first)
        let second = try XCTUnwrap(store.treasures.last)
        store.open(first)
        let firstDate = try XCTUnwrap(store.openedDates[first.id])
        store.open(second)
        store.open(first)
        XCTAssertEqual(store.openedDates[first.id], firstDate)
        XCTAssertEqual(store.openedDates.count, 2)
        let history = store.openedTreasures
        let restored = WorldStore(storageURL: url)
        XCTAssertEqual(restored.openedDates, store.openedDates)
        XCTAssertEqual(restored.openedTreasures, history)
        XCTAssertEqual(Set(history.map(\.id)), [first.id, second.id])
        if let secondDate = store.openedDates[second.id], secondDate > firstDate {
            XCTAssertEqual(history.first?.id, second.id)
        }
    }

    @MainActor
    func testDraftCanBeIncompleteAndPublishingClearsItInTheSameTransaction() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        var draft = makeDraft(title: "  还没想好 ")
        draft.body = "\n"
        XCTAssertTrue(store.saveDraft(draft))
        XCTAssertEqual(WorldStore(storageURL: url).draft, draft)
        XCTAssertNil(store.create(title: draft.title, body: draft.body, kind: draft.kind, coordinate: draft.coordinate, place: draft.place))
        XCTAssertEqual(store.draft, draft)
        _ = try makeOwn(store)
        XCTAssertNil(store.draft)
        XCTAssertNil(WorldStore(storageURL: url).draft)
        XCTAssertTrue(store.saveDraft(makeDraft(title: "")), "Empty unfinished text is a valid draft")
        XCTAssertTrue(store.discardDraft())
        XCTAssertNil(WorldStore(storageURL: url).draft)
    }

    @MainActor
    func testContentLimitsAndInvalidCoordinatesRejectWithoutMutatingState() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorldStore(storageURL: url)
        let own = try makeOwn(store)
        XCTAssertNil(store.create(title: String(repeating: "字", count: WorldStore.titleLimit + 1), body: "正文", kind: .letter, coordinate: WorldStore.demoCoordinate, place: "地点"))
        XCTAssertNil(store.update(own, title: "标题", body: String(repeating: "字", count: WorldStore.bodyLimit + 1), kind: .letter, place: "地点"))
        XCTAssertNil(store.update(own, title: "标题", body: "正文", kind: .letter, place: String(repeating: "字", count: WorldStore.placeLimit + 1)))
        for coordinate in [
            CLLocationCoordinate2D(latitude: 91, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 181),
            CLLocationCoordinate2D(latitude: .nan, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: .infinity)
        ] {
            XCTAssertNil(store.create(title: "标题", body: "正文", kind: .letter, coordinate: coordinate, place: "地点"))
            var draft = makeDraft()
            draft.latitude = coordinate.latitude
            draft.longitude = coordinate.longitude
            XCTAssertFalse(store.saveDraft(draft))
        }
        var overlongDraft = makeDraft()
        overlongDraft.title = String(repeating: "字", count: WorldStore.titleLimit + 1)
        XCTAssertFalse(store.saveDraft(overlongDraft))
        overlongDraft = makeDraft()
        overlongDraft.place = String(repeating: "字", count: WorldStore.placeLimit + 1)
        XCTAssertFalse(store.saveDraft(overlongDraft))
        store.reply(to: own, text: String(repeating: "字", count: WorldStore.replyLimit + 1))
        XCTAssertTrue(store.replies.isEmpty)
        XCTAssertEqual(store.ownTreasures, [own])
        XCTAssertNil(store.draft)
        XCTAssertNotNil(store.errorMessage)

        let boundary = try XCTUnwrap(store.update(
            own, title: String(repeating: "字", count: WorldStore.titleLimit),
            body: String(repeating: "字", count: WorldStore.bodyLimit), kind: .letter,
            place: String(repeating: "字", count: WorldStore.placeLimit)
        ))
        store.reply(to: boundary, text: String(repeating: "字", count: WorldStore.replyLimit))
        XCTAssertEqual(store.replies[own.id.uuidString]?.count, 1)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testFailedWritesDoNotCommitEditingTrashRestoreDraftOrOpeningDate() throws {
        let url = temporaryURL()
        let parent = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(storageURL: url)
        let active = try makeOwn(store, title: "还在地图上")
        let trashed = try makeOwn(store, title: "暂时收起来")
        XCTAssertTrue(store.moveToTrash(trashed))
        let originalDraft = makeDraft()
        XCTAssertTrue(store.saveDraft(originalDraft))
        let originalTreasures = store.treasures
        let originalDeletedDates = store.deletedDates
        try FileManager.default.removeItem(at: parent)
        try Data("blocked".utf8).write(to: parent)

        XCTAssertNil(store.update(active, title: "无法保存", body: "正文", kind: .wish, place: "地点"))
        XCTAssertFalse(store.moveToTrash(active))
        XCTAssertFalse(store.restoreFromTrash(trashed))
        XCTAssertFalse(store.saveDraft(makeDraft(title: "无法保存的新草稿")))
        XCTAssertFalse(store.discardDraft())
        XCTAssertNil(store.create(title: "无法保存", body: "正文", kind: .wish, coordinate: WorldStore.demoCoordinate, place: "地点"))
        store.open(active)
        XCTAssertEqual(store.treasures, originalTreasures)
        XCTAssertEqual(store.deletedDates, originalDeletedDates)
        XCTAssertEqual(store.draft, originalDraft)
        XCTAssertTrue(store.openedIDs.isEmpty)
        XCTAssertTrue(store.openedDates.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testMalformedV2MetadataIsPreservedAndCannotBeOverwritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = WorldStore(storageURL: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object.removeValue(forKey: "openedDates")
        let original = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try original.write(to: url)
        let store = WorldStore(storageURL: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.saveDraft(makeDraft()))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}

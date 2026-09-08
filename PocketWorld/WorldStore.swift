import CoreLocation
import Foundation
import Observation
import SwiftUI

enum TreasureKind: String, Codable, CaseIterable, Identifiable {
    case letter, wish, memory

    var id: String { rawValue }
    var title: String {
        switch self {
        case .letter: return "小纸条"
        case .wish: return "许愿星"
        case .memory: return "时光片"
        }
    }
    var symbol: String {
        switch self {
        case .letter: return "envelope.fill"
        case .wish: return "sparkles"
        case .memory: return "camera.macro"
        }
    }
    var tint: Color {
        switch self {
        case .letter: return Palette.mint
        case .wish: return Palette.lemon
        case .memory: return Palette.lilac
        }
    }
}

enum PetKind: String, Codable, CaseIterable, Identifiable {
    case bunny, otter

    var id: String { rawValue }
    var name: String { self == .bunny ? "糯糯" : "栗栗" }
    var asset: String { self == .bunny ? "PetBunny" : "PetOtter" }
    var subtitle: String { self == .bunny ? "把每一步，都走得软乎乎" : "擅长发现平凡里的小闪光" }
}

struct Treasure: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var place: String
    var latitude: Double
    var longitude: Double
    var kind: TreasureKind
    var author: String
    var isDemo: Bool
    var createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TreasureDraft: Codable, Equatable, Hashable {
    var title: String
    var body: String
    var kind: TreasureKind
    var latitude: Double
    var longitude: Double
    var place: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// All stories and interactions stay on this device. Callers supply a chosen
/// map coordinate or a demo anchor; this store never requests location access.
@MainActor
@Observable
final class WorldStore {
    var treasures: [Treasure]
    var savedIDs: Set<UUID>
    var openedIDs: Set<UUID>
    var pet: PetKind
    var errorMessage: String?
    var replies: [String: [String]]
    private(set) var openedDates: [UUID: Date]
    private(set) var deletedDates: [UUID: Date]
    private(set) var draft: TreasureDraft?

    static let demoCoordinate = CLLocationCoordinate2D(latitude: -33.9173, longitude: 151.2313)
    static let titleLimit = 60
    static let bodyLimit = 2_000
    static let replyLimit = 300
    static let placeLimit = 80

    @ObservationIgnored private let storageURL: URL
    @ObservationIgnored private var writeBlockedReason: String?

    private struct State: Codable {
        var version = 2
        var treasures: [Treasure]
        var savedIDs: Set<UUID>
        var openedIDs: Set<UUID>
        var pet: PetKind
        var replies: [String: [String]]
        var openedDates: [UUID: Date]
        var deletedDates: [UUID: Date]
        var draft: TreasureDraft?

        private enum CodingKeys: String, CodingKey {
            case version, treasures, savedIDs, openedIDs, pet, replies
            case openedDates, deletedDates, draft
        }

        init(
            treasures: [Treasure], savedIDs: Set<UUID>, openedIDs: Set<UUID>,
            pet: PetKind, replies: [String: [String]], openedDates: [UUID: Date],
            deletedDates: [UUID: Date], draft: TreasureDraft?
        ) {
            self.treasures = treasures
            self.savedIDs = savedIDs
            self.openedIDs = openedIDs
            self.pet = pet
            self.replies = replies
            self.openedDates = openedDates
            self.deletedDates = deletedDates
            self.draft = draft
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let sourceVersion = try container.decode(Int.self, forKey: .version)
            treasures = try container.decode([Treasure].self, forKey: .treasures)
            savedIDs = try container.decode(Set<UUID>.self, forKey: .savedIDs)
            openedIDs = try container.decode(Set<UUID>.self, forKey: .openedIDs)
            pet = try container.decode(PetKind.self, forKey: .pet)
            replies = try container.decode([String: [String]].self, forKey: .replies)
            if sourceVersion == 1 {
                // Older records have no opening times. Keep that information unknown.
                openedDates = [:]
                deletedDates = [:]
                draft = nil
            } else {
                openedDates = try container.decode([UUID: Date].self, forKey: .openedDates)
                deletedDates = try container.decode([UUID: Date].self, forKey: .deletedDates)
                draft = try container.decodeIfPresent(TreasureDraft.self, forKey: .draft)
            }
        }
    }

    private struct VersionHeader: Decodable {
        var version: Int
    }

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("PocketWorld", isDirectory: true)
            .appendingPathComponent("world-state.json")
        treasures = Self.demoTreasures
        savedIDs = []
        openedIDs = []
        pet = .bunny
        replies = [:]
        openedDates = [:]
        deletedDates = [:]
        draft = nil

        if FileManager.default.fileExists(atPath: self.storageURL.path) {
            do {
                let data = try Data(contentsOf: self.storageURL)
                let decoder = JSONDecoder()
                let version = try decoder.decode(VersionHeader.self, from: data).version
                guard version == 1 || version == 2 else {
                    let reason = "这份记录的版本暂不受支持。为保护原文件，暂时不能保存新操作。"
                    writeBlockedReason = reason
                    errorMessage = reason
                    return
                }
                let state = try decoder.decode(State.self, from: data)
                guard Set(state.treasures.map(\.id)).count == state.treasures.count,
                      state.treasures.allSatisfy({ Self.validCoordinate($0.coordinate) }),
                      state.draft.map({ Self.validCoordinate($0.coordinate) }) ?? true else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                restore(state)
                let validIDs = Set(treasures.map(\.id))
                savedIDs.formIntersection(validIDs)
                openedIDs.formIntersection(validIDs)
                replies = replies.filter { key, _ in
                    UUID(uuidString: key).map(validIDs.contains) ?? false
                }
                openedDates = openedDates.filter { openedIDs.contains($0.key) }
                let ownIDs = Set(treasures.filter { !$0.isDemo }.map(\.id))
                deletedDates = deletedDates.filter { ownIDs.contains($0.key) }
                // Migration happens in memory; the next successful transaction writes v2.
                // Merely opening the app never replaces a valid v1 file.
            } catch {
                let reason = "本机记录暂时无法读取，已显示示例内容。为保护原文件，暂时不能保存新操作。"
                writeBlockedReason = reason
                errorMessage = reason
            }
        } else {
            _ = persist(snapshot)
        }
    }

    var activeTreasures: [Treasure] {
        treasures.filter { deletedDates[$0.id] == nil }.sorted(by: Self.newestFirst)
    }
    var savedTreasures: [Treasure] { activeTreasures.filter { savedIDs.contains($0.id) } }
    var ownTreasures: [Treasure] { activeTreasures.filter { !$0.isDemo } }
    var trashedTreasures: [Treasure] {
        treasures.filter { deletedDates[$0.id] != nil }.sorted {
            let left = deletedDates[$0.id] ?? .distantPast
            let right = deletedDates[$1.id] ?? .distantPast
            return left == right ? Self.newestFirst($0, $1) : left > right
        }
    }
    var openedTreasures: [Treasure] {
        activeTreasures.filter { openedIDs.contains($0.id) }.sorted {
            switch (openedDates[$0.id], openedDates[$1.id]) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return Self.newestFirst($0, $1)
            }
        }
    }

    func treasure(id: UUID) -> Treasure? {
        treasures.first { $0.id == id && deletedDates[id] == nil }
    }

    func open(_ treasure: Treasure) {
        guard contains(treasure), !openedIDs.contains(treasure.id) else { return }
        var next = snapshot
        next.openedIDs.insert(treasure.id)
        next.openedDates[treasure.id] = Date()
        commit(next)
    }

    func toggleSaved(_ treasure: Treasure) {
        guard contains(treasure) else { return }
        var next = snapshot
        if next.savedIDs.contains(treasure.id) {
            next.savedIDs.remove(treasure.id)
        } else {
            next.savedIDs.insert(treasure.id)
        }
        commit(next)
    }

    @discardableResult
    func create(
        title: String, body: String, kind: TreasureKind,
        coordinate: CLLocationCoordinate2D, place: String
    ) -> Treasure? {
        guard let content = validatedContent(title: title, body: body),
              validateCoordinate(coordinate) else { return nil }
        let place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validatePlace(place) else { return nil }
        let treasure = Treasure(
            id: UUID(), title: content.title, body: content.body,
            place: place.isEmpty ? "地图上的小角落" : place,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            kind: kind, author: "我", isDemo: false, createdAt: Date()
        )
        var next = snapshot
        next.treasures.insert(treasure, at: 0)
        next.draft = nil
        guard commit(next) else { return nil }
        return treasure
    }

    @discardableResult
    func update(
        _ treasure: Treasure, title: String, body: String,
        kind: TreasureKind, place: String
    ) -> Treasure? {
        guard let current = editableTreasure(id: treasure.id),
              let content = validatedContent(title: title, body: body) else { return nil }
        var updated = current
        updated.title = content.title
        updated.body = content.body
        updated.kind = kind
        let place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validatePlace(place) else { return nil }
        updated.place = place.isEmpty ? current.place : place
        var next = snapshot
        guard let index = next.treasures.firstIndex(where: { $0.id == current.id }) else { return nil }
        next.treasures[index] = updated
        guard commit(next) else { return nil }
        return updated
    }

    @discardableResult
    func moveToTrash(_ treasure: Treasure) -> Bool {
        guard editableTreasure(id: treasure.id) != nil else { return false }
        var next = snapshot
        next.deletedDates[treasure.id] = Date()
        return commit(next)
    }

    @discardableResult
    func restoreFromTrash(_ treasure: Treasure) -> Bool {
        guard let current = treasures.first(where: { $0.id == treasure.id }), !current.isDemo,
              deletedDates[current.id] != nil else {
            errorMessage = "这条奇遇不在你的回收站里。"
            return false
        }
        var next = snapshot
        next.deletedDates.removeValue(forKey: current.id)
        return commit(next)
    }

    @discardableResult
    func saveDraft(_ draft: TreasureDraft) -> Bool {
        guard draft.title.count <= Self.titleLimit, draft.body.count <= Self.bodyLimit else {
            errorMessage = "草稿标题最多 \(Self.titleLimit) 字，正文最多 \(Self.bodyLimit) 字。"
            return false
        }
        guard validateCoordinate(draft.coordinate), validatePlace(draft.place) else { return false }
        var next = snapshot
        // Preserve unfinished text, including spaces, exactly as it was typed.
        next.draft = draft
        return commit(next)
    }

    @discardableResult
    func discardDraft() -> Bool {
        var next = snapshot
        next.draft = nil
        return commit(next)
    }

    func reply(to treasure: Treasure, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contains(treasure), !text.isEmpty else { return }
        guard text.count <= Self.replyLimit else {
            errorMessage = "回应最多写 \(Self.replyLimit) 字。"
            return
        }
        var next = snapshot
        next.replies[treasure.id.uuidString, default: []].append(text)
        commit(next)
    }

    func selectPet(_ pet: PetKind) {
        guard self.pet != pet else { return }
        var next = snapshot
        next.pet = pet
        commit(next)
    }

    func distanceLabel(for treasure: Treasure) -> String {
        guard Self.validCoordinate(treasure.coordinate) else { return "示范距离 · 暂不可用" }
        let origin = CLLocation(latitude: Self.demoCoordinate.latitude, longitude: Self.demoCoordinate.longitude)
        let destination = CLLocation(latitude: treasure.latitude, longitude: treasure.longitude)
        let meters = max(0, Int((origin.distance(from: destination) / 5).rounded()) * 5)
        if meters >= 1_000 {
            return String(format: "示范距离 · %.1f km", Double(meters) / 1_000)
        }
        return "示范距离 · \(meters) m"
    }

    private var snapshot: State {
        State(
            treasures: treasures, savedIDs: savedIDs, openedIDs: openedIDs,
            pet: pet, replies: replies, openedDates: openedDates,
            deletedDates: deletedDates, draft: draft
        )
    }

    private func contains(_ treasure: Treasure) -> Bool {
        self.treasure(id: treasure.id) != nil
    }

    private func editableTreasure(id: UUID) -> Treasure? {
        guard let current = treasure(id: id), !current.isDemo else {
            errorMessage = "只能修改自己留下、且没有放入回收站的奇遇。"
            return nil
        }
        return current
    }

    private func validatedContent(title: String, body: String) -> (title: String, body: String)? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else {
            errorMessage = "写下标题和一点心里话，再放进小世界吧。"
            return nil
        }
        guard title.count <= Self.titleLimit, body.count <= Self.bodyLimit else {
            errorMessage = "标题最多 \(Self.titleLimit) 字，正文最多 \(Self.bodyLimit) 字。"
            return nil
        }
        return (title, body)
    }

    private static func validCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite && CLLocationCoordinate2DIsValid(coordinate)
    }

    private func validatePlace(_ place: String) -> Bool {
        guard place.count <= Self.placeLimit else {
            errorMessage = "地点名称最多写 \(Self.placeLimit) 字。"
            return false
        }
        return true
    }

    private func validateCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard Self.validCoordinate(coordinate) else {
            errorMessage = "这个地点暂时不可用，请重新选择。"
            return false
        }
        return true
    }

    private static func newestFirst(_ left: Treasure, _ right: Treasure) -> Bool {
        left.createdAt == right.createdAt ? left.id.uuidString < right.id.uuidString : left.createdAt > right.createdAt
    }

    @discardableResult
    private func commit(_ state: State) -> Bool {
        guard persist(state) else { return false }
        restore(state)
        return true
    }

    private func restore(_ state: State) {
        treasures = state.treasures
        savedIDs = state.savedIDs
        openedIDs = state.openedIDs
        pet = state.pet
        replies = state.replies
        openedDates = state.openedDates
        deletedDates = state.deletedDates
        draft = state.draft
    }

    private func persist(_ state: State) -> Bool {
        if let writeBlockedReason {
            errorMessage = writeBlockedReason
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: storageURL, options: .atomic)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "还没能存进口袋，刚才的操作没有保存。请检查设备空间后再试一次。"
            return false
        }
    }

    private static let demoTreasures: [Treasure] = [
        Treasure(
            id: UUID(uuidString: "A23121A1-606B-4010-B845-000000000001")!,
            title: "给路过的你",
            body: "如果今天有一点累，就在这里停一下吧。\n\n不必把每一天都过得很厉害。好好吃了午饭，给喜欢的人回了消息，或者终于走出房门，都算数。\n\n这片草坪没有截止日期。你也可以慢一点，再慢一点。",
            place: "Library Lawn · 示范点", latitude: -33.9170, longitude: 151.2321,
            kind: .letter, author: "小世界示例", isDemo: true, createdAt: Date(timeIntervalSince1970: 1_780_000_000)
        ),
        Treasure(
            id: UUID(uuidString: "A23121A1-606B-4010-B845-000000000002")!,
            title: "长椅上的好消息",
            body: "想象一个平常的下午，你坐在这张长椅上，收到一句等了很久的「可以呀」。\n\n那一刻，风还是同一阵风，路过的人也没有变，但整个世界突然亮了一小格。\n\n愿你也早一点，收到自己的好消息。",
            place: "Quadrangle · 示范点", latitude: -33.9176, longitude: 151.2309,
            kind: .wish, author: "小世界示例", isDemo: true, createdAt: Date(timeIntervalSince1970: 1_779_980_000)
        ),
        Treasure(
            id: UUID(uuidString: "A23121A1-606B-4010-B845-000000000003")!,
            title: "今天的风很温柔",
            body: "记一件很小的事：午后的树影落在笔记本上，像有人悄悄加了一层书签。\n\n原来值得记住的，不一定是什么大日子。也可以是没迟到的一堂课，一杯刚好温热的咖啡，和一阵没有催你赶路的风。",
            place: "Main Walkway · 示范点", latitude: -33.9169, longitude: 151.2308,
            kind: .memory, author: "小世界示例", isDemo: true, createdAt: Date(timeIntervalSince1970: 1_779_950_000)
        ),
        Treasure(
            id: UUID(uuidString: "A23121A1-606B-4010-B845-000000000004")!,
            title: "给未来的一张便签",
            body: "希望下次经过这里的时候，你正在为某件喜欢的事忙碌。\n\n如果还没找到，也没关系。先把今天遇见的一点点好收好：抬头的云、路边的新叶、有人替你留住的门。\n\n小小的喜欢，会慢慢带你去远一点的地方。",
            place: "Scientia Lawn · 示范点", latitude: -33.9174, longitude: 151.2332,
            kind: .wish, author: "小世界示例", isDemo: true, createdAt: Date(timeIntervalSince1970: 1_779_920_000)
        )
    ]
}

import SwiftUI

struct PocketView: View {
    @Bindable var store: WorldStore
    let onSelect: (Treasure) -> Void
    let onExplore: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var collection: PocketCollection = .saved
    @State private var query = ""
    @State private var showTrash = false
    @State private var restoreMessage: String?
    @State private var restoreFailed = false
    @FocusState private var searchFocused: Bool

    private enum PocketCollection: String, CaseIterable, Identifiable {
        case saved = "收藏"
        case own = "我留下的"
        case opened = "打开过"
        var id: String { rawValue }
    }

    private var items: [Treasure] {
        switch collection {
        case .saved: return store.savedTreasures
        case .own: return store.ownTreasures
        case .opened: return store.openedTreasures
        }
    }

    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredItems: [Treasure] {
        guard !searchTerm.isEmpty else { return items }
        return items.filter {
            $0.title.localizedStandardContains(searchTerm) || $0.place.localizedStandardContains(searchTerm)
        }
    }

    private var columns: [GridItem] {
        // Longer titles can grow vertically; larger text gets an entire row.
        dynamicTypeSize >= .xxxLarge
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 145), alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                passport
                collections
                searchField
                if filteredItems.isEmpty {
                    if !searchTerm.isEmpty { emptySearchState }
                    else { emptyCollectionState }
                } else {
                    if !searchTerm.isEmpty {
                        Text("找到 \(filteredItems.count) 件小美好")
                            .font(.caption).foregroundStyle(Palette.secondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(filteredItems) { treasure in
                            Button {
                                searchFocused = false
                                onSelect(treasure)
                            } label: { itemCard(treasure) }
                                .buttonStyle(PressStyle())
                                .accessibilityElement(children: .combine)
                                .accessibilityHint("查看这份奇遇")
                        }
                    }
                }
                Label("这一口袋的美好，只保存在你的设备里", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity).padding(.bottom, 16)
            }
            .padding(.horizontal, 24).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.cream)
        .sheet(isPresented: $showTrash) { trashSheet }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(text: "LITTLE THINGS, BIG FEELINGS")
                Text("把喜欢的，\n装进口袋。")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .lineSpacing(3).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                searchFocused = false
                restoreMessage = nil
                restoreFailed = false
                showTrash = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.teal)
                    .frame(width: 46, height: 46)
                    .background(.white, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("回收站")
            .accessibilityValue("\(store.trashedTreasures.count) 件内容")
            .accessibilityHint("查看并恢复移入回收站的内容")
        }
    }

    private var passport: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Label("我的奇遇护照", systemImage: "sparkles")
                    .font(.subheadline.weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(store.openedTreasures.count))
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    Text("次小小的相遇").font(.caption.weight(.medium))
                }
                Text("和\(store.pet.name)，慢慢收集这个世界。")
                    .font(.caption).foregroundStyle(Palette.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(store.pet.asset).resizable().scaledToFit()
                    .frame(width: dynamicTypeSize >= .xxxLarge ? 78 : 112, height: 148)
                    .rotationEffect(.degrees(-8))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Palette.ink).padding(23)
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                Palette.mint
                Circle().fill(.white.opacity(0.32)).frame(width: 150, height: 150)
                    .offset(x: 44, y: -30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var collections: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PocketCollection.allCases) { option in
                    Button {
                        searchFocused = false
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            collection = option
                        }
                    } label: {
                        Text("\(option.rawValue)  \(count(for: option))")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 17).padding(.vertical, 12)
                            .foregroundStyle(collection == option ? Color.white : Palette.secondary)
                            .background(collection == option ? Palette.ink : Color.white, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(collection == option ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func count(for collection: PocketCollection) -> Int {
        switch collection {
        case .saved: return store.savedTreasures.count
        case .own: return store.ownTreasures.count
        case .opened: return store.openedTreasures.count
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                .accessibilityHidden(true)
            TextField("搜索标题或地点", text: $query)
                .font(.subheadline).foregroundStyle(Palette.ink)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("在\(collection.rawValue)中搜索标题或地点")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptySearchState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .light)).foregroundStyle(Palette.teal)
                .padding(18).background(Palette.mint, in: Circle())
                .accessibilityHidden(true)
            Text("这次还没找到")
                .font(.headline).foregroundStyle(Palette.ink)
            Text("在「\(collection.rawValue)」里没有匹配的标题或地点。试试短一点的关键词，或换个集合看看。")
                .font(.subheadline).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            Button("清除搜索") { query = ""; searchFocused = false }
                .font(.subheadline.weight(.bold)).foregroundStyle(Palette.teal)
                .frame(minHeight: 44)
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
    }

    private var emptyCollectionState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Palette.lemon.opacity(0.5)).frame(width: 122, height: 122)
                Image("StarCapsule").resizable().scaledToFit().frame(width: 117, height: 132)
                    .rotationEffect(.degrees(12))
            }.accessibilityHidden(true)
            Text(emptyTitle).font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(emptyDescription).font(.subheadline).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            Button(action: onExplore) {
                Label("出去逛逛", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.bold)).padding(.horizontal, 24).padding(.vertical, 14)
                    .foregroundStyle(.white).background(Palette.teal, in: Capsule())
            }.buttonStyle(PressStyle()).padding(.top, 4)
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
    }

    private var emptyTitle: String {
        switch collection {
        case .saved: return "口袋空空，好奇心满满"
        case .own: return "给下一个路过的人，一点惊喜"
        case .opened: return "第一次奇遇，正在等你"
        }
    }

    private var emptyDescription: String {
        switch collection {
        case .saved: return "拆开一份小惊喜，点一下收藏，就能在这里再次找到。"
        case .own: return "点下方的 +，把一句话藏在地图上。内容会先保存在这台设备。"
        case .opened: return "到地图上打开一份奇遇，这里会为你留下足迹。"
        }
    }

    private func itemCard(_ treasure: Treasure) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(treasure.kind.tint.opacity(0.65))
                if treasure.kind == .wish {
                    Image("StarCapsule").resizable().scaledToFit().padding(12)
                } else {
                    Image(systemName: treasure.kind.symbol).font(.system(size: 42, weight: .light))
                        .foregroundStyle(Palette.teal).rotationEffect(.degrees(-10))
                }
            }.frame(height: 125).accessibilityHidden(true)
            Text(treasure.title).font(.subheadline.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Label(treasure.place, systemImage: "mappin")
                .font(.caption).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if collection == .opened {
                Text(openedLabel(for: treasure))
                    .font(.caption).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(treasure.isDemo ? "示范故事" : "我留下的 · 本地")
                .font(.caption.weight(.medium)).foregroundStyle(Palette.teal)
        }
        .foregroundStyle(Palette.ink).padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
    }

    private func openedLabel(for treasure: Treasure) -> String {
        guard let date = store.openedDates[treasure.id] else { return "之前打开" }
        return "打开于 \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var trashSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("暂时收起来，也能再找回", systemImage: "leaf")
                            .font(.headline).foregroundStyle(Palette.ink)
                        Text("移入回收站的内容会从地图和口袋中隐藏。恢复后会回到原处，收藏和打开记录也会保留。回收站只在本机保存。")
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.mint, in: RoundedRectangle(cornerRadius: 24))

                    if let restoreMessage {
                        Label(restoreMessage, systemImage: restoreFailed ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(restoreFailed ? Palette.ink : Palette.teal)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(restoreFailed ? Palette.coral.opacity(0.18) : Color.white,
                                        in: RoundedRectangle(cornerRadius: 18))
                    }

                    if store.trashedTreasures.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 34, weight: .light)).foregroundStyle(Palette.teal)
                                .accessibilityHidden(true)
                            Text("回收站空空的").font(.headline).foregroundStyle(Palette.ink)
                            Text("在自己留下的奇遇详情中，可以把内容暂时收进这里。")
                                .font(.subheadline).foregroundStyle(Palette.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(28).frame(maxWidth: .infinity)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    } else {
                        Text("\(store.trashedTreasures.count) 件暂存的奇遇")
                            .font(.caption).foregroundStyle(Palette.secondary)
                        ForEach(store.trashedTreasures) { treasure in trashCard(treasure) }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden).background(Palette.cream)
            .navigationTitle("回收站").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showTrash = false }.foregroundStyle(Palette.teal)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func trashCard(_ treasure: Treasure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(treasure.kind.title, systemImage: treasure.kind.symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.teal)
            Text(treasure.title).font(.headline).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Label(treasure.place, systemImage: "mappin")
                .font(.subheadline).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let date = store.deletedDates[treasure.id] {
                Text("移入于 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Button {
                let restored = store.restoreFromTrash(treasure)
                restoreFailed = !restored
                restoreMessage = restored
                    ? "已恢复「\(treasure.title)」，可以在地图和「我留下的」中找到它。"
                    : (store.errorMessage ?? "这份奇遇暂时没能恢复，请再试一次。")
            } label: {
                Label("恢复这份奇遇", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(.white).background(Palette.teal, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("恢复\(treasure.title)")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}

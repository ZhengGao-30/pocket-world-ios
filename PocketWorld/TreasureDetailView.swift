import SwiftUI

struct TreasureDetailView: View {
    private let initialTreasure: Treasure
    let store: WorldStore
    let location: WorldLocation
    let onShowOnMap: () -> Void

    init(treasure: Treasure, store: WorldStore, location: WorldLocation, onShowOnMap: @escaping () -> Void) {
        initialTreasure = treasure
        self.store = store
        self.location = location
        self.onShowOnMap = onShowOnMap
    }

    private var treasure: Treasure { store.treasure(id: initialTreasure.id) ?? initialTreasure }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var simulatedNearby = false
    @State private var editingTreasure: Treasure?
    @State private var confirmTrash = false
    @State private var confirmClose = false
    @State private var closeToMap = false
    @State private var replyText = ""
    @State private var replySaved = false
    @Namespace private var capsuleMotion
    @GestureState private var lift: CGFloat = 0
    @FocusState private var replyFocused: Bool

    private var isOpened: Bool { store.openedIDs.contains(treasure.id) }
    private var isSaved: Bool { store.savedIDs.contains(treasure.id) }
    private var canOpen: Bool {
        !treasure.isDemo || (simulatedNearby && !location.isUsingDeviceLocation) || location.canOpen(treasure) || isOpened
    }
    private var hasUnsavedReply: Bool { !replyText.isEmpty }
    private var canReply: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyText.count <= WorldStore.replyLimit
    }
    private var savedReplies: [String] { store.replies[treasure.id.uuidString] ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    locationLabel
                    if isOpened {
                        openedStory
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        sealedStory
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.cream)
            .navigationTitle(isOpened ? "一份小惊喜" : "发现小惊喜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !treasure.isDemo {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("编辑内容", systemImage: "pencil") { editingTreasure = treasure }
                            Button("移到回收站", systemImage: "trash", role: .destructive) { confirmTrash = true }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 21)).foregroundStyle(Palette.teal)
                        }.accessibilityLabel("管理我的小惊喜")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { replyFocused = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if hasUnsavedReply { closeToMap = false; replyFocused = false; confirmClose = true }
                        else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.8), in: Circle())
                    }
                    .accessibilityLabel("关闭详情")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isOpened && !replyFocused { collectionButton }
            }
        }
        .tint(Palette.teal)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .sheet(item: $editingTreasure) { item in
            ComposeTreasureView(store: store, coordinate: item.coordinate, editing: item) { _ in }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .confirmationDialog("把这份小惊喜移到回收站？", isPresented: $confirmTrash, titleVisibility: .visible) {
            if hasUnsavedReply {
                Button("收好回应，再移到回收站") {
                    if saveReplyIfPossible(), store.moveToTrash(treasure) { dismiss() }
                }.disabled(!canReply)
            }
            Button(hasUnsavedReply ? "放弃未保存回应，移到回收站" : "移到回收站", role: .destructive) {
                if store.moveToTrash(treasure) { dismiss() }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("它会从地图和口袋里隐藏。内容与回应仍然保留，可以在口袋的回收站恢复。")
        }
        .interactiveDismissDisabled(hasUnsavedReply)
        .confirmationDialog("这句话还没有收好", isPresented: $confirmClose, titleVisibility: .visible) {
            Button(closeToMap ? "收好回应，去看地图" : "收好并关闭") { if saveReplyIfPossible() { finishClose() } }.disabled(!canReply)
            Button(closeToMap ? "放弃未保存回应，去看地图" : "放弃这句话并关闭", role: .destructive) { finishClose() }
            Button("继续写", role: .cancel) { }
        } message: { Text("保存后可以在这份小惊喜里再次看到。") }
        .sensoryFeedback(.success, trigger: isOpened)
        .sensoryFeedback(.selection, trigger: isSaved)
        .alert("还差一点点", isPresented: Binding(
            get: { store.errorMessage != nil && editingTreasure == nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "请稍后再试一次。")
        }
    }

    private var locationLabel: some View {
        VStack(spacing: 8) {
            Label(treasure.place, systemImage: "mappin.and.ellipse")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            Text(treasure.isDemo ? "示例内容 · \(location.distanceLabel(for: treasure))" : "我的小惊喜 · \(location.distanceLabel(for: treasure))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
            if location.isUsingDeviceLocation && (!location.hasFreshSnapshot || (location.snapshot?.horizontalAccuracy ?? .infinity) > WorldLocationPolicy.maximumAccuracy) {
                Text(location.statusText).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                if hasUnsavedReply { closeToMap = true; replyFocused = false; confirmClose = true }
                else { onShowOnMap() }
            } label: {
                Label("在地图中查看", systemImage: "map")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.teal)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white, in: Capsule())
            }.buttonStyle(PressStyle())
        }
        .padding(.top, 8)
    }

    private var sealedStory: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(canOpen ? "一份温柔，等你打开" : "这里藏着一份温柔")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(canOpen ? "轻轻向上滑，把小惊喜打开" : (location.isUsingDeviceLocation ? "走到附近 100 米内，或先用示范体验" : "先模拟走近，再把它带进今天"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
            }

            capsule

            if canOpen {
                VStack(spacing: 10) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.teal)
                    Button(action: openTreasure) {
                        Label("打开小惊喜", systemImage: "sparkles")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .foregroundStyle(.white)
                            .background(Palette.teal, in: RoundedRectangle(cornerRadius: 20))
                    }
                    Text("上滑松手即可打开，也可以点按按钮")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
                            if location.isUsingDeviceLocation { location.useDemo() }
                            simulatedNearby = true
                        }
                    } label: {
                        Label(location.isUsingDeviceLocation ? "用示范模式体验" : "模拟走近", systemImage: "figure.walk")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .foregroundStyle(.white)
                            .background(Palette.teal, in: RoundedRectangle(cornerRadius: 20))
                    }
                    Text(location.isUsingDeviceLocation ? "漫游位置用于计算距离；示范体验会切回校园起点。" : "示范模式使用校园起点，不需要定位权限。")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Label(treasure.kind.title, systemImage: treasure.kind.symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(treasure.kind.tint, in: Capsule())
                .padding(.top, 2)
        }
        .padding(.top, 12)
    }

    private var capsule: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.lemon.opacity(0.55), Palette.cream.opacity(0)], center: .center, startRadius: 20, endRadius: 145))
                .frame(width: 290, height: 290)
            Ellipse()
                .fill(Palette.teal.opacity(0.09))
                .frame(width: 135, height: 18)
                .blur(radius: 7)
                .offset(y: 105)
                .scaleEffect(1 + lift / 250)
            Image(systemName: "sparkle")
                .foregroundStyle(Palette.coral.opacity(0.75))
                .font(.system(size: 22))
                .offset(x: -111, y: -60)
            Image(systemName: "sparkle")
                .foregroundStyle(Palette.teal.opacity(0.55))
                .font(.system(size: 14))
                .offset(x: 112, y: 26)
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.coral)
                ForEach(0..<3) { line in
                    Capsule()
                        .fill(Palette.mint)
                        .frame(width: line == 2 ? 47 : 74, height: 4)
                }
            }
            .padding(20)
            .frame(width: 118, height: 125, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .shadow(color: Palette.teal.opacity(0.1), radius: 10, y: 5)
            .rotationEffect(.degrees(-6))
            .offset(y: 40)
            .opacity(min(1, Double(-lift / 65)))
            .accessibilityHidden(true)
            Image("StarCapsule")
                .resizable()
                .scaledToFit()
                .frame(width: 245, height: 245)
                .matchedGeometryEffect(id: "capsule", in: capsuleMotion)
                .rotationEffect(.degrees(Double(lift / 20)))
                .offset(y: lift)
                .shadow(color: Palette.teal.opacity(0.1), radius: 18, y: 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($lift) { value, state, _ in
                    guard canOpen else { return }
                    state = min(0, max(-115, value.translation.height))
                }
                .onEnded { value in
                    if canOpen && value.translation.height < -80 { openTreasure() }
                }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65), value: lift)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(canOpen ? "星星胶囊，可以打开" : "星星胶囊，走近或用示范模式体验")
        .accessibilityHint("使用下方按钮体验打开")
    }

    private var openedStory: some View {
        VStack(spacing: 22) {
            HStack(spacing: 10) {
                Image("StarCapsule")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
                    .matchedGeometryEffect(id: "capsule", in: capsuleMotion)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("一点善意，已经送达")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text("愿它让你的今天，轻一点点。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 23))

            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    Label(treasure.kind.title, systemImage: treasure.kind.symbol)
                        .foregroundStyle(Palette.teal)
                    Spacer()
                    Text(treasure.isDemo ? "示例故事" : "我的记录")
                        .foregroundStyle(Palette.secondary)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))

                Text(treasure.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(treasure.body)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .lineSpacing(9)
                    .foregroundStyle(Palette.ink.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack {
                    Spacer()
                    Text("— \(treasure.author)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(25)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 27))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.lemon.opacity(0.8))
                    .frame(width: 50, height: 6)
                    .offset(y: -3)
            }

            replySection
        }
    }

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("给这一刻，留句话")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("只记在这台设备，不会发送给他人。")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Palette.secondary)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("此刻的心情是……", text: $replyText, axis: .vertical)
                    .font(.system(size: 14, design: .rounded))
                    .lineLimit(1...4)
                    .focused($replyFocused)
                    .submitLabel(.done)
                    .onSubmit(saveReply)
                    .onChange(of: replyText) { _, _ in replySaved = false }
                    .accessibilityLabel("写下我的回应")
                Button(action: saveReply) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Palette.teal, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canReply)
                .opacity(canReply ? 1 : 0.4)
                .accessibilityLabel("收好这句话")
            }
            .padding(13)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))

            Text("\(replyText.count) / \(WorldStore.replyLimit)")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(replyText.count > WorldStore.replyLimit ? Palette.coral : Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if replySaved {
                Label("这句话已经收好", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.teal)
            }
            ForEach(Array(savedReplies.enumerated()), id: \.offset) { _, reply in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening")
                        .foregroundStyle(Palette.teal)
                    Text(reply)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 13, design: .rounded))
                .padding(14)
                .background(Palette.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var collectionButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.58)) {
                store.toggleSaved(treasure)
            }
        } label: {
            HStack(spacing: 9) {
                if reduceMotion {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                } else {
                    Image(systemName: isSaved ? "heart.fill" : "heart").symbolEffect(.bounce, value: isSaved)
                }
                Text(isSaved ? "已收进口袋" : "收进口袋")
                if isSaved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(isSaved ? Palette.teal : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(isSaved ? Palette.mint : Palette.teal, in: RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityHint(isSaved ? "再次点按可从口袋移出" : "保存后可以在口袋里再次阅读")
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Palette.cream.opacity(0.97))
    }

    private func finishClose() {
        if closeToMap { onShowOnMap() }
        else { dismiss() }
    }

    private func openTreasure() {
        guard canOpen else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)) {
            store.open(treasure)
        }
    }

    private func saveReply() { _ = saveReplyIfPossible() }

    @discardableResult
    private func saveReplyIfPossible() -> Bool {
        guard canReply else { return false }
        let oldCount = savedReplies.count
        store.reply(to: treasure, text: replyText)
        if savedReplies.count > oldCount {
            replyText = ""
            replyFocused = false
            replySaved = true
            return true
        }
        return false
    }
}

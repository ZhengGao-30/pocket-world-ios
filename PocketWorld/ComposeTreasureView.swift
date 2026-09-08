import CoreLocation
import MapKit
import SwiftUI

struct ComposeTreasureView: View {
    let store: WorldStore
    let coordinate: CLLocationCoordinate2D
    let editing: Treasure?
    let onCreated: (Treasure) -> Void
    @State private var isResumingDraft: Bool
    @State private var initialDraft: TreasureDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var title: String
    @State private var message: String
    @State private var place: String
    @State private var kind: TreasureKind
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var camera: MapCameraPosition
    @State private var visibleMapCamera: MapCamera?
    @State private var mapReloadID = UUID()
    @State private var isSaving = false
    @State private var didFinish = false
    @State private var showExitOptions = false
    @FocusState private var focusedField: Field?

    init(store: WorldStore, coordinate: CLLocationCoordinate2D, place: String = "地图选点",
         editing: Treasure? = nil, onCreated: @escaping (Treasure) -> Void) {
        self.store = store
        self.coordinate = coordinate
        self.editing = editing
        self.onCreated = onCreated
        let draft = editing == nil ? store.draft : nil
        _isResumingDraft = State(initialValue: draft != nil)
        let center = editing?.coordinate ?? draft?.coordinate ?? coordinate
        _initialDraft = State(initialValue: TreasureDraft(title: editing?.title ?? draft?.title ?? "", body: editing?.body ?? draft?.body ?? "",
                                     kind: editing?.kind ?? draft?.kind ?? .letter, latitude: center.latitude,
                                     longitude: center.longitude, place: editing?.place ?? draft?.place ?? place))
        _title = State(initialValue: editing?.title ?? draft?.title ?? "")
        _message = State(initialValue: editing?.body ?? draft?.body ?? "")
        _place = State(initialValue: editing?.place ?? draft?.place ?? place)
        _kind = State(initialValue: editing?.kind ?? draft?.kind ?? .letter)
        _selectedCoordinate = State(initialValue: center)
        _camera = State(initialValue: .region(MKCoordinateRegion(center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))))
    }

    private enum Field { case title, message, place }
    private var withinLimits: Bool {
        title.count <= WorldStore.titleLimit && message.count <= WorldStore.bodyLimit && place.count <= WorldStore.placeLimit
    }
    private var hasWriting: Bool { !title.isEmpty || !message.isEmpty }
    private var hasDraftContent: Bool {
        hasWriting || isResumingDraft || kind != initialDraft.kind || place != initialDraft.place ||
        abs(selectedCoordinate.latitude - initialDraft.latitude) > 0.00001 ||
        abs(selectedCoordinate.longitude - initialDraft.longitude) > 0.00001
    }
    private var hasChanges: Bool {
        if let editing {
            return title != editing.title || message != editing.body || kind != editing.kind || place != editing.place
        }
        return hasDraftContent
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && withinLimits && !isSaving
    }
    private var currentDraft: TreasureDraft {
        TreasureDraft(title: title, body: message, kind: kind, latitude: selectedCoordinate.latitude,
                      longitude: selectedCoordinate.longitude, place: place)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    introduction
                    if isResumingDraft {
                        Label("正在续写上次的草稿，地点也为你保留了", systemImage: "doc.text")
                            .font(.system(size: 12)).foregroundStyle(Palette.teal)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.mint.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                    }
                    kindPicker
                    writingCard
                    locationPreview
                }
                .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively).background(Palette.cream)
            .navigationTitle(editing == nil ? "留下一点美好" : "编辑小惊喜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        if hasChanges { focusedField = nil; showExitOptions = true }
                        else { didFinish = true; dismiss() }
                    }.foregroundStyle(Palette.secondary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        }
        .tint(Palette.teal)
        .interactiveDismissDisabled(hasChanges && !didFinish)
        .task(id: currentDraft) {
            guard editing == nil, !didFinish else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            saveDraftIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraftIfNeeded() }
        }
        .confirmationDialog(editing == nil ? "这份心意还没放好" : "保留这次修改吗？", isPresented: $showExitOptions, titleVisibility: .visible) {
            if editing == nil {
                Button("保存草稿并退出") {
                    guard withinLimits, store.saveDraft(currentDraft) else { return }
                    didFinish = true
                    dismiss()
                }.disabled(!withinLimits)
                Button("放弃这份草稿", role: .destructive) {
                    guard store.discardDraft() else { return }
                    didFinish = true
                    dismiss()
                }
            } else {
                Button("放弃本次修改", role: .destructive) { didFinish = true; dismiss() }
            }
            Button("继续写", role: .cancel) { }
        } message: {
            Text(editing == nil ? "保留草稿后，下次点 + 就能接着写。" : "原来的内容会保留，尚未保存的修改将放弃。")
        }
        .alert("还没能放好", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("继续编辑", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "你的文字还在，可以稍后再试。") }
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            Button(action: saveTreasure) {
                HStack(spacing: 8) {
                    Image(systemName: editing == nil ? "sparkles" : "checkmark")
                    Text(isSaving ? "正在收好…" : (editing == nil ? "放进小世界" : "保存修改"))
                }
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(canSave ? Palette.teal : Palette.teal.opacity(0.35), in: RoundedRectangle(cornerRadius: 21))
            }.disabled(!canSave).buttonStyle(PressStyle())
            Text(draftStatus).font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(withinLimits ? Palette.secondary : Palette.coral)
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
        .background(Palette.cream.opacity(0.97))
    }

    private var draftStatus: String {
        if !withinLimits { return "字数超过上限，缩短一点就可以保存了" }
        if editing != nil { return "修改仅保存在这台设备" }
        if hasDraftContent && store.draft == currentDraft { return "草稿已保存 · 仅在这台设备" }
        return "仅保存在这台设备 · 不会向他人发布"
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text(editing == nil ? "让平凡的角落，\n多一颗小星星。" : "把这一刻，\n再写得好一点。")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink).lineSpacing(4)
                Text("一句祝福，或一个值得记住的瞬间。")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image("StarCapsule").resizable().scaledToFit().frame(width: 78, height: 100)
                .rotationEffect(.degrees(8)).accessibilityHidden(true)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("你想留下什么？", step: "01")
            HStack(spacing: 10) {
                ForEach(TreasureKind.allCases) { item in
                    Button { kind = item } label: {
                        VStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 23, weight: .medium))
                                .foregroundStyle(Palette.teal).frame(height: 27)
                            Text(item.title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(kind == item ? item.tint : .white, in: RoundedRectangle(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(kind == item ? Palette.teal.opacity(0.5) : .clear, lineWidth: 1.5) }
                        .overlay(alignment: .topTrailing) {
                            if kind == item {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                                    .foregroundStyle(Palette.teal).padding(8)
                            }
                        }
                    }.buttonStyle(PressStyle()).accessibilityAddTraits(kind == item ? .isSelected : [])
                }
            }
        }
    }

    private var writingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("把心里话写下来", step: "02")
            VStack(alignment: .leading, spacing: 13) {
                TextField("给这份美好起个名字", text: $title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .focused($focusedField, equals: .title).submitLabel(.next)
                    .onSubmit { focusedField = .message }.accessibilityLabel("标题")
                counter(title.count, limit: WorldStore.titleLimit)
                Rectangle().fill(Palette.secondary.opacity(0.12)).frame(height: 1)
                TextField("例如：如果今天有一点累，就在这里停一下吧……", text: $message, axis: .vertical)
                    .font(.system(size: 15, design: .rounded)).lineSpacing(6).lineLimit(6...14)
                    .focused($focusedField, equals: .message).accessibilityLabel("小惊喜内容")
                counter(message.count, limit: WorldStore.bodyLimit)
            }.foregroundStyle(Palette.ink).padding(21).background(.white, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private var locationPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("留在这个小角落", step: "03")
            VStack(alignment: .leading, spacing: 0) {
                Map(position: $camera, interactionModes: editing == nil ? [.pan, .zoom] : []) {
                    if editing != nil { Marker(place, coordinate: selectedCoordinate).tint(Palette.teal) }
                }
                .id(mapReloadID)
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .continuous) { context in
                    visibleMapCamera = context.camera
                    if editing == nil { selectedCoordinate = context.region.center }
                }
                .accessibilityLabel(editing == nil ? "拖动地图，中心标记就是保存位置" : "这份记录原来的位置")
                .overlay(alignment: .center) {
                    if editing == nil {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 32))
                            .foregroundStyle(Palette.teal).background(.white, in: Circle())
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: reloadBasemap) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.teal)
                            .frame(width: 36, height: 36)
                            .background(.white, in: Circle())
                            .shadow(color: Palette.teal.opacity(0.1), radius: 8, y: 3)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("重新载入底图")
                    .accessibilityHint("保留当前地点、缩放和草稿")
                    .accessibilityIdentifier("compose.reloadMap")
                    .padding(8)
                }
                .frame(height: 170)
                VStack(alignment: .leading, spacing: 9) {
                    Label(editing == nil ? "拖动地图，把心意留在中心标记处" : "修改文字时，保留原来的位置", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                    TextField("给这个地点起个名字，例如：图书馆门口", text: $place)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                        .focused($focusedField, equals: .place).submitLabel(.done)
                        .onSubmit { focusedField = nil }.accessibilityLabel("地点名称")
                    HStack {
                        Text(String(format: "%.5f, %.5f", selectedCoordinate.latitude, selectedCoordinate.longitude))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                        counter(place.count, limit: WorldStore.placeLimit)
                    }
                }.padding(16).background(.white)
            }.clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private func reloadBasemap() {
        if let visibleMapCamera { camera = .camera(visibleMapCamera) }
        mapReloadID = UUID()
    }

    private func counter(_ count: Int, limit: Int) -> some View {
        Text("\(count) / \(limit)").font(.system(size: 10, design: .rounded))
            .foregroundStyle(count > limit ? Palette.coral : Palette.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func sectionTitle(_ text: String, step: String) -> some View {
        HStack(spacing: 8) {
            Text(step).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Palette.teal)
                .frame(width: 25, height: 25).background(Palette.mint, in: Circle())
            Text(text).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
        }
    }

    private func saveDraftIfNeeded() {
        guard editing == nil, !didFinish, withinLimits else { return }
        if hasDraftContent {
            if store.draft != currentDraft { _ = store.saveDraft(currentDraft) }
        } else if store.draft != nil { _ = store.discardDraft() }
    }

    private func saveTreasure() {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let treasure: Treasure?
        if let editing {
            treasure = store.update(editing, title: title, body: message, kind: kind, place: place)
        } else {
            treasure = store.create(title: title, body: message, kind: kind, coordinate: selectedCoordinate, place: place)
        }
        guard let treasure else { return }
        didFinish = true
        focusedField = nil
        onCreated(treasure)
        dismiss()
    }
}

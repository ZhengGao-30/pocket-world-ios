import SwiftUI
import MapKit

/// A real MapKit canvas with explicitly labelled demonstration content.
@MainActor
struct ExploreView: View {
    let store: WorldStore
    let location: WorldLocation
    @Binding var followsLocation: Bool
    let onSelect: (Treasure) -> Void
    let onCompose: (CLLocationCoordinate2D) -> Void
    let onPet: () -> Void
    let onCenterChange: (CLLocationCoordinate2D) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedKind: TreasureKind?
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var cameraPosition: MapCameraPosition
    @State private var visibleCenter: CLLocationCoordinate2D
    @State private var visibleCamera: MapCamera?
    @State private var visibleMapRect: MKMapRect?
    @State private var mapReloadID = UUID()

    init(
        store: WorldStore,
        location: WorldLocation,
        center: CLLocationCoordinate2D,
        followsLocation: Binding<Bool>,
        onSelect: @escaping (Treasure) -> Void,
        onCompose: @escaping (CLLocationCoordinate2D) -> Void,
        onPet: @escaping () -> Void,
        onCenterChange: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.store = store
        self.location = location
        _followsLocation = followsLocation
        self.onSelect = onSelect
        self.onCompose = onCompose
        self.onPet = onPet
        self.onCenterChange = onCenterChange
        let restoredCenter = CLLocationCoordinate2DIsValid(center) ? center : Self.startRegion.center
        _visibleCenter = State(initialValue: restoredCenter)
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(center: restoredCenter, span: Self.startRegion.span)
        ))
    }

    private static var startRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: WorldStore.demoCoordinate.latitude,
                longitude: WorldStore.demoCoordinate.longitude + 0.0006
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0036)
        )
    }

    private var visibleTreasures: [Treasure] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.activeTreasures.filter { treasure in
            (selectedKind == nil || treasure.kind == selectedKind)
                && (!location.isUsingDeviceLocation || !treasure.isDemo)
                && (query.isEmpty || treasure.title.localizedStandardContains(query)
                    || treasure.place.localizedStandardContains(query))
        }.sorted { location.distance(to: $0) < location.distance(to: $1) }
    }

    private var nearbyItems: [Treasure] {
        guard location.isUsingDeviceLocation else { return visibleTreasures }
        return visibleTreasures.filter { location.distance(to: $0) <= 2_000 }
    }

    private var onMapTreasureCount: Int {
        guard let rect = visibleMapRect else { return 0 }
        return visibleTreasures.filter { treasure in
            let point = MKMapPoint(treasure.coordinate)
            // A viewport crossing the date line can extend past the map world's edge.
            return [-MKMapRect.world.width, 0, MKMapRect.world.width].contains { offset in
                rect.contains(MKMapPoint(x: point.x + offset, y: point.y))
            }
        }.count
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    greeting
                    companionRibbon
                    locationControls
                    searchField
                    filters
                    mapCanvas
                        .frame(height: min(354, max(296, geometry.size.height * 0.475)))
                    nearbyTreasures
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.cream)
        }
        .onAppear {
            if followsLocation && location.isUsingDeviceLocation { recenter() }
            else { onCenterChange(visibleCenter) }
        }
        .onChange(of: location.cameraRevision) { _, _ in
            if followsLocation || !location.isUsingDeviceLocation { recenter() }
        }
        .onChange(of: cameraPosition.positionedByUser) { _, movedByUser in
            if movedByUser { followsLocation = false }
        }
    }

    private var greeting: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .heavy))
                    Text("POCKET WORLD")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(2.8)
                }
                .foregroundStyle(Palette.teal)

                Text("出门，捡点小美好。")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .tracking(-0.9)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                    Text(location.isUsingDeviceLocation ? "我的附近 · 本机故事" : "UNSW · 示范漫游")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onPet) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 29)
                        .fill(Palette.mint.opacity(0.75))
                        .frame(width: 66, height: 64)
                        .rotationEffect(.degrees(9))
                        .padding(.bottom, 7)
                    Image(store.pet.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 99)
                        .offset(y: 3)
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.coral)
                        .offset(x: 30, y: -67)
                }
                .frame(width: 80, height: 83)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("我的搭子，\(store.pet.name)")
            .accessibilityHint("查看并选择你的陪伴宠物")
        }
    }

    private var companionRibbon: some View {
        Button(action: onPet) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(-15))
                Text("\(store.pet.name)陪你，把日常逛成奇遇")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(Palette.teal)
            .padding(.horizontal, 14)
            .frame(height: 39)
            .background(Palette.mint.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterButton(nil, title: "全部", symbol: "square.grid.2x2.fill")
                filterButton(.letter, title: "小纸条", symbol: "envelope.fill")
                filterButton(.wish, title: "许愿星", symbol: "star.fill")
                filterButton(.memory, title: "时光片", symbol: "camera.fill")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.secondary)
            TextField("找找标题或地点", text: $searchText)
                .font(.subheadline)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel("搜索故事标题或地点")
                .accessibilityIdentifier("explore.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }

    private var locationControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { locationButtons }
                VStack(alignment: .leading, spacing: 8) { locationButtons }
            }
            Text(location.statusText)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("explore.locationStatus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var locationButtons: some View {
        Button {
            followsLocation = true
            if location.isTracking && location.hasFreshSnapshot { recenter() }
            else { location.requestLocation() }
        } label: {
            HStack(spacing: 6) {
                if location.isRequestingLocation {
                    ProgressView().tint(Palette.teal)
                } else {
                    Image(systemName: "location.fill")
                }
                Text(location.isRequestingLocation ? "正在定位…" : location.isTracking ? "回到我 · 跟随" : "开启实地漫游")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.teal)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(.white, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .disabled(location.isRequestingLocation)
        .accessibilityHint("在前台随行更新位置，进入后台暂停；手动拖地图可停止跟随")
        .accessibilityIdentifier("explore.locate")

        Button {
            followsLocation = false
            location.useDemo()
        } label: {
            Label(location.isUsingDeviceLocation ? "回到示范" : "UNSW 示范", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.teal)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.mint.opacity(0.75), in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("explore.demo")
    }

    private func filterButton(_ kind: TreasureKind?, title: String, symbol: String) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                selectedKind = kind
                selectedID = nil
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : Palette.secondary)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(isSelected ? Palette.teal : .white.opacity(0.85), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? .clear : Palette.ink.opacity(0.045), lineWidth: 1)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("筛选：\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var mapCanvas: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            if location.isUsingDeviceLocation, let fix = location.snapshot {
                MapCircle(center: fix.coordinate, radius: max(1, fix.horizontalAccuracy))
                    .foregroundStyle(Palette.teal.opacity(0.08))
                    .stroke(Palette.teal.opacity(0.2), lineWidth: 1)
            }
            Annotation(location.isUsingDeviceLocation ? "我的位置" : "示范起点", coordinate: location.referenceCoordinate, anchor: .center) {
                demoAnchor
            }
            .annotationTitles(.hidden)

            ForEach(visibleTreasures) { treasure in
                Annotation(treasure.title, coordinate: treasure.coordinate, anchor: .bottom) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65)) {
                            selectedID = treasure.id
                        }
                        onSelect(treasure)
                    } label: {
                        TreasureMapPin(
                            treasure: treasure,
                            isSelected: selectedID == treasure.id,
                            isOpened: store.openedIDs.contains(treasure.id)
                        )
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(treasure.kind.title)，\(treasure.title)，\(location.distanceLabel(for: treasure))")
                    .accessibilityHint("打开这份小惊喜")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .onMapCameraChange(frequency: .continuous) { context in
            visibleCenter = context.region.center
            visibleCamera = context.camera
            visibleMapRect = context.rect
            onCenterChange(context.region.center)
        }
        .id(mapReloadID)
        .overlay {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.teal)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(Palette.teal.opacity(0.25), lineWidth: 1))
                .allowsHitTesting(false)
                .accessibilityLabel("地图中心，新故事将留在这里")
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Palette.teal)
                    .frame(width: 5, height: 5)
                Text(location.isUsingDeviceLocation ? (followsLocation ? "跟着我走" : "自由看地图") : "示范漫游")
                    .font(.system(size: 10, weight: .bold))
                Text("·")
                    .foregroundStyle(Palette.secondary)
                Text("此处 \(onMapTreasureCount) 份")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            .padding(13)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Button {
                    followsLocation = location.isUsingDeviceLocation
                    recenter()
                } label: {
                    mapControlIcon(followsLocation && location.isUsingDeviceLocation ? "location.fill" : "scope")
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(location.isUsingDeviceLocation ? "回到我并跟随位置" : "回到 UNSW 示范起点")

                Button(action: reloadMap) {
                    mapControlIcon("arrow.clockwise")
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("重新载入底图")
                .accessibilityHint("道路未显示时重试，保留当前地图位置与缩放")
                .accessibilityIdentifier("explore.reloadMap")
            }
            .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                onCompose(visibleCenter)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                    Text("在中心留下")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Palette.teal)
                .padding(.horizontal, 14)
                .frame(height: 39)
                .background(Palette.lemon, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(color: Palette.ink.opacity(0.12), radius: 9, y: 4)
            }
            .buttonStyle(PressStyle())
            .padding(.trailing, 13)
            .padding(.bottom, 28)
            .accessibilityHint("在当前地图中心写下一份心意，保存到本机")
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(.white, lineWidth: 3)
                .allowsHitTesting(false)
        }
        .shadow(color: Palette.teal.opacity(0.07), radius: 15, y: 7)
        .accessibilityIdentifier("explore.map")
    }

    private func mapControlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Palette.teal)
            .frame(width: 36, height: 36)
            .background(.white.opacity(0.96), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: Palette.ink.opacity(0.10), radius: 8, y: 3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func reloadMap() {
        // SwiftUI Map has no tile-error callback. This is an explicit retry,
        // preserving the camera rather than treating GPS success as map readiness.
        if let visibleCamera { cameraPosition = .camera(visibleCamera) }
        mapReloadID = UUID()
    }

    private var demoAnchor: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Palette.teal.opacity(0.09))
                    .frame(width: 38, height: 38)
                Circle()
                    .fill(Palette.teal.opacity(0.1))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Palette.teal)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: Palette.teal.opacity(0.22), radius: 3, y: 2)
            }
            Text(location.isUsingDeviceLocation ? (location.hasFreshSnapshot ? "我在这里" : "上次位置") : "示范起点")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.white.opacity(0.95), in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(location.isUsingDeviceLocation ? (location.hasFreshSnapshot ? "我的位置，圆圈表示定位精度" : "上次定位，暂不可用于确认到达") : "UNSW 示范起点，并非实时定位")
    }

    private func recenter() {
        let center = location.isUsingDeviceLocation ? location.referenceCoordinate : Self.startRegion.center
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: Self.startRegion.span))
            visibleCenter = center
        }
        onCenterChange(center)
    }

    private var nearbyTreasures: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 7) {
                Text("附近的小惊喜")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(String(format: "%02d", nearbyItems.count))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.teal)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.mint, in: Capsule())
                Spacer(minLength: 0)
                Text(location.isUsingDeviceLocation ? "约 2 公里内" : "示范距离排序")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }

            if nearbyItems.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(searchText.isEmpty && selectedKind == nil ? "这一格，还等着你的心意" : "暂时没有匹配的小惊喜")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text(location.isUsingDeviceLocation
                             ? "目前只有本机故事，附近还没找到匹配的内容。可在地图中心留下第一份，或回到示范体验。"
                             : "换个关键词或类别试试，也可以在地图中心放下第一份。")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 93)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(nearbyItems) { treasure in
                            Button {
                                selectedID = treasure.id
                                onSelect(treasure)
                            } label: {
                                nearbyCard(treasure)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.bottom, 4)
                }
                .contentMargins(.trailing, 1)
            }
        }
    }

    private func nearbyCard(_ treasure: Treasure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(treasure.kind.tint.opacity(0.22))
                        .frame(width: 43, height: 43)
                    if treasure.kind == .wish {
                        Image("StarCapsule")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 41, height: 41)
                    } else {
                        Image(systemName: treasure.kind.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Palette.teal)
                            .rotationEffect(.degrees(-8))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text(treasure.kind.title)
                        if !treasure.isDemo {
                            Text("本地")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Palette.teal)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Palette.mint, in: Capsule())
                        }
                        Text("·")
                        Text(location.distanceLabel(for: treasure).replacingOccurrences(of: "示范距离 · ", with: ""))
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)

                    Text(treasure.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 9, weight: .semibold))
                Text(treasure.place)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if store.savedIDs.contains(treasure.id) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(Palette.teal)
                } else {
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(Palette.teal)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Palette.secondary)
        }
        .padding(13)
        .frame(width: 260, alignment: .leading)
        .background(.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Palette.teal.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct TreasureMapPin: View {
    let treasure: Treasure
    let isSelected: Bool
    let isOpened: Bool

    var body: some View {
        VStack(spacing: -2) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 49, height: 49)
                Circle()
                    .fill(treasure.kind.tint.opacity(0.35))
                    .frame(width: 41, height: 41)
                if treasure.kind == .wish {
                    Image("StarCapsule")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: treasure.kind.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .rotationEffect(.degrees(treasure.kind == .letter ? -12 : 8))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isOpened {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Palette.teal, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .offset(x: 1, y: -1)
                }
            }
            MapPinTip()
                .fill(.white)
                .frame(width: 12, height: 8)
        }
        .scaleEffect(isSelected ? 1.16 : 1)
        .shadow(color: Palette.teal.opacity(isSelected ? 0.25 : 0.18), radius: isSelected ? 8 : 5, y: 4)
    }
}

private struct MapPinTip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

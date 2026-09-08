import SwiftUI
import MapKit

@main
struct PocketWorldApp: App {
    @State private var store = WorldStore()
    var body: some Scene {
        WindowGroup {
            WorldRootView(store: store)
                .preferredColorScheme(.light)
                .tint(Palette.teal)
        }
    }
}

private enum WorldTab: String, CaseIterable {
    case explore = "发现", pocket = "口袋", companion = "伙伴"
    var symbol: String {
        switch self {
        case .explore: return "safari.fill"
        case .pocket: return "tray.full.fill"
        case .companion: return "pawprint.fill"
        }
    }
}

private enum WorldSheet: Identifiable {
    case treasure(Treasure)
    case compose(CLLocationCoordinate2D)
    var id: String {
        switch self {
        case .treasure(let item): return item.id.uuidString
        case .compose: return "compose"
        }
    }
}

struct WorldRootView: View {
    @Bindable var store: WorldStore
    @State private var location = WorldLocation()
    @State private var mapCenter = WorldStore.demoCoordinate
    @State private var mapGeneration = UUID()
    @State private var followsLocation = false
    @State private var tab: WorldTab = .explore
    @State private var sheet: WorldSheet?
    @State private var toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigation

    var body: some View {
        ZStack(alignment: .top) {
            Palette.cream.ignoresSafeArea()
            Group {
                switch tab {
                case .explore:
                    ExploreView(store: store, location: location, center: mapCenter, followsLocation: $followsLocation, onSelect: showTreasure,
                                onCompose: { sheet = .compose($0) },
                                onPet: { changeTab(.companion) },
                                onCenterChange: { mapCenter = $0 })
                        .id(mapGeneration)
                case .pocket:
                    PocketView(store: store, onSelect: showTreasure,
                               onExplore: { changeTab(.explore) })
                case .companion:
                    CompanionView(store: store, onExplore: { changeTab(.explore) })
                }
            }
            .transition(.opacity)
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(16).background(.regularMaterial, in: Capsule())
                    .foregroundStyle(Palette.teal).shadow(color: .black.opacity(0.08), radius: 15)
                    .padding(.top, 12).transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        .sheet(item: $sheet) { item in
            switch item {
            case .treasure(let treasure):
                TreasureDetailView(treasure: treasure, store: store, location: location) {
                        mapCenter = treasure.coordinate
                        mapGeneration = UUID()
                        followsLocation = false
                        tab = .explore
                        sheet = nil
                    }
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                    .presentationCornerRadius(34)
            case .compose(let coordinate):
                ComposeTreasureView(store: store, coordinate: coordinate) { created in
                    mapCenter = created.coordinate
                    followsLocation = false
                    mapGeneration = UUID()
                    tab = .explore
                    withAnimation { toast = "小惊喜已留在地图上 · 本地保存" }
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
        .alert("这次没有保存成功", isPresented: Binding(
            get: { store.errorMessage != nil && sheet == nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "请稍后再试。") }
    }

    private var navigationBar: some View {
        HStack(spacing: 3) {
            ForEach(WorldTab.allCases, id: \.self) { item in
                Button { changeTab(item) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol).font(.system(size: 19, weight: .semibold))
                        if item == tab { Text(item.rawValue).font(.system(size: 13, weight: .bold)) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(tab == item ? Palette.ink : .white.opacity(0.68))
                    .background {
                        if item == tab {
                            Capsule().fill(Palette.mint)
                                .matchedGeometryEffect(id: "selection", in: navigation)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(item == tab ? [.isSelected] : [])
                .accessibilityIdentifier("tab-\(item.rawValue)")
            }
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 20).padding(.horizontal, 7)
            Button { sheet = .compose(mapCenter) } label: {
                Image(systemName: "plus").font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Palette.ink).frame(width: 46, height: 46)
                    .background(Palette.lemon, in: Circle())
            }
            .buttonStyle(PressStyle()).accessibilityLabel("留下小惊喜")
        }
        .padding(8).background(Palette.ink, in: Capsule())
        .shadow(color: Palette.ink.opacity(0.16), radius: 15, y: 6)
        .padding(.horizontal, 22).padding(.top, 7).padding(.bottom, 4)
        .background(Palette.cream)
    }

    private func showTreasure(_ treasure: Treasure) { sheet = .treasure(treasure) }
    private func changeTab(_ value: WorldTab) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) { tab = value }
    }
}

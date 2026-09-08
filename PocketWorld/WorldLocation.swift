import CoreLocation
import Observation
import UIKit

/// The user explicitly starts a foreground roaming session. Launching the app
/// never requests permission; going into the background always stops updates.
@MainActor
@Observable
final class WorldLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var isUsingDeviceLocation = false
    private(set) var isRequestingLocation = false
    private(set) var isTracking = false
    private(set) var statusText = "示范漫游 · 尚未使用设备定位"
    private(set) var cameraRevision = 0
    private(set) var snapshot: CLLocation?
    private(set) var hasFreshSnapshot = false

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let applicationIsActive: @MainActor () -> Bool
    @ObservationIgnored private let servicesEnabled: @Sendable () async -> Bool
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let initialFixTimeout: Duration
    @ObservationIgnored private var wantsDeviceLocation = false
    @ObservationIgnored private var waitingForAuthorization = false
    @ObservationIgnored private var requestToken = UUID()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    override convenience init() {
        // Core Location calls delegates on the run loop where its manager was
        // created. Both creation and delegate installation occur on MainActor.
        self.init(manager: CLLocationManager())
    }

    /// Tests inject synthetic fixes and manager commands without accessing a
    /// real location or changing the user's system permission.
    init(
        manager: CLLocationManager,
        now: @escaping () -> Date = Date.init,
        applicationIsActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        servicesEnabled: @escaping @Sendable () async -> Bool = {
            await Task.detached(priority: .userInitiated) { CLLocationManager.locationServicesEnabled() }.value
        },
        notificationCenter: NotificationCenter = .default,
        initialFixTimeout: Duration = .seconds(20)
    ) {
        self.manager = manager
        self.now = now
        self.applicationIsActive = applicationIsActive
        self.servicesEnabled = servicesEnabled
        self.notificationCenter = notificationCenter
        self.initialFixTimeout = initialFixTimeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = false
        notificationCenter.addObserver(self, selector: #selector(didEnterBackground),
                                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(didBecomeActive),
                                       name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        manager.stopUpdatingLocation()
        expiryTask?.cancel()
        timeoutTask?.cancel()
        notificationCenter.removeObserver(self)
    }

    /// Paused or expired locations remain a labelled map reference, never proof
    /// of arrival. Camera following is controlled separately by ExploreView.
    var referenceCoordinate: CLLocationCoordinate2D {
        isUsingDeviceLocation ? (snapshot?.coordinate ?? WorldStore.demoCoordinate) : WorldStore.demoCoordinate
    }

    func distance(to treasure: Treasure) -> CLLocationDistance {
        WorldLocationPolicy.distance(from: referenceCoordinate, to: treasure.coordinate)
    }

    func distanceLabel(for treasure: Treasure) -> String {
        let meters = distance(to: treasure)
        guard meters.isFinite else { return "距离暂不可用" }
        let text: String
        if meters < 1_000 {
            text = "约 \(max(0, Int((meters / 5).rounded()) * 5)) 米"
        } else if meters < 100_000 {
            text = String(format: "约 %.1f 公里", meters / 1_000)
        } else {
            text = "约 \(Int((meters / 1_000).rounded())) 公里"
        }
        guard isUsingDeviceLocation else { return "示范距离 · \(text)" }
        if isTracking, hasFreshSnapshot, let snapshot, WorldLocationPolicy.isFresh(snapshot, now: now()) {
            return text
        }
        return "上次定位 · \(text)"
    }

    func canOpen(_ treasure: Treasure) -> Bool {
        guard isTracking, isUsingDeviceLocation, hasFreshSnapshot, !isRequestingLocation,
              applicationIsActive(), isAuthorized, let snapshot else { return false }
        return WorldLocationPolicy.canOpen(coordinate: treasure.coordinate, snapshot: snapshot, now: now())
    }

    /// Stopping before restarting forces a new initial update. Calling start
    /// repeatedly without stopping does not, according to Core Location.
    func requestLocation() {
        guard !isRequestingLocation, applicationIsActive() else { return }
        wantsDeviceLocation = true
        prepareRequest(allowPermissionPrompt: true)
    }

    func useDemo() {
        wantsDeviceLocation = false
        stopTracking()
        snapshot = nil
        isUsingDeviceLocation = false
        statusText = "示范漫游 · 尚未使用设备定位"
        cameraRevision += 1
    }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    private func prepareRequest(allowPermissionPrompt: Bool) {
        stopTracking()
        isRequestingLocation = true
        statusText = "位置更新中…"
        let token = requestToken
        let checkServices = servicesEnabled
        Task { [weak self] in
            let enabled = await checkServices()
            guard let self, self.wantsDeviceLocation, self.isRequestingLocation,
                  self.requestToken == token else { return }
            guard enabled else {
                self.finishFailure("系统定位已关闭，可在设置中开启或继续示范。")
                return
            }
            self.beginAuthorizedTracking(allowPermissionPrompt: allowPermissionPrompt)
        }
    }

    private func beginAuthorizedTracking(allowPermissionPrompt: Bool) {
        guard wantsDeviceLocation else { return }
        guard applicationIsActive() else {
            finishFailure("漫游已暂停，回到 App 后继续。")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            guard allowPermissionPrompt else {
                finishFailure("点击定位到我这里，开启前台漫游。")
                return
            }
            waitingForAuthorization = true
            statusText = "允许使用期间定位，即可开始漫游。"
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            waitingForAuthorization = false
            isTracking = true
            manager.startUpdatingLocation()
            let timeout = initialFixTimeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, let self, self.isRequestingLocation else { return }
                self.finishFailure("暂时没找到你的位置，点定位重试。")
            }
        case .denied:
            finishFailure("尚未获准定位，可在设置中允许或继续示范。")
        case .restricted:
            finishFailure("设备限制了定位权限，仍可使用示范漫游。")
        @unknown default:
            finishFailure("定位暂时不可用，仍可使用示范漫游。")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if waitingForAuthorization, isRequestingLocation {
            guard manager.authorizationStatus != .notDetermined else { return }
            beginAuthorizedTracking(allowPermissionPrompt: false)
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            let hadDeviceLocation = isUsingDeviceLocation
            let hadPendingRequest = isRequestingLocation || isTracking
            stopTracking()
            snapshot = nil
            isUsingDeviceLocation = false
            if hadDeviceLocation {
                statusText = "定位权限已关闭，已回到示范漫游。"
                cameraRevision += 1
            } else if hadPendingRequest {
                statusText = "定位权限未开启，仍可使用示范漫游。"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsDeviceLocation, isTracking, !waitingForAuthorization, applicationIsActive() else { return }
        let currentTime = now()
        guard let latest = WorldLocationPolicy.latestFreshLocation(in: locations, now: currentTime) else {
            invalidateFix("位置更新中，暂时无法验证到达。")
            return
        }
        // Never let a delayed batch move the map back or revive the location
        // invalidated when the session paused, failed or refreshed.
        if let snapshot, latest.timestamp <= snapshot.timestamp {
            if latest.timestamp == snapshot.timestamp,
               latest.horizontalAccuracy > WorldLocationPolicy.maximumAccuracy {
                invalidateFix("定位精度不足，正在等待更准确的位置。")
            }
            return
        }
        timeoutTask?.cancel()
        expiryTask?.cancel()
        isRequestingLocation = false
        snapshot = latest
        hasFreshSnapshot = true
        isUsingDeviceLocation = true
        statusText = latest.horizontalAccuracy <= WorldLocationPolicy.maximumAccuracy
            ? "前台漫游中 · 精度约 \(max(1, Int(latest.horizontalAccuracy.rounded()))) 米"
            : "定位精度不足，正在等待更准确的位置。"
        cameraRevision += 1
        let remaining = max(0, WorldLocationPolicy.maximumAge - currentTime.timeIntervalSince(latest.timestamp))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.1))
            guard !Task.isCancelled, let self, self.isTracking else { return }
            self.hasFreshSnapshot = false
            self.statusText = "位置已过期，点定位刷新后再打开故事。"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsDeviceLocation, isTracking || isRequestingLocation else { return }
        let code = (error as? CLError)?.code
        if code == .denied {
            finishFailure("定位权限或系统定位已关闭，请查看设置。")
        } else if code == .locationUnknown {
            // Temporary loss of GPS should not terminate the walking session,
            // but the previous fix is no longer accepted as proof of arrival.
            invalidateFix("GPS 信号暂弱，正在重新定位…")
        } else {
            finishFailure("定位暂时中断，点定位重新开始。")
        }
    }

    private func invalidateFix(_ message: String) {
        expiryTask?.cancel()
        hasFreshSnapshot = false
        statusText = message
    }

    private func finishFailure(_ message: String) {
        stopTracking()
        statusText = message
    }

    private func stopTracking() {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel()
        expiryTask?.cancel()
        waitingForAuthorization = false
        isRequestingLocation = false
        isTracking = false
        hasFreshSnapshot = false
        requestToken = UUID()
    }

    @objc private func didEnterBackground() {
        guard wantsDeviceLocation else { return }
        stopTracking()
        statusText = "漫游已暂停，回到 App 后继续。"
    }

    @objc private func didBecomeActive() {
        // Never prompt on foreground entry. Resume only the session that this
        // user explicitly selected during this app run, with existing access.
        guard wantsDeviceLocation, !isTracking, !isRequestingLocation, applicationIsActive(), isAuthorized else { return }
        prepareRequest(allowPermissionPrompt: false)
    }
}

/// Kept separate from permission/UI state so expiry, accuracy and proximity
/// boundaries can be tested without requesting real location access.
enum WorldLocationPolicy {
    static let maximumAge: TimeInterval = 120
    static let maximumAccuracy: CLLocationAccuracy = 100
    static let openingRadius: CLLocationDistance = 100

    static func isFresh(_ snapshot: CLLocation, now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.timestamp)
        return CLLocationCoordinate2DIsValid(snapshot.coordinate)
            && snapshot.horizontalAccuracy.isFinite && snapshot.horizontalAccuracy >= 0
            && age.isFinite && age >= 0 && age <= maximumAge
    }

    static func latestFreshLocation(in locations: [CLLocation], now: Date) -> CLLocation? {
        locations.filter { isFresh($0, now: now) }.max(by: { $0.timestamp < $1.timestamp })
    }

    static func canOpen(coordinate: CLLocationCoordinate2D, snapshot: CLLocation, now: Date) -> Bool {
        isFresh(snapshot, now: now)
            && snapshot.horizontalAccuracy <= maximumAccuracy
            && distance(from: snapshot.coordinate, to: coordinate) <= openingRadius
    }

    static func distance(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        guard CLLocationCoordinate2DIsValid(origin), CLLocationCoordinate2DIsValid(destination) else { return .infinity }
        return CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }
}

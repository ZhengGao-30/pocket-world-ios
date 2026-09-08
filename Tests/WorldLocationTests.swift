import CoreLocation
import UIKit
import XCTest
@testable import PocketWorld

final class WorldLocationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let origin = CLLocationCoordinate2D(latitude: -33.9173, longitude: 151.2313)

    private func snapshot(age: TimeInterval = 0, accuracy: CLLocationAccuracy = 10) -> CLLocation {
        CLLocation(coordinate: origin, altitude: 0, horizontalAccuracy: accuracy,
                   verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
    }

    func testFreshAccurateSnapshotAllowsNearbyButNotDistantStory() {
        XCTAssertTrue(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: snapshot(), now: now))
        let nearby = CLLocationCoordinate2D(latitude: origin.latitude + 0.0004, longitude: origin.longitude)
        let distant = CLLocationCoordinate2D(latitude: origin.latitude + 0.002, longitude: origin.longitude)
        XCTAssertTrue(WorldLocationPolicy.canOpen(coordinate: nearby, snapshot: snapshot(), now: now))
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: distant, snapshot: snapshot(), now: now))
    }

    func testSnapshotExpiresAfterTwoMinutesEvenWithoutAnotherLocationCallback() {
        let current = snapshot()
        XCTAssertTrue(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: current, now: now.addingTimeInterval(120)))
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: current, now: now.addingTimeInterval(120.01)))
    }

    func testPoorAccuracyCanLocateMapButCannotProveArrival() {
        XCTAssertTrue(WorldLocationPolicy.isFresh(snapshot(accuracy: 101), now: now))
        XCTAssertTrue(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: snapshot(accuracy: 100), now: now))
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: snapshot(accuracy: 101), now: now))
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: snapshot(accuracy: -1), now: now))
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: snapshot(accuracy: .infinity), now: now))
    }

    func testInvalidCoordinateAndFutureTimestampNeverProveArrival() {
        let invalid = CLLocationCoordinate2D(latitude: 91, longitude: 0)
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: invalid, snapshot: snapshot(), now: now))
        XCTAssertFalse(WorldLocationPolicy.canOpen(coordinate: origin, snapshot: snapshot(age: -1), now: now))
        XCTAssertEqual(WorldLocationPolicy.distance(from: origin, to: invalid), .infinity)
    }

    @MainActor
    func testNewLocationObjectStartsInDemoAndDoesNotRequestAccess() async {
        let harness = LocationTestHarness()
        let location = harness.location!
        XCTAssertFalse(location.isUsingDeviceLocation)
        XCTAssertFalse(location.isRequestingLocation)
        XCTAssertFalse(location.isTracking)
        XCTAssertNil(location.snapshot)
        XCTAssertEqual(location.referenceCoordinate.latitude, WorldStore.demoCoordinate.latitude)
        XCTAssertTrue(location.statusText.contains("示范"))
        let treasure = Treasure(id: UUID(), title: "示范故事", body: "你好", place: "示范点",
                                latitude: origin.latitude, longitude: origin.longitude,
                                kind: .letter, author: "示例", isDemo: true, createdAt: now)
        XCTAssertFalse(location.canOpen(treasure))
        location.useDemo()
        XCTAssertFalse(location.isRequestingLocation)
        XCTAssertNil(location.snapshot)
        harness.notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await settleTasks()
        XCTAssertEqual(harness.manager.starts, 0)
        XCTAssertEqual(harness.manager.permissionRequests, 0)
    }

    @MainActor
    func testAuthorizedSessionContinuouslyUpdatesWithoutRequestingOneOffLocation() async {
        let harness = LocationTestHarness()
        harness.location.requestLocation()
        await settleTasks()
        XCTAssertTrue(harness.location.isTracking)
        XCTAssertTrue(harness.location.isRequestingLocation)
        XCTAssertEqual(harness.manager.starts, 1)
        XCTAssertEqual(harness.manager.distanceFilter, 10)
        XCTAssertEqual(harness.manager.desiredAccuracy, kCLLocationAccuracyNearestTenMeters)
        XCTAssertFalse(harness.manager.allowsBackgroundLocationUpdates)

        harness.sendFix()
        XCTAssertFalse(harness.location.isRequestingLocation)
        XCTAssertTrue(harness.location.canOpen(harness.treasure))
        let firstRevision = harness.location.cameraRevision
        harness.date.addTimeInterval(5)
        let moved = CLLocationCoordinate2D(latitude: origin.latitude + 0.0004, longitude: origin.longitude)
        harness.sendFix(coordinate: moved)
        XCTAssertEqual(harness.location.referenceCoordinate.latitude, moved.latitude)
        XCTAssertEqual(harness.location.cameraRevision, firstRevision + 1)
        XCTAssertTrue(harness.location.isTracking)
        XCTAssertEqual(harness.manager.starts, 1)
        XCTAssertEqual(harness.manager.oneOffRequests, 0)
        XCTAssertEqual(harness.manager.permissionRequests, 0)
    }

    @MainActor
    func testPermissionPromptOnlyFollowsExplicitRequestAndRevocationStopsTracking() async {
        let harness = LocationTestHarness()
        harness.manager.stubAuthorization = .notDetermined
        harness.notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await settleTasks()
        XCTAssertEqual(harness.manager.permissionRequests, 0)

        harness.location.requestLocation()
        await settleTasks()
        XCTAssertEqual(harness.manager.permissionRequests, 1)
        XCTAssertFalse(harness.location.isTracking)
        harness.manager.stubAuthorization = .authorizedWhenInUse
        harness.location.locationManagerDidChangeAuthorization(harness.manager)
        XCTAssertEqual(harness.manager.starts, 1)
        harness.sendFix()
        XCTAssertTrue(harness.location.canOpen(harness.treasure))

        harness.manager.stubAuthorization = .denied
        harness.location.locationManagerDidChangeAuthorization(harness.manager)
        XCTAssertFalse(harness.location.isTracking)
        XCTAssertFalse(harness.location.hasFreshSnapshot)
        XCTAssertFalse(harness.location.isUsingDeviceLocation)
        XCTAssertNil(harness.location.snapshot)
        harness.notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await settleTasks()
        XCTAssertEqual(harness.manager.starts, 1)
        XCTAssertEqual(harness.manager.permissionRequests, 1)
    }

    @MainActor
    func testBackgroundPausesAndForegroundResumesOnlyUntilUserReturnsToDemo() async {
        let harness = LocationTestHarness()
        harness.location.requestLocation()
        await settleTasks()
        harness.sendFix()
        let previousFix = harness.location.snapshot!
        harness.isActive = false
        harness.notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(harness.location.isTracking)
        XCTAssertFalse(harness.location.hasFreshSnapshot)
        XCTAssertFalse(harness.location.canOpen(harness.treasure))
        XCTAssertNotNil(harness.location.snapshot)

        harness.date.addTimeInterval(10)
        harness.isActive = true
        harness.notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await settleTasks()
        XCTAssertEqual(harness.manager.starts, 2)
        XCTAssertTrue(harness.location.isTracking)
        XCTAssertFalse(harness.location.hasFreshSnapshot)
        harness.location.locationManager(harness.manager, didUpdateLocations: [previousFix])
        XCTAssertFalse(harness.location.canOpen(harness.treasure), "A cached pre-pause fix cannot revive arrival.")
        harness.sendFix()
        XCTAssertTrue(harness.location.canOpen(harness.treasure))

        harness.location.useDemo()
        XCTAssertFalse(harness.location.isTracking)
        XCTAssertNil(harness.location.snapshot)
        harness.isActive = false
        harness.notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        harness.isActive = true
        harness.notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await settleTasks()
        XCTAssertEqual(harness.manager.starts, 2)
        XCTAssertEqual(harness.manager.permissionRequests, 0)
    }

    @MainActor
    func testPoorOrMissingFixCannotReuseAnOlderAccurateArrival() async {
        let harness = LocationTestHarness()
        harness.location.requestLocation()
        await settleTasks()
        harness.sendFix()
        XCTAssertTrue(harness.location.canOpen(harness.treasure))

        harness.sendFix(accuracy: 500)
        XCTAssertFalse(harness.location.canOpen(harness.treasure), "A same-timestamp accuracy downgrade must invalidate the previous fix.")
        harness.date.addTimeInterval(5)
        harness.sendFix(accuracy: 500)
        XCTAssertTrue(harness.location.isUsingDeviceLocation)
        XCTAssertTrue(harness.location.isTracking)
        XCTAssertFalse(harness.location.canOpen(harness.treasure))
        XCTAssertTrue(harness.location.statusText.contains("精度不足"))

        harness.date.addTimeInterval(5)
        harness.sendFix()
        let lastAccurateFix = harness.location.snapshot!
        XCTAssertTrue(harness.location.canOpen(harness.treasure))
        harness.location.locationManager(harness.manager, didFailWithError: CLError(.locationUnknown))
        XCTAssertTrue(harness.location.isTracking)
        XCTAssertFalse(harness.location.hasFreshSnapshot)
        harness.location.locationManager(harness.manager, didUpdateLocations: [lastAccurateFix])
        XCTAssertFalse(harness.location.canOpen(harness.treasure))

        harness.date.addTimeInterval(5)
        harness.sendFix()
        XCTAssertTrue(harness.location.canOpen(harness.treasure))
        harness.sendFix(age: 200)
        XCTAssertFalse(harness.location.hasFreshSnapshot)
        XCTAssertFalse(harness.location.canOpen(harness.treasure))
        XCTAssertTrue(harness.location.isTracking)
    }

    @MainActor
    func testFirstFixTimeoutStopsUpdatesAndExplicitRetryCanRestart() async throws {
        let harness = LocationTestHarness(timeout: .milliseconds(20))
        harness.location.requestLocation()
        await settleTasks()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(harness.location.isTracking)
        XCTAssertFalse(harness.location.isRequestingLocation)
        harness.sendFix()
        XCTAssertNil(harness.location.snapshot, "Late fixes after stopping are ignored.")

        harness.location.requestLocation()
        await settleTasks()
        XCTAssertEqual(harness.manager.starts, 2)
        harness.sendFix()
        XCTAssertTrue(harness.location.canOpen(harness.treasure))
        XCTAssertTrue(harness.location.isTracking)
    }

    @MainActor
    func testExpiryChangesObservedStateAndCurrentClockGuardsArrival() async throws {
        let harness = LocationTestHarness()
        harness.location.requestLocation()
        await settleTasks()
        harness.sendFix(age: 119.99)
        XCTAssertTrue(harness.location.hasFreshSnapshot)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(harness.location.hasFreshSnapshot)
        XCTAssertFalse(harness.location.canOpen(harness.treasure))
        XCTAssertTrue(harness.location.isTracking)

        harness.date.addTimeInterval(1)
        harness.sendFix()
        XCTAssertTrue(harness.location.canOpen(harness.treasure))
        harness.date.addTimeInterval(121)
        XCTAssertFalse(harness.location.canOpen(harness.treasure))
        XCTAssertTrue(harness.location.distanceLabel(for: harness.treasure).contains("上次定位"))
    }

    @MainActor
    func testReturningToDemoCancelsPendingServiceCheck() async throws {
        let harness = LocationTestHarness(servicesEnabled: {
            try? await Task.sleep(for: .milliseconds(30))
            return true
        })
        harness.location.requestLocation()
        harness.location.useDemo()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(harness.location.isTracking)
        XCTAssertFalse(harness.location.isRequestingLocation)
        XCTAssertEqual(harness.manager.starts, 0)
        XCTAssertEqual(harness.manager.permissionRequests, 0)
    }

    @MainActor
    private func settleTasks() async {
        for _ in 0..<12 { await Task.yield() }
    }
}

/// Native calls are recorded, never forwarded to Core Location. No test asks
/// the simulator for real GPS coordinates or changes a system permission.
private final class StubLocationManager: CLLocationManager {
    var stubAuthorization: CLAuthorizationStatus = .authorizedWhenInUse
    var starts = 0
    var stops = 0
    var permissionRequests = 0
    var oneOffRequests = 0

    override var authorizationStatus: CLAuthorizationStatus { stubAuthorization }
    override func startUpdatingLocation() { starts += 1 }
    override func stopUpdatingLocation() { stops += 1 }
    override func requestWhenInUseAuthorization() { permissionRequests += 1 }
    override func requestLocation() { oneOffRequests += 1 }
}

@MainActor
private final class LocationTestHarness {
    let manager = StubLocationManager()
    let notifications = NotificationCenter()
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var isActive = true
    var location: WorldLocation!

    var treasure: Treasure {
        Treasure(id: UUID(), title: "附近故事", body: "你好", place: "测试点",
                 latitude: -33.9173, longitude: 151.2313, kind: .letter,
                 author: "测试", isDemo: false, createdAt: date)
    }

    init(timeout: Duration = .seconds(20), servicesEnabled: @escaping @Sendable () async -> Bool = { true }) {
        location = WorldLocation(manager: manager, now: { [unowned self] in self.date },
                                 applicationIsActive: { [unowned self] in self.isActive },
                                 servicesEnabled: servicesEnabled, notificationCenter: notifications,
                                 initialFixTimeout: timeout)
    }

    func sendFix(coordinate: CLLocationCoordinate2D? = nil, age: TimeInterval = 0, accuracy: CLLocationAccuracy = 10) {
        let fix = CLLocation(coordinate: coordinate ?? treasure.coordinate, altitude: 0,
                             horizontalAccuracy: accuracy, verticalAccuracy: -1,
                             timestamp: date.addingTimeInterval(-age))
        location.locationManager(manager, didUpdateLocations: [fix])
    }
}

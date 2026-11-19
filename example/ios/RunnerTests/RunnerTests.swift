import XCTest

final class RunnerTests: XCTestCase {
    func testExampleDeclaresWhenInUseLocationPermission() {
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
        XCTAssertFalse(usage?.isEmpty ?? true)
    }
}

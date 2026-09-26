import XCTest
@testable import MaroonCompass

@MainActor
final class CloudAccountTests: XCTestCase {
    func testUnconfiguredGoogleAccountLeavesLocalModeAvailable() async {
        let account = CloudAccountStore(configuration: nil)
        XCTAssertFalse(account.isConfigured)
        XCTAssertFalse(account.isSignedIn)

        await account.signInWithGoogle()

        XCTAssertFalse(account.isSignedIn)
        XCTAssertFalse(account.isBusy)
        XCTAssertNotNil(account.errorMessage)
    }
}

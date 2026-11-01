import XCTest
@testable import SiliciumUI
import SiliciumShared

@MainActor
final class NavigationTests: XCTestCase {
    private func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "Silicium.NavigationTests.\(UUID().uuidString)")!
        return AppModel(settings: AppSettings(defaults: defaults), historyPath: nil)
    }

    func testSelectingInternalUnitRevealsDieAndLeavingRestoresHardware() {
        let app = model()
        for id in [ComponentID.performanceCores, .efficiencyCores, .gpu, .neuralEngine] {
            app.select(id)
            XCTAssertTrue(app.inspectChip)
            XCTAssertEqual(app.selection, id)
            app.select(.battery)
            XCTAssertFalse(app.inspectChip)
        }
    }

    func testOverviewRestoresNavigationAfterExploration() {
        let app = model()
        app.select(.gpu)
        app.exploded = true
        app.hovered = .memory
        app.setView(.top)
        let previousToken = app.resetCameraToken
        app.showOverview()
        XCTAssertNil(app.selection)
        XCTAssertNil(app.hovered)
        XCTAssertFalse(app.inspectChip)
        XCTAssertFalse(app.exploded)
        XCTAssertEqual(app.cameraPreset, .perspective)
        XCTAssertEqual(app.resetCameraToken, previousToken + 1)
    }

    func testSceneInputCarriesInspectionAndAccessibilityPreference() {
        let app = model()
        app.select(.efficiencyCores)
        let input = SceneInput(model: app, reduceMotion: true)
        XCTAssertTrue(input.inspectChip)
        XCTAssertTrue(input.reduceMotion)
        XCTAssertEqual(input.selection, .efficiencyCores)
    }

    func testSelectingTheSameComponentRequestsReframing() {
        let app = model()
        app.select(.memory)
        let first = SceneInput(model: app, reduceMotion: false)
        app.select(.memory)
        let second = SceneInput(model: app, reduceMotion: false)
        XCTAssertEqual(first.selection, second.selection)
        XCTAssertNotEqual(first.selectionRevision, second.selectionRevision)
    }
}

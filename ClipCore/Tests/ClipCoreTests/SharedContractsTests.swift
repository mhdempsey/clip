import XCTest
@testable import ClipCore

final class SharedContractsTests: XCTestCase {
    func testClipWindowValidationUsesFixedProductValues() {
        for value in [10, 15, 20, 30] {
            XCTAssertEqual(ClipShared.validatedClipWindow(value), value)
        }
        XCTAssertEqual(ClipShared.validatedClipWindow(0), 15)
        XCTAssertEqual(ClipShared.validatedClipWindow(25), 15)
    }

    func testPlaybackRateValidationUsesOneToThreeRange() {
        XCTAssertEqual(ClipShared.validatedPlaybackRate(.nan), 1)
        XCTAssertEqual(ClipShared.validatedPlaybackRate(0), 1)
        XCTAssertEqual(ClipShared.validatedPlaybackRate(2.4), 2.4)
        XCTAssertEqual(ClipShared.validatedPlaybackRate(10), 3)
    }

    func testAudioTimeFormatting() {
        XCTAssertEqual(ClipShared.formattedAudioTime(-2), "0:00")
        XCTAssertEqual(ClipShared.formattedAudioTime(.nan), "0:00")
        XCTAssertEqual(ClipShared.formattedAudioTime(272.4), "4:32")
        XCTAssertEqual(ClipShared.formattedAudioTime(16_338), "4:32:18")
    }

    func testWhisperKitRepositoryVariantMapping() {
        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(for: "large-v3-turbo"),
            "openai_whisper-large-v3_turbo"
        )
        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(for: "large-v3"),
            "openai_whisper-large-v3"
        )
        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(for: "base"),
            "openai_whisper-base"
        )
    }

    func testWhisperKitStandardModelUsesOptimizedTurboWhenSupported() {
        let supported = [
            "openai_whisper-base",
            "openai_whisper-large-v3_turbo",
            "openai_whisper-large-v3_turbo_954MB",
            "openai_whisper-large-v3-v20240930_turbo_632MB",
        ]

        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(
                for: "large-v3-turbo",
                supportedModels: supported
            ),
            "openai_whisper-large-v3-v20240930_turbo_632MB"
        )
    }

    func testWhisperKitStandardModelFallsBackToSupportedLargeV3OnM1() {
        let m1Supported = [
            "openai_whisper-base",
            "openai_whisper-large-v3",
            "openai_whisper-large-v3_947MB",
            "openai_whisper-large-v3-v20240930_626MB",
        ]

        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(
                for: "large-v3-turbo",
                supportedModels: m1Supported
            ),
            "openai_whisper-large-v3-v20240930_626MB"
        )
    }

    func testWhisperKitModelSelectionKeepsExplicitSupportedModels() {
        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(
                for: "large-v3",
                supportedModels: ["openai_whisper-base", "openai_whisper-large-v3"]
            ),
            "openai_whisper-large-v3"
        )
        XCTAssertEqual(
            ClipShared.whisperKitRepositoryVariant(
                for: "base",
                supportedModels: ["openai_whisper-base"]
            ),
            "openai_whisper-base"
        )
    }

    func testTranscriptionProgressCountsTheActiveThirtySecondWindow() {
        XCTAssertEqual(
            ClipShared.transcriptionFraction(
                fileOffset: 0,
                fileDuration: 3_600,
                totalDuration: 3_600,
                activeWindowIndex: 0
            ),
            30.0 / 3_600.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ClipShared.transcriptionFraction(
                fileOffset: 300,
                fileDuration: 600,
                totalDuration: 900,
                activeWindowIndex: 1
            ),
            360.0 / 900.0,
            accuracy: 0.000_001
        )
    }

    func testTranscriptionProgressClampsToTheCurrentFileAndOverallWork() {
        XCTAssertEqual(
            ClipShared.transcriptionFraction(
                fileOffset: 0,
                fileDuration: 10,
                totalDuration: 10,
                activeWindowIndex: 0
            ),
            0.995,
            accuracy: 0.000_001
        )
    }
}

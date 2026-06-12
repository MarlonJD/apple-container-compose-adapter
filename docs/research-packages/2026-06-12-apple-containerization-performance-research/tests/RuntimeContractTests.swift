// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest
@testable import ContainerComposeAdapter

final class RuntimeContractTests: XCTestCase {
    func testNoopDryRunRedactsSecretEnvironmentValues() throws {
        let plan = RuntimePlan(
            project: ProjectName("Demo"),
            services: [
                ServicePlan(
                    name: "api",
                    image: "nginx:alpine",
                    environment: [
                        EnvironmentVariable("API_TOKEN", "super-secret"),
                        EnvironmentVariable("LOG_LEVEL", "debug")
                    ]
                )
            ]
        )

        let result = try NoopDryRunBackend().renderDryRun(command: .up, plan: plan, options: RuntimeOptions())
        let text = result.renderText()

        XCTAssertTrue(text.contains("API_TOKEN=<redacted>"))
        XCTAssertTrue(text.contains("LOG_LEVEL=debug"))
        XCTAssertFalse(text.contains("super-secret"))
        XCTAssertEqual(result.mutatingActionCount, 0)
    }

    func testUnsupportedFeatureDiagnosticsArePreservedInDryRun() throws {
        let diagnostic = Diagnostic.unsupported(
            "services.api.privileged",
            suggestion: "Remove privileged mode for the LinuxPod backend subset."
        )
        let plan = RuntimePlan(
            project: ProjectName("Diagnostics"),
            services: [],
            diagnostics: [diagnostic]
        )

        let result = try NoopDryRunBackend().renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        XCTAssertEqual(result.diagnostics, [diagnostic])
        XCTAssertTrue(result.renderText().contains("unsupported-compose-feature"))
    }

    func testNoopExecuteNeverTouchesRuntime() async throws {
        let plan = RuntimePlan(project: ProjectName("Noop"), services: [])

        do {
            _ = try await NoopDryRunBackend().execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(),
                approval: RuntimeApproval(approved: true, token: "anything")
            )
            XCTFail("Expected no runtime backend to reject execution.")
        } catch let error as RuntimeBackendError {
            XCTAssertEqual(
                error,
                .runtimeUnavailable("NoopDryRunBackend never creates, starts, stops, or deletes runtime resources.")
            )
        }
    }

    func testProjectNamesAreSanitizedForRuntimeResources() {
        let project = ProjectName("My API_Stack!")

        XCTAssertEqual(project.sanitized, "my-api-stack")
        XCTAssertEqual(project.adapterOwnedName(prefix: "cca-linuxpod-"), "cca-linuxpod-my-api-stack")
    }

    func testRuntimeLogCaptureSummarizesStdoutAndStderrForEvidence() {
        let capture = RuntimeLogCapture()

        capture.appendStdout(Data("migrate ok\n".utf8))
        capture.appendStderr(Data("warning: skipped optional seed\n".utf8))

        XCTAssertEqual(
            capture.evidenceMetadata(exitCode: 0, maxPreviewCharacters: 12),
            [
                "exitCode": "0",
                "logs": "captured",
                "stdoutBytes": "11",
                "stderrBytes": "31",
                "stdoutPreview": "migrate ok\n",
                "stderrPreview": "warning: ski..."
            ]
        )
    }

    func testRuntimeLogCaptureTailsKeepTheEndOfEachStream() {
        let capture = RuntimeLogCapture()

        capture.appendStdout(Data("starting db\n".utf8))
        capture.appendStderr(Data("fatal: data directory has wrong ownership\n".utf8))

        XCTAssertEqual(capture.stdoutTail(maxCharacters: 512), "starting db\n")
        XCTAssertEqual(capture.stderrTail(maxCharacters: 10), "...ownership\n")
    }

    func testHostFootprintCriteriaJudgesScalingAttributionAndThreshold() {
        let guestDelta: Int64 = 128 * 1024 * 1024

        let accepted = HostFootprintCriteria.evaluate(
            guestDeltaBytes: guestDelta,
            hostDeltaBytes: 100 * 1024 * 1024,
            systemWide: false
        )
        XCTAssertEqual(accepted.verdict, .accepted)

        let rejected = HostFootprintCriteria.evaluate(
            guestDeltaBytes: guestDelta,
            hostDeltaBytes: 8 * 1024 * 1024,
            systemWide: false
        )
        XCTAssertEqual(rejected.verdict, .rejectedNotScaling)

        let systemWide = HostFootprintCriteria.evaluate(
            guestDeltaBytes: guestDelta,
            hostDeltaBytes: guestDelta,
            systemWide: true
        )
        XCTAssertEqual(systemWide.verdict, .blocked)

        let unsampled = HostFootprintCriteria.evaluate(
            guestDeltaBytes: guestDelta,
            hostDeltaBytes: nil,
            systemWide: false
        )
        XCTAssertEqual(unsampled.verdict, .blocked)

        let inconclusive = HostFootprintCriteria.evaluate(
            guestDeltaBytes: 16 * 1024 * 1024,
            hostDeltaBytes: 16 * 1024 * 1024,
            systemWide: false
        )
        XCTAssertEqual(inconclusive.verdict, .blocked)
    }

    func testPhase6BenchmarkSummaryKeepsHostFootprintBlockedAndCountsFailures() {
        let measured = Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-12T04:00:00Z",
            project: "cca-linuxpod-phase6-backend-001",
            runLabel: "phase6-warm",
            iteration: 1,
            status: .measured,
            durationsSeconds: Phase6BenchmarkDurations(
                up: 12.25,
                status: 0.02,
                logs: 0.03,
                cleanup: 1.5
            ),
            guest: HostFootprintGuestStats(
                cgroupMemoryCurrentBytes: 128 * 1024 * 1024,
                cgroupMemoryLimitBytes: 1024 * 1024 * 1024,
                processCount: 8,
                cpuUsageUsec: 42,
                blockReadBytes: 9 * 1024 * 1024,
                blockWriteBytes: 4 * 1024 * 1024
            ),
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 16,
            cleanupStateDirectoryExistsAfterCleanup: false,
            failure: nil
        )
        let failed = Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-12T04:01:00Z",
            project: "cca-linuxpod-phase6-backend-002",
            runLabel: "phase6-warm",
            iteration: 2,
            status: .failed,
            durationsSeconds: Phase6BenchmarkDurations(up: 2.0, status: nil, logs: nil, cleanup: 0.5),
            guest: nil,
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 0,
            cleanupStateDirectoryExistsAfterCleanup: false,
            failure: "runtime unavailable"
        )

        let summary = Phase6BenchmarkSummaryRecord(
            timestamp: "2026-06-12T04:02:00Z",
            projectPrefix: "phase6-backend",
            runLabel: "phase6-warm",
            requestedIterations: 2,
            records: [measured, failed]
        )

        XCTAssertEqual(measured.schemaVersion, Phase6BenchmarkSchema.version)
        XCTAssertEqual(measured.recordType, Phase6BenchmarkSchema.iterationRecordType)
        XCTAssertEqual(measured.hostPhysicalMemoryStatus, .blocked)
        XCTAssertEqual(summary.recordType, Phase6BenchmarkSchema.summaryRecordType)
        XCTAssertEqual(summary.measuredIterations, 1)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.hostPhysicalMemoryStatus, .blocked)
        XCTAssertEqual(summary.guestCgroupMemoryCurrentP50Bytes, 128 * 1024 * 1024)
        XCTAssertEqual(summary.blockReadP50Bytes, 9 * 1024 * 1024)
        XCTAssertEqual(summary.upDurationP50Seconds, 12.25)
    }

    func testExecutionResultRendersActionMetadataForHumanOutput() {
        let result = ExecutionResult(
            backend: .linuxpod,
            command: .run,
            status: "executed",
            actionResults: [
                RuntimeActionResult(
                    order: 8,
                    kind: .runJob,
                    resourceName: "cca-linuxpod-phase4-backend-migrate",
                    status: "executed",
                    metadata: [
                        "exitCode": "0",
                        "logs": "captured",
                        "stdoutPreview": "migrate ok\n"
                    ]
                )
            ]
        )

        XCTAssertEqual(
            result.renderText(),
            """
            Container Compose Adapter execution
            backend: linuxpod
            command: run
            status: executed
            actions:
            8. runJob [executed] cca-linuxpod-phase4-backend-migrate
               exitCode=0
               logs=captured
               stdoutPreview=migrate ok

            """
        )
    }

    func testVirtualizationEntitlementMissingMessageIncludesSigningRemediation() {
        let message = RuntimePrerequisiteMessages.virtualizationEntitlementMissing

        XCTAssertTrue(message.contains("com.apple.security.virtualization"))
        XCTAssertTrue(message.contains("Virtualization.framework"))
        XCTAssertTrue(message.contains("not plain swift run"))
        XCTAssertTrue(message.contains("scripts/sign-debug-runtime.sh"))
        XCTAssertTrue(message.contains(".build/arm64-apple-macosx/debug/container-compose-adapter"))
    }
}

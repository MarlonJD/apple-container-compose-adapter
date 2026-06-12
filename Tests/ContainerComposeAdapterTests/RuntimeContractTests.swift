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

    func testAppleNativePlannerPreservesCurrentRuntimePlanShape() throws {
        let project = LocalDevProject(
            id: "demo-stack",
            name: "Demo Stack",
            services: [
                LocalDevService(
                    name: "api",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    command: ["python", "app.py"],
                    entrypoint: ["/bin/sh", "-ec"],
                    environment: ["API_TOKEN": "secret-value"],
                    mounts: [
                        LocalDevMount(kind: .namedVolume, source: "api-cache", target: "/cache")
                    ],
                    ports: [
                        LocalDevPort(hostIP: "127.0.0.1", hostPort: 18080, containerPort: 8080)
                    ],
                    dependencies: [
                        LocalDevDependency(target: "migrate", condition: .serviceCompletedSuccessfully)
                    ],
                    healthcheck: LocalDevHealthcheck(test: ["python", "-c", "print('ready')"], timeoutSeconds: 7)
                )
            ],
            jobs: [
                LocalDevJob(
                    name: "migrate",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    command: ["python", "migrate.py"],
                    mounts: [
                        LocalDevMount(kind: .namedVolume, source: "api-cache", target: "/cache")
                    ]
                )
            ],
            volumes: [
                LocalDevVolume(name: "api-cache")
            ]
        )

        let result = AppleNativePlanner().plan(project)

        XCTAssertEqual(result.runtimePlan.project.rawValue, "Demo Stack")
        XCTAssertEqual(result.runtimePlan.volumes, [VolumePlan(name: "api-cache")])
        XCTAssertEqual(result.runtimePlan.services.map(\.name), ["api", "migrate"])
        XCTAssertEqual(result.runtimePlan.services.map(\.kind), [.service, .oneOffJob])
        XCTAssertEqual(result.runtimePlan.services[0].command, ["/bin/sh", "-ec", "python", "app.py"])
        XCTAssertEqual(result.runtimePlan.services[0].ports, [PortMapping(hostPort: 18080, containerPort: 8080)])
        XCTAssertFalse(result.runtimePlan.hasBlockingDiagnostics)
    }

    func testAppleNativePlannerReportsCompatibilityDiagnosticsForPreservedIntent() {
        let project = LocalDevProject(
            id: "compat",
            name: "Compat",
            services: [
                LocalDevService(
                    name: "api",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    envFiles: [".env"],
                    aliases: ["api.local"],
                    restartPolicy: .always
                )
            ],
            jobs: [
                LocalDevJob(
                    name: "seed",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    completionPolicy: .allowFailure
                )
            ],
            networks: [
                LocalDevNetwork(name: "default", aliases: ["api"])
            ],
            routes: [
                LocalDevRoute(name: "api", host: "api.local", targetService: "api", targetPort: 8080)
            ],
            secrets: [
                LocalDevSecret(name: "api-token", environmentKey: "API_TOKEN")
            ],
            configs: [
                LocalDevConfig(name: "api-config", environmentKey: "APP_CONFIG")
            ]
        )

        let result = AppleNativePlanner().plan(project)
        let entries = Dictionary(uniqueKeysWithValues: result.support.entries.map { ($0.feature, $0.status) })
        let codes = Set(result.diagnostics.map(\.code))

        XCTAssertEqual(entries["env files"], .unsupported)
        XCTAssertEqual(entries["routes"], .preservedIntent)
        XCTAssertEqual(entries["network aliases"], .preservedIntent)
        XCTAssertEqual(entries["job allow-failure policy"], .unsupported)
        XCTAssertTrue(codes.contains("unsupported-apple-native-env-file"))
        XCTAssertTrue(codes.contains("preserved-apple-native-route-intent"))
        XCTAssertTrue(codes.contains("preserved-apple-native-secret-intent"))
        XCTAssertTrue(codes.contains("preserved-apple-native-config-intent"))
        XCTAssertTrue(codes.contains("preserved-apple-native-network-intent"))
        XCTAssertTrue(codes.contains("preserved-apple-native-restart-policy"))
        XCTAssertTrue(codes.contains("unsupported-apple-native-job-allow-failure"))
        XCTAssertTrue(result.runtimePlan.hasBlockingDiagnostics)
    }

    func testLocalDevProjectNormalizesServicesJobsAndNamedVolumesToRuntimePlan() throws {
        let project = LocalDevProject(
            id: "demo-stack",
            name: "Demo Stack",
            sourceFiles: ["compose.yaml"],
            services: [
                LocalDevService(
                    name: "api",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    command: ["python", "app.py"],
                    entrypoint: ["/bin/sh", "-ec"],
                    environment: [
                        "API_TOKEN": "secret-value",
                        "LOG_LEVEL": "debug"
                    ],
                    mounts: [
                        LocalDevMount(kind: .bind, source: ".", target: "/workspace", readOnly: true),
                        LocalDevMount(kind: .namedVolume, source: "api-cache", target: "/cache")
                    ],
                    ports: [
                        LocalDevPort(name: "http", hostIP: "127.0.0.1", hostPort: 18080, containerPort: 8080)
                    ],
                    dependencies: [
                        LocalDevDependency(target: "migrate", condition: .serviceCompletedSuccessfully)
                    ],
                    healthcheck: LocalDevHealthcheck(
                        test: ["python", "-c", "print('ready')"],
                        intervalSeconds: 5,
                        timeoutSeconds: 7,
                        retries: 3,
                        startPeriodSeconds: 2
                    ),
                    restartPolicy: .unlessStopped,
                    profiles: ["dev"]
                )
            ],
            jobs: [
                LocalDevJob(
                    name: "migrate",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    command: ["python", "migrate.py"],
                    environment: ["DATABASE_URL": "postgres://app:dev_password@db/app"],
                    mounts: [
                        LocalDevMount(kind: .namedVolume, source: "api-cache", target: "/cache")
                    ],
                    dependencies: [
                        LocalDevDependency(target: "db", condition: .serviceHealthy)
                    ],
                    completionPolicy: .runToCompletion,
                    profiles: ["dev"]
                )
            ],
            volumes: [
                LocalDevVolume(name: "api-cache", kind: .named, preserveByDefault: true)
            ],
            profiles: ["dev"]
        )

        let plan = project.runtimePlan()

        XCTAssertEqual(plan.project.rawValue, "Demo Stack")
        XCTAssertEqual(plan.volumes, [VolumePlan(name: "api-cache", preserveByDefault: true)])
        XCTAssertEqual(plan.services.map(\.name), ["api", "migrate"])
        XCTAssertEqual(plan.services.map(\.kind), [.service, .oneOffJob])
        XCTAssertEqual(
            plan.services[0].environment,
            [
                EnvironmentVariable("API_TOKEN", "secret-value"),
                EnvironmentVariable("LOG_LEVEL", "debug")
            ]
        )
        XCTAssertEqual(plan.services[0].ports, [PortMapping(hostPort: 18080, containerPort: 8080)])
        XCTAssertEqual(
            plan.services[0].mounts,
            [
                MountPlan(kind: .bind, source: ".", target: "/workspace", readOnly: true),
                MountPlan(kind: .namedVolume, source: "api-cache", target: "/cache")
            ]
        )
        XCTAssertEqual(
            plan.services[0].dependencies,
            [ServiceDependency(serviceName: "migrate", condition: .serviceCompletedSuccessfully)]
        )
        XCTAssertEqual(
            plan.services[0].readiness,
            [
                ReadinessProbe(
                    kind: .serviceHealthy,
                    command: ["python", "-c", "print('ready')"],
                    timeoutSeconds: 7
                )
            ]
        )
        XCTAssertEqual(plan.services[1].kind, .oneOffJob)
        XCTAssertEqual(plan.services[1].dependencies, [ServiceDependency(serviceName: "db", condition: .serviceHealthy)])
        XCTAssertFalse(plan.hasBlockingDiagnostics)
    }

    func testLocalDevProjectReportsUnsupportedRuntimeFeaturesDuringNormalization() {
        let project = LocalDevProject(
            id: "unsupported",
            name: "Unsupported",
            services: [
                LocalDevService(
                    name: "api",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    build: LocalDevBuildSpec(context: ".", dockerfile: "Dockerfile"),
                    mounts: [
                        LocalDevMount(kind: .tmpfs, target: "/tmp/cache", sizeBytes: 64 * 1024 * 1024)
                    ]
                )
            ]
        )

        let plan = project.runtimePlan()

        XCTAssertEqual(Set(plan.diagnostics.map(\.code)), [
            "unsupported-localdev-build",
            "unsupported-localdev-tmpfs-mount"
        ])
        XCTAssertTrue(plan.hasBlockingDiagnostics)
        XCTAssertEqual(plan.services.first?.mounts, [])
    }

    func testLocalDevProjectDecodesOlderPayloadWithoutDiagnostics() throws {
        let json = """
        {
          "id": "legacy",
          "name": "Legacy",
          "sourceFiles": [],
          "services": [],
          "jobs": [],
          "volumes": [],
          "networks": [],
          "routes": [],
          "secrets": [],
          "configs": [],
          "profiles": []
        }
        """

        let project = try JSONDecoder().decode(LocalDevProject.self, from: Data(json.utf8))

        XCTAssertEqual(project.id, "legacy")
        XCTAssertEqual(project.diagnostics, [])
    }

    func testLocalDevResourcePolicyRoundTripsThroughServicesAndJobs() throws {
        let resources = LocalDevResourcePolicy(
            cpuLimit: "2",
            memoryLimitBytes: 512 * 1024 * 1024,
            diskLimitBytes: 2 * 1024 * 1024 * 1024
        )
        let project = LocalDevProject(
            id: "resource-demo",
            name: "Resource Demo",
            services: [
                LocalDevService(
                    name: "api",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    resources: resources
                )
            ],
            jobs: [
                LocalDevJob(
                    name: "seed",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    resources: resources
                )
            ]
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(LocalDevProject.self, from: encoded)

        XCTAssertEqual(decoded.services.first?.resources, resources)
        XCTAssertEqual(decoded.jobs.first?.resources, resources)
    }

    func testProjectRuntimeStoreRequiresAdapterOwnedSentinelBeforeCleanup() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-runtime-store-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: root)
        let project = ProjectName("Persistent Demo")
        let projectDirectory = store.projectDirectory(for: project)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertThrowsError(try store.validateAdapterOwnedProjectDirectory(projectDirectory)) { error in
            XCTAssertEqual(
                error as? RuntimeBackendError,
                .runtimeUnavailable("Refusing cleanup for \(projectDirectory.path) because the adapter-owned sentinel is missing.")
            )
        }

        FileManager.default.createFile(atPath: store.projectSentinelURL(for: project).path, contents: Data())

        XCTAssertNoThrow(try store.validateAdapterOwnedProjectDirectory(projectDirectory))
        XCTAssertEqual(store.projectStorageURL(for: project).lastPathComponent, "project-storage.ext4")
        XCTAssertTrue(store.requiredProjectSubdirectories(for: project).map(\.lastPathComponent).contains("ports"))
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
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: "future LinuxPod warm",
                runtimeVersion: "apple/containerization LinuxPod",
                containerizationVersion: "0.26.5",
                appleContainerCLIVersion: "1.0.0",
                macOSVersion: "15.5",
                hostArchitecture: "arm64",
                lifecycle: .warm,
                projectRuntimeExistedBeforeRun: true,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .hit,
                initfsCacheStatus: .hit,
                volumeExistedBeforeRun: true
            ),
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
        XCTAssertEqual(measured.environment?.targetName, "future LinuxPod warm")
        XCTAssertEqual(measured.environment?.coldOrWarm, "warm")
        XCTAssertEqual(measured.environment?.lifecycle, .warm)
        XCTAssertEqual(measured.environment?.rootfsCacheStatus, .hit)
        XCTAssertEqual(summary.recordType, Phase6BenchmarkSchema.summaryRecordType)
        XCTAssertEqual(summary.environment, measured.environment)
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

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

    func testDockerHubOfficialImageMirrorRewritesOfficialImageReferences() {
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "docker.io/library/postgres:16-alpine",
                mirror: "mirror.gcr.io/"
            ),
            "mirror.gcr.io/library/postgres:16-alpine"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "registry-1.docker.io/library/python@sha256:abc123",
                mirror: "mirror.gcr.io"
            ),
            "mirror.gcr.io/library/python@sha256:abc123"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "postgres:16-alpine",
                mirror: "mirror.gcr.io"
            ),
            "mirror.gcr.io/library/postgres:16-alpine"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "ghcr.io/apple/containerization/vminit:0.33.4",
                mirror: "mirror.gcr.io"
            ),
            "ghcr.io/apple/containerization/vminit:0.33.4"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "docker.io/postgres:16-alpine",
                mirror: "mirror.gcr.io/"
            ),
            "mirror.gcr.io/library/postgres:16-alpine"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "registry-1.docker.io/postgres:16-alpine",
                mirror: "mirror.gcr.io"
            ),
            "mirror.gcr.io/library/postgres:16-alpine"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "index.docker.io/postgres@sha256:abc123",
                mirror: "mirror.gcr.io/"
            ),
            "mirror.gcr.io/library/postgres@sha256:abc123"
        )
        XCTAssertEqual(
            DockerHubOfficialImageMirror.rewrite(
                image: "docker.io/myorg/postgres:16-alpine",
                mirror: "mirror.gcr.io"
            ),
            "docker.io/myorg/postgres:16-alpine"
        )
    }

    func testDockerHubOfficialImageMirrorRejectsInvalidMirrorSchemes() {
        XCTAssertEqual(
            try DockerHubOfficialImageMirror.validatedMirror("mirror.gcr.io/"),
            "mirror.gcr.io"
        )
        XCTAssertThrowsError(
            try DockerHubOfficialImageMirror.validatedMirror("https://mirror.gcr.io")
        ) { error in
            XCTAssertTrue("\(error)".contains("without a URL scheme"))
        }
    }

    func testDockerHubOfficialImageMirrorRewritesRuntimePlanServicesOnly() {
        let plan = RuntimePlan(
            project: ProjectName("Mirror Test"),
            services: [
                ServicePlan(name: "db", image: "docker.io/library/postgres:16-alpine"),
                ServicePlan(name: "init", image: "ghcr.io/apple/containerization/vminit:0.33.4")
            ],
            volumes: [VolumePlan(name: "db-data")],
            diagnostics: [
                Diagnostic(severity: .warning, code: "kept", message: "kept")
            ]
        )

        let mirrored = DockerHubOfficialImageMirror.rewrite(plan: plan, mirror: "mirror.gcr.io")

        XCTAssertEqual(mirrored.project, plan.project)
        XCTAssertEqual(mirrored.services.map(\.image), [
            "mirror.gcr.io/library/postgres:16-alpine",
            "ghcr.io/apple/containerization/vminit:0.33.4"
        ])
        XCTAssertEqual(mirrored.volumes, plan.volumes)
        XCTAssertEqual(mirrored.diagnostics, plan.diagnostics)
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

    func testAppleNativePlannerUsesHealthcheckRetryBudgetForReadinessTimeout() {
        let project = LocalDevProject(
            id: "health-budget",
            name: "Health Budget",
            services: [
                LocalDevService(
                    name: "db",
                    image: "docker.io/library/postgres:16-alpine",
                    healthcheck: LocalDevHealthcheck(
                        test: ["pg_isready"],
                        intervalSeconds: 2,
                        timeoutSeconds: 2,
                        retries: 30,
                        startPeriodSeconds: 5
                    )
                )
            ]
        )

        let plan = AppleNativePlanner().plan(project).runtimePlan
        let readiness = plan.services.first?.readiness.first

        XCTAssertEqual(readiness?.kind, .serviceHealthy)
        XCTAssertEqual(readiness?.timeoutSeconds, 67)
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
                    timeoutSeconds: 24
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

    func testProjectRuntimeStoreRejectsProjectsRootAndOutsidePathsForCleanup() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-runtime-store-containment-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: root)
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("outside-cca-runtime-store-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try FileManager.default.createDirectory(at: store.projectsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: store.projectsDirectory.appendingPathComponent(ProjectRuntimeStore.sentinelFileName).path,
            contents: Data()
        )
        FileManager.default.createFile(
            atPath: outside.appendingPathComponent(ProjectRuntimeStore.sentinelFileName).path,
            contents: Data()
        )

        XCTAssertThrowsError(try store.validateAdapterOwnedProjectDirectory(store.projectsDirectory)) { error in
            XCTAssertEqual(
                error as? RuntimeBackendError,
                .runtimeUnavailable("Refusing cleanup for \(store.projectsDirectory.path) because it is not a project directory under \(store.projectsDirectory.path).")
            )
        }
        XCTAssertThrowsError(try store.validateAdapterOwnedProjectDirectory(outside)) { error in
            XCTAssertEqual(
                error as? RuntimeBackendError,
                .runtimeUnavailable("Refusing cleanup for \(outside.path) because it is outside \(store.projectsDirectory.path).")
            )
        }
    }

    func testProjectSessionPlanSeparatesProjectRuntimeStateFromReusableCacheState() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-session-plan-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: root)
        let project = LocalDevProject(
            id: "demo-stack",
            name: "Demo Display",
            services: [
                LocalDevService(name: "api", image: "mirror.gcr.io/library/python:3.12-alpine")
            ],
            volumes: [
                LocalDevVolume(name: "db-data")
            ]
        )

        let session = ProjectSessionManager(store: store).planSession(for: project)

        XCTAssertEqual(session.lifecycle, .persistentLinuxPod)
        XCTAssertEqual(session.localDevProjectID, "demo-stack")
        XCTAssertEqual(session.runtimeResourceName, "cca-linuxpod-demo-stack")
        XCTAssertTrue(session.paths.projectDirectory.hasSuffix("/projects/demo-stack"))
        XCTAssertTrue(session.paths.sentinelFile.hasSuffix("/projects/demo-stack/.container-compose-adapter-owned"))
        XCTAssertTrue(session.paths.projectStorageFile.hasSuffix("/projects/demo-stack/project-storage.ext4"))
        XCTAssertTrue(session.paths.runtimeStateDirectories.values.allSatisfy { path in
            path.hasPrefix(session.paths.projectDirectory + "/")
        })
        XCTAssertTrue(session.paths.reusableCacheDirectories.values.allSatisfy { path in
            path.hasPrefix(store.cacheDirectory.path + "/")
        })
        XCTAssertFalse(session.paths.reusableCacheDirectories.values.contains { path in
            path.hasPrefix(session.paths.projectDirectory + "/")
        })
        XCTAssertEqual(session.paths.volumeDirectories["db-data"], session.paths.projectDirectory + "/volumes/db-data")
        XCTAssertTrue(store.isProjectRuntimePath(URL(fileURLWithPath: session.paths.runtimeStateDirectories["logs"] ?? "")))
        XCTAssertFalse(store.isProjectRuntimePath(store.cacheDirectory))
        XCTAssertTrue(store.isReusableCachePath(store.rootfsCacheURL(imageReference: "mirror.gcr.io/library/python:3.12-alpine")))
        XCTAssertFalse(store.isReusableCachePath(URL(fileURLWithPath: session.paths.volumeDirectories["db-data"] ?? "")))
    }

    func testDryRunCleanupProofCoversRuntimeVolumesPortsLogsMetricsAndCache() throws {
        let dryRun = try LinuxPodBackend().renderDryRun(
            command: .down,
            plan: SamplePlans.publicImageSmoke(project: ProjectName("Cleanup Proof")),
            options: RuntimeOptions(includeVolumes: true)
        )

        let evidence = DryRunEvidenceRecord(timestamp: "2026-06-12T00:00:00.000Z", dryRun: dryRun)

        XCTAssertEqual(evidence.cleanupProof.runtimeMutation, "not-run")
        XCTAssertEqual(evidence.cleanupProof.runtimeCleanup, "planned-only")
        XCTAssertEqual(evidence.cleanupProof.volumeCleanup, "planned-only")
        XCTAssertEqual(evidence.cleanupProof.portCleanup, "planned-release")
        XCTAssertEqual(evidence.cleanupProof.logCleanup, "planned-runtime-state-cleanup")
        XCTAssertEqual(evidence.cleanupProof.metricsCleanup, "planned-runtime-state-cleanup")
        XCTAssertEqual(evidence.cleanupProof.cacheCleanup, "preserved")
        XCTAssertEqual(evidence.cleanupProof.globalCleanup, "not-run")
        XCTAssertTrue(evidence.cleanupProof.renderText().contains("cache cleanup: preserved"))
    }

    func testProjectSessionDryRunPlanningDoesNotCreateRuntimeOrCacheDirectories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-session-dry-run-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: root)
        let project = LocalDevProject(
            id: "dry-run",
            name: "Dry Run",
            services: [
                LocalDevService(name: "web", image: "mirror.gcr.io/library/nginx:alpine")
            ]
        )
        let session = ProjectSessionManager(store: store).planSession(for: project)
        let backend = LinuxPodBackend(
            stateStore: LinuxPodStateStore(root: root.appendingPathComponent("legacy-linuxpod-state", isDirectory: true))
        )

        let dryRun = try backend.renderDryRun(
            command: .up,
            plan: AppleNativePlanner().plan(project).runtimePlan,
            options: RuntimeOptions()
        )
        let evidence = DryRunEvidenceRecord(timestamp: "2026-06-12T00:00:00.000Z", dryRun: dryRun)

        XCTAssertTrue(dryRun.approvalRequired)
        XCTAssertGreaterThan(dryRun.mutatingActionCount, 0)
        XCTAssertEqual(evidence.status, "planned-dry-run-no-runtime-mutation")
        XCTAssertEqual(evidence.cleanupProof.runtimeMutation, "not-run")
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.paths.projectDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.paths.reusableCacheDirectories["rootfs-by-digest"] ?? ""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
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
            runLabel: "phase6-seeded-image-store",
            iteration: 1,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: "LinuxPod image-store-seeded fresh runtime",
                runtimeVersion: "apple/containerization LinuxPod",
                containerizationVersion: "0.26.5",
                appleContainerCLIVersion: "1.0.0",
                macOSVersion: "15.5",
                hostArchitecture: "arm64",
                lifecycle: .imageStoreSeededFreshRuntime,
                seedImageStoreRequested: true,
                seedImageStoreCopied: true,
                seedImageStoreValidated: true,
                seedImageStorePath: ".container-compose-adapter/benchmark-seed-image-stores/stage6-arm64",
                projectRuntimeDirectoryExistedBeforeSeed: false,
                projectRuntimeDirectoryExistedBeforeRun: true,
                podExistedBeforeRun: false,
                imageCacheStatus: .verifiedHit,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .miss,
                volumeExistedBeforeRun: false,
                hostPortPublishingNotImplemented: true
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
            runLabel: "phase6-seeded-image-store",
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
            runLabel: "phase6-seeded-image-store",
            requestedIterations: 2,
            records: [measured, failed]
        )

        XCTAssertEqual(measured.schemaVersion, Phase6BenchmarkSchema.version)
        XCTAssertEqual(measured.recordType, Phase6BenchmarkSchema.iterationRecordType)
        XCTAssertEqual(measured.hostPhysicalMemoryStatus, .blocked)
        XCTAssertEqual(measured.environment?.targetName, "LinuxPod image-store-seeded fresh runtime")
        XCTAssertEqual(measured.environment?.coldOrWarm, "image-store-seeded-fresh-runtime")
        XCTAssertEqual(measured.environment?.lifecycleMode, "image-store-seeded-fresh-runtime")
        XCTAssertEqual(measured.environment?.lifecycle, .imageStoreSeededFreshRuntime)
        XCTAssertEqual(measured.environment?.projectRuntimeDirectoryExistedBeforeSeed, false)
        XCTAssertEqual(measured.environment?.projectRuntimeDirectoryExistedBeforeRun, true)
        XCTAssertEqual(measured.environment?.podExistedBeforeRun, false)
        XCTAssertEqual(measured.environment?.imageCacheStatus, .verifiedHit)
        XCTAssertEqual(measured.environment?.rootfsCacheStatus, .miss)
        XCTAssertEqual(measured.environment?.hostPortPublishingNotImplemented, true)
        XCTAssertEqual(summary.recordType, Phase6BenchmarkSchema.summaryRecordType)
        XCTAssertEqual(summary.environment, measured.environment)
        XCTAssertEqual(summary.measuredIterations, 1)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.hostPhysicalMemoryStatus, .blocked)
        XCTAssertEqual(summary.guestCgroupMemoryCurrentP50Bytes, 128 * 1024 * 1024)
        XCTAssertEqual(summary.blockReadP50Bytes, 9 * 1024 * 1024)
        XCTAssertEqual(summary.upDurationP50Seconds, 12.25)
        XCTAssertEqual(summary.lifecycleMode, "image-store-seeded-fresh-runtime")
        XCTAssertEqual(summary.statusTimingMeaning, "control-plane-local-state")
        XCTAssertEqual(summary.logsTimingMeaning, "control-plane-no-op")
        XCTAssertEqual(summary.hostPortProbeStatus, "notMeasured")
    }

    func testPhase6BenchmarkOptionsParseSeedSafetyAndLifecycleNaming() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "stage6.jsonl",
            "--approval-token", "token",
            "--lifecycle", "image-store-seeded-fresh-runtime",
            "--seed-image-store", ".container-compose-adapter/benchmark-seed-image-stores/stage6-arm64",
            "--docker-hub-mirror", "mirror.gcr.io/"
        ])

        XCTAssertEqual(options.lifecycle, .imageStoreSeededFreshRuntime)
        XCTAssertEqual(options.seedImageStore, ".container-compose-adapter/benchmark-seed-image-stores/stage6-arm64")
        XCTAssertEqual(options.dockerHubMirror, "mirror.gcr.io")
        XCTAssertFalse(options.allowExternalSeedImageStore)

        XCTAssertThrowsError(
            try Phase6BenchmarkOptions.parse([
                "--evidence-jsonl", "stage6.jsonl",
                "--approval-token", "token",
                "--seed-image-store", "/tmp/external-seed"
            ])
        ) { error in
            XCTAssertTrue("\(error)".contains("outside adapter-owned benchmark seed cache"))
        }

        let external = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "stage6.jsonl",
            "--approval-token", "token",
            "--seed-image-store", "/tmp/external-seed",
            "--allow-external-seed-image-store"
        ])
        XCTAssertTrue(external.allowExternalSeedImageStore)
    }

    func testStage8LifecycleModesClassifyAThroughG() {
        let cases: [(BenchmarkLifecycleMode, BenchmarkRunMetadata)] = [
            (
                .coldRuntime,
                benchmarkMetadata(
                    lifecycle: .cold,
                    imageCacheStatus: .miss,
                    rootfsCacheStatus: .miss,
                    initfsCacheStatus: .miss
                )
            ),
            (
                .imageStoreSeededFreshRuntime,
                benchmarkMetadata(
                    lifecycle: .imageStoreSeededFreshRuntime,
                    seedImageStoreCopied: true,
                    imageCacheStatus: .verifiedHit,
                    rootfsCacheStatus: .miss,
                    initfsCacheStatus: .miss
                )
            ),
            (
                .rootfsCacheHitRuntime,
                benchmarkMetadata(
                    lifecycle: .persistentWarmProjectRuntime,
                    imageCacheStatus: .hit,
                    rootfsCacheStatus: .hit,
                    initfsCacheStatus: .miss
                )
            ),
            (
                .initfsCacheHitRuntime,
                benchmarkMetadata(
                    lifecycle: .persistentWarmProjectRuntime,
                    imageCacheStatus: .hit,
                    rootfsCacheStatus: .miss,
                    initfsCacheStatus: .hit
                )
            ),
            (
                .warmPreservedVolume,
                benchmarkMetadata(
                    lifecycle: .persistentWarmProjectRuntime,
                    imageCacheStatus: .hit,
                    rootfsCacheStatus: .miss,
                    initfsCacheStatus: .miss,
                    volumeExistedBeforeRun: true
                )
            ),
            (
                .persistentPodHotplug,
                benchmarkMetadata(
                    lifecycle: .persistentWarmProjectRuntime,
                    imageCacheStatus: .hit,
                    rootfsCacheStatus: .hit,
                    initfsCacheStatus: .miss,
                    podExistedBeforeRun: true
                )
            ),
            (
                .allWarmProjectRuntime,
                benchmarkMetadata(
                    lifecycle: .persistentWarmProjectRuntime,
                    imageCacheStatus: .hit,
                    rootfsCacheStatus: .hit,
                    initfsCacheStatus: .hit,
                    volumeExistedBeforeRun: true,
                    podExistedBeforeRun: true
                )
            )
        ]

        for (expectedMode, metadata) in cases {
            XCTAssertEqual(metadata.lifecycleModeID, expectedMode.id)
            XCTAssertEqual(metadata.lifecycleMode, expectedMode.rawValue)
        }
    }

    func testStage8BenchmarkOptionsParseExplicitLifecycleMode() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "stage8.jsonl",
            "--approval-token", "token",
            "--lifecycle-mode", "rootfs-cache-hit-runtime"
        ])

        XCTAssertEqual(options.lifecycleMode, .rootfsCacheHitRuntime)
        XCTAssertEqual(options.lifecycle, .persistentWarmProjectRuntime)
        XCTAssertEqual(options.effectiveLifecycleMode, .rootfsCacheHitRuntime)
    }

    func testStage8AllWarmBenchmarkPolicyReusesProjectUntilFinalCleanup() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "stage8.jsonl",
            "--approval-token", "token",
            "--project-prefix", "stage8",
            "--run-label", "all-warm",
            "--lifecycle-mode", "all-warm-project-runtime"
        ])

        XCTAssertEqual(options.projectName(forIteration: 1), "stage8-all-warm-shared")
        XCTAssertEqual(options.projectName(forIteration: 2), "stage8-all-warm-shared")
        XCTAssertEqual(options.cleanupPolicy(isFinalIteration: false), .preserveProjectRuntime)
        XCTAssertEqual(options.cleanupPolicy(isFinalIteration: true), .fullProjectAndVolumes)

        var warmVolume = options
        warmVolume.lifecycleMode = .warmPreservedVolume
        XCTAssertEqual(warmVolume.cleanupPolicy(isFinalIteration: false), .preserveVolumes)
        XCTAssertEqual(warmVolume.cleanupPolicy(isFinalIteration: true), .fullProjectAndVolumes)
    }

    func testStage8WarmLifecycleModesDeclareUnrecordedPrimerPolicy() throws {
        var options = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "stage8.jsonl",
            "--approval-token", "token"
        ])

        XCTAssertEqual(options.warmStatePrimerPolicy, .none)

        options.lifecycleMode = .warmPreservedVolume
        XCTAssertEqual(options.warmStatePrimerPolicy, .preservedVolume)

        options.lifecycleMode = .persistentPodHotplug
        XCTAssertEqual(options.warmStatePrimerPolicy, .emptyPersistentPod)

        options.lifecycleMode = .allWarmProjectRuntime
        XCTAssertEqual(options.warmStatePrimerPolicy, .allWarmProjectRuntime)
    }

    func testStage9BHotplugProbeOptionsParseDiagnosticHarnessMode() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--stage9b-hotplug-probe",
            "--evidence-jsonl", "stage9b.jsonl",
            "--approval-token", "token",
            "--project-prefix", "stage9b",
            "--run-label", "hotplug-capability",
            "--docker-hub-mirror", "mirror.gcr.io/"
        ])

        XCTAssertTrue(options.stage9BHotplugProbe)
        XCTAssertEqual(options.projectName(forIteration: 1), "stage9b-hotplug-capability-001")
        XCTAssertEqual(options.dockerHubMirror, "mirror.gcr.io")
        XCTAssertEqual(options.warmStatePrimerPolicy, .none)
    }

    func testStage9BHotplugProbeRuntimeResourceSuffixesStayBelowLinuxPodIDLimit() {
        let projectPrefix = "s9b0334"
        let runLabel = "hp"
        let maxLinuxPodIDLength = 64

        for (sequence, probeCase) in Stage9BHotplugProbeCase.allCases.enumerated() where probeCase != .cleanupProof {
            let project = ProjectName("\(projectPrefix)-\(runLabel)-\(String(format: "%02d", sequence + 1))-\(probeCase.runtimeResourceSuffix)")
            let resourceName = project.adapterOwnedName(prefix: LinuxPodStateStore.ownedPrefix)

            XCTAssertLessThanOrEqual(resourceName.count, maxLinuxPodIDLength, probeCase.rawValue)
            XCTAssertLessThanOrEqual("\(resourceName)-initial".count, maxLinuxPodIDLength, probeCase.rawValue)
            XCTAssertLessThanOrEqual("\(resourceName)-second".count, maxLinuxPodIDLength, probeCase.rawValue)
        }
    }

    func testStage9DHotplugProviderProbeOptionsParseDiagnosticHarnessMode() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--stage9d-hotplug-provider-probe",
            "--evidence-jsonl", "stage9d.jsonl",
            "--approval-token", "token",
            "--project-prefix", "stage9d",
            "--run-label", "hotplug-provider",
            "--docker-hub-mirror", "mirror.gcr.io/"
        ])

        XCTAssertFalse(options.stage9BHotplugProbe)
        XCTAssertTrue(options.stage9DHotplugProviderProbe)
        XCTAssertEqual(options.projectName(forIteration: 1), "stage9d-hotplug-provider-001")
        XCTAssertEqual(options.dockerHubMirror, "mirror.gcr.io")

        let normal = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "normal.jsonl",
            "--approval-token", "token"
        ])
        XCTAssertFalse(normal.stage9DHotplugProviderProbe)
    }

    func testStage10ARootfsMaterializationProbeOptionsParseDiagnosticHarnessMode() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--stage10a-rootfs-materialization-probe",
            "--rootfs-materialization-strategy", "clonefile",
            "--evidence-jsonl", "stage10a.jsonl",
            "--approval-token", "token",
            "--project-prefix", "stage10a",
            "--run-label", "rootfs-materialization",
            "--docker-hub-mirror", "mirror.gcr.io/"
        ])

        XCTAssertTrue(options.stage10ARootfsMaterializationProbe)
        XCTAssertEqual(options.rootfsMaterializationStrategy, .clonefile)
        XCTAssertFalse(options.stage9BHotplugProbe)
        XCTAssertFalse(options.stage9DHotplugProviderProbe)
        XCTAssertEqual(options.dockerHubMirror, "mirror.gcr.io")

        let normal = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "normal.jsonl",
            "--approval-token", "token"
        ])
        XCTAssertFalse(normal.stage10ARootfsMaterializationProbe)
        XCTAssertEqual(normal.rootfsMaterializationStrategy, .fullCopy)
    }

    func testStage10ARootfsMaterializationProbeRejectsInvalidStrategyAndProbeMixing() throws {
        XCTAssertThrowsError(
            try Phase6BenchmarkOptions.parse([
                "--stage10a-rootfs-materialization-probe",
                "--rootfs-materialization-strategy", "teleport",
                "--evidence-jsonl", "stage10a.jsonl",
                "--approval-token", "token"
            ])
        ) { error in
            XCTAssertTrue("\(error)".contains("--rootfs-materialization-strategy"))
        }

        XCTAssertThrowsError(
            try Phase6BenchmarkOptions.parse([
                "--stage9d-hotplug-provider-probe",
                "--stage10a-rootfs-materialization-probe",
                "--evidence-jsonl", "mixed.jsonl",
                "--approval-token", "token"
            ])
        ) { error in
            XCTAssertTrue("\(error)".contains("Choose only one diagnostic probe"))
        }
    }

    func testStage10BRuntimeComparisonOptionsStayGuardedAndNonDefault() throws {
        let options = try Phase6BenchmarkOptions.parse([
            "--stage10b-runtime-comparison",
            "--rootfs-materialization-strategy", "clonefile",
            "--evidence-jsonl", "stage10b.jsonl",
            "--approval-token", "token",
            "--project-prefix", "stage10b",
            "--run-label", "runtime",
            "--docker-hub-mirror", "mirror.gcr.io/"
        ])

        XCTAssertTrue(options.stage10BRuntimeComparison)
        XCTAssertEqual(options.rootfsMaterializationStrategy, .clonefile)
        XCTAssertFalse(options.stage10ARootfsMaterializationProbe)
        XCTAssertEqual(options.projectName(forIteration: 1), "stage10b-runtime-001")
        XCTAssertEqual(RuntimeOptions().rootfsMaterializationStrategyOverride, nil)

        let defaultCandidate = try Phase6BenchmarkOptions.parse([
            "--stage10b-runtime-comparison",
            "--evidence-jsonl", "stage10b.jsonl",
            "--approval-token", "token"
        ])
        XCTAssertEqual(defaultCandidate.rootfsMaterializationStrategy, .fullCopy)

        let normal = try Phase6BenchmarkOptions.parse([
            "--evidence-jsonl", "normal.jsonl",
            "--approval-token", "token"
        ])
        XCTAssertFalse(normal.stage10BRuntimeComparison)
        XCTAssertEqual(normal.rootfsMaterializationStrategy, .fullCopy)

        XCTAssertThrowsError(
            try Phase6BenchmarkOptions.parse([
                "--stage10b-runtime-comparison",
                "--stage10a-rootfs-materialization-probe",
                "--evidence-jsonl", "mixed.jsonl",
                "--approval-token", "token"
            ])
        ) { error in
            XCTAssertTrue("\(error)".contains("Choose only one diagnostic probe"))
        }

        XCTAssertThrowsError(
            try Phase6BenchmarkOptions.parse([
                "--stage10b-runtime-comparison",
                "--rootfs-materialization-strategy", "apfsClone",
                "--evidence-jsonl", "stage10b.jsonl",
                "--approval-token", "token"
            ])
        ) { error in
            XCTAssertTrue("\(error)".contains("--stage10b-runtime-comparison supports only"))
        }
    }

    func testStage10BRuntimeComparisonValidatorRequiresMeasuredComparisonAndNoUnmeasuredGatePass() {
        let fullCopyRecord = stage10BIteration(
            requestedStrategy: .fullCopy,
            runLabel: "stage10b-fullcopy",
            upDuration: 100,
            readinessDuration: 60,
            rootfsPreparation: [.completeTestBreakdown],
            rootfsWorkAvoided: .false
        )
        let clonefileRecord = stage10BIteration(
            requestedStrategy: .clonefile,
            runLabel: "stage10b-clonefile",
            upDuration: 60,
            readinessDuration: 58,
            rootfsPreparation: [.clonefileTestBreakdown],
            rootfsWorkAvoided: .true
        )
        let fullCopySummary = stage10BStrategySummary(
            requestedStrategy: .fullCopy,
            observedStrategies: [.copy],
            upDuration: 100,
            readinessDuration: 60,
            rootfsWorkAvoided: .false
        )
        let clonefileSummary = stage10BStrategySummary(
            requestedStrategy: .clonefile,
            observedStrategies: [.clonefile],
            upDuration: 60,
            readinessDuration: 58,
            rootfsWorkAvoided: .true
        )
        let comparison = Stage10BRuntimeComparisonRecord(
            timestamp: "2026-06-13T14:20:00Z",
            fullCopy: fullCopySummary,
            cloneCandidate: clonefileSummary
        )

        XCTAssertEqual(comparison.recommendation, .recommendStage10CRepeatedWarmBenchmark)
        XCTAssertEqual(
            Stage10BRuntimeComparisonEvidenceValidator().validate(
                records: [fullCopyRecord, clonefileRecord],
                comparison: comparison
            ),
            []
        )

        let unmeasuredGatePass = Stage10BRuntimeComparisonRecord(
            timestamp: "2026-06-13T14:21:00Z",
            fullCopy: fullCopySummary,
            cloneCandidate: clonefileSummary,
            dockerOrOrbStackGateMeasured: false,
            dockerOrOrbStackGatePassed: true
        )
        XCTAssertEqual(
            Set(
                Stage10BRuntimeComparisonEvidenceValidator().validate(
                    records: [fullCopyRecord, clonefileRecord],
                    comparison: unmeasuredGatePass
                ).map(\.code)
            ),
            ["stage10b-docker-orbstack-gate-unmeasured"]
        )

        let missingJobMetrics = Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-13T14:22:00Z",
            project: "cca-linuxpod-stage10b-missing",
            runLabel: "stage10b-missing",
            iteration: 1,
            environment: benchmarkMetadata(
                lifecycle: .persistentWarmProjectRuntime,
                lifecycleMode: .rootfsCacheHitRuntime,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .hit,
                initfsCacheStatus: .hit
            ),
            status: .measured,
            durationsSeconds: Phase6BenchmarkDurations(
                up: 10,
                status: 0.02,
                logs: 0.01,
                cleanup: 0.2,
                rootfsPrep: 0.1,
                healthcheck: 0.5
            ),
            guest: HostFootprintGuestStats(
                cgroupMemoryCurrentBytes: 128 * 1024 * 1024,
                cgroupMemoryLimitBytes: nil,
                cgroupMemoryLimitUnlimited: true,
                processCount: 7,
                cpuUsageUsec: 500,
                blockReadBytes: 2048,
                blockWriteBytes: 4096,
                processRSSBytes: 64 * 1024 * 1024
            ),
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 16,
            cleanupStateDirectoryExistsAfterCleanup: false,
            healthcheckAttempts: 1,
            dataFootprintBytes: 32 * 1024 * 1024,
            failure: nil,
            rootfsPreparation: [.completeTestBreakdown],
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )
        XCTAssertTrue(
            Stage10BRuntimeComparisonEvidenceValidator().validate(
                records: [missingJobMetrics],
                comparison: comparison
            ).map(\.code).contains("stage10b-job-metrics-missing")
        )
    }

    func testStage9DHotplugProviderProbeRuntimeResourceNamesStayBelowLinuxPodIDLimit() {
        let projectPrefix = "stage9d"
        let runLabel = "stage9d-hotplug-provider-feasibility"
        let project = Stage9DHotplugProviderProbeRuntimeNames.ownedProjectResourceName(
            projectPrefix: projectPrefix,
            runLabel: runLabel
        )

        XCTAssertLessThanOrEqual(project.count, Stage9DHotplugProviderProbeRuntimeNames.linuxPodIDMaximumLength, runLabel)
        XCTAssertLessThanOrEqual(
            Stage9DHotplugProviderProbeRuntimeNames.initialContainerID(projectResource: project).count,
            Stage9DHotplugProviderProbeRuntimeNames.linuxPodIDMaximumLength,
            runLabel
        )
        XCTAssertLessThanOrEqual(
            Stage9DHotplugProviderProbeRuntimeNames.secondContainerID(projectResource: project).count,
            Stage9DHotplugProviderProbeRuntimeNames.linuxPodIDMaximumLength,
            runLabel
        )
        XCTAssertGreaterThan(
            ProjectName("\(projectPrefix)-\(runLabel)-provider").adapterOwnedName(prefix: LinuxPodStateStore.ownedPrefix).count,
            Stage9DHotplugProviderProbeRuntimeNames.linuxPodIDMaximumLength,
            "This assertion documents why Stage 9D does not include the human run label in LinuxPod IDs."
        )
    }

    func testStage9DSchemaValidatesProviderInstallOnlyEvidence() {
        let record = stage9DProbeRecord(
            probeCases: [.providerInstallOnly],
            provider: .installedOnly,
            rootfs: .notAttempted,
            hotplug: .notAttempted,
            interpretation: .providerSpikeNeedsMoreWork
        )

        XCTAssertEqual(Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [record]), [])
    }

    func testStage9DSchemaValidatesProviderCalledButRealHotplugFailedEvidence() {
        let record = stage9DProbeRecord(
            probeCases: [.providerInstallOnly, .providerReceivesHotplug],
            status: .failed,
            provider: .called,
            rootfs: .blockAttachUnsupported,
            hotplug: .providerCalledButNotAttached,
            interpretation: .publicBlockHotplugAPIMissing
        )

        XCTAssertEqual(Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [record]), [])
    }

    func testStage9DSchemaValidatesRealHotplugSuccessEvidenceShape() {
        let record = stage9DProbeRecord(
            probeCases: [.providerInstallOnly, .providerReceivesHotplug, .realSecondContainerHotplug],
            provider: .called,
            rootfs: .publicBlockAttached,
            hotplug: .realSecondContainerStarted,
            interpretation: .hotplugAvailable
        )

        XCTAssertEqual(Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [record]), [])
    }

    func testStage9DValidatorRejectsFakeAttachedFilesystemSuccess() {
        let fake = stage9DProbeRecord(
            probeCases: [.providerInstallOnly, .providerReceivesHotplug, .realSecondContainerHotplug],
            provider: .called,
            rootfs: .fakeAttachedFilesystem,
            hotplug: .realSecondContainerStarted,
            interpretation: .hotplugAvailable
        )

        XCTAssertEqual(
            Set(Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [fake]).map(\.code)),
            [
                "stage9d-fake-attached-filesystem",
                "stage9d-real-hotplug-success-unsafe"
            ]
        )
    }

    func testStage9DValidatorRejectsUnsafeProductAvailabilityClaim() {
        let unsafe = stage9DProbeRecord(
            probeCases: [.providerInstallOnly, .providerReceivesHotplug],
            status: .failed,
            provider: .called,
            rootfs: .blockAttachUnsupported,
            hotplug: .providerCalledButNotAttached,
            interpretation: Stage9DInterpretationEvidence(
                productHotplugAvailable: true,
                productShouldDependOnHotplug: true,
                nextRecommendedPath: .forcedWarmServiceRecreateWithHotplug
            )
        )

        XCTAssertEqual(
            Set(Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [unsafe]).map(\.code)),
            [
                "stage9d-product-availability-unsafe",
                "stage9d-product-dependency-unsafe"
            ]
        )
    }

    func testStage9DValidatorRequiresNotMeasuredHostPortAndLoadWindowGaps() {
        let invalid = stage9DProbeRecord(
            probeCases: [.providerInstallOnly],
            provider: .installedOnly,
            rootfs: .notAttempted,
            hotplug: .notAttempted,
            interpretation: .providerSpikeNeedsMoreWork,
            hostPortProbeStatus: "missing",
            loadWindowStatus: "missing"
        )

        XCTAssertEqual(
            Set(Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [invalid]).map(\.code)),
            [
                "stage9d-host-port-not-measured-missing",
                "stage9d-load-window-not-measured-missing"
            ]
        )
    }

    func testStage10AEvidenceSchemaValidatesFullCopyCloneFallbackAndUnsupportedRecords() {
        let fullCopy = stage10AProbeRecord(strategy: .fullCopy)
        XCTAssertEqual(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [fullCopy]), [])

        let cloneSuccess = stage10AProbeRecord(strategy: .cloneSuccess)
        XCTAssertEqual(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [cloneSuccess]), [])

        let fallback = stage10AProbeRecord(strategy: .cloneFallback)
        XCTAssertEqual(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [fallback]), [])

        let unsupported = stage10AProbeRecord(status: .unsupported, strategy: .unsupportedClone)
        XCTAssertEqual(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [unsupported]), [])
    }

    func testStage10AEvidenceValidatorRejectsUnsafeProductReadyClaims() {
        let dirtyCleanup = stage10AProbeRecord(
            strategy: .cloneSuccess,
            cleanup: RootfsMaterializationCleanupEvidence(
                cleanupResult: "leftovers",
                cleanupStateDirectoryExistsAfterCleanup: true,
                leftoverPathsCount: 1,
                zeroAdapterOwnedLeftovers: false
            ),
            interpretation: .productReadyFixture
        )
        let noWorkAvoided = stage10AProbeRecord(
            strategy: .fullCopy,
            interpretation: .productReadyFixture
        )
        let unknownCloneVerification = stage10AProbeRecord(
            strategy: .cloneSuccessWithUnknownVerification,
            interpretation: .productReadyFixture
        )

        XCTAssertEqual(
            Set(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [dirtyCleanup]).map(\.code)),
            ["stage10a-product-ready-cleanup-unsafe"]
        )
        XCTAssertEqual(
            Set(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [noWorkAvoided]).map(\.code)),
            ["stage10a-product-ready-work-not-avoided"]
        )
        XCTAssertEqual(
            Set(Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: [unknownCloneVerification]).map(\.code)),
            ["stage10a-product-ready-clone-verification-unknown"]
        )
    }

    func testStage10AMaterializerFullCopyCreatesDestinationAndDoesNotMutateSource() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage10a-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".container-compose-adapter", isDirectory: true)
        let source = root
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("source.ext4")
        let destination = root
            .appendingPathComponent("cca-linuxpod-stage10a-probe", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("rootfs", isDirectory: true)
            .appendingPathComponent("project.ext4")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sourceBytes = Data("stage10a-rootfs".utf8)
        try sourceBytes.write(to: source)

        let result = try await RootfsMaterializer().materialize(
            source: source,
            destination: destination,
            strategy: .fullCopy,
            context: RootfsMaterializationContext(
                adapterOwnedRoot: root,
                phase: .cachedBaseToProjectRootfs
            )
        )

        XCTAssertEqual(result.requestedStrategy, .fullCopy)
        XCTAssertEqual(result.actualStrategy, .fullCopy)
        XCTAssertTrue(result.copyAttempted)
        XCTAssertTrue(result.copySucceeded)
        XCTAssertFalse(result.cloneSucceeded)
        XCTAssertEqual(result.byteForByteCopyAvoided, .false)
        XCTAssertEqual(result.rootfsWorkAvoided, .false)
        XCTAssertEqual(try Data(contentsOf: destination), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    }

    func testStage10AMaterializerRejectsNonAdapterOwnedDestination() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage10a-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".container-compose-adapter", isDirectory: true)
        let source = root.appendingPathComponent("cache/source.ext4")
        let destination = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("outside-stage10a.ext4")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stage10a-rootfs".utf8).write(to: source)

        do {
            _ = try await RootfsMaterializer().materialize(
                source: source,
                destination: destination,
                strategy: .fullCopy,
                context: RootfsMaterializationContext(
                    adapterOwnedRoot: root,
                    phase: .cachedBaseToProjectRootfs
                )
            )
            XCTFail("Expected materializer to reject a non-adapter-owned destination.")
        } catch let error as RootfsMaterializationError {
            XCTAssertEqual(error, .destinationOutsideAdapterOwnedRoot(destination.path, root.path))
        }
    }

    func testStage10AMaterializerCloneStrategyFallsBackSafelyWhenCloneIsUnsupported() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage10a-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".container-compose-adapter", isDirectory: true)
        let source = root.appendingPathComponent("cache/source.ext4")
        let destination = root.appendingPathComponent("cca-linuxpod-stage10a-probe/runtime/rootfs/project.ext4")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stage10a-rootfs".utf8).write(to: source)

        let result = try await RootfsMaterializer().materialize(
            source: source,
            destination: destination,
            strategy: .clonefile,
            context: RootfsMaterializationContext(
                adapterOwnedRoot: root,
                phase: .cachedBaseToProjectRootfs,
                publicCloneAPIsAvailable: false
            )
        )

        XCTAssertEqual(result.requestedStrategy, .clonefile)
        XCTAssertFalse(result.cloneSupported)
        XCTAssertFalse(result.cloneAttempted)
        XCTAssertEqual(result.actualStrategy, .fullCopy)
        XCTAssertEqual(result.fallbackStrategy, .fullCopy)
        XCTAssertTrue(result.fallbackReason?.contains("public clone API unavailable") == true)
        XCTAssertTrue(result.copySucceeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testStage8BenchmarkEvidenceValidatorRequiresClassifiedMetricsAndNotMeasuredGaps() {
        let valid = Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-12T13:00:00Z",
            project: "cca-linuxpod-stage8-rootfs-001",
            runLabel: "stage8-rootfs",
            iteration: 1,
            environment: benchmarkMetadata(
                lifecycle: .persistentWarmProjectRuntime,
                lifecycleMode: .rootfsCacheHitRuntime,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .hit,
                initfsCacheStatus: .miss,
                hostPortProbeStatus: "notMeasured",
                loadWindowStatus: "notMeasured"
            ),
            status: .measured,
            durationsSeconds: Phase6BenchmarkDurations(
                up: 11.0,
                status: 0.02,
                logs: 0.01,
                cleanup: 0.4,
                rootfsPrep: 0.05,
                initfsPrep: 1.2,
                volumeCreateOrReuse: 0.01,
                podCreateOrReuse: 4.0,
                containerStart: 2.1,
                healthcheck: 3.3
            ),
            guest: HostFootprintGuestStats(
                cgroupMemoryCurrentBytes: 128 * 1024 * 1024,
                cgroupMemoryLimitBytes: nil,
                cgroupMemoryLimitUnlimited: true,
                processCount: 7,
                cpuUsageUsec: 500,
                blockReadBytes: 2048,
                blockWriteBytes: 4096,
                processRSSBytes: 64 * 1024 * 1024
            ),
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 16,
            cleanupStateDirectoryExistsAfterCleanup: false,
            healthcheckAttempts: 4,
            dataFootprintBytes: 32 * 1024 * 1024,
            failure: nil,
            rootfsPreparation: [.completeTestBreakdown],
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(Stage8BenchmarkEvidenceValidator().validate(records: [valid]), [])

        let invalid = Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-12T13:01:00Z",
            project: "cca-linuxpod-stage8-rootfs-002",
            runLabel: "stage8-rootfs",
            iteration: 2,
            environment: benchmarkMetadata(
                lifecycle: .persistentWarmProjectRuntime,
                lifecycleMode: .rootfsCacheHitRuntime,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .miss,
                hostPortProbeStatus: "unknown",
                loadWindowStatus: "unknown"
            ),
            status: .measured,
            durationsSeconds: Phase6BenchmarkDurations(up: nil, status: nil, logs: nil, cleanup: 0.4),
            guest: nil,
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 16,
            cleanupStateDirectoryExistsAfterCleanup: true,
            failure: nil
        )

        XCTAssertEqual(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [invalid]).map(\.code)),
            [
                "stage8-lifecycle-mode-cache-mismatch",
                "stage8-host-port-not-measured-missing",
                "stage8-load-window-not-measured-missing",
                "stage8-startup-duration-missing",
                "stage8-rootfs-prep-duration-missing",
                "stage8-initfs-prep-duration-missing",
                "stage8-volume-duration-missing",
                "stage8-pod-duration-missing",
                "stage8-container-start-duration-missing",
                "stage8-healthcheck-duration-missing",
                "stage8-healthcheck-attempts-missing",
                "stage8-guest-metrics-missing",
                "stage8-process-rss-missing",
                "stage8-data-footprint-missing",
                "stage8-cleanup-leftovers",
                "stage9-rootfs-breakdown-missing",
                "stage9-block-io-attribution-missing"
            ]
        )
    }

    func testStage8BenchmarkEvidenceValidatorAcceptsWarmReuseWithFinalCleanCleanup() {
        let preserved = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: true,
            cleanupResult: "preserved-project-runtime-for-warm-reuse",
            rootfsPreparation: [.completeTestBreakdown],
            hotplugDiagnostics: .completeTest(),
            warmServiceRecreate: .noOpWarmReconcileNotEvidence,
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )
        let finalClean = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 2,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            rootfsPreparation: [.completeTestBreakdown],
            hotplugDiagnostics: .completeTest(),
            warmServiceRecreate: .noOpWarmReconcileNotEvidence,
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(Stage8BenchmarkEvidenceValidator().validate(records: [preserved, finalClean]), [])
        XCTAssertEqual(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [preserved]).map(\.code)),
            ["stage8-final-cleanup-missing"]
        )
    }

    func testStage8BenchmarkEvidenceValidatorRejectsMarkerOnlyPodReuse() {
        let markerOnly = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            podReuseVerificationStatus: "markerFile",
            rootfsPreparation: [.completeTestBreakdown],
            hotplugDiagnostics: .completeTest(),
            warmServiceRecreate: .noOpWarmReconcileNotEvidence,
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [markerOnly]).map(\.code)),
            ["stage8-pod-reuse-unverified"]
        )
    }

    func testStage9ARootfsBreakdownAndBlockIOAttributionAreRequiredForMeasuredRecords() {
        let missingBreakdown = completeStage8IterationRecord(
            lifecycleMode: .rootfsCacheHitRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean"
        )

        XCTAssertTrue(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [missingBreakdown]).map(\.code))
                .isSuperset(of: [
                    "stage9-rootfs-breakdown-missing",
                    "stage9-block-io-attribution-missing"
                ])
        )

        let explicitBreakdown = completeStage8IterationRecord(
            lifecycleMode: .rootfsCacheHitRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            rootfsPreparation: [
                RootfsPreparationBreakdown(
                    actionKind: "prepareImageRootfs",
                    resourceName: "mirror.gcr.io/library/postgres:16-alpine",
                    image: "mirror.gcr.io/library/postgres:16-alpine",
                    imageReferenceResolveDuration: 0.12,
                    imageStoreLookupDuration: nil,
                    platformValidationDuration: 0.03,
                    imagePullDuration: nil,
                    baseRootfsCacheLookupDuration: 0.01,
                    baseRootfsCacheHit: true,
                    baseRootfsCreateOrUnpackDuration: 0.0,
                    containerRootfsMaterializeDuration: nil,
                    containerRootfsCopyDuration: nil,
                    containerRootfsCloneDuration: nil,
                    containerRootfsMountPrepareDuration: nil,
                    rootfsBytesCopied: 2_147_483_648,
                    rootfsSourcePath: "/tmp/cache/postgres.ext4",
                    rootfsDestinationPath: "/tmp/runtime/rootfs/postgres.ext4",
                    rootfsMaterializationStrategy: .copy,
                    rootfsWorkAvoided: .false,
                    rootfsCacheClaim: .baseArtifactHit
                )
            ],
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        let diagnosticCodes = Set(Stage8BenchmarkEvidenceValidator().validate(records: [explicitBreakdown]).map(\.code))
        XCTAssertFalse(diagnosticCodes.contains("stage9-rootfs-breakdown-missing"))
        XCTAssertFalse(diagnosticCodes.contains("stage9-block-io-attribution-missing"))
    }

    func testStage9APersistentPodFailureCanBeStructuredKnownBlocker() {
        let failedHotplug = Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-12T13:20:01Z",
            project: "cca-linuxpod-stage9-f-hotplug",
            runLabel: "stage9-hotplug",
            iteration: 1,
            environment: benchmarkMetadata(
                lifecycle: .persistentWarmProjectRuntime,
                lifecycleMode: .persistentPodHotplug,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .hit,
                initfsCacheStatus: .miss,
                podExistedBeforeRun: true,
                podReuseVerificationStatus: "liveExecutorState"
            ),
            status: .failed,
            durationsSeconds: Phase6BenchmarkDurations(up: nil, status: nil, logs: nil, cleanup: 0.12),
            guest: nil,
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 3,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            failure: "invalidState: \"pod must be initialized to add container\"",
            hotplugDiagnostics: HotplugLifecycleDiagnostics(
                podMarkerExists: true,
                runtimeDirectoryExists: true,
                podObjectInitialized: true,
                podObjectPhase: "created",
                podCreatedStateKnown: true,
                podActuallyRunning: true,
                podReconnectAttempted: false,
                podReconnectSucceeded: false,
                podReuseClaim: .liveObject,
                addContainerAttempted: true,
                addContainerPhase: .afterPodCreate,
                hotplugAttempted: true,
                hotplugSucceeded: false,
                hotplugUnsupported: true,
                duplicateContainerDetected: false,
                failurePhase: "addContainer",
                failureErrorType: "invalidState",
                failureErrorMessage: "pod must be initialized to add container",
                mutationBeforeFailure: .true
            ),
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(Stage8BenchmarkEvidenceValidator().validate(records: [failedHotplug]), [])
    }

    func testStage9ARejectsMarkerOnlyPodReuseClaimInStructuredDiagnostics() {
        let markerOnly = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            podReuseVerificationStatus: "liveExecutorState",
            rootfsPreparation: [.completeTestBreakdown],
            hotplugDiagnostics: HotplugLifecycleDiagnostics.completeTest(
                podReuseClaim: .markerOnly,
                hotplugSucceeded: false
            ),
            warmServiceRecreate: .noOpWarmReconcileNotEvidence,
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [markerOnly]).map(\.code)),
            ["stage9-marker-only-pod-reuse"]
        )
    }

    func testStage9AAllWarmRequiresForcedRecreateOrExplicitNoOpNonViability() {
        let missing = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            rootfsPreparation: [.completeTestBreakdown],
            hotplugDiagnostics: .completeTest(),
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [missing]).map(\.code)),
            ["stage9-warm-service-recreate-missing"]
        )

        let explicitNoOp = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean",
            rootfsPreparation: [.completeTestBreakdown],
            hotplugDiagnostics: .completeTest(),
            warmServiceRecreate: .noOpWarmReconcileNotEvidence,
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )

        XCTAssertEqual(Stage8BenchmarkEvidenceValidator().validate(records: [explicitNoOp]), [])
    }

    func testStage8RuntimeEvidenceFilesValidateToKnownRuntimeBlockers() throws {
        let evidenceDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("docs/evidence/linuxpod-stage8-benchmark", isDirectory: true)
        let validator = Stage8BenchmarkEvidenceValidator()
        let successfulModes = [
            "20260612T180000Z-stage8-A-cold-runtime.jsonl",
            "20260612T180000Z-stage8-B-image-store-seeded-fresh-runtime.jsonl",
            "20260612T180000Z-stage8-C-rootfs-cache-hit-runtime.jsonl",
            "20260612T180000Z-stage8-D-initfs-cache-hit-runtime.jsonl",
            "20260612T180000Z-stage8-E-warm-preserved-volume.jsonl",
            "20260612T180000Z-stage8-G-all-warm-project-runtime.jsonl"
        ]

        for filename in successfulModes {
            let diagnostics = try validator.validate(evidenceURL: evidenceDir.appendingPathComponent(filename))
            var expected: Set<String> = [
                "stage8-process-rss-missing",
                "stage9-rootfs-breakdown-missing",
                "stage9-block-io-attribution-missing"
            ]
            if filename.contains("stage8-G") {
                expected.formUnion([
                    "stage9-hotplug-diagnostics-missing",
                    "stage9-warm-service-recreate-missing"
                ])
            }
            XCTAssertEqual(Set(diagnostics.map(\.code)), expected, filename)
        }

        let persistentPodDiagnostics = try validator.validate(
            evidenceURL: evidenceDir.appendingPathComponent(
                "20260612T180000Z-stage8-F-persistent-pod-hotplug.jsonl"
            )
        )
        XCTAssertEqual(
            Set(persistentPodDiagnostics.map(\.code)),
            [
                "stage8-startup-duration-missing",
                "stage8-rootfs-prep-duration-missing",
                "stage8-initfs-prep-duration-missing",
                "stage8-volume-duration-missing",
                "stage8-pod-duration-missing",
                "stage8-container-start-duration-missing",
                "stage8-healthcheck-duration-missing",
                "stage8-healthcheck-attempts-missing",
                "stage8-guest-metrics-missing",
                "stage8-process-rss-missing",
                "stage8-data-footprint-missing",
                "stage9-hotplug-diagnostics-missing"
            ]
        )
    }

    func testStage9ARuntimeEvidenceFilesValidateToRemainingKnownRuntimeBlockers() throws {
        let evidenceDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("docs/evidence/linuxpod-stage9a-benchmark", isDirectory: true)
        let validator = Stage8BenchmarkEvidenceValidator()

        let persistentPodDiagnostics = try validator.validate(
            evidenceURL: evidenceDir.appendingPathComponent(
                "20260612T233739Z-stage9a-F-persistent-pod-hotplug.jsonl"
            )
        )
        XCTAssertEqual(Set(persistentPodDiagnostics.map(\.code)), [])

        let allWarmDiagnostics = try validator.validate(
            evidenceURL: evidenceDir.appendingPathComponent(
                "20260612T233739Z-stage9a-G-all-warm-project-runtime.jsonl"
            )
        )
        XCTAssertEqual(Set(allWarmDiagnostics.map(\.code)), ["stage8-process-rss-missing"])

        let retestPersistentPodURL = evidenceDir.appendingPathComponent(
            "20260613T085301Z-stage9a0334meta-F-persistent-pod-hotplug.jsonl"
        )
        let retestPersistentPodDiagnostics = try validator.validate(evidenceURL: retestPersistentPodURL)
        XCTAssertEqual(Set(retestPersistentPodDiagnostics.map(\.code)), [])

        let retestPersistentPod = try readFirstPhase6IterationRecord(retestPersistentPodURL)
        XCTAssertEqual(retestPersistentPod.environment?.containerizationVersion, "0.33.4")
        XCTAssertEqual(retestPersistentPod.status, .failed)
        XCTAssertEqual(retestPersistentPod.failure, #"unsupported: "hotplug not supported""#)
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.failurePhase, "addContainer")
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.failureErrorType, "unsupported")
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.hotplugUnsupported, true)
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.podReuseClaim, .liveObject)
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.vmConfigExtensionCount, 0)
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.vmConfigExtensionTypes, [])
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.hotplugProviderInstalled, false)
        XCTAssertEqual(retestPersistentPod.hotplugDiagnostics?.hotplugProviderStatus, "missing")
        XCTAssertEqual(retestPersistentPod.rootfsPreparation?.first?.rootfsMountType, "block")
        XCTAssertEqual(retestPersistentPod.rootfsPreparation?.first?.rootfsMountFormat, "ext4")
        XCTAssertEqual(retestPersistentPod.rootfsPreparation?.first?.rootfsMountIsBlock, true)
        XCTAssertEqual(retestPersistentPod.cleanupResult, "clean")

        let retestAllWarmURL = evidenceDir.appendingPathComponent(
            "20260613T085301Z-stage9a0334meta-G-all-warm-project-runtime.jsonl"
        )
        let retestAllWarmDiagnostics = try validator.validate(evidenceURL: retestAllWarmURL)
        XCTAssertEqual(Set(retestAllWarmDiagnostics.map(\.code)), ["stage8-process-rss-missing"])

        let retestAllWarm = try readFirstPhase6IterationRecord(retestAllWarmURL)
        XCTAssertEqual(retestAllWarm.environment?.containerizationVersion, "0.33.4")
        XCTAssertEqual(retestAllWarm.status, .measured)
        XCTAssertEqual(retestAllWarm.warmServiceRecreate?.recreateStrategy, .noOp)
        XCTAssertEqual(retestAllWarm.warmServiceRecreate?.noOpWarmReconcile, true)
        XCTAssertEqual(retestAllWarm.warmServiceRecreate?.notProductViabilityEvidence, true)
        XCTAssertEqual(retestAllWarm.hotplugDiagnostics?.hotplugProviderInstalled, false)
        XCTAssertEqual(retestAllWarm.hotplugDiagnostics?.vmConfigExtensionCount, 0)
        XCTAssertTrue(retestAllWarm.rootfsPreparation?.allSatisfy { $0.rootfsMountType == "block" } == true)
        XCTAssertTrue(retestAllWarm.rootfsPreparation?.allSatisfy { $0.rootfsMountFormat == "ext4" } == true)
        XCTAssertTrue(retestAllWarm.rootfsPreparation?.allSatisfy { $0.rootfsMountIsBlock == true } == true)
        XCTAssertEqual(retestAllWarm.cleanupResult, "clean")
    }

    func testStage9BHotplugProbeEvidenceRequiresAllLifecycleCasesAndCleanupProof() {
        let complete = [
            stage9BProbeRecord(
                probeCase: .preCreateRegistrationControl,
                podCreateCalled: true,
                podCreateSucceeded: true,
                initialContainerRegisteredBeforeCreate: true,
                addContainerPhase: .beforePodCreate
            ),
            stage9BProbeRecord(
                probeCase: .emptyPodPostCreateAddContainer,
                podCreateCalled: true,
                podCreateSucceeded: true,
                postCreateAddContainerAttempted: true,
                addContainerPhase: .afterPodCreateEmptyPod,
                hotplugAttempted: true,
                hotplugSucceeded: false,
                hotplugUnsupported: true,
                failurePhase: "addContainer",
                failureErrorType: "invalidState",
                failureErrorMessage: "pod must be initialized to add container",
                mutationBeforeFailure: .true
            ),
            stage9BProbeRecord(
                probeCase: .nonEmptyPodPostCreateAddSecondContainer,
                podCreateCalled: true,
                podCreateSucceeded: true,
                initialContainerRegisteredBeforeCreate: true,
                initialContainerStarted: true,
                postCreateAddContainerAttempted: true,
                addContainerPhase: .afterPodCreateNonEmptyPod,
                hotplugAttempted: true,
                hotplugSucceeded: false,
                hotplugUnsupported: true,
                failurePhase: "addContainer",
                failureErrorType: "invalidState",
                failureErrorMessage: "pod must be initialized to add container",
                mutationBeforeFailure: .true
            ),
            stage9BProbeRecord(
                probeCase: .duplicateContainerIDGuard,
                podCreateCalled: false,
                podCreateSucceeded: false,
                initialContainerRegisteredBeforeCreate: true,
                postCreateAddContainerAttempted: true,
                addContainerPhase: .duplicateContainer,
                duplicateContainerDetected: true,
                failurePhase: "addContainer",
                failureErrorType: "invalidArgument",
                failureErrorMessage: "container already exists",
                mutationBeforeFailure: .false
            ),
            stage9BProbeRecord(
                probeCase: .cleanupProof,
                addContainerPhase: .unknown
            )
        ]

        XCTAssertEqual(Stage9BHotplugProbeEvidenceValidator().validate(records: complete), [])

        var missingCleanup = Array(complete.dropLast())
        missingCleanup[1] = stage9BProbeRecord(
            probeCase: .emptyPodPostCreateAddContainer,
            podCreateCalled: true,
            podCreateSucceeded: true,
            postCreateAddContainerAttempted: true,
            addContainerPhase: .afterPodCreateEmptyPod,
            hotplugAttempted: true,
            hotplugSucceeded: false,
            cleanupResult: "leftovers",
            cleanupStateDirectoryExistsAfterCleanup: true,
            leftoverPathsCount: 1
        )

        XCTAssertEqual(
            Set(Stage9BHotplugProbeEvidenceValidator().validate(records: missingCleanup).map(\.code)),
            [
                "stage9b-cleanup-proof-missing",
                "stage9b-case-cleanup-leftovers"
            ]
        )
    }

    func testStage9BHotplugProbeRecordUsesRequestedEvidenceKeys() throws {
        let record = stage9BProbeRecord(
            probeCase: .nonEmptyPodPostCreateAddSecondContainer,
            podCreateCalled: true,
            podCreateSucceeded: true,
            initialContainerRegisteredBeforeCreate: true,
            initialContainerStarted: true,
            postCreateAddContainerAttempted: true,
            postCreateAddContainerSucceeded: false,
            addContainerPhase: .afterPodCreateNonEmptyPod,
            hotplugAttempted: true,
            hotplugSucceeded: false,
            hotplugUnsupported: true,
            failurePhase: "addContainer",
            failureErrorType: "invalidState",
            failureErrorMessage: "pod must be initialized to add container",
            mutationBeforeFailure: .true
        )

        let encoded = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["recordType"] as? String, Stage9BHotplugProbeSchema.caseRecordType)
        XCTAssertEqual(object["schemaVersion"] as? String, Stage9BHotplugProbeSchema.version)
        XCTAssertEqual(object["probeCase"] as? String, "non-empty-pod-post-create-add-second-container")
        XCTAssertEqual(object["addContainerPhase"] as? String, "afterPodCreateNonEmptyPod")
        XCTAssertEqual(object["podObjectCreated"] as? Bool, true)
        XCTAssertEqual(object["podCreateCalled"] as? Bool, true)
        XCTAssertEqual(object["podCreateSucceeded"] as? Bool, true)
        XCTAssertEqual(object["initialContainerRegisteredBeforeCreate"] as? Bool, true)
        XCTAssertEqual(object["initialContainerStarted"] as? Bool, true)
        XCTAssertEqual(object["postCreateAddContainerAttempted"] as? Bool, true)
        XCTAssertEqual(object["postCreateAddContainerSucceeded"] as? Bool, false)
        XCTAssertEqual(object["hotplugAttempted"] as? Bool, true)
        XCTAssertEqual(object["hotplugSucceeded"] as? Bool, false)
        XCTAssertEqual(object["hotplugUnsupported"] as? Bool, true)
        XCTAssertEqual(object["duplicateContainerDetected"] as? Bool, false)
        XCTAssertEqual(object["failurePhase"] as? String, "addContainer")
        XCTAssertEqual(object["failureErrorType"] as? String, "invalidState")
        XCTAssertEqual(object["mutationBeforeFailure"] as? String, "true")
        XCTAssertEqual(object["cleanupResult"] as? String, "clean")
        XCTAssertEqual(object["cleanupStateDirectoryExistsAfterCleanup"] as? Bool, false)
        XCTAssertEqual(object["leftoverPathsCount"] as? Int, 0)
        XCTAssertEqual(object["runtimePackageVersion"] as? String, "0.26.5")
        XCTAssertEqual(object["containerizationVersion"] as? String, "0.26.5")
        XCTAssertEqual(object["macOSVersion"] as? String, "test-macos")
    }

    func testStage9BRuntimeEvidenceFilesValidateHotplugCapabilityProbe() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let evidenceURL = root
            .appendingPathComponent(
                "docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T000136Z-stage9b-hotplug-capability.jsonl"
            )
        let retestEvidenceURL = root
            .appendingPathComponent(
                "docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T002830Z-stage9b-hotplug-capability-0334-escalated.jsonl"
            )

        XCTAssertEqual(try Stage9BHotplugProbeEvidenceValidator().validate(evidenceURL: evidenceURL), [])
        XCTAssertEqual(try Stage9BHotplugProbeEvidenceValidator().validate(evidenceURL: retestEvidenceURL), [])

        let records = try readStage9BProbeRecords(evidenceURL)
        let byCase = Dictionary(uniqueKeysWithValues: records.map { ($0.probeCase, $0) })

        let preCreate = try XCTUnwrap(byCase[.preCreateRegistrationControl])
        XCTAssertTrue(preCreate.initialContainerRegisteredBeforeCreate)
        XCTAssertTrue(preCreate.podCreateSucceeded)
        XCTAssertTrue(preCreate.initialContainerStarted)
        XCTAssertFalse(preCreate.hotplugAttempted)

        let emptyPod = try XCTUnwrap(byCase[.emptyPodPostCreateAddContainer])
        XCTAssertTrue(emptyPod.hotplugAttempted)
        XCTAssertFalse(emptyPod.hotplugSucceeded)
        XCTAssertTrue(emptyPod.hotplugUnsupported)
        XCTAssertEqual(emptyPod.failureErrorType, "invalidState")

        let nonEmptyPod = try XCTUnwrap(byCase[.nonEmptyPodPostCreateAddSecondContainer])
        XCTAssertTrue(nonEmptyPod.initialContainerRegisteredBeforeCreate)
        XCTAssertTrue(nonEmptyPod.initialContainerStarted)
        XCTAssertTrue(nonEmptyPod.hotplugAttempted)
        XCTAssertFalse(nonEmptyPod.hotplugSucceeded)
        XCTAssertTrue(nonEmptyPod.hotplugUnsupported)
        XCTAssertEqual(nonEmptyPod.failureErrorMessage, "invalidState: \"pod must be initialized to add container\"")

        let duplicate = try XCTUnwrap(byCase[.duplicateContainerIDGuard])
        XCTAssertTrue(duplicate.duplicateContainerDetected)
        XCTAssertEqual(duplicate.failureErrorType, "invalidArgument")

        let cleanup = try XCTUnwrap(byCase[.cleanupProof])
        XCTAssertEqual(cleanup.cleanupResult, "clean")
        XCTAssertFalse(cleanup.cleanupStateDirectoryExistsAfterCleanup)
        XCTAssertEqual(cleanup.leftoverPathsCount, 0)

        let retestRecords = try readStage9BProbeRecords(retestEvidenceURL)
        let retestByCase = Dictionary(uniqueKeysWithValues: retestRecords.map { ($0.probeCase, $0) })

        let retestPreCreate = try XCTUnwrap(retestByCase[.preCreateRegistrationControl])
        XCTAssertEqual(retestPreCreate.runtimePackageVersion, "0.33.4")
        XCTAssertEqual(retestPreCreate.containerizationVersion, "0.33.4")
        XCTAssertTrue(retestPreCreate.initialContainerRegisteredBeforeCreate)
        XCTAssertTrue(retestPreCreate.podCreateSucceeded)
        XCTAssertTrue(retestPreCreate.initialContainerStarted)

        let retestEmptyPod = try XCTUnwrap(retestByCase[.emptyPodPostCreateAddContainer])
        XCTAssertTrue(retestEmptyPod.hotplugAttempted)
        XCTAssertFalse(retestEmptyPod.hotplugSucceeded)
        XCTAssertTrue(retestEmptyPod.hotplugUnsupported)
        XCTAssertEqual(retestEmptyPod.failureErrorType, "unsupported")
        XCTAssertEqual(retestEmptyPod.failureErrorMessage, #"unsupported: "hotplug not supported""#)

        let retestNonEmptyPod = try XCTUnwrap(retestByCase[.nonEmptyPodPostCreateAddSecondContainer])
        XCTAssertTrue(retestNonEmptyPod.initialContainerRegisteredBeforeCreate)
        XCTAssertTrue(retestNonEmptyPod.initialContainerStarted)
        XCTAssertTrue(retestNonEmptyPod.hotplugAttempted)
        XCTAssertFalse(retestNonEmptyPod.hotplugSucceeded)
        XCTAssertTrue(retestNonEmptyPod.hotplugUnsupported)
        XCTAssertEqual(retestNonEmptyPod.failureErrorType, "unsupported")

        let retestCleanup = try XCTUnwrap(retestByCase[.cleanupProof])
        XCTAssertEqual(retestCleanup.cleanupResult, "clean")
        XCTAssertFalse(retestCleanup.cleanupStateDirectoryExistsAfterCleanup)
        XCTAssertEqual(retestCleanup.leftoverPathsCount, 0)
    }

    func testStage9DRuntimeEvidenceFileValidatesHotplugProviderFeasibilityProbe() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let evidenceURL = root.appendingPathComponent(
            "docs/evidence/linuxpod-stage9d-hotplug-provider/20260613T093056Z-stage9d-hotplug-provider-feasibility.jsonl"
        )

        XCTAssertEqual(try Stage9DHotplugProviderProbeEvidenceValidator().validate(evidenceURL: evidenceURL), [])

        let line = try XCTUnwrap(
            String(data: try Data(contentsOf: evidenceURL), encoding: .utf8)?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
        )
        let record = try JSONDecoder().decode(Stage9DHotplugProviderProbeRecord.self, from: Data(line.utf8))

        XCTAssertEqual(record.containerizationVersion, "0.33.4")
        XCTAssertEqual(record.containerizationRevision, "9275f365dd555c8f072e7d250d809f5eb7bdd746")
        XCTAssertEqual(record.probeCases, [.providerInstallOnly, .providerReceivesHotplug])
        XCTAssertTrue(record.provider.extensionInstalled)
        XCTAssertEqual(record.provider.linuxPodConfigExtensionCount, 1)
        XCTAssertEqual(record.provider.vmConfigExtensionCount, 1)
        XCTAssertTrue(record.provider.providerDidCreateCalled)
        XCTAssertTrue(record.provider.hotplugProviderInstalled)
        XCTAssertTrue(record.provider.providerHotplugCalled)
        XCTAssertTrue(record.hotplug.postCreateAddContainerReachedProvider)
        XCTAssertFalse(record.hotplug.realHotplugSucceeded)
        XCTAssertFalse(record.hotplug.secondContainerStarted)
        XCTAssertEqual(record.hotplug.blocker, .unsupportedRootfsBlockHotplug)
        XCTAssertEqual(record.rootfs.rootfsAttachStrategy, .vzUSBMassStorage)
        XCTAssertTrue(record.cleanup.attachedDeviceDetached ?? false)
        XCTAssertEqual(record.cleanup.cleanupResult, "clean")
        XCTAssertTrue(record.cleanup.zeroAdapterOwnedLeftovers)
        XCTAssertFalse(record.interpretation.productHotplugAvailable)
        XCTAssertFalse(record.interpretation.productShouldDependOnHotplug)
        XCTAssertEqual(record.interpretation.nextRecommendedPath, .upstreamIssue)
    }

    func testStage10ARuntimeEvidenceFileValidatesRootfsMaterializationProbe() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let evidenceURL = root.appendingPathComponent(
            "docs/evidence/linuxpod-stage10a-rootfs-materialization/20260613T101706Z-stage10a-rootfs-materialization.jsonl"
        )

        XCTAssertEqual(try Stage10ARootfsMaterializationProbeEvidenceValidator().validate(evidenceURL: evidenceURL), [])

        let lines = try XCTUnwrap(String(data: try Data(contentsOf: evidenceURL), encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: true)
        let records = try lines.map {
            try JSONDecoder().decode(RootfsMaterializationProbeRecord.self, from: Data($0.utf8))
        }

        XCTAssertEqual(records.count, 2)
        let fullCopy = try XCTUnwrap(records.first { $0.strategy.requestedStrategy == .fullCopy })
        let auto = try XCTUnwrap(records.first { $0.strategy.requestedStrategy == .auto })

        XCTAssertEqual(fullCopy.status, .measured)
        XCTAssertEqual(fullCopy.environment.containerizationVersion, "0.33.4")
        XCTAssertEqual(fullCopy.environment.containerizationRevision, "9275f365dd555c8f072e7d250d809f5eb7bdd746")
        XCTAssertTrue(fullCopy.environment.runtimePathRedacted)
        XCTAssertEqual(fullCopy.strategy.actualStrategy, .fullCopy)
        XCTAssertFalse(fullCopy.strategy.cloneAttempted)
        XCTAssertFalse(fullCopy.strategy.cloneSucceeded)
        XCTAssertTrue(fullCopy.strategy.copyAttempted)
        XCTAssertEqual(fullCopy.strategy.rootfsWorkAvoided, .false)
        XCTAssertEqual(fullCopy.strategy.byteForByteCopyAvoided, .false)
        XCTAssertEqual(fullCopy.correctness.baseRootfsUnchanged, .true)
        XCTAssertTrue(fullCopy.correctness.ext4ImageLooksValid ?? false)
        XCTAssertEqual(fullCopy.cleanup.cleanupResult, "clean")
        XCTAssertEqual(fullCopy.cleanup.leftoverPathsCount, 0)
        XCTAssertFalse(fullCopy.interpretation.productReady)
        XCTAssertEqual(fullCopy.interpretation.nextRecommendedPath, .keepFullCopy)

        XCTAssertEqual(auto.status, .measured)
        XCTAssertEqual(auto.strategy.actualStrategy, .clonefile)
        XCTAssertTrue(auto.strategy.cloneAttempted)
        XCTAssertTrue(auto.strategy.cloneReturnedSuccess)
        XCTAssertTrue(auto.strategy.cloneVerified)
        XCTAssertTrue(auto.strategy.cloneSucceeded)
        XCTAssertEqual(auto.strategy.cloneVerificationStrength, .strong)
        XCTAssertFalse(auto.strategy.copyAttempted)
        XCTAssertEqual(auto.strategy.rootfsWorkAvoided, .true)
        XCTAssertEqual(auto.strategy.byteForByteCopyAvoided, .true)
        XCTAssertNil(auto.sizesBytes.bytesCopiedIfKnown)
        XCTAssertEqual(auto.correctness.baseRootfsUnchanged, .true)
        XCTAssertTrue(auto.correctness.ext4ImageLooksValid ?? false)
        XCTAssertEqual(auto.cleanup.cleanupResult, "clean")
        XCTAssertEqual(auto.cleanup.leftoverPathsCount, 0)
        XCTAssertFalse(auto.interpretation.productReady)
        XCTAssertEqual(auto.interpretation.nextRecommendedPath, .useClonefileForRootfs)
    }

    func testPhase6SeedImageStorePolicyRequiresSentinelAndProtectsExternalSources() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-seed-policy-\(UUID().uuidString)", isDirectory: true)
        let ownedSeed = root
            .appendingPathComponent(".container-compose-adapter", isDirectory: true)
            .appendingPathComponent("benchmark-seed-image-stores", isDirectory: true)
            .appendingPathComponent("stage6-arm64", isDirectory: true)
        let externalSeed = root.appendingPathComponent("external-seed", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: ownedSeed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalSeed, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try Phase6SeedImageStorePolicy.validateSeedSource(
                ownedSeed,
                allowExternal: false,
                repositoryRoot: root
            )
        ) { error in
            XCTAssertTrue("\(error)".contains(Phase6SeedImageStorePolicy.sentinelFileName))
        }

        try Phase6SeedImageStorePolicy.writeSentinel(in: ownedSeed)
        XCTAssertNoThrow(
            try Phase6SeedImageStorePolicy.validateSeedSource(
                ownedSeed,
                allowExternal: false,
                repositoryRoot: root
            )
        )

        try Phase6SeedImageStorePolicy.writeSentinel(in: externalSeed)
        XCTAssertThrowsError(
            try Phase6SeedImageStorePolicy.validateSeedSource(
                externalSeed,
                allowExternal: false,
                repositoryRoot: root
            )
        ) { error in
            XCTAssertTrue("\(error)".contains("outside adapter-owned benchmark seed cache"))
        }
        XCTAssertNoThrow(
            try Phase6SeedImageStorePolicy.validateSeedSource(
                externalSeed,
                allowExternal: true,
                repositoryRoot: root
            )
        )

        let sourceExistsBeforeCleanup = FileManager.default.fileExists(atPath: externalSeed.path)
        try Phase6SeedImageStorePolicy.assertCleanupDoesNotTargetSeedSource(
            cleanupTarget: root.appendingPathComponent(".container-compose-adapter/cca-linuxpod-demo/runtime"),
            seedSource: externalSeed
        )
        XCTAssertTrue(sourceExistsBeforeCleanup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalSeed.path))
        XCTAssertThrowsError(
            try Phase6SeedImageStorePolicy.assertCleanupDoesNotTargetSeedSource(
                cleanupTarget: root,
                seedSource: externalSeed
            )
        ) { error in
            XCTAssertTrue("\(error)".contains("contains seed image-store source"))
        }
    }

    func testHostFootprintMetricAccumulatorTreatsCgroupUnlimitedAsUnlimited() {
        XCTAssertEqual(
            HostFootprintMetricAccumulator.sumSaturating([UInt64.max, 4]),
            UInt64.max
        )
        XCTAssertEqual(
            HostFootprintMetricAccumulator.sumCgroupMemoryLimit([512, 1024]),
            HostFootprintCgroupMemoryLimit(bytes: 1536, unlimited: false)
        )
        XCTAssertEqual(
            HostFootprintMetricAccumulator.sumCgroupMemoryLimit([UInt64.max, 1024]),
            HostFootprintCgroupMemoryLimit(bytes: nil, unlimited: true)
        )
        XCTAssertEqual(
            HostFootprintMetricAccumulator.sumCgroupMemoryLimit([UInt64.max - 3]),
            HostFootprintCgroupMemoryLimit(bytes: nil, unlimited: true)
        )
    }

    func testStage4MicrobenchmarkPlanCoversRootfsVolumeAndHealthcheckWithoutRuntimeMutation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-microbenchmarks-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: root)
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("backend-shaped/compose.yaml"), projectName: "backend-shaped")
            .project

        let record = Stage4MicrobenchmarkPlanner(store: store).plan(
            project: project,
            timestamp: "2026-06-12T08:00:00Z"
        )

        XCTAssertEqual(record.schemaVersion, Stage4MicrobenchmarkSchema.version)
        XCTAssertEqual(record.recordType, Stage4MicrobenchmarkSchema.planRecordType)
        XCTAssertEqual(record.status, "planned-dry-run-no-runtime-mutation")
        XCTAssertEqual(record.projectID, "backend-shaped")
        XCTAssertEqual(record.runtimeResourceName, "cca-linuxpod-backend-shaped")
        XCTAssertEqual(record.hostPhysicalMemoryStatus, .blocked)
        XCTAssertEqual(record.cleanupExpectation.cacheCleanup, "preserved")
        XCTAssertEqual(record.cleanupExpectation.volumeCleanup, "preserved-by-default")

        XCTAssertTrue(record.probes.allSatisfy { probe in
            probe.runtimeMutation == "not-run" && probe.requiresRuntimeApprovalToMeasure
        })
        XCTAssertEqual(
            Set(record.probes.map(\.kind)),
            [
                .rootfsUnpack,
                .rootfsCopy,
                .apfsClone,
                .namedVolumeFresh,
                .namedVolumeWarm,
                .healthcheckExec
            ]
        )

        let rootfsUnpackProbes = record.probes.filter { $0.kind == .rootfsUnpack }
        XCTAssertEqual(
            rootfsUnpackProbes.map(\.imageReference).sorted(),
            [
                "docker.io/library/postgres:16-alpine",
                "docker.io/library/python:3.12-alpine"
            ]
        )
        XCTAssertTrue(rootfsUnpackProbes.allSatisfy { probe in
            probe.cacheKeyKind == .imageReferencePendingDigest
                && probe.targetPath.contains("/cache/rootfs-by-digest/")
                && probe.expectedMetrics.contains("rootfs_prep_seconds")
                && probe.expectedMetrics.contains("block_read_bytes")
        })

        let volumeProbes = record.probes.filter { $0.kind == .namedVolumeFresh || $0.kind == .namedVolumeWarm }
        XCTAssertEqual(Set(volumeProbes.map(\.volumeName)), ["db-data"])
        XCTAssertTrue(volumeProbes.allSatisfy { probe in
            probe.targetPath.hasSuffix("/projects/backend-shaped/volumes/db-data")
                && probe.expectedMetrics.contains("volume_setup_seconds")
                && probe.expectedMetrics.contains("block_write_bytes")
        })

        let healthcheckProbes = record.probes.filter { $0.kind == .healthcheckExec }
        XCTAssertEqual(Set(healthcheckProbes.map(\.serviceName)), ["api", "db"])
        XCTAssertTrue(healthcheckProbes.allSatisfy { probe in
            probe.expectedMetrics.contains("healthcheck_exec_seconds")
                && probe.expectedMetrics.contains("healthcheck_attempts")
        })

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(Stage4MicrobenchmarkPlanRecord.self, from: encoded)
        XCTAssertEqual(decoded, record)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(json.contains("\"record_type\":\"linuxpod-stage4-microbenchmark-plan\""))
        XCTAssertTrue(json.contains("\"host_physical_memory_status\":\"blocked\""))

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testStage4MicrobenchmarkOperationPlanRendersApprovalGatedActionsWithoutRuntimeMutation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-operation-plan-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: root)
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("backend-shaped/compose.yaml"), projectName: "backend-shaped")
            .project
        let record = Stage4MicrobenchmarkPlanner(store: store).plan(
            project: project,
            timestamp: "2026-06-12T09:00:00Z"
        )

        let operations = Stage4MicrobenchmarkOperationPlanner().planOperations(for: record)

        XCTAssertEqual(operations.count, record.probes.count)
        XCTAssertTrue(operations.allSatisfy { operation in
            operation.schemaVersion == Stage4MicrobenchmarkSchema.version
                && operation.recordType == Stage4MicrobenchmarkSchema.operationRecordType
                && operation.timestamp == record.timestamp
                && operation.projectID == record.projectID
                && operation.runtimeResourceName == record.runtimeResourceName
                && operation.runtimeMutation == "planned-not-run"
                && operation.requiresRuntimeApproval
                && !operation.mutatesGlobalState
        })
        let rootfsUnpack = try XCTUnwrap(operations.first { $0.kind == .rootfsUnpack })
        XCTAssertEqual(rootfsUnpack.mutationScope, .reusableCache)
        XCTAssertEqual(rootfsUnpack.cleanupExpectation, "preserve-reusable-cache")
        XCTAssertTrue(rootfsUnpack.targetPath.contains("/cache/rootfs-by-digest/"))

        let rootfsCopy = try XCTUnwrap(operations.first { $0.kind == .rootfsCopy })
        XCTAssertEqual(rootfsCopy.mutationScope, .projectRuntimeState)
        XCTAssertEqual(rootfsCopy.cleanupExpectation, "remove-project-runtime-copy")

        let apfsClone = try XCTUnwrap(operations.first { $0.kind == .apfsClone })
        XCTAssertEqual(apfsClone.mutationScope, .projectRuntimeState)
        XCTAssertEqual(apfsClone.cleanupExpectation, "remove-project-runtime-clone")

        let namedVolumeFresh = try XCTUnwrap(operations.first { $0.kind == .namedVolumeFresh })
        XCTAssertEqual(namedVolumeFresh.mutationScope, .projectNamedVolume)
        XCTAssertEqual(namedVolumeFresh.cleanupExpectation, "preserve-named-volume-by-default")

        let healthcheck = try XCTUnwrap(operations.first { $0.kind == .healthcheckExec && $0.serviceName == "api" })
        XCTAssertEqual(healthcheck.mutationScope, .runtimeExec)
        XCTAssertEqual(healthcheck.command, [
            "sh",
            "-ec",
            "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/ready', timeout=2).read()\""
        ])
        XCTAssertEqual(healthcheck.cleanupExpectation, "remove-metrics-only")

        let encoded = try JSONEncoder().encode(rootfsUnpack)
        let decoded = try JSONDecoder().decode(Stage4MicrobenchmarkOperation.self, from: encoded)
        XCTAssertEqual(decoded, rootfsUnpack)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(json.contains("\"runtime_mutation\":\"planned-not-run\""))
        XCTAssertTrue(json.contains("\"mutates_global_state\":false"))
        XCTAssertTrue(json.contains("\"record_type\":\"linuxpod-stage4-microbenchmark-operation\""))

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testStage4MicrobenchmarkEvidenceValidatorAcceptsPlanAndOperationEvidence() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:05:00Z")
        let operations = Stage4MicrobenchmarkOperationPlanner().planOperations(for: record)

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            operations: operations
        )

        XCTAssertEqual(diagnostics, [])
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsIncompleteOrMalformedPlanEvidence() throws {
        let validRecord = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:05:30Z")
        let malformedPlan = Stage4MicrobenchmarkPlanRecord(
            timestamp: "2026-06-12T09:05:31Z",
            projectID: validRecord.projectID,
            displayName: validRecord.displayName,
            runtimeResourceName: validRecord.runtimeResourceName,
            probes: [
                Stage4MicrobenchmarkProbe(
                    probeID: "rootfs-unpack-invalid",
                    kind: .rootfsUnpack,
                    coldOrWarm: BenchmarkLifecycle.cold.rawValue,
                    imageReference: "",
                    targetPath: "/tmp/project-rootfs.ext4",
                    cacheKeyKind: .notApplicable,
                    expectedMetrics: ["rootfs_prep_seconds"]
                )
            ]
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(plan: malformedPlan)

        XCTAssertEqual(
            Set(diagnostics.map(\.code)),
            [
                "stage4-plan-required-probes-missing",
                "stage4-rootfs-image-missing",
                "stage4-rootfs-cache-key-missing",
                "stage4-rootfs-cache-path-missing"
            ]
        )
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorReadsPlanAndOperationJSONLFiles() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-file-validation-\(UUID().uuidString)", isDirectory: true)
        let planURL = tempRoot.appendingPathComponent("stage4-plan.jsonl")
        let operationURL = tempRoot.appendingPathComponent("stage4-operations.jsonl")
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:07:00Z")
        let operations = Stage4MicrobenchmarkOperationPlanner().planOperations(for: record)
        let writer = Stage4MicrobenchmarkJSONLWriter()
        try writer.append(record, to: planURL)
        for operation in operations {
            try writer.append(operation, to: operationURL)
        }

        let diagnostics = try Stage4MicrobenchmarkEvidenceValidator().validate(
            planEvidenceURL: planURL,
            operationEvidenceURL: operationURL
        )

        XCTAssertEqual(diagnostics, [])
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsUnsafeOrMismatchedOperationEvidence() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:06:00Z")
        var operations = Stage4MicrobenchmarkOperationPlanner().planOperations(for: record)
        let rootfsProbe = try XCTUnwrap(record.probes.first { $0.kind == .rootfsUnpack })
        operations[0] = Stage4MicrobenchmarkOperation(
            probe: rootfsProbe,
            plan: record,
            mutationScope: .runtimeExec,
            cleanupExpectation: "delete-global-cache",
            runtimeMutation: "executed",
            requiresRuntimeApproval: false,
            mutatesGlobalState: true
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            operations: operations
        )

        XCTAssertEqual(
            Set(diagnostics.map(\.code)),
            [
                "stage4-operation-runtime-mutation-not-planned",
                "stage4-operation-approval-missing",
                "stage4-operation-global-mutation",
                "stage4-operation-scope-mismatch",
                "stage4-operation-cleanup-mismatch"
            ]
        )
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsOperationTargetMismatches() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:06:30Z")
        var operations = Stage4MicrobenchmarkOperationPlanner().planOperations(for: record)
        let plannedProbe = try XCTUnwrap(record.probes.first { $0.kind == .rootfsUnpack })
        let mismatchedProbe = Stage4MicrobenchmarkProbe(
            probeID: plannedProbe.probeID,
            kind: plannedProbe.kind,
            coldOrWarm: plannedProbe.coldOrWarm,
            imageReference: "docker.io/library/busybox:latest",
            targetPath: "/tmp/not-adapter-owned/rootfs",
            cacheKeyKind: plannedProbe.cacheKeyKind,
            expectedMetrics: plannedProbe.expectedMetrics
        )
        operations[0] = Stage4MicrobenchmarkOperation(
            probe: mismatchedProbe,
            plan: record,
            mutationScope: .reusableCache,
            cleanupExpectation: "preserve-reusable-cache"
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            operations: operations
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-operation-target-mismatch"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkPlanHarnessEmitsOperationEvidenceWithoutRuntimeMutation() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-operation-evidence-\(UUID().uuidString)", isDirectory: true)
        let evidencePath = tempRoot.appendingPathComponent("stage4-operations.jsonl")
        let storeRoot = tempRoot.appendingPathComponent("store", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let operations = try Stage4MicrobenchmarkPlanHarness(
            store: ProjectRuntimeStore(baseDirectory: storeRoot)
        ).emitOperationPlan(
            composeFile: fixtureURL("backend-shaped/compose.yaml"),
            projectName: "backend-shaped",
            timestamp: "2026-06-12T09:10:00Z",
            evidenceURL: evidencePath
        )

        XCTAssertEqual(operations.count, 10)
        XCTAssertTrue(operations.allSatisfy { $0.runtimeMutation == "planned-not-run" && !$0.mutatesGlobalState })
        let contents = try String(contentsOf: evidencePath, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, operations.count + 1)
        XCTAssertEqual(lines.last, "")
        let decoded = try JSONDecoder().decode(
            Stage4MicrobenchmarkOperation.self,
            from: Data(String(lines[0]).utf8)
        )
        XCTAssertEqual(decoded, operations[0])
        XCTAssertTrue(contents.contains("\"record_type\":\"linuxpod-stage4-microbenchmark-operation\""))
        XCTAssertTrue(contents.contains("\"mutation_scope\":\"runtime-exec\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeRoot.path))
    }

    func testStage4MicrobenchmarkWriterAppendsDecodableJSONLWithoutRuntimeMutation() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-jsonl-\(UUID().uuidString)", isDirectory: true)
        let evidencePath = tempRoot
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("stage4-plan.jsonl")
        let storeRoot = tempRoot.appendingPathComponent("store", isDirectory: true)
        let store = ProjectRuntimeStore(baseDirectory: storeRoot)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("backend-shaped/compose.yaml"), projectName: "backend-shaped")
            .project
        let record = Stage4MicrobenchmarkPlanner(store: store).plan(
            project: project,
            timestamp: "2026-06-12T08:10:00Z"
        )

        try Stage4MicrobenchmarkJSONLWriter().append(record, to: evidencePath)

        let contents = try String(contentsOf: evidencePath, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.last, "")
        let decoded = try JSONDecoder().decode(
            Stage4MicrobenchmarkPlanRecord.self,
            from: Data(String(lines[0]).utf8)
        )
        XCTAssertEqual(decoded, record)
        XCTAssertTrue(contents.contains("\"record_type\":\"linuxpod-stage4-microbenchmark-plan\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeRoot.path))
    }

    func testStage4MicrobenchmarkPlanHarnessEmitsFixturePlanEvidenceWithoutRuntimeMutation() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-harness-\(UUID().uuidString)", isDirectory: true)
        let evidencePath = tempRoot.appendingPathComponent("stage4-plan.jsonl")
        let storeRoot = tempRoot.appendingPathComponent("store", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let record = try Stage4MicrobenchmarkPlanHarness(
            store: ProjectRuntimeStore(baseDirectory: storeRoot)
        ).emitPlan(
            composeFile: fixtureURL("backend-shaped/compose.yaml"),
            projectName: "backend-shaped",
            timestamp: "2026-06-12T08:20:00Z",
            evidenceURL: evidencePath
        )

        XCTAssertEqual(record.projectID, "backend-shaped")
        XCTAssertEqual(record.recordType, Stage4MicrobenchmarkSchema.planRecordType)
        XCTAssertEqual(record.probes.filter { $0.kind == .healthcheckExec }.map(\.serviceName).sorted(), ["api", "db"])
        let contents = try String(contentsOf: evidencePath, encoding: .utf8)
        let decoded = try JSONDecoder().decode(
            Stage4MicrobenchmarkPlanRecord.self,
            from: Data(contents.split(separator: "\n")[0].utf8)
        )
        XCTAssertEqual(decoded, record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeRoot.path))
    }

    func testStage4MicrobenchmarkPlanCommandOptionsStayNoRuntimeOnly() throws {
        let options = try Stage4MicrobenchmarkPlanCommandOptions.parse([
            "--compose-file", "docs/evidence/fixtures/backend-shaped/compose.yaml",
            "--project-name", "backend-shaped",
            "--timestamp", "2026-06-12T08:30:00Z",
            "--evidence-jsonl", "docs/evidence/linuxpod-stage4-microbenchmarks/plan.jsonl",
            "--operation-evidence-jsonl", "docs/evidence/linuxpod-stage4-microbenchmarks/operations.jsonl",
            "--measurement-evidence-jsonl", "docs/evidence/linuxpod-stage4-microbenchmarks/measurements.jsonl",
            "--validate-evidence",
            "--store-root", "/tmp/cca-stage4-store"
        ])

        XCTAssertEqual(options.composeFile.path, "docs/evidence/fixtures/backend-shaped/compose.yaml")
        XCTAssertEqual(options.projectName, "backend-shaped")
        XCTAssertEqual(options.timestamp, "2026-06-12T08:30:00Z")
        XCTAssertEqual(options.evidenceJSONL.path, "docs/evidence/linuxpod-stage4-microbenchmarks/plan.jsonl")
        XCTAssertEqual(options.operationEvidenceJSONL?.path, "docs/evidence/linuxpod-stage4-microbenchmarks/operations.jsonl")
        XCTAssertEqual(options.measurementEvidenceJSONL?.path, "docs/evidence/linuxpod-stage4-microbenchmarks/measurements.jsonl")
        XCTAssertTrue(options.validateEvidence)
        XCTAssertEqual(options.storeRoot.path, "/tmp/cca-stage4-store")
        XCTAssertThrowsError(
            try Stage4MicrobenchmarkPlanCommandOptions.parse([
                "--compose-file", "compose.yaml",
                "--project-name", "demo",
                "--evidence-jsonl", "plan.jsonl",
                "--approval-token", LinuxPodBackend.runtimeApprovalToken
            ])
        )
        XCTAssertThrowsError(
            try Stage4MicrobenchmarkPlanCommandOptions.parse([
                "--compose-file", "compose.yaml",
                "--project-name", "demo",
                "--evidence-jsonl", "plan.jsonl",
                "--measurement-evidence-jsonl", "measurements.jsonl"
            ])
        ) { error in
            XCTAssertEqual(error as? Stage4MicrobenchmarkPlanCommandError, .measurementEvidenceRequiresValidation)
        }
    }

    func testStage4MicrobenchmarkPlanCommandRunnerValidatesMeasurementEvidenceFiles() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-command-runner-\(UUID().uuidString)", isDirectory: true)
        let planURL = tempRoot.appendingPathComponent("stage4-plan.jsonl")
        let operationURL = tempRoot.appendingPathComponent("stage4-operations.jsonl")
        let measurementURL = tempRoot.appendingPathComponent("stage4-measurements.jsonl")
        let storeRoot = tempRoot.appendingPathComponent("store", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let timestamp = "2026-06-12T09:35:00Z"
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("backend-shaped/compose.yaml"), projectName: "backend-shaped")
            .project
        let expectedPlan = Stage4MicrobenchmarkPlanner(store: ProjectRuntimeStore(baseDirectory: storeRoot))
            .plan(project: project, timestamp: timestamp)
        let measurements = completeStage4Measurements(plan: expectedPlan, timestamp: "2026-06-12T09:36:00Z")
        let writer = Stage4MicrobenchmarkJSONLWriter()
        for measurement in measurements {
            try writer.append(measurement, to: measurementURL)
        }

        let result = try Stage4MicrobenchmarkPlanCommandRunner().run(
            options: Stage4MicrobenchmarkPlanCommandOptions(
                composeFile: .init(fixtureURL("backend-shaped/compose.yaml").path),
                projectName: "backend-shaped",
                timestamp: timestamp,
                evidenceJSONL: .init(planURL.path),
                operationEvidenceJSONL: .init(operationURL.path),
                measurementEvidenceJSONL: .init(measurementURL.path),
                validateEvidence: true,
                storeRoot: .init(storeRoot.path)
            )
        )

        XCTAssertEqual(result.plan, expectedPlan)
        XCTAssertEqual(result.operations.count, expectedPlan.probes.count)
        XCTAssertEqual(result.validationDiagnostics, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: planURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: operationURL.path))
    }

    func testStage4MicrobenchmarkPlanCommandValidationFailureDescriptionListsDiagnosticCodes() {
        let error = Stage4MicrobenchmarkPlanCommandError.evidenceValidationFailed([
            Diagnostic(
                severity: .blocking,
                code: "stage4-operation-global-mutation",
                message: "bad"
            )
        ])

        XCTAssertEqual(
            error.description,
            "Stage 4 evidence validation failed: stage4-operation-global-mutation."
        )
    }

    func testStage4MicrobenchmarkExecutorRequiresApprovalBeforeMeasurement() async throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T08:40:00Z")

        do {
            _ = try await Stage4MicrobenchmarkExecutor().measure(plan: record, approval: RuntimeApproval())
            XCTFail("Expected Stage 4 measurements to require approval.")
        } catch let error as RuntimeBackendError {
            XCTAssertEqual(
                error,
                .runtimeMutationRequiresApproval(
                    "Stage 4 microbenchmark measurement requires explicit current-task approval and token \(LinuxPodBackend.runtimeApprovalToken)."
                )
            )
        }
    }

    func testStage4MicrobenchmarkExecutorStopsAfterApprovalUntilRuntimeSliceExists() async throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T08:45:00Z")

        do {
            _ = try await Stage4MicrobenchmarkExecutor().measure(
                plan: record,
                approval: RuntimeApproval(approved: true, token: LinuxPodBackend.runtimeApprovalToken)
            )
            XCTFail("Expected approved Stage 4 measurement scaffold to stop before runtime work.")
        } catch let error as RuntimeBackendError {
            XCTAssertEqual(
                error,
                .runtimeUnavailable(
                    "Stage 4 microbenchmark measurement executor is approval-gated but not implemented in this no-runtime slice."
                )
            )
        }
    }

    func testStage4MicrobenchmarkExecutorUsesApprovedRunnerToProduceMeasurementRecords() async throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T08:50:00Z")

        let measurements = try await Stage4MicrobenchmarkExecutor(
            runner: RecordingStage4MicrobenchmarkRunner(timestamp: "2026-06-12T08:51:00Z")
        ).measure(
            plan: record,
            approval: RuntimeApproval(approved: true, token: LinuxPodBackend.runtimeApprovalToken)
        )

        XCTAssertEqual(measurements.count, record.probes.count)
        XCTAssertEqual(measurements.first?.schemaVersion, Stage4MicrobenchmarkSchema.version)
        XCTAssertEqual(measurements.first?.recordType, Stage4MicrobenchmarkSchema.measurementRecordType)
        XCTAssertEqual(measurements.first?.projectID, record.projectID)
        XCTAssertEqual(measurements.first?.runtimeResourceName, record.runtimeResourceName)
        XCTAssertEqual(measurements.first?.probeID, record.probes.first?.probeID)
        XCTAssertEqual(measurements.first?.kind, record.probes.first?.kind)
        XCTAssertEqual(measurements.first?.environment?.coldOrWarm, record.probes.first?.coldOrWarm)
        XCTAssertEqual(measurements.first?.status, .measured)
        XCTAssertEqual(measurements.first?.hostPhysicalMemoryStatus, .blocked)
        XCTAssertEqual(measurements.first?.metrics.durationSeconds, 1.25)
        XCTAssertEqual(measurements.first?.metrics.blockReadBytes, 1024)
        XCTAssertEqual(measurements.first?.metrics.blockWriteBytes, 2048)
        XCTAssertEqual(measurements.first?.metrics.cleanupResult, "clean")
        XCTAssertEqual(measurements.first?.guest?.cgroupMemoryCurrentBytes, 64 * 1024 * 1024)
        XCTAssertNil(measurements.first?.failure)
    }

    func testLinuxPodStage4MicrobenchmarkRunnerTranslatesProbesIntoScopedOperations() async throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T08:52:00Z")
        let operationExecutor = RecordingStage4OperationExecutor(timestamp: "2026-06-12T08:53:00Z")

        let measurements = try await Stage4MicrobenchmarkExecutor(
            runner: LinuxPodStage4MicrobenchmarkRunner(operationExecutor: operationExecutor)
        ).measure(
            plan: record,
            approval: RuntimeApproval(approved: true, token: LinuxPodBackend.runtimeApprovalToken)
        )

        XCTAssertEqual(measurements.count, record.probes.count)
        XCTAssertEqual(operationExecutor.operations.count, record.probes.count)
        let rootfsOperation = try XCTUnwrap(operationExecutor.operations.first { $0.kind == .rootfsUnpack })
        XCTAssertEqual(rootfsOperation.mutationScope, .reusableCache)
        XCTAssertEqual(rootfsOperation.cleanupExpectation, "preserve-reusable-cache")
        XCTAssertTrue(rootfsOperation.requiresRuntimeApproval)
        XCTAssertFalse(rootfsOperation.mutatesGlobalState)
        let volumeOperation = try XCTUnwrap(operationExecutor.operations.first { $0.kind == .namedVolumeFresh })
        XCTAssertEqual(volumeOperation.mutationScope, .projectNamedVolume)
        XCTAssertEqual(volumeOperation.cleanupExpectation, "preserve-named-volume-by-default")
        let healthcheckOperation = try XCTUnwrap(operationExecutor.operations.first { $0.kind == .healthcheckExec })
        XCTAssertEqual(healthcheckOperation.mutationScope, .runtimeExec)
        XCTAssertFalse(healthcheckOperation.command.isEmpty)

        let healthcheckMeasurement = try XCTUnwrap(measurements.first { $0.kind == .healthcheckExec })
        XCTAssertEqual(healthcheckMeasurement.recordType, Stage4MicrobenchmarkSchema.measurementRecordType)
        XCTAssertEqual(healthcheckMeasurement.timestamp, "2026-06-12T08:53:00Z")
        XCTAssertEqual(healthcheckMeasurement.status, .measured)
        XCTAssertEqual(healthcheckMeasurement.metrics.healthcheckAttempts, 1)
        XCTAssertEqual(healthcheckMeasurement.metrics.cleanupResult, "clean")
        XCTAssertEqual(healthcheckMeasurement.environment?.runtime, .linuxpod)
        XCTAssertEqual(healthcheckMeasurement.hostPhysicalMemoryStatus, .blocked)
        XCTAssertNil(healthcheckMeasurement.failure)
    }

    func testStage4MicrobenchmarkWriterAppendsMeasurementJSONL() async throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T08:55:00Z")
        let measurements = try await Stage4MicrobenchmarkExecutor(
            runner: RecordingStage4MicrobenchmarkRunner(timestamp: "2026-06-12T08:56:00Z")
        ).measure(
            plan: record,
            approval: RuntimeApproval(approved: true, token: LinuxPodBackend.runtimeApprovalToken)
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-measurement-jsonl-\(UUID().uuidString)", isDirectory: true)
        let evidencePath = tempRoot.appendingPathComponent("stage4-measurement.jsonl")
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try Stage4MicrobenchmarkJSONLWriter().append(measurements[0], to: evidencePath)

        let contents = try String(contentsOf: evidencePath, encoding: .utf8)
        let decoded = try JSONDecoder().decode(
            Stage4MicrobenchmarkMeasurementRecord.self,
            from: Data(contents.split(separator: "\n")[0].utf8)
        )
        XCTAssertEqual(decoded, measurements[0])
        XCTAssertTrue(contents.contains("\"record_type\":\"linuxpod-stage4-microbenchmark-measurement\""))
        XCTAssertTrue(contents.contains("\"host_physical_memory_status\":\"blocked\""))
        XCTAssertTrue(contents.contains("\"block_read_bytes\":1024"))
        XCTAssertTrue(contents.contains("\"runtime_context\""))
        XCTAssertTrue(contents.contains("\"vminit_image_digest\":\"sha256:test-vminit-1\""))
        XCTAssertTrue(contents.contains("\"cleanup_proof\""))
        XCTAssertTrue(contents.contains("\"global_cleanup\":\"not-run\""))
    }

    func testStage4MicrobenchmarkEvidenceValidatorReadsMeasurementJSONLFiles() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-measurement-validation-\(UUID().uuidString)", isDirectory: true)
        let planURL = tempRoot.appendingPathComponent("stage4-plan.jsonl")
        let measurementURL = tempRoot.appendingPathComponent("stage4-measurements.jsonl")
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:15:00Z")
        let measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:16:00Z")
        let writer = Stage4MicrobenchmarkJSONLWriter()
        try writer.append(record, to: planURL)
        for measurement in measurements {
            try writer.append(measurement, to: measurementURL)
        }

        let diagnostics = try Stage4MicrobenchmarkEvidenceValidator().validate(
            planEvidenceURL: planURL,
            measurementEvidenceURL: measurementURL
        )

        XCTAssertEqual(diagnostics, [])
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsIncompleteMeasurementEvidence() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:20:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:21:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:21:00Z",
            projectID: "other-project",
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: nil,
            runtimeContext: Self.measurementRuntimeContext(sequence: 1),
            cleanupProof: Self.measurementCleanupProof(sequence: 1),
            status: .measured,
            metrics: Stage4MicrobenchmarkMetrics(),
            guest: nil,
            failure: nil
        )
        let secondProbe = try XCTUnwrap(record.probes.dropFirst().first)
        measurements[1] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:21:01Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: secondProbe,
            environment: measurementEnvironment(
                for: secondProbe,
                runtimeResourceName: record.runtimeResourceName,
                sequence: 2
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: 2),
            cleanupProof: Self.measurementCleanupProof(sequence: 2),
            status: .failed,
            metrics: measurementMetrics(for: secondProbe, sequence: 2),
            guest: measurementGuest(sequence: 2),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(
            Set(diagnostics.map(\.code)),
            [
                "stage4-measurement-project-mismatch",
                "stage4-measurement-environment-missing",
                "stage4-measurement-duration-missing",
                "stage4-measurement-block-io-missing",
                "stage4-measurement-cleanup-missing",
                "stage4-measurement-guest-missing",
                "stage4-measurement-failure-missing"
            ]
        )
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsRuntimeTargetMismatch() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:22:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:23:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:23:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: "cca-linuxpod-other-project",
                runtimeVersion: "test",
                containerizationVersion: "0.26.5",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: BenchmarkLifecycle(rawValue: firstProbe.coldOrWarm) ?? .cold,
                projectRuntimeExistedBeforeRun: false,
                imageCacheStatus: .miss,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .miss,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: 1),
            cleanupProof: Self.measurementCleanupProof(sequence: 1),
            status: .measured,
            metrics: measurementMetrics(for: firstProbe, sequence: 1),
            guest: measurementGuest(sequence: 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-runtime-target-mismatch"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsMissingImageCacheStateForImageProbe() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:24:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:24:30Z")
        let rootfsProbe = try XCTUnwrap(record.probes.first { !$0.imageReference.isEmpty })
        let rootfsIndex = try XCTUnwrap(measurements.firstIndex { $0.probeID == rootfsProbe.probeID })
        measurements[rootfsIndex] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:24:30Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: rootfsProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: record.runtimeResourceName,
                runtimeVersion: "test",
                containerizationVersion: "0.26.5",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: BenchmarkLifecycle(rawValue: rootfsProbe.coldOrWarm) ?? .cold,
                projectRuntimeExistedBeforeRun: false,
                imageCacheStatus: .unknown,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .miss,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: rootfsIndex + 1),
            cleanupProof: Self.measurementCleanupProof(sequence: rootfsIndex + 1),
            status: .measured,
            metrics: measurementMetrics(for: rootfsProbe, sequence: rootfsIndex + 1),
            guest: measurementGuest(sequence: rootfsIndex + 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-image-cache-state-missing"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsMeasurementWithoutRuntimeContext() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:25:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:26:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:26:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: measurementEnvironment(
                for: firstProbe,
                runtimeResourceName: record.runtimeResourceName,
                sequence: 1
            ),
            cleanupProof: Self.measurementCleanupProof(sequence: 1),
            status: .measured,
            metrics: measurementMetrics(for: firstProbe, sequence: 1),
            guest: measurementGuest(sequence: 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-runtime-context-missing"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsMeasurementWithoutCleanupProof() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:30:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:31:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:31:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: measurementEnvironment(
                for: firstProbe,
                runtimeResourceName: record.runtimeResourceName,
                sequence: 1
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: 1),
            status: .measured,
            metrics: measurementMetrics(for: firstProbe, sequence: 1),
            guest: measurementGuest(sequence: 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-cleanup-proof-missing"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsRootfsCacheStateMismatch() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:32:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:33:00Z")
        let rootfsCopyIndex = try XCTUnwrap(measurements.firstIndex { $0.kind == .rootfsCopy })
        let rootfsCopyProbe = try XCTUnwrap(record.probes.first { $0.probeID == measurements[rootfsCopyIndex].probeID })
        measurements[rootfsCopyIndex] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:33:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: rootfsCopyProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: record.runtimeResourceName,
                runtimeVersion: "test",
                containerizationVersion: "0.26.5",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: .warm,
                projectRuntimeExistedBeforeRun: true,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .hit,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: rootfsCopyIndex + 1),
            cleanupProof: Self.measurementCleanupProof(sequence: rootfsCopyIndex + 1),
            status: .measured,
            metrics: measurementMetrics(for: rootfsCopyProbe, sequence: rootfsCopyIndex + 1),
            guest: measurementGuest(sequence: rootfsCopyIndex + 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-rootfs-cache-state-mismatch"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsNamedVolumeLifecycleMismatch() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:34:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:35:00Z")
        let namedVolumeWarmIndex = try XCTUnwrap(measurements.firstIndex { $0.kind == .namedVolumeWarm })
        let namedVolumeWarmProbe = try XCTUnwrap(record.probes.first { $0.probeID == measurements[namedVolumeWarmIndex].probeID })
        measurements[namedVolumeWarmIndex] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:35:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: namedVolumeWarmProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: record.runtimeResourceName,
                runtimeVersion: "test",
                containerizationVersion: "0.26.5",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: .warm,
                projectRuntimeExistedBeforeRun: true,
                imageCacheStatus: .unknown,
                rootfsCacheStatus: .unknown,
                initfsCacheStatus: .hit,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: namedVolumeWarmIndex + 1),
            cleanupProof: Self.measurementCleanupProof(sequence: namedVolumeWarmIndex + 1),
            status: .measured,
            metrics: measurementMetrics(for: namedVolumeWarmProbe, sequence: namedVolumeWarmIndex + 1),
            guest: measurementGuest(sequence: namedVolumeWarmIndex + 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-volume-lifecycle-mismatch"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsContainerizationVersionMismatch() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:36:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:37:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:37:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: record.runtimeResourceName,
                runtimeVersion: "test",
                containerizationVersion: "0.25.0",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: BenchmarkLifecycle(rawValue: firstProbe.coldOrWarm) ?? .cold,
                projectRuntimeExistedBeforeRun: false,
                imageCacheStatus: .miss,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .miss,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: 1),
            cleanupProof: Self.measurementCleanupProof(sequence: 1),
            status: .measured,
            metrics: measurementMetrics(for: firstProbe, sequence: 1),
            guest: measurementGuest(sequence: 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-containerization-version-mismatch"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsMissingContainerizationVersion() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:38:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:39:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:39:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: record.runtimeResourceName,
                runtimeVersion: "test",
                containerizationVersion: nil,
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: BenchmarkLifecycle(rawValue: firstProbe.coldOrWarm) ?? .cold,
                projectRuntimeExistedBeforeRun: false,
                imageCacheStatus: .miss,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .miss,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: 1),
            cleanupProof: Self.measurementCleanupProof(sequence: 1),
            status: .measured,
            metrics: measurementMetrics(for: firstProbe, sequence: 1),
            guest: measurementGuest(sequence: 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-containerization-version-missing"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    func testStage4MicrobenchmarkEvidenceValidatorRejectsInitfsCacheStateMismatch() throws {
        let record = try stage4MicrobenchmarkPlan(timestamp: "2026-06-12T09:40:00Z")
        var measurements = completeStage4Measurements(plan: record, timestamp: "2026-06-12T09:41:00Z")
        let firstProbe = try XCTUnwrap(record.probes.first)
        measurements[0] = Stage4MicrobenchmarkMeasurementRecord(
            timestamp: "2026-06-12T09:41:00Z",
            projectID: record.projectID,
            runtimeResourceName: record.runtimeResourceName,
            probe: firstProbe,
            environment: BenchmarkRunMetadata(
                runtime: .linuxpod,
                targetName: record.runtimeResourceName,
                runtimeVersion: "test",
                containerizationVersion: "0.26.5",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                lifecycle: BenchmarkLifecycle(rawValue: firstProbe.coldOrWarm) ?? .cold,
                projectRuntimeExistedBeforeRun: false,
                imageCacheStatus: .miss,
                rootfsCacheStatus: .miss,
                initfsCacheStatus: .hit,
                volumeExistedBeforeRun: false
            ),
            runtimeContext: Self.measurementRuntimeContext(sequence: 1),
            cleanupProof: Self.measurementCleanupProof(sequence: 1),
            status: .measured,
            metrics: measurementMetrics(for: firstProbe, sequence: 1),
            guest: measurementGuest(sequence: 1),
            failure: nil
        )

        let diagnostics = Stage4MicrobenchmarkEvidenceValidator().validate(
            plan: record,
            measurements: measurements
        )

        XCTAssertEqual(Set(diagnostics.map(\.code)), ["stage4-measurement-initfs-cache-state-mismatch"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .blocking })
    }

    private func stage4MicrobenchmarkPlan(timestamp: String) throws -> Stage4MicrobenchmarkPlanRecord {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cca-stage4-executor-\(UUID().uuidString)", isDirectory: true)
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("backend-shaped/compose.yaml"), projectName: "backend-shaped")
            .project
        return Stage4MicrobenchmarkPlanner(store: ProjectRuntimeStore(baseDirectory: root))
            .plan(project: project, timestamp: timestamp)
    }

    private func benchmarkMetadata(
        lifecycle: BenchmarkLifecycle,
        lifecycleMode: BenchmarkLifecycleMode? = nil,
        seedImageStoreCopied: Bool = false,
        imageCacheStatus: BenchmarkCacheStatus,
        rootfsCacheStatus: BenchmarkCacheStatus,
        initfsCacheStatus: BenchmarkCacheStatus,
        volumeExistedBeforeRun: Bool = false,
        podExistedBeforeRun: Bool = false,
        podReuseVerificationStatus: String? = nil,
        hostPortProbeStatus: String = "notMeasured",
        loadWindowStatus: String = "notMeasured"
    ) -> BenchmarkRunMetadata {
        BenchmarkRunMetadata(
            runtime: .linuxpod,
            runtimeVersion: "test",
            containerizationVersion: "0.26.5",
            appleContainerCLIVersion: nil,
            macOSVersion: "test-macos",
            hostArchitecture: "arm64",
            lifecycle: lifecycle,
            lifecycleMode: lifecycleMode,
            seedImageStoreRequested: seedImageStoreCopied,
            seedImageStoreCopied: seedImageStoreCopied,
            seedImageStoreValidated: seedImageStoreCopied,
            projectRuntimeExistedBeforeRun: podExistedBeforeRun || volumeExistedBeforeRun,
            podExistedBeforeRun: podExistedBeforeRun,
            podReuseVerificationStatus: podReuseVerificationStatus,
            imageCacheStatus: imageCacheStatus,
            rootfsCacheStatus: rootfsCacheStatus,
            initfsCacheStatus: initfsCacheStatus,
            volumeExistedBeforeRun: volumeExistedBeforeRun,
            hostPortProbeStatus: hostPortProbeStatus,
            hostPortPublishingNotImplemented: true,
            loadWindowStatus: loadWindowStatus
        )
    }

    private func completeStage8IterationRecord(
        lifecycleMode: BenchmarkLifecycleMode,
        iteration: Int,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        cleanupResult: String,
        podReuseVerificationStatus: String? = nil,
        rootfsPreparation: [RootfsPreparationBreakdown]? = nil,
        hotplugDiagnostics: HotplugLifecycleDiagnostics? = nil,
        warmServiceRecreate: WarmServiceRecreateMetadata? = nil,
        blockIOAttribution: String? = nil,
        rootfsBlockIOAttribution: String? = nil
    ) -> Phase6BenchmarkIterationRecord {
        Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-12T13:10:0\(iteration)Z",
            project: "cca-linuxpod-stage8-all-warm",
            runLabel: "stage8-all-warm",
            iteration: iteration,
            environment: benchmarkMetadata(
                lifecycle: .persistentWarmProjectRuntime,
                lifecycleMode: lifecycleMode,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .hit,
                initfsCacheStatus: .hit,
                volumeExistedBeforeRun: true,
                podExistedBeforeRun: true,
                podReuseVerificationStatus: podReuseVerificationStatus
            ),
            status: .measured,
            durationsSeconds: Phase6BenchmarkDurations(
                up: 5.0,
                status: 0.01,
                logs: 0.01,
                cleanup: 0.25,
                rootfsPrep: 0.02,
                initfsPrep: 0.02,
                volumeCreateOrReuse: 0.01,
                podCreateOrReuse: 0.01,
                containerStart: 0.1,
                healthcheck: 0.4
            ),
            guest: HostFootprintGuestStats(
                cgroupMemoryCurrentBytes: 128 * 1024 * 1024,
                cgroupMemoryLimitBytes: nil,
                cgroupMemoryLimitUnlimited: true,
                processCount: 7,
                cpuUsageUsec: 500,
                blockReadBytes: 2048,
                blockWriteBytes: 4096,
                processRSSBytes: 64 * 1024 * 1024
            ),
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 16,
            cleanupStateDirectoryExistsAfterCleanup: cleanupStateDirectoryExistsAfterCleanup,
            healthcheckAttempts: 1,
            dataFootprintBytes: 32 * 1024 * 1024,
            cleanupResult: cleanupResult,
            failure: nil,
            rootfsPreparation: rootfsPreparation,
            hotplugDiagnostics: hotplugDiagnostics,
            warmServiceRecreate: warmServiceRecreate,
            blockIOAttribution: blockIOAttribution,
            rootfsBlockIOAttribution: rootfsBlockIOAttribution
        )
    }

    private func stage10BIteration(
        requestedStrategy: RootfsMaterializationStrategy,
        runLabel: String,
        upDuration: Double,
        readinessDuration: Double,
        rootfsPreparation: [RootfsPreparationBreakdown],
        rootfsWorkAvoided: EvidenceTruthValue
    ) -> Phase6BenchmarkIterationRecord {
        Phase6BenchmarkIterationRecord(
            timestamp: "2026-06-13T14:20:00Z",
            project: "cca-linuxpod-\(runLabel)",
            runLabel: runLabel,
            iteration: 1,
            environment: benchmarkMetadata(
                lifecycle: .persistentWarmProjectRuntime,
                lifecycleMode: .rootfsCacheHitRuntime,
                imageCacheStatus: .hit,
                rootfsCacheStatus: .hit,
                initfsCacheStatus: .hit
            ),
            status: .measured,
            durationsSeconds: Phase6BenchmarkDurations(
                up: upDuration,
                status: 0.02,
                logs: 0.01,
                cleanup: 0.25,
                rootfsPrep: 0.12,
                initfsPrep: 0.02,
                volumeCreateOrReuse: 0.01,
                podCreateOrReuse: 4.0,
                containerStart: 1.1,
                healthcheck: readinessDuration
            ),
            guest: HostFootprintGuestStats(
                cgroupMemoryCurrentBytes: 128 * 1024 * 1024,
                cgroupMemoryLimitBytes: nil,
                cgroupMemoryLimitUnlimited: true,
                processCount: 7,
                cpuUsageUsec: 500,
                blockReadBytes: rootfsWorkAvoided == .true ? 1024 : 2048,
                blockWriteBytes: rootfsWorkAvoided == .true ? 2048 : 4096,
                processRSSBytes: 64 * 1024 * 1024
            ),
            hostPhysicalMemoryStatus: .blocked,
            actionCount: 16,
            cleanupStateDirectoryExistsAfterCleanup: false,
            healthcheckAttempts: 3,
            jobAttempts: 2,
            successfulJobCount: 2,
            jobExitCodes: ["migrate=0", "seed=0"],
            dataFootprintBytes: 32 * 1024 * 1024,
            cleanupResult: "clean",
            failure: nil,
            rootfsPreparation: rootfsPreparation,
            blockIOAttribution: "wholeRunOnly",
            rootfsBlockIOAttribution: "notMeasured"
        )
    }

    private func stage10BStrategySummary(
        requestedStrategy: RootfsMaterializationStrategy,
        observedStrategies: [RootfsMaterializationStrategy],
        upDuration: Double,
        readinessDuration: Double,
        rootfsWorkAvoided: EvidenceTruthValue
    ) -> Stage10BStrategyRuntimeSummary {
        Stage10BStrategyRuntimeSummary(
            requestedStrategy: requestedStrategy,
            observedStrategies: observedStrategies,
            measured: true,
            upDurationSeconds: upDuration,
            readinessDurationSeconds: readinessDuration,
            rootfsPrepDurationSeconds: 0.12,
            projectRootfsMaterializeDurationSeconds: 0.04,
            containerRootfsMaterializeDurationSeconds: 0.05,
            blockReadBytes: rootfsWorkAvoided == .true ? 1024 : 2048,
            blockWriteBytes: rootfsWorkAvoided == .true ? 2048 : 4096,
            healthcheckAttempts: 3,
            jobAttempts: 2,
            successfulJobCount: 2,
            volumeExistedBeforeRun: false,
            volumeCreateOrReuseDurationSeconds: 0.01,
            dataFootprintBytes: 32 * 1024 * 1024,
            cleanupResult: "clean",
            cleanupStateDirectoryExistsAfterCleanup: false,
            hostPortProbeStatus: "notMeasured",
            loadWindowStatus: "notMeasured",
            rootfsWorkAvoided: rootfsWorkAvoided,
            failure: nil
        )
    }

    private func stage9BProbeRecord(
        probeCase: Stage9BHotplugProbeCase,
        podObjectCreated: Bool = true,
        podCreateCalled: Bool = false,
        podCreateSucceeded: Bool = false,
        podObjectPhase: String? = "created",
        podCreatedStateKnown: Bool = true,
        podActuallyRunning: Bool? = false,
        initialContainerRegisteredBeforeCreate: Bool = false,
        initialContainerStarted: Bool = false,
        postCreateAddContainerAttempted: Bool = false,
        postCreateAddContainerSucceeded: Bool = false,
        addContainerPhase: Stage9BAddContainerPhase,
        hotplugAttempted: Bool = false,
        hotplugSucceeded: Bool = false,
        hotplugUnsupported: Bool = false,
        duplicateContainerDetected: Bool = false,
        failurePhase: String? = nil,
        failureErrorType: String? = nil,
        failureErrorMessage: String? = nil,
        mutationBeforeFailure: EvidenceTruthValue = .false,
        cleanupResult: String = "clean",
        cleanupStateDirectoryExistsAfterCleanup: Bool = false,
        leftoverPathsCount: Int = 0
    ) -> Stage9BHotplugProbeRecord {
        Stage9BHotplugProbeRecord(
            timestamp: "2026-06-13T00:00:00Z",
            project: "cca-linuxpod-stage9b-\(probeCase.rawValue)",
            probeCase: probeCase,
            podObjectCreated: podObjectCreated,
            podCreateCalled: podCreateCalled,
            podCreateSucceeded: podCreateSucceeded,
            podObjectPhase: podObjectPhase,
            podCreatedStateKnown: podCreatedStateKnown,
            podActuallyRunning: podActuallyRunning,
            initialContainerRegisteredBeforeCreate: initialContainerRegisteredBeforeCreate,
            initialContainerStarted: initialContainerStarted,
            postCreateAddContainerAttempted: postCreateAddContainerAttempted,
            postCreateAddContainerSucceeded: postCreateAddContainerSucceeded,
            addContainerPhase: addContainerPhase,
            hotplugAttempted: hotplugAttempted,
            hotplugSucceeded: hotplugSucceeded,
            hotplugUnsupported: hotplugUnsupported,
            duplicateContainerDetected: duplicateContainerDetected,
            failurePhase: failurePhase,
            failureErrorType: failureErrorType,
            failureErrorMessage: failureErrorMessage,
            mutationBeforeFailure: mutationBeforeFailure,
            cleanupResult: cleanupResult,
            cleanupStateDirectoryExistsAfterCleanup: cleanupStateDirectoryExistsAfterCleanup,
            leftoverPathsCount: leftoverPathsCount,
            runtimePackageVersion: "0.26.5",
            macOSVersion: "test-macos",
            containerizationVersion: "0.26.5"
        )
    }

    private func stage9DProbeRecord(
        probeCases: [Stage9DProbeCase],
        status: Stage9DProbeStatus = .measured,
        provider: Stage9DProviderEvidence,
        rootfs: Stage9DRootfsEvidence,
        hotplug: Stage9DHotplugEvidence,
        cleanup: Stage9DCleanupEvidence = .clean,
        interpretation: Stage9DInterpretationEvidence,
        hostPortProbeStatus: String = "notMeasured",
        loadWindowStatus: String = "notMeasured"
    ) -> Stage9DHotplugProviderProbeRecord {
        Stage9DHotplugProviderProbeRecord(
            timestamp: "2026-06-13T00:00:00Z",
            status: status,
            containerizationVersion: "0.33.4",
            containerizationRevision: "9275f365dd555c8f072e7d250d809f5eb7bdd746",
            macOSVersion: "test-macos",
            hostArchitecture: "arm64",
            probeCases: probeCases,
            provider: provider,
            rootfs: rootfs,
            hotplug: hotplug,
            cleanup: cleanup,
            interpretation: interpretation,
            hostPortTTFBSeconds: nil,
            hostPortProbeStatus: hostPortProbeStatus,
            loadWindowSeconds: nil,
            loadWindowStatus: loadWindowStatus
        )
    }

    private func stage10AProbeRecord(
        status: Stage10ARootfsMaterializationStatus = .measured,
        strategy: RootfsMaterializationDiagnostics,
        cleanup: RootfsMaterializationCleanupEvidence = .clean,
        interpretation: RootfsMaterializationInterpretation = .diagnosticOnly
    ) -> RootfsMaterializationProbeRecord {
        RootfsMaterializationProbeRecord(
            timestamp: "2026-06-13T00:00:00Z",
            status: status,
            environment: RootfsMaterializationEnvironment(
                containerizationVersion: "0.33.4",
                containerizationRevision: "9275f365dd555c8f072e7d250d809f5eb7bdd746",
                macOSVersion: "test-macos",
                hostArchitecture: "arm64",
                filesystemType: "apfs",
                adapterOwnedStateRoot: "<repo>/.container-compose-adapter",
                runtimePath: "<repo>/.container-compose-adapter/cca-linuxpod-stage10a-probe/runtime",
                runtimePathRedacted: true
            ),
            strategy: strategy,
            paths: RootfsMaterializationPaths(
                sourceRootfsPath: "<repo>/.container-compose-adapter/cache/rootfs/postgres.ext4",
                projectRootfsPath: "<repo>/.container-compose-adapter/cca-linuxpod-stage10a-probe/runtime/rootfs/postgres.ext4",
                containerRootfsPath: "<repo>/.container-compose-adapter/cca-linuxpod-stage10a-probe/runtime/rootfs/containers/db.ext4",
                sourceAndDestinationSameVolume: true
            ),
            durationsSeconds: RootfsMaterializationDurations(
                imageReferenceLookup: 0.01,
                imageStoreLookup: 0.02,
                baseRootfsCacheLookup: 0.001,
                baseRootfsUnpack: 0,
                projectRootfsMaterialize: 0.04,
                containerRootfsMaterialize: 0.05,
                mountPrepare: 0.001,
                cleanup: 0.01,
                totalRootfsPrep: 0.121
            ),
            sizesBytes: RootfsMaterializationSizes(
                sourceRootfs: 2_147_483_648,
                projectRootfs: 2_147_483_648,
                containerRootfs: 2_147_483_648,
                apparentSize: 2_147_483_648,
                allocatedSize: 1_048_576,
                bytesCopiedIfKnown: strategy.copySucceeded ? 2_147_483_648 : nil
            ),
            io: RootfsMaterializationIOEvidence(
                blockReadBytesWholeRun: nil,
                blockWriteBytesWholeRun: nil,
                phaseBlockIOAttribution: "notMeasured"
            ),
            correctness: RootfsMaterializationCorrectnessEvidence(
                projectRootfsExists: true,
                containerRootfsExists: true,
                containerRootfsReadable: true,
                ext4ImageLooksValid: true,
                noMutationOfBaseRootfs: true,
                baseRootfsChecksumBefore: nil,
                baseRootfsChecksumAfter: nil,
                baseRootfsUnchanged: .true
            ),
            cleanup: cleanup,
            interpretation: interpretation
        )
    }

    private func readStage9BProbeRecords(_ url: URL) throws -> [Stage9BHotplugProbeRecord] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try contents.split(separator: "\n").map { line in
            try decoder.decode(Stage9BHotplugProbeRecord.self, from: Data(line.utf8))
        }
    }

    private func readFirstPhase6IterationRecord(_ url: URL) throws -> Phase6BenchmarkIterationRecord {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let firstLine = try XCTUnwrap(contents.split(separator: "\n").first)
        return try JSONDecoder().decode(Phase6BenchmarkIterationRecord.self, from: Data(firstLine.utf8))
    }

    private func completeStage4Measurements(
        plan: Stage4MicrobenchmarkPlanRecord,
        timestamp: String
    ) -> [Stage4MicrobenchmarkMeasurementRecord] {
        plan.probes.enumerated().map { index, probe in
            Stage4MicrobenchmarkMeasurementRecord(
                timestamp: timestamp,
                projectID: plan.projectID,
                runtimeResourceName: plan.runtimeResourceName,
                probe: probe,
                environment: measurementEnvironment(
                    for: probe,
                    runtimeResourceName: plan.runtimeResourceName,
                    sequence: index + 1
                ),
                runtimeContext: Self.measurementRuntimeContext(sequence: index + 1),
                cleanupProof: Self.measurementCleanupProof(sequence: index + 1),
                status: .measured,
                metrics: measurementMetrics(for: probe, sequence: index + 1),
                guest: measurementGuest(sequence: index + 1),
                failure: nil
            )
        }
    }

    private func measurementEnvironment(
        for probe: Stage4MicrobenchmarkProbe,
        runtimeResourceName: String,
        sequence: Int
    ) -> BenchmarkRunMetadata {
        let lifecycle = BenchmarkLifecycle(rawValue: probe.coldOrWarm) ?? .warm
        let rootfsCacheStatus: BenchmarkCacheStatus
        switch probe.kind {
        case .rootfsUnpack:
            rootfsCacheStatus = .miss
        case .rootfsCopy, .apfsClone:
            rootfsCacheStatus = .hit
        case .namedVolumeFresh, .namedVolumeWarm, .healthcheckExec:
            rootfsCacheStatus = .unknown
        }
        return BenchmarkRunMetadata(
            runtime: .linuxpod,
            targetName: runtimeResourceName,
            runtimeVersion: "test",
            containerizationVersion: "0.26.5",
            appleContainerCLIVersion: nil,
            macOSVersion: "test-macos",
            hostArchitecture: "arm64",
            lifecycle: lifecycle,
            projectRuntimeExistedBeforeRun: lifecycle == .warm,
            imageCacheStatus: probe.imageReference.isEmpty ? .unknown : (sequence == 1 ? .miss : .hit),
            rootfsCacheStatus: rootfsCacheStatus,
            initfsCacheStatus: sequence == 1 ? .miss : .hit,
            volumeExistedBeforeRun: probe.kind == .namedVolumeWarm
        )
    }

    private static func measurementRuntimeContext(sequence: Int) -> Stage4MicrobenchmarkRuntimeContext {
        Stage4MicrobenchmarkRuntimeContext(
            containerizationVersion: "0.26.5",
            rootfsFormatVersion: "ext4-v1",
            vminitImageReference: "ghcr.io/apple/containerization/vminit:0.26.5",
            vminitImageDigest: "sha256:test-vminit-\(sequence)",
            kernelPath: "/System/Library/Kernels/kernel",
            kernelVersion: "test-kernel-\(sequence)",
            kernelArchitecture: "arm64",
            initfsCacheStatus: sequence == 1 ? .miss : .hit
        )
    }

    private static func measurementCleanupProof(sequence: Int) -> Stage4MicrobenchmarkCleanupProof {
        Stage4MicrobenchmarkCleanupProof(
            cleanupDurationSeconds: Double(sequence) / 100.0,
            runtimeCleanup: "clean",
            volumeCleanup: "preserved-by-default",
            portCleanup: "released",
            logCleanup: "clean",
            metricsCleanup: "clean",
            cacheCleanup: "preserved",
            globalCleanup: "not-run",
            staleFileCount: 0,
            staleProcessCount: 0,
            stalePortCount: 0
        )
    }

    private func measurementMetrics(
        for probe: Stage4MicrobenchmarkProbe,
        sequence: Int
    ) -> Stage4MicrobenchmarkMetrics {
        let duration = Double(sequence) / 10.0
        switch probe.kind {
        case .rootfsUnpack:
            return Stage4MicrobenchmarkMetrics(
                durationSeconds: duration,
                blockReadBytes: UInt64(sequence * 4096),
                blockWriteBytes: UInt64(sequence * 8192),
                cleanupResult: "clean"
            )
        case .rootfsCopy:
            return Stage4MicrobenchmarkMetrics(
                durationSeconds: duration,
                bytesCopied: UInt64(sequence * 1_048_576),
                blockReadBytes: UInt64(sequence * 4096),
                blockWriteBytes: UInt64(sequence * 8192),
                cleanupResult: "clean"
            )
        case .apfsClone:
            return Stage4MicrobenchmarkMetrics(
                durationSeconds: duration,
                blockWriteBytes: UInt64(sequence * 1024),
                cloneSuccess: true,
                cleanupResult: "clean"
            )
        case .namedVolumeFresh, .namedVolumeWarm:
            return Stage4MicrobenchmarkMetrics(
                durationSeconds: duration,
                blockReadBytes: UInt64(sequence * 2048),
                blockWriteBytes: UInt64(sequence * 4096),
                cleanupResult: "clean"
            )
        case .healthcheckExec:
            return Stage4MicrobenchmarkMetrics(
                durationSeconds: duration,
                blockReadBytes: UInt64(sequence * 512),
                healthcheckAttempts: 1,
                timeoutSeconds: 2,
                cleanupResult: "clean"
            )
        }
    }

    private func measurementGuest(sequence: Int) -> HostFootprintGuestStats {
        HostFootprintGuestStats(
            cgroupMemoryCurrentBytes: UInt64(sequence) * 16 * 1024 * 1024,
            cgroupMemoryLimitBytes: 512 * 1024 * 1024,
            processCount: 2,
            cpuUsageUsec: UInt64(sequence * 100),
            blockReadBytes: UInt64(sequence * 4096),
            blockWriteBytes: UInt64(sequence * 8192)
        )
    }

    private struct RecordingStage4MicrobenchmarkRunner: Stage4MicrobenchmarkRunning {
        let timestamp: String

        func measure(
            probe: Stage4MicrobenchmarkProbe,
            plan: Stage4MicrobenchmarkPlanRecord,
            sequence: Int
        ) async throws -> Stage4MicrobenchmarkMeasurementRecord {
            Stage4MicrobenchmarkMeasurementRecord(
                timestamp: timestamp,
                projectID: plan.projectID,
                runtimeResourceName: plan.runtimeResourceName,
                probe: probe,
                environment: BenchmarkRunMetadata(
                    runtime: .linuxpod,
                    targetName: plan.runtimeResourceName,
                    runtimeVersion: "test",
                    containerizationVersion: "0.26.5",
                    appleContainerCLIVersion: nil,
                    macOSVersion: "test-macos",
                    hostArchitecture: "arm64",
                    lifecycle: BenchmarkLifecycle(rawValue: probe.coldOrWarm) ?? .warm,
                    projectRuntimeExistedBeforeRun: sequence > 1,
                    imageCacheStatus: sequence > 1 ? .hit : .miss,
                    rootfsCacheStatus: sequence > 1 ? .hit : .miss,
                    initfsCacheStatus: sequence == 1 ? .miss : .hit,
                    volumeExistedBeforeRun: sequence > 1
                ),
                runtimeContext: RuntimeContractTests.measurementRuntimeContext(sequence: sequence),
                cleanupProof: RuntimeContractTests.measurementCleanupProof(sequence: sequence),
                status: .measured,
                metrics: Stage4MicrobenchmarkMetrics(
                    durationSeconds: Double(sequence) + 0.25,
                    bytesCopied: UInt64(sequence * 4096),
                    blockReadBytes: UInt64(sequence * 1024),
                    blockWriteBytes: UInt64(sequence * 2048),
                    cleanupResult: "clean"
                ),
                guest: HostFootprintGuestStats(
                    cgroupMemoryCurrentBytes: UInt64(sequence) * 64 * 1024 * 1024,
                    cgroupMemoryLimitBytes: 512 * 1024 * 1024,
                    processCount: 3,
                    cpuUsageUsec: 500,
                    blockReadBytes: UInt64(sequence * 1024),
                    blockWriteBytes: UInt64(sequence * 2048)
                ),
                failure: nil
            )
        }
    }

    private final class RecordingStage4OperationExecutor: Stage4MicrobenchmarkOperationExecuting, @unchecked Sendable {
        let timestamp: String
        var operations: [Stage4MicrobenchmarkOperation] = []

        init(timestamp: String) {
            self.timestamp = timestamp
        }

        func measure(
            operation: Stage4MicrobenchmarkOperation,
            plan: Stage4MicrobenchmarkPlanRecord,
            sequence: Int
        ) async throws -> Stage4MicrobenchmarkOperationResult {
            operations.append(operation)
            return Stage4MicrobenchmarkOperationResult(
                timestamp: timestamp,
                environment: BenchmarkRunMetadata(
                    runtime: .linuxpod,
                    targetName: plan.runtimeResourceName,
                    runtimeVersion: "test",
                    containerizationVersion: "0.26.5",
                    appleContainerCLIVersion: nil,
                    macOSVersion: "test-macos",
                    hostArchitecture: "arm64",
                    lifecycle: BenchmarkLifecycle(rawValue: operation.coldOrWarm) ?? .warm,
                    projectRuntimeExistedBeforeRun: operation.coldOrWarm == BenchmarkLifecycle.warm.rawValue,
                    imageCacheStatus: operation.imageReference.isEmpty ? .unknown : .hit,
                    rootfsCacheStatus: operation.imageReference.isEmpty ? .unknown : .hit,
                    initfsCacheStatus: sequence == 1 ? .miss : .hit,
                    volumeExistedBeforeRun: operation.coldOrWarm == BenchmarkLifecycle.warm.rawValue
                ),
                runtimeContext: RuntimeContractTests.measurementRuntimeContext(sequence: sequence),
                cleanupProof: RuntimeContractTests.measurementCleanupProof(sequence: sequence),
                status: .measured,
                metrics: Stage4MicrobenchmarkMetrics(
                    durationSeconds: 0.15,
                    blockReadBytes: 512,
                    blockWriteBytes: 128,
                    healthcheckAttempts: operation.kind == .healthcheckExec ? 1 : nil,
                    cleanupResult: "clean"
                ),
                guest: HostFootprintGuestStats(
                    cgroupMemoryCurrentBytes: 32 * 1024 * 1024,
                    cgroupMemoryLimitBytes: 512 * 1024 * 1024,
                    processCount: 2,
                    cpuUsageUsec: 100,
                    blockReadBytes: 512,
                    blockWriteBytes: 128
                ),
                failure: nil
            )
        }
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

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/evidence/fixtures")
            .appendingPathComponent(name)
    }
}

private extension RootfsPreparationBreakdown {
    static let completeTestBreakdown = RootfsPreparationBreakdown(
        actionKind: "prepareImageRootfs",
        resourceName: "mirror.gcr.io/library/postgres:16-alpine",
        image: "mirror.gcr.io/library/postgres:16-alpine",
        imageReferenceResolveDuration: 0.12,
        imageStoreLookupDuration: nil,
        platformValidationDuration: 0.03,
        imagePullDuration: nil,
        baseRootfsCacheLookupDuration: 0.01,
        baseRootfsCacheHit: true,
        baseRootfsCreateOrUnpackDuration: 0.0,
        containerRootfsMaterializeDuration: nil,
        containerRootfsCopyDuration: nil,
        containerRootfsCloneDuration: nil,
        containerRootfsMountPrepareDuration: nil,
        rootfsBytesCopied: 2_147_483_648,
        rootfsSourcePath: "/tmp/cache/postgres.ext4",
        rootfsDestinationPath: "/tmp/runtime/rootfs/postgres.ext4",
        rootfsMaterializationStrategy: .copy,
        rootfsWorkAvoided: .false,
        rootfsCacheClaim: .baseArtifactHit
    )

    static let clonefileTestBreakdown = RootfsPreparationBreakdown(
        actionKind: "prepareImageRootfs",
        resourceName: "mirror.gcr.io/library/postgres:16-alpine",
        image: "mirror.gcr.io/library/postgres:16-alpine",
        imageReferenceResolveDuration: 0.12,
        imageStoreLookupDuration: nil,
        platformValidationDuration: 0.03,
        imagePullDuration: nil,
        baseRootfsCacheLookupDuration: 0.01,
        baseRootfsCacheHit: true,
        baseRootfsCreateOrUnpackDuration: 0.0,
        containerRootfsMaterializeDuration: 0.04,
        containerRootfsCopyDuration: nil,
        containerRootfsCloneDuration: 0.04,
        containerRootfsMountPrepareDuration: 0.01,
        rootfsBytesCopied: nil,
        rootfsSourcePath: "/tmp/cache/postgres.ext4",
        rootfsDestinationPath: "/tmp/runtime/rootfs/postgres.ext4",
        rootfsMaterializationStrategy: .clonefile,
        rootfsWorkAvoided: .true,
        rootfsCacheClaim: .baseArtifactHit
    )
}

private extension Stage9DProviderEvidence {
    static let installedOnly = Stage9DProviderEvidence(
        extensionInstalled: true,
        extensionType: "CCAHotplugFeasibilityExtension",
        linuxPodConfigExtensionCount: 1,
        vmConfigExtensionCount: 1,
        vmInstanceType: "VZVirtualMachineInstance",
        hotplugProviderInstalled: true,
        hotplugProviderType: "CCAHotplugFeasibilityProvider",
        providerDidCreateCalled: true,
        providerHotplugCalled: false,
        providerHotplugVirtioFSCalled: false,
        providerReleaseHotplugCalled: false,
        providerReleaseVirtioFSCalled: false
    )

    static let called = Stage9DProviderEvidence(
        extensionInstalled: true,
        extensionType: "CCAHotplugFeasibilityExtension",
        linuxPodConfigExtensionCount: 1,
        vmConfigExtensionCount: 1,
        vmInstanceType: "VZVirtualMachineInstance",
        hotplugProviderInstalled: true,
        hotplugProviderType: "CCAHotplugFeasibilityProvider",
        providerDidCreateCalled: true,
        providerHotplugCalled: true,
        providerHotplugVirtioFSCalled: false,
        providerReleaseHotplugCalled: true,
        providerReleaseVirtioFSCalled: false
    )
}

private extension Stage9DRootfsEvidence {
    static let notAttempted = Stage9DRootfsEvidence(
        rootfsMountType: nil,
        rootfsIsBlock: nil,
        rootfsIsExt4: nil,
        rootfsSourcePath: nil,
        rootfsSourcePathRedacted: true,
        rootfsAttachStrategy: .none,
        attachedFilesystemSource: nil,
        attachedFilesystemSourceKnown: false
    )

    static let blockAttachUnsupported = Stage9DRootfsEvidence(
        rootfsMountType: "block",
        rootfsIsBlock: true,
        rootfsIsExt4: true,
        rootfsSourcePath: "<repo>/.container-compose-adapter/projects/stage9d/rootfs/second.ext4",
        rootfsSourcePathRedacted: true,
        rootfsAttachStrategy: .unsupported,
        attachedFilesystemSource: nil,
        attachedFilesystemSourceKnown: false
    )

    static let publicBlockAttached = Stage9DRootfsEvidence(
        rootfsMountType: "block",
        rootfsIsBlock: true,
        rootfsIsExt4: true,
        rootfsSourcePath: "<repo>/.container-compose-adapter/projects/stage9d/rootfs/second.ext4",
        rootfsSourcePathRedacted: true,
        rootfsAttachStrategy: .publicVZStorageAttach,
        attachedFilesystemSource: "/dev/vdb",
        attachedFilesystemSourceKnown: true
    )

    static let fakeAttachedFilesystem = Stage9DRootfsEvidence(
        rootfsMountType: "block",
        rootfsIsBlock: true,
        rootfsIsExt4: true,
        rootfsSourcePath: "<repo>/.container-compose-adapter/projects/stage9d/rootfs/second.ext4",
        rootfsSourcePathRedacted: true,
        rootfsAttachStrategy: .none,
        attachedFilesystemSource: nil,
        attachedFilesystemSourceKnown: false
    )
}

private extension Stage9DHotplugEvidence {
    static let notAttempted = Stage9DHotplugEvidence(
        preCreateRegistrationSucceeded: false,
        podCreateSucceeded: false,
        firstContainerStarted: false,
        postCreateAddContainerAttempted: false,
        postCreateAddContainerReachedProvider: false,
        postCreateAddContainerSucceeded: false,
        secondContainerStarted: false,
        realHotplugSucceeded: false,
        hotplugUnsupported: false,
        providerInstalledButAttachUnsupported: false,
        publicBlockHotplugAPIMissing: false,
        failurePhase: nil,
        failureErrorType: nil,
        failureErrorMessage: nil,
        blocker: .none
    )

    static let providerCalledButNotAttached = Stage9DHotplugEvidence(
        preCreateRegistrationSucceeded: true,
        podCreateSucceeded: true,
        firstContainerStarted: true,
        postCreateAddContainerAttempted: true,
        postCreateAddContainerReachedProvider: true,
        postCreateAddContainerSucceeded: false,
        secondContainerStarted: false,
        realHotplugSucceeded: false,
        hotplugUnsupported: false,
        providerInstalledButAttachUnsupported: true,
        publicBlockHotplugAPIMissing: true,
        failurePhase: "addContainer",
        failureErrorType: "unsupported",
        failureErrorMessage: "public block hotplug attach API missing",
        blocker: .publicBlockHotplugAPIMissing
    )

    static let realSecondContainerStarted = Stage9DHotplugEvidence(
        preCreateRegistrationSucceeded: true,
        podCreateSucceeded: true,
        firstContainerStarted: true,
        postCreateAddContainerAttempted: true,
        postCreateAddContainerReachedProvider: true,
        postCreateAddContainerSucceeded: true,
        secondContainerStarted: true,
        realHotplugSucceeded: true,
        hotplugUnsupported: false,
        providerInstalledButAttachUnsupported: false,
        publicBlockHotplugAPIMissing: false,
        failurePhase: nil,
        failureErrorType: nil,
        failureErrorMessage: nil,
        blocker: .none
    )
}

private extension Stage9DCleanupEvidence {
    static let clean = Stage9DCleanupEvidence(
        cleanupResult: "clean",
        cleanupStateDirectoryExistsAfterCleanup: false,
        leftoverPathsCount: 0,
        providerReleaseCalled: true,
        attachedDeviceDetached: nil,
        zeroAdapterOwnedLeftovers: true
    )
}

private extension Stage9DInterpretationEvidence {
    static let providerSpikeNeedsMoreWork = Stage9DInterpretationEvidence(
        productHotplugAvailable: false,
        productShouldDependOnHotplug: false,
        nextRecommendedPath: .providerSpikeNeedsMoreWork
    )

    static let publicBlockHotplugAPIMissing = Stage9DInterpretationEvidence(
        productHotplugAvailable: false,
        productShouldDependOnHotplug: false,
        nextRecommendedPath: .upstreamIssue
    )

    static let hotplugAvailable = Stage9DInterpretationEvidence(
        productHotplugAvailable: true,
        productShouldDependOnHotplug: false,
        nextRecommendedPath: .forcedWarmServiceRecreateWithHotplug
    )
}

private extension RootfsMaterializationDiagnostics {
    static let fullCopy = RootfsMaterializationDiagnostics(
        requestedStrategy: .fullCopy,
        actualStrategy: .fullCopy,
        fallbackStrategy: nil,
        fallbackReason: nil,
        cloneSupported: false,
        cloneAttempted: false,
        cloneReturnedSuccess: false,
        cloneVerified: false,
        cloneVerificationStrength: .notApplicable,
        cloneSucceeded: false,
        copyAttempted: true,
        copySucceeded: true,
        publicCloneAPIMissing: false,
        byteForByteCopyAvoided: .false,
        rootfsWorkAvoided: .false
    )

    static let cloneSuccess = RootfsMaterializationDiagnostics(
        requestedStrategy: .clonefile,
        actualStrategy: .clonefile,
        fallbackStrategy: nil,
        fallbackReason: nil,
        cloneSupported: true,
        cloneAttempted: true,
        cloneReturnedSuccess: true,
        cloneVerified: true,
        cloneVerificationStrength: .strong,
        cloneSucceeded: true,
        copyAttempted: false,
        copySucceeded: false,
        publicCloneAPIMissing: false,
        byteForByteCopyAvoided: .true,
        rootfsWorkAvoided: .true
    )

    static let cloneFallback = RootfsMaterializationDiagnostics(
        requestedStrategy: .clonefile,
        actualStrategy: .fullCopy,
        fallbackStrategy: .fullCopy,
        fallbackReason: "clonefile returned ENOTSUP; fell back to fullCopy",
        cloneSupported: false,
        cloneAttempted: true,
        cloneReturnedSuccess: false,
        cloneVerified: false,
        cloneVerificationStrength: .notApplicable,
        cloneSucceeded: false,
        copyAttempted: true,
        copySucceeded: true,
        publicCloneAPIMissing: false,
        byteForByteCopyAvoided: .false,
        rootfsWorkAvoided: .false
    )

    static let unsupportedClone = RootfsMaterializationDiagnostics(
        requestedStrategy: .copyfileClone,
        actualStrategy: .unsupported,
        fallbackStrategy: nil,
        fallbackReason: "public clone API unavailable",
        cloneSupported: false,
        cloneAttempted: false,
        cloneReturnedSuccess: false,
        cloneVerified: false,
        cloneVerificationStrength: .notApplicable,
        cloneSucceeded: false,
        copyAttempted: false,
        copySucceeded: false,
        publicCloneAPIMissing: true,
        byteForByteCopyAvoided: .unknown,
        rootfsWorkAvoided: .unknown
    )

    static let cloneSuccessWithUnknownVerification = RootfsMaterializationDiagnostics(
        requestedStrategy: .copyfileClone,
        actualStrategy: .copyfileClone,
        fallbackStrategy: nil,
        fallbackReason: nil,
        cloneSupported: true,
        cloneAttempted: true,
        cloneReturnedSuccess: true,
        cloneVerified: false,
        cloneVerificationStrength: .unknown,
        cloneSucceeded: true,
        copyAttempted: false,
        copySucceeded: false,
        publicCloneAPIMissing: false,
        byteForByteCopyAvoided: .true,
        rootfsWorkAvoided: .true
    )
}

private extension RootfsMaterializationCleanupEvidence {
    static let clean = RootfsMaterializationCleanupEvidence(
        cleanupResult: "clean",
        cleanupStateDirectoryExistsAfterCleanup: false,
        leftoverPathsCount: 0,
        zeroAdapterOwnedLeftovers: true
    )
}

private extension RootfsMaterializationInterpretation {
    static let diagnosticOnly = RootfsMaterializationInterpretation(
        materializationImproved: false,
        productReady: false,
        nextRecommendedPath: .keepFullCopy
    )

    static let productReadyFixture = RootfsMaterializationInterpretation(
        materializationImproved: true,
        productReady: true,
        nextRecommendedPath: .useClonefileForRootfs
    )
}

private extension HotplugLifecycleDiagnostics {
    static func completeTest(
        podReuseClaim: PodReuseClaim = .liveObject,
        hotplugSucceeded: Bool = true
    ) -> HotplugLifecycleDiagnostics {
        HotplugLifecycleDiagnostics(
            podMarkerExists: true,
            runtimeDirectoryExists: true,
            podObjectInitialized: true,
            podObjectPhase: "created",
            podCreatedStateKnown: true,
            podActuallyRunning: true,
            podReconnectAttempted: false,
            podReconnectSucceeded: false,
            podReuseClaim: podReuseClaim,
            addContainerAttempted: true,
            addContainerPhase: .afterPodCreate,
            hotplugAttempted: true,
            hotplugSucceeded: hotplugSucceeded,
            hotplugUnsupported: false,
            duplicateContainerDetected: false,
            failurePhase: nil,
            failureErrorType: nil,
            failureErrorMessage: nil,
            mutationBeforeFailure: .false
        )
    }
}

private extension WarmServiceRecreateMetadata {
    static let noOpWarmReconcileNotEvidence = WarmServiceRecreateMetadata(
        forcedServiceRecreateRequested: false,
        forcedServiceName: "api",
        serviceChanged: false,
        previousServiceStateKnown: true,
        recreateStrategy: .noOp,
        dbVolumePreserved: true,
        podPreserved: true,
        serviceRecreateDuration: nil,
        postRecreateReadinessDuration: nil,
        hostPortStatus: "notMeasured",
        loadWindowStatus: "notMeasured",
        noOpWarmReconcile: true,
        notProductViabilityEvidence: true
    )
}

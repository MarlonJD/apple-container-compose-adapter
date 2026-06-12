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
                image: "ghcr.io/apple/containerization/vminit:0.26.5",
                mirror: "mirror.gcr.io"
            ),
            "ghcr.io/apple/containerization/vminit:0.26.5"
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
                ServicePlan(name: "init", image: "ghcr.io/apple/containerization/vminit:0.26.5")
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
            "ghcr.io/apple/containerization/vminit:0.26.5"
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
            failure: nil
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
                "stage8-cleanup-leftovers"
            ]
        )
    }

    func testStage8BenchmarkEvidenceValidatorAcceptsWarmReuseWithFinalCleanCleanup() {
        let preserved = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 1,
            cleanupStateDirectoryExistsAfterCleanup: true,
            cleanupResult: "preserved-project-runtime-for-warm-reuse"
        )
        let finalClean = completeStage8IterationRecord(
            lifecycleMode: .allWarmProjectRuntime,
            iteration: 2,
            cleanupStateDirectoryExistsAfterCleanup: false,
            cleanupResult: "clean"
        )

        XCTAssertEqual(Stage8BenchmarkEvidenceValidator().validate(records: [preserved, finalClean]), [])
        XCTAssertEqual(
            Set(Stage8BenchmarkEvidenceValidator().validate(records: [preserved]).map(\.code)),
            ["stage8-final-cleanup-missing"]
        )
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
        cleanupResult: String
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
                podExistedBeforeRun: true
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
            failure: nil
        )
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

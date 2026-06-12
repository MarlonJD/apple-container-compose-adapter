// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest
@testable import ContainerComposeAdapter

final class ComposeFrontendTests: XCTestCase {
    func testSimpleWebFixtureParsesIntoLocalDevProject() throws {
        let result = try ComposeFrontend().parseProject(
            fileURL: fixtureURL("simple-web/compose.yaml"),
            projectName: "simple-web"
        )

        XCTAssertEqual(result.diagnostics, [])
        XCTAssertEqual(result.project.id, "simple-web")
        XCTAssertEqual(result.project.name, "simple-web")
        XCTAssertTrue(result.project.sourceFiles.first?.hasSuffix("docs/evidence/fixtures/simple-web/compose.yaml") ?? false)
        XCTAssertEqual(result.project.jobs, [])
        XCTAssertEqual(result.project.volumes, [])

        let web = try XCTUnwrap(result.project.services.first)
        XCTAssertEqual(web.name, "web")
        XCTAssertEqual(web.image, "docker.io/library/nginx:1.27-alpine")
        XCTAssertEqual(
            web.ports,
            [LocalDevPort(hostIP: "127.0.0.1", hostPort: 18080, containerPort: 80)]
        )
        XCTAssertEqual(
            web.healthcheck,
            LocalDevHealthcheck(
                test: ["sh", "-ec", "wget -qO- http://127.0.0.1/ >/dev/null"],
                intervalSeconds: 2,
                timeoutSeconds: 2,
                retries: 30,
                startPeriodSeconds: 2
            )
        )
        XCTAssertEqual(web.profiles, [])
    }

    func testBackendShapedFixtureParsesServicesJobsVolumesAndDependencies() throws {
        let result = try ComposeFrontend().parseProject(
            fileURL: fixtureURL("backend-shaped/compose.yaml"),
            projectName: "backend-shaped"
        )

        XCTAssertEqual(result.diagnostics, [])
        XCTAssertEqual(result.project.services.map(\.name), ["db", "api"])
        XCTAssertEqual(result.project.jobs.map(\.name), ["migrate", "seed"])
        XCTAssertEqual(result.project.volumes, [LocalDevVolume(name: "db-data")])

        let db = try XCTUnwrap(result.project.services.first { $0.name == "db" })
        XCTAssertEqual(db.image, "docker.io/library/postgres:16-alpine")
        XCTAssertEqual(db.environment["POSTGRES_USER"], "app")
        XCTAssertEqual(db.environment["POSTGRES_PASSWORD"], "dev_password")
        XCTAssertEqual(db.environment["POSTGRES_DB"], "app")
        XCTAssertEqual(
            db.ports,
            [LocalDevPort(hostIP: "127.0.0.1", hostPort: 15432, containerPort: 5432)]
        )
        XCTAssertEqual(
            db.mounts,
            [LocalDevMount(kind: .namedVolume, source: "db-data", target: "/var/lib/postgresql/data")]
        )
        XCTAssertEqual(
            db.healthcheck,
            LocalDevHealthcheck(
                test: ["sh", "-ec", "pg_isready -U app -d app"],
                intervalSeconds: 2,
                timeoutSeconds: 2,
                retries: 30,
                startPeriodSeconds: 5
            )
        )

        let migrate = try XCTUnwrap(result.project.jobs.first { $0.name == "migrate" })
        XCTAssertEqual(migrate.environment, ["PGPASSWORD": "dev_password"])
        XCTAssertEqual(Array(migrate.command.prefix(2)), ["sh", "-ec"])
        XCTAssertTrue(migrate.command.last?.contains("create table if not exists pilot_items") ?? false)
        XCTAssertEqual(migrate.dependencies, [LocalDevDependency(target: "db", condition: .serviceHealthy)])

        let seed = try XCTUnwrap(result.project.jobs.first { $0.name == "seed" })
        XCTAssertEqual(seed.dependencies, [LocalDevDependency(target: "migrate", condition: .serviceCompletedSuccessfully)])

        let api = try XCTUnwrap(result.project.services.first { $0.name == "api" })
        XCTAssertEqual(api.image, "docker.io/library/python:3.12-alpine")
        XCTAssertEqual(Array(api.command.prefix(2)), ["python", "-c"])
        XCTAssertEqual(
            api.dependencies,
            [
                LocalDevDependency(target: "db", condition: .serviceHealthy),
                LocalDevDependency(target: "seed", condition: .serviceCompletedSuccessfully)
            ]
        )
        XCTAssertEqual(
            api.ports,
            [LocalDevPort(hostIP: "127.0.0.1", hostPort: 18081, containerPort: 8080)]
        )
        XCTAssertEqual(
            api.healthcheck?.test,
            [
                "sh",
                "-ec",
                "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/ready', timeout=2).read()\""
            ]
        )
    }

    func testUnsupportedRuntimeRelevantComposeFieldsBecomeDiagnostics() throws {
        let yaml = """
        services:
          api:
            image: docker.io/library/python:3.12-alpine
            privileged: true
            ports:
              - "8080"
        """

        let result = try ComposeFrontend().parseProject(
            yaml: yaml,
            sourceName: "compose.yaml",
            projectName: "unsupported"
        )
        let plan = result.project.runtimePlan()

        XCTAssertEqual(result.diagnostics.map(\.code), ["unsupported-compose-feature"])
        XCTAssertTrue(plan.diagnostics.contains { $0.code == "unsupported-compose-feature" })
        XCTAssertTrue(plan.diagnostics.contains { $0.code == "unsupported-localdev-dynamic-port" })
        XCTAssertTrue(plan.hasBlockingDiagnostics)
    }

    func testComposeFrontendAcceptsYAMLBytes() throws {
        let yaml = """
        services:
          web:
            image: docker.io/library/nginx:1.27-alpine
        """
        let result = try ComposeFrontend().parseProject(
            yaml: Data(yaml.utf8),
            sourceName: "inline-compose.yaml",
            projectName: "inline"
        )

        XCTAssertEqual(result.project.sourceFiles, ["inline-compose.yaml"])
        XCTAssertEqual(result.project.services.map(\.name), ["web"])
    }

    func testSimpleWebFixtureRendersNoopDryRunWithoutRuntimeMutation() throws {
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("simple-web/compose.yaml"), projectName: "simple-web")
            .project
        let plannerResult = AppleNativePlanner().plan(project)
        let plan = plannerResult.runtimePlan

        XCTAssertEqual(plannerResult.diagnostics, [])
        let dryRun = try NoopDryRunBackend().renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        XCTAssertEqual(dryRun.mutatingActionCount, 0)
        XCTAssertEqual(dryRun.actions.map(\.kind), [.renderPlan])
        XCTAssertEqual(dryRun.actions.first?.resourceName, "web")
        XCTAssertTrue(dryRun.renderText().contains("Render service web from image docker.io/library/nginx:1.27-alpine"))
    }

    func testBackendShapedFixtureRendersLinuxPodDryRunActionShape() throws {
        let project = try ComposeFrontend()
            .parseProject(fileURL: fixtureURL("backend-shaped/compose.yaml"), projectName: "backend-shaped")
            .project
        let plannerResult = AppleNativePlanner().plan(project)
        let plan = plannerResult.runtimePlan

        XCTAssertEqual(plannerResult.diagnostics, [])
        XCTAssertFalse(plan.hasBlockingDiagnostics)

        let backend = LinuxPodBackend(
            stateStore: LinuxPodStateStore(root: URL(fileURLWithPath: "/tmp/cca-composefrontend-state", isDirectory: true))
        )
        let dryRun = try backend.renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        XCTAssertEqual(dryRun.diagnostics, [])
        XCTAssertEqual(dryRun.project, "cca-linuxpod-backend-shaped")
        let createRuntime = try XCTUnwrap(dryRun.actions.first { $0.kind == .createProjectRuntime })
        XCTAssertEqual(createRuntime.metadata["hosts"], "127.0.0.1 db migrate seed api")

        let lifecycleKinds: Set<PlannedActionKind> = [.addContainer, .startContainer, .runJob, .waitForReadiness]
        XCTAssertEqual(
            dryRun.actions
                .filter { lifecycleKinds.contains($0.kind) }
                .map { "\($0.kind.rawValue):\($0.resourceName ?? "")" },
            [
                "addContainer:cca-linuxpod-backend-shaped-db",
                "addContainer:cca-linuxpod-backend-shaped-migrate",
                "addContainer:cca-linuxpod-backend-shaped-seed",
                "addContainer:cca-linuxpod-backend-shaped-api",
                "startContainer:cca-linuxpod-backend-shaped-db",
                "waitForReadiness:db",
                "runJob:cca-linuxpod-backend-shaped-migrate",
                "waitForReadiness:migrate",
                "runJob:cca-linuxpod-backend-shaped-seed",
                "waitForReadiness:seed",
                "startContainer:cca-linuxpod-backend-shaped-api",
                "waitForReadiness:api"
            ]
        )

        let text = dryRun.renderText()
        XCTAssertTrue(text.contains("POSTGRES_PASSWORD=<redacted>"))
        XCTAssertTrue(text.contains("PGPASSWORD=<redacted>"))
        XCTAssertFalse(text.contains("dev_password"))
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/evidence/fixtures")
            .appendingPathComponent(name)
    }
}

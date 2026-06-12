// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest
@testable import ContainerComposeAdapter

final class KubernetesSubsetFrontendTests: XCTestCase {
    func testBackendShapedKubernetesRenderMatchesComposeRuntimeGraph() throws {
        let composeResult = try ComposeFrontend().parseProject(
            fileURL: fixtureURL("compose.yaml"),
            projectName: "backend-shaped"
        )
        let kubernetesResult = try KubernetesSubsetFrontend().parseProject(
            fileURL: fixtureURL("k8s.yaml"),
            projectName: "backend-shaped"
        )

        let composePlan = AppleNativePlanner().plan(composeResult.project).runtimePlan
        let kubernetesPlan = AppleNativePlanner().plan(kubernetesResult.project).runtimePlan

        XCTAssertEqual(kubernetesPlan.project, composePlan.project)
        XCTAssertEqual(kubernetesPlan.volumes, composePlan.volumes)
        XCTAssertEqual(
            kubernetesPlan.services.map(\.name),
            composePlan.services.map(\.name)
        )
        for (kubernetesService, composeService) in zip(kubernetesPlan.services, composePlan.services) {
            XCTAssertEqual(kubernetesService, composeService, "service plan mismatch for \(composeService.name)")
        }
        XCTAssertFalse(kubernetesPlan.diagnostics.contains { $0.severity == .blocking })
    }

    func testBackendShapedKubernetesRenderTranslatesSubsetObjects() throws {
        let result = try KubernetesSubsetFrontend().parseProject(
            fileURL: fixtureURL("k8s.yaml"),
            projectName: "backend-shaped"
        )
        let project = result.project

        XCTAssertEqual(project.services.map(\.name), ["db", "api"])
        XCTAssertEqual(project.jobs.map(\.name), ["migrate", "seed"])
        XCTAssertEqual(project.volumes.map(\.name), ["db-data"])
        XCTAssertEqual(project.volumes.first?.sizeBytes, 1024 * 1024 * 1024)

        let db = try XCTUnwrap(project.services.first)
        XCTAssertEqual(db.environment["POSTGRES_USER"], "app")
        XCTAssertEqual(db.environment["POSTGRES_DB"], "app")
        XCTAssertEqual(db.environment["POSTGRES_PASSWORD"], "dev_password")
        XCTAssertEqual(db.ports, [LocalDevPort(hostIP: "127.0.0.1", hostPort: 15432, containerPort: 5432)])
        XCTAssertEqual(db.healthcheck?.test, ["sh", "-ec", "pg_isready -U app -d app"])
        XCTAssertEqual(db.healthcheck?.startPeriodSeconds, 5)
        XCTAssertEqual(db.mounts, [
            LocalDevMount(kind: .namedVolume, source: "db-data", target: "/var/lib/postgresql/data")
        ])

        let migrate = try XCTUnwrap(project.jobs.first)
        XCTAssertEqual(migrate.environment["PGPASSWORD"], "dev_password")
        XCTAssertEqual(migrate.dependencies, [LocalDevDependency(target: "db", condition: .serviceHealthy)])

        let api = try XCTUnwrap(project.services.last)
        XCTAssertEqual(api.dependencies, [
            LocalDevDependency(target: "db", condition: .serviceHealthy),
            LocalDevDependency(target: "seed", condition: .serviceCompletedSuccessfully)
        ])
        XCTAssertEqual(api.ports, [LocalDevPort(hostIP: "127.0.0.1", hostPort: 18081, containerPort: 8080)])

        XCTAssertEqual(project.secrets.map(\.name), ["db-credentials"])
        XCTAssertEqual(project.configs.map(\.name), ["db-config"])
        XCTAssertEqual(project.routes, [
            LocalDevRoute(name: "api-local", host: "api.local", pathPrefix: "/", targetService: "api", targetPort: 8080)
        ])
    }

    func testDiagnosticsForUnsupportedKubernetesShapes() throws {
        let yaml = """
        apiVersion: apps/v1
        kind: DaemonSet
        metadata:
          name: node-agent
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: web
        spec:
          replicas: 3
          template:
            metadata:
              labels:
                app: web
            spec:
              containers:
                - name: web
                  image: docker.io/library/python:3.12-alpine
                  env:
                    - name: TOKEN
                      valueFrom:
                        secretKeyRef:
                          name: missing-secret
                          key: TOKEN
                  readinessProbe:
                    httpGet:
                      path: /healthz
                      port: 8080
                - name: sidecar
                  image: docker.io/library/python:3.12-alpine
              volumes:
                - name: scratch
                  emptyDir: {}
        ---
        apiVersion: v1
        kind: Service
        metadata:
          name: orphan
        spec:
          selector:
            app: missing
          ports:
            - port: 80
        """
        let result = try KubernetesSubsetFrontend().parseProject(yaml: yaml, projectName: "diagnostics")

        let codes = Set(result.diagnostics.map(\.code))
        XCTAssertTrue(codes.contains("unsupported-kubernetes-kind"))
        XCTAssertTrue(codes.contains("kubernetes-multi-replica"))
        XCTAssertTrue(codes.contains("kubernetes-multi-container"))
        XCTAssertTrue(codes.contains("kubernetes-probe-type"))
        XCTAssertTrue(codes.contains("kubernetes-secret-resolution"))
        XCTAssertTrue(codes.contains("kubernetes-volume-source"))
        XCTAssertTrue(codes.contains("kubernetes-service-selector"))

        let resolution = try XCTUnwrap(result.diagnostics.first { $0.code == "kubernetes-secret-resolution" })
        XCTAssertEqual(resolution.severity, .blocking)
        XCTAssertEqual(result.project.services.count, 1)
        XCTAssertNil(result.project.services.first?.healthcheck)
    }

    func testNamespaceCollapseAndIgnoreAnnotation() throws {
        let yaml = """
        apiVersion: v1
        kind: Namespace
        metadata:
          name: one
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: ignored
          namespace: two
          annotations:
            cca.local/ignore: "true"
        data:
          KEY: value
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: kept
          namespace: two
        data:
          KEY: value
        """
        let result = try KubernetesSubsetFrontend().parseProject(yaml: yaml, projectName: "scopes")

        XCTAssertEqual(result.project.configs.map(\.name), ["kept"])
        XCTAssertTrue(result.diagnostics.contains { $0.code == "kubernetes-namespace-collapse" })
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/evidence/fixtures/backend-shaped/\(name)")
    }
}

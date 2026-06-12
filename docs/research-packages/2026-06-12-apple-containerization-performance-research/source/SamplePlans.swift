// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum SamplePlans {
    public static func publicImageSmoke(project: ProjectName = ProjectName("linuxpod-smoke")) -> RuntimePlan {
        RuntimePlan(
            project: project,
            services: [
                ServicePlan(
                    name: "web",
                    image: "mirror.gcr.io/library/nginx:alpine",
                    command: ["/docker-entrypoint.sh", "nginx", "-g", "daemon off;"],
                    environment: [
                        EnvironmentVariable("SESSION_TOKEN", "dry-run-token")
                    ],
                    ports: [
                        PortMapping(hostPort: 18080, containerPort: 80)
                    ],
                    mounts: [
                        MountPlan(
                            kind: .bind,
                            source: "docs/evidence/fixtures",
                            target: "/usr/share/nginx/html",
                            readOnly: true
                        ),
                        MountPlan(
                            kind: .namedVolume,
                            source: "web-cache",
                            target: "/var/cache/nginx"
                        )
                    ],
                    readiness: [
                        ReadinessProbe(kind: .serviceStarted, timeoutSeconds: 30)
                    ]
                )
            ],
            volumes: [
                VolumePlan(name: "web-cache")
            ]
        )
    }

    public static func publicBackendShaped(project: ProjectName = ProjectName("linuxpod-backend")) -> RuntimePlan {
        RuntimePlan(
            project: project,
            services: [
                ServicePlan(
                    name: "api",
                    image: "mirror.gcr.io/library/python:3.12-alpine",
                    command: [
                        "python",
                        "-c",
                        """
                        import http.server
                        import socket
                        import time

                        deadline = time.time() + 30
                        while True:
                            try:
                                with socket.create_connection(("db", 5432), timeout=2):
                                    break
                            except OSError:
                                if time.time() > deadline:
                                    raise
                                time.sleep(1)

                        class Handler(http.server.BaseHTTPRequestHandler):
                            def do_GET(self):
                                if self.path not in ("/", "/ready"):
                                    self.send_response(404)
                                    self.end_headers()
                                    return
                                body = b"ready\\n"
                                self.send_response(200)
                                self.send_header("Content-Type", "text/plain")
                                self.send_header("Content-Length", str(len(body)))
                                self.end_headers()
                                self.wfile.write(body)

                            def log_message(self, format, *args):
                                return

                        http.server.ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
                        """
                    ],
                    ports: [
                        PortMapping(hostPort: 18081, containerPort: 8080)
                    ],
                    readiness: [
                        ReadinessProbe(
                            kind: .serviceHealthy,
                            command: [
                                "python",
                                "-c",
                                "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/ready', timeout=2).read()"
                            ],
                            timeoutSeconds: 60
                        )
                    ],
                    dependencies: [
                        ServiceDependency(serviceName: "db", condition: .serviceHealthy),
                        ServiceDependency(serviceName: "seed", condition: .serviceCompletedSuccessfully)
                    ]
                ),
                ServicePlan(
                    name: "seed",
                    kind: .oneOffJob,
                    image: "mirror.gcr.io/library/postgres:16-alpine",
                    command: [
                        "sh",
                        "-ec",
                        """
                        psql -h db -U app -d app -v ON_ERROR_STOP=1 \
                          -c "insert into pilot_items (name) values ('public-fixture') on conflict do nothing;"
                        """
                    ],
                    readiness: [
                        ReadinessProbe(kind: .serviceCompletedSuccessfully, timeoutSeconds: 60)
                    ],
                    dependencies: [
                        ServiceDependency(serviceName: "migrate", condition: .serviceCompletedSuccessfully)
                    ]
                ),
                ServicePlan(
                    name: "migrate",
                    kind: .oneOffJob,
                    image: "mirror.gcr.io/library/postgres:16-alpine",
                    command: [
                        "sh",
                        "-ec",
                        """
                        psql -h db -U app -d app -v ON_ERROR_STOP=1 \
                          -c "create table if not exists pilot_items (id serial primary key, name text not null);"
                        """
                    ],
                    readiness: [
                        ReadinessProbe(kind: .serviceCompletedSuccessfully, timeoutSeconds: 60)
                    ],
                    dependencies: [
                        ServiceDependency(serviceName: "db", condition: .serviceHealthy)
                    ]
                ),
                ServicePlan(
                    name: "db",
                    image: "mirror.gcr.io/library/postgres:16-alpine",
                    environment: [
                        EnvironmentVariable("POSTGRES_USER", "app"),
                        EnvironmentVariable("POSTGRES_PASSWORD", "dev_password"),
                        EnvironmentVariable("POSTGRES_DB", "app")
                    ],
                    ports: [
                        PortMapping(hostPort: 15432, containerPort: 5432)
                    ],
                    mounts: [
                        MountPlan(
                            kind: .namedVolume,
                            source: "db-data",
                            target: "/var/lib/postgresql/data"
                        )
                    ],
                    readiness: [
                        ReadinessProbe(
                            kind: .serviceHealthy,
                            command: ["pg_isready", "-U", "app", "-d", "app"],
                            timeoutSeconds: 60
                        )
                    ]
                )
            ],
            volumes: [
                VolumePlan(name: "db-data")
            ]
        )
    }
}

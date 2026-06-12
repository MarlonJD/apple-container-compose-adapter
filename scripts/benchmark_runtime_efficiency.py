#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Burak Karahan
"""Benchmark Docker/OrbStack and Apple container runtime efficiency.

This harness intentionally uses public fixtures and project-scoped names only.
It does not prune images, delete non-benchmark resources, or touch private
workloads.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import statistics
import subprocess
import sys
import threading
import time
import socket
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib import request


ROOT = Path(__file__).resolve().parents[1]
SIMPLE_COMPOSE = ROOT / "docs/evidence/fixtures/simple-web/compose.yaml"
BACKEND_COMPOSE = ROOT / "docs/evidence/fixtures/backend-shaped/compose.yaml"
DEFAULT_OUTPUT_DIR = ROOT / "docs/evidence/runtime-efficiency"
BENCH_PREFIX = "cca-bench"
POSTGRES_IMAGE = "docker.io/library/postgres:16-alpine"
PYTHON_IMAGE = "docker.io/library/python:3.12-alpine"
NGINX_IMAGE = "docker.io/library/nginx:1.27-alpine"


API_SCRIPT = r"""
import http.server
import socket
import sys
import time

db_host = sys.argv[1]
deadline = time.time() + 30
while True:
    try:
        with socket.create_connection((db_host, 5432), timeout=2):
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
        body = b"ready\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

http.server.ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
""".strip()


@dataclass(frozen=True)
class CommandResult:
    argv: list[str]
    returncode: int
    stdout: str
    stderr: str
    duration_s: float


class BenchmarkError(RuntimeError):
    pass


class Recorder:
    def __init__(self, jsonl_path: Path) -> None:
        self.jsonl_path = jsonl_path
        self.jsonl_path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = self.jsonl_path.open("w", encoding="utf-8")

    def close(self) -> None:
        self._fh.close()

    def write(self, row: dict[str, Any]) -> None:
        row = {"recorded_at": now_iso(), **row}
        self._fh.write(json.dumps(row, sort_keys=True) + "\n")
        self._fh.flush()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def run(
    argv: list[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
    timeout: float = 180.0,
) -> CommandResult:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    start = time.perf_counter()
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        env=merged_env,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    duration = time.perf_counter() - start
    result = CommandResult(
        argv=argv,
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
        duration_s=duration,
    )
    if check and result.returncode != 0:
        raise BenchmarkError(format_failure(result))
    return result


def format_failure(result: CommandResult) -> str:
    return (
        f"command failed ({result.returncode}) after {result.duration_s:.2f}s: "
        f"{result.argv}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def parse_size_token(token: str | None) -> int | None:
    if not token:
        return None
    token = token.strip().split("/", 1)[0].strip()
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B|B)$", token, re.I)
    if not match:
        return None
    amount = float(match.group(1))
    unit = match.group(2).lower()
    factors = {
        "b": 1,
        "kb": 1000,
        "mb": 1000**2,
        "gb": 1000**3,
        "tb": 1000**4,
        "kib": 1024,
        "mib": 1024**2,
        "gib": 1024**3,
        "tib": 1024**4,
    }
    return int(amount * factors[unit])


def parse_size_bytes(value: str | None) -> int | None:
    if not value:
        return None
    return parse_size_token(value.strip().split("/", 1)[0].strip())


def parse_io_pair(value: str | None) -> dict[str, int | None]:
    if not value or "/" not in value:
        return {"read_bytes": None, "write_bytes": None}
    left, right = value.split("/", 1)
    return {
        "read_bytes": parse_size_token(left.strip()),
        "write_bytes": parse_size_token(right.strip()),
    }


def parse_percent(value: str | None) -> float | None:
    if not value:
        return None
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*%", value)
    return float(match.group(1)) if match else None


def parse_status_metrics(raw: str) -> dict[str, int]:
    metrics: dict[str, int] = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].endswith(":"):
            key = parts[0].rstrip(":")
            try:
                metrics[f"proc_{key.lower()}_bytes"] = int(parts[1]) * 1024
            except ValueError:
                pass
        elif line.startswith("memory.current="):
            metrics["cgroup_memory_current_bytes"] = int(line.split("=", 1)[1])
        elif line.startswith("memory.peak="):
            metrics["cgroup_memory_peak_bytes"] = int(line.split("=", 1)[1])
        elif line.startswith("memory.max="):
            value = line.split("=", 1)[1].strip()
            if value != "max":
                metrics["cgroup_memory_max_bytes"] = int(value)
        elif line.startswith("du_kib="):
            _, payload = line.split("=", 1)
            size_text, path = payload.split(" ", 1)
            safe_path = path.strip().strip("/").replace("/", "_").replace("-", "_")
            try:
                metrics[f"du_{safe_path}_bytes"] = int(size_text) * 1024
            except ValueError:
                pass
    return metrics


def proc_probe_argv(disk_paths: list[str] | None = None) -> list[str]:
    disk_commands = ""
    for path in disk_paths or []:
        safe_path = path.replace("'", "'\\''")
        disk_commands += (
            f" if [ -e '{safe_path}' ]; then "
            f"set -- $(du -sk '{safe_path}' 2>/dev/null || true); "
            f"if [ $# -ge 1 ]; then printf 'du_kib=%s {safe_path}\\n' \"$1\"; fi; "
            "fi;"
        )
    return [
        "sh",
        "-ec",
        (
            "awk '/VmRSS|VmHWM|VmSize/ {print}' /proc/1/status; "
            "if [ -f /sys/fs/cgroup/memory.current ]; then "
            "printf 'memory.current='; cat /sys/fs/cgroup/memory.current; fi; "
            "if [ -f /sys/fs/cgroup/memory.peak ]; then "
            "printf 'memory.peak='; cat /sys/fs/cgroup/memory.peak; fi; "
            "if [ -f /sys/fs/cgroup/memory.max ]; then "
            "printf 'memory.max='; cat /sys/fs/cgroup/memory.max; fi;"
            f"{disk_commands}"
        ),
    ]


def docker_env() -> dict[str, str]:
    return {"DOCKER_DEFAULT_PLATFORM": "linux/arm64"}


def docker_compose(
    project: str,
    compose_file: Path,
    args: list[str],
    *,
    force_arm64: bool = False,
) -> CommandResult:
    return run(
        ["docker", "compose", "-p", project, "-f", str(compose_file), *args],
        env=docker_env() if force_arm64 else None,
        timeout=240.0,
    )


def docker_compose_cleanup(
    project: str,
    compose_file: Path,
    *,
    force_arm64: bool = False,
) -> None:
    run(
        [
            "docker",
            "compose",
            "-p",
            project,
            "-f",
            str(compose_file),
            "down",
            "--volumes",
            "--remove-orphans",
        ],
        env=docker_env() if force_arm64 else None,
        check=False,
        timeout=180.0,
    )


def docker_container_id(project: str, compose_file: Path, service: str) -> str:
    result = docker_compose(project, compose_file, ["ps", "-q", service])
    container_id = result.stdout.strip()
    if not container_id:
        raise BenchmarkError(f"missing docker container id for {project}/{service}")
    return container_id


def docker_stats(container_id: str) -> dict[str, Any]:
    result = run(
        ["docker", "stats", "--no-stream", "--format", "{{json .}}", container_id],
        timeout=60.0,
    )
    raw = result.stdout.strip()
    if not raw:
        return {"raw": raw}
    parsed = json.loads(raw)
    block = parse_io_pair(parsed.get("BlockIO"))
    net = parse_io_pair(parsed.get("NetIO"))
    return {
        "raw": raw,
        "cpu_percent": parse_percent(parsed.get("CPUPerc")),
        "memory_usage_bytes": parse_size_bytes(parsed.get("MemUsage")),
        "memory_limit_bytes": parse_size_bytes(
            parsed.get("MemUsage", "").split("/", 1)[1]
            if "/" in parsed.get("MemUsage", "")
            else None
        ),
        "net_io": parsed.get("NetIO"),
        "net_read_bytes": net["read_bytes"],
        "net_write_bytes": net["write_bytes"],
        "block_io": parsed.get("BlockIO"),
        "block_read_bytes": block["read_bytes"],
        "block_write_bytes": block["write_bytes"],
        "pids": parsed.get("PIDs"),
    }


def docker_proc_metrics(container_id: str, disk_paths: list[str] | None = None) -> dict[str, Any]:
    result = run(["docker", "exec", container_id, *proc_probe_argv(disk_paths)], timeout=60.0)
    return {"raw": result.stdout, **parse_status_metrics(result.stdout)}


def summarize_latency(latencies_s: list[float]) -> dict[str, Any]:
    return summarize_values(latencies_s)


def http_load_with_stats(
    url: str,
    stats_fn: Callable[[], dict[str, Any]],
    *,
    duration_s: float = 2.0,
    concurrency: int = 4,
) -> dict[str, Any]:
    deadline = time.perf_counter() + duration_s
    latencies: list[float] = []
    errors: list[str] = []
    lock = threading.Lock()

    def worker() -> None:
        while time.perf_counter() < deadline:
            start = time.perf_counter()
            try:
                with request.urlopen(url, timeout=2.0) as response:
                    response.read()
                    if response.status >= 400:
                        raise RuntimeError(f"http {response.status}")
                elapsed = time.perf_counter() - start
                with lock:
                    latencies.append(elapsed)
            except Exception as exc:  # noqa: BLE001 - errors are benchmark evidence.
                with lock:
                    errors.append(str(exc))

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(concurrency)]
    start = time.perf_counter()
    for thread in threads:
        thread.start()
    time.sleep(min(0.5, duration_s / 2))
    stats = stats_fn()
    for thread in threads:
        thread.join()
    elapsed = time.perf_counter() - start
    return {
        "duration_s": elapsed,
        "requests": len(latencies),
        "errors": len(errors),
        "first_error": errors[0] if errors else None,
        "latency_s": summarize_latency(latencies),
        "runtime_stats": stats,
    }


def db_load_command() -> list[str]:
    return [
        "sh",
        "-ec",
        (
            "i=0; end=$(($(date +%s)+2)); "
            "while [ $(date +%s) -lt $end ]; do "
            "psql -U app -d app -v ON_ERROR_STOP=1 "
            "-c 'select count(*) from generate_series(1, 5000);' >/dev/null; "
            "i=$((i+1)); "
            "done; "
            "printf 'queries=%s\\n' \"$i\""
        ),
    ]


def docker_db_load(name: str) -> dict[str, Any]:
    start = time.perf_counter()
    process = subprocess.Popen(
        ["docker", "exec", name, *db_load_command()],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(0.5)
    stats = docker_stats(name)
    stdout, stderr = process.communicate(timeout=20.0)
    return {
        "duration_s": time.perf_counter() - start,
        "returncode": process.returncode,
        "stdout": stdout,
        "stderr": stderr,
        "runtime_stats": stats,
    }


def wait_for_http(url: str, *, timeout_s: float, label: str) -> CommandResult:
    return wait_for(
        lambda: run(["curl", "-fsS", url], check=False, timeout=10.0),
        is_success=lambda result: result.returncode == 0 and bool(result.stdout.strip()),
        timeout_s=timeout_s,
        label=label,
    )


def docker_simple_iteration(iteration: int) -> dict[str, Any]:
    project = f"{BENCH_PREFIX}-simple-docker"
    docker_compose_cleanup(project, SIMPLE_COMPOSE)
    up = docker_compose(project, SIMPLE_COMPOSE, ["up", "-d", "--wait"])
    ready = wait_for_http(
        "http://127.0.0.1:18080/",
        timeout_s=30.0,
        label=f"apple simple-web readiness iteration {iteration}",
    )
    cid = docker_container_id(project, SIMPLE_COMPOSE, "web")
    stats = docker_stats(cid)
    proc = docker_proc_metrics(cid, ["/usr/share/nginx/html", "/var/cache/nginx"])
    load = http_load_with_stats("http://127.0.0.1:18080/", lambda: docker_stats(cid))
    down = docker_compose(project, SIMPLE_COMPOSE, ["down", "--remove-orphans"])
    return {
        "runtime": "docker-compose",
        "scenario": "simple-web",
        "iteration": iteration,
        "status": "measured",
        "timings_s": {
            "start_to_wait": up.duration_s,
            "readiness_probe": ready.duration_s,
            "stop_delete": down.duration_s,
        },
        "metrics": {"web": {"runtime_stats": stats, "process": proc, "load": load}},
    }


def docker_run_cleanup(name: str, volume: str) -> None:
    run(["docker", "rm", "-f", name], check=False, timeout=60.0)
    run(["docker", "volume", "rm", volume], check=False, timeout=60.0)


def docker_db_only_iteration(iteration: int) -> dict[str, Any]:
    name = f"{BENCH_PREFIX}-db-docker"
    volume = f"{BENCH_PREFIX}-db-docker-data"
    docker_run_cleanup(name, volume)
    create_volume = run(["docker", "volume", "create", volume], timeout=60.0)
    start = run(
        [
            "docker",
            "run",
            "--detach",
            "--name",
            name,
            "--env",
            "POSTGRES_USER=app",
            "--env",
            "POSTGRES_PASSWORD=dev_password",
            "--env",
            "POSTGRES_DB=app",
            "--env",
            "PGDATA=/var/lib/postgresql/data/pgdata",
            "--volume",
            f"{volume}:/var/lib/postgresql/data",
            POSTGRES_IMAGE,
        ],
        env=docker_env(),
        timeout=180.0,
    )
    health = wait_for(
        lambda: run(
            ["docker", "exec", name, "pg_isready", "-U", "app", "-d", "app"],
            check=False,
            timeout=30.0,
        ),
        is_success=lambda result: result.returncode == 0,
        timeout_s=60.0,
        label=f"docker db health iteration {iteration}",
    )
    stats = docker_stats(name)
    proc = docker_proc_metrics(name, ["/var/lib/postgresql/data"])
    load = docker_db_load(name)
    stop = run(["docker", "stop", name], timeout=60.0)
    delete = run(["docker", "rm", name], timeout=60.0)
    delete_volume = run(["docker", "volume", "rm", volume], timeout=60.0)
    return {
        "runtime": "docker-run",
        "scenario": "postgres-db-only",
        "iteration": iteration,
        "status": "measured",
        "timings_s": {
            "volume_create": create_volume.duration_s,
            "start_command": start.duration_s,
            "health_wait": health.duration_s,
            "stop": stop.duration_s,
            "delete": delete.duration_s,
            "volume_delete": delete_volume.duration_s,
        },
        "metrics": {"db": {"runtime_stats": stats, "process": proc, "load": load}},
    }


def docker_backend_iteration(iteration: int) -> dict[str, Any]:
    project = f"{BENCH_PREFIX}-backend-docker"
    docker_compose_cleanup(project, BACKEND_COMPOSE, force_arm64=True)
    up = docker_compose(project, BACKEND_COMPOSE, ["up", "-d", "--wait"], force_arm64=True)
    ready = wait_for_http(
        "http://127.0.0.1:18081/ready",
        timeout_s=30.0,
        label=f"apple backend API readiness iteration {iteration}",
    )
    db_cid = docker_container_id(project, BACKEND_COMPOSE, "db")
    api_cid = docker_container_id(project, BACKEND_COMPOSE, "api")
    db_stats = docker_stats(db_cid)
    api_stats = docker_stats(api_cid)
    db_proc = docker_proc_metrics(db_cid, ["/var/lib/postgresql/data"])
    api_proc = docker_proc_metrics(api_cid, ["/tmp"])
    db_load = docker_db_load(db_cid)
    api_load = http_load_with_stats("http://127.0.0.1:18081/ready", lambda: docker_stats(api_cid))
    down = docker_compose(
        project,
        BACKEND_COMPOSE,
        ["down", "--volumes", "--remove-orphans"],
        force_arm64=True,
    )
    return {
        "runtime": "docker-compose",
        "scenario": "backend-shaped",
        "iteration": iteration,
        "status": "measured",
        "timings_s": {
            "start_to_wait": up.duration_s,
            "readiness_probe": ready.duration_s,
            "stop_delete": down.duration_s,
        },
        "metrics": {
            "db": {"runtime_stats": db_stats, "process": db_proc, "load": db_load},
            "api": {"runtime_stats": api_stats, "process": api_proc, "load": api_load},
        },
    }


def apple_system_start() -> CommandResult:
    return run(["container", "system", "start"], check=False, timeout=180.0)


def apple_system_status() -> CommandResult:
    return run(["container", "system", "status"], check=False, timeout=60.0)


def wait_for_apple_system_ready() -> CommandResult:
    result = wait_for(
        apple_system_status,
        is_success=lambda status: status.returncode == 0 and "status" in status.stdout and "running" in status.stdout,
        timeout_s=30.0,
        label="apple container system ready",
    )
    time.sleep(1.0)
    return result


def apple_system_stop() -> CommandResult:
    return run(["container", "system", "stop"], check=False, timeout=180.0)


def apple_delete_container(name: str) -> None:
    run(["container", "stop", name], check=False, timeout=90.0)
    run(["container", "delete", "--force", name], check=False, timeout=90.0)
    wait_for_apple_container_absent(name, timeout_s=10.0)


def apple_cleanup(names: list[str], networks: list[str], volumes: list[str]) -> None:
    for name in names:
        apple_delete_container(name)
    for network in networks:
        run(["container", "network", "delete", network], check=False, timeout=90.0)
    for volume in volumes:
        run(["container", "volume", "delete", volume], check=False, timeout=90.0)


def apple_container_state(name: str) -> str | None:
    result = run(["container", "list", "--all"], check=False, timeout=60.0)
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        if line.startswith(name):
            fields = line.split()
            if len(fields) >= 5:
                return fields[4].lower()
            return "unknown"
    return None


def wait_for_apple_container_absent(name: str, *, timeout_s: float) -> None:
    wait_for(
        lambda: CommandResult(
            argv=["container", "list", "--all"],
            returncode=0,
            stdout=apple_container_state(name) or "absent",
            stderr="",
            duration_s=0.0,
        ),
        is_success=lambda result: result.stdout == "absent",
        timeout_s=timeout_s,
        label=f"Apple container {name} to be absent",
    )


def wait_for_apple_container_running(name: str, *, timeout_s: float) -> None:
    wait_for(
        lambda: CommandResult(
            argv=["container", "list", "--all"],
            returncode=0,
            stdout=apple_container_state(name) or "absent",
            stderr="",
            duration_s=0.0,
        ),
        is_success=lambda result: result.stdout == "running",
        timeout_s=timeout_s,
        label=f"Apple container {name} to be running",
    )


def apple_stats(names: list[str]) -> dict[str, Any]:
    result = run(["container", "stats", "--no-stream", *names], timeout=90.0)
    parsed: dict[str, Any] = {"raw": result.stdout}
    for name in names:
        line = next(
            (candidate for candidate in result.stdout.splitlines() if candidate.startswith(name)),
            "",
        )
        metric: dict[str, Any] = {"raw": line}
        fields = re.split(r"\s{2,}", line.strip()) if line else []
        if len(fields) >= 3:
            metric["cpu_percent"] = parse_percent(fields[1])
            metric["memory_usage_bytes"] = parse_size_bytes(fields[2])
            metric["memory_limit_bytes"] = parse_size_bytes(
                fields[2].split("/", 1)[1] if "/" in fields[2] else None
            )
        if len(fields) >= 4:
            net = parse_io_pair(fields[3])
            metric["net_read_bytes"] = net["read_bytes"]
            metric["net_write_bytes"] = net["write_bytes"]
        if len(fields) >= 5:
            block = parse_io_pair(fields[4])
            metric["block_read_bytes"] = block["read_bytes"]
            metric["block_write_bytes"] = block["write_bytes"]
        parsed[name] = metric
    return parsed


def apple_proc_metrics(name: str, disk_paths: list[str] | None = None) -> dict[str, Any]:
    result = run(["container", "exec", name, *proc_probe_argv(disk_paths)], timeout=60.0)
    return {"raw": result.stdout, **parse_status_metrics(result.stdout)}


def apple_db_load(name: str) -> dict[str, Any]:
    start = time.perf_counter()
    process = subprocess.Popen(
        ["container", "exec", name, *db_load_command()],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(0.5)
    stats = apple_stats([name]).get(name, {})
    stdout, stderr = process.communicate(timeout=20.0)
    return {
        "duration_s": time.perf_counter() - start,
        "returncode": process.returncode,
        "stdout": stdout,
        "stderr": stderr,
        "runtime_stats": stats,
    }


def apple_container_ip(name: str) -> str:
    inspect = run(["container", "inspect", name], timeout=60.0)
    ip = first_ipv4(inspect.stdout)
    if ip:
        return ip
    listing = run(["container", "list", "--all"], timeout=60.0)
    for line in listing.stdout.splitlines():
        if name in line:
            ip = first_ipv4(line)
            if ip:
                return ip
    raise BenchmarkError(f"could not determine Apple container IP for {name}")


def first_ipv4(text: str) -> str | None:
    for match in re.finditer(r"\b(?!127\.|0\.0\.0\.0)(\d{1,3}(?:\.\d{1,3}){3})\b", text):
        parts = [int(part) for part in match.group(1).split(".")]
        if all(0 <= part <= 255 for part in parts):
            return match.group(1)
    return None


def apple_simple_iteration(iteration: int) -> dict[str, Any]:
    name = f"{BENCH_PREFIX}-simple-apple-{iteration:03d}"
    apple_cleanup([name], [], [])
    start = run(
        [
            "container",
            "run",
            "--detach",
            "--name",
            name,
            "--label",
            "com.container-compose-adapter.benchmark.workload=simple-web",
            "--publish",
            "127.0.0.1:18080:80",
            NGINX_IMAGE,
        ],
        timeout=180.0,
    )
    wait_for_apple_container_running(name, timeout_s=30.0)
    ready = wait_for_http(
        "http://127.0.0.1:18080/",
        timeout_s=30.0,
        label=f"apple simple-web readiness iteration {iteration}",
    )
    stats = apple_stats([name])
    proc = apple_proc_metrics(name, ["/usr/share/nginx/html", "/var/cache/nginx"])
    load = http_load_with_stats("http://127.0.0.1:18080/", lambda: apple_stats([name]).get(name, {}))
    stop = run(["container", "stop", name], timeout=90.0)
    delete = run(["container", "delete", "--force", name], timeout=90.0)
    wait_for_apple_container_absent(name, timeout_s=30.0)
    port_closed = wait_for_port_closed(
        "127.0.0.1",
        18080,
        timeout_s=30.0,
        label=f"apple simple-web cleanup iteration {iteration}",
    )
    return {
        "runtime": "apple-container",
        "scenario": "simple-web",
        "iteration": iteration,
        "status": "measured",
        "timings_s": {
            "start_command": start.duration_s,
            "readiness_probe": ready.duration_s,
            "stop": stop.duration_s,
            "delete": delete.duration_s,
            "port_closed": port_closed,
        },
        "metrics": {
            "web": {
                "runtime_stats": stats.get(name, {}),
                "process": proc,
                "load": load,
            }
        },
    }


def apple_db_only_iteration(iteration: int) -> dict[str, Any]:
    name = f"{BENCH_PREFIX}-db-apple-{iteration:03d}"
    volume = f"{BENCH_PREFIX}-db-apple-data-{iteration:03d}"
    apple_cleanup([name], [], [volume])
    create_volume = run(["container", "volume", "create", volume], timeout=90.0)
    start = run(
        [
            "container",
            "run",
            "--detach",
            "--name",
            name,
            "--label",
            "com.container-compose-adapter.benchmark.workload=postgres-db-only",
            "--env",
            "POSTGRES_USER=app",
            "--env",
            "POSTGRES_PASSWORD=dev_password",
            "--env",
            "POSTGRES_DB=app",
            "--env",
            "PGDATA=/var/lib/postgresql/data/pgdata",
            "--volume",
            f"{volume}:/var/lib/postgresql/data",
            POSTGRES_IMAGE,
        ],
        timeout=180.0,
    )
    wait_for_apple_container_running(name, timeout_s=30.0)
    health = wait_for(
        lambda: run(
            ["container", "exec", name, "pg_isready", "-U", "app", "-d", "app"],
            check=False,
            timeout=30.0,
        ),
        is_success=lambda result: result.returncode == 0,
        timeout_s=90.0,
        label=f"apple db health iteration {iteration}",
    )
    stats = apple_stats([name])
    proc = apple_proc_metrics(name, ["/var/lib/postgresql/data"])
    load = apple_db_load(name)
    stop = run(["container", "stop", name], timeout=90.0)
    delete = run(["container", "delete", "--force", name], timeout=90.0)
    wait_for_apple_container_absent(name, timeout_s=30.0)
    delete_volume = run(["container", "volume", "delete", volume], timeout=90.0)
    return {
        "runtime": "apple-container",
        "scenario": "postgres-db-only",
        "iteration": iteration,
        "status": "measured",
        "timings_s": {
            "volume_create": create_volume.duration_s,
            "start_command": start.duration_s,
            "health_wait": health.duration_s,
            "stop": stop.duration_s,
            "delete": delete.duration_s,
            "volume_delete": delete_volume.duration_s,
        },
        "metrics": {
            "db": {
                "runtime_stats": stats.get(name, {}),
                "process": proc,
                "load": load,
            }
        },
    }


def apple_backend_iteration(iteration: int) -> dict[str, Any]:
    db = f"{BENCH_PREFIX}-backend-db-apple-{iteration:03d}"
    api = f"{BENCH_PREFIX}-backend-api-apple-{iteration:03d}"
    network = f"{BENCH_PREFIX}-backend-apple-net-{iteration:03d}"
    volume = f"{BENCH_PREFIX}-backend-apple-data-{iteration:03d}"
    apple_cleanup([api, db], [network], [volume])
    create_network = run(["container", "network", "create", network], timeout=90.0)
    create_volume = run(["container", "volume", "create", volume], timeout=90.0)
    db_start = run(
        [
            "container",
            "run",
            "--detach",
            "--name",
            db,
            "--label",
            "com.container-compose-adapter.benchmark.workload=backend-shaped",
            "--label",
            "com.container-compose-adapter.benchmark.role=db",
            "--network",
            network,
            "--publish",
            "127.0.0.1:15432:5432",
            "--env",
            "POSTGRES_USER=app",
            "--env",
            "POSTGRES_PASSWORD=dev_password",
            "--env",
            "POSTGRES_DB=app",
            "--env",
            "PGDATA=/var/lib/postgresql/data/pgdata",
            "--volume",
            f"{volume}:/var/lib/postgresql/data",
            POSTGRES_IMAGE,
        ],
        timeout=180.0,
    )
    wait_for_apple_container_running(db, timeout_s=30.0)
    db_health = wait_for(
        lambda: run(
            ["container", "exec", db, "pg_isready", "-U", "app", "-d", "app"],
            check=False,
            timeout=30.0,
        ),
        is_success=lambda result: result.returncode == 0,
        timeout_s=90.0,
        label=f"apple backend db health iteration {iteration}",
    )
    db_ip = apple_container_ip(db)
    migrate = run(
        [
            "container",
            "run",
            "--remove",
            "--name",
            f"{BENCH_PREFIX}-backend-migrate-apple-{iteration:03d}",
            "--label",
            "com.container-compose-adapter.benchmark.role=migrate",
            "--network",
            network,
            "--env",
            "PGPASSWORD=dev_password",
            POSTGRES_IMAGE,
            "sh",
            "-ec",
            (
                f"psql -h {db_ip} -U app -d app -v ON_ERROR_STOP=1 "
                "-c \"create table if not exists pilot_items "
                "(id serial primary key, name text not null);\""
            ),
        ],
        timeout=120.0,
    )
    seed = run(
        [
            "container",
            "run",
            "--remove",
            "--name",
            f"{BENCH_PREFIX}-backend-seed-apple-{iteration:03d}",
            "--label",
            "com.container-compose-adapter.benchmark.role=seed",
            "--network",
            network,
            "--env",
            "PGPASSWORD=dev_password",
            POSTGRES_IMAGE,
            "sh",
            "-ec",
            (
                f"psql -h {db_ip} -U app -d app -v ON_ERROR_STOP=1 "
                "-c \"insert into pilot_items (name) values ('public-fixture');\""
            ),
        ],
        timeout=120.0,
    )
    api_start = run(
        [
            "container",
            "run",
            "--detach",
            "--name",
            api,
            "--label",
            "com.container-compose-adapter.benchmark.workload=backend-shaped",
            "--label",
            "com.container-compose-adapter.benchmark.role=api",
            "--network",
            network,
            "--publish",
            "127.0.0.1:18081:8080",
            PYTHON_IMAGE,
            "python",
            "-c",
            API_SCRIPT,
            db_ip,
        ],
        timeout=180.0,
    )
    wait_for_apple_container_running(api, timeout_s=30.0)
    ready = wait_for_http(
        "http://127.0.0.1:18081/ready",
        timeout_s=30.0,
        label=f"apple backend api readiness iteration {iteration}",
    )
    stats = apple_stats([db, api])
    db_proc = apple_proc_metrics(db, ["/var/lib/postgresql/data"])
    api_proc = apple_proc_metrics(api, ["/tmp"])
    db_load = apple_db_load(db)
    api_load = http_load_with_stats(
        "http://127.0.0.1:18081/ready",
        lambda: apple_stats([api]).get(api, {}),
    )
    stop = run(["container", "stop", api, db], timeout=120.0)
    delete = run(["container", "delete", "--force", api, db], timeout=120.0)
    wait_for_apple_container_absent(api, timeout_s=30.0)
    wait_for_apple_container_absent(db, timeout_s=30.0)
    api_port_closed = wait_for_port_closed(
        "127.0.0.1",
        18081,
        timeout_s=30.0,
        label=f"apple backend api cleanup iteration {iteration}",
    )
    db_port_closed = wait_for_port_closed(
        "127.0.0.1",
        15432,
        timeout_s=30.0,
        label=f"apple backend db cleanup iteration {iteration}",
    )
    delete_network = run(["container", "network", "delete", network], timeout=90.0)
    delete_volume = run(["container", "volume", "delete", volume], timeout=90.0)
    return {
        "runtime": "apple-container",
        "scenario": "backend-shaped",
        "iteration": iteration,
        "status": "measured-with-workarounds",
        "timings_s": {
            "network_create": create_network.duration_s,
            "volume_create": create_volume.duration_s,
            "db_start_command": db_start.duration_s,
            "db_health_wait": db_health.duration_s,
            "migrate": migrate.duration_s,
            "seed": seed.duration_s,
            "api_start_command": api_start.duration_s,
            "readiness_probe": ready.duration_s,
            "stop": stop.duration_s,
            "delete": delete.duration_s,
            "api_port_closed": api_port_closed,
            "db_port_closed": db_port_closed,
            "network_delete": delete_network.duration_s,
            "volume_delete": delete_volume.duration_s,
        },
        "metrics": {
            "db": {
                "runtime_stats": stats.get(db, {}),
                "process": db_proc,
                "load": db_load,
            },
            "api": {
                "runtime_stats": stats.get(api, {}),
                "process": api_proc,
                "load": api_load,
            },
        },
    }


def wait_for(
    command: Callable[[], CommandResult],
    *,
    is_success: Callable[[CommandResult], bool],
    timeout_s: float,
    label: str,
) -> CommandResult:
    start = time.perf_counter()
    last: CommandResult | None = None
    while time.perf_counter() - start < timeout_s:
        last = command()
        if is_success(last):
            return CommandResult(
                argv=last.argv,
                returncode=last.returncode,
                stdout=last.stdout,
                stderr=last.stderr,
                duration_s=time.perf_counter() - start,
            )
        time.sleep(1.0)
    if last is None:
        raise BenchmarkError(f"timeout waiting for {label}")
    raise BenchmarkError(f"timeout waiting for {label}: {format_failure(last)}")


def wait_for_http(url: str, *, timeout_s: float, label: str) -> CommandResult:
    return wait_for(
        lambda: run(["curl", "-fsS", url], check=False, timeout=10.0),
        is_success=lambda result: result.returncode == 0 and bool(result.stdout.strip()),
        timeout_s=timeout_s,
        label=label,
    )


def is_port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.2):
            return True
    except OSError:
        return False


def wait_for_port_closed(host: str, port: int, *, timeout_s: float, label: str) -> float:
    start = time.perf_counter()
    while time.perf_counter() - start < timeout_s:
        if not is_port_open(host, port):
            return time.perf_counter() - start
        time.sleep(0.1)
    raise BenchmarkError(f"timeout waiting for {label} port {host}:{port} to close")


def percentile(values: list[float], percent: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * (percent / 100.0)
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[int(rank)]
    weight = rank - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def summarize_values(values: list[float]) -> dict[str, float | int | None]:
    if not values:
        return {"n": 0, "min": None, "p50": None, "p95": None, "p99": None, "max": None, "mean": None}
    return {
        "n": len(values),
        "min": min(values),
        "p50": percentile(values, 50),
        "p95": percentile(values, 95),
        "p99": percentile(values, 99),
        "max": max(values),
        "mean": statistics.fmean(values),
    }


def collect_metric(row: dict[str, Any], path: list[str]) -> float | None:
    current: Any = row
    for part in path:
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    if isinstance(current, (int, float)):
        return float(current)
    return None


def build_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    summary: dict[str, Any] = {"groups": {}}
    keys = sorted({(row["scenario"], row["runtime"]) for row in rows})
    for scenario, runtime in keys:
        group_rows = [
            row for row in rows if row["scenario"] == scenario and row["runtime"] == runtime
        ]
        timings: dict[str, Any] = {}
        timing_keys = sorted(
            {
                key
                for row in group_rows
                for key in row.get("timings_s", {}).keys()
            }
        )
        for key in timing_keys:
            timings[key] = summarize_values(
                [
                    float(row["timings_s"][key])
                    for row in group_rows
                    if key in row.get("timings_s", {})
                ]
            )
        metrics: dict[str, Any] = {}
        for role in ("web", "db", "api"):
            role_rows = [row for row in group_rows if role in row.get("metrics", {})]
            if not role_rows:
                continue
            metrics[role] = {
                "runtime_memory_usage_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                [
                                    "metrics",
                                    role,
                                    "runtime_stats",
                                    "memory_usage_bytes",
                                ],
                            )
                        )
                        is not None
                    ]
                ),
                "runtime_cpu_percent": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "runtime_stats", "cpu_percent"],
                            )
                        )
                        is not None
                    ]
                ),
                "load_cpu_percent": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                [
                                    "metrics",
                                    role,
                                    "load",
                                    "runtime_stats",
                                    "cpu_percent",
                                ],
                            )
                        )
                        is not None
                    ]
                ),
                "load_requests": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "load", "requests"],
                            )
                        )
                        is not None
                    ]
                ),
                "runtime_block_read_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "runtime_stats", "block_read_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "runtime_block_write_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "runtime_stats", "block_write_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "runtime_net_read_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "runtime_stats", "net_read_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "runtime_net_write_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "runtime_stats", "net_write_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "proc_vmrss_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "process", "proc_vmrss_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "cgroup_memory_current_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "process", "cgroup_memory_current_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "cgroup_memory_peak_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                ["metrics", role, "process", "cgroup_memory_peak_bytes"],
                            )
                        )
                        is not None
                    ]
                ),
                "disk_postgres_data_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                [
                                    "metrics",
                                    role,
                                    "process",
                                    "du_var_lib_postgresql_data_bytes",
                                ],
                            )
                        )
                        is not None
                    ]
                ),
                "disk_nginx_html_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                [
                                    "metrics",
                                    role,
                                    "process",
                                    "du_usr_share_nginx_html_bytes",
                                ],
                            )
                        )
                        is not None
                    ]
                ),
                "disk_nginx_cache_bytes": summarize_values(
                    [
                        value
                        for row in role_rows
                        if (
                            value := collect_metric(
                                row,
                                [
                                    "metrics",
                                    role,
                                    "process",
                                    "du_var_cache_nginx_bytes",
                                ],
                            )
                        )
                        is not None
                    ]
                ),
            }
        summary["groups"][f"{scenario}/{runtime}"] = {
            "scenario": scenario,
            "runtime": runtime,
            "iterations": len(group_rows),
            "timings_s": timings,
            "metrics": metrics,
        }
    return summary


def seconds(value: Any) -> str:
    return "n/a" if value is None else f"{float(value):.3f}s"


def mib(value: Any) -> str:
    return "n/a" if value is None else f"{float(value) / (1024 * 1024):.2f}MiB"


def percent(value: Any) -> str:
    return "n/a" if value is None else f"{float(value):.2f}%"


def write_markdown_report(
    report_path: Path,
    *,
    rows: list[dict[str, Any]],
    summary: dict[str, Any],
    raw_path: Path,
    summary_path: Path,
    args: argparse.Namespace,
    apple_start: CommandResult | None,
    apple_stop: CommandResult | None,
) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = [
        "# Runtime Efficiency Benchmark Evidence",
        "",
        f"**Date:** {datetime.now().date().isoformat()}",
        "**Scope:** Docker/OrbStack versus Apple `container` repeated runtime measurements before implementation starts.",
        "",
        "## Methodology",
        "",
        "- Public fixtures only; no private EMSI workloads.",
        "- Images and runtime caches were preserved; this report measures cached-image runtime behavior with fresh benchmark containers and volumes.",
        "- DB scenarios use fresh volumes per iteration.",
        "- Apple backend uses the already discovered PGDATA and DB-IP workarounds; service-name DNS parity is not assumed.",
        "- Percentiles are sample percentiles from the recorded iteration count.",
        "- Runtime stats are one idle snapshot after readiness; process RSS and cgroup memory are collected from inside the container when available.",
        "- No image prune, registry login, Docker build, Apple `container build`, or global cleanup was run.",
        "",
        "## Iteration Counts",
        "",
        "| Scenario | Runtime | Iterations |",
        "| --- | --- | ---: |",
    ]
    for group in summary["groups"].values():
        lines.append(
            f"| `{group['scenario']}` | `{group['runtime']}` | {group['iterations']} |"
        )
    lines.extend(
        [
            "",
            "## Timing Percentiles",
            "",
            "| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |",
            "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for group in summary["groups"].values():
        for metric, stats in group["timings_s"].items():
            lines.append(
                "| `{}` | `{}` | `{}` | {} | {} | {} | {} | {} |".format(
                    group["scenario"],
                    group["runtime"],
                    metric,
                    stats["n"],
                    seconds(stats["p50"]),
                    seconds(stats["p95"]),
                    seconds(stats["p99"]),
                    seconds(stats["max"]),
                )
            )
    lines.extend(
        [
            "",
            "## Memory And CPU Percentiles",
            "",
            "| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |",
            "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    memory_metric_names = [
        ("runtime_memory_usage_bytes", "runtime memory"),
        ("proc_vmrss_bytes", "process VmRSS"),
        ("cgroup_memory_current_bytes", "cgroup current"),
        ("cgroup_memory_peak_bytes", "cgroup peak"),
        ("runtime_block_read_bytes", "block read"),
        ("runtime_block_write_bytes", "block write"),
        ("runtime_net_read_bytes", "net read"),
        ("runtime_net_write_bytes", "net write"),
        ("disk_postgres_data_bytes", "disk /var/lib/postgresql/data"),
        ("disk_nginx_html_bytes", "disk /usr/share/nginx/html"),
        ("disk_nginx_cache_bytes", "disk /var/cache/nginx"),
    ]
    for group in summary["groups"].values():
        for role, metrics in group["metrics"].items():
            for key, label in memory_metric_names:
                stats = metrics.get(key)
                if not stats or stats["n"] == 0:
                    continue
                lines.append(
                    "| `{}` | `{}` | `{}` | {} | {} | {} | {} | {} | {} |".format(
                        group["scenario"],
                        group["runtime"],
                        role,
                        label,
                        stats["n"],
                        mib(stats["p50"]),
                        mib(stats["p95"]),
                        mib(stats["p99"]),
                        mib(stats["max"]),
                    )
                )
            cpu = metrics.get("runtime_cpu_percent")
            if cpu and cpu["n"]:
                lines.append(
                    "| `{}` | `{}` | `{}` | runtime CPU snapshot | {} | {} | {} | {} | {} |".format(
                        group["scenario"],
                        group["runtime"],
                        role,
                        cpu["n"],
                        percent(cpu["p50"]),
                        percent(cpu["p95"]),
                        percent(cpu["p99"]),
                        percent(cpu["max"]),
                    )
                )
            load_cpu = metrics.get("load_cpu_percent")
            if load_cpu and load_cpu["n"]:
                lines.append(
                    "| `{}` | `{}` | `{}` | load CPU snapshot | {} | {} | {} | {} | {} |".format(
                        group["scenario"],
                        group["runtime"],
                        role,
                        load_cpu["n"],
                        percent(load_cpu["p50"]),
                        percent(load_cpu["p95"]),
                        percent(load_cpu["p99"]),
                        percent(load_cpu["max"]),
                    )
                )
            requests = metrics.get("load_requests")
            if requests and requests["n"]:
                lines.append(
                    "| `{}` | `{}` | `{}` | load HTTP requests | {} | {:.0f} | {:.0f} | {:.0f} | {:.0f} |".format(
                        group["scenario"],
                        group["runtime"],
                        role,
                        requests["n"],
                        requests["p50"],
                        requests["p95"],
                        requests["p99"],
                        requests["max"],
                    )
                )
    lines.extend(
        [
            "",
            "## Apple Runtime Lifecycle",
            "",
            f"- `container system start`: {apple_start.returncode if apple_start else 'not run'}, {seconds(apple_start.duration_s if apple_start else None)}.",
            f"- `container system stop`: {apple_stop.returncode if apple_stop else 'not run'}, {seconds(apple_stop.duration_s if apple_stop else None)}.",
            "",
            "## Evidence Files",
            "",
            f"- Raw JSONL: `{raw_path.relative_to(ROOT)}`",
            f"- Summary JSON: `{summary_path.relative_to(ROOT)}`",
            "",
            "## Harness Command",
            "",
            "```text",
            " ".join(sys.argv),
            "```",
            "",
            "## Cleanup Scope",
            "",
            "The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.",
        ]
    )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_scenario(
    *,
    name: str,
    iterations: int,
    runner: Callable[[int], dict[str, Any]],
    recorder: Recorder,
    rows: list[dict[str, Any]],
) -> None:
    for iteration in range(1, iterations + 1):
        print(f"[{now_iso()}] {name} iteration {iteration}/{iterations}", flush=True)
        try:
            row = runner(iteration)
        except Exception as exc:  # noqa: BLE001 - benchmark evidence should capture failures.
            row = {
                "runtime": name.split("/", 1)[0],
                "scenario": name.split("/", 1)[1] if "/" in name else name,
                "iteration": iteration,
                "status": "failed",
                "error": str(exc),
            }
            recorder.write(row)
            raise
        recorder.write(row)
        rows.append(row)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--simple-iterations", type=int, default=30)
    parser.add_argument("--db-iterations", type=int, default=30)
    parser.add_argument("--backend-iterations", type=int, default=10)
    parser.add_argument(
        "--runtimes",
        default="docker,apple",
        help="Comma-separated runtime list: docker,apple",
    )
    parser.add_argument(
        "--skip-apple-stop",
        action="store_true",
        help="Leave Apple container system running after benchmark.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    raw_path = args.output_dir / f"{timestamp}-runtime-efficiency-raw.jsonl"
    summary_path = args.output_dir / f"{timestamp}-runtime-efficiency-summary.json"
    report_path = args.output_dir / f"{timestamp}-runtime-efficiency-report.md"
    recorder = Recorder(raw_path)
    rows: list[dict[str, Any]] = []
    apple_start: CommandResult | None = None
    apple_stop: CommandResult | None = None
    runtimes = {runtime.strip() for runtime in args.runtimes.split(",") if runtime.strip()}

    try:
        if "docker" in runtimes:
            run_scenario(
                name="docker/simple-web",
                iterations=args.simple_iterations,
                runner=docker_simple_iteration,
                recorder=recorder,
                rows=rows,
            )
            run_scenario(
                name="docker/postgres-db-only",
                iterations=args.db_iterations,
                runner=docker_db_only_iteration,
                recorder=recorder,
                rows=rows,
            )
            run_scenario(
                name="docker/backend-shaped",
                iterations=args.backend_iterations,
                runner=docker_backend_iteration,
                recorder=recorder,
                rows=rows,
            )

        if "apple" in runtimes:
            print(f"[{now_iso()}] starting Apple container system", flush=True)
            apple_start = apple_system_start()
            recorder.write(
                {
                    "runtime": "apple-container",
                    "scenario": "system",
                    "iteration": 1,
                    "status": "measured",
                    "timings_s": {"system_start": apple_start.duration_s},
                    "returncode": apple_start.returncode,
                    "stdout": apple_start.stdout,
                    "stderr": apple_start.stderr,
                }
            )
            if apple_start.returncode != 0 and "already" not in (
                apple_start.stdout + apple_start.stderr
            ).lower():
                raise BenchmarkError(format_failure(apple_start))
            apple_ready = wait_for_apple_system_ready()
            recorder.write(
                {
                    "runtime": "apple-container",
                    "scenario": "system",
                    "iteration": 1,
                    "status": "measured",
                    "timings_s": {"system_ready_wait": apple_ready.duration_s},
                    "returncode": apple_ready.returncode,
                    "stdout": apple_ready.stdout,
                    "stderr": apple_ready.stderr,
                }
            )

            run_scenario(
                name="apple/simple-web",
                iterations=args.simple_iterations,
                runner=apple_simple_iteration,
                recorder=recorder,
                rows=rows,
            )
            run_scenario(
                name="apple/postgres-db-only",
                iterations=args.db_iterations,
                runner=apple_db_only_iteration,
                recorder=recorder,
                rows=rows,
            )
            run_scenario(
                name="apple/backend-shaped",
                iterations=args.backend_iterations,
                runner=apple_backend_iteration,
                recorder=recorder,
                rows=rows,
            )
    finally:
        if "apple" in runtimes and not args.skip_apple_stop:
            print(f"[{now_iso()}] stopping Apple container system", flush=True)
            apple_stop = apple_system_stop()
            recorder.write(
                {
                    "runtime": "apple-container",
                    "scenario": "system",
                    "iteration": 1,
                    "status": "measured",
                    "timings_s": {"system_stop": apple_stop.duration_s},
                    "returncode": apple_stop.returncode,
                    "stdout": apple_stop.stdout,
                    "stderr": apple_stop.stderr,
                }
            )
        recorder.close()

    summary = build_summary(rows)
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown_report(
        report_path,
        rows=rows,
        summary=summary,
        raw_path=raw_path,
        summary_path=summary_path,
        args=args,
        apple_start=apple_start,
        apple_stop=apple_stop,
    )
    print(f"raw={raw_path}", flush=True)
    print(f"summary={summary_path}", flush=True)
    print(f"report={report_path}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

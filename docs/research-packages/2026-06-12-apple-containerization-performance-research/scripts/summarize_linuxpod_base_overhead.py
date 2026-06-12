#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Burak Karahan

import argparse
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path


METRIC_FIELDS = [
    "setupSeconds",
    "createSeconds",
    "readinessSeconds",
    "loadSeconds",
    "stopSeconds",
    "deleteSeconds",
    "processRSSBytes",
    "processHighWaterRSSBytes",
    "processCount",
    "cgroupMemoryCurrentBytes",
    "cgroupMemoryPeakBytes",
    "cgroupMemoryLimitBytes",
    "hostRuntimeRSSBytes",
    "dbDataFootprintBytes",
    "blockReadBytes",
    "blockWriteBytes",
    "cpuPercent",
    "cpuUsageUsec",
    "loadCompletedWork",
    "loadErrors",
]

MEASURED_STATUSES = {"measured-with-limitations"}


def load_jsonl(path):
    records = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{line_number}: invalid JSONL: {exc}") from exc
    return records


def summarize_metric(values):
    if not values:
        return None
    values = sorted(values)
    return {
        "n": len(values),
        "min": values[0],
        "p50": statistics.median(values),
        "max": values[-1],
    }


def summarize(records):
    by_scenario = defaultdict(list)
    for record in records:
        by_scenario[record.get("scenario", "unknown")].append(record)

    scenarios = {}
    for scenario, scenario_records in sorted(by_scenario.items()):
        statuses = Counter(record.get("status", "unknown") for record in scenario_records)
        measured_records = [
            record
            for record in scenario_records
            if record.get("status") in MEASURED_STATUSES
        ]
        metrics = {}
        for field in METRIC_FIELDS:
            values = [
                record.get("metrics", {}).get(field)
                for record in measured_records
                if record.get("metrics", {}).get(field) is not None
            ]
            metrics[field] = summarize_metric(values)

        scenarios[scenario] = {
            "records": len(scenario_records),
            "measuredRecords": len(measured_records),
            "statuses": dict(sorted(statuses.items())),
            "metrics": metrics,
        }

    return {
        "schemaVersion": "linuxpod-base-overhead-summary/v1",
        "records": len(records),
        "statuses": dict(sorted(Counter(record.get("status", "unknown") for record in records).items())),
        "scenarios": scenarios,
    }


def write_report(summary, path):
    lines = [
        "# LinuxPod Base Overhead Evidence Report",
        "",
        f"Total records: `{summary['records']}`",
        "",
        "## Status Counts",
        "",
    ]
    for status, count in summary["statuses"].items():
        lines.append(f"- `{status}`: `{count}`")

    lines.extend(["", "## Scenarios", ""])
    for scenario, scenario_summary in summary["scenarios"].items():
        lines.append(f"### `{scenario}`")
        lines.append("")
        lines.append(f"Records: `{scenario_summary['records']}`")
        lines.append(f"Measured records: `{scenario_summary['measuredRecords']}`")
        lines.append("")
        lines.append("Statuses:")
        for status, count in scenario_summary["statuses"].items():
            lines.append(f"- `{status}`: `{count}`")
        measured_metrics = {
            key: value
            for key, value in scenario_summary["metrics"].items()
            if value is not None
        }
        if measured_metrics:
            lines.append("")
            lines.append("Measured metrics:")
            for key, value in measured_metrics.items():
                lines.append(
                    f"- `{key}`: n=`{value['n']}`, min=`{value['min']}`, p50=`{value['p50']}`, max=`{value['max']}`"
                )
        else:
            lines.append("")
            lines.append("Measured metrics: none")
        lines.append("")

    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Summarize LinuxPod base overhead JSONL evidence.")
    parser.add_argument("jsonl", type=Path)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    records = load_jsonl(args.jsonl)
    summary = summarize(records)
    args.summary.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_report(summary, args.report)


if __name__ == "__main__":
    main()

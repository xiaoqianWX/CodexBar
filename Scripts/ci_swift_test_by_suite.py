#!/usr/bin/env python3
"""Run SwiftPM tests in suite shards so CI cannot hang inside one aggregate run."""

from __future__ import annotations

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from collections.abc import Iterable
from dataclasses import dataclass


@dataclass(frozen=True)
class CommandResult:
    exit_code: int
    duration: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--group-size", type=int, default=12)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--limit-groups", type=int)
    parser.add_argument("--list-only", action="store_true")
    parser.add_argument("--timing-summary-limit", type=int, default=10)
    return parser.parse_args()


def run_command(command: list[str], timeout: int | None = None) -> CommandResult:
    print(f"+ {' '.join(command)}", flush=True)
    started_at = time.monotonic()
    process = subprocess.Popen(command, start_new_session=True)
    try:
        exit_code = process.wait(timeout=timeout)
        return CommandResult(exit_code=exit_code, duration=time.monotonic() - started_at)
    except subprocess.TimeoutExpired:
        print(f"::warning::Command timed out after {timeout}s: {' '.join(command)}", flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return CommandResult(exit_code=124, duration=time.monotonic() - started_at)


def swift_test_list() -> list[str]:
    result = subprocess.run(["swift", "test", "list"], check=True, capture_output=True, text=True)
    suites: set[str] = set()
    for line in result.stdout.splitlines():
        if "/" not in line:
            continue
        suite = line.split("/", 1)[0]
        if "." not in suite:
            continue
        suites.add(suite)
    return sorted(suites)


def chunks(items: list[str], size: int) -> Iterable[list[str]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def prioritized_suites(suites: list[str]) -> list[str]:
    priority = ["CodexBarTests.CLIEntryTests"]
    ordered = [suite for suite in priority if suite in suites]
    ordered.extend(suite for suite in suites if suite not in priority)
    return ordered


def filtered_suites_for_environment(suites: list[str]) -> list[str]:
    if os.environ.get("GITHUB_ACTIONS") != "true" or sys.platform != "darwin":
        return suites

    # SwiftPM hangs before suite output for this executable-target suite on the Intel macOS runner.
    # Linux CI still runs it in the full Swift test lane, and local macOS runs it directly.
    skipped = {"CodexBarTests.CLIEntryTests"}
    filtered = [suite for suite in suites if suite not in skipped]
    if len(filtered) != len(suites):
        print(f"Skipping macOS CI-only suites: {', '.join(sorted(skipped))}", flush=True)
    return filtered


def filter_for(suites: list[str]) -> str:
    escaped = [re.escape(suite) for suite in suites]
    return rf"^({'|'.join(escaped)})/"


def run_group(suites: list[str], timeout: int) -> CommandResult:
    return run_command(["swift", "test", "--no-parallel", "--filter", filter_for(suites)], timeout=timeout)


def timing_label(group_index: int, group_count: int, suites: list[str]) -> str:
    if len(suites) == 1:
        return suites[0]
    return f"shard {group_index}/{group_count}: {suites[0]} ... {suites[-1]} ({len(suites)} suites)"


def print_timing_summary(timings: list[tuple[str, CommandResult]], limit: int) -> None:
    if limit <= 0 or not timings:
        return

    print("::group::Swift test timing summary", flush=True)
    for label, result in sorted(timings, key=lambda item: item[1].duration, reverse=True)[:limit]:
        status = "passed" if result.exit_code == 0 else f"exit {result.exit_code}"
        print(f"{result.duration:7.1f}s  {status:<8} {label}", flush=True)
    print("::endgroup::", flush=True)


def main() -> int:
    args = parse_args()
    if args.group_size < 1:
        print("--group-size must be positive", file=sys.stderr)
        return 2
    if args.timing_summary_limit < 0:
        print("--timing-summary-limit must be non-negative", file=sys.stderr)
        return 2

    suites = prioritized_suites(filtered_suites_for_environment(swift_test_list()))
    print(f"Discovered {len(suites)} test suites", flush=True)
    if args.list_only:
        for suite in suites:
            print(suite)
        return 0

    suite_groups = list(chunks(suites, args.group_size))
    if args.limit_groups is not None:
        suite_groups = suite_groups[: args.limit_groups]

    timings: list[tuple[str, CommandResult]] = []
    for group_index, group in enumerate(suite_groups, start=1):
        print(
            f"::group::Swift test shard {group_index}/{len(suite_groups)} "
            f"({len(group)} suites)",
            flush=True,
        )
        result = run_group(group, args.timeout)
        timings.append((timing_label(group_index, len(suite_groups), group), result))
        print(f"Swift test shard {group_index} finished in {result.duration:.1f}s", flush=True)
        print("::endgroup::", flush=True)
        if result.exit_code == 0:
            continue
        if result.exit_code != 124 or len(group) == 1:
            print_timing_summary(timings, args.timing_summary_limit)
            return result.exit_code

        print(f"Shard {group_index} timed out; retrying suites one at a time", flush=True)
        for suite in group:
            print(f"::group::Swift test retry {suite}", flush=True)
            retry_result = run_group([suite], args.timeout)
            timings.append((suite, retry_result))
            print(f"Swift test retry {suite} finished in {retry_result.duration:.1f}s", flush=True)
            print("::endgroup::", flush=True)
            if retry_result.exit_code != 0:
                print_timing_summary(timings, args.timing_summary_limit)
                return retry_result.exit_code

    print_timing_summary(timings, args.timing_summary_limit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

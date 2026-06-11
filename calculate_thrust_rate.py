#!/usr/bin/env python3
"""Fit a linear relationship between hover height and motor speed."""

from __future__ import annotations

import argparse
import math
import sys


def parse_measurement(value: str) -> tuple[float, float]:
    try:
        height_text, speed_text = value.split(",", maxsplit=1)
        return float(height_text), float(speed_text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"invalid measurement {value!r}; expected HEIGHT,SPEED"
        ) from exc


def linear_fit(measurements: list[tuple[float, float]]) -> tuple[float, float, float]:
    count = len(measurements)
    mean_height = sum(height for height, _ in measurements) / count
    mean_speed = sum(speed for _, speed in measurements) / count

    height_variance = sum(
        (height - mean_height) ** 2 for height, _ in measurements
    )
    if height_variance == 0:
        raise ValueError("measurements must contain at least two different heights")

    covariance = sum(
        (height - mean_height) * (speed - mean_speed)
        for height, speed in measurements
    )
    rate = covariance / height_variance
    intercept = mean_speed - rate * mean_height

    residual_sum = sum(
        (speed - (intercept + rate * height)) ** 2
        for height, speed in measurements
    )
    total_sum = sum((speed - mean_speed) ** 2 for _, speed in measurements)
    r_squared = 1.0 if total_sum == 0 else 1.0 - residual_sum / total_sum

    return rate, intercept, r_squared


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Calculate the linear motor-speed increase per Y level from hover "
            "measurements."
        ),
        epilog=(
            "example: calculate_thrust_rate.py --reference-y=-50 -- "
            "-50,137 0,145.5 50,154"
        ),
    )
    parser.add_argument(
        "measurements",
        metavar="HEIGHT,SPEED",
        nargs="+",
        type=parse_measurement,
        help="measured hover height and motor speed, for example -50,137",
    )
    parser.add_argument(
        "--reference-y",
        type=float,
        default=-50,
        help="Y coordinate represented by baseThrust (default: -50)",
    )
    args = parser.parse_args()

    if len(args.measurements) < 2:
        parser.error("at least two measurements are required")

    try:
        rate, intercept, r_squared = linear_fit(args.measurements)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    base_thrust = intercept + rate * args.reference_y
    predicted_speeds = [
        intercept + rate * height for height, _ in args.measurements
    ]
    maximum_error = max(
        abs(measured - predicted)
        for (_, measured), predicted in zip(args.measurements, predicted_speeds)
    )

    print(f"每格动力增长率: {rate:.6f}")
    print(f"参考高度: {args.reference_y:.6f}")
    print(f"参考高度理论动力: {base_thrust:.6f}")
    print(f"线性拟合 R²: {r_squared:.6f}")
    print(f"最大测量误差: {maximum_error:.6f}")
    print()
    print("controller-config.lua:")
    print(f"baseThrust = {base_thrust:.6f},")
    print(f"baseThrustReferenceY = {args.reference_y:.6f},")
    print(f"thrustPerYLevel = {rate:.6f},")

    if not math.isfinite(rate) or not math.isfinite(base_thrust):
        print("error: calculation produced a non-finite result", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

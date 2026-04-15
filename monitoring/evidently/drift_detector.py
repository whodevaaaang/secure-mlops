"""
Evidently AI Drift Detection Script

Compares reference data (training test set) against current production data
collected from the /predict endpoint. Exports drift metrics to Prometheus
Pushgateway and saves HTML reports.

Usage:
    python drift_detector.py \
        --reference /app/data/reference.csv \
        --current /app/data/current.csv \
        --pushgateway http://monitoring-kube-prometheus-pushgateway:9091 \
        --report-dir /app/reports
"""

import argparse
import json
import os
import sys
from datetime import datetime

import pandas as pd
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset, DataQualityPreset
from evidently.metrics import (
    DataDriftTable,
    DatasetDriftMetric,
    ColumnDriftMetric,
)
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway


FEATURES = [
    "age",
    "income",
    "loan_amount",
    "credit_score",
    "employment_years",
    "num_existing_loans",
]


def load_data(path: str) -> pd.DataFrame:
    """Load CSV data and validate columns."""
    df = pd.read_csv(path)
    missing = set(FEATURES) - set(df.columns)
    if missing:
        print(f"ERROR: Missing columns in {path}: {missing}")
        sys.exit(1)
    return df[FEATURES]


def run_drift_report(reference: pd.DataFrame, current: pd.DataFrame) -> Report:
    """Run Evidently drift detection report."""
    report = Report(metrics=[
        DatasetDriftMetric(),
        DataDriftTable(),
    ] + [
        ColumnDriftMetric(column_name=col) for col in FEATURES
    ])
    report.run(reference_data=reference, current_data=current)
    return report


def extract_metrics(report: Report) -> dict:
    """Extract drift metrics from the Evidently report."""
    result = report.as_dict()
    metrics = {}

    for metric_result in result["metrics"]:
        metric_id = metric_result["metric"]

        if metric_id == "DatasetDriftMetric":
            r = metric_result["result"]
            metrics["dataset_drift_detected"] = 1.0 if r["dataset_drift"] else 0.0
            metrics["dataset_drift_share"] = r["drift_share"]
            metrics["number_of_drifted_columns"] = float(r["number_of_drifted_columns"])

        elif metric_id == "ColumnDriftMetric":
            r = metric_result["result"]
            col = r["column_name"]
            metrics[f"feature_drift_score_{col}"] = r["drift_score"]
            metrics[f"feature_drift_detected_{col}"] = 1.0 if r["drift_detected"] else 0.0

    return metrics


def push_metrics(metrics: dict, pushgateway_url: str, job_name: str = "drift_detection"):
    """Push drift metrics to Prometheus Pushgateway."""
    registry = CollectorRegistry()

    # Dataset-level metrics
    Gauge(
        "ml_drift_dataset_detected",
        "Whether dataset-level drift was detected (1=yes, 0=no)",
        registry=registry,
    ).set(metrics.get("dataset_drift_detected", 0))

    Gauge(
        "ml_drift_share",
        "Share of drifted features",
        registry=registry,
    ).set(metrics.get("dataset_drift_share", 0))

    Gauge(
        "ml_drift_columns_count",
        "Number of drifted columns",
        registry=registry,
    ).set(metrics.get("number_of_drifted_columns", 0))

    # Per-feature drift scores
    feature_score = Gauge(
        "ml_drift_feature_score",
        "Drift score per feature (p-value or distance)",
        ["feature"],
        registry=registry,
    )
    feature_detected = Gauge(
        "ml_drift_feature_detected",
        "Whether drift was detected for a feature (1=yes, 0=no)",
        ["feature"],
        registry=registry,
    )

    for col in FEATURES:
        score_key = f"feature_drift_score_{col}"
        detected_key = f"feature_drift_detected_{col}"
        if score_key in metrics:
            feature_score.labels(feature=col).set(metrics[score_key])
        if detected_key in metrics:
            feature_detected.labels(feature=col).set(metrics[detected_key])

    # Timestamp of last run
    Gauge(
        "ml_drift_last_run_timestamp",
        "Unix timestamp of last drift detection run",
        registry=registry,
    ).set(datetime.utcnow().timestamp())

    push_to_gateway(pushgateway_url, job=job_name, registry=registry)
    print(f"Metrics pushed to {pushgateway_url}")


def save_report(report: Report, report_dir: str):
    """Save HTML report and JSON metrics."""
    os.makedirs(report_dir, exist_ok=True)
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")

    html_path = os.path.join(report_dir, f"drift_report_{timestamp}.html")
    report.save_html(html_path)
    print(f"HTML report saved to {html_path}")

    json_path = os.path.join(report_dir, f"drift_metrics_{timestamp}.json")
    metrics = extract_metrics(report)
    with open(json_path, "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"JSON metrics saved to {json_path}")

    return metrics


def main():
    parser = argparse.ArgumentParser(description="Evidently AI Drift Detection")
    parser.add_argument("--reference", required=True, help="Path to reference dataset CSV")
    parser.add_argument("--current", required=True, help="Path to current dataset CSV")
    parser.add_argument("--pushgateway", default=None, help="Prometheus Pushgateway URL")
    parser.add_argument("--report-dir", default="/app/reports", help="Directory for reports")
    args = parser.parse_args()

    print("=== Evidently AI Drift Detection ===")
    print(f"Reference: {args.reference}")
    print(f"Current:   {args.current}")

    reference = load_data(args.reference)
    current = load_data(args.current)
    print(f"Reference samples: {len(reference)}, Current samples: {len(current)}")

    report = run_drift_report(reference, current)
    metrics = save_report(report, args.report_dir)

    # Print summary
    print("\n=== Drift Summary ===")
    print(f"Dataset drift detected: {bool(metrics.get('dataset_drift_detected', 0))}")
    print(f"Drifted features: {int(metrics.get('number_of_drifted_columns', 0))}/{len(FEATURES)}")
    for col in FEATURES:
        score = metrics.get(f"feature_drift_score_{col}", "N/A")
        detected = bool(metrics.get(f"feature_drift_detected_{col}", 0))
        status = "DRIFT" if detected else "OK"
        print(f"  {col}: score={score:.4f} [{status}]" if isinstance(score, float) else f"  {col}: {status}")

    # Push to Prometheus if configured
    if args.pushgateway:
        try:
            push_metrics(metrics, args.pushgateway)
        except Exception as e:
            print(f"WARNING: Failed to push metrics: {e}")
            print("Continuing without Pushgateway...")

    # Exit with code 1 if drift detected (useful for alerting)
    if metrics.get("dataset_drift_detected", 0):
        print("\nWARNING: Dataset drift detected!")
        sys.exit(0)  # Still exit 0 — CronJob should not fail on drift

    print("\nNo significant drift detected.")


if __name__ == "__main__":
    main()

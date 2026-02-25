import argparse
import json
import os
from pathlib import Path
from typing import Tuple
from urllib.parse import urlparse

import boto3
import joblib
from sklearn.datasets import make_classification
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import train_test_split


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n-samples", type=int, default=10000)
    parser.add_argument("--n-features", type=int, default=20)
    parser.add_argument("--n-estimators", type=int, default=300)
    parser.add_argument("--max-depth", type=int, default=8)
    parser.add_argument("--test-size", type=float, default=0.2)
    parser.add_argument("--random-state", type=int, default=42)

    parser.add_argument("--model-dir", type=str, default=os.getenv("SM_MODEL_DIR", "/opt/ml/model"))
    parser.add_argument(
        "--output-data-dir",
        type=str,
        default=os.getenv("SM_OUTPUT_DATA_DIR", "/opt/ml/output/data"),
    )
    parser.add_argument("--model-s3-uri", type=str, default=os.getenv("MODEL_S3_URI", ""))
    return parser.parse_args()


def parse_s3_uri(uri: str) -> Tuple[str, str]:
    parsed = urlparse(uri)
    if parsed.scheme != "s3" or not parsed.netloc:
        raise ValueError(f"Invalid S3 URI: {uri}")
    return parsed.netloc, parsed.path.lstrip("/")


def build_s3_keys(base_key: str) -> Tuple[str, str]:
    cleaned = base_key.lstrip("/")
    if cleaned == "":
        return "model.pkl", "metrics.json"
    if cleaned.endswith("/"):
        return f"{cleaned}model.pkl", f"{cleaned}metrics.json"
    if cleaned.endswith(".pkl"):
        parent = cleaned.rsplit("/", 1)[0] if "/" in cleaned else ""
        metrics_key = f"{parent}/metrics.json" if parent else "metrics.json"
        return cleaned, metrics_key
    return f"{cleaned}/model.pkl", f"{cleaned}/metrics.json"


def upload_artifacts_to_s3(model_path: Path, metrics_path: Path, model_s3_uri: str) -> None:
    bucket, key = parse_s3_uri(model_s3_uri)
    model_key, metrics_key = build_s3_keys(key)

    s3_client = boto3.client("s3")
    s3_client.upload_file(str(model_path), bucket, model_key)
    s3_client.upload_file(str(metrics_path), bucket, metrics_key)

    print(f"Uploaded model to s3://{bucket}/{model_key}")
    print(f"Uploaded metrics to s3://{bucket}/{metrics_key}")


def main() -> None:
    args = parse_args()

    model_dir = Path(args.model_dir)
    output_data_dir = Path(args.output_data_dir)
    model_dir.mkdir(parents=True, exist_ok=True)
    output_data_dir.mkdir(parents=True, exist_ok=True)

    n_informative = max(2, args.n_features // 2)
    n_redundant = max(1, args.n_features // 5)
    while n_informative + n_redundant >= args.n_features:
        n_redundant = max(0, n_redundant - 1)

    X, y = make_classification(
        n_samples=args.n_samples,
        n_features=args.n_features,
        n_informative=n_informative,
        n_redundant=n_redundant,
        n_classes=2,
        weights=[0.7, 0.3],
        flip_y=0.01,
        class_sep=1.0,
        random_state=args.random_state,
    )

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=args.test_size,
        random_state=args.random_state,
        stratify=y,
    )

    model = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        class_weight="balanced",
        n_jobs=-1,
        random_state=args.random_state,
    )
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    metrics = {
        "accuracy": float(accuracy_score(y_test, y_pred)),
        "roc_auc": None,
        "n_samples": args.n_samples,
        "n_features": args.n_features,
        "n_estimators": args.n_estimators,
        "max_depth": args.max_depth,
    }

    if hasattr(model, "predict_proba"):
        y_prob = model.predict_proba(X_test)[:, 1]
        metrics["roc_auc"] = float(roc_auc_score(y_test, y_prob))

    model_path = model_dir / "model.pkl"
    metrics_path = output_data_dir / "metrics.json"

    joblib.dump(model, model_path)
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print(f"Model saved to: {model_path}")
    print(f"Metrics saved to: {metrics_path}")
    print(f"Metrics: {json.dumps(metrics)}")

    if args.model_s3_uri:
        upload_artifacts_to_s3(model_path, metrics_path, args.model_s3_uri)


if __name__ == "__main__":
    main()

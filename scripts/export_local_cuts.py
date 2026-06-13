#!/usr/bin/env python3
"""
Export cutter model files and metadata from local app data.

This does not call any remote API. Point it at an unpacked OfflineApp folder,
or at app data pulled from a device after the official app has completed sync.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any


ZIP_PASSWORD = b"HSApp3568h9k"
BLT_DES_KEY = b"abcd1234"
MODEL_HINT_DIRS = {"model", "models"}


def is_sqlite(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(16) == b"SQLite format 3\x00"
    except OSError:
        return False


def extract_zip(path: Path, work_dir: Path) -> Path:
    target = work_dir / path.stem
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path) as archive:
        archive.extractall(target, pwd=ZIP_PASSWORD)
    return target


def iter_sources(paths: list[Path], work_dir: Path) -> list[Path]:
    resolved: list[Path] = []
    for path in paths:
        path = path.expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(path)
        if path.is_file() and path.suffix.lower() == ".zip":
            resolved.append(extract_zip(path, work_dir))
        else:
            resolved.append(path)
    return resolved


def discover_sqlite_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if path.is_file() and is_sqlite(path):
            files.append(path)
    return files


def discover_model_files(root: Path) -> dict[str, Path]:
    files: dict[str, Path] = {}
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        parent_names = {part.lower() for part in path.parts}
        looks_like_model = bool(parent_names & MODEL_HINT_DIRS)
        looks_like_cut_file = path.suffix.lower() in {".plt", ".blt"}
        if looks_like_model or looks_like_cut_file:
            files.setdefault(path.name, path)
    return files


def table_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')]


def find_model_tables(conn: sqlite3.Connection) -> list[tuple[str, list[str]]]:
    tables = [
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
    ]
    candidates: list[tuple[str, list[str]]] = []
    for table in tables:
        cols = table_columns(conn, table)
        lower_cols = {col.lower() for col in cols}
        if "file" in lower_cols and (
            "modelname" in lower_cols
            or "model_name" in lower_cols
            or "category_id" in lower_cols
            or "brand_id" in lower_cols
        ):
            candidates.append((table, cols))
    return candidates


def normalize_row(db_path: Path, table: str, row: sqlite3.Row) -> dict[str, Any]:
    data = {key: row[key] for key in row.keys()}
    lowered = {key.lower(): key for key in data}

    def get(*names: str) -> Any:
        for name in names:
            key = lowered.get(name)
            if key is not None:
                return data.get(key)
        return None

    return {
        "db": str(db_path),
        "table": table,
        "id": get("id", "_id"),
        "modelname": get("modelname", "model_name", "name"),
        "category_id": get("category_id"),
        "brand_id": get("brand_id"),
        "series_id": get("series_id"),
        "cutclassify_id": get("cutclassify_id"),
        "cutcount": get("cutcount"),
        "file": get("file"),
        "updated_time": get("updated_time", "updatetime", "update_time"),
        "raw": data,
    }


def load_model_metadata(db_path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        for table, cols in find_model_tables(conn):
            selected = ", ".join(f'"{col}"' for col in cols)
            for row in conn.execute(f'SELECT {selected} FROM "{table}"'):
                records.append(normalize_row(db_path, table, row))
    finally:
        conn.close()
    return records


def maybe_decrypt_blt(src: Path, dst: Path) -> bool:
    if src.suffix.lower() != ".blt":
        return False
    try:
        from Crypto.Cipher import DES  # type: ignore
    except Exception:
        return False

    data = src.read_bytes()
    cipher = DES.new(BLT_DES_KEY, DES.MODE_ECB)
    decrypted = cipher.decrypt(data)
    pad = decrypted[-1] if decrypted else 0
    if 0 < pad <= 8:
        decrypted = decrypted[:-pad]
    dst.write_bytes(decrypted)
    return True


def copy_model_files(
    model_files: dict[str, Path], output_model_dir: Path, decrypt_blt: bool
) -> dict[str, dict[str, Any]]:
    output_model_dir.mkdir(parents=True, exist_ok=True)
    copied: dict[str, dict[str, Any]] = {}
    for name, src in sorted(model_files.items()):
        dst = output_model_dir / name
        shutil.copy2(src, dst)
        decrypted_path = None
        if decrypt_blt:
            candidate = dst.with_suffix(".plt")
            if maybe_decrypt_blt(src, candidate):
                decrypted_path = str(candidate)
        copied[name] = {
            "source": str(src),
            "exported": str(dst),
            "size": src.stat().st_size,
            "decrypted": decrypted_path,
        }
    return copied


def write_csv(path: Path, records: list[dict[str, Any]]) -> None:
    fieldnames = [
        "id",
        "modelname",
        "category_id",
        "brand_id",
        "series_id",
        "cutclassify_id",
        "cutcount",
        "file",
        "has_file",
        "source_file",
        "db",
        "table",
        "updated_time",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for record in records:
            writer.writerow({key: record.get(key) for key in fieldnames})


def build_export(
    sources: list[Path], output: Path, copy_files: bool, decrypt_blt: bool
) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=True)
    all_model_files: dict[str, Path] = {}
    all_records: list[dict[str, Any]] = []
    db_files: list[Path] = []

    for source in sources:
        all_model_files.update(discover_model_files(source))
        db_files.extend(discover_sqlite_files(source))

    for db_path in db_files:
        try:
            all_records.extend(load_model_metadata(db_path))
        except sqlite3.DatabaseError as exc:
            print(f"Skipping unreadable sqlite file {db_path}: {exc}", file=sys.stderr)

    copied = {}
    if copy_files:
        copied = copy_model_files(all_model_files, output / "model", decrypt_blt)

    for record in all_records:
        file_name = record.get("file")
        src = all_model_files.get(str(file_name)) if file_name else None
        record["has_file"] = src is not None
        record["source_file"] = str(src) if src else None

    summary = {
        "sources": [str(path) for path in sources],
        "sqlite_files": [str(path) for path in db_files],
        "metadata_records": len(all_records),
        "model_files_found": len(all_model_files),
        "model_files_copied": len(copied),
        "records_missing_local_file": sum(1 for row in all_records if not row["has_file"]),
    }

    (output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (output / "cuts_index.json").write_text(
        json.dumps(all_records, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    write_csv(output / "cuts_index.csv", all_records)
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export local cutter model metadata/files from app data."
    )
    parser.add_argument(
        "source",
        nargs="+",
        help="Unpacked OfflineApp folder, app files folder, database folder, or zip.",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="cuts_export",
        help="Output folder. Default: cuts_export",
    )
    parser.add_argument(
        "--no-copy",
        action="store_true",
        help="Only write indexes; do not copy model files.",
    )
    parser.add_argument(
        "--decrypt-blt",
        action="store_true",
        help="Also try to decrypt .blt files if pycryptodome is installed.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    with tempfile.TemporaryDirectory(prefix="cutter_export_") as temp_dir:
        sources = iter_sources([Path(item) for item in args.source], Path(temp_dir))
        summary = build_export(
            sources=sources,
            output=Path(args.output).expanduser().resolve(),
            copy_files=not args.no_copy,
            decrypt_blt=args.decrypt_blt,
        )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

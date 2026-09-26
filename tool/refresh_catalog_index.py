"""Refresh the searchable public Delfan catalog snapshot used by MBNMovie."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from hashlib import md5
import json
from pathlib import Path
import random
import re
import threading
import time

import requests

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "lib/services/movie_api.dart").read_text(encoding="utf-8")
KEY = re.search(r"defaultValue: '([^']+)'", SOURCE).group(1)
BASE = "http://googfilmazappfordownfilmmedis.xyz/app-plus/"
OUT = ROOT / "assets/catalog_index.json"
CHECKPOINT = ROOT / "tool/catalog_index_checkpoint.jsonl"
THREAD = threading.local()


def session():
    if not hasattr(THREAD, "session"):
        THREAD.session = requests.Session()
    return THREAD.session


def digest(value):
    return md5(value.encode("utf-8")).hexdigest()


def call(action, extra=None):
    client = session()
    for attempt in range(3):
        try:
            init = client.post(
                f"{BASE}users.php?key={KEY}&action=login",
                data={"user_name": "", "token": "", "android_id": "",
                      "app_verion": "2", "version_sp": "ورژن 2",
                      "is_tv": "", "apname": "Delfan"},
                timeout=25,
            ).json()
            auth = str(init["infos"][0]["auth"])
            nonce = random.randrange(500)
            stamp = datetime.now(timezone.utc).isoformat()
            body = (
                digest(f"{nonce}cotation") + auth +
                "fdaa94a151e2c5d474a290e8" + auth +
                "y87mdjsodonc215sfxd545fgs" + digest(stamp + "cotation")
            )
            data = {
                "user_name": "", "token": "", "body": body,
                "an": digest(str(int(init.get("q1", 0)) + int(init.get("q2", 0)) + 101)),
                "langueg": "", "u_s": init.get("night_mode", ""),
                "s_n": init.get("tx_size", ""), "apname": "Delfan",
                **(extra or {}),
            }
            response = client.post(
                f"{BASE}vp1.php?key={KEY}&action={action}",
                data=data,
                timeout=65,
            ).json()
            if response.get("state_all") == "T":
                return response
        except (requests.RequestException, ValueError, KeyError):
            pass
        time.sleep(.4 * (attempt + 1))
    raise RuntimeError(f"Could not read {action}")


def list_kind(kind):
    rows = {}
    page = 1
    while True:
        response = call(f"movie_list&pageno={page}", {
            "c": "2", "select_dub": "", "is_movie": kind,
        })
        items = response.get("all") or []
        if not items:
            break
        for item in items:
            item_id = str(item.get("videos_id") or item.get("id") or "")
            if item_id:
                rows[item_id] = {
                    "id": item_id,
                    "title": str(item.get("title") or ""),
                    "image": str(item.get("thumbnail_url") or ""),
                    "year": str(item.get("year") or ""),
                    "rating": str(item.get("imdb") or ""),
                    "kind": kind,
                }
        if page % 25 == 0:
            print(f"{kind}: {page} pages, {len(rows)} titles", flush=True)
        page += 1
        if page > 800:
            raise RuntimeError(f"Catalog pagination did not end for {kind}")
    print(f"{kind}: {len(rows)} titles", flush=True)
    return rows


def enrich(row):
    response = call("detials", {"id": row["id"], "is_mobile": "1"})
    details = response.get("detiles") or []
    if details:
        detail = details[0]
        description = str(detail.get("description") or "")
        match = re.search(r"نام\s*اصلی\s*[:：]\s*([^<\r\n]+)", description)
        row["aliases"] = [match.group(1).strip()] if match else []
        row["genres"] = str(detail.get("genre") or "")
        row["countries"] = str(detail.get("country") or "")
        row["is_duble"] = str(detail.get("is_duble") or "")
        row["subtitles"] = str(detail.get("subtitles") or "")
        row["state_serie"] = str(detail.get("state_serie") or "")
    return row


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    CHECKPOINT.parent.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(list_kind, kind) for kind in ("movie", "serie")]
        rows = {}
        for job in as_completed(jobs):
            rows.update(job.result())
    completed = {}
    if CHECKPOINT.exists():
        for line in CHECKPOINT.read_text(encoding="utf-8").splitlines():
            try:
                item = json.loads(line)
                completed[item["id"]] = item
            except (ValueError, KeyError):
                continue
    pending = [row for row in rows.values()
               if row["id"] not in completed or "is_duble" not in completed[row["id"]]]
    print(f"Detail metadata: {len(completed)} cached, {len(pending)} pending", flush=True)
    with CHECKPOINT.open("a", encoding="utf-8") as checkpoint:
        with ThreadPoolExecutor(max_workers=10) as pool:
            futures = {pool.submit(enrich, row): row for row in pending}
            for number, future in enumerate(as_completed(futures), start=1):
                try:
                    item = future.result()
                except RuntimeError:
                    continue
                completed[item["id"]] = item
                checkpoint.write(json.dumps(item, ensure_ascii=False) + "\n")
                if number % 50 == 0:
                    checkpoint.flush()
                    print(f"Detail metadata: {len(completed)}/{len(rows)}", flush=True)
    if len(completed) < len(rows):
        raise RuntimeError(f"Index incomplete: {len(completed)}/{len(rows)}")
    data = [completed[item_id] for item_id in rows]
    priority = ROOT / 'tool/catalog_priority.json'
    if priority.exists():
        preferred = {row['id']: row for row in
                     json.loads(priority.read_text(encoding='utf-8'))}
        for row in data:
            if row['id'] in preferred:
                row.update(preferred[row['id']])
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Saved {len(data)} titles to {OUT}", flush=True)


if __name__ == "__main__":
    main()

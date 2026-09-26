"""Build a complete lightweight title catalog, then merge saved detail metadata."""

from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path

from refresh_catalog_index import call, CHECKPOINT, OUT, ROOT


def fetch(kind, page):
    result = call(f"movie_list&pageno={page}", {
        "c": "2", "select_dub": "", "is_movie": kind,
    })
    items = []
    for item in result.get("all") or []:
        item_id = str(item.get("videos_id") or item.get("id") or "")
        if item_id:
            items.append({
                "id": item_id,
                "title": str(item.get("title") or ""),
                "image": str(item.get("thumbnail_url") or ""),
                "year": str(item.get("year") or ""),
                "rating": str(item.get("imdb") or ""),
                "kind": kind,
            })
    return items


def main():
    rows = {}
    for kind in ("movie", "serie"):
        page = 1
        with ThreadPoolExecutor(max_workers=8) as pool:
            while page <= 800:
                batch = list(pool.map(lambda n: fetch(kind, n), range(page, page + 16)))
                if not any(batch):
                    break
                for items in batch:
                    for item in items:
                        rows[item["id"]] = item
                page += 16
                if page % 64 == 1:
                    print(f"{kind}: {page - 1} pages", flush=True)
        print(f"{kind}: finished at page {page - 1}", flush=True)
    base = ROOT / "tool/catalog_base.json"
    base.write_text(json.dumps(list(rows.values()), ensure_ascii=False), encoding="utf-8")
    merge()


def merge():
    base = ROOT / "tool/catalog_base.json"
    rows = {item["id"]: item for item in json.loads(base.read_text(encoding="utf-8"))}
    if CHECKPOINT.exists():
        for line in CHECKPOINT.read_text(encoding="utf-8").splitlines():
            try:
                item = json.loads(line)
                if item["id"] in rows:
                    rows[item["id"]].update(item)
            except (ValueError, KeyError):
                continue
    priority = ROOT / "tool/catalog_priority.json"
    if priority.exists():
        for item in json.loads(priority.read_text(encoding="utf-8")):
            if item["id"] in rows:
                rows[item["id"]].update(item)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(list(rows.values()), ensure_ascii=False,
                              separators=(",", ":")), encoding="utf-8")
    print(f"Saved {len(rows)} titles to {OUT}", flush=True)


if __name__ == "__main__":
    main()

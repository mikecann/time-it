#!/usr/bin/env python3
"""Read the signed-in owner's entire Clockify history using a user-created API key.

Only GET requests are made. The key comes from a private file, never command-line text.
The raw archive retains source metadata; time-it.json is the portable native import.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, quote
from urllib.request import Request, build_opener, HTTPRedirectHandler


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # Never forward an API credential to a different destination.


class Clockify:
    def __init__(self, key):
        self.key = key
        self.opener = build_opener(NoRedirect())

    def get(self, path, params=None):
        url = "https://api.clockify.me/api/v1/" + path
        if params:
            url += "?" + urlencode(params)
        for attempt in range(4):
            try:
                request = Request(url, headers={"X-Api-Key": self.key, "Accept": "application/json"})
                with self.opener.open(request, timeout=30) as response:
                    return json.load(response), response.headers
            except HTTPError as error:
                if error.code >= 500 and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                # Response bodies can contain personal data. Keep diagnostics to status and path.
                raise RuntimeError(f"Clockify returned HTTP {error.code} for {path}. Nothing has been imported.") from None
            except URLError:
                if attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError("Could not reach Clockify. Nothing has been imported.") from None

    def pages(self, path, params=None):
        records, known, audit = [], set(), []
        for page in range(1, 10001):
            values, headers = self.get(path, {**(params or {}), "page": page, "page-size": 1000})
            if not isinstance(values, list):
                raise RuntimeError("Clockify did not return a paginated list.")
            last = headers.get("Last-Page", "").lower()
            audit.append({"page": page, "count": len(values), "lastPage": last})
            if any(value["id"] in known for value in values):
                # A moving history or an ignored page parameter must not silently create a partial export.
                raise RuntimeError("Clockify returned overlapping pages. Retry after its timer has stopped.")
            records.extend(values)
            known.update(value["id"] for value in values)
            if last == "true" or not values:
                return records, audit
        raise RuntimeError("Clockify pagination did not finish.")


def milliseconds(value):
    return round(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)


def normalize(workspaces):
    categories, entries, known, skipped = {}, [], set(), 0
    for workspace in workspaces:
        wid = workspace["id"]
        projects = {value["id"]: value for value in workspace["projects"]}
        clients = {value["id"]: value for value in workspace["clients"]}
        tags = {value["id"]: value for value in workspace["tags"]}
        for source in workspace["entries"]:
            interval = source["timeInterval"]
            if not interval.get("end"):
                skipped += 1
                continue
            hydrated = source.get("project") or {}
            pid = source.get("projectId") or hydrated.get("id")
            project = {**projects.get(pid, {}), **hydrated}
            client = project.get("client") or clients.get(project.get("clientId")) or {}
            name = client.get("name") or project.get("clientName") or project.get("name") or "Uncategorised"
            if name.casefold() == "convex" or project.get("name", "").casefold() in ("convex", "convex general"):
                name = "Convex"
            if len(name.encode("utf-16-le")) // 2 > 100:
                raise RuntimeError("A Clockify category exceeds 100 characters. The raw archive retains it; adjust the mapping before import.")
            cid = "clockify:category:" + hashlib.sha256(name.casefold().encode()).hexdigest()[:32]
            color = project.get("color") or "#79B8B0"
            if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
                color = "#79B8B0"
            if name == "Convex":
                color = "#E8AE58"
            categories.setdefault(cid, {"clientId": cid, "name": name, "color": color, "archived": False, "revision": 1, "deviceId": "clockify-import", "updatedAt": 0})
            details = []
            if project.get("name"):
                details.append("Project: " + project["name"])
            task = source.get("task") or {}
            if task.get("name"):
                details.append("Task: " + task["name"])
            elif source.get("taskId"):
                details.append("Task ID: " + source["taskId"])
            source_tags = source.get("tags") or [tags.get(tid, {"name": tid}) for tid in source.get("tagIds", [])]
            if source_tags:
                details.append("Tags: " + ", ".join(tag["name"] for tag in source_tags))
            note = "\n".join(filter(None, [source.get("description", ""), " · ".join(details)]))
            if len(note.encode("utf-16-le")) // 2 > 2000:
                raise RuntimeError("A Clockify note exceeds 2,000 characters. The raw archive retains it; adjust the mapping before import.")
            eid = f"clockify:{wid}:{source['id']}"
            if eid in known:
                raise RuntimeError("Clockify export contains duplicate session IDs.")
            known.add(eid)
            start, end = milliseconds(interval["start"]), milliseconds(interval["end"])
            if end < start:
                raise RuntimeError("Clockify contains an entry ending before it starts.")
            entries.append({"clientId": eid, "categoryId": cid, "note": note, "startedAt": start, "endedAt": end, "deleted": False, "revision": 1, "deviceId": "clockify-import", "updatedAt": end})
    return {"version": 1, "source": "clockify", "categories": list(categories.values()), "entries": entries, "skippedRunning": skipped}


def save_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)


def export(api, output):
    user, _ = api.get("user")
    workspaces, _ = api.get("workspaces")
    raw = {"exportedAt": datetime.now(timezone.utc).isoformat(), "user": user, "workspaces": []}
    for workspace in workspaces:
        wid = workspace["id"]
        prefix = "workspaces/" + quote(wid, safe="") + "/"
        entries, pages = api.pages(prefix + "user/" + quote(user["id"], safe="") + "/time-entries", {"hydrated": "true"})
        # Active and archived projects are both required to label old history correctly.
        active, _ = api.pages(prefix + "projects", {"archived": "false"})
        archived, _ = api.pages(prefix + "projects", {"archived": "true"})
        projects = {p["id"]: p for p in active + archived}
        for entry in entries:
            pid = entry.get("projectId") or (entry.get("project") or {}).get("id")
            if pid and pid not in projects:
                project, _ = api.get(prefix + "projects/" + quote(pid, safe=""))
                projects[pid] = project
        active_clients, _ = api.pages(prefix + "clients", {"archived": "false"})
        archived_clients, _ = api.pages(prefix + "clients", {"archived": "true"})
        clients = list({c["id"]: c for c in active_clients + archived_clients}.values())
        active_tags, _ = api.pages(prefix + "tags", {"archived": "false"})
        archived_tags, _ = api.pages(prefix + "tags", {"archived": "true"})
        tags = list({t["id"]: t for t in active_tags + archived_tags}.values())
        record = {"id": wid, "name": workspace["name"], "entries": entries, "entryPages": pages, "projects": list(projects.values()), "clients": clients, "tags": tags}
        raw["workspaces"].append(record)
        save_private(output / "clockify-source.json", raw)
        print(f"Read {len(entries):,} sessions from a workspace across {len(pages)} pages.", flush=True)
    archive = normalize(raw["workspaces"])
    save_private(output / "time-it.json", archive)
    summary = {"workspaces": len(workspaces), "completedSessions": len(archive["entries"]), "categories": len(archive["categories"]), "skippedRunning": archive["skippedRunning"], "seconds": sum((e["endedAt"] - e["startedAt"]) / 1000 for e in archive["entries"]), "firstStart": min((e["startedAt"] for e in archive["entries"]), default=None), "lastEnd": max((e["endedAt"] for e in archive["entries"]), default=None)}
    save_private(output / "summary.json", summary)
    print(json.dumps(summary))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("work/clockify-export"))
    args = parser.parse_args()
    key = args.key_file.read_text().strip()
    if not key:
        parser.error("The private key file is empty. Create a Clockify API key first.")
    try:
        export(Clockify(key), args.output)
    except (RuntimeError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

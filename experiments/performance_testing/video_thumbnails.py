#!/usr/bin/env python3

import requests
import time
import os
import sys
import argparse

# ============================================================
# Configuration
# ============================================================

IMMICH_SERVER_URL = "https://homelab-fbx.lasea.fr:25405/photos/"
API_KEY = os.environ.get("API_KEY")

VERIFY_SSL = False

MB = 1024 * 1024

SMALL_LIMIT = 50 * MB
LARGE_LIMIT = 512 * MB

SAMPLE_FILES_LIMIT = 50

GROUPS = {
    "small": (0, SMALL_LIMIT),
    "medium": (SMALL_LIMIT, LARGE_LIMIT),
    "large": (LARGE_LIMIT, float("inf")),
}

JOB_POLL_INTERVAL = 0.2

JOBS = {
    "thumbnail": {
        "asset_job": "regenerate-thumbnail",
        "queue": "thumbnailGeneration",
    },
    "metadata": {
        "asset_job": "refresh-metadata",
        "queue": "metadataExtraction",
    },
    "transcode": {
        "asset_job": "transcode-video",
        "queue": "videoConversion",
    },
}

DEBUG_PRINT_IDS = True

# ============================================================


class ImmichClient:

    def __init__(self, server, api_key, verify_ssl=False):

        self.server = server.rstrip("/")

        self.session = requests.Session()
        self.session.verify = verify_ssl

        self.session.headers.update({
            "x-api-key": api_key,
            "Accept": "application/json",
            "Content-Type": "application/json",
        })

    def get_all_assets(self):

        page = 1
        size = 1000

        assets = []

        while True:

            r = self.session.post(
                f"{self.server}/api/search/metadata",
                json={
                    "page": page,
                    "size": size,
                    "withExif": True,
                },
            )

            r.raise_for_status()

            data = r.json()

            items = data["assets"]["items"]

            if not items:
                break

            assets.extend(items)

            print(f"Loaded page {page}: {len(items)} assets")

            if len(items) < size:
                break

            page += 1

        return assets

    def clear_queue(self, queue):

        r = self.session.put(
            f"{self.server}/api/jobs/{queue}",
            json={
                "command": "empty",
            },
        )

        r.raise_for_status()

    def run_asset_job(self, asset_ids, asset_job):

        r = self.session.post(
            f"{self.server}/api/assets/jobs",
            json={
                "assetIds": asset_ids,
                "name": asset_job,
            },
        )

        r.raise_for_status()

    def wait_job(self, queue):

        while True:

            r = self.session.get(
                f"{self.server}/api/jobs"
            )

            r.raise_for_status()

            counts = r.json()[queue]["jobCounts"]

            waiting = counts["waiting"]
            active = counts["active"]

            # print(
            #     f"{queue}: "
            #     f"waiting={waiting} "
            #     f"active={active}"
            # )

            if waiting == 0 and active == 0:
                return

            time.sleep(JOB_POLL_INTERVAL)


def human_size(size):

    units = [
        "B",
        "KB",
        "MB",
        "GB",
        "TB",
    ]

    size = float(size)

    for unit in units:

        if size < 1024:
            return f"{size:.1f} {unit}"

        size /= 1024

    return f"{size:.1f} PB"

def parse_args():
    parser = argparse.ArgumentParser(
        description="Benchmark Immich background jobs on video assets."
    )

    parser.add_argument(
        "--group",
        required=True,
        choices=GROUPS.keys(),
        help="Video size group to process.",
    )

    parser.add_argument(
        "--job",
        required=True,
        choices=JOBS.keys(),
        help="Immich background job to execute.",
    )

    return parser.parse_args()

def main():

    args = parse_args()

    if not API_KEY:
        sys.exit("Error: API_KEY environment variable is not set.")

    client = ImmichClient(
        IMMICH_SERVER_URL,
        API_KEY,
        VERIFY_SSL,
    )

    job = JOBS[args.job]

    assets = client.get_all_assets()

    images = 0
    videos = 0

    group_stats = {
        "small": 0,
        "medium": 0,
        "large": 0,
    }

    total_video_size = 0

    for asset in assets:

        asset_type = asset["type"]

        if asset_type == "IMAGE":
            images += 1
            continue

        if asset_type != "VIDEO":
            continue

        videos += 1

        size = int(
            asset["exifInfo"].get("fileSizeInByte") or 0
        )

        total_video_size += size

        if size < SMALL_LIMIT:
            group_stats["small"] += 1
        elif size < LARGE_LIMIT:
            group_stats["medium"] += 1
        else:
            group_stats["large"] += 1

    print()
    print("========== SUMMARY ==========")
    print(f"Total assets : {len(assets)}")
    print(f"Images       : {images}")
    print(f"Videos       : {videos}")
    print()

    print("Video size distribution")
    print("-----------------------")
    print(
        f"Small  (<{SMALL_LIMIT // MB} MB)              : "
        f"{group_stats['small']}"
    )
    print(
        f"Medium ({SMALL_LIMIT // MB}-{LARGE_LIMIT // MB} MB)      : "
        f"{group_stats['medium']}"
    )
    print(
        f"Large  (≥{LARGE_LIMIT // MB} MB)             : "
        f"{group_stats['large']}"
    )
    print()

    if videos:
        print(
            f"Total video size   : "
            f"{human_size(total_video_size)}"
        )
        print(
            f"Average video size : "
            f"{human_size(total_video_size / videos)}"
        )

    min_size, max_size = GROUPS[args.group]

    selected = []

    for asset in assets:

        if asset["type"] != "VIDEO":
            continue

        size = int(asset["exifInfo"]["fileSizeInByte"])

        if not (min_size <= size < max_size):
            continue

        selected.append(asset)

        if len(selected) == SAMPLE_FILES_LIMIT:
            break

    for asset in selected:

        asset_id = asset["id"]

        print()
        print("=" * 80)
        print(asset_id)
        print(asset["originalFileName"])

        start = time.perf_counter()

        client.run_asset_job(
            [asset_id],
            job["asset_job"],
        )

        client.wait_job(job["queue"])

        elapsed = time.perf_counter() - start

        print(f"{elapsed:.2f} s")

    return

if __name__ == "__main__":
    if not VERIFY_SSL:
        requests.packages.urllib3.disable_warnings()

    main()
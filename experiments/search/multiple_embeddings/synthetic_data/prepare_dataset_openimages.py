#!/usr/bin/env python3

import argparse
import csv
import json
import random
import shutil
import urllib.request
from collections import defaultdict
from pathlib import Path

from PIL import Image


# ============================================================
# URLs
# ============================================================

CLASS_DESCRIPTIONS_URL = (
    "https://storage.googleapis.com/"
    "openimages/v6/oidv6-class-descriptions.csv"
)

TRAIN_BBOXES_URL = (
    "https://storage.googleapis.com/"
    "openimages/v6/"
    "oidv6-train-annotations-bbox.csv"
)

VALIDATION_BBOXES_URL = (
    "https://storage.googleapis.com/"
    "openimages/v6/"
    "validation/"
    "validation-annotations-bbox.csv"
)


# ============================================================
# DEFAULT CLASSES
# ============================================================

DEFAULT_OBJECTS = [
    "dog",
    "cat",
    "car",
    "motorcycle",
]


DEFAULT_BACKGROUNDS = [
    "forest",
    "lake",
    "grass",
    "sky",
    "house",
]


# ============================================================
# LOGGING
# ============================================================

def log(message):
    print(
        f"[INFO] {message}",
        flush=True,
    )


def warning(message):
    print(
        f"[WARNING] {message}",
        flush=True,
    )


# ============================================================
# DOWNLOAD
# ============================================================

def download_file(
    url,
    destination,
):
    destination = Path(destination)

    if destination.exists():
        return

    destination.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    log(
        f"Downloading:\n"
        f"  {url}\n"
        f"  -> {destination}"
    )

    urllib.request.urlretrieve(
        url,
        destination,
    )


# ============================================================
# JSON
# ============================================================

def save_json(
    path,
    data,
):
    path = Path(path)

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with open(
        path,
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2,
        )


# ============================================================
# CLASS DESCRIPTIONS
# ============================================================

def load_class_descriptions(
    path,
):
    mapping = {}

    with open(
        path,
        "r",
        encoding="utf-8",
    ) as f:

        reader = csv.reader(f)

        for row in reader:

            if len(row) < 2:
                continue

            label_name = row[0]
            class_name = row[1]

            mapping[
                label_name
            ] = class_name

    return mapping


def normalize_class_name(
    name,
):
    return (
        name
        .strip()
        .lower()
    )


def find_label_ids(
    class_descriptions,
    requested_classes,
):
    normalized = {
        normalize_class_name(name): name
        for name in requested_classes
    }

    result = {}

    for label_id, class_name in (
        class_descriptions.items()
    ):

        normalized_name = normalize_class_name(
            class_name
        )

        if normalized_name in normalized:

            requested_name = normalized[
                normalized_name
            ]

            result[
                requested_name
            ] = label_id

    return result


# ============================================================
# BBOX RECORD
# ============================================================

def parse_bbox_row(
    row,
):
    return {
        "image_id": row["ImageID"],
        "source": row["Source"],
        "label_name": row["LabelName"],
        "confidence": float(
            row.get(
                "Confidence",
                1,
            )
        ),
        "xmin": float(
            row["XMin"]
        ),
        "xmax": float(
            row["XMax"]
        ),
        "ymin": float(
            row["YMin"]
        ),
        "ymax": float(
            row["YMax"]
        ),
        "is_occluded": int(
            row.get(
                "IsOccluded",
                0,
            )
        ),
        "is_truncated": int(
            row.get(
                "IsTruncated",
                0,
            )
        ),
        "is_group_of": int(
            row.get(
                "IsGroupOf",
                0,
            )
        ),
        "is_depiction": int(
            row.get(
                "IsDepiction",
                0,
            )
        ),
        "is_inside": int(
            row.get(
                "IsInside",
                0,
            )
        ),
    }


# ============================================================
# READ ANNOTATIONS
# ============================================================

def collect_annotations(
    annotation_file,
    label_ids,
    max_candidates,
    seed,
):
    random.seed(seed)

    label_id_to_class = {
        label_id: class_name
        for class_name, label_id
        in label_ids.items()
    }

    candidates = defaultdict(list)

    log(
        f"Reading annotations:\n"
        f"  {annotation_file}"
    )

    with open(
        annotation_file,
        "r",
        encoding="utf-8",
    ) as f:

        reader = csv.DictReader(f)

        total_rows = 0
        matched_rows = 0

        for row in reader:

            total_rows += 1

            label_id = row[
                "LabelName"
            ]

            class_name = (
                label_id_to_class.get(
                    label_id
                )
            )

            if class_name is None:
                continue

            matched_rows += 1

            ann = parse_bbox_row(
                row
            )

            candidates[
                class_name
            ].append(
                ann
            )

    log(
        f"Read {total_rows:,} "
        f"annotation rows"
    )

    log(
        f"Matched {matched_rows:,} "
        f"requested objects"
    )

    for class_name in candidates:

        random.shuffle(
            candidates[
                class_name
            ]
        )

        if max_candidates > 0:

            candidates[
                class_name
            ] = candidates[
                class_name
            ][
                :max_candidates
            ]

        log(
            f"{class_name}: "
            f"{len(candidates[class_name])} "
            f"candidate annotations"
        )

    return candidates


# ============================================================
# FILTER FOREGROUND
# ============================================================

def filter_annotations(
    candidates,
    min_size,
    allow_occluded,
    allow_truncated,
    allow_group_of,
    allow_depiction,
):
    result = defaultdict(list)

    for class_name, annotations in (
        candidates.items()
    ):

        for ann in annotations:

            if (
                not allow_occluded
                and ann["is_occluded"]
            ):
                continue

            if (
                not allow_truncated
                and ann["is_truncated"]
            ):
                continue

            if (
                not allow_group_of
                and ann["is_group_of"]
            ):
                continue

            if (
                not allow_depiction
                and ann["is_depiction"]
            ):
                continue

            width = (
                ann["xmax"]
                - ann["xmin"]
            )

            height = (
                ann["ymax"]
                - ann["ymin"]
            )

            if width <= 0:
                continue

            if height <= 0:
                continue

            if width < min_size:
                continue

            if height < min_size:
                continue

            result[
                class_name
            ].append(
                ann
            )

    return result


# ============================================================
# IMAGE URL
# ============================================================

def get_image_url(
    image_id,
    split,
):
    if split == "train":

        return (
            "https://open-images-dataset.s3."
            "amazonaws.com/train/"
            f"{image_id}.jpg"
        )

    if split == "validation":

        return (
            "https://open-images-dataset.s3."
            "amazonaws.com/validation/"
            f"{image_id}.jpg"
        )

    raise ValueError(
        f"Unsupported split: {split}"
    )


# ============================================================
# DOWNLOAD IMAGE
# ============================================================

def download_image(
    image_id,
    split,
    destination,
):
    destination = Path(
        destination
    )

    if destination.exists():
        return True

    destination.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    url = get_image_url(
        image_id,
        split,
    )

    try:

        urllib.request.urlretrieve(
            url,
            destination,
        )

        return True

    except Exception as exc:

        warning(
            f"Failed to download "
            f"{image_id}: {exc}"
        )

        if destination.exists():

            try:
                destination.unlink()
            except OSError:
                pass

        return False


# ============================================================
# IMAGE CACHE
# ============================================================

class ImageCache:

    def __init__(
        self,
        root,
    ):
        self.root = Path(
            root
        )

    def get_path(
        self,
        image_id,
        split,
    ):
        return (
            self.root
            / split
            / f"{image_id}.jpg"
        )

    def get(
        self,
        image_id,
        split,
    ):
        path = self.get_path(
            image_id,
            split,
        )

        if not path.exists():

            ok = download_image(
                image_id=image_id,
                split=split,
                destination=path,
            )

            if not ok:
                return None

        return path


# ============================================================
# BBOX CROP
# ============================================================

def crop_bbox(
    image,
    annotation,
    padding,
):
    width, height = (
        image.size
    )

    xmin = annotation[
        "xmin"
    ]

    xmax = annotation[
        "xmax"
    ]

    ymin = annotation[
        "ymin"
    ]

    ymax = annotation[
        "ymax"
    ]

    x1 = xmin * width
    x2 = xmax * width
    y1 = ymin * height
    y2 = ymax * height

    bbox_width = (
        x2 - x1
    )

    bbox_height = (
        y2 - y1
    )

    pad_x = (
        bbox_width
        * padding
    )

    pad_y = (
        bbox_height
        * padding
    )

    x1 = max(
        0,
        int(
            round(
                x1 - pad_x
            )
        ),
    )

    y1 = max(
        0,
        int(
            round(
                y1 - pad_y
            )
        ),
    )

    x2 = min(
        width,
        int(
            round(
                x2 + pad_x
            )
        ),
    )

    y2 = min(
        height,
        int(
            round(
                y2 + pad_y
            )
        ),
    )

    if x2 <= x1:
        return None

    if y2 <= y1:
        return None

    return (
        image.crop(
            (
                x1,
                y1,
                x2,
                y2,
            )
        ),
        (
            x1,
            y1,
            x2,
            y2,
        ),
    )


# ============================================================
# PROCESS FOREGROUND
# ============================================================

def process_foreground(
    output,
    annotations,
    image_cache,
    max_per_class,
    padding,
    split,
    quality,
):
    output = Path(
        output
    )

    metadata = []

    counters = defaultdict(
        int
    )

    used_images = set()

    for class_name in sorted(
        annotations.keys()
    ):

        class_annotations = (
            annotations[
                class_name
            ]
        )

        random.shuffle(
            class_annotations
        )

        class_output = (
            output
            / "foreground"
            / class_name
        )

        class_output.mkdir(
            parents=True,
            exist_ok=True,
        )

        log(
            f"Processing foreground "
            f"{class_name}: "
            f"{len(class_annotations)} "
            f"annotations"
        )

        for ann in class_annotations:

            if (
                counters[
                    class_name
                ]
                >= max_per_class
            ):
                break

            image_id = ann[
                "image_id"
            ]

            source_path = (
                image_cache.get(
                    image_id,
                    split,
                )
            )

            if source_path is None:
                continue

            used_images.add(
                source_path
            )

            try:

                image = Image.open(
                    source_path
                ).convert(
                    "RGB"
                )

            except Exception as exc:

                warning(
                    f"Could not open "
                    f"{source_path}: "
                    f"{exc}"
                )

                continue

            cropped = crop_bbox(
                image=image,
                annotation=ann,
                padding=padding,
            )

            if cropped is None:
                continue

            crop, actual_bbox = (
                cropped
            )

            index = counters[
                class_name
            ]

            object_id = (
                f"{class_name}_"
                f"{index:06d}"
            )

            output_path = (
                class_output
                / f"{object_id}.jpg"
            )

            try:

                crop.save(
                    output_path,
                    format="JPEG",
                    quality=quality,
                    subsampling=0,
                )

            except Exception as exc:

                warning(
                    f"Could not save "
                    f"{output_path}: "
                    f"{exc}"
                )

                continue

            metadata.append(
                {
                    "id": object_id,
                    "class": class_name,
                    "type": "foreground",
                    "source": "open_images",
                    "split": split,
                    "source_image": image_id,
                    "source_image_file": (
                        source_path.name
                    ),
                    "label_name": (
                        ann["label_name"]
                    ),
                    "annotation_source": (
                        ann["source"]
                    ),
                    "original_image_size": {
                        "width": image.width,
                        "height": image.height,
                    },
                    "bbox_normalized": [
                        ann["xmin"],
                        ann["ymin"],
                        ann["xmax"],
                        ann["ymax"],
                    ],
                    "bbox_pixels": [
                        int(
                            round(
                                ann["xmin"]
                                * image.width
                            )
                        ),
                        int(
                            round(
                                ann["ymin"]
                                * image.height
                            )
                        ),
                        int(
                            round(
                                ann["xmax"]
                                * image.width
                            )
                        ),
                        int(
                            round(
                                ann["ymax"]
                                * image.height
                            )
                        ),
                    ],
                    "crop_bbox_pixels": [
                        actual_bbox[0],
                        actual_bbox[1],
                        actual_bbox[2],
                        actual_bbox[3],
                    ],
                    "padding": padding,
                    "is_occluded": (
                        ann["is_occluded"]
                    ),
                    "is_truncated": (
                        ann["is_truncated"]
                    ),
                    "is_group_of": (
                        ann["is_group_of"]
                    ),
                    "is_depiction": (
                        ann["is_depiction"]
                    ),
                    "is_inside": (
                        ann["is_inside"]
                    ),
                    "output_size": {
                        "width": crop.width,
                        "height": crop.height,
                    },
                    "file": str(
                        output_path.relative_to(
                            output
                        )
                    ),
                }
            )

            counters[
                class_name
            ] += 1

            if (
                counters[
                    class_name
                ] % 25 == 0
            ):

                log(
                    f"  "
                    f"{class_name}: "
                    f"{counters[class_name]}"
                )

    return (
        metadata,
        used_images,
    )


# ============================================================
# BACKGROUND CANDIDATES
# ============================================================

def collect_background_candidates(
    annotation_file,
    label_ids,
    max_candidates,
    seed,
):
    random.seed(seed)

    label_id_to_class = {
        label_id: class_name
        for class_name, label_id
        in label_ids.items()
    }

    candidates = defaultdict(list)

    log(
        "Collecting background "
        "images..."
    )

    with open(
        annotation_file,
        "r",
        encoding="utf-8",
    ) as f:

        reader = csv.DictReader(f)

        total_rows = 0
        matched_rows = 0

        for row in reader:

            total_rows += 1

            label_id = row[
                "LabelName"
            ]

            class_name = (
                label_id_to_class.get(
                    label_id
                )
            )

            if class_name is None:
                continue

            matched_rows += 1

            image_id = row[
                "ImageID"
            ]

            candidates[
                class_name
            ].append(
                {
                    "image_id": image_id,
                    "label_name": label_id,
                    "source": row.get(
                        "Source",
                        "",
                    ),
                }
            )

    log(
        f"Read {total_rows:,} "
        f"annotation rows"
    )

    log(
        f"Matched {matched_rows:,} "
        f"background annotations"
    )

    # --------------------------------------------------------
    # Remove duplicate image IDs
    # --------------------------------------------------------

    for class_name in list(
        candidates.keys()
    ):

        unique = {}

        for item in candidates[
            class_name
        ]:

            unique[
                item["image_id"]
            ] = item

        items = list(
            unique.values()
        )

        random.shuffle(
            items
        )

        if max_candidates > 0:

            items = items[
                :max_candidates
            ]

        candidates[
            class_name
        ] = items

        log(
            f"background/{class_name}: "
            f"{len(items)} candidates"
        )

    return candidates


# ============================================================
# PROCESS BACKGROUNDS
# ============================================================

def process_backgrounds(
    output,
    candidates,
    image_cache,
    max_per_class,
    split,
    quality,
    min_width,
    min_height,
    used_background_images,
):
    output = Path(
        output
    )

    metadata = []

    counters = defaultdict(
        int
    )

    for class_name in sorted(
        candidates.keys()
    ):

        class_candidates = list(
            candidates[
                class_name
            ]
        )

        random.shuffle(
            class_candidates
        )

        class_output = (
            output
            / "background"
            / class_name
        )

        class_output.mkdir(
            parents=True,
            exist_ok=True,
        )

        log(
            f"Processing background "
            f"{class_name}: "
            f"{len(class_candidates)} "
            f"candidates"
        )

        for candidate in (
            class_candidates
        ):

            if (
                counters[
                    class_name
                ]
                >= max_per_class
            ):
                break

            image_id = candidate[
                "image_id"
            ]

            # ------------------------------------------------
            # Do not reuse the same source photo for another
            # background category.
            # ------------------------------------------------

            if image_id in (
                used_background_images
            ):
                continue

            source_path = (
                image_cache.get(
                    image_id,
                    split,
                )
            )

            if source_path is None:
                continue

            try:

                image = Image.open(
                    source_path
                ).convert(
                    "RGB"
                )

            except Exception as exc:

                warning(
                    f"Could not open "
                    f"{source_path}: "
                    f"{exc}"
                )

                continue

            # ------------------------------------------------
            # Reject very small source images.
            # ------------------------------------------------

            if (
                image.width
                < min_width
            ):
                continue

            if (
                image.height
                < min_height
            ):
                continue

            index = counters[
                class_name
            ]

            background_id = (
                f"{class_name}_"
                f"{index:06d}"
            )

            output_path = (
                class_output
                / f"{background_id}.jpg"
            )

            try:

                image.save(
                    output_path,
                    format="JPEG",
                    quality=quality,
                    subsampling=0,
                )

            except Exception as exc:

                warning(
                    f"Could not save "
                    f"{output_path}: "
                    f"{exc}"
                )

                continue

            used_background_images.add(
                image_id
            )

            metadata.append(
                {
                    "id": background_id,
                    "class": class_name,
                    "type": "background",
                    "source": "open_images",
                    "split": split,
                    "source_image": image_id,
                    "source_image_file": (
                        source_path.name
                    ),
                    "label_name": (
                        candidate[
                            "label_name"
                        ]
                    ),
                    "annotation_source": (
                        candidate[
                            "source"
                        ]
                    ),
                    "original_image_size": {
                        "width": image.width,
                        "height": image.height,
                    },
                    "output_size": {
                        "width": image.width,
                        "height": image.height,
                    },
                    "file": str(
                        output_path.relative_to(
                            output
                        )
                    ),
                }
            )

            counters[
                class_name
            ] += 1

            if (
                counters[
                    class_name
                ] % 25 == 0
            ):

                log(
                    f"  background/"
                    f"{class_name}: "
                    f"{counters[class_name]}"
                )

    return metadata


# ============================================================
# ARGUMENTS
# ============================================================

def parse_args():

    parser = argparse.ArgumentParser(
        description=(
            "Prepare foreground objects "
            "and full-image backgrounds "
            "from Open Images."
        )
    )

    # --------------------------------------------------------
    # General
    # --------------------------------------------------------

    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            "./scene_dataset"
        ),
    )

    parser.add_argument(
        "--objects",
        nargs="+",
        default=DEFAULT_OBJECTS,
    )

    parser.add_argument(
        "--backgrounds",
        nargs="+",
        default=DEFAULT_BACKGROUNDS,
        help=(
            "Open Images classes used "
            "as full-image backgrounds."
        ),
    )

    # --------------------------------------------------------
    # Foreground
    # --------------------------------------------------------

    parser.add_argument(
        "--max-per-class",
        type=int,
        default=200,
        help=(
            "Maximum number of "
            "foreground objects per class."
        ),
    )

    parser.add_argument(
        "--padding",
        type=float,
        default=0.15,
        help=(
            "Padding around foreground "
            "bbox as fraction of bbox "
            "width/height."
        ),
    )

    parser.add_argument(
        "--min-size",
        type=float,
        default=0.05,
        help=(
            "Minimum foreground bbox "
            "width and height as fraction "
            "of original image."
        ),
    )

    # --------------------------------------------------------
    # Background
    # --------------------------------------------------------

    parser.add_argument(
        "--backgrounds-per-class",
        type=int,
        default=100,
        help=(
            "Maximum number of full "
            "background images per class."
        ),
    )

    parser.add_argument(
        "--background-max-candidates",
        type=int,
        default=5000,
        help=(
            "Maximum background candidates "
            "loaded per class."
        ),
    )

    parser.add_argument(
        "--background-min-width",
        type=int,
        default=640,
        help=(
            "Minimum source background "
            "width in pixels."
        ),
    )

    parser.add_argument(
        "--background-min-height",
        type=int,
        default=480,
        help=(
            "Minimum source background "
            "height in pixels."
        ),
    )

    parser.add_argument(
        "--no-backgrounds",
        action="store_true",
        help=(
            "Prepare foreground only."
        ),
    )

    # --------------------------------------------------------
    # Dataset
    # --------------------------------------------------------

    parser.add_argument(
        "--max-candidates",
        type=int,
        default=10000,
        help=(
            "Maximum foreground annotation "
            "candidates loaded per class."
        ),
    )

    parser.add_argument(
        "--split",
        choices=[
            "train",
            "validation",
        ],
        default="train",
    )

    parser.add_argument(
        "--annotations",
        type=Path,
        default=None,
        help=(
            "Path to local Open Images "
            "bbox CSV."
        ),
    )

    parser.add_argument(
        "--class-descriptions",
        type=Path,
        default=None,
        help=(
            "Path to local "
            "class-descriptions.csv."
        ),
    )

    # --------------------------------------------------------
    # Filtering
    # --------------------------------------------------------

    parser.add_argument(
        "--allow-occluded",
        action="store_true",
    )

    parser.add_argument(
        "--allow-truncated",
        action="store_true",
    )

    parser.add_argument(
        "--allow-group-of",
        action="store_true",
    )

    parser.add_argument(
        "--allow-depiction",
        action="store_true",
    )

    # --------------------------------------------------------
    # Storage
    # --------------------------------------------------------

    parser.add_argument(
        "--keep-source-images",
        action="store_true",
        help=(
            "Keep downloaded Open Images "
            "source photographs."
        ),
    )

    parser.add_argument(
        "--quality",
        type=int,
        default=95,
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=42,
    )

    return parser.parse_args()


# ============================================================
# MAIN
# ============================================================

def main():

    args = parse_args()

    random.seed(
        args.seed
    )

    # ========================================================
    # Validation
    # ========================================================

    if (
        args.max_per_class
        <= 0
    ):
        raise ValueError(
            "--max-per-class "
            "must be > 0"
        )

    if (
        args.backgrounds_per_class
        <= 0
    ):
        raise ValueError(
            "--backgrounds-per-class "
            "must be > 0"
        )

    if args.padding < 0:
        raise ValueError(
            "--padding must be >= 0"
        )

    if not (
        0 < args.min_size <= 1
    ):
        raise ValueError(
            "--min-size must be "
            "between 0 and 1"
        )

    if (
        args.background_min_width
        <= 0
    ):
        raise ValueError(
            "--background-min-width "
            "must be > 0"
        )

    if (
        args.background_min_height
        <= 0
    ):
        raise ValueError(
            "--background-min-height "
            "must be > 0"
        )

    if not (
        1 <= args.quality <= 100
    ):
        raise ValueError(
            "--quality must be "
            "between 1 and 100"
        )

    # ========================================================
    # Paths
    # ========================================================

    root = Path(
        args.output
    )

    root.mkdir(
        parents=True,
        exist_ok=True,
    )

    cache_root = (
        root
        / "open_images_cache"
    )

    metadata_root = (
        root
        / "metadata"
    )

    metadata_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ========================================================
    # Class descriptions
    # ========================================================

    if args.class_descriptions:

        class_descriptions_path = (
            args.class_descriptions
        )

    else:

        class_descriptions_path = (
            cache_root
            / "oidv6-class-descriptions.csv"
        )

        if not (
            class_descriptions_path.exists()
        ):

            download_file(
                CLASS_DESCRIPTIONS_URL,
                class_descriptions_path,
            )

    log(
        "Loading Open Images "
        "class descriptions..."
    )

    class_descriptions = (
        load_class_descriptions(
            class_descriptions_path
        )
    )

    # ========================================================
    # Find foreground classes
    # ========================================================

    foreground_label_ids = (
        find_label_ids(
            class_descriptions,
            args.objects,
        )
    )

    log(
        "Foreground classes:"
    )

    for class_name in args.objects:

        label_id = (
            foreground_label_ids.get(
                class_name
            )
        )

        if label_id:

            log(
                f"  {class_name}: "
                f"{label_id}"
            )

        else:

            warning(
                f"Could not find "
                f"Open Images class "
                f"'{class_name}'"
            )

    if not foreground_label_ids:

        raise RuntimeError(
            "None of the requested "
            "foreground classes "
            "were found."
        )

    # ========================================================
    # Find background classes
    # ========================================================

    background_label_ids = {}

    if not args.no_backgrounds:

        background_label_ids = (
            find_label_ids(
                class_descriptions,
                args.backgrounds,
            )
        )

        log(
            "Background classes:"
        )

        for class_name in (
            args.backgrounds
        ):

            label_id = (
                background_label_ids.get(
                    class_name
                )
            )

            if label_id:

                log(
                    f"  {class_name}: "
                    f"{label_id}"
                )

            else:

                warning(
                    f"Could not find "
                    f"Open Images background "
                    f"class '{class_name}'"
                )

    # ========================================================
    # Annotation file
    # ========================================================

    if args.annotations:

        annotation_path = (
            args.annotations
        )

    else:

        if args.split == "train":

            annotation_url = (
                TRAIN_BBOXES_URL
            )

            annotation_filename = (
                "oidv6-train-"
                "annotations-bbox.csv"
            )

        else:

            annotation_url = (
                VALIDATION_BBOXES_URL
            )

            annotation_filename = (
                "validation-"
                "annotations-bbox.csv"
            )

        annotation_path = (
            cache_root
            / annotation_filename
        )

        if not annotation_path.exists():

            download_file(
                annotation_url,
                annotation_path,
            )

    # ========================================================
    # Foreground candidates
    # ========================================================

    foreground_candidates = (
        collect_annotations(
            annotation_file=(
                annotation_path
            ),
            label_ids=(
                foreground_label_ids
            ),
            max_candidates=(
                args.max_candidates
            ),
            seed=args.seed,
        )
    )

    # ========================================================
    # Foreground filtering
    # ========================================================

    foreground_annotations = (
        filter_annotations(
            candidates=(
                foreground_candidates
            ),
            min_size=args.min_size,
            allow_occluded=(
                args.allow_occluded
            ),
            allow_truncated=(
                args.allow_truncated
            ),
            allow_group_of=(
                args.allow_group_of
            ),
            allow_depiction=(
                args.allow_depiction
            ),
        )
    )

    log(
        "Foreground after filtering:"
    )

    for class_name in args.objects:

        log(
            f"  {class_name}: "
            f"{len(
                foreground_annotations.get(
                    class_name,
                    [],
                )
            )}"
        )

    # ========================================================
    # Image cache
    # ========================================================

    image_cache = ImageCache(
        cache_root
        / "images"
    )

    # ========================================================
    # Process foreground
    # ========================================================

    log(
        "========================================"
    )

    log(
        "PROCESSING FOREGROUND"
    )

    log(
        "========================================"
    )

    foreground_metadata, used_images = (
        process_foreground(
            output=root,
            annotations=(
                foreground_annotations
            ),
            image_cache=image_cache,
            max_per_class=(
                args.max_per_class
            ),
            padding=args.padding,
            split=args.split,
            quality=args.quality,
        )
    )

    # ========================================================
    # Process backgrounds
    # ========================================================

    background_metadata = []

    used_background_images = set()

    if (
        not args.no_backgrounds
        and background_label_ids
    ):

        background_candidates = (
            collect_background_candidates(
                annotation_file=(
                    annotation_path
                ),
                label_ids=(
                    background_label_ids
                ),
                max_candidates=(
                    args.background_max_candidates
                ),
                seed=args.seed + 1,
            )
        )

        log(
            "========================================"
        )

        log(
            "PROCESSING BACKGROUNDS"
        )

        log(
            "========================================"
        )

        background_metadata = (
            process_backgrounds(
                output=root,
                candidates=(
                    background_candidates
                ),
                image_cache=image_cache,
                max_per_class=(
                    args.backgrounds_per_class
                ),
                split=args.split,
                quality=args.quality,
                min_width=(
                    args.background_min_width
                ),
                min_height=(
                    args.background_min_height
                ),
                used_background_images=(
                    used_background_images
                ),
            )
        )

    # ========================================================
    # Save metadata
    # ========================================================

    foreground_metadata_path = (
        metadata_root
        / "foreground.json"
    )

    background_metadata_path = (
        metadata_root
        / "background.json"
    )

    save_json(
        foreground_metadata_path,
        foreground_metadata,
    )

    save_json(
        background_metadata_path,
        background_metadata,
    )

    # ========================================================
    # Summary
    # ========================================================

    foreground_counts = {
        class_name: sum(
            1
            for item
            in foreground_metadata
            if item["class"]
            == class_name
        )
        for class_name
        in args.objects
    }

    background_counts = {
        class_name: sum(
            1
            for item
            in background_metadata
            if item["class"]
            == class_name
        )
        for class_name
        in args.backgrounds
    }

    summary = {
        "source": "open_images",
        "split": args.split,

        "foreground": {
            "objects": foreground_counts,
            "total": len(
                foreground_metadata
            ),
            "padding": args.padding,
            "min_size": args.min_size,
        },

        "background": {
            "classes": background_counts,
            "total": len(
                background_metadata
            ),
            "full_images": True,
            "min_width": (
                args.background_min_width
            ),
            "min_height": (
                args.background_min_height
            ),
        },

        "seed": args.seed,
    }

    save_json(
        metadata_root
        / "summary.json",
        summary,
    )

    # ========================================================
    # Cleanup
    # ========================================================

    if not args.keep_source_images:

        source_images_root = (
            cache_root
            / "images"
        )

        if source_images_root.exists():

            log(
                "Removing downloaded "
                "Open Images source "
                "photographs..."
            )

            shutil.rmtree(
                source_images_root
            )

    # ========================================================
    # Report
    # ========================================================

    print()

    print(
        "=" * 60
    )

    print(
        "OPEN IMAGES DATASET "
        "PREPARATION FINISHED"
    )

    print(
        "=" * 60
    )

    print()

    print(
        "FOREGROUND:"
    )

    for class_name, count in (
        foreground_counts.items()
    ):

        print(
            f"  {class_name:15s} "
            f"{count}"
        )

    print(
        f"  {'TOTAL':15s} "
        f"{len(foreground_metadata)}"
    )

    print()

    print(
        "BACKGROUND:"
    )

    for class_name, count in (
        background_counts.items()
    ):

        print(
            f"  {class_name:15s} "
            f"{count}"
        )

    print(
        f"  {'TOTAL':15s} "
        f"{len(background_metadata)}"
    )

    print()

    print(
        f"Foreground: "
        f"{root / 'foreground'}"
    )

    print(
        f"Background: "
        f"{root / 'background'}"
    )

    print(
        f"Metadata: "
        f"{metadata_root}"
    )

    print()

    print(
        "=" * 60
    )


if __name__ == "__main__":
    main()

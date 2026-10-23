import argparse
import ast
import json
import pickle
from pathlib import Path

import numpy as np
import requests


# ============================================================
# CONSTANTS
# ============================================================

DEFAULT_ANNOTATIONS = "./voc_subset/annotations.json"
DEFAULT_OUTPUT = "./voc_similarity"
DEFAULT_MODEL = "EVA02-B-16__merged2b_s8b_b131k"
DEFAULT_API_URL = "http://localhost:3003/predict"
DEFAULT_SCALE = 100.0
DEFAULT_THRESHOLD = 0.5
NUM_SEGMENTS = 9
NUM_IMAGE_EMBEDDINGS = 2 + NUM_SEGMENTS * 2


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
# NUMPY / EMBEDDINGS
# ============================================================

def parse_embedding(x):
    """
    Convert API response to numpy float32 array.
    """

    if isinstance(x, str):
        x = ast.literal_eval(x)

    return np.asarray(
        x,
        dtype=np.float32,
    )


def normalize_embedding(x):
    """
    L2-normalize embedding(s).
    """

    x = np.asarray(
        x,
        dtype=np.float32,
    )

    if x.ndim == 1:
        norm = np.linalg.norm(x)

        if norm == 0:
            raise ValueError(
                "Zero-norm embedding."
            )

        return x / norm

    if x.ndim == 2:
        norms = np.linalg.norm(
            x,
            axis=-1,
            keepdims=True,
        )

        if np.any(norms == 0):
            raise ValueError(
                "Zero-norm embedding found."
            )

        return x / norms

    raise ValueError(
        f"Unsupported embedding shape: "
        f"{x.shape}"
    )


def softmax(x):
    """
    Numerically stable softmax.
    """

    x = np.asarray(
        x,
        dtype=np.float32,
    )

    x = (
        x
        - np.max(
            x,
            axis=-1,
            keepdims=True,
        )
    )

    e = np.exp(x)

    return (
        e
        / np.sum(
            e,
            axis=-1,
            keepdims=True,
        )
    )


# ============================================================
# API CLIENT
# ============================================================

class ImmichCLIPClient:

    def __init__(
        self,
        api_url,
        model_name,
        timeout,
    ):
        self.api_url = api_url
        self.model_name = model_name
        self.timeout = timeout

    # --------------------------------------------------------
    # Text
    # --------------------------------------------------------

    def get_text_embedding(
        self,
        text,
    ):
        response = requests.post(
            self.api_url,
            data={
                "entries": json.dumps(
                    {
                        "clip": {
                            "textual": {
                                "modelName": (
                                    self.model_name
                                )
                            }
                        }
                    }
                ),
                "text": text,
            },
            timeout=self.timeout,
        )

        if response.status_code != 200:
            raise RuntimeError(
                "Text embedding request failed:\n"
                f"{response.text}"
            )

        data = response.json()

        embedding = parse_embedding(
            data["clip"]
        )

        return normalize_embedding(
            embedding
        )

    # --------------------------------------------------------
    # Image
    # --------------------------------------------------------

    def get_image_embedding(
        self,
        image_path,
    ):
        image_path = Path(
            image_path
        )

        with open(
            image_path,
            "rb",
        ) as f:
            response = requests.post(
                self.api_url,
                data={
                    "entries": json.dumps(
                        {
                            "clip": {
                                "visual": {
                                    "modelName": (
                                        self.model_name
                                    )
                                }
                            }
                        }
                    ),
                },
                files={
                    "image": f
                },
                timeout=self.timeout,
            )

        if response.status_code != 200:
            raise RuntimeError(
                "Image embedding request failed:\n"
                f"{response.text}"
            )

        data = response.json()

        embedding = parse_embedding(
            data["clip"]
        )

        return normalize_embedding(
            embedding
        )


# ============================================================
# ANNOTATIONS
# ============================================================

def load_annotations(
    annotations_path,
):
    annotations_path = Path(
        annotations_path
    )

    if not annotations_path.exists():
        raise RuntimeError(
            f"Annotations file does not exist: "
            f"{annotations_path}"
        )

    with annotations_path.open(
        "r",
        encoding="utf-8",
    ) as f:
        data = json.load(f)

    if "images" not in data:
        raise RuntimeError(
            "Invalid annotations file: "
            "'images' field is missing."
        )

    return data


def collect_classes(
    annotations,
):
    classes = set()

    for image in annotations["images"]:
        for class_name in image.get(
            "classes",
            [],
        ):
            classes.add(
                class_name
            )

    return sorted(classes)


# ============================================================
# TEXT EMBEDDINGS
# ============================================================

def build_text_embeddings(
    client,
    classes,
):
    embeddings = {}

    log(
        "========================================"
    )

    log(
        "TEXT EMBEDDINGS"
    )

    log(
        "========================================"
    )

    for index, class_name in enumerate(
        classes,
        start=1,
    ):

        log(
            f"[{index}/{len(classes)}] "
            f"Text: '{class_name}'"
        )

        embedding = (
            client.get_text_embedding(
                class_name
            )
        )

        embeddings[
            class_name
        ] = embedding.astype(
            np.float32
        )

        log(
            f"  shape={embedding.shape}"
        )

    return embeddings


# ============================================================
# IMAGE PATH
# ============================================================

def find_image_path(
    annotations_path,
    image_file,
):
    annotations_path = Path(
        annotations_path
    )

    base_dir = (
        annotations_path.parent
    )

    candidates = [
        base_dir / image_file,
        base_dir / "images" / image_file,
    ]

    for path in candidates:
        if path.exists():
            return path

    filename = Path(
        image_file
    ).name

    matches = list(
        base_dir.rglob(filename)
    )

    if matches:
        return matches[0]

    raise FileNotFoundError(
        f"Could not find image "
        f"'{image_file}' relative to "
        f"{base_dir}"
    )


# ============================================================
# SIMILARITY FOR ONE IMAGE
# ============================================================

def calculate_image_similarities(
    image_embedding,
    classes,
    text_embeddings,
    scale,
    threshold,
):
    """
    Embedding order:

        0       original
        1       squared
        2-10    segmented_original
        11-19   segmented_squared
    """

    image_embedding = normalize_embedding(
        image_embedding
    )

    if image_embedding.shape[0] < NUM_IMAGE_EMBEDDINGS:
        raise ValueError(
            f"Unexpected number of image embeddings: "
            f"got {image_embedding.shape[0]}, "
            f"expected at least {NUM_IMAGE_EMBEDDINGS}."
        )

    if image_embedding.shape[0] > NUM_IMAGE_EMBEDDINGS:
        warning(
            f"API returned "
            f"{image_embedding.shape[0]} image embeddings; "
            f"using first {NUM_IMAGE_EMBEDDINGS}."
        )

        image_embedding = (
            image_embedding[
                :NUM_IMAGE_EMBEDDINGS
            ]
        )

    text_matrix = np.stack(
        [
            text_embeddings[
                class_name
            ]
            for class_name in classes
        ],
        axis=0,
    )

    text_matrix = normalize_embedding(
        text_matrix
    )

    # --------------------------------------------------------
    # Cosine similarity
    # --------------------------------------------------------

    cosine = (
        image_embedding
        @ text_matrix.T
    )

    # --------------------------------------------------------
    # Modified similarity
    # --------------------------------------------------------

    logits = (
        scale * cosine
    )

    modified = softmax(
        logits
    )

    # --------------------------------------------------------
    # Embedding groups
    # --------------------------------------------------------

    original_index = 0
    squared_index = 1

    original_segments = slice(
        2,
        2 + NUM_SEGMENTS,
    )

    squared_segments = slice(
        2 + NUM_SEGMENTS,
        NUM_IMAGE_EMBEDDINGS,
    )

    # --------------------------------------------------------
    # Per-class results
    # --------------------------------------------------------

    class_results = {}

    for class_index, class_name in enumerate(
        classes
    ):

        class_cosines = (
            cosine[
                :,
                class_index
            ]
        )

        class_modified = (
            modified[
                :,
                class_index
            ]
        )

        best_cosine_index = int(
            np.argmax(
                class_cosines
            )
        )

        best_modified_index = int(
            np.argmax(
                class_modified
            )
        )

        max_cosine = float(
            class_cosines[
                best_cosine_index
            ]
        )

        max_modified = float(
            class_modified[
                best_modified_index
            ]
        )

        original_cosine = float(
            class_cosines[
                original_index
            ]
        )

        original_modified = float(
            class_modified[
                original_index
            ]
        )

        squared_modified = float(
            class_modified[
                squared_index
            ]
        )

        segmented_original_modified = (
            class_modified[
                original_segments
            ]
        )

        segmented_squared_modified = (
            class_modified[
                squared_segments
            ]
        )

        original = (
            original_modified
            >= threshold
        )

        squared = (
            squared_modified
            >= threshold
        )

        segmented_original = bool(
            np.any(
                segmented_original_modified
                >= threshold
            )
        )

        segmented_squared = bool(
            np.any(
                segmented_squared_modified
                >= threshold
            )
        )

        found = (
            max_modified
            >= threshold
        )

        better = (
            not original
            and found
        )

        class_results[
            class_name
        ] = {
            "cosine": (
                class_cosines
                .astype(
                    np.float32
                )
                .tolist()
            ),

            "modified_similarity": (
                class_modified
                .astype(
                    np.float32
                )
                .tolist()
            ),

            "original_cosine": (
                original_cosine
            ),

            "original_modified_similarity": (
                original_modified
            ),

            "max_cosine": max_cosine,

            "max_modified_similarity": (
                max_modified
            ),

            "best_embedding_by_cosine": (
                best_cosine_index
            ),

            "best_embedding_by_modified_similarity": (
                best_modified_index
            ),

            "original": original,

            "squared": squared,

            "segmented_original": (
                segmented_original
            ),

            "segmented_squared": (
                segmented_squared
            ),

            "found": found,

            "better": better,
        }

    return class_results


# ============================================================
# STATISTICS ACCUMULATOR
# ============================================================

def create_statistics_accumulator():
    return {
        "images": 0,
        "annotated_objects": 0,

        "original_objects": 0,
        "squared_objects": 0,
        "segmented_original_objects": 0,
        "segmented_squared_objects": 0,

        "found_objects": 0,
        "better_objects": 0,

        "all_cosines": [],
        "all_modified": [],

        "found_cosines": [],
        "found_modified": [],

        "missed_cosines": [],
        "missed_modified": [],

        "per_class": {},
    }


def update_statistics(
    accumulator,
    class_results,
):
    accumulator["images"] += 1

    for class_name, values in (
        class_results.items()
    ):

        accumulator[
            "annotated_objects"
        ] += 1

        max_cosine = values[
            "max_cosine"
        ]

        max_modified = values[
            "max_modified_similarity"
        ]

        original = values[
            "original"
        ]

        squared = values[
            "squared"
        ]

        segmented_original = values[
            "segmented_original"
        ]

        segmented_squared = values[
            "segmented_squared"
        ]

        found = values[
            "found"
        ]

        better = values[
            "better"
        ]

        accumulator[
            "all_cosines"
        ].append(
            max_cosine
        )

        accumulator[
            "all_modified"
        ].append(
            max_modified
        )

        if original:
            accumulator[
                "original_objects"
            ] += 1

        if squared:
            accumulator[
                "squared_objects"
            ] += 1

        if segmented_original:
            accumulator[
                "segmented_original_objects"
            ] += 1

        if segmented_squared:
            accumulator[
                "segmented_squared_objects"
            ] += 1

        if found:
            accumulator[
                "found_objects"
            ] += 1

            accumulator[
                "found_cosines"
            ].append(
                max_cosine
            )

            accumulator[
                "found_modified"
            ].append(
                max_modified
            )

        else:
            accumulator[
                "missed_cosines"
            ].append(
                max_cosine
            )

            accumulator[
                "missed_modified"
            ].append(
                max_modified
            )

        if better:
            accumulator[
                "better_objects"
            ] += 1

        if class_name not in accumulator[
            "per_class"
        ]:
            accumulator[
                "per_class"
            ][
                class_name
            ] = {
                "total": 0,
                "original": 0,
                "squared": 0,
                "segmented_original": 0,
                "segmented_squared": 0,
                "found": 0,
                "missed": 0,
                "better": 0,
                "cosines": [],
                "modified_similarities": [],
            }

        stats = accumulator[
            "per_class"
        ][
            class_name
        ]

        stats["total"] += 1

        if original:
            stats["original"] += 1

        if squared:
            stats["squared"] += 1

        if segmented_original:
            stats["segmented_original"] += 1

        if segmented_squared:
            stats["segmented_squared"] += 1

        if found:
            stats["found"] += 1
        else:
            stats["missed"] += 1

        if better:
            stats["better"] += 1

        stats[
            "cosines"
        ].append(
            max_cosine
        )

        stats[
            "modified_similarities"
        ].append(
            max_modified
        )


# ============================================================
# STATISTICS
# ============================================================

def calculate_statistics(
    accumulator,
    threshold,
):
    total_images = accumulator[
        "images"
    ]

    total_objects = accumulator[
        "annotated_objects"
    ]

    original_objects = accumulator[
        "original_objects"
    ]

    squared_objects = accumulator[
        "squared_objects"
    ]

    segmented_original_objects = (
        accumulator[
            "segmented_original_objects"
        ]
    )

    segmented_squared_objects = (
        accumulator[
            "segmented_squared_objects"
        ]
    )

    found_objects = accumulator[
        "found_objects"
    ]

    better_objects = accumulator[
        "better_objects"
    ]

    all_cosines = accumulator[
        "all_cosines"
    ]

    all_modified = accumulator[
        "all_modified"
    ]

    found_cosines = accumulator[
        "found_cosines"
    ]

    found_modified = accumulator[
        "found_modified"
    ]

    missed_cosines = accumulator[
        "missed_cosines"
    ]

    missed_modified = accumulator[
        "missed_modified"
    ]

    per_class_result = {}

    def numeric_stats(values):
        if not values:
            return {
                "mean": None,
                "median": None,
                "min": None,
                "max": None,
            }

        return {
            "mean": float(
                np.mean(values)
            ),
            "median": float(
                np.median(values)
            ),
            "min": float(
                np.min(values)
            ),
            "max": float(
                np.max(values)
            ),
        }

    for class_name, stats in sorted(
        accumulator["per_class"].items()
    ):

        total = stats[
            "total"
        ]

        original = stats[
            "original"
        ]

        squared = stats[
            "squared"
        ]

        segmented_original = stats[
            "segmented_original"
        ]

        segmented_squared = stats[
            "segmented_squared"
        ]

        found = stats[
            "found"
        ]

        better = stats[
            "better"
        ]

        original_rate = (
            original / total
            if total
            else 0.0
        )

        squared_rate = (
            squared / total
            if total
            else 0.0
        )

        segmented_original_rate = (
            segmented_original / total
            if total
            else 0.0
        )

        segmented_squared_rate = (
            segmented_squared / total
            if total
            else 0.0
        )

        recall = (
            found / total
            if total
            else 0.0
        )

        better_rate = (
            better / total
            if total
            else 0.0
        )

        per_class_result[
            class_name
        ] = {
            "total": total,

            "original": original,

            "original_rate": original_rate,

            "squared": squared,

            "squared_rate": squared_rate,

            "segmented_original": (
                segmented_original
            ),

            "segmented_original_rate": (
                segmented_original_rate
            ),

            "segmented_squared": (
                segmented_squared
            ),

            "segmented_squared_rate": (
                segmented_squared_rate
            ),

            "found": found,

            "missed": (
                stats["missed"]
            ),

            "better": better,

            "recall": recall,

            "better_rate": better_rate,

            "cosine": numeric_stats(
                stats["cosines"]
            ),

            "modified_similarity": (
                numeric_stats(
                    stats[
                        "modified_similarities"
                    ]
                )
            ),
        }

    original_rate = (
        original_objects / total_objects
        if total_objects
        else 0.0
    )

    squared_rate = (
        squared_objects / total_objects
        if total_objects
        else 0.0
    )

    segmented_original_rate = (
        segmented_original_objects
        / total_objects
        if total_objects
        else 0.0
    )

    segmented_squared_rate = (
        segmented_squared_objects
        / total_objects
        if total_objects
        else 0.0
    )

    recall = (
        found_objects / total_objects
        if total_objects
        else 0.0
    )

    better_rate = (
        better_objects / total_objects
        if total_objects
        else 0.0
    )

    return {
        "threshold": threshold,

        "images": total_images,

        "annotated_objects": (
            total_objects
        ),

        "original_objects": (
            original_objects
        ),

        "original_rate": (
            original_rate
        ),

        "squared_objects": (
            squared_objects
        ),

        "squared_rate": (
            squared_rate
        ),

        "segmented_original_objects": (
            segmented_original_objects
        ),

        "segmented_original_rate": (
            segmented_original_rate
        ),

        "segmented_squared_objects": (
            segmented_squared_objects
        ),

        "segmented_squared_rate": (
            segmented_squared_rate
        ),

        "found_objects": (
            found_objects
        ),

        "missed_objects": (
            total_objects
            - found_objects
        ),

        "better_objects": (
            better_objects
        ),

        "recall": recall,

        "better_rate": better_rate,

        "all": {
            "cosine": numeric_stats(
                all_cosines
            ),

            "modified_similarity": (
                numeric_stats(
                    all_modified
                )
            ),
        },

        "found": {
            "cosine": numeric_stats(
                found_cosines
            ),

            "modified_similarity": (
                numeric_stats(
                    found_modified
                )
            ),
        },

        "missed": {
            "cosine": numeric_stats(
                missed_cosines
            ),

            "modified_similarity": (
                numeric_stats(
                    missed_modified
                )
            ),
        },

        "per_class": per_class_result,
    }


# ============================================================
# PROCESS ONE IMAGE
# ============================================================

def process_image(
    client,
    image_info,
    annotations_path,
    text_embeddings,
    scale,
    threshold,
):
    image_file = image_info[
        "file"
    ]

    image_path = find_image_path(
        annotations_path,
        image_file,
    )

    classes = image_info.get(
        "classes",
        [],
    )

    if not classes:
        warning(
            f"No classes in annotation "
            f"for {image_file}"
        )

        return None

    missing_classes = [
        class_name
        for class_name in classes
        if class_name
        not in text_embeddings
    ]

    if missing_classes:
        raise RuntimeError(
            f"Missing text embeddings "
            f"for {image_file}: "
            f"{missing_classes}"
        )

    image_embedding = (
        client.get_image_embedding(
            image_path
        )
    )

    log(
        f"  image embeddings: "
        f"{image_embedding.shape[0]}"
    )

    log(
        f"  classes: "
        f"{', '.join(classes)}"
    )

    class_results = (
        calculate_image_similarities(
            image_embedding=image_embedding,
            classes=classes,
            text_embeddings=text_embeddings,
            scale=scale,
            threshold=threshold,
        )
    )

    found_classes = [
        class_name
        for class_name, values
        in class_results.items()
        if values["found"]
    ]

    original_classes = [
        class_name
        for class_name, values
        in class_results.items()
        if values["original"]
    ]

    squared_classes = [
        class_name
        for class_name, values
        in class_results.items()
        if values["squared"]
    ]

    segmented_original_classes = [
        class_name
        for class_name, values
        in class_results.items()
        if values["segmented_original"]
    ]

    segmented_squared_classes = [
        class_name
        for class_name, values
        in class_results.items()
        if values["segmented_squared"]
    ]

    better_classes = [
        class_name
        for class_name, values
        in class_results.items()
        if values["better"]
    ]

    for class_name, values in (
        class_results.items()
    ):
        log(
            f"  {class_name}: "
            f"original="
            f"{values['original_modified_similarity']:.6f}, "
            f"max="
            f"{values['max_modified_similarity']:.6f}, "
            f"original="
            f"{values['original']}, "
            f"squared="
            f"{values['squared']}, "
            f"segmented_original="
            f"{values['segmented_original']}, "
            f"segmented_squared="
            f"{values['segmented_squared']}, "
            f"found="
            f"{values['found']}, "
            f"better="
            f"{values['better']}"
        )

    return {
        "file": image_file,

        "source": image_info.get(
            "source"
        ),

        "annotated_classes": classes,

        "annotated_class_counts": (
            image_info.get(
                "class_counts",
                {}
            )
        ),

        "num_image_embeddings": (
            int(
                min(
                    image_embedding.shape[0],
                    NUM_IMAGE_EMBEDDINGS,
                )
            )
        ),

        "classes": class_results,

        "original_classes": (
            original_classes
        ),

        "squared_classes": (
            squared_classes
        ),

        "segmented_original_classes": (
            segmented_original_classes
        ),

        "segmented_squared_classes": (
            segmented_squared_classes
        ),

        "found_classes": (
            found_classes
        ),

        "better_classes": (
            better_classes
        ),
    }


# ============================================================
# PICKLE
# ============================================================

def save_pickle(
    path,
    data,
):
    path = Path(
        path
    )

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with path.open(
        "wb"
    ) as f:
        pickle.dump(
            data,
            f,
            protocol=pickle.HIGHEST_PROTOCOL,
        )


# ============================================================
# JSON
# ============================================================

def make_json_serializable(
    data,
):
    if isinstance(
        data,
        np.ndarray,
    ):
        return data.tolist()

    if isinstance(
        data,
        np.floating,
    ):
        return float(data)

    if isinstance(
        data,
        np.integer,
    ):
        return int(data)

    if isinstance(
        data,
        dict,
    ):
        return {
            key: make_json_serializable(
                value
            )
            for key, value in data.items()
        }

    if isinstance(
        data,
        list,
    ):
        return [
            make_json_serializable(
                value
            )
            for value in data
        ]

    return data


# ============================================================
# PRINT STATISTICS
# ============================================================

def print_statistics(
    statistics,
):
    print()

    print(
        "=" * 70
    )

    print(
        "FINAL STATISTICS"
    )

    print(
        "=" * 70
    )

    print(
        f"Images:                       "
        f"{statistics['images']}"
    )

    print(
        f"Annotated objects:            "
        f"{statistics['annotated_objects']}"
    )

    print()

    print(
        "ORIGINAL"
    )

    print(
        f"  Objects:                    "
        f"{statistics['original_objects']}"
    )

    print(
        f"  Rate:                       "
        f"{statistics['original_rate']:.4f} "
        f"({statistics['original_rate'] * 100:.2f}%)"
    )

    print()

    print(
        "SQUARED"
    )

    print(
        f"  Objects:                    "
        f"{statistics['squared_objects']}"
    )

    print(
        f"  Rate:                       "
        f"{statistics['squared_rate']:.4f} "
        f"({statistics['squared_rate'] * 100:.2f}%)"
    )

    print()

    print(
        "SEGMENTED ORIGINAL"
    )

    print(
        f"  Objects:                    "
        f"{statistics['segmented_original_objects']}"
    )

    print(
        f"  Rate:                       "
        f"{statistics['segmented_original_rate']:.4f} "
        f"({statistics['segmented_original_rate'] * 100:.2f}%)"
    )

    print()

    print(
        "SEGMENTED SQUARED"
    )

    print(
        f"  Objects:                    "
        f"{statistics['segmented_squared_objects']}"
    )

    print(
        f"  Rate:                       "
        f"{statistics['segmented_squared_rate']:.4f} "
        f"({statistics['segmented_squared_rate'] * 100:.2f}%)"
    )

    print()

    print(
        "FOUND"
    )

    print(
        f"  Objects:                    "
        f"{statistics['found_objects']}"
    )

    print(
        f"  Missed:                     "
        f"{statistics['missed_objects']}"
    )

    print(
        f"  Recall:                     "
        f"{statistics['recall']:.4f} "
        f"({statistics['recall'] * 100:.2f}%)"
    )

    print()

    print(
        "BETTER"
    )

    print(
        f"  Objects:                    "
        f"{statistics['better_objects']}"
    )

    print(
        f"  Rate:                       "
        f"{statistics['better_rate']:.4f} "
        f"({statistics['better_rate'] * 100:.2f}%)"
    )

    print()

    print(
        f"Threshold:                    "
        f"{statistics['threshold']:.4f}"
    )

    print()

    print(
        "ALL OBJECTS"
    )

    if statistics["all"]["cosine"]["mean"] is not None:

        print(
            f"  Cosine mean:                "
            f"{statistics['all']['cosine']['mean']:.6f}"
        )

        print(
            f"  Cosine median:              "
            f"{statistics['all']['cosine']['median']:.6f}"
        )

        print(
            f"  Modified mean:              "
            f"{statistics['all']['modified_similarity']['mean']:.6f}"
        )

        print(
            f"  Modified median:            "
            f"{statistics['all']['modified_similarity']['median']:.6f}"
        )

    else:
        print(
            "  No objects."
        )

    print()

    print(
        "FOUND OBJECTS"
    )

    if statistics["found"]["cosine"]["mean"] is not None:

        print(
            f"  Cosine mean:                "
            f"{statistics['found']['cosine']['mean']:.6f}"
        )

        print(
            f"  Cosine median:              "
            f"{statistics['found']['cosine']['median']:.6f}"
        )

        print(
            f"  Modified mean:              "
            f"{statistics['found']['modified_similarity']['mean']:.6f}"
        )

        print(
            f"  Modified median:            "
            f"{statistics['found']['modified_similarity']['median']:.6f}"
        )

    else:

        print(
            "  No objects found."
        )

    print()

    print(
        "MISSED OBJECTS"
    )

    if statistics["missed"]["cosine"]["mean"] is not None:

        print(
            f"  Cosine mean:                "
            f"{statistics['missed']['cosine']['mean']:.6f}"
        )

        print(
            f"  Cosine median:              "
            f"{statistics['missed']['cosine']['median']:.6f}"
        )

        print(
            f"  Modified mean:              "
            f"{statistics['missed']['modified_similarity']['mean']:.6f}"
        )

        print(
            f"  Modified median:            "
            f"{statistics['missed']['modified_similarity']['median']:.6f}"
        )

    else:

        print(
            "  No missed objects."
        )

    print()

    print(
        "PER-CLASS STATISTICS"
    )

    for class_name, stats in sorted(
        statistics["per_class"].items()
    ):

        print()

        print(
            f"  {class_name}"
        )

        print(
            f"    total:                   "
            f"{stats['total']}"
        )

        print(
            f"    original:                "
            f"{stats['original']} "
            f"({stats['original_rate'] * 100:.2f}%)"
        )

        print(
            f"    squared:                 "
            f"{stats['squared']} "
            f"({stats['squared_rate'] * 100:.2f}%)"
        )

        print(
            f"    segmented original:      "
            f"{stats['segmented_original']} "
            f"({stats['segmented_original_rate'] * 100:.2f}%)"
        )

        print(
            f"    segmented squared:       "
            f"{stats['segmented_squared']} "
            f"({stats['segmented_squared_rate'] * 100:.2f}%)"
        )

        print(
            f"    found:                   "
            f"{stats['found']}"
        )

        print(
            f"    missed:                  "
            f"{stats['missed']}"
        )

        print(
            f"    better:                  "
            f"{stats['better']}"
        )

        print(
            f"    recall:                  "
            f"{stats['recall']:.4f}"
        )

        print(
            f"    better rate:             "
            f"{stats['better_rate']:.4f} "
            f"({stats['better_rate'] * 100:.2f}%)"
        )

        print(
            "    cosine:"
        )

        print(
            f"      mean:                 "
            f"{stats['cosine']['mean']:.6f}"
        )

        print(
            f"      median:              "
            f"{stats['cosine']['median']:.6f}"
        )

        print(
            "    modified:"
        )

        print(
            f"      mean:                 "
            f"{stats['modified_similarity']['mean']:.6f}"
        )

        print(
            f"      median:              "
            f"{stats['modified_similarity']['median']:.6f}"
        )

    print()

    print(
        "=" * 70
    )


# ============================================================
# ARGUMENTS
# ============================================================

def parse_args():

    parser = argparse.ArgumentParser(
        description=(
            "Calculate CLIP similarity between "
            "multiple visual embeddings of VOC "
            "images and text embeddings of the "
            "classes annotated for each image."
        )
    )

    parser.add_argument(
        "--annotations",
        type=Path,
        default=Path(
            DEFAULT_ANNOTATIONS
        ),
        help=(
            "Path to annotations.json."
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            DEFAULT_OUTPUT
        ),
        help=(
            "Output directory."
        ),
    )

    parser.add_argument(
        "--api-url",
        type=str,
        default=DEFAULT_API_URL,
        help=(
            "CLIP API endpoint."
        ),
    )

    parser.add_argument(
        "--model",
        type=str,
        default=DEFAULT_MODEL,
        help=(
            "CLIP model name."
        ),
    )

    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help=(
            "HTTP request timeout."
        ),
    )

    parser.add_argument(
        "--scale",
        type=float,
        default=DEFAULT_SCALE,
        help=(
            "Scale used before softmax."
        ),
    )

    parser.add_argument(
        "--threshold",
        type=float,
        default=DEFAULT_THRESHOLD,
        help=(
            "Modified similarity threshold "
            "for detecting an object."
        ),
    )

    return parser.parse_args()


# ============================================================
# MAIN
# ============================================================

def main():

    args = parse_args()

    output_root = (
        args.output
    )

    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ========================================================
    # Load annotations
    # ========================================================

    log(
        f"Loading annotations: "
        f"{args.annotations}"
    )

    annotations = load_annotations(
        args.annotations
    )

    log(
        f"Images in annotations: "
        f"{len(annotations['images'])}"
    )

    # ========================================================
    # Classes
    # ========================================================

    classes = collect_classes(
        annotations
    )

    log(
        f"Classes found: "
        f"{len(classes)}"
    )

    for class_name in classes:
        log(
            f"  {class_name}"
        )

    # ========================================================
    # Client
    # ========================================================

    client = ImmichCLIPClient(
        api_url=args.api_url,
        model_name=args.model,
        timeout=args.timeout,
    )

    # ========================================================
    # Text embeddings
    # ========================================================

    text_embeddings = (
        build_text_embeddings(
            client=client,
            classes=classes,
        )
    )

    text_embeddings_path = (
        output_root
        / "text_embeddings.pkl"
    )

    save_pickle(
        text_embeddings_path,
        text_embeddings,
    )

    log(
        f"Saved text embeddings: "
        f"{text_embeddings_path}"
    )

    # ========================================================
    # Process images
    # ========================================================

    log(
        "========================================"
    )

    log(
        "PROCESSING IMAGES"
    )

    log(
        "========================================"
    )

    total = len(
        annotations["images"]
    )

    results = []

    statistics_accumulator = (
        create_statistics_accumulator()
    )

    for index, image_info in enumerate(
        annotations["images"],
        start=1,
    ):

        image_file = image_info[
            "file"
        ]

        log(
            f"[{index}/{total}] "
            f"{image_file}"
        )

        try:

            result = process_image(
                client=client,
                image_info=image_info,
                annotations_path=(
                    args.annotations
                ),
                text_embeddings=(
                    text_embeddings
                ),
                scale=args.scale,
                threshold=args.threshold,
            )

            if result is None:
                continue

            results.append(
                result
            )

            update_statistics(
                accumulator=(
                    statistics_accumulator
                ),
                class_results=(
                    result["classes"]
                ),
            )

        except Exception as exc:

            warning(
                f"Failed to process "
                f"{image_file}: "
                f"{exc}"
            )

    # ========================================================
    # Statistics
    # ========================================================

    statistics = (
        calculate_statistics(
            accumulator=(
                statistics_accumulator
            ),
            threshold=args.threshold,
        )
    )

    # ========================================================
    # Final result
    # ========================================================

    final_result = {
        "config": {
            "annotations": str(
                args.annotations
            ),

            "model": args.model,

            "api_url": args.api_url,

            "scale": args.scale,

            "threshold": (
                args.threshold
            ),
        },

        "results": results,

        "statistics": statistics,
    }

    # ========================================================
    # Save PKL
    # ========================================================

    results_pkl_path = (
        output_root
        / "results.pkl"
    )

    save_pickle(
        results_pkl_path,
        final_result,
    )

    # ========================================================
    # Save JSON
    # ========================================================

    results_json_path = (
        output_root
        / "results.json"
    )

    with results_json_path.open(
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            make_json_serializable(
                final_result
            ),
            f,
            ensure_ascii=False,
            indent=2,
        )

    # ========================================================
    # Print statistics
    # ========================================================

    print_statistics(
        statistics
    )

    # ========================================================
    # Finished
    # ========================================================

    print()

    print(
        "=" * 70
    )

    print(
        "FINISHED"
    )

    print(
        "=" * 70
    )

    print(
        f"Text embeddings: "
        f"{text_embeddings_path}"
    )

    print(
        f"Results PKL:      "
        f"{results_pkl_path}"
    )

    print(
        f"Results JSON:     "
        f"{results_json_path}"
    )

    print(
        "=" * 70
    )


if __name__ == "__main__":
    main()

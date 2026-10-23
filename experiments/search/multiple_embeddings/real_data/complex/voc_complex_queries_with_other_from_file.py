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
DEFAULT_OTHER_EMBEDDING = "./other_embedding.pkl"
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


def calculate_modified_similarity(
    query_cosine,
    other_cosine,
    scale,
):
    """
    Calculate modified similarity as a two-class
    softmax between the query and the "other" embedding.

    For every image embedding:

        class 0 = query cosine similarity
        class 1 = "other" cosine similarity

    The returned value is the probability of class 0.
    """

    logits = np.stack(
        [
            scale * query_cosine,
            scale * other_cosine,
        ],
        axis=-1,
    )

    probabilities = softmax(
        logits
    )

    return probabilities[..., 0]


# ============================================================
# QUERY GENERATION
# ============================================================

def number_to_word(number):
    words = {
        1: "one",
        2: "two",
        3: "three",
        4: "four",
        5: "five",
        6: "six",
        7: "seven",
        8: "eight",
        9: "nine",
        10: "ten",
    }

    return words.get(
        number,
        str(number),
    )


def pluralize(
    class_name,
    count,
):
    if count == 1:
        return class_name

    irregular = {
        "person": "people",
        "sheep": "sheep",
        "bus": "buses",
    }

    if class_name in irregular:
        return irregular[
            class_name
        ]

    if class_name.endswith(
        (
            "s",
            "x",
            "z",
            "ch",
            "sh",
        )
    ):
        return (
            class_name
            + "es"
        )

    return (
        class_name
        + "s"
    )


def format_query_list(
    items,
):
    if not items:
        return ""

    if len(items) == 1:
        return items[0]

    if len(items) == 2:
        return (
            f"{items[0]} and "
            f"{items[1]}"
        )

    return (
        ", ".join(items[:-1])
        + " and "
        + items[-1]
    )


def build_query_groups(
    image_info,
):
    classes = image_info.get(
        "classes",
        [],
    )

    class_counts = image_info.get(
        "class_counts",
        {},
    )

    # --------------------------------------------------------
    # Individual
    # --------------------------------------------------------

    individual = list(
        dict.fromkeys(
            classes
        )
    )

    # --------------------------------------------------------
    # Combined
    # --------------------------------------------------------

    combined = []

    if classes:
        combined.append(
            format_query_list(
                classes
            )
        )

    # --------------------------------------------------------
    # Counted
    # --------------------------------------------------------

    counted_items = []

    for class_name in classes:

        count = int(
            class_counts.get(
                class_name,
                1,
            )
        )

        if count == 1:
            counted_items.append(
                class_name
            )
        else:
            counted_items.append(
                f"{number_to_word(count)} "
                f"{pluralize(class_name, count)}"
            )

    counted = []

    if counted_items:
        counted.append(
            format_query_list(
                counted_items
            )
        )

    return {
        "individual": individual,
        "combined": combined,
        "counted": counted,
    }


def collect_queries(
    annotations,
):
    queries = {
        "individual": set(),
        "combined": set(),
        "counted": set(),
    }

    for image_info in (
        annotations["images"]
    ):

        groups = build_query_groups(
            image_info
        )

        for group_name, group_queries in (
            groups.items()
        ):

            queries[
                group_name
            ].update(
                group_queries
            )

    return {
        group_name: sorted(
            group_queries
        )
        for group_name, group_queries
        in queries.items()
    }


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


# ============================================================
# TEXT EMBEDDINGS
# ============================================================

def build_text_embeddings(
    client,
    queries,
):
    embeddings = {}

    all_queries = set()

    for group_queries in (
        queries.values()
    ):
        all_queries.update(
            group_queries
        )

    all_queries = sorted(
        all_queries
    )

    log(
        "========================================"
    )

    log(
        "TEXT EMBEDDINGS"
    )

    log(
        "========================================"
    )

    log(
        f"Unique queries: "
        f"{len(all_queries)}"
    )

    for index, query in enumerate(
        all_queries,
        start=1,
    ):

        log(
            f"[{index}/{len(all_queries)}] "
            f"Text: '{query}'"
        )

        embedding = (
            client.get_text_embedding(
                query
            )
        )

        embeddings[
            query
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
# SIMILARITY FOR ONE QUERY
# ============================================================

def calculate_query_similarity(
    image_embedding,
    text_embedding,
    other_embedding,
    scale,
    threshold,
):
    """
    Calculate similarity for ONE text query.

    The 20 image embeddings are:

        0       original
        1       squared
        2-10    segmented_original
        11-19   segmented_squared

    Modified similarity is calculated independently
    for every image embedding as a two-class softmax:

        [query cosine, other cosine]

    The returned modified similarity is the probability
    assigned to the query class.
    """

    image_embedding = normalize_embedding(
        image_embedding
    )

    text_embedding = normalize_embedding(
        text_embedding
    )

    other_embedding = normalize_embedding(
        other_embedding
    )

    if text_embedding.ndim != 1:
        raise ValueError(
            f"Expected one text embedding, "
            f"got shape {text_embedding.shape}"
        )

    if other_embedding.ndim != 1:
        raise ValueError(
            f"Expected one other embedding, "
            f"got shape {other_embedding.shape}"
        )

    if image_embedding.shape[0] < (
        NUM_IMAGE_EMBEDDINGS
    ):
        raise ValueError(
            f"Unexpected number of image embeddings: "
            f"got {image_embedding.shape[0]}, "
            f"expected at least "
            f"{NUM_IMAGE_EMBEDDINGS}."
        )

    if image_embedding.shape[0] > (
        NUM_IMAGE_EMBEDDINGS
    ):
        warning(
            f"API returned "
            f"{image_embedding.shape[0]} image embeddings; "
            f"using first "
            f"{NUM_IMAGE_EMBEDDINGS}."
        )

        image_embedding = (
            image_embedding[
                :NUM_IMAGE_EMBEDDINGS
            ]
        )

    if image_embedding.shape[1] != other_embedding.shape[0]:
        raise ValueError(
            f"Embedding dimension mismatch: "
            f"image embeddings have dimension "
            f"{image_embedding.shape[1]}, "
            f"other embedding has dimension "
            f"{other_embedding.shape[0]}."
        )

    # --------------------------------------------------------
    # Cosine similarity
    # --------------------------------------------------------

    cosine = (
        image_embedding
        @ text_embedding
    )

    other_cosine = (
        image_embedding
        @ other_embedding
    )

    # --------------------------------------------------------
    # Modified similarity
    # --------------------------------------------------------

    modified = calculate_modified_similarity(
        query_cosine=cosine,
        other_cosine=other_cosine,
        scale=scale,
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
    # Best values
    # --------------------------------------------------------

    best_cosine_index = int(
        np.argmax(
            cosine
        )
    )

    best_modified_index = int(
        np.argmax(
            modified
        )
    )

    max_cosine = float(
        cosine[
            best_cosine_index
        ]
    )

    max_modified = float(
        modified[
            best_modified_index
        ]
    )

    original_cosine = float(
        cosine[
            original_index
        ]
    )

    original_modified = float(
        modified[
            original_index
        ]
    )

    squared_modified = float(
        modified[
            squared_index
        ]
    )

    segmented_original_modified = (
        modified[
            original_segments
        ]
    )

    segmented_squared_modified = (
        modified[
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

    return {
        "cosine": (
            cosine
            .astype(
                np.float32
            )
            .tolist()
        ),

        "modified_similarity": (
            modified
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


# ============================================================
# STATISTICS ACCUMULATOR
# ============================================================

def create_group_statistics_accumulator():
    return {
        "queries": 0,

        "original": 0,
        "squared": 0,
        "segmented_original": 0,
        "segmented_squared": 0,

        "found": 0,
        "better": 0,

        "all_cosines": [],
        "all_modified": [],

        "found_cosines": [],
        "found_modified": [],

        "missed_cosines": [],
        "missed_modified": [],

        "per_query": {},
    }


def create_statistics_accumulator():
    return {
        "images": 0,

        "groups": {
            "individual": (
                create_group_statistics_accumulator()
            ),

            "combined": (
                create_group_statistics_accumulator()
            ),

            "counted": (
                create_group_statistics_accumulator()
            ),
        },
    }


def update_group_statistics(
    accumulator,
    query,
    values,
):
    accumulator[
        "queries"
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
            "original"
        ] += 1

    if squared:
        accumulator[
            "squared"
        ] += 1

    if segmented_original:
        accumulator[
            "segmented_original"
        ] += 1

    if segmented_squared:
        accumulator[
            "segmented_squared"
        ] += 1

    if found:

        accumulator[
            "found"
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
            "better"
        ] += 1

    if query not in accumulator[
        "per_query"
    ]:

        accumulator[
            "per_query"
        ][
            query
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
        "per_query"
    ][
        query
    ]

    stats[
        "total"
    ] += 1

    if original:
        stats[
            "original"
        ] += 1

    if squared:
        stats[
            "squared"
        ] += 1

    if segmented_original:
        stats[
            "segmented_original"
        ] += 1

    if segmented_squared:
        stats[
            "segmented_squared"
        ] += 1

    if found:
        stats[
            "found"
        ] += 1
    else:
        stats[
            "missed"
        ] += 1

    if better:
        stats[
            "better"
        ] += 1

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


def update_statistics(
    accumulator,
    image_result,
):
    accumulator[
        "images"
    ] += 1

    for group_name, query_results in (
        image_result[
            "groups"
        ].items()
    ):

        group_accumulator = (
            accumulator[
                "groups"
            ][
                group_name
            ]
        )

        for query, values in (
            query_results.items()
        ):

            update_group_statistics(
                accumulator=(
                    group_accumulator
                ),
                query=query,
                values=values,
            )


# ============================================================
# STATISTICS
# ============================================================

def numeric_stats(
    values,
):
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


def calculate_group_statistics(
    accumulator,
    threshold,
):
    total = accumulator[
        "queries"
    ]

    original = accumulator[
        "original"
    ]

    squared = accumulator[
        "squared"
    ]

    segmented_original = accumulator[
        "segmented_original"
    ]

    segmented_squared = accumulator[
        "segmented_squared"
    ]

    found = accumulator[
        "found"
    ]

    better = accumulator[
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

    found_rate = (
        found / total
        if total
        else 0.0
    )

    better_rate = (
        better / total
        if total
        else 0.0
    )

    per_query_result = {}

    for query, stats in sorted(
        accumulator[
            "per_query"
        ].items()
    ):

        query_total = stats[
            "total"
        ]

        per_query_result[
            query
        ] = {
            "total": query_total,

            "original": (
                stats["original"]
            ),

            "original_rate": (
                stats["original"]
                / query_total
                if query_total
                else 0.0
            ),

            "squared": (
                stats["squared"]
            ),

            "squared_rate": (
                stats["squared"]
                / query_total
                if query_total
                else 0.0
            ),

            "segmented_original": (
                stats[
                    "segmented_original"
                ]
            ),

            "segmented_original_rate": (
                stats[
                    "segmented_original"
                ]
                / query_total
                if query_total
                else 0.0
            ),

            "segmented_squared": (
                stats[
                    "segmented_squared"
                ]
            ),

            "segmented_squared_rate": (
                stats[
                    "segmented_squared"
                ]
                / query_total
                if query_total
                else 0.0
            ),

            "found": (
                stats["found"]
            ),

            "missed": (
                stats["missed"]
            ),

            "better": (
                stats["better"]
            ),

            "recall": (
                stats["found"]
                / query_total
                if query_total
                else 0.0
            ),

            "better_rate": (
                stats["better"]
                / query_total
                if query_total
                else 0.0
            ),

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

    return {
        "threshold": threshold,

        "queries": total,

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
            total - found
        ),

        "better": better,

        "recall": found_rate,

        "better_rate": better_rate,

        "all": {
            "cosine": numeric_stats(
                accumulator[
                    "all_cosines"
                ]
            ),

            "modified_similarity": (
                numeric_stats(
                    accumulator[
                        "all_modified"
                    ]
                )
            ),
        },

        "found_statistics": {
            "cosine": numeric_stats(
                accumulator[
                    "found_cosines"
                ]
            ),

            "modified_similarity": (
                numeric_stats(
                    accumulator[
                        "found_modified"
                    ]
                )
            ),
        },

        "missed_statistics": {
            "cosine": numeric_stats(
                accumulator[
                    "missed_cosines"
                ]
            ),

            "modified_similarity": (
                numeric_stats(
                    accumulator[
                        "missed_modified"
                    ]
                )
            ),
        },

        "per_query": (
            per_query_result
        ),
    }


def calculate_statistics(
    accumulator,
    threshold,
):
    return {
        "images": accumulator[
            "images"
        ],

        "groups": {
            group_name: calculate_group_statistics(
                accumulator=(
                    group_accumulator
                ),
                threshold=threshold,
            )
            for group_name, group_accumulator
            in accumulator[
                "groups"
            ].items()
        },
    }


# ============================================================
# PROCESS ONE IMAGE
# ============================================================

def process_image(
    client,
    image_info,
    annotations_path,
    text_embeddings,
    other_embedding,
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

    query_groups = build_query_groups(
        image_info
    )

    all_queries = []

    for group_queries in (
        query_groups.values()
    ):
        all_queries.extend(
            group_queries
        )

    missing_queries = [
        query
        for query in all_queries
        if query not in text_embeddings
    ]

    if missing_queries:
        raise RuntimeError(
            f"Missing text embeddings "
            f"for {image_file}: "
            f"{missing_queries}"
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

    groups = {
        "individual": {},
        "combined": {},
        "counted": {},
    }

    # --------------------------------------------------------
    # Calculate every query independently
    # --------------------------------------------------------

    for group_name, queries in (
        query_groups.items()
    ):

        for query in queries:

            values = (
                calculate_query_similarity(
                    image_embedding=(
                        image_embedding
                    ),
                    text_embedding=(
                        text_embeddings[
                            query
                        ]
                    ),
                    other_embedding=(
                        other_embedding
                    ),
                    scale=scale,
                    threshold=threshold,
                )
            )

            groups[
                group_name
            ][
                query
            ] = values

            log(
                f"  [{group_name}] "
                f"{query}: "
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

        "queries": query_groups,

        "groups": groups,
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


def load_pickle(
    path,
):
    path = Path(
        path
    )

    if not path.exists():
        raise RuntimeError(
            f"Pickle file does not exist: "
            f"{path}"
        )

    with path.open(
        "rb"
    ) as f:

        return pickle.load(
            f
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
        f"Images: "
        f"{statistics['images']}"
    )

    for group_name, group in (
        statistics[
            "groups"
        ].items()
    ):

        print()

        print(
            group_name.upper()
        )

        print(
            f"  Queries:                    "
            f"{group['queries']}"
        )

        print(
            f"  Original:                   "
            f"{group['original']} "
            f"({group['original_rate'] * 100:.2f}%)"
        )

        print(
            f"  Squared:                    "
            f"{group['squared']} "
            f"({group['squared_rate'] * 100:.2f}%)"
        )

        print(
            f"  Segmented original:         "
            f"{group['segmented_original']} "
            f"({group['segmented_original_rate'] * 100:.2f}%)"
        )

        print(
            f"  Segmented squared:          "
            f"{group['segmented_squared']} "
            f"({group['segmented_squared_rate'] * 100:.2f}%)"
        )

        print(
            f"  Found:                      "
            f"{group['found']} "
            f"({group['recall'] * 100:.2f}%)"
        )

        print(
            f"  Missed:                     "
            f"{group['missed']}"
        )

        print(
            f"  Better:                     "
            f"{group['better']} "
            f"({group['better_rate'] * 100:.2f}%)"
        )

        print()

        print(
            "  ALL QUERIES"
        )

        cosine = group[
            "all"
        ][
            "cosine"
        ]

        modified = group[
            "all"
        ][
            "modified_similarity"
        ]

        if cosine["mean"] is not None:

            print(
                f"    Cosine mean:              "
                f"{cosine['mean']:.6f}"
            )

            print(
                f"    Cosine median:            "
                f"{cosine['median']:.6f}"
            )

            print(
                f"    Modified mean:            "
                f"{modified['mean']:.6f}"
            )

            print(
                f"    Modified median:          "
                f"{modified['median']:.6f}"
            )

        else:

            print(
                "    No queries."
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
            "images and individual, combined "
            "and counted text queries."
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
        "--other-embedding",
        type=Path,
        default=Path(
            DEFAULT_OTHER_EMBEDDING
        ),
        help=(
            "Path to the normalized "
            "'other' text embedding."
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
            "Scale used before two-class softmax."
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

    parser.add_argument(
        "--count",
        type=int,
        default=None,
        help=(
            "Process only the first N images."
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

    images = annotations[
        "images"
    ]

    if args.count is not None:
        images = images[
            :args.count
        ]

    log(
        f"Images in annotations: "
        f"{len(images)}"
    )

    annotations_for_queries = {
        **annotations,
        "images": images,
    }

    # ========================================================
    # Queries
    # ========================================================

    queries = collect_queries(
        annotations_for_queries
    )

    log(
        f"Individual queries: "
        f"{len(queries['individual'])}"
    )

    log(
        f"Combined queries:   "
        f"{len(queries['combined'])}"
    )

    log(
        f"Counted queries:    "
        f"{len(queries['counted'])}"
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
    # Other embedding
    # ========================================================

    log(
        f"Loading other embedding: "
        f"{args.other_embedding}"
    )

    other_embedding = load_pickle(
        args.other_embedding
    )

    other_embedding = normalize_embedding(
        other_embedding
    )

    if other_embedding.ndim != 1:
        raise RuntimeError(
            f"Expected one-dimensional "
            f"other embedding, got shape "
            f"{other_embedding.shape}"
        )

    log(
        f"  shape={other_embedding.shape}"
    )

    # ========================================================
    # Text embeddings
    # ========================================================

    text_embeddings = (
        build_text_embeddings(
            client=client,
            queries=queries,
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
        images
    )

    results = []

    statistics_accumulator = (
        create_statistics_accumulator()
    )

    for index, image_info in enumerate(
        images,
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
                other_embedding=(
                    other_embedding
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
                image_result=result,
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

            "other_embedding": str(
                args.other_embedding
            ),

            "scale": args.scale,

            "threshold": (
                args.threshold
            ),
        },

        "queries": queries,

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

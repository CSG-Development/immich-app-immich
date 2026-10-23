#!/usr/bin/env python3

import argparse
import ast
import json
import math
import pickle
from pathlib import Path

import numpy as np
import requests


# ============================================================
# CONSTANTS
# ============================================================

DEFAULT_SCENES = (
    "./scene_dataset/scenes"
)

DEFAULT_OUTPUT = (
    "./scene_dataset/scene_embeddings.pkl"
)

DEFAULT_JSON_OUTPUT = (
    "./scene_dataset/scene_embeddings.json"
)

DEFAULT_MODEL = (
    "EVA02-B-16__merged2b_s8b_b131k"
)

DEFAULT_API_URL = (
    "http://localhost:3003/predict"
)

DEFAULT_SCALE = 100.0

DEFAULT_TIMEOUT = 30.0

DEFAULT_GRID_COLS = 2

DEFAULT_GRID_ROWS = 2

IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
}


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
        return np.array(
            ast.literal_eval(x),
            dtype=np.float32,
        )

    return np.array(
        x,
        dtype=np.float32,
    )


def normalize_embedding(x):
    """
    L2-normalize embedding.

    Supports:

        (D,)
        (N, D)
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
        "Unsupported embedding shape: "
        f"{x.shape}"
    )


# ============================================================
# SOFTMAX
# ============================================================

def softmax(x):
    """
    Numerically stable softmax.

    Supports 1D arrays.
    """

    x = np.asarray(
        x,
        dtype=np.float32,
    )

    x = (
        x
        - np.max(x)
    )

    exp_x = np.exp(x)

    return (
        exp_x
        / np.sum(exp_x)
    )


# ============================================================
# MODIFIED SIMILARITY
# ============================================================

def calculate_modified_similarity(
    query_cosine,
    other_cosine,
    scale,
):
    """
    Calculate modified similarity of a query
    against the special "other" class.

    Formula:

        softmax(
            [
                scale * query_cosine,
                scale * other_cosine
            ]
        )[0]

    Result is the probability of the query
    against:

        query vs other
    """

    logits = np.array(
        [
            scale * query_cosine,
            scale * other_cosine,
        ],
        dtype=np.float32,
    )

    probabilities = softmax(
        logits
    )

    return float(
        probabilities[0]
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
        """
        Get normalized CLIP text embedding.
        """

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

        if "clip" not in data:
            raise RuntimeError(
                "Text embedding response "
                "does not contain 'clip':\n"
                f"{data}"
            )

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
        """
        Get normalized CLIP image embedding.
        """

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

        if "clip" not in data:
            raise RuntimeError(
                "Image embedding response "
                "does not contain 'clip':\n"
                f"{data}"
            )

        embedding = parse_embedding(
            data["clip"]
        )

        return normalize_embedding(
            embedding
        )


# ============================================================
# IMAGE PROCESSING
# ============================================================

def load_image(
    image_path,
):
    """
    Load image using PIL.

    Returns:
        PIL.Image
    """

    from PIL import Image

    image = Image.open(
        image_path
    )

    return image.convert(
        "RGB"
    )


def save_temp_crop(
    image,
    path,
):
    """
    Save cropped image.
    """

    path = Path(
        path
    )

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    image.save(
        path,
        format="PNG",
    )


# ============================================================
# GRID GENERATION
# ============================================================

def generate_regular_grid(
    image_width,
    image_height,
    grid_cols,
    grid_rows,
):
    """
    Generate regular non-overlapping grid.

    The image is divided into:

        grid_rows x grid_cols

    cells.

    Returns a list of dictionaries.
    """

    if grid_cols <= 0:
        raise ValueError(
            "grid_cols must be > 0"
        )

    if grid_rows <= 0:
        raise ValueError(
            "grid_rows must be > 0"
        )

    cell_width = (
        image_width
        / grid_cols
    )

    cell_height = (
        image_height
        / grid_rows
    )

    cells = []

    for row in range(
        grid_rows
    ):

        for col in range(
            grid_cols
        ):

            x0 = int(
                round(
                    col * cell_width
                )
            )

            y0 = int(
                round(
                    row * cell_height
                )
            )

            x1 = int(
                round(
                    (col + 1)
                    * cell_width
                )
            )

            y1 = int(
                round(
                    (row + 1)
                    * cell_height
                )
            )

            cells.append(
                {
                    "part_type": "grid",
                    "row": row,
                    "col": col,
                    "x": x0,
                    "y": y0,
                    "width": x1 - x0,
                    "height": y1 - y0,
                    "x1": x1,
                    "y1": y1,
                }
            )

    return cells


# ============================================================
# OVERLAPPING GRID
# ============================================================

def generate_overlapping_grid(
    image_width,
    image_height,
    grid_cols,
    grid_rows,
):
    """
    Generate overlapping windows.

    The window has exactly the size of one
    regular grid cell.

    Horizontal shift:
        half of cell width

    Vertical shift:
        half of cell height

    The first window starts at (0, 0).

    Windows are generated until the image
    boundary is reached.

    If the last regular step would leave
    a part of the image uncovered, a final
    window is aligned with the right/bottom
    boundary.
    """

    if grid_cols <= 0:
        raise ValueError(
            "grid_cols must be > 0"
        )

    if grid_rows <= 0:
        raise ValueError(
            "grid_rows must be > 0"
        )

    cell_width = (
        image_width
        / grid_cols
    )

    cell_height = (
        image_height
        / grid_rows
    )

    window_width = int(
        round(cell_width)
    )

    window_height = int(
        round(cell_height)
    )

    if (
        window_width <= 0
        or window_height <= 0
    ):
        raise ValueError(
            "Calculated window size is zero."
        )

    step_x = max(
        1,
        int(
            round(
                window_width / 2
            )
        )
    )

    step_y = max(
        1,
        int(
            round(
                window_height / 2
            )
        )
    )

    max_x = (
        image_width
        - window_width
    )

    max_y = (
        image_height
        - window_height
    )

    if max_x < 0:
        raise ValueError(
            "Window width is larger "
            "than image width."
        )

    if max_y < 0:
        raise ValueError(
            "Window height is larger "
            "than image height."
        )

    x_positions = []

    x = 0

    while x <= max_x:

        x_positions.append(
            x
        )

        x += step_x

    if (
        not x_positions
        or x_positions[-1] != max_x
    ):
        x_positions.append(
            max_x
        )

    y_positions = []

    y = 0

    while y <= max_y:

        y_positions.append(
            y
        )

        y += step_y

    if (
        not y_positions
        or y_positions[-1] != max_y
    ):
        y_positions.append(
            max_y
        )

    cells = []

    index = 0

    for row, y in enumerate(
        y_positions
    ):

        for col, x in enumerate(
            x_positions
        ):

            index += 1

            cells.append(
                {
                    "part_type": "overlap",
                    "index": index,
                    "row": row,
                    "col": col,
                    "x": int(x),
                    "y": int(y),
                    "width": int(
                        window_width
                    ),
                    "height": int(
                        window_height
                    ),
                    "x1": int(
                        x + window_width
                    ),
                    "y1": int(
                        y + window_height
                    ),
                }
            )

    return cells


# ============================================================
# COSINE
# ============================================================

def cosine_similarity(
    image_embedding,
    text_embedding,
):
    """
    Calculate cosine similarity.

    Embeddings are normalized,
    therefore dot product is enough.
    """

    image_embedding = np.asarray(
        image_embedding,
        dtype=np.float32,
    )

    text_embedding = np.asarray(
        text_embedding,
        dtype=np.float32,
    )

    if image_embedding.ndim != 1:
        raise ValueError(
            "Image embedding must be 1D, "
            f"got {image_embedding.shape}"
        )

    if text_embedding.ndim != 1:
        raise ValueError(
            "Text embedding must be 1D, "
            f"got {text_embedding.shape}"
        )

    if (
        image_embedding.shape
        != text_embedding.shape
    ):
        raise ValueError(
            "Embedding dimension mismatch: "
            f"{image_embedding.shape} vs "
            f"{text_embedding.shape}"
        )

    return float(
        image_embedding
        @ text_embedding
    )


# ============================================================
# SIMILARITY FOR ONE EMBEDDING
# ============================================================

def calculate_similarity_results(
    image_embedding,
    text_embeddings,
    description,
    classes,
    scale,
):
    """
    Calculate similarities for one image
    embedding.

    Queries:

        description
        every represented class
        other

    Modified similarity is calculated
    against "other".
    """

    if "other" not in text_embeddings:
        raise RuntimeError(
            "Text embedding for 'other' "
            "is missing."
        )

    other_embedding = (
        text_embeddings["other"]
    )

    other_cosine = cosine_similarity(
        image_embedding,
        other_embedding,
    )

    queries = []

    queries.append(
        (
            "description",
            description,
        )
    )

    for class_name in classes:

        queries.append(
            (
                "class",
                class_name,
            )
        )

    results = {}

    for query_type, text in queries:

        if text not in text_embeddings:
            raise RuntimeError(
                f"Missing text embedding "
                f"for query: '{text}'"
            )

        query_embedding = (
            text_embeddings[text]
        )

        query_cosine = (
            cosine_similarity(
                image_embedding,
                query_embedding,
            )
        )

        modified = (
            calculate_modified_similarity(
                query_cosine=query_cosine,
                other_cosine=other_cosine,
                scale=scale,
            )
        )

        if query_type == "description":
            key = "description"
        else:
            key = text

        results[key] = {
            "text": text,
            "type": query_type,
            "cosine": query_cosine,
            "modified_similarity": modified,
            "other_cosine": other_cosine,
        }

    results["other"] = {
        "text": "other",
        "type": "other",
        "cosine": other_cosine,
    }

    return results


# ============================================================
# PART DESCRIPTION
# ============================================================

def make_part_id(
    part_type,
    index,
    row,
    col,
):
    """
    Generate stable identifier for image part.
    """

    if part_type == "grid":

        return (
            f"grid_"
            f"r{row + 1}_"
            f"c{col + 1}"
        )

    return (
        f"overlap_"
        f"{index:03d}_"
        f"r{row + 1}_"
        f"c{col + 1}"
    )


def add_part_identity(
    part,
):
    """
    Add human-readable part ID.
    """

    part = dict(
        part
    )

    part["part_id"] = make_part_id(
        part_type=part[
            "part_type"
        ],
        index=part.get(
            "index",
            0,
        ),
        row=part["row"],
        col=part["col"],
    )

    return part


# ============================================================
# PART STATISTICS
# ============================================================

def calculate_part_statistics(
    parts,
    similarity_key,
):
    """
    Calculate min/max similarity across
    image parts.

    similarity_key:

        cosine
        modified_similarity

    Returns statistics separately for
    every query.
    """

    if not parts:
        return {}

    query_names = set()

    for part in parts:

        similarities = (
            part["similarities"]
        )

        for key in similarities:

            if key != "other":
                query_names.add(
                    key
                )

    statistics = {}

    for query_name in sorted(
        query_names
    ):

        values = []

        for part in parts:

            similarities = (
                part["similarities"]
            )

            if query_name not in similarities:
                continue

            value = similarities[
                query_name
            ].get(
                similarity_key
            )

            if value is None:
                continue

            values.append(
                (
                    float(value),
                    part,
                )
            )

        if not values:
            continue

        min_value, min_part = min(
            values,
            key=lambda x: x[0]
        )

        max_value, max_part = max(
            values,
            key=lambda x: x[0]
        )

        statistics[
            query_name
        ] = {
            "text": (
                parts[0][
                    "similarities"
                ][
                    query_name
                ]["text"]
            ),

            "min": float(
                min_value
            ),

            "min_part": {
                "part_id": (
                    min_part[
                        "part_id"
                    ]
                ),
                "part_type": (
                    min_part[
                        "part_type"
                    ]
                ),
                "row": (
                    min_part[
                        "row"
                    ]
                ),
                "col": (
                    min_part[
                        "col"
                    ]
                ),
                "x": (
                    min_part[
                        "x"
                    ]
                ),
                "y": (
                    min_part[
                        "y"
                    ]
                ),
                "width": (
                    min_part[
                        "width"
                    ]
                ),
                "height": (
                    min_part[
                        "height"
                    ]
                ),
            },

            "max": float(
                max_value
            ),

            "max_part": {
                "part_id": (
                    max_part[
                        "part_id"
                    ]
                ),
                "part_type": (
                    max_part[
                        "part_type"
                    ]
                ),
                "row": (
                    max_part[
                        "row"
                    ]
                ),
                "col": (
                    max_part[
                        "col"
                    ]
                ),
                "x": (
                    max_part[
                        "x"
                    ]
                ),
                "y": (
                    max_part[
                        "y"
                    ]
                ),
                "width": (
                    max_part[
                        "width"
                    ]
                ),
                "height": (
                    max_part[
                        "height"
                    ]
                ),
            },
        }

    return statistics


def calculate_all_part_statistics(
    grid_parts,
    overlap_parts,
):
    """
    Calculate statistics across ALL parts:

        regular grid
        +
        overlapping windows
    """

    all_parts = (
        list(grid_parts)
        + list(overlap_parts)
    )

    return {
        "cosine": (
            calculate_part_statistics(
                parts=all_parts,
                similarity_key="cosine",
            )
        ),

        "modified_similarity": (
            calculate_part_statistics(
                parts=all_parts,
                similarity_key=(
                    "modified_similarity"
                ),
            )
        ),
    }


# ============================================================
# SCENE DATASET
# ============================================================

def find_metadata_files(
    scenes_root,
):
    """
    Find all scene metadata files.
    """

    scenes_root = Path(
        scenes_root
    )

    metadata_root = (
        scenes_root
        / "metadata"
    )

    if not metadata_root.exists():
        raise RuntimeError(
            "Metadata directory does not exist: "
            f"{metadata_root}"
        )

    files = sorted(
        metadata_root.glob(
            "*.json"
        )
    )

    if not files:
        raise RuntimeError(
            "No metadata JSON files found in: "
            f"{metadata_root}"
        )

    return files


def load_scene_metadata(
    metadata_path,
):
    """
    Load one scene metadata JSON.
    """

    with open(
        metadata_path,
        "r",
        encoding="utf-8",
    ) as f:

        metadata = json.load(
            f
        )

    required_fields = [
        "scene_id",
        "configuration_id",
        "combination_id",
        "description",
        "class_counts",
        "num_objects",
        "objects",
    ]

    missing = [
        field
        for field in required_fields
        if field not in metadata
    ]

    if missing:
        raise RuntimeError(
            f"Metadata file {metadata_path} "
            f"is missing fields: {missing}"
        )

    return metadata


# ============================================================
# CLASS QUERIES
# ============================================================

def get_scene_classes(
    metadata,
):
    """
    Return classes represented on the scene.
    """

    class_counts = (
        metadata[
            "class_counts"
        ]
    )

    classes = [
        class_name
        for class_name, count
        in class_counts.items()
        if int(count) > 0
    ]

    return classes


# ============================================================
# TEXT EMBEDDINGS
# ============================================================

def collect_required_text_queries(
    scene_metadata,
):
    """
    Collect all unique text queries needed
    by the entire dataset.
    """

    queries = set()

    queries.add(
        "other"
    )

    for metadata in scene_metadata:

        description = (
            metadata[
                "description"
            ]
        )

        queries.add(
            description
        )

        for class_name in (
            get_scene_classes(
                metadata
            )
        ):

            queries.add(
                class_name
            )

    return sorted(
        queries
    )


def build_text_embeddings(
    client,
    queries,
):
    """
    Build one embedding for every
    unique text query.
    """

    embeddings = {}

    log("")
    log("=" * 70)
    log("TEXT EMBEDDINGS")
    log("=" * 70)

    log(
        f"Unique text queries: "
        f"{len(queries)}"
    )

    for index, text in enumerate(
        queries,
        start=1,
    ):

        log(
            f"[{index}/{len(queries)}] "
            f"Text: '{text}'"
        )

        try:

            embedding = (
                client.get_text_embedding(
                    text
                )
            )

            embeddings[text] = (
                embedding.astype(
                    np.float32
                )
            )

            log(
                f"  shape={embedding.shape}"
            )

        except Exception as exc:

            warning(
                f"Failed to generate "
                f"text embedding for "
                f"'{text}': {exc}"
            )

            raise

    return embeddings


# ============================================================
# IMAGE EMBEDDINGS
# ============================================================

def process_image_part(
    client,
    image,
    part,
    temp_path,
    text_embeddings,
    description,
    classes,
    scale,
):
    """
    Crop one image part, calculate embedding
    and all similarities.
    """

    crop = image.crop(
        (
            part["x"],
            part["y"],
            part["x1"],
            part["y1"],
        )
    )

    save_temp_crop(
        crop,
        temp_path,
    )

    embedding = (
        client.get_image_embedding(
            temp_path
        )
    )

    embedding = (
        embedding.astype(
            np.float32
        )
    )

    similarities = (
        calculate_similarity_results(
            image_embedding=embedding,
            text_embeddings=text_embeddings,
            description=description,
            classes=classes,
            scale=scale,
        )
    )

    result = dict(
        part
    )

    result["embedding"] = (
        embedding
    )

    result["similarities"] = (
        similarities
    )

    return result


# ============================================================
# PROCESS ONE SCENE
# ============================================================

def process_scene(
    client,
    image_path,
    scene_id,
    description,
    classes,
    text_embeddings,
    grid_cols,
    grid_rows,
    scale,
    temp_root,
):
    """
    Process one scene.

    Calculates:

        1. full-image embedding
        2. regular grid embeddings
        3. overlapping window embeddings

    Similarity is calculated for all of them.
    """

    image = load_image(
        image_path
    )

    image_width, image_height = (
        image.size
    )

    log(
        f"Image size: "
        f"{image_width}x"
        f"{image_height}"
    )

    # ========================================================
    # FULL IMAGE
    # ========================================================

    log(
        "  Calculating full-image embedding..."
    )

    full_embedding = (
        client.get_image_embedding(
            image_path
        )
    )

    full_embedding = (
        full_embedding.astype(
            np.float32
        )
    )

    full_similarities = (
        calculate_similarity_results(
            image_embedding=(
                full_embedding
            ),
            text_embeddings=(
                text_embeddings
            ),
            description=(
                description
            ),
            classes=classes,
            scale=scale,
        )
    )

    # ========================================================
    # REGULAR GRID
    # ========================================================

    grid_parts = (
        generate_regular_grid(
            image_width=image_width,
            image_height=image_height,
            grid_cols=grid_cols,
            grid_rows=grid_rows,
        )
    )

    grid_parts = [
        add_part_identity(
            part
        )
        for part in grid_parts
    ]

    log(
        f"  Regular grid: "
        f"{grid_rows} rows x "
        f"{grid_cols} cols = "
        f"{len(grid_parts)} parts"
    )

    processed_grid_parts = []

    for index, part in enumerate(
        grid_parts,
        start=1,
    ):

        log(
            f"    Grid part "
            f"{index}/{len(grid_parts)}: "
            f"{part['part_id']} "
            f""
            f"({part['x']}, {part['y']}) "
            f""
            f"{part['width']}x"
            f"{part['height']}"
        )

        temp_path = (
            temp_root
            / (
                f"{scene_id}_"
                f"{part['part_id']}.png"
            )
        )

        processed = (
            process_image_part(
                client=client,
                image=image,
                part=part,
                temp_path=temp_path,
                text_embeddings=text_embeddings,
                description=description,
                classes=classes,
                scale=scale,
            )
        )

        processed_grid_parts.append(
            processed
        )

    # ========================================================
    # OVERLAPPING WINDOWS
    # ========================================================

    overlap_parts = (
        generate_overlapping_grid(
            image_width=image_width,
            image_height=image_height,
            grid_cols=grid_cols,
            grid_rows=grid_rows,
        )
    )

    overlap_parts = [
        add_part_identity(
            part
        )
        for part in overlap_parts
    ]

    log(
        f"  Overlapping windows: "
        f"{len(overlap_parts)} parts"
    )

    processed_overlap_parts = []

    for index, part in enumerate(
        overlap_parts,
        start=1,
    ):

        log(
            f"    Overlap part "
            f"{index}/{len(overlap_parts)}: "
            f"{part['part_id']} "
            f""
            f"({part['x']}, {part['y']}) "
            f""
            f"{part['width']}x"
            f"{part['height']}"
        )

        temp_path = (
            temp_root
            / (
                f"{scene_id}_"
                f"{part['part_id']}.png"
            )
        )

        processed = (
            process_image_part(
                client=client,
                image=image,
                part=part,
                temp_path=temp_path,
                text_embeddings=text_embeddings,
                description=description,
                classes=classes,
                scale=scale,
            )
        )

        processed_overlap_parts.append(
            processed
        )

    # ========================================================
    # PART STATISTICS
    # ========================================================

    part_statistics = (
        calculate_all_part_statistics(
            grid_parts=(
                processed_grid_parts
            ),
            overlap_parts=(
                processed_overlap_parts
            ),
        )
    )

    # ========================================================
    # RESULT
    # ========================================================

    return {
        "image": str(
            image_path
        ),

        "image_width": (
            image_width
        ),

        "image_height": (
            image_height
        ),

        "grid": {
            "rows": grid_rows,
            "cols": grid_cols,
        },

        # ----------------------------------------------------
        # Full image
        # ----------------------------------------------------

        "full_image": {
            "embedding": (
                full_embedding
            ),

            "similarities": (
                full_similarities
            ),
        },

        # ----------------------------------------------------
        # Regular grid
        # ----------------------------------------------------

        "grid_parts": (
            processed_grid_parts
        ),

        # ----------------------------------------------------
        # Overlapping parts
        # ----------------------------------------------------

        "overlap_parts": (
            processed_overlap_parts
        ),

        # ----------------------------------------------------
        # Statistics across all parts
        # ----------------------------------------------------

        "part_statistics": (
            part_statistics
        ),
    }


# ============================================================
# PROCESS SCENES
# ============================================================

def process_scenes(
    client,
    scenes_root,
    metadata_files,
    text_embeddings,
    grid_cols,
    grid_rows,
    scale,
):
    """
    Process all scenes.
    """

    scenes_root = Path(
        scenes_root
    )

    images_root = (
        scenes_root
        / "images"
    )

    if not images_root.exists():
        raise RuntimeError(
            "Images directory does not exist: "
            f"{images_root}"
        )

    temp_root = (
        scenes_root
        / ".embedding_crops"
    )

    temp_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    configurations = {}

    total = len(
        metadata_files
    )

    processed = 0
    failed = 0

    for metadata_path in metadata_files:

        processed += 1

        try:

            metadata = (
                load_scene_metadata(
                    metadata_path
                )
            )

            scene_id = (
                metadata[
                    "scene_id"
                ]
            )

            configuration_id = int(
                metadata[
                    "configuration_id"
                ]
            )

            configuration_key = (
                f"config_"
                f"{configuration_id:03d}"
            )

            image_path = (
                images_root
                / f"{scene_id}.png"
            )

            if not image_path.exists():

                found = None

                for extension in (
                    IMAGE_EXTENSIONS
                ):

                    candidate = (
                        images_root
                        / (
                            f"{scene_id}"
                            f"{extension}"
                        )
                    )

                    if candidate.exists():
                        found = candidate
                        break

                if found is None:
                    raise RuntimeError(
                        "Scene image does not "
                        "exist: "
                        f"{image_path}"
                    )

                image_path = found

            description = (
                metadata[
                    "description"
                ]
            )

            classes = (
                get_scene_classes(
                    metadata
                )
            )

            log("")
            log("=" * 70)

            log(
                f"[{processed}/{total}] "
                f"{scene_id}"
            )

            log(
                f"Configuration: "
                f"{configuration_key}"
            )

            log(
                f"Description: "
                f"{description}"
            )

            log(
                f"Classes: "
                f"{', '.join(classes)}"
            )

            log(
                f"Image: "
                f"{image_path}"
            )

            scene_result = (
                process_scene(
                    client=client,
                    image_path=image_path,
                    scene_id=scene_id,
                    description=description,
                    classes=classes,
                    text_embeddings=text_embeddings,
                    grid_cols=grid_cols,
                    grid_rows=grid_rows,
                    scale=scale,
                    temp_root=temp_root,
                )
            )

            # =================================================
            # INITIALIZE CONFIGURATION
            # =================================================

            if (
                configuration_key
                not in configurations
            ):

                configurations[
                    configuration_key
                ] = {

                    "configuration_id": (
                        configuration_id
                    ),

                    "description": (
                        description
                    ),

                    "class_counts": (
                        metadata[
                            "class_counts"
                        ]
                    ),

                    "num_objects": (
                        metadata[
                            "num_objects"
                        ]
                    ),

                    "classes": (
                        classes
                    ),

                    "scenes": {},
                }

            # =================================================
            # STORE SCENE
            # =================================================

            configurations[
                configuration_key
            ][
                "scenes"
            ][
                scene_id
            ] = {

                "scene_id": (
                    scene_id
                ),

                "configuration_id": (
                    configuration_id
                ),

                "combination_id": (
                    metadata[
                        "combination_id"
                    ]
                ),

                "description": (
                    description
                ),

                "class_counts": (
                    metadata[
                        "class_counts"
                    ]
                ),

                "num_objects": (
                    metadata[
                        "num_objects"
                    ]
                ),

                "classes": (
                    classes
                ),

                **scene_result,
            }

            # =================================================
            # LOG FULL IMAGE SIMILARITY
            # =================================================

            log(
                "  Full image similarity:"
            )

            for key, result in (
                scene_result[
                    "full_image"
                ][
                    "similarities"
                ].items()
            ):

                if key == "other":

                    log(
                        f"    Other: "
                        f"cosine="
                        f"{result['cosine']:.6f}"
                    )

                    continue

                log(
                    f"    {key}: "
                    f"cosine="
                    f"{result['cosine']:.6f}, "
                    f"modified="
                    f"{result['modified_similarity']:.6f}"
                )

            # =================================================
            # LOG MAX STATISTICS
            # =================================================

            log(
                "  Maximum similarities "
                "among all parts:"
            )

            for (
                similarity_type,
                statistics,
            ) in (
                scene_result[
                    "part_statistics"
                ].items()
            ):

                log(
                    f"    {similarity_type}:"
                )

                for (
                    query_name,
                    values,
                ) in statistics.items():

                    log(
                        f"      "
                        f"{query_name}: "
                        f"min="
                        f"{values['min']:.6f}, "
                        f"max="
                        f"{values['max']:.6f}, "
                        f"max_part="
                        f"{values['max_part']['part_id']}"
                    )

        except Exception as exc:

            failed += 1

            warning(
                f"Failed to process "
                f"{metadata_path}: "
                f"{exc}"
            )

    return (
        configurations,
        failed,
    )


# ============================================================
# DATASET STATISTICS
# ============================================================

def calculate_dataset_statistics(
    configurations,
):
    """
    Calculate global statistics.
    """

    total_scenes = sum(
        len(
            configuration[
                "scenes"
            ]
        )
        for configuration
        in configurations.values()
    )

    return {
        "num_configurations": (
            len(configurations)
        ),

        "num_scenes": (
            total_scenes
        ),
    }


# ============================================================
# SAVE PKL
# ============================================================

def save_pickle(
    path,
    data,
):
    """
    Save arbitrary Python structure to PKL.
    """

    path = Path(
        path
    )

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with open(
        path,
        "wb",
    ) as f:

        pickle.dump(
            data,
            f,
            protocol=pickle.HIGHEST_PROTOCOL,
        )


# ============================================================
# JSON SERIALIZATION
# ============================================================

def make_json_serializable(
    data,
):
    """
    Recursively convert numpy objects
    to JSON-compatible Python objects.
    """

    if isinstance(
        data,
        np.ndarray,
    ):

        return data.tolist()

    if isinstance(
        data,
        np.floating,
    ):

        return float(
            data
        )

    if isinstance(
        data,
        np.integer,
    ):

        return int(
            data
        )

    if isinstance(
        data,
        dict,
    ):

        return {
            key: make_json_serializable(
                value
            )
            for key, value
            in data.items()
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

    if isinstance(
        data,
        tuple,
    ):

        return [
            make_json_serializable(
                value
            )
            for value in data
        ]

    return data


def save_json(
    path,
    data,
):
    """
    Save JSON-compatible representation.
    """

    path = Path(
        path
    )

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
            make_json_serializable(
                data
            ),
            f,
            ensure_ascii=False,
            indent=2,
        )


# ============================================================
# SUMMARY
# ============================================================

def print_summary(
    configurations,
    failed,
):
    """
    Print final summary.
    """

    total_scenes = sum(
        len(
            configuration[
                "scenes"
            ]
        )
        for configuration
        in configurations.values()
    )

    print()
    print("=" * 70)
    print("FINISHED")
    print("=" * 70)

    print(
        f"Configurations: "
        f"{len(configurations)}"
    )

    print(
        f"Scenes processed successfully: "
        f"{total_scenes}"
    )

    print(
        f"Scenes failed: "
        f"{failed}"
    )

    print()

    for (
        configuration_key,
        configuration,
    ) in configurations.items():

        scene_count = len(
            configuration[
                "scenes"
            ]
        )

        print(
            f"{configuration_key}: "
            f"{scene_count} scenes | "
            f"{configuration['description']}"
        )

    print("=" * 70)


# ============================================================
# ARGUMENTS
# ============================================================

def parse_args():

    parser = argparse.ArgumentParser(
        description=(
            "Generate CLIP embeddings for "
            "full scene images, regular "
            "grid cells and overlapping "
            "image windows. Calculate "
            "cosine and modified similarity "
            "for every embedding."
        )
    )

    parser.add_argument(
        "--scenes",
        type=Path,
        default=Path(
            DEFAULT_SCENES
        ),
        help=(
            "Root directory containing "
            "generated scenes. Expected: "
            "scenes/images/*.png and "
            "scenes/metadata/*.json"
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            DEFAULT_OUTPUT
        ),
        help=(
            "Output PKL file."
        ),
    )

    parser.add_argument(
        "--json-output",
        type=Path,
        default=Path(
            DEFAULT_JSON_OUTPUT
        ),
        help=(
            "Output JSON file."
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
        default=DEFAULT_TIMEOUT,
        help=(
            "HTTP request timeout."
        ),
    )

    parser.add_argument(
        "--scale",
        type=float,
        default=DEFAULT_SCALE,
        help=(
            "Scale used before the "
            "query-vs-other softmax."
        ),
    )

    parser.add_argument(
        "--grid-cols",
        type=int,
        default=DEFAULT_GRID_COLS,
        help=(
            "Number of regular grid "
            "cells horizontally."
        ),
    )

    parser.add_argument(
        "--grid-rows",
        type=int,
        default=DEFAULT_GRID_ROWS,
        help=(
            "Number of regular grid "
            "cells vertically."
        ),
    )

    return parser.parse_args()


# ============================================================
# MAIN
# ============================================================

def main():

    args = parse_args()

    scenes_root = (
        args.scenes
    )

    output_path = (
        args.output
    )

    json_output_path = (
        args.json_output
    )

    # ========================================================
    # Validate arguments
    # ========================================================

    if args.grid_cols <= 0:
        raise RuntimeError(
            "--grid-cols must be > 0"
        )

    if args.grid_rows <= 0:
        raise RuntimeError(
            "--grid-rows must be > 0"
        )

    # ========================================================
    # Validate scenes
    # ========================================================

    if not scenes_root.exists():

        raise RuntimeError(
            "Scenes directory does not exist: "
            f"{scenes_root}"
        )

    metadata_files = (
        find_metadata_files(
            scenes_root
        )
    )

    log(
        f"Scenes root: "
        f"{scenes_root}"
    )

    log(
        f"Metadata files: "
        f"{len(metadata_files)}"
    )

    log(
        f"Grid: "
        f"{args.grid_rows} rows x "
        f"{args.grid_cols} cols"
    )

    log(
        "Overlapping window: "
        "half-cell horizontal/vertical shift"
    )

    # ========================================================
    # Load metadata
    # ========================================================

    log("")
    log(
        "Loading scene metadata..."
    )

    scene_metadata = []

    for metadata_path in (
        metadata_files
    ):

        metadata = (
            load_scene_metadata(
                metadata_path
            )
        )

        scene_metadata.append(
            metadata
        )

    # ========================================================
    # Collect text queries
    # ========================================================

    text_queries = (
        collect_required_text_queries(
            scene_metadata
        )
    )

    log("")
    log(
        "Required text queries:"
    )

    for text in text_queries:

        log(
            f"  {text}"
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
            queries=text_queries,
        )
    )

    # ========================================================
    # Scene embeddings
    # ========================================================

    (
        configurations,
        failed,
    ) = process_scenes(
        client=client,
        scenes_root=scenes_root,
        metadata_files=metadata_files,
        text_embeddings=text_embeddings,
        grid_cols=args.grid_cols,
        grid_rows=args.grid_rows,
        scale=args.scale,
    )

    # ========================================================
    # Dataset statistics
    # ========================================================

    dataset_statistics = (
        calculate_dataset_statistics(
            configurations
        )
    )

    # ========================================================
    # Build final result
    # ========================================================

    result = {

        "config": {

            "scenes": str(
                scenes_root
            ),

            "model": (
                args.model
            ),

            "api_url": (
                args.api_url
            ),

            "scale": (
                args.scale
            ),

            "grid_rows": (
                args.grid_rows
            ),

            "grid_cols": (
                args.grid_cols
            ),

            "overlap_shift": (
                "half cell width "
                "and half cell height"
            ),

            "modified_similarity": (
                "softmax("
                "[scale * cosine(query), "
                "scale * cosine(other)"
                "])[query]"
            ),
        },

        "statistics": (
            dataset_statistics
        ),

        "text_embeddings": (
            text_embeddings
        ),

        "configurations": (
            configurations
        ),
    }

    # ========================================================
    # Save PKL
    # ========================================================

    save_pickle(
        output_path,
        result,
    )

    log("")
    log(
        f"Saved PKL: "
        f"{output_path}"
    )

    # ========================================================
    # Save JSON
    # ========================================================

    if json_output_path is not None:

        save_json(
            json_output_path,
            result,
        )

        log(
            f"Saved JSON: "
            f"{json_output_path}"
        )

    # ========================================================
    # Summary
    # ========================================================

    print_summary(
        configurations=configurations,
        failed=failed,
    )


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()

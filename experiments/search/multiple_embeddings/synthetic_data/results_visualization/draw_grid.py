#!/usr/bin/env python3

import argparse
import json
import pickle
import re
from pathlib import Path

import matplotlib.colors as mcolors
import matplotlib.patches as patches
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image


# ============================================================
# CONSTANTS
# ============================================================

DEFAULT_RESULTS = (
    "./scene_embeddings.pkl"
)

DEFAULT_SCENES = (
    "../../../scene_dataset/scenes"
)

DEFAULT_OUTPUT_DIR = (
    "./similarity_visualizations"
)

DEFAULT_DPI = 150

# Transparency of the heatmap.
# Lower value = original image is more visible.
DEFAULT_ALPHA = 0.35

DEFAULT_LINE_WIDTH = 2.0

DEFAULT_FONT_SIZE = 9

IMAGE_EXTENSIONS = (
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
)

# Modified similarity is expected to be in [0, 1].
MODIFIED_SIMILARITY_MIN = 0.0
MODIFIED_SIMILARITY_MAX = 1.0

# Blue -> Yellow -> Red
COLOR_MAP_NAME = "turbo"


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
# LOAD
# ============================================================


def load_results(path):
    """
    Load testing results.

    Supports:
        .pkl
        .pickle
        .json
    """

    path = Path(path)

    if not path.exists():
        raise RuntimeError(
            "Results file does not exist: "
            f"{path}"
        )

    log(
        f"Loading results from: {path}"
    )

    suffix = path.suffix.lower()

    if suffix in (
        ".pkl",
        ".pickle",
    ):
        with open(
            path,
            "rb",
        ) as f:
            return pickle.load(f)

    if suffix == ".json":
        with open(
            path,
            "r",
            encoding="utf-8",
        ) as f:
            return json.load(f)

    raise RuntimeError(
        "Unsupported results file format: "
        f"{suffix}"
    )


# ============================================================
# GENERIC HELPERS
# ============================================================


def first_existing(
    dictionary,
    names,
    default=None,
):
    """
    Return the first existing non-None field.
    """

    if not isinstance(
        dictionary,
        dict,
    ):
        return default

    for name in names:
        if name in dictionary:
            value = dictionary[name]

            if value is not None:
                return value

    return default


def safe_float(value):
    try:
        return float(value)
    except (
        TypeError,
        ValueError,
    ):
        return None


def safe_filename(text):
    """
    Make filesystem-safe filename.
    """

    text = str(text)

    text = re.sub(
        r"[^a-zA-Z0-9._-]+",
        "_",
        text,
    )

    text = re.sub(
        r"_+",
        "_",
        text,
    )

    return text.strip(
        "_."
    )


# ============================================================
# SCENE METADATA
# ============================================================


def get_mode(scene):
    return first_existing(
        scene,
        (
            "mode",
            "generation_mode",
            "render_mode",
            "variation_mode",
        ),
        "unknown_mode",
    )


def get_size_variation(scene):
    return first_existing(
        scene,
        (
            "size_variation",
            "size_variant",
            "size_variant_name",
            "variation",
            "size",
        ),
        "unknown_size",
    )


def get_configuration(
    scene,
    fallback=None,
):
    value = first_existing(
        scene,
        (
            "configuration",
            "configuration_key",
            "configuration_id",
        ),
        fallback,
    )

    if isinstance(
        value,
        int,
    ):
        return f"config_{value:03d}"

    return str(value)


def get_scene_id(
    scene,
    fallback=None,
):
    return str(
        first_existing(
            scene,
            (
                "scene_id",
                "id",
                "name",
            ),
            fallback,
        )
    )


def get_description(
    scene,
):
    return first_existing(
        scene,
        (
            "description",
        ),
        "",
    )


# ============================================================
# SCENE IMAGE
# ============================================================


def find_scene_image(
    scenes_root,
    scene_id,
    scene=None,
):
    """
    Find scene image.

    First tries:

        scene["image"]

    and other path fields.

    Then:

        scenes/images/<scene_id>.*
    """

    scenes_root = Path(
        scenes_root
    )

    images_root = (
        scenes_root
        / "images"
    )

    # --------------------------------------------------------
    # Path from result
    # --------------------------------------------------------

    if scene is not None:

        image_value = first_existing(
            scene,
            (
                "image",
                "image_path",
                "path",
                "source_image",
            ),
        )

        if image_value:

            image_path = Path(
                image_value
            )

            if image_path.exists():
                return image_path

            candidate = (
                scenes_root
                / image_path
            )

            if candidate.exists():
                return candidate

    # --------------------------------------------------------
    # Standard scene image
    # --------------------------------------------------------

    for extension in IMAGE_EXTENSIONS:

        candidate = (
            images_root
            / f"{scene_id}"
            f"{extension}"
        )

        if candidate.exists():
            return candidate

    raise RuntimeError(
        "Could not find image for scene "
        f"'{scene_id}' in {images_root}"
    )


# ============================================================
# SCENE ITERATION
# ============================================================


def iter_scenes(data):
    """
    Find scene records in several possible
    result structures.

    Supports:

        configurations
            config_001
                scenes
                    scene_001
    """

    if not isinstance(
        data,
        dict,
    ):
        raise RuntimeError(
            "Results root must be a dictionary."
        )

    # --------------------------------------------------------
    # Standard structure
    # --------------------------------------------------------

    configurations = data.get(
        "configurations"
    )

    if isinstance(
        configurations,
        dict,
    ):

        for (
            configuration_key,
            configuration,
        ) in configurations.items():

            if not isinstance(
                configuration,
                dict,
            ):
                continue

            scenes = configuration.get(
                "scenes",
                {},
            )

            if not isinstance(
                scenes,
                dict,
            ):
                continue

            for (
                scene_id,
                scene,
            ) in scenes.items():

                if not isinstance(
                    scene,
                    dict,
                ):
                    continue

                yield (
                    str(configuration_key),
                    str(scene_id),
                    scene,
                )

        return

    # --------------------------------------------------------
    # Direct scenes
    # --------------------------------------------------------

    scenes = data.get(
        "scenes"
    )

    if isinstance(
        scenes,
        dict,
    ):

        for (
            scene_id,
            scene,
        ) in scenes.items():

            if not isinstance(
                scene,
                dict,
            ):
                continue

            configuration_key = (
                get_configuration(
                    scene
                )
            )

            yield (
                configuration_key,
                str(scene_id),
                scene,
            )

        return

    raise RuntimeError(
        "Could not find scenes in results."
    )


# ============================================================
# OVERLAP DATA
# ============================================================


def get_overlap_data(
    scene,
):
    """
    Find overlap data.

    Actual preparation script stores overlap
    regions in:

        scene["overlap_parts"]
    """

    names = (
        "overlap_parts",
        "overlap",
        "overlaps",
        "overlap_cells",
        "overlap_embeddings",
        "overlap_results",
    )

    return first_existing(
        scene,
        names,
    )


# ============================================================
# CELL NORMALIZATION
# ============================================================


def normalize_cells(
    data,
):
    """
    Convert various possible overlap structures
    into a list of dictionaries.
    """

    if data is None:
        return []

    # --------------------------------------------------------
    # Dictionary of cells
    # --------------------------------------------------------

    if isinstance(
        data,
        dict,
    ):

        nested = first_existing(
            data,
            (
                "cells",
                "parts",
                "regions",
                "items",
                "results",
            ),
        )

        if nested is not None:
            return normalize_cells(
                nested
            )

        result = []

        for key, value in data.items():

            if not isinstance(
                value,
                dict,
            ):
                continue

            cell = dict(
                value
            )

            cell.setdefault(
                "id",
                key,
            )

            result.append(
                cell
            )

        return result

    # --------------------------------------------------------
    # List
    # --------------------------------------------------------

    if isinstance(
        data,
        list,
    ):

        result = []

        for index, value in enumerate(
            data
        ):

            if not isinstance(
                value,
                dict,
            ):
                continue

            cell = dict(
                value
            )

            cell.setdefault(
                "id",
                index,
            )

            result.append(
                cell
            )

        return result

    return []


# ============================================================
# CELL BOUNDING BOX
# ============================================================


def get_bbox(
    cell,
):
    """
    Extract bounding box.

    Supports:

        x, y, width, height

    and:

        left, top, right, bottom

    and:

        bbox = [x, y, w, h]

    and:

        bbox = {
            x, y, width, height
        }
    """

    # --------------------------------------------------------
    # Explicit x/y/w/h
    # --------------------------------------------------------

    x = first_existing(
        cell,
        (
            "x",
            "left",
            "x1",
        ),
    )

    y = first_existing(
        cell,
        (
            "y",
            "top",
            "y1",
        ),
    )

    width = first_existing(
        cell,
        (
            "width",
            "w",
        ),
    )

    height = first_existing(
        cell,
        (
            "height",
            "h",
        ),
    )

    if (
        x is not None
        and y is not None
        and width is not None
        and height is not None
    ):

        return (
            float(x),
            float(y),
            float(width),
            float(height),
        )

    # --------------------------------------------------------
    # left/top/right/bottom
    # --------------------------------------------------------

    left = first_existing(
        cell,
        (
            "left",
            "x1",
        ),
    )

    top = first_existing(
        cell,
        (
            "top",
            "y1",
        ),
    )

    right = first_existing(
        cell,
        (
            "right",
            "x2",
        ),
    )

    bottom = first_existing(
        cell,
        (
            "bottom",
            "y2",
        ),
    )

    if (
        left is not None
        and top is not None
        and right is not None
        and bottom is not None
    ):

        return (
            float(left),
            float(top),
            float(right) - float(left),
            float(bottom) - float(top),
        )

    # --------------------------------------------------------
    # bbox
    # --------------------------------------------------------

    bbox = first_existing(
        cell,
        (
            "bbox",
            "box",
            "rect",
            "rectangle",
        ),
    )

    if isinstance(
        bbox,
        (list, tuple),
    ) and len(bbox) >= 4:

        return (
            float(bbox[0]),
            float(bbox[1]),
            float(bbox[2]),
            float(bbox[3]),
        )

    if isinstance(
        bbox,
        dict,
    ):

        bx = first_existing(
            bbox,
            (
                "x",
                "left",
            ),
        )

        by = first_existing(
            bbox,
            (
                "y",
                "top",
            ),
        )

        bw = first_existing(
            bbox,
            (
                "width",
                "w",
            ),
        )

        bh = first_existing(
            bbox,
            (
                "height",
                "h",
            ),
        )

        if (
            bx is not None
            and by is not None
            and bw is not None
            and bh is not None
        ):

            return (
                float(bx),
                float(by),
                float(bw),
                float(bh),
            )

    return None


# ============================================================
# SIMILARITY EXTRACTION
# ============================================================


def get_similarity_container(
    cell,
):
    """
    Find similarity dictionary for an overlap cell.

    Actual structure:

        cell["similarities"]
    """

    similarities = first_existing(
        cell,
        (
            "similarities",
            "similarity",
            "scores",
            "results",
        ),
    )

    if isinstance(
        similarities,
        dict,
    ):
        return similarities

    return cell


def get_similarity(
    cell,
    query,
    metric,
):
    """
    Get cosine or modified similarity for
    an overlap region.
    """

    similarities = (
        get_similarity_container(
            cell
        )
    )

    if not isinstance(
        similarities,
        dict,
    ):
        return None

    # --------------------------------------------------------
    # Standard nested query structure
    # --------------------------------------------------------

    query_result = (
        similarities.get(
            query
        )
    )

    if isinstance(
        query_result,
        dict,
    ):

        if metric == "cosine":

            value = first_existing(
                query_result,
                (
                    "cosine",
                    "cosine_similarity",
                ),
            )

        else:

            value = first_existing(
                query_result,
                (
                    "modified_similarity",
                    "modified",
                ),
            )

        value = safe_float(
            value
        )

        if value is not None:
            return value

    # --------------------------------------------------------
    # Direct field variants
    # --------------------------------------------------------

    if metric == "cosine":

        possible_names = [
            f"{query}_cosine",
            f"{query}_cosine_similarity",
        ]

    else:

        possible_names = [
            f"{query}_modified_similarity",
            f"{query}_modified",
        ]

    for name in possible_names:

        if name in cell:

            value = safe_float(
                cell[name]
            )

            if value is not None:
                return value

    # --------------------------------------------------------
    # Direct generic fields
    # --------------------------------------------------------

    if metric == "cosine":

        value = safe_float(
            cell.get(
                "cosine"
            )
        )

    else:

        value = safe_float(
            cell.get(
                "modified_similarity"
            )
        )

    return value


# ============================================================
# WHOLE SCENE SIMILARITY
# ============================================================


def get_scene_similarity_container(
    scene,
):
    """
    Extract the scene-level similarity dictionary.

    Primary structure:

        scene["full_image"]["similarities"]
    """

    # ========================================================
    # PRIMARY
    # ========================================================

    full_image = scene.get(
        "full_image"
    )

    if isinstance(
        full_image,
        dict,
    ):

        similarities = first_existing(
            full_image,
            (
                "similarities",
                "similarity",
                "scores",
                "results",
            ),
        )

        if isinstance(
            similarities,
            dict,
        ):
            return similarities

    # ========================================================
    # FALLBACK
    # ========================================================

    similarities = first_existing(
        scene,
        (
            "similarities",
            "similarity",
            "scores",
            "results",
        ),
    )

    if isinstance(
        similarities,
        dict,
    ):
        return similarities

    return None


def get_scene_similarity(
    scene,
    query,
    metric,
):
    """
    Extract similarity for the complete/original scene.
    """

    similarities = (
        get_scene_similarity_container(
            scene
        )
    )

    # ========================================================
    # Standard structure
    # ========================================================

    if isinstance(
        similarities,
        dict,
    ):

        query_result = (
            similarities.get(
                query
            )
        )

        if isinstance(
            query_result,
            dict,
        ):

            if metric == "cosine":

                value = first_existing(
                    query_result,
                    (
                        "cosine",
                        "cosine_similarity",
                    ),
                )

            else:

                value = first_existing(
                    query_result,
                    (
                        "modified_similarity",
                        "modified",
                    ),
                )

            value = safe_float(
                value
            )

            if value is not None:
                return value

        # ----------------------------------------------------
        # Scalar query
        # ----------------------------------------------------

        if query in similarities:

            value = safe_float(
                similarities[query]
            )

            if value is not None:
                return value

    # ========================================================
    # Direct fields in scene
    # ========================================================

    if metric == "cosine":

        possible_names = [
            f"{query}_cosine",
            f"{query}_cosine_similarity",
        ]

    else:

        possible_names = [
            f"{query}_modified_similarity",
            f"{query}_modified",
        ]

    for name in possible_names:

        if name in scene:

            value = safe_float(
                scene[name]
            )

            if value is not None:
                return value

    # ========================================================
    # Direct fields in full_image
    # ========================================================

    full_image = scene.get(
        "full_image"
    )

    if isinstance(
        full_image,
        dict,
    ):

        if metric == "cosine":

            possible_names = [
                f"{query}_cosine",
                f"{query}_cosine_similarity",
            ]

        else:

            possible_names = [
                f"{query}_modified_similarity",
                f"{query}_modified",
            ]

        for name in possible_names:

            if name in full_image:

                value = safe_float(
                    full_image[name]
                )

                if value is not None:
                    return value

        # ----------------------------------------------------
        # Generic fields
        # ----------------------------------------------------

        if metric == "cosine":

            possible_names = [
                "cosine",
                "cosine_similarity",
            ]

        else:

            possible_names = [
                "modified_similarity",
                "modified",
            ]

        for name in possible_names:

            value = safe_float(
                full_image.get(
                    name
                )
            )

            if value is not None:
                return value

    # ========================================================
    # Alternative generic scene-level naming
    # ========================================================

    if metric == "cosine":

        possible_names = [
            "cosine",
            "cosine_similarity",
        ]

    else:

        possible_names = [
            "modified_similarity",
            "modified",
        ]

    for name in possible_names:

        value = safe_float(
            scene.get(
                name
            )
        )

        if value is not None:
            return value

    return None


# ============================================================
# QUERY DISCOVERY
# ============================================================


def discover_queries(
    scene,
):
    """
    Discover available similarity queries.
    """

    queries = set()

    # ========================================================
    # PRIMARY
    # ========================================================

    similarities = (
        get_scene_similarity_container(
            scene
        )
    )

    if isinstance(
        similarities,
        dict,
    ):

        for key, value in (
            similarities.items()
        ):

            if not isinstance(
                value,
                dict,
            ):
                continue

            if (
                "cosine" in value
                or "cosine_similarity" in value
                or "modified_similarity" in value
                or "modified" in value
            ):

                queries.add(
                    str(key)
                )

    # ========================================================
    # FALLBACK
    # ========================================================

    if not queries:

        overlap_data = get_overlap_data(
            scene
        )

        cells = normalize_cells(
            overlap_data
        )

        for cell in cells:

            similarities = (
                get_similarity_container(
                    cell
                )
            )

            if not isinstance(
                similarities,
                dict,
            ):
                continue

            for key, value in (
                similarities.items()
            ):

                if not isinstance(
                    value,
                    dict,
                ):
                    continue

                if (
                    "cosine" in value
                    or "cosine_similarity" in value
                    or "modified_similarity" in value
                    or "modified" in value
                ):

                    queries.add(
                        str(key)
                    )

    return sorted(
        queries
    )


# ============================================================
# COLOR MAPPING
# ============================================================


def get_modified_similarity_color(
    modified_similarity,
    alpha,
):
    """
    Convert modified similarity to a color.

    Mapping:

        0.0 -> blue
        0.5 -> yellow
        1.0 -> red

    Returns None if similarity is unavailable.
    """

    if modified_similarity is None:
        return None

    value = safe_float(
        modified_similarity
    )

    if value is None:
        return None

    value = max(
        MODIFIED_SIMILARITY_MIN,
        min(
            MODIFIED_SIMILARITY_MAX,
            value,
        ),
    )

    norm = mcolors.Normalize(
        vmin=MODIFIED_SIMILARITY_MIN,
        vmax=MODIFIED_SIMILARITY_MAX,
    )

    cmap = plt.get_cmap(
        COLOR_MAP_NAME
    )

    rgba = cmap(
        norm(value)
    )

    return (
        rgba[0],
        rgba[1],
        rgba[2],
        alpha,
    )


def create_similarity_colorbar(
    fig,
    ax,
):
    """
    Add a colorbar directly to the right
    of the PARTS panel.
    """

    norm = mcolors.Normalize(
        vmin=MODIFIED_SIMILARITY_MIN,
        vmax=MODIFIED_SIMILARITY_MAX,
    )

    cmap = plt.get_cmap(
        COLOR_MAP_NAME
    )

    scalar_mappable = plt.cm.ScalarMappable(
        norm=norm,
        cmap=cmap,
    )

    scalar_mappable.set_array(
        []
    )

    colorbar = fig.colorbar(
        scalar_mappable,
        ax=ax,
        fraction=0.035,
        pad=0.025,
    )

    colorbar.set_label(
        "Relative Relevance Score",
        fontsize=11,
        fontweight="bold",
    )

    colorbar.set_ticks(
        [
            0.0,
            0.25,
            0.50,
            0.75,
            1.0,
        ]
    )

    return colorbar


# ============================================================
# DRAW OVERLAP CELL
# ============================================================


def draw_overlap_cell(
    ax,
    cell,
    cell_index,
    query,
    alpha,
    linewidth,
    fontsize,
):
    """
    Draw one overlap region.
    """

    bbox = get_bbox(
        cell
    )

    if bbox is None:

        warning(
            f"Overlap cell O{cell_index} "
            "does not contain a valid bbox."
        )

        return

    x, y, width, height = bbox

    cosine = get_similarity(
        cell,
        query,
        "cosine",
    )

    modified = get_similarity(
        cell,
        query,
        "modified",
    )

    # --------------------------------------------------------
    # Color
    # --------------------------------------------------------

    facecolor = (
        get_modified_similarity_color(
            modified,
            alpha,
        )
    )

    if facecolor is None:

        facecolor = (
            0.3,
            0.3,
            0.3,
            alpha,
        )

    # --------------------------------------------------------
    # Rectangle
    # --------------------------------------------------------

    rectangle = patches.Rectangle(
        (
            x,
            y,
        ),
        width,
        height,
        facecolor=facecolor,
        edgecolor="white",
        alpha=None,
        linewidth=linewidth,
        linestyle="-",
    )

    ax.add_patch(
        rectangle
    )

    # --------------------------------------------------------
    # Text
    # --------------------------------------------------------

    cosine_text = (
        f"{cosine:.4f}"
        if cosine is not None
        else "N/A"
    )

    modified_text = (
        f"{modified:.4f}"
        if modified is not None
        else "N/A"
    )

    text = (
        f"Segment {cell_index}\n"
        f"Cosine: {cosine_text}\n"
        f"Relevance: {modified_text}"
    )

    center_x = (
        x + width / 2.0
    )

    center_y = (
        y + height / 2.0
    )

    ax.text(
        center_x,
        center_y,
        text,
        ha="center",
        va="center",
        fontsize=fontsize,
        fontweight="bold",
        color="white",
        bbox=dict(
            boxstyle="round,pad=0.35",
            facecolor="black",
            alpha=0.70,
            edgecolor="none",
        ),
    )


# ============================================================
# DRAW ORIGINAL PANEL
# ============================================================


def draw_original_panel(
    ax,
    image,
    scene,
    query,
    fontsize,
):
    """
    Draw the original scene.
    """

    ax.imshow(
        image
    )

    height, width = (
        image.shape[:2]
    )

    ax.set_xlim(
        0,
        width,
    )

    ax.set_ylim(
        height,
        0,
    )

    ax.set_aspect(
        "equal"
    )

    ax.axis(
        "off"
    )

    # ========================================================
    # Whole-image similarity
    # ========================================================

    cosine = get_scene_similarity(
        scene,
        query,
        "cosine",
    )

    modified = get_scene_similarity(
        scene,
        query,
        "modified",
    )

    cosine_text = (
        f"{cosine:.4f}"
        if cosine is not None
        else "N/A"
    )

    modified_text = (
        f"{modified:.4f}"
        if modified is not None
        else "N/A"
    )

    similarity_text = (
        f"Cosine: {cosine_text}\n"
        f"Relevance: {modified_text}"
    )

    # ========================================================
    # Center label
    # ========================================================

    center_x = (
        width / 2.0
    )

    center_y = (
        height / 2.0
    )

    label_color = (
        get_modified_similarity_color(
            modified,
            0.90,
        )
    )

    if label_color is None:

        label_color = (
            0.0,
            0.0,
            0.0,
            0.80,
        )

    ax.text(
        center_x,
        center_y,
        similarity_text,
        ha="center",
        va="center",
        fontsize=fontsize + 3,
        fontweight="bold",
        color="white",
        bbox=dict(
            boxstyle="round,pad=0.60",
            facecolor=label_color,
            edgecolor="white",
            linewidth=2.0,
        ),
    )


# ============================================================
# DRAW PARTS PANEL
# ============================================================


def draw_overlap_panel(
    ax,
    image,
    overlap_cells,
    query,
    fontsize,
    linewidth,
    alpha,
):
    """
    Draw original image divided into PARTS.
    """

    ax.imshow(
        image
    )

    height, width = (
        image.shape[:2]
    )

    for index, cell in enumerate(
        overlap_cells,
        start=1,
    ):

        draw_overlap_cell(
            ax=ax,
            cell=cell,
            cell_index=index,
            query=query,
            alpha=alpha,
            linewidth=linewidth,
            fontsize=fontsize,
        )

    ax.set_xlim(
        0,
        width,
    )

    ax.set_ylim(
        height,
        0,
    )

    ax.set_aspect(
        "equal"
    )

    ax.axis(
        "off"
    )


# ============================================================
# PLOT
# ============================================================


def plot_scene_similarity(
    image,
    scene,
    configuration_key,
    scene_id,
    query,
    output_path,
    dpi,
    alpha,
    linewidth,
    fontsize,
):
    """
    Create one visualization for one query.

    Layout:

        ORIGINAL
        ┌──────────────────────────────┐
        │                              │
        │          original            │
        │           image              │
        │                              │
        └──────────────────────────────┘

        PARTS
        ┌──────────────────────────────┐  ┌─────┐
        │                              │  │     │
        │       overlap heatmap        │  │color│
        │                              │  │ bar │
        └──────────────────────────────┘  └─────┘

    IMPORTANT:
        The original image and the PARTS image use exactly
        the same display dimensions and are positioned
        directly one above the other.
    """

    # --------------------------------------------------------
    # OVERLAP
    # --------------------------------------------------------

    overlap_data = get_overlap_data(
        scene
    )

    overlap_cells = normalize_cells(
        overlap_data
    )

    if not overlap_cells:

        warning(
            f"No overlap cells for "
            f"{configuration_key}/{scene_id}"
        )

        return False

    image_np = np.asarray(
        image
    )

    mode = get_mode(
        scene
    )

    size_variation = (
        get_size_variation(
            scene
        )
    )

    description = (
        get_description(
            scene
        )
    )

    # --------------------------------------------------------
    # IMAGE SIZE
    # --------------------------------------------------------

    image_height, image_width = (
        image_np.shape[:2]
    )

    # --------------------------------------------------------
    # FIGURE
    #
    # The two image panels have exactly the same physical
    # size and are placed directly one above another.
    #
    # The colorbar occupies a separate narrow column on
    # the right.
    # --------------------------------------------------------

    figure_width = 12.0

    image_display_width = 10.0

    # Preserve the original image aspect ratio.
    image_display_height = (
        image_display_width
        * image_height
        / image_width
    )

    title_height = 1.35

    vertical_gap = 0.10

    colorbar_width = 0.30

    right_gap = 0.25

    bottom_margin = 0.20

    top_margin = 0.25

    figure_height = (
        title_height
        + image_display_height * 2.0
        + vertical_gap
        + bottom_margin
        + top_margin
    )

    fig = plt.figure(
        figsize=(
            figure_width,
            figure_height,
        ),
        dpi=dpi,
    )

    # --------------------------------------------------------
    # AXES POSITIONS
    #
    # Coordinates are in figure-relative units.
    #
    # Both image axes have:
    #
    #     exactly the same width
    #     exactly the same height
    #     exactly the same X position
    #
    # Therefore the images are perfectly aligned.
    # --------------------------------------------------------

    image_left = (
        0.035
    )

    image_right = (
        0.035
        + 0.80
    )

    image_axis_width = (
        image_right
        - image_left
    )

    colorbar_left = (
        image_right
        + 0.025
    )

    colorbar_width_norm = (
        0.025
    )

    # The total vertical space for the two images.
    total_image_height_norm = (
        0.84
    )

    gap_norm = (
        0.012
    )

    single_image_height_norm = (
        (
            total_image_height_norm
            - gap_norm
        )
        / 2.0
    )

    # Bottom image: PARTS
    parts_bottom = (
        0.045
    )

    # Top image: ORIGINAL
    original_bottom = (
        parts_bottom
        + single_image_height_norm
        + gap_norm
    )

    # --------------------------------------------------------
    # CREATE AXES
    # --------------------------------------------------------

    original_ax = fig.add_axes(
        [
            image_left,
            original_bottom,
            image_axis_width,
            single_image_height_norm,
        ]
    )

    overlap_ax = fig.add_axes(
        [
            image_left,
            parts_bottom,
            image_axis_width,
            single_image_height_norm,
        ]
    )

    # --------------------------------------------------------
    # ORIGINAL
    # --------------------------------------------------------

    draw_original_panel(
        ax=original_ax,
        image=image_np,
        scene=scene,
        query=query,
        fontsize=fontsize,
    )

    original_ax.set_title(
        "ORIGINAL",
        fontsize=15,
        fontweight="bold",
        pad=5,
    )

    # --------------------------------------------------------
    # PARTS
    # --------------------------------------------------------

    draw_overlap_panel(
        ax=overlap_ax,
        image=image_np,
        overlap_cells=overlap_cells,
        query=query,
        fontsize=fontsize,
        linewidth=linewidth,
        alpha=alpha,
    )

    overlap_ax.set_title(
        "SEGMENTS",
        fontsize=15,
        fontweight="bold",
        pad=5,
    )

    # --------------------------------------------------------
    # COLORBAR
    #
    # Dedicated axis on the right of PARTS.
    # It is vertically aligned with the PARTS image.
    # --------------------------------------------------------

    colorbar_ax = fig.add_axes(
        [
            colorbar_left,
            parts_bottom,
            colorbar_width_norm,
            single_image_height_norm,
        ]
    )

    norm = mcolors.Normalize(
        vmin=MODIFIED_SIMILARITY_MIN,
        vmax=MODIFIED_SIMILARITY_MAX,
    )

    cmap = plt.get_cmap(
        COLOR_MAP_NAME
    )

    scalar_mappable = plt.cm.ScalarMappable(
        norm=norm,
        cmap=cmap,
    )

    scalar_mappable.set_array(
        []
    )

    colorbar = fig.colorbar(
        scalar_mappable,
        cax=colorbar_ax,
    )

    colorbar.set_label(
        "Relative Relevance Score",
        fontsize=11,
        fontweight="bold",
        labelpad=10,
    )

    colorbar.set_ticks(
        [
            0.0,
            0.25,
            0.50,
            0.75,
            1.0,
        ]
    )

    # --------------------------------------------------------
    # GLOBAL TITLE
    #
    # mode and size are intentionally removed.
    # --------------------------------------------------------

    title_lines = [
        (
            f"{configuration_key} | "
            f"{scene_id}"
        ),
        (
            f"query={query}"
        ),
    ]

    if description:
        title_lines.append(
            f"description: {description}"
        )

    fig.suptitle(
        "\n".join(
            title_lines
        ),
        fontsize=15,
        fontweight="bold",
        x=0.47,
        y=0.985,
        ha="center",
    )

    # --------------------------------------------------------
    # SAVE
    # --------------------------------------------------------

    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    fig.savefig(
        output_path,
        dpi=dpi,
        bbox_inches="tight",
        facecolor="white",
    )

    plt.close(
        fig
    )

    return True


# ============================================================
# SCENE PROCESSING
# ============================================================


def process_scene(
    scenes_root,
    configuration_key,
    scene_id,
    scene,
    output_root,
    dpi,
    alpha,
    linewidth,
    fontsize,
    queries,
):
    """
    Process one scene.
    """

    log(
        f"Processing "
        f"{configuration_key} / "
        f"{scene_id}"
    )

    image_path = find_scene_image(
        scenes_root=scenes_root,
        scene_id=scene_id,
        scene=scene,
    )

    log(
        f"  Image: {image_path}"
    )

    image = Image.open(
        image_path
    ).convert(
        "RGB"
    )

    # --------------------------------------------------------
    # Discover queries
    # --------------------------------------------------------

    discovered_queries = (
        discover_queries(
            scene
        )
    )

    if queries:

        selected_queries = []

        for query in queries:

            if query in discovered_queries:

                selected_queries.append(
                    query
                )

            else:

                warning(
                    f"Query '{query}' "
                    f"not found in "
                    f"{configuration_key}/"
                    f"{scene_id}"
                )

    else:

        selected_queries = (
            discovered_queries
        )

    if not selected_queries:

        warning(
            f"No similarity queries found "
            f"for {configuration_key}/"
            f"{scene_id}"
        )

        return 0

    scene_output = (
        output_root
        / safe_filename(
            configuration_key
        )
        / safe_filename(
            scene_id
        )
    )

    generated = 0

    # --------------------------------------------------------
    # One image per query
    # --------------------------------------------------------

    for query in selected_queries:

        # ----------------------------------------------------
        # Log whole-scene similarity
        # ----------------------------------------------------

        cosine = get_scene_similarity(
            scene,
            query,
            "cosine",
        )

        modified = get_scene_similarity(
            scene,
            query,
            "modified",
        )

        cosine_text = (
            f"{cosine:.6f}"
            if cosine is not None
            else "N/A"
        )

        modified_text = (
            f"{modified:.6f}"
            if modified is not None
            else "N/A"
        )

        log(
            f"  Query: '{query}'"
        )

        log(
            f"    Whole image cosine: "
            f"{cosine_text}"
        )

        log(
            f"    Whole image modified: "
            f"{modified_text}"
        )

        # ----------------------------------------------------
        # Output
        # ----------------------------------------------------

        filename = (
            f"{safe_filename(query)}.png"
        )

        output_path = (
            scene_output
            / filename
        )

        success = (
            plot_scene_similarity(
                image=image,
                scene=scene,
                configuration_key=(
                    configuration_key
                ),
                scene_id=scene_id,
                query=query,
                output_path=(
                    output_path
                ),
                dpi=dpi,
                alpha=alpha,
                linewidth=linewidth,
                fontsize=fontsize,
            )
        )

        if success:

            generated += 1

            log(
                f"  Saved: "
                f"{output_path}"
            )

    return generated


# ============================================================
# ARGUMENTS
# ============================================================


def parse_args():

    parser = argparse.ArgumentParser(
        description=(
            "Visualize cosine and modified "
            "similarity for original scenes "
            "and overlap image regions."
        ),
    )

    parser.add_argument(
        "--results",
        type=Path,
        default=Path(
            DEFAULT_RESULTS
        ),
        help=(
            "Testing results PKL/JSON."
        ),
    )

    parser.add_argument(
        "--scenes",
        type=Path,
        default=Path(
            DEFAULT_SCENES
        ),
        help=(
            "scene_dataset root. "
            "Expected: "
            "scenes/images/*.png"
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            DEFAULT_OUTPUT_DIR
        ),
        help=(
            "Output directory."
        ),
    )

    parser.add_argument(
        "--query",
        action="append",
        default=None,
        help=(
            "Query to visualize. "
            "Can be specified multiple times. "
            "If omitted, all queries found "
            "in the results are visualized."
        ),
    )

    parser.add_argument(
        "--dpi",
        type=int,
        default=DEFAULT_DPI,
        help=(
            "Output image DPI."
        ),
    )

    parser.add_argument(
        "--alpha",
        type=float,
        default=DEFAULT_ALPHA,
        help=(
            "Transparency of PARTS heatmap. "
            "Lower value makes the original "
            "image more visible."
        ),
    )

    parser.add_argument(
        "--linewidth",
        type=float,
        default=DEFAULT_LINE_WIDTH,
        help=(
            "Overlap boundary width."
        ),
    )

    parser.add_argument(
        "--fontsize",
        type=float,
        default=DEFAULT_FONT_SIZE,
        help=(
            "Similarity label font size."
        ),
    )

    return parser.parse_args()


# ============================================================
# MAIN
# ============================================================


def main():

    args = parse_args()

    results_path = (
        args.results
    )

    scenes_root = (
        args.scenes
    )

    output_root = (
        args.output
    )

    # --------------------------------------------------------
    # Load
    # --------------------------------------------------------

    data = load_results(
        results_path
    )

    # --------------------------------------------------------
    # Iterate
    # --------------------------------------------------------

    scenes = list(
        iter_scenes(
            data
        )
    )

    if not scenes:

        raise RuntimeError(
            "No scenes found in results."
        )

    log(
        f"Scenes found: "
        f"{len(scenes)}"
    )

    total_generated = 0

    failed = 0

    # --------------------------------------------------------
    # Process
    # --------------------------------------------------------

    for (
        configuration_key,
        scene_id,
        scene,
    ) in scenes:

        try:

            generated = (
                process_scene(
                    scenes_root=(
                        scenes_root
                    ),
                    configuration_key=(
                        configuration_key
                    ),
                    scene_id=scene_id,
                    scene=scene,
                    output_root=(
                        output_root
                    ),
                    dpi=args.dpi,
                    alpha=args.alpha,
                    linewidth=args.linewidth,
                    fontsize=args.fontsize,
                    queries=args.query,
                )
            )

            total_generated += (
                generated
            )

        except Exception as exc:

            failed += 1

            warning(
                f"Failed to process "
                f"{configuration_key}/"
                f"{scene_id}: {exc}"
            )

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------

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
        f"Scenes: "
        f"{len(scenes)}"
    )

    print(
        f"Visualizations generated: "
        f"{total_generated}"
    )

    print(
        f"Scenes failed: "
        f"{failed}"
    )

    print(
        f"Output directory: "
        f"{output_root}"
    )

    print(
        "=" * 70
    )


# ============================================================
# ENTRY POINT
# ============================================================


if __name__ == "__main__":
    main()

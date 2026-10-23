#!/usr/bin/env python3

import argparse
import json
import math
import random
from itertools import product
from pathlib import Path

from PIL import Image


# ============================================================
# CONSTANTS
# ============================================================

DEFAULT_FOREGROUND = Path(
    "./scene_dataset/foreground"
)

DEFAULT_OUTPUT = Path(
    "./scene_dataset/scenes"
)

DEFAULT_CLASSES = [
    "dog",
    "cat",
    "car",
    "motorcycle",
]

IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
}

# Exactly two objects per scene.
OBJECTS_PER_SCENE = 2

# Use exactly the first four images of every class.
IMAGES_PER_CLASS = 4

# Transparent padding around the final scene.
DEFAULT_PADDING = 2

# Minimum gap between objects.
DEFAULT_GAP = 2

DEFAULT_MAX_ATTEMPTS = 300

# Final square side for mode2 is a multiple of this value.
MODE2_MULTIPLE = 224

# IMPORTANT:
# Only these five scale combinations are generated.
#
# s1x1
# s1x2
# s1x4
# s2x1
# s4x1
#
# First value = scale of the first image.
# Second value = scale of the second image.
SIZE_VARIATIONS = [
    (1, 1),
    (1, 2),
    (1, 4),
    (2, 1),
    (4, 1),
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
# DATASET
# ============================================================

def find_images(class_directory):
    """
    Find all supported images recursively.

    The result is sorted, so the first four images
    are deterministic.
    """

    class_directory = Path(
        class_directory
    )

    return sorted(
        path
        for path in class_directory.rglob("*")
        if (
            path.is_file()
            and path.suffix.lower()
            in IMAGE_EXTENSIONS
        )
    )


def load_dataset(
    foreground_root,
    classes,
):
    """
    Load exactly the first four images for every class.

    Returns:

        {
            "dog": [
                Path(...),
                Path(...),
                Path(...),
                Path(...),
            ],
            ...
        }
    """

    foreground_root = Path(
        foreground_root
    )

    dataset = {}

    for class_name in classes:

        class_directory = (
            foreground_root
            / class_name
        )

        if not class_directory.exists():
            raise RuntimeError(
                "Class directory does not exist: "
                f"{class_directory}"
            )

        all_images = find_images(
            class_directory
        )

        if len(all_images) < IMAGES_PER_CLASS:
            raise RuntimeError(
                f"Class '{class_name}' contains "
                f"only {len(all_images)} images. "
                f"At least {IMAGES_PER_CLASS} "
                "images are required."
            )

        selected_images = (
            all_images[
                :IMAGES_PER_CLASS
            ]
        )

        dataset[class_name] = (
            selected_images
        )

        log(
            f"Class '{class_name}': "
            f"using first "
            f"{IMAGES_PER_CLASS} images"
        )

        for index, image_path in enumerate(
            selected_images,
            start=1,
        ):
            log(
                f"    [{index}] "
                f"{image_path}"
            )

    return dataset


# ============================================================
# CLASS CONFIGURATIONS
# ============================================================

def generate_class_configurations(
    classes,
    total_objects,
):
    """
    Generate all unordered distributions of
    total_objects among classes.

    For four classes and two objects this produces:

        C(4 + 2 - 1, 2) = 10

    configurations.
    """

    configurations = []

    def recursive(
        class_index,
        remaining,
        current,
    ):

        if class_index == len(classes) - 1:

            class_name = (
                classes[class_index]
            )

            configuration = (
                current.copy()
            )

            configuration[
                class_name
            ] = remaining

            configurations.append(
                configuration
            )

            return

        class_name = (
            classes[class_index]
        )

        for count in range(
            remaining + 1
        ):

            configuration = (
                current.copy()
            )

            configuration[
                class_name
            ] = count

            recursive(
                class_index=(
                    class_index + 1
                ),
                remaining=(
                    remaining - count
                ),
                current=configuration,
            )

    recursive(
        class_index=0,
        remaining=total_objects,
        current={},
    )

    return configurations


# ============================================================
# DESCRIPTION
# ============================================================

NUMBER_WORDS = {
    1: "one",
    2: "two",
    3: "three",
    4: "four",
}


def pluralize_class(
    class_name,
    count,
):
    """
    Simple pluralization.
    """

    if count == 1:
        return class_name

    return f"{class_name}s"


def make_description(
    configuration,
):
    """
    Example:

        {
            "dog": 1,
            "cat": 1,
            "car": 0,
            "motorcycle": 0
        }

    becomes:

        "one dog and one cat"
    """

    parts = []

    for class_name, count in (
        configuration.items()
    ):

        if count <= 0:
            continue

        number = NUMBER_WORDS.get(
            count,
            str(count),
        )

        noun = pluralize_class(
            class_name,
            count,
        )

        parts.append(
            f"{number} {noun}"
        )

    if not parts:
        return ""

    if len(parts) == 1:
        return parts[0]

    if len(parts) == 2:
        return (
            f"{parts[0]} and "
            f"{parts[1]}"
        )

    return (
        ", ".join(
            parts[:-1]
        )
        + " and "
        + parts[-1]
    )


# ============================================================
# IMAGE LOADING
# ============================================================

def load_foreground(
    image_path,
):
    """
    Load foreground as RGBA and crop transparent
    borders.

    The alpha channel is preserved.
    """

    image = Image.open(
        image_path
    ).convert(
        "RGBA"
    )

    alpha = image.getchannel(
        "A"
    )

    bbox = alpha.getbbox()

    if bbox is None:
        raise RuntimeError(
            "Image contains no visible "
            f"foreground: {image_path}"
        )

    image = image.crop(
        bbox
    )

    return image


# ============================================================
# SCALING
# ============================================================

def scale_image(
    image,
    scale,
):
    """
    Scale an image by an explicit coefficient.

    scale=1 -> original size
    scale=2 -> 2x width and 2x height
    scale=4 -> 4x width and 4x height
    """

    if scale == 1:
        return image.copy()

    width = max(
        1,
        int(
            round(
                image.width * scale
            )
        ),
    )

    height = max(
        1,
        int(
            round(
                image.height * scale
            )
        ),
    )

    return image.resize(
        (width, height),
        Image.Resampling.LANCZOS,
    )


# ============================================================
# GEOMETRY
# ============================================================

def rectangles_overlap(
    rectangle_a,
    rectangle_b,
    gap=0,
):
    """
    Check whether two rectangles overlap.

    Rectangle:

        (x, y, width, height)
    """

    ax, ay, aw, ah = rectangle_a
    bx, by, bw, bh = rectangle_b

    return not (
        ax + aw + gap <= bx
        or bx + bw + gap <= ax
        or ay + ah + gap <= by
        or by + bh + gap <= ay
    )


def bounding_box(
    rectangles,
):
    """
    Return bounding box containing all rectangles.

    Returns:

        min_x,
        min_y,
        max_x,
        max_y
    """

    min_x = min(
        rectangle[0]
        for rectangle in rectangles
    )

    min_y = min(
        rectangle[1]
        for rectangle in rectangles
    )

    max_x = max(
        rectangle[0]
        + rectangle[2]
        for rectangle in rectangles
    )

    max_y = max(
        rectangle[1]
        + rectangle[3]
        for rectangle in rectangles
    )

    return (
        min_x,
        min_y,
        max_x,
        max_y,
    )


def bounding_area(
    rectangles,
):
    """
    Area of the bounding rectangle.
    """

    (
        min_x,
        min_y,
        max_x,
        max_y,
    ) = bounding_box(
        rectangles
    )

    return (
        max_x - min_x
    ) * (
        max_y - min_y
    )


# ============================================================
# COMPACT PACKING
# ============================================================

def candidate_positions(
    width,
    height,
    placed,
    gap,
    search_range,
):
    """
    Generate candidate positions close to
    already placed objects.
    """

    candidates = []

    if not placed:

        candidates.append(
            (0, 0)
        )

    else:

        for (
            x,
            y,
            w,
            h,
        ) in placed:

            candidates.extend(
                [
                    (
                        x + w + gap,
                        y,
                    ),

                    (
                        x - width - gap,
                        y,
                    ),

                    (
                        x,
                        y + h + gap,
                    ),

                    (
                        x,
                        y - height - gap,
                    ),

                    (
                        x + w + gap,
                        y + h + gap,
                    ),

                    (
                        x - width - gap,
                        y + h + gap,
                    ),

                    (
                        x + w + gap,
                        y - height - gap,
                    ),

                    (
                        x - width - gap,
                        y - height - gap,
                    ),
                ]
            )

    # Additional randomized candidates.
    for _ in range(50):

        candidates.append(
            (
                random.randint(
                    -search_range,
                    search_range,
                ),
                random.randint(
                    -search_range,
                    search_range,
                ),
            )
        )

    return candidates


def pack_objects(
    objects,
    gap,
    max_attempts,
):
    """
    Find a compact non-overlapping layout.

    The algorithm tries multiple randomized
    object orders and keeps the layout with
    the smallest bounding rectangle.
    """

    if not objects:
        return []

    best_layout = None
    best_area = None

    for _ in range(
        max_attempts
    ):

        order = objects.copy()

        random.shuffle(
            order
        )

        placed_rectangles = []

        total_area = sum(
            (
                obj["image"].width
                * obj["image"].height
            )
            for obj in order
        )

        max_dimension = max(
            max(
                obj["image"].width,
                obj["image"].height,
            )
            for obj in order
        )

        search_range = int(
            math.sqrt(
                max(
                    total_area,
                    1,
                )
            )
            + max_dimension * 2
            + 100
        )

        current_layout = []

        failed = False

        for obj in order:

            image = obj["image"]

            width = image.width
            height = image.height

            candidates = (
                candidate_positions(
                    width=width,
                    height=height,
                    placed=(
                        placed_rectangles
                    ),
                    gap=gap,
                    search_range=(
                        search_range
                    ),
                )
            )

            best_position = None
            best_position_score = None

            for x, y in candidates:

                rectangle = (
                    x,
                    y,
                    width,
                    height,
                )

                collision = False

                for other_rectangle in (
                    placed_rectangles
                ):

                    if rectangles_overlap(
                        rectangle,
                        other_rectangle,
                        gap=gap,
                    ):
                        collision = True
                        break

                if collision:
                    continue

                test_rectangles = (
                    placed_rectangles
                    + [rectangle]
                )

                score = bounding_area(
                    test_rectangles
                )

                if (
                    best_position_score
                    is None
                    or score
                    < best_position_score
                ):

                    best_position_score = (
                        score
                    )

                    best_position = (
                        x,
                        y,
                    )

            if best_position is None:

                failed = True
                break

            x, y = best_position

            rectangle = (
                x,
                y,
                width,
                height,
            )

            placed_rectangles.append(
                rectangle
            )

            obj_copy = obj.copy()

            obj_copy["_x"] = x
            obj_copy["_y"] = y

            current_layout.append(
                obj_copy
            )

        if failed:
            continue

        area = bounding_area(
            placed_rectangles
        )

        if (
            best_area is None
            or area < best_area
        ):

            best_area = area

            best_layout = (
                current_layout
            )

    if best_layout is None:
        raise RuntimeError(
            "Unable to find a valid "
            "non-overlapping layout."
        )

    return best_layout


# ============================================================
# MODE 1
# ============================================================

def create_scene_mode1(
    objects,
    padding,
    gap,
    max_attempts,
):
    """
    Mode 1.

    Objects are scaled according to their
    individual scale coefficients and then
    tightly packed.

    Final dimensions are determined by the
    resulting bounding box.
    """

    layout = pack_objects(
        objects=objects,
        gap=gap,
        max_attempts=max_attempts,
    )

    rectangles = []

    for obj in layout:

        rectangles.append(
            (
                obj["_x"],
                obj["_y"],
                obj["image"].width,
                obj["image"].height,
            )
        )

    (
        min_x,
        min_y,
        max_x,
        max_y,
    ) = bounding_box(
        rectangles
    )

    shift_x = (
        padding
        - min_x
    )

    shift_y = (
        padding
        - min_y
    )

    scene_width = (
        max_x
        - min_x
        + padding * 2
    )

    scene_height = (
        max_y
        - min_y
        + padding * 2
    )

    scene = Image.new(
        "RGBA",
        (
            scene_width,
            scene_height,
        ),
        (
            0,
            0,
            0,
            0,
        ),
    )

    placements = []

    for obj in layout:

        x = (
            obj["_x"]
            + shift_x
        )

        y = (
            obj["_y"]
            + shift_y
        )

        image = obj["image"]

        scene.alpha_composite(
            image,
            (
                x,
                y,
            ),
        )

        placements.append(
            {
                "class": obj["class"],

                "source": str(
                    obj["path"]
                ),

                "scale": float(
                    obj["scale"]
                ),

                "x": int(x),

                "y": int(y),

                "width": int(
                    image.width
                ),

                "height": int(
                    image.height
                ),
            }
        )

    return (
        scene,
        placements,
    )


# ============================================================
# MODE 2
# ============================================================

def round_up_to_multiple(
    value,
    multiple,
):
    """
    Round value up to the next multiple.
    """

    return int(
        math.ceil(
            value / multiple
        )
        * multiple
    )


def create_scene_mode2(
    objects,
    padding,
    gap,
    max_attempts,
):
    """
    Mode 2.

    First the two scaled objects are packed
    tightly.

    Then the resulting scene is placed into
    a square whose side is the smallest multiple
    of 224 that can contain the whole scene.

    The objects are centered in that square.
    """

    layout = pack_objects(
        objects=objects,
        gap=gap,
        max_attempts=max_attempts,
    )

    rectangles = []

    for obj in layout:

        rectangles.append(
            (
                obj["_x"],
                obj["_y"],
                obj["image"].width,
                obj["image"].height,
            )
        )

    (
        min_x,
        min_y,
        max_x,
        max_y,
    ) = bounding_box(
        rectangles
    )

    content_width = (
        max_x
        - min_x
    )

    content_height = (
        max_y
        - min_y
    )

    required_width = (
        content_width
        + padding * 2
    )

    required_height = (
        content_height
        + padding * 2
    )

    square_size = round_up_to_multiple(
        max(
            required_width,
            required_height,
        ),
        MODE2_MULTIPLE,
    )

    scene = Image.new(
        "RGBA",
        (
            square_size,
            square_size,
        ),
        (
            0,
            0,
            0,
            0,
        ),
    )

    # Center the tightly packed content
    # inside the final square.

    content_offset_x = int(
        (
            square_size
            - content_width
        )
        / 2
    )

    content_offset_y = int(
        (
            square_size
            - content_height
        )
        / 2
    )

    placements = []

    for obj in layout:

        x = int(
            obj["_x"]
            - min_x
            + content_offset_x
        )

        y = int(
            obj["_y"]
            - min_y
            + content_offset_y
        )

        image = obj["image"]

        scene.alpha_composite(
            image,
            (
                x,
                y,
            ),
        )

        placements.append(
            {
                "class": obj["class"],

                "source": str(
                    obj["path"]
                ),

                "scale": float(
                    obj["scale"]
                ),

                "x": x,

                "y": y,

                "width": int(
                    image.width
                ),

                "height": int(
                    image.height
                ),
            }
        )

    return (
        scene,
        placements,
    )


# ============================================================
# IMAGE COMBINATIONS
# ============================================================

def generate_image_combinations(
    configuration,
    dataset,
):
    """
    Generate the complete Cartesian product
    of images for the current two-object
    class configuration.

    Sampling is WITH replacement.

    Therefore:

        dog_1 + dog_1
        dog_1 + dog_2
        dog_2 + dog_1
        dog_2 + dog_2

    are all different combinations.

    With four images per class:

        4^2 = 16 combinations.
    """

    class_sequence = []
    image_lists = []

    for class_name, count in (
        configuration.items()
    ):

        if count <= 0:
            continue

        for _ in range(count):

            class_sequence.append(
                class_name
            )

            image_lists.append(
                dataset[class_name]
            )

    for image_combination in product(
        *image_lists
    ):

        yield (
            class_sequence,
            image_combination,
        )


# ============================================================
# SIZE VARIATIONS
# ============================================================

def generate_size_variations():
    """
    Return exactly the required five
    size variations.

    Order is important because it is also
    used in the generated filenames.
    """

    return list(
        SIZE_VARIATIONS
    )


def size_variant_name(
    scale_first,
    scale_second,
):
    """
    Example:

        1, 1 -> s1x1
        1, 2 -> s1x2
        1, 4 -> s1x4
        2, 1 -> s2x1
        4, 1 -> s4x1
    """

    return (
        f"s{scale_first}x{scale_second}"
    )


# ============================================================
# METADATA
# ============================================================

def build_metadata(
    scene_id,
    base_scene_id,
    configuration_id,
    combination_id,
    mode,
    scale_first,
    scale_second,
    configuration,
    description,
    placements,
    scene,
):
    """
    Build metadata for a single generated image.
    """

    class_counts = {
        class_name: int(count)
        for class_name, count
        in configuration.items()
        if count > 0
    }

    return {
        "scene_id": scene_id,

        "base_scene_id": base_scene_id,

        "configuration_id": (
            configuration_id
        ),

        "combination_id": (
            combination_id
        ),

        "mode": mode,

        "size_variant": (
            size_variant_name(
                scale_first,
                scale_second,
            )
        ),

        "scale_first": float(
            scale_first
        ),

        "scale_second": float(
            scale_second
        ),

        "description": (
            description
        ),

        "class_counts": (
            class_counts
        ),

        "num_objects": (
            sum(
                class_counts.values()
            )
        ),

        "scene_width": int(
            scene.width
        ),

        "scene_height": int(
            scene.height
        ),

        "objects": placements,
    }


# ============================================================
# SAVE SCENE
# ============================================================

def save_scene(
    scene,
    metadata,
    output_root,
):
    """
    Save PNG and JSON metadata.

    Images:

        output/images/<scene_id>.png

    Metadata:

        output/metadata/<scene_id>.json
    """

    scene_id = metadata[
        "scene_id"
    ]

    image_path = (
        output_root
        / "images"
        / f"{scene_id}.png"
    )

    metadata_path = (
        output_root
        / "metadata"
        / f"{scene_id}.json"
    )

    image_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    metadata_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    scene.save(
        image_path
    )

    with open(
        metadata_path,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            metadata,
            f,
            ensure_ascii=False,
            indent=2,
        )


# ============================================================
# CONFIGURATION GENERATION
# ============================================================

def generate_configuration(
    configuration,
    configuration_id,
    dataset,
    output_root,
    padding,
    gap,
    max_attempts,
    scene_id_filter=None,
):
    """
    Generate all combinations for one
    two-object class configuration.

    If scene_id_filter is None:
        generate all 16 image combinations.

    If scene_id_filter is specified:
        generate only that image combination.

    For each selected combination:

        5 size variants
        x
        2 modes
    """

    description = make_description(
        configuration
    )

    log("")
    log(
        "=" * 70
    )

    log(
        f"CONFIGURATION "
        f"{configuration_id:03d}"
    )

    log(
        f"Description: "
        f"{description}"
    )

    log(
        f"Class counts: "
        f"{configuration}"
    )

    log(
        "Size variations: "
        f"{len(SIZE_VARIATIONS)}"
    )

    log(
        "Modes: mode1, mode2"
    )

    if scene_id_filter is not None:
        log(
            f"Scene filter: "
            f"{scene_id_filter:03d}"
        )

    log(
        "=" * 70
    )

    generated = 0

    combinations = (
        generate_image_combinations(
            configuration=configuration,
            dataset=dataset,
        )
    )

    for combination_id, (
        class_sequence,
        image_combination,
    ) in enumerate(
        combinations,
        start=1,
    ):

        # ----------------------------------------------------
        # Scene filter.
        # ----------------------------------------------------

        if (
            scene_id_filter is not None
            and combination_id != scene_id_filter
        ):
            continue

        # ----------------------------------------------------
        # Load original foreground images.
        # ----------------------------------------------------

        original_images = []

        for image_path in image_combination:

            image = load_foreground(
                image_path
            )

            original_images.append(
                image
            )

        base_scene_id = (
            f"config_"
            f"{configuration_id:03d}_"
            f"scene_"
            f"{combination_id:03d}"
        )

        source_names = [
            Path(
                image_path
            ).name
            for image_path
            in image_combination
        ]

        # ----------------------------------------------------
        # Five scale variants.
        # ----------------------------------------------------

        for (
            scale_first,
            scale_second,
        ) in SIZE_VARIATIONS:

            variant_name = (
                size_variant_name(
                    scale_first,
                    scale_second,
                )
            )

            # ------------------------------------------------
            # Scale both source images.
            # ------------------------------------------------

            scaled_first = scale_image(
                original_images[0],
                scale_first,
            )

            scaled_second = scale_image(
                original_images[1],
                scale_second,
            )

            # ------------------------------------------------
            # Generate both modes.
            # ------------------------------------------------

            for mode in (
                "mode1",
                "mode2",
            ):

                objects = [
                    {
                        "class": class_sequence[0],

                        "path": image_combination[0],

                        "image": scaled_first,

                        "scale": scale_first,
                    },

                    {
                        "class": class_sequence[1],

                        "path": image_combination[1],

                        "image": scaled_second,

                        "scale": scale_second,
                    },
                ]

                # --------------------------------------------
                # Create scene.
                # --------------------------------------------

                try:

                    if mode == "mode1":

                        (
                            scene,
                            placements,
                        ) = create_scene_mode1(
                            objects=objects,
                            padding=padding,
                            gap=gap,
                            max_attempts=(
                                max_attempts
                            ),
                        )

                    else:

                        (
                            scene,
                            placements,
                        ) = create_scene_mode2(
                            objects=objects,
                            padding=padding,
                            gap=gap,
                            max_attempts=(
                                max_attempts
                            ),
                        )

                except Exception as exc:

                    warning(
                        f"Failed to generate "
                        f"configuration "
                        f"{configuration_id}, "
                        f"combination "
                        f"{combination_id}, "
                        f"{mode}, "
                        f"{variant_name}: "
                        f"{exc}"
                    )

                    continue

                # --------------------------------------------
                # Scene ID.
                # --------------------------------------------

                scene_id = (
                    f"{base_scene_id}_"
                    f"{mode}_"
                    f"{variant_name}"
                )

                # --------------------------------------------
                # Metadata.
                # --------------------------------------------

                metadata = build_metadata(
                    scene_id=scene_id,

                    base_scene_id=(
                        base_scene_id
                    ),

                    configuration_id=(
                        configuration_id
                    ),

                    combination_id=(
                        combination_id
                    ),

                    mode=mode,

                    scale_first=(
                        scale_first
                    ),

                    scale_second=(
                        scale_second
                    ),

                    configuration=(
                        configuration
                    ),

                    description=(
                        description
                    ),

                    placements=(
                        placements
                    ),

                    scene=scene,
                )

                # --------------------------------------------
                # Save.
                # --------------------------------------------

                save_scene(
                    scene=scene,

                    metadata=metadata,

                    output_root=(
                        output_root
                    ),
                )

                generated += 1

                log(
                    f"[{generated:03d}] "
                    f"{scene_id} "
                    f"-> "
                    f"{', '.join(source_names)} "
                    f"-> "
                    f"{scene.width}x"
                    f"{scene.height}"
                )

    return generated


# ============================================================
# DATASET METADATA
# ============================================================

def calculate_expected_combinations(
    total_objects,
    images_per_class,
):
    """
    Number of image combinations.

    With replacement:

        images_per_class ^ total_objects

    For two objects and four images:

        4^2 = 16
    """

    return (
        images_per_class
        ** total_objects
    )


def save_dataset_metadata(
    output_root,
    classes,
    configurations,
):
    """
    Save global dataset description.
    """

    combinations_per_configuration = (
        calculate_expected_combinations(
            total_objects=(
                OBJECTS_PER_SCENE
            ),
            images_per_class=(
                IMAGES_PER_CLASS
            ),
        )
    )

    num_size_variations = len(
        SIZE_VARIATIONS
    )

    num_modes = 2

    variants_per_combination = (
        num_size_variations
        * num_modes
    )

    scenes_per_configuration = (
        combinations_per_configuration
        * variants_per_combination
    )

    configuration_metadata = []

    for configuration_id, configuration in (
        enumerate(
            configurations,
            start=1,
        )
    ):

        configuration_metadata.append(
            {
                "configuration_id": (
                    configuration_id
                ),

                "description": (
                    make_description(
                        configuration
                    )
                ),

                "class_counts": {
                    class_name: int(
                        count
                    )
                    for (
                        class_name,
                        count,
                    ) in configuration.items()
                    if count > 0
                },

                "num_image_combinations": (
                    combinations_per_configuration
                ),

                "num_size_variations": (
                    num_size_variations
                ),

                "size_variations": [
                    {
                        "scale_first": (
                            first
                        ),

                        "scale_second": (
                            second
                        ),

                        "name": (
                            size_variant_name(
                                first,
                                second,
                            )
                        ),
                    }
                    for (
                        first,
                        second,
                    ) in SIZE_VARIATIONS
                ],

                "modes": [
                    "mode1",
                    "mode2",
                ],

                "num_generated_scenes": (
                    scenes_per_configuration
                ),
            }
        )

    total_scenes = (
        len(configurations)
        * scenes_per_configuration
    )

    metadata = {
        "classes": classes,

        "images_per_class": (
            IMAGES_PER_CLASS
        ),

        "objects_per_scene": (
            OBJECTS_PER_SCENE
        ),

        "num_class_configurations": (
            len(configurations)
        ),

        "image_combinations_per_configuration": (
            combinations_per_configuration
        ),

        "size_variations": [
            {
                "name": size_variant_name(
                    first,
                    second,
                ),

                "scale_first": first,

                "scale_second": second,
            }
            for (
                first,
                second,
            ) in SIZE_VARIATIONS
        ],

        "num_size_variations": (
            num_size_variations
        ),

        "modes": [
            "mode1",
            "mode2",
        ],

        "num_modes": (
            num_modes
        ),

        "variants_per_image_combination": (
            variants_per_combination
        ),

        "scenes_per_configuration": (
            scenes_per_configuration
        ),

        "total_expected_scenes": (
            total_scenes
        ),

        "sampling_with_replacement": True,

        "mode2_square_multiple": (
            MODE2_MULTIPLE
        ),

        "configurations": (
            configuration_metadata
        ),
    }

    path = (
        output_root
        / "dataset.json"
    )

    with open(
        path,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            metadata,
            f,
            ensure_ascii=False,
            indent=2,
        )

    log(
        f"Saved dataset metadata: "
        f"{path}"
    )


# ============================================================
# ARGUMENTS
# ============================================================

def parse_args():

    parser = argparse.ArgumentParser(
        description=(
            "Generate two-object scenes "
            "using the first four foreground "
            "images of each class."
        )
    )

    parser.add_argument(
        "--foreground",
        type=Path,
        default=(
            DEFAULT_FOREGROUND
        ),
        help=(
            "Foreground root directory. "
            "Expected structure: "
            "foreground/dog/*.png, "
            "foreground/cat/*.png, "
            "foreground/car/*.png, "
            "foreground/motorcycle/*.png."
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=(
            DEFAULT_OUTPUT
        ),
        help=(
            "Output directory."
        ),
    )

    parser.add_argument(
        "--padding",
        type=int,
        default=(
            DEFAULT_PADDING
        ),
        help=(
            "Transparent padding around "
            "the content."
        ),
    )

    parser.add_argument(
        "--gap",
        type=int,
        default=(
            DEFAULT_GAP
        ),
        help=(
            "Minimum distance between "
            "object bounding boxes."
        ),
    )

    parser.add_argument(
        "--max-attempts",
        type=int,
        default=(
            DEFAULT_MAX_ATTEMPTS
        ),
        help=(
            "Number of packing attempts "
            "per generated scene."
        ),
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help=(
            "Random seed used for "
            "compact packing."
        ),
    )

    parser.add_argument(
        "--config",
        type=int,
        default=None,
        help=(
            "Generate only the specified "
            "configuration number. "
            "If omitted, all configurations "
            "are generated."
        ),
    )

    parser.add_argument(
        "--scene",
        type=int,
        default=None,
        help=(
            "Generate only the specified "
            "scene number (image combination) "
            "inside the selected configuration. "
            "If omitted, all scenes are generated."
        ),
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

    foreground_root = (
        args.foreground
    )

    output_root = (
        args.output
    )

    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ========================================================
    # CLASSES
    # ========================================================

    classes = list(
        DEFAULT_CLASSES
    )

    log(
        "Classes:"
    )

    for class_name in classes:

        log(
            f"  {class_name}"
        )

    # ========================================================
    # SIZE VARIATIONS
    # ========================================================

    log("")

    log(
        "Size variations:"
    )

    for (
        scale_first,
        scale_second,
    ) in SIZE_VARIATIONS:

        log(
            f"  "
            f"{size_variant_name(scale_first, scale_second)} "
            f"("
            f"first={scale_first}x, "
            f"second={scale_second}x"
            f")"
        )

    # ========================================================
    # DATASET
    # ========================================================

    log("")

    log(
        "Loading foreground dataset..."
    )

    dataset = load_dataset(
        foreground_root=(
            foreground_root
        ),
        classes=classes,
    )

    # ========================================================
    # CLASS CONFIGURATIONS
    # ========================================================

    configurations = (
        generate_class_configurations(
            classes=classes,
            total_objects=(
                OBJECTS_PER_SCENE
            ),
        )
    )

    combinations_per_configuration = (
        calculate_expected_combinations(
            total_objects=(
                OBJECTS_PER_SCENE
            ),
            images_per_class=(
                IMAGES_PER_CLASS
            ),
        )
    )

    variants_per_combination = (
        len(SIZE_VARIATIONS)
        * 2
    )

    scenes_per_configuration = (
        combinations_per_configuration
        * variants_per_combination
    )

    expected_total = (
        len(configurations)
        * scenes_per_configuration
    )

    # ========================================================
    # VALIDATE FILTERS
    # ========================================================

    if args.config is not None:

        if not (
            1
            <= args.config
            <= len(configurations)
        ):

            raise ValueError(
                f"Configuration number "
                f"must be in range "
                f"1..{len(configurations)}, "
                f"got {args.config}"
            )

    if args.scene is not None:

        if not (
            1
            <= args.scene
            <= combinations_per_configuration
        ):

            raise ValueError(
                f"Scene number "
                f"must be in range "
                f"1..{combinations_per_configuration}, "
                f"got {args.scene}"
            )

    # ========================================================
    # EXPECTED NUMBER FOR SELECTED FILTER
    # ========================================================

    if (
        args.config is not None
        and args.scene is not None
    ):

        selected_expected = (
            variants_per_combination
        )

    elif args.config is not None:

        selected_expected = (
            scenes_per_configuration
        )

    elif args.scene is not None:

        selected_expected = (
            len(configurations)
            * variants_per_combination
        )

    else:

        selected_expected = (
            expected_total
        )

    # ========================================================
    # GENERATION INFO
    # ========================================================

    log("")

    log(
        f"Class configurations: "
        f"{len(configurations)}"
    )

    log(
        f"Image combinations per configuration: "
        f"{combinations_per_configuration}"
    )

    log(
        f"Size variations per combination: "
        f"{len(SIZE_VARIATIONS)}"
    )

    log(
        "Modes: 2"
    )

    log(
        f"Scenes per configuration: "
        f"{scenes_per_configuration}"
    )

    log(
        f"Expected total scenes: "
        f"{expected_total}"
    )

    if args.config is not None:
        log(
            f"Configuration filter: "
            f"{args.config}"
        )
    else:
        log(
            "Configuration filter: all"
        )

    if args.scene is not None:
        log(
            f"Scene filter: "
            f"{args.scene}"
        )
    else:
        log(
            "Scene filter: all"
        )

    log(
        f"Expected scenes for this run: "
        f"{selected_expected}"
    )

    # ========================================================
    # GLOBAL METADATA
    # ========================================================

    save_dataset_metadata(
        output_root=(
            output_root
        ),
        classes=classes,
        configurations=(
            configurations
        ),
    )

    # ========================================================
    # GENERATION
    # ========================================================

    total_generated = 0

    for configuration_id, configuration in (
        enumerate(
            configurations,
            start=1,
        )
    ):

        # ----------------------------------------------------
        # Configuration filter.
        # ----------------------------------------------------

        if (
            args.config is not None
            and configuration_id != args.config
        ):
            continue

        generated = (
            generate_configuration(
                configuration=(
                    configuration
                ),

                configuration_id=(
                    configuration_id
                ),

                dataset=dataset,

                output_root=(
                    output_root
                ),

                padding=(
                    args.padding
                ),

                gap=(
                    args.gap
                ),

                max_attempts=(
                    args.max_attempts
                ),

                scene_id_filter=(
                    args.scene
                ),
            )
        )

        total_generated += generated

    # ========================================================
    # SUMMARY
    # ========================================================

    log("")

    log(
        "=" * 70
    )

    log(
        "FINISHED"
    )

    log(
        "=" * 70
    )

    log(
        f"Classes: "
        f"{len(classes)}"
    )

    log(
        f"Images per class: "
        f"{IMAGES_PER_CLASS}"
    )

    log(
        f"Objects per scene: "
        f"{OBJECTS_PER_SCENE}"
    )

    log(
        f"Class configurations: "
        f"{len(configurations)}"
    )

    log(
        f"Image combinations per configuration: "
        f"{combinations_per_configuration}"
    )

    log(
        f"Size variations: "
        f"{len(SIZE_VARIATIONS)}"
    )

    log(
        "Modes: 2"
    )

    log(
        f"Scenes per configuration: "
        f"{scenes_per_configuration}"
    )

    log(
        f"Expected scenes for this run: "
        f"{selected_expected}"
    )

    log(
        f"Generated scenes: "
        f"{total_generated}"
    )

    log(
        f"Output directory: "
        f"{output_root}"
    )

    log(
        "=" * 70
    )


if __name__ == "__main__":
    main()

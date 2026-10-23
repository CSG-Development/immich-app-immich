import argparse
import json
import random
import shutil
import tarfile
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

from tqdm import tqdm


DEFAULT_COUNT = None
DEFAULT_OUTPUT = "./voc_subset"
DEFAULT_SEED = 42

VOC_URLS = {
    "2007": (
        "https://thor.robots.ox.ac.uk/pascal/VOC/"
        "voc2007/VOCtrainval_06-Nov-2007.tar"
    ),
    "2012": (
        "https://thor.robots.ox.ac.uk/pascal/VOC/"
        "voc2012/VOCtrainval_11-May-2012.tar"
    ),
}


CLASSES = [
    "aeroplane",
    "bicycle",
    "bird",
    "boat",
    "bottle",
    "bus",
    "car",
    "cat",
    "chair",
    "cow",
    "diningtable",
    "dog",
    "horse",
    "motorbike",
    "person",
    "pottedplant",
    "sheep",
    "sofa",
    "train",
    "tvmonitor",
]


def format_size(size: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]

    value = float(size)

    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.2f} {unit}"

        value /= 1024

    return f"{size} B"


def get_directory_size(path: Path) -> int:
    if not path.exists():
        return 0

    if path.is_file():
        return path.stat().st_size

    return sum(
        file.stat().st_size
        for file in path.rglob("*")
        if file.is_file()
    )


def download_file(url: str, path: Path):
    if path.exists():
        print(
            f"[INFO] Already downloaded: {path} "
            f"({format_size(path.stat().st_size)})"
        )
        return

    print("[INFO] Downloading:")
    print(f"       {url}")
    print(f"       -> {path}")

    path.parent.mkdir(parents=True, exist_ok=True)

    with urllib.request.urlopen(url) as response:
        total_size = int(
            response.headers.get("Content-Length", 0)
        )

        with path.open("wb") as f:
            with tqdm(
                total=total_size if total_size > 0 else None,
                unit="B",
                unit_scale=True,
                unit_divisor=1024,
                desc=path.name,
            ) as progress:
                while True:
                    chunk = response.read(1024 * 1024)

                    if not chunk:
                        break

                    f.write(chunk)
                    progress.update(len(chunk))

    print(
        f"[INFO] Download complete: "
        f"{format_size(path.stat().st_size)}"
    )


def extract_tar(tar_path: Path, output_dir: Path):
    marker = output_dir / ".extracted"

    if marker.exists():
        print(
            f"[INFO] Already extracted: {output_dir} "
            f"({format_size(get_directory_size(output_dir))})"
        )
        return

    print(
        f"[INFO] Extracting {tar_path} "
        f"({format_size(tar_path.stat().st_size)})..."
    )

    output_dir.mkdir(parents=True, exist_ok=True)

    with tarfile.open(tar_path, "r") as archive:
        members = archive.getmembers()

        total_size = sum(
            member.size
            for member in members
            if member.isfile()
        )

        with tqdm(
            total=total_size,
            unit="B",
            unit_scale=True,
            unit_divisor=1024,
            desc=output_dir.name,
        ) as progress:
            for member in members:
                archive.extract(member, output_dir)

                if member.isfile():
                    progress.update(member.size)

    marker.touch()

    extracted_size = get_directory_size(output_dir)

    print(
        f"[INFO] Extraction complete: "
        f"{format_size(extracted_size)}"
    )


def find_voc_root(extracted_dir: Path, year: str) -> Path:
    expected = extracted_dir / "VOCdevkit" / f"VOC{year}"

    if expected.exists():
        return expected

    matches = list(extracted_dir.rglob(f"VOC{year}"))

    if not matches:
        raise RuntimeError(
            f"Could not find VOC{year} directory in {extracted_dir}"
        )

    return matches[0]


def get_image_ids(voc_root: Path):
    trainval_file = (
        voc_root
        / "ImageSets"
        / "Main"
        / "trainval.txt"
    )

    if not trainval_file.exists():
        raise RuntimeError(f"Missing: {trainval_file}")

    with trainval_file.open("r", encoding="utf-8") as f:
        return [
            line.strip()
            for line in f
            if line.strip()
        ]


def parse_annotation(xml_path: Path):
    root = ET.parse(xml_path).getroot()

    size = root.find("size")

    width = int(size.find("width").text)
    height = int(size.find("height").text)

    objects = []

    for obj in root.findall("object"):
        name = obj.find("name").text

        difficult_node = obj.find("difficult")
        difficult = (
            int(difficult_node.text)
            if difficult_node is not None
            else 0
        )

        truncated_node = obj.find("truncated")
        truncated = (
            int(truncated_node.text)
            if truncated_node is not None
            else 0
        )

        bbox = obj.find("bndbox")

        xmin = int(float(bbox.find("xmin").text))
        ymin = int(float(bbox.find("ymin").text))
        xmax = int(float(bbox.find("xmax").text))
        ymax = int(float(bbox.find("ymax").text))

        objects.append(
            {
                "class": name,
                "bbox": [
                    xmin,
                    ymin,
                    xmax,
                    ymax,
                ],
                "difficult": difficult,
                "truncated": truncated,
            }
        )

    return {
        "width": width,
        "height": height,
        "objects": objects,
    }


def collect_images(voc_roots):
    images = []

    for year, voc_root in voc_roots.items():
        image_dir = voc_root / "JPEGImages"
        annotation_dir = voc_root / "Annotations"

        for image_id in get_image_ids(voc_root):
            image_path = (
                image_dir / f"{image_id}.jpg"
            )

            annotation_path = (
                annotation_dir / f"{image_id}.xml"
            )

            if not image_path.exists():
                continue

            if not annotation_path.exists():
                continue

            images.append(
                {
                    "year": year,
                    "id": image_id,
                    "image_path": image_path,
                    "annotation_path": annotation_path,
                }
            )

    return images


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Download a subset of PASCAL VOC "
            "images with annotations."
        )
    )

    parser.add_argument(
        "--count",
        type=int,
        default=DEFAULT_COUNT,
        help=(
            f"Number of images to select; "
            f"if omitted, use all available images "
            f"(default: {DEFAULT_COUNT})"
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=Path(DEFAULT_OUTPUT),
        help=(
            f"Output directory "
            f"(default: {DEFAULT_OUTPUT})"
        ),
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=(
            f"Random seed "
            f"(default: {DEFAULT_SEED})"
        ),
    )

    args = parser.parse_args()

    if args.count is not None and args.count <= 0:
        raise ValueError(
            "--count must be greater than 0"
        )

    random.seed(args.seed)

    output_dir = args.output
    download_dir = output_dir / "_download"
    images_dir = output_dir / "images"

    images_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    download_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ------------------------------------------------------------
    # Download and extract VOC
    # ------------------------------------------------------------

    voc_roots = {}

    for year, url in VOC_URLS.items():
        archive_path = (
            download_dir / Path(url).name
        )

        extracted_dir = (
            download_dir / year
        )

        download_file(
            url,
            archive_path,
        )

        extract_tar(
            archive_path,
            extracted_dir,
        )

        voc_roots[year] = find_voc_root(
            extracted_dir,
            year,
        )

    # ------------------------------------------------------------
    # Collect images
    # ------------------------------------------------------------

    print("[INFO] Collecting VOC images...")

    all_images = collect_images(voc_roots)

    print(
        f"[INFO] Available images: "
        f"{len(all_images)}"
    )

    # ------------------------------------------------------------
    # Select images
    # ------------------------------------------------------------

    if args.count is None:
        print(
            "[INFO] No image count limit specified. "
            "Using all available images."
        )

        selected = all_images
    else:
        if args.count > len(all_images):
            raise ValueError(
                f"Requested {args.count} images, "
                f"but only {len(all_images)} "
                f"are available."
            )

        selected = random.sample(
            all_images,
            args.count,
        )

    selected.sort(
        key=lambda x: (
            x["year"],
            x["id"],
        )
    )

    # ------------------------------------------------------------
    # Prepare metadata
    # ------------------------------------------------------------

    annotations = {
        "dataset": "PASCAL VOC",
        "source": {
            "VOC2007": "trainval",
            "VOC2012": "trainval",
        },
        "count": len(selected),
        "seed": args.seed,
        "classes": CLASSES,
        "images": [],
    }

    # ------------------------------------------------------------
    # Copy images and parse annotations
    # ------------------------------------------------------------

    with tqdm(
        total=len(selected),
        desc="Copying images",
        unit="image",
    ) as progress:
        for index, item in enumerate(selected):
            annotation = parse_annotation(
                item["annotation_path"]
            )

            objects = annotation["objects"]

            classes = sorted(
                set(
                    obj["class"]
                    for obj in objects
                )
            )

            class_counts = {}

            for obj in objects:
                class_name = obj["class"]

                class_counts[class_name] = (
                    class_counts.get(class_name, 0) + 1
                )

            output_name = (
                f"{index:05d}_"
                f"voc{item['year']}_"
                f"{item['id']}.jpg"
            )

            output_image = (
                images_dir / output_name
            )

            shutil.copy2(
                item["image_path"],
                output_image,
            )

            annotations["images"].append(
                {
                    "file": output_name,
                    "source": {
                        "year": item["year"],
                        "id": item["id"],
                    },
                    "width": annotation["width"],
                    "height": annotation["height"],
                    "classes": classes,
                    "class_counts": class_counts,
                    "objects": objects,
                }
            )

            progress.set_postfix(
                file=output_name,
            )

            progress.update(1)

    # ------------------------------------------------------------
    # Save metadata
    # ------------------------------------------------------------

    annotations_path = (
        output_dir / "annotations.json"
    )

    with annotations_path.open(
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            annotations,
            f,
            indent=2,
            ensure_ascii=False,
        )

    # ------------------------------------------------------------
    # Final sizes
    # ------------------------------------------------------------

    archives_size = get_directory_size(
        download_dir
    )

    images_size = get_directory_size(
        images_dir
    )

    annotations_size = (
        annotations_path.stat().st_size
    )

    output_size = get_directory_size(
        output_dir
    )

    print()
    print("[INFO] Done.")
    print()
    print("[INFO] Sizes:")

    print(
        f"       Downloads:   "
        f"{format_size(archives_size)}"
    )

    print(
        f"       Images:      "
        f"{format_size(images_size)}"
    )

    print(
        f"       Annotations: "
        f"{format_size(annotations_size)}"
    )

    print(
        f"       Total:       "
        f"{format_size(output_size)}"
    )

    print()

    print(
        f"[INFO] Images:      {images_dir}"
    )

    print(
        f"[INFO] Annotations: "
        f"{annotations_path}"
    )


if __name__ == "__main__":
    main()

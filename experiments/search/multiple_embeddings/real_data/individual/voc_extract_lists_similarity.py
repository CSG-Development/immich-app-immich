import argparse
import json
from pathlib import Path


DEFAULT_RESULTS = "./voc_similarity_reprocessed/results.json"
DEFAULT_OUTPUT = "./voc_similarity_reprocessed/image_lists_similarity.json"


def log(message):
    print(f"[INFO] {message}")


def warning(message):
    print(f"[WARNING] {message}")


def load_results(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "results" not in data:
        raise RuntimeError(
            "Invalid results.json: 'results' field is missing."
        )

    return data


def extract_image_lists(results):
    image_lists = {}

    for image_result in results:
        image_file = image_result.get("file")

        if not image_file:
            warning("Skipping result without image file")
            continue

        classes = image_result.get("classes", {})

        if not isinstance(classes, dict):
            warning(
                f"Skipping classes for {image_file}: "
                f"unexpected type {type(classes).__name__}"
            )
            continue

        for class_name, class_result in classes.items():
            if not isinstance(class_result, dict):
                warning(
                    f"Skipping {class_name} for {image_file}: "
                    f"unexpected type {type(class_result).__name__}"
                )
                continue

            if class_name not in image_lists:
                image_lists[class_name] = {
                    "original": [],
                    "all": [],
                }

            modified_similarity = class_result.get(
                "max_modified_similarity"
            )

            if modified_similarity is None:
                warning(
                    f"Missing max modified similarity for "
                    f"{image_file}, class {class_name}"
                )
                continue

            if class_result.get("original", False):
                image_lists[class_name]["original"].append(
                    {
                        "file": image_file,
                        "modified_similarity": modified_similarity,
                    }
                )

            if class_result.get("found", False):
                image_lists[class_name]["all"].append(
                    {
                        "file": image_file,
                        "modified_similarity": modified_similarity,
                    }
                )

    for class_name in image_lists:
        image_lists[class_name]["original"].sort(
            key=lambda item: item["modified_similarity"],
            reverse=True,
        )

        image_lists[class_name]["all"].sort(
            key=lambda item: item["modified_similarity"],
            reverse=True,
        )

    return image_lists


def save_json(data, path):
    path.parent.mkdir(parents=True, exist_ok=True)

    with open(path, "w", encoding="utf-8") as f:
        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2,
        )


def print_summary(image_lists):
    print()
    print("=" * 70)
    print("IMAGE LISTS")
    print("=" * 70)

    for class_name in sorted(image_lists):
        original = image_lists[class_name]["original"]
        all_images = image_lists[class_name]["all"]

        print()
        print(class_name)
        print(f"  original: {len(original)}")
        print(f"  all:      {len(all_images)}")

        if original:
            print(
                f"    top original: "
                f"{original[0]['file']} "
                f"({original[0]['modified_similarity']:.6f})"
            )

        if all_images:
            print(
                f"    top modified: "
                f"{all_images[0]['file']} "
                f"({all_images[0]['modified_similarity']:.6f})"
            )


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Extract image lists and maximum modified similarity "
            "for each object class from results.json."
        )
    )

    parser.add_argument(
        "--results",
        default=DEFAULT_RESULTS,
        help=(
            f"Path to results.json "
            f"(default: {DEFAULT_RESULTS})"
        ),
    )

    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help=(
            f"Output JSON path "
            f"(default: {DEFAULT_OUTPUT})"
        ),
    )

    return parser.parse_args()


def main():
    args = parse_args()

    results_path = Path(args.results)
    output_path = Path(args.output)

    log(f"Loading results: {results_path}")

    data = load_results(results_path)
    results = data["results"]

    log(f"Images in results: {len(results)}")

    image_lists = extract_image_lists(results)

    log(f"Classes found: {len(image_lists)}")

    save_json(
        image_lists,
        output_path,
    )

    log(f"Saved: {output_path}")

    print_summary(image_lists)


if __name__ == "__main__":
    main()

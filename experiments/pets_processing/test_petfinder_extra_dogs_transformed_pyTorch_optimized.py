import argparse
import csv
import os
import sys
import pickle
import time

import numpy as np
import torch
import torch.nn.functional as F

EMBEDDINGS_LIMIT = 10_000

EMBEDDINGS_PATH = "embeddings/petfinder_extra_dogs_transformed_v6_new"

ALL_FILENAME = "count_petfinder_extra_dogs_transformed_v6.csv"

INPUT_ALL_FILENAME = (
    "all_clear_petfinder_extra_dogs_transformed_v6.csv"
)

RESULTS_FILENAME = (
    f"all_petfinder_extra_dogs_transformed_v6_new_100_{EMBEDDINGS_LIMIT}-matrix.csv"
)

IMAGES_PATH = (
    "../pets_datasets/petfinder_extra_dogs_transformed_v6"
)

DEFAULT_BLOCK_SIZE = 4096

def load_embedding(name, num):

    fname = os.path.join(
        EMBEDDINGS_PATH,
        name,
        f"{num}.pkl",
    )

    with open(fname, "rb") as f:
        emb = pickle.load(f)

    if not torch.is_tensor(emb):
        emb = torch.tensor(emb)

    emb = emb.float().cpu()

    # Embeddings are saved as (512,) or (1, 512).
    # For the common Tensor each embedding is converted to (512,).
    if emb.ndim == 2 and emb.shape[0] == 1:
        emb = emb.squeeze(0)

    if emb.ndim != 1:
        raise ValueError(
            f"Unexpected embedding shape: {tuple(emb.shape)}"
        )

    return emb


EMBEDDINGS = {}
def get_embedding(name, num):
    if name not in EMBEDDINGS:
        EMBEDDINGS[name] = {}

    if num not in EMBEDDINGS[name]:
        try:
            EMBEDDINGS[name][num] = load_embedding(
                name,
                num,
            )
        except Exception as e:
            print(
                f"Error on loading embedding "
                f"{name} {num}: {e}"
            )
            EMBEDDINGS[name][num] = None

    return EMBEDDINGS[name][num]

# ====================================================
# Helper functions
# ====================================================

def get_all_dict():
    result = {}

    with open(
        ALL_FILENAME,
        newline="",
        encoding="utf-8",
    ) as infile:

        reader = csv.DictReader(infile)

        for row in reader:
            name = row["name"]
            count = int(row["images"])
            result[name] = count

    return result


def get_all_list():
    result = []

    with open(
        INPUT_ALL_FILENAME,
        newline="",
        encoding="utf-8",
    ) as infile:

        reader = csv.DictReader(infile)

        for row in reader:
            name = row["name"]
            imagenum = int(row["imagenum"])

            result.append(
                {
                    "name": name,
                    "imagenum": imagenum,
                }
            )

    return result


def get_block_size():
    parser = argparse.ArgumentParser(
        description=(
            "Calculate pairwise embedding metrics "
            "using block processing."
        )
    )
    parser.add_argument(
        "--block-size",
        type=int,
        default=DEFAULT_BLOCK_SIZE,
        help=(
            "Number of embeddings processed in one block "
            f"(default: {DEFAULT_BLOCK_SIZE})."
        ),
    )

    args = parser.parse_args()

    if args.block_size <= 0:
        parser.error("--block-size must be greater than zero")

    return args.block_size


def get_device():
    if torch.cuda.is_available():
        return torch.device("cuda")

    return torch.device("cpu")


def load_all_embeddings(all_list):
    loaded_embeddings = []
    loaded_items = []

    all_len = len(all_list)

    for index, item in enumerate(all_list):
        name = item["name"]
        imagenum = item["imagenum"]

        embedding = get_embedding(name, imagenum)

        if embedding is not None:
            loaded_embeddings.append(embedding)
            loaded_items.append(item)

        print(
            "Loading embeddings:",
            index + 1,
            "/",
            all_len,
            (index + 1) * 100 // all_len,
        )

    if not loaded_embeddings:
        raise RuntimeError("No embeddings were loaded")

    embeddings = torch.stack(
        loaded_embeddings,
        dim=0,
    )

    return embeddings, loaded_items


def build_labels(all_list, device):
    # Class names are converted to integer identifiers.
    # Equality of identifiers is fully equivalent to name1 == name2.
    label_ids = {}
    labels = []

    for item in all_list:
        name = item["name"]

        if name not in label_ids:
            label_ids[name] = len(label_ids)

        labels.append(label_ids[name])

    return torch.tensor(
        labels,
        dtype=torch.int64,
        device=device,
    )

# ====================================================
# Main
# ====================================================


def main():

    started_at = time.perf_counter()

    block_size = get_block_size()
    device = get_device()

    print(f"Device: {device}")

    if device.type == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(device)}")
    else:
        print("GPU: not available")

    all_list = get_all_list()[:EMBEDDINGS_LIMIT]

    embeddings, all_list = load_all_embeddings(all_list)

    # Normalization is performed exactly once for all embeddings.
    embeddings = F.normalize(
        embeddings,
        dim=1,
    )

    embeddings = embeddings.to(device)

    all_len = len(all_list)
    labels = build_labels(all_list, device)

    #thresholds = list(range(0, 101, 0.1))
    thresholds = [ t/10 for t in range(0, 1001)]

    results = [
        {
            "Threshold": t,
            "TP": 0,
            "FP": 0,
            "TN": 0,
            "FN": 0,
        }
        for t in thresholds
    ]

    print(f"Embeddings: {all_len}")
    print(f"Block size: {block_size}")

    total_blocks = (
        all_len + block_size - 1
    ) // block_size

    all_column_indices = torch.arange(
        all_len,
        device=device,
    ).unsqueeze(0)

    for block_number, start in enumerate(
        range(0, all_len, block_size),
        start=1,
    ):
        end = min(
            start + block_size,
            all_len,
        )

        E = embeddings[start:end]

        # After F.normalize dot product is equivalent to cosine similarity.
        # The similarity formula is saved without changes:
        # (cosine_similarity + 1) / 2.
        similarity = (
            E @ embeddings.T + 1.0
        ) / 2.0

        block_labels = labels[start:end]

        same_class = (
            block_labels.unsqueeze(1)
            == labels.unsqueeze(0)
        )

        block_row_indices = torch.arange(
            start,
            end,
            device=device,
        ).unsqueeze(1)

        # The mask fully corresponds to the original condition:
        # if j <= i:
        #     continue
        pair_mask = (
            all_column_indices
            > block_row_indices
        )

        for t, threshold in enumerate(thresholds):
            predicted = (
                similarity
                >= threshold / 100.0
            )

            tp_mask = (
                pair_mask
                & predicted
                & same_class
            )

            fp_mask = (
                pair_mask
                & predicted
                & ~same_class
            )

            fn_mask = (
                pair_mask
                & ~predicted
                & same_class
            )

            tn_mask = (
                pair_mask
                & ~predicted
                & ~same_class
            )

            results[t]["TP"] += tp_mask.sum().item()
            results[t]["FP"] += fp_mask.sum().item()
            results[t]["FN"] += fn_mask.sum().item()
            results[t]["TN"] += tn_mask.sum().item()

        print(
            "Processing blocks:",
            block_number,
            "/",
            total_blocks,
            block_number * 100 // total_blocks,
            f"rows {start}:{end}",
        )

    for t in range(len(thresholds)):

        TP = results[t]["TP"]
        FP = results[t]["FP"]
        TN = results[t]["TN"]
        FN = results[t]["FN"]

        total = TP + FP + TN + FN

        results[t]["TP%"] = TP * 100 / total
        results[t]["FP%"] = FP * 100 / total
        results[t]["TN%"] = TN * 100 / total
        results[t]["FN%"] = FN * 100 / total

        results[t]["Accuracy"] = (TP + TN) / total

        results[t]["Precision"] = (
            TP / (TP + FP)
            if (TP + FP) > 0
            else -1
        )

        results[t]["Recall"] = (
            TP / (TP + FN)
            if (TP + FN) > 0
            else -1
        )

        results[t]["F1"] = (
            2 * TP / (2 * TP + FP + FN)
            if (2 * TP + FP + FN) > 0
            else -1
        )

    fieldnames = [
        "Threshold",
        "TP",
        "FP",
        "TN",
        "FN",
        "TP%",
        "FP%",
        "TN%",
        "FN%",
        "Accuracy",
        "Precision",
        "Recall",
        "F1",
    ]

    with open(
        RESULTS_FILENAME,
        "w",
        newline="",
        encoding="utf-8",
    ) as outfile:

        writer = csv.DictWriter(
            outfile,
            fieldnames=fieldnames,
        )

        writer.writeheader()
        writer.writerows(results)

    if device.type == "cuda":
        torch.cuda.synchronize()

    elapsed = time.perf_counter() - started_at

    print(f"Execution time: {elapsed:.2f} seconds")


if __name__ == "__main__":
    main()

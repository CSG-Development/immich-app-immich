import csv
import os
import sys
import pickle

import numpy as np
import torch
import torch.nn.functional as F


EMBEDDINGS_PATH = "embeddings/petfinder_extra_dogs_transformed_v6"

EMBEDDINGS = {}


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

    # Оставляем размерность такой же,
    # какой она была сохранена моделью.
    if emb.ndim == 1:
        emb = emb.unsqueeze(0)

    return emb

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


def compare_embeddings(emb1, emb2):

    similarity = F.cosine_similarity(
        emb1,
        emb2,
    )

    return similarity.item()
    

ALL_FILENAME = "count_petfinder_extra_dogs_transformed_v6.csv"

INPUT_ALL_FILENAME = (
    "all_clear_petfinder_extra_dogs_transformed_v6.csv"
)

RESULTS_FILENAME = (
    "all_final_results_petfinder_extra_dogs_transformed_v6_new_fixed3_proj_3_100_10000.csv"
)

IMAGES_PATH = (
    "../pets_datasets/petfinder_extra_dogs_transformed_v6"
)


def test(filename1: str, filename2: str, threshold: int) -> int:
    return int(
        (hash(filename1 + filename2 + str(threshold)) % 2) == 0
    )


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


ALL_DICT = get_all_dict()


# ====================================================
# Main
# ====================================================
def main():
    all_list = get_all_list()[:10000]

    all_len = len(all_list)

    thresholds = list(range(0, 101, 1))

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

    for i, item1 in enumerate(all_list):

        print(
            i + 1,
            "/",
            all_len,
            (i + 1) * 100 // all_len,
            item1,
        )

        for j, item2 in enumerate(all_list):

            if j <= i:
                continue

            name1 = item1["name"]
            num1 = item1["imagenum"]

            name2 = item2["name"]
            num2 = item2["imagenum"]

            try:

                emb1 = get_embedding(name1, num1)
                emb2 = get_embedding(name2, num2)

                if emb1 is None or emb2 is None:
                    continue

                similarity_score = compare_embeddings(
                    emb1,
                    emb2,
                )

                for t, threshold in enumerate(thresholds):

                    identical = (
                        similarity_score
                        >= threshold / 100.0
                    )

                    if identical:

                        if name1 == name2:
                            results[t]["TP"] += 1
                        else:
                            results[t]["FP"] += 1

                    else:

                        if name1 == name2:
                            results[t]["FN"] += 1
                        else:
                            results[t]["TN"] += 1

            except Exception as e:
                print(
                    f"Error comparing "
                    f"{name1}/{num1} "
                    f"{name2}/{num2}: {e}"
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


if __name__ == "__main__":
    main()

import csv
import os
import sys
import cv2
import pickle
import numpy as np

EMBEDDINGS_PATH = "embeddings/buffalo_l_det"

def load_embedding(name, num):
    fname = os.path.join(EMBEDDINGS_PATH, name, f"{name}_{num:04d}.pkl")
    with open(fname, "rb") as f:
        data = pickle.load(f)
        return data

EMBEDDINGS = {}

def get_embedding(name, num):
    if name not in EMBEDDINGS:
        EMBEDDINGS[name] = {}
    if num not in EMBEDDINGS[name]:
        try:
            EMBEDDINGS[name][num] = load_embedding(name, num)
        except Exception as e:
            print(f"Error on loading embedding {name} {num}: {e}")
            EMBEDDINGS[name][num] = None

    return EMBEDDINGS[name][num]

def compare_faces(emb1, emb2, threshold=0.65): # Adjust this threshold according to your usecase.
    """Compare two embeddings using cosine similarity"""
    similarity = np.dot(emb1, emb2) / (np.linalg.norm(emb1) * np.linalg.norm(emb2))
    return similarity, similarity > threshold

def compare_faces_score(emb1, emb2): # Adjust this threshold according to your usecase.
    """Compare two embeddings using cosine similarity"""
    similarity = np.dot(emb1, emb2) / (np.linalg.norm(emb1) * np.linalg.norm(emb2))
    return similarity

# === Configuration ===
ALL_FILENAME = "lfw_allnames.csv"                         # Input CSV file with columns: name, imagenum1, imagenum2
INPUT_ALL_FILENAME = "all_clear_buffalo_l_det.csv"        # Input CSV file with columns: name, imagenum1, imagenum2
RESULTS_FILENAME = "all_final_results_buffalo_l_det.csv"  # Output CSV file
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"         # Base folder with images

# === Mock test function (replace with your own implementation) ===
def test(filename1: str, filename2: str, threshold: int) -> int:
    """
    Placeholder for the real "test" function.
    Should return 0 or 1 depending on comparison result.
    """
    # Example dummy implementation
    return int((hash(filename1 + filename2 + str(threshold)) % 2) == 0)

def get_all_dict():
    result = {}
    with open(ALL_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            count = int(row["images"])
            result[name] = count
    return result

def get_all_list():
    result = []
    with open(INPUT_ALL_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            imagenum = int(row["imagenum"])
            result.append({"name": name, "imagenum": imagenum})
    return result

ALL_DICT = get_all_dict()

# === Main script ===
def main():
    all_list = get_all_list()
    all_len = len(all_list)
    thresholds = list(range(0, 105, 5))

    results = [{"Threshold": t, "TP": 0, "FP": 0, "TN": 0, "FN": 0} for t in thresholds]

    for i, item1 in enumerate(all_list):
        print(i + 1, "/", all_len, (i + 1) * 100 // all_len, item1)
        for j, item2 in enumerate(all_list):
            if j > i:
                name1 = item1["name"]
                num1 = item1["imagenum"]
                name2 = item2["name"]
                num2 = item2["imagenum"]

                similarity_score = -10
                try:
                    emb1 = get_embedding(name1, num1)
                    emb2 = get_embedding(name2, num2)
                    if emb1 is not None and emb2 is not None:
                        similarity_score = compare_faces_score(emb1, emb2)
                        for t, threshold in enumerate(thresholds):
                            identical = similarity_score >= threshold / 100
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
                    print(f"Error {e}")
                    pass

    for t, threshold in enumerate(thresholds):
        total = results[t]["TP"] + results[t]["TN"] + results[t]["FP"] + results[t]["FN"]
        results[t]["TP%"] = (results[t]["TP"] * 100 / total) if results[t]["TP"] != 0 else 0
        results[t]["FP%"] = (results[t]["FP"] * 100 / total) if results[t]["FP"] != 0 else 0
        results[t]["TN%"] = (results[t]["TN"] * 100 / total) if results[t]["TN"] != 0 else 0
        results[t]["FN%"] = (results[t]["FN"] * 100 / total) if results[t]["FN"] != 0 else 0
        results[t]["Accuracy"] = (results[t]["TP"] + results[t]["TN"]) / total if (results[t]["TP"] + results[t]["TN"]) > 0 else -1
        results[t]["Precision"] = (results[t]["TP"] / (results[t]["TP"] + results[t]["FP"])) if (results[t]["TP"] + results[t]["FP"]) > 0 else -1
        results[t]["Recall"] = (results[t]["TP"] / (results[t]["TP"] + results[t]["FN"])) if (results[t]["TP"] + results[t]["FN"]) > 0 else -1
        results[t]["F1"] = (2*results[t]["TP"] / (2*results[t]["TP"] + results[t]["FP"] + results[t]["FN"])) if (2*results[t]["TP"] + results[t]["FP"] + results[t]["FN"]) > 0 else -1

    fieldnames = ["Threshold", "TP", "FP", "TN", "FN", "TP%", "FP%", "TN%", "FN%", "Accuracy", "Precision", "Recall", "F1"]
    with open(RESULTS_FILENAME, "w", newline="", encoding="utf-8") as outfile:
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

if __name__ == "__main__":
    main()

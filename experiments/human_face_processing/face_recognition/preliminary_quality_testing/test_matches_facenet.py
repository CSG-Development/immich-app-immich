import csv
import os
import sys
import cv2
import torch
import numpy as np
from PIL import Image
from facenet_pytorch import MTCNN, InceptionResnetV1

# === Initialize models ===
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# MTCNN for face detection & alignment
mtcnn = MTCNN(image_size=250, margin=0, min_face_size=20, device=device)

# InceptionResnetV1 for face embeddings
resnet = InceptionResnetV1(pretrained="vggface2").eval().to(device)


def get_face_embedding(image_path):
    """Extract a 512D face embedding from an image using facenet_pytorch"""
    img = Image.open(image_path).convert("RGB")

    # Detect and align face
    aligned_face = mtcnn(img)

    if aligned_face is None:
        raise ValueError(f"No face detected in {image_path}")

    # Compute embedding
    with torch.no_grad():
        embedding = resnet(aligned_face.unsqueeze(0).to(device)).cpu().numpy().flatten()

    return embedding


def compare_faces(emb1, emb2, threshold=0.65):
    """Compare two embeddings using cosine similarity"""
    similarity = np.dot(emb1, emb2) / (np.linalg.norm(emb1) * np.linalg.norm(emb2))
    return similarity, similarity > threshold


def compare_faces_score(emb1, emb2):
    """Return cosine similarity score between two embeddings"""
    similarity = np.dot(emb1, emb2) / (np.linalg.norm(emb1) * np.linalg.norm(emb2))
    return similarity


# === Configuration ===
TEST_FILE_NAME = "matchpairsDevTrain.csv"          # CSV file with columns: name, imagenum1, imagenum2
RESULTS_FILENAME = "match_results_facenet.csv"     # Output CSV file
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"  # Base folder with images


# === Main script ===
def main():
    thresholds = list(range(10, 100, 10))  # [10, 20, ..., 90]
    results = []

    # Read CSV input
    with open(TEST_FILE_NAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            num1 = int(row["imagenum1"])
            num2 = int(row["imagenum2"])
            print(name, num1, num2)

            # Image paths
            filename1 = os.path.join(IMAGES_PATH, name, f"{name}_{num1:04d}.jpg")
            filename2 = os.path.join(IMAGES_PATH, name, f"{name}_{num2:04d}.jpg")

            result_row = {
                "name": name,
                "imagenum1": num1,
                "imagenum2": num2
            }

            similarity_score = -1
            try:
                emb1 = get_face_embedding(filename1)
                emb2 = get_face_embedding(filename2)
                similarity_score = compare_faces_score(emb1, emb2)
            except Exception as e:
                print(f"Error processing {name}: {e}")

            result_row["similarity"] = similarity_score

            for t in thresholds:
                result_row[f"t{t}"] = int(similarity_score >= t / 100)

            results.append(result_row)
            sys.stdout.flush()
            sys.stderr.flush()

    # Write results
    fieldnames = ["name", "imagenum1", "imagenum2", "similarity"] + [f"t{t}" for t in thresholds]
    with open(RESULTS_FILENAME, "w", newline="", encoding="utf-8") as outfile:
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"Results written to {RESULTS_FILENAME}")


if __name__ == "__main__":
    main()

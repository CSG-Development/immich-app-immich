import csv
import os
import sys
import cv2
import insightface
import numpy as np
from insightface.app import FaceAnalysis

# Initialize face analysis model
app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])  # Use "CUDAExecutionProvider" for GPU
app.prepare(ctx_id=-1)  # ctx_id=-1 for CPU, 0 for GPU

def get_face_embedding(image_path):
    """Extract face embedding from an image"""
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")
    
    faces = app.get(img)
    
    if len(faces) < 1:
        raise ValueError("No faces detected in the image")
    if len(faces) > 1:
        print("Warning: Multiple faces detected. Using first detected face")
    
    return faces[0].embedding

def compare_faces(emb1, emb2, threshold=0.65): # Adjust this threshold according to your usecase.
    """Compare two embeddings using cosine similarity"""
    similarity = np.dot(emb1, emb2) / (np.linalg.norm(emb1) * np.linalg.norm(emb2))
    return similarity, similarity > threshold

def compare_faces_score(emb1, emb2): # Adjust this threshold according to your usecase.
    """Compare two embeddings using cosine similarity"""
    similarity = np.dot(emb1, emb2) / (np.linalg.norm(emb1) * np.linalg.norm(emb2))
    return similarity

# === Configuration ===
TEST_FILE_NAME = "matchpairsDevTrain.csv"          # Input CSV file with columns: name, imagenum1, imagenum2
RESULTS_FILENAME = "match_results.csv"             # Output CSV file
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"  # Base folder with images

# === Mock test function (replace with your own implementation) ===
def test(filename1: str, filename2: str, threshold: int) -> int:
    """
    Placeholder for the real "test" function.
    Should return 0 or 1 depending on comparison result.
    """
    # Example dummy implementation
    return int((hash(filename1 + filename2 + str(threshold)) % 2) == 0)


# === Main script ===
def main():
    thresholds = list(range(10, 100, 10))  # [10, 20, ..., 90]
    results = []

    # Read input file
    with open(TEST_FILE_NAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            num1 = int(row["imagenum1"])
            num2 = int(row["imagenum2"])
            print(name, num1, num2)

            # Format image filenames with leading zeros (4 digits)
            filename1 = os.path.join(IMAGES_PATH, name, f"{name}_{num1:04d}.jpg")
            filename2 = os.path.join(IMAGES_PATH, name, f"{name}_{num2:04d}.jpg")

            # Compute results for each threshold
            result_row = {
                "name": name,
                "imagenum1": num1,
                "imagenum2": num2
            }

            similarity_score = -1
            try:
                # Get embeddings
                emb1 = get_face_embedding(filename1)
                emb2 = get_face_embedding(filename2)

                # Compare faces
                similarity_score = compare_faces_score(emb1, emb2)
            except Exception as e:
                print(f"Error: {e}")

            result_row["similarity"] = similarity_score

            for t in thresholds:
                result_row[f"t{t}"] = int(similarity_score >= t / 100)

            results.append(result_row)
            sys.stdout.flush()
            sys.stderr.flush()

    # Write results to output file
    fieldnames = ["name", "imagenum1", "imagenum2"] + ["similarity"] + [f"t{t}" for t in thresholds]
    with open(RESULTS_FILENAME, "w", newline="", encoding="utf-8") as outfile:
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"Results written to {RESULTS_FILENAME}")


if __name__ == "__main__":
    main()

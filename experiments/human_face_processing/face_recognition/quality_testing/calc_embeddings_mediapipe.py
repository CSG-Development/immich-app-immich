import csv
import os
import sys
import cv2
import numpy as np
import pickle
import mediapipe as mp

# Initialize face analysis model
mp_face_mesh = mp.solutions.face_mesh

def get_face_embedding(image_path):
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    with mp_face_mesh.FaceMesh(
        static_image_mode=True,
        max_num_faces=1,
        refine_landmarks=True,
        min_detection_confidence=0.5
    ) as face_mesh:
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        results = face_mesh.process(rgb)

        if not results.multi_face_landmarks:
            raise ValueError("No faces detected in the image")

        face_landmarks = results.multi_face_landmarks[0]
        h, w, _ = img.shape

        coords = np.array([[lm.x * w, lm.y * h, lm.z * w] for lm in face_landmarks.landmark])
        vector = coords.flatten()
        vector = vector / np.linalg.norm(vector)
        return vector


# === Configuration ===
INPUT_FILENAME = "all.csv"
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"
RESULTS_PATH = "embeddings/mediapipe"
OUTPUT_FILENAME = "all_mediapipe.csv"

# === Main script ===
def main():
    results = []

    # Read input file
    with open(INPUT_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        rows = [row for row in reader]
        for i, row in enumerate(rows):
            name = row["name"]
            num = int(row["imagenum"])
            print(i + 1, "/", len(rows), (i + 1) * 100 // len(rows), name, num)

            # Format image filenames with leading zeros (4 digits)
            image_filename = os.path.join(IMAGES_PATH, name, f"{name}_{num:04d}.jpg")
            output_filename = os.path.join(RESULTS_PATH, name, f"{name}_{num:04d}.pkl")

            # Compute results for each threshold
            result_row = {
                "name": name,
                "imagenum": num,
                "success": 0
            }

            similarity_score = -1
            try:
                emb = get_face_embedding(image_filename)
                os.makedirs(os.path.join(RESULTS_PATH, name), exist_ok=True)
                with open(output_filename, "wb") as f:
                    pickle.dump(emb, f)
                    result_row["success"] = 1

            except Exception as e:
                print(f"Error: {e}")

            results.append(result_row)
            sys.stdout.flush()
            sys.stderr.flush()

    # Write results to output file
    fieldnames = ["name", "imagenum", "success"]
    with open(OUTPUT_FILENAME, "w", newline="", encoding="utf-8") as outfile:
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"Results written to {OUTPUT_FILENAME}")

if __name__ == "__main__":
    main()

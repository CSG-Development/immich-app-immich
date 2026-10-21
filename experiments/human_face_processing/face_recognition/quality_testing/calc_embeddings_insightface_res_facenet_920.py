import csv
import os
import sys
import cv2
import pickle
import numpy as np
import insightface
from insightface.model_zoo import get_model
from insightface.utils import face_align

# === Initialize res-facenet model ===
# Note: This model only computes embeddings, so you must run face detection separately.
model = get_model("resnet-face-recognition-model-920", download=True)
model.prepare(ctx_id=-1)  # CPU; use ctx_id=0 for GPU

# Load a separate face detector (e.g., SCRFD)
detector = get_model("scrfd_10g_bnkps", download=True)
detector.prepare(ctx_id=-1)

def get_face_embedding(image_path):
    """Extract face embedding from an image using res-facenet model920"""
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    bboxes, kpss = detector.detect(img, det_thresh=0.5, input_size=(640, 640))

    if bboxes.shape[0] < 1:
        raise ValueError("No faces detected in the image")
    if bboxes.shape[0] > 1:
        print("Warning: Multiple faces detected. Using first detected face")

    # Align face using first keypoints set
    face_img = face_align.norm_crop(img, landmark=kpss[0])

    # Get embedding
    embedding = model.get_embedding(face_img)
    return embedding

# === Configuration ===
INPUT_FILENAME = "all.csv"
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"
RESULTS_PATH = "embeddings/insightface_res_facenet_920"
OUTPUT_FILENAME = "all_insightface_res_facenet_920.csv"

# === Main script ===
def main():
    results = []

    # Read input file
    with open(INPUT_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            num = int(row["imagenum"])
            print(name, num)

            # Format image filenames with leading zeros (4 digits)
            image_filename = os.path.join(IMAGES_PATH, name, f"{name}_{num:04d}.jpg")
            output_filename = os.path.join(RESULTS_PATH, name, f"{name}_{num:04d}.pkl")

            # Compute results for each image
            result_row = {
                "name": name,
                "imagenum": num,
                "success": 0
            }

            try:
                emb = get_face_embedding(image_filename)
                os.makedirs(os.path.join(RESULTS_PATH, name), exist_ok=True)
                with open(output_filename, "wb") as f:
                    pickle.dump(emb, f)
                    result_row["success"] = 1

            except Exception as e:
                print(f"Error processing {name}_{num:04d}: {e}")

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

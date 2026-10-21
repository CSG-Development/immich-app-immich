import csv
import os
import sys
import cv2
import torch
import pickle
import numpy as np
from res_facenet.models import model_920
from facenet_pytorch import MTCNN

# ============================================================
# Initialize models
# ============================================================

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Load FaceNet model (res-facenet)
model = model_920(pretrained=True).to(device)
model.eval()

# Face detector (MTCNN from facenet-pytorch)
mtcnn = MTCNN(image_size=224, margin=0, post_process=True, device=device)

# ============================================================
# Face embedding extraction
# ============================================================

def get_face_embedding(image_path):
    """Detects a face in an image and returns its embedding using res-facenet model_920."""
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    # Convert BGR → RGB for MTCNN
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Detect and align face
    face_tensor = mtcnn(img_rgb)
    if face_tensor is None:
        raise ValueError("No face detected in the image")

    face_tensor = face_tensor.unsqueeze(0).to(device)

    # Extract embedding
    with torch.no_grad():
        embedding = model(face_tensor).cpu().numpy().flatten()

    return embedding

# ============================================================
# === Configuration ===
# ============================================================

INPUT_FILENAME = "all.csv"
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"
RESULTS_PATH = "embeddings/res_facenet_920"
OUTPUT_FILENAME = "all_res_facenet_920.csv"

# ============================================================
# === Main script ===
# ============================================================

def main():
    results = []

    with open(INPUT_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            num = int(row["imagenum"])
            print(name, num)

            image_filename = os.path.join(IMAGES_PATH, name, f"{name}_{num:04d}.jpg")
            output_filename = os.path.join(RESULTS_PATH, name, f"{name}_{num:04d}.pkl")

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


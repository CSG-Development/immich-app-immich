import csv
import os
import sys
import cv2
import torch
from PIL import Image
import pickle
from facenet_pytorch import MTCNN, InceptionResnetV1

# === Initialize models ===
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# MTCNN for face detection and alignment
mtcnn = MTCNN(image_size=250, margin=0, min_face_size=20, device=device)

# InceptionResnetV1 for face embeddings (pretrained on VGGFace2)
resnet = InceptionResnetV1(pretrained="casia-webface").eval().to(device)


def get_face_embedding(image_path):
    """Extract a 512D face embedding from an image using facenet_pytorch"""
    try:
        img = Image.open(image_path).convert("RGB")
    except Exception as e:
        raise ValueError(f"Could not open image: {image_path} ({e})")

    # Detect and align face
    aligned_face = mtcnn(img)

    if aligned_face is None:
        raise ValueError(f"No face detected in {image_path}")

    # Compute embedding
    with torch.no_grad():
        embedding = resnet(aligned_face.unsqueeze(0).to(device)).cpu().numpy().flatten()

    return embedding

# === Configuration ===
INPUT_FILENAME = "all.csv"
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"
RESULTS_PATH = "embeddings/facenet_casia_webface"
OUTPUT_FILENAME = "all_facenet_casia_webface.csv"

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

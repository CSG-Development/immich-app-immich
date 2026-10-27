import csv
import os
import sys
import cv2
import insightface
import pickle
from insightface.app import FaceAnalysis
from insightface.model_zoo import get_model

# Initialize face analysis model
app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])  # Use 'CUDAExecutionProvider' for GPU
app.prepare(ctx_id=-1)  # ctx_id=-1 for CPU, 0 for GPU

custom_rec_model_path = "models/arcfaceresnet100-11-int8.onnx"

rec_model = get_model(custom_rec_model_path, providers=['CPUExecutionProvider'])
rec_model.prepare(ctx_id=-1) # Prepare the custom model for inference

app.rec_model = rec_model
app.models["recognition"] = rec_model

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

# === Configuration ===
INPUT_FILENAME = "all.csv"
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"
RESULTS_PATH = "embeddings/arcfaceresnet100-11-int8"
OUTPUT_FILENAME = "all_arcfaceresnet100-11-int8.csv"

# === Main script ===
def main():
    results = []

    # Read input file
    with open(INPUT_FILENAME, newline='', encoding='utf-8') as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row['name']
            num = int(row['imagenum'])
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

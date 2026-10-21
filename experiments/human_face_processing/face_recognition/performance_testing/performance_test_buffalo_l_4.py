import os
import cv2
import insightface
from insightface.app import FaceAnalysis
import psutil
import time

process = psutil.Process(os.getpid())

def get_face_embedding(image_path):
    """Extract face embedding from an image"""

    cpu = process.cpu_percent(interval=None)
    mem = process.memory_info().rss / (1024 ** 2)
    print(f",A,{cpu:.1f},{mem:.1f},")

    # Initialize face analysis model
    app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])  # Use "CUDAExecutionProvider" for GPU
    app.prepare(ctx_id=-1)  # ctx_id=-1 for CPU, 0 for GPU

    cpu = process.cpu_percent(interval=None)
    mem = process.memory_info().rss / (1024 ** 2)
    print(f",B,{cpu:.1f},{mem:.1f},")

    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    cpu = process.cpu_percent(interval=None)
    mem = process.memory_info().rss / (1024 ** 2)
    print(f",C,{cpu:.1f},{mem:.1f},")

    faces = app.get(img)

    cpu = process.cpu_percent(interval=None)
    mem = process.memory_info().rss / (1024 ** 2)
    print(f",D,{cpu:.1f},{mem:.1f},")

    if len(faces) < 1:
        raise ValueError("No faces detected in the image")
    if len(faces) > 1:
        print("Warning: Multiple faces detected. Using first detected face")

    cpu = process.cpu_percent(interval=None)
    mem = process.memory_info().rss / (1024 ** 2)
    print(f",E,{cpu:.1f},{mem:.1f},")

    return faces[0].embedding, cpu, mem

# === Configuration ===
IMAGE_PATH = "lfw-deepfunneled/lfw-deepfunneled//Aaron_Eckhart/Aaron_Eckhart_0001.jpg"

# === Main script ===
def main():
    for i in range(0, 11):
        step_start_time = time.time()
        embedding, cpu, mem = get_face_embedding(IMAGE_PATH)
        step_end_time = time.time()

        print(f"{i},F,{cpu:.1f},{mem:.1f},{step_end_time - step_start_time:.3f}")

if __name__ == "__main__":
    main()

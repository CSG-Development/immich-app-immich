import os
import cv2
import insightface
from insightface.app import FaceAnalysis
import psutil
import time
from memory_profiler import memory_usage

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

# === Configuration ===
IMAGE_PATH = "lfw-deepfunneled/lfw-deepfunneled//Aaron_Eckhart/Aaron_Eckhart_0001.jpg"

# === Main script ===
def main():
    process = psutil.Process(os.getpid())

    for i in range(0, 101):
        cpu = process.cpu_percent(interval=None)
        mem = process.memory_info().rss / (1024 ** 2)
        step_start_time = time.time()
        mem_usage = memory_usage((get_face_embedding, (IMAGE_PATH,)))
        step_end_time = time.time()

        print(f"{i},{cpu:.1f},{mem:.1f},{max(mem_usage):.2f},{step_end_time - step_start_time:.3f}")

if __name__ == "__main__":
    main()

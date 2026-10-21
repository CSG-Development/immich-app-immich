import os
import torch
from PIL import Image
from facenet_pytorch import MTCNN, InceptionResnetV1
import psutil
import time

# === Initialize models ===
device = torch.device("cpu")

# MTCNN for face detection and alignment
mtcnn = MTCNN(image_size=250, margin=0, min_face_size=20, device=device)

# InceptionResnetV1 for face embeddings (pretrained on VGGFace2)
resnet = InceptionResnetV1(pretrained="vggface2").eval().to(device)


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
IMAGE_PATH = "lfw-deepfunneled/lfw-deepfunneled//Aaron_Eckhart/Aaron_Eckhart_0001.jpg"

# === Main script ===
def main():
    process = psutil.Process(os.getpid())

    for i in range(0, 1001):
        step_start_time = time.time()
        embedding = get_face_embedding(IMAGE_PATH)
        step_end_time = time.time()
        cpu = process.cpu_percent(interval=None)
        mem = process.memory_info().rss / (1024 ** 2)

        print(f"{i},{cpu:.1f},{mem:.1f},{step_end_time - step_start_time:.3f}")

if __name__ == "__main__":
    main()

import os
import cv2
import insightface
from insightface.app import FaceAnalysis
from insightface.model_zoo import get_model
import psutil
import time
import onnxruntime as ort
import resource

# Get the default session options and modify them globally
_default_session_options = ort.capi._pybind_state.get_default_session_options()
def get_default_session_options_new():
    _default_session_options.inter_op_num_threads = 1
    _default_session_options.intra_op_num_threads = 1  # Set your desired thread count
    return _default_session_options

# Override the global function
ort.capi._pybind_state.get_default_session_options = get_default_session_options_new

# Initialize face analysis model
app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])  # Use 'CUDAExecutionProvider' for GPU
app.prepare(ctx_id=-1)  # ctx_id=-1 for CPU, 0 for GPU
custom_rec_model_path = "models/arcfaceresnet100-8.onnx"
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
IMAGE_PATH = "lfw-deepfunneled/lfw-deepfunneled//Aaron_Eckhart/Aaron_Eckhart_0001.jpg"

# === Main script ===
def main():
    process = psutil.Process(os.getpid())
    cpu_usage = []
    mem_usage = []
    run_times = []

    for i in range(0, 101):
        step_start_time = time.time()
        embedding = get_face_embedding(IMAGE_PATH)
        step_end_time = time.time()
        cpu = process.cpu_percent(interval=None)
        mem = process.memory_info().rss / (1024 ** 2)
        run_time = step_end_time - step_start_time
        if i > 0:
            cpu_usage.append(cpu)
            mem_usage.append(mem)
            run_times.append(run_time)
        print(f"{i},{cpu:.1f},{mem:.1f},{run_time:.3f}")

    avg_cpu = sum(cpu_usage) / len(cpu_usage)
    avg_mem = sum(mem_usage) / len(mem_usage)
    avg_time = sum(run_times) / len(run_times)
    print(f"Average cpu usage: {avg_cpu:.1f}")
    print(f"Average mem usage: {avg_mem:.1f}")
    print(f"Average run time: {avg_time:.3f}")
    print(f"{avg_cpu:.1f},{avg_mem:.1f},{avg_time:.3f}")

if __name__ == "__main__":
    main()
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    print("Max memory usage: {:.2f} MB".format(peak / 1024))

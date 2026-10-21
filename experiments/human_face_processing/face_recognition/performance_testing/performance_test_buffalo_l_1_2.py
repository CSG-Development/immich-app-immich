import os
import cv2
import insightface
from insightface.app import FaceAnalysis
from insightface.model_zoo import get_model
import psutil
import time

import onnxruntime as ort

# Get the default session options and modify them globally
_default_session_options = ort.capi._pybind_state.get_default_session_options()
def get_default_session_options_new():
    _default_session_options.intra_op_num_threads = 1  # Set your desired thread count
    return _default_session_options

# Override the global function
ort.capi._pybind_state.get_default_session_options = get_default_session_options_new

import resource

# Initialize face analysis model
custom_det_model_path = "models/det_10g.onnx"
det_model = insightface.model_zoo.get_model(custom_det_model_path, providers=["CPUExecutionProvider"])
det_model.prepare(ctx_id=-1, input_size=(640, 640), det_tresh=0.5) # Prepare the custom model for inference

def det_get(img, max_num=0, det_metric="default"):
    bboxes, kpss = det_model.detect(img, max_num=max_num, metric=det_metric)
    return bboxes, kpss

def get_faces(image_path):
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    bboxes, kpss = det_get(img)

    return bboxes, kpss

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
        bboxes, kpss = get_faces(IMAGE_PATH)
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

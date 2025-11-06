from typing import Any

import torch
import numpy as np
from insightface.model_zoo import RetinaFace
from numpy.typing import NDArray

from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import decode_cv2
from immich_ml.schemas import FaceDetectionOutput, ModelSession, ModelTask, ModelType
from immich_ml.config import log

class FaceDetector(InferenceModel):
    depends = []
    identity = (ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str, min_score: float = 0.7, **model_kwargs: Any) -> None:
        self.min_score = model_kwargs.pop("minScore", min_score)
        super().__init__(model_name, **model_kwargs)

    def _load(self) -> ModelSession:
        device = "cuda:0" if torch.cuda.is_available() else "cpu"

        # Path to ONNX model file
        model_path = self.model_path_for_format(ModelFormat.ONNX).as_posix()

        # Create ONNXRuntime session
        session = self._make_session(model_path)

        self.model = RetinaFace(session=session)
        self.model.prepare(
          ctx_id=0 if "cuda" in device else -1,
          det_thresh=self.min_score,
          input_size=(640, 640)
        )

        return session

    def download(self) -> None:
        # Override base download method to do nothing
        log.info(f"Skipping download for FaceDetector ({self.model_name})")

    def _predict(self, inputs: NDArray[np.uint8] | bytes, **kwargs: Any) -> FaceDetectionOutput:
        inputs = decode_cv2(inputs)

        boxes, probs, landmarks = self._detect(inputs)

        # Defensive checks
        if boxes is None or not isinstance(boxes, (list, tuple, np.ndarray)) or np.size(boxes) == 0:
            return {
                "boxes": np.empty((0, 4), dtype=int),
                "scores": np.empty((0,), dtype=float),
                "landmarks": np.empty((0, 5, 2), dtype=float),
            }

        # Convert all to numpy arrays, ensure proper dtypes
        boxes = np.asarray(boxes, dtype=np.float32)
        probs = np.asarray(probs, dtype=np.float32)
        landmarks = np.asarray(landmarks, dtype=np.float32)

        # Additional check in case probs is NaN or float instead of list/array
        if probs.ndim == 0 or np.isnan(probs).any():
            log.warning("[FaceDetector] Invalid probs output, skipping frame")
            return {
                "boxes": np.empty((0, 4), dtype=int),
                "scores": np.empty((0,), dtype=float),
                "landmarks": np.empty((0, 5, 2), dtype=float),
            }

        return {
            "boxes": np.round(boxes).astype(int),
            "scores": probs,
            "landmarks": landmarks,
        }

#     def _detect(self, inputs: NDArray[np.uint8] | bytes) -> tuple[NDArray[np.float32], NDArray[np.float32]]:
#         return self.model.detect(inputs)  # type: ignore
    def _detect(self, inputs: NDArray[np.uint8]) -> tuple[
        NDArray[np.float32] | None,
        list[float] | None,
        NDArray[np.float32] | None,
    ]:
        # This can return None for any of the values
        return self.model.detect(inputs, landmarks=True)

#     def configure(self, **kwargs: Any) -> None:
#         self.model.det_thresh = kwargs.pop("minScore", self.model.det_thresh)
    def configure(self, **kwargs: Any) -> None:
        new_thresh = kwargs.pop("minScore", self.min_score)
        self.model.thresholds = [new_thresh] * 3

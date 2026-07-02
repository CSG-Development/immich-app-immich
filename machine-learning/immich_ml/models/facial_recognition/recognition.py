from typing import Any

import cv2
import numpy as np
import onnxruntime as ort
from insightface.model_zoo.arcface_onnx import ArcFaceONNX
from numpy.typing import NDArray
from PIL import Image

from immich_ml.config import log, settings
from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import decode_cv2, serialize_np_array
from immich_ml.schemas import (
    FaceDetectionOutput,
    FacialRecognitionOutput,
    ModelFormat,
    ModelSession,
    ModelTask,
    ModelType,
)


from immich_ml.timing import elapsed_ms

class FaceRecognizer(InferenceModel):
    depends = [(ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)]
    identity = (ModelType.RECOGNITION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str, **model_kwargs: Any) -> None:
        super().__init__(model_name, **model_kwargs)
        max_batch_size = settings.max_batch_size.facial_recognition if settings.max_batch_size else None
        self.batch_size = max_batch_size if max_batch_size else self._batch_size_default

    def _load(self) -> ModelSession:
        log.info(f"[%.3f ms] FaceRecognizer._load:START", elapsed_ms())

        # Path to ONNX model file
        model_path = self.model_path_for_format(ModelFormat.ONNX)

        # Create ONNXRuntime session
        session = self._make_session(model_path)

        # Initialize ArcFaceONNX wrapper
        self.model = ArcFaceONNX(
            model_path,
            session=session,
        )

        log.info(f"[%.3f ms] FaceRecognizer._load:END", elapsed_ms())

        return session

    def download(self) -> None:
        # Override base download method to do nothing
        log.info(f"Skipping download for FaceRecognizer ({self.model_name})")

    def _predict(
        self, inputs: NDArray[np.uint8] | bytes | Image.Image, faces: FaceDetectionOutput, **kwargs: Any
    ) -> FacialRecognitionOutput:
        log.info(f"[%.3f ms] FaceRecognizer._predict:START", elapsed_ms())
        if faces["boxes"].shape[0] == 0:
            return []
        inputs = decode_cv2(inputs)
        cropped_faces = self._crop(inputs, faces)
        embeddings = self._predict_batch(cropped_faces)
        #return self.postprocess(faces, embeddings)
        result = self.postprocess(faces, embeddings)
        log.info(f"[%.3f ms] FaceRecognizer._predict:END", elapsed_ms())
        return result

    def _predict_batch(self, cropped_faces: list[NDArray[np.uint8]]) -> NDArray[np.float32]:
        batch_embeddings: list[NDArray[np.float32]] = []

        for i in range(0, len(cropped_faces), self.batch_size or 1):
            batch = cropped_faces[i : i + (self.batch_size or 1)]
            for face in batch:
                # Wrap single image in a list so get_feat sees batch size 1
                emb = self.model.get_feat([face])
                batch_embeddings.append(emb)

        return np.concatenate(batch_embeddings, axis=0)

    def postprocess(self, faces: FaceDetectionOutput, embeddings: NDArray[np.float32]) -> FacialRecognitionOutput:
        log.info(f"[%.3f ms] FaceRecognizer.postprocess:START", elapsed_ms())
        #return [
        #    {
        #        "boundingBox": {"x1": x1, "y1": y1, "x2": x2, "y2": y2},
        #        "embedding": serialize_np_array(embedding),
        #        "score": score,
        #    }
        #    for (x1, y1, x2, y2), embedding, score in zip(faces["boxes"], embeddings, faces["scores"])
        #]
        result = [
            {
                "boundingBox": {"x1": x1, "y1": y1, "x2": x2, "y2": y2},
                "embedding": serialize_np_array(embedding),
                "score": score,
            }
            for (x1, y1, x2, y2), embedding, score in zip(faces["boxes"], embeddings, faces["scores"])
        ]
        log.info(f"[%.3f ms] FaceRecognizer.postprocess:END", elapsed_ms())
        return result

    def _crop(self, image: NDArray[np.uint8], faces: FaceDetectionOutput) -> list[NDArray[np.uint8]]:
        log.info(f"[%.3f ms] FaceRecognizer._crop:START", elapsed_ms())
        reference = np.array([
            [38.2946, 51.6963],
            [73.5318, 51.5014],
            [56.0252, 71.7366],
            [41.5493, 92.3655],
            [70.7299, 92.2041],
        ], dtype=np.float32)

        aligned_faces = []
        output_size = (112, 112)

        for landmark in faces["landmarks"]:
            src = np.array(landmark, dtype=np.float32)
            transform = cv2.estimateAffinePartial2D(src, reference, method=cv2.LMEDS)[0]
            aligned = cv2.warpAffine(image, transform, output_size, borderValue=0.0)
            aligned_faces.append(aligned)

        log.info(f"[%.3f ms] FaceRecognizer._crop:END", elapsed_ms())
        return aligned_faces

    @property
    def _batch_size_default(self) -> int | None:
        providers = ort.get_available_providers()
        return None if self.model_format == ModelFormat.ONNX and "OpenVINOExecutionProvider" not in providers else 1

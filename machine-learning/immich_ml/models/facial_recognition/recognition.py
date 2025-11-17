from pathlib import Path
from typing import Any
import cv2
import numpy as np
from numpy.typing import NDArray
from PIL import Image
import onnxruntime as ort
from insightface.model_zoo.arcface_onnx import ArcFaceONNX

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

class FaceRecognizer(InferenceModel):
    depends = [(ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)]
    identity = (ModelType.RECOGNITION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str, **model_kwargs: Any) -> None:
        super().__init__(model_name, **model_kwargs)
        max_batch_size = settings.max_batch_size.facial_recognition if settings.max_batch_size else None
        self.batch_size = max_batch_size if max_batch_size else self._batch_size_default

    def _load(self) -> ModelSession:
        # Path to ONNX model file
        model_path = self.model_path_for_format(ModelFormat.ONNX)

        # Create ONNXRuntime session
        session = self._make_session(model_path)

#         # If your session input has static batch dim and you need dynamic batching
#         if (not self.batch_size or self.batch_size > 1) and str(session.get_inputs()[0].shape[0]) != "batch":
#             self._add_batch_axis(self.model_path)
#             session = self._make_session(model_path)

        # Initialize ArcFaceONNX wrapper
        self.model = ArcFaceONNX(
            model_path,
            session=session,
        )

        return session

    def download(self) -> None:
        # Override base download method to do nothing
        log.info(f"Skipping download for FaceRecognizer ({self.model_name})")

    def _predict(
        self, inputs: NDArray[np.uint8] | bytes | Image.Image, faces: FaceDetectionOutput, **kwargs: Any
    ) -> FacialRecognitionOutput:
        if faces["boxes"].shape[0] == 0:
            return []
        inputs = decode_cv2(inputs)
        cropped_faces = self._crop(inputs, faces)
        embeddings = self._predict_batch(cropped_faces)
        return self.postprocess(faces, embeddings)

    def _predict_batch(self, cropped_faces: list[NDArray[np.uint8]]) -> NDArray[np.float32]:
        batch_embeddings: list[NDArray[np.float32]] = []

        for i in range(0, len(cropped_faces), self.batch_size or 1):
            batch = cropped_faces[i : i + (self.batch_size or 1)]
            for face in batch:
                # Wrap single image in a list so get_feat sees batch size 1
                emb = self.model.get_feat([face])
                batch_embeddings.append(emb)

        return np.concatenate(batch_embeddings, axis=0)
#         preprocess = transforms.Compose([
#             transforms.ToTensor(),  # Converts to (C, H, W), normalizes to [0,1]
#             transforms.Normalize(mean=[0.5]*3, std=[0.5]*3),  # Scale to [-1,1]
#         ])
#
#         batch = torch.stack([preprocess(Image.fromarray(face)) for face in cropped_faces]).to(device)
#         with torch.no_grad():
#             embeddings = self.model(batch)
#
#         return embeddings.cpu().numpy() <- For Facenet Pytorch

    def postprocess(self, faces: FaceDetectionOutput, embeddings: NDArray[np.float32]) -> FacialRecognitionOutput:
        return [
            {
                "boundingBox": {"x1": x1, "y1": y1, "x2": x2, "y2": y2},
                "embedding": serialize_np_array(embedding),
                "score": score,
            }
            for (x1, y1, x2, y2), embedding, score in zip(faces["boxes"], embeddings, faces["scores"])
        ]

#     def _crop(self, image: NDArray[np.uint8], faces: FaceDetectionOutput) -> list[NDArray[np.uint8]]:
#         return [norm_crop(image, landmark) for landmark in faces["landmarks"]]
    def _crop(self, image: NDArray[np.uint8], faces: FaceDetectionOutput) -> list[NDArray[np.uint8]]:
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

        return aligned_faces

#     def _add_batch_axis(self, model_path: Path) -> None:
#         log.debug(f"Adding batch axis to model {model_path}")
#         proto = onnx.load(model_path)
#         static_input_dims = [shape.dim_value for shape in proto.graph.input[0].type.tensor_type.shape.dim[1:]]
#         static_output_dims = [shape.dim_value for shape in proto.graph.output[0].type.tensor_type.shape.dim[1:]]
#         input_dims = {proto.graph.input[0].name: ["batch"] + static_input_dims}
#         output_dims = {proto.graph.output[0].name: ["batch"] + static_output_dims}
#         updated_proto = update_inputs_outputs_dims(proto, input_dims, output_dims)
#         onnx.save(updated_proto, model_path)

    @property
    def _batch_size_default(self) -> int | None:
        providers = ort.get_available_providers()
        return None if self.model_format == ModelFormat.ONNX and "OpenVINOExecutionProvider" not in providers else 1

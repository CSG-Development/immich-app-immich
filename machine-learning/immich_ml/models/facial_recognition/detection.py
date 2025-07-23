from typing import Any

import numpy as np
# from insightface.model_zoo import RetinaFace
from facenet_pytorch import MTCNN
from numpy.typing import NDArray

from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import decode_cv2
from immich_ml.schemas import FaceDetectionOutput, ModelSession, ModelTask, ModelType


class FaceDetector(InferenceModel):
    depends = []
    identity = (ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str, min_score: float = 0.7, **model_kwargs: Any) -> None:
        self.min_score = model_kwargs.pop("minScore", min_score)
        super().__init__(model_name, **model_kwargs)

    def _load(self) -> ModelSession:
        self.model = MTCNN(keep_all=True, thresholds=[self.min_score]*3, post_process=False, device="cuda:0")
        return self._make_session("facenet-pytorch::MTCNN")
#         session = self._make_session(self.model_path)
#         self.model = RetinaFace(session=session)
#         self.model.prepare(ctx_id=0, det_thresh=self.min_score, input_size=(640, 640))
#
#         return session


    def _predict(self, inputs: NDArray[np.uint8] | bytes, **kwargs: Any) -> FaceDetectionOutput:
        inputs = decode_cv2(inputs)

#         bboxes, landmarks = self._detect(inputs)
        bboxes, probs, landmarks = self._detect(inputs)
#         return {
#             "boxes": bboxes[:, :4].round(),
#             "scores": bboxes[:, 4],
#             "landmarks": landmarks,
#         }
        if bboxes is None or len(bboxes) == 0:
            return {
                "boxes": np.zeros((0, 4)),
                "scores": np.zeros((0,)),
                "landmarks": np.zeros((0, 5, 2)),
            }

        return {
            "boxes": np.round(bboxes).astype(np.float32),
            "scores": np.array(probs),
            "landmarks": np.array(landmarks),
        }

#     def _detect(self, inputs: NDArray[np.uint8] | bytes) -> tuple[NDArray[np.float32], NDArray[np.float32]]:
#         return self.model.detect(inputs)  # type: ignore
    def _detect(self, inputs: NDArray[np.uint8]) -> tuple[NDArray[np.float32], list[float], NDArray[np.float32]]:
        boxes, probs, landmarks = self.model.detect(inputs, landmarks=True)
        return boxes, probs, landmarks

#     def configure(self, **kwargs: Any) -> None:
#         self.model.det_thresh = kwargs.pop("minScore", self.model.det_thresh)
    def configure(self, **kwargs: Any) -> None:
        new_thresh = kwargs.pop("minScore", self.min_score)
        self.model.thresholds = [new_thresh] * 3

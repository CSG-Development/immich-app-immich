from typing import Any

import numpy as np
from insightface.model_zoo import SCRFD
from numpy.typing import NDArray

from immich_ml.models.base import InferenceModel
from immich_ml.models.transforms import decode_cv2
from immich_ml.schemas import FaceDetectionOutput, ModelSession, ModelTask, ModelType

from immich_ml.config import log
from immich_ml.timing import elapsed_ms

class FaceDetector(InferenceModel):
    depends = []
    identity = (ModelType.DETECTION, ModelTask.FACIAL_RECOGNITION)

    def __init__(self, model_name: str = "scrfd_10g_gnkps", min_score: float = 0.5, **model_kwargs: Any) -> None:
        self.min_score = model_kwargs.pop("minScore", min_score)
        super().__init__(model_name, **model_kwargs)

    def _load(self) -> ModelSession:
            log.info(f"[%.3f ms] FaceDetector._load:START", elapsed_ms())

            session = self._make_session(self.model_path)
            self.model = SCRFD(session=session)
            self.model.prepare(ctx_id=0, det_thresh=self.min_score, input_size=(640, 640))

            log.info(f"[%.3f ms] FaceDetector._load:END", elapsed_ms())

            return session

    def _predict(self, inputs: NDArray[np.uint8] | bytes, **kwargs: Any) -> FaceDetectionOutput:
            log.info(f"[%.3f ms] FaceDetector._predict:START", elapsed_ms())

            inputs = decode_cv2(inputs)

            bboxes, landmarks = self._detect(inputs)
            #return {
            #    "boxes": bboxes[:, :4].round(),
            #    "scores": bboxes[:, 4],
            #    "landmarks": landmarks,
            #}
            result = {
                "boxes": bboxes[:, :4].round(),
                "scores": bboxes[:, 4],
                "landmarks": landmarks,
            }
            log.info(f"[%.3f ms] FaceDetector._predict:END", elapsed_ms())
            return result

    def _detect(self, inputs: NDArray[np.uint8] | bytes) -> tuple[NDArray[np.float32], NDArray[np.float32]]:
        log.info(f"[%.3f ms] FaceDetector._detect:START", elapsed_ms())
        #return self.model.detect(inputs)  # type: ignore
        result = self.model.detect(inputs)
        log.info(f"[%.3f ms] FaceDetector._detect:END", elapsed_ms())
        return result

    def configure(self, **kwargs: Any) -> None:
        self.model.det_thresh = kwargs.pop("minScore", self.model.det_thresh)

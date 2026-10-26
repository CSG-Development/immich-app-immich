import csv
import os
import sys
import pickle
import random

import cv2
import numpy as np

import torch
import torch.nn as nn
import torch.nn.functional as F

from torchvision import models, transforms
from torchvision.transforms import functional as TF

from losses import SoftmaxBasedMetricLearning


seed = 42

random.seed(seed)
np.random.seed(seed)

torch.manual_seed(seed)
torch.cuda.manual_seed_all(seed)

torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False

DEVICE = torch.device(
    "cuda" if torch.cuda.is_available() else "cpu"
)

CHECKPOINT_HEAD = (
    "configs/to_reproduce/dog_fe/epoch=36_head.ckpt"
)

IMAGES_PATH = (
    "../pets_datasets/petfinder_extra_dogs_transformed_v6"
)

TMP_PICKLE = "__compare_tmp.pkl"

STOP_ON_FIRST_DIFFERENCE = False

EPS = 1e-12

TEST_PAIRS = [

    (
        ("10298430", 2),
        ("10298430", 1),
    ),

    (
        ("20080044", 0),
        ("20080044", 1),
    ),

    (
        ("27818785", 0),
        ("27818785", 1),
    ),

    (
        ("37513258", 0),
        ("37513258", 1),
    ),

    (
        ("46744476", 0),
        ("46744476", 1),
    ),

]


def image_path(name, num):
    return os.path.join(
        IMAGES_PATH,
        name,
        f"{num}.png",
    )


def print_header(title):
    print()
    print("=" * 80)
    print(title)
    print("=" * 80)


def stop_if_needed(ok):
    if ok:
        return

    if STOP_ON_FIRST_DIFFERENCE:
        raise RuntimeError(
            "First difference detected."
        )


def print_tensor_stats(title, tensor):
    tensor = tensor.detach().float().cpu()

    print(title)

    print(f"  shape : {tuple(tensor.shape)}")
    print(f"  dtype : {tensor.dtype}")

    print(
        f"  min   : {tensor.min().item():.10f}"
    )

    print(
        f"  max   : {tensor.max().item():.10f}"
    )

    print(
        f"  mean  : {tensor.mean().item():.10f}"
    )

    print(
        f"  std   : {tensor.std().item():.10f}"
    )


def compare_tensor(title, t1, t2):
    print_header(title)

    t1 = t1.detach().float().cpu()
    t2 = t2.detach().float().cpu()

    print_tensor_stats(
        "Realtime Pipeline",
        t1,
    )

    print()

    print_tensor_stats(
        "Stored Embeddings Pipeline",
        t2,
    )

    print()

    if tuple(t1.shape) != tuple(t2.shape):

        print("Result")
        print("------")
        print("Tensor shapes are different.")
        print()

        print(
            f"Realtime Pipeline        : {tuple(t1.shape)}"
        )

        print(
            f"Stored Embeddings Pipeline: {tuple(t2.shape)}"
        )

        print()
        print(
            "Element-wise comparison skipped."
        )

        stop_if_needed(False)

        return False

    diff = (t1 - t2).abs()

    max_diff = diff.max().item()
    mean_diff = diff.mean().item()

    cosine = F.cosine_similarity(
        t1.reshape(1, -1),
        t2.reshape(1, -1),
    ).item()

    identical = torch.equal(
        t1,
        t2,
    )

    print("Result")
    print("------")

    print(
        f"Max abs diff : {max_diff:.12f}"
    )

    print(
        f"Mean abs diff: {mean_diff:.12f}"
    )

    print(
        f"Cosine       : {cosine:.12f}"
    )

    print(
        f"Identical    : {identical}"
    )

    stop_if_needed(identical)

    return identical


def compare_numpy(title, arr1, arr2):
    print_header(title)

    print("Realtime Pipeline")

    print(
        f"  shape : {arr1.shape}"
    )

    print()

    print("Stored Embeddings Pipeline")

    print(
        f"  shape : {arr2.shape}"
    )

    print()

    if arr1.shape != arr2.shape:

        print("Result")
        print("------")
        print("Array shapes are different.")
        print()

        stop_if_needed(False)

        return False

    diff = np.abs(
        arr1.astype(np.float32)
        -
        arr2.astype(np.float32)
    )

    identical = np.array_equal(
        arr1,
        arr2,
    )

    print("Result")
    print("------")

    print(
        f"Max abs diff : {diff.max():.12f}"
    )

    print(
        f"Mean abs diff: {diff.mean():.12f}"
    )

    print(
        f"Identical    : {identical}"
    )

    stop_if_needed(identical)

    return identical


def compare_pil(title, img1, img2):
    print_header(title)

    print("Realtime Pipeline")

    print(
        f"  size : {img1.size}"
    )

    print(
        f"  mode : {img1.mode}"
    )

    print()

    print("Stored Embeddings Pipeline")

    print(
        f"  size : {img2.size}"
    )

    print(
        f"  mode : {img2.mode}"
    )

    print()

    arr1 = np.array(img1)
    arr2 = np.array(img2)

    if arr1.shape != arr2.shape:

        print("Result")
        print("------")
        print("Image shapes are different.")
        print()

        print(
            f"Realtime Pipeline         : {arr1.shape}"
        )

        print(
            f"Stored Embeddings Pipeline: {arr2.shape}"
        )

        print()

        stop_if_needed(False)

        return False

    diff = np.abs(
        arr1.astype(np.float32)
        -
        arr2.astype(np.float32)
    )

    identical = np.array_equal(
        arr1,
        arr2,
    )

    print("Result")
    print("------")

    print(
        f"Max abs diff : {diff.max():.12f}"
    )

    print(
        f"Mean abs diff: {diff.mean():.12f}"
    )

    print(
        f"Identical    : {identical}"
    )

    stop_if_needed(identical)

    return identical


def compare_pickle(title, tensor):
    print_header(title)

    with open(
        TMP_PICKLE,
        "wb",
    ) as f:

        pickle.dump(
            tensor,
            f,
        )

    with open(
        TMP_PICKLE,
        "rb",
    ) as f:

        loaded = pickle.load(f)

    compare_tensor(
        "Tensor before and after pickle",
        tensor,
        loaded,
    )

    if os.path.exists(
        TMP_PICKLE,
    ):
        os.remove(
            TMP_PICKLE,
        )


def similarity_f(t1, t2):
    return (
        F.cosine_similarity(
            t1,
            t2,
        )
        + 1.0
    ) / 2.0


def build_resnet50():
    model = models.resnet50(
        weights=models.ResNet50_Weights.IMAGENET1K_V1
    )

    model.fc = nn.Linear(
        2048,
        512,
    )

    return model


class RealtimePipeline:
    def __init__(self, checkpoint_path):
        backbone = build_resnet50()

        self.model = SoftmaxBasedMetricLearning(
            model=backbone,
            num_class=1,
            embedding_size=512,
            arc_margin=True,
            is_focal=True,
        )

        checkpoint = torch.load(
            checkpoint_path,
            map_location=DEVICE,
        )

        self.model.load_state_dict(
            checkpoint,
            strict=False,
        )

        self.model.eval()
        self.model.add_margin = None
        self.model.to(DEVICE)

        self.preprocess = transforms.Compose([
            transforms.ToPILImage(),
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ])

    # ------------------------------------------------------

    def read_image(self, filename):
        image = cv2.imread(filename)

        if image is None:
            raise RuntimeError(
                f"Cannot read image: {filename}"
            )

        return image

    # ------------------------------------------------------

    def preprocess_step_by_step(self, image):
        pil = transforms.ToPILImage()(image)

        resized = TF.resize(
            pil,
            [224, 224],
        )

        tensor = TF.to_tensor(
            resized,
        )

        normalized = TF.normalize(
            tensor,
            mean=[0.485, 0.456, 0.406],
            std=[0.229, 0.224, 0.225],
        )

        batch = (
            normalized
            .unsqueeze(0)
            .to(DEVICE)
        )

        return {
            "pil": pil,
            "resize": resized,
            "tensor": tensor,
            "normalized": normalized,
            "batch": batch,
        }

    # ------------------------------------------------------

    def forward(self, batch):
        with torch.no_grad():
            embedding = self.model(batch)

        return embedding.cpu()


class StoredEmbeddingsPipeline:
    def __init__(self, checkpoint_path):
        backbone = build_resnet50()

        self.model = SoftmaxBasedMetricLearning(
            model=backbone,
            num_class=1,
            embedding_size=512,
            arc_margin=True,
            is_focal=True,
        )

        checkpoint = torch.load(
            checkpoint_path,
            map_location=DEVICE,
        )

        state_dict = checkpoint.get(
            "state_dict",
            checkpoint,
        )

        missing, unexpected = self.model.load_state_dict(
            state_dict,
            strict=False,
        )

        print_header("Stored Embeddings Pipeline")

        print(
            f"Missing keys    : {len(missing)}"
        )

        print(
            f"Unexpected keys : {len(unexpected)}"
        )

        self.model.eval()
        self.model.add_margin = None
        self.model.to(DEVICE)

        self.preprocess = transforms.Compose([
            transforms.ToPILImage(),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ])

    # ------------------------------------------------------

    def read_image(self, filename):
        image = cv2.imread(filename)

        if image is None:
            raise RuntimeError(
                f"Cannot read image: {filename}"
            )

        return image

    # ------------------------------------------------------

    def preprocess_step_by_step(self, image):
        pil = transforms.ToPILImage()(image)

        resized = pil

        tensor = TF.to_tensor(
            resized,
        )

        normalized = TF.normalize(
            tensor,
            mean=[0.485, 0.456, 0.406],
            std=[0.229, 0.224, 0.225],
        )

        batch = (
            normalized
            .unsqueeze(0)
            .to(DEVICE)
        )

        return {
            "pil": pil,
            "resize": resized,
            "tensor": tensor,
            "normalized": normalized,
            "batch": batch,
        }

    # ------------------------------------------------------

    def forward(self, batch):

        with torch.no_grad():
            embedding = self.model(batch)

        return embedding.cpu()


def compare_pipeline(
    realtime,
    stored,
    image_path,
):
    print_header(
        f"COMPARE IMAGE\n{image_path}"
    )

    image_rt = realtime.read_image(
        image_path,
    )

    image_st = stored.read_image(
        image_path,
    )

    compare_numpy(
        "STEP 1 : cv2.imread()",
        image_rt,
        image_st,
    )

    # ------------------------------------------------------
    # Step-By-Step Processing
    # ------------------------------------------------------

    prep_rt = realtime.preprocess_step_by_step(
        image_rt,
    )

    prep_st = stored.preprocess_step_by_step(
        image_st,
    )

    # ------------------------------------------------------
    # PIL
    # ------------------------------------------------------

    compare_pil(
        "STEP 2 : ToPILImage()",
        prep_rt["pil"],
        prep_st["pil"],
    )

    # ------------------------------------------------------
    # Resize
    # ------------------------------------------------------

    compare_pil(
        "STEP 3 : Resize()",
        prep_rt["resize"],
        prep_st["resize"],
    )

    # ------------------------------------------------------
    # ToTensor
    # ------------------------------------------------------

    compare_tensor(
        "STEP 4 : ToTensor()",
        prep_rt["tensor"],
        prep_st["tensor"],
    )

    # ------------------------------------------------------
    # Normalize
    # ------------------------------------------------------

    compare_tensor(
        "STEP 5 : Normalize()",
        prep_rt["normalized"],
        prep_st["normalized"],
    )

    # ------------------------------------------------------
    # Batch
    # ------------------------------------------------------

    compare_tensor(
        "STEP 6 : Batch",
        prep_rt["batch"],
        prep_st["batch"],
    )

    # ------------------------------------------------------
    # Forward
    # ------------------------------------------------------

    emb_rt = realtime.forward(
        prep_rt["batch"],
    )

    emb_st = stored.forward(
        prep_st["batch"],
    )

    compare_tensor(
        "STEP 7 : Embedding",
        emb_rt,
        emb_st,
    )

    # ------------------------------------------------------
    # Pickle
    # ------------------------------------------------------

    compare_pickle(
        "STEP 8 : Pickle (Realtime Pipeline)",
        emb_rt,
    )

    compare_pickle(
        "STEP 9 : Pickle (Stored Embeddings Pipeline)",
        emb_st,
    )

    return (
        emb_rt,
        emb_st,
    )


def compare_similarity(
    emb1_rt,
    emb2_rt,
    emb1_st,
    emb2_st,
):

    cosine_rt = F.cosine_similarity(
        emb1_rt,
        emb2_rt,
    ).item()

    cosine_st = F.cosine_similarity(
        emb1_st,
        emb2_st,
    ).item()

    similarity_rt = similarity_f(
        emb1_rt,
        emb2_rt,
    ).item()

    similarity_st = similarity_f(
        emb1_st,
        emb2_st,
    ).item()

    print()

    print("Realtime Pipeline")
    print("-----------------")
    print(f"Cosine     : {cosine_rt:.12f}")
    print(f"Similarity : {similarity_rt:.12f}")

    print()

    print("Stored Embeddings Pipeline")
    print("--------------------------")
    print(f"Cosine     : {cosine_st:.12f}")
    print(f"Similarity : {similarity_st:.12f}")

    print()

    print("Difference")
    print("----------")
    print(
        f"Cosine diff     : {abs(cosine_rt-cosine_st):.12f}"
    )

    print(
        f"Similarity diff : {abs(similarity_rt-similarity_st):.12f}"
    )

    identical = (
        abs(similarity_rt - similarity_st)
        < EPS
    )

    print()
    print(
        f"Identical : {identical}"
    )

    return identical


# ==========================================================
# Main
# ==========================================================
def main():
    realtime = RealtimePipeline(
        CHECKPOINT_HEAD,
    )

    stored = StoredEmbeddingsPipeline(
        CHECKPOINT_HEAD,
    )

    passed = 0

    total = len(TEST_PAIRS)

    for index, pair in enumerate(TEST_PAIRS, 1):

        (name1, num1), (name2, num2) = pair

        image1 = image_path(
            name1,
            num1,
        )

        image2 = image_path(
            name2,
            num2,
        )

        print()
        print("=" * 80)
        print(
            f"TEST {index} / {total}"
        )
        print("=" * 80)

        print()
        print(
            f"Image #1 : {image1}"
        )

        emb1_rt, emb1_st = compare_pipeline(
            realtime,
            stored,
            image1,
        )

        print()
        print(
            f"Image #2 : {image2}"
        )

        emb2_rt, emb2_st = compare_pipeline(
            realtime,
            stored,
            image2,
        )

        print_header(
            "STEP 10 : Similarity"
        )

        ok = compare_similarity(
            emb1_rt,
            emb2_rt,
            emb1_st,
            emb2_st,
        )

        if ok:
            passed += 1

    print()
    print("=" * 80)
    print("FINAL SUMMARY")
    print("=" * 80)

    print(
        f"Passed : {passed}"
    )

    print(
        f"Failed : {total-passed}"
    )

    print(
        f"Total  : {total}"
    )

    if passed == total:

        print()
        print(
            "Realtime Pipeline and Stored Embeddings Pipeline "
            "produce identical similarities "
            "for all tested image pairs."
        )

    else:

        print()
        print(
            "Similarity differences were detected."
        )


if __name__ == "__main__":
    main()

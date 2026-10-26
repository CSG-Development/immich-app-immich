import csv
import os
import sys
import pickle
import random

import cv2
import numpy as np

import torch
import torch.nn as nn

from torchvision import models, transforms

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

CHECKPOINT_HEAD = "configs/to_reproduce/dog_fe/epoch=36_head.ckpt"

INPUT_FILENAME = "petfinder_extra_dogs_transformed_v6.csv"

IMAGES_PATH = "../pets_datasets/petfinder_extra_dogs_transformed_v6"

RESULTS_PATH = (
    "embeddings/"
    "petfinder_extra_dogs_transformed_v6"
)

OUTPUT_FILENAME = (
    "all_petfinder_extra_dogs_transformed_v6.csv"
)

HEAD_SIZE = 224

# ----------------------------------------------------
# ResNet50
# ----------------------------------------------------

def build_resnet50():

    model = models.resnet50(
        weights=models.ResNet50_Weights.IMAGENET1K_V1
    )

    model.fc = nn.Linear(
        2048,
        512
    )

    return model

def load_project_model(checkpoint_path):

    backbone = build_resnet50()

    wrapper = SoftmaxBasedMetricLearning(
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

    wrapper.load_state_dict(
        checkpoint,
        strict=False,
    )

    wrapper.eval()

    wrapper.add_margin = None

    wrapper.to(DEVICE)

    return wrapper

embedding_model = load_project_model(
    CHECKPOINT_HEAD
)

print(f"Embedding model loaded on {DEVICE}")


preprocess = transforms.Compose([
    transforms.ToPILImage(),

    transforms.Resize(
        (224,224)
    ),

    transforms.ToTensor(),

    transforms.Normalize(
        mean=[0.485,0.456,0.406],
        std=[0.229,0.224,0.225],
    )
])


def get_embedding(image_path):
    image = cv2.imread(image_path)

    if image is None:
        raise RuntimeError(
            f"Cannot read image {image_path}"
        )

    tensor = preprocess(image)

    tensor = (
        tensor
        .unsqueeze(0)
        .to(DEVICE)
    )

    with torch.no_grad():

        emb = embedding_model(tensor)

    return emb.cpu()

# ----------------------------------------------------
# Main
# ----------------------------------------------------
def main():
    results = []

    with open(
        INPUT_FILENAME,
        newline="",
        encoding="utf-8",
    ) as infile:

        reader = csv.DictReader(infile)

        for row in reader:

            name = row["name"]
            num = int(row["imagenum"])

            print(f"{name} {num}")

            image_filename = os.path.join(
                IMAGES_PATH,
                name,
                f"{num}.png",
            )

            output_dir = os.path.join(
                RESULTS_PATH,
                name,
            )

            output_filename = os.path.join(
                output_dir,
                f"{num}.pkl",
            )

            result_row = {
                "name": name,
                "imagenum": num,
                "success": 0,
            }

            try:

                emb = get_embedding(
                    image_filename,
                )

                os.makedirs(
                    output_dir,
                    exist_ok=True,
                )

                with open(
                    output_filename,
                    "wb",
                ) as f:

                    pickle.dump(
                        emb,
                        f,
                    )

                result_row["success"] = 1

            except Exception as e:

                print()
                print("=" * 80)
                print(f"ERROR: {image_filename}")
                print(e)
                print("=" * 80)
                print()

            results.append(result_row)

            sys.stdout.flush()
            sys.stderr.flush()

    with open(
        OUTPUT_FILENAME,
        "w",
        newline="",
        encoding="utf-8",
    ) as outfile:

        writer = csv.DictWriter(
            outfile,
            fieldnames=[
                "name",
                "imagenum",
                "success",
            ],
        )

        writer.writeheader()
        writer.writerows(results)

    print()
    print("=" * 80)
    print("Finished.")
    print(f"Embeddings saved to:")
    print(RESULTS_PATH)
    print("=" * 80)


if __name__ == "__main__":
    main()

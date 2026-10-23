import ast
import json
import pickle

import numpy as np
import requests


API_URL = "http://localhost:3003/predict"
MODEL_NAME = "EVA02-B-16__merged2b_s8b_b131k"
TEXT = "other"
OUTPUT_FILE = "other_embedding.pkl"


def parse_embedding(value):
    if isinstance(value, str):
        value = ast.literal_eval(value)

    return np.asarray(value, dtype=np.float32)


def normalize_embedding(embedding):
    norm = np.linalg.norm(embedding)

    if norm == 0:
        raise ValueError("Zero-norm embedding.")

    return embedding / norm


response = requests.post(
    API_URL,
    data={
        "entries": json.dumps(
            {
                "clip": {
                    "textual": {
                        "modelName": MODEL_NAME
                    }
                }
            }
        ),
        "text": TEXT,
    },
    timeout=30.0,
)

if response.status_code != 200:
    raise RuntimeError(
        "Text embedding request failed:\n"
        f"{response.text}"
    )

data = response.json()

embedding = parse_embedding(data["clip"])
embedding = normalize_embedding(embedding)

with open(OUTPUT_FILE, "wb") as f:
    pickle.dump(
        embedding.astype(np.float32),
        f,
        protocol=pickle.HIGHEST_PROTOCOL,
    )

print(f"Saved embedding: {OUTPUT_FILE}")
print(f"Shape: {embedding.shape}")

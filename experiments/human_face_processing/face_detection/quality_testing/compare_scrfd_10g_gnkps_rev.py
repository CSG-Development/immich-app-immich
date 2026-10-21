import os
import cv2

# Paths
source_images_dir = "images/train"
images_dir = "images/train"
labels_1_dir = "labels/train"
labels_2_dir = "output_labels_scrfd_10g_gnkps"

from typing import List, Tuple
import numpy as np

def iou(boxA, boxB):
    xA = max(boxA[0], boxB[0])
    yA = max(boxA[1], boxB[1])
    xB = min(boxA[0] + boxA[2], boxB[0] + boxB[2])
    yB = min(boxA[1] + boxA[3], boxB[1] + boxB[3])

    interW = max(0, xB - xA)
    interH = max(0, yB - yA)
    interArea = interW * interH

    boxAArea = boxA[2] * boxA[3]
    boxBArea = boxB[2] * boxB[3]

    return interArea / float(boxAArea + boxBArea - interArea + 1e-6)

def match_bboxes_iou(
    gt_boxes: List[List[int]],
    pred_boxes: List[List[int]],
    iou_threshold: float = 0.5
) -> dict:

    iou_matrix = np.zeros((len(gt_boxes), len(pred_boxes)))

    for i, gt in enumerate(gt_boxes):
        for j, pred in enumerate(pred_boxes):
            iou_matrix[i, j] = iou(gt, pred)

    matched_gt = set()
    matched_pred = set()
    matches = []

    # Greedy matching by IoU
    tmp_matrix = iou_matrix.copy()
    while True:
        if tmp_matrix.size == 0:
            break
        max_iou = np.max(tmp_matrix)
        if max_iou < iou_threshold:
            break

        i, j = np.unravel_index(np.argmax(tmp_matrix), tmp_matrix.shape)
        matches.append((i, j, max_iou))
        matched_gt.add(i)
        matched_pred.add(j)

        tmp_matrix[i, :] = -1
        tmp_matrix[:, j] = -1

    # Add unmatched GT with pred index = -1 and IoU = 0.0
    for i in range(len(gt_boxes)):
        if i not in matched_gt:
            matches.append((i, -1, 0.0))

    matches = sorted(matches, key=lambda x: x[0])  # Keep sorted by GT index

    TP = len(matched_gt)
    FN = len(gt_boxes) - TP
    FP = len(pred_boxes) - len(matched_pred)
    TN = 0

    precision = TP / (TP + FP) if (TP + FP) > 0 else 0.0
    recall = TP / (TP + FN) if (TP + FN) > 0 else 0.0
    accuracy = TP / (TP + FP + FN)
    F1 = 2 * precision * recall / (precision + recall + 1e-6)

    avg_iou = (sum([iou for _, _, iou in matches]) / len(matches) ) if len(matches) > 0 else 0.0

    return {
        "Matches": matches,
        "IoUs": [iou for _, _, iou in matches],
        "Average_IoU": avg_iou,
        "TP": TP,
        "FP": FP,
        "TN": TN,
        "FN": FN,
        "Accuracy": accuracy,
        "Precision": precision,
        "Recall": recall,
        "F1": F1
    }

# Collect image names without extension
image_names = [os.path.splitext(f)[0].replace("_annotated", "") for f in os.listdir(source_images_dir) if f.lower().endswith(".jpg")]
image_names.sort()

print("Image Id,Avg IoU,TP,FP,TN,FN,Accuracy,Precision,Recall,F1 score")

for img_name in image_names:
    img_path = os.path.join(images_dir, img_name + ".jpg")
    label_1_path = os.path.join(labels_1_dir, img_name + ".txt")
    label_2_path = os.path.join(labels_2_dir, img_name + ".txt")

    # Load image
    img = cv2.imread(img_path)
    if img is None:
        print(f"Warning: unable to read {img_path}")
        continue

    h, w = img.shape[:2]

    orig_gt_1_boxes = []
    gt_1_boxes = []

    # Read bounding boxes if label file exists
    if os.path.exists(label_1_path):
        with open(label_1_path, "r") as f:
            for line in f:
                data = line.strip().split()
                if len(data) != 5:
                    continue

                marker, x_rel, y_rel, w_rel, h_rel = map(float, data)

                # Convert to pixel coordinates
                x1 = int((x_rel - 0.5 * w_rel) * w)
                y1 = int((y_rel - 0.5 * h_rel) * h)
                x2 = int((x_rel + 0.5 * w_rel) * w)
                y2 = int((y_rel + 0.5 * h_rel) * h)

                # Draw bounding box
                orig_gt_1_boxes.append([x_rel, y_rel, w_rel, h_rel])
                gt_1_boxes.append([x1, y1, x2, y2])

    orig_gt_2_boxes = []
    gt_2_boxes = []

    # Read bounding boxes if label file exists
    if os.path.exists(label_2_path):
        with open(label_2_path, "r") as f:
            for line in f:
                # Expected: x_min, y_min, width, height in relative coords
                data = line.strip().split()
                if len(data) != 5:
                    continue

                marker, x_rel, y_rel, w_rel, h_rel = map(float, data)

                # Convert to pixel coordinates
                x1 = int((x_rel - 0.5 * w_rel) * w)
                y1 = int((y_rel - 0.5 * h_rel) * h)
                x2 = int((x_rel + 0.5 * w_rel) * w)
                y2 = int((y_rel + 0.5 * h_rel) * h)

                # Draw bounding box
                orig_gt_2_boxes.append([x_rel, y_rel, w_rel, h_rel])
                gt_2_boxes.append([x1, y1, x2, y2])

    match_res = match_bboxes_iou(gt_2_boxes, gt_1_boxes, iou_threshold=0.5)
    print("{},{},{},{},{},{},{},{},{},{}".format(img_name, match_res["Average_IoU"], match_res["TP"], match_res["FP"], match_res["TN"], match_res["FN"], match_res["Accuracy"], match_res["Precision"], match_res["Recall"],  match_res["F1"]))

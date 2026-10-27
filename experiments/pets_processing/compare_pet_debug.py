import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import transforms, models
from torchvision.models import resnet50
from losses import SoftmaxBasedMetricLearning

import cv2
import numpy as np
from pathlib import Path
import random


seed = 42
random.seed(seed)
np.random.seed(seed)
torch.manual_seed(seed)
torch.cuda.manual_seed_all(seed)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False

IMAGE1_PATH = "dogs/20080044/0.png"
IMAGE2_PATH = "dogs/20080044/1.png"

CHECKPOINT_MASK = "configs/to_reproduce/mask/epoch=64.ckpt"
CHECKPOINT_KP = "configs/to_reproduce/keypoint/epoch=14.ckpt"

CHECKPOINT_HEAD = "configs/to_reproduce/dog_fe/epoch=36_head.ckpt"
CHECKPOINT_BODY = "configs/to_reproduce/dog_fe/epoch=37_body.ckpt"

HEAD_CROP_SIZE = 224
SCORE_THRESHOLD = 0.7
SIMILARITY_THRESHOLD_HEAD = 0.8
SIMILARITY_THRESHOLD_BODY = 0.8

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

from configs.mask.mask_rcnn_config import model as build_mask_model
from configs.keypoint.keypoints_config import model as build_kp_model

mask_model = build_mask_model().to(DEVICE).eval()
checkpoint = torch.load(CHECKPOINT_MASK, map_location=DEVICE)
mask_model.load_state_dict({k.replace("model_loss.model.","").replace("model.",""):v
                            for k,v in checkpoint.get("state_dict", checkpoint).items()})

kp_model = build_kp_model().to(DEVICE).eval()
checkpoint_kp = torch.load(CHECKPOINT_KP, map_location=DEVICE)
kp_model.load_state_dict({k.replace("model_loss.model.","").replace("model.",""):v
                          for k,v in checkpoint_kp.get("state_dict", checkpoint_kp).items()})

from engine import Controller
from utils import get_dict_wrapper

def build_resnet50():

    model = models.resnet50(
        weights=models.ResNet50_Weights.IMAGENET1K_V1
    )

    model.fc = nn.Linear(
        2048,
        512,
    )

    return model


def clean_state_dict(state_dict):

    cleaned = {}

    for key, value in state_dict.items():

        # если checkpoint Lightning
        if key.startswith("state_dict."):
            key = key[len("state_dict."):]

        # именно твой случай
        if key.startswith("model_loss."):
            key = key[len("model_loss."):]

        cleaned[key] = value

    return cleaned


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

    state_dict = checkpoint.get(
        "state_dict",
        checkpoint,
    )

    fixed_state_dict = {}

    for key, value in state_dict.items():

        new_key = key

        if new_key.startswith("model_loss."):
            new_key = new_key[len("model_loss."):]

        if new_key.startswith("model."):
            new_key = new_key[len("model."):]

        fixed_state_dict[new_key] = value

    missing, unexpected = wrapper.load_state_dict(
        fixed_state_dict,
        strict=False,
    )

    ignored_missing = {
        "add_margin.weight",
    }

    real_missing = [
        k for k in missing
        if k not in ignored_missing
    ]

    print("=" * 80)
    print("Checkpoint:", checkpoint_path)
    print("Missing:", len(real_missing))
    print("Unexpected:", len(unexpected))

    if real_missing:
        print("\nMissing keys:")
        for k in real_missing:
            print(" ", k)

    if unexpected:
        print("\nUnexpected keys:")
        for k in unexpected:
            print(" ", k)

    if not real_missing and not unexpected:
        print("\n✓ Checkpoint loaded successfully.")

    wrapper.add_margin = None
    wrapper.eval()
    wrapper.to(DEVICE)

    return wrapper
    
def load_controller(config_path, checkpoint_path):

    controller = Controller(
        get_dict_wrapper(config_path)
    )

    checkpoint = torch.load(
        checkpoint_path,
        map_location=DEVICE,
    )

    state_dict = checkpoint.get(
        "state_dict",
        checkpoint,
    )

    state_dict = clean_state_dict(
        state_dict,
    )

    missing, unexpected = controller.load_state_dict(
        state_dict,
        strict=False,
    )

    print("=" * 80)
    print("Checkpoint:", checkpoint_path)
    print("Missing:", len(missing))
    print("Unexpected:", len(unexpected))

    if missing:
        print("\nMissing keys:")
        for k in missing:
            print(" ", k)

    if unexpected:
        print("\nUnexpected keys:")
        for k in unexpected:
            print(" ", k)

    controller.eval()

    model = controller.model_loss

    model.add_margin = None

    model.to(DEVICE)

    return model

head_model = load_project_model(CHECKPOINT_HEAD)
body_model = load_project_model(CHECKPOINT_BODY)

preprocess = transforms.Compose([
    transforms.ToPILImage(),
    transforms.Resize((224,224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485,0.456,0.406],
                         std=[0.229,0.224,0.225])
])

def draw_keypoints(image, keypoints, radius=15):
    for x,y in keypoints:
        cv2.circle(image,(int(x),int(y)),radius,(0,255,0),-1)
    return image

def detect_body(image):
    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    tensor = torch.from_numpy(image_rgb/255.0).permute(2,0,1).float().to(DEVICE)
    with torch.no_grad():
        output = mask_model([tensor])[0]
    boxes = output["boxes"].cpu().numpy()
    scores = output["scores"].cpu().numpy()
    masks = output["masks"].cpu().numpy()
    idx = np.argmax(scores)
    if scores[idx]<SCORE_THRESHOLD:
        return None,None,None
    x1,y1,x2,y2 = boxes[idx].astype(int)
    body_crop = image[y1:y2,x1:x2]
    mask = masks[idx][0]>0.5
    masked = image.copy()
    masked[mask] = masked[mask]*0.5 + np.array([0,0,255],dtype=np.uint8)*0.5
    return masked,body_crop,(x1,y1,x2,y2)

def detect_keypoints(crop):
    tensor = torch.from_numpy(crop/255.0).permute(2,0,1).float().unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        output = kp_model(tensor)
        if isinstance(output,list): output=output[0]
        keypoints = output["keypoints"].cpu().numpy()[0,:,:2]
    return keypoints

def crop_head(crop,keypoints):
    x_min,y_min = keypoints.min(axis=0)
    x_max,y_max = keypoints.max(axis=0)
    w,h = x_max-x_min,y_max-y_min
    pad_ratio=1.5
    x_min = max(int(x_min - w*pad_ratio),0)
    x_max = min(int(x_max + w*pad_ratio),crop.shape[1])
    y_min = max(int(y_min - h*pad_ratio),0)
    y_max = min(int(y_max + h*pad_ratio),crop.shape[0])
    head = crop[y_min:y_max,x_min:x_max]
    head = cv2.resize(head,(HEAD_CROP_SIZE,HEAD_CROP_SIZE))
    return head,(x_min,y_min,x_max,y_max)

def get_embedding(img,model):
    tensor = preprocess(img).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        return model(tensor)

def process_dog(image_path,out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True,exist_ok=True)
    image = cv2.imread(image_path)
    masked, body, bbox = detect_body(image)
    cv2.imwrite(str(out_dir/"masked.png"), masked)
    cv2.imwrite(str(out_dir/"cropped.png"), body)
    keypoints = detect_keypoints(body)
    vis = draw_keypoints(body.copy(),keypoints)
    cv2.imwrite(str(out_dir/"keypoints.png"), vis)
    head, head_bbox = crop_head(body,keypoints)
    cv2.imwrite(str(out_dir/"head_224x224.png"),head)
    x_min,y_min,x_max,y_max = head_bbox
    keypoints_local = keypoints.copy()
    keypoints_local[:,0] -= x_min
    keypoints_local[:,1] -= y_min
    scale_x = HEAD_CROP_SIZE/(x_max-x_min)
    scale_y = HEAD_CROP_SIZE/(y_max-y_min)
    keypoints_local[:,0] *= scale_x
    keypoints_local[:,1] *= scale_y
    head_kp = draw_keypoints(head.copy(),keypoints_local,5)
    cv2.imwrite(str(out_dir/"head_keypoints_224x224.png"),head_kp)
    emb_head = get_embedding(head,head_model)
    emb_body = get_embedding(body,body_model)

    import pickle

    with open("debug_head.pkl", "wb") as f:
        pickle.dump(emb_head.cpu(), f)
    
    return emb_head, emb_body

def compare_dogs(img1,img2):
    emb1_head, emb1_body = process_dog(img1,"results/dog1")
    emb2_head, emb2_body = process_dog(img2,"results/dog2")
    sim_head = F.cosine_similarity(emb1_head,emb2_head).item()
    sim_body = F.cosine_similarity(emb1_body,emb2_body).item()
    same_head = sim_head>=SIMILARITY_THRESHOLD_HEAD
    same_body = sim_body>=SIMILARITY_THRESHOLD_BODY
    overall = same_head or same_body
    return sim_head,same_head,sim_body,same_body,overall

def save_debug_comparison(img1_dir,img2_dir,sim_head, same_head, sim_body, same_body,
                          output_path="results/comparison_debug.png"):
    dog1_head = cv2.imread(str(Path(img1_dir)/"head_keypoints_224x224.png"))
    dog2_head = cv2.imread(str(Path(img2_dir)/"head_keypoints_224x224.png"))
    dog1_body = cv2.imread(str(Path(img1_dir)/"keypoints.png"))
    dog2_body = cv2.imread(str(Path(img2_dir)/"keypoints.png"))

    dog1_head_resized = cv2.resize(dog1_head,(HEAD_CROP_SIZE,HEAD_CROP_SIZE))
    dog2_head_resized = cv2.resize(dog2_head,(HEAD_CROP_SIZE,HEAD_CROP_SIZE))
    top_heads = np.hstack([dog1_head_resized,dog2_head_resized])

    max_body_h = max(dog1_body.shape[0],dog2_body.shape[0])
    def resize_height_keep_aspect(img,target_height):
        h,w = img.shape[:2]
        new_w = int(w*target_height/h)
        return cv2.resize(img,(new_w,target_height))
    dog1_body_resized = resize_height_keep_aspect(dog1_body,max_body_h)
    dog2_body_resized = resize_height_keep_aspect(dog2_body,max_body_h)
    bottom = np.hstack([dog1_body_resized,dog2_body_resized])

    text_area_w = 400
    h_top = top_heads.shape[0]
    black_area_top = np.zeros((h_top,text_area_w,3),dtype=np.uint8)
    top_with_text = np.hstack([top_heads,black_area_top])

    target_width = top_with_text.shape[1]
    def resize_width_keep_aspect(img,target_width):
        h,w = img.shape[:2]
        new_h = int(h*target_width/w)
        return cv2.resize(img,(target_width,new_h))
    bottom = resize_width_keep_aspect(bottom,target_width)

    final_img = np.vstack([top_with_text,bottom])

    font_scale = 1.2
    thickness = 2

    font = cv2.FONT_HERSHEY_SIMPLEX
    color_yes = (0,255,0)
    color_no  = (0,0,255)
    y0 = 50
    dy = 50

    head_color = color_yes if same_head else color_no
    body_color = color_yes if same_body else color_no
    overall_color = color_yes if (same_head or same_body) else color_no

    cv2.putText(final_img,f"Head: {sim_head:.4f} {'YES' if same_head else 'NO'}",
                (top_heads.shape[1]+10,y0), font, font_scale, head_color, thickness)
    cv2.putText(final_img,f"Body: {sim_body:.4f} {'YES' if same_body else 'NO'}",
                (top_heads.shape[1]+10,y0+dy), font, font_scale, body_color, thickness)
    cv2.putText(final_img,f"Final: {'YES' if (same_head or same_body) else 'NO'}",
                (top_heads.shape[1]+10,y0+2*dy), font, font_scale, overall_color, thickness)

    Path(output_path).parent.mkdir(parents=True,exist_ok=True)
    cv2.imwrite(output_path,final_img)
    print(f"🎨 Diagnostic comparison saved: {output_path}")

if __name__=="__main__":
    sim_head,same_head,sim_body,same_body,overall = compare_dogs(IMAGE1_PATH,IMAGE2_PATH)
    print(f"Head similarity: {sim_head:.4f}, same? {'YES' if same_head else 'NO'}")
    print(f"Body similarity: {sim_body:.4f}, same? {'YES' if same_body else 'NO'}")
    print(f"Overall verdict: {'YES' if overall else 'NO'}")
    save_debug_comparison("results/dog1","results/dog2",sim_head,same_head,sim_body,same_body)

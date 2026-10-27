import os
import re
import csv

def get_list_of_subfolders(images_path):
    """
    Get a list of all subfolder names in the given directory.
    """
    if not os.path.exists(images_path):
        return []
    
    subfolders = []
    for item in os.listdir(images_path):
        item_path = os.path.join(images_path, item)
        if os.path.isdir(item_path):
            subfolders.append(item)
    
    return subfolders

def get_list_of_files(images_path, subfolder_name):
    """
    Get a list of all files in a specific subfolder.
    """
    subfolder_path = os.path.join(images_path, subfolder_name)
    
    if not os.path.exists(subfolder_path) or not os.path.isdir(subfolder_path):
        return []
    
    files = []
    for item in os.listdir(subfolder_path):
        item_path = os.path.join(subfolder_path, item)
        if os.path.isfile(item_path):
            files.append(item)
    
    return files

def parse_filename(filename):
    """
    Parse a filename in the format {person_name}_{image_index_4_digits_with_leading_zeros}.jpg
    """
    # Remove file extension if present
    if filename.endswith(".jpg"):
        filename = filename[:-4]
    elif filename.endswith(".jpeg"):
        filename = filename[:-5]
    
    # Pattern explanation:
    # ^(.+?)_ - captures everything up to the last underscore as person_name (non-greedy)
    # (\d{4})$ - captures exactly 4 digits at the end as image_index
    pattern = r"^(.+?)_(\d{4})$"
    match = re.match(pattern, filename)
    
    if match:
        person_name = match.group(1)
        image_index = int(match.group(2))
        return person_name, image_index
    else:
        return None, None


# Main logic
IMAGES_PATH = "lfw-deepfunneled/lfw-deepfunneled"
OUTPUT_FILENAME = "all.csv"

# Get all subfolders
subfolders = get_list_of_subfolders(IMAGES_PATH)
print("Subfolders:", subfolders)

records = []

# Iterate through all subfolders and collect (name, imagenum)
for subfolder in subfolders:
    files = get_list_of_files(IMAGES_PATH, subfolder)
    for fname in files:
        name, imagenum = parse_filename(fname)
        if name is not None and imagenum is not None:
            records.append((name, imagenum))

# Save records to CSV
with open(OUTPUT_FILENAME, mode="w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["name", "imagenum"])  # header
    writer.writerows(records)

print(f"✅ CSV файл "{OUTPUT_FILENAME}" успешно сохранён. Записано {len(records)} строк.")

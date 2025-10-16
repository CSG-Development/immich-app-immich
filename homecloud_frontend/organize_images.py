#   Do NOT modify or remove this copyright and confidentiality notice
#
#   Copyright (c) 2025 Seagate Technology LLC or one of its affiliates.
#
#   This code is classified as SEAGATE CONFIDENTIAL
#   and may be covered under one or more Non-Disclosure Agreements.
#   Any use, modification, duplication, derivation, distribution or disclosure
#   of this code, for any reason, not expressly authorized is prohibited.
#   All other rights are expressly reserved by Seagate Technology LLC.
#

import os
import sys
import shutil
import tinify

tinify.key = "API_KEY"  # Replace with your actual Tinify API key

# You can run this script before to import images to asset folder
# Example: python organize_images.py "/download/new_images"

def process_files(directory):
    # Define suffixes and target folders
    suffixes = {
        "@1.5x": "1.5x",
        "@2x": "2.0x",
        "@3x": "3.0x",
        "@4x": "4.0x"
    }

    # Iterate over all files in the folder
    for filename in os.listdir(directory):
        file_path = os.path.join(directory, filename)

        # Skip if not a file
        if not os.path.isfile(file_path):
            continue
            
        # Compression with Tinify
        try:
            source = tinify.from_file(file_path)
            converted = source.convert(type=["image/webp"])
            converted_filename = os.path.splitext(filename)[0] + ".webp"
            converted_path = os.path.join(directory, converted_filename)
            converted.to_file(converted_path)                    
            # Delete the old file
            os.remove(file_path)
            file_path = converted_path
            filename = converted_filename
            print(f"Compressed: {filename}")
        except tinify.Error as e:
            print(f"Compression error for {filename}: {e}")

        for suffix, folder in suffixes.items():
            
            if suffix in filename:
                # Create target folder if it does not exist
                target_folder = os.path.join(directory, folder)
                os.makedirs(target_folder, exist_ok=True)

                # New filename without the suffix
                new_filename = filename.replace(suffix, "")
                new_path = os.path.join(target_folder, new_filename)

                # Move and rename the file
                shutil.move(file_path, new_path)
                print(f"Moved: {filename} -> {new_path}")                

                break

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python organize_images.py <folder_path>")
    else:
        process_files(sys.argv[1])

"""
Testing Data Generation Template
Original file: https://colab.research.google.com/drive/1iDu3v3m3iOKyRs6IggnOPbN6tKKa9SRV
"""

## Setup Environment

!pip install requests tqdm icrawler

import numpy as np
import pandas as pd
import os
import shutil
import urllib3
import logging
from icrawler import ImageDownloader
from icrawler.builtin import BingImageCrawler

OUTPUT_ROOT = "Feature_Dataset_HQ"
TARGET_COUNT = 100

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class No403Filter(logging.Filter):
    def filter(self, record):
        return "403" not in record.getMessage()


logging.getLogger("downloader").addFilter(No403Filter())


class RobustDownloader(ImageDownloader):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.session.verify = False
        self.session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Referer": "https://www.bing.com/",
            }
        )


SEARCH_MAPPING = {
    "soft-light": "soft light, gentle illumination, low contrast, wrap-around light",
    "specular-highlights": "strong specular highlights, shiny skin, glossy reflections, bright hotspots",
    "backlit": "backlit lighting from behind the subject, rim light, silhouette effect, sun flare",
    "studio-lighting": "professional studio lighting, controlled illumination, three-point lighting setup",
    "flat-lighting": "flat lighting, low contrast, even illumination, no shadows, cloudy day look",
    "dramatic-contrast": "dramatic high-contrast lighting, chiaroscuro, hard shadows, noir style",
    "diffused": "soft diffused lighting, cloudy sky light, light box look, scattered light, no hard edges",
}


def count_files(folder):
    if not os.path.exists(folder):
        return 0
    return len([f for f in os.listdir(folder) if f.endswith((".jpg", ".png", ".jpeg"))])


def trim_excess(folder, limit):
    files = sorted(
        [f for f in os.listdir(folder) if f.endswith((".jpg", ".png", ".jpeg"))]
    )
    if len(files) > limit:
        print(f"   -> Overshot! Trimming {len(files) - limit} extra images...")
        for f in files[limit:]:
            try:
                os.remove(os.path.join(folder, f))
            except:
                pass


if __name__ == "__main__":
    if not os.path.exists(OUTPUT_ROOT):
        os.makedirs(OUTPUT_ROOT)

    print(f"Starting Recursive Download (Target: {TARGET_COUNT})...")

    for category, query in SEARCH_MAPPING.items():
        print(f"\n--- Processing: {category} ---")
        save_dir = os.path.join(OUTPUT_ROOT, category)

        if not os.path.exists(save_dir):
            os.makedirs(save_dir)

        # Initial Search Depth
        search_depth = 200

        while True:
            current_count = count_files(save_dir)

            # 1. CHECK CONDITION
            if current_count >= TARGET_COUNT:
                print(f"   -> Success! Found {current_count} images.")
                break

            # 2. INCREASE DEPTH
            print(
                f"   -> Have {current_count}/{TARGET_COUNT}. Increasing search depth to {search_depth}..."
            )

            crawler = BingImageCrawler(
                downloader_cls=RobustDownloader,
                feeder_threads=1,
                parser_threads=2,
                downloader_threads=4,
                storage={"root_dir": save_dir},
                log_level="ERROR",
            )

            # 3. SAFETY OFFSET
            if current_count == 0:
                offset_param = 0
            else:
                offset_param = "auto"

            crawler.crawl(
                keyword=query,
                max_num=search_depth,
                filters={"type": "photo"},
                file_idx_offset=offset_param,
            )

            # Increase the search buffer for the next loop
            search_depth += 500

            # Safety break
            if search_depth > 5000:
                print("   -> Hit safety limit (5000). Stopping.")
                break

        # Final Trim
        trim_excess(save_dir, TARGET_COUNT)
        print(f"   Final Count: {count_files(save_dir)}")

    print(f"\n Material Look Dataset (HQ) Download Complete!")


## Compress dataset folder into .zip

import shutil
import os

FOLDER_TO_ZIP = "MaterialLook_Dataset_HQ"
OUTPUT_FILENAME = "MaterialLook_Dataset"  # .zip will be added automatically

if __name__ == "__main__":
    if os.path.exists(FOLDER_TO_ZIP):
        print(f"Compressing '{FOLDER_TO_ZIP}'...")
        shutil.make_archive(OUTPUT_FILENAME, "zip", FOLDER_TO_ZIP)
        zip_size = os.path.getsize(f"{OUTPUT_FILENAME}.zip") / (1024 * 1024)
        print(f" Success! Created {OUTPUT_FILENAME}.zip ({zip_size:.2f} MB)")
    else:
        print(f" Error: Folder '{FOLDER_TO_ZIP}' not found.")

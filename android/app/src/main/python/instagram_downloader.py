import instaloader
import re
import os
import json
from pathlib import Path

def download_instagram_image(url, output_dir):
    """
    Downloads all images from an Instagram post.
    """
    try:
        os.makedirs(output_dir, exist_ok=True)

        # Initialize Instaloader
        L = instaloader.Instaloader(
            download_pictures=True,
            download_videos=False, 
            download_video_thumbnails=False,
            download_geotags=False, 
            download_comments=False,
            save_metadata=False,
            compress_json=False,
        )
        L.filename_pattern = "{shortcode}"

        # Extract shortcode from URL
        shortcode_match = re.search(r'instagram\.com/(?:p|reel|tv)/([^/?#&]+)', url)
        if not shortcode_match:
            return json.dumps({
                "success": False,
                "error": "Could not extract shortcode. Use format: https://instagram.com/p/ShortCode/"
            })
        shortcode = shortcode_match.group(1)

        # Download post
        post = instaloader.Post.from_shortcode(L.context, shortcode)
        L.download_post(post, target=Path(output_dir))

        found_files = []
        extensions = ['jpg', 'png', 'webp', 'jpeg']
        patterns = [f"{shortcode}.{{ext}}", f"{shortcode}_*.{{ext}}"]

        output_path = Path(output_dir)
        for ext in extensions:
            for pattern in patterns:
                matches = list(output_path.glob(pattern.format(ext=ext)))
                for match in matches:
                    found_files.append(str(match.absolute()))

        found_files = sorted(list(set(found_files)))

        if found_files:
            return json.dumps({
                "success": True,
                "file_paths": found_files,
                "shortcode": shortcode
            })
        else:
            all_files = [f.name for f in output_path.glob("*")]
            return json.dumps({
                "success": False,
                "error": f"Downloaded but no images found. Files in dir: {all_files}"
            })

    except instaloader.exceptions.InstaloaderException as e:
        return json.dumps({
            "success": False,
            "error": f"Instaloader error: {str(e)}"
        })
    except Exception as e:
        return json.dumps({
            "success": False,
            "error": f"Python error: {str(e)}"
        })
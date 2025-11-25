import instaloader
import re
import os
import json
from pathlib import Path

def download_instagram_image(url, output_dir):
    """
    Downloads an image from an Instagram URL using Instaloader.
    
    Args:
        url (str): The full Instagram URL (e.g., https://www.instagram.com/p/ShortCode/)
        output_dir (str): Directory where the image should be saved
    
    Returns:
        dict: Result with success status and file path or error message
    """
    try:
        # Initialize Instaloader
        L = instaloader.Instaloader(
            download_pictures=True,
            download_videos=False, 
            download_video_thumbnails=False,
            download_geotags=False, 
            download_comments=False,
            save_metadata=False,
            compress_json=False
        )

        # Extract shortcode from URL
        # Matches /p/ShortCode, /reel/ShortCode, etc.
        shortcode_match = re.search(r'instagram\.com/(?:p|reel|tv)/([^/?#&]+)', url)
        
        if not shortcode_match:
            return json.dumps({
                "success": False,
                "error": "Could not extract shortcode from URL. Please ensure the URL is in the format: https://www.instagram.com/p/ShortCode/"
            })

        shortcode = shortcode_match.group(1)

        # Load the post using the shortcode
        post = instaloader.Post.from_shortcode(L.context, shortcode)
        
        # Create output directory if it doesn't exist
        os.makedirs(output_dir, exist_ok=True)
        
        # Download the post
        L.download_post(post, target=output_dir)
        
        # Find the downloaded image file
        # Instaloader saves files with pattern: {shortcode}_*.jpg or {shortcode}_*.png
        output_path = Path(output_dir)
        image_files = list(output_path.glob(f"{shortcode}_*.jpg")) + list(output_path.glob(f"{shortcode}_*.png"))
        
        if not image_files:
            # Try alternative pattern
            image_files = list(output_path.glob(f"{shortcode}.*"))
        
        if image_files:
            image_path = str(image_files[0])
            return json.dumps({
                "success": True,
                "file_path": image_path,
                "shortcode": shortcode
            })
        else:
            return json.dumps({
                "success": False,
                "error": "Image downloaded but file not found"
            })

    except instaloader.exceptions.InstaloaderException as e:
        return json.dumps({
            "success": False,
            "error": f"Instaloader error: {str(e)}. Note: This works best for PUBLIC posts. Private posts require login."
        })
    except Exception as e:
        return json.dumps({
            "success": False,
            "error": f"Unexpected error: {str(e)}"
        })


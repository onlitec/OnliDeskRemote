import os
from PIL import Image

src_img_path = r"C:\Users\Alessandro\.gemini\antigravity-ide\brain\8cb6fd24-f512-41e9-8766-30903c52698c\media__1779983077820.jpg"
res_dir = r"c:\Users\Alessandro\OneDrive\OnliDeskRemote\res"

if not os.path.exists(src_img_path):
    print(f"Error: Source image not found at {src_img_path}")
    exit(1)

# Open the source image
img = Image.open(src_img_path)

# Ensure the res directory exists
os.makedirs(res_dir, exist_ok=True)

# 1. Save res/icon.png (main high-res source)
icon_png_path = os.path.join(res_dir, "icon.png")
# Save as 512x512 PNG
img_512 = img.resize((512, 512), Image.Resampling.LANCZOS)
img_512.save(icon_png_path, "PNG")
print("Saved res/icon.png")

# 2. Save res/mac-icon.png
mac_icon_path = os.path.join(res_dir, "mac-icon.png")
img_512.save(mac_icon_path, "PNG")
print("Saved res/mac-icon.png")

# 3. Save res/128x128.png
png_128_path = os.path.join(res_dir, "128x128.png")
img_128 = img.resize((128, 128), Image.Resampling.LANCZOS)
img_128.save(png_128_path, "PNG")
print("Saved res/128x128.png")

# 4. Save res/128x128@2x.png (256x256)
png_256_path = os.path.join(res_dir, "128x128@2x.png")
img_256 = img.resize((256, 256), Image.Resampling.LANCZOS)
img_256.save(png_256_path, "PNG")
print("Saved res/128x128@2x.png")

# 5. Save res/64x64.png
png_64_path = os.path.join(res_dir, "64x64.png")
img_64 = img.resize((64, 64), Image.Resampling.LANCZOS)
img_64.save(png_64_path, "PNG")
print("Saved res/64x64.png")

# 6. Save res/32x32.png
png_32_path = os.path.join(res_dir, "32x32.png")
img_32 = img.resize((32, 32), Image.Resampling.LANCZOS)
img_32.save(png_32_path, "PNG")
print("Saved res/32x32.png")

# 7. Save res/icon.ico (multi-resolution ICO)
ico_path = os.path.join(res_dir, "icon.ico")
sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
icon_imgs = [img.resize(size, Image.Resampling.LANCZOS) for size in sizes]
img.save(ico_path, format="ICO", sizes=sizes)
print("Saved res/icon.ico")

# 8. Save res/tray-icon.ico (multi-resolution tray icon)
tray_ico_path = os.path.join(res_dir, "tray-icon.ico")
img.save(tray_ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
print("Saved res/tray-icon.ico")

print("All icon conversions completed successfully!")

#!/data/data/com.termux/files/usr/bin/bash
set -e

ICON_SRC="icon.png"
RES_DIR="app/src/main/res"

if [ ! -f "$ICON_SRC" ]; then
    echo "❌ Error: $ICON_SRC tidak ditemukan di root proyek!"
    exit 1
fi

# Pastikan Pillow terpasang
if ! python3 -c "import PIL" 2>/dev/null; then
    echo "📦 Menginstall Pillow di Termux..."
    pkg install -y python-pillow || pip install pillow
fi

python3 - << 'PYEOF'
import os, glob
from PIL import Image

src_path = "icon.png"
res_dir = "app/src/main/res"
img = Image.open(src_path).convert("RGBA")

# 1. Mapping ukuran standar mipmap Android
densities = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for folder, size in densities.items():
    target_dir = os.path.join(res_dir, folder)
    if not os.path.exists(target_dir):
        continue
    # Cari semua ic_launcher* (.png atau .webp)
    for file_path in glob.glob(os.path.join(target_dir, "ic_launcher*.*")):
        ext = os.path.splitext(file_path)[1].lower()
        if ext in [".png", ".webp"]:
            resized = img.resize((size, size), Image.Resampling.LANCZOS)
            resized.save(file_path, format="WEBP" if ext == ".webp" else "PNG")
            print(f"✅ Updated {file_path} ({size}x{size})")

# 2. Tangani Adaptive Icon Foreground (Android 8+) dengan safe-zone padding (~66%)
fg_patterns = [
    os.path.join(res_dir, "drawable*", "ic_launcher_foreground.*"),
    os.path.join(res_dir, "mipmap*", "ic_launcher_foreground.*"),
]
for pattern in fg_patterns:
    for file_path in glob.glob(pattern):
        ext = os.path.splitext(file_path)[1].lower()
        if ext in [".png", ".webp"]:
            with Image.open(file_path) as orig:
                w, h = orig.size
            canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            inner_w, inner_h = int(w * 0.66), int(h * 0.66)
            fg_resized = img.resize((inner_w, inner_h), Image.Resampling.LANCZOS)
            offset = ((w - inner_w) // 2, (h - inner_h) // 2)
            canvas.paste(fg_resized, offset, fg_resized)
            canvas.save(file_path, format="WEBP" if ext == ".webp" else "PNG")
            print(f"✅ Updated Adaptive Foreground {file_path} ({w}x{h} + safe padding)")

# 3. Timpa ikon logo UI tambahan di drawable* jika ada
ui_names = ["ic_logo.*", "app_icon.*", "logo.*", "splash_icon.*"]
for name in ui_names:
    for file_path in glob.glob(os.path.join(res_dir, "drawable*", name)):
        ext = os.path.splitext(file_path)[1].lower()
        if ext in [".png", ".webp"]:
            with Image.open(file_path) as orig:
                w, h = orig.size
            resized = img.resize((w, h), Image.Resampling.LANCZOS)
            resized.save(file_path, format="WEBP" if ext == ".webp" else "PNG")
            print(f"✅ Updated UI Icon {file_path} ({w}x{h})")
PYEOF

echo "🎉 Semua aset ikon berhasil diperbarui dari $ICON_SRC!"

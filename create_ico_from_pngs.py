#!/usr/bin/env python3
"""
Create app_icon.ico from existing PNG files for Windows .exe build.
This is separate from the MSIX package which will use the original PNGs.
"""

from PIL import Image
import struct
import io
import os

def create_ico_from_pngs(png_dir, output_ico):
    """Create multi-resolution ICO from existing PNG files."""
    
    # Map of sizes to PNG files
    png_files = {
        256: os.path.join(png_dir, 'app_icon_256.png'),
        128: os.path.join(png_dir, 'app_icon_128.png'),
        64: os.path.join(png_dir, 'app_icon_64.png'),
        48: os.path.join(png_dir, 'app_icon_48.png'),
        36: os.path.join(png_dir, 'app_icon_36.png'),
        16: os.path.join(png_dir, 'app_icon_16.png'),
    }
    
    # Load all available PNGs
    images_data = []
    
    print("Loading PNG files for ICO creation...")
    for size in sorted(png_files.keys(), reverse=True):
        path = png_files[size]
        if os.path.exists(path):
            img = Image.open(path)
            
            if img.mode != 'RGBA':
                img = img.convert('RGBA')
            
            # Save as PNG in memory
            png_buffer = io.BytesIO()
            img.save(png_buffer, format='PNG')
            png_data = png_buffer.getvalue()
            
            images_data.append({
                'size': size,
                'data': png_data,
            })
            
            print(f"  ✓ {size}x{size} - {len(png_data)} bytes")
    
    if not images_data:
        print("Error: No PNG files found!")
        return
    
    # Write ICO file
    print(f"\nCreating ICO with {len(images_data)} resolutions...")
    
    with open(output_ico, 'wb') as f:
        # ICO header
        f.write(struct.pack('<HHH', 0, 1, len(images_data)))
        
        # Calculate offset for first image data
        offset = 6 + (16 * len(images_data))
        
        # Write directory entries
        for img_info in images_data:
            size = img_info['size']
            width = size if size < 256 else 0
            height = size if size < 256 else 0
            data_size = len(img_info['data'])
            
            f.write(struct.pack('<BBBBHHII',
                width,
                height,
                0,
                0,
                1,
                32,
                data_size,
                offset
            ))
            
            offset += data_size
        
        # Write image data
        for img_info in images_data:
            f.write(img_info['data'])
    
    print(f"\n✓ Created: {output_ico}")
    print("✓ ICO file ready for Windows .exe build")
    print("✓ Original PNG files preserved for MSIX package")

if __name__ == '__main__':
    png_dir = r'e:\ScheduleHQ\ScheduleHQ_Desktop\windows\runner\resources'
    output_ico = os.path.join(png_dir, 'app_icon.ico')
    
    create_ico_from_pngs(png_dir, output_ico)

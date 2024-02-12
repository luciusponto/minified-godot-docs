# minified-godot-docs
Godot documentation with drastically smaller file sizes for improved accessibility.

### Getting the minified docs
Download the desired version from the releases page.

### Size comparison for Godot 4.3:

| type | .zip size | decompressed size |
| --- | --- | --- |
| minified | 33 MB | 50 MB |
| regular | 305 MB | 1.6 GB |

### How it works

This project produces a significant smaller build of the docs by:
- Removing the class reference (by changing conf.py as below)
```python
exclude_patterns = ["_build", "classes"]
```
- Simplifying the sidebar links (by changing conf.py as below)
```python
html_theme_options = {
# keep usual options here, then append
"collapse_navigation": True,
}
```
- Making all animated gif and webp images into single frame images by extracting the 1st frame
- Re-compressing all images into webp (and overwriting the original images, some of which will now contain the wrong .webp file extension)


### Build instructions
To be added



## minified-godot-docs
Custom build of Godot manual with 40x smaller file size. Useful for offline reading, saving bandwidth, or browsing on low-end hardware.

Download the desired version from the [releases](https://github.com/luciusponto/minified-godot-docs/releases) page.

The Godot documentation was created by Juan Linietsky, Ariel Manzur and the Godot community under the CC BY 3.0 licence.

## Size comparison - Godot 4.3:

| type | .zip size | decompressed size |
| --- | --- | --- |
| minified html manual | 23 MB | 40 MB |
| regular html offline docs | 305 MB | 1.6 GB |

## Limitations
The class reference is omitted; it can be accessed inside the Godot editor with the F1 shortcut.

The sidebar navigation is simplified.

Images are heavily compressed. Some may be unreadable.

## Sidebar comparison
| Regular | Minified |
| --- | --- |
| ![Original navigation bar](/images/original-navbar.png) | ![Minified navigation bar](/images/minified-navbar.png) |

## Build Setup
### Windows
- Install python 3
- [Install Git for Windows](https://gitforwindows.org/) to have Git Bash. It will be needed to run the build script.
- [Set up Godot docs build environment](https://docs.godotengine.org/en/latest/contributing/documentation/building_the_manual.html), but don't clone the docs repo or run the make.bat command.
- Install [ImageMagick v7.x (static, 8-bit per pixel component)](https://imagemagick.org/script/download.php#windows), add to PATH
- Install [libwebp](https://developers.google.com/speed/webp/download), add bin folder to PATH


If you want to build pdf's, you also need these:
- [Install Weasyprint dependencies, then Weasyprint itself](https://doc.courtbouillon.org/weasyprint/stable/first_steps.html#windows)
- Ensure GTK bin folder from Weasyprint dependencies is added to PATH



## Build instructions
### Windows
- Download zip of docs repo you want to build. E.g., [master](https://github.com/godotengine/godot-docs/archive/refs/heads/master.zip).
- Open git bash
- To build the manual in html format:
```sh
source ./godot-docs-venv/Scripts/activate
./small_build.sh [zip path] --format=html --content=manual --yes-to-all=true
```


For other build options, display the help:
```sh
./small_build.sh
```

## How it works

This project produces a significant smaller build of the docs by:

- Simplifying the sidebar links (by changing conf.py as below), saves ~ 438 MB
```python
html_theme_options = {
# keep usual options here, then append
"collapse_navigation": True,
}
```

- Removing the class reference (by changing conf.py as below), saves ~ 68 MB
```python
exclude_patterns = ["_build", "classes"]
```

- Making all animated gif and webp images into single frame images by extracting the 1st frame
- Resizing and re-compressing all images

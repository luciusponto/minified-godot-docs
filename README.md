## minified-godot-docs
Custom build of Godot manual with much smaller file size. Useful for offline reading, saving bandwidth, or browsing on low-end hardware.

Download the desired version from the [releases](https://github.com/luciusponto/minified-godot-docs/releases) page.

On desktop, html works well. On mobile devices, pdf might be a good choice.

The Godot documentation was created by Juan Linietsky, Ariel Manzur and the Godot community under the CC BY 3.0 licence.

## Size comparison - Godot 4.2:

| type | download size | decompressed size |
| --- | --- | --- |
| regular html offline docs | 305 MB | 1.6 GB |
| minified html manual | 28 MB | 46 MB |
| minified pdf manual | 25 MB | 30 MB |
| minified epub manual | 20 MB | 20 MB |

## Limitations
The class reference is omitted; it can be accessed inside the Godot editor with the F1 shortcut.

The sidebar navigation is simplified in the html version.

Images are heavily compressed. Some may be unreadable.

Animations are replaced by a still image of their first frame.

## Sidebar comparison
| Regular | Minified |
| --- | --- |
| ![Original navigation bar](/images/original-navbar.png) | ![Minified navigation bar](/images/minified-navbar.png) |

## Image compression
Done with libwebp for webp only and Image Magick 7 for other formats.
The defaults below could be out of date. Double check in the small_build.sh code.

### Default settings
jpg quality = 50
webp quality = 50

### Default resize resolution
Resized keeping aspect ratio.
Max width = 800
Max height = 1024


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

On an old i5 desktop, the build process takes around 45 minutes.

### Windows
- Download zip of docs repo you want to build. E.g., [master](https://github.com/godotengine/godot-docs/archive/refs/heads/master.zip).
- Open git bash
- To build the manual in html format:
```sh
./small_build.sh [zip path] --format=html --content=manual --yes-to-all
```


For other build options, display the help:
```sh
./small_build.sh
```

## How it works

This project reduces the size of the the docs through:

- Simplifying the sidebar links (by changing conf.py as below), saves ~ 438 MB in the html build
```python
html_theme_options = {
# keep usual options here, then append
"collapse_navigation": True,
}
```

- Removing the class reference (by changing conf.py as below), saves ~ 68 MB in the html build
```python
exclude_patterns = ["_build", "classes"]
```

- Making all animated gif and webp images into single frame images by extracting the 1st frame
- Resizing and re-compressing all images

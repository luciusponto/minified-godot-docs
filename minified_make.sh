#!/bin/bash

# TODO: put those tools in PATH and remove below lines
SPHINX_BUILD=../godot-docs-venv/Scripts/sphinx-build.exe
WEBPMUX=../libwebp-1.3.2-windows-x64/bin/webpmux.exe
WEBPINFO=../libwebp-1.3.2-windows-x64/bin/webpinfo.exe
GIF2WEBP=../libwebp-1.3.2-windows-x64/bin/gif2webp.exe
CWEBP=../libwebp-1.3.2-windows-x64/bin/cwebp.exe
DWEBP=../libwebp-1.3.2-windows-x64/bin/dwebp.exe
MOGRIFY=../ImageMagick-7.1.1-27-portable-Q8-x64/mogrify.exe
CONVERT=../ImageMagick-7.1.1-27-portable-Q8-x64/convert.exe

# find_files extension min_size_kb
# e.g.: find_files webp 20
find_files () {
	find $IMAGES_BKP -type f -size +$2k -iname "*.$1" -print | sed -e "s/.*\///g"
}

# turn movies into first frame still; recompress stills with lossy compression
process_webp () {
	for file in $(find_files webp 30); do
		input_path=$IMAGES_BKP/$file
		output_path=$IMAGES/$file
		input_size=$(ls -lh $input_path | cut -f5 -d" ")
		image_type=still
		frames_line=$($WEBPINFO -quiet -summary $input_path | grep "Number of frames: ")
		if [ $? -eq 0 ]; then
			frame_count=$(echo $frames_line | sed -e "s/Number of frames. //")
			#echo "-$frame_count-"
			if [ "$frame_count" -gt 1 ]; then
				image_type=movie
				#echo $file is input_path with $frame_count frames
				# extract first frame only
				$WEBPMUX -get frame 1 $input_path -o $output_path  2> /dev/null 1> /dev/null
			fi
		fi
		if [ "$image_type" == "still" ]; then
			png_file=$TMP_IMAGES/$(echo $file | sed -e "s/\.webp/\.png/")
			# convert to png
			$DWEBP $input_path -o $png_file 2> /dev/null 1> /dev/null
			# convert back to webp with lossy compression
			$CWEBP $png_file -o $output_path 2> /dev/null 1> /dev/null
			[ -f "$png_file" ] && rm $png_file
		fi
		output_size=$(ls -lh $output_path | cut -f5 -d" ")
		[ "$input_size" != "$output_size" ] && echo "$image_type: $input_size => $output_size ($file)"
	done
}

# turn movies into first frame still; recompress stills with lossy compression
process_gif () {
	for file in $(find_files gif 30); do
		input_path=$IMAGES_BKP/$file
		webp_file=$TMP_IMAGES/$(echo $file | sed -e "s/\.gif/\.webp/")
		webp_single_frame=$TMP_IMAGES/first_frame.webp
		output_path=$IMAGES/$file
		input_size=$(ls -lh $input_path | cut -f5 -d" ")
		image_type=still
		$GIF2WEBP $input_path -o $webp_file 2> /dev/null 1> /dev/null
		[ $? -ne 0 ] && continue
		input_path=$webp_file
		frames_line=$($WEBPINFO -quiet -summary $input_path | grep "Number of frames: ")
		if [ $? -eq 0 ]; then
			frame_count=$(echo $frames_line | sed -e "s/Number of frames. //")
			#echo "-$frame_count-"
			if [ "$frame_count" -gt 1 ]; then
				image_type=movie
				#echo $file is input_path with $frame_count frames
				# extract first frame only
				$WEBPMUX -get frame 1 $input_path -o $webp_single_frame  2> /dev/null 1> /dev/null
			fi
		fi
		if [ "$image_type" == "still" ]; then
			png_file=$TMP_IMAGES/$(echo $file | sed -e "s/\.webp/\.png/")
			# convert to png
			$DWEBP $input_path -o $png_file 2> /dev/null 1> /dev/null
			# convert back to webp with lossy compression
			$CWEBP $png_file -o $webp_single_frame 2> /dev/null 1> /dev/null
			[ -f "$png_file" ] && rm $png_file
		fi
		$CONVERT $webp_single_frame $output_path
		[ -f "$webp_file" ] && rm $webp_file
		[ -f "$webp_single_frame" ] && rm $webp_single_frame
		output_size=$(ls -lh $output_path | cut -f5 -d" ")
		[ "$input_size" != "$output_size" ] && echo "$image_type: $input_size => $output_size ($file)"
	done
}

# Hack! Convert png to webp, but leave output named as .png, so we don't have to change html files.
# Still worked on Chrome, Firefox, Edge on Windows with wrongly named webp files.
process_png () {
	for file in $(find_files png 30); do
		input_path=$IMAGES_BKP/$file
		output_path=$IMAGES/$file
		input_size=$(ls -lh $input_path | cut -f5 -d" ")
		$CWEBP $input_path -o $output_path 2> /dev/null 1> /dev/null
		output_size=$(ls -lh $output_path | cut -f5 -d" ")
		[ "$input_size" != "$output_size" ] && echo "still: $input_size => $output_size ($file)"
	done
}

build () {
	# build with collapsed navigation tree to save a lot of disk space
	# exclude classes directory to build faster and save disk space
	cp conf.$BUILDTYPE.py conf.py
	
	  # Remove banners at the top of each page when building `latest`.
	  sed -i 's/"godot_is_latest": True/"godot_is_latest": False/' conf.py
	  sed -i 's/"godot_show_article_status": True/"godot_show_article_status": False/' conf.py	
	
	[ ! -d $BUILDDIR ] && mkdir -p $BUILDDIR

	$SPHINX_BUILD -M html . $BUILDDIR

	# remove _downloads folder to save disk space. Some links for tutorial follow along resources will break, but it's pretty minor.
	 rm -rf $BUILDDIR/html/_downloads
	 

	[ ! -d $TMP_IMAGES ] && mkdir -p $TMP_IMAGES
	[ ! -d $IMAGES_BKP ] && cp -r $IMAGES $IMAGES_BKP

	process_webp
	process_gif
	process_png
}

BUILDTYPE=manual
BUILDDIR=_build/$BUILDTYPE
IMAGES=$BUILDDIR/html/_images
IMAGES_BKP=$BUILDDIR/html/_images_orig
TMP_IMAGES=$BUILDDIR/html/_tmp_images

# uncomment below to generate manual
build

BUILDTYPE=classes
BUILDDIR=_build/$BUILDTYPE
IMAGES=$BUILDDIR/html/_images
IMAGES_BKP=$BUILDDIR/html/_images_orig
TMP_IMAGES=$BUILDDIR/html/_tmp_images

# uncomment below to generate classes reference
#build

set_vars () {
	TEST_VAR=test2
}

export_vars () {
	export TEST_VAR=test3
}

TEST_VAR=test1
echo $TEST_VAR

set_vars
echo $TEST_VAR

export_vars
echo $TEST_VAR

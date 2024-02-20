#!/bin/bash

JPG_QUALITY=50
WEBP_QUALITY=50
JPG_FALLBACK_THRESHOLD_KB=50
PNG_MAX_COLORS=16 # max colors per channel
PNG_DEPTH=4 # bit-depth per channel (e.g. 4 means a maximum of 16 different colors per channel, 16^3 total different colors)

# resize if image exceeds max width and/or max height, keeping aspect ratio
IMG_MAGICK_RESIZE_RES="800x1024>"

TOO_FEW_ARGUMENTS=1
FILE_NOT_FOUND=2
INVALID_ARGUMENT=3
ZIP_ERROR=4
CANNOT_OVERWRITE=5
DEPENDENCY_NOT_FOUND=6

# get_size file_path unit_letter
# e.g. get_size foo.txt k 		# return size in kB
# e.g. get_size foo.txt M			# return size in MB
get_size () {
	[ $# -lt 1 ] && return $TOO_FEW_ARGUMENTS
	unit=$2
	[ $# -lt 2 ] && unit=k
	[ ! -f $1 ] && echo "File not found: $1" >2 && return $FILE_NOT_FOUND
	ls -l --block-size=1${unit} $1 | sed -e "s/[ ][ ]*/ /g" | cut -f 5 -d " "
}

# process_webp_image input_path tmp_path
process_webp_image () {
	seq_type=still
	webpmux -get frame 1 $1 -o $2  2> /dev/null 1> /dev/null && seq_type=movie
	# convert to png
	dwebp $1 -mt -o $temp_png 2> /dev/null 1> /dev/null
	magick $temp_png -resize $IMG_MAGICK_RESIZE_RES -interlace none -strip $temp_png >/dev/null 2>&1
	# convert back to webp with lossy compression
	cwebp $temp_png -mt -preset text -q $WEBP_QUALITY -o $2 2> /dev/null 1> /dev/null
}

# process_gif_image input_path tmp_path
process_gif_image () {
	[ $# -lt 2 ] && return $TOO_FEW_ARGUMENTS
	[ ! -f "$1" ] && echo "$0: input file does not exist: $1" >2 && return 2

	seq_type=still
	frame_count=$($MAGICK identify "$1" | grep -iPe "gif\[[0-9]+\]" | wc -l)
	[ "$frame_count" != "" ] && [ $frame_count -gt 1 ] && seq_type=movie
	# save only first frame of animation
	magick "$1[0]" +dither -resize $IMG_MAGICK_RESIZE_RES -colors $PNG_MAX_COLORS -depth $PNG_DEPTH -strip $2
}

# process_jpg_image input_path tmp_path
process_jpg_image () {
	[ $# -lt 2 ] && return $TOO_FEW_ARGUMENTS
	[ ! -f "$1" ] && echo "$0: input file does not exist: $1" >2 && return 2

	# save only first frame of animation
	magick $1 -resize $IMG_MAGICK_RESIZE_RES -quality $JPG_QUALITY -interlace none -strip $2
}

# process_png_image input_path tmp_path
process_png_image () {
	[ $# -lt 2 ] && return 1
	[ ! -f "$1" ] && echo "$0: input file does not exist: $1" >2 && return 2
	input_png=$1
	output_png=$2
	magick $input_png +dither -resize $IMG_MAGICK_RESIZE_RES -colors $PNG_MAX_COLORS -depth $PNG_DEPTH -interlace none -strip $output_png #>/dev/null 2>&1
}

# process_images file_extension min_size_kb
# e.g.: process_images png 30
process_images () {
	file_extension=$1
	files=(./$zip_root/**/*.$file_extension)
	total_files=${#files[@]}
	echo Found $total_files $file_extension files
	processed=0
	original_total=0
	new_total=0
	overwrite_total=0
	temp_path=./tmp_file.$file_extension
	for file in "${files[@]}"; do
		processed=$(( processed + 1 ))
		input_path=$file
		seq_type="still"
		case "$file_extension" in
		   "png") process_png_image $input_path $temp_path
		   ;;
			# TODO if epub, convert webp to jpg and update *.srt to reference jpg instead of webp
		   "webp") process_webp_image $input_path $temp_path
		   ;;
		   "gif") process_gif_image $input_path $temp_path
		   ;;
		   "jpg") process_jpg_image $input_path $temp_path
		   ;;
		   "jpeg") process_jpg_image $input_path $temp_path
		   ;;
		esac
		
		original_size=$(get_size $input_path)
		original_total=$(( original_total + original_size ))
		
		if [ "$temp_path" == "" ] || [ ! -f "$temp_path" ]; then
			echo "Error: could not process $input_path"
			# new_total=$(( new_total + original_size ))
			overwrite_total=$(( overwrite_total + original_size ))
			continue
		fi

		new_size=$(get_size $temp_path)
		
		short_path=$(basename $file)
		# echo "$file size  - $short_path orig: $original_size; $temp_path new: $new_size"
		if [ "$new_size" -lt "$original_size" ]; then
			echo "$seq_type: $original_size => $new_size ($short_path$colors_st - $processed/$total_files)"
			cp $temp_path $input_path
		else
			echo "$seq_type: kept size: $original_size ($short_path$colors_st - $processed/$total_files)"
		fi
		overwrite_size=$(get_size $input_path)
		overwrite_total=$(( overwrite_total + overwrite_size ))
	done
	[ -f "$temp_path" ] && rm "$temp_path"
	diff_k=$(( original_total - overwrite_total ))
	diff_M=$(( diff_k / 1024 ))
	echo "$original_total => $overwrite_total; diff: $diff_M MiB"
}

get_zip_root_dir () {
	7z l $1 | tail -n3 | head -n1 | sed -e "s/[ ][ ]*/ /g" | cut -f 6 -d" " | sed -e "s/[\\].*//" | sed -e "s/\/.*//"
}

missing_args () {
	echo "$1: Missing arguments. Expected at least $2, only $3 received".
	return $
}

check_arg_count () {
	expected_arg_count=$2
	actual_arg_count=$(( $# - 2 ))
	
	if [ $actual_arg_count -lt $expected_arg_count ]; then
		echo -e "$1: Too few arguments. Expected at least $expected_arg_count, only $actual_arg_count received.\n"
		return $TOO_FEW_ARGUMENTS
	fi
}

exit_error () {
	echo "Exiting with error code $1"
	exit $1
}

exit_help () {
	cat small_build_help.txt | sed -e "s/SCRIPT_NAME/"$script_name"/g"
	exit $1
}

# exit_msg_code msg error_code
# e.g. exit_msg_code "File x not found" $FILE_NOT_FOUND
exit_msg_code () {
	echo -e "$1\n"
	exit_help $2
}

# get_arg arg_name default_value $@(all_arguments)
# E.g. get_arg max_res 1024 $@
get_arg () {
	local arg_name=$1
	local short_arg_name=$2
	local arg_value=$3
	shift 4
	
	local arg=""
	
	for arg in $@; do
		echo $arg | grep -e "^--$arg_name\=[^ ]" >/dev/null 2>&1 || echo $arg | grep -e "^-$short_arg_name\=[^ ]" >/dev/null 2>&1 
		if [ $? -eq 0 ]; then
			arg_value=$(echo "$arg" | sed -e "s/[^\=]*\=//")
			break
		fi
	done
	to_lower $arg_value
}

clear_dir () {
	local dir_to_clear=$1
	if [ -d ${dir_to_clear} ]; then
		if [ "$auto_overwrite" == "true" ]; then
			echo "Deleting ${dir_to_clear}..." && rm -rf "$dir_to_clear"
		else
			exit_msg_code "Aborted: cannot clear directory $dir_to_clear. Remove it manually or run with --auto-overwrite=true" $CANNOT_OVERWRITE
		fi
	fi
	return 0
}

clear_build_dir () {
	clear_dir ${BUILD_ROOT}
	return $?
}

clear_source_dir () {
	clear_dir $zip_root
	return $?
}

unzip_source_zip () {
	echo "Unzipping $source_zip..."

	# unzip godot-docs zip file, overwriting any pre-existing files
	7z x -y $source_zip || exit_msg_code "Error: could not unzip $source_zip." $ZIP_ERROR
}

to_lower () {
	echo $@ | tr '[:upper:]' '[:lower:]'
}

process_all_images () {
	
	temp_png=./tmp1.png

	process_images png
	process_images gif
	process_images webp
	process_images jpg
	process_images jpeg
	
	[ -f "temp_png" ] && rm "$temp_png"

}

build () {
	local exclude_patterns_string="["
	local exclude_folder
	
	for exclude_folder in $exclude_patterns; do
		exclude_patterns_string="$exclude_patterns_string\"$exclude_folder\", "
	done
	
	exclude_patterns_string=$(echo "$exclude_patterns_string" | sed -e "s/\,[ ]*$/\]/")

	# Exclude directories according to building manual or class reference
	sed -i "s/exclude_patterns \=.*/exclude_patterns \=${exclude_patterns_string}/" "${zip_root}/conf.py"
	
	# Enable collapse_navigation to greatly reduce size of html at the cost of reduced sidebar functionality
	sed -i 's/"collapse_navigation": False/"collapse_navigation": True/' "${zip_root}/conf.py"
	
	# Remove banners at the top of each page when building `latest`.
	sed -i 's/"godot_is_latest": True/"godot_is_latest": False/' "${zip_root}/conf.py"
	sed -i 's/"godot_show_article_status": True/"godot_show_article_status": False/' "${zip_root}/conf.py"
	
	godot_version=$(grep "Godot Docs" ${zip_root}/index.rst | head -n1 | sed -e "s/^[^\*]*[\*]//" | sed -e "s/[\*].*$//")
	
	output_file_name="godot-${output_content}-${output_format}-${godot_version}"
	
	pdf_name="${output_file_name}.pdf"
	inject_simplepdf_1="simplepdf_use_weasyprint_api = True\n"
	inject_simplepdf_2="simplepdf_file_name = \"${pdf_name}\"\n\n"

	grep -qe "simplepdf_use_weasyprint_api" "${zip_root}/conf.py" || sed -i "s/extensions = \[/${inject_simplepdf_1}${inject_simplepdf_2}extensions = \[/" "${zip_root}/conf.py"

	sphinx-build -M $sphinx_builder "$zip_root" $BUILD_OUTPUT_PATH
	
	initial_dir=$(pwd)
	artifact_dir="${initial_dir}/_artifacts"
	[ ! -d "$artifact_dir" ] && mkdir -p "$artifact_dir"

	
	if  [ "$output_format" == "html" ]; then
		zip_file="${artifact_dir}/${output_file_name}.zip"
		[ -f "$zip_file" ] && rm "$zip_file"
		cd _build/html/${output_content}
		files=(html/*)
		for file in "${files[@]}"; do
			local zip_exclusions="_sources$"
			[ "$exclude_downloads" == "true" ] && zip_exclusions="${zip_exclusions}\|_downloads\$"
			echo "$file" | grep -qe "_sources$" && continue
			[ -f "$file" ] && echo "Adding file $file to zip..." && 7z a "$zip_file" "$file" >/dev/null
			[ -d "$file" ] && echo "Adding dir $file to zip..." && 7z a "$zip_file" "$file" >/dev/null
		done
		cd ${initial_dir}
	elif [ "$output_format" == "epub" ] || [ "$output_format" == "pdf" ]; then
		echo "Moving $output_format to ${artifact_dir}..."
		artifact_file_glob="${BUILD_OUTPUT_PATH}/${sphinx_builder}/*.${output_format}"
		mv $artifact_file_glob "$artifact_dir"
	fi

}

prepare () {
	script_name=$(basename "$0")

	check_arg_count $0 1 $@ || exit_help $?
	source_zip=$1

	echo "$source_zip" | grep -ie "^.*\.zip$" >/dev/null 2>&1 || exit_msg_code "The first argument must be a zip file" $INVALID_ARGUMENT
	[ ! -f $source_zip ] && exit_msg_code "Error: file not found: $source_zip" $FILE_NOT_FOUND

	output_content=$(get_arg content c manual $@)
	output_format=$(get_arg format f html $@)
	image_quality=$(get_arg quality q low $@)
	max_res=$(get_arg max_res mr 1024 $@)
	auto_overwrite=$(get_arg auto_overwrite ao false $@)
	exclude_downloads=$(get_arg exclude_downloads ed false $@)
	sphinx_builder=""
	
	local BUILD_ROOT=_build
	
	if [ "$output_format" == "html" ]; then
		sphinx_builder=html
	elif [ "$output_format" == "epub" ]; then
		sphinx_builder=epub
	elif [ "$output_format" == "pdf" ]; then
		sphinx_builder=simplepdf
	else
		exit_msg_code "Invalid output_format: $output_format" $INVALID_ARGUMENT
	fi
	
	BUILD_OUTPUT_PATH=${BUILD_ROOT}/${output_format}/${output_content}

	
	exclude_patterns=_build
	if [ "$output_content" == "manual" ]; then
		exclude_patterns="_build classes"
	elif [ "$output_content" == "classes" ]; then
		exclude_patterns="_build about community contributing getting_started tutorials"
	elif [ "$output_content" == "about" ]; then
		exclude_patterns="_build classes community contributing getting_started tutorials"
	else
		exit_msg_code "Invalid output_content: $output_content" $INVALID_ARGUMENT
	fi
	
	echo -e "Running with:\n\toutput_content=$output_content\n\toutput_format=$output_format"
	echo -e "\timage_quality=$image_quality\n\tmax_res=$max_res\n\tauto_overwrite=$auto_overwrite\n\texclude_downloads=$exclude_downloads"
	echo ""

	zip_root=$(get_zip_root_dir $source_zip)
	
}

check_dependencies () {
	local deps=(webpmux cwebp dwebp magick 7z sphinx-build libgobject-2.0-0.dll)
	for dep in "${deps[@]}"; do
		which $dep >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "Dependency $dep not found. Check that it is installed and can be found by the which command"
			exit $DEPENDENCY_NOT_FOUND
		fi
	done
}

check_dependencies

shopt -s globstar
shopt -s nullglob

# TODO add args to skip some of the stages below, except prepare 

prepare $@
clear_build_dir
clear_source_dir
unzip_source_zip
process_all_images
build

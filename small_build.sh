#!/bin/bash

BUILD_ROOT=_build

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
	local output_image_ext="$3"
	seq_type=still
	webpmux -get frame 1 "$1" -o "$2"  2> /dev/null 1> /dev/null && seq_type=movie
	
	# convert to png
	if [ "$seq_type" == "still" ]; then
		dwebp "$1" -mt -o "$temp_png" 2> /dev/null 1> /dev/null
	else
		dwebp "$2" -mt -o "$temp_png" 2> /dev/null 1> /dev/null
	fi
	
	if [ "$output_image_ext" == "png" ]; then
		process_png_image "$temp_png" "$2"
	else
		magick "$temp_png" -resize $IMG_MAGICK_RESIZE_RES -interlace none -strip "$temp_png" >/dev/null 2>&1
		# convert back to webp with lossy compression
		cwebp "$temp_png" -mt -preset text -q $WEBP_QUALITY -o "$2" 2> /dev/null 1> /dev/null
	fi
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
	local file_extension="$1"
	local output_file_extension="$2"
	[ "$should_process_images" != "true" ] && [ "$should_process_images" != "$file_extension" ] && return 0
	local files=(./$zip_root/**/*.$file_extension)
	local total_files=${#files[@]}
	echo -e "\nProcessing $file_extension files..."
	local processed=0
	local original_total=0
	local new_total=0
	local overwrite_total=0
	local temp_path=./tmp_file.$output_file_extension
	local file=""
	for file in "${files[@]}"; do
		processed=$(( processed + 1 ))
		if  [ $debug_max_images -gt -1 ] && [ $processed -gt $debug_max_images ]; then
			break
		fi
		local input_path=$file
		local seq_type="still"
		case "$file_extension" in
		   "png") process_png_image "$input_path" "$temp_path"
		   ;;
			# TODO if epub, convert webp to jpg and update *.srt to reference jpg instead of webp
		   "webp") process_webp_image "$input_path" "$temp_path" "$output_file_extension"
		   ;;
		   "gif") process_gif_image "$input_path" "$temp_path"
		   ;;
		   "jpg") process_jpg_image "$input_path" "$temp_path"
		   ;;
		   "jpeg") process_jpg_image "$input_path" "$temp_path"
		   ;;
		esac
		
		local original_size=$(get_size $input_path)
		original_total=$(( original_total + original_size ))
		
		if [ "$temp_path" == "" ] || [ ! -f "$temp_path" ]; then
			echo "Error: could not process $input_path"
			# new_total=$(( new_total + original_size ))
			overwrite_total=$(( overwrite_total + original_size ))
			continue
		fi

		local new_size=$(get_size $temp_path)
		
		local short_path=$(basename $file)
		local input_dir=$(echo $file | sed -e "s/\/[^\/]*$//")
		local short_path_no_ext=$(echo $short_path | sed -e "s/\.[^\.]*$//")
		local output_short_path="${short_path_no_ext}.${output_file_extension}"
		local output_path="${input_dir}/${output_short_path}"

		if [ "$new_size" -lt "$original_size" ] || [ "$input_path" != "$output_path" ]; then
			echo "$seq_type: $original_size => $new_size ($short_path$colors_st - $processed/$total_files)"
			cp $temp_path $output_path
		else
			echo "$seq_type: kept size: $original_size ($short_path$colors_st - $processed/$total_files)"
		fi
		local overwrite_size=$(get_size $output_path)
		overwrite_total=$(( overwrite_total + overwrite_size ))
	done
	[ -f "$temp_path" ] && rm "$temp_path"
	local diff_k=$(( original_total - overwrite_total ))
	local diff_M=$(( diff_k / 1024 ))
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
# E.g. get_arg output_format html $@
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

# e.g. confirm_dir_destruction "$zip_root" "directory where zip source was unzipped" "overwrite"
# e.g. confirm_dir_destruction "$zip_root" "directory where zip source was unzipped" "delete"
confirm_dir_destruction () {
	echo ""

	[ "$yes_to_all" == "true" ] && return 0
	
	local target_dir="$1"
	local dir_description="$2"
	local action="$3"
	
	[ ! -d "${target_dir}" ] && return 0

	local can_overwrite="tbd"

	while [ "$can_overwrite" != "y" ] && [ "$can_overwrite" != "n" ]; do
		read -p "About to ${action} contents of ${dir_description} (${target_dir}). Proceed? (y/n): " can_overwrite
		can_overwrite=$(echo "$can_overwrite" | tr '[:upper:]' '[:lower:]')
	done
	
	[ "$can_overwrite" == "y" ]; return $?
}

clear_dir () {
	local dir_to_clear="$1"
	local dir_description="$2"
	if [ -d "$dir_to_clear" ]; then
		if confirm_dir_destruction "$dir_to_clear" "$dir_description" "delete"; then
			echo "Deleting ${dir_to_clear}..." && rm -rf "$dir_to_clear"
		else
			echo "Aborted: cannot clear directory $dir_to_clear. Remove it manually or run with --auto-overwrite=true" && exit $CANNOT_OVERWRITE
		fi
	fi
}

clear_build_dir () {
	[ "$should_clear_build_dir" != "true" ] && return 0
	clear_dir "${BUILD_ROOT}"  "build directory"
	return $?
}

clear_source_dir () {
	[ "$should_clear_source" != "true" ] && return 0
	clear_dir "$zip_root" "directory where zip source was unzipped"
	return $?
}

unzip_source_zip () {
	[ "$should_unzip_source" != "true" ] && return 0
	
	echo ""
	
	if [ -d "${zip_root}" ] && ! confirm_dir_destruction "${zip_root}" "directory where zip source was unzipped" "overwrite"; then
		echo "Aborted: cannot overwrite directory ${zip_root}." && exit $CANNOT_OVERWRITE
	fi

	echo -e "\nUnzipping $source_zip..."
	
	# unzip godot-docs zip file, overwriting any pre-existing files
	7z x -y $source_zip || exit_msg_code "Error: could not unzip $source_zip." $ZIP_ERROR
}

to_lower () {
	echo $@ | tr '[:upper:]' '[:lower:]'
}

process_all_images () {
	[ "$should_process_images" == "false" ] && return 0
	
	temp_png=./tmp1.png

	process_images png png
	process_images gif gif
	process_images jpg jpg
	process_images jpeg jpeg
	if [ "$output_format" == "epub" ]; then
		# epub has patchy webp compatibility. Replace webp images with png images so that epub
		process_images webp png
	else
		process_images webp webp
	fi
	
	[ -f "temp_png" ] && rm "$temp_png"

}

build () {
	[ "$should_build" != "true" ] && return 0
	local conf_file="${zip_root}/conf.py"
	local conf_backup="${zip_root}/conf.orig.py"
	local index_file="${zip_root}/index.rst"
	local index_backup="${zip_root}/index.rst.bkp"
	local exclude_patterns_string="["
	local exclude_folder
	
	# create backups
	[ ! -f "$conf_backup" ] && cp "$conf_file" "$conf_backup"
	[ ! -f "$index_backup" ] && cp "$index_file" "$index_backup"
	
	# restore backups
	cp "$conf_backup" "$conf_file"
	cp "$index_backup" "$index_file"
		
	for exclude_folder in $exclude_patterns; do
		exclude_patterns_string="$exclude_patterns_string\"$exclude_folder\", "
	done
	
	exclude_patterns_string=$(echo "$exclude_patterns_string" | sed -e "s/\,[ ]*$/\]/")

	# Exclude directories according to building manual or class reference
	sed -i "s/exclude_patterns \=.*/exclude_patterns \=${exclude_patterns_string}/" "$conf_file"
	
	# Enable collapse_navigation to greatly reduce size of html at the cost of reduced sidebar functionality
	[ "$output_format" == "html" ] &&	sed -i 's/"collapse_navigation": False/"collapse_navigation": True/' "$conf_file"
	
	# Remove banners at the top of each page when building `latest`.
	sed -i 's/"godot_is_latest": True/"godot_is_latest": False/' "$conf_file"
	sed -i 's/"godot_show_article_status": True/"godot_show_article_status": False/' "$conf_file"

	local godot_version=$(grep "Godot Docs" ${zip_root}/index.rst | head -n1 | sed -e "s/^[^\*]*[\*]//" | sed -e "s/[\*].*$//" | sed -e "s/\./_/g")
	local output_file_name="godot-${output_content}-${godot_version}"
	
	if [ "$output_format" == "epub" ]; then
		# Enable table of contents in epub files
		sed -i 's/:hidden://g' "$index_file"
		
		# Fix output file name
		sed -i "s/project = \"Godot Engine\"/project = \"${output_file_name}\"/g" "$conf_file"

		if [ "$process_all_images" == "true" ] || [ "$process_all_images" == "webp" ]; then
			echo "Replacing webp references with png..."
			# replace references to webp images with references to png images
			rst_files=(./$zip_root/{about,community,contributing,getting_started,tutorials}/**/*.rst)
			for rst_file in "${rst_files[@]}"; do
				sed -i "s/\.webp$/\.png/g" $rst_file
			done
			echo "Finished."
		fi
	fi
	
	local pdf_name="${output_file_name}.pdf"
	local inject_simplepdf_1="simplepdf_use_weasyprint_api = True\n"
	local inject_simplepdf_2="simplepdf_file_name = \"${pdf_name}\"\n\n"

	grep -qe "simplepdf_use_weasyprint_api" "$conf_file" || sed -i "s/extensions = \[/${inject_simplepdf_1}${inject_simplepdf_2}extensions = \[/" "$conf_file"

	sphinx-build -M $sphinx_builder "$zip_root" $BUILD_OUTPUT_PATH
	
	initial_dir=$(pwd)
	artifact_dir="${initial_dir}/_artifacts"
	[ ! -d "$artifact_dir" ] && mkdir -p "$artifact_dir"

	
	if  [ "$output_format" == "html" ]; then
		local zip_file="${artifact_dir}/${output_file_name}-html.zip"
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
		local artifact_file_name="${output_file_name}.${output_format}"
		local artifact_origin="${BUILD_OUTPUT_PATH}/${sphinx_builder}/${artifact_file_name}"
		local artifact_destination="$artifact_dir/${artifact_file_name}"
		echo "Moving $output_format to ${artifact_dir}..."
		cp "$artifact_origin" "$artifact_destination"
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
	yes_to_all=$(get_arg yes-to-all y false $@)
	exclude_downloads=$(get_arg exclude-downloads ed false $@)
	should_clear_source_dir=$(get_arg clear-source-dir csd true $@)
	should_unzip_source=$(get_arg unzip-source us true $@)
	should_process_images=$(get_arg process-images pi true $@)
	should_clear_build_dir=$(get_arg clear-build-dir cbd true $@)
	should_build=$(get_arg build b true $@)
	debug_max_images=$(get_arg debug-max-images dmi -1 $@)
	
	sphinx_builder=""
	
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
	elif [ "$output_content" == "all" ]; then
		exclude_patterns="_build"
	else
		exit_msg_code "Invalid output_content: $output_content" $INVALID_ARGUMENT
	fi
	
	echo "Running with:"
	for run_option in output_content output_format yes_to_all exclude_downloads should_clear_source_dir should_unzip_source should_process_images should_clear_build_dir should_build debug_max_images; do
		option_value=$(eval "echo \$$run_option")
		echo -e "\t${run_option}: ${option_value}"
	done
	
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

prepare $@
clear_source_dir
clear_build_dir
unzip_source_zip
process_all_images
build

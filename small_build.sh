#!/bin/bash

source godot-docs-venv/Scripts/activate

BUILD_ROOT=_build

JPG_QUALITY=50
WEBP_QUALITY=50
JPG_FALLBACK_THRESHOLD_KB=50
PNG_MAX_COLORS=16 # max colors per channel
PNG_DEPTH=4 # bit-depth per channel (e.g. 4 means a maximum of 16 different colors per channel, 16^3 total different colors)

IMG_MAX_WIDTH=800
IMG_MAX_HEIGHT=1024

TOO_FEW_ARGUMENTS=1
FILE_NOT_FOUND=2
INVALID_ARGUMENT=3
ZIP_ERROR=4
CANNOT_OVERWRITE=5
DEPENDENCY_NOT_FOUND=6
COULD_NOT_EXTRACT_FRAME=7

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

compress_image () {
	[ $# -lt 3 ] && return $TOO_FEW_ARGUMENTS
	[ ! -f "$1" ] && echo "$0: input file does not exist: $1" >2 && return 2
	local input_file="$1"
	local output_file="$2"
	local output_type="$3"

	case "$output_type" in
			"png")
				magick "$input_file" +dither -resize $img_magick_resize_res -colors $PNG_MAX_COLORS -depth $PNG_DEPTH -interlace none -strip "$output_file" >/dev/null 2>&1
				;;
			"webp")
				echo "CI - Converting $input_file into $output_file"
				cwebp "$input_file" -mt -preset text -q $webp_quality -o "$output_file" >/dev/null 2>&1
				;;
			"gif")
				# TODO: find compression settings
				magick "$input_file" "$output_file"
				;;
			"jpg")
				magick "$input_file" -resize $img_magick_resize_res -quality $jpg_quality -interlace none -strip "$output_file"
				;;
		esac
}

# extracts first frame into png image
# extract_frame input_path output_path input_type
extract_first_frame () {
	[ $# -lt 3 ] && return $TOO_FEW_ARGUMENTS
	[ ! -f "$1" ] && echo "$0: input file does not exist: $1" >2 && return 2
	local input_file="$1"
	local output_file="$2"
	local input_type="$3"
	
	echo "Extract first frame: input_file = $input_file; output_file = $output_file; input_type = $input_type"

	seq_type=still

	case "$input_type" in
		"webp")
			webpmux -get frame 1 "$input_file" -o "$temp_webp" >/dev/null 2>&1 && seq_type=movie
			# convert to png
			if [ "$seq_type" == "still" ]; then
				dwebp "$input_file" -mt -o "$output_file" >/dev/null 2>&1
			else
				dwebp "$temp_webp" -mt -o "$output_file" >/dev/null 2>&1
			fi
			return $?
		;;
		"gif")
			local frame_count=$($MAGICK identify "$input_file" | grep -iPe "gif\[[0-9]+\]" | wc -l)
			[ "$frame_count" != "" ] && [ $frame_count -gt 1 ] && seq_type=movie
			# save only first frame of animation
			magick "$input_file[0]" -resize $img_magick_resize_res -interlace none -strip  "$output_file"
			return $?
		;;
	esac
		
	return $COULD_NOT_EXTRACT_FRAME
}

# process_images file_extension output_file_extension
# e.g.: process_images png png
process_images () {
	local file_extension="$1"
	local output_file_extension="$2"
	[ "$images_to_process" != "all" ] && [ "$images_to_process" != "$file_extension" ] && return 0

	local files=()
	local inc_pattern
	for inc_pattern in $include_patterns; do
		files+=(./$zip_root/$inc_pattern/**/*.$file_extension)
	done

	local total_files=${#files[@]}
	echo -e "\nProcessing $file_extension files, $total_files found..."
	local processed=0
	local original_total=0
	local overwrite_total=0
	
	local file=""
	for file in "${files[@]}"; do
		# echo $file | sed -e "s/.*$zip_root\///"

		local temp_path=./tmp_file.$output_file_extension
		local single_frame=./single_frame.png
	
		processed=$(( processed + 1 ))
		if  [ $debug_max_images -gt -1 ] && [ $processed -gt $debug_max_images ]; then
			break
		fi
		
		local input_path=$file
		local original_size=$(get_size $input_path)
		original_total=$(( original_total + original_size ))		
		
		local seq_type="still"

		# extract 1st frame into image magick compatible input file
		if [ "$file_extension" == "webp" ] || [ "$file_extension" == "gif" ]; then
			extract_first_frame "$input_path" "$single_frame" "$file_extension"
		else	
			single_frame="$input_path"
		fi
		
		compress_image "$single_frame" "$temp_path" $output_file_extension
	
		if [ "$temp_path" == "" ] || [ ! -f "$temp_path" ]; then
			echo "Error: could not process $input_path"
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
			echo -n "$seq_type: $original_size => $new_size"
			[ "$input_path" != "$output_path" ] && echo -n "; $file_extension => $output_file_extension"
			echo " ($short_path - $processed/$total_files)"
			cp $temp_path $output_path
		else
			echo "$seq_type: kept size: $original_size ($short_path - $processed/$total_files)"
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

# get_arg arg_name default_value is_toggle $@(all_arguments)
# E.g. get_arg output_format html $@
get_arg () {
	echo -n "." 1>&2
	local arg_name=$1
	local short_arg_name=$2
	local arg_value=$3
	local is_toggle=$4
	shift 5
	
	local new_val=""
	
	if [ "$is_toggle" == "true" ]; then
		new_val="false"
		echo $@ | grep -qPe "--$arg_name[^\=]|-$short_arg_name[^\=]|--${arg_name}$|-${short_arg_name}$" && new_val="true"
	else
		new_val=$(echo $@ | grep -ohPe "--$arg_name\=[^ \=]+|-$short_arg_name\=[^ \=]+" | sed -e "s/.*\=//")
	fi
	[ "$new_val" != "" ] && arg_value=$new_val

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
	[ "$keep_build_dir" == "true" ] && return 0
	clear_dir "${BUILD_ROOT}"  "build directory"
	return $?
}

clear_source_dir () {
	[ "$keep_source_dir" == "true" ] && return 0
	clear_dir "$zip_root" "directory where zip source was unzipped"
	return $?
}

unzip_source_zip () {
	[ "$dont_unzip_source" == "true" ] && return 0
	
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
	[ "$images_to_process" == "none" ] && return 0
	
	temp_png=./tmp1.png
	temp_webp=./tmp1.webp
	
	local source_img_ext
	
	for source_img_ext in $proc_images_ext; do
		local target_img_ext=$(eval echo "\$${source_img_ext}_output")
		process_images $source_img_ext $target_img_ext
	done
	
	[ -f "$temp_png" ] && rm "$temp_png"
	[ -f "$temp_webp" ] && rm "$temp_webp"

}

build () {
	[ "$dont_build" == "true" ] && return 0
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
	
	# fix image references after changing image format
	local img_ref_replacement=""
	local img_input_ext=""
	local img_output_ext=""

	for img_input_ext in webp png jpg gif; do
		img_output_ext=$(eval "echo \$${img_input_ext}_output")
		[ "$img_input_ext" != "$img_output_ext" ] && img_ref_replacement="${img_ref_replacement} -e \"s/\.${img_input_ext}$/\.${img_output_ext}/\""
	done
	
	echo -n "Fixing image references"

	local rst_files=()
	local inc_pattern
	for inc_pattern in $include_patterns; do
		rst_files+=(./$zip_root/$inc_pattern/**/*.rst)
	done
	for rst_file in ${rst_files[@]}; do
		echo -n "."
		eval "sed -i $img_ref_replacement $rst_file"
		processed_rst=$(( processed_rst + 1 ))
	done
	echo ""
		
	# set up which folders are excluded from build in conf.py
	for exclude_folder in $exclude_patterns; do
		exclude_patterns_string="$exclude_patterns_string\"$exclude_folder\", "
	done
	
	exclude_patterns_string=$(echo "$exclude_patterns_string" | sed -e "s/\,[ ]*$/\]/")

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

	elif [ "$output_format" == "pdf" ]; then
		# Set pdf settings in conf.py
		grep -qe "simplepdf_use_weasyprint_api" "$conf_file"
		if [ $? -ne 0 ]; then
			local pdf_name="${output_file_name}.pdf"
			# Use weasyprint python api. Default is using executable and did not work.
			local inject_simplepdf="simplepdf_use_weasyprint_api = True\n"
			inject_simplepdf="${inject_simplepdf}simplepdf_file_name = \"${pdf_name}\"\n"
			# Remove cover page from pdf output
			inject_simplepdf="${inject_simplepdf}simplepdf_theme_options = {\n\t\"nocover\": True,\n}\n"
			inject_simplepdf="${inject_simplepdf}\n"
			sed -i "s/\(extensions = \[\)/${inject_simplepdf}\1/" "$conf_file"
		fi
	fi

	sphinx-build -M $sphinx_builder "$zip_root" $BUILD_OUTPUT_PATH
	
	initial_dir=$(pwd)
	artifact_dir="${initial_dir}/_artifacts"
	[ ! -d "$artifact_dir" ] && mkdir -p "$artifact_dir"

	if  [ "$output_format" == "html" ]; then
		local zip_file="${artifact_dir}/${output_file_name}-${sphinx_builder}.zip"
		[ -f "$zip_file" ] && rm "$zip_file"
		cd _build/html/${output_content}
		files=($sphinx_builder/*)
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

	# check_arg_count $0 1 $@ || exit_help $?
	source_zip="$1"
	[ ! -f "$source_zip" ] && exit_msg_code "Error: file not found: $source_zip" $FILE_NOT_FOUND
	echo "$source_zip" | grep -ie "^.*\.zip$" >/dev/null 2>&1 || exit_msg_code "The first argument must be a zip file" $INVALID_ARGUMENT
	
	echo -n "Parsing args"

	# get_arg long_name short_name default_value is_toggle
	output_content=$(get_arg content c manual false $@)
	output_format=$(get_arg format f html false $@)
	max_width=$(get_arg max-width w $IMG_MAX_WIDTH false $@)
	max_height=$(get_arg max-height h $IMG_MAX_HEIGHT false $@)
	jpg_quality=$(get_arg jpeg-quality jq $JPG_QUALITY false $@)
	webp_quality=$(get_arg webp-quality wq $WEBP_QUALITY false $@)
	yes_to_all=$(get_arg yes-to-all y false true $@)
	exclude_downloads=$(get_arg exclude-downloads ed false true $@)
	keep_source_dir=$(get_arg debug-keep-source-dir dks false true $@)
	dont_unzip_source=$(get_arg debug-dont-unzip-source ddu false true $@)
	images_to_process=$(get_arg debug-process-images dpi all false $@)
	keep_build_dir=$(get_arg debug-keep-build-dir dkb false true $@)
	dont_build=$(get_arg debug-dont-build ddb false true $@)
	keep_all=$(get_arg debug-keep-all dka false true $@)
	debug_max_images=$(get_arg debug-max-images dmi -1 false $@)
	
	[ "$keep_all" == "true" ] && keep_source_dir=true && keep_build_dir=true && dont_unzip_source=true
	
	echo -e "\n\nRunning with:"
	local run_option
	for run_option in output_content output_format max_width max_height jpg_quality webp_quality images_to_process; do
		local option_value=$(eval "echo \$$run_option")
		echo -e "\t${run_option}: ${option_value}"
	done
	
	echo ""
	for run_option in yes_to_all exclude_downloads keep_source_dir dont_unzip_source keep_build_dir dont_build; do
		local toggle_value=$(eval "echo \$$run_option")
		[ "$toggle_value" == true ] && echo -e "\t${run_option}: ${toggle_value}"
	done
	
	if [ "$debug_max_images" != "-1" ]; then
		echo -e "\n\tdebug_max_images: $debug_max_images"
	fi
	
	img_magick_resize_res="${max_width}x${max_height}>"
	echo -e "\n\tImage Magick resize resolution: $img_magick_resize_res"
	
	echo ""
	
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
	
	include_patterns=""
	exclude_patterns=_build

	if [ "$output_content" == "manual" ]; then
		include_patterns="about community contributing getting_started tutorials"
		# exclude_patterns="_build classes"
	elif [ "$output_content" == "classes" ]; then
		include_patterns="classes"
		# exclude_patterns="_build about community contributing getting_started tutorials"
	elif [ "$output_content" == "about" ]; then
		include_patterns="about"
	elif [ "$output_content" == "community" ]; then
		include_patterns="community"
	elif [ "$output_content" == "contributing" ]; then
		include_patterns="contributing"
	elif [ "$output_content" == "tutorials" ]; then
		include_patterns="tutorials/3d"
	elif [ "$output_content" == "all" ]; then
		include_patterns="classes about community contributing getting_started tutorials"
	else
		exit_msg_code "Invalid output_content: $output_content" $INVALID_ARGUMENT
	fi
	
	local inc_folder
	local exc_search
	
	for inc_folder in classes about community contributing getting_started tutorials; do
		echo $include_patterns | grep -ohe "$inc_folder" || exclude_patterns="${exclude_patterns} $inc_folder"
	done
	
	echo "Include patterns: ${include_patterns}"
	echo "Exclude patterns: ${exclude_patterns}"
	
	proc_images_ext="jpg webp gif png"
	
	png_output=png
	gif_output=gif
	jpg_output=jpg
	webp_output=webp
	
	case "$output_format" in
		"epub") webp_output=jpg; gif_output=jpg; png_output=jpg; proc_images_ext="jpg webp gif png" ;;
		"pdf") webp_output=jpg; gif_output=jpg; png_output=jpg; proc_images_ext="jpg webp gif png" ;;
		"html") jpg_output=webp; gif_output=webp; png_output=webp; proc_images_ext="webp jpg gif png" ;;
	esac
	
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

# TODO: bug - webp now works fine, but png is now broken in tutorials/UI. Probably elsewhere too.

check_dependencies

shopt -s globstar
shopt -s nullglob

prepare $@
clear_source_dir
clear_build_dir
unzip_source_zip
process_all_images
build

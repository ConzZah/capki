#!/usr/bin/env sh

### /// capki.sh // ConzZah // 2026-09-25 10:47

### ConzZahs-Apk-Installer ###

## depcheck before we go any further
deps="aapt2 unzip head grep find sort uniq adb sed cut tr wc"
missing_deps=""
for dep in $deps; do
! command -v "$dep" >/dev/null && \
missing_deps="$dep $missing_deps"
done

## if $missing_deps is nonzero, tell the user which are missing & exit.
[ -n "$missing_deps" ] && printf '%s\n%s\n' "--> DEPENDENCIES MISSING:" "$missing_deps" && exit 1


check_for_device () {
adb start-server
## gets the first device it finds and obtains information about it
device="$(adb devices| sed '1d'| grep 'device'| head -n 1 |cut -f 1)"

## if there is no device present, tell the user we're waiting for one
[ -z "$device" ] && printf '\n%s\n%s\n' "--> WAITING FOR DEVICE TO CONNECT.." \
"--> MAKE SURE TO ALLOW USB DEBUGGING ON YOUR DEVICE"
adb wait-for-device && get_device_info
printf '\n%s\n\n%s\n%s\n%s\n%s\n' "--> FOUND DEVICE!" \
"NAME: $device_manufacturer $device_model" \
"ARCHITECTURE: $device_architecture" \
"SERIAL NUMBER: $device" \
"SDK VERSION: $device_sdk_version // ANDROID $device_android_version"
}


get_device_info () {
## gets information about connected device
device="$(adb devices| sed '1d'| grep -m1 'device'| cut -f 1)"
device_architecture="$(adb shell getprop ro.product.cpu.abi)" ## <-- gets devices architecture
device_sdk_version="$(adb shell getprop ro.build.version.sdk)" ## <-- gets devices sdk version
device_manufacturer="$(adb shell getprop ro.product.vendor.manufacturer)" ## <-- gets devices manufacturer
device_model="$(adb shell getprop ro.product.vendor.model)" ## <-- gets devices model
device_android_version="$(adb shell getprop ro.build.version.release)" ## <-- gets devices android version

## exclude & include other architectures dynamically
all_architectures='x86|x86_64|armeabi|armeabi-v7a|arm64-v8a'

case "$device_architecture" in
'x86_64') device_architecture='x86|x86_64';;
'arm64-v8a') device_architecture='armeabi|armeabi-v7a|arm64-v8a';;
'armeabi-v7a') device_architecture='armeabi|armeabi-v7a';;
*) ;;
esac
excluded_architectures="$(printf '%s\n' "$all_architectures" | \
sed -e "s#$device_architecture##g" -e 's#^|##g' -e 's#|$##g' -e 's#||#|#g')"
}


process_input () {
apkpaths=""

## check if any input was provided via arguments
[ -n "$args" ] && { apkpaths="$args" ;}

## if no arguments were passed, ask the user for the path to one or multiple apks
[ -z "$args" ] && {
printf '\n%s\n\n' "--> ENTER PATH(S) TO APK(S) & PRESS ENTER TWICE"

## read input with sed and stop reading on the first empty line
apkpaths="$(sed '/^$/q')"
}

## get rid of any empty lines
apkpaths="$(printf '%s\n' "$apkpaths"| sed '/^$/d')"

## if $apkpaths is still empty, tell the user to provide some input and exit
[ -z "$apkpaths" ] && printf '%s\n\n' "--> NO INPUT PROVIDED, NOTHING TO INSTALL." && exit 1

## format $apkpaths to an actual list
apkpaths="$(printf '%s\n' "$apkpaths"| sed "s#' '#'\n'#g"| tr -s "'"| cut -d "'" -f 2)"

## remove duplicates
apkpaths="$(printf '%s\n' "$apkpaths"| sort| uniq)"

## write $apkpaths to tmpfile
printf '%s\n' "$apkpaths" > "/tmp/apkpaths"

## check if the entered path(s) exist and are files or directories
apks=""
while read -r apkpath; do

## if $apkpath is a file, check if it is actually a .apk and add it to $apks
[ -f "$apkpath" ] && printf '%s\n' "$apkpath"| grep -qE '.*xapk$|.*apkm$|.*apk$' && \
apks="$(printf '%s\n%s\n' "$apkpath" "$apks"| sed '/^$/d')" && continue

## if $apkpath is a directory, check it for .apk files and add them to $apks
[ -d "$apkpath" ] && \
apks="$(printf '%s\n%s\n' "$(find "$apkpath" -type f 2>/dev/null| grep -E '.*xapk$|.*apkm$|.*apk$')" "$apks"| sed '/^$/d')" && continue

done < "/tmp/apkpaths"

## if $apks is empty, we have nothing to install
[ -z "$apks" ] && printf '\n%s\n\n' "--> NO APK(S) PROVIDED, NOTHING TO INSTALL." && exit 1

## check if the user has provided any Android/obb OR Android/data directories, and build a list of them.
## THE FOLDER STRUCTURE !!NEEDS!! TO BE: 'Android/obb/packagename', OR Android/data/packagename,
## (else, they will be ignored!)
while read -r apkpath; do

## get obb and data dirs respectively
data_dirs="$(printf '%s\n%s\n' "$(find "$apkpath/Android/data" -type d 2>/dev/null| grep -v '.*Android/data$'| head -n1)" "$data_dirs"| sed '/^$/d')"
obb_dirs="$(printf '%s\n%s\n' "$(find "$apkpath/Android/obb" -type d 2>/dev/null| grep -v '.*Android/obb$'| head -n1)" "$obb_dirs"| sed '/^$/d')"

done < "/tmp/apkpaths"
}


get_apk_package_name () {
apk_package_name=""
## get package name of the apk via aapt2
## (multi)
[ "$install" = "install-multiple" ] && {

for a in $apk; do
apk_package_name="$(aapt2 dump packagename "$a")"
[ -n "$apk_package_name" ] && break && return 0
done
}

## (single)
[ "$install" = "install" ] && {
apk_package_name="$(aapt2 dump packagename "$apk")"
}

## if $apk_package_name is still empty, return 1
[ -z "$apk_package_name" ] && return 1
}


get_apk_architecture () {
apk_architecture=""
## (try to) get $apk_architecture via aapt2
## if the $apk_architecture matches the $device_architecture(s), return 0, else return 1
## (multi)
[ "$install" = "install-multiple" ] && {

for a in $apk; do
apk_architecture="$(aapt2 dump badging "$a" | grep -oE "$device_architecture")"
[ -n "$apk_architecture" ] && break && return 0
done
}

## (single)
[ "$install" = "install" ] && {
apk_architecture="$(aapt2 dump badging "$apk" | grep -oE "$device_architecture")"
[ -n "$apk_architecture" ] && return 0
}
}


get_apk_sdk_version () {
apk_sdk_version=""
## get required sdk version via aapt2 and check if we can actually install the given .apk
## (multi)
[ "$install" = "install-multiple" ] && {

for a in $apk; do
apk_sdk_version="$(aapt2 dump badging "$a"| grep -m1 "sdkVersion"| cut -d "'" -f 2)"
[ -n "$apk_sdk_version" ] && break
done
}

## (single)
[ "$install" = "install" ] && {
apk_sdk_version="$(aapt2 dump badging "$apk"| grep -m1 "sdkVersion"| cut -d "'" -f 2)"
}

## if $apk_sdk_version is higher than $device_sdk_version, return 1
[ -n "$apk_sdk_version" ] && [ "$apk_sdk_version" -gt "$device_sdk_version" ] && return 1
return 0
}


push_obb_and_data () {
test=""
## check for Android dir within /tmp/xmapk,
## and push data & obb dirs to the device, should they exist.)
## (multi)
[ "$install" = "install-multiple" ] && {
test="$(find "/tmp/xmapk/Android")"

## if $test is nonzero, push the Android folder to /sdcard
[ -n "$test" ] && printf '\n%s\n\n' "--> PUSHING OBB/DATA DIR FOR: $apk_package_name" && \
adb push "/tmp/xmapk/Android" "/sdcard"
}

## check for Android dir based on $apk_package_name, 
## and push them, should a match be found.
## (single)
[ "$install" = "install" ] && {
obb=""
data=""

## test if we have a obb dir associated with $apk_package_name
obb="$(printf '%s\n' "$obb_dirs"| grep "$apk_package_name")"

## if $obb is nonzero, push to device
[ -n "$obb" ] && printf '\n%s\n\n' "--> PUSHING OBB DIR FOR: $apk_package_name" && \
adb push "$obb" "/sdcard/Android/obb"

## test if we have a data dir associated with $apk_package_name
data="$(printf '%s\n' "$data"| grep "$apk_package_name")"

## if $data is nonzero, push to device
[ -n "$data" ] && printf '\n%s\n\n' "--> PUSHING DATA DIR FOR: $apk_package_name" && \
adb push "$data" "/sdcard/Android/data"
}
}


install_apks () {
count="1"
total="$(printf '%s\n' "$apks"| wc -l)"
## installs given apk files on the connected device
printf '%s\n' "$apks"| while read -r apk; do
install="install"

## TEST FOR .XAPK AND .APKM
printf '%s\n' "$apk"| grep -qE '.*xapk$|.*apkm$' && {
## if we have a .xapk or .apkm file, 
## we need to extract it and set $install to install-multiple
install="install-multiple"
[ -d "/tmp/xmapk" ] && rm -rf "/tmp/xmapk"
mkdir -p "/tmp/xmapk"
unzip -d "/tmp/xmapk" "$apk"

## write all the .apk files (splits & base) to $apk,
## and exclude the $excluded_architectures
apk="$(find "/tmp/xmapk/" -type f| grep 'apk$'| grep -vE "$excluded_architectures")"

## back up $apk while it's still a newline-delimited list
apk_list="$apk"

## turn $apk from a newline delimited list into a string
apk="$(printf '%s\n' "$apk"| tr '\n' ' ')"
}

## get the package name of the apk
get_apk_package_name

## get the architecture of the apk before trying to install anything.
## if the $device_architecture does not match the $apk_architecture, print a warning.
get_apk_architecture
[ -z "$apk_architecture" ] && printf '\n%s\n%s\n' "--> WARNING: COULD NOT GET ARCHITECTURE OF: '${apk_package_name}'" "--> TRYING TO INSTALL REGARDLESS.." 

## get the $apk_sdk_version and skip the apk if it's higher than our $device_sdk_version.
! get_apk_sdk_version && printf '\n%s\n' "--> ERROR: '$apk_package_name' IS INCOMPATIBLE BECAUSE REQUIRED SDK VERSION IS HIGHER THAN WHAT THE DEVICE CAN HANDLE. SKIPPING." && \
count="$((count + 1))" && continue

## if the $apk_sdk_version could not be found, it doesn't automatically mean that the apk is incompatible, print a warning.
[ -z "$apk_sdk_version" ] && printf '\n%s\n%s\n' "--> WARNING: COULDN'T GET SDK VERSION OF APK" "TRYING TO INSTALL REGARDLESS.."

## fix quoting
## (multi)
[ "$install" = "install-multiple" ] && \
apk="$(printf '%s\n' "$apk_list"| sed -e "s#\$#'#g" -e "s#^#'#g"| tr '\n' ' ')"

## (single)
[ "$install" = "install" ] && \
apk="$(printf '%s\n' "$apk"| sed -e "s#\$#'#g" -e "s#^#'#g")"

## if we have a $device_sdk_version of 34 (A14) or higher, add --bypass-low-target-sdk-block to $install,
## so we can (try to) install legacy apks on devices with Android 14 or higher.
## this may not always work and will probably lead to compatibility issues.
## we also only add it on a case-by-case basis because A13 and below don't support this option.
[ "$device_sdk_version" -ge "34" ] && install="$install --bypass-low-target-sdk-block"

## install the apk(s) on the device.
## if the installation was successful,
## detect if we have Android/obb or Android/data directories associated with $apk_package name
## if true, they are pushed to the device.
printf '\n%s\n\n' "--> [[ ${count}/${total} ]] INSTALLING: $apk_package_name"
eval "adb $install -r $apk" && {
## reset $install to its former value
install="$(printf '%s\n' "$install"| sed 's# --bypass-low-target-sdk-block##')"
## push iiiiit
push_obb_and_data
}

[ "$count" -ge "$total" ] && exit 0
count="$((count + 1))"
done
}

# shellcheck disable=SC2016
## REASON: logo

## logo
## font: Big Money-ne
## generated with: https://patorjk.com/software/taag/ <3
printf '%s\n\n' '
                               /$$       /$$
                              | $$      |__/
  /$$$$$$$  /$$$$$$   /$$$$$$ | $$   /$$ /$$
 /$$_____/ |____  $$ /$$__  $$| $$  /$$/| $$
| $$        /$$$$$$$| $$  \ $$| $$$$$$/ | $$
| $$       /$$__  $$| $$  | $$| $$_  $$ | $$
|  $$$$$$$|  $$$$$$$| $$$$$$$/| $$ \  $$| $$
 \_______/ \_______/| $$____/ |__/  \__/|__/
                    | $$
                    | $$
                    |__/

         == ConzZahs-Apk-Installer =='


_help () {
printf '%s\n\n' "
USAGE:  sh capki.sh [/path/to/some.apk]

SUPPORTED FORMATS: .apk, .xapk .apkm

FEATURES:

capki is able to handle multiple apks,
and will install them sequentially.

it's also able to handle obb files.

EXAMPLES:

you can do something like this:

sh capki.sh '/path/to/1st.apk' 'path/to/2nd.apk'

it can also search directories for apks:

sh capki.sh '/path/to/my-apk-directory'


NOTES:

QUOTING IS IMPORTANT!!
Thankfully, most shells do that automagically, 
when you drag & drop files into the terminal.


CAVEATS:

FILENAMES CAN'T CONTAIN SINGLE QUOTES. --> ' <--

=============================================
 AUTHOR: ConzZah // (c) 2026 // LICENSE: MIT
=============================================
          MADE WITH <3 IN GERMANY."
}


#### CHECK FOR ARGS ####
args=""

## check if any input was provided via arguments
[ -n "$1" ] && {
while [ "$#" -gt "0" ]; do

## check if the user asked for help
case "$1" in
'h'|'-h'|'help'|'--help') _help; exit ;;
*) ;;
esac

## otherwise, put the args in a newline-delimited list.
args="$(printf '%s\n%s\n' "$1" "$args")"
shift
done
}

#### LAUNCH ####
main () {
check_for_device
process_input "$args"
install_apks
}

main

#!/bin/bash
#
#     This script is for mounting large number of ISOs and bind directories
#     Bob Brandt <projects@brandt.ie>
#

_version=1.1
_brandt_utils=/opt/brandt/common/brandt.sh
_this_conf=/etc/brandt/mountISOs.conf
_this_list=/etc/brandt/mountISOs.list
_this_script=/opt/brandt/proxy/mountISOs.sh
_this_rc=/usr/local/bin/mountISOs
_this_init=/etc/init/mountISOs.conf

[ ! -r "$_brandt_utils" ] && echo "Unable to find required file: $_brandt_utils" 1>&2 && exit 6
if [ ! -r "$_this_conf" ]; then
	( echo -e "#     Configuration file for mountISOs script"
	  echo -e "#     Bob Brandt <projects@brandt.ie>\n#"
	  echo -e "_repoBase='/repository'"
	  echo -e "_optionsISO='auto,ro,user,loop,uid=www-data,gid=www-data'"
          echo -e "_optionsBIND='bind,ro'"
	  echo -e '_optionsArchive="readonly,auto_unmount,allow_other,uid=$( id -u tftp ),gid=$( id -g tftp )"' ) > "$_this_conf"
	echo "Unable to find required file: $_this_conf" 1>&2
fi

. "$_brandt_utils"
. "$_this_conf"

function createLoops() {
	local -i _neededLoops=${1:-8}
	local -i _availableLoops=$( ls -l /dev/loop* | sed -n "s|^b.*/dev/loop[0-9]*$|&|p" | wc -l )

	test $_neededLoops -gt 256 && echo "Unable to create $_neededLoops loopback devices, 256 is the hard-coded limit!" 1>&2 && exit 6

	echo "Detected $_availableLoops loopback devices on this system."
	if [ $_neededLoops -gt $_availableLoops ]; then
		echo "System needs $_neededLoops loopback devices."
		for _node in $(seq $_availableLoops $(( $_neededLoops - 1 )) ); do
			if [ ! -b "/dev/loop${_node}" ] && [ "$_test" == "0" ]; then
				echo "Creating loopback device /dev/loop${_node}" 2>&1
				mknod -m 660 "/dev/loop${_node}" b 7 ${_node} && chown root:disk "/dev/loop${_node}"
			fi
		done
		if [ "$_test" == "0" ]; then
			echo "Reloading the loopback module so the kernel sees the additional loopback devices!" 2>&1
			echo "options loop max_loop=$_neededLoops" > /etc/modprobe.d/loop
			modprobe loop
			if [ -f "/etc/default/grub" ] && [ -x "/usr/sbin/update-grub2" ]; then
				GRUB_CMDLINE_LINUX_DEFAULT=$( trim $( sed -n 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"|\1|p' /etc/default/grub ) )
				GRUB_CMDLINE_LINUX_DEFAULT=$( trim $( echo $GRUB_CMDLINE_LINUX_DEFAULT | tr " " "\n" | grep -v "^max_loop=" | tr "\n" " " ) )
				GRUB_CMDLINE_LINUX_DEFAULT=$( trim "$GRUB_CMDLINE_LINUX_DEFAULT max_loop=$_neededLoops" )
				sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE_LINUX_DEFAULT\"|" /etc/default/grub
				/usr/sbin/update-grub2
			fi
		fi
	fi
}

function mountISO9660() {
	local _file="$1"
	local _location="$2"

	if [ -f "$_file" ]; then
		echo "Mounting $_file at $_location"
		test "$_test" == "0" && mount -t udf,iso9660 -o "$_optionsISO" "$_file" "$_location"
	else
		echo "The ISO file $_file is not present!" 1>&2
	fi
	return $?
}

function mountNone() {
        local _file="$1"
        local _location="$2"

        if [ -f "$_file" ]; then
                echo "Mounting $_file at $_location"
                test "$_test" == "0" && mount -t none -o "$_optionsBIND" "$_file" "$_location"
        else
                echo "The Bind directory $_file is not present!" 1>&2
        fi
        return $?
}

function mountArchive() {
        local _file="$1"
        local _location="$2"

        if [ -f "$_file" ]; then
                echo "Mounting $_file at $_location"
                test "$_test" == "0" && archivemount -o "$_optionsArchive" "$_file" "$_location"
        else
                echo "The Archive $_file is not present!" 1>&2
        fi
        return $?
}

function setup() {
	local _status=0
	ln -sf "$_this_script" "$_this_rc" > /dev/null 2>&1
	_status=$?
	( echo -e "# mountISOs - Mount  ISO and Bind filesystems"
	  echo -e "#"
	  echo -e "# Send mountall the USR1 signal to inform it to try ISO and Bind filesystems"
	  echo -e "# again."
	  echo -e '\ndescription	"Mount ISO and Bind filesystems"'
	  echo -e "\nstart on remote-filesystems"
	  echo -e "\ntask"
	  echo -e "\nscript"
	  echo -e "    /usr/local/bin/mountISOs"
	  echo -e "end script" ) > "$_this_init"
	exit $(( $_status | $? ))
}

function usage() {
	local _exitcode=${1-0}
	local _output=2
	[ "$_exitcode" == "0" ] && _output=1
	[ "$2" == "" ] || echo -e "$2"
	( echo -e "Usage: $0 [options]"
	  echo -e "Options:"
	  echo -e " -s, --setup    setup script"
	  echo -e " -t, --test     don't actually do anything"	  
	  echo -e " -h, --help     display this help and exit"
	  echo -e " -v, --version  output version information and exit" ) >&$_output
	exit $_exitcode
}

# Execute getopt
if ! _args=$( getopt -o stvh -l "setup,test,help,version" -n "$0" -- "$@" 2>/dev/null ); then
	_err=$( getopt -o stvh -l "setup,test,help,version" -n "$0" -- "$@" 2>&1 >/dev/null )
	usage 1 "${BOLD_RED}$_err${NORMAL}"
fi

#Bad arguments
#[ $? -ne 0 ] && usage 1 "$0: No arguments supplied!\n"

eval set -- "$_args";
_test=0
while /bin/true ; do
    case "$1" in
        "-t" | "--test" )      _test=1 ;;
        "-s" | "--setup" )     setup ;;
        "-h" | "--help" )      usage 0 ;;
        "-v" | "--version" )   brandt_version $_version ;;
        "--" )               shift ; break ;;
        * )                usage 1 "${BOLD_RED}$0: Invalid argument!${NORMAL}" ;;
    esac
    shift
done
_command=$( lower "$1" )
shift 1

# Check to see if user is root, if not re-run script as root.
brandt_amiroot || { echo "${BOLD_RED}This program must be run as root!${NORMAL}" >&2 ; sudo "$0" $_args ; exit $?; }

if [ ! -r "$_this_list" ]; then
	( echo -e "# Configuration file for mountISOs.sh"
	  echo -e "#"
	  echo -e "# Type\tFile Name (Relative path)\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tMount Location"
	  echo -e "#-------------------------------------------------------------------------------------------------------------------------------------\n" ) > "$_this_list"
	echo "Unable to find required file: $_this_list" 1>&2 && exit 6
fi

count=$( grep -v '^[# ]' "$_this_list" | sed '/^$/d' | wc -l )
echo "Mounting $count ISOs/Binds."
createLoops $count

_IFSOLD="$IFS"
IFS=$'\n'
for _line in $( grep -v '^[# ]' "$_this_list" | sed '/^$/d' ); do
        _type=$( trim $( echo "$_line" | sed -n 's|\s\+.*||p' ) )
	_file=$( trim $( echo "$_line" | sed -n -e 's|\S\+\s\+||' -e 's|\s\+.*||p' ) )

	_extension=$( echo "$_file" | sed -n 's|.*\.||p' )
        _extension=$( trim $( lower "$_extension" ) )

	_location=$( trim $( echo "$_line" | sed -n -e 's|\S\+\s\+||' -e 's|\S\+\s\+||p' ) )

	echo "$_type,$_file ($_extension),$_location"


	if [ ! -d "$_location" ]; then
		echo "Location $_location does not exist, creating it!" 2>&1
		test "$_test" == "0" && mkdir -p "$_location"
	fi

	if mount | sed -e "s|.* on ||" -e "s| type .*||" | grep "^${_location}$" > /dev/null 2>&1
	then
		echo "The location ($_location) is already mounted!"
		mount 2>/dev/null | grep " on ${_location} type " | sed "s|^|\t|"
	else
		if [ ! "$( ls -A $_location 2>&1 )" == "" ]; then
			echo "The directory $_location is not empty!" 1>&2
		else
			case "$_type" in
				"iso9660" ) mountISO9660 "$_repoBase/$_file" "$_location" ;;
				"none"    ) mountNone "$_repoBase/$_file" "$_location" ;;
				"archive" ) mountArchive "$_repoBase/$_file" "$_location" ;;
			esac
		fi



#			if [ "$_type" == "iso9660" ]; then
#				if [ -f "$_repoBase/$_file" ]; then
#					echo "Mounting $_repoBase/$_file  at  $_location"
#					test "$_test" == "0" && mount -t udf,iso9660 -o "$_optionsISO" "$_repoBase/$_file" "$_location"
#				else
#					echo "The ISO file $_repoBase/$_file is not present!" 1>&2
#				fi
#			else
#				if [ -d "$_repoBase/$_file" ]; then
#					echo "Mounting $_repoBase/$_file  at  $_location"
#					test "$_test" == "0" && mount -t none -o "$_optionsBIND" "$_repoBase/$_file" "$_location"
#				else
#					echo "The Bind directory $_repoBase/$_file is not present!" 1>&2
#				fi
#			fi
	fi
done
IFS="$_IFSOLD"

exit $?


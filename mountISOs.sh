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

[ ! -r "$_brandt_utils" ] && echo "Unable to find required file: $_brandt_utils" 1>&2 && exit 6
if [ ! -r "$_this_conf" ]; then
	( echo -e "#     Configuration file for DHCP wrapper startup script"
	  echo -e "#     Bob Brandt <projects@brandt.ie>\n#"
   	  echo -e "_dhcpd_sysconfig=/etc/sysconfig/dhcpd" ) > "$_this_conf"
	echo "Unable to find required file: $_this_conf" 1>&2
fi

. "$_brandt_utils"
. "$_this_conf"

function createLoops() {
	local -i _neededLoops=${1:-8}
	local -i _availableLoops=$( ls -l /dev/loop* | sed -n "s|^b.*/dev/loop[0-9]*$|&|p" | wc -l )

	echo $_test
	echo "Detected $_availableLoops loopback devices on this system."
	if [ $_availableLoops -le $_neededLoops ]; then
		echo "System needs $_neededLoops loopback devices."
		for _node in $(seq $_availableLoops $_neededLoops ); do 
			if ! test -b /dev/loop${_node}; then
				test "$_test" -eq "0" && echo mknod -m 660 /dev/loop${_node} b 7 ${_node}
			fi
		done
		if [ "$_test" -eq "0" ]; then
			echo chown root:disk /dev/loop*
			echo "options loop max_loop=$_neededLoops" > /etc/modprobe.d/loop
			echo modprobe loop
		fi
	fi
}









function setup() {
	local _status=0	
	ln -sf "$_this_script" "$_this_rc" > /dev/null 2>&1
	_status=$?	
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

[ ! -r "$_this_list" ] && echo "Unable to find required file: $_this_list" 1>&2 && exit 6

count=$( grep -v '^[# ]' "$_this_list" | sed '/^$/d' | wc -l )

echo "Mounting $count ISOs/Binds."

createLoops $count
_IFSOLD="$IFS"
IFS=$'\n'
for _line in $( grep -v '^[# ]' "$_this_list" | sed '/^$/d' ); do
	_file=$( echo "$_line" | sed -n 's|\s\+.*||p' )
	_location=$( echo "$_line" | sed -n 's|\S*\s\+||p' )

	_extension=$( lower "${_file:(-4)}" )

	if [ ! -d "$_location" ]; then
		echo mkdir -p "$_location"
	fi

	if [ "$( ls -A $_location 2>&1 )" == "" ]; then
		if [ "$_extension" == ".iso" ]; then
			if [ -f "$_repoBase/$_file" ]; then
				echo mount -t udf,iso9660 -o "$_optionsISO" "$_repoBase/$_file" "$_location"
			else
				echo "The ISO file $_repoBase/$_file is not present!" 1>&2				
			fi
		else
			if [ -d "$_repoBase/$_file" ]; then
				echo mount -t none -o "$_optionsBIND" "$_repoBase/$_file" "$_location"
			else
				echo "The Bind directory $_repoBase/$_file is not present!" 1>&2				
			fi
		fi
	else
		echo "The directory $_location is not empty!" 1>&2
	fi
done
IFS="$_IFSOLD"

exit $?

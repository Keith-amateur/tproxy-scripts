#! /bin/bash


if [[ $(id -u) -ne 0 ]]; then
	echo "Please run it as root or use sudo"
	exit 1
fi

sslocal_path=$(which sslocal)
xray_path=$(which xray)


set_cap() {
	setcap cap_net_admin,cap_net_bind_service+ep "$sslocal_path"
	setcap cap_net_admin,cap_net_bind_service+ep "$xray_path"
}

get_cap() {
	getcap "$sslocal_path"
	getcap "$xray_path"
}

show_help() {
	echo -e "Usage: \n\t $0 set|get|help"
}

main() {
	if [[ $# -ne 1 ]]; then
		show_help
		return 1
	fi
	
	case "$@" in 
		set) set_cap ;;
		get) get_cap ;;
		help) show_help ;;
		*) echo "Unknown option: $@"; show_help; exit 1;;
	esac
}

main "$@"



#! /bin/bash
if [[ $(id -u) -ne 0 ]]; then
	echo "Please run it as root or use sudo"
	exit 1
fi

if ! [[ -f semi-privileged-bash.c ]]; then
	echo "semi-privileged-bash.c not found"
	exit 1
fi

is_existed() {
	if id -u proxy >/dev/null 2>&1; then
		echo "User proxy exists."
		return 0
	else 
		echo "User proxy does not exist."
		return 1
	fi
}

add_user(){
	is_existed && return 0
	set -xe 
	gcc ./semi-privileged-bash.c -o ./semi-privileged-bash -lcap-ng
	mv ./semi-privileged-bash /usr/local/bin/
	setcap cap_net_bind_service,cap_net_admin+ep /usr/local/bin/semi-privileged-bash
	sed -i '$a \/usr/local/bin/semi-privileged-bash' /etc/shells
	useradd -Mr -d/tmp -s/usr/local/bin/semi-privileged-bash proxy
}

del_user() {
	! is_existed && reutrn 0
	set -xe
	rm -f /usr/local/bin/semi-privileged-bash
	sed -i '/semi-privileged-bash/d' /etc/shells
	userdel proxy
}

show_info() {
	! is_existed && return 1
	local uid=$(id -u proxy)
	local gid=$(id -g proxy)
	echo "----------------------------------------------"
	echo "User: proxy"
	echo -e "uid: $uid\tgid: $gid"
	echo "shell: $(awk -F: '/proxy/{print $NF}' /etc/passwd)"
	echo "----------------------------------------------"
}

show_help() {
	echo -e "Usage: \n\t $0 add|del|info|help"
}

main() {
	if [[ $# -ne 1 ]]; then
		show_help
		exit 1
	fi


	case "$@" in
		add) add_user ;;
		del) del_user ;;
		info) show_info ;;
		help) show_help ;;
		*) echo "Unknown option: $@"; show_help; exit 1;;
	esac
}

main "$@"

#! /bin/bash

if [[ $(id -u) -ne 0 ]]; then
	echo "Please run as root or use sudo"
	exit 1
fi 

if ! id -u proxy >/dev/null 2>&1; then
	echo "user proxy who runs the xray does not exist"
	exit 1
fi


proxy_uid=$(id -u proxy)
proxy_gid=$(id -g proxy)
proxy_port=10080

readonly IPV4_PRIVATE_ADDR=(
	0.0.0.0/8
	10.0.0.0/8
	100.64.0.0/10
	127.0.0.0/8
	169.254.0.0/16
	172.16.0.0/12
	192.0.0.0/24
	192.0.2.0/24
	192.88.99.0/24
	192.168.0.0/16
	192.18.0.0/15
	192.51.100.0/24
	203.0.113.0/24
	224.0.0.0/4
	240.0.0.0/4
	255.255.255.255/32
)
# no use of it right now
readonly IPV6_RESERVED_IPADDRS=(
    ::/128
    ::1/128
    ::ffff:0:0/96
    ::ffff:0:0:0/96
    64:ff9b::/96
    100::/64
    2001::/32
    2001:20::/28
    2001:db8::/32
    2002::/16
    fc00::/7
    fe80::/10
    ff00::/8
)

create_ipset() {
	ipset -N privaddrV4 hash:net
	for net in "${IPV4_PRIVATE_ADDR[@]}"; do
		ipset -A -exist privaddrV4 "$net"
	done
}

del_ipset() {
	ipset -F privaddrV4
	ipset destroy privaddrV4
}

add_iproute() {
	ip route add local default dev lo table 233
	ip rule add fwmark 0x233 table 233
}

del_iproute() {
	ip route flush table 233
	ip rule del fwmark 0x233 table 233
}

add_ss_rule() {
	iptables -t mangle -N SS_RULE
	iptables -t mangle -A SS_RULE -j CONNMARK --restore-mark
	iptables -t mangle -A SS_RULE -m mark --mark 0x233 -j RETURN
	iptables -t mangle -A SS_RULE -m set --match-set privaddrV4 dst -j RETURN
	# mark the first packet of the connection
	iptables -t mangle -A SS_RULE -p tcp --syn -j MARK --set-mark 0x233
	iptables -t mangle -A SS_RULE -p udp -m conntrack --ctstate NEW -j MARK --set-mark 0x233
	iptables -t mangle -A SS_RULE -j CONNMARK --save-mark
}

del_ss_rule() {
	iptables -t mangle -F SS_RULE
	iptables -t mangle -X SS_RULE
}

add_ss_prerouting() {
	iptables -t mangle -N SS_PREROUTING
	# handle packets with mark from OUTPUT 
	iptables -t mangle -A SS_PREROUTING -i lo -m mark ! --mark 0x233 -j RETURN
	iptables -t mangle -A SS_PREROUTING -p tcp -m addrtype ! --src-type LOCAL ! --dst-type LOCAL -j SS_RULE
	iptables -t mangle -A SS_PREROUTING -p udp -m addrtype ! --src-type LOCAL ! --dst-type LOCAL -j SS_RULE
	iptables -t mangle -A SS_PREROUTING -p tcp -m mark --mark 0x233 -j TPROXY --on-port "$proxy_port" --on-ip 127.0.0.1
	iptables -t mangle -A SS_PREROUTING -p udp -m mark --mark 0x233 -j TPROXY --on-port "$proxy_port" --on-ip 127.0.0.1
	iptables -t mangle -A PREROUTING -j SS_PREROUTING
}

del_ss_prerouting() {
	iptables -t mangle -D PREROUTING -j SS_PREROUTING
	iptables -t mangle -F SS_PREROUTING
	iptables -t mangle -X SS_PREROUTING
}

add_ss_output() {
	iptables -t mangle -N SS_OUTPUT
	iptables -t mangle -A SS_OUTPUT -m owner --uid-owner $proxy_uid --gid-owner $proxy_gid -j RETURN
	iptables -t mangle -A SS_OUTPUT -p tcp -m addrtype --src-type LOCAL ! --dst-type LOCAL -j SS_RULE
	iptables -t mangle -A SS_OUTPUT -p udp -m addrtype --src-type LOCAL ! --dst-type LOCAL -j SS_RULE
	iptables -t mangle -A OUTPUT -j SS_OUTPUT
}

del_ss_output() {
	iptables -t mangle -D OUTPUT -j SS_OUTPUT
	iptables -t mangle -F SS_OUTPUT
	iptables -t mangle -X SS_OUTPUT
}


start() {
	create_ipset
	add_iproute
	add_ss_rule
	add_ss_prerouting
}

stop() {
	del_ss_prerouting
	del_ss_rule
	del_iproute
	del_ipset
}

status() {
	local status_code
	if nc -zv 127.0.0.1 "$proxy_port" &>/dev/null; then
		echo -e "tproxy tcp: \e[36m127.0.0.1:"$proxy_port"\e[0m \e[32mopen\e[0m"
		status_code=0
	else
		echo -e "tproxy tcp: \e[36m127.0.0.1:"$proxy_port"\e[0m \e[31mclose\e[0m"
		status_code=1
	fi

	if nc -zuv 127.0.0.1 "$proxy_port" &>/dev/null; then
		echo -e "tproxy udp: \e[36m127.0.0.1:"$proxy_port"\e[0m \e[32mopen\e[0m"
		status_code=$(( $status_code | 0 ))
	else
		echo -e "tproxy udp: \e[36m127.0.0.1:"$proxy_port"\e[0m \e[31mclose\e[0m"
		status_code=$(( $status_code | 1 ))
	fi

	return $status_code
}

start_self() {
	start
	add_ss_output
}

stop_self() {
	del_ss_output
	stop
}

show_help() {
	echo -e "Usage: \n\t $0 \n\t\t -p <PORT> \n\t\t -o <start|stop|status|start_self|stop_self> \n\t\t -h show help"
}

main() {
	if [[ $# -eq 0 ]]; then
		show_help
		return 1
	fi
	for func in "$@"; do
		if [[ "$(type -t $func)" != "function" ]]; then
			echo "$func not a shell function"
			show_help
			return 1
		fi
	done

	for func in "$@"; do
		$func
	done
}

while getopts :p:o:h opt; do
	case "$opt" in
		p) proxy_port="$OPTARG" ;;
		o) main "$OPTARG" ;;
		h) show_help; exit 0;;
		*) echo "Unknown option: $opt"; show_help; exit 1;;
	esac
done



#! /bin/bash

if [[ $(id -u) -ne 0 ]]; then
	echo "Please run as root or use sudo"
	exit 1
fi

if ! id -u proxy >/dev/null 2>&1; then
	echo "user proxy who runs the xray does not exist"
	exit 1
fi

# useradd -Mr -d/tmp -s/bin/bash -c "To diff the regular traffic from proxy traffic"  proxy
proxy_uid=$(id -u proxy)
proxy_gid=$(id -g proxy)
proxy_port=12345

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
	ip route add local 0.0.0.0/0 dev lo table 100
	ip rule add fwmark 1 table 100
}

del_iproute() {
	ip route flush table 100
	ip rule del fwmark 1 table 100
}

add_iptables_xray() {
	# create new chain XRAY
	iptables -t mangle -N XRAY
	# ipv4 private address does not need proxy 
	iptables -t mangle -A XRAY -m set --match-set privaddrV4 dst -j RETURN
	# proxy traffic to xray
	# give the tcp and udp traffic mark 1, forward them to port "$proxy_port"(tcp/udp)
	# only the traffic with mark 1 will be accepted by xray dokodemo-door
	iptables -t mangle -A XRAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port "$proxy_port" --tproxy-mark 1
	iptables -t mangle -A XRAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port "$proxy_port" --tproxy-mark 1
	# add XRAY to PREROUTING
	iptables -t mangle -A PREROUTING -j XRAY
}

del_iptables_xray() {
	iptables -t mangle -D PREROUTING -j XRAY
	iptables -t mangle -F XRAY
	iptables -t mangle -X XRAY
}

add_iptables_xray_self() {
	iptables -t mangle -N XRAY_SELF
	iptables -t mangle -A XRAY_SELF -m set --match-set privaddrV4 dst -j RETURN
	# avoid the round loop
	iptables -t mangle -A XRAY_SELF -m owner --uid-owner "$proxy_uid" --gid-owner "$proxy_gid" -j RETURN
	# OUTPUT --> PREROUTING
	iptables -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark 1
	iptables -t mangle -A XRAY_SELF -p udp -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -j XRAY_SELF
}

del_iptables_xray_self() {
	iptables -t mangle -D OUTPUT -j XRAY_SELF
	iptables -t mangle -F XRAY_SELF
	iptables -t mangle -X XRAY_SELF
}

add_iptables_divert() {
	iptables -t mangle -N DIVERT
	iptables -t mangle -A DIVERT -j MARK --set-mark 1
	iptables -t mangle -A DIVERT -j ACCEPT
	iptables -t mangle -I PREROUTING -p tcp -m socket -j DIVERT
}

# DIVERT rules 避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
del_iptables_divert() {
	iptables -t mangle -D PREROUTING -p tcp -m socket -j DIVERT
	iptables -t mangle -F DIVERT
	iptables -t mangle -X DIVERT
}



start() {
	create_ipset
	add_iproute
	add_iptables_xray
	add_iptables_divert
}

stop() {
	del_iproute
	del_iptables_xray
	del_iptables_divert
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
	add_iptables_xray_self
}

stop_self() {
	del_iptables_xray_self
	stop
}

show_help() {
	echo -e "Usage: \n\t $0 \n\t\t -p <PORT> \n\t\t -o <start|stop|status|start_self|stop_self> \n\t\t -h show_help"
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

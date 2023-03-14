#! /bin/bash
if [[ $(id -u) -ne 0 ]]; then
	echo "Please run as root or use sudo"
	exit 1
fi 

if ! id -u proxy &>/dev/null; then
	echo "user proxy who runs the xray does not exist"
	exit 1
fi


proxy_uid=$(id -u proxy)
proxy_gid=$(id -g proxy)
proxy_port=10080
proxy_mode=""

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

destroy_ipset() {
	ipset -F privaddrV4
	ipset destroy privaddrV4
}

exist_ipset() {
	ipset list privaddrV4 &>/dev/null
}

in_use_ipset() {
	iptables -t mangle -nL | grep privaddrV4 &>/dev/null || iptables -t nat -nL | grep privaddrV4 &>/dev/null
}

add_iproute() {
	ip route add local default dev lo table 250
	ip rule add fwmark 0xff table 250
}

del_iproute() {
	ip route flush table 250
	ip rule del fwmark 0xff table 250
}

add_mark_rule() {
	iptables -t mangle -N MARK_RULE
	iptables -t mangle -A MARK_RULE -j CONNMARK --restore-mark
	iptables -t mangle -A MARK_RULE -m mark --mark 0xff -j RETURN
	iptables -t mangle -A MARK_RULE -m set --match-set privaddrV4 dst -j RETURN
	# mark the first packet of the connection
	iptables -t mangle -A MARK_RULE -p tcp --syn -j MARK --set-mark 0xff
	iptables -t mangle -A MARK_RULE -p udp -m conntrack --ctstate NEW -j MARK --set-mark 0xff
	iptables -t mangle -A MARK_RULE -j CONNMARK --save-mark
}

del_mark_rule() {
	iptables -t mangle -F MARK_RULE
	iptables -t mangle -X MARK_RULE
}

add_tproxy_prerouting() {
	local tcp=true
	local udp=true
	local mode="$1"
	if [[ "$mode" == "tcp_only" ]]; then
		udp=false
	elif [[ "$mode" == "udp_only" ]]; then
		tcp=false
	fi
	iptables -t mangle -N TPROXY_PREROUTING
	# handle packets with mark from OUTPUT 
	iptables -t mangle -A TPROXY_PREROUTING -i lo -m mark ! --mark 0xff -j RETURN
	$tcp && iptables -t mangle -A TPROXY_PREROUTING -p tcp -m addrtype ! --src-type LOCAL ! --dst-type LOCAL -j MARK_RULE
	$udp && iptables -t mangle -A TPROXY_PREROUTING -p udp -m addrtype ! --src-type LOCAL ! --dst-type LOCAL -j MARK_RULE
	$tcp && iptables -t mangle -A TPROXY_PREROUTING -p tcp -m mark --mark 0xff -j TPROXY --on-port "$proxy_port" --on-ip 127.0.0.1
	$udp && iptables -t mangle -A TPROXY_PREROUTING -p udp -m mark --mark 0xff -j TPROXY --on-port "$proxy_port" --on-ip 127.0.0.1
	iptables -t mangle -A PREROUTING -j TPROXY_PREROUTING
}

del_tproxy_prerouting() {
	iptables -t mangle -D PREROUTING -j TPROXY_PREROUTING
	iptables -t mangle -F TPROXY_PREROUTING
	iptables -t mangle -X TPROXY_PREROUTING
}

add_tproxy_output() {
	local tcp=true
	local udp=true
	local mode="$1"
	if [[ "$mode" == "tcp_only" ]]; then
		udp=false
	elif [[ "$mode" == "udp_only" ]]; then
		tcp=false
	fi
	iptables -t mangle -N TPROXY_OUTPUT
	iptables -t mangle -A TPROXY_OUTPUT -m owner --uid-owner "$proxy_uid" --gid-owner "$proxy_gid" -j RETURN
	$tcp && iptables -t mangle -A TPROXY_OUTPUT -p tcp -m addrtype --src-type LOCAL ! --dst-type LOCAL -j MARK_RULE
	$udp && iptables -t mangle -A TPROXY_OUTPUT -p udp -m addrtype --src-type LOCAL ! --dst-type LOCAL -j MARK_RULE
	iptables -t mangle -A OUTPUT -j TPROXY_OUTPUT
}

del_tproxy_output() {
	iptables -t mangle -D OUTPUT -j TPROXY_OUTPUT
	iptables -t mangle -F TPROXY_OUTPUT
	iptables -t mangle -X TPROXY_OUTPUT
}


start_tproxy() {
	! exist_ipset && create_ipset
	add_iproute
	add_mark_rule
	add_tproxy_prerouting
}

start_tproxy_tcp() {
	! exist_ipset && create_ipset
	add_iproute
	add_mark_rule
	add_tproxy_prerouting "tcp_only"
}

start_tproxy_udp() {
	! exist_ipset && create_ipset
	add_iproute
	add_mark_rule
	add_tproxy_prerouting "udp_only"
}

stop_tproxy() {
	del_tproxy_prerouting
	del_mark_rule
	del_iproute
	exist_ipset && ! in_use_ipset && destroy_ipset
}

start_tproxy_self() {
	tproxy_op="$1"
	$tproxy_op
	add_tproxy_output "${tproxy_op##*_}_only"
}

stop_tproxy_self() {
	del_tproxy_output
	stop_tproxy
}

add_redirect_rule() {
	iptables -t nat -N REDIRECT_RULE
	iptables -t nat -A REDIRECT_RULE -m set --match-set privaddrV4 dst -j RETURN
	# sysctl -w net.ipv4.conf.eth0.route_localnet=1
	iptables -t nat -A REDIRECT_RULE -p tcp -j DNAT --to 127.0.0.1:"$proxy_port"
}

del_redirect_rule() {
	iptables -t nat -F REDIRECT_RULE
	iptables -t nat -X REDIRECT_RULE
}

add_redirect_prerouting() {
	iptables -t nat -N REDIRECT_PREROUTING
	iptables -t nat -A REDIRECT_PREROUTING -p tcp -m addrtype ! --src-type LOCAL ! --dst-type LOCAL -j REDIRECT_RULE

	iptables -t nat -A PREROUTING -j REDIRECT_PREROUTING
}

del_redirect_prerouting() {
	iptables -t nat -D PREROUTING -j REDIRECT_PREROUTING
	iptables -t nat -F REDIRECT_PREROUTING
	iptables -t nat -X REDIRECT_PREROUTING
}

add_redirect_output() {
	iptables -t nat -N REDIRECT_OUTPUT
	iptables -t nat -A REDIRECT_OUTPUT -m owner --uid-owner "$proxy_uid" --gid-owner "$proxy_gid" -j RETURN
	iptables -t nat -A REDIRECT_OUTPUT -p tcp -m addrtype --src-type LOCAL ! --dst-type LOCAL -j REDIRECT_RULE

	iptables -t nat -A OUTPUT -j REDIRECT_OUTPUT
}

del_redirect_output() {
	iptables -t nat -D OUTPUT -j REDIRECT_OUTPUT
	iptables -t nat -F REDIRECT_OUTPUT
	iptables -t nat -X REDIRECT_OUTPUT
}

start_redirect_others() {
	! exist_ipset && create_ipset
	add_redirect_rule
	add_redirect_prerouting
}

stop_redirect_others() {
	del_redirect_prerouting
	del_redirect_rule
	exist_ipset && ! in_use_ipset && destroy_ipset
}

start_redirect_self() {
	! exist_ipset && create_ipset
	add_redirect_rule
	add_redirect_output
}

stop_redirect_self() {
	del_redirect_output
	del_redirect_rule
	exist_ipset && ! in_use_ipset && destroy_ipset
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


show_help() {
	echo -e "Usage: \n $0 \n\t -p <PROXY_PORT> \n\t -m 1,2,3,4 \n\t -o <start|stop> \n\t -h show this help"
}

main() {
	if [[ $# -ne 2 ]]; then
		show_help
		return 1
	fi

	if [[ -z $proxy_port ]]; then
		echo "The Listen Port hasn't been assigned"
		show_help
		return 1
	fi
	local op="$1"
	local mode="$2"
	## proxy taffic from others
	# mode 1: tcp-tproxy(chain PREROUTING table mangle) udp-tproxy(chain PREROUTING table mangle)
	# mode 2: tcp-redir(chain PREROUTING table nat)  udp-tproxy(chain PREROUTING table mangle) 
	## proxy traffic from host(self)
	# mode 3: tcp-tproxy(chain PREROUTING,OUTPUT table mangle) udp-tproxy(chain PREROUTING,OUTPUT table mangle)
	# mode 4: tcp-redir(chain OUTPUT table nat) udp-tproxy(chain PREROUTING,OUTPUT table mangle)
	if [[ "$op" == "start" ]]; then
		case "$mode" in
			1) start_tproxy ;;
			2) start_redirect_others; start_tproxy_udp ;;
			3) start_tproxy_self "start_tproxy" ;;
			4) start_redirect_self; start_tproxy_self "start_tproxy_udp" ;;
			*) echo "Unknown Proxy Mode"; show_help; return 1 ;;
		esac
	elif [[ "$op" == "stop" ]]; then
		case "$mode" in
			1) stop_tproxy ;;
			2) stop_redirect_others; stop_tproxy ;;
			3) stop_tproxy_self ;;
			4) stop_redirect_self; stop_tproxy_self ;;
			*) echo "Unknown Proxy Mode"; show_help; return 1 ;;
		esac
	elif [[ "$op" == "status" ]]; then
		status
	fi
}

arg_check_number='^[0-9]+$'
arg_check_op='^(start|stop|status)$' 
while getopts :p:m:o:h opt; do
	case "$opt" in
		p) [[ "$OPTARG" =~ $arg_check_number ]] && [[ "$OPTARG" -le 65535 ]] && proxy_port="$OPTARG" ;;
		m) [[ "$OPTARG" =~ $arg_check_number ]] && proxy_mode="$OPTARG" ;;
		o) [[ "$OPTARG" =~ $arg_check_op ]] && main "$OPTARG" "$proxy_mode";;
		h) show_help; exit 0 ;;
		*) echo "Unknown option: $opt"; show_help; exit 1;;
	esac
done

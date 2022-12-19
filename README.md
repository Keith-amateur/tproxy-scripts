# tproxy-scripts
## Executable
- /usr/local/bin/xray
- /usr/local/bin/sslocal(from [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)) or ss-local(from [shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev))

## Preparation
- create the user 'proxy' to run xray and sslocal. (to identify the traffic by uid and gid)
- make sure the executable files have enough capabilities. (to let the non-privileged user 'proxy' be capable of running xray and sslocal)
- make sure the configuration files of xray and sslocal are correct.

---

## Operations
1. add user
```bash
# user 'proxy' will have a semi-privileged bash
./user-tproxy.sh add
# check the brief information about the user proxy
./user-tproxy.sh info
```
2. set capabilities
```bash
# set cap_net_admin,cap_net_bind_service on executable files
./capabilities.sh set
# show the current capabilities of executables files
./capabilities.sh get
```
Operation 1 and 2 only need to be run once.
Only if the executable files changes, operation 2 will have to be run again.

---
3. add iptables rules and set policy routing
```bash
# 'start_self' can proxy the traffic from host and other instances in LAN while 'start' can not proxy the traffic from host.
# for xray
./xray-tproxy.sh -p <PORT> -o start_self
# for sslocal
./ss-tproxy.sh -p <PORT> -o start_self
# remember to run ./xray-tproxy.sh(./ss-tproxy.sh) -p <PORT> -o stop_self when you don't want the traffic to be proxied.
```
4. run xray or sslocal in tproxy mode
```bash
systemctl start xray-client@tproxy
systemctl start sslocal-client@tproxy
```

# Reference
1. [Project X](https://xtls.github.io/)
2. [Xray-core](https://github.com/XTLS/Xray-core)
3. [Shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)
4. [Shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)
5. [ss-tproxy](https://github.com/zfl9/ss-tproxy)
6. [Linux Capabilities](https://github.com/ContainerSolutions/capabilities-blog)

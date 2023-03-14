# tproxy-scripts
## Executable
- /usr/local/bin/sslocal(from [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)) or ss-local(from [shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev))
- or program that supports (tcp-redir, udp-tproxy or tcp-tproxu, udp-tproxy)

## Preparation
- create the user 'proxy' to run sslocal. (to identify the traffic by uid and gid in chain OUTPUT)
- make sure the executable files have enough capabilities. (to let the non-privileged user 'proxy' be capable of running sslocal)
- make sure the configuration files of sslocal are correct.

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
sudo setcap cap_net_admin,cap_net_bind_service+ep sslocal
```
Operation 1 and 2 only need to be run once.
Only if the executable files changes, operation 2 will have to be run again.

---
3. add iptables rules and set policy routing
```bash
./ipt-rules.sh -p <proxy_port> -m <proxy_mode_number> -o <start|stop|status>
	## proxy taffic from others
	    # mode 1: tcp-tproxy(chain PREROUTING table mangle) udp-tproxy(chain PREROUTING table mangle)
	    # mode 2: tcp-redir(chain PREROUTING table nat)  udp-tproxy(chain PREROUTING table mangle)
	## proxy traffic from host(self)
	    # mode 3: tcp-tproxy(chain PREROUTING,OUTPUT table mangle) udp-tproxy(chain PREROUTING,OUTPUT table mangle)
	    # mode 4: tcp-redir(chain OUTPUT table nat) udp-tproxy(chain PREROUTING,OUTPUT table mangle)
```

# Reference
1. [Project X](https://xtls.github.io/)
2. [Shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)
3. [Shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)
4. [ss-tproxy](https://github.com/zfl9/ss-tproxy)
5. [Linux Capabilities](https://github.com/ContainerSolutions/capabilities-blog)

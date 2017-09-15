# gfwlist2dnsmasq
A shell script which convert gfwlist into dnsmasq rules.

Working on both Linux-based (Debian/Ubuntu/Cent OS/OpenWrt/LEDE/Cygwin/Bash on Windows/etc.) system.

This script needs `awk`, `base64` and `wget`. You should have these binaries on you system.

### Usage
```
sh gfwlist2dnsmasq.sh [options] -o FILE

Valid options:
    -d <dns_ip>
            DNS IP address for the GfwList Domains (default: 127.0.0.1)
    -p <dns_port>
            DNS Port for the GfwList Domains (default: 5353)
    -s <ipset_name>
            Ipset name for the GfwList domains (default: gfwlist)
            Set blank ("") to disable ipset rule output
    -o <FILE>
            /path/to/output_filename (required)
    -q
            Quiet mode (no output)
    -i
            Force bypass certificate validation (insecure)
    -h
            Show this message
```

### OpenWRT / LEDE Usage

For OpenWrt/LEDE system, `base64` and `wget` may not be included into the system by default. For security reason, this script won't bypass the certificate validation. So you should install ca-certificates as well. For LEDE users, you should install ca-bundle in addition:

```
# OpenWrt
opkg update
opkg install coreutils-base64 wget ca-certificates
# LEDE
opkg update
opkg install coreutils-base64 wget ca-certificates ca-bundle
```

If you really want to bypass the certificate validation, use '-i' or '--insecure' option. You should know this is insecure.

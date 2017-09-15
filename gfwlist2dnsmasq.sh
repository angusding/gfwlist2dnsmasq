#!/bin/sh
#
# Copyright (C) 2017 Xingwang Liao<kuoruan@gmail.com>
#
# This is free software licensed under the terms of the GNU GPL v3.0
#

GFWLIST_URL='https://github.com/gfwlist/gfwlist/raw/master/gfwlist.txt'

DNS_IP='127.0.0.1'
DNS_PORT='5353'
IPSET_NAME='gfwlist'
IPSET_FILE=""

usage() {
	cat >&1 <<-EOF
		Usage: $(basename $0) [options]
		Valid options:
		    -d <dns_ip>
		            DNS IP address for the GfwList Domains (Default: 127.0.0.1)
		    -p <dns_port>
		            DNS Port for the GfwList Domains (Default: 5353)
		    -s <ipset_name>
		            Ipset name for the GfwList domains (Default: ss_spec_dst_fw)
		            Set blank ("") to disable ipset output
		    -o <FILE>
		            /path/to/output_filename (Required)
		    -i
		            Force bypass certificate validation (Insecure)
		    -h
		            Show this message
	EOF
	exit $1
}

all_process() {
	command -v base64 >/dev/null || {
		echo "base64 support is required. Please install 'coreutils-base64'"
		exit 1
	}

	TMP_DIR="$(mktemp -d)"
	GFWLIST_FILE="${TMP_DIR}/gfwlist.txt"
	DECODE_FILE="${TMP_DIR}/gfwlist_decode.txt"
	DOMAIN_FILE="${TMP_DIR}/domains.txt"
	IPSET_TMP_FILE="${TMP_DIR}/ipset.txt.tmp"

	IGNORE_PATTERN='^$|^\!|\[|^@@|[0-9]{1,3}(\.[0-9]{1,3}){3}'
	DOMAIN_PATTERN='[0-9A-Za-z\-\_]+\.[0-9A-Za-z\-\_\.]+'

	GOOGLE_DOMAINS="ac|ad|ae|al|am|as|at|az|ba|be|bf|bg|bi|bj|bs|bt|by|ca|cat|cd|cf|cg|ch|ci|cl|cm"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|co.ao|co.bw|co.ck|co.cr|co.id|co.il|co.in|co.jp|co.ke|co.kr"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|co.ls|co.ma|com|com.af|com.ag|com.ai|com.ar|com.au|com.bd|com.bh"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|com.bn|com.bo|com.br|com.bz|com.co|com.cu|com.cy|com.do|com.ec"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|com.eg|com.et|com.fj|com.gh|com.gi|com.gt|com.hk|com.jm|com.kh"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|com.kw|com.lb|com.ly|com.mm|com.mt|com.mx|com.my|com.na|com.nf"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|com.ng|com.ni|com.np|com.om|com.pa|com.pe|com.pg|com.ph|com.pk"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|com.pr|com.py|com.qa|com.sa|com.sb|com.sg|com.sl|com.sv|com.tj"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|com.tr|com.tw|com.ua|com.uy|com.vc|com.vn|co.mz|co.nz|co.th|co.tz"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|co.ug|co.uk|co.uz|co.ve|co.vi|co.za|co.zm|co.zw|cv|cz|de|dj|dk"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|dm|dz|ee|es|eu|fi|fm|fr|ga|ge|gg|gl|gm|gp|gr|gy|hk|hn|hr|ht|hu"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|ie|im|iq|is|it|je|jo|kg|ki|kz|la|li|lk|lt|lu|lv|md|me|mg|mk|ml"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|mn|ms|mu|mv|mw|mx|ne|nl|no|nr|nu|org|pl|pn|ps|pt|ro|rs|ru|rw|sc"
	GOOGLE_DOMAINS="${GOOGLE_DOMAINS}|se|sh|si|sk|sm|sn|so|sr|st|td|tg|tk|tl|tm|tn|to|tt|us|vg|vn|vu|ws"

	clean_and_exit() {
		rm -rf "$TMP_DIR"
		exit $1
	}

	download_gfwlist() {
		[ -z "$download_count" ] && download_count=1
		if ! ( wget -qO "$GFWLIST_FILE" $DOWNLOAD_ARG "$GFWLIST_URL" ); then
			if [ "$download_count" -lt 3 ]; then
				download_count=$(expr $download_count + 1)
				download_gfwlist
			else
				clean_and_exit 1
			fi
		fi
	}

	download_gfwlist

	base64 -d "$GFWLIST_FILE" 2>/dev/null >"$DECODE_FILE" || clean_and_exit 1

	grep -vE "$IGNORE_PATTERN" "$DECODE_FILE" | \
		grep -oE "$DOMAIN_PATTERN" >"$DOMAIN_FILE" || clean_and_exit 1

	# export Google and Blogspot domains
	echo "$GOOGLE_DOMAINS" | awk -F\| '
		{
			for ( i = 0; ++i <= NF; ) {
				printf "google.%s\nblogspot.%s\n", $i, $i
			}
		}' >>"$DOMAIN_FILE"

	cat "$DOMAIN_FILE" 2>/dev/null | sort | uniq | \
		awk -v dns_ip="$DNS_IP" -v dns_port="$DNS_PORT" -v ipset_name="$IPSET_NAME" -F'.' \
		'{
			if ( NF >= 3 ) {
				sub(/^www[0-9]*\./, "", $0)
			}
			printf "server=/%s/%s#%d\n", $0, dns_ip, dns_port
			if ( ipset_name != "" ) {
				printf "ipset=/%s/%s\n", $0, ipset_name
			}
		}' >"$IPSET_TMP_FILE" || clean_and_exit 1

	ipset_file_bak=""
	if [ -f "$IPSET_FILE" ]; then
		ipset_file_bak="${IPSET_FILE}.bak"
		mv -f "$IPSET_FILE" "$ipset_file_bak"
	else
		ipset_dir="$(dirname "$IPSET_FILE")"
		if [ ! -d "$ipset_dir" ]; then
			mkdir -p "$ipset_dir"
		fi
	fi

	cat >"$IPSET_FILE" <<-EOF
		#
		# Update Date: $(date +"%Y-%m-%d %H:%M:%S")
		#
		$(cat "$IPSET_TMP_FILE" 2>/dev/null)
	EOF

	if [ "$(awk 'END { print NR }' "$IPSET_FILE" 2>/dev/null)" -le 4 ]; then
		[ -n "$ipset_file_bak" ] && mv -f "$ipset_file_bak" "$IPSET_FILE"
		clean_and_exit 1
	fi

	[ -n "$ipset_file_bak" ] && rm -f "$ipset_file_bak"

	echo "Done."
	clean_and_exit 0
}

while getopts 'd:p:s:o:ih' arg; do
	case $arg in
		d)
			[ -n "$OPTARG" ] || {
				echo "Invalid DNS IP."
				exit 1
			}
			DNS_IP="$OPTARG"
			;;
		p)
			[ -n "$OPTARG" ] || {
				echo "Invalid DNS port."
				exit 1
			}
			DNS_PORT="$OPTARG"
			;;
		s)
			IPSET_NAME="$OPTARG"
			;;
		o)
			IPSET_FILE="$OPTARG"
			;;
		i)
			DOWNLOAD_ARG="${DOWNLOAD_ARG} --no-check-certificate"
			;;
		h)
			usage 0
			;;
		?)
			usage 1
			;;
		esac
done

[ -n "$IPSET_FILE" ] || {
	echo 'Invalid output filename.'
	exit 1
}

all_process

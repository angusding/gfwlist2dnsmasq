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
OUTPUT_FILE=''
QUIET=''

DOWNLOAD_ARGS=''

usage() {
	cat >&1 <<-EOF
		Usage: $(basename $0) [options]
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
	EOF
	exit $1
}

all_process() {
	command -v base64 >/dev/null || {
		[ -n "$QUIET" ] || echo "base64 support is required. Please install 'coreutils-base64'"
		exit 1
	}

	TMP_DIR="$(mktemp -d)"
	GFWLIST_FILE="${TMP_DIR}/gfwlist.txt"
	DECODE_FILE="${TMP_DIR}/gfwlist_decode.txt"
	DOMAIN_FILE="${TMP_DIR}/domains.txt"
	OUTPUT_FILE_TMP="${TMP_DIR}/output.conf.tmp"

	IGNORE_PATTERN='^$|^\!|\[|^@@|[0-9]{1,3}(\.[0-9]{1,3}){3}'
	DOMAIN_PATTERN='[0-9A-Za-z\-\_]+\.[0-9A-Za-z\-\_\.]+'

	SUFFIX_LIST="ac|ad|ae|al|am|as|at|az|ba|be|bf|bg|bi|bj|bs|bt|by|ca|cat|cd|cf|cg|ch|ci|cl|cm"
	SUFFIX_LIST="${SUFFIX_LIST}|co.ao|co.bw|co.ck|co.cr|co.id|co.il|co.in|co.jp|co.ke|co.kr"
	SUFFIX_LIST="${SUFFIX_LIST}|co.ls|co.ma|com|com.af|com.ag|com.ai|com.ar|com.au|com.bd|com.bh"
	SUFFIX_LIST="${SUFFIX_LIST}|com.bn|com.bo|com.br|com.bz|com.co|com.cu|com.cy|com.do|com.ec"
	SUFFIX_LIST="${SUFFIX_LIST}|com.eg|com.et|com.fj|com.gh|com.gi|com.gt|com.hk|com.jm|com.kh"
	SUFFIX_LIST="${SUFFIX_LIST}|com.kw|com.lb|com.ly|com.mm|com.mt|com.mx|com.my|com.na|com.nf"
	SUFFIX_LIST="${SUFFIX_LIST}|com.ng|com.ni|com.np|com.om|com.pa|com.pe|com.pg|com.ph|com.pk"
	SUFFIX_LIST="${SUFFIX_LIST}|com.pr|com.py|com.qa|com.sa|com.sb|com.sg|com.sl|com.sv|com.tj"
	SUFFIX_LIST="${SUFFIX_LIST}|com.tr|com.tw|com.ua|com.uy|com.vc|com.vn|co.mz|co.nz|co.th|co.tz"
	SUFFIX_LIST="${SUFFIX_LIST}|co.ug|co.uk|co.uz|co.ve|co.vi|co.za|co.zm|co.zw|cv|cz|de|dj|dk"
	SUFFIX_LIST="${SUFFIX_LIST}|dm|dz|ee|es|eu|fi|fm|fr|ga|ge|gg|gl|gm|gp|gr|gy|hk|hn|hr|ht|hu"
	SUFFIX_LIST="${SUFFIX_LIST}|ie|im|iq|is|it|je|jo|kg|ki|kz|la|li|lk|lt|lu|lv|md|me|mg|mk|ml"
	SUFFIX_LIST="${SUFFIX_LIST}|mn|ms|mu|mv|mw|mx|ne|nl|no|nr|nu|org|pl|pn|ps|pt|ro|rs|ru|rw|sc"
	SUFFIX_LIST="${SUFFIX_LIST}|se|sh|si|sk|sm|sn|so|sr|st|td|tg|tk|tl|tm|tn|to|tt|us|vg|vn|vu|ws"

	clean_and_exit() {
		rm -rf "$TMP_DIR"
		exit $1
	}

	download_gfwlist() {
		if ! ( wget -O "$GFWLIST_FILE" $DOWNLOAD_ARGS "$GFWLIST_URL" ); then
			download_count="${download_count:-1}"
			if [ "$download_count" -lt 3 ]; then
				download_count=$(expr $download_count + 1)
				download_gfwlist
			else
				[ -n "$QUIET" ] || echo "Download gfwlist failed."
				clean_and_exit 1
			fi
		fi
	}

	download_gfwlist

	base64 -d "$GFWLIST_FILE" 2>/dev/null >"$DECODE_FILE" || {
		[ -n "$QUIET" ] || echo "Decode gfwlist failed."
		clean_and_exit 1
	}

	grep -vE "$IGNORE_PATTERN" "$DECODE_FILE" | \
		grep -oE "$DOMAIN_PATTERN" >"$DOMAIN_FILE" || {
			[ -n "$QUIET" ] || echo "Filter blocked domains failed."
			clean_and_exit 1
		}

	# export Google and Blogspot domains
	echo "$SUFFIX_LIST" | awk -F\| '
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
		}' >"$OUTPUT_FILE_TMP" || {
			[ -n "$QUIET" ] || echo "Create dnsmasq config file failed."
			clean_and_exit 1
		}

	config_file_bak=""
	if [ -f "$OUTPUT_FILE" ]; then
		config_file_bak="${OUTPUT_FILE}.bak"
		mv -f "$OUTPUT_FILE" "$config_file_bak"
	else
		output_dir="$(dirname "$OUTPUT_FILE")"
		if [ ! -d "$output_dir" ]; then
			mkdir -p "$output_dir"
		fi
	fi

	cat >"$OUTPUT_FILE" <<-EOF
		#
		# Update Date: $(date +"%Y-%m-%d %H:%M:%S")
		#
		$(cat "$OUTPUT_FILE_TMP" 2>/dev/null)
	EOF

	if [ "$(awk 'END { print NR }' "$OUTPUT_FILE" 2>/dev/null)" -le 4 ]; then
		rm -f "$OUTPUT_FILE"
		[ -n "$config_file_bak" ] && mv -f "$config_file_bak" "$OUTPUT_FILE"

		[ -n "$QUIET" ] || echo "Create output file failed."
		clean_and_exit 1
	fi

	[ -n "$config_file_bak" ] && rm -f "$config_file_bak"

	[ -n "$QUIET" ] || echo "Done."
	clean_and_exit 0
}

while getopts 'd:p:s:o:qih' arg; do
	case $arg in
		d)
			[ -n "$OPTARG" ] || {
				[ -n "$QUIET" ] || echo "Invalid DNS IP."
				exit 1
			}
			DNS_IP="$OPTARG"
			;;
		p)
			[ -n "$OPTARG" ] || {
				[ -n "$QUIET" ] || echo "Invalid DNS port."
				exit 1
			}
			DNS_PORT="$OPTARG"
			;;
		s)
			IPSET_NAME="$OPTARG"
			;;
		o)
			OUTPUT_FILE="$OPTARG"
			;;
		q)
			QUIET=1
			DOWNLOAD_ARGS="${DOWNLOAD_ARGS} -q"
			;;
		i)
			DOWNLOAD_ARGS="${DOWNLOAD_ARGS} --no-check-certificate"
			;;
		h)
			usage 0
			;;
		?)
			usage 1
			;;
		esac
done

[ -n "$OUTPUT_FILE" ] || {
	[ -n "$QUIET" ] || echo 'Invalid output filename.'
	exit 1
}

all_process

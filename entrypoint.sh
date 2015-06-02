#!/bin/bash

source /etc/sysconfig/ccc

get_coreos_signing_key() {
    if [ ! -e "$CCC_CACHEDIR"/CoreOS_Image_Signing_Key.pem ]; then
        if wget --quiet -c -P "$CCC_CACHEDIR" http://coreos.com/security/image-signing-key/CoreOS_Image_Signing_Key.pem
	then
		echo "Downloaded CoreOS signing key" 
	else
		echo "Failed to download CoreOS signing key"
		exit 1
	fi
    else
        echo "CoreOS signing key already downloaded" 
    fi
       
    gpg --quiet --import "$CCC_CACHEDIR"/CoreOS_Image_Signing_Key.pem &>/dev/null || { echo "Failed to import signing key"; exit 1; }

    echo "Imported CoreOS signing key"
}

get_coreos_images() {

    (
      cd "$CCC_CACHEDIR" || exit 1

      for channelversion in $CCC_COREOS_VERSIONS
      do

	channel=${channelversion%%:*}
	version=${channelversion#*:}
	test "$version" = "$channel" && version=""

	if ! { echo "$channel" | grep -P '^(stable|beta|alpha)$' &>/dev/null; }
	then
		echo "Warning: bad channel specification '$channel'" 
		echo "Skipping downloading images for '$channelversion'" 
		continue
	fi

	if test -z "$version" && ! test "true" = "$CCC_SKIP_VERIFICATION"
	then
	        version=$(wget -q -O - "http://$channel.release.core-os.net/amd64-usr/" | tr \" "\n" | grep -P '^\d{3,4}\.\d{1,2}\.\d{1,2}\/?' | tail -1)
		version=${version%/}	

		if test -n "$version" 
		then
			echo "$channel channel: detected latest is $version"
		else
			echo "Warning: $channel channel: unable to detect latest version from coreos site"
		fi
	fi

	test -z "$version" && version=$(find_latest $channel)

	if ! { echo "$version" | grep -P '^\d+\.\d+\.\d+$' &>/dev/null; }
	then
		test -n "$version" && echo "Skipping downloading images for '$channelversion'"
		continue
	fi

        for image in $CCC_COREOS_PXE_VMLINUZ $CCC_COREOS_PXE_IMAGE_CPIO
        do

          if ! test -e "$channel/$version/$image" || ! test -e "$channel/$version/$image.sig"
          then
        
            echo "Downloading $channel/$version/$image ..."

            wget -q -c -P $channel/$version http://$channel.release.core-os.net/amd64-usr/$version/$image.sig && \
            wget -q -c -P $channel/$version http://$channel.release.core-os.net/amd64-usr/$version/$image

            test $? -eq 0 || { echo "Failed to download $channel:$version image files"; exit 1; }

          fi

	  if test "true" != "$CCC_SKIP_VERIFICATION"     
	  then
            echo "Verifying $channel/$version/$image ..."

            if ! ( cd $channel/$version && gpg --verify $image.sig &>/dev/null)
            then
              echo "Image verification failed for $channel:$version files. Deleting them. Check and or run again." 
	      rm -f "$channel/$version/$image"  "$channel/$version/$image.sig"
              exit 1
            fi

	  fi

        done

      done


    ) || exit 1
    
}

function init_files() {

	echo "Recreating/checking files in '$CCC_DIR'"

	mkdir -p "$CCC_DIR"
	mkdir -p "$CCC_NODESDIR"
	mkdir -p "$CCC_SSHDIR"
	mkdir -p "$CCC_TFTPDIR"
	mkdir -p "$CCC_PXEDIR"
	mkdir -p "$CCC_CACHEDIR"
	mkdir -p "$CCC_HOSTSDIR"

	/bin/cp -f /usr/share/syslinux/pxelinux.0 "$CCC_PXEDIR/.."
	
	/bin/cp -f /etc/dnsmasq.conf.base /etc/dnsmasq.conf
	echo "server=$CCC_DNS1" >> /etc/dnsmasq.conf
	echo "server=$CCC_DNS2" >> /etc/dnsmasq.conf
	echo "tftp-root=$CCC_TFTPDIR" >> /etc/dnsmasq.conf
	echo "conf-dir=$CCC_NODESDIR" >> /etc/dnsmasq.conf
	echo "domain=$CCC_SERVERDOMAIN" >> /etc/dnsmasq.conf
	echo "dhcp-range=$CCC_SERVERSUBNET,$CCC_SERVERSUBNET,0h" >> /etc/dnsmasq.conf 
	echo "dhcp-boot=pxelinux.0,$CCC_SERVERNAME,$CCC_SERVERIP" >> /etc/dnsmasq.conf
	echo "addn-hosts=$CCC_HOSTSDIR" >> /etc/dnsmasq.conf

	if ! test -e "$CCC_SERVERKEYFILE"
	then
		echo "Creating new public/private key pair"
		ssh-keygen -q -N '' -f "$CCC_SERVERKEYFILE"
	fi

	test -e "$CCC_DIR/cloud-init.yml.default.template" ||
		/bin/cp /cloud-init.yml.default.template "$CCC_DIR/cloud-init.yml.default.template"
}

init_files

test "true" = "$CCC_SKIP_VERIFICATION" & echo "Warning: image verification and autodetection of online latest channel versions are DISABLED"

test "true" = "$CCC_SKIP_VERIFICATION" || get_coreos_signing_key 

get_coreos_images

current_stable=$(find_latest stable)
if test -n "$current_stable"
then
	echo "Using $current_stable as current for stable channel"
else
	echo "Unable to locally find the current image for stable channel"
	exit 1
fi

current_beta=$(find_latest beta)
if test -n "$current_beta"
then
	echo "Using $current_beta as current for beta channel"
else
	echo "Unable to locally find the current image for beta channel"
	exit 1
fi

current_alpha=$(find_latest alpha)
if test -n "$current_alpha"
then
	echo "Using $current_alpha as current for alpha channel"
else
	echo "Unable to locally find the current image for alpha channel"
	exit 1
fi

echo
echo "Starting DHCP+PXE -- $CCC_SERVERIPDATA"
dnsmasq -k -q --log-dhcp &>>"$CCC_DIR"/dnsmasq.logs &
ret=$?
test $ret -eq 0 || exit 1
pid=$!

echo "dnsmasq: running under pid $pid"

/bin/rm -f "$CCC_DIR/reconfigure"

while test -d "/proc/$pid"
do
	sleep 1
	if test -f "$CCC_DIR/reconfigure"
	then
		/bin/rm -f "$CCC_DIR/reconfigure"
		echo "dnsmasq: restarting due to reconfiguration request"
		kill "$pid" 2>/dev/null
	 	sleep 1
		kill -9 "$pid" 2>/dev/null

		echo 
		echo "Starting DHCP+PXE -- $CCC_SERVERIPDATA"
		dnsmasq -k -q --log-dhcp &>>"$CCC_DIR"/dnsmasq.logs &
		ret=$?
		test $ret -eq 0 || exit 1
		pid=$!
		echo "dnsmasq: running under pid $pid"
	else
		test 0 -eq "$((SECONDS % 5))" && kill -HUP "$pid" 2>/dev/null # to re-read addn-hosts files each 5seconds
	fi
done

kill "$pid" 2>/dev/null
kill -9 "$pid" 2>/dev/null
echo "finished"

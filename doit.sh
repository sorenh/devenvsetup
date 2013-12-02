#!/bin/bash
#
# There are many ways to do this, but this is how I did it. - Soren
#
# Starting from a clean install of Ubuntu Saucy,
# this cares care of everything:
#

CACHE_CONTAINER="${CACHE_CONTAINER:-cacher}"
DEVSTACK_CONTAINER="${DEVSTACK_CONTAINER:-devstack}"

function find_lxc_ip {
    cont_name="$1"
	out=""
    # The container may not be up just quite yet.
    while ! echo "$out" | grep -q 10\.0\.3\.
    do
        out="$(sudo lxc-ls --fancy --fancy-format name,ipv4 ^${cont_name}\$ | tail -n 1)"
    done
    echo $out | sed -e 's/.*\(10\.0\.3\.[0-9]*\).*/\1/g'
}

function install_base_packages {
    # Install lxc
    sudo apt-get install lxc
}

function find_cacher_ip {
    cache_ip="$(find_lxc_ip ${CACHE_CONTAINER})"
}

function find_devstack_ip {
    devstack_ip="$(find_lxc_ip ${DEVSTACK_CONTAINER})"
}

function create_cache_container {
    # Create the cacher container
    sudo lxc-create -t ubuntu -n ${CACHE_CONTAINER} -- -r precise -b $USER
    # Start it
    sudo lxc-start -d -n ${CACHE_CONTAINER}

    # Find and set the cache_ip environment variable
	find_cacher_ip

    # Log in over SSH and install devpi and apt-cacher-ng
    ssh -t $cache_ip 'sudo apt-get -y install python-pip apt-cacher-ng ; \
	                  sudo pip install devpi-server ; \
					  echo -e "PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin\n@reboot devpi-server --host=0.0.0.0" | crontab -'


    mkdir -p ${HOME}/.pip
    echo "[global]" >> ${HOME}/.pip/pip.conf
	echo "index-url = http://${cache_ip}:3141/root/pypi/+simple/" > ${HOME}/.pip/pip.conf
}

function create_devstack_container {
    # Grab the cacher's IP if we don't already have it
	find_cacher_ip

    # Create the devstack container
    sudo lxc-create -t ubuntu -n ${DEVSTACK_CONTAINER} -- -r precise -b $USER

    # Allow for nested containers (specifically, we need the ability to
    # twiddle with cgroups inside the devstack container)
    sudo sed -e 's/^#\(lxc.aa_profile = lxc-co\)/\1/g' \
	         -e 's/^#\(lxc.hook.mount\)/\1/g' -i \
			 /var/lib/lxc/${DEVSTACK_CONTAINER}/config

	echo -e '# nbd\necho 'lxc.cgroup.devices.allow = c 43:* rwm' | sudo tee --append /var/lib/lxc/${DEVSTACK_CONTAINER}/config

    # Fire it up and grab its IP
    sudo lxc-start -d -n ${DEVSTACK_CONTAINER}
	find_devstack_ip

    # Log in and configure the APT proxy and add the havana cloud-archive
    ssh -t $devstack_ip 'echo Acquire::Http::Proxy \"http://'${cache_ip}':3142/\"\; | sudo tee /etc/apt/apt.conf.d/90proxy ;
	                     sudo mkdir /dev/net ;
						 sudo apt-get install python-software-properties ;
						 sudo add-apt-repository cloud-archive:havana ;
						 sudo apt-get update ;
						 sudo apt-get install git curl python-setuptools ;
						 sudo mkdir /var/run/openstack ;
						 sudo chmod 777 /var/run/openstack ;
                         sudo mkdir -p ${HOME}/.pip ;
                         echo "[global]" | sudo tee --apend /root/.pip/pip.conf ;
	                     echo "index-url = http://'${cache_ip}':3141/root/pypi/+simple/" | sudo tee --append /root/.pip/pip.conf'

    # Add kvm and tun ctrl devices
    sudo lxc-device -n ${DEVSTACK_CONTAINER} add /dev/kvm
    sudo lxc-device -n ${DEVSTACK_CONTAINER} add /dev/net/tun

	echo "To access the devstack instance:"
    echo "   ssh ${devstack_ip}"
}

function setup_module_loading {
    # Load a couple of modules on the host that the containers need
    for mod in ebtable_filter kvm_intel scsi_transport_iscsi nbd
    do
        sudo modprobe $mod
        grep -q $mod /etc/modules || echo $mod | sudo tee --append /etc/modules
    done
}

step=${1:-start}

case $1 in
    start|install_base_packages)
	    install_base_packages
		;&
    create_cacher)
        create_cache_container
		;&
    create_devstack)
        create_devstack_container
		;&
	setup_module_loading)
        setup_module_loading
		;;
esac

exit 0

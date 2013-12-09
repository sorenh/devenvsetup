#!/bin/bash

test -e config && . config

BASE_MIRROR_DIR=${BASE_MIRROR_DIR:-${HOME}/src/stack}

if [ -e "${BASE_MIRROR_DIR}" ]
then
	echo "Creating base mirror dir at $BASE_MIRROR_DIR"
    mkdir -p ${BASE_MIRROR_DIR}
fi

cd "${BASE_MIRROR_DIR}"
mkdir -p openstack openstack-dev

for x in openstack/{cinder,glance,horizon,keystone,neutron,nova,oslo.config,oslo.messaging,python-cinderclient,python-glanceclient,python-heatclient,python-keystoneclient,python-neutronclient,python-novaclient,python-openstackclient,python-swiftclient,requirements,tempest} openstack-dev/pbr
do
	if [ -e $x ]
	then
		echo "Refreshing $x"
		cd $x
		git pull
		cd -
	else
		echo "Cloning $x"
		git clone git@github.com:$x $x
	fi
done

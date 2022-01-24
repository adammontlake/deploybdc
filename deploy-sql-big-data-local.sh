#!/bin/bash

#Allowed parameters to run script
allowed_commands=["help","check_dependencies","create_cluster"]

help(){
	echo "Script to deploy bdc on local OpenShift cluster"
	echo "Enter 1 or more of the following options:"
	echo "check_dependencies - Check that all script dependencies are present"
	echo "create_cluster - deploy the cluster"
}

check_dependencies(){
	{
		az --version 2>/dev/null | grep -q -e "azure-cli" && echo "Found az-cli" 
	} || {
		echo "Failed to find az cli, exiting script..."
		exit 1
	}
	{
		azdata --version 2>/dev/null | grep -q -e "Build" && echo "Found azdata" 
	} || {
		echo "Failed to find azdata, exiting script..."
		exit 1
	}
	{
		oc version 2>/dev/null | grep -q -e "Client Version:" && echo "Found oc" 
	} || {
		echo "Failed to find oc, exiting script..."
		exit 1
	}
	{
		ls bdc-scc.yaml 2>/dev/null && echo "Found scc"
	} || {
		echo "Failed to find scc, exiting script..."
		exit 1
	}
}

oc_login(){
	read -p 'OC_CLUSTER_USERNAME (default: kubeadmin): ' OC_CLUSTER_USERNAME
	read -sp 'OC_CLUSTER_PASSWORD: ' OC_CLUSTER_PASSWOR
	read -p 'APISERVER: ' APISERVER
	OC_CLUSTER_USERNAME=${OC_CLUSTER_USERNAME:-kubeadmin}
	oc login $APISERVER -u $OC_CLUSTER_USERNAME -p $OC_CLUSTER_PASSWORD
}

Prepare_cluster(){
	echo "Create new project $CLUSTER_NAME"
	oc new-project $CLUSTER_NAME

	echo "create custom SCC for BDC"
	oc apply -f bdc-scc.yaml
}

create_role(){
	echo "Create role..."
	oc create clusterrole bdc-role --verb=use --resource=scc --resource-name=bdc-scc -n $CLUSTER_NAME
}
create_binding(){
	echo "Create role binding..."
	oc create rolebinding bdc-rbac --clusterrole=bdc-role --group=system:serviceaccounts:$CLUSTER_NAME
}

deploy_cluster(){
	read -p 'AZDATA USERNAME (sqladmin): ' AZDATA_USERNAME
	read -sp 'AZDATA PASSWORD (password): ' AZDATA_PASSWORD

	AZDATA_USERNAME=${AZDATA_USERNAME:-sqladmin}
	AZDATA_PASSWORD=${AZDATA_PASSWORD:-password}

	export AZDATA_USERNAME=$AZDATA_USERNAME
	export AZDATA_PASSWORD=$AZDATA_PASSWORD
	export ACCEPT_EULA="Yes"
	azdata bdc config init --source openshift-dev-test -p custom --accept-eula yes --force
	
	echo "Update config"
	read -p 'Docker registry: ' REGISTRY
	read -p 'Docker repository: ' REPOSITORY
	read -p 'Image tag: ' IMAGE_TAG
	read -p 'Storage class: ' STORAGE_CLASS
	azdata bdc config replace -p custom/bdc.json -j metadata.name=$CLUSTER_NAME
	azdata bdc config replace -p custom/control.json -j spec.docker.registry=$REGISTRY
	azdata bdc config replace -p custom/control.json -j spec.docker.repository=$REPOSITORY
	azdata bdc config replace -p custom/control.json -j spec.docker.imageTag=$IMAGE_TAG
	azdata bdc config replace -p custom/control.json -j spec.storage.data.className=$STORAGE_CLASS
	azdata bdc config replace -p custom/control.json -j spec.storage.logs.className=$STORAGE_CLASS

	azdata bdc create --config-profile custom --accept-eula yes
	azdata login -n $CLUSTER_NAME
	azdata bdc endpoint list -o table
}

create_cluster(){
	read -p 'CLUSTER NAME (default: bdcsql): ' CLUSTER_NAME
	CLUSTER_NAME=${CLUSTER_NAME:-bdcsql}
	check_dependencies
	oc_login
	Prepare_cluster
	create_role
	create_binding
	deploy_cluster
}

if [ $# == 0 ] 
then
	help
else
	for var in "$@"
	do
		if [[ $allowed_commands =~ $var ]]; 
		then 
			$var 
		else
			help
		fi
	done
fi


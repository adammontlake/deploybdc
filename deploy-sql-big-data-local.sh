#!/bin/bash

#Allowed parameters to run script
allowed_commands=["help","check_dependencies","create_cluster"]

#Cluster and project name
CLUSTER_NAME="bdcsql"

#Cluster connection settings
CLUSTER_TYPE="openshift-prod"	#openshift-prod or openshift-dev-test
OC_CLUSTER_USERNAME="kubeadmin"
OC_CLUSTER_PASSWORD=""
APISERVER=""

#Application credentials
AZDATA_USERNAME=""
AZDATA_PASSWORD=""

#Registry settings
REGISTRY=""
REPOSITORY=""
IMAGE_TAG=""

#Storage type (use local-path for testing)
STORAGE_CLASS=""

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
	echo "Login"
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
	export AZDATA_USERNAME=$AZDATA_USERNAME
	export AZDATA_PASSWORD=$AZDATA_PASSWORD
	export ACCEPT_EULA="Yes"
	azdata bdc config init --source openshift-dev-test -p custom --accept-eula yes --force
	
	echo "Update config"
	azdata bdc config replace -p custom/bdc.json -j metadata.name=$CLUSTER_NAME
	azdata bdc config replace -p custom/control.json -j spec.docker.registry=$REGISTRY
	azdata bdc config replace -p custom/control.json -j spec.docker.repository=$REPOSITORY
	azdata bdc config replace -p custom/control.json -j spec.docker.imageTag=$IMAGE_TAG
	azdata bdc config replace -p custom/control.json -j spec.storage.data.className=$STORAGE_CLASS
	azdata bdc config replace -p custom/control.json -j spec.storage.logs.className=$STORAGE_CLASS

	echo "Deploy"
	azdata bdc create --config-profile custom --accept-eula yes
	azdata login -n $CLUSTER_NAME
	azdata bdc endpoint list -o table
}

create_cluster(){
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


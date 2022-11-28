#!/bin/bash

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(realpath ${__dir}/../../..)"
source ${__dir}/../common.sh
source ${__dir}/../utils.sh
playbooks_dir=${__dir}/playbooks

export SSH_PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
export HOSTED_CLUSTER_NAME=$(oc get hostedclusters -n clusters -ojsonpath="{.items[0].metadata.name}")
export HOSTED_CONTROL_PLANE_NAMESPACE="clusters-"${HOSTED_CLUSTER_NAME}
export ASSISTED_PULLSECRET_JSON="${ASSISTED_PULLSECRET_JSON:-${PULL_SECRET_FILE}}"
export INFRAENV_NAME=${HOSTED_CLUSTER_NAME}

echo "Running Ansible playbook to create kubernetes objects"
ansible-playbook "${__dir}/bmh-playbook.yaml"

oc get secret pull-secret -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
    oc create secret generic pull-secret --from-file=.dockerconfigjson="${ASSISTED_PULLSECRET_JSON}" --type=kubernetes.io/dockerconfigjson -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"
oc get secret "${ASSISTED_PRIVATEKEY_NAME}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
    oc create secret generic "${ASSISTED_PRIVATEKEY_NAME}" --from-file=ssh-privatekey=/root/.ssh/id_rsa --type=kubernetes.io/ssh-auth -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"

for manifest in $(find ${__dir}/generated -type f); do
    tee < "${manifest}" >(oc apply -f -)
done

#oc wait --timeout=5m --for=condition=ImageCreated --namespace=${HOSTED_CONTROL_PLANE_NAMESPACE} InfraEnv/${INFRAENV_NAME}

#wait_for_condition "infraenv/${HOSTED_CLUSTER_NAME}" "ImageCreated" "5m" "${HOSTED_CONTROL_PLANE_NAMESPACE}"
#export ISO_DOWNLOAD_URL=$(oc get -n $HOSTED_CONTROL_PLANE_NAMESPACE infraenv $HOSTED_CLUSTER_NAME -o jsonpath='{.status.isoDownloadURL}')

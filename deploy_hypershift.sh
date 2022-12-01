#!/bin/bash

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(realpath ${__dir}/../../..)"
source ${__dir}/../common.sh
source /root/dev-scripts-additional-config
playbooks_dir=${__dir}/playbooks

export SSH_PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
export HOSTED_CLUSTER_NAME=$(oc get hostedclusters -n clusters -ojsonpath="{.items[0].metadata.name}")
export HOSTED_CONTROL_PLANE_NAMESPACE="clusters-"${HOSTED_CLUSTER_NAME}
export ASSISTED_PULLSECRET_JSON="${ASSISTED_PULLSECRET_JSON:-${PULL_SECRET_FILE}}"
export ASSISTED_PRIVATEKEY_NAME="${ASSISTED_PRIVATEKEY_NAME:-assisted-ssh-private-key}"
export INFRAENV_NAME=${HOSTED_CLUSTER_NAME}

echo "Running Ansible playbook to create kubernetes objects"
ansible-playbook "${playbooks_dir}/bmh-playbook.yaml"

oc get secret pull-secret -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
    oc create secret generic pull-secret --from-file=.dockerconfigjson="${ASSISTED_PULLSECRET_JSON}" --type=kubernetes.io/dockerconfigjson -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"
oc get secret "${ASSISTED_PRIVATEKEY_NAME}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
    oc create secret generic "${ASSISTED_PRIVATEKEY_NAME}" --from-file=ssh-privatekey=/root/.ssh/id_rsa --type=kubernetes.io/ssh-auth -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"

oc apply -f ${playbooks_dir}/generated/infraEnv.yaml
oc apply -f ${playbooks_dir}/generated/baremetalHost.yaml

echo "wait BareMetalHost ready"
oc wait --all=true BareMetalHost -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --for=jsonpath='{.status.provisioning.state}'=provisioned --timeout=10m

set +e
for ((i=1; i<=10; i++)); do
    count=$(oc get agent -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --no-headers --ignore-not-found | wc -l)
    if [ ${count} == ${NUM_EXTRA_WORKERS} ]  ; then
        echo "agent resources already exist"
        break
    fi
    echo "Waiting on agent resources create"
    sleep 90
done
set -e

echo "scale nodepool replicas => $NUM_EXTRA_WORKERS"
oc scale nodepool ${HOSTED_CLUSTER_NAME} -n clusters --replicas ${NUM_EXTRA_WORKERS}
echo "wait agent ready"
oc wait --all=true agent -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --for=jsonpath='{.status.debugInfo.state}'=added-to-existing-cluster --timeout=30m

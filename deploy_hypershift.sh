#!/bin/bash

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(realpath ${__dir}/../../..)"
source ${__dir}/../common.sh
source /root/dev-scripts-additional-config
playbooks_dir=${__dir}/playbooks

export SSH_PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
export HOSTED_CLUSTER_NS=$(oc get hostedcluster -A -ojsonpath='{.items[0].metadata.namespace}')
export HOSTED_CLUSTER_NAME=$(oc get hostedclusters -n "$HOSTED_CLUSTER_NS" -ojsonpath="{.items[0].metadata.name}")
export HOSTED_CONTROL_PLANE_NAMESPACE=${HOSTED_CLUSTER_NS}"-2"${HOSTED_CLUSTER_NAME}
export ASSISTED_PULLSECRET_JSON="${ASSISTED_PULLSECRET_JSON:-${PULL_SECRET_FILE}}"
export INFRAENV_NAME=${HOSTED_CLUSTER_NAME}

oc create ns HOSTED_CONTROL_PLANE_NAMESPACE
playload=$(oc get clusterversion version -ojsonpath='{.status.desired.image}')
export IRONIC_IMAGE=$(oc adm release info --image-for=ironic-agent "$playload")
echo "Running Ansible playbook to create kubernetes objects"
ansible-playbook "${playbooks_dir}/bmh-playbook.yaml"

#oc get secret pull-secret -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
#    oc create secret generic pull-secret --from-file=.dockerconfigjson="${ASSISTED_PULLSECRET_JSON}" --type=kubernetes.io/dockerconfigjson -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"

oc apply -f ${playbooks_dir}/generated/infraEnv.yaml
oc apply -f ${playbooks_dir}/generated/baremetalHost.yaml

_agentExist=0
set +e
for ((i=1; i<=20; i++)); do
    count=$(oc get agent -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --no-headers --ignore-not-found | wc -l)
    if [ ${count} == ${NUM_EXTRA_WORKERS} ]  ; then
        echo "agent resources already exist"
        _agentExist=1
        break
    fi
    echo "Waiting on agent resources create"
    sleep 60
done
set -e
if [ $_agentExist -eq 0 ]; then
  echo "FATAL: agent cr not Exist"
  exit 1
fi

oc wait --all=true agent -n ${HOSTED_CONTROL_PLANE_NAMESPACE}  --for=condition=RequirementsMet
echo "scale nodepool replicas => $NUM_EXTRA_WORKERS"
oc scale nodepool ${HOSTED_CLUSTER_NAME} -n "$HOSTED_CLUSTER_NS" --replicas ${NUM_EXTRA_WORKERS}
echo "wait agent ready"
oc wait --all=true agent -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --for=jsonpath='{.status.debugInfo.state}'=added-to-existing-cluster --timeout=45m

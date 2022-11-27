#!/bin/bash

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(realpath ${__dir}/../../..)"
source ${__dir}/../common.sh
source ${__dir}/../utils.sh
playbooks_dir=${__dir}/playbooks

export SSH_PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
export HOSTED_CLUSTER_NAME=$(oc get hostedclusters -n clusters -ojsonpath="{.items[0].metadata.name}")
export HOSTED_CONTROL_PLANE_NAMESPACE="clusters-"${HOSTED_CLUSTER_NAME}
export ASSISTED_PULLSECRET_NAME="${ASSISTED_PULLSECRET_NAME:-assisted-pull-secret}"
export ASSISTED_PULLSECRET_JSON="${ASSISTED_PULLSECRET_JSON:-${PULL_SECRET_FILE}}"
export ASSISTED_PRIVATEKEY_NAME="${ASSISTED_PRIVATEKEY_NAME:-assisted-ssh-private-key}"

oc get secret "${ASSISTED_PULLSECRET_NAME}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
    oc create secret generic "${ASSISTED_PULLSECRET_NAME}" --from-file=.dockerconfigjson="${ASSISTED_PULLSECRET_JSON}" --type=kubernetes.io/dockerconfigjson -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"
oc get secret "${ASSISTED_PRIVATEKEY_NAME}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" || \
    oc create secret generic "${ASSISTED_PRIVATEKEY_NAME}" --from-file=ssh-privatekey=/root/.ssh/id_rsa --type=kubernetes.io/ssh-auth -n "${HOSTED_CONTROL_PLANE_NAMESPACE}"

envsubst <<"EOF" | oc apply -f -
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: ${HOSTED_CLUSTER_NAME}
  namespace: ${HOSTED_CONTROL_PLANE_NAMESPACE}
spec:
  pullSecretRef:
    name: ${ASSISTED_PULLSECRET_NAME}
  sshAuthorizedKey: ${SSH_PUB_KEY}
EOF

#wait_for_condition "infraenv/${HOSTED_CLUSTER_NAME}" "ImageCreated" "5m" "${HOSTED_CONTROL_PLANE_NAMESPACE}"
#export ISO_DOWNLOAD_URL=$(oc get -n $HOSTED_CONTROL_PLANE_NAMESPACE infraenv $HOSTED_CLUSTER_NAME -o jsonpath='{.status.isoDownloadURL}')

#echo "Apply BareMetalHost on hub"
#ansible-playbook "${playbooks_dir}/bmh-playbook.yaml"
#oc apply -f ${playbooks_dir}/generated/baremetalHost.yaml -n $HOSTED_CONTROL_PLANE_NAMESPACE
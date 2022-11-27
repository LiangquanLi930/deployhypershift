#!/bin/bash

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(realpath ${__dir}/../../..)"
source ${__dir}/../common.sh
source ${__dir}/../utils.sh
playbooks_dir=${__dir}/playbooks

export SSH_PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
export HOSTED_CLUSTER_NAME=$(oc get hostedclusters -n clusters -ojsonpath="{.items[0].metadata.name}")
export HOSTED_CONTROL_PLANE_NAMESPACE="clusters-"${HOSTED_CLUSTER_NAME}

envsubst <<"EOF" | oc apply -f -
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: ${HOSTED_CLUSTER_NAME}
  namespace: ${HOSTED_CONTROL_PLANE_NAMESPACE}
spec:
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: ${SSH_PUB_KEY}
EOF

#wait_for_condition "infraenv/${HOSTED_CLUSTER_NAME}" "ImageCreated" "5m" "${HOSTED_CONTROL_PLANE_NAMESPACE}"
#export ISO_DOWNLOAD_URL=$(oc get -n $HOSTED_CONTROL_PLANE_NAMESPACE infraenv $HOSTED_CLUSTER_NAME -o jsonpath='{.status.isoDownloadURL}')

#echo "Apply BareMetalHost on hub"
#ansible-playbook "${playbooks_dir}/bmh-playbook.yaml"
#oc apply -f ${playbooks_dir}/generated/baremetalHost.yaml -n $HOSTED_CONTROL_PLANE_NAMESPACE
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(realpath ${__dir}/../..)"
source ${__dir}/common.sh
source ${__dir}/utils.sh
source ${__dir}/mirror_utils.sh

set -x

ASSISTED_NAMESPACE="multicluster-engine"

STORAGE_CLASS_NAME=$(oc get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

function registry_config() {
  src_image=${1}
  mirrored_image=${2}
  printf '
    [[registry]]
      location = "%s"
      insecure = false
      mirror-by-digest-only = true

      [[registry.mirror]]
        location = "%s"
  ' ${src_image} ${mirrored_image}
}

function configmap_config() {
    if [ -n "${OS_IMAGES:-}" ]; then
cat <<EOF
  OS_IMAGES: '${OS_IMAGES}'
EOF
    fi

    if [ -n "${SERVICE_BASE_URL:-}" ]; then
cat <<EOF
  SERVICE_BASE_URL: '${SERVICE_BASE_URL}'
EOF
    fi

    if [ -n "${PUBLIC_CONTAINER_REGISTRIES:-}" ]; then
cat <<EOF
  PUBLIC_CONTAINER_REGISTRIES: 'quay.io,${PUBLIC_CONTAINER_REGISTRIES}'
EOF
    fi
    if [ -n "${ALLOW_CONVERGED_FLOW:-}" ]; then
cat <<EOF
  ALLOW_CONVERGED_FLOW: '${ALLOW_CONVERGED_FLOW}'
EOF
    fi

}

function config_agentserviceconfig() {
  tee << EOCR >(oc apply -f -)
apiVersion: v1
kind: ConfigMap
metadata:
  name: assisted-service-config
  namespace: ${ASSISTED_NAMESPACE}
data:
  LOG_LEVEL: "debug"
$(configmap_config)
EOCR
  CLUSTER_VERSION=$(oc get clusterversion -o jsonpath={..desired.version} | cut -d '.' -f 1,2)

  tee << EOCR >(oc apply -f -)
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
 name: agent
 annotations:
  unsupported.agent-install.openshift.io/assisted-service-configmap: "assisted-service-config"
spec:
 databaseStorage:
  storageClassName: ${STORAGE_CLASS_NAME}
  accessModes:
  - ReadWriteOnce
  resources:
   requests:
    storage: 16Gi
 filesystemStorage:
  storageClassName: ${STORAGE_CLASS_NAME}
  accessModes:
  - ReadWriteOnce
  resources:
   requests:
    storage: 16Gi
 imageStorage:
  storageClassName: ${STORAGE_CLASS_NAME}
  accessModes:
  - ReadWriteOnce
  resources:
   requests:
    storage: 200Gi
 mirrorRegistryRef:
  name: 'assisted-mirror-config'
 osImages:
 - openshiftVersion: "${CLUSTER_VERSION}"
   version: 413.92.202307260246-0
   url: https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.13/4.13.10/rhcos-4.13.10-x86_64-live.x86_64.iso
   cpuArchitecture: x86_64
EOCR
}

function deploy_mirror_config_map() {
  oc get configmap -n openshift-config user-ca-bundle -o json | jq -r '.data."ca-bundle.crt"' > ca-bundle-crt
  cat << EOCR > ./assisted-mirror-config
apiVersion: v1
kind: ConfigMap
metadata:
  name: assisted-mirror-config
  namespace: ${ASSISTED_NAMESPACE}
  labels:
    app: assisted-service
data:
  registries.conf: |
    unqualified-search-registries = ["registry.access.redhat.com", "docker.io"]

    $(for row in $(kubectl get imagecontentsourcepolicy -o json |
        jq -rc ".items[].spec.repositoryDigestMirrors[] | [.mirrors[0], .source]"); do
      row=$(echo ${row} | tr -d '[]"');
      source=$(echo ${row} | cut -d',' -f2);
      mirror=$(echo ${row} | cut -d',' -f1);
      registry_config ${source} ${mirror};
    done)
EOCR
  python ${__dir}/set_ca_bundle.py "./ca-bundle-crt" "./assisted-mirror-config"
  tee < ./assisted-mirror-config >(oc apply -f -)
}

${__dir}/libvirt_disks.sh create

deploy_mirror_config_map
config_agentserviceconfig

wait_for_condition "agentserviceconfigs/agent" "ReconcileCompleted" "5m"
wait_for_deployment "assisted-service" "${ASSISTED_NAMESPACE}" "5m"
wait_for_pod "assisted-image-service" "${ASSISTED_NAMESPACE}" "app=assisted-image-service"

echo "Enabling configuration of BMH resources outside of openshift-machine-api namespace"
oc patch provisioning provisioning-configuration --type merge -p '{"spec":{"watchAllNamespaces": true}}'
sleep 10 # Wait for the operator to notice our patch
timeout 15m oc rollout status -n openshift-machine-api deployment/metal3
oc wait --timeout=5m pod -n openshift-machine-api -l baremetal.openshift.io/cluster-baremetal-operator=metal3-state --for=condition=Ready

echo "Configuration of Assisted Installer operator passed successfully!"

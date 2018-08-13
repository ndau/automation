#!/bin/bash
# This script sets up prometheus and grafana.
# It also includes the kubernetes app, but without any configuration or customization.
# When connecting the kubernetes app to kubernetes in grafana, you must use all authentication options.

set -e # exit on error

helm install --tls stable/prometheus --name prom \
  --set alertmanager.enabled=false \
  --set server.ingress.enabled=true \
  --set server.ingress.hosts[0]=prometheus.dev-chaos.ndau.tech

helm install --tls stable/grafana --name graf \
  --set persistence.enabled=true \
  --set persistence.size=1Gi \
  --set persistence.accessModes[0]=ReadWriteOnce \
  --set ingress.enabled=true \
  --set ingress.hosts[0]=grafana.dev-chaos.ndau.tech

# Install a workaround for version 5.1.3
# https://github.com/grafana/grafana-docker/issues/167
kubectl create --filename=- <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: grafana-chown}
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: grafana-chown
        command: [chown, -R, "472:472", /var/lib/grafana]
        image: busybox:latest
        volumeMounts:
        - {name: storage, mountPath: /var/lib/grafana}
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: graf-grafana
EOF

# wait_for_grafana waits until the pod is ready
wait_for_grafana() {
    local retries=5
	local wait_seconds=5
	local pod_name
	pod_name=$(kubectl get pods -l app=grafana,release=graf -o jsonpath='{.items[0].metadata.name}')
    for i in $(seq $retries 0); do
        local pending_test
		pending_test=$(kubectl get pod "$pod_name" | grep Running)
        if [ -z "$pending_test" ]; then

			# This will install the kubernetes app
			errcho "Installing the kubernetes app in grafana"
			kubectl exec "$pod_name" grafana-cli plugins install grafana-kubernetes-app

			errcho "Restarting the pod"
			kubectl delete pod "$pod_name"

			errcho "Reprinting connection instructions"
			helm status graf --tls

            break
        else
            errcho "grafana pod not ready. Retrying $i more times."
            sleep $wait_seconds
        fi
    done
}

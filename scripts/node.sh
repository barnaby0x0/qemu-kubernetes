#!/bin/bash
#
# Setup for Node servers

set -euxo pipefail

config_path="/vagrant/configs"
target_host="10.10.19.10"
target_port=6443
api_url="https://${target_host}:${target_port}/healthz"

# Initialize the timeout and the elapsed time counters
timeout=900  # 15 minutes in seconds
elapsed_time=0
wait_interval=10  # Check every 10 seconds

# Wait for the join.sh script to be available, or until timeout
while [[ ! -f "$config_path/join.sh" ]]; do
  if (( elapsed_time >= timeout )); then
    echo "Timeout reached waiting for join.sh. Exiting."
    exit 1
  fi
  echo "Waiting for join.sh to be available..."
  sleep $wait_interval
  ((elapsed_time += wait_interval))
done

echo "join.sh is available."

# Wait for the Kubernetes API server to be ready
while true; do
  # Check the health of the Kubernetes API
  health_status=$(curl -k --silent --max-time 5 "${api_url}" || echo "failure")
  if [[ "$health_status" == "ok" ]]; then
    echo "Kubernetes API server is ready at ${api_url}."
    break
  elif (( elapsed_time >= timeout )); then
    echo "Timeout reached waiting for Kubernetes API server to be ready. Exiting."
    exit 1
  else
    echo "Waiting for Kubernetes API server to be ready..."
    sleep $wait_interval
    ((elapsed_time += wait_interval))
  fi
done

# Proceed with executing the join.sh script
/bin/bash $config_path/join.sh -v
sleep 5
sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i $config_path/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
NODENAME=$(hostname -s)
kubectl label node $(hostname -s) node-role.kubernetes.io/worker=worker
exit 0
EOF

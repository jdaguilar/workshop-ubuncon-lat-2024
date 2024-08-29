sudo kubectl delete namespace spark

sudo microk8s kubectl-minio delete
sudo microk8s disable rbac
sudo microk8s disable storage
sudo microk8s disable storage
sudo microk8s disable hostpath-storage
sudo microk8s disable metallb

sudo snap remove microk8s --purge

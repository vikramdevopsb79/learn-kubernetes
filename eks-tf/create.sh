terraform init
terraform apply -auto-approve

aws eks update-kubeconfig --name example
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


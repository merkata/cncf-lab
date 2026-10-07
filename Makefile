.PHONY: up down status

up:
	@chmod +x bootstrap.sh
	@./bootstrap.sh

down:
	@echo "Destroying lab environment..."
	kind delete cluster --name cncf-lab

status:
	@kubectl get nodes
	@kubectl get apps -n argocd

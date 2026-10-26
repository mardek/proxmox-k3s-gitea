# DevSecOps Interview Preparation Guide

Comprehensive preparation guide for DevSecOps engineer interviews.

## Week 1: Kubernetes Fundamentals

### Day 1-2: Cluster Architecture
- Control plane components (API server, etcd, scheduler, controller manager)
- Worker node components (kubelet, container runtime, kube-proxy)
- Pod lifecycle and scheduling

### Day 3-4: Storage
- PVC/PV lifecycle
- Storage classes and provisioners
- Access modes (RWO, RWX, ROX)
- Stateful vs stateless workloads

### Day 5-7: Networking
- CNI plugins (Flannel, Calico, Cilium)
- Service types (ClusterIP, NodePort, LoadBalancer)
- Ingress and ingress controllers
- Network policies

## Week 2: AWS EKS

### EKS-Specific Topics
- IRSA (IAM Roles for Service Accounts)
- Managed Node Groups vs Fargate
- VPC CNI and pod networking
- EBS/EFS CSI drivers
- ALB Ingress Controller
- Add-ons management

### Hands-On Labs
1. Create EKS cluster with eksctl
2. Configure IRSA for S3 access
3. Deploy application with ALB ingress
4. Set up HPA and Cluster Autoscaler

## Week 3: Security

### DevSecOps Practices
- Image scanning (Trivy, Clair)
- Pod Security Standards
- Network policies
- Secrets management
- RBAC and least privilege

### Tools
- Falco for runtime security
- OPA/Gatekeeper for policy enforcement
- cert-manager for TLS

## Mock Interview Questions

1. Walk me through what happens when you run `kubectl apply`
2. How do pods get IPs in EKS?
3. How do you secure pod-to-pod traffic?
4. Explain IRSA and how it works
5. How do you handle secrets in Kubernetes?

## Resources

- Kubernetes documentation: https://kubernetes.io/docs
- EKS documentation: https://docs.aws.amazon.com/eks
- k3s documentation: https://docs.k3s.io

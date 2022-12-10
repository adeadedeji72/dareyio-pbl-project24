## Building Elastic Kubernetes Service (EKS) With Terraform ##

In this Project:
1. I used Terraform to create a Kubernetes EKS cluster and dynamically add scalable worker nodes
1. I deployed multiple applications using HELM
1. I experienced more kubernetes objects and how to use them with Helm. Such as Dynamic provisioning of volumes to make pods stateful
1. I improved my CI/CD skills with Jenkins.

### Building EKS with Terraform ###
The project instruction specify Terraform version of **1.0.5**, this is done by:
a. Download the specified version zip file
~~~
wget https://releases.hashicorp.com/terraform/1.0.5/terraform_1.0.5_linux_amd64.zip
~~~
b. Move it to a different folder (named 105 in /usr/local/tf directory in my case) apart from your existing terraform version
~~~
mv terraform_1.0.5_linux_amd64.zip /usr/local/tf/105
~~~
c. Extract the zip file here
~~~
unzip terraform_1.0.5_linux_amd64.zip
~~~
d. Create a symlink for the Terraform version in /usr/bin/ directory:
~~~
ln -s /usr/local/tf/105/terraform /usr/bin/terraform105
~~~
e. Check the version to verify success
~~~
terraform105 version
~~~
**Output**:
~~~
Terraform v1.0.5
on linux_amd64

Your version of Terraform is out of date! The latest version
is 1.3.5. You can update by downloading from https://www.terraform.io/downloads.html
~~~
1.Create a project directory with and 'cd' into it
~~~
mkdir eks && cd eks
~~~

2. Create an S3 bucket with aws cli
~~~
aws s3api create-bucket \
    --bucket bayo-project24-bucket \
    --region us-east-1
~~~

3. Create a file – backend.tf, configure it to use remote backend
~~~
terraform {
  backend "s3" {
    bucket         = "bayo-project24-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
~~~
4. Create a file – network.tf and provision Elastic IP for Nat Gateway, VPC (Create VPC using the official AWS module), Private and public subnets.
~~~
# reserve Elastic IP to be used in our NAT gateway
resource "aws_eip" "nat_gw_elastic_ip" { 
    vpc = true

tags = { 
    Name            = "${var.cluster_name}-nat-eip"
    iac_environment = var.iac_environment_tag
    }
}

module "vpc" { 
    source  = "terraform-aws-modules/vpc/aws"

    name = "${var.name_prefix}-vpc"
    cidr = var.main_network_block
    
    azs  = data.aws_availability_zones.available_azs.names
    private_subnets = [
# this loop will create a one-line list as ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20", ...]
# with a length depending on how many Zones are available
        for zone_id in data.aws_availability_zones.available_azs.zone_ids :
        cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) - 1)
        ]

        public_subnets = [
# this loop will create a one-line list as ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20", ...]
# with a length depending on how many Zones are available
# there is a zone Offset variable, to make sure no collisions are present with private subnet blocks
        for zone_id in data.aws_availability_zones.available_azs.zone_ids :
        cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) + var.zone_offset - 1)
        ]

# Enable single NAT Gateway to save some money
# WARNING: this could create a single point of failure, since we are creating a NAT Gateway in one AZ only
# feel free to change these options if you need to ensure full Availability without the need of running 'terraform apply'
# reference: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/2.44.0#nat-gateway-scenarios
        enable_nat_gateway     = true
        single_nat_gateway     = true
        one_nat_gateway_per_az = false
        enable_dns_hostnames   = true
        reuse_nat_ips          = true
        external_nat_ip_ids    = [aws_eip.nat_gw_elastic_ip.id]

# Add VPC/Subnet tags required by EKS
    tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
        iac_environment                             = var.iac_environment_tag
        }
        public_subnet_tags = {
            "kubernetes.io/cluster/${var.cluster_name}" = "shared"
            "kubernetes.io/role/elb"                    = "1"
            iac_environment                             = var.iac_environment_tag
            }
        private_subnet_tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
        "kubernetes.io/role/internal-elb"           = "1"
        iac_environment                             = var.iac_environment_tag
    }
}
~~~
**Note:** The tags added to the subnets is very important. The Kubernetes Cloud Controller Manager (cloud-controller-manager) and AWS Load Balancer Controller (aws-load-balancer-controller) needs to identify the cluster’s. To do that, it querries the cluster’s subnets by using the tags as a filter.

- For public and private subnets that use load balancer resources: each subnet must be tagged
~~~
Key: kubernetes.io/cluster/cluster-name
Value: shared
~~~
- For private subnets that use internal load balancer resources: each subnet must be tagged
~~~
Key: kubernetes.io/role/internal-elb
Value: 1
~~~
- For public subnets that use internal load balancer resources: each subnet must be tagged
~~~
Key: kubernetes.io/role/elb
Value: 1
~~~

5. Create a file – variables.tf
~~~
# create some variables
variable "cluster_name" {
    type        = string
    description = "EKS cluster name."
}

variable "iac_environment_tag" {
    type        = string
    description = "AWS tag to indicate environment name of each infrastructure object."
}

variable "name_prefix" {
    type        = string
    description = "Prefix to be used on each infrastructure object Name created in AWS."
}

variable "main_network_block" {
    type        = string
    description = "Base CIDR block to be used in our VPC."
}

variable "subnet_prefix_extension" {
    type        = number
    description = "CIDR block bits extension to calculate CIDR blocks of each subnetwork."
}

variable "zone_offset" {
    type        = number
    description = "CIDR block bits extension offset to calculate Public subnets, avoiding collisions with Private subnets."
}

# create some variables
variable "admin_users" {
  type        = list(string)
  description = "List of Kubernetes admins."
}
variable "developer_users" {
  type        = list(string)
  description = "List of Kubernetes developers."
}
variable "asg_instance_types" {
  description = "List of EC2 instance machine types to be used in EKS."
}
variable "autoscaling_minimum_size_by_az" {
  type        = number
  description = "Minimum number of EC2 instances to autoscale our EKS cluster on each AZ."
}
variable "autoscaling_maximum_size_by_az" {
  type        = number
  description = "Maximum number of EC2 instances to autoscale our EKS cluster on each AZ."
}
~~~
6. Create a file – data.tf – This will pull the available AZs for use.
~~~
data "aws_availability_zones" "available_azs" {
    state = "available"
}
data "aws_caller_identity" "current" {} # used for accesing Account ID and ARN

# get EKS cluster info to configure Kubernetes and Helm providers
data "aws_eks_cluster" "cluster" {
  name = module.eks_cluster.cluster_id
}
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.cluster_id
}
~~~
7. Create a file – eks.tf and provision EKS cluster
~~~
module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"
  cluster_name    = var.cluster_name
  cluster_version = "1.22"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access = true

  # Self Managed Node Group(s)
  self_managed_node_group_defaults = {
    instance_type                          = var.asg_instance_types[0]
    update_launch_template_default_version = true
  }
  self_managed_node_groups = local.self_managed_node_groups

  # aws-auth configmap
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  aws_auth_users = concat(local.admin_user_map_users, local.developer_user_map_users)
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}
~~~
8. Create a file – **locals.tf** to create local variables. Terraform does not allow assigning variable to variables. There is good reasons for that to avoid repeating your code unecessarily. So a terraform way to achieve this would be to use locals so that your code can be kept DRY
~~~
# render Admin & Developer users list with the structure required by EKS module
locals {
  admin_user_map_users = [
    for admin_user in var.admin_users :
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${admin_user}"
      username = admin_user
      groups   = ["system:masters"]
    }
  ]
  developer_user_map_users = [
    for developer_user in var.developer_users :
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${developer_user}"
      username = developer_user
      groups   = ["${var.name_prefix}-developers"]
    }
  ]

  self_managed_node_groups = {
    worker_group1 = {
      name = "${var.cluster_name}-wg"

      min_size      = var.autoscaling_minimum_size_by_az * length(data.aws_availability_zones.available_azs.zone_ids)
      desired_size      = var.autoscaling_minimum_size_by_az * length(data.aws_availability_zones.available_azs.zone_ids)
      max_size  = var.autoscaling_maximum_size_by_az * length(data.aws_availability_zones.available_azs.zone_ids)
      instance_type = var.asg_instance_types[0].instance_type

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            delete_on_termination = true
            encrypted             = false
            volume_size           = 10
            volume_type           = "gp2"
          }
        }
      }

      use_mixed_instances_policy = true
      mixed_instances_policy = {
        instances_distribution = {
          spot_instance_pools = 4
        }

        override = var.asg_instance_types
      }
    }
  }
}
~~~

9. Create a file – terraform.auto.tfvars to set values for variables.
~~~
cluster_name            = "tooling-app-eks"
iac_environment_tag     = "development"
name_prefix             = "darey-io-eks"
main_network_block      = "10.0.0.0/16"
subnet_prefix_extension = 4
zone_offset             = 8

# Ensure that these users already exist in AWS IAM. Another approach is that you can introduce an iam.tf file to manage users separately, get the data source and interpolate their ARN.
admin_users                    = ["darey", "solomon"]
developer_users                = ["leke", "david"]
asg_instance_types             = [ { instance_type = "t3.small" }, { instance_type = "t2.small" }, ]
autoscaling_minimum_size_by_az = 1
autoscaling_maximum_size_by_az = 10
~~~
10. Create file – provider.tf
~~~
provider "random" {
}

# get EKS authentication for being able to manage k8s objects from terraform
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
~~~
11. Run terraform init

12. Run Terraform plan – Your plan should have an output
13. Run Terraform apply
This will begin to create cloud resources, and fail at some point with the error
~~~
╷
│ Error: Post "http://localhost/api/v1/namespaces/kube-system/configmaps": dial tcp [::1]:80: connect: connection refused
│ 
│   with module.eks-cluster.kubernetes_config_map.aws_auth[0],
│   on .terraform/modules/eks-cluster/aws_auth.tf line 63, in resource "kubernetes_config_map" "aws_auth":
│   63: resource "kubernetes_config_map" "aws_auth" {
~~~
That is because for us to connect to the cluster using the kubeconfig, Terraform needs to be able to connect and set the credentials correctly.

### FIXING THE ERROR ###
- Append to the file data.tf
~~~
# get EKS cluster info to configure Kubernetes and Helm providers
data "aws_eks_cluster" "cluster" {
  name = module.eks_cluster.cluster_id
}
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.cluster_id
}
~~~
- Append to the file provider.tf
~~~
# get EKS authentication for being able to manage k8s objects from terraform
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
~~~
- Run the init and plan again, you should see something similar to:
~~~
  # module.eks-cluster.kubernetes_config_map.aws_auth[0] will be created
  + resource "kubernetes_config_map" "aws_auth" {
      + data = {
          + "mapAccounts" = jsonencode([])
          + "mapRoles"    = <<-EOT
                - "groups":
                  - "system:bootstrappers"
                  - "system:nodes"
                  "rolearn": "arn:aws:iam::696742900004:role/tooling-app-eks20210718113602300300000009"
                  "username": "system:node:{{EC2PrivateDNSName}}"
            EOT
          + "mapUsers"    = <<-EOT
                - "groups":
                  - "system:masters"
                  "userarn": "arn:aws:iam::696742900004:user/dare"
                  "username": "dare"
                - "groups":
                  - "system:masters"
                  "userarn": "arn:aws:iam::696742900004:user/solomon"
                  "username": "solomon"
                - "groups":
                  - "darey-io-eks-developers"
                  "userarn": "arn:aws:iam::696742900004:user/leke"
                  "username": "leke"
                - "groups":
                  - "darey-io-eks-developers"
                  "userarn": "arn:aws:iam::696742900004:user/david"
                  "username": "david"
            EOT
        }
      + id   = (known after apply)

      + metadata {
          + generation       = (known after apply)
          + labels           = {
              + "app.kubernetes.io/managed-by" = "Terraform"
              + "terraform.io/module"          = "terraform-aws-modules.eks.aws"
            }
          + name             = "aws-auth"
          + namespace        = "kube-system"
          + resource_version = (known after apply)
          + uid              = (known after apply)
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
~~~
14. Create kubeconfig file using awscli.
~~~
aws eks update-kubeconfig --name tooling-app-eks --region eu-west-2 --kubeconfig kubeconfig
~~~

### DEPLOY APPLICATIONS WITH HELM ###
Helm is the most popular tool used to deploy resources into kubernetes. That is because it has a rich set of features that allows deployments to be packaged as a unit. Rather than have multiple YAML files managed individually – which can quickly become messy.

A Helm chart is a definition of the resources that are required to run an application in Kubernetes. Instead of having to think about all of the various deployments/services/volumes/configmaps/ etc that make up your application, you can use a command like
~~~
helm install stable/mysql
~~~
and Helm will make sure all the required resources are installed. In addition you will be able to tweak helm configuration by setting a single variable to a particular value and more or less resources will be deployed. For example, enabling slave for MySQL so that it can have read only replicas.

Behind the scenes, a helm chart is essentially a bunch of YAML manifests that define all the resources required by the application. Helm takes care of creating the resources in Kubernetes (where they don’t exist) and removing old resources.

1. Parameterising YAML manifests using Helm templates
Let’s consider that our Tooling app have been Dockerised into an image called tooling-app, and that you wish to deploy with Kubernetes. Without helm, you would create the YAML manifests defining the **deployment**, **service**, and **ingress**, and apply them to your Kubernetes cluster using kubectl apply. Initially, your application is version 1, and so the Docker image is tagged as tooling-app:1.0.0. A simple deployment manifest might look something like the following:
~~~
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tooling-app-deployment
  labels:
    app: tooling-app
spec:
  replicas: 3
  strategy: 
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      app: tooling-app
  template:
    metadata:
      labels:
        app: tooling-app
    spec:
      containers:
      - name: tooling-app
        image: "tooling-app:1.0.0"
        ports:
        - containerPort: 80
~~~
Now lets imagine you produce another version of your app, version 1.1.0. How do you deploy that? Assuming nothing needs to be changed with the service or ingress, it may be as simple as copying the deployment manifest and replacing the image defined in the spec section. You would then re-apply this manifest to the cluster, and the deployment would be updated, performing a rolling-update as I described in my first post.

The main problem with this is that all of the values specific to your application – the labels and the image names etc – are mixed up with the "mechanical" definition of the manifest.

Helm tackles this by splitting the configuration of a chart out from its basic definition. For example, instead of baking the name of your app or the specific container image into the manifest, you can provide those when you install the chart into the cluster.

For example, a simple templated version of the previous deployment might look like the following:
~~~
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-deployment
  labels:
    app: "{{ template "name" . }}"
spec:
  replicas: 3
  strategy: 
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      app: "{{ template "name" . }}"
  template:
    metadata:
      labels:
        app: "{{ template "name" . }}"
    spec:
      containers:
      - name: "{{ template "name" . }}"
        image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: 80
~~~
This example demonstrates a number of features of Helm templates:

The template is based on YAML, with {{ }} mustache syntax defining dynamic sections.
Helm provides various variables that are populated at install time. For example, the {{.Release.Name}} allows you to change the name of the resource at runtime by using the release name. Installing a Helm chart creates a release (this is a Helm concept rather than a Kubernetes concept).
You can define helper methods in external files. The {{template "name"}} call gets a safe name for the app, given the name of the Helm chart (but which can be overridden). By using helper functions, you can reduce the duplication of static values (like tooling-app), and hopefully reduce the risk of typos.

You can manually provide configuration at runtime. The {{.Values.image.name}} value for example is taken from a set of default values, or from values provided when you call helm install. There are many different ways to provide the configuration values needed to install a chart using Helm. Typically, you would use two approaches:

A values.yaml file that is part of the chart itself. This typically provides default values for the configuration, as well as serving as documentation for the various configuration values.

When providing configuration on the command line, you can either supply a file of configuration values using the -f flag. We will see a lot more on this later on.

### Now lets setup Helm and begin to use it. ###
1. Download the tar.gz file from the project’s Github release page. Or simply use wget to download version 3.6.3 directly
~~~
wget https://github.com/helm/helm/archive/refs/tags/v3.6.3.tar.gz
~~~
2. Unpack the tar.gz file
~~~
tar -zxvf v3.6.3.tar.gz
~~~
3. cd into the unpacked directory
~~~
cd helm-3.6.3
~~~
4. Build the source code using make utility
~~~
make build
~~~
5. Helm binary will be in the bin folder. Simply move it to the bin directory on your system. You cna check other tools to know where that is. fOr example, check where pwd utility is being called from by running which pwd. Assuming the output is /usr/local/bin. You can move the helm binary there.
~~~
sudo mv bin/helm /usr/local/bin/
~~~
If maje doesn't work, follow this:
1. go to:
~~~
https://helm.sh/docs/intro/install/
~~~
2. Download the 3.6.3 binary
~~~
wget https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz
~~~
3. Untar the file
~~~
tar -zxvf helm-v3.6.3-linux-amd64.tar.gz
~~~
4. Move the binary in in /usr/local/bin
~~~
sudo mv linux-amd64/helm /usr/local/bin/helm
~~~
5. Check the installation with version check
~~~
helm version
~~~
**Output:**
~~~
version.BuildInfo{Version:"v3.6.3", GitCommit:"d506314abfb5d21419df8c7e7e68012379db2354", GitTreeState:"clean", GoVersion:"go1.16.5"}
~~~
### DEPLOY JENKINS WITH HELM ###
Before we begin to develop our own helm charts, lets make use of publicly available charts to deploy all the tools that we need.

One of the amazing things about helm is the fact that you can deploy applications that are already packaged from a public helm repository directly with very minimal configuration. An example is Jenkins.

1. Visit [Artifact Hub](https://artifacthub.io/packages/search) to find packaged applications as Helm Charts
2. Search for Jenkins
3. Add the repository to helm so that you can easily download and deploy
~~~
helm repo add jenkins https://charts.jenkins.io
~~~
4. Update helm repo
~~~
helm repo update 
~~~
5. Install the chart
~~~
helm install [RELEASE_NAME] jenkins/jenkins --kubeconfig [kubeconfig file]
~~~
Example
~~~
helm install jenkins jenkins/jenkins
~~~
**Output:**
~~~
NAME: jenkins
LAST DEPLOYED: Sat Dec 10 09:18:12 2022
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get your 'admin' user password by running:
  kubectl exec --namespace default -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
2. Get the Jenkins URL to visit by running these commands in the same shell:
  echo http://127.0.0.1:8080
  kubectl --namespace default port-forward svc/jenkins 8080:8080

3. Login with the password from step 1 and the username: admin
4. Configure security realm and authorization strategy
5. Use Jenkins Configuration as Code by specifying configScripts in your values.yaml file, see documentation: http://127.0.0.1:8080/configuration-as-code and examples: https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos

For more information on running Jenkins on Kubernetes, visit:
https://cloud.google.com/solutions/jenkins-on-container-engine

For more information about Jenkins Configuration as Code, visit:
https://jenkins.io/projects/jcasc/


NOTE: Consider using a custom image with pre-installed plugins
~~~
6. Check the Helm deployment
~~~
helm ls --kubeconfig [kubeconfig file]

helm ls --kubeconfig kubeconfig
~~~
**Output:**
~~~
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART           APP VERSION
jenkins default         1               2022-12-10 09:18:12.503476938 +0000 UTC deployed        jenkins-4.2.17  2.375.1
~~~
7. Check the pods
~~~
kubectl get pods --kubeconfig [kubeconfig file]

kubectl get pods --kubeconfig kubeconfig
~~~
**Output:**
~~~
NAME        READY   STATUS    RESTARTS   AGE
jenkins-0   2/2     Running   0          6m59s  
~~~
8. Describe the running pod (review the output and try to understand what you see)
~~~
kubectl describe pod jenkins-0 --kubeconfig [kubeconfig file]
~~~
**Output:**
~~~
Name:             jenkins-0
Namespace:        default
Priority:         0
Service Account:  jenkins
Node:             ip-10-0-37-153.eu-west-2.compute.internal/10.0.37.153
Start Time:       Sat, 10 Dec 2022 09:18:31 +0000
Labels:           app.kubernetes.io/component=jenkins-controller
                  app.kubernetes.io/instance=jenkins
                  app.kubernetes.io/managed-by=Helm
                  app.kubernetes.io/name=jenkins
                  controller-revision-hash=jenkins-55d6fd98d7
                  statefulset.kubernetes.io/pod-name=jenkins-0
Annotations:      checksum/config: 7b6cf8279a56bb7ca67e925218b2ead05ad1f60beba85964b3807af17fa9c1fe
                  kubernetes.io/psp: eks.privileged
Status:           Running
IP:               10.0.38.132
IPs:
  IP:           10.0.38.132
Controlled By:  StatefulSet/jenkins
Init Containers:

...
~~~
9. Check the logs of the running pod
~~~
kubectl logs jenkins-0 --kubeconfig [kubeconfig file]
~~~
You will notice an **error*:
~~~
Defaulted container "jenkins" out of: jenkins, config-reload, init (init)
Running from: /usr/share/jenkins/jenkins.war
2022-12-10 09:19:10.329+0000 [id=1]     INFO    winstone.Logger#logInternal: Beginning extraction from war file
2022-12-10 09:19:12.193+0000 [id=1]     WARNING o.e.j.s.handler.ContextHandler#setContextPath: Empty contextPath
2022-12-10 09:19:12.361+0000 [id=1]     INFO    org.eclipse.jetty.server.Server#doStart: jetty-10.0.12; built: 2022-09-14T01:54:40.076Z; git: 408d0139887e27a57b54ed52e2d92a36731a7e88; jvm 11.0.17+8
2022-12-10 09:19:13.117+0000 [id=1]     INFO    o.e.j.w.StandardDescriptorProcessor#visitServlet: NO JSP Support for /, did not find org.eclipse.jetty.jsp.JettyJspServlet
2022-12-10 09:19:13.284+0000 [id=1]     INFO    o.e.j.s.s.DefaultSessionIdManager#doStart: Session workerName=node0
2022-12-10 09:19:14.430+0000 [id=1]     INFO    hudson.WebAppMain#contextInitialized: Jenkins home directory: /var/jenkins_home found at: EnvVars.masterEnvVars.get("JENKINS_HOME")
2022-12-10 09:19:14.890+0000 [id=1]     INFO    o.e.j.s.handler.ContextHandler#doStart: Started w.@5a2bd7c8{Jenkins v2.375.1,/,file:///var/jenkins_cache/war/,AVAILABLE}{/var/jenkins_cache/war}
2022-12-10 09:19:14.935+0000 [id=1]     INFO    o.e.j.server.AbstractConnector#doStart: Started ServerConnector@5c10f1c3{HTTP/1.1, (http/1.1)}{0.0.0.0:8080}
2022-12-10 09:19:14.972+0000 [id=1]     INFO    org.eclipse.jetty.server.Server#doStart: Started Server@312ab28e{STARTING}[10.0.12,sto=0] @5947ms
2022-12-10 09:19:14.979+0000 [id=23]    INFO    winstone.Logger#logInternal: Winstone Servlet Engine running: controlPort=disabled
2022-12-10 09:19:15.541+0000 [id=30]    INFO    jenkins.InitReactorRunner$1#onAttained: Started initialization
2022-12-10 09:19:16.097+0000 [id=28]    INFO    hudson.PluginManager#considerDetachedPlugin: Loading a detached plugin as a dependency: /var/jenkins_home/plugins/javax-mail-api.jpi
2022-12-10 09:19:16.886+0000 [id=31]    INFO    hudson.PluginManager#considerDetachedPlugin: Loading a detached plugin as a dependency: /var/jenkins_home/plugins/sshd.jpi
2022-12-10 09:19:17.659+0000 [id=31]    INFO    hudson.PluginManager#considerDetachedPlugin: Loading a detached plugin as a dependency: /var/jenkins_home/plugins/command-launcher.jpi
2022-12-10 09:19:17.680+0000 [id=31]    INFO    hudson.PluginManager#considerDetachedPlugin: Loading a detached plugin as a dependency: /var/jenkins_home/plugins/jdk-tool.jpi
2022-12-10 09:19:19.134+0000 [id=31]    INFO    jenkins.InitReactorRunner$1#onAttained: Listed all plugins
2022-12-10 09:19:24.613+0000 [id=31]    INFO    jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
2022-12-10 09:19:24.677+0000 [id=28]    INFO    jenkins.InitReactorRunner$1#onAttained: Started all plugins
2022-12-10 09:19:24.741+0000 [id=28]    INFO    jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
WARNING: An illegal reflective access operation has occurred
WARNING: Illegal reflective access by org.codehaus.groovy.vmplugin.v7.Java7$1 (file:/var/jenkins_cache/war/WEB-INF/lib/groovy-all-2.4.21.jar) to constructor java.lang.invoke.MethodHandles$Lookup(java.lang.Class,int)
WARNING: Please consider reporting this to the maintainers of org.codehaus.groovy.vmplugin.v7.Java7$1
WARNING: Use --illegal-access=warn to enable warnings of further illegal reflective access operations
WARNING: All illegal access operations will be denied in a future release
2022-12-10 09:19:28.163+0000 [id=28]    INFO    jenkins.InitReactorRunner$1#onAttained: System config loaded
2022-12-10 09:19:28.599+0000 [id=28]    WARNING i.j.p.casc.BaseConfigurator#createAttribute: Can't handle class org.csanchez.jenkins.plugins.kubernetes.PodTemplate#listener: type is abstract but not Describable.
2022-12-10 09:19:29.515+0000 [id=28]    WARNING i.j.p.casc.BaseConfigurator#createAttribute: Can't handle class org.csanchez.jenkins.plugins.kubernetes.PodTemplate#listener: type is abstract but not Describable.
2022-12-10 09:19:30.133+0000 [id=28]    INFO    jenkins.InitReactorRunner$1#onAttained: System config adapted
2022-12-10 09:19:30.134+0000 [id=28]    INFO    jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
2022-12-10 09:19:30.154+0000 [id=30]    INFO    jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
2022-12-10 09:19:30.187+0000 [id=47]    INFO    hudson.util.Retrier#start: Attempt #1 to do the action check updates server
2022-12-10 09:19:30.211+0000 [id=28]    INFO    jenkins.InitReactorRunner$1#onAttained: Completed initialization
2022-12-10 09:19:30.284+0000 [id=22]    INFO    hudson.lifecycle.Lifecycle#onReady: Jenkins is fully up and running
2022-12-10 09:19:30.781+0000 [id=14]    INFO    i.j.p.casc.TokenReloadAction#doIndex: Configuration reload triggered via token
2022-12-10 09:19:30.852+0000 [id=14]    WARNING i.j.p.casc.BaseConfigurator#createAttribute: Can't handle class org.csanchez.jenkins.plugins.kubernetes.PodTemplate#listener: type is abstract but not Describable.
2022-12-10 09:19:31.460+0000 [id=14]    WARNING i.j.p.casc.BaseConfigurator#createAttribute: Can't handle class org.csanchez.jenkins.plugins.kubernetes.PodTemplate#listener: type is abstract but not Describable.
2022-12-10 09:19:57.864+0000 [id=47]    INFO    h.m.DownloadService$Downloadable#load: Obtained the updated data file for hudson.tasks.Maven.MavenInstaller
2022-12-10 09:19:59.019+0000 [id=47]    INFO    h.m.DownloadService$Downloadable#load: Obtained the updated data file for hudson.tools.JDKInstaller
2022-12-10 09:19:59.021+0000 [id=47]    INFO    hudson.util.Retrier#start: Performed the action check updates server successfully at the attempt #1
~~~
This is because the pod has a Sidecar container alongside with the Jenkins container. As you can see fromt he error output, there is a list of containers inside the pod [jenkins config-reload] i.e jenkins and config-reload containers. The job of the config-reload is mainly to help Jenkins to reload its configuration without recreating the pod.

Therefore we need to let kubectl know, which pod we are interested to see its log. Hence, the command will be updated like:
~~~
kubectl logs jenkins-0 -c jenkins --kubeconfig [kubeconfig file]
~~~

10. Now lets avoid calling the [kubeconfig file] everytime. Kubectl expects to find the default kubeconfig file in the location ~/.kube/config. But what if you already have another cluster using that same file? It doesn’t make sense to overwrite it. What you will do is to merge all the kubeconfig files together using a kubectl plugin called [konfig](https://github.com/corneliusweig/konfig) and select whichever one you need to be active.
    1. Install a package manager for kubectl called [krew](https://krew.sigs.k8s.io/docs/user-guide/setup/install/) so that it will enable you to install   plugins to extend the functionality of kubectl. Read more about it [Here](https://github.com/kubernetes-sigs/krew)

    2. Install the [konfig plugin](https://github.com/corneliusweig/konfig)

    (
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
   )
 
    Add the $HOME/.krew/bin directory to your PATH environment variable
    ~~~
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    ~~~
    
    3. Import the kubeconfig into the default kubeconfig file. Ensure to accept the prompt to overide.
    ~~~
    sudo kubectl konfig import --save  [kubeconfig file]
    ~~~
    
    4. Show all the contexts – Meaning all the clusters configured in your kubeconfig. If you have more than 1 Kubernetes clusters configured, you will         see them all in the output.
    ~~~
    kubectl config get-contexts
    ~~~
    **Output:**
    ~~~
    CURRENT   NAME                                                                CLUSTER                                                                     AUTHINFO                                                            NAMESPACE
    *         arn:aws:eks:eu-west-2:762376985576:cluster/tooling-app-eks          arn:aws:eks:eu-west-2:762376985576:cluster/tooling-app-eks                 arn:aws:eks:eu-west-2:762376985576:cluster/tooling-app-eks          
          arn:aws:eks:us-east-1:762376985576:cluster/terraform-eks-practice   arn:aws:eks:us-east-1:762376985576:cluster/terraform-eks-practice               arn:aws:eks:us-east-1:762376985576:cluster/terraform-eks-practice 
    ~~~
    5. Set the current context to use for all kubectl and helm commands
    ~~~
    kubectl config use-context [name of EKS cluster]
    ~~~
    **Output:**
    ~~~
    Switched to context "arn:aws:eks:eu-west-2:762376985576:cluster/tooling-app-eks".
    ~~~
    6. Test that it is working without specifying the --kubeconfig flag
    ~~~
    kubectl get po
    ~~~
    **Output:**
    ~~~
    NAME        READY   STATUS    RESTARTS   AGE
    jenkins-0   2/2     Running   0          60m
    ~~~
    7. Display the current context. This will let you know the context in which you are using to interact with Kubernetes.
    ~~~
    kubectl config current-context
    ~~~
    **Output:**
    ~~~
    arn:aws:eks:eu-west-2:762376985576:cluster/tooling-app-eks
    ~~~
11. Now that we can use kubectl without the --kubeconfig flag, Lets get access to the Jenkins UI. (In later projects we will further configure Jenkins. For now, it is to set up all the tools we need)

    1. There are some commands that was provided on the screen when Jenkins was installed with Helm. See number 5 above. Get the password to the admin          user
    ~~~
    kubectl exec --namespace default -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
    ~~~
    2. Use port forwarding to access Jenkins from the UI
    ~~~
    kubectl --namespace default port-forward svc/jenkins 8080:8080
    ~~~
    INSERT SCREENSHOT HERE
    3. Go to the browser localhost:8080 and authenticate with the username and password from number 1 above
    INSERT SCREENSHOT HERE

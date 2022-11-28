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


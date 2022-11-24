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


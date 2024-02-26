# Terraform-AWS-Three-Tier-VPC

Terraform Module to Create a Three Tier VPC on AWS

[Three-tier architecture overview](https://docs.aws.amazon.com/whitepapers/latest/serverless-multi-tier-architectures-api-gateway-lambda/three-tier-architecture-overview.html)

## Known Issues ##

* Currently NACLs cannot cross-reference subnets. So for example the NACL for the data subnets is unable to create a rule that allows ingress from the private subnet and vice versa.
* The NACLs also contain undefined locals that are dependant on upstream resources. This causes an error during apply. The current workaround for this is to comment out the NACLs and apply all the resources before the NACLs.
* The Flow Logs to CLoudWatch connector is not declared.

## Statement ##

This module **does** in fact create A VPC, Subnets, An Internet Gateway, NAT Gateways per AZ, and some NACLs, and endpoints. I tested it many times during development against my personal AWS account.

However as of now it cannot create NACLs that can cross-reference subnets.

I ran out of time before figuring out a way to solve these problems.

## Provider ##

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "companyname-test-terraform"
    key    = "terraform/test"
    region = "us-east-1"
  }
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy = "Terraform"
    }
  }
}
```

## How To Apply

1. Refer to example in `vpc/README.md`.
2. Create resource using module example.
3. Terraform apply.



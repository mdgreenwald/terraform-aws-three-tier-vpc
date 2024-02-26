# VPC Module

## Variables ##

* vpc_name | name of VPC | e.g. "three-tier-vpc"
* vpc_cidr | cidr block for vpc | e.g. "10.0.0.0/16"
* subnet_count | number of subnets of each type | e.g. 2
* subnet_mask | mask bits for subnets | e.g. 24
* public_network_acls | please see example
* private_network_acls | please see example
* data_network_acls | please see example

## Example ##

```hcl
module "three-tier-vpc" {
  source = "./modules/vpc"

  vpc_name     = "three-tier-vpc"
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 2
  subnet_mask  = 24

  public_network_acls = {
    ingress = [
      {
        rule_no    = 200
        action     = "allow"
        from_port  = 80
        to_port    = 80
        protocol   = "tcp"
      },
    ]
    egress = [
      {
        rule_no    = 200
        action     = "allow"
        from_port  = 8080
        to_port    = 8080
        protocol   = "tcp"
      },
    ]
  }

    private_network_acls = {
    ingress = [
      {
        rule_no    = 200
        action     = "allow"
        from_port  = 8080
        to_port    = 8080
        protocol   = "tcp"
      },
    ]
    egress = [
      {
        rule_no    = 200
        action     = "allow"
        from_port  = 443
        to_port    = 443
        protocol   = "tcp"
      },
      {
        rule_no    = 201
        action     = "allow"
        from_port  = 3306
        to_port    = 3306
        protocol   = "tcp"
      },
    ]
  }

    data_network_acls = {
    ingress = [
      {
        rule_no    = 200
        action     = "allow"
        from_port  = 3306
        to_port    = 3306
        protocol   = "tcp"
      },
    ]
    egress = [
      {
        rule_no    = 200
        action     = "deny"
        from_port  = 0
        to_port    = 0
        protocol   = "tcp"
      },
    ]
  }


}

```
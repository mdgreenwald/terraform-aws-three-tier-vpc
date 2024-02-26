variable "vpc_name" {
  description = "The name for the VPC"
  type        = string
  default     = "three-tier-vpc"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_-]*$", var.vpc_name))
    error_message = "The vpc_name must start with a letter or underscore, and only contain letters, digits, underscores, and dashes."
  }
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = length(split("/", var.vpc_cidr)) == 2 && element(split("/", var.vpc_cidr), 1) == "16"
    error_message = "The CIDR block must have a /16 range."
  }
}

variable "subnet_count" {
  description = "Number for each subnet type"
  default     = 2
  type        = number

  validation {
    condition     = var.subnet_count >= 1 && var.subnet_count <= 3 && floor(var.subnet_count) == var.subnet_count
    error_message = "The specified value must be an integer between 1 and 3."
  }
}


variable "subnet_mask" {
  description = "The subnet_mask for the subnets"
  default     = 24
  type        = number

  validation {
    condition     = var.subnet_mask >= 18 && var.subnet_mask <= 30
    error_message = "The subnet_mask value must be a number between 18 and 30."
  }
}

variable "public_network_acls" {
  description = "Map of network ACLs"
  type = map(list(object({
    rule_no   = number
    action    = string
    from_port = number
    to_port   = number
    protocol  = string
    icmp_type = optional(number)
    icmp_code = optional(number)
    subnet    = optional(string)
  })))

  default = {
    ingress = [
      {
        rule_no   = 110
        action    = "allow"
        from_port = 0
        to_port   = 0
        protocol  = "-1"
      },
    ]
    egress = [
      {
        rule_no   = 110
        action    = "allow"
        from_port = 0
        to_port   = 0
        protocol  = "-1"
      },
    ]
  }
}

variable "private_network_acls" {
  description = "Map of network ACLs"
  type = map(list(object({
    rule_no   = number
    action    = string
    from_port = number
    to_port   = number
    protocol  = string
    icmp_type = optional(number)
    icmp_code = optional(number)
    subnet    = optional(string)
  })))

  default = {
    ingress = [
      {
        rule_no   = 110
        action    = "allow"
        from_port = 0
        to_port   = 0
        protocol  = "-1"
      },
    ]
    egress = [
      {
        rule_no   = 110
        action    = "allow"
        from_port = 0
        to_port   = 0
        protocol  = "-1"
      },
    ]
  }
}

variable "data_network_acls" {
  description = "Map of network ACLs"
  type = map(list(object({
    rule_no   = number
    action    = string
    from_port = number
    to_port   = number
    protocol  = string
    icmp_type = optional(number)
    icmp_code = optional(number)
    subnet    = optional(string)
  })))

  default = {
    ingress = [
      {
        rule_no   = 110
        action    = "allow"
        from_port = 0
        to_port   = 0
        protocol  = "-1"
      },
    ]
    egress = [
      {
        rule_no   = 110
        action    = "allow"
        from_port = 0
        to_port   = 0
        protocol  = "-1"
      },
    ]
  }
}

locals {
  #  Splitting a network address into several subnets, the number and sizes of which are determined by the new_bits attributes of objects in the networks local value.
  addrs_by_idx = cidrsubnets(var.vpc_cidr, local.networks[*].new_bits...)

  az_count = length(data.aws_availability_zones.available.names)

  # Generates an array of objects, where each object represents a subnet and has a name and new_bits.
  networks = flatten([
    for st, counts in local.subnet_types : [
      for i in counts : {
        name     = "${st}-${i}"
        new_bits = var.subnet_mask - 16
      }
    ]
  ])

  # Each key is a network name, and the corresponding value is an object with the same name and a CIDR block associated with the network.
  network_objs = { for i, n in local.networks : "${n.name}" => {
    name       = n.name
    cidr_block = local.addrs_by_idx[i]
  } }

  # Each one maps a subnet ID (as a string) to an object containing the ID and CIDR block of a certain type of AWS subnet.
  subnets = {
    public  = { for n, v in aws_subnet.public_subnets : n => { id : tostring(v.id), cidr_block : v.cidr_block } },
    private = { for n, v in aws_subnet.private_subnets : n => { id : tostring(v.id), cidr_block : v.cidr_block } },
    data    = { for n, v in aws_subnet.data_subnets : n => { id : tostring(v.id), cidr_block : v.cidr_block } },
  }

  # A map that lists numbers from 1 to var.subnet_count + 1 under three keys: public, private, and data
  subnet_types = tomap({
    "public"  = range(1, var.subnet_count + 1)
    "private" = range(1, var.subnet_count + 1)
    "data"    = range(1, var.subnet_count + 1)
  })

  # Generates a map of rule numbers, CIDR blocks, and IDs for each type of subnet: public, private, and data. Each entry is labeled as "subnet-{number}", where {number} starts from 1.
  rule_numbers = {
    for type, nets in local.subnets : type =>
    {
      for i in range(var.subnet_count) : format("subnet-%d", i + 1) => {
        rule_number : i + 100,
        cidr_block : try(nets[keys(nets)[i]].cidr_block, null),
        id : try(nets[keys(nets)[i]].id, null)
      }
    }
  }

  # Generates a map of rule numbers, CIDR blocks, and IDs for each type of subnet: public, private, and data. Each entry is labeled as "subnet-{number}", where {number} starts from 1.
  rule_numbers_dynamic = {
    for type, nets in local.subnets : type =>
    {
      for i in range(var.subnet_count) : nets[keys(nets)[i]].id => merge(
        {
          rule_number : i + 110
        },
        {
          cidr_block : nets[keys(nets)[i]].cidr_block
        }
      )
    }
  }

}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.vpc_name}"
  }
}

# Purge rules from default security group.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-default-sg"
  }

}

# Purge rules from default NACL and detach from subnets.
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.vpc.default_network_acl_id

  tags = {
    Name = "${var.vpc_name}-default-nacl"
  }

}


###
# SUBNETS
###

resource "aws_subnet" "public_subnets" {
  for_each = { for k, n in local.network_objs : k => n if substr(k, 0, 6) == "public" }

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[tonumber(substr(each.key, 7, length(each.key))) % local.az_count]

  tags = {
    Name = "${var.vpc_name}-${each.key}"
  }
}

resource "aws_subnet" "private_subnets" {
  for_each = { for k, n in local.network_objs : k => n if substr(k, 0, 7) == "private" }

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[tonumber(substr(each.key, 8, length(each.key))) % local.az_count]

  tags = {
    Name = "${var.vpc_name}-${each.key}"
  }
}

resource "aws_subnet" "data_subnets" {
  for_each = { for k, n in local.network_objs : k => n if substr(k, 0, 4) == "data" }

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[tonumber(substr(each.key, 5, length(each.key))) % local.az_count]

  tags = {
    Name = "${var.vpc_name}-${each.key}"
  }
}

###
# PUBLIC SUBNET RESOURCES
###

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}-rtb-public"
  }
}

resource "aws_route_table_association" "public_subnets_rtas" {
  for_each = aws_subnet.public_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.vpc.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = tomap({ for s in aws_subnet.public_subnets : substr(s.availability_zone, -1, 1) => s })

  domain = "vpc"

  tags = {
    Name = "${var.vpc_name}-eip-nat-${each.key}"
  }
}

resource "aws_nat_gateway" "nat" {
  for_each = { for s in aws_subnet.public_subnets : substr(s.availability_zone, -1, 1) => s }

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags = {
    Name = "${var.vpc_name}-nat-${each.key}"
  }
}

###
# PRIVATE SUBNET RESOURCES
###

resource "aws_route_table" "private-rtb" {
  for_each = tomap({ for s in aws_subnet.private_subnets : substr(s.availability_zone, -1, 1) => s })

  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-private-rtb-${each.key}"
  }
}

resource "aws_route" "private_nat_gateways" {
  for_each = tomap({ for s in aws_subnet.private_subnets : substr(s.availability_zone, -1, 1) => s })

  route_table_id         = aws_route_table.private-rtb[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[each.key].id

  depends_on = [aws_nat_gateway.nat, aws_route_table.private-rtb]
}

resource "aws_route_table_association" "private-assoc" {
  for_each = tomap({ for s in aws_subnet.private_subnets : substr(s.availability_zone, -1, 1) => s })

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private-rtb[each.key].id

  depends_on = [aws_route_table.private-rtb]
}


###
# DATA SUBNET RESOURCES
###

resource "aws_route_table" "data-rtb" {
  for_each = tomap({ for s in aws_subnet.data_subnets : substr(s.availability_zone, -1, 1) => s })

  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-data-rtb-${each.key}"
  }
}

resource "aws_route" "data_nat_gateways" {
  for_each = tomap({ for s in aws_subnet.data_subnets : substr(s.availability_zone, -1, 1) => s })

  route_table_id         = aws_route_table.data-rtb[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[each.key].id

  depends_on = [aws_nat_gateway.nat, aws_route_table.data-rtb]
}

resource "aws_route_table_association" "data-assoc" {
  for_each = tomap({ for s in aws_subnet.data_subnets : substr(s.availability_zone, -1, 1) => s })

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data-rtb[each.key].id

  depends_on = [aws_route_table.data-rtb]
}

###
# ACLS
###

resource "aws_network_acl" "public_acl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = [for s in aws_subnet.public_subnets : s.id]

  tags = {
    Name = "${var.vpc_name}-public-nacl"
  }

  depends_on = [aws_subnet.public_subnets]

}

resource "aws_network_acl_rule" "public_net_acl_ingress" {
  for_each       = { for k, v in local.rule_numbers.public : k => v if v.id != null }
  network_acl_id = aws_network_acl.public_acl.id
  protocol       = "-1"
  rule_number    = each.value.rule_number
  rule_action    = "allow"
  egress         = false
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "public_net_acl_egress" {
  for_each       = { for k, v in local.rule_numbers.public : k => v if v.id != null }
  network_acl_id = aws_network_acl.public_acl.id
  protocol       = "-1"
  rule_number    = each.value.rule_number + length(local.rule_numbers.public)
  rule_action    = "allow"
  egress         = true
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "public_acl_dynamic_ingress" {
  for_each = local.rule_numbers_dynamic.public

  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = var.public_network_acls["ingress"][0]["protocol"]
  rule_action    = var.public_network_acls["ingress"][0]["action"]
  cidr_block     = each.value.cidr_block
  from_port      = var.public_network_acls["ingress"][0]["from_port"]
  to_port        = var.public_network_acls["ingress"][0]["to_port"]
}

resource "aws_network_acl_rule" "public_acl_dynamic_egress" {
  for_each = local.rule_numbers_dynamic.public

  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = var.public_network_acls["egress"][0]["protocol"]
  rule_action    = var.public_network_acls["egress"][0]["action"]
  cidr_block     = each.value.cidr_block
  from_port      = var.public_network_acls["egress"][0]["from_port"]
  to_port        = var.public_network_acls["egress"][0]["to_port"]
}


resource "aws_network_acl" "private_acl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = [for s in aws_subnet.private_subnets : s.id]

  tags = {
    Name = "${var.vpc_name}-private-nacl"
  }

  depends_on = [aws_subnet.private_subnets]

}

resource "aws_network_acl_rule" "private_net_acl_ingress" {
  for_each       = local.rule_numbers.private
  network_acl_id = aws_network_acl.private_acl.id
  protocol       = "-1"
  rule_number    = each.value.rule_number
  rule_action    = "allow"
  egress         = false
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "private_net_acl_egress" {
  for_each       = local.rule_numbers.private
  network_acl_id = aws_network_acl.private_acl.id
  protocol       = "-1"
  rule_number    = each.value.rule_number + length(local.rule_numbers.private)
  rule_action    = "allow"
  egress         = true
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "private_acl_dynamic_ingress" {
  for_each = local.rule_numbers_dynamic.private

  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = var.private_network_acls["ingress"][0]["protocol"]
  rule_action    = var.private_network_acls["ingress"][0]["action"]
  cidr_block     = each.value.cidr_block
  from_port      = var.private_network_acls["ingress"][0]["from_port"]
  to_port        = var.private_network_acls["ingress"][0]["to_port"]
}

resource "aws_network_acl_rule" "private_acl_dynamic_egress" {
  for_each = local.rule_numbers_dynamic.private

  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = var.private_network_acls["egress"][0]["protocol"]
  rule_action    = var.private_network_acls["egress"][0]["action"]
  cidr_block     = each.value.cidr_block
  from_port      = var.private_network_acls["egress"][0]["from_port"]
  to_port        = var.private_network_acls["egress"][0]["to_port"]
}

resource "aws_network_acl" "data_acl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = [for s in aws_subnet.data_subnets : s.id]

  tags = {
    Name = "${var.vpc_name}-data-nacl"
  }

  depends_on = [aws_subnet.data_subnets]

}

resource "aws_network_acl_rule" "data_net_acl_ingress" {
  for_each       = local.rule_numbers.data
  network_acl_id = aws_network_acl.data_acl.id
  protocol       = "-1"
  rule_number    = each.value.rule_number
  rule_action    = "allow"
  egress         = false
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "data_net_acl_egress" {
  for_each       = local.rule_numbers.data
  network_acl_id = aws_network_acl.data_acl.id
  protocol       = "-1"
  rule_number    = each.value.rule_number + length(local.rule_numbers.data)
  rule_action    = "allow"
  egress         = true
  cidr_block     = each.value.cidr_block
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "data_acl_dynamic_ingress" {
  for_each = local.rule_numbers_dynamic.data

  network_acl_id = aws_network_acl.data_acl.id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = var.data_network_acls["ingress"][0]["protocol"]
  rule_action    = var.data_network_acls["ingress"][0]["action"]
  cidr_block     = each.value.cidr_block
  from_port      = var.data_network_acls["ingress"][0]["from_port"]
  to_port        = var.data_network_acls["ingress"][0]["to_port"]
}

resource "aws_network_acl_rule" "data_acl_dynamic_egress" {
  for_each = local.rule_numbers_dynamic.data

  network_acl_id = aws_network_acl.data_acl.id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = var.data_network_acls["egress"][0]["protocol"]
  rule_action    = var.data_network_acls["egress"][0]["action"]
  cidr_block     = each.value.cidr_block
  from_port      = var.data_network_acls["egress"][0]["from_port"]
  to_port        = var.data_network_acls["egress"][0]["to_port"]
}

###
# ENDPOINTS
###

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [for s in aws_route_table.private-rtb : s.id]

  tags = {
    Name = "fargate-vpce-s3"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3_private_endpoint_association" {
  for_each = aws_route_table.private-rtb

  route_table_id  = each.value.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id

}

resource "aws_vpc_endpoint" "ecr_api" {
  for_each          = aws_subnet.private_subnets
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type = "Interface"

  subnet_ids = [each.value.id]

  tags = {
    Name = "${var.vpc_name}-vpce-ecr-api-${each.key}"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  for_each          = aws_subnet.private_subnets
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  subnet_ids = [each.value.id]

  tags = {
    Name = "${var.vpc_name}-vpce-ecr-dkr-${each.key}"
  }
}

###
# OUTPUTS
###

output "public_subnets_cidrs" {
  description = "The CIDR blocks of the public subnets"
  value       = [for s in aws_subnet.public_subnets : s.cidr_block]
}

output "private_subnets_cidrs" {
  description = "The CIDR blocks of the private subnets"
  value       = [for s in aws_subnet.private_subnets : s.cidr_block]
}

output "data_subnets_cidrs" {
  description = "The CIDR blocks of the data subnets"
  value       = [for s in aws_subnet.data_subnets : s.cidr_block]
}
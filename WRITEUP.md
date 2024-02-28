# Writeup

Terraform Module to Create a Three Tier VPC on AWS

* [Three-tier architecture overview](https://docs.aws.amazon.com/whitepapers/latest/serverless-multi-tier-architectures-api-gateway-lambda/three-tier-architecture-overview.html)

* [Private Network](https://en.wikipedia.org/wiki/Private_network)

## Part One - Proposed Solution

Based on the above document from AWS and the technical requirements from Phillps I am proposing to create a parent/child terraform module that creates a VPC and Subnets that are striped across between one and three availibility zones. One subnet of each type; public, private, and data (3) per availibility zone. Subnets also require routing tables which will also be created. Then the module will create NACLs to constrain traffic between the subnets.

In AWS, Routing tables are created with a local route that allows traffic to/from the VPC CIDR range. If this fact is ignored, this will negate the benefit of the three tier architecture because any subnet in the VPC can reach any other subnet. This is where the NACLs come in to play.

There will also need to be Internet and NAT Gateways to allow traffic to the public internet. Additional resources will include service endpoints and VPC Flow Logs.

The VPC will use a /16 netmask which allows for 65,536 hosts (Except for broadcast and network addresses on subnets). Subnets by default will use /24 netmasks which allow for 256 hosts per subnet, again minus broadcast and net addresses. I personally would use a /22 (1024) instead of /24 which gives each subnet a bit more room to grow in terms of resources.

## Part Three - Development Experience

So at the outset I began by creating the folder structure for the module by following Terraforms [reccomendations](https://developer.hashicorp.com/terraform/language/modules/develop/structure).

I started writing the module by creating each resource in terms of depdency  hierarchy, so for example the VPC must come before the Subnets, and the Subnets must come before the Internet Gateway and so on.

I also chose early on to leverage the terraform [`cidrsubnets`](https://developer.hashicorp.com/terraform/language/functions/cidrsubnets) function. This may or may not have been a fundamental mistake in my approach. Without having attempted this, another approach may have been to use a map and arithmetic to create the subnets--the map being more easily referenced later by the `for_each` functions.

I can't find it now but there is an old blog post about how everything is infinitely complex, the author uses building a simple staircase in a house as his example but then goes into detail about how many hidden intricies lie in wait for you to find as you work through the project. This VPC module with NACLs was of course no different.

### NAT Gateways

This is the first hurdle with using `for_each`. Because you can't key off the subents alone you must also consider availibilty zones, otherwise you might end up with 1 subnet that contains multiple EIPs and NAT Gateways. That would be a big waste on an already [infamously expensive AWS Resource](https://duckduckgo.com/?t=ffab&q=why+are+aws+nat+gateways+so+expensive&ia=web). So I spent a bit of time on this part to address this.

```HCL
for_each = { for s in aws_subnet.public_subnets : substr(s.availability_zone, -1, 1) => s }
```

### NACLS

I think the NACLs are the throniest part of the entire project and where I spent most of my time and struggled quite a bit. It would be one thing to have NACLs that are hard coded into the module and that might be acceptable if the module is only to be used by one team in one company in perpetuity--but if its going to be generalized the NACLs need to be configurable.

The other aspect of the NACLs that makes them thorny is the Rule Number. These need to be incremented because overlapping numbers will override the previous directive. This is because they are processed in order. So if you have `100 DENY ALL` but then `100 ALLOW ALL` you will be left with `ALLOW ALL`. However incrementing them and also using a `for_each` which prevents the use of `count` is quite trickey indeed and then add to that the variablity of user defined rules where we don't know the length of the rule set being configured by the user. This is really the crux of the complexity of this challenge in my opinion.

### Epilogue

I think if I resorted to hard coded NACLs and just wrote about that in the epilogue I might have been able to deliver a complete working module with all the other requirements. However I was extremely determined to figure the user configurable NACLs out and I spent all my time on them, perhaps to my detriment.

Another way NACLs could be addressed is with a separate child module taking a similar approach to the [ECS container definition](https://github.com/terraform-aws-modules/terraform-aws-ecs/blob/master/modules/container-definition/main.tf) which basically lets the end user pass HCL encoded JSON into the API. So instead we would in let the end user write all their rules and we just use that to define the NACLs instead of the gymnastics that I attempted to try to abstract the rules away.

Overall this was a fun and interesting engineering problem! I learned a ton about terraform along the way which only helps me become better at writing terraform.
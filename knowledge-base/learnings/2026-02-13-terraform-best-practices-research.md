# Terraform Module Structure and Best Practices Research

**Date:** 2026-02-13
**Context:** Research for SRE agent implementation (feat-sre-agent)
**Source:** HashiCorp official documentation, AWS/Azure best practices, community standards (2024-2026)

## Executive Summary

This document captures current Terraform best practices for module structure, file organization, variable/output design, state management, and naming conventions. These patterns inform the SRE agent's code generation and review capabilities.

## 1. File Organization Conventions

### Single vs Split Files

**Rule of thumb:** Use single `main.tf` for simple modules. Split into logical files when navigation becomes difficult due to size.

**Standard split patterns:**

1. **By component type:**
   - `network.tf` - VPC, subnets, load balancers, networking resources
   - `compute.tf` - EC2 instances, auto-scaling groups
   - `storage.tf` - S3, EBS, object storage
   - `database.tf` - RDS, DynamoDB tables
   - `security.tf` - Security groups, IAM roles, policies

2. **By service:**
   - One file per business service (e.g., `web-app.tf`, `api-gateway.tf`)
   - Contains all resources for that service (compute, network, storage)

**Key principle:** No matter how you split, it must be immediately clear where to find a specific resource definition.

### Example HCL: Split File Structure

```hcl
# network.tf
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpc"
    }
  )
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-${count.index + 1}"
      Tier = "Public"
    }
  )
}
```

```hcl
# compute.tf
resource "aws_instance" "web" {
  count         = var.instance_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[count.index % length(aws_subnet.public)].id

  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user-data.sh", {
    environment = var.environment
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-web-${count.index + 1}"
    }
  )
}
```

## 2. Standard Module Structure

### Required Files

**Root module (minimum):**
- `main.tf` - Primary entrypoint, resource creation, module calls
- `variables.tf` - Input variable declarations
- `outputs.tf` - Output value declarations
- `versions.tf` (or `terraform.tf`) - Provider and Terraform version constraints
- `README.md` - Documentation

### Example HCL: versions.tf

```hcl
terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
```

### Nested Modules

Place under `modules/` subdirectory. Any nested module with `README.md` is considered public/usable by external users. Modules without README are internal-only.

**Example structure:**
```
my-terraform-project/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
└── modules/
    ├── networking/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── README.md
    └── compute/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf  # No README = internal-only
```

## 3. Variable Design

### Naming Conventions

- **Format:** `snake_case` (all lowercase with underscores)
- **Plurals:** Use plural form when type is `list(...)` or `map(...)`
- **Units:** Include units for numeric values: `ram_size_gb`, `timeout_seconds`
- **Avoid negatives:** Use positive names (`enable_monitoring` not `disable_monitoring`)

### Variable Block Structure

**Required elements:** `description`, `type`. Optional: `default`, `validation`, `sensitive`.

**Ordering:** description, type, default, validation.

### Example HCL: Variables with Validation

```hcl
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t[23]\\.(nano|micro|small|medium|large)$", var.instance_type))
    error_message = "Only t2/t3 instance types (nano to large) are allowed for cost control."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for subnet placement"
  type        = list(string)
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
  }
}

variable "ssh_config" {
  description = "SSH configuration for remote access"
  type = object({
    username        = string
    public_key_path = string
    port            = number
  })
  default = {
    username        = "ubuntu"
    public_key_path = "~/.ssh/id_rsa.pub"
    port            = 22
  }
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  # NEVER define a default for secrets
}
```

### Type Constraints

**Simple types:** `string`, `number`, `bool`

**Collection types:**
- `list(string)` - Ordered collection of strings
- `map(string)` - Key-value pairs
- `set(string)` - Unordered unique values

**Structural types:**
- `object({...})` - Fixed schema with typed attributes
- `tuple([...])` - Fixed-length list with typed elements
- `any` - Disable type validation (use sparingly)

**Best practice:** Prefer simple types over `object()` unless strict constraints are needed on each key.

### Terraform 1.9+ Cross-Variable Validation

Since Terraform 1.9, validation blocks can reference other variables, data sources, and local values:

```hcl
variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string

  validation {
    condition     = cidrsubnet(var.vpc_cidr, 8, 0) != var.subnet_cidr || can(cidrsubnet(var.vpc_cidr, 8, 1))
    error_message = "Subnet CIDR must be within the VPC CIDR range."
  }
}
```

## 4. Output Design

### Naming Conventions

- **Format:** `snake_case`
- **Pattern:** `{resource_name}_{attribute}` (e.g., `vpc_id`, `alb_dns_name`)
- **Plurals:** Use plural names for list outputs
- **Avoid interpolation in names:** Keep output names simple and predictable

### Output Block Structure

**Required:** `value`, `description`. Optional: `sensitive`.

**Best practice:** For every resource in a reusable module, include at least one output. This enables dependency inference between modules.

### Example HCL: Outputs

```hcl
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "web_instance_private_ips" {
  description = "Private IP addresses of web server instances"
  value       = aws_instance.web[*].private_ip
}

output "security_group_id" {
  description = "ID of the security group for web servers"
  value       = aws_security_group.web.id
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.main.dns_name
}

output "db_connection_string" {
  description = "Database connection string (password excluded)"
  value       = "postgresql://${aws_db_instance.main.username}@${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}"
  sensitive   = true
}
```

## 5. State Management

### Backend Options

**AWS (S3 + DynamoDB):**
- S3 Standard: 99.999999999% durability, 99.99% availability
- DynamoDB state locking (deprecated in Terraform 1.10+)
- S3 native state locking (recommended since Terraform 1.10)

**Terraform Cloud/HCP:**
- SaaS platform with built-in state management
- Access controls, policy checks, collaboration features
- Optimal for teams prioritizing security/governance over self-hosting

**Consul:**
- Distributed key-value store
- Suitable for multi-datacenter setups
- Requires Consul infrastructure

### Example HCL: S3 Backend with Native Locking

```hcl
# backend.tf (Terraform 1.10+)
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "projects/web-app/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true  # S3 native locking (recommended)

    # Optional: DynamoDB for legacy locking
    # dynamodb_table = "terraform-state-lock"
  }
}
```

### Example HCL: S3 Backend with DynamoDB Locking (Legacy)

```hcl
# backend.tf (Pre-1.10 or compatibility)
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "projects/web-app/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Security hardening
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }
}
```

### Backend Best Practices

1. **Environment isolation:** Use distinct backends per environment (dev/staging/prod)
2. **State bucket security:**
   - Enable versioning for rollback
   - Enable encryption at rest
   - Restrict IAM access (read-only for most users)
   - Enable CloudTrail logging for audit trail
3. **Access control:**
   - Production state: read-only for humans, write access for CI/CD only
   - Use break-glass roles for emergency access
4. **State file structure:**
   - Pattern: `s3://bucket-name/project/environment/component/terraform.tfstate`
   - Example: `s3://infra-state/web-app/prod/networking/terraform.tfstate`

### Backend Initialization

```bash
# Initialize backend
terraform init

# Migrate existing local state to S3
terraform init -migrate-state

# Reconfigure backend
terraform init -reconfigure
```

## 6. Workspace Strategies

### Workspaces vs Directory-Per-Environment

**Workspaces:**
- One codebase, multiple state files
- Switch with `terraform workspace select <name>`
- Good for: Identical infrastructure across environments
- Limitations: Shared backend, same credentials, weak isolation

**Directory-per-environment:**
- Separate folder per environment with own config/state
- Strong isolation, different credentials, unique policies
- Better CI/CD integration (per-directory pipelines)
- Recommended for: Prod vs non-prod separation

**Hybrid approach:**
- Separate directories for major tiers (dev, staging, prod)
- Workspaces within directories for variations (staging-us, staging-eu)

### Example: Directory-Per-Environment

```
terraform/
├── dev/
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── backend.tf  # backend key: "dev/terraform.tfstate"
├── staging/
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── backend.tf  # backend key: "staging/terraform.tfstate"
└── prod/
    ├── main.tf
    ├── variables.tf
    ├── terraform.tfvars
    └── backend.tf  # backend key: "prod/terraform.tfstate"
```

### Example: Workspace Usage

```bash
# Create workspace
terraform workspace new staging

# List workspaces
terraform workspace list

# Select workspace
terraform workspace select prod

# Use workspace name in config
resource "aws_instance" "web" {
  tags = {
    Environment = terraform.workspace
  }
}
```

### HashiCorp Recommendation

**Formula:** Terraform configurations × environments = workspaces

One workspace per environment of a given infrastructure component. For strong isolation (different credentials, access controls), use separate configurations (directories) instead of CLI workspaces.

## 7. Version Constraints

### Terraform Core Version

**Syntax:** Use `~>` (pessimistic constraint) to allow patch updates.

```hcl
terraform {
  required_version = "~> 1.9"  # 1.9.0 <= version < 2.0.0
}
```

**Best practice:** Pin major.minor, allow patch. Set both minimum (feature compatibility) and maximum (future-proofing).

### Provider Versions

**Syntax:** Version constraint operators:
- `=` - Exact version (maximum stability)
- `~>` - Allow rightmost version component to increment
- `>=`, `<=`, `>`, `<` - Comparison operators
- `,` - Combine constraints (AND logic)

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # 5.0.x updates allowed
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5, < 4.0"
    }
  }
}
```

**Best practice:**
- Production: Use `~>` to allow patch updates, prevent minor/major changes
- Root modules: Set upper bounds to avoid incompatible upgrades
- Every provider should have an explicit version constraint

### Dependency Lock File

`.terraform.lock.hcl` ensures reproducible provider installations.

```bash
# Generate/update lock file
terraform init

# Commit to version control
git add .terraform.lock.hcl

# Upgrade providers
terraform init -upgrade
```

**Best practice:** Commit lock file to version control for reproducibility across team/CI.

## 8. Naming Conventions

### Resource Names (Terraform identifiers)

- **Format:** `snake_case` (lowercase with underscores)
- **Pattern:** Noun-based, no type prefix
- **Example:** `resource "aws_instance" "web"` (not `aws_instance_web`)

### Resource Naming (Cloud provider names)

**Consistent pattern:** `<prefix>-<project>-<env>-<resource>-<location>-<description>`

**Example patterns:**
- AWS: `mycompany-webapp-prod-alb-us-east-1`
- Azure: `mycompany-prod-eastus-app-rg`
- Hetzner: `mycompany-api-staging-cx21-fsn1`

### Naming with Locals

```hcl
locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  resource_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CostCenter  = var.cost_center
  }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = merge(
    local.resource_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}
```

### Tagging Strategies

**Common tags (apply to all resources):**
- `Environment` - dev, staging, prod
- `Project` - Project or application name
- `ManagedBy` - Terraform (or tool name)
- `Owner` - Team or email
- `CostCenter` - For cost allocation

**Best practice:** Define tags in `locals`, use `merge()` for resource-specific additions.

```hcl
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Owner       = "platform-team@example.com"
    CostCenter  = var.cost_center
  }
}

resource "aws_instance" "web" {
  # ... other config ...

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-web-${count.index + 1}"
      Role = "WebServer"
    }
  )
}
```

### Provider-Specific Naming

**AWS:**
- Use hyphen-separated lowercase
- Include region for global resources (S3 buckets)
- Pattern: `{org}-{project}-{env}-{resource}-{region}`

**Azure:**
- Follow Cloud Adoption Framework naming conventions
- Resource group: `{company}-{env}-{location}-{purpose}-rg`
- Storage account: `{company}{project}{env}sa` (no hyphens, max 24 chars)

**Hetzner:**
- Use hyphen-separated lowercase
- Include datacenter location: `fsn1`, `nbg1`, `hel1`
- Pattern: `{project}-{env}-{resource}-{location}`

## 9. Module Composition Patterns

### Composable Modules

**Anti-pattern:** Monolithic module that creates everything (VPC, subnets, instances, databases)

**Best practice:** Small, single-purpose modules that receive dependencies from root module.

```hcl
# main.tf (root module)

module "networking" {
  source = "./modules/networking"

  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b"]
  environment         = "prod"
}

module "compute" {
  source = "./modules/compute"

  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.public_subnet_ids
  instance_count     = 3
  instance_type      = "t3.medium"
  environment        = "prod"
}

module "database" {
  source = "./modules/database"

  vpc_id                 = module.networking.vpc_id
  subnet_ids             = module.networking.private_subnet_ids
  allowed_security_groups = [module.compute.security_group_id]
  environment            = "prod"
}
```

**Benefits:**
- Independent versioning per module
- Easier testing and reuse
- Clear dependency graph
- Flexibility in composition

## 10. Security Best Practices (IaC-Specific)

### Secrets Management

**Never do this:**
```hcl
# BAD: Hardcoded secrets
variable "db_password" {
  default = "supersecret123"  # NEVER DO THIS
}
```

**Do this:**
```hcl
# GOOD: No default, marked sensitive
variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  # No default - must be provided at runtime
}
```

**Runtime secret injection:**
```bash
# From environment
export TF_VAR_db_password="$(aws secretsmanager get-secret-value --secret-id prod/db/password --query SecretString --output text)"
terraform apply

# From file (add to .gitignore)
terraform apply -var-file=secrets.tfvars
```

### Public Exposure Checks

**Common issues to flag:**
- S3 buckets with public ACLs
- Security groups with `0.0.0.0/0` on non-standard ports
- RDS instances with `publicly_accessible = true`
- Overly permissive IAM policies (`Action: "*"`, `Resource: "*"`)

### Example: Secure S3 Bucket

```hcl
resource "aws_s3_bucket" "app_data" {
  bucket = "${local.name_prefix}-app-data"

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

## 11. Cost Optimization Patterns

### Instance Sizing Guidelines

**Hetzner Cloud (2024 pricing - verify current):**
- CX22 (2 vCPU, 4GB RAM): ~$5.83/month - Good for small apps
- CX32 (4 vCPU, 8GB RAM): ~$11.66/month - Medium workloads
- CX42 (8 vCPU, 16GB RAM): ~$23.33/month - Larger workloads

**AWS EC2 (us-east-1, on-demand 2024 pricing - verify current):**
- t3.micro (2 vCPU, 1GB RAM): ~$7.52/month
- t3.small (2 vCPU, 2GB RAM): ~$15.04/month
- t3.medium (2 vCPU, 4GB RAM): ~$30.08/month

**Recommendation pattern:** Start small, use validation blocks to prevent oversizing.

```hcl
variable "instance_type" {
  description = "Instance type (use t3.micro/small for dev, t3.medium+ for prod)"
  type        = string

  validation {
    condition = (
      var.environment == "prod"
      ? can(regex("^(t3\\.(medium|large|xlarge)|c6i\\.(large|xlarge))$", var.instance_type))
      : true
    )
    error_message = "Production requires t3.medium or larger for reliability."
  }
}
```

### Resource Cleanup Patterns

**Auto-termination for dev environments:**
```hcl
resource "aws_instance" "dev_server" {
  count = var.environment == "dev" ? var.instance_count : 0

  # ... instance config ...

  tags = merge(
    local.common_tags,
    {
      AutoShutdown = "true"  # For automated cleanup scripts
      TTL          = "7d"    # Time-to-live
    }
  )
}
```

## 12. Code Review Checklist (For SRE Agent)

### Security
- [ ] No hardcoded secrets in variables
- [ ] Sensitive variables marked with `sensitive = true`
- [ ] S3 buckets have public access blocked (unless explicitly required)
- [ ] Security groups don't allow `0.0.0.0/0` on non-HTTP(S) ports
- [ ] RDS instances not publicly accessible
- [ ] IAM policies follow least privilege
- [ ] Encryption enabled for storage resources

### Cost
- [ ] Instance types appropriate for environment (t3.micro for dev, not c6i.8xlarge)
- [ ] Dev/staging resources have auto-shutdown tags
- [ ] No unused Elastic IPs
- [ ] S3 lifecycle policies for old data
- [ ] Reserved instances or Savings Plans considered for prod

### Best Practices
- [ ] All variables have `description` and `type`
- [ ] All outputs have `description`
- [ ] Provider versions pinned with `~>` constraint
- [ ] Terraform version constraint set
- [ ] Resources use consistent naming pattern
- [ ] Common tags applied via `locals`
- [ ] Backend configured for remote state
- [ ] State locking enabled
- [ ] `.terraform.lock.hcl` committed

### Structure
- [ ] Files split logically (network.tf, compute.tf) if > 300 lines
- [ ] Nested modules in `modules/` directory
- [ ] Each module has `variables.tf`, `outputs.tf`, `README.md`
- [ ] No duplicate resource definitions

## Sources

This research synthesized information from:

### HashiCorp Official Documentation
- [Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
- [Style Guide](https://developer.hashicorp.com/terraform/language/style)
- [Module Creation Pattern](https://developer.hashicorp.com/terraform/tutorials/modules/pattern-module-creation)
- [Module Composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition)
- [Naming Conventions](https://developer.hashicorp.com/terraform/plugin/best-practices/naming)
- [Version Constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints)
- [Variable Block Reference](https://developer.hashicorp.com/terraform/language/block/variable)
- [Type Constraints](https://developer.hashicorp.com/terraform/language/expressions/type-constraints)
- [S3 Backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Manage Workspaces](https://developer.hashicorp.com/terraform/cli/workspaces)
- [Workspace Best Practices](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/best-practices)

### Cloud Provider Best Practices
- [AWS Terraform Best Practices - Code Structure](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html)
- [AWS Terraform Best Practices - Backend](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html)
- [AWS Terraform Best Practices - Version Management](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/version.html)
- [Google Cloud Terraform Best Practices](https://cloud.google.com/docs/terraform/best-practices/general-style-structure)

### Community Resources
- [Terraform Best Practices - Naming](https://www.terraform-best-practices.com/naming)
- [Terraform Best Practices - Code Structure](https://www.terraform-best-practices.com/code-structure)
- [Spacelift - Terraform Best Practices](https://spacelift.io/blog/terraform-best-practices)
- [Spacelift - Terraform Files](https://spacelift.io/blog/terraform-files)
- [Spacelift - Terraform S3 Backend](https://spacelift.io/blog/terraform-s3-backend)
- [Spacelift - Terraform Output Values](https://spacelift.io/blog/terraform-output)
- [Spacelift - Terraform Variables](https://spacelift.io/blog/how-to-use-terraform-variables)
- [Spacelift - Terraform Modules](https://spacelift.io/blog/what-are-terraform-modules-and-how-do-they-work)
- [Spacelift - Terraform Variable Validation](https://spacelift.io/blog/terraform-variable-validation)
- [env0 - Terraform Workspaces](https://www.env0.com/blog/terraform-workspaces-guide-examples-commands-and-best-practices)
- [env0 - Terraform Modules](https://www.env0.com/blog/terraform-modules)
- [env0 - Terraform Versioning](https://www.env0.com/blog/tutorial-how-to-manage-terraform-versioning)
- [env0 - Terraform Files and Folders](https://www.env0.com/blog/terraform-files-and-folder-structure-organizing-infrastructure-as-code)
- [GlobalDots - Terraform Naming Conventions](https://www.globaldots.com/resources/blog/terraform-naming-conventions-best-practices-a-hell-of-a-practical-guide/)
- [Gruntwork - Terraform Style Guide](https://docs.gruntwork.io/guides/style/terraform-style-guide/)
- [Gruntwork Blog - Terraform Workspaces](https://blog.gruntwork.io/how-to-manage-multiple-environments-with-terraform-using-workspaces-98680d89a03e)
- [Microsoft Engineering Playbook - Terraform Variables](https://microsoft.github.io/code-with-engineering-playbook/CI-CD/recipes/terraform/share-common-variables-naming-conventions/)
- [Prosperasoft - Split Terraform Files](https://prosperasoft.com/blog/cloud/gcp/split-terraform-main-tf/)
- [Medium - Terraform File Structure](https://medium.com/@shabarimeda/terraform-file-structure-explained-a-clean-scalable-way-to-organize-your-iac-67fc18791dd1)
- [Medium - Terraform Azure Naming](https://medium.com/@devopswithyoge/terraform-azure-coding-naming-convention-and-resource-creation-patterns-91e1e8e45283)
- [Medium - Terraform Naming Conventions](https://medium.com/codex/terraform-best-practices-using-a-consistent-naming-convention-5df9068c2454)
- [Coding Architect - Workspaces vs Folders](https://codingarchitect.dev/blog/terraform-workspaces-vs-separate-folders-which-one-should-you-use/)
- [Build5Nines - Terraform Environments](https://build5nines.com/best-practices-to-promote-from-dev-to-prod-environments-with-hashicorp-terraform-using-workspaces-and-folders/)
- [Terraform Variable Cross Validation](https://mattias.engineer/blog/2024/terraform-variable-cross-validation/)
- [Terraform Fundamentals - Type Constraints](https://www.100daysofredteam.com/p/terraform-fundamentals-type-constraints-and-validation-blocks)
- [Ned in the Cloud - Variable Validation Terraform 1.9](https://nedinthecloud.com/2024/07/08/variable-validation-improvements-in-terraform-1.9/)
- [DevOpsCube - Terraform S3 Backend with DynamoDB](https://devopscube.com/setup-terraform-remote-state-s3-dynamodb/)
- [Doximity - Terraform S3 Backend Best Practices](https://technology.doximity.com/articles/terraform-s3-backend-best-practices)
- [AWS DevOps Blog - Managing Terraform State Files](https://aws.amazon.com/blogs/devops/best-practices-for-managing-terraform-state-files-in-aws-ci-cd-pipeline/)

### Tooling and Utilities
- [Scalr - Terraform Provider Requirements](https://scalr.com/learning-center/terraform-provider-requirements-foundations-for-reproducible-infrastructure/)
- [Scalr - Terraform Modules Explained](https://scalr.com/learning-center/terraform-modules-explained/)
- [Compile N Run - Terraform Project Structure](https://www.compilenrun.com/docs/devops/terraform/terraform-best-practices/terraform-project-structure/)
- [Compile N Run - Terraform Naming Conventions](https://www.compilenrun.com/docs/devops/terraform/terraform-best-practices/terraform-naming-conventions/)
- [James R Counts - Terraform Namer Pattern](https://jamesrcounts.com/2025/06/29/terraform-namer-pattern.html)
- [CloudPosse - terraform-aws-tfstate-backend](https://github.com/cloudposse/terraform-aws-tfstate-backend)

## Next Steps

This research informs the SRE agent prompt design. Key takeaways for agent capabilities:

1. **Generation:** Default to split-file structure (network.tf, compute.tf) for non-trivial configs
2. **Variables:** Always include description/type, add validation for security/cost constraints
3. **Outputs:** Include at least one output per resource, use descriptive names
4. **Backend:** Recommend S3 native locking (Terraform 1.10+), warn about DynamoDB deprecation
5. **Naming:** Enforce snake_case for identifiers, hyphen-separated-lowercase for resource names
6. **Security:** Flag public S3 buckets, overly permissive security groups, hardcoded secrets
7. **Cost:** Validate instance types against environment (t3.micro for dev, larger for prod)
8. **Versioning:** Use `~>` constraints, generate `.terraform.lock.hcl`

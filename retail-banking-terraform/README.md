# Retail Banking AWS Lab — Terraform

Recreate **Customer Profile → Account → Statement** in Tokyo (**ap-northeast-1**) using Terraform. Infrastructure, S3 binary upload, EC2 configuration, service startup, ALB, and optional custom-domain HTTPS are automated.

The only local preparation is downloading the Linux executable. Terraform uploads it to a new private S3 bucket; EC2 retrieves it using an IAM role. No SSH keys, manual file copying to EC2, Go installation, or inbound SSH rules are required.

## Architecture

~~~mermaid
flowchart TD
    Browser["Browser"] --> ALB["Customer ALB · HTTP 80 or HTTPS 443"]
    subgraph C["Customer VPC · 10.10.0.0/16"]
        ALB --> Customer["Customer Profile · 10.10.3.170:9091"]
    end
    subgraph A["Account VPC · 10.20.0.0/16"]
        Account["Account · 10.20.1.141:9092"]
    end
    subgraph S["Statement VPC · 10.30.0.0/16"]
        Statement["Statement · 10.30.1.130:9093"]
    end
    Customer -->|"HTTP · peering"| Account
    Account -->|"HTTP · peering"| Statement
~~~

Route 53 points the custom hostname to the ALB. TLS terminates at the ALB; the private application hops use HTTP. Account makes a separate request to Statement. Peering does not provide transitive routing from Customer to Statement.

## What this creates

| Component | Configuration |
|---|---|
| VPCs | Customer 10.10.0.0/16, Account 10.20.0.0/16, Statement 10.30.0.0/16 |
| Subnets | One private subnet per service; two Customer public subnets in different AZs |
| Internet access | Customer IGW, one public NAT Gateway and Elastic IP |
| Peering | Customer ↔ Account and Account ↔ Statement, accepted automatically |
| Routing | Explicit subnet associations and reciprocal peering routes |
| EC2 | Three AL2023 x86_64 instances, no public IPs, encrypted gp3 root disks, IMDSv2 |
| Management | EC2 IAM role, SSM + ssmmessages Interface endpoints in each backend VPC |
| Distribution | Private encrypted S3 bucket/object, S3 Gateway endpoint in each backend VPC |
| Application | fake-service v0.26.2, systemd startup/restart, SHA-256 verification after S3 download |
| ALB | Internet-facing, two public AZs, Customer HTTP target on 9091, health path / |
| DNS/TLS | Optional ACM certificate, DNS validation, A Alias in an existing public hosted zone, HTTPS 443 |
| Redirect | HTTPS mode changes HTTP 80 to canonical-host HTTPS 301 |

## Existing manual lab

**This creates a new stack. It does not automatically import your manual resources.** A new prefix, VPCs, role and S3 bucket allow independent testing. The old lab can remain running; it incurs separate costs.

Use **bank-tf.hellogeolab.site** while the original **bank.hellogeolab.site** remains live. Route 53 records use allow_overwrite=false. A conflicting alias or validation CNAME causes an error rather than silently taking ownership. Choose an unused hostname or deliberately import a conflicting record after reviewing its ownership.

Overlapping CIDRs in isolated stacks are allowed, but do not peer old and new overlapping VPCs. The existing Route 53 zone is read as a data source and is not owned/deleted by this stack.

## Prerequisites

- Terraform **1.14+**, below 2.0.
- AWS CLI v2 authenticated to the intended account.
- bash, curl, unzip, file, and Python 3.
- Permissions for VPC/EC2/ELB/S3/IAM/SSM endpoints; for HTTPS, ACM and records in the selected Route 53 zone. Launching EC2 with a role also requires iam:PassRole.
- For HTTPS: an existing authoritative **public Route 53 zone**, in the same account.

On MacBook M2 use macOS ARM64 Terraform/AWS CLI packages. The downloaded application executable is Linux AMD64 for EC2, not macOS.

[Install Terraform](https://developer.hashicorp.com/terraform/install) and [install AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) if needed.

~~~bash
terraform version
aws --version
python3 --version
aws sts get-caller-identity
~~~

For an existing named profile:

~~~bash
export AWS_PROFILE="YOUR_PROFILE"
# If this is an IAM Identity Center profile:
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
~~~

Credentials stay in your CLI profile/environment. Do not put access keys in Terraform files.

## Project files

| File | Purpose |
|---|---|
| versions.tf | Terraform and AWS provider constraints |
| variables.tf / locals.tf | Inputs, addressing, AZ selection, service configuration |
| network.tf | VPCs, subnets, IGW, NAT, routes and peering |
| security.tf | ALB, EC2 and endpoint security groups |
| endpoints.tf | Backend SSM/ssmmessages/S3 endpoints |
| storage-iam.tf | Binary bucket/object, IAM role and instance profile |
| compute.tf | Private EC2 with rendered startup scripts |
| alb.tf / dns-https.tf | Target group, listeners, ACM and Route 53 |
| outputs.tf | URLs, resource IDs and connection commands |
| templates/user-data.sh.tftpl | S3 fetch and systemd service |
| scripts/prepare-binary.sh | Download/extract the pinned Linux release |
| scripts/verify.sh | ALB health, complete service response and redirect checks |
| scripts/check-response.py | Verify each service name and response code |
| tests/stack.tftest.hcl | Mocked HTTP/HTTPS Terraform tests |
| terraform.tfvars.example | Configuration template |
| .terraform.lock.hcl | Tested AWS provider selection and checksums |
| VALIDATION.md | Checks performed before delivery |

## Step 1 — Prepare the executable

Extract the downloaded project and enter its root:

~~~bash
cd retail-banking-terraform
bash scripts/prepare-binary.sh
~~~

The script downloads fake_service_linux_amd64.zip from the official **v0.26.2** GitHub release, extracts the executable and confirms Linux x86-64 format.

The resulting assets/fake-service is excluded from Git and from the source ZIP. Terraform computes its SHA-256 and instances verify that hash after downloading from S3. This checks distribution integrity; it is not an independent publisher-signature check.

If you already have the correct executable from the manual lab:

~~~bash
mkdir -p assets
cp ~/fake-service-linux/fake-service assets/fake-service
chmod +x assets/fake-service
file assets/fake-service
~~~

Expected: ELF 64-bit, x86-64.

## Step 2 — Configure your public IP

~~~bash
cp terraform.tfvars.example terraform.tfvars
curl -4 --fail --silent --show-error https://checkip.amazonaws.com
~~~

Edit terraform.tfvars; substitute the returned public IPv4:

~~~hcl
aws_region           = "ap-northeast-1"
project_name         = "retail-bank-tf"
allowed_client_cidrs = ["YOUR_PUBLIC_IPV4/32"]
enable_https         = false
~~~

The example 203.0.113.10/32 is a documentation IP and will not permit your browser to connect. Add approved client CIDRs if a reviewer needs access. If your public IP changes or a VPN changes it, update the input and apply again.

The default is t3.micro. Other types must be **x86_64**; t4g ARM instances cannot run this executable.

## Step 3 — Initialize, check, plan and apply

~~~bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
terraform plan -out=lab.tfplan
terraform apply lab.tfplan
~~~

Mock tests create no AWS resources and need no AWS credentials. Real plan/apply uses your configured AWS identity. Review the saved plan before applying.

Terraform provisions endpoints, routing, IAM and the uploaded executable before launching EC2. User data creates a non-login service user, writes environment settings and a systemd unit, retrieves the binary from S3, checks its hash, starts the service and enables startup on reboot. Download and process failures are retried.

Backend bootstrap does not download from GitHub or install packages. AL2023 supplies AWS CLI and SSM Agent; the executable comes through S3 Gateway endpoints.

Apply completion does not guarantee cloud-init or ALB health checks have completed. Give the instances a few minutes, then:

~~~bash
terraform output
bash scripts/verify.sh
terraform output -raw ui_url
~~~

Open the printed UI URL. The verification script waits for the Customer target to become Healthy and checks **all three services**, not only the outer HTTP status.

## Step 4 — Session Manager and service checks

AWS console: EC2 → select an instance → Connect → SSM Session Manager.

CLI commands are available as an output:

~~~bash
terraform output session_manager_commands
~~~

For CLI sessions, install the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html). Example:

~~~bash
INSTANCE_ID="$(terraform output -json instance_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["account"])')"
aws ssm start-session --target "$INSTANCE_ID" --region ap-northeast-1
~~~

On an instance:

~~~bash
sudo cloud-init status --long
sudo systemctl status fake-service --no-pager
sudo journalctl -u fake-service -n 80 --no-pager
sudo cat /etc/fake-service/service.env
ss -lnt
~~~

| Session | Local test | Upstream test |
|---|---|---|
| Statement | curl --max-time 10 http://localhost:9093/ | None |
| Account | curl --max-time 10 http://localhost:9092/ | curl --max-time 10 http://10.30.1.130:9093/ |
| Customer | curl --max-time 10 http://localhost:9091/ | curl --max-time 10 http://10.20.1.141:9092/ |

~~~bash
sudo systemctl restart fake-service
sudo systemctl is-active fake-service
~~~

Services start after EC2 reboot. Logs are in the systemd journal rather than the manual nohup log files.

## Step 5 — Custom-domain HTTPS

HTTPS can be enabled on the first apply if your DNS is ready. Starting with HTTP lets you verify application connectivity before certificate validation.

List hosted zones and identify the existing public zone for hellogeolab.site:

~~~bash
aws route53 list-hosted-zones --output table
~~~

Use its ID without the /hostedzone/ prefix. Confirm the registrar delegates authoritative nameservers to that Route 53 zone. A domain registered with Cloudflare can use Route 53 after NS delegation.

Edit the existing input values:

~~~hcl
enable_https    = true
domain_name     = "bank-tf.hellogeolab.site"
route53_zone_id = "ZYOURACTUALHOSTEDZONEID"
~~~

~~~bash
terraform plan -out=https.tfplan
terraform apply https.tfplan
bash scripts/verify.sh
terraform output -raw ui_url
~~~

Terraform requests ACM in the ALB's Region, creates the validation CNAME, waits for issuance, creates HTTPS 443, adds the A Alias, and changes HTTP 80 to redirect. Validation may take several minutes; the configured timeout is 45 minutes.

HTTP redirects to the configured custom hostname, including when you use the raw ALB DNS name. This is the hostname covered by the certificate. The AWS-owned ALB DNS name is not covered by your custom certificate.

~~~bash
URL="$(terraform output -raw application_url)"
curl --fail --max-time 30 "$URL/" | python3 scripts/check-response.py
curl -I --max-time 30 "http://bank-tf.hellogeolab.site/ui/?demo=1"
~~~

Do not use curl -k to verify certificates. If ACM times out, fix NS delegation or the validation CNAME, then rerun plan/apply with the same state.

## Network and security details

| Route table | Non-local routes |
|---|---|
| Customer public | 0.0.0.0/0 → IGW |
| Customer private | 0.0.0.0/0 → NAT; 10.20.0.0/16 → Customer–Account peering |
| Account private | 10.10.0.0/16 → Customer–Account; 10.30.0.0/16 → Account–Statement; S3 prefix list → endpoint |
| Statement private | 10.20.0.0/16 → Account–Statement; S3 prefix list → endpoint |

| Destination | Allowed inbound |
|---|---|
| ALB | Approved CIDRs on 80, and also 443 when HTTPS is enabled |
| Customer | ALB SG on 9091 |
| Account | Customer EC2 SG on 9092 |
| Statement | Account EC2 SG on 9093 |
| Backend Interface endpoints | Corresponding EC2 SG on 443 |

ALB outbound is restricted to Customer port 9091. EC2 outbound is allow-all for the lab; backend VPCs still have no Internet default route. Endpoint SGs need no outbound rules for stateful responses. Default VPC network ACLs are used.

Each backend has **two Interface endpoints** (ssm and ssmmessages) and **one S3 Gateway endpoint**. Customer uses NAT for SSM and S3. The role and S3 endpoint policies grant only GetObject on the demo executable. The bucket denies non-TLS access.

This lab uses one EC2 per service and one NAT in one AZ. It is not a highly available production banking system. Application authentication, end-to-end TLS, autoscaling and persistent business data are outside this demo.

## Changes and state

- Edit inputs, review plan, then apply.
- Startup-script or binary-hash changes replace affected instances because user_data_replace_on_change=true. Expect temporary downtime.
- The AMI defaults to the latest AL2023 x86_64 public SSM parameter. A future plan can detect a newer AMI. Set ami_id to the selected_ami_id output if you want to pin it.
- Private IPs are fixed to preserve this service chain; do not change an address without updating its upstream reference.
- Keep Terraform state. Losing state does not delete resources; applying with empty state creates another stack.
- State is local by default and ignored by Git. Use an independently managed encrypted remote backend with locking before sharing Terraform operations across a team.

## Troubleshooting

| Symptom | Checks |
|---|---|
| Binary missing at plan/test | Run prepare-binary.sh or set binary_path. |
| AWS authentication failure | Check profile, login expiry and sts get-caller-identity. |
| Browser timeout | Check current public IP against allowed_client_cidrs and ALB status. |
| Target Unhealthy / ALB 502 | Check cloud-init, systemd logs, listening port and upstream responses; allow bootstrap time. |
| S3 403 | Check object key, IAM role, object ARN and endpoint policy. Fetch retries IAM propagation failures. |
| SSM offline | Check profile, endpoints/Private DNS and port 443 SG rules; Customer also needs NAT. |
| ACM Pending validation | Check authoritative nameservers and validation CNAME. |
| DNS record already exists | Choose an unused hostname or deliberately import the record. |
| Browser Not Secure | Use the custom HTTPS hostname and verify ACM/listener; raw ALB DNS does not match the certificate. |
| Process failed | Inspect journalctl and restart the systemd service. |

On EC2:

~~~bash
sudo tail -n 100 /var/log/cloud-init-output.log
sudo journalctl -u fake-service -n 100 --no-pager
~~~

From your computer:

~~~bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw target_group_arn)" \
  --region "$(terraform output -raw aws_region)"
~~~

## Cleanup

EC2, ALB, NAT Gateway, public IPv4 and Interface endpoints incur ongoing charges, alongside storage and DNS usage.

Review and destroy only resources tracked by this directory's state:

~~~bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
~~~

The shared hosted zone and the separate manual lab remain. The new bucket uses force_destroy=false; if you manually add unmanaged objects, remove them deliberately before deletion can succeed.

## GitHub

Use a dedicated repository or subdirectory. State, private inputs, plans and downloaded binaries are ignored. Commit .terraform.lock.hcl; never commit credentials or private keys.

For a new repository, first create an empty GitHub repository, then:

~~~bash
git init
git branch -M main
git add .
git commit -m "Add Terraform retail banking VPC peering lab"
git remote add origin https://github.com/YOUR_USERNAME/retail-banking-terraform.git
git push -u origin main
~~~

For an existing checkout, add, commit and push without reinitializing or adding the same remote again.

## References

- [fake-service v0.26.2](https://github.com/nicholasjackson/fake-service/releases/tag/v0.26.2)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform provider mocking](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [Systems Manager VPC endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [VPC peering](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html)
- [ACM DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [ALB HTTPS listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html)

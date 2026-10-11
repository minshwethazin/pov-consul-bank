# Validation

Prepared on 2026-10-11.

## Passed

- Terraform 1.14.0: formatting and HCL parsing with terraform fmt -check -recursive.
- AWS provider 6.68.0 installation; official Linux ZIP checksum verified against HashiCorp's SHA256SUMS.
- Bash syntax for the preparation and verification scripts.
- Bash syntax for the rendered EC2 startup script and its embedded download script.
- README command syntax and balanced Markdown fences.
- Real fake-service v0.26.2 Linux AMD64 binary downloaded and inspected as an ELF x86-64 executable.
- Local integration test with three real processes: Customer Profile → Account → Statement, all code 200.
- Customer /ui/ responded with HTTP 200 and the expected UI page.
- Response-checking script accepted the complete service chain.

## Environment limitation

Full provider-schema validation and Terraform mock tests could not finish in
this execution environment. The provider failed to open the local Unix socket
required by Terraform's plugin protocol:

    listen unix /tmp/plugin...: socket: operation not permitted

No AWS resources were deployed. Neither a real AWS plan nor an apply was
executed. Formatting and application integration checks are not substitutes
for those checks.

The source includes mocked HTTP and HTTPS tests. On your Mac, after downloading
the executable and installing providers, run:

~~~bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
terraform plan -out=lab.tfplan
~~~

Inspect the plan, apply it, then run bash scripts/verify.sh to verify actual
AWS target health, each service response and, in HTTPS mode, the redirect and
certificate.

The delivered provider lock file records the official package checksums;
provider executables/caches and the local application binary are not included.

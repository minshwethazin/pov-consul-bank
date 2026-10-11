# Terraform နဲ့ ဒီ Lab ကို ပြန်ဆောက်ရန်

ဒီ project က လက်ရှိ manual lab ကို import မလုပ်ဘဲ AWS resource အသစ်တွေ ဆောက်ပေးပါတယ်။
ပထမဆုံး HTTP နဲ့ service ၃ ခုကို စစ်ပြီးမှ HTTPS ထည့်လို့ရပါတယ်။

## 1. ZIP ဖြည်ပြီး project folder ထဲဝင်ပါ

~~~bash
cd retail-banking-terraform
bash scripts/prepare-binary.sh
cp terraform.tfvars.example terraform.tfvars
curl -4 https://checkip.amazonaws.com
~~~

terraform.tfvars ထဲက allowed_client_cidrs ကို ကိုယ့် public IP/32 နဲ့ ပြောင်းပါ။
AWS credential တွေကို ဒီဖိုင်ထဲ မရေးပါနဲ့။

## 2. AWS account နဲ့ configuration ကို စစ်ပါ

~~~bash
aws sts get-caller-identity
terraform init
terraform validate
terraform test
terraform plan -out=lab.tfplan
~~~

Plan ထဲမှာ ဆောက်မယ့် resource တွေကို စစ်ပြီး ဆက်လုပ်ပါ။

~~~bash
terraform apply lab.tfplan
bash scripts/verify.sh
terraform output -raw ui_url
~~~

EC2 startup နဲ့ health check ပြီးဖို့ မိနစ်အနည်းငယ်ကြာနိုင်ပါတယ်။
ပေးထားတဲ့ URL ကို browser မှာဖွင့်ပါ။

## 3. HTTPS ထည့်ပါ

လက်ရှိ bank.hellogeolab.site ကို ဆက်ထားချင်ရင် အသစ်အတွက် bank-tf.hellogeolab.site သုံးပါ။
terraform.tfvars ထဲမှာ အောက်က values ကို ဖြည့်ပါ။

~~~hcl
enable_https    = true
domain_name     = "bank-tf.hellogeolab.site"
route53_zone_id = "ZYOURACTUALHOSTEDZONEID"
~~~

Hosted zone ID ကို ကိုယ့် Route 53 က ID နဲ့ ပြောင်းပါ။
Domain ရဲ့ authoritative nameserver က ဒီ hosted zone ကို ညွှန်ထားရပါမယ်။

~~~bash
terraform plan -out=https.tfplan
terraform apply https.tfplan
bash scripts/verify.sh
terraform output -raw ui_url
~~~

ACM certificate၊ DNS validation၊ HTTPS listener နဲ့ HTTP redirect ကို Terraform က လုပ်ပေးပါတယ်။

## အသေးစိတ်

README.md မှာ architecture၊ configuration၊ commands၊ troubleshooting နဲ့ cleanup အစုံပါပါတယ်။
VALIDATION.md မှာ စစ်ပြီးသား checks နဲ့ ဒီ environment မှာ မလုပ်နိုင်ခဲ့တဲ့ checks ကို ရေးထားပါတယ်။
AWS deploy မလုပ်ရသေးပါ။ ကိုယ့် Mac မှာ validate/test/plan ကို run ပြီးမှ deploy လုပ်ပါ။

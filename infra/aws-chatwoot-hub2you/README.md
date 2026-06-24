# Chatwoot Autonomia - AWS hub2you

Infraestrutura para subir o Chatwoot Autonomia na conta AWS `hub2you`, preservando a VPC e subnets ja existentes.

## Rede Reaproveitada

- Account: `354307071110`
- Region: `us-east-1`
- VPC: `vpc-0dc630d9b0d30e44e`
- Subnets publicas default usadas para ALB, EC2, RDS subnet group e Redis subnet group.

Nesta conta nao havia ALB, ECR, RDS, ElastiCache ou certificado ACM emitido em `us-east-1` no momento da preparacao.

## Antes do apply

1. Copie `terraform.tfvars.example` para `terraform.tfvars`.
2. Ajuste `domain_name` para a URL final.
3. Emita ou importe um certificado ACM em `us-east-1` na conta `hub2you`.
4. Ajuste `certificate_arn` com o ARN real.
5. Preencha SMTP/WAHA/SES se forem usados neste ambiente.

## Comandos

```sh
terraform -chdir=infra/aws-chatwoot-hub2you init
terraform -chdir=infra/aws-chatwoot-hub2you plan -var-file=terraform.tfvars
terraform -chdir=infra/aws-chatwoot-hub2you apply -var-file=terraform.tfvars
```

Depois do apply, apontar o CNAME externo do `domain_name` para o output `ec2_alb_dns_name`.

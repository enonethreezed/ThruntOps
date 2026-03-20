# Vulnerabilities

Attack surface and known vulnerability classes present in the ThruntOps lab.

## By Technology

| Technology | Vectors |
|---|---|
| Active Directory (dual domain) | Kerberoasting, AS-REP roasting, ACL abuse, lateral movement, trust abuse |
| ADCS | ESC1–ESC16 certificate template misconfigurations |
| IIS + ASP.NET + MSSQL | Web application attacks, SQL injection, authentication bypass |
| GitLab CE | Source code exposure, CI/CD pipeline abuse, secret leakage |
| Elastic SIEM | Detection engineering, alert tuning, log analysis |

## Notes

- All domain and local accounts use weak passwords (`password`) — intentional for credential attack testing
- No password policy enforced on the domain
- ADCS is configured with intentionally misconfigured templates to enable ESC attack paths
- GitLab CI/CD pipeline deploys directly to IIS on push — pipeline poisoning surface
- Domain trust between `thruntops.domain` and `secondary.thruntops.domain` enables cross-domain lateral movement

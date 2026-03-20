# Users

All credentials used in the ThruntOps lab.

---

## Domain — thruntops.domain

| User | Password | Type |
|---|---|---|
| `domainadmin` | `iFgu¿83¿` | Domain Admin (Ludus default) |
| `domainuser` | `NV#8SL9#` | Domain User (Ludus default) |
| `basicdomainuser` | `Zz5)"8Gf` | Domain User |
| `pkiadmin` | `L4U8v!P¿` | Domain Admin (PKI) |
| `webdev` | `n4&1Kj@K` | Domain User — member of Developers group, GitLab maintainer |
| `primary_user01` | `iFgu¿83¿` | Domain User |
| `primary_user02` | `iFgu¿83¿` | Domain User |
| `primary_user03` | `iFgu¿83¿` | Domain User |
| `primary_user04` | `iFgu¿83¿` | Domain User |
| `primary_user05` | `iFgu¿83¿` | Domain User |
| `primary_user06` | `iFgu¿83¿` | Domain User |
| `primary_user07` | `iFgu¿83¿` | Domain User |
| `primary_user08` | `iFgu¿83¿` | Domain User |
| `primary_user09` | `iFgu¿83¿` | Domain User |
| `primary_user10` | `iFgu¿83¿` | Domain User |

> `primary_user01`–`primary_user10` share the domain admin password — intentional credential reuse for attack testing.

## Domain — secondary.thruntops.domain

| User | Password | Type |
|---|---|---|
| `domainadmin` | `Ut2cf7%/` | Domain Admin (Ludus default) |
| `domainuser` | `p0aAQ¿9)` | Domain User (Ludus default) |
| `basicdomainuser` | `FrN1u/1?` | Domain User |
| `secondary_user01` | `Ut2cf7%/` | Domain User |
| `secondary_user02` | `Ut2cf7%/` | Domain User |
| `secondary_user03` | `Ut2cf7%/` | Domain User |
| `secondary_user04` | `Ut2cf7%/` | Domain User |
| `secondary_user05` | `Ut2cf7%/` | Domain User |
| `secondary_user06` | `Ut2cf7%/` | Domain User |
| `secondary_user07` | `Ut2cf7%/` | Domain User |
| `secondary_user08` | `Ut2cf7%/` | Domain User |
| `secondary_user09` | `Ut2cf7%/` | Domain User |
| `secondary_user10` | `Ut2cf7%/` | Domain User |

> `secondary_user01`–`secondary_user10` share the domain admin password — intentional credential reuse for attack testing.

## Local (all Windows VMs)

| User | Password | Type | Scope |
|---|---|---|---|
| `localuser` | `ZT4q?%5x` | Local Admin | All Windows VMs (Ludus default) |
| `basicuser` | `H)2?H8vC` | Local User | All Windows VMs |
| `webadmin` | `O5G=S(5q` | Local Admin | WEB only — IIS/wwwroot access |

## Services

| User | Password | Service | URL |
|---|---|---|---|
| `elastic` | `thisisapassword` | Kibana / Fleet API | https://10.2.50.1:5601 |
| `kibana_system` | `thisisapassword` | Internal Kibana | — |
| `logstash_system` | `thisisapassword` | Logstash monitoring | — |
| `beats_system` | `thisisapassword` | Beats monitoring | — |
| `apm_system` | `thisisapassword` | APM monitoring | — |
| `remote_monitoring_user` | `thisisapassword` | Metricbeat | — |
| `webdev` | `n4&1Kj@K` | GitLab maintainer (use AD credentials via LDAP) | http://10.2.50.15 |

## Notes

- All Windows users have RDP access on their respective machines
- Domain users in `primary_user*` / `secondary_user*` are low-privilege Domain Users
- Elastic service accounts all share the password set in `ludus_elastic_password`
- Special characters in passwords are drawn from: `!"$%&/()=?¿@#|`

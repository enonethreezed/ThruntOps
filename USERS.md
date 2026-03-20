# Users

All credentials used in the ThruntOps lab.

---

## Domain — thruntops.domain

| User | Password | Type |
|---|---|---|
| `domainadmin` | `password` | Domain Admin (Ludus default) |
| `domainuser` | `password` | Domain User (Ludus default) |
| `basicdomainuser` | `password` | Domain User |
| `pkiadmin` | `password` | Domain Admin (PKI) |
| `webdev` | `password` | Domain User — member of Developers group, GitLab maintainer |
| `primary_user01` | `password` | Domain User |
| `primary_user02` | `password` | Domain User |
| `primary_user03` | `password` | Domain User |
| `primary_user04` | `password` | Domain User |
| `primary_user05` | `password` | Domain User |
| `primary_user06` | `password` | Domain User |
| `primary_user07` | `password` | Domain User |
| `primary_user08` | `password` | Domain User |
| `primary_user09` | `password` | Domain User |
| `primary_user10` | `password` | Domain User |

## Domain — secondary.thruntops.domain

| User | Password | Type |
|---|---|---|
| `domainadmin` | `password` | Domain Admin (Ludus default) |
| `domainuser` | `password` | Domain User (Ludus default) |
| `basicdomainuser` | `password` | Domain User |
| `secondary_user01` | `password` | Domain User |
| `secondary_user02` | `password` | Domain User |
| `secondary_user03` | `password` | Domain User |
| `secondary_user04` | `password` | Domain User |
| `secondary_user05` | `password` | Domain User |
| `secondary_user06` | `password` | Domain User |
| `secondary_user07` | `password` | Domain User |
| `secondary_user08` | `password` | Domain User |
| `secondary_user09` | `password` | Domain User |
| `secondary_user10` | `password` | Domain User |

## Local (all Windows VMs)

| User | Password | Type | Scope |
|---|---|---|---|
| `localuser` | `password` | Local Admin | All Windows VMs (Ludus default) |
| `basicuser` | `password` | Local User | All Windows VMs |
| `webadmin` | `password` | Local Admin | WEB only — IIS/wwwroot access |

## Services

| User | Password | Service | URL |
|---|---|---|---|
| `elastic` | `thisisapassword` | Kibana / Fleet API | https://10.2.50.1:5601 |
| `kibana_system` | `thisisapassword` | Internal Kibana | — |
| `logstash_system` | `thisisapassword` | Logstash monitoring | — |
| `beats_system` | `thisisapassword` | Beats monitoring | — |
| `apm_system` | `thisisapassword` | APM monitoring | — |
| `remote_monitoring_user` | `thisisapassword` | Metricbeat | — |
| `webdev` | `password` | GitLab maintainer (domain user — use AD credentials via LDAP) | http://10.2.50.15 |

## Notes

- All Windows users have RDP access on their respective machines
- Domain users in `primary_user*` / `secondary_user*` are low-privilege Domain Users
- Elastic service accounts all share the password set in `ludus_elastic_password`

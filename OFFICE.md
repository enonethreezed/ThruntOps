# Office - Propuesta de Arquitectura y Matriz TTP

Propuesta para incorporar una linea de abuso de ofimatica en ThruntOps, con y sin spearphishing, reutilizando la infraestructura actual y minimizando el impacto en recursos.

---

## Objetivo

Cubrir una categoria que actualmente aparece incompleta en `docs/coverage.md`: ejecucion de documentos de Office, entrega de payloads, captura de credenciales y acceso inicial basado en usuario.

La propuesta se divide en dos bloques:

- **Sin spearphishing**: el documento malicioso se distribuye por shares internos.
- **Con spearphishing**: el documento o enlace se entrega por correo interno.

---

## Alcance funcional

La ampliacion debe permitir los siguientes escenarios:

1. Apertura manual de documentos maliciosos desde recursos compartidos SMB.
2. Ejecucion de macros VBA en Word y Excel.
3. Entrega de payloads mediante LOLBins ya presentes en la matriz (`powershell`, `mshta`, `wscript`, `cscript`, `certutil`).
4. Captura de NTLM mediante documentos con referencias remotas.
5. Campanas de spearphishing internas con adjuntos o enlaces.
6. Encadenado posterior con tecnicas ya existentes en el laboratorio: AD, LAPS, RDP, WEB, MSSQL y GitLab.

---

## Arquitectura propuesta

### 1. Clientes Office

Se reutilizan los dos puestos Windows ya existentes:

- `WIN11-22H2-1` - usuario principal del dominio `thruntops.domain`
- `WIN11-22H2-2` - usuario principal del dominio `secondary.thruntops.domain`

Requisito ya cubierto:

- Microsoft Office instalado en ambos equipos.

### 2. Shares SMB / NAS en `WEB`

Se aprovecha `WEB` como servidor de ficheros SMB para no introducir una VM adicional.

Shares propuestos:

- `\\WEB\thruntops_docs`
- `\\WEB\secondary_docs`
- `\\WEB\xdomain_docs`

Funcion de cada share:

- `thruntops_docs`: intercambio interno del dominio `thruntops.domain`
- `secondary_docs`: intercambio interno del dominio `secondary.thruntops.domain`
- `xdomain_docs`: intercambio y colaboracion entre ambos dominios

Estructura sugerida:

```text
thruntops_docs/
  HR/
  IT/
  Finance/
  Templates/

secondary_docs/
  HR/
  IT/
  Finance/
  Templates/

xdomain_docs/
  Projects/
  Reports/
  Shared-Templates/
```

### 3. Servicio de correo en `gitlab`

Se descarta Exchange por coste de recursos.

Se propone desplegar en `gitlab` una pila ligera:

- Postfix
- Dovecot
- Roundcube

Modelo recomendado:

- un unico servicio de correo
- dos dominios de correo virtuales:
  - `thruntops.domain`
  - `secondary.thruntops.domain`

Capacidades minimas necesarias:

- envio interno SMTP
- buzones IMAP
- acceso webmail con Roundcube
- soporte de adjuntos
- soporte de enlaces clicables en correo HTML o texto
- logs suficientes para analisis defensivo

### 4. Hosting de payloads y documentos enlazados

No es estrictamente necesario anadir un nuevo host web.

Opciones validas:

- servir contenido desde `gitlab`
- servir contenido desde `ops`
- usar directamente rutas SMB en `WEB`

Para una primera fase, SMB + correo interno es suficiente.

---

## Requisitos de identidad y permisos

### Grupos AD sugeridos

Para controlar mejor el acceso a shares, se recomienda crear grupos dedicados.

En `thruntops.domain`:

- `FileShare_Users`
- `XDomain_Docs_RW`
- `XDomain_Docs_RO`

En `secondary.thruntops.domain`:

- `FileShare_Users`
- `XDomain_Docs_RW`
- `XDomain_Docs_RO`

### ACLs recomendadas

- `thruntops_docs`: acceso del dominio `thruntops`
- `secondary_docs`: acceso del dominio `secondary`
- `xdomain_docs`: acceso explicito para ambos dominios

Modelo recomendado:

- algunos usuarios con escritura para plantar documentos
- otros usuarios solo lectura para abrir y consumir documentos
- evitar permisos amplios a `Domain Users` en todos los shares sin distincion

Esto permite representar mejor:

- colaboracion legitima
- staging de lures
- abuso por atacante con acceso previo
- victimas que solo abren documentos

---

## Casos de uso sin spearphishing

Estos escenarios no requieren servicio de correo. El documento se coloca en un recurso compartido y el usuario lo abre manualmente.

### 1. Macro VBA desde share SMB

**Cadena:**

```text
Acceso previo a share interno o cross-domain
  -> copia de documento .docm o .xlsm
  -> usuario navega al share
  -> abre documento
  -> macro ejecuta powershell/mshta/wscript
  -> shell en contexto de usuario
```

**Valor:**

- simula abuso interno sin necesidad de infraestructura de correo
- encadena bien con AD, LAPS, WEB y MSSQL

### 2. Documento con plantilla remota / referencia SMB

**Cadena:**

```text
Documento ofimatico en share
  -> usuario lo abre
  -> Office intenta cargar recurso remoto SMB/HTTP
  -> autenticacion NTLM o recuperacion de contenido remoto
```

**Valor:**

- no depende de macro
- util para captura de credenciales y deteccion de trafico saliente

### 3. Documento con payload indirecto via LOLBin

**Cadena:**

```text
Documento con macro
  -> macro invoca certutil/mshta/wscript/cscript
  -> descarga o ejecuta payload adicional
  -> shell de usuario
```

**Valor:**

- reutiliza tecnicas ya documentadas en Windows
- genera muy buena telemetria en endpoints

---

## Casos de uso con spearphishing

Estos escenarios anaden entrega por correo y narrativa de usuario.

### 1. Adjunto malicioso con macro

**Pretextos sugeridos:**

- RRHH: actualizacion de nominas
- IT: nueva politica de contrasenas
- Seguridad: revisiones de acceso
- Finanzas: plantilla de gastos
- Proyecto cross-domain: informe trimestral

**Cadena:**

```text
Correo interno con adjunto .docm/.xlsm
  -> usuario abre adjunto en WIN11
  -> macro ejecuta payload
  -> shell en contexto de usuario
```

### 2. Correo con enlace a documento en SMB

**Cadena:**

```text
Correo interno con enlace a \\WEB\xdomain_docs\...
  -> usuario accede al share
  -> abre documento alojado en SMB
  -> ejecucion de macro o referencia remota
```

**Valor:**

- une correo y NAS en una sola tecnica
- evita depender siempre de adjuntos directos

### 3. Correo con enlace a documento remoto

**Cadena:**

```text
Correo interno con enlace HTTP interno
  -> usuario descarga documento
  -> apertura en Office
  -> ejecucion o captura de NTLM
```

---

## Matriz propuesta de tecnicas Office

| Categoria | Tecnica | Requiere correo | Requiere NAS | Objetivo principal |
|---|---|---:|---:|---|
| Office | Macro VBA en Word | No | Si | Ejecucion en contexto de usuario |
| Office | Macro VBA en Excel | No | Si | Ejecucion en contexto de usuario |
| Office | Plantilla remota / referencia SMB | No | Si | Captura NTLM / retrieval remoto |
| Office | Spearphishing con adjunto | Si | No | Acceso inicial |
| Office | Spearphishing con enlace a SMB | Si | Si | Acceso inicial / user execution |
| Office | Spearphishing con enlace HTTP interno | Si | No | Acceso inicial / retrieval |
| Office | Macro + LOLBin | Opcional | Si | Descarga y ejecucion de payload |

---

## Telemetria y detecciones esperadas

### En endpoints Windows

- `WINWORD.EXE` o `EXCEL.EXE` lanzando:
  - `powershell.exe`
  - `cmd.exe`
  - `mshta.exe`
  - `wscript.exe`
  - `cscript.exe`
  - `certutil.exe`
- escrituras en `%TEMP%`, `Downloads` o rutas de Office recovery
- conexiones SMB/HTTP salientes tras apertura de documento

### En `WEB` como SMB server

- creacion, renombrado y lectura de documentos en shares
- accesos a `thruntops_docs`, `secondary_docs` y `xdomain_docs`
- identificacion del usuario que planta el lure y del usuario que lo abre

### En `gitlab` como correo

- login a Roundcube
- entrega SMTP
- acceso IMAP
- remitente, destinatario, asunto, adjuntos, enlaces incluidos

---

## Encaje con la matriz actual

La linea Office debe servir como capa de acceso inicial o user execution, y no como un bloque aislado.

Encadenados recomendados:

### Cadena A - Office -> AD / LAPS

```text
Documento malicioso en share o adjunto
  -> shell en WIN11
  -> robo de credenciales o contexto de usuario
  -> abuso de LAPS / movimiento lateral / RDP
```

### Cadena B - Office -> WEB

```text
Documento malicioso
  -> shell en usuario de workstation
  -> acceso a WEB por RDP/SMB/credenciales recuperadas
  -> pivot a IIS o MSSQL
```

### Cadena C - Office -> GitLab / secretos / CI

```text
Compromiso de workstation de usuario con acceso a GitLab
  -> robo de credenciales o sesion
  -> acceso a repositorios / CI
  -> encadenado con pipeline poisoning
```

---

## Implementacion por fases

### Fase 1 - Sin correo

1. Crear los tres shares SMB en `WEB`.
2. Definir grupos AD y ACLs.
3. Crear estructura de carpetas realista.
4. Validar apertura de documentos desde `WIN11-22H2-1` y `WIN11-22H2-2`.
5. Incorporar al menos dos escenarios:
   - macro VBA
   - referencia remota SMB

### Fase 2 - Con correo

1. Desplegar `postfix + dovecot + roundcube` en `gitlab`.
2. Crear buzones y aliases realistas.
3. Validar envio de adjuntos y enlaces internos.
4. Incorporar campanas de spearphishing.

### Fase 3 - Documentacion y cobertura

1. Actualizar `docs/coverage.md`.
2. Anadir seccion Office a `docs/vulnerabilities.md`.
3. Documentar usuarios objetivo y pretextos.
4. Anadir ideas de deteccion Sigma para Office child-process abuse y Office -> SMB/HTTP.

---

## Recomendacion final

La expansion Office debe apoyarse en dos pilares:

- `WEB` como servidor SMB con tres shares (`thruntops_docs`, `secondary_docs`, `xdomain_docs`)
- `gitlab` como plataforma ligera de correo interno (`postfix + dovecot + roundcube`)

Con esto se cubren de forma realista y barata dos familias de TTP que hoy faltan en la matriz:

- abuso de documentos de Office sin spearphishing
- acceso inicial via spearphishing interno

La primera fase puede desplegarse sin correo y ya aportaria valor inmediato a la matriz.

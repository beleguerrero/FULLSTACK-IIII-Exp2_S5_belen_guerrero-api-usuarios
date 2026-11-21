# Microservicio - API USUARIOS

# Exp1_S2_belen_guerrero
Actividad Sumativa 1: Programando nuestro BackEnd


## Configuración
- **Puerto:** `8081`
- **URL:** `http://localhost:8081/api`
- **Base de datos:** Oracle Cloud

La conexión a la base de datos debe estar configurada en `application.properties`.

### Oracle Wallet

El proyecto tiene configurada la conexión a Oracle mediante **Oracle Wallet**, ubicado en la siguiente ruta de Windows: `C:/Wallets/Wallet_MIBD_belen_guerrero`

## Endpoints

### Autenticación

| Método HTTP | Endpoint | Descripción | Body |
|---|---|---|---|
| POST | `/auth/login` | Validar las credenciales del usuario y generar un token JWT para acceder a los endpoints protegidos de los microservicios. | Sí, campos obligatorios |

#### Body para obtener el token (POST)

```json
{
  "usuario": "usuario_uno",
  "password": "contraseña"
}
```

**Respuesta:** devuelve un token JWT que debe enviarse en el header `Authorization` de las peticiones protegidas, utilizando el esquema `Bearer`.

```http
Authorization: Bearer <token>
```

### Usuario

**Todos los endpoints requieren autenticación mediante **Bearer Token (JWT)** en el header `Authorization`.**

| Método HTTP | Endpoint | Descripción | Body |
|---|---|---|---|
| GET | `/mi-foro/usuarios` | Obtener todos los usuarios. | No requiere |
| GET | `/mi-foro/usuarios/{id}` | Obtener un usuario por su ID. | No requiere |
| POST | `/mi-foro/usuarios` | Crear un usuario. | Sí, campos obligatorios |
| PUT | `/mi-foro/usuarios/{id}` | Actualizar un usuario existente. | Sí, todos los campos son opcionales |
| DELETE | `/mi-foro/usuarios/{id}` | Eliminar un usuario por su ID. | No requiere |

#### Body para crear un usuario (POST)


```json
{
    "usuario": "usuario_1",
    "password": "contraseña",
    "nombre": "Usuario Prueba",
    "correo": "correo.prueba@mail.com",  // puede ser null
    "tipoUsuarioId": 1
}
```

#### Body para actualizar un usuario (PUT)

Todos los campos son opcionales. Solo se actualizarán aquellos que sean enviados en el body. Los campos omitidos conservarán su valor actual.

```json
{
    "usuario": "usuario_uno",
    "password": "contraseña",
}
```

También es posible actualizar un solo campo:

```json
{
    "nombre": "Usuario Uno",
}
```

O varios campos:

```json
{
    "usuario": "usuario_uno",
    "password": "contraseña",
    "nombre": "Usuario Uno",
    "correo": "correo.uno@mail.com",
    "tipoUsuarioId": 1
}
```


# ProyectoFinal-BDA-Equipo7

Repositorio del Proyecto Final de la materia Base de Datos Avanzadas donde se desarrollará un prototipo de Sistema de Trazabilidad con RFID para un hospital.

Equipo:
- Isis Villanueva 667725
- Allison Rodriguez 628093
- Roberto Sánchez 668945

Antes de ejecutar esta aplicación deberá instalar las siguientes dependencias en su terminal:
pip3 install psycopg2-binary flask_sqlalchemy

Para cargar el archivo hospital.sql en PostgreSQL:
cp /ruta/original/hospital.sql /tmp/hospital.sql
chmod 644 /tmp/hospital.sql
sudo -i -u postgres psql -d hospital -f /tmp/hospital.sql

Notas:
- El error Permission denied ocurre porque el usuario postgres no tiene acceso al archivo. Moverlo a /tmp y darle permisos de lectura permite que PostgreSQL pueda ejecutarlo correctamente.

Solución de conexión PostgreSQL

Durante el desarrollo se presentó un error de conexión entre Flask y PostgreSQL relacionado con la autenticación del usuario.
El problema ocurría porque PostgreSQL estaba configurado para usar autenticación tipo peer/ident, lo que no permite el uso de contraseñas cuando la conexión se realiza desde una aplicación como Flask.
Para solucionarlo, primero se asignó una contraseña al usuario de PostgreSQL utilizando el comando ALTER USER. Posteriormente, se modificó el archivo de configuración pg_hba.conf para cambiar el método de autenticación a md5, permitiendo así el uso de contraseña en conexiones locales.
Después de realizar estos cambios, se reinició el servicio de PostgreSQL para aplicar la nueva configuración. Finalmente, en el archivo app.py se configuró la conexión utilizando 127.0.0.1 en lugar de localhost, junto con el usuario, contraseña y nombre de la base de datos.
Con estos ajustes, se logró establecer correctamente la conexión entre Flask y PostgreSQL, permitiendo el funcionamiento adecuado de la aplicación.
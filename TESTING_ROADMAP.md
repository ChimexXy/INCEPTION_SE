
# Testing roadmap

Use this checklist before correction and defense. The goal is to demonstrate the subject requirements and understand where every feature is implemented.

## 1. Clean mandatory deployment

From the repository root:

~~~bash
make fclean
make
~~~

Then:

~~~bash
docker ps
~~~

Expected mandatory services:

~~~text
nginx      Up
wordpress  Up
mariadb    Up (healthy)
~~~

Do not continue while a mandatory container is restarting or MariaDB is unhealthy.

## 2. Compose checks

~~~bash
docker compose -f srcs/docker-compose.yml config
docker compose -f srcs/docker-compose.yml config --services
~~~

The mandatory service list must contain exactly:

~~~text
nginx
wordpress
mariadb
~~~

For the bonus:

~~~bash
docker compose -f srcs/docker-compose.yml -f srcs/docker-compose.bonus.yml config --services
~~~

The additional services are:

~~~text
redis
ftp
adminer
static-site
status
~~~

## 3. Network

~~~bash
docker network inspect inception
docker exec wordpress getent hosts mariadb
~~~

Bonus:

~~~bash
docker exec wordpress getent hosts redis
~~~

Be ready to explain Docker's internal DNS and why a user-defined bridge network is used.

## 4. Port exposure

~~~bash
docker ps
ss -lnt
~~~

Mandatory expectation:

- host port 443 is published by NGINX;
- host ports 3306 and 9000 are not published.

Bonus FTP:

- port 21 is published;
- ports 21000-21010 are published for passive mode.

## 5. NGINX and TLS

~~~bash
curl -kI https://mozahnou.42.fr
docker logs nginx
openssl s_client -connect mozahnou.42.fr:443 -tls1_2
openssl s_client -connect mozahnou.42.fr:443 -tls1_3
~~~

Verify that HTTPS works and be able to explain:

- TLS termination at NGINX;
- the self-signed certificate;
- TLS 1.2 and TLS 1.3;
- FastCGI forwarding to WordPress;
- no mandatory port 80 service.

## 6. WordPress and PHP-FPM

~~~bash
docker logs wordpress
docker exec wordpress ps aux
docker exec wordpress wp --allow-root --path=/var/www/html option get siteurl
docker exec wordpress wp --allow-root --path=/var/www/html user list
docker exec wordpress wp --allow-root --path=/var/www/html db check
~~~

Verify the two WordPress users exist and the site URL is the HTTPS project domain.

Explain why WordPress uses PHP-FPM instead of a web server inside the WordPress container.

## 7. MariaDB

~~~bash
docker inspect mariadb --format '{{.State.Status}} health={{.State.Health.Status}}'
docker logs mariadb
docker exec mariadb mariadb-admin ping --socket=/run/mysqld/mysqld.sock
docker exec mariadb sh -c 'mariadb -u root -p"$(cat /run/secrets/db_root_password)" -e "SHOW DATABASES;"'
~~~

Verify that the wordpress database exists.

Be ready to explain first-time initialization, the data volume, the application user and the healthcheck.

## 8. Secrets

~~~bash
ls -la secrets/
git ls-files secrets
~~~

The secret files must not be tracked by Git.

Inspect container configuration without exposing password contents:

~~~bash
docker inspect wordpress
docker inspect mariadb
~~~

Explain why passwords are Docker secrets and not environment variables.

## 9. Volumes

~~~bash
docker volume ls --filter name=inception
docker volume inspect inception_wordpress_files
docker volume inspect inception_mariadb_data
ls -la /home/mozahnou/data/wordpress
ls -la /home/mozahnou/data/mariadb
~~~

Be ready to explain:

- named volumes;
- the local driver with bind-style storage;
- the required host path;
- persistence outside the container writable layer.

## 10. Persistence test

Create a visible WordPress change, then:

~~~bash
make down
make
~~~

Open the website again and confirm the change is still present.

This demonstrates that application files and database data survive container removal.

Do not use make fclean for this test because it is intended for destructive cleanup.

## 11. Restart and initialization test

Restart services:

~~~bash
docker compose -f srcs/docker-compose.yml restart mariadb wordpress nginx
~~~

Then:

~~~bash
docker ps
docker logs mariadb
docker logs wordpress
~~~

Existing MariaDB data and an existing wp-config.php must be reused rather than reinitialized.

Be ready to explain why the entrypoints are idempotent.

## 12. Bonus: Redis

~~~bash
make bonus
docker ps
docker logs redis
docker exec wordpress wp --allow-root --path=/var/www/html plugin list
docker exec wordpress wp --allow-root --path=/var/www/html redis status
~~~

Explain that Redis is a cache and MariaDB remains the persistent database.

## 13. Bonus: FTP

Check:

~~~bash
docker ps
docker logs ftp
~~~

Use an FTP client with:

~~~text
host: mozahnou.42.fr
port: 21
user: ftp_user
password: contents of secrets/ftp_password.txt
mode: passive
~~~

Upload a small test file and verify it appears in the shared WordPress files.

## 14. Bonus: Adminer

Open:

~~~text
https://adminer.mozahnou.42.fr
~~~

Connect with:

~~~text
System:   MySQL
Server:   mariadb
Database: wordpress
User:     wp_user
Password: contents of secrets/db_password.txt
~~~

Demonstrate that Adminer reaches MariaDB through the Docker network rather than through a host-published MariaDB port.

## 15. Bonus: static site

Open:

~~~text
https://static.mozahnou.42.fr
~~~

Verify it is served through the NGINX bonus configuration.

## 16. Bonus: status

Open:

~~~text
https://status.mozahnou.42.fr
https://status.mozahnou.42.fr/health
~~~

Verify that the status service answers and reports the expected service states.

## 17. Configuration modification test

Use a controlled change that proves you understand the service-to-service connection.

Example:

1. Change the PHP-FPM listen port in the WordPress pool configuration.
2. Change the matching FastCGI destination in the NGINX configuration.
3. Rebuild/recreate the affected services.
4. Verify the WordPress site still works.
5. Explain why both configuration points must match.
6. Revert the change.

The important part is understanding the dependency, not changing a value for its own sake.

## 18. Final correction checklist

- [ ] Repository and documentation are up to date.
- [ ] Mandatory Compose file contains exactly three services.
- [ ] Each mandatory service has its own Dockerfile.
- [ ] NGINX is the only mandatory public HTTPS entry point.
- [ ] MariaDB and PHP-FPM ports are internal only.
- [ ] No host networking is used.
- [ ] No legacy links mechanism is used.
- [ ] Persistent WordPress and MariaDB data use named volumes.
- [ ] Volume backing data is under /home/mozahnou/data.
- [ ] Passwords are supplied through Docker secrets.
- [ ] MariaDB initialization works from a fresh volume.
- [ ] WordPress installation works from a fresh volume.
- [ ] WordPress and MariaDB survive make down followed by make.
- [ ] TLS 1.2 and TLS 1.3 work.
- [ ] The main hostname resolves correctly.
- [ ] make works for the mandatory stack.
- [ ] make bonus works for the bonus stack.
- [ ] Redis works as the bonus object cache.
- [ ] FTP works in passive mode.
- [ ] Adminer reaches MariaDB.
- [ ] Static site works through NGINX.
- [ ] Status page and health endpoint work.
- [ ] Entrypoints use the real daemon as PID 1.
- [ ] No fake keep-alive process is used.
- [ ] Every requirement can be explained during defense.

## 19. Defense rule

For every requirement, answer three questions:

**Where?**  
Which Dockerfile, Compose file, configuration or entrypoint implements it?

**How?**  
Which exact command demonstrates it?

**Why?**  
What technical reason explains the design?

Core concepts to know:

~~~text
Docker image vs container
Dockerfile vs Compose
Docker vs virtual machine
Bridge network and service DNS
Named volumes vs bind mounts
Persistence
Docker secrets
NGINX and TLS
FastCGI and PHP-FPM
MariaDB initialization
PID 1 and exec
Restart/dependency behavior
Mandatory vs bonus separation
~~~

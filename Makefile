WEB_CONTAINERS = web-a web-b web-c web-d
LB_CONTAINERS = lb1 lb2 lb3 lb4 lb5 lb6
SLEEP_TIME = 3
SLEEP_TIME_IN_TUTUM = 60

test:test-unittest test-with-tutum ;

test-docker-available:
	@set -e
	@echo "==> Testing docker environment"
	docker version || (echo "==> Failed: cannot run docker" && false)
	@echo

clean:test-docker-available
	@set -e
	@echo "==> Cleaning tmp files and containers"
	docker rm -f $(WEB_CONTAINERS) $(LB_CONTAINERS) > /dev/null 2>&1 || true
	rm -f key.pem ca.pem cert.pem
	@echo

create-cert:clean
	@set -e
	@echo "==> Generating certificate for tests"
	openssl req -x509 -newkey rsa:2048 -keyout key.pem -out ca.pem -days 1080 -nodes -subj '/CN=localhost/O=My Company Name LTD./C=US'
	cp key.pem cert.pem
	cat ca.pem >> cert.pem
	@echo

build:create-cert
	@set -e
	@echo "==> Building haproxy image"
	docker build -t haproxy .
	@echo

certs = $(shell awk 1 ORS='\\n' cert.pem)
test-without-tutum:build
	@set -e
	@echo "====== Running integration tests with Tutum ======"
	@echo "==> Running testing containers"
	docker run -d --name web-a -e HOSTNAME="web-a" tutum/hello-world
	docker run -d --name web-b -e HOSTNAME="web-b" tutum/hello-world
	docker run -d --name web-c -e HOSTNAME=web-c -e VIRTUAL_HOST=web-c.org tutum/hello-world
	docker run -d --name web-d -e HOSTNAME=web-d -e VIRTUAL_HOST="web-d.org, test.org" tutum/hello-world
	@echo

	@echo "==> Testing if haproxy is running properly"
	docker run -d --name lb1 --link web-a:web-a --link web-b:web-b -p 8000:80 haproxy
	sleep $(SLEEP_TIME)
	curl --retry 10 --retry-delay 5 -L -I http://localhost:8000 | grep "200 OK"
	@echo

	@echo "==> Testing virtual host - specified in haproxy cotnainer"
	docker run -d --name lb2 --link web-a:web-a --link web-b:web-b -e VIRTUAL_HOST=" web-a = www.web-a.org, www.test.org, web-b = www.web-b.org " -p 8001:80 haproxy
	sleep $(SLEEP_TIME)
	curl --retry 10 --retry-delay 5 -H 'Host:www.web-a.org' 127.0.0.1:8001 | grep 'My hostname is web-a'
	curl --retry 10 --retry-delay 5 -H 'Host:www.test.org' 127.0.0.1:8001 | grep 'My hostname is web-a'
	curl --retry 10 --retry-delay 5 -H 'Host:www.web-b.org' 127.0.0.1:8001 | grep 'My hostname is web-b'
	@echo

	@echo "==> Testing virtual host - specified in linked containers"
	docker run -d --name lb3 --link web-c:web-c --link web-d:web-d -p 8002:80 haproxy
	sleep $(SLEEP_TIME)
	curl --retry 10 --retry-delay 5 -H 'Host:web-c.org' 127.0.0.1:8002 | grep 'My hostname is web-c'
	curl --retry 10 --retry-delay 5 -H 'Host:test.org' 127.0.0.1:8002 | grep 'My hostname is web-d'
	curl --retry 10 --retry-delay 5 -H 'Host:web-d.org' 127.0.0.1:8002 | grep 'My hostname is web-d'
	@echo

	@echo "==> Testing SSL settings"
	docker run -d --name lb4 --link web-a:web-a -e SSL_CERT="$(certs)" -p 443:443 haproxy
	sleep $(SLEEP_TIME)
	curl --retry 10 --retry-delay 5 --cacert ca.pem -L https://localhost | grep 'My hostname is web-a'
	@echo

	@echo "==> Testing wildcard sub-domains on virtual host (HDR=hdr_end)"
	docker run -d --name lb5 --link web-c:web-c -e HDR="hdr_end" -p 8003:80 haproxy
	sleep $(SLEEP_TIME)
	curl --retry 10 --retry-delay 5 -H 'Host:www.web-c.org' 127.0.0.1:8003 | grep 'My hostname is web-c'
	@echo

test-with-tutum:build
	@set -e
	@echo "====== Running integration tests with Tutum ======"
	@echo "==> Terminating containers in Tuttum"
	tutum service terminate $(WEB_CONTAINERS) $(LB_CONTAINERS) > /dev/null 2>&1 || true
	@echo

	@echo "=> Pushing the image to tifayuki/haproxy"
	docker login -u $(DOCKER_USER) -p $(DOCKER_PASS) -e a@a.com
	docker tag haproxy tifayuki/haproxy
	docker push tifayuki/haproxy
	@echo

	@echo "=> Pulling the images"
	tutum service terminate pre1 pre2 > /dev/null 2>&1 || true
	sleep $(SLEEP_TIME_IN_TUTUM)
	tutum service run --name pre1 tutum/hello-world
	tutum service run --name pre2 tifayuki/haproxy
	sleep $(SLEEP_TIME_IN_TUTUM)
	tutum service terminate pre1 pre2 > /dev/null 2>&1 || true

	@echo "==> Testing if haproxy is running properly"
	tutum service run --name web-a -e HOSTNAME="web-a" tutum/hello-world
	tutum service run --name web-b -e HOSTNAME="web-b" tutum/hello-world
	sleep $(SLEEP_TIME_IN_TUTUM)
	tutum service run --name lb1 --link web-a:web-a --link web-b:web-b -p 8000:80 tifayuki/haproxy
	sleep $(SLEEP_TIME_IN_TUTUM)
	curl --retry 10 --retry-delay 5 -L -I http://302a494c-tifayuki.node.tutum.io:8000 | grep "200 OK"
	tutum service terminate
	@echo

test-unittest:build
	@echo "====== Running unit test ======"
	@echo
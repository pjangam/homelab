.PHONY: run
run:
	docker-compose up -d
	npx pm2 start node-red -- -v 
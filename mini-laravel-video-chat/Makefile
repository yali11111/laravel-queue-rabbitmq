up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

signaling:
	cd services/signaling && npm start

auth:
	cd services/auth && php artisan serve --port=8001

call:
	cd services/call && php artisan serve --port=8002
